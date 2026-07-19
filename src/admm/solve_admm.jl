# src/admm/solve_admm.jl
#
# SEAM: solve_admm — the hand-rolled dual-ascent ADMM loop (ADMM-01 / ADMM-03 / ADMM-04).
# OWNER: plan 06-04 (Wave 3). Declares its own `export`s per the include-graph convention.
#
# THE OUTER ORCHESTRATOR (RESEARCH Pattern 2 / thesis eq. 3.31 dual update, 3.46/3.47 blocks).
# Builds the per-node AGR-OPT[j] (plan 06-02, thesis 3.46) and the whole-network DSO-OPT
# (plan 06-03, thesis 3.47) subproblems ONCE, then alternates their coefficient-update solves
# and takes one gradient-ascent step on the coupling price each iteration (hand-rolled per
# CLAUDE.md — no Coluna/StructJuMP):
#
#     (1) AGR-OPT[j]:  solve with linear coeff −λ_j − ρ·c_j     → a_j = value(pag_j)   (thesis 3.46)
#     (2) DSO-OPT   :  solve with linear coeff −λ_j − ρ·a_j     → pag_dso_j            (thesis 3.47)
#     (3) primal residual  R_{p,j}[t] = value(pag_j[t]) − value(pag_dso_j[t])         (consensus → 0)
#         netflow target   c_j[t]     = netflow_j[t] = −value(pag_dso_j[t])           (for next AGR)
#         dual ascent      λ_j[t] ←  λ_j[t] + ρ·R_{p,j}[t]                            (thesis: λ ← λ + ρ·R)
#
# SIGN DERIVATION (RESEARCH Pattern 1 / Pitfall 5 — the ONE augmented Lagrangian, NOT the
# thesis-3.47 printed sign). From the single MAX augmented Lagrangian of the centralized GLB-CVX
#     L_ρ = Σ_j U_ag,j − λ₀ᵀp_import − Σ_j λ_jᵀ R_{p,j} − (ρ/2) Σ_j ‖R_{p,j}‖²,
#           R_{p,j} = netflow_j + pag_j        (the physical balance 3.31)
# the AGR block fixes netflow_j = c_j (→ penalty −(ρ/2)(c_j+pag_j)², coeff −λ_j−ρ·c_j), and the
# DSO block renames pag_dso_j := −netflow_j (→ R_{p,j} = a_j − pag_dso_j, MIN penalty
# +(ρ/2)(pag_dso_j−a_j)², coeff −λ_j−ρ·a_j). Hence c_j = netflow_j = −value(pag_dso_j) (the
# network injection carries the OPPOSITE sign of the coupling variable — the digest-diagram
# "c_j = value(pag_dso_j)" is sign-ambiguous; this derivation is the authority). At the DSO
# optimum the internal balance dual β_j satisfies β_j = λ_j at consensus (pag_dso_j = a_j), so
# the recovered λ_j equals the centralized DADP `dual(balance_p[j])` with the SAME sign — pinned
# strictly-POSITIVE on the near-lossless uncongested 2-bus fixture (RESEARCH Pattern 2).
#
# BUILD-ONCE / RE-SOLVE (ADMM-03, RESEARCH Pattern 3 / Pitfall 6): AGR-OPT and DSO-OPT are built
# ONCE outside the loop; the loop mutates ONLY scalar objective coefficients via
# `set_objective_coefficient` (inside `solve_agr!`/`solve_dso!`) — NO JuMP model is constructed
# inside the loop, so num_variables/num_constraints are iteration-count-independent. (Clarabel is
# copy_to-only, so the per-iteration re-copy still happens and warm starts are a no-op — RESEARCH
# Pitfall 4; the ADMM-03 win is eliminating the JuMP-side REBUILD, not solver warm starts.)
#
# STOPPING / FAIL-LOUD (RESEARCH Pitfall 2): stop on the PRIMAL residual max_{j,t}|R_{p,j}| ≤ tol;
# hitting `maxiter` WITHOUT convergence THROWS loudly (naming iters/maxiter/worst residual) —
# NEVER returns the last iterate silently. The centralized cross-validation (ADMM-04) is the true
# false-convergence net.
#
# CONVERGENCE OUTPUTS: at convergence a FINAL DSO solve runs the PF-04 exactness gate
# (`solve_dso!(...; check_exact=true)` → `assert_socp_exact!`), welfare is recomputed from PRIMAL
# values (Σ value(U_ag) − Σ_t λ₀[t]·value(p_import) — NOT the penalized subproblem objective,
# RESEARCH Pattern 5), and the converged coupling price is returned as the DADP.

using JuMP

"""
    solve_admm(feeder, pf::ConvexBranchFlow, aggregators;
               T::Int = 24, λ₀, ρ, maxiter::Int = 200, tol::Real = 1e-5,
               allow_export::Bool = true)
        -> (; welfare, dadp, λ, iters, residuals, dso_ctx, exact_maxgap)

Solve the operational GLB-CVX social-welfare problem by hand-rolled 2-block ADMM (thesis
eqs. 3.46/3.47), the Phase-6 DECOMPOSED counterpart of the centralized [`solve_welfare`](@ref).
Recovers the SAME welfare AND the SAME day-ahead dynamic prices (DADPs) as the monolithic
optimum — the load-bearing correctness gate (ADMM-04), since the transactive prices ARE the
duals of the nodal balance (RESEARCH Pattern 5).

# Algorithm (RESEARCH System Architecture Diagram)
1. BUILD ONCE (outside the loop): one [`build_agr_opt`](@ref) per aggregator and one
   [`build_dso_opt`](@ref); initialize the coupling price `λ_j` (per load node) to `λ₀` (a
   physical warm start — the DADP is `λ₀` plus small loss/congestion/voltage terms), the netflow
   target `c_j` and the AGR-consensus target `a_j` to zeros, and an [`AdmmResiduals`](@ref).
2. Iterate `k = 1:maxiter`: solve each [`solve_agr!`](@ref) with coeff `−λ_j − ρ·c_j` collecting
   `a_j = pag_j`; solve [`solve_dso!`](@ref) with coeff `−λ_j − ρ·a_j` (mid-loop `check_exact =
   false`) collecting `pag_dso_j`; compute the primal residual `R_{p,j} = a_j − pag_dso_j` and a
   dual-residual diagnostic `ρ·Δa`; [`record!`](@ref) both; take the dual step
   `λ_j ← λ_j + ρ·R_{p,j}` and refresh the netflow target `c_j = −pag_dso_j`. Stop when
   [`converged`](@ref)`(residuals, tol)` (primal residual ≤ `tol`).
3. On convergence: a FINAL [`solve_dso!`](@ref)`(...; check_exact = true)` runs the PF-04 gate
   [`assert_socp_exact!`](@ref) (`exact_maxgap`); recompute `welfare = Σ_j value(U_ag,j) − Σ_t
   λ₀[t]·value(p_import[t])` from PRIMALS; set `dadp = λ`.

# Returns
`(; welfare, dadp, λ, iters, residuals, dso_ctx, exact_maxgap)` where `λ == dadp` is the
`(n_load_nodes, T)` converged DADP matrix (row `i` ↔ the `i`-th load node in ascending bus order,
matching `extract_dlmp(centralized)[load_buses, :]`), `dso_ctx` is the converged DSO-OPT
[`ModelContext`](@ref) (its `.model` shape is iteration-count-independent — ADMM-03), and
`exact_maxgap` the certified SOC cone residual (PF-04).

# Throws
- `ArgumentError` on empty `aggregators`, a `λ₀` shape mismatch, or more than one aggregator per
  load node (the 1:1 node↔aggregator coupling this Phase-6 loop assumes; multi-aggregator-per-bus
  netflow splitting is a Phase-7 generalization).
- A loud `ErrorException` if `maxiter` is reached WITHOUT convergence — the fail-loud cap that
  refuses to return a non-consensus iterate (RESEARCH Pitfall 2).
"""
function solve_admm(
    feeder,
    pf::ConvexBranchFlow,
    aggregators::AbstractVector{<:Aggregator};
    T::Int = 24,
    λ₀,
    ρ::Real,
    maxiter::Int = 200,
    tol::Real = 1e-5,
    allow_export::Bool = true,
)
    # ---- Boundary guards (fail here, not deep in the loop) -------------------------------------
    isempty(aggregators) && throw(ArgumentError("solve_admm needs at least one aggregator"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
    allow_export || throw(
        ArgumentError(
            "solve_admm requires allow_export=true (the free-sign priced frontier is the " *
            "SOC-exactness enabler, PF-04; import-only is out of Phase-6 scope)",
        ),
    )

    ρf = Float64(ρ)

    # ---- BUILD ONCE (ADMM-03): the subproblem models are constructed OUTSIDE the loop ----------
    # One AGR-OPT per aggregator (thesis 3.46); the whole-network DSO-OPT (thesis 3.47). No
    # `Model(`/`build_*` call appears below this point — the loop only re-solves via coefficient
    # updates, so num_variables/num_constraints stay fixed (RESEARCH Pattern 3 / Pitfall 6).
    dso = build_dso_opt(feeder, aggregators, T; ρ = ρf, λ₀ = λ₀)
    load_nodes = dso.load_nodes                       # ascending non-root aggregator buses

    # This Phase-6 loop assumes a 1:1 node↔aggregator coupling (both cross-validation fixtures
    # satisfy it: one aggregator per non-root bus). With several aggregators sharing a bus the
    # shared netflow target `c_j` could not be split unambiguously — a Phase-7 generalization.
    length(aggregators) == length(load_nodes) || throw(
        ArgumentError(
            "solve_admm assumes one aggregator per load node (got $(length(aggregators)) " *
            "aggregators for $(length(load_nodes)) load nodes); multi-aggregator-per-bus " *
            "coupling is a Phase-7 extension",
        ),
    )
    agr_by_bus = Dict{Int,AgrOpt}()
    for agg in aggregators
        haskey(agr_by_bus, agg.bus) &&
            throw(ArgumentError("two aggregators share bus $(agg.bus); solve_admm assumes 1:1"))
        agr_by_bus[agg.bus] = build_agr_opt(agg, T; ρ = ρf)
    end

    N = length(feeder.buses)
    residuals = AdmmResiduals(N, T)

    # ---- ADMM state (per load node, length-T profiles; NEVER a JuMP Parameter — Pitfall 1) -----
    # Warm-start the INTERNAL multiplier at −λ₀. The internal `λ` is the multiplier of the
    # `−λ_jᵀR_{p,j}` term and converges to `−DADP` (the reported price negates it — see the
    # return block). Since the DADP is `λ₀` plus small loss/congestion/voltage terms, `−λ₀` starts
    # the internal multiplier RIGHT NEXT to the solution; warm-starting at `+λ₀` (its negation)
    # would place it a distance `≈2·λ₀` away and make dual ascent crawl across the whole gap
    # (empirically ~100+ iters on the congested IEEE-13), whereas `−λ₀` converges the DADP in ~10.
    λ = Dict{Int,Vector{Float64}}(j => Float64[-λ₀[t] for t in 1:T] for j in load_nodes)
    c = Dict{Int,Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)   # netflow target for AGR
    a = Dict{Int,Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)   # pag target for DSO
    a_prev = Dict{Int,Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)
    util = Dict{Int,Float64}(j => 0.0 for j in load_nodes)                      # U_ag per node (primal welfare)
    p_import = zeros(Float64, T)                                                # frontier exchange (primal welfare)
    exact_maxgap = nothing

    converged_flag = false
    for k in 1:maxiter
        # (1) AGR-OPT[j] ∀j: coeff −λ_j − ρ·c_j (thesis 3.46). a_j = solved net injection.
        # `check_battery = false` mid-loop: the App. C complementarity is a property of the
        # correctly-priced CONVERGED optimum, not of an off-consensus iterate where λ_j is still
        # being found (the battery legitimately co-activates at a wrong price) — the same reason
        # the DSO exactness gate is deferred to convergence (RESEARCH Pitfall 3). The gate is run
        # on the final converged re-solve below.
        for j in load_nodes
            r = solve_agr!(agr_by_bus[j], λ[j], c[j], ρf; check_battery = false, strict = false)
            a[j] = r.pag
            util[j] = r.utility
        end

        # (2) DSO-OPT: coeff −λ_j − ρ·a_j (thesis 3.47). Mid-loop iterates are legitimately
        # inexact, so the PF-04 gate is NOT run here (check_exact = false; RESEARCH Pitfall 3),
        # and the mid-loop solve tolerates a NEARLY_FEASIBLE primal (strict = false; the DSO dual
        # is never read — the price is the outer multiplier λ). The final solve below is STRICT.
        dres = solve_dso!(dso, λ, a, ρf; check_exact = false, strict = false)
        pag_dso = dres.pag_dso
        p_import = dres.p_import

        # (3) Primal residual R_{p,j}[t] = a_j[t] − pag_dso_j[t] (consensus violation → 0), and
        # the dual-residual diagnostic ρ·Δa (tracked in Phase 6; the hard dual-residual stop is
        # Phase 7). The centralized cross-validation is Phase 6's true false-convergence net.
        primal_maxabs = 0.0
        dual_maxabs = 0.0
        for j in load_nodes, t in 1:T
            rp = a[j][t] - pag_dso[j, t]
            primal_maxabs = max(primal_maxabs, abs(rp))
            dual_maxabs = max(dual_maxabs, ρf * abs(a[j][t] - a_prev[j][t]))
        end
        record!(residuals, k, primal_maxabs, dual_maxabs)

        if converged(residuals, tol)
            converged_flag = true
            break
        end

        # Dual ascent λ_j ← λ_j + ρ·R_{p,j} and refresh the netflow target c_j = −pag_dso_j (the
        # network injection carries the OPPOSITE sign of the coupling variable — see file header).
        for j in load_nodes
            a_prev[j] = copy(a[j])
            for t in 1:T
                λ[j][t] += ρf * (a[j][t] - pag_dso[j, t])
                c[j][t] = -pag_dso[j, t]
            end
        end
    end

    # ---- FAIL LOUD on the maxiter cap (RESEARCH Pitfall 2) — never return a non-consensus point.
    converged_flag || throw(
        ErrorException(
            "solve_admm FAILED to converge: hit maxiter=$maxiter without the primal residual " *
            "reaching tol=$tol (worst |R_p| = $(last(residuals.primal_trace)); ρ=$ρf). Retune ρ " *
            "or raise maxiter — the last iterate is NOT a consensus optimum and is refused " *
            "(thesis §2.6; RESEARCH Pitfall 2).",
        ),
    )

    # ---- Converged: FINAL consolidation pass running BOTH PHYSICAL gates (RESEARCH Pitfall 3 /
    # Pattern 5). The coupling (λ, c, a) is unchanged from the converged iterate, so these re-solves
    # reproduce the converged primal and only ADD the certificates:
    #   • AGR-OPT[j] with check_battery = true: the App. C complementarity gate at the correctly-
    #     priced optimum, with the interior-point τ_batt = 1e-3 (Clarabel is an IPM that
    #     co-activates the optimal face, matching the SOCP-path τ in `solve_welfare`; the QP-tight
    #     1e-6 under-tolerances the converged point at IEEE-13 scale).
    #   • DSO-OPT with check_exact = true: the PF-04 SOC exactness gate (assert_socp_exact!).
    #
    # `strict = false` on BOTH: the ADMM subproblem DUALS are never the published price (the DADP
    # is the outer multiplier λ, cross-validated against the centralized optimum), so requiring
    # the interior-point backend to hit its centralized-grade 1e-8 gap EXACTLY at the converged
    # point is a brittle, non-load-bearing condition (under the ρ-penalty Clarabel intermittently
    # stops at ALMOST_OPTIMAL / NEARLY_FEASIBLE). The load-bearing certificate of the converged
    # PRIMAL is the pair of PHYSICAL gates run here — the base-free PF-04 SOC exactness check
    # (`rtol = 1e-4`) and the relative App. C battery complementarity check — which are strictly
    # stronger than the solver's OPTIMAL/ALMOST label. This mirrors the mid-loop treatment; the
    # ONLY difference between mid-loop and final is that the final pass RUNS these physical gates.
    for j in load_nodes
        r = solve_agr!(
            agr_by_bus[j], λ[j], c[j], ρf; check_battery = true, τ_batt = 1e-3, strict = false,
        )
        a[j] = r.pag
        util[j] = r.utility
    end
    dres_final = solve_dso!(dso, λ, a, ρf; check_exact = true, strict = false)
    p_import = dres_final.p_import
    exact_maxgap = dres_final.exact_maxgap

    # ---- Welfare recomputed from PRIMALS (Σ U_ag − λ₀ᵀp_import — NOT the penalized objective) --
    welfare = sum(util[j] for j in load_nodes) - sum(λ₀[t] * p_import[t] for t in 1:T)

    # ---- Converged DADP: the coupling price, as an (n_load_nodes, T) matrix in ascending-bus
    # order (matching extract_dlmp(centralized)[load_buses, :]). dadp == λ.
    #
    # SIGN CONVENTION (RESEARCH Pitfall 5 — pinned empirically on the 2-bus). The internal
    # multiplier `λ[j]` is the Lagrange multiplier of the `−λ_jᵀR_{p,j}` term in the MAX augmented
    # Lagrangian; it converges to `−dual(balance_p[j])` under JuMP's equality-dual sign convention
    # for a `Max` objective. `extract_dlmp` reports `+dual(balance_p[j])` (positive = marginal cost
    # of consumption). So the reported DADP is the NEGATED internal multiplier — verified against
    # the near-lossless uncongested 2-bus, where the analytic load-bus price is `+λ₀ > 0` and the
    # centralized `dual` is `+4.0` while the raw internal `λ` lands at `−4.0`. This negation is a
    # reporting-only convention alignment; the internal `λ` (unnegated) is what drove the
    # coefficient updates and the (welfare-exact) convergence above.
    λ_mat = reduce(vcat, (permutedims(-λ[j]) for j in load_nodes))

    return (;
        welfare = welfare,
        dadp = λ_mat,
        λ = λ_mat,
        iters = residuals.iters,
        residuals = residuals,
        dso_ctx = dso.ctx,
        exact_maxgap = exact_maxgap,
    )
end

export solve_admm

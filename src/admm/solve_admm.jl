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
# STOPPING / FAIL-LOUD (RESEARCH Pattern 2/3 / Pitfall 2): stop on BOTH the Boyd 2-norm PRIMAL
# residual ‖r‖₂ = ‖a − pag_dso‖₂ ≤ ε_pri AND the z-block DUAL residual ‖s‖₂ = ρ·‖Δ(pag_dso)‖₂ ≤
# ε_dual, with per-unit-normalized thresholds ε_pri = √p·ε_abs + ε_rel·max(‖a‖,‖pag_dso‖) / ε_dual
# = √p·ε_abs + ε_rel·‖λ‖ (p = n = n_load_nodes·T). A primal-only stop is the textbook
# false-convergence bug — the dual side (the price has stopped moving) is MANDATORY. Hitting
# `maxiter` WITHOUT both residuals below threshold THROWS loudly (naming ‖r‖/ε_pri/‖s‖/ε_dual) —
# NEVER returns the last iterate silently. The centralized cross-validation (ADMM-04) is the
# outer false-convergence net.
#
# CONVERGENCE OUTPUTS: at convergence a FINAL DSO solve runs the PF-04 exactness gate
# (`solve_dso!(...; check_exact=true)` → `assert_socp_exact!`), welfare is recomputed from PRIMAL
# values (Σ value(U_ag) − Σ_t λ₀[t]·value(p_import) — NOT the penalized subproblem objective,
# RESEARCH Pattern 5), and the converged coupling price is returned as the DADP.

using JuMP

"""
    solve_admm(feeder, pf::ConvexBranchFlow, aggregators;
               T::Int = 24, λ₀, ρ, maxiter::Int = 200, tol::Real = 1e-5,
               ε_abs::Real = 1e-4, ε_rel::Real = 1e-3,
               τ::Real = 2.0, μ::Real = 10.0, ρ_min::Real = 1e-2, ρ_max::Real = 1e4,
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
   false`) collecting `pag_dso_j`; compute the Boyd PRIMAL residual `‖r‖₂ = ‖a − pag_dso‖₂` and the
   z-block DUAL residual `‖s‖₂ = ρ·‖pag_dso − pag_dso_prev‖₂` (RESEARCH Pattern 2), the per-unit
   thresholds `ε_pri`/`ε_dual` (Pattern 3), and the price move `‖Δλ‖₂`; [`record!`](@ref) the
   extended trace tuple; take the UNSCALED dual step `λ_j ← λ_j + ρ·R_{p,j}` (λ is NEVER rescaled on
   a ρ change), refresh the netflow target `c_j = −pag_dso_j`, and snapshot `pag_dso_prev = pag_dso`.
   Stop when [`converged`](@ref)`(residuals, ε_pri, ε_dual)` — BOTH `‖r‖ ≤ ε_pri` AND `‖s‖ ≤ ε_dual`
   (a primal-only stop is the textbook false-convergence bug).
   After the step, ADAPT ρ by residual balancing (RESEARCH Pattern 4, Boyd §3.4.1): `ρ ← τ·ρ` if
   the primal lags (`‖r‖ > μ‖s‖`), `ρ ← ρ/τ` if the dual lags (`‖s‖ > μ‖r‖`), clamped to
   `[ρ_min, ρ_max]`; on an actual change call [`set_rho!`](@ref) on the DSO-OPT and every AGR-OPT so
   the quadratic penalty tracks ρ WITHOUT a rebuild (build-once preserved). ρ FREEZES once both
   residuals fall within `10×` their thresholds (Boyd's fixed-ρ convergence tail).
3. On convergence: a FINAL [`solve_dso!`](@ref)`(...; check_exact = true)` runs the PF-04 gate
   [`assert_socp_exact!`](@ref) (`exact_maxgap`); recompute `welfare = Σ_j value(U_ag,j) − Σ_t
   λ₀[t]·value(p_import[t])` from PRIMALS; set `dadp = λ`.

# Adaptive ρ (RESEARCH Pattern 4 — the Phase-7 upgrade of the Phase-6 fixed ρ)
The `ρ` keyword is now the INITIAL penalty ρ₀ (all Phase-6 call sites keep working). ρ then adapts
by per-unit residual balancing (`τ`, `μ`) and is clamped to `[ρ_min, ρ_max]`, so the SAME
`(ε_abs, ε_rel, τ, μ, ρ_min, ρ_max)` converge the 2-bus, IEEE-13 AND IEEE-123 cases WITHOUT any
hard-coded scale-specific penalty (per-unit scale-invariance, ADMM-02). λ is the UNSCALED physical
price and is NEVER rescaled on a ρ change. The `tol` keyword is RETAINED for call-site
compatibility but is superseded by the per-unit two-residual stop (`ε_abs`/`ε_rel`).

# Returns
`(; welfare, dadp, λ, iters, residuals, dso_ctx, exact_maxgap)` where `λ == dadp` is the
`(n_load_nodes, T)` converged DADP matrix (row `i` ↔ the `i`-th load node in ascending bus order,
matching `extract_dlmp(centralized)[load_buses, :]`), `dso_ctx` is the converged DSO-OPT
[`ModelContext`](@ref) (its `.model` shape is iteration-count-independent — ADMM-03), and
`exact_maxgap` the certified SOC cone residual (PF-04).

# Throws
- `ArgumentError` on empty `aggregators`, a `λ₀` shape mismatch, a non-positive `maxiter`
  (`maxiter < 1` cannot even attempt consensus), or more than one aggregator per load node (the
  1:1 node↔aggregator coupling this Phase-6 loop assumes; multi-aggregator-per-bus netflow
  splitting is a Phase-7 generalization).
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
    ε_abs::Real = 1e-4,
    ε_rel::Real = 1e-3,
    τ::Real = 2.0,
    μ::Real = 10.0,
    ρ_min::Real = 1e-2,
    ρ_max::Real = 1e4,
    allow_export::Bool = true,
)
    # ---- Boundary guards (fail here, not deep in the loop) -------------------------------------
    isempty(aggregators) && throw(ArgumentError("solve_admm needs at least one aggregator"))
    # A degenerate horizon (T = 0, with a length-0 λ₀ that would pass the shape guard below) makes
    # the coupling-entry count p = length(load_nodes)·T == 0, so ε_pri = ε_dual = 0 AND every
    # residual sum is 0 — `converged` then returns true on iteration 1 and the loop reports a
    # NONSENSICAL "converged" result for an empty problem (IN-03). Reject it up front.
    T >= 1 || throw(ArgumentError("solve_admm needs T ≥ 1 (got T=$T)"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
    # A non-positive iteration budget never enters the loop, so the residual trace stays empty and
    # the fail-loud cap below would itself throw an opaque BoundsError on `last(...)` (WR-01). Reject
    # it here with a CLEAR message instead — maxiter ≥ 1 is the minimum to even attempt consensus.
    maxiter >= 1 ||
        throw(ArgumentError("solve_admm needs maxiter ≥ 1 (got maxiter=$maxiter)"))
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
    # Boyd z-block dual residual s = ρ·‖Δ(pag_dso)‖₂ tracks the CONSENSUS (second-updated) block —
    # store the previous iterate's pag_dso EXACTLY as Phase 6 stored `a_prev` for its ρ·Δa
    # diagnostic. Initialized to zeros ⇒ iteration 1's s = ρ·‖pag_dso¹‖₂ is large (so a 1-iteration
    # budget cannot false-converge; RESEARCH Pattern 2 / Pitfall 2).
    pag_dso_prev = Dict{Int,Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)
    util = Dict{Int,Float64}(j => 0.0 for j in load_nodes)                      # U_ag per node (primal welfare)
    p_import = zeros(Float64, T)                                                # frontier exchange (primal welfare)
    exact_maxgap = nothing

    # ---- Adaptive-ρ state (RESEARCH Pattern 4, Boyd §3.4.1). `ρf` is the LIVE penalty/dual-step
    # (initialized to the ρ₀ keyword). `ρ_frozen` latches TRUE once both residuals fall within ~10×
    # tolerance, after which ρ is held fixed (Boyd's convergence theory assumes ρ eventually
    # constant — prevents late-stage oscillation stalling the tail). τ/μ are the residual-balancing
    # multiplier/band; [ρ_min, ρ_max] clamp the penalty (SOCP-conditioning + proximal meaningfulness).
    ρ_frozen = false

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
        # is never read — the price is the outer multiplier λ). The final solve below likewise
        # tolerates the benign ALMOST_OPTIMAL label but adds PHYSICAL published-primal certificates
        # (PF-04 exactness + the WR-01 active-balance no-slack gate — see the final block).
        dres = solve_dso!(dso, λ, a, ρf; check_exact = false, strict = false)
        pag_dso = dres.pag_dso
        p_import = dres.p_import

        # (3) BOYD TWO-RESIDUAL diagnostics (RESEARCH Pattern 2 / 3; thesis App. B.30–B.32, the
        # UNSCALED form). PRIMAL residual r = ‖a − pag_dso‖₂ (the 2-norm of the consensus violation,
        # → 0 ⇔ the two blocks agree). DUAL residual s = ρ·‖pag_dso − pag_dso_prev‖₂ (the z-block
        # change — the SECOND-updated consensus block; → 0 ⇔ the price has stopped moving, i.e.
        # optimality). This REPLACES the Phase-6 ρ·Δa x-block diagnostic (the wrong block, a textbook
        # false-convergence bug). Both use the 2-norm over the flattened (j,t) coupling entries so
        # they match the √p·ε_abs per-unit tolerance scaling.
        sq_r = 0.0        # Σ (a − pag_dso)²        → ‖r‖₂
        sq_ds = 0.0       # Σ (Δ pag_dso)²          → ‖s‖₂ / ρ
        sq_a = 0.0        # Σ a²                    → ‖a‖₂
        sq_pd = 0.0       # Σ pag_dso²              → ‖pag_dso‖₂
        sq_λ = 0.0        # Σ λ²                    → ‖λ‖₂
        for j in load_nodes, t in 1:T
            rp = a[j][t] - pag_dso[j, t]
            dz = pag_dso[j, t] - pag_dso_prev[j][t]
            sq_r += rp^2
            sq_ds += dz^2
            sq_a += a[j][t]^2
            sq_pd += pag_dso[j, t]^2
            sq_λ += λ[j][t]^2
        end
        r_norm = sqrt(sq_r)
        s_norm = ρf * sqrt(sq_ds)

        # (4) PER-UNIT stopping thresholds (Boyd §3.3.1 eq. 3.12, RESEARCH Pattern 3). p = n =
        # n_load_nodes·T is the coupling-entry count; the √p·ε_abs floor is dimensionless-in-pu and
        # the ε_rel·‖·‖ term makes the threshold a fixed fraction of the iterate magnitude, so the
        # SAME (ε_abs, ε_rel) transfer unchanged across the 2-bus / IEEE-13 / IEEE-123 scales
        # (per-unit scale-invariance — the "no hard-coded scale-specific penalty" requirement).
        p = length(load_nodes) * T
        ε_pri = sqrt(p) * ε_abs + ε_rel * max(sqrt(sq_a), sqrt(sq_pd))
        ε_dual = sqrt(p) * ε_abs + ε_rel * sqrt(sq_λ)
        # price_gap = ‖Δλ‖₂ of the pending UNSCALED dual step λ ← λ + ρ·r (== ρ·‖r‖₂, since Δλ = ρ·r):
        # the per-iteration price-convergence trajectory (ADMM-05 plot diagnostic).
        price_gap = ρf * r_norm

        record!(residuals, k, r_norm, s_norm, ρf, ε_pri, ε_dual, price_gap)

        # STOP iff BOTH ‖r‖₂ ≤ ε_pri AND ‖s‖₂ ≤ ε_dual (RESEARCH Pattern 2 / Pitfall 2). A
        # primal-satisfied-but-dual-unsatisfied iterate does NOT stop — the false-convergence net.
        if converged(residuals, ε_pri, ε_dual)
            converged_flag = true
            break
        end

        # Dual ascent λ_j ← λ_j + ρ·R_{p,j} (UNSCALED — λ is the physical price, NOT rescaled on a ρ
        # change; RESEARCH Pattern 4) and refresh the netflow target c_j = −pag_dso_j (the network
        # injection carries the OPPOSITE sign of the coupling variable — see file header). Snapshot
        # pag_dso into pag_dso_prev for the NEXT iteration's z-block dual residual.
        for j in load_nodes
            for t in 1:T
                pag_dso_prev[j][t] = pag_dso[j, t]
                λ[j][t] += ρf * (a[j][t] - pag_dso[j, t])
                c[j][t] = -pag_dso[j, t]
            end
        end

        # (5) RESIDUAL-BALANCING ADAPTIVE ρ (Boyd §3.4.1 eq. 3.13, RESEARCH Pattern 4). Once BOTH
        # residuals are within ~10× tolerance, FREEZE (latch) — Boyd's convergence theory assumes ρ
        # eventually fixed, and freezing stops late-stage ρ oscillation from stalling the tail.
        #
        # BALANCE ON ε-NORMALIZED RESIDUALS (r̂ = ‖r‖/ε_pri, ŝ = ‖s‖/ε_dual), NOT the raw ‖r‖/‖s‖:
        # here ε_pri (∝ the tiny per-unit injection magnitude) and ε_dual (∝ ‖λ‖, the O(1–10) price)
        # differ by ~50×, so a RAW ‖r‖-vs-μ‖s‖ comparison is apples-to-oranges — it reads "balanced"
        # while the primal is 60× its tolerance and the dual only 3×, leaving ρ stuck at a value too
        # small to regularize the DSO SOCP (Clarabel NUMERICAL_ERROR by iter 3 on IEEE-13). Comparing
        # each residual to its OWN threshold makes the balancing dimensionless and self-consistent
        # with the freeze/stop tests (which already use r/ε_pri, s/ε_dual), so the SAME (τ, μ, ρ_min,
        # ρ_max) climb ρ from ρ₀ to a well-conditioned value on the 2-bus, IEEE-13 AND IEEE-123
        # (per-unit scale-invariance, ADMM-02). This is the standard scaled-residual balancing form.
        #
        # ρ ← τ·ρ if the primal lags (r̂ > μ·ŝ ⇒ penalize consensus harder), ρ ← ρ/τ if the dual lags
        # (ŝ > μ·r̂ ⇒ relax the penalty), clamped to [ρ_min, ρ_max]. On an ACTUAL change call set_rho!
        # on the DSO-OPT and every AGR-OPT so the QUADRATIC penalty matches the new ρ WITHOUT a
        # rebuild (build-once preserved, ADMM-04) — in lockstep with the linear/ascent ρf (Pitfall 1:
        # penalty ρ and ascent ρ must never diverge). λ is NOT rescaled (unscaled physical price;
        # Pattern 4). ρ > 0 always (clamp ⇒ convexity kept).
        if !ρ_frozen
            r̂ = r_norm / ε_pri
            ŝ = s_norm / ε_dual
            if r̂ <= 10 && ŝ <= 10
                ρ_frozen = true
            else
                ρ_new = if r̂ > μ * ŝ
                    τ * ρf
                elseif ŝ > μ * r̂
                    ρf / τ
                else
                    ρf
                end
                ρ_new = clamp(ρ_new, ρ_min, ρ_max)
                if ρ_new != ρf
                    ρf = ρ_new
                    set_rho!(dso, ρf)
                    for j in load_nodes
                        set_rho!(agr_by_bus[j], ρf)
                    end
                end
            end
        end
    end

    # ---- FAIL LOUD on the maxiter cap (RESEARCH Pitfall 2) — never return a non-consensus point.
    converged_flag || throw(
        ErrorException(
            "solve_admm FAILED to converge: hit maxiter=$maxiter without BOTH the primal residual " *
            "‖r‖ ≤ ε_pri AND the dual residual ‖s‖ ≤ ε_dual (last ‖r‖ = $(last(residuals.primal_trace)) " *
            "vs ε_pri = $(last(residuals.eps_pri_trace)); last ‖s‖ = $(last(residuals.dual_trace)) vs " *
            "ε_dual = $(last(residuals.eps_dual_trace)); ρ=$ρf). Retune the adaptive-ρ config " *
            "(ε_abs/ε_rel/τ/μ/ρ_min/ρ_max) or raise maxiter — the last iterate is NOT a consensus " *
            "optimum and is refused (thesis §2.6; RESEARCH Pitfall 2).",
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
    # `strict = false` on BOTH tolerates the conic backend's BENIGN solver LABEL: under the converged
    # ρ-penalty Clarabel intermittently stops at ALMOST_OPTIMAL / NEARLY_FEASIBLE — an interior-point
    # gap artefact at the true optimum, NOT a physical infeasibility, and the ADMM subproblem DUALS
    # are never the published price (the DADP is the outer multiplier λ, cross-validated against the
    # centralized optimum). Requiring the STRICT solver label here is brittle: it spuriously rejects
    # the genuinely-converged IEEE-13 / IEEE-123 optima (verified — they stop ALMOST_OPTIMAL).
    #
    # WR-01 / INFRA-03: because THIS primal is PUBLISHED (the reported `welfare`
    # Σ value(U_ag) − λ₀ᵀvalue(p_import), and the PF-04 exactness certificate), the "no near-feasible
    # result is ever published" contract is enforced by PHYSICAL gates that are INDEPENDENT of the
    # solver's OPTIMAL/ALMOST label — strictly stronger than that label — rather than by tolerating a
    # near-infeasible primal silently: (1) the PF-04 SOC exactness gate (`assert_socp_exact!`, rtol
    # 1e-4); (2) the App. C battery complementarity gate; and (3) the ACTIVE nodal-balance no-slack
    # certificate added AFTER the final solve below (`assert_no_slack` on `:balance_p`). A genuinely
    # near-INFEASIBLE final primal fails LOUDLY on those gates at runtime; only the benign solver
    # LABEL is tolerated.
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

    # WR-01 PUBLISHED-PRIMAL CERTIFICATE (INFRA-03). The final DSO solve tolerates the conic
    # backend's BENIGN `ALMOST_OPTIMAL`/`NEARLY_FEASIBLE` LABEL (under the converged ρ-penalty
    # Clarabel intermittently stops just shy of its centralized-grade gap — a solver-label artefact,
    # not a physical infeasibility). But `welfare` (Σ value(U_ag) − λ₀ᵀvalue(p_import)) is PUBLISHED
    # from THIS primal, so relying on the solver's OPTIMAL/ALMOST label alone would let a genuinely
    # near-infeasible primal flow silently into the reported price. Add a PHYSICAL runtime gate that
    # is INDEPENDENT of the solver label: recompute the ACTIVE nodal-balance residual (`:balance_p`,
    # thesis 3.31 — the constraint whose primal feeds `p_import`→`welfare` and whose dual is the
    # DADP) from the solved variables and FAIL LOUDLY if any entry carries hidden slack. The active
    # balance is closed by the FREE `p_import`/`pag_dso` variables, so a genuinely converged primal
    # satisfies it to machine precision (empirically ≈0); a near-INFEASIBLE final primal would show
    # slack here and is refused — the loud runtime signal WR-01 requires, strictly stronger than the
    # `allow_almost` solver label. `:balance_q` (the INELASTIC constant reactive-draw closure — NOT a
    # published/load-bearing quantity; the DADP and welfare are ACTIVE) legitimately carries the
    # conic solver's NEARLY_FEASIBLE reactive slack under the ρ-penalty, so it is intentionally not
    # gated here — gating it would spuriously reject a genuinely-converged transactive optimum.
    let balance_p = dso.ctx.constraints[:balance_p]
        for j in 1:size(balance_p, 1), t in 1:size(balance_p, 2)
            assert_no_slack(dso.model, balance_p[j, t]; atol = 1e-6)
        end
    end

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

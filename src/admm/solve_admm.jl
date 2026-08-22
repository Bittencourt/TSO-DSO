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
               allow_export::Bool = true, reactive_consensus = false, ρ_q::Real = ρ,
               time_limit_s::Union{Nothing,Real} = nothing)
        -> (; welfare, dadp, λ, iters, residuals, dso_ctx, exact_maxgap, mu_q, q_devices, status)

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
    `a_j = pag_j`; solve [`solve_dso!`](@ref) with coeff `−λ_j − ρ·a_j` (mid-loop `check_exact = false`) collecting `pag_dso_j`; compute the Boyd PRIMAL residual `‖r‖₂ = ‖a − pag_dso‖₂` and the
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
    [`assert_socp_exact!`](@ref) (`exact_maxgap`); recompute `welfare = Σ_j value(U_ag,j) − Σ_t λ₀[t]·value(p_import[t])` from PRIMALS; set `dadp = λ`.

# Adaptive ρ (RESEARCH Pattern 4 — the Phase-7 upgrade of the Phase-6 fixed ρ)

The `ρ` keyword is now the INITIAL penalty ρ₀ (all Phase-6 call sites keep working). ρ then adapts
by per-unit residual balancing (`τ`, `μ`) and is clamped to `[ρ_min, ρ_max]`, so the SAME
`(ε_abs, ε_rel, τ, μ, ρ_min, ρ_max)` converge the 2-bus, IEEE-13 AND IEEE-123 cases WITHOUT any
hard-coded scale-specific penalty (per-unit scale-invariance, ADMM-02). λ is the UNSCALED physical
price and is NEVER rescaled on a ρ change. The `tol` keyword is RETAINED for call-site
compatibility but is superseded by the per-unit two-residual stop (`ε_abs`/`ε_rel`).

# Reactive consensus (Phase 16, REACT-01/02 — `reactive_consensus::Bool = false`)

Threaded straight into [`build_dso_opt`](@ref). At the DEFAULT `false`, byte-identical to
pre-Phase-16 behavior (REACT-03): the per-load-node reactive draw stays the constant `q_draw`
and NO extra certificate runs. At `true`, `build_dso_opt` promotes it to the pinned coupling
variable `qag_dso[j,t]` (`ctx.meta[:qag_dso]`), and after the final consolidation solve this
function additionally certifies `:balance_q` via [`assert_no_slack`](@ref) — mirroring the
`:balance_p` certificate — so its dual becomes trustworthy/publishable (e.g. as a reactive DLMP
component). This is a ONE-SHOT certified dual read, NOT a live μ dual-ascent loop (thesis A3:
`qag_dso` is pinned to a fixed target that never moves, so convergence speed is materially
unaffected).

# Live reactive dual-ascent (Phase 19, MESH-05 — `reactive_consensus = :live`, `ρ_q::Real = ρ`)

`reactive_consensus` now accepts a 3-state [`ReactiveMode`](@ref) (via
[`normalize_reactive_mode`](@ref) — `Bool`/`Symbol`/`ReactiveMode` all accepted; `false → OFF`,
`true → CERTIFIED`, back-compat preserved byte-identically for both). The NEW `LIVE` state
(`:live`) makes `qag_dso[j,t]` a genuinely OPEN coupling variable — unpinned, unlike
`CERTIFIED` — and drives it with a SECOND, jointly-converging dual-ascent block on the SAME
outer loop, in EXACT mirror of the ACTIVE `λ`/`pag_dso` machinery above:

  - A reactive coupling multiplier `μ` (NEVER named bare `μ`/`mu`/`MU` internally — that
    identifier is the adaptive-ρ residual-balancing imbalance band, `μ::Real = 10.0` above; the
    internal state uses the distinct name `μq`) is dual-ascended alongside `λ`, with its OWN
    penalty weight `ρ_q` (defaults to tracking `ρ`, adapted independently thereafter).
  - JOINT STACKED STOPPING RULE (Boyd §3.3's multi-block caveat; RESEARCH Pitfall 17): the primal/
    dual residuals and per-unit thresholds are computed as ONE stacked norm over BOTH the active
    (`λ`/`pag_dso`) and reactive (`μ`/`qag_dso`) coupling axes, feeding a SINGLE
    [`record!`](@ref)/[`converged`](@ref) call — NEVER two independent per-block checks (a
    textbook false-convergence bug on a two-block ADMM). `ρ` and `ρ_q` adapt INDEPENDENTLY of
    each other (each block balances its OWN normalized residuals), since a shared ρ would be
    badly scaled for the typically much-smaller reactive channel.
  - SIGN CONVENTION (empirically verified this plan, on a 2-bus + `FourQuadBESS` fixture with
    REAL — non-near-lossless — impedance, mirroring EXACTLY how `λ`'s sign was originally pinned
    above): the internal `μq` converges to the NEGATED `dual(:balance_q[j])` — the SAME
    relationship `λ` has to `dual(:balance_p[j])` — consistent with the P↔Q structural symmetry
    of the single augmented Lagrangian (the reactive block is built by the IDENTICAL
    AGR-fixes-target / DSO-renames-coupling-variable construction, merely on the `Rq`/`qag_dso`
    axis). The reported `mu_q` (see Returns) is therefore the NEGATED internal `μq`, mirroring
    `λ_mat = -λ` exactly. (`mu_q` is the return-key handle the phase-16 naming audit RESERVED
    for exactly this quantity — `test_admm_reactive.jl`'s grep-audit header; a bare-`μ` return
    key would collide with the `μ::Real = 10.0` adaptive-ρ band kwarg in this very signature,
    the phase-19 review's WR-03.)
  - The final consolidation block ALSO wires the NEW 4Q complementarity certificate
    ([`assert_4q_complementarity!`](@ref) via `solve_agr!`'s `check_4q` kwarg) for any aggregator
    whose devices genuinely include a `FourQuadBESS` — INDEPENDENT of `reactive_consensus`, since
    the App. C-style `p_ch·p_dch ≈ 0` property is a property of the DEVICE, not of whether its
    reactive coupling happens to be pinned or live.
  - CROSS-VALIDATION SCOPE (D-03): comparing a `LIVE` run against the centralized [`solve_welfare`](@ref)
    compares welfare, `λ`, AND `μ` — but NEVER an individual `FourQuadBESS`'s `q` trajectory. When
    the reactive nodal dual `μ ≈ 0` (a near-lossless/uncongested reactive channel, an HONEST
    feature of the model, not a bug), a device's own P-Q split inside its apparent-power cone can
    be non-unique/degenerate — pinning a non-unique quantity would be meaningless.

# Wall-clock budget (Phase 25, D-18 — `time_limit_s::Union{Nothing,Real} = nothing`)

An OPTIONAL wall-clock budget for the WHOLE consensus loop, checked once per iteration
immediately AFTER the convergence check and BEFORE the dual-ascent update. The DEFAULT
`nothing` preserves the pre-existing unbounded behavior BYTE-FOR-BYTE — this is purely
additive. When a finite `time_limit_s` elapses before convergence, the loop breaks
HONESTLY: it does NOT throw (unlike the `maxiter` fail-loud cap below, which still fires
for a genuine non-convergence with NO time budget set) and it does NOT run the final
consolidation pass (which assumes a converged, certified iterate — meaningless on a
mid-loop point). Instead it returns EARLY with `status = :budget_exceeded` and
`welfare = dadp = λ = exact_maxgap = mu_q = nothing`, `q_devices = Dict{Int,Vector{Float64}}()`
— a `nothing` price is a deliberate signal that no certified transactive price exists yet,
never a plausible-but-uncertified number silently returned as if it were the DADP.

# Exactness-gate override seam (2026-08-22 follow-up, quick task 260822-f0b —
`atol_exact::Real = 1e-6, rtol_exact::Real = 1e-4`)

An ADDITIVE override onto [`assert_socp_exact!`](@ref)'s own `atol`/`rtol` kwargs, threaded
ONLY into the FINAL consolidation [`solve_dso!`](@ref) call (the mid-loop `check_exact = false`
call never reaches the gate, so there is nothing to thread there). Defaults are copied VERBATIM
from `assert_socp_exact!`'s own current defaults (`src/models/exactness.jl:78`), matching this
project's existing `rtol_exact` naming precedent (`solve_welfare`, `stochastic_welfare.jl`,
`subproblem.jl`) — every existing caller of `solve_admm` is byte-identical at these defaults.
This is a SEAM, not a default weakening (T-25-12, certificate-laundering): it must never be
used to manufacture a passing verdict for a point that would otherwise be inexact under the
project's own default gate. A caller overriding it is asserting they have their OWN
independently measured noise floor for the tolerance they pass, mirroring how
`scripts/benchmark_ieee8500.jl`'s `IEEE8500_MV_EXACT_ATOL`/`IEEE8500_EXACT_ATOL` were derived.

# Returns

`(; welfare, dadp, λ, iters, residuals, dso_ctx, exact_maxgap, mu_q, q_devices, status)` where
`status` is `:converged` on the normal path (ADDITIVE new field — every other field is
UNCHANGED from before this plan) or `:budget_exceeded` on the new early-exit path above
(see "Wall-clock budget"). `λ == dadp`
is the `(n_load_nodes, T)` converged DADP matrix (row `i` ↔ the `i`-th load node in ascending bus
order, matching `extract_dlmp(centralized)[load_buses, :]`), `dso_ctx` is the converged DSO-OPT
[`ModelContext`](@ref) (its `.model` shape is iteration-count-independent — ADMM-03), and
`exact_maxgap` the certified SOC cone residual (PF-04). `mu_q`/`q_devices` are STABLE keys, ALWAYS
present in the returned `NamedTuple` (Claude's Discretion, MESH-05 D-11): under `OFF`/`CERTIFIED`
both are `nothing` (mirrors this file's own `exact_maxgap` convention — always a key, `nothing`
until populated); under `LIVE`, `mu_q` is the `(n_load_nodes, T)` converged reactive-price matrix
(SAME ascending-bus-order convention as `λ_mat`, sign-corrected per the empirical finding above)
and `q_devices::Dict{Int,Vector{Float64}}` holds each `FourQuadBESS`'s converged length-`T` `q`
trajectory, keyed by bus. The key is `mu_q`, NEVER bare `μ`: the same signature carries the
`μ::Real = 10.0` adaptive-ρ residual-balancing band kwarg, and the phase-16 naming audit
(`test_admm_reactive.jl`'s header) reserves `mu_q` as THE code handle for the extracted reactive
price (WR-03, phase-19 review).

# Throws

  - `ArgumentError` on empty `aggregators`, a `λ₀` shape mismatch, a non-positive `maxiter`
    (`maxiter < 1` cannot even attempt consensus), or more than one aggregator per load node (the
    1:1 node↔aggregator coupling this Phase-6 loop assumes; multi-aggregator-per-bus netflow
    splitting is a Phase-7 generalization).
  - `ArgumentError` (via [`build_dso_opt`](@ref) — WR-04, phase-19 review) when any aggregator
    carries a `q_inject`-bearing device (`FourQuadBESS`) while `reactive_consensus` is NOT
    `:live`: under `OFF`/`CERTIFIED` the DSO reactive closure is the inelastic `−Pdc·tanφ` draw
    alone, so the device's reactive decision would be silently dropped from the network model
    (and, under `CERTIFIED`, the certified `dual(:balance_q)` would be priced against a closure
    that no longer matches the centralized model's). Pass `reactive_consensus = :live`.
  - A loud `ErrorException` if `maxiter` is reached WITHOUT convergence AND WITHOUT the
    `time_limit_s` wall-clock budget having been exceeded first — the fail-loud cap that
    refuses to return a non-consensus iterate (RESEARCH Pitfall 2). When `time_limit_s` IS
    exceeded first, this throw is SKIPPED — the honest `status = :budget_exceeded` return
    (see "Wall-clock budget" above) replaces it; that path is not itself a genuine
    non-convergence, so it is not fail-loud.
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
    reactive_consensus = false,
    ρ_q::Real = ρ,
    time_limit_s::Union{Nothing, Real} = nothing,
    atol_exact::Real = 1e-6,
    rtol_exact::Real = 1e-4,
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
    ρ_qf = Float64(ρ_q)
    # MESH-05 (D-12): normalize ONCE, before the loop, alongside ρf — the SINGLE source of truth
    # for OFF/CERTIFIED/LIVE threaded symmetrically into build_dso_opt AND every build_agr_opt
    # call below (mirrors normalize_reactive_mode's own D-12 back-compat: Bool/Symbol/ReactiveMode
    # all accepted). NEVER named bare `μ`/`mu`/`MU` anywhere in this file's NEW reactive-dual-ascent
    # state below — that identifier is PERMANENTLY the adaptive-ρ residual-balancing imbalance band
    # (the `μ::Real = 10.0` kwarg above; test_admm_reactive.jl's grep audit). The reactive coupling
    # multiplier uses the DISTINCT identifier `μq` instead.
    mode = normalize_reactive_mode(reactive_consensus)

    # ---- BUILD ONCE (ADMM-03): the subproblem models are constructed OUTSIDE the loop ----------
    # One AGR-OPT per aggregator (thesis 3.46); the whole-network DSO-OPT (thesis 3.47). No
    # `Model(`/`build_*` call appears below this point — the loop only re-solves via coefficient
    # updates, so num_variables/num_constraints stay fixed (RESEARCH Pattern 3 / Pitfall 6).
    dso = build_dso_opt(
        feeder,
        aggregators,
        T;
        ρ = ρf,
        λ₀ = λ₀,
        reactive_consensus = mode,
        ρ_q = ρ_qf,
    )
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
    agr_by_bus = Dict{Int, AgrOpt}()
    for agg in aggregators
        haskey(agr_by_bus, agg.bus) && throw(
            ArgumentError("two aggregators share bus $(agg.bus); solve_admm assumes 1:1"),
        )
        agr_by_bus[agg.bus] = build_agr_opt(agg, T; ρ = ρf, reactive_mode = mode, ρ_q = ρ_qf)
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
    λ = Dict{Int, Vector{Float64}}(j => Float64[-λ₀[t] for t in 1:T] for j in load_nodes)
    c = Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)   # netflow target for AGR
    a = Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)   # pag target for DSO
    # Boyd z-block dual residual s = ρ·‖Δ(pag_dso)‖₂ tracks the CONSENSUS (second-updated) block —
    # store the previous iterate's pag_dso EXACTLY as Phase 6 stored `a_prev` for its ρ·Δa
    # diagnostic. Initialized to zeros ⇒ iteration 1's s = ρ·‖pag_dso¹‖₂ is large (so a 1-iteration
    # budget cannot false-converge; RESEARCH Pattern 2 / Pitfall 2).
    pag_dso_prev = Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)
    util = Dict{Int, Float64}(j => 0.0 for j in load_nodes)                      # U_ag per node (primal welfare)
    p_import = zeros(Float64, T)                                                # frontier exchange (primal welfare)
    exact_maxgap = nothing

    # ---- LIVE reactive dual-ascent state (MESH-05, D-11) — mirrors the ACTIVE λ/a/c/pag_dso_prev
    # state exactly, on the REACTIVE coupling axis (`qag_dso` ↔ `qag_live`): `μq` is the reactive
    # coupling multiplier (mirrors `λ`), `b` is AGR's solved `qag_live` value (mirrors `a`), `d` is
    # the reactive netflow target for AGR (mirrors `c`), `qag_dso_prev` is the z-block snapshot
    # (mirrors `pag_dso_prev`). Claude's Discretion (per the plan): `μq` warm-starts at ZERO, NOT
    # `-λ₀`-style — unlike the active DADP, the reactive price has no comparable physical anchor to
    # warm-start from. Allocated ONLY under `LIVE`; OFF/CERTIFIED keep these as empty `Dict`s (never
    # indexed — every reactive-block code path below is itself gated on `mode == LIVE`), so no
    # T-length array allocation happens on the byte-identical default path.
    μq = if mode == LIVE
        Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)
    else
        Dict{Int, Vector{Float64}}()
    end
    d = if mode == LIVE
        Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)
    else
        Dict{Int, Vector{Float64}}()
    end
    b = if mode == LIVE
        Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)
    else
        Dict{Int, Vector{Float64}}()
    end
    qag_dso_prev = if mode == LIVE
        Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)
    else
        Dict{Int, Vector{Float64}}()
    end
    ρ_q_frozen = false

    # ---- Adaptive-ρ state (RESEARCH Pattern 4, Boyd §3.4.1). `ρf` is the LIVE penalty/dual-step
    # (initialized to the ρ₀ keyword). `ρ_frozen` latches TRUE once both residuals fall within ~10×
    # tolerance, after which ρ is held fixed (Boyd's convergence theory assumes ρ eventually
    # constant — prevents late-stage oscillation stalling the tail). τ/μ are the residual-balancing
    # multiplier/band; [ρ_min, ρ_max] clamp the penalty (SOCP-conditioning + proximal meaningfulness).
    ρ_frozen = false

    # ---- Wall-clock budget state (Phase 25, D-18). `t0_wall_ns` is the loop-entry timestamp;
    # `budget_exceeded_flag` mirrors `converged_flag`'s latch shape exactly (checked once per
    # iteration, right after the convergence check, right before the dual-ascent update). Both
    # are complete no-ops when `time_limit_s === nothing` (the default) — byte-identical to the
    # pre-existing unbounded behavior.
    t0_wall_ns = time_ns()
    budget_exceeded_flag = false

    converged_flag = false
    for k in 1:maxiter
        # (1) AGR-OPT[j] ∀j: coeff −λ_j − ρ·c_j (thesis 3.46). a_j = solved net injection.
        # `check_battery = false` mid-loop: the App. C complementarity is a property of the
        # correctly-priced CONVERGED optimum, not of an off-consensus iterate where λ_j is still
        # being found (the battery legitimately co-activates at a wrong price) — the same reason
        # the DSO exactness gate is deferred to convergence (RESEARCH Pitfall 3). The gate is run
        # on the final converged re-solve below.
        # UNDER LIVE (MESH-05): thread μq_j/d_j/ρ_q in the SAME call, mid-loop `check_4q = false`
        # (mirroring `check_battery = false`'s existing mid-loop discipline — the 4Q certificate is
        # a property of the correctly-priced CONVERGED optimum, not an off-consensus iterate). Then
        # collect `b_j = value.(qag_live)` (mirrors `a_j = value.(pag)`).
        for j in load_nodes
            r = if mode == LIVE
                solve_agr!(
                    agr_by_bus[j],
                    λ[j],
                    c[j],
                    ρf;
                    μ_j = μq[j],
                    d_j = d[j],
                    ρ_q = ρ_qf,
                    check_battery = false,
                    strict = false,
                )
            else
                solve_agr!(
                    agr_by_bus[j],
                    λ[j],
                    c[j],
                    ρf;
                    check_battery = false,
                    strict = false,
                )
            end
            a[j] = r.pag
            util[j] = r.utility
            if mode == LIVE
                b[j] = value.(agr_by_bus[j].qag_live)
            end
        end

        # (2) DSO-OPT: coeff −λ_j − ρ·a_j (thesis 3.47). Mid-loop iterates are legitimately
        # inexact, so the PF-04 gate is NOT run here (check_exact = false; RESEARCH Pitfall 3),
        # and the mid-loop solve tolerates a NEARLY_FEASIBLE primal (strict = false; the DSO dual
        # is never read — the price is the outer multiplier λ). The final solve below likewise
        # tolerates the benign ALMOST_OPTIMAL label but adds PHYSICAL published-primal certificates
        # (PF-04 exactness + the WR-01 active-balance no-slack gate — see the final block).
        #
        # UNDER LIVE ONLY (MESH-05): `solve_dso!` (plan 19-03's shipped signature — confirmed, not
        # assumed) does NOT accept a μq/b/ρ_q kwarg; `DsoOpt.qag` is a public field, so THIS outer
        # loop drives `qag_dso[j,t]`'s linear objective coefficient directly via
        # `set_objective_coefficient`, mirroring `solve_dso!`'s own internal `pag_dso` update
        # exactly (`-λ[j][t] - ρ*a[j][t]` uses `a` — AGR's OWN solved pag value — NEVER `c`, the
        # AGR-side netflow target; the reactive mirror is therefore `-μq[j][t] - ρ_q*b[j][t]`,
        # using `b` — AGR's OWN solved qag_live value — NEVER `d`, the reactive netflow target fed
        # into `solve_agr!`'s `d_j` instead), BEFORE calling `solve_dso!` so the same solve picks
        # up both coefficient updates.
        if mode == LIVE
            for j in load_nodes, t in 1:T
                set_objective_coefficient(dso.model, dso.qag[j, t], -μq[j][t] - ρ_qf * b[j][t])
            end
        end
        dres = solve_dso!(dso, λ, a, ρf; check_exact = false, strict = false)
        pag_dso = dres.pag_dso
        p_import = dres.p_import
        qag_dso = mode == LIVE ? value.(dso.qag) : nothing

        # (3) BOYD TWO-RESIDUAL diagnostics (RESEARCH Pattern 2 / 3; thesis App. B.30–B.32, the
        # UNSCALED form). PRIMAL residual r = ‖a − pag_dso‖₂ (the 2-norm of the consensus violation,
        # → 0 ⇔ the two blocks agree). DUAL residual s = ρ·‖pag_dso − pag_dso_prev‖₂ (the z-block
        # change — the SECOND-updated consensus block; → 0 ⇔ the price has stopped moving, i.e.
        # optimality). This REPLACES the Phase-6 ρ·Δa x-block diagnostic (the wrong block, a textbook
        # false-convergence bug). Both use the 2-norm over the flattened (j,t) coupling entries so
        # they match the √p·ε_abs per-unit tolerance scaling.
        #
        # MESH-05 EXTENSION: under LIVE, the SAME loop ALSO accumulates the reactive-block
        # `_q`-suffixed quantities (mirroring the active ones on the `qag_dso`/`qag_live` coupling
        # axis) — NEVER a second loop (RESEARCH Code Examples, verbatim structure). Under
        # OFF/CERTIFIED every `_q` accumulator stays 0.0 (untouched), so `r_norm`/`s_norm`/`ε_pri`/
        # `ε_dual` below are ALGEBRAICALLY IDENTICAL to the pre-Phase-19 single-block form —
        # BYTE-IDENTICAL default path.
        sq_r = 0.0        # Σ (a − pag_dso)²        → ‖r_p‖₂
        sq_ds = 0.0       # Σ (Δ pag_dso)²          → ‖s_p‖₂ / ρ
        sq_a = 0.0        # Σ a²                    → ‖a‖₂
        sq_pd = 0.0       # Σ pag_dso²              → ‖pag_dso‖₂
        sq_λ = 0.0        # Σ λ²                    → ‖λ‖₂
        sq_r_q = 0.0      # Σ (b − qag_dso)²        → ‖r_q‖₂ (LIVE only)
        sq_ds_q = 0.0     # Σ (Δ qag_dso)²          → ‖s_q‖₂ / ρ_q (LIVE only)
        sq_b = 0.0        # Σ b²                    → ‖b‖₂ (LIVE only)
        sq_qd = 0.0       # Σ qag_dso²              → ‖qag_dso‖₂ (LIVE only)
        sq_μq = 0.0       # Σ μq²                   → ‖μq‖₂ (LIVE only)
        for j in load_nodes, t in 1:T
            rp = a[j][t] - pag_dso[j, t]
            dz = pag_dso[j, t] - pag_dso_prev[j][t]
            sq_r += rp^2
            sq_ds += dz^2
            sq_a += a[j][t]^2
            sq_pd += pag_dso[j, t]^2
            sq_λ += λ[j][t]^2
            if mode == LIVE
                rq = b[j][t] - qag_dso[j, t]
                dzq = qag_dso[j, t] - qag_dso_prev[j][t]
                sq_r_q += rq^2
                sq_ds_q += dzq^2
                sq_b += b[j][t]^2
                sq_qd += qag_dso[j, t]^2
                sq_μq += μq[j][t]^2
            end
        end

        # ACTIVE-BLOCK-ONLY quantities (mirrors pre-Phase-19 EXACTLY — used for the INDEPENDENT
        # active-ρ adaptation decision below, kept separate from the JOINT stacked stopping-rule
        # quantities so a LIVE reactive block can never contaminate the active block's own
        # freeze/adapt decision).
        r_norm_p = sqrt(sq_r)
        s_norm_p = ρf * sqrt(sq_ds)
        p_p = length(load_nodes) * T
        ε_pri_p = sqrt(p_p) * ε_abs + ε_rel * max(sqrt(sq_a), sqrt(sq_pd))
        ε_dual_p = sqrt(p_p) * ε_abs + ε_rel * sqrt(sq_λ)

        # (4) PER-UNIT stopping thresholds (Boyd §3.3.1 eq. 3.12, RESEARCH Pattern 3), extended to
        # the JOINT (λ,μq) STACKED norm (RESEARCH Code Examples — used verbatim in STRUCTURE; Boyd
        # §3.3's own multi-block caveat / Pitfall 17: a genuinely INDEPENDENT per-block
        # `converged(...)` check is a textbook false-convergence bug on a two-block ADMM). p_p =
        # n_load_nodes·T is the coupling-entry count for ONE block; under LIVE the total doubles
        # (both blocks contribute). The SAME (ε_abs, ε_rel) transfer unchanged across scales
        # (per-unit scale-invariance — the "no hard-coded scale-specific penalty" requirement).
        r_norm = sqrt(sq_r + sq_r_q)
        s_norm = ρf * sqrt(sq_ds) + ρ_qf * sqrt(sq_ds_q)
        p_total = p_p * (mode == LIVE ? 2 : 1)
        ε_pri = sqrt(p_total) * ε_abs + ε_rel * max(sqrt(sq_a + sq_b), sqrt(sq_pd + sq_qd))
        ε_dual = sqrt(p_total) * ε_abs + ε_rel * sqrt(sq_λ + sq_μq)
        # price_gap = ‖Δλ‖₂ of the pending UNSCALED dual step λ ← λ + ρ·r (== ρ·‖r_p‖₂, since
        # Δλ = ρ·r_p): the per-iteration ACTIVE price-convergence trajectory (ADMM-05 plot
        # diagnostic) — kept as the active-only move (identical to pre-Phase-19) even under LIVE, so
        # the existing plot/diagnostic contract is unchanged.
        price_gap = ρf * r_norm_p

        # ONE record!/converged call on the JOINT stacked (r_norm,s_norm,ε_pri,ε_dual) — never two
        # independent per-block checks (T-19-15; grep-enforced at exactly one call site).
        record!(residuals, k, r_norm, s_norm, ρf, ε_pri, ε_dual, price_gap)

        # STOP iff BOTH ‖r‖₂ ≤ ε_pri AND ‖s‖₂ ≤ ε_dual (RESEARCH Pattern 2 / Pitfall 2). A
        # primal-satisfied-but-dual-unsatisfied iterate does NOT stop — the false-convergence net.
        # Under LIVE this is the JOINT (λ,μq) check — genuinely converging BOTH blocks together.
        if converged(residuals, ε_pri, ε_dual)
            converged_flag = true
            break
        end

        # ---- Wall-clock budget check (Phase 25, D-18). Placed AFTER the convergence check
        # (never preempts a genuine consensus on the SAME iteration) and BEFORE the dual-ascent
        # update below (a mid-loop iterate about to be perturbed further is exactly the point at
        # which "budget exceeded, stop here honestly" belongs). A complete no-op when
        # `time_limit_s === nothing` (byte-identical default path).
        if time_limit_s !== nothing && (time_ns() - t0_wall_ns) / 1.0e9 > time_limit_s
            budget_exceeded_flag = true
            break
        end

        # Dual ascent λ_j ← λ_j + ρ·R_{p,j} (UNSCALED — λ is the physical price, NOT rescaled on a ρ
        # change; RESEARCH Pattern 4) and refresh the netflow target c_j = −pag_dso_j (the network
        # injection carries the OPPOSITE sign of the coupling variable — see file header). Snapshot
        # pag_dso into pag_dso_prev for the NEXT iteration's z-block dual residual.
        #
        # MESH-05: the SAME loop ALSO ascends μq (mirrored, ONLY under LIVE): μq_j ← μq_j +
        # ρ_q·(b_j − qag_dso_j), refresh d_j = −qag_dso_j, snapshot qag_dso into qag_dso_prev.
        for j in load_nodes
            for t in 1:T
                pag_dso_prev[j][t] = pag_dso[j, t]
                λ[j][t] += ρf * (a[j][t] - pag_dso[j, t])
                c[j][t] = -pag_dso[j, t]
                if mode == LIVE
                    qag_dso_prev[j][t] = qag_dso[j, t]
                    μq[j][t] += ρ_qf * (b[j][t] - qag_dso[j, t])
                    d[j][t] = -qag_dso[j, t]
                end
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
        #
        # THIS BLOCK NOW OPERATES ON THE ACTIVE-BLOCK-ONLY quantities (r_norm_p/s_norm_p/ε_pri_p/
        # ε_dual_p, renamed from r_norm/s_norm/ε_pri/ε_dual — IDENTICAL VALUES under OFF/CERTIFIED,
        # since sq_r_q etc. are 0.0 there) so LIVE's reactive block can never perturb this decision.
        if !ρ_frozen
            r̂ = r_norm_p / ε_pri_p
            ŝ = s_norm_p / ε_dual_p
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

        # MESH-05: an ANALOGOUS, INDEPENDENT ρ_q adaptation for the REACTIVE block, using the
        # reactive block's OWN r̂_q/ŝ_q (RESEARCH's recommendation — a SHARED ρ would be badly
        # scaled for the typically much-smaller reactive channel; an independent freeze/adapt
        # decision from the active block's own). Mirrors the block above exactly, ONLY under
        # LIVE — a complete no-op (ρ_qf untouched, no set_rho_q! calls) under OFF/CERTIFIED.
        if mode == LIVE && !ρ_q_frozen
            r_norm_q = sqrt(sq_r_q)
            s_norm_q = ρ_qf * sqrt(sq_ds_q)
            ε_pri_q = sqrt(p_p) * ε_abs + ε_rel * max(sqrt(sq_b), sqrt(sq_qd))
            ε_dual_q = sqrt(p_p) * ε_abs + ε_rel * sqrt(sq_μq)
            r̂_q = r_norm_q / ε_pri_q
            ŝ_q = s_norm_q / ε_dual_q
            if r̂_q <= 10 && ŝ_q <= 10
                ρ_q_frozen = true
            else
                ρ_q_new = if r̂_q > μ * ŝ_q
                    τ * ρ_qf
                elseif ŝ_q > μ * r̂_q
                    ρ_qf / τ
                else
                    ρ_qf
                end
                ρ_q_new = clamp(ρ_q_new, ρ_min, ρ_max)
                if ρ_q_new != ρ_qf
                    ρ_qf = ρ_q_new
                    set_rho_q!(dso, ρ_qf)
                    for j in load_nodes
                        set_rho_q!(agr_by_bus[j], ρ_qf)
                    end
                end
            end
        end
    end

    # ---- FAIL LOUD on the maxiter cap (RESEARCH Pitfall 2) — never return a non-consensus point.
    # Phase 25 (D-18): this throw fires ONLY on a genuine non-convergence — i.e. NEITHER converged
    # NOR an honest wall-clock budget exit. An expired `time_limit_s` is NOT itself a
    # non-convergence bug; it gets its OWN honest early return (`status = :budget_exceeded`)
    # below instead of this loud throw.
    if !converged_flag && !budget_exceeded_flag
        throw(
            ErrorException(
                "solve_admm FAILED to converge: hit maxiter=$maxiter without BOTH the primal residual " *
                "‖r‖ ≤ ε_pri AND the dual residual ‖s‖ ≤ ε_dual (last ‖r‖ = $(last(residuals.primal_trace)) " *
                "vs ε_pri = $(last(residuals.eps_pri_trace)); last ‖s‖ = $(last(residuals.dual_trace)) vs " *
                "ε_dual = $(last(residuals.eps_dual_trace)); ρ=$ρf). Retune the adaptive-ρ config " *
                "(ε_abs/ε_rel/τ/μ/ρ_min/ρ_max) or raise maxiter — the last iterate is NOT a consensus " *
                "optimum and is refused (thesis §2.6; RESEARCH Pitfall 2).",
            ),
        )
    elseif budget_exceeded_flag
        # ---- HONEST early exit on the wall-clock budget (Phase 25, D-18). SKIPS the final
        # consolidation pass below — it assumes a converged iterate and runs the battery/4Q/
        # exactness certificates, which are meaningless on a mid-loop, non-consensus point.
        # `welfare`/`dadp`/`λ`/`exact_maxgap`/`mu_q` are `nothing` BY DESIGN: a `:budget_exceeded`
        # result never carries a plausible-but-uncertified price — a caller cannot silently
        # mistake this mid-loop iterate for a certified DADP.
        return (;
            welfare = nothing,
            dadp = nothing,
            λ = nothing,
            iters = residuals.iters,
            residuals = residuals,
            dso_ctx = dso.ctx,
            exact_maxgap = nothing,
            mu_q = nothing,
            q_devices = Dict{Int, Vector{Float64}}(),
            status = :budget_exceeded,
        )
    end

    # ---- Converged: FINAL consolidation pass running BOTH PHYSICAL gates (RESEARCH Pitfall 3 /
    # Pattern 5). The coupling (λ, c, a) is unchanged from the converged iterate, so these re-solves
    # reproduce the converged primal and only ADD the certificates:
    #   • AGR-OPT[j] with check_battery = true: the App. C complementarity gate at the correctly-
    #     priced optimum, with the interior-point τ_batt = 1e-3 (Clarabel is an IPM that
    #     co-activates the optimal face, matching the SOCP-path τ in `solve_welfare`; the QP-tight
    #     1e-6 under-tolerances the converged point at IEEE-13 scale).
    #   • the 4Q certificate (check_4q, below) runs with the SAME interior-point loosening
    #     discipline as τ_batt: rtol_4q = 1e-3 / atol_4q = 1e-7 instead of the certificate's
    #     tight centralized-path defaults (1e-4 / 1e-8). MEASURED (CR-01 follow-up, 2026-08-08):
    #     at THIS consolidation re-solve — converged prices, ρ-penalty in the objective,
    #     strict = false — the IEEE-13 4Q fixture's p_ch·p_dch lands DETERMINISTICALLY at
    #     ≈1.41e-8 (scale = 0.0025, i.e. rel ≈2.3e-3·scale²), an order above the centralized
    #     noise floor the tight defaults are sized for, for exactly the reason τ_batt is 1e-3
    #     here and not 1e-6: the IPM co-activates the optimal face harder under the penalty.
    #     The loosened pair clears that measurement with ≈7.5× margin (tol ≈ 1.06e-7 at the
    #     0.0025 scale) while still flagging simultaneous legs above ~13% (IEEE-13) / ~3.5%
    #     (2-bus) of the device rating — versus the ~40% escape CR-01 fixed.
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
    #
    # MESH-05 (Task 2, D-11): whether the aggregator at each load node carries an ACTUAL
    # `FourQuadBESS` device — the correct `check_4q` discriminator. NOT
    # `agr_by_bus[j].qag_live !== nothing`: plan 19-06 ties `qag_live` to `mode == LIVE` ALONE
    # (declared for EVERY aggregator under LIVE, regardless of device composition — re-derived
    # against 19-06's actual shipped semantics, per this plan's own warning against assuming
    # `qag_live !== nothing` is sufficient). INDEPENDENT of `mode`: the App. C-style
    # `p_ch·p_dch ≈ 0` property is a property of the DEVICE's own charge/discharge behavior,
    # checkable whenever a `FourQuadBESS` is present, whether or not its reactive coupling is
    # pinned (`CERTIFIED`) or genuinely live (`LIVE`).
    has_4q_by_bus = Dict{Int, Bool}(
        agg.bus => any(dv -> dv isa FourQuadBESS, agg.devices) for agg in aggregators
    )
    for j in load_nodes
        r = if mode == LIVE
            solve_agr!(
                agr_by_bus[j],
                λ[j],
                c[j],
                ρf;
                μ_j = μq[j],
                d_j = d[j],
                ρ_q = ρ_qf,
                check_battery = true,
                τ_batt = 1e-3,
                strict = false,
                check_4q = has_4q_by_bus[j],
                rtol_4q = 1e-3,
                atol_4q = 1e-7,
            )
        else
            solve_agr!(
                agr_by_bus[j],
                λ[j],
                c[j],
                ρf;
                check_battery = true,
                τ_batt = 1e-3,
                strict = false,
                check_4q = has_4q_by_bus[j],
                rtol_4q = 1e-3,
                atol_4q = 1e-7,
            )
        end
        a[j] = r.pag
        util[j] = r.utility
    end
    # UNDER LIVE ONLY (MESH-05): re-assert `qag_dso`'s linear coefficient one final time (mirrors
    # the mid-loop discipline exactly, `-μq[j][t] - ρ_q*b[j][t]` — `b`, NEVER `d`, see the
    # mid-loop comment above) BEFORE the final `solve_dso!` — a no-op numerically (μq/b are
    # unchanged since the last mid-loop iteration) but keeps this final solve's coefficient state
    # explicit/self-contained, mirroring how λ[j]/c[j] are also explicitly re-passed above.
    if mode == LIVE
        for j in load_nodes, t in 1:T
            set_objective_coefficient(dso.model, dso.qag[j, t], -μq[j][t] - ρ_qf * b[j][t])
        end
    end
    dres_final = solve_dso!(
        dso,
        λ,
        a,
        ρf;
        check_exact = true,
        strict = false,
        atol_exact = atol_exact,
        rtol_exact = rtol_exact,
    )
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

    # REACT-02 (Phase 16): `:balance_q` is now ALSO certified, but ONLY when `mode != OFF`
    # (`CERTIFIED` or `LIVE`) — the reactive draw at each load node is then a genuine coupling
    # variable `qag_dso[j,t]` (not a hand-summed constant; PINNED under `CERTIFIED`, genuinely
    # dual-ascended under `LIVE`), so its dual becomes a PUBLISHABLE reactive price component and
    # deserves the SAME no-slack certificate as `:balance_p`, mirrored exactly. At the DEFAULT
    # `mode == OFF`, `:balance_q` remains the INELASTIC constant closure described above —
    # intentionally NOT gated, NOT published/load-bearing, UNCHANGED from pre-Phase-16 behavior
    # (REACT-03 non-regression). MESH-05: checked against the NORMALIZED `mode`, never the raw
    # `reactive_consensus` argument directly — `reactive_consensus` is no longer typed `Bool` (it
    # now also accepts `Symbol`/`ReactiveMode`), so a bare `if reactive_consensus` would throw a
    # `MethodError` (Julia requires an `if` condition to be a genuine `Bool`) whenever a caller
    # passes `:live`/`:certified`/`LIVE`/`CERTIFIED` instead of a `Bool` — this is a REQUIRED fix
    # (Rule 1/3), not new scope.
    if mode != OFF
        let balance_q = dso.ctx.constraints[:balance_q]
            for j in 1:size(balance_q, 1), t in 1:size(balance_q, 2)
                assert_no_slack(dso.model, balance_q[j, t]; atol = 1e-6)
            end
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

    # ---- MESH-05 (D-11): mu_q / q_devices as FIRST-CLASS PEERS of λ/dadp under LIVE. Stable
    # return-tuple SHAPE (Claude's Discretion, per the plan's "pick ONE approach" instruction):
    # the KEYS `mu_q`/`q_devices` are ALWAYS present, `nothing` under OFF/CERTIFIED — mirrors this
    # file's own existing convention for `exact_maxgap` (always a key, `nothing` until a
    # `check_exact = true` solve stashes a value). This is documented here, not a partial/optional
    # NamedTuple shape. The key is the audit-reserved `mu_q`, never bare `μ` (WR-03: bare `μ`
    # would make one identifier mean BOTH the adaptive-ρ band kwarg and the reactive price in
    # one public signature, and would collide with `Scenario.jl`'s serialized `μ::Float64` band
    # field if the reactive price is ever threaded into the DrWatson `savename` schema).
    mu_q_mat = nothing
    q_devices = nothing
    if mode == LIVE
        # SIGN CONVENTION (Task 1's empirical finding, mirroring the λ/dual(:balance_p) derivation
        # above VERBATIM with P↔Q substituted): the internal `μq[j]` converges to the NEGATED
        # `dual(:balance_q[j])` — verified on a 2-bus + `FourQuadBESS` fixture with REAL (non-
        # near-lossless) impedance, where the internal `μq` and `dual(:balance_q)` land with
        # OPPOSITE signs at consensus (the SAME relationship `λ` already has to
        # `dual(:balance_p)`), consistent with the P↔Q structural symmetry of the SINGLE augmented
        # Lagrangian this file's header comment derives `λ`'s sign from (the reactive block is
        # built by the identical AGR-fixes-target / DSO-renames-coupling-variable construction,
        # merely on the `Rq`/`qag_dso` axis instead of `Rp`/`pag_dso`). SAME `reduce(vcat,
        # permutedims(...))` idiom, SAME ascending-bus order as `λ_mat`.
        #
        # D-03 DEGENERACY NOTE: on a near-lossless/uncongested reactive channel the nodal reactive
        # dual μ can converge to ≈0 (no genuine reactive network cost to price) — this is an
        # HONEST feature of the model, not a bug: cross-validation against the centralized solve
        # (below/at the call site) compares welfare, λ, AND μ, but NEVER a `FourQuadBESS`'s
        # individual `q` trajectory, since a near-zero μ makes that device's own P-Q split
        # non-unique/degenerate (many `(p,q)` splits inside the apparent-power cone are equally
        # optimal at a ≈0 reactive price) — pinning a non-unique quantity would be meaningless.
        mu_q_mat = reduce(vcat, (permutedims(-μq[j]) for j in load_nodes))

        # Extract each `FourQuadBESS`'s converged `q[t]` trajectory from
        # `ctx.meta[:agg_device_vars]` (the SAME stash `assert_4q_complementarity!` iterates),
        # selected by the SAME `:p_ch`/`:p_dch`/`:q` triple the certificate uses — mirrors its own
        # selection condition exactly, never a looser/different check.
        q_devices = Dict{Int, Vector{Float64}}()
        for j in load_nodes
            for v in agr_by_bus[j].ctx.meta[:agg_device_vars][j]
                if haskey(v, :p_ch) && haskey(v, :p_dch) && haskey(v, :q)
                    q_devices[j] = Float64[value(v.q[t]) for t in 1:T]
                end
            end
        end
    end

    return (;
        welfare = welfare,
        dadp = λ_mat,
        λ = λ_mat,
        iters = residuals.iters,
        residuals = residuals,
        dso_ctx = dso.ctx,
        exact_maxgap = exact_maxgap,
        mu_q = mu_q_mat,
        q_devices = q_devices,
        status = :converged,
    )
end

export solve_admm

# src/admm/AgrOpt.jl
#
# SEAM: AGR-OPT — the per-node aggregator/device ADMM subproblem (ADMM-01).
# OWNER: plan 06-02 (Wave 2). Declares its own `export`s per the include-graph convention.
#
# Block 1 of the 2-block ADMM split (RESEARCH Pattern 1/4, thesis eq. 3.46): a thin
# per-aggregator QP that REUSES the existing device / `Aggregator.contribute!` builders
# VERBATIM — ADMM is orchestration, NOT a model re-implementation. Derived from the single
# augmented Lagrangian of the centralized GLB-CVX (fixing the network side `netflow_j = c_j`):
#
#       max_{device vars}  U_ag,j(devices)                            (thesis 3.21)
#                          − Σ_t λ_j[t]·pag_j[t]                      (linear price term)
#                          − (ρ/2) Σ_t ( c_j[t] + pag_j[t] )²        (quadratic ρ-penalty)
#         s.t.  pag_j[t] == Σ_d p_inject_d[t] − Pdc[t]               (coupling var, thesis 3.22)
#               qag_j[t]  =  −Pdc[t]·tan(arccos φ)                   (thesis 3.23, constant)
#               device constraints (thesis 3.2–3.9, via contribute!)
#
# BUILD-ONCE / RE-SOLVE (ADMM-03, RESEARCH Pattern 3): the model is built ONCE. The quadratic
# self-penalty coefficient (−ρ/2 on pag_j²) is FIXED; expanding −(ρ/2)(pag+c)² shows the only
# per-iteration change is the LINEAR coefficient on pag_j[t], which absorbs BOTH the price and
# the shifted penalty target: coeff = −λ_j[t] − ρ·c_j[t]. Each ADMM iteration mutates only that
# scalar via `set_objective_coefficient(model, pag_j[t], −λ_j[t] − ρ·c_j[t])` (one call per
# hour) — NO JuMP rebuild. λ_j is a plain `Float64`, NEVER a JuMP `Parameter` (a `λ·pag`
# Parameter×variable term is an indefinite bilinear the convex conic backend rejects — RESEARCH
# Pitfall 1). Solver via `select_optimizer(QP())` (INFRA-02, never names a concrete solver); solves are
# gated on `assert_solved!(...; dual=true)` (INFRA-03); the App. C battery-complementarity check
# (`assert_battery_complementarity!`) runs after each solve — the batteries live in AGR-OPT now.

using JuMP

"""
    AgrOpt

The per-node AGR-OPT ADMM subproblem (thesis eq. 3.46) — block 1 of the 2-block split. A
BUILD-ONCE JuMP QP wrapping one [`Aggregator`](@ref)'s device roll-up, re-solved each ADMM
iteration by a single `set_objective_coefficient` update on the coupling variable (ADMM-03).

# Fields

  - `model::Model` — the JuMP QP (backend chosen by `select_optimizer(QP())`), built ONCE.
  - `ctx::ModelContext` — the model context the aggregator/device `contribute!` wrote into; its
    `ctx.meta[:objective]` holds the aggregator utility `U_ag` (a `QuadExpr`) and
    `ctx.meta[:agg_device_vars]` the battery vars for the App. C complementarity check.
  - `pag::Vector{VariableRef}` — the coupling variable `pag_j[t]` (net active injection), pinned
    to `Σ_d p_inject_d[t] − Pdc[t]` (thesis 3.22). Its linear objective coefficient is the
    per-iteration ADMM handle.
  - `qag::Vector{Float64}` — the CONSTANT net reactive injection `−Pdc[t]·tan(arccos φ)` (thesis
    3.23; DERs are active-only, A3). Kept UNCONDITIONALLY, in every `reactive_mode`, as the fixed
    inelastic-demand component of the aggregator's total reactive injection. Under Phase 19 LIVE
    mode (MESH-05) the genuine, live consensus quantity lives in the new `qag_live` field below —
    this field itself is NEVER a live consensus variable; it is NOT read by `solve_admm` (IN-02)
    outside of composing `qag_live`'s pinning target.
  - `qag_live::Union{Nothing,Vector{VariableRef}}` — the LIVE reactive coupling variable
    `qag_live[t]` (MESH-05), mirroring `pag`'s coupling shape exactly: `nothing` under `OFF`/
    `CERTIFIED` (no live reactive coupling block exists, byte-identical to pre-Phase-19), or a
    genuine `Vector{VariableRef}` of length `T` under `LIVE`, PINNED via an equality constraint to
    the aggregator's total reactive injection `qag[t] + res.q_inject[t]` and carrying its own
    `ρ_q`-scaled quadratic objective penalty. Its linear objective coefficient is the per-iteration
    `μ`-dual-ascent handle for [`solve_agr!`](@ref), exactly as `pag`'s is for `λ`.
  - `T::Int` — the day-ahead horizon.
  - `bus::Int` — the aggregator's distribution bus.
  - `ρ::Float64` — the INITIAL penalty ρ₀ captured at build time. NOTE (IN-01): the LIVE penalty
    under adaptive ρ lives ONLY in the model's quadratic objective coefficients (mutated by
    [`set_rho!`](@ref)); this immutable field is NEVER updated, so after the first ρ adaptation it
    holds ρ₀, not the current penalty. Do not read it as "the current ρ". Currently unused elsewhere.
"""
struct AgrOpt
    model::Model
    ctx::ModelContext
    pag::Vector{VariableRef}
    qag::Vector{Float64}
    qag_live::Union{Nothing, Vector{VariableRef}}
    T::Int
    bus::Int
    ρ::Float64
end

"""
    build_agr_opt(agg::Aggregator, T::Int; ρ::Real, reactive_mode = false, ρ_q::Real = ρ) -> AgrOpt

Build the AGR-OPT per-node subproblem for aggregator `agg` over horizon `T` (thesis eq. 3.46),
ONCE, following RESEARCH Pattern 4 (option a — reuse `Aggregator.contribute!` verbatim):

 1. `model = Model(select_optimizer(QP()))`; `ctx = ModelContext(model)`; stash `T` (INFRA-02).
 2. Reuse the aggregator roll-up: `res = contribute!(agg, ctx; T)` drives each device once and
    sums their `p_inject` / `utility` (thesis 3.21–3.22) and, since plan 19-04, its total device
    reactive injection `res.q_inject` (`zero(AffExpr)` per `t` when no member device carries an
    optional `q_inject`, MESH-04 D-09). It also writes `:Rp`/`:Rq` and stashes the battery vars —
    the stray residual writes are HARMLESS here (AGR-OPT never closes them), and the battery
    stash is exactly what the App. C check consumes post-solve.
 3. Create the coupling variable `pag[t]` and pin it to the net active injection
    `pag[t] == res.p_inject[t] − agg.Pdc[t]` (thesis 3.22).
 4. Expose the CONSTANT reactive injection `qag[t] = −Pdc[t]·tan(arccos φ)` (thesis 3.23) for the
    μ update — computed UNCONDITIONALLY, in every `reactive_mode` (never gated), since it is
    also the fixed component `qag_live` pins to under `LIVE`.
 5. `reactive_mode` (MESH-05, mirrors [`build_dso_opt`](@ref)'s `reactive_consensus`): normalized
    via [`normalize_reactive_mode`](@ref), accepting a `Bool` (back-compat: `false → OFF`,
    `true → CERTIFIED`), a `Symbol` (`:off`/`:certified`/`:live`), or a [`ReactiveMode`](@ref)
    directly.
      + `OFF`/`CERTIFIED` (default): BYTE-IDENTICAL to pre-Phase-19 — no `qag_live` variable is
        declared, `agr.qag_live === nothing`, the objective is unchanged.
      + `LIVE` (NEW — MESH-05): a genuine coupling variable `qag_live[t]` is declared and PINNED,
        mirroring `pag`'s `coupling` constraint exactly, to the aggregator's TOTAL reactive
        injection `qag[t] + res.q_inject[t]` (the same quantity `Aggregator.contribute!` writes
        into `:Rq` — thesis 3.23 plus the D-10 additive device term). It carries its own
        `ρ_q`-scaled quadratic penalty in the objective, folded into the SAME accumulator as
        `pag`'s penalty before the single `@objective` call (so `OFF`/`CERTIFIED` never construct
        or touch it).
 6. Set `@objective(model, Max, U_ag − (ρ/2)·Σ_t pag[t]² [− (ρ_q/2)·Σ_t qag_live[t]² under LIVE])`
    — the FIXED quadratic ρ-penalty part(s), built ONCE. The linear price+penalty-shift
    coefficient on `pag[t]` (and, under `LIVE`, `qag_live[t]`) starts at zero and is updated per
    iteration by [`solve_agr!`](@ref) via `set_objective_coefficient` (never a JuMP `Parameter`
    for the price — RESEARCH Pitfall 1).

`ρ_q::Real = ρ` (MESH-05): the FIXED quadratic penalty weight for the `LIVE` reactive coupling
block, mirroring `ρ`'s role for the active `pag` block and [`build_dso_opt`](@ref)'s `ρ_q`
default. Unused (never referenced) under `OFF`/`CERTIFIED`.

Returns an [`AgrOpt`](@ref). No concrete solver is named (INFRA-02); the model is well-posed and
solves OPTIMAL at the default zero price.
"""
function build_agr_opt(
    agg::Aggregator,
    T::Int;
    ρ::Real,
    reactive_mode = false,
    ρ_q::Real = ρ,
)
    mode = normalize_reactive_mode(reactive_mode)

    # (1) One QP model per node, chosen by problem class only (INFRA-02 — never names a solver).
    model = Model(select_optimizer(QP()))
    ctx = ModelContext(model)
    ctx.meta[:T] = T

    # (2) Reuse the aggregator/device builders VERBATIM (RESEARCH Pattern 4, option a). This
    # populates ctx.meta[:objective] (U_ag, a QuadExpr) and ctx.meta[:agg_device_vars] (the
    # battery vars for the App. C check). Its :Rp/:Rq writes are never closed here (harmless).
    # `res.q_inject` (plan 19-04) is the summed OPTIONAL device reactive injection, zero when no
    # member device carries it — the LIVE branch below adds it to `qag` for the pinning target.
    res = contribute!(agg, ctx; T = T)

    # (3) Coupling variable pag_j[t] pinned to the net active injection (thesis 3.22).
    @variable(model, pag[1:T])
    @constraint(model, coupling[t = 1:T], pag[t] == res.p_inject[t] - agg.Pdc[t])
    register_constraint!(ctx, :agr_coupling, coupling)

    # (4) Constant net reactive injection (thesis 3.23; DERs active-only, A3), UNCONDITIONAL and
    # UNCHANGED across every reactive_mode — also the fixed component of the LIVE pinning target.
    tanφ = reactive_factor(agg.φ)               # tan(arccos φ) (thesis 3.23), single-sourced (IN-01)
    qag = Float64[-agg.Pdc[t] * tanφ for t in 1:T]

    # (5)/(6) Objective accumulator: aggregator utility − FIXED (ρ/2)·Σ pag² penalty, built ONCE.
    # Under LIVE ONLY, declare + pin qag_live and fold its (ρ_q/2)·Σ qag_live² penalty into the
    # SAME accumulator BEFORE the single @objective call — OFF/CERTIFIED never construct or touch
    # it (byte-identical built objective under those two modes).
    obj_expr = ctx.meta[:objective] - 0.5 * ρ * sum(pag[t]^2 for t in 1:T)
    qag_live = nothing
    if mode == LIVE
        # NEW (MESH-05): qag_live[t] genuinely PINNED to the aggregator's TOTAL reactive
        # injection, mirroring pag's coupling constraint exactly. `qag[t] + res.q_inject[t]` is
        # precisely the expression Aggregator.contribute! writes into :Rq (thesis 3.23 + D-10).
        @variable(model, qag_live_var[1:T])
        @constraint(
            model,
            qag_coupling[t = 1:T],
            qag_live_var[t] == qag[t] + res.q_inject[t]
        )
        register_constraint!(ctx, :agr_qag_coupling, qag_coupling)
        obj_expr -= 0.5 * ρ_q * sum(qag_live_var[t]^2 for t in 1:T)
        qag_live = collect(qag_live_var)
    end
    @objective(model, Max, obj_expr)

    return AgrOpt(model, ctx, collect(pag), qag, qag_live, T, agg.bus, Float64(ρ))
end

"""
    solve_agr!(agr::AgrOpt, λ_j::AbstractVector, c_j::AbstractVector, ρ::Real;
               μ_j::Union{Nothing,AbstractVector} = nothing,
               d_j::Union{Nothing,AbstractVector} = nothing,
               ρ_q::Union{Nothing,Real} = nothing,
               check_battery::Bool = true, τ_batt::Real = 1e-6, strict::Bool = true,
               check_4q::Bool = false, rtol_4q::Real = 1e-4, atol_4q::Real = 1e-8)
        -> (; pag::Vector{Float64}, utility::Float64)

Re-solve the AGR-OPT subproblem for one ADMM iteration (RESEARCH Pattern 3, thesis 3.46)
WITHOUT rebuilding the JuMP model (ADMM-03). For each hour `t` it updates ONLY the linear
objective coefficient of the coupling variable `pag_j[t]` to `−λ_j[t] − ρ·c_j[t]` — the price
plus the shifted-penalty term (expanding `−(ρ/2)(pag+c)²` leaves `−ρ·c` on the linear part; the
FIXED `−ρ/2` quadratic self-term built by [`build_agr_opt`](@ref) is untouched). `λ_j` is a
plain `Float64` vector, NEVER a JuMP `Parameter` (a `λ·pag` Parameter×variable term is an
indefinite bilinear the convex conic backend rejects — RESEARCH Pitfall 1).

`μ_j`/`d_j`/`ρ_q` (MESH-05, NEW — the reactive analogs of `λ_j`/`c_j`/`ρ`): when `μ_j !== nothing`, in the SAME loop as the `pag[t]` update, `qag_live[t]`'s linear objective coefficient
is set to `−μ_j[t] − ρ_q·d_j[t]`, mirroring the active-power update exactly. `agr.qag_live === nothing` (an `OFF`/`CERTIFIED`-built `AgrOpt`) while `μ_j !== nothing` is a CALLER ERROR — it
throws `ArgumentError` rather than silently no-op-ing (which could mask a caller forgetting to
build with `reactive_mode = :live`). `μ_j`/`d_j` are length-guarded against `agr.T` exactly like
`λ_j`/`c_j`. When `μ_j === nothing` (the default), the `qag_live` coefficient is left untouched —
every existing call site's behavior is preserved verbatim.

After the coefficient update(s) it:

  - gates the solve on [`assert_solved!`](@ref)`(...; dual = true)` (INFRA-03) before reading any
    value;
  - runs the App. C battery-complementarity check
    [`assert_battery_complementarity!`](@ref)`(agr.ctx; τ = τ_batt, T = agr.T)` — the batteries live
    in AGR-OPT now, so a degenerate simultaneous charge/discharge is caught here (threat T-06-10);
    and
  - (NEW, MESH-04/MESH-05) when `check_4q = true`, in the SAME post-solve block, runs
    [`assert_4q_complementarity!`](@ref)`(agr.ctx; rtol = rtol_4q, atol = atol_4q, T = agr.T)` —
    the 4Q-BESS peer certificate (plan 19-05). The `rtol_4q`/`atol_4q` DEFAULTS mirror the
    certificate's own measured centralized-path defaults; `solve_admm`'s FINAL consolidation
    passes the interior-point-loosened `rtol_4q = 1e-3, atol_4q = 1e-7` instead (the exact
    `τ_batt = 1e-3` discipline — see the τ_batt paragraph below and `solve_admm`'s
    consolidation comment for the measurement).

`check_battery` / `τ_batt` — the App. C complementarity is a property of the CORRECTLY-PRICED
optimum, NOT of an arbitrary intermediate ADMM iterate. Mid-loop the coupling price `λ_j` is
still being found, so the battery legitimately co-activates at an off-consensus price — exactly
as the SOC relaxation is legitimately inexact mid-loop (RESEARCH Pitfall 3, why `solve_dso!`
gates its exactness check behind `check_exact`). `solve_admm` therefore passes
`check_battery = false` on the mid-loop re-solves and `check_battery = true` on the FINAL,
converged re-solve — where it also uses the interior-point `τ_batt` (Clarabel is an IPM that
co-activates the optimal face more, so the QP-tight `1e-6` under-tolerances the converged point
at scale; `1e-3` matches the `problem_class`-aware SOCP-path τ in `solve_welfare`). Default
`(check_battery = true, τ_batt = 1e-6)` preserves the plan-06-02 standalone behavior. `check_4q`
follows the SAME convergence-only discipline (mid-loop iterates are legitimately off-consensus).

`strict` — the [`assert_solved!`](@ref) mode (mirrors [`solve_dso!`](@ref)). `strict = true` (the
default, and ALWAYS used on the final/converged re-solve) requires a fully OPTIMAL, dual-feasible
point via `assert_solved!(agr.model; dual = true)`. `strict = false` is the MID-LOOP mode: the
AGR-OPT subproblem's DUALS are never the priced quantity (the transactive price is the outer
multiplier `λ`, not an AGR dual), so an `ALMOST_OPTIMAL` / `NEARLY_FEASIBLE` primal — the backend
stopping just shy of its centralized-grade gap under the ρ-penalty — is acceptable at an
intermediate iterate (the residual loop self-corrects; RESEARCH Pitfall 2/4). `solve_admm` passes
`strict = false` on every mid-loop re-solve and keeps the default `strict = true` on the final one.

Returns `(; pag = value.(agr.pag), utility = value(agr.ctx.meta[:objective]))`: the solved net
active injection over the horizon and the aggregator utility `U_ag` value (the un-penalized
welfare term the ADMM loop recombines for reporting). Throws `ArgumentError` on a `λ_j`/`c_j` or
`μ_j`/`d_j` length mismatch — the boundary guard against a silently-wrong coefficient update.
"""
function solve_agr!(
    agr::AgrOpt,
    λ_j::AbstractVector,
    c_j::AbstractVector,
    ρ::Real;
    μ_j::Union{Nothing, AbstractVector} = nothing,
    d_j::Union{Nothing, AbstractVector} = nothing,
    ρ_q::Union{Nothing, Real} = nothing,
    check_battery::Bool = true,
    τ_batt::Real = 1e-6,
    strict::Bool = true,
    check_4q::Bool = false,
    rtol_4q::Real = 1e-4,
    atol_4q::Real = 1e-8,
)
    length(λ_j) == agr.T || throw(
        ArgumentError("solve_agr!: λ_j has length $(length(λ_j)), expected T=$(agr.T)"),
    )
    length(c_j) == agr.T || throw(
        ArgumentError("solve_agr!: c_j has length $(length(c_j)), expected T=$(agr.T)"),
    )

    # NEW (MESH-05): μ_j supplied but this AgrOpt has no live reactive coupling block ⇒ a caller
    # error (fail loud — never a silent no-op that could mask a caller forgetting to build with
    # reactive_mode = :live).
    if μ_j !== nothing
        agr.qag_live !== nothing || throw(
            ArgumentError(
                "solve_agr!: μ_j supplied but this AgrOpt was built without " *
                "reactive_mode=:live",
            ),
        )
        length(μ_j) == agr.T || throw(
            ArgumentError("solve_agr!: μ_j has length $(length(μ_j)), expected T=$(agr.T)"),
        )
        d_j === nothing && throw(ArgumentError("solve_agr!: μ_j supplied without d_j"))
        length(d_j) == agr.T || throw(
            ArgumentError("solve_agr!: d_j has length $(length(d_j)), expected T=$(agr.T)"),
        )
        ρ_q === nothing && throw(ArgumentError("solve_agr!: μ_j supplied without ρ_q"))
    end

    # Build-once re-solve (ADMM-03): one scalar coefficient update per hour — no JuMP rebuild.
    # The qag_live update (when μ_j !== nothing) lives in the SAME loop as pag's, mirroring the
    # active-power update exactly — never a second loop.
    for t in 1:agr.T
        set_objective_coefficient(agr.model, agr.pag[t], -λ_j[t] - ρ * c_j[t])
        if μ_j !== nothing
            set_objective_coefficient(agr.model, agr.qag_live[t], -μ_j[t] - ρ_q * d_j[t])
        end
    end

    # INFRA-03 gate before any value()/dual() read. `strict = true` (default, and always on the
    # final/converged solve) requires a fully OPTIMAL point; `strict = false` is the MID-LOOP mode
    # (the AGR dual is not the priced quantity, so an ALMOST_OPTIMAL / NEARLY_FEASIBLE primal at an
    # intermediate iterate is acceptable — the residual loop self-corrects; RESEARCH Pitfall 2/4).
    if strict
        assert_solved!(agr.model; dual = true)
    else
        assert_solved!(agr.model; dual = false, allow_almost = true)
    end

    # App. C battery complementarity — CONVERGENCE-ONLY under ADMM (see docstring): mid-loop
    # iterates are legitimately off-consensus, so `solve_admm` gates this behind check_battery.
    if check_battery
        assert_battery_complementarity!(agr.ctx; τ = τ_batt, T = agr.T)
    end

    # NEW (MESH-04/MESH-05): the 4Q-BESS peer certificate, SAME post-solve block, SAME
    # convergence-only discipline as check_battery — gated behind check_4q so mid-loop,
    # off-consensus iterates never spuriously throw.
    if check_4q
        assert_4q_complementarity!(agr.ctx; rtol = rtol_4q, atol = atol_4q, T = agr.T)
    end

    return (; pag = value.(agr.pag), utility = value(agr.ctx.meta[:objective]))
end

"""
    set_rho!(agr::AgrOpt, ρ::Real) -> AgrOpt

Mutate the FIXED quadratic penalty weight of the built-ONCE AGR-OPT in place when the adaptive-ρ
loop (07-04) changes ρ — WITHOUT rebuilding the JuMP model (ADMM-04 build-once preserved,
RESEARCH Pattern 1). AGR-OPT is `Max U_ag − (ρ/2)·Σ_t pag[t]²`, so the diagonal quadratic
coefficient of every `pag[t]²` is `−0.5ρ`. One BATCH call sets them all:

    set_objective_coefficient(agr.model, agr.pag, agr.pag, fill(-0.5ρ, agr.T))

The 4-arg (quadratic) `set_objective_coefficient(model, x, x, c)` sets the coefficient of `x²`
to `c` directly (JuMP 1.30.1 absorbs the MOI `0.5·xᵀQx` canonicalization — VERIFIED, RESEARCH
Pattern 1 / objective.jl:629,712). The mutation is stored in the `CachingOptimizer` and re-applied
on the next `optimize!`, identical mechanism to the LINEAR `set_objective_coefficient` update
[`solve_agr!`](@ref) already runs each iteration — so `num_variables`/`num_constraints` are
INVARIANT (no rebuild) and a mutate-then-solve is EQUIVALENT to a fresh build at the new ρ.

CONTRACT for the caller (07-04): call `set_rho!` ONLY on iterations where ρ actually changed
(guard `ρ_new != ρ_old`), and in LOCKSTEP with the linear coefficient update — the linear term
`−λ_j[t] − ρ·c_j[t]` carries the SAME ρ (Pitfall 1: the penalty ρ and the ascent ρ must not
diverge). Never model ρ (or λ) as a JuMP `Parameter`. Keep ρ strictly POSITIVE (convexity guard,
Pitfall 6: ρ > 0 ⇒ AGR stays concave-Max); the adaptive policy clamps ρ ∈ `[ρ_min, ρ_max]`.
Returns `agr`.
"""
function set_rho!(agr::AgrOpt, ρ::Real)
    # Diagonal quadratic coeff of every pag[t]² set to −0.5ρ (Max objective, penalty subtracted).
    # BATCH form — one MOI modification list for all T hours; no rebuild (RESEARCH Pattern 1).
    set_objective_coefficient(agr.model, agr.pag, agr.pag, fill(-0.5 * ρ, agr.T))
    return agr
end

"""
    set_rho_q!(agr::AgrOpt, ρ_q::Real) -> AgrOpt

Mutate the FIXED quadratic penalty weight of the built-ONCE LIVE reactive coupling block in
place — the exact [`set_rho!`](@ref) PEER for the `qag_live` block (MESH-05, mirroring
[`DsoOpt`](@ref)'s [`set_rho_q!`](@ref) at AGR-OPT scale; plan 19-07's outer μ-dual-ascent loop
adapts `ρ_q` independently of `ρ`). AGR-OPT under `LIVE` carries an ADDITIONAL
`Max ... − (ρ_q/2)·Σ_t qag_live[t]²` term (see [`build_agr_opt`](@ref)'s objective assembly), so
the diagonal quadratic coefficient of every `qag_live[t]²` is `−0.5ρ_q`. One BATCH call sets them
all, mirroring `set_rho!`'s exact flatten-then-one-call shape:

    set_objective_coefficient(agr.model, agr.qag_live, agr.qag_live, fill(-0.5ρ_q, agr.T))

`num_variables`/`num_constraints` are INVARIANT (no rebuild) — a mutate-then-solve is EQUIVALENT
to a fresh build at the new `ρ_q` (identical mechanism to `set_rho!`).

Throws `ArgumentError` if `agr.qag_live === nothing` — calling this on an `OFF`/`CERTIFIED`-built
`AgrOpt` (no live reactive coupling block exists) is a caller error, fail loud rather than
silently no-op. Returns `agr`.

Note: `DsoOpt.jl` also exports a `set_rho_q!` for its own type — Julia dispatches on the
argument type (`AgrOpt` vs `DsoOpt`), so both exports coexisting is correct method-table
behavior, not a naming collision.
"""
function set_rho_q!(agr::AgrOpt, ρ_q::Real)
    agr.qag_live !== nothing || throw(
        ArgumentError(
            "set_rho_q!: this AgrOpt was built without a live reactive coupling block " *
            "(reactive_mode != :live); nothing to update",
        ),
    )
    # Diagonal quadratic coeff of every qag_live[t]² set to −0.5ρ_q (Max objective, penalty
    # subtracted). BATCH form — one MOI modification list; no rebuild (RESEARCH Pattern 1).
    set_objective_coefficient(
        agr.model,
        agr.qag_live,
        agr.qag_live,
        fill(-0.5 * ρ_q, agr.T),
    )
    return agr
end

export AgrOpt, build_agr_opt, solve_agr!, set_rho!, set_rho_q!

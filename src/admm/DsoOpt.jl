# src/admm/DsoOpt.jl
#
# SEAM: DSO-OPT — the whole-network SOCP ADMM subproblem.
# Declares its own exports per the include-graph convention.
#
# WHAT IT IS (thesis eq. 3.47):
#   The network subproblem that REUSES `ConvexBranchFlow.contribute!` verbatim (P, Q, v, v̂,
#   l, cone, vdrop, cpydrop, smax, :Rp/:Rq) plus the priced FREE-SIGN frontier import — the
#   SOC-exactness enabler. Block 2 of the 2-block split derived from the single
#   augmented Lagrangian:
#
#       min_{P,Q,v,v̂,l,p_import,q_import,pag_dso}
#             Σ_t λ₀[t]·p_import[t]                            (frontier active cost)
#           − Σ_j Σ_t λ_j[t]·pag_dso_j[t]                     (coupling linear price)
#           + (ρ/2) Σ_j Σ_t ( pag_dso_j[t] − a_j[t] )²        (ρ-penalty)
#         s.t.  ConvexBranchFlow constraints (thesis 3.31–3.45)
#               :Rp[root] + p_import[t]  == 0                 (root, hard — no aggregator)
#               :Rp[j]    + pag_dso_j[t] == 0                 (load-node ACTIVE coupling var)
#               :Rq[root] + q_import[t]  == 0                 (free-sign reactive frontier)
#               :Rq[j]    + q_ag_j[t]    == 0                 (load-node CONSTANT reactive draw)
#
#   `pag_dso_j := −netflow_j` is an explicit coupling variable so the objective touches a
#   SINGLE variable per (j,t) — the key that makes `set_objective_coefficient` a one-call
#   update. Solver via `select_optimizer(SOCP())`; gated on
#   `assert_solved!(...; dual=true)`. `assert_socp_exact!(dso.ctx)` runs on the
#   CONVERGED solve only — never mid-loop (early iterates are
#   legitimately inexact). Never model λ_j as a `Parameter`.
#
# REACTIVE CLOSURE (mirrors the centralized `solve_welfare` SOCP path): `ConvexBranchFlow`
# sets `reactive = true` (allocates :Rq at every bus), so the whole-network Q balance MUST be
# closed or the reactive flow is unconstrained/free and the ADMM welfare + duals cannot match
# the centralized SOCP on IEEE-13 (φ = 0.90). Each load node injects its CONSTANT reactive
# draw `−Pdc·tan(acos φ)` (thesis 3.23, inelastic per A3 — NOT a consensus quantity, so no μ
# dual-ascent) into :Rq; a free-sign `q_import` at the root supplies it; then :Rq is pinned to
# zero at ALL nodes and registered as :balance_q.
#
# Reactive consensus (`reactive_consensus` kwarg, default OFF): when CERTIFIED, the
# per-load-node CONSTANT `q_draw[j][t]` injected above is instead promoted to a genuine JuMP
# coupling variable `qag_dso[j,t]` (stashed at `ctx.meta[:qag_dso]`), PINNED to the same fixed
# target via an explicit equality `qag_dso[j,t] == q_draw[j][t]` (registered `:qag_pin`) — this
# is a ONE-SHOT certified dual read, NOT a live μ dual-ascent loop (thesis A3: `AgrOpt.qag`/
# `q_draw` never moves, so no ρ-penalty is needed). The DEFAULT (`false`) path is
# bit-for-bit identical to the pre-reactive-consensus build;  `:balance_q`'s own registration is UNCHANGED either way.

using JuMP

"""
    DsoOpt

The built-ONCE whole-network `DSO-OPT` SOCP subproblem (thesis eq. 3.47), block 2 of the
2-block ADMM. Holds the JuMP `model`, its [`ModelContext`](@ref) `ctx` (carrying the
`ConvexBranchFlow` `pf_vars`, the stashed `feeder`/`T`, and the registered `:balance_p` /
`:balance_q` duals), and the handles the ADMM loop mutates or reads between iterations:

# Fields

  - `model::Model` — the SOCP model, built once (`select_optimizer(SOCP())`); re-solved via
    `set_objective_coefficient` only (never rebuilt).
  - `ctx::ModelContext` — the shared context; `ctx.pf_vars` carries `:l` (the SOC cone is
    present), `ctx.feeder`/`[:T]` feed the SOC exactness gate, `:socp_maxgap` is
    stashed after a `check_exact` solve, and `:ladder_baseline` (see the ladder reset in
    `solve_dso!`) holds the AS-BUILT Clarabel conditioning-ladder attributes snapshotted once by
    `_snapshot_ladder_attrs` in `build_dso_opt`; `solve_dso!` reads it back to restore the
    model to this baseline immediately before every `check_exact = true` (FINAL/converged)
    solve.
  - `pag` — the ACTIVE coupling container `pag[j,t]` (`j` over the load nodes, `t` over `1:T`),
    each pinned by `:Rp[j] + pag[j,t] == 0`. The SOLE variable per `(j,t)` whose linear
    objective coefficient the ADMM loop updates.
  - `qag` — the REACTIVE coupling container, mirroring `pag`'s shape `(load_nodes, T)`.
    `nothing` under `OFF`/`CERTIFIED` (no live reactive coupling block exists); under `LIVE`,
    the SAME `qag_dso` container stashed at `ctx.meta[:qag_dso]`, carrying its own
    `0.5·ρ_q·qag[j,t]²` quadratic objective penalty, mutated in place by [`set_rho_q!`](@ref).
  - `p_import` — the FREE-SIGN active frontier exchange `p_import[t]` at `feeder.root` (>0 buy,
    <0 sell surplus to the MEM at λ₀); priced export is the SOC-exactness enabler.
  - `load_nodes::Vector{Int}` — the non-root buses carrying an aggregator (== every non-root bus,
    guarded at build time); the `j` axis of `pag`.
  - `T::Int` — the day-ahead horizon (thesis A1).
  - `feeder` — the network the SOCP is built on.
  - `ρ::Float64` — the INITIAL penalty ρ₀ captured at build time. NOTE: under adaptive ρ the
    LIVE penalty lives ONLY in the model's quadratic objective coefficients (mutated by
    [`set_rho!`](@ref)); this immutable field is NEVER updated, so after the first ρ adaptation it
    holds ρ₀, not the current penalty. Do not read it as "the current ρ". Currently unused elsewhere.
  - `λ₀::Vector{Float64}` — the MEM / wholesale price profile pricing `p_import`.
"""
struct DsoOpt{P, Q, PI, F <: AbstractFeeder}
    model::Model
    ctx::ModelContext
    pag::P
    qag::Q
    p_import::PI
    load_nodes::Vector{Int}
    T::Int
    feeder::F
    ρ::Float64
    λ₀::Vector{Float64}
end

"""
    _snapshot_ladder_attrs(model::Model) -> Dict{String,Any}

Ladder reset helper: read back the current value of each of the 4 Clarabel
conditioning-ladder attributes named by [`LADDER_ATTR_NAMES`](@ref) directly from `model` via
`get_optimizer_attribute`, and return them as a `Dict`. Called EXACTLY ONCE per model, immediately
after the model is constructed and BEFORE any solve or `solve_with_retry!` escalation can possibly
have touched it (inside `build_dso_opt`, and in `run_stochastic` on the out-of-sample harness,
which restores the snapshot before every held-out re-solve) — so the returned Dict captures
the genuine AS-BUILT factory configuration of the selected backend (e.g. Clarabel's own
defaults `static_regularization_constant = 1.0e-8`, etc.), never a value hardcoded in this
file. If the backend does not expose a given attribute (e.g. after a non-Clarabel
solver-factory swap), that key is simply omitted from the Dict rather than raising — a graceful
degradation so `solve_dso!` keeps working under any factory backend; `_restore_ladder_attrs!`
below then no-ops for the missing key instead of failing the build.
"""
function _snapshot_ladder_attrs(model::Model)
    baseline = Dict{String, Any}()
    for name in LADDER_ATTR_NAMES
        try
            baseline[name] = get_optimizer_attribute(model, name)
        catch
            # Backend doesn't expose this Clarabel-specific attribute — omit it; restore
            # then no-ops for this key instead of failing the build (graceful degradation,
            # solve_dso! must keep working under any factory backend).
        end
    end
    return baseline
end

"""
    _restore_ladder_attrs!(model::Model, baseline::Dict{String,Any}) -> Nothing

Ladder reset helper: write each `(name, value)` pair in `baseline` back onto
`model` via `set_optimizer_attribute`, undoing whatever `solve_with_retry!` escalation
(STICKY, never restored on its own) may have accumulated on the model since it was built.
Called from `solve_dso!` immediately before the FINAL/converged (`check_exact = true`) solve,
so the published solve always runs at the AS-BUILT baseline captured once by
`_snapshot_ladder_attrs` in `build_dso_opt`, never an inherited mid-loop escalation.
`run_stochastic` also calls it before every held-out re-solve of the out-of-sample harness, so
no draw inherits an escalation from an earlier draw.
`set_optimizer_attribute` invalidates any prior solution held by the model, but that is
harmless here because the very next statement in `solve_dso!` re-solves it. If the backend
rejects restoring a given attribute, that key is skipped rather than raising — no solve
happens inside this function, so this catch can never swallow a real solve error.
"""
function _restore_ladder_attrs!(model::Model, baseline::Dict{String, Any})
    for (name, value) in baseline
        try
            set_optimizer_attribute(model, name, value)
        catch
            # Backend rejected restoring this attribute — degrade gracefully. No solve
            # happens inside this function, so this catch can never swallow a real solve
            # error.
        end
    end
    return nothing
end

"""
    _any_flexible_reactive(aggregators) -> Bool

Returns `true` iff ANY aggregator in `aggregators` has a
`:devices` property containing at least one member for which `dv isa FourQuadBESS || is_flexible_load(dv)` holds — i.e. a device whose reactive decision is NOT the constant
`-Pdc*tanφ` draw alone (a `FourQuadBESS`'s live `q_inject`, or a flexible-load member's
`p_inject*tanφ` term the centralized `Aggregator.contribute!` folds into `:Rq` in the centralized model).
Shared (unexported — same `TSODSO` module) by both `build_dso_opt`'s and
`solve_admm`'s smart `reactive_consensus` default below, so a caller of EITHER function who does
not pass `reactive_consensus` explicitly gets `LIVE` whenever such a member is present, keeping
ADMM's DSO-OPT subproblem matched to the centralized model's reactive draw by default. Returns
`false` (no behavior change) for a population with no such member.
"""
function _any_flexible_reactive(aggregators)
    for agg in aggregators
        hasproperty(agg, :devices) || continue
        any(dv -> dv isa FourQuadBESS || is_flexible_load(dv), agg.devices) && return true
    end
    return false
end

"""
    build_dso_opt(feeder, aggregators, T::Int; ρ::Real, λ₀,
                  reactive_consensus = _any_flexible_reactive(aggregators) ? ReactiveMode.LIVE : ReactiveMode.OFF,
                  ρ_q::Real = ρ)
        -> DsoOpt

Build the whole-network `DSO-OPT` SOCP (thesis eq. 3.47) ONCE, reusing the validated
[`ConvexBranchFlow`](@ref) branch-flow builder verbatim and mirroring the centralized
[`solve_welfare`](@ref) frontier + balance-closure path, but closing each LOAD node with an
explicit coupling variable `pag_dso_j[t]` instead of an aggregator injection. Steps:

 1. `model = Model(select_optimizer(SOCP()))` (never names a concrete solver);
    register the `RSOCtoNonConvexQuad` / `SOCtoNonConvexQuad` cross-solver bridges exactly as
    `solve_welfare`; wrap in a [`ModelContext`](@ref); stash `ctx.feeder` / `[:T]` for
    the SOC exactness gate, and `ctx.meta[:ladder_baseline] = _snapshot_ladder_attrs(model)`, taken at THIS exact point, before any solve or
    `solve_with_retry!` escalation can have touched the model, so it captures the genuine
    as-built factory conditioning rather than a hardcoded Clarabel default; `solve_dso!`
    restores it before every FINAL/converged solve.
 2. `contribute!(ConvexBranchFlow(), ctx, feeder; T)` — VERBATIM reuse: builds `P, Q, v, v̂, l ≥ 0`, the rotated SOC cone (3.39), the true voltage drop (3.33), the exactness copy
    (3.43), the apparent-power limit (3.36, only where a real limit binds), accumulates
    `:Rp` (3.31) / `:Rq` (3.32), and stashes `ctx.pf_vars = (; v, v̂, P, Q, l)`.
 3. Add the FREE-SIGN priced frontier `p_import[t]` (active, 3.31) and `q_import[t]` (reactive,
    3.32) at `feeder.root`, injected into `:Rp[root]` / `:Rq[root]` (mirrors
    `solve_welfare(...; allow_export = true)`). Priced export makes the objective strictly
    decreasing in the loss current `l`, keeping the SOC cone TIGHT (exact) under reverse flow.
 4. Close BOTH balances (mirroring the centralized SOCP so ADMM welfare + duals match on
    IEEE-13):
      + ACTIVE: for each load node `j` introduce `pag_dso[j,t]` and inject it into `:Rp[j]`;
        `p_import` already closes the root. Pin `:Rp[j,t] == 0` at all buses, register
        `:balance_p` (its dual is the DADP λ_j).
      + REACTIVE: inject each load node's CONSTANT reactive draw `−Pdc·tan(acos φ)` (thesis 3.23,
        inelastic per A3) into `:Rq[j]`, `q_import` supplies the root; pin `:Rq[j,t] == 0` at all
        buses, register `:balance_q`. This is a FIXED constant (no μ dual-ascent — reactive is
        not a consensus quantity). Certified mode (`reactive_consensus = ReactiveMode.CERTIFIED`): promote this constant
        to a genuine JuMP coupling variable `qag_dso[j,t]`, PINNED to the same fixed target via
        the registered equality `:qag_pin` (`qag_dso[j,t] == q_draw[j][t]`) — still a one-shot
        certified dual read, NOT a live consensus ascent (Assumption A1/A3).
 5. `@objective(model, Min, Σ_t λ₀[t]·p_import[t] + 0.5·ρ·Σ_{j,t} pag_dso[j,t]²)` — the FIXED
    ρ-penalty built ONCE. Each ADMM iteration mutates only the LINEAR coefficient of each
    `pag_dso[j,t]` via `set_objective_coefficient` (see [`solve_dso!`](@ref)) — no rebuild.
    λ_j is a plain `Float64` coefficient, NEVER a JuMP `Parameter` (an indefinite
    bilinear `λ·pag` the conic backend rejects).

Load nodes are the aggregator buses (the root carries no aggregator). A non-root bus WITHOUT an
aggregator is admitted as a physically-valid ZERO-INJECTION TRANSIT node: it carries no coupling variable and no reactive draw, and its `:Rp`/`:Rq` is pinned to
zero via `balance_p`/`balance_q` (closed at all `N` buses) — the correct zero-injection closure
that lets IEEE-123 (~37 junction buses) build. `load_nodes` (the ADMM coupling axis) is thereby
DECOUPLED from "all non-root buses" (the balance-closure axis); on the 2-bus / IEEE-13 fixtures
every non-root bus is a load node, so both axes coincide and the model is unchanged. Throws
`ArgumentError` on empty `aggregators`, a `λ₀` shape mismatch, an aggregator bus outside
`1:length(feeder.buses)`, an aggregator ON the root, or — widened by the flexible-device probe
— a device for which `dv isa FourQuadBESS || is_flexible_load(dv)`
holds combined with a NORMALIZED `mode != LIVE` (the guard compares the
value `normalize_reactive_mode(reactive_consensus)` resolves to, NEVER the caller's raw
`reactive_consensus` keyword spelling; a maintainer must not "simplify" this to
`reactive_consensus != ReactiveMode.LIVE`, which would be WRONG whenever `reactive_consensus` is passed as a
`ReactiveMode.T`) (under `OFF`/`CERTIFIED` the reactive
closure is the inelastic `−Pdc·tanφ` draw alone, so the device's reactive decision — a `FourQuadBESS`'s live
`q_inject`, OR a flexible-load member's `p_inject·tanφ` term the centralized model folds into
`:Rq` in the centralized model — would be silently dropped from the network model — genuinely invalid inputs
still fail loud). `reactive_consensus`'s OWN default (see signature above) resolves
to `LIVE` whenever [`_any_flexible_reactive`](@ref) finds such a member, so this guard now only
fires on an EXPLICIT caller override to `OFF`/`CERTIFIED` against such a population — never on
the default path.

`reactive_consensus`: a 3-state mode a
`ReactiveMode.T` (`ReactiveMode.OFF`, `ReactiveMode.CERTIFIED` or `ReactiveMode.LIVE`), validated
by `normalize_reactive_mode`; `Bool` and `Symbol` values throw `ArgumentError`. Its OWN DEFAULT is the CONTEXT-SENSITIVE
expression `_any_flexible_reactive(aggregators) ? ReactiveMode.LIVE : ReactiveMode.OFF` — resolving to `LIVE` whenever
ANY aggregator carries a `FourQuadBESS` or an `is_flexible_load` member, so ADMM's DSO-OPT
matches the centralized `Aggregator`'s reactive draw WITHOUT the caller having to
pass `reactive_consensus = ReactiveMode.LIVE` by hand; a population with NO such member still defaults to
`ReactiveMode.OFF`, unchanged from the previous default.

  - `OFF` (default when no flexible-load/FourQuadBESS member is present): step 4's
    reactive injection is the bit-for-bit identical constant `q_draw[j][t]` (no `ctx.meta[:qag_dso]`
    key exists).
  - `CERTIFIED`: the constant is promoted to a genuine JuMP coupling variable
    `qag_dso[j,t]` (stashed at `ctx.meta[:qag_dso]`), pinned to the SAME fixed target via a
    registered equality `:qag_pin` (`qag_dso[j,t] == q_draw[j][t]`) — a one-shot certified dual
    read, NOT a live consensus ascent (thesis A3: `q_draw` never moves, so no new
    ρ-penalty/residual is needed).
  - `LIVE` (NEW): `qag_dso[j,t]` is declared the SAME way as `CERTIFIED`
    (stashed at `ctx.meta[:qag_dso]`), but NO `:qag_pin` equality is registered — it is left as
    a genuinely open coupling variable, carrying its own `0.5·ρ_q·Σ qag_dso[j,t]²` quadratic
    penalty in the objective (see `ρ_q` below), for the outer μ-dual-ascent loop to
    drive.

`ρ_q::Real = ρ`: the FIXED quadratic penalty weight for the `LIVE` reactive coupling
block, mirroring `ρ`'s role for the active `pag_dso` block. Defaults to tracking `ρ` unless the
caller overrides it (the outer loop adapts it independently via [`set_rho_q!`](@ref)). Unused
(never referenced) under `OFF`/`CERTIFIED`.
"""
function build_dso_opt(
    feeder::AbstractFeeder,
    aggregators,
    T::Int;
    ρ::Real,
    λ₀,
    reactive_consensus = _any_flexible_reactive(aggregators) ? ReactiveMode.LIVE :
                         ReactiveMode.OFF,
    ρ_q::Real = ρ,
    pf::AbstractPowerFlow = ConvexBranchFlow(),
)
    _check_admm_pair!(:build_dso_opt, feeder, pf)
    mode = normalize_reactive_mode(reactive_consensus)

    # Boundary guards (mirror solve_welfare): fail here, not deep in objective assembly.
    isempty(aggregators) &&
        throw(ArgumentError("build_dso_opt needs at least one aggregator"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))

    N = length(feeder.buses)
    root = feeder.root

    # Every aggregator must sit on a real, NON-root feeder bus.
    for (k, agg) in enumerate(aggregators)
        1 <= agg.bus <= N || throw(
            ArgumentError("aggregator[$k] bus=$(agg.bus) is outside feeder buses 1:$N"),
        )
        agg.bus == root && throw(
            ArgumentError(
                "aggregator[$k] sits on the root bus $root; the frontier root carries " *
                "no aggregator in DSO-OPT (thesis 3.47)",
            ),
        )
    end

    # Guard against silently dropping device-level reactive decisions: under
    # OFF/CERTIFIED this model's reactive closure target `q_draw[j][t]` is composed from the
    # INELASTIC `−Pdc·tanφ` term ALONE (thesis 3.23, below), so a DEVICE-carried reactive
    # decision — the `q_inject` contract (`FourQuadBESS`), OR a flexible-load
    # member's `p_inject·tanφ` term (Thermostatic/Deferrable/Interruptible, `is_flexible_load`
    # trait's reactive draw) — would be silently DROPPED from the network model, while
    # the centralized model's `Aggregator.contribute!` DOES write it into `:Rq` — a silent
    # semantic divergence. Under CERTIFIED that divergence would additionally be laundered
    # through the `:balance_q` no-slack certificate into a PUBLISHED reactive dual priced
    # against the wrong closure. It fails LOUD (project convention), directing the caller to
    # `:live` — the only mode whose coupling target (`qag_live == qag + q_inject`, AgrOpt.jl;
    # or the centralized `Aggregator`'s flexible-load `:Rq` roll-up) includes the device's
    # reactive decision. The probe now covers `dv isa FourQuadBESS || is_flexible_load(dv)` —
    # a future `q_inject`-carrying OR reactive-drawing device must extend this guard (or the
    # probe should move to a single contract-level trait). This guard fires ONLY
    # on an EXPLICIT caller override to OFF/CERTIFIED (this function's own default now resolves
    # to LIVE whenever such a member is present, via `_any_flexible_reactive` above).
    if mode != ReactiveMode.LIVE
        for (k, agg) in enumerate(aggregators)
            if hasproperty(agg, :devices) &&
               any(dv -> dv isa FourQuadBESS || is_flexible_load(dv), agg.devices)
                throw(
                    ArgumentError(
                        "build_dso_opt: aggregator[$k] (bus $(agg.bus)) carries a " *
                        "FourQuadBESS or flexible-load (is_flexible_load) member — a " *
                        "device-level reactive decision (q_inject, or the " *
                        "p_inject·tanφ flexible-load draw) — but reactive_consensus " *
                        "normalizes to $(mode), not LIVE. Under OFF/CERTIFIED the DSO " *
                        "reactive closure is the inelastic −Pdc·tanφ draw alone, so the " *
                        "device's reactive decision would be silently dropped from the " *
                        "network model (and under CERTIFIED the published dual(:balance_q) " *
                        "would be priced against a closure that no longer matches the " *
                        "centralized model's). Pass reactive_consensus = ReactiveMode.LIVE " *
                        "(or omit it to use the context-sensitive default).",
                    ),
                )
            end
        end
    end

    # TRANSIT-NODE RELAXATION: DECOUPLE the ADMM coupling axis
    # (`load_nodes` = aggregator buses) from the balance-closure axis (all non-root buses). A
    # non-root bus WITHOUT an aggregator is a physically-valid ZERO-INJECTION TRANSIT node (a
    # junction / lateral tap): it carries NO coupling variable and NO reactive draw, so its
    # :Rp/:Rq residual is exactly the branch-flow residual, which `balance_p`/`balance_q` (closed
    # at ALL N buses below) pins to zero — the correct zero-injection closure, NOT an
    # under-determined node. Only genuinely invalid buses fail loud: an aggregator out of range or
    # ON the root (both guarded above). IEEE-123 has ~37 transit buses; the 2-bus / IEEE-13
    # fixtures have NONE (every non-root bus is a load node ⇒ transit_nodes == Int[]), so those
    # cases are byte-for-byte unaffected — same load_nodes, same model shape.
    agg_buses = Set(agg.bus for agg in aggregators)
    load_nodes = sort!(collect(agg_buses))
    transit_nodes = Int[j for j in 1:N if j != root && !(j in agg_buses)]

    # Per-load-node CONSTANT reactive draw q_ag_j[t] = Σ_{agg@j} −Pdc[t]·tan(acos φ) (thesis
    # 3.23). Summed over any aggregators sharing a bus; the temporal guard mirrors Aggregator.
    q_draw = Dict{Int, Vector{Float64}}(j => zeros(Float64, T) for j in load_nodes)
    for agg in aggregators
        length(agg.Pdc) >= T || throw(
            ArgumentError(
                "aggregator at bus $(agg.bus) has Pdc length $(length(agg.Pdc)) < T=$T " *
                "(thesis 3.22/3.23)",
            ),
        )
        tanφ = reactive_factor(agg.φ)               # tan(arccos φ) (thesis 3.23), single-sourced
        q = q_draw[agg.bus]
        for t in 1:T
            q[t] += -agg.Pdc[t] * tanφ
        end
    end

    model = Model(select_optimizer(SOCP()))          # SOCP factory; never names a solver

    # Cross-solver enablement (mirror solve_welfare): the SOC→nonconvex-quad bridges are
    # DORMANT for the primary conic path (the SOCP backend takes the cones natively) and only
    # activate when a smooth-NLP backend re-solves the SOCP as a cross-check. No concrete solver is named.
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.RSOCtoNonConvexQuadBridge)
    JuMP.add_bridge(model, JuMP.MOI.Bridges.Constraint.SOCtoNonConvexQuadBridge)

    ctx = ModelContext(model)
    ctx.feeder = feeder
    ctx.T = T
    # Snapshot the AS-BUILT ladder conditioning NOW —
    # before any solve or `solve_with_retry!` escalation can have touched the model — so
    # `solve_dso!`'s FINAL/converged solve can restore TO THIS later, never to a hardcoded
    # Clarabel default.
    ctx.meta[:ladder_baseline] = _snapshot_ladder_attrs(model)

    # (2) VERBATIM ConvexBranchFlow reuse: P, Q, v, v̂, l, cone, vdrop, cpydrop, smax,
    # :Rp/:Rq, and the pf_vars stash (with :l) — the SOCP is NOT re-implemented here.
    contribute!(pf, ctx, feeder; T = T)

    # (3) FREE-SIGN priced frontier at the root, injected BEFORE closing the residuals.
    @variable(model, p_import[t = 1:T])              # free-sign active frontier exchange
    @variable(model, q_import[t = 1:T])              # free-sign reactive frontier import
    for t in 1:T
        add_to_residual!(ctx, :Rp, root, t, p_import[t])
        add_to_residual!(ctx, :Rq, root, t, q_import[t])
    end
    ctx.meta[:p_import] = p_import
    ctx.meta[:q_import] = q_import

    # (4a) ACTIVE load-node coupling: one variable per (load node, t), injected into :Rp[j].
    @variable(model, pag_dso[j = load_nodes, t = 1:T])
    for j in load_nodes, t in 1:T
        add_to_residual!(ctx, :Rp, j, t, pag_dso[j, t])
    end

    # (4b) REACTIVE load-node closure (thesis 3.23), 3 EXPLICIT branches keyed on `mode`
    # — never a shared branch with a conditional skip. A fixed
    # parameter under OFF/CERTIFIED (no μ dual-ascent — reactive is not a consensus quantity
    # there); a genuinely live coupling variable under LIVE.
    if mode == ReactiveMode.OFF
        # Bit-for-bit identical to the original `reactive_consensus = false` build: inject the CONSTANT
        # draw directly, no qag_dso variable, no ctx.meta[:qag_dso] key.
        for j in load_nodes, t in 1:T
            add_to_residual!(ctx, :Rq, j, t, q_draw[j][t])
        end
    elseif mode == ReactiveMode.CERTIFIED
        # Bit-for-bit identical to the original `reactive_consensus = true` build:
        # promote the constant to a genuine JuMP coupling variable `qag_dso[j,t]`, PINNED to
        # the SAME fixed target via the registered equality `:qag_pin` — a one-shot certified
        # dual read, NOT a live consensus ascent (Assumption A1/A3: q_draw never moves). The
        # `:qag_pin` registration is UNCONDITIONAL in this branch (never skip it).
        @variable(model, qag_dso[j = load_nodes, t = 1:T])
        for j in load_nodes, t in 1:T
            add_to_residual!(ctx, :Rq, j, t, qag_dso[j, t])
        end
        @constraint(model, qag_pin[j = load_nodes, t = 1:T], qag_dso[j, t] == q_draw[j][t])
        register_constraint!(ctx, :qag_pin, qag_pin)
        ctx.meta[:qag_dso] = qag_dso
    elseif mode == ReactiveMode.LIVE
        # NEW: declare qag_dso the SAME way as CERTIFIED (same @variable call, same
        # :Rq injection, same ctx.meta[:qag_dso] stash), but register NO :qag_pin equality —
        # qag_dso stays a genuinely OPEN coupling variable, driven by the outer μ
        # dual-ascent loop and carrying its own ρ_q-scaled quadratic penalty (see (5) below).
        @variable(model, qag_dso[j = load_nodes, t = 1:T])
        for j in load_nodes, t in 1:T
            add_to_residual!(ctx, :Rq, j, t, qag_dso[j, t])
        end
        ctx.meta[:qag_dso] = qag_dso
    else
        error("unreachable: normalize_reactive_mode returned an unhandled ReactiveMode")
    end

    # (4b') TRANSIT-NODE ZERO INJECTION: each non-root, non-load bus is a
    # physical zero-injection junction — inject a pinned 0 into its :Rp/:Rq so `balance_p`/
    # `balance_q` (below, at all N buses) close it as a zero-injection node rather than leaving
    # it out of the coupling. A documentary no-op on feeders with no transit bus (2-bus/IEEE-13:
    # transit_nodes == Int[]), so their model is unchanged. NO coupling variable / reactive draw
    # is added here — transit buses have no aggregator, so they are absent from `load_nodes`,
    # `pag_dso`, and `q_draw`, keeping the ADMM coupling axis untouched.
    for j in transit_nodes, t in 1:T
        add_to_residual!(ctx, :Rp, j, t, 0.0)
        add_to_residual!(ctx, :Rq, j, t, 0.0)
    end

    # (4c) Close BOTH balances at ALL buses (root + every load node). Registered so the DADP
    # duals are recoverable (mirrors the centralized SOCP; ADMM welfare + duals then match).
    close_balance!(ctx, N, T; reactive = true)

    # (5) FIXED-penalty objective built ONCE (thesis 3.47). The pag_dso variables carry NO
    # linear term yet (default zero coupling price); solve_dso! sets each linear coefficient
    # per iteration via set_objective_coefficient — the ρ/2 quadratic below is never touched.
    # Under LIVE ONLY, an ADDITIONAL 0.5·ρ_q·Σ qag_dso[j,t]² term is folded into the SAME
    # accumulator BEFORE the single @objective call, so OFF/CERTIFIED literally never construct
    # or touch the ρ_q term (bit-for-bit identical built objective under those two modes).
    obj_expr =
        sum(λ₀[t] * p_import[t] for t in 1:T) +
        0.5 * ρ * sum(pag_dso[j, t]^2 for j in load_nodes, t in 1:T)
    if mode == ReactiveMode.LIVE
        obj_expr += 0.5 * ρ_q * sum(qag_dso[j, t]^2 for j in load_nodes, t in 1:T)
    end
    @objective(model, Min, obj_expr)

    return DsoOpt(
        model,
        ctx,
        pag_dso,
        mode == ReactiveMode.LIVE ? qag_dso : nothing,
        p_import,
        load_nodes,
        T,
        feeder,
        Float64(ρ),
        Vector{Float64}(λ₀),
    )
end

"""
    solve_dso!(dso::DsoOpt, λ, a, ρ::Real; check_exact::Bool = false, strict::Bool = true)
        -> (; pag_dso, p_import, exact_maxgap)

Re-solve the built-ONCE `DSO-OPT` (thesis eq. 3.47) for one ADMM iteration by mutating ONLY
the LINEAR objective coefficient of each coupling variable `pag_dso[j,t]` — no JuMP rebuild. For each load node `j` and time `t` it calls

    set_objective_coefficient(dso.model, dso.pag[j,t], −λ[j][t] − ρ·a[j][t])

(the FIXED `0.5·ρ·pag²` quadratic penalty from `build_dso_opt` is left UNTOUCHED), then gates
the solve on [`assert_solved!`](@ref)`(...; dual = true)` before any dual is read.
The MID-LOOP (`strict = false`) solve instead routes through
[`solve_with_retry!`](@ref)`(...; dual = false, allow_almost = true)` — the same solve-status gate,
wrapped in the Clarabel conditioning ladder, because that solve reads NO duals (see the
inline rationale at the call site and the IEEE-13 numerical-error note in the docs).

`check_exact = true` — the FINAL/converged consolidation
call — ALSO now resets the Clarabel conditioning ladder to the as-built snapshot
(`dso.ctx.meta[:ladder_baseline]`, taken once by `build_dso_opt`) immediately before the
solve, REGARDLESS of `strict`. This runs BEFORE the `strict`/`else` dispatch below, so it
applies whichever branch this call happens to take. Mid-loop iterates (`check_exact = false`)
are never reset, so an escalation rescued mid-loop stays STICKY in force across the remaining
mid-loop iterations exactly as before — only the published FINAL/converged solve is guaranteed
to run at the factory's own configuration.

`λ` and `a` are indexable by the load-node bus id, each yielding a length-`T` price / target
profile (`λ[j][t]`, `a[j][t]`): `λ` is the current DADP estimate, `a` the AGR-OPT consensus
target. λ_j is a plain scalar coefficient, NEVER a JuMP `Parameter` (an indefinite bilinear
`λ·pag` the conic backend rejects).

`check_exact` is the CONVERGENCE flag. When `true` (only the final, converged solve — mid-loop
iterates are legitimately inexact and would throw) it runs the SOC
exactness gate [`assert_socp_exact!`](@ref)`(dso.ctx; rtol = rtol_exact, atol = atol_exact)`,
stashing the returned `maxgap` under `dso.ctx.meta[:socp_maxgap]`; a STRICT (inexact) cone means
`l` is a fictitious over-current and the recovered prices are physically meaningless, so the
gate THROWS and prices are refused. When `false` the gate is NOT run (and `atol_exact`/
`rtol_exact` are inert — never consulted).

`atol_exact`/`rtol_exact` (2026-08-22 follow-up) are an ADDITIVE override
seam onto [`assert_socp_exact!`](@ref)'s own `atol`/`rtol` kwargs. Their defaults (`nothing`/`1e-4`)
are `assert_socp_exact!`'s own defaults: `atol_exact = nothing` selects the
hybrid per-branch/hour floor `max(TAU_SOLVER_EXACT, MEASURED_REL_TOL_EXACT*ref_b)` = `max(2e-7, 1e-9·ref_b)`; an explicit `Real` is a flat per-branch floor that bypasses it. Previously the
default was a FLAT `1e-6`, so `check_exact = true` callers relying on the default are NOT
bit-for-bit identical: the gate is STRICTER where `ref_b < 1000` (smax below ≈ 31.6 pu, or an unlimited
branch whose hour's head-branch |S| is below ≈ 31.6 pu — a gap in `(2e-7, 1e-6]` now raises
`CertificateError`) and LOOSER where `ref_b > 1000` (up to ≈ `9.8e-6` at smax just below
`SMAX_NO_LIMIT = 99`, unbounded in principle on an unlimited branch with head flow above ≈ 31.6
pu). Mid-loop `check_exact = false` calls never consult these kwargs and are unaffected. A
`check_exact = true` call records the `atol_exact` it judged with in
`dso.ctx.meta[:socp_atol_exact]` (before the gate runs, so also on a refusal).
This is a SEAM, not a default weakening (certificate-laundering): never
use it to make a point classify as exact that would otherwise be inexact under the project's own
default gate. A caller overriding it is asserting they have their OWN independently measured
noise floor for the tolerance they pass (mirrors how `scripts/benchmark_ieee8500.jl`'s
`IEEE8500_MV_EXACT_ATOL`/`IEEE8500_EXACT_ATOL` were derived).

Returns `(; pag_dso, p_import, exact_maxgap)` — the solved coupling values `value.(dso.pag)`,
the frontier exchange `value.(dso.p_import)`, and the certified cone residual (`nothing` until
a `check_exact = true` solve stashes it).
"""
function solve_dso!(
    dso::DsoOpt,
    λ,
    a,
    ρ::Real;
    check_exact::Bool = false,
    strict::Bool = true,
    atol_exact::Union{Nothing, Real} = nothing,
    rtol_exact::Real = 1e-4,
)
    # Build-once re-solve: mutate ONLY the linear coefficient of each pag_dso[j,t]
    # (one scalar call per (j,t)); the ρ/2 quadratic penalty built in build_dso_opt is fixed.
    for j in dso.load_nodes, t in 1:dso.T
        set_objective_coefficient(dso.model, dso.pag[j, t], -λ[j][t] - ρ * a[j][t])
    end

    # Reset the Clarabel conditioning ladder to the
    # AS-BUILT snapshot (`dso.ctx.meta[:ladder_baseline]`, taken once in `build_dso_opt`)
    # immediately before the FINAL/converged solve. Gated on `check_exact`, NOT `strict`:
    # `solve_admm`'s actual production final-consolidation call passes `strict = false`
    # (see the PUBLISHED-PRIMAL CERTIFICATE block in `solve_admm.jl` — it
    # deliberately relies on the PHYSICAL `:balance_p` no-slack gate rather than a bare
    # `dual = true` solver label), so gating on `strict` alone would never fire on the path
    # this fix exists to protect. `check_exact` is this function's OWN pre-existing "is
    # this the final/converged call" flag (every mid-loop iterate
    # passes it `false`), so it is the correct signal regardless of which `strict` branch
    # is about to run below, and it fires EXACTLY ONCE per `solve_admm` run — mid-loop
    # iterations (`check_exact = false`) are UNTOUCHED, so a `solve_with_retry!` escalation
    # applied mid-loop stays STICKY across them exactly as before (no wasted per-iteration
    # re-failure).
    if check_exact
        _restore_ladder_attrs!(
            dso.model,
            get(dso.ctx.meta, :ladder_baseline, Dict{String, Any}()),
        )
    end

    # Never trust a dual (price) before a trusted primal solve. `strict = true` (the
    # default, and ALWAYS used on the final/converged solve) requires a fully OPTIMAL, dual-
    # feasible point. `strict = false` is the MID-LOOP mode: the DSO subproblem's DUALS are never
    # read in ADMM (the transactive price is the outer multiplier λ, not `dual(balance_p)`), so an
    # ALMOST_OPTIMAL / NEARLY_FEASIBLE primal — the interior-point backend stopping just shy of its
    # centralized-grade gap under the ρ-penalty — is acceptable at an intermediate iterate (the
    # residual loop self-corrects). The converged solve is still STRICT.
    if strict
        assert_solved!(dso.model; dual = true)
    else
        # CONDITIONING LADDER on the MID-LOOP solve ONLY.
        # On IEEE-13 the mid-loop DSO-OPT
        # sits on a numerical knife-edge once adaptive-ρ has doubled from ρ₀ = 100 to ρ = 200
        # (τ = 2; this is NOT the ρ_max = 1e4 clamp, just one climb step) and the residuals are
        # within ~1.5-2x of tolerance: Clarabel's DEFAULT static regularization is not
        # always enough, and whether a given build lands on the failing side is decided by
        # pure floating-point/codegen perturbation (an UNREACHABLE `include` flips it; so does
        # a Julia PATCH bump — 1.10.11/1.11.9/1.12.5 fail, 1.12.7 converges, each pair stably).
        # A bare `assert_solved!` therefore throws `NUMERICAL_ERROR` mid-iteration on an ADMM
        # run that is otherwise converging normally. `solve_with_retry!` already owns exactly
        # this escalation (`MOI.NUMERICAL_ERROR ∈ RETRYABLE_STATUSES`); rung 2
        # (`static_regularization_constant => 1e-6`) recovers the SAME optimum the failing
        # builds were converging to (58 iterations, welfare agreeing to ~1e-9 relative with
        # every natively-converging environment) — it rescues a solve, it does not paper over
        # a divergence.
        #
        # SCOPE — the LADDER IS WIRED ONLY ON THIS BRANCH. This paragraph describes the
        # `strict = true` branch's OWN behaviour for any caller that selects it (e.g. direct
        # test calls in `test/test_dso.jl`) — `solve_admm`'s own final-consolidation call in
        # production actually passes `strict = false` (see the ladder-reset comment above the
        # `strict`/`else` dispatch for why the reset fix does not depend on which branch runs).
        # The `strict = true` FINAL/converged solve above deliberately keeps the BARE
        # `assert_solved!(…; dual = true)` STRICT gate: it is the solve whose result is
        # published, so it must never be allowed to pass on a merely ALMOST_OPTIMAL/
        # NEARLY_FEASIBLE point, and it must still hard-fail (not silently escalate) if it is
        # the one that goes numerically bad. `allow_almost = true` here preserves this branch's
        # pre-existing acceptance of a NEARLY_FEASIBLE intermediate primal EXACTLY
        # (`solve_with_retry!`'s new `allow_almost` kwarg defaults to `false`, so no other
        # caller's behaviour changes).
        #
        # HONEST CAVEAT (CORRECTED) — escalation is STILL
        # STICKY WITHIN the mid-loop iterations after a rescue (`solve_with_retry!`'s documented
        # contract: `set_optimizer_attribute` mutates the model PERMANENTLY and is never
        # restored on its own); `dso` is BUILD-ONCE, so once a mid-loop rescue escalates to
        # rung 2, the REMAINING mid-loop iterations run at
        # `static_regularization_constant = 1e-6` — intentional, unchanged. It NO LONGER
        # reaches the final/converged solve: `solve_dso!` now resets the ladder to the as-built
        # snapshot before every `check_exact = true` call (see the ladder-reset block above this
        # `if strict` dispatch). The PREVIOUS version of this comment claimed the escalation
        # "reaches the final `strict = true` solve" — that claim was later corrected: 
        # `solve_admm.jl`'s actual final-consolidation call passes
        # `strict = false`, which is exactly why the ladder reset is gated on `check_exact`
        # rather than `strict`. The mid-loop stickiness itself is bounded and measured, not
        # overlooked:
        #   * the ADMM transactive price is the OUTER multiplier λ (`dadp == λ` in
        #     `solve_admm.jl`), never `dual(balance_p)` of this model — so no published price is
        #     read off a regularization-escalated dual;
        #   * the escalation only ever fires in an environment where the alternative is a HARD
        #     CRASH mid-ADMM (no result at all). Where the default conditioning suffices, no
        #     rung ≥ 2 is applied and behaviour is bit-identical to before this change;
        #   * measured price/welfare impact is BELOW the cross-environment noise floor: rescued
        #     IEEE-13 welfare = -4822.903616694139 vs -4822.903620476632 (1.10, unreachable-
        #     include A/B) and -4822.903625595291 (1.12.7, native convergence) — a ~2e-9
        #     relative spread the natively-converging builds already exhibit among themselves,
        #     at an IDENTICAL 58 iterations;
        #   * the final solve still runs the full STRICT gate AND the SOC exactness gate, now
        #     preceded by the ladder restore.
        solve_with_retry!(dso.model; dual = false, allow_almost = true)
    end

    # SOC EXACTNESS GATE — CONVERGENCE ONLY. Runs strictly AFTER
    # assert_solved! and refuses prices (throws) if the SOC cone is inexact; stashes maxgap.
    # Mid-loop iterates skip this — they are legitimately inexact and would throw spuriously.
    if check_exact && has_branch_current(dso.ctx)
        # Record the gate floor this certificate was judged with (`nothing` =
        # hybrid floor, a `Real` = flat override) BEFORE the gate runs, so the default that
        # actually reached the gate is traceable — and testable — even when the gate refuses.
        dso.ctx.meta[:socp_atol_exact] = atol_exact
        dso.ctx.meta[:socp_maxgap] =
            assert_socp_exact!(dso.ctx; rtol = rtol_exact, atol = atol_exact)
    end

    return (;
        pag_dso = value.(dso.pag),
        p_import = value.(dso.p_import),
        exact_maxgap = get(dso.ctx.meta, :socp_maxgap, nothing),
    )
end

"""
    set_rho!(dso::DsoOpt, ρ::Real) -> DsoOpt

Mutate the FIXED quadratic penalty weight of the built-ONCE DSO-OPT in place when the adaptive-ρ
loop changes ρ — WITHOUT rebuilding the JuMP model (build-once preserved).
DSO-OPT is `Min λ₀ᵀp_import + (ρ/2)·Σ_{j,t} pag_dso[j,t]²`, so the diagonal
quadratic coefficient of every `pag_dso[j,t]²` is `+0.5ρ` (Min objective — MIRROR of the AGR-OPT
`−0.5ρ`). Flatten the `pag` coupling container to a `Vector{VariableRef}` and set them all in one
BATCH call:

    set_objective_coefficient(dso.model, v, v, fill(0.5ρ, length(v)))

The 4-arg (quadratic) `set_objective_coefficient(model, x, x, c)` sets the coefficient of `x²`
to `c` directly (JuMP 1.30.1 absorbs the MOI `0.5·xᵀQx` canonicalization — verified in the JuMP source,
objective.jl:629,712). The mutation is stored in the `CachingOptimizer` and re-applied
on the next `optimize!`, identical mechanism to the LINEAR `set_objective_coefficient` update
[`solve_dso!`](@ref) already runs each iteration — so `num_variables`/`num_constraints` are
INVARIANT (no rebuild) and a mutate-then-solve is EQUIVALENT to a fresh build at the new ρ.

CONTRACT for the caller: call `set_rho!` ONLY when ρ actually changed and in LOCKSTEP
with the linear coefficient update `−λ[j][t] − ρ·a[j][t]` (same ρ: penalty ρ and
ascent ρ must not diverge). Never model ρ (or λ) as a JuMP `Parameter`. Keep ρ strictly POSITIVE
(convexity guard: ρ > 0 ⇒ DSO stays convex-Min); the adaptive policy clamps
ρ ∈ `[ρ_min, ρ_max]`. Returns `dso`.
"""
function set_rho!(dso::DsoOpt, ρ::Real)
    # Flatten the pag_dso DenseAxisArray (j over load_nodes × t) to a flat Vector{VariableRef}
    # by indexing over its KNOWN axes — `collect` on a Vector-axis DenseAxisArray is unsupported.
    v = VariableRef[dso.pag[j, t] for j in dso.load_nodes for t in 1:dso.T]
    # Diagonal quadratic coeff of every pag_dso[j,t]² set to +0.5ρ (Min objective, penalty added).
    # BATCH form — one MOI modification list; no rebuild.
    set_objective_coefficient(dso.model, v, v, fill(0.5 * ρ, length(v)))
    return dso
end

"""
    set_rho_q!(dso::DsoOpt, ρ_q::Real) -> DsoOpt

Mutate the FIXED quadratic penalty weight of the built-ONCE `LIVE` reactive coupling block in
place — the exact `set_rho!` PEER for the reactive `qag` block (the outer
μ-dual-ascent loop adapts `ρ_q` independently of `ρ`). DSO-OPT under `LIVE` carries an
ADDITIONAL `Min ... + (ρ_q/2)·Σ_{j,t} qag[j,t]²` term (see `build_dso_opt`'s objective
assembly), so the diagonal quadratic coefficient of every `qag[j,t]²` is `+0.5ρ_q`. Flatten the
`qag` coupling container to a `Vector{VariableRef}` and set them all in one BATCH call, mirroring
`set_rho!`'s exact shape:

    set_objective_coefficient(dso.model, v, v, fill(0.5ρ_q, length(v)))

`num_variables`/`num_constraints` are INVARIANT (no rebuild) — a mutate-then-solve is EQUIVALENT
to a fresh build at the new `ρ_q` (identical mechanism to `set_rho!`).

Throws `ArgumentError` if `dso.qag === nothing` — calling this on an `OFF`/`CERTIFIED`-built
`DsoOpt` (no live reactive coupling block exists) is a caller error, fail loud rather than
silently no-op. Returns `dso`.
"""
function set_rho_q!(dso::DsoOpt, ρ_q::Real)
    dso.qag !== nothing || throw(
        ArgumentError(
            "set_rho_q!: this DsoOpt was built without a live reactive coupling block " *
            "(reactive_consensus != ReactiveMode.LIVE); nothing to update",
        ),
    )
    # Flatten the qag_dso DenseAxisArray (j over load_nodes × t) to a flat Vector{VariableRef},
    # mirroring set_rho!'s exact flatten-then-one-call shape.
    v = VariableRef[dso.qag[j, t] for j in dso.load_nodes for t in 1:dso.T]
    # Diagonal quadratic coeff of every qag[j,t]² set to +0.5ρ_q (Min objective, penalty added).
    # BATCH form — one MOI modification list; no rebuild.
    set_objective_coefficient(dso.model, v, v, fill(0.5 * ρ_q, length(v)))
    return dso
end

export DsoOpt, build_dso_opt, solve_dso!

# src/experiments/run.jl
#
# SEAM: ScenarioResult + `TSODSO.run` strategy method dispatch + normalization (EXP-01 / INFRA-04,
# reshaped in Phase 32 / ARCH-01, ARCH-02).
#
# Phase 32 turns the former symbol dispatch into METHOD dispatch on the strategy type:
# `run(::Centralized, s)` -> `solve_welfare` + `extract_dlmp`, `run(::ADMM, s)` -> `solve_admm`,
# each normalized into one comparable `ScenarioResult` (common fields + typed `details`). The
# power-flow formulation comes from `build_powerflow(s)` — nothing is hard-coded. `run_scenario`
# stays as a thin wrapper. MPC/Stochastic methods live in mpc_loop.jl / run_stochastic.jl.
#
# PURE ORCHESTRATION over already-validated builders — no new model, no solver named anywhere
# (INFRA-02). Because the seed is threaded end-to-end (`sub_seed`) and the conic path is
# single-threaded, a same-Scenario same-seed run is bit-for-bit identical within one process
# (INFRA-04). Timings are recorded but EXCLUDED from every equality comparison.
#
# `run` is PATH-FREE — it returns a `ScenarioResult`, never writes a file (see `store.jl`).

"""
    ScenarioResult

The normalized, comparable outcome of [`run_scenario`](@ref) / `TSODSO.run`.

# Fields

  - `scenario::Scenario` — the scenario actually run (provenance).
  - `welfare::Float64` — headline social welfare. Centralized/ADMM: the optimum (eq. 3.38).
    MPC: `realized_welfare` (truth-settled). Stochastic: expected `in_sample.welfare`.
  - `dadp::Matrix{Float64}` — day-ahead dynamic price. Centralized/ADMM: `(n_load_nodes, T)`,
    rows in ascending load-bus order. MPC: published-hour prices as a `1 x n` row. Stochastic:
    `expected_dadp` as a `1 x n` row at the first aggregator's bus.
  - `exact_maxgap::Float64` — SOC-cone exactness certificate. `NaN` means "not applicable":
    LinDistFlow and AC have no SOC cone; MPC has no numeric gap.
  - `elapsed::Float64` — wall-clock seconds (NON-REPRODUCIBLE; never compared).
  - `details` — `nothing` (Centralized), `ADMMDetails`, `MPCDetails` or `StochasticDetails`.

The ADMM-only properties `iters`, `final_r`, `final_s`, `reactive_consensus_mode` are forwarded
from `details` by `getproperty` and are `missing` for non-ADMM results.
"""
struct ScenarioResult
    scenario::Scenario
    welfare::Float64
    dadp::Matrix{Float64}
    exact_maxgap::Float64
    elapsed::Float64
    details::Union{Nothing, ADMMDetails, MPCDetails, StochasticDetails}
end

const _ADMM_FORWARDED = (:iters, :final_r, :final_s, :reactive_consensus_mode)

function Base.getproperty(r::ScenarioResult, name::Symbol)
    if name in _ADMM_FORWARDED
        d = getfield(r, :details)
        return d isa ADMMDetails ? getfield(d, name) : missing
    end
    return getfield(r, name)
end

function Base.propertynames(r::ScenarioResult, private::Bool = false)
    return (fieldnames(ScenarioResult)..., _ADMM_FORWARDED...)
end

# Shared, UNCHANGED materialize sequence (seeds / sub_seed tags / call order: INFRA-04).
function _materialize(s::Scenario)
    feeder = build_feeder(s.feeder)
    profiles = generate_profiles(; seed = sub_seed(s.seed, :profiles), T = s.T)
    λ₀ = build_price(s.price, s.T, profiles)
    aggs = build_population(
        s.population,
        feeder,
        s.feeder,
        profiles,
        sub_seed(s.seed, :population),
    )
    return feeder, λ₀, aggs
end

_effective_scenario(st::AbstractStrategy, s::Scenario) = st == s.strategy ? s : with_strategy(s, st)

"""
    TSODSO.run(::Centralized, s::Scenario) -> ScenarioResult

Monolithic solve with the power flow selected by `s.pf` (via `build_powerflow`). AC is solved with
`allow_local = true` (a local NLP optimum is `LOCALLY_SOLVED`, refused by default).
`exact_maxgap` is the SOC certificate for the convex/restricted formulations and `NaN` for
LinDistFlow/AC.
"""
function run(st::Centralized, s::Scenario)
    s_eff = _effective_scenario(st, s)
    local result
    elapsed = @elapsed begin
        feeder, λ₀, aggs = _materialize(s_eff)
        pf = build_powerflow(s_eff)
        ctx, welfare, _ = solve_welfare(
            feeder,
            pf,
            aggs;
            T = s_eff.T,
            λ₀ = λ₀,
            allow_export = s_eff.allow_export,
            allow_local = pf isa ACPowerFlow,
        )
        load_buses = sort!([a.bus for a in aggs])
        dadp = Matrix{Float64}(extract_dlmp(ctx)[load_buses, :])
        maxgap =
            pf isa Union{ConvexBranchFlow,RestrictedBranchFlow} ?
            Float64(ctx.meta[:socp_maxgap]) : NaN
        result = (Float64(welfare), dadp, maxgap)
    end
    return ScenarioResult(s_eff, result[1], result[2], result[3], elapsed, nothing)
end

"""
    TSODSO.run(st::ADMM, s::Scenario) -> ScenarioResult

ADMM-decomposed solve with the knobs of `st`; `details` is an `ADMMDetails`.
"""
function run(st::ADMM, s::Scenario)
    s_eff = _effective_scenario(st, s)
    local result
    elapsed = @elapsed begin
        feeder, λ₀, aggs = _materialize(s_eff)
        pf = build_powerflow(s_eff)
        r = solve_admm(
            feeder,
            pf,
            aggs;
            T = s_eff.T,
            λ₀ = λ₀,
            ρ = st.ρ,
            maxiter = st.maxiter,
            ε_abs = st.ε_abs,
            ε_rel = st.ε_rel,
            τ = st.τ_ratio,
            μ = st.μ,
            allow_export = s_eff.allow_export,
        )
        details = ADMMDetails(
            Int(r.iters),
            Float64(last(r.residuals.primal_trace)),
            Float64(last(r.residuals.dual_trace)),
            r.reactive_consensus_mode,
        )
        result = (Float64(r.welfare), Matrix{Float64}(r.dadp), Float64(r.exact_maxgap), details)
    end
    return ScenarioResult(s_eff, result[1], result[2], result[3], elapsed, result[4])
end

run(s::Scenario) = run(s.strategy, s)

"""
    run_scenario(s::Scenario) -> ScenarioResult

Thin wrapper over `TSODSO.run(s.strategy, s)` (dispatch is method dispatch on the strategy type).
PATH-FREE: never writes to disk (see [`run_and_store`](@ref)). Same-seed runs in one process
return `==`-identical `welfare`/`dadp`/`exact_maxgap` (INFRA-04); `elapsed` is excluded.
"""
run_scenario(s::Scenario) = run(s.strategy, s)

export ScenarioResult, run_scenario

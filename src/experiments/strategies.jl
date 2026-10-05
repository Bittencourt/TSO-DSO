# src/experiments/strategies.jl
#
# Solve strategies as types. A strategy carries its own knobs and validates
# them in its constructor; `TSODSO.run(strategy, scenario)` is the package-owned generic entry
# point. This file also owns the valid strategy x power-flow matrix (`supports_pf`) and the typed
# strategy-specific result `details` structs (defined here because run.jl is included before
# mpc_loop.jl / run_stochastic.jl).

"""
    AbstractStrategy

Supertype of the solve strategies: [`Centralized`](@ref), [`ADMM`](@ref), [`MPC`](@ref) and
[`Stochastic`](@ref). A strategy is a plain value carrying the knobs of that solve mode.
"""
abstract type AbstractStrategy end

"""
    TSODSO.run(strategy::AbstractStrategy, s::Scenario) -> ScenarioResult

Package-owned generic function that runs scenario `s` under `strategy`. It is deliberately NOT
exported (to avoid colliding with `Base.run`) and is always called qualified, `TSODSO.run(...)`.
"""
function run end

"""
    Centralized()

Monolithic social-welfare solve (no knobs).
"""
struct Centralized <: AbstractStrategy end

"""
    ADMM(; ρ = 100.0, ε_abs = 1e-4, ε_rel = 1e-3, maxiter = 200, τ_ratio = 2.0, μ = 10.0)

ADMM-decomposed solve with penalty `ρ`, absolute/relative residual tolerances, iteration cap
`maxiter` and residual-balancing parameters `τ_ratio`, `μ`. Throws `ArgumentError` on invalid knobs.
"""
struct ADMM <: AbstractStrategy
    ρ::Float64
    ε_abs::Float64
    ε_rel::Float64
    maxiter::Int
    τ_ratio::Float64
    μ::Float64
    function ADMM(ρ, ε_abs, ε_rel, maxiter, τ_ratio, μ)
        if !all(isfinite, (ρ, ε_abs, ε_rel, τ_ratio, μ))
            throw(
                ArgumentError(
                    "ADMM: ρ/ε_abs/ε_rel/τ_ratio/μ must be finite; got ρ=$ρ, ε_abs=$ε_abs, " *
                    "ε_rel=$ε_rel, τ_ratio=$τ_ratio, μ=$μ",
                ),
            )
        end
        if maxiter < 1
            throw(ArgumentError("ADMM: maxiter must be ≥ 1 (ADMM iteration cap); got maxiter=$maxiter"))
        end
        if ρ <= 0
            throw(ArgumentError("ADMM: ρ must be > 0 (ADMM penalty); got ρ=$ρ"))
        end
        if ε_abs <= 0 || ε_rel <= 0
            throw(ArgumentError("ADMM: ε_abs/ε_rel must be > 0; got ε_abs=$ε_abs, ε_rel=$ε_rel"))
        end
        if τ_ratio <= 0 || μ <= 0
            throw(ArgumentError("ADMM: τ_ratio/μ must be > 0; got τ_ratio=$τ_ratio, μ=$μ"))
        end
        return new(ρ, ε_abs, ε_rel, maxiter, τ_ratio, μ)
    end
end

function ADMM(; ρ = 100.0, ε_abs = 1e-4, ε_rel = 1e-3, maxiter = 200, τ_ratio = 2.0, μ = 10.0)
    return ADMM(Float64(ρ), Float64(ε_abs), Float64(ε_rel), Int(maxiter), Float64(τ_ratio), Float64(μ))
end

"""
    MPC(; H = 6, step = 1, terminal_soc = true, forecast_error = 0.05)

Rolling-horizon closed-loop strategy: window length `H`, re-solve every `step` hours, optional
terminal state-of-charge constraint, and forecast error level in `[0, 1)`. `step ≤ H` and
`H ≤ T` are run-time guards in the MPC loop, not constructor checks.
"""
struct MPC <: AbstractStrategy
    H::Int
    step::Int
    terminal_soc::Bool
    forecast_error::Float64
    function MPC(H, step, terminal_soc, forecast_error)
        if H < 1
            throw(ArgumentError("MPC: H must be ≥ 1 (window length); got H=$H"))
        end
        if step < 1
            throw(ArgumentError("MPC: step must be ≥ 1; got step=$step"))
        end
        if !(0 <= forecast_error < 1)
            throw(ArgumentError("MPC: forecast_error must be in [0, 1); got forecast_error=$forecast_error"))
        end
        return new(H, step, terminal_soc, forecast_error + 0.0)   # -0.0 -> +0.0 (== / hash)
    end
end

function MPC(; H = 6, step = 1, terminal_soc = true, forecast_error = 0.05)
    return MPC(Int(H), Int(step), Bool(terminal_soc), Float64(forecast_error))
end

# Shared by the constructor and `_run_stochastic` (the stored vector is mutable, so it is
# re-validated before each run).
function _check_probabilities(S::Integer, probabilities::AbstractVector)
    if length(probabilities) != S
        throw(ArgumentError("Stochastic: probabilities must have length S=$S; got $(length(probabilities))"))
    end
    if !all(>(0), probabilities)
        throw(ArgumentError("Stochastic: probabilities must all be > 0; got $probabilities"))
    end
    if !isapprox(sum(probabilities), 1; atol = 1e-8)
        throw(ArgumentError("Stochastic: probabilities must sum to 1; got sum=$(sum(probabilities))"))
    end
    return nothing
end

"""
    Stochastic(; S = 3, probabilities = Float64[], H_oos = 5)

Extensive-form stochastic strategy with `S ∈ 3:5` in-sample scenarios and an out-of-sample
horizon `H_oos ∈ 5:10`. An empty `probabilities` means uniform `1/S`; an explicit vector must have
length `S`, be strictly positive and sum to 1, and is stored as a defensive copy.
"""
struct Stochastic <: AbstractStrategy
    S::Int
    probabilities::Vector{Float64}
    H_oos::Int
    function Stochastic(S, probabilities, H_oos)
        if !(3 <= S <= 5)
            throw(ArgumentError("Stochastic: S must be in 3:5; got S=$S"))
        end
        if !(5 <= H_oos <= 10)
            throw(ArgumentError("Stochastic: H_oos must be in 5:10; got H_oos=$H_oos"))
        end
        if isempty(probabilities)
            p = fill(1 / S, S)
        else
            _check_probabilities(S, probabilities)
            p = copy(probabilities)
        end
        return new(S, p, H_oos)
    end
end

function Stochastic(; S = 3, probabilities = Float64[], H_oos = 5)
    return Stochastic(Int(S), Vector{Float64}(probabilities), Int(H_oos))
end

# Value semantics: Scenario equality and sweeps must compare strategies by value.
Base.:(==)(a::ADMM, b::ADMM) =
    a.ρ == b.ρ && a.ε_abs == b.ε_abs && a.ε_rel == b.ε_rel &&
    a.maxiter == b.maxiter && a.τ_ratio == b.τ_ratio && a.μ == b.μ
Base.hash(a::ADMM, h::UInt) = hash((a.ρ, a.ε_abs, a.ε_rel, a.maxiter, a.τ_ratio, a.μ), hash(:ADMM, h))

Base.:(==)(a::MPC, b::MPC) =
    a.H == b.H && a.step == b.step && a.terminal_soc == b.terminal_soc &&
    a.forecast_error == b.forecast_error
Base.hash(a::MPC, h::UInt) = hash((a.H, a.step, a.terminal_soc, a.forecast_error), hash(:MPC, h))

Base.:(==)(a::Stochastic, b::Stochastic) =
    a.S == b.S && a.H_oos == b.H_oos && a.probabilities == b.probabilities
Base.hash(a::Stochastic, h::UInt) = hash((a.S, a.probabilities, a.H_oos), hash(:Stochastic, h))

"""
    TSODSO.supported_pfs(strategy::AbstractStrategy) -> Tuple{Vararg{Symbol}}

Power-flow selectors the strategy accepts. See [`TSODSO.supports_pf`](@ref).
"""
supported_pfs(::Centralized) = (:convex_branch_flow, :restricted_branch_flow, :lindistflow, :ac)
supported_pfs(::ADMM) = (:convex_branch_flow, :restricted_branch_flow, :lindistflow)
supported_pfs(::Union{MPC,Stochastic}) = (:convex_branch_flow,)

"""
    TSODSO.supports_pf(strategy, pf::Symbol, thesis_literal::Bool) -> Bool

Single place encoding the valid strategy x power-flow matrix. `Centralized` accepts all four
selectors. `ADMM` accepts convex (thesis-literal allowed), restricted and LinDistFlow; it mirrors
`admm_supported` (`:ac` is rejected). `MPC`, `Stochastic` accept only `:convex_branch_flow` with
`thesis_literal = false` (they fail, measured, on restricted/LinDistFlow/AC).
"""
supports_pf(st::ADMM, pf::Symbol, thesis_literal::Bool) = pf in supported_pfs(st)
supports_pf(st::Centralized, pf::Symbol, thesis_literal::Bool) = pf in supported_pfs(st)
supports_pf(::Union{MPC,Stochastic}, pf::Symbol, thesis_literal::Bool) =
    pf === :convex_branch_flow && !thesis_literal

"""
    ADMMDetails(iters, final_r, final_s, reactive_consensus_mode)

ADMM-specific result details, carried in `ScenarioResult.details` beside the headline fields.
"""
struct ADMMDetails
    iters::Int
    final_r::Float64
    final_s::Float64
    reactive_consensus_mode::ReactiveMode.T
end

"""
    MPCDetails(regret, steps, day_ahead_welfare, forecast_settled_welfare, realized_welfare, raw)

MPC-specific details. The headline `welfare` of the `ScenarioResult` is `realized_welfare`
(truth-settled). `raw` holds the complete unchanged `run_mpc` NamedTuple.
"""
struct MPCDetails
    regret::Float64
    steps::Int
    day_ahead_welfare::Float64
    forecast_settled_welfare::Float64
    realized_welfare::Float64
    raw::NamedTuple
end

"""
    StochasticDetails(in_sample, oos)

Stochastic-specific details. The headline `welfare` of the `ScenarioResult` is the expected
`in_sample.welfare`; `in_sample` and `oos` are the unchanged `run_stochastic` NamedTuples.
"""
struct StochasticDetails
    in_sample::NamedTuple
    oos::NamedTuple
end

export AbstractStrategy, Centralized, ADMM, MPC, Stochastic

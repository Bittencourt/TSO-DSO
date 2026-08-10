# src/experiments/Scenario.jl
#
# SEAM: Scenario — the immutable, primitive-selector declarative scenario spec (EXP-01).
# OWNER: plan 08-02 (this plan).
#
# `Scenario` holds ONLY primitive selectors (Symbol/Int/Float64/Bool/String) — never a
# built `Feeder`/`Vector{Aggregator}`/`λ₀::Vector` — so `savename(s)` (DrWatson) works with
# ZERO `DrWatson.default_allowed` overloading (RESEARCH Pitfall 1): every SCALAR field sits
# inside DrWatson's `default_allowed = (Real, String, SubString, Symbol, TimeType)` filter.
# ONE documented exception (phase-22 review WR-02): `stoch_probabilities::Vector{Float64}`
# is NOT in `default_allowed` and IS silently dropped from the bare `savename` string —
# `scenario_filename` (store.jl) restores filename identity by folding a stable FNV-1a
# digest of the vector into the name whenever it is non-uniform. Never use a bare
# `savename(s, ...)` as an on-disk identity key. NOTE (CR-01 fix): `savename`'s
# DEFAULT float formatting still rounds `AbstractFloat` fields to `sigdigits = 3`, so two
# `Scenario`s differing only in a sub-percent ADMM float knob (`ρ`/`ε_abs`/`ε_rel`/`τ_ratio`/`μ`)
# CAN produce an identical default `savename` — every on-disk-storage call site (`store.jl`)
# MUST pass `digits = 10` (lossless round-trip) and `safe = true` (never overwrite) to avoid a
# silent JLD2 collision; do not rely on the bare `savename(s, "jld2")` string as a uniqueness
# key. The heavy objects are materialized later, deterministically, by
# `src/experiments/materialize.jl` from these selectors + the master `seed`.
#
# Validation is a CONSTRUCTION invariant (mirrors `Thermostatic`/`PVBattery`/`Aggregator`):
# an explicit inner constructor `throw`s `ArgumentError` (never `@assert`, threat T-03-04
# convention) on any unknown feeder/strategy/price/population selector or out-of-range
# T/seed/maxiter, so a `Scenario` can never silently underdetermine a run (threat T-08-05).

"""
Valid `feeder` selectors a `Scenario` may name (dispatch target: `build_feeder`, materialize.jl).
"""
const SCENARIO_VALID_FEEDERS = (:ieee13, :ieee123)

"""
Valid `strategy` selectors a `Scenario` may name (dispatch target: `run_scenario`, plan 08-03).
"""
const SCENARIO_VALID_STRATEGIES = (:centralized, :admm)

"""
Valid `price` selectors a `Scenario` may name (dispatch target: `build_price`, materialize.jl).
"""
const SCENARIO_VALID_PRICES = (:mem,)

"""
Valid `population` selectors a `Scenario` may name (dispatch target: `build_population`, materialize.jl).
"""
const SCENARIO_VALID_POPULATIONS = (:default,)

"""
    Scenario

An immutable, `savename`-able declarative experiment specification (EXP-01). Every field is
a PRIMITIVE selector — `Symbol`/`Int`/`Float64`/`Bool`/`String` — never a constructed
`Feeder`/`Vector{Aggregator}`/price vector. This is the load-bearing design decision that
makes `savename`, hashing, diffing, and bit-for-bit reproducibility (INFRA-04) fall out for
free with ZERO `DrWatson.default_allowed` overloading: assert that invariant here rather
than re-discovering it at a call site.

ONE documented exception (phase-22 review WR-02): `stoch_probabilities` is a
`Vector{Float64}` — the struct's first (and only) non-scalar field — which DrWatson's
`default_allowed` filter silently DROPS from the bare `savename` string. Two `Scenario`s
differing only in their probability weighting therefore share a `savename`;
[`scenario_filename`](@ref) (store.jl) restores on-disk filename identity by folding a
stable digest of the vector into the name whenever it is non-uniform. The field is also
defensively COPIED at construction (phase-22 review WR-01) so the validated value can
never be mutated through the caller's own array after construction.

NOTE (CR-01 fix — corrects a prior false claim): this does NOT imply two `Scenario`s
differing only in a `Float64` field produce distinct default `savename`s — DrWatson's default
`sigdigits = 3` float rounding can collapse sub-percent-different ADMM knobs (`ρ`/`ε_abs`/
`ε_rel`/`τ_ratio`/`μ`) onto the identical string. Any code path that uses `savename(s, ...)` as
an on-disk uniqueness key (`run_and_store`, `store.jl`) MUST use `digits = 10` (lossless) and
`safe = true` (never silently overwrite on a residual collision).

# Fields

  - `name::String` — human label; also a `savename` component.
  - `feeder::Symbol = :ieee13` — feeder selector, one of `$(SCENARIO_VALID_FEEDERS)` (dispatches
    `build_feeder`, NEVER a live `Feeder`).
  - `strategy::Symbol = :centralized` — solve-strategy selector, one of
    `$(SCENARIO_VALID_STRATEGIES)` (dispatches `run_scenario`, plan 08-03).
  - `seed::Int = 1` — master seed; `run_scenario` derives independent deterministic sub-seeds
    from it via `sub_seed` (never touches the global RNG, RESEARCH Pitfall 5).
  - `T::Int = 24` — day-ahead horizon length (hours).
  - `population::Symbol = :default` — population selector, one of
    `$(SCENARIO_VALID_POPULATIONS)` (dispatches `build_population`).
  - `price::Symbol = :mem` — price selector, one of `$(SCENARIO_VALID_PRICES)` (dispatches
    `build_price`).
  - `allow_export::Bool = true` — whether the frontier allows priced export (PF-04 exactness
    enabler under PV back-feed).
  - `ρ::Float64 = 100.0`, `ε_abs::Float64 = 1e-4`, `ε_rel::Float64 = 1e-3`, `maxiter::Int = 200`,
    `τ_ratio::Float64 = 2.0`, `μ::Float64 = 10.0` — ADMM-only knobs, kept in the one flat schema
    so the `:centralized` branch simply ignores them (no separate strategy-specific struct).
    `ρ`'s default (100.0) is the empirically-validated initial penalty for the default
    `:ieee13` feeder + `:default` population (matching `test_admm.jl`'s `ρ_ieee13`, RESEARCH):
    starting the Phase-7 adaptive-ρ loop at `ρ₀ = 1.0` numerically errors on this congested
    default population before residual balancing can climb it to a well-conditioned value
    (08-03 deviation — RULE 1, discovered exercising `run_scenario(:admm)` end-to-end for the
    first time). Adaptive ρ still self-tunes per scenario from THIS starting point; a
    hand-tuned `Scenario(; ρ = …)` override remains available for other feeders/populations.
  - `mpc_H::Int = 6`, `mpc_step::Int = 1`, `mpc_terminal_soc::Bool = true`,
    `mpc_forecast_error::Float64 = 0.05` — Phase-21 MPC-only knobs (D-12), additive and kept in
    the SAME flat schema. `mpc_H` is the receding-horizon window length (6 hours, giving
    `T - mpc_H + 1 = 19` published steps on the `T = 24` day-ahead default); `mpc_step` is the
    step size between successive windows (kept `1`, a hook for a future coarser stride);
    `mpc_terminal_soc` toggles D-06's hard terminal-SOC equality (on by default);
    `mpc_forecast_error` is D-08's bounded PV/demand perturbation magnitude (±5% by default,
    a fraction strictly in `[0, 1)`). These four fields are NO-OPS for the `:centralized`/
    `:admm` strategies — consumed ONLY by the phase's own `run_mpc(scenario)` entry point (plan
    21-05), NEVER by `run_scenario`'s `strategy` dispatch. Adding them changes every
    `Scenario`'s `savename` STRING (a documented, accepted cost per RESEARCH.md Pitfall 6's
    resolution) while preserving every EXISTING numeric golden result, since no
    `:centralized`/`:admm` code path reads any of the four.
  - `stoch_S::Int = 3`, `stoch_probabilities::Vector{Float64} = Float64[]`,
    `stoch_H_oos::Int = 5` — Phase-22 stochastic-only knobs (D-01/D-04/D-10), additive and kept
    in the SAME flat schema. `stoch_S` is the in-sample scenario count, LOCKED to the band
    `3 <= stoch_S <= 5` (D-01's "3-5 seeded Markov scenarios"); `stoch_H_oos` is the held-out,
    out-of-sample scenario budget, LOCKED to the band `5 <= stoch_H_oos <= 10` (D-10).
    `stoch_probabilities` uses an EMPTY-VECTOR SENTINEL convention (D-04): the literal
    `@kwdef` default is `Float64[]` (a `@kwdef` field default cannot self-reference the sibling
    `stoch_S` default), but the inner constructor RESOLVES that sentinel to
    `fill(1 / stoch_S, stoch_S)` before it ever reaches `new(...)` — a constructed `Scenario`
    NEVER stores the empty sentinel, only ever a fully-materialized, validated probability
    vector (uniform-by-default, or the researcher's own explicit non-uniform vector, honored
    verbatim). These three fields are NO-OPS for the `:centralized`/`:admm`/`run_mpc` code
    paths — consumed ONLY by the phase's own `run_stochastic(scenario)` entry point (plan
    22-04). Adding them changes every `Scenario`'s `savename` STRING (the same documented,
    accepted cost as the `mpc_*` block above) while preserving every EXISTING numeric golden
    result, since no `:centralized`/`:admm`/`run_mpc` code path reads any of the three.

Construction throws `ArgumentError` when `feeder`/`strategy`/`price`/`population` is not one
of the named valid selectors above, or when `T < 1`, `seed < 1`, `maxiter < 1`, `mpc_H < 1`,
`mpc_step < 1`, `mpc_forecast_error` is not a bounded fraction in `[0, 1)`, `stoch_S` is
outside `[3, 5]`, `stoch_H_oos` is outside `[5, 10]`, or an explicit (non-empty-sentinel)
`stoch_probabilities` fails length/positivity/sum-to-one validation against `stoch_S` (a
Scenario must fully determine a runnable, sane experiment — threat T-08-05).
"""
Base.@kwdef struct Scenario
    name::String
    feeder::Symbol = :ieee13
    strategy::Symbol = :centralized
    seed::Int = 1
    T::Int = 24
    population::Symbol = :default
    price::Symbol = :mem
    allow_export::Bool = true
    ρ::Float64 = 100.0
    ε_abs::Float64 = 1e-4
    ε_rel::Float64 = 1e-3
    maxiter::Int = 200
    τ_ratio::Float64 = 2.0
    μ::Float64 = 10.0
    mpc_H::Int = 6
    mpc_step::Int = 1
    mpc_terminal_soc::Bool = true
    mpc_forecast_error::Float64 = 0.05
    stoch_S::Int = 3
    stoch_probabilities::Vector{Float64} = Float64[]
    stoch_H_oos::Int = 5

    function Scenario(
        name::String,
        feeder::Symbol,
        strategy::Symbol,
        seed::Int,
        T::Int,
        population::Symbol,
        price::Symbol,
        allow_export::Bool,
        ρ::Float64,
        ε_abs::Float64,
        ε_rel::Float64,
        maxiter::Int,
        τ_ratio::Float64,
        μ::Float64,
        mpc_H::Int,
        mpc_step::Int,
        mpc_terminal_soc::Bool,
        mpc_forecast_error::Float64,
        stoch_S::Int,
        stoch_probabilities::Vector{Float64},
        stoch_H_oos::Int,
    )
        # V5 input validation (threat T-08-05): a Scenario must never silently underdetermine
        # its run. Every selector is checked LOUDLY against its named valid set — throw, never
        # @assert (project convention; @assert is elided under -O).
        if feeder ∉ SCENARIO_VALID_FEEDERS
            throw(
                ArgumentError(
                    "Scenario: unknown feeder selector $(repr(feeder)); expected one of " *
                    "$(SCENARIO_VALID_FEEDERS)",
                ),
            )
        end
        if strategy ∉ SCENARIO_VALID_STRATEGIES
            throw(
                ArgumentError(
                    "Scenario: unknown strategy selector $(repr(strategy)); expected one of " *
                    "$(SCENARIO_VALID_STRATEGIES)",
                ),
            )
        end
        if price ∉ SCENARIO_VALID_PRICES
            throw(
                ArgumentError(
                    "Scenario: unknown price selector $(repr(price)); expected one of " *
                    "$(SCENARIO_VALID_PRICES)",
                ),
            )
        end
        if population ∉ SCENARIO_VALID_POPULATIONS
            throw(
                ArgumentError(
                    "Scenario: unknown population selector $(repr(population)); expected one " *
                    "of $(SCENARIO_VALID_POPULATIONS)",
                ),
            )
        end
        if T < 1
            throw(ArgumentError("Scenario: T must be ≥ 1 (day-ahead horizon); got T=$T"))
        end
        if seed < 1
            throw(
                ArgumentError(
                    "Scenario: seed must be ≥ 1 (a sane master-seed range); got seed=$seed",
                ),
            )
        end
        if maxiter < 1
            throw(
                ArgumentError(
                    "Scenario: maxiter must be ≥ 1 (ADMM iteration cap); got maxiter=$maxiter",
                ),
            )
        end
        # WR-01 fix: the ADMM float knobs were previously unvalidated, contradicting this same
        # constructor's own "checked LOUDLY" claim — a non-positive ρ/ε_abs/ε_rel/τ_ratio/μ
        # constructed silently and only failed (or silently misbehaved) much later, deep inside
        # solve_admm.
        if ρ <= 0
            throw(ArgumentError("Scenario: ρ must be > 0 (ADMM penalty); got ρ=$ρ"))
        end
        if ε_abs <= 0 || ε_rel <= 0
            throw(
                ArgumentError(
                    "Scenario: ε_abs/ε_rel must be > 0; got ε_abs=$ε_abs, ε_rel=$ε_rel",
                ),
            )
        end
        if τ_ratio <= 0 || μ <= 0
            throw(
                ArgumentError(
                    "Scenario: τ_ratio/μ must be > 0; got τ_ratio=$τ_ratio, μ=$μ",
                ),
            )
        end
        # D-12: Phase-21 MPC-only additive fields — same "checked LOUDLY" convention.
        if mpc_H < 1
            throw(ArgumentError("Scenario: window length H must be ≥ 1; got mpc_H=$mpc_H"))
        end
        if mpc_step < 1
            throw(
                ArgumentError("Scenario: step size must be ≥ 1; got mpc_step=$mpc_step"),
            )
        end
        if !(0 <= mpc_forecast_error < 1)
            throw(
                ArgumentError(
                    "Scenario: mpc_forecast_error must be a bounded fraction in [0, 1); got " *
                    "mpc_forecast_error=$mpc_forecast_error",
                ),
            )
        end
        # D-01/D-04/D-10: Phase-22 stochastic-only additive fields — same "checked LOUDLY"
        # convention as the D-12 MPC block above.
        if !(3 <= stoch_S <= 5)
            throw(
                ArgumentError(
                    "Scenario: stoch_S (in-sample scenario count) must be in the locked D-01 " *
                    "band 3 <= stoch_S <= 5; got stoch_S=$stoch_S",
                ),
            )
        end
        if !(5 <= stoch_H_oos <= 10)
            throw(
                ArgumentError(
                    "Scenario: stoch_H_oos (held-out scenario budget) must be in the locked " *
                    "D-10 band 5 <= stoch_H_oos <= 10; got stoch_H_oos=$stoch_H_oos",
                ),
            )
        end
        # D-04: an empty `stoch_probabilities` is the SENTINEL for "materialize default-uniform
        # at construction time" — never left as the ambiguous empty vector on a constructed
        # Scenario. A non-empty vector is the researcher's own explicit, non-uniform weighting
        # and is validated then honored VERBATIM (never silently replaced).
        if isempty(stoch_probabilities)
            stoch_probabilities = fill(1 / stoch_S, stoch_S)
        else
            if length(stoch_probabilities) != stoch_S
                throw(
                    ArgumentError(
                        "Scenario: stoch_probabilities must have length stoch_S=$stoch_S; " *
                        "got length $(length(stoch_probabilities))",
                    ),
                )
            end
            if !all(>(0), stoch_probabilities)
                throw(
                    ArgumentError(
                        "Scenario: every stoch_probabilities entry must be > 0; got " *
                        "$stoch_probabilities",
                    ),
                )
            end
            if !isapprox(sum(stoch_probabilities), 1; atol = 1e-8)
                throw(
                    ArgumentError(
                        "Scenario: stoch_probabilities must sum to 1 (atol=1e-8); got sum=" *
                        "$(sum(stoch_probabilities)) for $stoch_probabilities",
                    ),
                )
            end
            # Phase-22 review WR-01 fix: defensively COPY the caller's vector before it
            # reaches `new(...)`. `Scenario` is immutable, but a `Vector{Float64}` field
            # ALIASED to caller memory lets post-construction mutation (`p[1] = 99.0`)
            # silently destroy every invariant just validated above — the first (and only)
            # mutable-aliasing hole in an otherwise all-primitive struct, defeating the
            # "a Scenario can never silently underdetermine a run" claim (threat T-08-05)
            # for savename/hashing/reproducibility keyed to the validated value.
            stoch_probabilities = copy(stoch_probabilities)
        end
        return new(
            name,
            feeder,
            strategy,
            seed,
            T,
            population,
            price,
            allow_export,
            ρ,
            ε_abs,
            ε_rel,
            maxiter,
            τ_ratio,
            μ,
            mpc_H,
            mpc_step,
            mpc_terminal_soc,
            mpc_forecast_error,
            stoch_S,
            stoch_probabilities,
            stoch_H_oos,
        )
    end
end

export Scenario

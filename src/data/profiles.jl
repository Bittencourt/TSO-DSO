# src/data/profiles.jl
#
# SEAM: seeded first-order Markov profile generator (DATA-04).
# OWNER: plan 03-02.
#
# Data-layer ONLY — pure, JuMP-free reproducible profile synthesis. Given a
# row-stochastic transition matrix, an initial state, a state->value map, a
# horizon, and an EXPLICIT `AbstractRNG` (a `StableRNGs.LehmerRNG` seeded once by
# the caller — never the global RNG), produces inelastic-demand and PV profiles
# that regenerate bit-for-bit across Julia 1.10/1.11/1.12 (INFRA-04). Same seed ->
# identical profiles. These profiles enter the welfare solve as PARAMETERS, not
# decisions (RESEARCH Pattern 4; thesis §2.8).

using StableRNGs

# `StableRNGs` is a hard dependency (Project.toml) and re-uses the stdlib `Random`
# abstract interface. We reach the `AbstractRNG` supertype THROUGH `StableRNGs`
# (`StableRNGs.Random.AbstractRNG`) rather than `import Random`, because `Random` is
# not a direct dependency of `TSODSO` and adding it is out of this plan's scope.
# Accepting the `AbstractRNG` supertype (not a concrete `LehmerRNG`) keeps the walk
# generic, while the reproducibility contract is upheld by the CALLER seeding a
# `StableRNGs.LehmerRNG` — the only stream that is stable across Julia versions.

"""
    markov_path(P::AbstractMatrix, s0::Int, steps::Int, rng::StableRNGs.Random.AbstractRNG) -> Vector{Int}

Walk a first-order Markov chain for `steps` states, starting at state `s0`, using the
row-stochastic transition matrix `P` (`P[s, :]` is the categorical distribution over the
next state given the current state `s`). Returns the length-`steps` state path as a
`Vector{Int}` whose first entry is `s0` (thesis §2.8, data-generation only).

Each step draws a single `u = rand(rng)` and selects the next state by the standard
inverse-CDF (cumulative-sum) categorical draw over row `P[s, :]`. Threading an EXPLICIT
`rng` — a `StableRNGs.LehmerRNG` seeded once by the caller — is what makes the walk
reproducible bit-for-bit across Julia versions (INFRA-04, threat T-03-03). NEVER use the
global RNG / `Random.seed!` here: the stdlib stream is not stable across Julia minors
(RESEARCH Anti-Patterns).

# Arguments
- `P::AbstractMatrix` — square, row-stochastic transition matrix (each row sums to 1).
- `s0::Int` — initial state, a valid row index `1 ≤ s0 ≤ size(P, 1)`.
- `steps::Int` — number of states to emit (`≥ 1`); the returned path has this length.
- `rng::AbstractRNG` — an explicit RNG; seed a `StableRNGs.LehmerRNG(seed)` for reproducibility.

Throws `ArgumentError` (project convention: throw LOUDLY, never `@assert`, which `-O` can
elide — threat T-03-04) when `P` is not square, when any row does not sum to 1 within
tolerance, when `s0` is out of range, or when `steps < 1`.
"""
function markov_path(P::AbstractMatrix, s0::Int, steps::Int, rng::StableRNGs.Random.AbstractRNG)
    # --- Validate the transition matrix and walk parameters LOUDLY (threat T-03-04) ---
    n, m = size(P)
    if n != m
        throw(ArgumentError("markov_path: transition matrix P must be square; got size $(size(P))"))
    end
    if !(1 <= s0 <= n)
        throw(ArgumentError("markov_path: initial state s0=$s0 is out of range 1:$n"))
    end
    if steps < 1
        throw(ArgumentError("markov_path: steps must be ≥ 1; got $steps"))
    end
    rowsum_tol = 1e-8
    for s in axes(P, 1)
        rs = sum(@view P[s, :])
        if !isapprox(rs, one(rs); atol=rowsum_tol)
            throw(
                ArgumentError(
                    "markov_path: row $s of P must be row-stochastic (sum to 1 ±$rowsum_tol); " *
                    "got sum=$rs",
                ),
            )
        end
    end

    # --- First-order Markov walk (RESEARCH Pattern 4; thesis §2.8) ---
    path = Vector{Int}(undef, steps)
    s = s0
    @inbounds for k in 1:steps
        path[k] = s
        u = rand(rng)          # a single categorical draw per step (reproducible via rng)
        c = 0.0
        nxt = s
        for j in axes(P, 2)
            c += P[s, j]
            if u <= c
                nxt = j
                break
            end
        end
        s = nxt
    end
    return path
end

export markov_path

# --- Default state→value tables and transition matrices (documented, overridable) ---
#
# These defaults describe a small, well-mixing 3-state chain for each series so the
# generated profiles are non-trivial and reproducible. All magnitudes are in per-unit
# (RESEARCH Pitfall 4 / threat T-03-05): demand lives in a [0.3, 0.9] pu band; PV maps
# an irradiance state in [0.2, 1.0] pu through a diurnal daylight envelope, so night
# hours are ~0 and the peak stays ≤ 1 pu. Callers may override every matrix/table.

const _DEFAULT_DEMAND_TRANSITION = [
    0.6 0.3 0.1
    0.2 0.6 0.2
    0.1 0.3 0.6
]
const _DEFAULT_DEMAND_VALUES = [0.3, 0.6, 0.9]     # low / medium / high load (pu)

const _DEFAULT_PV_TRANSITION = [
    0.5 0.3 0.2
    0.2 0.5 0.3
    0.2 0.3 0.5
]
const _DEFAULT_PV_VALUES = [0.2, 0.6, 1.0]         # cloudy / partly / clear irradiance (pu)

"""
    _pv_diurnal_envelope(T::Int) -> Vector{Float64}

A deterministic daylight envelope over the `T`-step horizon: zero outside a daytime
window (roughly the middle half of the day) and a smooth half-sine bell peaking at solar
noon. Multiplying a non-negative irradiance state by this non-negative envelope keeps PV
output non-negative (threat T-03-05) and makes night hours ≈ 0, matching the thesis §2.8
convention of aggregating a sub-daily pattern to the hourly optimization resolution.
"""
function _pv_diurnal_envelope(T::Int)
    env = zeros(Float64, T)
    @inbounds for t in 1:T
        frac = (t - 0.5) / T                 # midpoint of step t within the day, in (0, 1)
        if 0.25 <= frac <= 0.75              # daylight window ≈ 06:00–18:00
            env[t] = sinpi((frac - 0.25) / 0.5)  # 0 at the window edges, 1 at solar noon
        end
    end
    return env
end

"""
    generate_profiles(; seed::Integer, T::Int=24,
                       P_demand=_DEFAULT_DEMAND_TRANSITION, demand_values=_DEFAULT_DEMAND_VALUES,
                       P_pv=_DEFAULT_PV_TRANSITION, pv_values=_DEFAULT_PV_VALUES,
                       s0_demand::Int=1, s0_pv::Int=1) -> NamedTuple

Generate seeded, reproducible hourly inelastic-demand and PV profiles of length `T`
(default `T=24`) as a `NamedTuple` `(; demand, pv)` of per-unit vectors (DATA-04, thesis
§2.8). Both series are produced PURELY — no JuMP, no decision variables — and enter the
welfare solve only as parameters (Assumption A4).

A single `StableRNGs.LehmerRNG(seed)` is created ONCE and threaded through [`markov_path`](@ref)
for both chains, so the whole result is deterministic in `seed`: two calls with the same
`seed` (and same arguments) return `==` vectors bit-for-bit (INFRA-04, threat T-03-03),
while a different `seed` produces a different profile. The RNG is never the global RNG /
`Random.seed!` — that stream is not stable across Julia versions (RESEARCH Anti-Patterns).

`demand` maps the demand state path through `demand_values` (per-unit load levels). `pv`
maps the PV state path through `pv_values` (per-unit irradiance levels) and scales it by a
diurnal daylight envelope, so PV is non-negative and ≈ 0 at night (threat T-03-05).

Throws `ArgumentError` when `T < 1`, when a `*_values` table length does not match its
transition matrix, or when any value table has a negative entry (a negative magnitude
would silently enter the solve — threat T-03-05). Matrix/range validation is delegated to
[`markov_path`](@ref).
"""
function generate_profiles(;
    seed::Integer,
    T::Int=24,
    P_demand::AbstractMatrix=_DEFAULT_DEMAND_TRANSITION,
    demand_values::AbstractVector=_DEFAULT_DEMAND_VALUES,
    P_pv::AbstractMatrix=_DEFAULT_PV_TRANSITION,
    pv_values::AbstractVector=_DEFAULT_PV_VALUES,
    s0_demand::Int=1,
    s0_pv::Int=1,
)
    if T < 1
        throw(ArgumentError("generate_profiles: T must be ≥ 1; got $T"))
    end
    if length(demand_values) != size(P_demand, 1)
        throw(
            ArgumentError(
                "generate_profiles: demand_values length $(length(demand_values)) must match " *
                "P_demand states $(size(P_demand, 1))",
            ),
        )
    end
    if length(pv_values) != size(P_pv, 1)
        throw(
            ArgumentError(
                "generate_profiles: pv_values length $(length(pv_values)) must match " *
                "P_pv states $(size(P_pv, 1))",
            ),
        )
    end
    if any(<(0), demand_values)
        throw(ArgumentError("generate_profiles: demand_values must be non-negative (threat T-03-05)"))
    end
    if any(<(0), pv_values)
        throw(ArgumentError("generate_profiles: pv_values must be non-negative (threat T-03-05)"))
    end

    # Seed ONCE, thread the SAME rng through both walks — this is what makes the full
    # returned NamedTuple deterministic in `seed` (INFRA-04). markov_path validates each
    # matrix (square + row-stochastic) and the initial states.
    rng = StableRNGs.LehmerRNG(seed)
    demand_states = markov_path(P_demand, s0_demand, T, rng)
    pv_states = markov_path(P_pv, s0_pv, T, rng)

    demand = [float(demand_values[s]) for s in demand_states]
    envelope = _pv_diurnal_envelope(T)
    pv = [float(pv_values[s]) * envelope[t] for (t, s) in enumerate(pv_states)]

    return (; demand, pv)
end

export generate_profiles

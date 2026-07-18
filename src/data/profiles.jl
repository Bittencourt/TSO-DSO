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

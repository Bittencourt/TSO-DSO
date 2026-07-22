# src/pricing/checks.jl
#
# SEAM: economic-direction price checks (PRICE-05).
# OWNER: plan 05-04.
#
# Empty (comment-only) stub wired onto the include graph in plan 05-01. Plan 05-04 fills
# it and declares its own `export`s. It will export:
#   - `economic_direction_checks(ctx; ...)` — assert the DLMP moves in the ECONOMICALLY
#     CORRECT direction in the canonical regimes: prices rise into a congestion / import
#     window and fall (can go negative) in a PV-glut / reverse-flow / over-voltage window,
#     i.e. the congestion and voltage DLMP components carry the expected sign.
#
# Consumes the decomposed DLMP (plan 05-02) — pure post-processing over a solved ctx.
#
# INDEPENDENCE (Wave-2 parallelism): this module reads the DADP DIRECTLY from the registered
# `:balance_p` active nodal-balance dual (`dual.(ctx.constraints[:balance_p])`) — the SAME
# primitive `extract_dlmp` uses — so it does NOT depend on `dlmp.jl` (owned by the parallel
# plan 05-02) and can be developed/tested in the same wave.

using JuMP

"""
    economic_direction_checks(ctx::ModelContext; λ₀, regime=:auto, bus=nothing,
                              dadp=nothing, T=ctx.meta[:T], tol=1e-6)
        -> (; pv_glut_ok::Bool, congestion_ok::Bool)

Assert the distribution price (the DADP `λ_j[t]` = dual of the registered `:balance_p` active
nodal balance) moves in the ECONOMICALLY-CORRECT direction relative to the wholesale price
`λ₀` (PRICE-05). This is the qualitative economic-correctness net that catches a BACKWARDS
price signal — an internally-consistent (sum-to-price / surplus-identity) yet economically
INVERTED price from a dual-sign or attribution bug — which the additive checks cannot see.

Two canonical regimes (thesis Fig 4.5 / 4.6, node 9):

  - `:pv_glut`     — at a PV-glut / reverse-flow / over-voltage window the DADP falls BELOW
    wholesale (`min_{j,t}(λ_j[t] − λ₀[t]) < −tol`); local generation is worth
    LESS than the wholesale reference (Fig 4.5, node 9 @ 15:00 < MEM).
  - `:congestion`  — at a head-branch congestion window the DADP rises ABOVE wholesale
    (`max_{j,t}(λ_j[t] − λ₀[t]) > tol`); constrained delivery makes local
    power worth MORE than the reference (Fig 4.6, node 9 @ 22:00 > MEM).

The DADP is read DIRECTLY as `dual.(ctx.constraints[:balance_p])` (a `bus × time` matrix — the
same primitive `extract_dlmp` uses), keeping this module INDEPENDENT of `dlmp.jl` for parallel
Wave-2 execution. The per-hour comparison is aligned `λ_j[t]` vs `λ₀[t]`, so the extremum over
the horizon lands AT the regime-active hours without hard-coding them (non-vacuous: the
extremum must exceed `tol` in the expected direction).

# Arguments / keywords

  - `λ₀::AbstractVector` — the length-`T` wholesale price reference.
  - `regime::Symbol = :auto` — `:pv_glut` asserts the below-wholesale relation and THROWS an
    `ArgumentError` on a backwards signal; `:congestion` asserts the above-wholesale relation
    and throws on a backwards signal; `:auto` only reports the observed directions (no throw).
  - `bus::Union{Nothing,Integer} = nothing` — restrict the scan to one bus; default scans every
    NON-root bus (the frontier/root DADP just tracks `λ₀`).
  - `dadp = nothing` — optional DADP override (a `Vector` single-bus series or a `bus × time`
    `Matrix`); when supplied it REPLACES the `:balance_p` read. Used to prove non-vacuity (feed a
    sign-flipped DADP and watch the check throw); the default path always reads `:balance_p`.
  - `T::Integer = ctx.meta[:T]` — horizon; `length(λ₀) == T` is a loud shape guard (T-05-11).
  - `tol::Real = 1e-6` — strict-inequality slack separating a genuine excursion from dual noise.

Returns `(; pv_glut_ok, congestion_ok)` — whether a strict below-/above-wholesale excursion
was observed. THROWS `ArgumentError` (never `@assert`, which `-O` can elide) on a horizon shape
mismatch, an unknown `regime`, a missing `:balance_p` registration, or — for an explicit
`regime` — a backwards price signal. Run only on a `ctx` produced by `solve_welfare` (its PF-04
exactness gate is what makes the dual trustworthy; threat T-05-01).
"""
function economic_direction_checks(
    ctx::ModelContext;
    λ₀::AbstractVector,
    regime::Symbol = :auto,
    bus::Union{Nothing, Integer} = nothing,
    dadp::Union{Nothing, AbstractVecOrMat} = nothing,
    T::Integer = ctx.meta[:T],
    tol::Real = 1e-6,
)
    regime in (:auto, :pv_glut, :congestion) || throw(
        ArgumentError(
            "economic_direction_checks: regime must be :auto, :pv_glut, or :congestion; got :$regime",
        ),
    )
    # T-05-11 shape guard: a λ₀ / horizon mismatch would mis-align the per-hour comparison —
    # fail LOUDLY before any indexing (never @assert, threat convention).
    length(λ₀) == T || throw(
        ArgumentError(
            "economic_direction_checks: λ₀ has length $(length(λ₀)), expected T=$T (shape guard, T-05-11)",
        ),
    )

    # DADP source. Default: read the registered active-balance dual DIRECTLY (the same
    # primitive extract_dlmp uses) — this is what keeps the module independent of dlmp.jl.
    # An explicit `dadp` override (used to prove non-vacuity with a sign-flipped price) bypasses
    # the read but leaves the default path — the one that matters — reading balance_p.
    Λ = if dadp === nothing
        haskey(ctx.constraints, :balance_p) || throw(
            ArgumentError(
                "economic_direction_checks: ctx has no registered :balance_p — pass a ctx " *
                "produced by solve_welfare (its exactness-gated DADP dual; threat T-05-01)",
            ),
        )
        balance_p = ctx.constraints[:balance_p]
        size(balance_p, 2) == T || throw(
            ArgumentError(
                "economic_direction_checks: :balance_p has $(size(balance_p, 2)) time columns, expected T=$T",
            ),
        )
        dual.(balance_p)                       # bus × time matrix of λ_j[t] (the DADP)
    elseif dadp isa AbstractVector
        reshape(collect(float.(dadp)), 1, :)   # a single-bus DADP series
    else
        collect(float.(dadp))                  # a bus × time override matrix
    end
    size(Λ, 2) == T || throw(
        ArgumentError(
            "economic_direction_checks: DADP has $(size(Λ, 2)) time columns, expected T=$T",
        ),
    )

    Np = size(Λ, 1)
    # Exclude the frontier/root bus when reading from the true balance (its DADP just tracks
    # λ₀, contributing a ~0 deviation). With a `dadp` override we cannot know the root, so scan
    # all supplied rows.
    feeder = get(ctx.meta, :feeder, nothing)
    root = (dadp === nothing && feeder !== nothing) ? feeder.root : 0
    buses = bus === nothing ? [j for j in 1:Np if j != root] : [Int(bus)]
    isempty(buses) && throw(
        ArgumentError(
            "economic_direction_checks: no buses to inspect (bus=$bus, Np=$Np, root=$root)",
        ),
    )

    # Extremal per-hour deviation λ_j[t] − λ₀[t] over the scanned buses/hours. The MOST NEGATIVE
    # excursion is the PV-glut signature; the MOST POSITIVE is the congestion signature.
    below = Inf     # min deviation (below-wholesale, PV glut)
    above = -Inf    # max deviation (above-wholesale, congestion)
    for j in buses, t in 1:T
        d = Λ[j, t] - λ₀[t]
        below = min(below, d)
        above = max(above, d)
    end

    pv_glut_ok = below < -tol
    congestion_ok = above > tol

    if regime === :pv_glut && !pv_glut_ok
        throw(
            ArgumentError(
                "economic_direction_checks: BACKWARDS price signal (PV glut) — expected the " *
                "DADP to fall BELOW wholesale λ₀ at over-generation (thesis Fig 4.5, node 9 @ " *
                "15:00 < MEM), but min(λ_j − λ₀) = $below is not < −tol (tol=$tol)",
            ),
        )
    elseif regime === :congestion && !congestion_ok
        throw(
            ArgumentError(
                "economic_direction_checks: BACKWARDS price signal (congestion) — expected the " *
                "DADP to rise ABOVE wholesale λ₀ at head-branch congestion (thesis Fig 4.6, " *
                "node 9 @ 22:00 > MEM), but max(λ_j − λ₀) = $above is not > tol (tol=$tol)",
            ),
        )
    end

    return (; pv_glut_ok, congestion_ok)
end

export economic_direction_checks

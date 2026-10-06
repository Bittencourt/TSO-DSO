# src/planning/master_integer.jl
#
# SEAM: build-once binary-expansion MILP Benders master.
#
# A NEW, COMPLETELY SEPARATE builder alongside the continuous `build_master`
# (master.jl) — NOT an `integer=false` flag on the existing builder. The
# continuous v2.0 path stays bit-for-bit identical BY CONSTRUCTION: this file never
# touches master.jl, so the continuous-path goldens remain trivially safe to diff
# against.
#
# WHY A NEW STRUCT, NOT `BendersMaster` REUSED: `add_optimality_cut!`/`add_feasibility_cut!` dispatch on the CONCRETE
# `BendersMaster` type, and that struct has no slot for the raw binary vector `b`
# the Laporte-Louveaux (LL) cut needs — the LL cut is written directly over the
# raw 0/1 decision variables, never over the derived continuous expression
# `y_inv`. `BendersMasterInteger` adds that slot and the
# matching `add_optimality_cut!`/`add_feasibility_cut!` overloads for this type.
#
# `L = α_op_lb + α_x_lb` (the finite epigraph lower bound of `build_master`, reused
# verbatim in the "reuse the seam" spirit) doubles as the Laporte-Louveaux
# cut's required global lower bound `L` on the recourse `Q(y_inv)` — pinned once
# at construction so the cut code never re-derives it.

using JuMP

"""
    BendersMasterInteger{Y,Z,AOP,AX,B}

The built-ONCE binary-expansion MILP Benders master: a
completely separate sibling of [`BendersMaster`](@ref) — the leader's
own MILP over K raw binary variables `b`, a DERIVED continuous investment
expression `y_inv` (an `AffExpr` over `b`), coupling flow `z[t]`, and the
SAME two epigraph variables `α_op`/`α_x` (discipline reused
unchanged) — with cuts appended as persistent `@constraint` rows, never
rebuilt, mirroring `BendersMaster`'s own mutate-without-rebuild idiom.

# Fields

  - `model::Model` — the master MILP, built ONCE via
    `Model(select_optimizer(MILP()))`; mutated ONLY by appending new
    `@constraint` rows (cuts), never rebuilt.

  - `y_inv::Y` — the DERIVED continuous investment expression
    `(y_max/2^K) * Σ_k 2^(k-1) b_k` (an `AffExpr`). Used in
    constraints/objective exactly like the continuous master's `y_inv`
    variable; NEVER used to reconstruct the LL cut's `S^ν` (use
    `b` for that).

  - `z::Z` — the length-T coupling flow (`0 <= z[t] <= y_inv`), identical box
    shape to `BendersMaster`.

  - `α_op::AOP` — the oracle's own epigraph variable (`α_op >= α_op_lb`).

  - `α_x::AX` — the follower's own epigraph variable (`α_x >= α_x_lb`).

  - `b::B` — the raw `Vector{VariableRef}` of K binaries. Needed because the
    Laporte-Louveaux cut is written over `b`, never over the
    derived `y_inv` (the derived `y_inv` is an expression, not a variable).

  - `K::Int` — the number of binary blocks in the expansion.

  - `T::Int` — the horizon.

  - `c_y::Float64` — the leader's flexibility-investment unit cost.

  - `y_max::Float64` — the nominal investment ceiling. NOTE: the
    all-ones corner reaches `y_max*(1 - 2^-K)`, NOT `y_max` itself — see
    [`build_master_integer`](@ref)'s own docstring for the full lattice
    derivation.

  - `L::Float64` — the pinned `α_op_lb + α_x_lb`, stored once at construction
    so the Laporte-Louveaux cut never has to re-derive the recourse's
    global lower bound.

  - `lb_slack::NamedTuple{(:op, :x), Tuple{Float64, Float64}}` — ALWAYS `(; op=0.0, x=0.0)`
    — port of `BendersMaster.lb_slack`'s own
    field (master.jl). An earlier design populated this identically to the
    continuous master's own field (how far ABOVE its derived relaxed optimum each
    declared epigraph lower bound was ALLOWED to be when `build_master_integer` accepted
    it); the build-time clamp supersedes that design: `build_master_integer` now CLAMPS any
    accepted-but-slack explicit bound DOWN to the certified `:auto`-equivalent minimum at
    build time (see `lb_clamped` below), so this field is always zero and is kept only so
    `_accepted_lb_slack(::BendersMasterInteger, label)` keeps a uniform interface,
    dispatched automatically by `benders.jl`'s pre-existing generic
    `_accepted_lb_slack` fallback mechanism.

  - `cuts::Vector{Any}` — a bookkeeping log of every cut appended, mirroring
    `BendersMaster.cuts`'s exact convention.

  - `visited::Dict{Vector{Int}, Vector{Float64}}` — empty at construction.
    The anti-stall no-good fallback populates this, mapping
    each previously-visited binary corner to the LAST `z` trial the master
    picked there — declared here so the struct's full field list is fixed in
    one place.

    **Changed from `Set{Vector{Int}}`
    to `Dict{Vector{Int}, Vector{Float64}}`:** the original `Set`-membership
    "has this corner EVER been visited before" test treats every legitimate
    cutting-plane REFINEMENT revisit (the master picking the SAME corner
    again with a DIFFERENT, better-converged `z`, exactly how a Benders-style
    outer approximation is SUPPOSED to close in on a corner's true argmin) as
    an indistinguishable "stall" — banning the corner via `add_nogood_cut!`
    before the incumbent `UB` has had a chance to converge to that corner's
    true minimized value, including (confirmed empirically on the
    canonical fixture) the GLOBALLY OPTIMAL corner itself. Once a corner is
    banned it is EXCLUDED from the master's feasible region forever (unlike
    an LL cut, which only tightens `θ`'s bound, `add_nogood_cut!`'s row
    removes the binary vector from the feasible set entirely) — banning the
    true optimum before its incumbent value is captured makes it
    PERMANENTLY UNREACHABLE, no matter how many further iterations run. The
    `Dict` records each corner's LAST `z` trial so [`apply_integer_cuts!`](@ref)
    can distinguish a GENUINE stall (the SAME corner revisited with an
    UNCHANGED `z`, i.e. the cutting-plane refinement has already reached its
    own fixed point there and no further progress is possible) from ordinary,
    expected refinement progress (a DIFFERENT `z`) — see
    [`apply_integer_cuts!`](@ref)'s own docstring for the full diagnosis.

  - `lb_clamped::NamedTuple{(:op, :x), Tuple{Float64, Float64}}` — verbatim port of `BendersMaster.lb_clamped`'s own field (master.jl)
    — how far DOWN an accepted explicit epigraph lower bound was moved to reach the
    certified `:auto`-equivalent minimum. `0.0` for every pre-existing call site, `:auto`,
    or an unvalidated explicit bound; positive only when build-time clamping actually
    fired.
"""
struct BendersMasterInteger{Y, Z, AOP, AX, B}
    model::Model
    y_inv::Y
    z::Z
    α_op::AOP
    α_x::AX
    b::B
    K::Int
    T::Int
    c_y::Float64
    y_max::Float64
    L::Float64
    lb_slack::NamedTuple{(:op, :x), Tuple{Float64, Float64}}
    cuts::Vector{Any}
    visited::Dict{Vector{Int}, Vector{Float64}}
    lb_clamped::NamedTuple{(:op, :x), Tuple{Float64, Float64}}
end

"""
    build_master_integer(; T::Int, K::Int = 4, c_y::Real, y_max::Real,
                         α_op_lb::Union{Symbol,Real} = :auto,
                         α_x_lb::Union{Symbol,Real} = :auto,
                         bounds_ctx::Union{Nothing,NamedTuple} = nothing,
                         rejection_tol::Real = ALPHA_LB_REJECTION_TOL) -> BendersMasterInteger

Build the binary-expansion MILP Benders master EXACTLY ONCE:

 1. Boundary guards — `T >= 1`, `K >= 1`, `y_max > 0`, `c_y >= 0` — each throws
    `ArgumentError` naming the offending value, BEFORE any `@variable`/
    `@objective` assembly (mirrors `build_master`'s own discipline, master.jl).

 2. `model = Model(select_optimizer(MILP()))`, never
    `Model(HiGHS.Optimizer)` directly.

 3. `b[1:K]` binary variables and the DERIVED continuous expression
    `y_inv = (y_max/2^K) * Σ_k 2^(k-1) b_k`.

    **Lattice/endpoint artifact — documented here, not "fixed" elsewhere:**
    dividing by `2^K` (NOT `2^K - 1`) means the reachable investment set is the
    K=4 default's `{0, y_max/16, 2*y_max/16, ..., 15*y_max/16}` — for
    `y_max = 8.0` that is `{0, 0.5, 1.0, ..., 7.5}`, a step of `0.5`. The
    all-ones corner (`b = ones(K)`) reaches `y_max*(1 - 2^-K)`, e.g.
    `8.0*(1 - 1/16) = 7.5` — **`y_max` itself is never attainable.** This is a
    deliberate, accepted consequence of the round-step-size convention,
    not a bug to be corrected by changing the divisor to `2^K - 1`.

 4. `z[1:T]`, `α_op >= α_op_lb_resolved`, `α_x >= α_x_lb_resolved` — SAME
    finite-lower-bound-at-build-time discipline as `build_master`,
    reused for the MILP master.

 5. `box_lo[t]: z[t] >= 0`, `box_hi[t]: z[t] <= y_inv` — identical box shape to
    `build_master` (`y_inv` here is an `AffExpr`; JuMP supports this in
    `@constraint` RHS unchanged).

 6. `Min c_y*y_inv + α_op + α_x` — identical objective shape to `build_master`.

**`α_op_lb`/`α_x_lb` gain the SAME `:auto`/validated-explicit/
opt-out `bounds_ctx` machinery `build_master` already has —
ported VERBATIM from `build_master` (master.jl), reusing
`derive_alpha_op_lb`/`alpha_op_lb_derivation`/`derive_alpha_x_lb`/
`alpha_x_lb_derivation`/`alpha_lb_margin` unchanged (no duplication). Every
pre-existing call site (explicit `Real` `α_op_lb`/`α_x_lb`, no `bounds_ctx`) stays
BIT-FOR-BIT IDENTICAL — the `bounds_ctx === nothing` branch never calls the derivation
helpers. See `build_master`'s own docstring for the full three-way
`bounds_ctx.follower_kwargs` dispatch (`NamedTuple` / `FollowerLP` / `nothing`) this
function reuses verbatim.** An ACCEPTED bound that lies strictly above the certified
`:auto`-equivalent minimum `d.bound` (inside the acceptance slack band) is CLAMPED DOWN
to `d.bound` at build time, never installed at the
raw requested value — the clamp amount is recorded on
`BendersMasterInteger.lb_clamped`, the identical verbatim port of
`build_master`'s own clamp transformation.

Returns a [`BendersMasterInteger`](@ref) with an empty `cuts` log, an empty
`visited` set, `lb_slack` ALWAYS `(; op=0.0, x=0.0)` (no runtime
floor slack is ever needed again), a populated `lb_clamped` field recording any
build-time clamp, and `L = α_op_lb_resolved + α_x_lb_resolved` (computed from the
CLAMPED resolved values) pinned for reuse by the Laporte-Louveaux cut.
"""
function build_master_integer(;
    T::Int,
    K::Int = 4,
    c_y::Real,
    y_max::Real,
    α_op_lb::Union{Symbol, Real} = :auto,
    α_x_lb::Union{Symbol, Real} = :auto,
    bounds_ctx::Union{Nothing, NamedTuple} = nothing,
    rejection_tol::Real = ALPHA_LB_REJECTION_TOL,
)
    # Boundary guards FIRST — fail here, not deep in objective assembly (mirrors
    # build_master's own discipline, master.jl).
    T >= 1 || throw(ArgumentError("build_master_integer needs T >= 1, got T=$T"))
    K >= 1 || throw(ArgumentError("build_master_integer needs K >= 1, got K=$K"))
    y_max > 0 || throw(ArgumentError("build_master_integer needs y_max > 0, got $y_max"))
    c_y >= 0 || throw(ArgumentError("build_master_integer needs c_y >= 0, got $c_y"))

    (α_op_lb === :auto || α_x_lb === :auto) &&
        bounds_ctx === nothing &&
        throw(
            ArgumentError(
                "build_master_integer: α_op_lb/α_x_lb = :auto requires bounds_ctx",
            ),
        )
    # (Ported from build_master.) The keyword type already restricts these to
    # Union{Symbol,Real}, so the guard must reject every Symbol OTHER than :auto (a typo
    # such as :atuo used to fall through to a MethodError deep in the resolution).
    (α_op_lb isa Real || α_op_lb === :auto) || throw(
        ArgumentError(
            "build_master_integer: α_op_lb must be :auto or a Real, got $(repr(α_op_lb))",
        ),
    )
    (α_x_lb isa Real || α_x_lb === :auto) || throw(
        ArgumentError(
            "build_master_integer: α_x_lb must be :auto or a Real, got $(repr(α_x_lb))",
        ),
    )

    # (Ported from build_master.) The acceptance slack actually granted to each
    # declared bound, carried to BendersMasterInteger.lb_slack for _accepted_lb_slack.
    # Both ALWAYS stay 0.0 — any accepted bound
    # is clamped down to a genuine certified minimum at build time (see clamp_op/clamp_x
    # below), so no runtime floor slack is ever needed again.
    slack_op = 0.0
    slack_x = 0.0
    # How far DOWN an accepted explicit bound was
    # moved to reach the certified minimum (0.0 unless clamping actually fired).
    clamp_op = 0.0
    clamp_x = 0.0

    # Resolution of α_op_lb. :auto always derives; an explicit bound is
    # validated ONLY when bounds_ctx is supplied (the opt-in design decision) — the
    # bounds_ctx === nothing branch is the bit-for-bit identical, zero-regression path.
    α_op_lb_resolved = if α_op_lb === :auto
        derive_alpha_op_lb(
            bounds_ctx.feeder,
            bounds_ctx.pf,
            bounds_ctx.aggregators;
            λ₀ = bounds_ctx.λ₀,
            T = T,
            y_max = y_max,
        )
    elseif bounds_ctx !== nothing
        d = alpha_op_lb_derivation(
            bounds_ctx.feeder,
            bounds_ctx.pf,
            bounds_ctx.aggregators;
            λ₀ = bounds_ctx.λ₀,
            T = T,
            y_max = y_max,
        )
        # Compare against the UN-margined optimum plus a measured, scale-aware
        # slack (see ALPHA_LB_REJECTION_TOL's derivation) — never `bound + tol`, which
        # cancelled to the raw optimum and left no tolerance at all.
        slack = alpha_lb_margin(d.optimum, d.gap; floor = rejection_tol)
        α_op_lb > d.optimum + slack && throw(
            ArgumentError(
                "build_master_integer: α_op_lb=$α_op_lb exceeds the derived relaxed " *
                "minimum $(d.optimum) by more than the measured slack $slack (duality " *
                "gap $(d.gap)) — would silently produce a wrong-converged answer",
            ),
        )
        # Clamp an accepted-but-slack bound DOWN to
        # the certified :auto-equivalent minimum d.bound, rather than installing the raw
        # requested value and widening the runtime certificate (rejected: measured to break
        # the project's flagship pinned goldens).
        α_eff = min(Float64(α_op_lb), d.bound)
        α_eff < Float64(α_op_lb) && @warn(
            "build_master_integer: α_op_lb=$α_op_lb lies within the acceptance slack " *
            "above the derived minimum $(d.bound); installing the certified bound " *
            "$α_eff instead (clamped to the certified minimum)",
            maxlog = 1,
        )
        clamp_op = Float64(α_op_lb) - α_eff   # >= 0.0; the amount clamped (0.0 if none)
        slack_op = 0.0   # The installed bound is a genuine certified lower
        # bound by construction -- no runtime floor slack needed
        α_eff
    else
        Float64(α_op_lb)
    end

    # Resolution of α_x_lb. Three-way dispatch on
    # bounds_ctx.follower_kwargs: a NamedTuple, a FollowerLP, or nothing (no sound
    # derivation for this follower type — skip the rejection check, accept the explicit
    # value as-is; :auto in this branch is a hard error, since there is nothing to
    # derive from).
    _fk = bounds_ctx === nothing ? nothing : bounds_ctx.follower_kwargs
    α_x_lb_resolved = if α_x_lb === :auto
        _fk === nothing && throw(
            ArgumentError(
                "build_master_integer: α_x_lb=:auto requires bounds_ctx.follower_kwargs " *
                "to be a NamedTuple or a FollowerLP — got `nothing` (no sound derivation " *
                "for this follower type)",
            ),
        )
        _fk isa NamedTuple ? derive_alpha_x_lb(; _fk..., T = T) : derive_alpha_x_lb(_fk)
    elseif bounds_ctx !== nothing && _fk !== nothing
        d =
            _fk isa NamedTuple ? alpha_x_lb_derivation(; _fk..., T = T) :
            alpha_x_lb_derivation(_fk)
        slack = alpha_lb_margin(d.optimum, d.gap; floor = rejection_tol)
        α_x_lb > d.optimum + slack && throw(
            ArgumentError(
                "build_master_integer: α_x_lb=$α_x_lb exceeds the derived relaxed " *
                "minimum $(d.optimum) by more than the measured slack $slack (duality " *
                "gap $(d.gap)) — would silently produce a wrong-converged answer",
            ),
        )
        # Mirror the α_op_lb clamp above.
        α_eff = min(Float64(α_x_lb), d.bound)
        α_eff < Float64(α_x_lb) && @warn(
            "build_master_integer: α_x_lb=$α_x_lb lies within the acceptance slack " *
            "above the derived minimum $(d.bound); installing the certified bound " *
            "$α_eff instead (clamped to the certified minimum)",
            maxlog = 1,
        )
        clamp_x = Float64(α_x_lb) - α_eff   # >= 0.0; the amount clamped (0.0 if none)
        slack_x = 0.0   # The installed bound is a genuine certified lower
        # bound by construction -- no runtime floor slack needed
        α_eff
    else
        # bounds_ctx === nothing (opt-out, bit-for-bit identical path), OR _fk === nothing (a
        # pre-built follower with no sound derivation) — accept the explicit value
        # unvalidated at build time; the universal runtime floor guard (benders.jl)
        # remains the defense-in-depth check.
        Float64(α_x_lb)
    end

    model = Model(select_optimizer(MILP()))   # never Model(HiGHS.Optimizer) directly

    @variable(model, b[1:K], Bin)
    # Divide by 2^K (NOT 2^K - 1) — all-ones reaches y_max*(1-2^-K), never
    # y_max itself. Documented artifact, not a bug (see docstring above).
    y_inv = @expression(model, (y_max / 2^K) * sum(2^(k - 1) * b[k] for k in 1:K))

    @variable(model, z[t = 1:T])
    # (Reused verbatim from build_master.) FINITE epigraph lower bounds
    # declared AT BUILD TIME — the very first (zero-cut) solve depends on this.
    @variable(model, α_op >= α_op_lb_resolved)
    @variable(model, α_x >= α_x_lb_resolved)

    # (Reused verbatim from build_master.) z is a physically nonnegative
    # delivered import flow, bounded above by the leader's own (derived) investment.
    @constraint(model, box_lo[t = 1:T], z[t] >= 0)
    @constraint(model, box_hi[t = 1:T], z[t] <= y_inv)

    @objective(model, Min, c_y * y_inv + α_op + α_x)

    return BendersMasterInteger(
        model,
        y_inv,
        z,
        α_op,
        α_x,
        b,
        K,
        T,
        Float64(c_y),
        Float64(y_max),
        Float64(α_op_lb_resolved + α_x_lb_resolved),
        (; op = Float64(slack_op), x = Float64(slack_x)),
        Any[],
        Dict{Vector{Int}, Vector{Float64}}(),
        (; op = Float64(clamp_op), x = Float64(clamp_x)),
    )
end

"""
    _accepted_lb_slack(master::BendersMasterInteger, label::Symbol) -> Float64

Port of `_accepted_lb_slack(::BendersMaster, ...)` (benders.jl) for
the integer master: `master.lb_slack[label]`, the build-time acceptance slack of the
declared `:op`/`:x` epigraph lower bound. This is an ADDITIVE new method on the
generic `_accepted_lb_slack` function already defined in `benders.jl` — Julia's dispatch
picks this specific method up automatically for a `BendersMasterInteger`, falling back to
the generic `0.0` for any other master type without a `lb_slack` record.
"""
_accepted_lb_slack(master::BendersMasterInteger, label::Symbol) =
    getproperty(master.lb_slack, label)

"""
    solve_master!(master::BendersMasterInteger; max_attempts::Int = 4,
                 attempts_out::Union{Nothing,Ref{Int}} = nothing) -> NamedTuple

Re-solve the built-ONCE [`BendersMasterInteger`](@ref) via `solve_with_retry!`
— NEVER the choke point called directly.

**Deliberate divergence from `solve_master!(::BendersMaster; ...)`'s
`dual = true` default: this method calls `solve_with_retry!` with
`dual = false`.** HiGHS/MOI does not report a meaningful dual status for a
genuine MIP solve — branch-and-bound has no LP dual at the integer solution in
general — so passing `dual = true` (the continuous master's default) would
make `is_solved_and_feasible` spuriously fail on every solve of this MILP
master. This is a deliberate, documented divergence justified by the
problem-class difference (LP vs. genuine MIP), NOT an accidental relaxation of
the choke point's "strict solve" discipline — exercised by this file's own zero-cut
first-solve regression test.

Returns `(; y, z, LB, b)` where `y = value(master.y_inv)`,
`z = value.(master.z)`, `LB = objective_value(master.model)`, and
`b = value.(master.b)` — the extra `b` field (absent from the continuous
`solve_master!`'s return) is read ONLY by the integer-specific
cut/loop code via duck typing; it never needs to exist on the continuous
return.
"""
function solve_master!(
    master::BendersMasterInteger;
    max_attempts::Int = 4,
    attempts_out::Union{Nothing, Ref{Int}} = nothing,
)
    # solve_with_retry! is the SOLE solve entry point on the master, mirroring
    # the continuous master's own discipline. dual=false: see docstring above — a
    # genuine MIP solve has no meaningful LP dual at the integer solution.
    solve_with_retry!(
        master.model;
        max_attempts = max_attempts,
        dual = false,
        attempts_out = attempts_out,
    )

    return (;
        y = value(master.y_inv),
        z = value.(master.z),
        LB = _objective(master.model),
        b = value.(master.b),
    )
end

"""
    add_optimality_cut!(master::BendersMasterInteger, epigraph::Symbol, cost_k::Real,
                        grad_k::AbstractVector{<:Real},
                        z_k::AbstractVector{<:Real}) -> BendersMasterInteger

Append ONE new persistent optimality-cut row to `master.model` — NEVER a
rebuild — reusing the EXACT SAME algebra as `add_optimality_cut!(::BendersMaster, ...)`
(`master.jl`):

```
α >= cost_k + Σ_t grad_k[t] * (z[t] - z_k[t])
```

where `α` is `master.α_op` if `epigraph === :op` or `master.α_x` if `epigraph === :x`.

**Why this is a plain transcription, not a re-derivation:** `Q(y_inv) = min_{0<=z<=y_inv}[α_op(z)+α_x(z)]` is a partial
minimization of a jointly-convex function over a jointly-convex, monotonically
expanding feasible set, hence `Q` is convex (and monotone non-increasing) in the
*continuous relaxation* of `y_inv`. Because `y_inv` is a *linear* function of the
binary vector `b` (`y_inv = (y_max/2^K)*Σ 2^(k-1) b_k`), `Q(b)` is convex over
`[0,1]^K` too, and any subgradient cut on `z` derived at a trial `z_k` is a
globally valid supporting hyperplane over the ENTIRE continuous relaxation —
hence valid at every one of the `2^K` binary corners of `b`. This is exactly the
classical justification behind Geoffrion's Generalized Benders Decomposition
(GBD, 1972): integer/complicating master variables coupled *linearly* to a
convex continuous recourse always admit valid cuts from the recourse's
continuous relaxation. The continuous `:op`/`:x` cuts are therefore REUSED
unmodified alongside the Laporte-Louveaux integer cut, never
replaced by it.

Throws `ArgumentError` under the SAME conditions as the continuous method
(bad `epigraph`, length mismatch against `master.T`, or any non-finite
`cost_k`/`grad_k`/`z_k` entry) — a malformed cut triple must fail loudly BEFORE
corrupting the master's persistent constraint set (same discipline,
reused verbatim).

Logs `(; kind = :optimality, epigraph, cost_k, grad_k, z_k)` to `master.cuts`
(the SAME NamedTuple shape as `BendersMaster.cuts`, so `master.cuts` is
filterable by `kind` uniformly across both master types) and returns `master`.
"""
function add_optimality_cut!(
    master::BendersMasterInteger,
    epigraph::Symbol,
    cost_k::Real,
    grad_k::AbstractVector{<:Real},
    z_k::AbstractVector{<:Real},
)
    epigraph in (:op, :x) || throw(
        ArgumentError("add_optimality_cut!: epigraph must be :op or :x, got $epigraph"),
    )
    length(grad_k) == master.T ||
        throw(ArgumentError("grad_k has length $(length(grad_k)), expected T=$(master.T)"))
    length(z_k) == master.T ||
        throw(ArgumentError("z_k has length $(length(z_k)), expected T=$(master.T)"))
    # finiteness guard — a NaN/Inf cut row would permanently poison the
    # build-once master (rows are never removed); fail loudly BEFORE @constraint.
    isfinite(cost_k) ||
        throw(ArgumentError("add_optimality_cut!: cost_k must be finite, got $cost_k"))
    all(isfinite, grad_k) || throw(
        ArgumentError("add_optimality_cut!: grad_k contains a non-finite entry: $grad_k"),
    )
    all(isfinite, z_k) ||
        throw(ArgumentError("add_optimality_cut!: z_k contains a non-finite entry: $z_k"))

    α = epigraph === :op ? master.α_op : master.α_x
    @constraint(
        master.model,
        α >= cost_k + sum(grad_k[t] * (master.z[t] - z_k[t]) for t in 1:(master.T))
    )
    push!(
        master.cuts,
        (;
            kind = :optimality,
            epigraph,
            cost_k,
            grad_k = Vector{Float64}(grad_k),
            z_k = Vector{Float64}(z_k),
        ),
    )
    return master
end

"""
    add_feasibility_cut!(master::BendersMasterInteger, v_k::Real,
                         u_k::AbstractVector{<:Real},
                         z_k::AbstractVector{<:Real}) -> BendersMasterInteger

Append ONE new persistent feasibility-cut row to `master.model` — NEVER a
rebuild — reusing the EXACT SAME algebra as `add_feasibility_cut!(::BendersMaster, ...)`
(`master.jl`), from the follower's own genuine HiGHS Farkas certificate
`(v_k, u_k)` (see [`solve_follower!`](@ref)):

```
v_k + Σ_t u_k[t] * (z[t] - z_k[t]) <= 0
```

**Same justification as
[`add_optimality_cut!`](@ref)(::BendersMasterInteger, ...)** applies here: a
feasibility cut derived against the follower's continuous recourse remains a
valid supporting hyperplane over the entire continuous relaxation of `y_inv`,
hence at every binary corner of `b` — reused unmodified, never re-derived.

Throws `ArgumentError` if `length(u_k) != master.T` or `length(z_k) != master.T`,
or if `v_k`, any `u_k[t]`, or any `z_k[t]` is non-finite (NaN/Inf)
(reused verbatim).

Logs `(; kind = :feasibility, v_k, u_k, z_k)` to `master.cuts` (the SAME
NamedTuple shape as `BendersMaster.cuts`) and returns `master`.
"""
function add_feasibility_cut!(
    master::BendersMasterInteger,
    v_k::Real,
    u_k::AbstractVector{<:Real},
    z_k::AbstractVector{<:Real},
)
    length(u_k) == master.T ||
        throw(ArgumentError("u_k has length $(length(u_k)), expected T=$(master.T)"))
    length(z_k) == master.T ||
        throw(ArgumentError("z_k has length $(length(z_k)), expected T=$(master.T)"))
    # finiteness guard — mirror add_optimality_cut!'s own discipline; a
    # NaN/Inf feasibility row is just as unremovable and just as poisonous.
    isfinite(v_k) ||
        throw(ArgumentError("add_feasibility_cut!: v_k must be finite, got $v_k"))
    all(isfinite, u_k) ||
        throw(ArgumentError("add_feasibility_cut!: u_k contains a non-finite entry: $u_k"))
    all(isfinite, z_k) ||
        throw(ArgumentError("add_feasibility_cut!: z_k contains a non-finite entry: $z_k"))

    @constraint(
        master.model,
        v_k + sum(u_k[t] * (master.z[t] - z_k[t]) for t in 1:(master.T)) <= 0
    )
    push!(
        master.cuts,
        (;
            kind = :feasibility,
            v_k,
            u_k = Vector{Float64}(u_k),
            z_k = Vector{Float64}(z_k),
        ),
    )
    return master
end

"""
    add_ll_cut!(master::BendersMasterInteger, b_trial::AbstractVector{<:Real},
               Q_nu::Real, L::Real) -> BendersMasterInteger

Append ONE new persistent Laporte-Louveaux "no-good cut with a value" row to
`master.model` — NEVER a rebuild — over the RAW binary vector `master.b`
(writing this cut over the
DERIVED `master.y_inv` instead would silently invalidate the whole
combinatorial argument; this function never reads `master.y_inv`).

**Citation:** G. Laporte and F. V. Louveaux, "The integer L-shaped method for
stochastic integer programs with complete recourse," *Operations Research
Letters* 13 (1993), pp. 133-142; also Birge & Louveaux, *Introduction to
Stochastic Programming*, 2nd ed., Sec. 5.2 ("Binary First-Stage Variables"),
Springer, 2011.

Given the incumbent trial `b^ν = round.(Int, b_trial)`, its "on" set
`S^ν = {i : b^ν_i = 1}`, and its EXACT recourse value `Q_nu = Q(b^ν)` (already
computed by the caller — never estimated here), the cut is

```
D(b) = Σ_{i∈S^ν} b[i] − Σ_{i∉S^ν} b[i] − |S^ν| + 1
θ = master.α_op + master.α_x
θ >= (Q_nu − L) * D(b) + L
```

**One-sentence property (verified exhaustively, not taken on faith, by this
plan's own K=4 16-corner unit test):** the cut is TIGHT at `b = b^ν`
(`D = 1`, reduces to `θ >= Q_nu`) and adds ZERO new information — is IMPLIED
by the master's own existing `θ >= L` epigraph bound — at every other binary
corner (`D = 1 - k` at Hamming distance `k`, reduces to
`θ >= L - (k-1)(Q_nu - L) <= L` for Hamming distance `k >= 1`).

Throws `ArgumentError` if `length(b_trial) != master.K` or any entry of
`b_trial` is non-finite (same discipline, reused verbatim from
`add_optimality_cut!`/`add_feasibility_cut!`) — a malformed trial must fail
loudly BEFORE corrupting the build-once master's persistent constraint set.

**The `Q_nu >= L` precondition is ENFORCED, not merely
assumed:** the cut's own validity argument above requires `Q_nu >= L` (an exact
recourse value can never fall below the master's own declared global lower
bound on that recourse); previously this was undocumented and unchecked, so a
caller-side bug in `Q_nu`'s computation could silently append an INVALID cut
that over-constrains `θ` at every corner with Hamming distance `>= 2`. Throws a
named `ErrorException` (not `ArgumentError` — this is a precondition violation
on otherwise well-typed/finite inputs, not a malformed-argument shape/
finiteness check) if `Q_nu < L - atol * max(1, abs(L))`, BEFORE any cut is
appended (`master.cuts`/`master.model` are left untouched on the throw path).

**The tolerance band never appends an invalid cut.**
Inside the band `L − atol·max(1, |L|) <= Q_nu < L` the cut is built with
`Q_eff = max(Q_nu, L)` (and a `@warn`): an unclamped negative slope `Q_nu − L` would
make the cut `θ >= L + (k−1)(L − Q_nu)` at Hamming distance `k`, over-constraining every
corner with `k >= 2` by up to `(K−1)·atol·max(1,|L|)`. The clamped cut is `θ >= L` at
every corner — valid, and implied by the epigraph bound. A larger `atol` therefore only
widens what is accepted as noise around `L`; it can never make the appended cut invalid.

Logs `(; kind = :ll, b_trial = round.(Int, b_trial), Q_nu = Q_eff, L, Q_nu_raw = Q_nu)`
to `master.cuts` (`Q_nu` is the value the installed cut uses, so a consumer rebuilding
the cut's RHS from the log reproduces the installed row) and returns `master`.
"""
function add_ll_cut!(
    master::BendersMasterInteger,
    b_trial::AbstractVector{<:Real},
    Q_nu::Real,
    L::Real;
    atol::Real = 1e-6,
)
    length(b_trial) == master.K || throw(
        ArgumentError(
            "add_ll_cut!: b_trial has length $(length(b_trial)), expected K=$(master.K)",
        ),
    )
    all(isfinite, b_trial) ||
        throw(ArgumentError("add_ll_cut!: b_trial contains a non-finite entry: $b_trial"))
    isfinite(Q_nu) || throw(ArgumentError("add_ll_cut!: Q_nu must be finite, got $Q_nu"))
    isfinite(L) || throw(ArgumentError("add_ll_cut!: L must be finite, got $L"))
    # The cut's own validity argument requires Q_nu >= L —
    # enforce it loudly here, BEFORE any cut is appended, rather than silently appending an
    # invalid cut that over-constrains θ at every corner with Hamming distance >= 2.
    Q_nu >= L - atol * max(1, abs(L)) || error(
        "add_ll_cut!: Q_nu=$Q_nu < L=$L — the declared epigraph lower bound " *
        "α_op_lb + α_x_lb is not a valid lower bound on the per-corner recourse; " *
        "the LL cut would be INVALID at every corner with Hamming distance >= 2.",
    )

    # The tolerance band above must not let an INVALID cut
    # through. For L − atol·max(1,|L|) <= Q_nu < L the slope (Q_nu − L) is negative and
    # the cut would read θ >= L + (k−1)(L − Q_nu) > L at Hamming distance k >= 2 —
    # over-constraining. Clamp to Q_eff = max(Q_nu, L): a sub-L recourse inside the band
    # is solver noise around L, and θ >= L is already implied everywhere, so the clamped
    # cut is valid at every corner (tight at b^ν up to that noise).
    Q_eff = max(Float64(Q_nu), Float64(L))
    Q_eff == Q_nu || @warn(
        "add_ll_cut!: Q_nu=$Q_nu < L=$L within atol=$atol; clamping the cut's value " *
        "to L so it stays valid at every corner",
    )

    b_nu = round.(Int, b_trial)
    K = master.K
    S = findall(==(1), b_nu)
    Sc = setdiff(1:K, S)
    # RAW binaries master.b ONLY — never master.y_inv.
    Dexpr =
        sum(master.b[i] for i in S; init = 0) - sum(master.b[i] for i in Sc; init = 0) -
        length(S) + 1
    θ = master.α_op + master.α_x
    @constraint(master.model, θ >= (Q_eff - L) * Dexpr + L)
    # `Q_nu` records the value the INSTALLED cut uses (consumers rebuild the cut's RHS
    # from it); `Q_nu_raw` the caller's original value.
    push!(master.cuts, (; kind = :ll, b_trial = b_nu, Q_nu = Q_eff, L, Q_nu_raw = Q_nu))
    return master
end

"""
    add_nogood_cut!(master::BendersMasterInteger,
                    b_trial::AbstractVector{<:Real}) -> BendersMasterInteger

Append ONE new persistent classical (un-weighted) no-good cut row to
`master.model` — NEVER a rebuild — forbidding exact re-visitation of the
incumbent trial `b^ν = round.(Int, b_trial)`. This is the documented anti-stall
FALLBACK, strictly weaker than [`add_ll_cut!`](@ref) (it pins no objective
value), which is why a run that needs this cut is attributed `:nogood_assisted`
rather than presented as clean Laporte-Louveaux convergence.

**Citation:** same source as [`add_ll_cut!`](@ref) (Laporte & Louveaux 1993 /
Birge & Louveaux 2011 Sec 5.2) — the classical no-good cut this method
generalizes.

Given `S^ν = {i : b^ν_i = 1}`, the cut is

```
Σ_{i∈S^ν} (1 - b[i]) + Σ_{i∉S^ν} b[i] >= 1
```

which is satisfied by every binary vector EXCEPT `b^ν` itself (RAW binaries
`master.b` only — never `master.y_inv`, same discipline as
`add_ll_cut!`).

Throws `ArgumentError` under the same conditions as [`add_ll_cut!`](@ref)
(length mismatch against `master.K`, or a non-finite `b_trial` entry).

Logs `(; kind = :nogood, b_trial = round.(Int, b_trial))` to `master.cuts`
and returns `master`.
"""
function add_nogood_cut!(master::BendersMasterInteger, b_trial::AbstractVector{<:Real})
    length(b_trial) == master.K || throw(
        ArgumentError(
            "add_nogood_cut!: b_trial has length $(length(b_trial)), expected K=$(master.K)",
        ),
    )
    all(isfinite, b_trial) || throw(
        ArgumentError("add_nogood_cut!: b_trial contains a non-finite entry: $b_trial"),
    )

    b_nu = round.(Int, b_trial)
    K = master.K
    S = findall(==(1), b_nu)
    Sc = setdiff(1:K, S)
    @constraint(
        master.model,
        sum(1 - master.b[i] for i in S; init = 0) +
        sum(master.b[i] for i in Sc; init = 0) >= 1
    )
    push!(master.cuts, (; kind = :nogood, b_trial = b_nu))
    return master
end

# The numerical tolerance for declaring a REVISITED
# corner GENUINELY stalled (its own cutting-plane refinement has reached a fixed point —
# further visits provably cannot improve the incumbent there), as opposed to ordinary,
# EXPECTED refinement progress (a materially different `z` trial). Deliberately DISTINCT
# from `KNOWN_OPTIMUM_ATOL` (benders.jl) — that constant certifies the FINAL answer against
# the enumerated oracle; this one only decides when to stop re-exploring a corner, a much
# coarser bookkeeping question. `1e-6` mirrors the continuous loop's own inherited `tol`
# default order of magnitude (a z-trial that has stopped moving by more than this amount is
# the same "no further progress" signal `gap <= tol` uses elsewhere in this codebase), and
# is many orders of magnitude looser than genuine solver noise (~1e-9, KNOWN_OPTIMUM_ATOL's
# own measurement), so it never mistakes solver jitter for continued progress.
const STALL_Z_ATOL = 1e-6

# STALL_Z_ATOL is a FIXED absolute constant, but nothing
# ties it to the problem's own natural scale (`y_max`/`K`, both ordinary CONFIGURATION
# changes -- not code changes). Because `z` is box-bounded by `y_inv <= y_max`,
# the lattice's own step size `y_max / 2^K` is that natural scale: as it SHRINKS (a
# smaller `y_max` and/or larger `K`), a fixed 1e-6 absolute tolerance becomes RELATIVELY
# LOOSER, risking a false "stalled" verdict on a corner still making genuine progress --
# i.e. defect #2's exact catastrophic failure mode (a permanent, silent wrong-answer ban
# of a still-converging corner), reintroduced via a different mechanism than the one
# already fixed. A missed stall (too TIGHT) only costs a few extra iterations
# (loud, bounded by `max_iter`) -- so this predicate must always err toward the TIGHTER
# (harder-to-satisfy, `min`) of the two candidate tolerances, never the looser one.
#
# `stall_z_atol(master)` is a NO-OP on the certified fixture (step =
# 8.0/2^4 = 0.5, so `1e-3 * step = 5e-4 > STALL_Z_ATOL`, and `min` picks the ORIGINAL
# `1e-6`) -- the certified run's tolerance is UNCHANGED byte-for-byte. It only tightens
# (never loosens) `apply_integer_cuts!`'s stall predicate on a rescaled problem.
stall_z_atol(master::BendersMasterInteger) =
    min(STALL_Z_ATOL, 1.0e-3 * (master.y_max / 2.0^master.K))

"""
    apply_integer_cuts!(master, lb_res, Q_nu) -> NamedTuple{(:nogood_fired,)}

Dispatched entry point unifying the integer-cut mechanism behind
ONE call site (wired into `solve_stackelberg!`):

  - `apply_integer_cuts!(::BendersMaster, lb_res, Q_nu)` — a TRUE no-op for the
    continuous master: touches ZERO fields of `lb_res` (compiles/runs
    identically regardless of what `lb_res` actually contains), always
    returns `(; nogood_fired = false)`. A future accidental field access here
    would surface as a compile-time-visible `MethodError`/`ArgumentError` on
    the continuous path's OWN test suite, never a silent behavior change.
  - `apply_integer_cuts!(master::BendersMasterInteger, lb_res, Q_nu)` — the
    real logic: reads `b_trial = lb_res.b` (the field `solve_master!` already
    returns), ALWAYS calls
    `add_ll_cut!(master, b_trial, Q_nu, master.L)`
    (the LL cut coexists with, never replaces, the continuous `:op`/`:x` cuts),
    then checks whether `key = round.(Int, b_trial)` has already been visited
    (`master.visited`'s anti-stall bookkeeping) AND, if so, whether the
    CURRENT `z` trial (`lb_res.z`) matches the RECORDED `z` from that corner's
    LAST visit within ```stall_z_atol``(master)``` (scale-hardened, see its own
    docstring) — only THAT combination (same
    corner, unchanged `z`) is a genuine STALL, triggering
    `add_nogood_cut!(master, b_trial)`. `master.visited[key]` is updated to
    the current `z` trial regardless of the stall outcome.

**WHY "any revisit" was itself a defect:**
the PRE-fix version treated `key in master.visited` (ANY repeat visit,
regardless of `z`) as the stall signal. But a Laporte-Louveaux LL cut only
constrains `θ`, never `z` — the master's OWN continuous `z` choice at a given
corner is refined PURELY by the (separately accumulating) global `:op`/`:x`
cuts, exactly the standard outer-linearization/cutting-plane mechanism, and
REQUIRES revisiting the same corner across MULTIPLE iterations as those cuts
tighten (empirically confirmed on the fixture: the master's own `z` at
the TRUE optimal corner moved `0.195 → 0.442 → 0.497 → 0.500` — genuine,
converging progress — across what the pre-fix code classified as
"1st visit, then IMMEDIATELY STALLED"). Because `add_nogood_cut!` EXCLUDES a
corner from the master's feasible region PERMANENTLY (unlike the LL cut, which
only tightens `θ`'s floor), banning a corner mid-refinement makes it
UNREACHABLE for the REST OF THE RUN — including, on this fixture, the globally
optimal corner itself, which was banned on its 2nd visit while the incumbent
`UB` there (`-0.194`) was still `~0.03` away from its true minimized value
(`-0.225`), making `result.UB ≈ enum_result.best_total` PROVABLY UNREACHABLE
regardless of how correct `Q_nu` is. See
`test/test_planning_certification_integer.jl`'s file header for the full,
empirically-confirmed diagnosis this fix resolves (a SECOND, DISTINCT defect
from the `Q_nu` recourse-value bug, found while re-verifying this
certification).

Returns `(; nogood_fired::Bool)` — `true` only on the integer path's genuinely
stalled branch; always `false` on the continuous no-op.
"""
apply_integer_cuts!(::BendersMaster, lb_res, Q_nu) = (; nogood_fired = false)

function apply_integer_cuts!(master::BendersMasterInteger, lb_res, Q_nu)
    b_trial = lb_res.b
    add_ll_cut!(master, b_trial, Q_nu, master.L)
    key = round.(Int, b_trial)
    z_trial = Vector{Float64}(lb_res.z)
    # A genuine stall requires BOTH the SAME corner
    # AND an UNCHANGED z trial (within stall_z_atol(master), scale-hardened -- see its
    # own docstring) -- a revisit with a materially different z is expected
    # cutting-plane refinement progress, never a stall.
    stalled =
        haskey(master.visited, key) &&
        isapprox(master.visited[key], z_trial; atol = stall_z_atol(master), rtol = 0.0)
    master.visited[key] = z_trial
    if stalled
        add_nogood_cut!(master, b_trial)
    end
    return (; nogood_fired = stalled)
end

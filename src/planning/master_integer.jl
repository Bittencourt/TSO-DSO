# src/planning/master_integer.jl
#
# SEAM: build-once binary-expansion MILP Benders master (Phase 24, INT-01).
# OWNER: plan 24-01.
#
# A NEW, COMPLETELY SEPARATE builder alongside the continuous `build_master`
# (master.jl, D-05) — NOT an `integer=false` flag on the existing builder. The
# continuous v2.0 path stays byte-identical BY CONSTRUCTION: this file never
# touches master.jl, so the PVAL-02..04 goldens remain trivially safe to diff
# against.
#
# WHY A NEW STRUCT, NOT `BendersMaster` REUSED (24-RESEARCH.md Priority Finding 1 /
# Pattern 2): `add_optimality_cut!`/`add_feasibility_cut!` dispatch on the CONCRETE
# `BendersMaster` type, and that struct has no slot for the raw binary vector `b`
# the Laporte-Louveaux (LL) cut needs — the LL cut is written directly over the
# raw 0/1 decision variables, never over the derived continuous expression
# `y_inv` (Pitfall 1). `BendersMasterInteger` adds that slot; plan 24-02 adds the
# matching `add_optimality_cut!`/`add_feasibility_cut!` overloads for this type.
#
# `L = α_op_lb + α_x_lb` (Pitfall M1's finite epigraph lower bound, reused
# verbatim per D-08's "reuse the seam" spirit) doubles as the Laporte-Louveaux
# cut's required global lower bound `L` on the recourse `Q(y_inv)` — pinned once
# at construction so plan 24-02's cut code never re-derives it.

using JuMP

"""
    BendersMasterInteger{Y,Z,AOP,AX,B}

The built-ONCE binary-expansion MILP Benders master (Phase 24, INT-01): a
completely separate sibling of [`BendersMaster`](@ref) (D-05) — the leader's
own MILP over K raw binary variables `b`, a DERIVED continuous investment
expression `y_inv` (an `AffExpr` over `b`, D-01), coupling flow `z[t]`, and the
SAME two epigraph variables `α_op`/`α_x` (Pitfall M1 discipline reused
unchanged) — with cuts appended as persistent `@constraint` rows, never
rebuilt, mirroring `BendersMaster`'s own mutate-without-rebuild idiom.

# Fields

  - `model::Model` — the master MILP, built ONCE via
    `Model(select_optimizer(MILP()))` (INFRA-02); mutated ONLY by appending new
    `@constraint` rows (cuts), never rebuilt.

  - `y_inv::Y` — the DERIVED continuous investment expression
    `(y_max/2^K) * Σ_k 2^(k-1) b_k` (an `AffExpr`, D-01/D-02). Used in
    constraints/objective exactly like the continuous master's `y_inv`
    variable; NEVER used to reconstruct the LL cut's `S^ν` (Pitfall 1 — use
    `b` for that).

  - `z::Z` — the length-T coupling flow (`0 <= z[t] <= y_inv`), identical box
    shape to `BendersMaster`.

  - `α_op::AOP` — the oracle's own epigraph variable (`α_op >= α_op_lb`).

  - `α_x::AX` — the follower's own epigraph variable (`α_x >= α_x_lb`).

  - `b::B` — the raw `Vector{VariableRef}` of K binaries. Needed because the
    Laporte-Louveaux cut (plan 24-02) is written over `b`, never over the
    derived `y_inv` (24-RESEARCH.md Priority Finding 1 / Pitfall 1).

  - `K::Int` — the number of binary blocks in the expansion.

  - `T::Int` — the horizon.

  - `c_y::Float64` — the leader's flexibility-investment unit cost.

  - `y_max::Float64` — the nominal investment ceiling. NOTE (D-02): the
    all-ones corner reaches `y_max*(1 - 2^-K)`, NOT `y_max` itself — see
    [`build_master_integer`](@ref)'s own docstring for the full lattice
    derivation.

  - `L::Float64` — the pinned `α_op_lb + α_x_lb`, stored once at construction
    so plan 24-02's Laporte-Louveaux cut never has to re-derive the recourse's
    global lower bound.

  - `cuts::Vector{Any}` — a bookkeeping log of every cut appended, mirroring
    `BendersMaster.cuts`'s exact convention.

  - `visited::Dict{Vector{Int}, Vector{Float64}}` — empty at construction.
    Plan 24-02's anti-stall no-good fallback (D-16) populates this, mapping
    each previously-visited binary corner to the LAST `z` trial the master
    picked there — declared here so the struct's full field list is fixed in
    one place.

    **Phase 24 gap-closure (plan 24-05.1) — changed from `Set{Vector{Int}}`
    to `Dict{Vector{Int}, Vector{Float64}}`:** the original `Set`-membership
    "has this corner EVER been visited before" test treats every legitimate
    cutting-plane REFINEMENT revisit (the master picking the SAME corner
    again with a DIFFERENT, better-converged `z`, exactly how a Benders-style
    outer approximation is SUPPOSED to close in on a corner's true argmin) as
    an indistinguishable "stall" — banning the corner via `add_nogood_cut!`
    before the incumbent `UB` has had a chance to converge to that corner's
    true minimized value, including (confirmed empirically on the D-12
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
    cuts::Vector{Any}
    visited::Dict{Vector{Int}, Vector{Float64}}
end

"""
    build_master_integer(; T::Int, K::Int = 4, c_y::Real, y_max::Real,
                         α_op_lb::Real, α_x_lb::Real) -> BendersMasterInteger

Build the binary-expansion MILP Benders master EXACTLY ONCE:

 1. Boundary guards — `T >= 1`, `K >= 1`, `y_max > 0`, `c_y >= 0` — each throws
    `ArgumentError` naming the offending value, BEFORE any `@variable`/
    `@objective` assembly (mirrors `build_master`'s own discipline, master.jl).

 2. `model = Model(select_optimizer(MILP()))` — INFRA-02, never
    `Model(HiGHS.Optimizer)` directly.

 3. `b[1:K]` binary variables and the DERIVED continuous expression
    `y_inv = (y_max/2^K) * Σ_k 2^(k-1) b_k` (D-01).

    **D-02 lattice/endpoint artifact — documented here, not "fixed" elsewhere:**
    dividing by `2^K` (NOT `2^K - 1`) means the reachable investment set is the
    K=4 default's `{0, y_max/16, 2*y_max/16, ..., 15*y_max/16}` — for
    `y_max = 8.0` that is `{0, 0.5, 1.0, ..., 7.5}`, a step of `0.5`. The
    all-ones corner (`b = ones(K)`) reaches `y_max*(1 - 2^-K)`, e.g.
    `8.0*(1 - 1/16) = 7.5` — **`y_max` itself is never attainable.** This is a
    deliberate, accepted consequence of the round-step-size convention (D-02),
    not a bug to be corrected by changing the divisor to `2^K - 1`.

 4. `z[1:T]`, `α_op >= α_op_lb`, `α_x >= α_x_lb` — SAME finite-lower-bound-at-
    build-time discipline as `build_master` (Pitfall M1), reused for the MILP
    master.

 5. `box_lo[t]: z[t] >= 0`, `box_hi[t]: z[t] <= y_inv` — identical box shape to
    `build_master` (`y_inv` here is an `AffExpr`; JuMP supports this in
    `@constraint` RHS unchanged).

 6. `Min c_y*y_inv + α_op + α_x` — identical objective shape to `build_master`.

Returns a [`BendersMasterInteger`](@ref) with an empty `cuts` log and an empty
`visited` set, and `L = α_op_lb + α_x_lb` pinned for reuse by plan 24-02's
Laporte-Louveaux cut.
"""
function build_master_integer(;
    T::Int,
    K::Int = 4,
    c_y::Real,
    y_max::Real,
    α_op_lb::Real,
    α_x_lb::Real,
)
    # Boundary guards FIRST — fail here, not deep in objective assembly (mirrors
    # build_master's own discipline, master.jl).
    T >= 1 || throw(ArgumentError("build_master_integer needs T >= 1, got T=$T"))
    K >= 1 || throw(ArgumentError("build_master_integer needs K >= 1, got K=$K"))
    y_max > 0 || throw(ArgumentError("build_master_integer needs y_max > 0, got $y_max"))
    c_y >= 0 || throw(ArgumentError("build_master_integer needs c_y >= 0, got $c_y"))

    model = Model(select_optimizer(MILP()))   # INFRA-02: never Model(HiGHS.Optimizer) directly

    @variable(model, b[1:K], Bin)
    # D-01/D-02: divide by 2^K (NOT 2^K - 1) — all-ones reaches y_max*(1-2^-K), never
    # y_max itself. Documented artifact, not a bug (see docstring above).
    y_inv = @expression(model, (y_max / 2^K) * sum(2^(k - 1) * b[k] for k in 1:K))

    @variable(model, z[t = 1:T])
    # Pitfall M1 (reused verbatim from build_master): FINITE epigraph lower bounds
    # declared AT BUILD TIME — the very first (zero-cut) solve depends on this.
    @variable(model, α_op >= α_op_lb)
    @variable(model, α_x >= α_x_lb)

    # Pitfall O1 (reused verbatim from build_master): z is a physically nonnegative
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
        Float64(α_op_lb + α_x_lb),
        Any[],
        Dict{Vector{Int}, Vector{Float64}}(),
    )
end

"""
    solve_master!(master::BendersMasterInteger; max_attempts::Int = 4,
                 attempts_out::Union{Nothing,Ref{Int}} = nothing) -> NamedTuple

Re-solve the built-ONCE [`BendersMasterInteger`](@ref) via `solve_with_retry!`
(D-08) — NEVER the SOLE INFRA-03 choke point directly.

**Deliberate divergence from `solve_master!(::BendersMaster; ...)`'s
`dual = true` default: this method calls `solve_with_retry!` with
`dual = false`.** HiGHS/MOI does not report a meaningful dual status for a
genuine MIP solve — branch-and-bound has no LP dual at the integer solution in
general — so passing `dual = true` (the continuous master's default) would
make `is_solved_and_feasible` spuriously fail on every solve of this MILP
master. This is a deliberate, documented divergence justified by the
problem-class difference (LP vs. genuine MIP), NOT an accidental relaxation of
INFRA-03's "strict solve" discipline — exercised by this file's own zero-cut
first-solve regression test.

Returns `(; y, z, LB, b)` where `y = value(master.y_inv)`,
`z = value.(master.z)`, `LB = objective_value(master.model)`, and
`b = value.(master.b)` — the extra `b` field (absent from the continuous
`solve_master!`'s return) is read ONLY by plan 24-02/24-03's integer-specific
cut/loop code via duck typing; it never needs to exist on the continuous
return.
"""
function solve_master!(
    master::BendersMasterInteger;
    max_attempts::Int = 4,
    attempts_out::Union{Nothing, Ref{Int}} = nothing,
)
    # D-08: solve_with_retry! is the SOLE solve entry point on the master, mirroring
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
        LB = objective_value(master.model),
        b = value.(master.b),
    )
end

"""
    add_optimality_cut!(master::BendersMasterInteger, epigraph::Symbol, cost_k::Real,
                        grad_k::AbstractVector{<:Real},
                        z_k::AbstractVector{<:Real}) -> BendersMasterInteger

Append ONE new persistent optimality-cut row to `master.model` — NEVER a
rebuild — reusing the EXACT SAME algebra as `add_optimality_cut!(::BendersMaster, ...)`
(`master.jl`, PLAN-05):

```
α >= cost_k + Σ_t grad_k[t] * (z[t] - z_k[t])
```

where `α` is `master.α_op` if `epigraph === :op` or `master.α_x` if `epigraph === :x`.

**Why this is a plain transcription, not a re-derivation (24-RESEARCH.md Priority
Finding 2):** `Q(y_inv) = min_{0<=z<=y_inv}[α_op(z)+α_x(z)]` is a partial
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
unmodified alongside the (plan 24-03) Laporte-Louveaux integer cut, never
replaced by it.

Throws `ArgumentError` under the SAME conditions as the continuous method
(bad `epigraph`, length mismatch against `master.T`, or any non-finite
`cost_k`/`grad_k`/`z_k` entry) — a malformed cut triple must fail loudly BEFORE
corrupting the master's persistent constraint set (T-11-03/WR-03 discipline,
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
    # WR-03: finiteness guard — a NaN/Inf cut row would permanently poison the
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
(`master.jl`, PLAN-05), from the follower's own genuine HiGHS Farkas certificate
`(v_k, u_k)` (see [`solve_follower!`](@ref)):

```
v_k + Σ_t u_k[t] * (z[t] - z_k[t]) <= 0
```

**Same 24-RESEARCH.md Priority Finding 2 justification as
[`add_optimality_cut!`](@ref)(::BendersMasterInteger, ...)** applies here: a
feasibility cut derived against the follower's continuous recourse remains a
valid supporting hyperplane over the entire continuous relaxation of `y_inv`,
hence at every binary corner of `b` — reused unmodified, never re-derived.

Throws `ArgumentError` if `length(u_k) != master.T` or `length(z_k) != master.T`,
or if `v_k`, any `u_k[t]`, or any `z_k[t]` is non-finite (NaN/Inf)
(T-11-03/WR-03, reused verbatim).

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
    # WR-03: finiteness guard — mirror add_optimality_cut!'s own discipline; a
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
(24-RESEARCH.md Priority Finding 1 / Pitfall 1: writing this cut over the
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
corner (`D <= -1`, reduces to `θ >= L - 2k(Q_nu - L) <= L` for Hamming
distance `k >= 1`).

Throws `ArgumentError` if `length(b_trial) != master.K` or any entry of
`b_trial` is non-finite (WR-03 discipline, reused verbatim from
`add_optimality_cut!`/`add_feasibility_cut!`) — a malformed trial must fail
loudly BEFORE corrupting the build-once master's persistent constraint set.

Logs `(; kind = :ll, b_trial = round.(Int, b_trial), Q_nu, L)` to
`master.cuts` and returns `master`.
"""
function add_ll_cut!(
    master::BendersMasterInteger,
    b_trial::AbstractVector{<:Real},
    Q_nu::Real,
    L::Real,
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

    b_nu = round.(Int, b_trial)
    K = master.K
    S = findall(==(1), b_nu)
    Sc = setdiff(1:K, S)
    # RAW binaries master.b ONLY — never master.y_inv (Pitfall 1).
    Dexpr =
        sum(master.b[i] for i in S; init = 0) - sum(master.b[i] for i in Sc; init = 0) -
        length(S) + 1
    θ = master.α_op + master.α_x
    @constraint(master.model, θ >= (Q_nu - L) * Dexpr + L)
    push!(master.cuts, (; kind = :ll, b_trial = b_nu, Q_nu, L))
    return master
end

"""
    add_nogood_cut!(master::BendersMasterInteger,
                    b_trial::AbstractVector{<:Real}) -> BendersMasterInteger

Append ONE new persistent classical (un-weighted) no-good cut row to
`master.model` — NEVER a rebuild — forbidding exact re-visitation of the
incumbent trial `b^ν = round.(Int, b_trial)`. D-16's documented anti-stall
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
`master.b` only — never `master.y_inv`, same Pitfall 1 discipline as
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

# Phase 24 gap-closure (plan 24-05.1): the numerical tolerance for declaring a REVISITED
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

# WR-02 (Phase 24 code review): STALL_Z_ATOL is a FIXED absolute constant, but nothing
# ties it to the problem's own natural scale (`y_max`/`K`, both ordinary CONFIGURATION
# changes per D-01 -- not code changes). Because `z` is box-bounded by `y_inv <= y_max`,
# the lattice's own step size `y_max / 2^K` is that natural scale: as it SHRINKS (a
# smaller `y_max` and/or larger `K`), a fixed 1e-6 absolute tolerance becomes RELATIVELY
# LOOSER, risking a false "stalled" verdict on a corner still making genuine progress --
# i.e. defect #2's exact catastrophic failure mode (a permanent, silent wrong-answer ban
# of a still-converging corner), reintroduced via a different mechanism than the one
# 24-05.1 already fixed. A missed stall (too TIGHT) only costs a few extra iterations
# (loud, bounded by `max_iter`) -- so this predicate must always err toward the TIGHTER
# (harder-to-satisfy, `min`) of the two candidate tolerances, never the looser one.
#
# `stall_z_atol(master)` is a NO-OP on the certified D-12 fixture (step =
# 8.0/2^4 = 0.5, so `1e-3 * step = 5e-4 > STALL_Z_ATOL`, and `min` picks the ORIGINAL
# `1e-6`) -- the certified run's tolerance is UNCHANGED byte-for-byte. It only tightens
# (never loosens) `apply_integer_cuts!`'s stall predicate on a rescaled problem.
stall_z_atol(master::BendersMasterInteger) =
    min(STALL_Z_ATOL, 1.0e-3 * (master.y_max / 2.0^master.K))

"""
    apply_integer_cuts!(master, lb_res, Q_nu) -> NamedTuple{(:nogood_fired,)}

Dispatched entry point unifying the integer-cut mechanism (plan 24-03) behind
ONE call site (wired into `solve_stackelberg!` by plan 24-04):

  - `apply_integer_cuts!(::BendersMaster, lb_res, Q_nu)` — a TRUE no-op for the
    continuous master: touches ZERO fields of `lb_res` (compiles/runs
    identically regardless of what `lb_res` actually contains), always
    returns `(; nogood_fired = false)`. A future accidental field access here
    would surface as a compile-time-visible `MethodError`/`ArgumentError` on
    the continuous path's OWN test suite, never a silent behavior change
    (T-24-08).
  - `apply_integer_cuts!(master::BendersMasterInteger, lb_res, Q_nu)` — the
    real logic: reads `b_trial = lb_res.b` (the field `solve_master!` already
    returns, plan 24-01), ALWAYS calls
    `add_ll_cut!(master, b_trial, Q_nu, master.L)` (24-RESEARCH.md Finding 2:
    the LL cut coexists with, never replaces, the continuous `:op`/`:x` cuts),
    then checks whether `key = round.(Int, b_trial)` has already been visited
    (`master.visited`, D-16's anti-stall bookkeeping) AND, if so, whether the
    CURRENT `z` trial (`lb_res.z`) matches the RECORDED `z` from that corner's
    LAST visit within [`stall_z_atol`](@ref)`(master)` (WR-02-hardened, see its own
    docstring) — only THAT combination (same
    corner, unchanged `z`) is a genuine STALL, triggering
    `add_nogood_cut!(master, b_trial)`. `master.visited[key]` is updated to
    the current `z` trial regardless of the stall outcome.

**Phase 24 gap-closure (plan 24-05.1) — WHY "any revisit" was itself a defect:**
the PRE-fix version treated `key in master.visited` (ANY repeat visit,
regardless of `z`) as the stall signal. But a Laporte-Louveaux LL cut only
constrains `θ`, never `z` — the master's OWN continuous `z` choice at a given
corner is refined PURELY by the (separately accumulating) global `:op`/`:x`
cuts, exactly the standard outer-linearization/cutting-plane mechanism, and
REQUIRES revisiting the same corner across MULTIPLE iterations as those cuts
tighten (empirically confirmed on the D-12 fixture: the master's own `z` at
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
certification during gap-closure).

Returns `(; nogood_fired::Bool)` — `true` only on the integer path's genuinely
stalled branch; always `false` on the continuous no-op.
"""
apply_integer_cuts!(::BendersMaster, lb_res, Q_nu) = (; nogood_fired = false)

function apply_integer_cuts!(master::BendersMasterInteger, lb_res, Q_nu)
    b_trial = lb_res.b
    add_ll_cut!(master, b_trial, Q_nu, master.L)
    key = round.(Int, b_trial)
    z_trial = Vector{Float64}(lb_res.z)
    # Phase 24 gap-closure (plan 24-05.1): a genuine stall requires BOTH the SAME corner
    # AND an UNCHANGED z trial (within stall_z_atol(master), WR-02-hardened -- see its
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

export BendersMasterInteger,
    build_master_integer, add_ll_cut!, add_nogood_cut!, apply_integer_cuts!

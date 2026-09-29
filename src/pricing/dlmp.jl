# src/pricing/dlmp.jl
#
# SEAM: DLMP extraction + four-way decomposition (PRICE-01 / PRICE-02).
# OWNER: plan 05-02.
#
# Pure convex-duality POST-PROCESSING over a solved `ModelContext` from
# `solve_welfare(feeder, ConvexBranchFlow(), aggs; allow_export=true)`. Reads duals only;
# builds and solves nothing (no model here names a solver). Three public functions:
#
#   * `extract_dlmp(ctx)`    — the day-ahead dynamic price / DLMP: the dual of the nodal
#     ACTIVE-power balance (thesis eq. 3.31), per node per hour. Positive = marginal cost of
#     consumption (sign pinned by the 2-bus regression). REFUSES prices (throws) on an
#     UNGATED SOCP ctx — one carrying a squared-current `:l` but no PF-04 exactness
#     certificate `ctx.meta[:socp_maxgap]` — because a strict SOC relaxation makes `l` a
#     fictitious over-current and the recovered duals physically meaningless (PF-04).
#
#   * `extract_reactive_dlmp(ctx)` — the reactive nodal price (REACT-02): the dual of the
#     nodal REACTIVE-power balance `:balance_q` (thesis eq. 3.23's network closure), per node
#     per hour. Mirrors `extract_dlmp`'s shape/gate exactly, plus a presence guard since a
#     DC/active-only formulation never registers `:balance_q`. This is a SEPARATE price
#     signal from the active DADP — never summed into it.
#
#   * `decompose_dlmp(ctx)`  — the four-way DLMP split into energy + cone + congestion +
#     drop that provably SUMS to the nodal price, PLUS the reactive price as a 5th,
#     UN-summed field (`reactive`). The thesis gives the active split only qualitatively
#     (Fig 4.5/4.6), so each component is reconstructed INDEPENDENTLY from a DISTINCT
#     registered dual (RESEARCH strategy B — cone is NOT the leftover) and a HARD
#     relative-tolerance assertion checks `energy+cone+congestion+drop ≈ dual(balance_p)`
#     per node/hour, throwing with the worst per-node residual so a dropped term is
#     localizable (RESEARCH Pitfall 2). `reactive` is documented and citable but is NOT part
#     of this 4-term active-price reconstruction (REACT-02; distinct component, distinct unit
#     of account). [FIX-07, phase 27] `cone`/`drop` are named after what they mathematically
#     ARE (the rotated-SOC cone-slot multiplier, thesis 3.39, and the voltage-drop/copy-drop
#     multiplier, thesis 3.33/3.43); `.loss`/`.voltage` remain as deprecated aliases.
#
# Decomposition derivation (KKT stationarity of the branch active flow P_b, empirically
# certified to machine precision on the 2-bus / IEEE-13 / high-PV solves). For branch
# b = (i→j) the price increment across it is
#
#     λ_j − λ_i = −( cone_dualᵦ[3]  +  2·rᵦ·(βᵦ + γᵦ)  +  smax_dualᵦ[2] )
#
# where βᵦ = dual(:vdrop[b]) (3.33), γᵦ = dual(:cpydrop[b]) (3.43), cone_dualᵦ is the rotated
# SOC dual (3.39; slot 3 is the P-slot), and smax_dualᵦ is the apparent-power SOC dual (3.36;
# slot 2 is the P-slot, present only where a real limit binds — the head branch). Because the
# feeder is a radial TREE, node j has a unique path root→j; summing the increment telescopes
# to λ_j − λ_0, attributing (FIX-07, phase 27: fields named `cone`/`drop` after what they ARE,
# not the misleading `loss`/`voltage` they were previously called):
#   energy = λ_0 (root MEM price, same at every node),
#   cone   = Σ_path −cone_dual[3]        (the rotated-SOC cone-slot multiplier, 3.39),
#   cong   = Σ_path −smax_dual[2] − smax_rev_dual[2]
#                                         (thermal congestion, SENDING-end 3.36 PLUS
#                                          RECEIVING-end 3.37; 0 unless a head-branch limit
#                                          binds, from EITHER end),
#   drop   = Σ_path −2·r·(β + γ)         (voltage-drop/copy-drop multiplier propagation of the
#                                          v/v̂ bound pressure, 3.33/3.43; 0 when no voltage
#                                          headroom is engaged).
#
# [Phase 26 / FIX-03 congestion follow-up, plan 26-10] `:smax_rev` (thesis 3.37, the
# RECEIVING-end apparent-power cone added by plan 26-05) was NOT read by the congestion term
# above until this plan. On IEEE-13, PV back-feed at t=9-16 makes the receiving-end cone bind
# on the limited head branch INSTEAD OF the sending-end one, so the old sending-end-only
# `cong_b` went to ~0 in that window and the hard sum-to-price assertion failed (residual 6.23
# at bus 10, t=9). Fixed by adding a SOFT-guarded (`haskey`) read of `dual(:smax_rev[b,t])[2]`
# into `cong_b`, SAME sign convention as the sending-end term (empirically verified: the worst
# residual on the IEEE-13 back-feed window dropped to machine precision, 3.55e-15, at the
# chosen sign — see `26-10-SUMMARY.md`).
#
# [Phase 26 / FIX-01-02 re-certification, plan 26-06] Phase 26 flipped `ConvexBranchFlow`'s
# default `cpydrop` coefficient (v̂ ≥ v, the Gan-Low direction) — only the coefficient of the
# branch's OWN r·l / x·l loss term inside cpydrop changed; P's own coefficient (the quantity
# this file's KKT-stationarity derivation actually depends on) did NOT change. This formula
# was therefore EMPIRICALLY RE-VERIFIED UNCHANGED (no code edit) against the corrected default
# by re-running the SAME hard sum-to-price assertion below on three regimes, to at/near machine
# precision:
#   - congestion-binding:  IEEE-13 ground solve (`test_pricing_dlmp.jl`'s
#     "four components SUM to the DADP on IEEE-13" item) — worst residual 6.2e-12;
#   - voltage-engaged:     the high-PV over-voltage solve (`test_pricing_dlmp.jl`'s
#     "SUM holds and voltage is engaged" item) — worst residual 1.8e-15;
#   - uncongested/in-bound: a lossy, uncongested, in-bound 2-bus (Deferrable load, r=0.01,
#     x=0.02, smax=10 — the SAME fixture as this plan's own `<verify>` smoke test) —
#     residual 2.2e-16, congestion/voltage both ≈1e-13 (≈0), matching the intended regime of
#     `test_pricing_dlmp.jl`'s "≈0 congestion/voltage on an uncongested in-bound 2-bus" item.
# The THIRD item's own PVBattery-based fixture could not be re-exercised as originally written:
# bisection (see phase 26 `deferred-items.md`) confirms a PRE-EXISTING, UNRELATED SOCP-exactness
# regression introduced by Plan 26-03's battery SOC-horizon fix (commit cfa7e6e, FIX-04) breaks
# that specific fixture's `assert_socp_exact!` gate before `decompose_dlmp` is ever reached —
# confirmed NOT caused by this file's cpydrop-consuming formula or by the cpydrop sign flip
# itself (the flip alone, commit f677965, leaves that fixture exact to residual 0.0). Out of
# this plan's file scope (`src/pricing/dlmp.jl` only); logged, not fixed, here.
#
# Consumes ONLY the additive Phase-4 seam registered by plan 05-01 (`:cone`, `:vdrop`,
# `:cpydrop`, `:smax`, and `ctx.meta[:pf_vars]`) plus the always-present `:balance_p` — no
# change to `solve_welfare` or the power-flow formulations.

using JuMP

# ---------------------------------------------------------------------------------------------
# Price-refusal gate (PF-04). A dual is a valid price ONLY if the SOCP exactness gate certified
# the cone. `solve_welfare` runs `assert_socp_exact!` (stashing `ctx.meta[:socp_maxgap]`)
# whenever the formulation carries a squared current `:l`; if that certificate is ABSENT on an
# `:l`-bearing ctx the solve was never gated (or was hand-built bypassing the gate) and its
# DADP duals must be REFUSED, not returned (RESEARCH Anti-Pattern "reading the DADP before the
# exactness gate"; threat T-05-01). DC/LinDistFlow ctxs carry no `:l` and are priced normally.
# ---------------------------------------------------------------------------------------------
function _assert_priceable(ctx::ModelContext)
    haskey(ctx.constraints, :balance_p) || throw(
        ArgumentError(
            "extract_dlmp: ctx has no registered :balance_p — this is not a solved " *
            "welfare ModelContext (thesis eq. 3.31)",
        ),
    )
    if haskey(ctx.meta, :pf_vars) &&
       haskey(ctx.meta[:pf_vars], :l) &&
       !haskey(ctx.meta, :socp_maxgap)
        throw(
            ArgumentError(
                "extract_dlmp: refusing to price an UNGATED SOCP ctx — the PF-04 exactness " *
                "certificate `ctx.meta[:socp_maxgap]` is ABSENT while a squared-current `:l` " *
                "is present, so the SOC relaxation was never certified exact. A strict cone " *
                "makes `l` a fictitious over-current and the DADP duals physically meaningless " *
                "(thesis 3.43-3.45; PF-04 gate — see assert_socp_exact!).",
            ),
        )
    end
    return nothing
end

"""
    extract_dlmp(ctx; bus = nothing, T = nothing) -> Matrix{Float64} | Vector{Float64}

The day-ahead dynamic price (DADP / DLMP) — the dual of the nodal ACTIVE-power balance
(thesis eq. 3.31), per node per hour (PRICE-01). Positive = marginal cost of consumption at
that node/hour (sign pinned by the 2-bus hand-solved regression, RESEARCH Pitfall 1).

Requires a `ctx` from `solve_welfare(...)`, which gates every dual behind `assert_solved!`
AND — for a SOCP formulation — the PF-04 exactness certificate. This function REFUSES prices
(throws an `ArgumentError`, never `@assert`) if handed an `:l`-bearing SOCP ctx that lacks
`ctx.meta[:socp_maxgap]` (ungated / inexact cone; threat T-05-01).

With `bus === nothing` (default) it returns the full `(N_buses, T)` DADP matrix
`dual.(ctx.constraints[:balance_p])`. Passing `bus` returns that bus's length-`T` price
vector (`T` defaults to the full horizon; a shorter `T` keeps the leading hours `1:T` and
truncates the trailing ones).
"""
function extract_dlmp(ctx::ModelContext; bus = nothing, T = nothing)
    _assert_priceable(ctx)
    bp = ctx.constraints[:balance_p]          # bus × time ConstraintRef array (thesis 3.31)
    N, Tfull = size(bp)
    M = Float64[dual(bp[j, t]) for j in 1:N, t in 1:Tfull]
    bus === nothing && return M
    Tsel = T === nothing ? Tfull : Int(T)
    return M[bus, 1:Tsel]
end

"""
    extract_reactive_dlmp(ctx; bus = nothing, T = nothing) -> Matrix{Float64} | Vector{Float64}

The reactive nodal price (REACT-02) — the dual of the nodal REACTIVE-power balance
`:balance_q` (thesis eq. 3.23's network closure), per node per hour. A SEPARATE price
signal from [`extract_dlmp`](@ref)'s active DADP — never summed into it, never folded into
`decompose_dlmp`'s `total`.

Requires a `ctx` from `solve_welfare(...)`, gated by the SAME `_assert_priceable` PF-04
exactness certificate `extract_dlmp` requires (this function REFUSES prices on an ungated
SOCP ctx exactly like `extract_dlmp`). Additionally throws `ArgumentError` (never `KeyError`)
if `ctx` has no registered `:balance_q` — a DC/active-only formulation (e.g. `DCPowerFlow`)
never carries a reactive channel (thesis A3 note in `welfare_solve.jl`), so no reactive price
exists to extract.

With `bus === nothing` (default) it returns the full `(N_buses, T)` reactive-price matrix
`dual.(ctx.constraints[:balance_q])`. Passing `bus` returns that bus's length-`T` price
vector (`T` defaults to the full horizon; a shorter `T` keeps the leading hours `1:T` and
truncates the trailing ones). The root's price is expected to be DEGENERATE (≈0): the
root's `q_import` is a free-sign, zero-objective-coefficient frontier variable, so its own
KKT stationarity condition forces `dual(:balance_q[root,t]) ≡ 0` (RESEARCH "Free slack,
precisely located" — no reactive energy market exists at the substation in this model).
"""
function extract_reactive_dlmp(ctx::ModelContext; bus = nothing, T = nothing)
    _assert_priceable(ctx)
    haskey(ctx.constraints, :balance_q) || throw(
        ArgumentError(
            "extract_reactive_dlmp: ctx has no :balance_q -- this formulation has no " *
            "reactive channel (e.g. DCPowerFlow); no reactive price exists to extract",
        ),
    )
    bq = ctx.constraints[:balance_q]          # bus × time ConstraintRef array (thesis 3.23)
    N, Tfull = size(bq)
    M = Float64[dual(bq[j, t]) for j in 1:N, t in 1:Tfull]
    bus === nothing && return M
    Tsel = T === nothing ? Tfull : Int(T)
    return M[bus, 1:Tsel]
end

# ---------------------------------------------------------------------------------------------
# Radial path root→j: walk the tree's parent pointers (feeder.branches are parent→child, N−1
# of them on a validated radial feeder — DATA-02 `assert_radial`). No graph library needed
# (RESEARCH "Don't Hand-Roll"). Returns the branch indices on the unique path, root-first.
# ---------------------------------------------------------------------------------------------
function _path_branches(feeder, j::Int)
    child_branch = Dict{Int, Int}()
    for (b, br) in enumerate(feeder.branches)
        child_branch[br.to] = b
    end
    path = Int[]
    cur = j
    while cur != feeder.root
        haskey(child_branch, cur) || error(
            "decompose_dlmp: bus $cur has no parent branch — feeder is not the expected " *
            "radial tree (DATA-02)",
        )
        b = child_branch[cur]
        push!(path, b)
        cur = feeder.branches[b].from
    end
    return reverse(path)   # root-first (order is immaterial for a sum, but keeps intent clear)
end

# P-slot of the apparent-power SOC dual (thesis 3.36), or 0.0 where the branch carries no
# binding limit (its (b,t) key is absent from the sparse `:smax` container — RESEARCH A5).
function _smax_P(smax, keyset::Set{Tuple{Int, Int}}, b::Int, t::Int)
    (b, t) in keyset || return 0.0
    return dual(smax[b, t])[2]      # SecondOrderCone dual [smax, P, Q]; slot 2 = P
end

"""
    DlmpDecomposition{A}

The return type of [`decompose_dlmp`](@ref): the five-component (plus `total`) DLMP
decomposition. `A` is `Matrix{Float64}` for the full-`(N_buses, T)` shape (`bus === nothing`)
or a `Vector{Float64}` for the `bus`-sliced shape — the SAME struct is reused for both.

Fields (thesis-traceable multiplier identity, FIX-07 — named after what each component
mathematically IS, not a downstream physical effect):

  - `energy::A`     — the root MEM price `dual(:balance_p[root,t])`, SAME at every node (≈λ₀);
  - `cone::A`       — the rotated-SOC cone-slot multiplier (thesis 3.39; formerly `loss`);
  - `drop::A`       — the voltage-drop/copy-drop multiplier (thesis 3.33/3.43; formerly
    `voltage`);
  - `congestion::A` — the thermal-limit dual (thesis 3.36 sending-end / 3.37 receiving-end);
  - `reactive::A`   — the reactive nodal price (`dual(:balance_q)`), a SEPARATE, UN-summed
    signal (REACT-02), never folded into `total`;
  - `total::A`      — the reference DADP (`dual(:balance_p)`); `energy+cone+congestion+drop`
    reconstructs this within `decompose_dlmp`'s hard sum-to-price tolerance.

`.loss` and `.voltage` remain accessible as ONE-TIME `Base.depwarn`-deprecated aliases for
`.cone`/`.drop` respectively (never erroring, returning the identical value) — kept for
backward compatibility with existing consumers, removal scheduled for Phase 36 (Code & Export
Cleanup).
"""
struct DlmpDecomposition{A}
    energy::A
    cone::A
    drop::A
    congestion::A
    reactive::A
    total::A
end

function Base.getproperty(d::DlmpDecomposition, s::Symbol)
    if s === :loss
        Base.depwarn(
            "DlmpDecomposition.loss is deprecated, use .cone (the rotated-SOC cone-slot " *
            "multiplier, thesis 3.39) -- removal scheduled for Phase 36",
            :decompose_dlmp,
        )
        return getfield(d, :cone)
    elseif s === :voltage
        Base.depwarn(
            "DlmpDecomposition.voltage is deprecated, use .drop (the voltage-drop/copy-drop " *
            "multiplier, thesis 3.33/3.43) -- removal scheduled for Phase 36",
            :decompose_dlmp,
        )
        return getfield(d, :drop)
    else
        return getfield(d, s)
    end
end

# WR-01 fix (27-REVIEW.md, 2026-09-29): `DlmpDecomposition` is a plain `struct`, not a
# `NamedTuple` (unlike its pre-Phase-27 return type) — `propertynames` would otherwise omit
# the deprecated `.loss`/`.voltage` virtual properties `Base.getproperty` above still serves,
# which could confuse introspection (`propertynames(d)`, REPL tab-completion) into looking
# incomplete relative to what `getproperty` actually accepts.
Base.propertynames(::DlmpDecomposition, ::Bool = false) =
    (:energy, :cone, :drop, :congestion, :reactive, :total, :loss, :voltage)

"""
    NamedTuple(d::DlmpDecomposition) -> NamedTuple

WR-01 fix (27-REVIEW.md, 2026-09-29): before Phase 27's FIX-07 rename, `decompose_dlmp`
returned a plain `NamedTuple` with field order `(energy, loss, congestion, voltage,
reactive, total)`. Any consumer that used genuine `NamedTuple`-only semantics on that return
value (`Tuple(nt)`/`values(nt)`/`collect(nt)`, or positional destructuring) now hits a
`MethodError` against `DlmpDecomposition` (a plain `struct`) instead — a LOUD failure, never
a silent field-order mismatch, but still a breaking change for such a call site (none found
in this tree, but this API is `export`ed). This conversion restores the OLD field
NAMES-AND-ORDER exactly — never the new struct's own field order, which additionally
TRANSPOSES `congestion`/`drop` relative to the old `congestion`/`voltage` positions (see
`DlmpDecomposition`'s own docstring) — so a duck-typed-as-a-NamedTuple call site can be
repaired by wrapping the call in `NamedTuple(decompose_dlmp(...))`.
"""
function Base.NamedTuple(d::DlmpDecomposition)
    return (;
        energy = d.energy,
        loss = getfield(d, :cone),
        congestion = getfield(d, :congestion),
        voltage = getfield(d, :drop),
        reactive = getfield(d, :reactive),
        total = getfield(d, :total),
    )
end

"""
    decompose_dlmp(ctx; bus = nothing, T = nothing, rtol = 1e-5, atol = 1e-7)
        -> DlmpDecomposition

Four-way DLMP decomposition (PRICE-02): split the nodal ACTIVE price into **energy + cone +
congestion + drop** components that provably SUM to the DADP, PLUS a 5th, UN-summed
`reactive` field (REACT-02). Each active component is reconstructed INDEPENDENTLY from a
DISTINCT registered dual (RESEARCH strategy B — cone is NOT the leftover, so a dropped
congestion/drop term cannot hide), then a HARD relative-tolerance assertion checks
`energy + cone + congestion + drop ≈ total` per node/hour and `total ≈ extract_dlmp(ctx)`,
throwing (never `@assert`) with the worst per-node residual so a missing term is localizable
(RESEARCH Pitfall 2; threat T-05-02). This 4-term reconstruction and its assertion are
UNCHANGED by the `reactive` field — `reactive` is a SEPARATE price signal (the dual of
`:balance_q`), never folded into `total` or the sum-to-price check.

Components (each summed over the unique radial path root→j; derivation in the file header):

  - `energy`     = `dual(:balance_p[root, t])`     — the MEM price, SAME at every node (≈ λ₀);
  - `cone`       = `Σ_path −dual(:cone[b,t])[3]`   — the rotated-SOC cone-slot multiplier
    (thesis 3.39);
  - `congestion` = `Σ_path (−dual(:smax[b,t])[2] − dual(:smax_rev[b,t])[2])` — thermal
    congestion, SENDING-end (3.36) PLUS RECEIVING-end (3.37, FIX-03/26-05; soft-guarded —
    reads 0 if `:smax_rev` is absent from `ctx`) — 0 off the head branch, from either end;
  - `drop`       = `Σ_path −2·r·(dual(:vdrop) + dual(:cpydrop))` — the voltage-drop/copy-drop
    multiplier (thesis 3.33/3.43; 0 with unengaged voltage headroom);
  - `reactive`   = `extract_reactive_dlmp(ctx)`    — the reactive nodal price (REACT-02;
    `dual(:balance_q[j,t])`), a documented, citable 5th component, DISTINCT from and NEVER
    summed into `total`;
  - `total`      = `extract_dlmp(ctx)`             — the reference DADP (active price only).

FIX-07 (phase 27): these fields were previously named `loss`/`voltage` — misleading, since
they name each component after a downstream PHYSICAL EFFECT rather than the multiplier it
provably IS. `.loss`/`.voltage` remain accessible as deprecated aliases (see
[`DlmpDecomposition`](@ref)) so existing consumers keep working unchanged.

Inherits the PF-04 exactness gate from [`extract_dlmp`](@ref) (an ungated SOCP ctx is
refused). Requires the SOCP branch-flow handles registered by plan 05-01 (`:cone`, `:vdrop`,
`:cpydrop`, `:smax`); throws a clear `ArgumentError` on a formulation that lacks them. Since
these handles are `ConvexBranchFlow`-only, any ctx that reaches `decompose_dlmp` always also
carries `:balance_q` (registered unconditionally on that formulation), so `reactive` needs no
additional presence guard here (the guard lives in the standalone `extract_reactive_dlmp` for
direct/DC-only callers).

With `bus === nothing` (default) every field is an `(N_buses, T)` matrix; passing `bus`
returns a `DlmpDecomposition` of that bus's length-`T` component vectors.
"""
function decompose_dlmp(
    ctx::ModelContext;
    bus = nothing,
    T = nothing,
    rtol::Real = 1e-5,
    atol::Real = 1e-7,
)
    _assert_priceable(ctx)
    for name in (:cone, :vdrop, :cpydrop, :smax)
        haskey(ctx.constraints, name) || throw(
            ArgumentError(
                "decompose_dlmp: ctx is missing the registered :$name dual — the four-way " *
                "split needs the SOCP ConvexBranchFlow handles (thesis 3.39/3.33/3.43/3.36; " *
                "registered by plan 05-01). Was this solved with ConvexBranchFlow()?",
            ),
        )
    end

    feeder = ctx.meta[:feeder]
    bp = ctx.constraints[:balance_p]
    N, Tfull = size(bp)
    root = feeder.root

    cone_constr = ctx.constraints[:cone]      # constraint container (renamed from `cone` to
    # avoid shadowing the `cone` COMPONENT accumulator matrix built below, FIX-07)
    vdrop = ctx.constraints[:vdrop]
    cpydrop = ctx.constraints[:cpydrop]
    smax = ctx.constraints[:smax]
    smaxkeys = Set{Tuple{Int, Int}}(Tuple(k) for k in eachindex(smax))
    # FIX-03/26-05 (plan 26-10): `:smax_rev` (thesis 3.37, the RECEIVING-end apparent-power
    # cone) is registered under the IDENTICAL `B[b].smax < _SMAX_NO_LIMIT` filter as `:smax`
    # (ConvexBranchFlow.jl), so `smaxkeys` (already built from `:smax`) applies unchanged to
    # `:smax_rev` too. Soft-guarded (not added to the hard required-containers loop above)
    # since some hand-built test contexts (e.g. this file's own unit-test ctxs) may not carry
    # it — the congestion split degrades gracefully to sending-end-only in that case.
    smax_rev = get(ctx.constraints, :smax_rev, nothing)

    total = extract_dlmp(ctx)                          # (N, Tfull) reference DADP (re-runs gate)
    energy = Matrix{Float64}(undef, N, Tfull)
    cone = zeros(Float64, N, Tfull)
    congestion = zeros(Float64, N, Tfull)
    drop = zeros(Float64, N, Tfull)

    # Per-branch/time increments, computed ONCE (each from its own distinct dual — strategy B).
    nB = length(feeder.branches)
    cone_b = Matrix{Float64}(undef, nB, Tfull)
    cong_b = Matrix{Float64}(undef, nB, Tfull)
    drop_b = Matrix{Float64}(undef, nB, Tfull)
    for b in 1:nB, t in 1:Tfull
        r = feeder.branches[b].r
        cone_b[b, t] = -dual(cone_constr[b, t])[3]                 # 3.39 P-slot (cone)
        # 3.36 P-slot (sending-end congestion) PLUS 3.37 P-slot (receiving-end congestion,
        # FIX-03/26-05, plan 26-10) — same sign convention (SAME cone shape, SAME filter),
        # empirically verified against the hard sum-to-price assertion below on IEEE-13's
        # PV back-feed window (t=9-16, bus 10) where :smax_rev binds and :smax is slack.
        cong_b[b, t] =
            -_smax_P(smax, smaxkeys, b, t) -
            (smax_rev === nothing ? 0.0 : _smax_P(smax_rev, smaxkeys, b, t))
        drop_b[b, t] = -2 * r * (dual(vdrop[b, t]) + dual(cpydrop[b, t]))  # 3.33/3.43 (drop)
    end

    # Accumulate along each node's unique root→j tree path (energy is the same root price).
    for j in 1:N
        pth = j == root ? Int[] : _path_branches(feeder, j)
        for t in 1:Tfull
            energy[j, t] = total[root, t]
            for b in pth
                cone[j, t] += cone_b[b, t]
                congestion[j, t] += cong_b[b, t]
                drop[j, t] += drop_b[b, t]
            end
        end
    end

    # HARD sum-to-nodal-price assertion (RESEARCH Success Criterion #2 / Pitfall 2). Relative-
    # tolerance, mirroring `assert_socp_exact!`'s scale-free `atol + rtol·max(...)` style. This
    # is the correctness NET: because each component came from a DISTINCT dual, a dropped or
    # mis-signed term produces an O(price) residual here rather than shipping a silently-wrong
    # split (threat T-05-02). The THROW path exists and fires whenever the reconstruction fails;
    # on a genuine exact SOCP optimum the residual is ~machine-epsilon.
    worst_res = 0.0
    worst_j = 0
    worst_t = 0
    for j in 1:N, t in 1:Tfull
        recon = energy[j, t] + cone[j, t] + congestion[j, t] + drop[j, t]
        res = abs(recon - total[j, t])
        if res > worst_res
            worst_res = res
            worst_j = j
            worst_t = t
        end
    end
    tol = atol + rtol * maximum(abs, total)
    worst_res <= tol || error(
        "decompose_dlmp: four-way split does NOT reconstruct the nodal DADP — worst residual " *
        "|energy+cone+congestion+drop − dual(balance_p)| = $worst_res at (bus=$worst_j, " *
        "t=$worst_t) exceeds tol=$tol (atol=$atol, rtol=$rtol). A component is missing or " *
        "mis-signed (RESEARCH Pitfall 2; thesis 3.31/3.33/3.36/3.39/3.43; threat T-05-02).",
    )

    reactive = extract_reactive_dlmp(ctx)               # (N, Tfull) reactive price (REACT-02)

    bus === nothing && return DlmpDecomposition(energy, cone, drop, congestion, reactive, total)
    Tsel = T === nothing ? Tfull : Int(T)
    rows = 1:Tsel
    return DlmpDecomposition(
        energy[bus, rows],
        cone[bus, rows],
        drop[bus, rows],
        congestion[bus, rows],
        reactive[bus, rows],
        total[bus, rows],
    )
end

export extract_dlmp, extract_reactive_dlmp, decompose_dlmp, DlmpDecomposition

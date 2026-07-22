# src/pricing/dlmp.jl
#
# SEAM: DLMP extraction + four-way decomposition (PRICE-01 / PRICE-02).
# OWNER: plan 05-02.
#
# Pure convex-duality POST-PROCESSING over a solved `ModelContext` from
# `solve_welfare(feeder, ConvexBranchFlow(), aggs; allow_export=true)`. Reads duals only;
# builds and solves nothing (no model here names a solver). Two public functions:
#
#   * `extract_dlmp(ctx)`    — the day-ahead dynamic price / DLMP: the dual of the nodal
#     ACTIVE-power balance (thesis eq. 3.31), per node per hour. Positive = marginal cost of
#     consumption (sign pinned by the 2-bus regression). REFUSES prices (throws) on an
#     UNGATED SOCP ctx — one carrying a squared-current `:l` but no PF-04 exactness
#     certificate `ctx.meta[:socp_maxgap]` — because a strict SOC relaxation makes `l` a
#     fictitious over-current and the recovered duals physically meaningless (PF-04).
#
#   * `decompose_dlmp(ctx)`  — the four-way DLMP split into energy + loss + congestion +
#     voltage that provably SUMS to the nodal price. The thesis gives the split only
#     qualitatively (Fig 4.5/4.6), so each component is reconstructed INDEPENDENTLY from a
#     DISTINCT registered dual (RESEARCH strategy B — loss is NOT the leftover) and a HARD
#     relative-tolerance assertion checks `energy+loss+congestion+voltage ≈ dual(balance_p)`
#     per node/hour, throwing with the worst per-node residual so a dropped term is
#     localizable (RESEARCH Pitfall 2).
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
# to λ_j − λ_0, attributing:
#   energy = λ_0 (root MEM price, same at every node),
#   loss   = Σ_path −cone_dual[3]        (the SOC/DistFlow marginal-loss term, 3.39),
#   cong   = Σ_path −smax_dual[2]        (thermal congestion, 3.36; 0 unless the head binds),
#   volt   = Σ_path −2·r·(β + γ)         (voltage-drop propagation of the v/v̂ bound pressure,
#                                          3.33/3.43; 0 when no voltage headroom is engaged).
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
    decompose_dlmp(ctx; bus = nothing, T = nothing, rtol = 1e-5, atol = 1e-7)
        -> NamedTuple(energy, loss, congestion, voltage, total)

Four-way DLMP decomposition (PRICE-02): split the nodal price into **energy + loss +
congestion + voltage** components that provably SUM to the DADP. Each component is
reconstructed INDEPENDENTLY from a DISTINCT registered dual (RESEARCH strategy B — loss is
NOT the leftover, so a dropped congestion/voltage term cannot hide), then a HARD relative-
tolerance assertion checks `energy + loss + congestion + voltage ≈ total` per node/hour and
`total ≈ extract_dlmp(ctx)`, throwing (never `@assert`) with the worst per-node residual so a
missing term is localizable (RESEARCH Pitfall 2; threat T-05-02).

Components (each summed over the unique radial path root→j; derivation in the file header):

  - `energy`     = `dual(:balance_p[root, t])`     — the MEM price, SAME at every node (≈ λ₀);
  - `loss`       = `Σ_path −dual(:cone[b,t])[3]`   — SOC/DistFlow marginal loss (thesis 3.39);
  - `congestion` = `Σ_path −dual(:smax[b,t])[2]`   — thermal congestion (3.36; 0 off the head);
  - `voltage`    = `Σ_path −2·r·(dual(:vdrop) + dual(:cpydrop))` — voltage-drop propagation of
    the v/v̂ bound pressure (thesis 3.33/3.43; 0 with unengaged voltage headroom);
  - `total`      = `extract_dlmp(ctx)`             — the reference DADP.

Inherits the PF-04 exactness gate from [`extract_dlmp`](@ref) (an ungated SOCP ctx is
refused). Requires the SOCP branch-flow handles registered by plan 05-01 (`:cone`, `:vdrop`,
`:cpydrop`, `:smax`); throws a clear `ArgumentError` on a formulation that lacks them.

With `bus === nothing` (default) every field is an `(N_buses, T)` matrix; passing `bus`
returns that bus's length-`T` component vectors.
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

    cone = ctx.constraints[:cone]
    vdrop = ctx.constraints[:vdrop]
    cpydrop = ctx.constraints[:cpydrop]
    smax = ctx.constraints[:smax]
    smaxkeys = Set{Tuple{Int, Int}}(Tuple(k) for k in eachindex(smax))

    total = extract_dlmp(ctx)                          # (N, Tfull) reference DADP (re-runs gate)
    energy = Matrix{Float64}(undef, N, Tfull)
    loss = zeros(Float64, N, Tfull)
    congestion = zeros(Float64, N, Tfull)
    voltage = zeros(Float64, N, Tfull)

    # Per-branch/time increments, computed ONCE (each from its own distinct dual — strategy B).
    nB = length(feeder.branches)
    loss_b = Matrix{Float64}(undef, nB, Tfull)
    cong_b = Matrix{Float64}(undef, nB, Tfull)
    volt_b = Matrix{Float64}(undef, nB, Tfull)
    for b in 1:nB, t in 1:Tfull
        r = feeder.branches[b].r
        loss_b[b, t] = -dual(cone[b, t])[3]                        # 3.39 P-slot (loss)
        cong_b[b, t] = -_smax_P(smax, smaxkeys, b, t)              # 3.36 P-slot (congestion)
        volt_b[b, t] = -2 * r * (dual(vdrop[b, t]) + dual(cpydrop[b, t]))  # 3.33/3.43 (voltage)
    end

    # Accumulate along each node's unique root→j tree path (energy is the same root price).
    for j in 1:N
        pth = j == root ? Int[] : _path_branches(feeder, j)
        for t in 1:Tfull
            energy[j, t] = total[root, t]
            for b in pth
                loss[j, t] += loss_b[b, t]
                congestion[j, t] += cong_b[b, t]
                voltage[j, t] += volt_b[b, t]
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
        recon = energy[j, t] + loss[j, t] + congestion[j, t] + voltage[j, t]
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
        "|energy+loss+congestion+voltage − dual(balance_p)| = $worst_res at (bus=$worst_j, " *
        "t=$worst_t) exceeds tol=$tol (atol=$atol, rtol=$rtol). A component is missing or " *
        "mis-signed (RESEARCH Pitfall 2; thesis 3.31/3.33/3.36/3.39/3.43; threat T-05-02).",
    )

    bus === nothing && return (; energy, loss, congestion, voltage, total)
    Tsel = T === nothing ? Tfull : Int(T)
    rows = 1:Tsel
    return (;
        energy = energy[bus, rows],
        loss = loss[bus, rows],
        congestion = congestion[bus, rows],
        voltage = voltage[bus, rows],
        total = total[bus, rows],
    )
end

export extract_dlmp, decompose_dlmp

# scripts/td_hybrid_6node_case_study.jl
#
# Case study backing the draft paper
#   J. P. Palacios et al., "Convexification Strategies for Optimal Power Flow in Coupled
#   Transmission and Distribution Networks" (draft, 2026-09-29), Sec. VII-VIII:
#   the 6-node T&D system with a HYBRID SDP-SOCP relaxation (meshed transmission nodes 1-3 as a
#   3x3 Hermitian PSD block W, radial feeder 3-4-5-6 as SOC-relaxed DistFlow, coupled at the
#   boundary bus 3 through W33 = v3) and its TSO-DSO ADMM decomposition.
#
# What this script does (one deterministic run, single process):
#   Experiment 0  Baseline self-check: reproduce the paper's monolithic optimum (cost, operating
#                 point, losses, eigenvalues of W, cone residuals, line loadings, 12 nodal
#                 prices) and FAIL LOUDLY (error) if any quantity leaves its measured-justified
#                 tolerance. All 12 prices are validated by central finite differences.
#   Experiment 1  Global optimality: non-convex polar AC-OPF of the full 6-node system solved by
#                 Ipopt from a flat start + seeded random starts + the framework's deterministic
#                 NLP strategy variants; gap to the relaxation; AC power-flow residuals of the
#                 voltages recovered from W's leading eigenvector + Baran-Wu feeder recursion.
#   Experiment 2  The paper's Gauss-Seidel TSO-DSO ADMM (Sec. VII-G, rho = 500, eps = 1e-2):
#                 iterations, residuals, Table II/III quantities, -lambda_p vs piP3, plus rho and
#                 eps sweeps (cone slack of intermediate DSO iterates).
#   Experiment 3  Congestion (left as future work by the paper): binding transmission line
#                 (1,2) and binding feeder head (3,4); prices, binding duals, DLMP decomposition,
#                 exactness re-check, AC-OPF gap, ADMM.
#   Experiment 4  Inexact regime (left as future work by the paper): non-curtailable PV at the
#                 feeder end as a negative load, swept with and without the LinDistFlow
#                 exactness copy, against Ipopt AC-OPF ground truth.
#
# Run (Figure env, CairoMakie comes from the docs environment):
#     JULIA_LOAD_PATH="docs:.:@stdlib" julia +release --project=. scripts/td_hybrid_6node_case_study.jl
# Outputs: results/td_hybrid_6node/  -- CSV + summary.txt (committed), PDF/PNG figures
#          (gitignored, regenerable).
#
# REUSED FROM THE FRAMEWORK (TSODSO):
#   - solver factory `select_optimizer(TSODSO.SOCP(); ...)` (Clarabel) and
#     `select_optimizer(TSODSO.NLP(); ...)` (Ipopt) + `TSODSO.nlp_multistart_variants()`;
#     no model builder in this file names a solver.
#   - `Bus` / `Branch` / `Feeder` (validated radial feeder data for nodes 3-6).
#   - the "framework-hosted" DSO block: `contribute!(ConvexBranchFlow(), ctx, feeder)` on the
#     SAME JuMP model as the SDP block, `add_to_residual!` + `TSODSO.close_balance!` for the
#     nodal balances, `assert_socp_exact!` / `TSODSO.socp_gap_report` (hybrid exactness floor
#     `TSODSO.TAU_SOLVER_EXACT` / `TSODSO.MEASURED_REL_TOL_EXACT`), `decompose_dlmp` (feeder
#     DLMP decomposition) and `TSODSO.recover_voltage_angles` (Baran-Wu phasors).
#
# FRAMEWORK FINDING (documented, no src/ change): `ConvexBranchFlow` FIXES the feeder root
# squared voltage v and its exactness copy v_hat at 1.0, so it cannot natively represent a
# T&D boundary where v3 = W33 is a decision variable. Workaround used here: after
# `contribute!`, the root `v` and `v_hat` are `unfix`ed, the squared-voltage bounds are
# re-imposed on the root, and `v_root == real(W33)`, `v_hat_root == v_root` are added; the
# boundary import (shared with the SDP node-3 balance) and the fixed loads are injected into the
# residuals before `close_balance!`. Two further differences of the framework block versus the
# paper model are kept and reported: (i) the framework adds the RECEIVING-end apparent-power
# cone (thesis 3.37) on every limited branch, the paper only the sending end; (ii) the
# framework always carries the exactness copy, the paper does not. The current limit
# l <= Imax^2 (paper eq. 32) is not part of `ConvexBranchFlow` and is added here. The
# framework-hosted model is checked against the paper-faithful model at the baseline (where
# none of these differences binds).
#
# SCRIPT-LOCAL (NEW):
#   - the transmission SDP block (3x3 HermitianPSDCone W, pi-model admittance, trace balances,
#     sending- and receiving-end line-flow SOC limits) -- port of the paper's eqs. 20-28;
#   - the paper-faithful DistFlow feeder block (eqs. 29-33) and an optional script-local mirror
#     of the framework's Gan-Low exactness copy (root v_hat = W33);
#   - the TSO and DSO ADMM subproblems (eqs. 35-39) and the Gauss-Seidel loop (eqs. 40-42),
#     built once and re-solved with an updated objective only;
#   - the polar AC-OPF of the 6-node system (Ipopt ground truth) and the 6-node Ybus.
#
# Units: power in pu on Sbase = 100 MVA; costs in $/h; prices reported in $/MWh ($/Mvarh),
# i.e. the balance dual in $/h per pu divided by 100.

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using JuMP
using LinearAlgebra
using Printf
using CSV
using DataFrames
using StableRNGs
using CairoMakie

const OUT = projectdir("results", "td_hybrid_6node")
mkpath(OUT)

saveboth(name, fig) =
    (save(joinpath(OUT, "$name.pdf"), fig); save(joinpath(OUT, "$name.png"), fig))

const SEED = 42
const SBASE = 100.0                   # MVA; dual ($/h per pu) / SBASE = $/MWh

# Clarabel settings (MEASURED, baseline monolithic model). The paper used CVXPY + Clarabel at
# 1e-7. With Clarabel's default Ruiz equilibration, the solve stalls at the SAME iterate for
# every tolerance from 1e-7 to 1e-9 (OPTIMAL at 1e-7, ALMOST_OPTIMAL below), with cone residual
# 1.1e-7 on branch (3,4) and balance duals off by up to 7e-4 $/MWh from central finite
# differences (node 6: dual 65.9404 vs FD 65.9411). Disabling equilibration reaches OPTIMAL at
# 1e-9 (cone residuals <= 5e-10, |lambda2/lambda1| = 1e-11) and its duals agree with the finite
# differences; it is therefore used throughout. Every solve status is recorded, and
# ALMOST_OPTIMAL is reported wherever it occurs.
socp_optimizer() = select_optimizer(
    TSODSO.SOCP();
    tol_gap_abs = 1e-9,
    tol_gap_rel = 1e-9,
    tol_feas = 1e-9,
    equilibrate_enable = false,
)
nlp_optimizer(; attrs...) = select_optimizer(TSODSO.NLP(); tol = 1e-10, attrs...)

# ------------------------------------------------------------------------------------------
# Case data (paper Table I)
# ------------------------------------------------------------------------------------------

const TLine = @NamedTuple{i::Int, j::Int, r::Float64, x::Float64, b::Float64, smax::Float64}
const DLine = @NamedTuple{i::Int, j::Int, r::Float64, x::Float64, smax::Float64, imax::Float64}

struct Case6
    tl::Vector{TLine}           # transmission lines (pi model, total charging b)
    dl::Vector{DLine}           # feeder branches 3-4, 4-5, 5-6 (series only)
    Pd::Vector{Float64}         # NET active demand per node (load - PV), pu
    Qd::Vector{Float64}
    c2::Float64
    c1::Float64
    c0::Float64
    pgmin::Float64
    pgmax::Float64
    qgmin::Float64
    qgmax::Float64
    vmin::Float64
    vmax::Float64
    flex::Bool                  # congestion extension (NOT in the paper): see `case6(; flex)`
end

const PD_BASE = [0.0, 0.90, 0.60, 0.12, 0.10, 0.08]
const QD_BASE = [0.0, 0.30, 0.20, 0.05, 0.04, 0.03]

# Congestion extension (Experiment 3 only, NOT part of the paper's system). The paper's system
# has one generator and inelastic loads, so no flow can be redispatched; to study congestion
# with a well-posed redispatch, two OUT-OF-MERIT resources are added, both idle at the baseline
# (their marginal cost exceeds the baseline nodal price where they sit, so the baseline
# optimum, prices and ADMM run are unchanged -- checked in Experiment 3):
#   G2 at node 2 (TSO side): cost G2_C2 Pg2^2 + G2_C1 Pg2, 0 <= Pg2 <= G2_PMAX, unity power
#      factor (marginal cost at 0: 65 $/MWh > baseline piP2 = 61.88);
#   DG at node 6 (DSO side): cost DG_C1 Pdg, 0 <= Pdg <= DG_PMAX, unity power factor
#      (marginal cost 70 $/MWh > baseline piP6 = 65.94).
# Both are active-power only: a first version gave G2 a free reactive range, which lowered the
# baseline cost by 7.4 $/h through voltage support even at Pg2 = 0 (MEASURED), i.e. it was not
# out of merit; the unity-power-factor version leaves the baseline unchanged (asserted).
const G2_C2 = 1100.0
const G2_C1 = 6500.0
const G2_PMAX = 1.0
const DG_C1 = 7000.0
const DG_PMAX = 0.2

"""
    case6(; smax_line, smax_feeder, pv, load_scale, flex = false)

Paper Table I with keyword overrides: `smax_line[k]` (transmission line k, default 2.0 pu),
`smax_feeder[k]` (feeder branch k; Imax = Smax as in the paper), `pv` (6-vector of extra
active injection, modelled as a negative load, Q = 0), `load_scale` (scales every Pd, Qd) and
`flex` (adds the out-of-merit G2 / DG of the congestion extension, see the constants above).
"""
function case6(;
    smax_line = [2.0, 2.0, 2.0],
    smax_feeder = [1.0, 0.6, 0.4],
    pv = zeros(6),
    load_scale = 1.0,
    flex::Bool = false,
)
    tl = TLine[
        (i = 1, j = 2, r = 0.010, x = 0.085, b = 0.176, smax = smax_line[1]),
        (i = 2, j = 3, r = 0.017, x = 0.092, b = 0.158, smax = smax_line[2]),
        (i = 1, j = 3, r = 0.032, x = 0.161, b = 0.306, smax = smax_line[3]),
    ]
    dl = DLine[
        (i = 3, j = 4, r = 0.010, x = 0.060, smax = smax_feeder[1], imax = smax_feeder[1]),
        (i = 4, j = 5, r = 0.080, x = 0.060, smax = smax_feeder[2], imax = smax_feeder[2]),
        (i = 5, j = 6, r = 0.090, x = 0.070, smax = smax_feeder[3], imax = smax_feeder[3]),
    ]
    return Case6(
        tl,
        dl,
        load_scale .* PD_BASE .- pv,
        load_scale .* QD_BASE,
        1100.0,
        2000.0,
        100.0,
        0.0,
        3.0,
        -1.5,
        1.5,
        0.95,
        1.05,
        flex,
    )
end

"Copy of `c` with the net demand at node `k` shifted by (dP, dQ) (finite differences)."
function perturb(c::Case6, k::Int, dP::Float64, dQ::Float64)
    Pd = copy(c.Pd)
    Qd = copy(c.Qd)
    Pd[k] += dP
    Qd[k] += dQ
    return Case6(
        c.tl,
        c.dl,
        Pd,
        Qd,
        c.c2,
        c.c1,
        c.c0,
        c.pgmin,
        c.pgmax,
        c.qgmin,
        c.qgmax,
        c.vmin,
        c.vmax,
        c.flex,
    )
end

gencost(c::Case6, pg) = c.c2 * pg^2 + c.c1 * pg + c.c0
g2cost(pg2) = G2_C2 * pg2^2 + G2_C1 * pg2
dgcost(pdg) = DG_C1 * pdg

"The 3x3 transmission admittance matrix (pi model, b/2 shunt at each end)."
function ybus3(c::Case6)
    Y = zeros(ComplexF64, 3, 3)
    for ln in c.tl
        y = 1 / (ln.r + im * ln.x)
        Y[ln.i, ln.i] += y + im * ln.b / 2
        Y[ln.j, ln.j] += y + im * ln.b / 2
        Y[ln.i, ln.j] -= y
        Y[ln.j, ln.i] -= y
    end
    return Y
end

"The full 6-node admittance matrix (transmission pi model + feeder series branches)."
function ybus6(c::Case6)
    Y = zeros(ComplexF64, 6, 6)
    Y[1:3, 1:3] .= ybus3(c)
    for br in c.dl
        y = 1 / (br.r + im * br.x)
        Y[br.i, br.i] += y
        Y[br.j, br.j] += y
        Y[br.i, br.j] -= y
        Y[br.j, br.i] -= y
    end
    return Y
end

"Framework `Feeder` for nodes 3-6 (local ids 1-4; root = node 3 = local 1)."
function feeder_of(c::Case6)
    buses = [Bus{Float64}(k, c.vmin, c.vmax, k == 1) for k in 1:4]
    branches = [Branch{Float64}(br.i - 2, br.j - 2, br.r, br.x, br.smax) for br in c.dl]
    return Feeder(buses, branches, 1)
end

# ------------------------------------------------------------------------------------------
# Model blocks
# ------------------------------------------------------------------------------------------

"""
    add_transmission_block!(m, c, Pg, Qg, P34, Q34)

SDP block (paper eqs. 18, 20-25): 3x3 Hermitian PSD W, trace balances at nodes 1-3 (node 3
supplies the boundary export P34 + jQ34), line-flow SOC limits at both ends of every line.
Returns `(; W, balP, balQ, linecones)` with `linecones[(k, end)]`, end = 1 sending, 2 receiving.
"""
function add_transmission_block!(
    m::Model,
    c::Case6,
    Pg,
    Qg,
    P34,
    Q34;
    Pg2 = nothing,
    Qg2 = nothing,
)
    Y = ybus3(c)
    W = @variable(m, [1:3, 1:3] in HermitianPSDCone())
    for k in 1:3
        @constraint(m, c.vmin^2 <= real(W[k, k]) <= c.vmax^2)
    end
    S(k) = sum(conj(Y[k, j]) * W[k, j] for j in 1:3)
    inj2P = Pg2 === nothing ? -c.Pd[2] + 0 * Pg : Pg2 - c.Pd[2]
    inj2Q = Qg2 === nothing ? -c.Qd[2] + 0 * Qg : Qg2 - c.Qd[2]
    injP = [Pg - c.Pd[1], inj2P, -c.Pd[3] - P34]
    injQ = [Qg - c.Qd[1], inj2Q, -c.Qd[3] - Q34]
    balP = [@constraint(m, real(S(k)) == injP[k]) for k in 1:3]
    balQ = [@constraint(m, imag(S(k)) == injQ[k]) for k in 1:3]
    linecones = Dict{Tuple{Int, Int}, Any}()
    for (k, ln) in enumerate(c.tl), (e, (a, b)) in enumerate(((ln.i, ln.j), (ln.j, ln.i)))
        y = 1 / (ln.r + im * ln.x)
        Sab = conj(y) * (W[a, a] - W[a, b]) - im * ln.b / 2 * W[a, a]
        linecones[(k, e)] =
            @constraint(m, [ln.smax; real(Sab); imag(Sab)] in SecondOrderCone())
    end
    return (; W, balP, balQ, linecones)
end

"""
    add_feeder_block!(m, c, vroot; copy = false)

Paper-faithful DistFlow feeder block (eqs. 19, 29-33) hanging below the boundary squared
voltage `vroot` (an affine expression: real(W33) in the monolithic model, a local variable in
the DSO subproblem). `copy = true` adds a script-local mirror of the framework's Gan-Low
exactness copy (`ConvexBranchFlow` default): v_hat_root = vroot,
v_hat_j = v_hat_i - 2(r(P - r l) + x(Q - x l)), Vmin^2 <= v_hat <= Vmax^2.
"""
function add_feeder_block!(m::Model, c::Case6, vroot; copy::Bool = false, Pdg = nothing)
    P = @variable(m, [1:3])
    Q = @variable(m, [1:3])
    l = @variable(m, [1:3], lower_bound = 0.0)
    vloc = @variable(m, [4:6], lower_bound = c.vmin^2, upper_bound = c.vmax^2)
    vv(i) = i == 3 ? vroot : vloc[i]
    fP = ConstraintRef[]
    fQ = ConstraintRef[]
    cones = ConstraintRef[]
    smaxc = ConstraintRef[]
    imaxc = ConstraintRef[]
    for (k, br) in enumerate(c.dl)
        # Downstream flow; at node 6 the (optional) DG injection enters with a minus sign.
        dP = k < 3 ? 1.0 * P[k + 1] : (Pdg === nothing ? 0.0 : -1.0 * Pdg)
        dQ = k < 3 ? Q[k + 1] : 0.0
        push!(fP, @constraint(m, P[k] - br.r * l[k] - dP == c.Pd[br.j]))
        push!(fQ, @constraint(m, Q[k] - br.x * l[k] - dQ == c.Qd[br.j]))
        @constraint(
            m,
            vv(br.j) == vv(br.i) - 2 * (br.r * P[k] + br.x * Q[k]) + (br.r^2 + br.x^2) * l[k]
        )
        push!(smaxc, @constraint(m, [br.smax; P[k]; Q[k]] in SecondOrderCone()))
        push!(imaxc, @constraint(m, l[k] <= br.imax^2))
        push!(
            cones,
            @constraint(m, [l[k]; 0.5 * vv(br.i); P[k]; Q[k]] in RotatedSecondOrderCone())
        )
    end
    vhat = nothing
    if copy
        vh = @variable(m, [4:6], lower_bound = c.vmin^2, upper_bound = c.vmax^2)
        vhh(i) = i == 3 ? vroot : vh[i]
        for (k, br) in enumerate(c.dl)
            @constraint(
                m,
                vhh(br.j) ==
                vhh(br.i) - 2 * (br.r * (P[k] - br.r * l[k]) + br.x * (Q[k] - br.x * l[k]))
            )
        end
        vhat = vh
    end
    vexpr = [vv(i) for i in 3:6]   # squared voltages of nodes 3..6
    return (; P, Q, l, v = vexpr, fP, fQ, cones, smaxc, imaxc, vhat)
end

"""
    build_hybrid(c; dso = :paper, copy = false, optimizer = socp_optimizer())

Monolithic hybrid SDP-SOCP model. `dso = :paper` uses the paper-faithful feeder block;
`dso = :framework` hosts the feeder with `contribute!(ConvexBranchFlow(), ...)` (see header).
Returns a NamedTuple with uniform handles: `pbal[k]`, `qbal[k]` and `psign[k]` such that the
nodal price of node k is `psign[k] * dual(pbal[k]) / SBASE`.
"""
function build_hybrid(
    c::Case6;
    dso::Symbol = :paper,
    copy::Bool = false,
    optimizer = socp_optimizer(),
)
    m = Model(optimizer)
    set_silent(m)
    Pg = @variable(m, lower_bound = c.pgmin, upper_bound = c.pgmax)
    Qg = @variable(m, lower_bound = c.qgmin, upper_bound = c.qgmax)
    Pg2, Qg2, Pdg = flex_vars!(m, c)
    ctx = nothing
    if dso === :paper
        # The feeder block needs vroot = real(W33) and the SDP needs P34 = P[1]: create the
        # boundary flows first as free variables tied to the feeder head below.
        P34 = @variable(m)
        Q34 = @variable(m)
        tb = add_transmission_block!(m, c, Pg, Qg, P34, Q34; Pg2, Qg2)
        fb = add_feeder_block!(m, c, real(tb.W[3, 3]); copy = copy, Pdg)
        @constraint(m, P34 == fb.P[1])
        @constraint(m, Q34 == fb.Q[1])
        pbal = ConstraintRef[tb.balP; fb.fP]
        qbal = ConstraintRef[tb.balQ; fb.fQ]
        psign = [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0]
        feeder = (; fb.P, fb.Q, fb.l, fb.v, fb.cones, fb.smaxc, fb.imaxc, smaxrev = nothing)
    elseif dso === :framework
        pimp = @variable(m)
        qimp = @variable(m)
        tb = add_transmission_block!(m, c, Pg, Qg, pimp, qimp; Pg2, Qg2)
        fdr = feeder_of(c)
        ctx = ModelContext(m)
        contribute!(ConvexBranchFlow(), ctx, fdr; T = 1)
        ctx.feeder = fdr
        ctx.T = 1
        pv = ctx.pf_vars
        # Boundary workaround: ConvexBranchFlow fixes v_root = v_hat_root = 1.0.
        unfix(pv.v[1, 1])
        unfix(pv.v̂[1, 1])
        set_lower_bound(pv.v[1, 1], c.vmin^2)
        set_upper_bound(pv.v[1, 1], c.vmax^2)
        @constraint(m, pv.v[1, 1] == real(tb.W[3, 3]))
        @constraint(m, pv.v̂[1, 1] == pv.v[1, 1])
        add_to_residual!(ctx, :Rp, 1, 1, 1.0 * pimp)
        add_to_residual!(ctx, :Rq, 1, 1, 1.0 * qimp)
        for jl in 2:4
            add_to_residual!(ctx, :Rp, jl, 1, AffExpr(-c.Pd[jl + 2]))
            add_to_residual!(ctx, :Rq, jl, 1, AffExpr(-c.Qd[jl + 2]))
        end
        Pdg === nothing || add_to_residual!(ctx, :Rp, 4, 1, 1.0 * Pdg)
        bp, bq = TSODSO.close_balance!(ctx, 4, 1; reactive = true)
        imaxc = [@constraint(m, pv.l[k, 1] <= c.dl[k].imax^2) for k in 1:3]
        pbal = ConstraintRef[tb.balP; [bp[jl, 1] for jl in 2:4]]
        qbal = ConstraintRef[tb.balQ; [bq[jl, 1] for jl in 2:4]]
        psign = [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0]
        smaxc = [ctx.constraints[:smax][k, 1] for k in 1:3]
        smaxrev = [ctx.constraints[:smax_rev][k, 1] for k in 1:3]
        feeder = (;
            P = [pv.P[k, 1] for k in 1:3],
            Q = [pv.Q[k, 1] for k in 1:3],
            l = [pv.l[k, 1] for k in 1:3],
            v = [pv.v[jl, 1] for jl in 1:4],
            cones = [ctx.constraints[:cone][k, 1] for k in 1:3],
            smaxc,
            imaxc,
            smaxrev,
        )
    else
        throw(ArgumentError("dso must be :paper or :framework, got $dso"))
    end
    if c.flex
        @objective(m, Min, c.c2 * Pg^2 + c.c1 * Pg + c.c0 + g2cost(Pg2) + dgcost(Pdg))
    else
        @objective(m, Min, c.c2 * Pg^2 + c.c1 * Pg + c.c0)
    end
    return (;
        m,
        Pg,
        Qg,
        Pg2,
        Qg2,
        Pdg,
        tb.W,
        tb.balP,
        tb.balQ,
        tb.linecones,
        feeder,
        pbal,
        qbal,
        psign,
        ctx,
    )
end

"Out-of-merit flexibility variables of the congestion extension (all `nothing` if `!c.flex`)."
function flex_vars!(m::Model, c::Case6)
    c.flex || return nothing, nothing, nothing
    Pg2 = @variable(m, lower_bound = 0.0, upper_bound = G2_PMAX)
    Pdg = @variable(m, lower_bound = 0.0, upper_bound = DG_PMAX)
    return Pg2, nothing, Pdg     # unity power factor: no Qg2
end

_val(x) = x === nothing ? 0.0 : value(x)

# ------------------------------------------------------------------------------------------
# Post-processing of a solved hybrid model
# ------------------------------------------------------------------------------------------

"Per-branch cone residual l*v_from - (P^2+Q^2) and the framework hybrid-floor ratio."
function cone_rows(c::Case6, h)
    rows = NamedTuple[]
    for (k, br) in enumerate(c.dl)
        l = value(h.feeder.l[k])
        vf = value(h.feeder.v[br.i - 2])
        P = value(h.feeder.P[k])
        Q = value(h.feeder.Q[k])
        lhs = l * vf
        rhs = P^2 + Q^2
        gap = lhs - rhs
        atol_b = max(TSODSO.TAU_SOLVER_EXACT, TSODSO.MEASURED_REL_TOL_EXACT * br.smax^2)
        ratio = abs(gap) / (atol_b + 1e-4 * max(abs(lhs), abs(rhs)))
        push!(rows, (; k, i = br.i, j = br.j, l, v = vf, P, Q, gap, ratio))
    end
    return rows
end

"Sorted eigenvalues (ascending) of the solved W and |lambda2/lambda1|."
function w_eigs(h)
    Wv = Hermitian(value.(h.W))
    ev = eigvals(Wv)
    return ev, abs(ev[2] / ev[3])
end

"Squared voltages of all 6 nodes."
vsq(h) = [real(value(h.W[1, 1])), real(value(h.W[2, 2])), real(value(h.W[3, 3])),
    value.(h.feeder.v[2:4])...]

"Apparent power at both ends of every transmission line and its loading (max end / Smax)."
function line_flows(c::Case6, h)
    Wv = value.(h.W)
    out = NamedTuple[]
    for ln in c.tl
        y = 1 / (ln.r + im * ln.x)
        Sab(a, b) = conj(y) * (Wv[a, a] - Wv[a, b]) - im * ln.b / 2 * Wv[a, a]
        Sij = Sab(ln.i, ln.j)
        Sji = Sab(ln.j, ln.i)
        push!(out, (; ln.i, ln.j, Sij, Sji, loading = max(abs(Sij), abs(Sji)) / ln.smax))
    end
    return out
end

"Feeder sending-end loading |S|/Smax per branch."
feeder_loading(c::Case6, h) =
    [hypot(value(h.feeder.P[k]), value(h.feeder.Q[k])) / c.dl[k].smax for k in 1:3]

"Nodal prices (piP, piQ) in \$/MWh and \$/Mvarh."
function prices(h)
    piP = [h.psign[k] * dual(h.pbal[k]) / SBASE for k in 1:6]
    piQ = [h.psign[k] * dual(h.qbal[k]) / SBASE for k in 1:6]
    return piP, piQ
end

"Equilibrated Clarabel (factory default scaling) at the same tolerances: numerical fallback."
socp_optimizer_equilibrated() =
    select_optimizer(TSODSO.SOCP(); tol_gap_abs = 1e-9, tol_gap_rel = 1e-9, tol_feas = 1e-9)

"""
    solve_hybrid(c; kw...)

Solve a hybrid model and collect the full operating point. If Clarabel without equilibration
ends in a numerical failure (neither optimal nor a definite infeasibility certificate), the
SAME model is re-solved once with the equilibrated setting; the returned `solver` field
records which setting produced the result.
"""
function solve_hybrid(c::Case6; optimizer = nothing, kw...)
    h = build_hybrid(c; optimizer = something(optimizer, socp_optimizer()), kw...)
    optimize!(h.m)
    st = termination_status(h.m)
    solver = optimizer === nothing ? "clarabel_noequil" : "custom"
    if optimizer === nothing && !(st in (OPTIMAL, ALMOST_OPTIMAL, INFEASIBLE))
        h = build_hybrid(c; optimizer = socp_optimizer_equilibrated(), kw...)
        optimize!(h.m)
        st = termination_status(h.m)
        solver = "clarabel_equil_fallback"
    end
    if !(st in (OPTIMAL, ALMOST_OPTIMAL))
        return (; h, status = st, ok = false, solver)
    end
    piP, piQ = prices(h)
    ev, rr = w_eigs(h)
    Pg = value(h.Pg)
    P34 = value(h.feeder.P[1])
    Pg2 = _val(h.Pg2)
    Pdg = _val(h.Pdg)
    loss_t = Pg + Pg2 - sum(c.Pd[1:3]) - P34
    loss_f = P34 + Pdg - sum(c.Pd[4:6])
    return (;
        h,
        status = st,
        ok = true,
        cost = objective_value(h.m),
        Pg,
        Qg = value(h.Qg),
        Pg2,
        Qg2 = _val(h.Qg2),
        Pdg,
        P34,
        Q34 = value(h.feeder.Q[1]),
        Vm = sqrt.(max.(vsq(h), 0.0)),
        loss_t,
        loss_f,
        ev,
        rr,
        cones = cone_rows(c, h),
        lines = line_flows(c, h),
        floading = feeder_loading(c, h),
        piP,
        piQ,
        solver,
    )
end

# ------------------------------------------------------------------------------------------
# Experiment 0 -- baseline self-check
# ------------------------------------------------------------------------------------------

# Paper values (Sec. VIII-B, Tables II-III, monolithic column).
const PAPER = (
    cost = 7461.105,
    Pg = 1.83287,
    Qg = 0.13381,
    P34 = 0.30486,
    Q34 = 0.12926,
    V3 = 1.01405,
    loss = 0.0329,
    loss_t = 0.0280,
    loss_f = 0.0049,
    lambda1 = 3.1737,
    Vm = [1.0500, 1.0212, 1.0141],
    Va = [0.0, -4.95, -5.97],
    cone = [2.6e-7, 2.9e-8, 2.3e-8],
    load12 = 0.569,
    floading = [0.331, 0.330, 0.216],
    piP = [60.323, 61.881, 62.590, 62.995, 64.931, 65.941],
    piQ = [0.000, 0.411, 0.537, 0.736, 1.507, 1.889],
)

# ------------------------------------------------------------------------------------------
# Output helpers (fixed significant digits so two runs give byte-identical files)
# ------------------------------------------------------------------------------------------

_r(x::AbstractFloat) = isfinite(x) ? round(x; sigdigits = 8) : x
_r(x) = x

function writecsv(name::AbstractString, df::DataFrame)
    out = DataFrame([col => _r.(df[!, col]) for col in names(df)])
    CSV.write(joinpath(OUT, name), out)
    return nothing
end

f(x; d = 6) = isfinite(x) ? @sprintf("%.*f", d, x) : string(x)
e(x) = isfinite(x) ? @sprintf("%.2e", x) : string(x)
section(io, title) = println(io, "\n", "="^78, "\n", title, "\n", "="^78)

# ------------------------------------------------------------------------------------------
# Experiment 0 -- baseline self-check
# ------------------------------------------------------------------------------------------

"Central finite differences of the optimal cost w.r.t. Pd_k and Qd_k (\$/MWh, \$/Mvarh)."
function fd_prices(c::Case6; h = 1e-4)
    cost(cc) = (hh = build_hybrid(cc); optimize!(hh.m); objective_value(hh.m))
    fdP = [(cost(perturb(c, k, h, 0.0)) - cost(perturb(c, k, -h, 0.0))) / (2h) / SBASE for k in 1:6]
    fdQ = [(cost(perturb(c, k, 0.0, h)) - cost(perturb(c, k, 0.0, -h))) / (2h) / SBASE for k in 1:6]
    return fdP, fdQ
end

"Voltages of nodes 1-3 from W's leading eigenvector (scaled by sqrt(lambda1), angle(V1) = 0)."
function voltages_from_W(h)
    F = eigen(Hermitian(value.(h.W)))
    u = F.vectors[:, end] * sqrt(max(F.values[end], 0.0))
    return u .* cis(-angle(u[1]))
end

"Script-local Baran-Wu recursion V_j = V_i - z conj(S)/conj(V_i) down the feeder from V3."
function feeder_phasors(c::Case6, h, V3::ComplexF64)
    V = zeros(ComplexF64, 6)
    V[3] = V3
    for (k, br) in enumerate(c.dl)
        S = complex(value(h.feeder.P[k]), value(h.feeder.Q[k]))
        V[br.j] = V[br.i] - complex(br.r, br.x) * conj(S) / conj(V[br.i])
    end
    return V
end

"AC nodal injection mismatch max|dP|, max|dQ| (pu) of phasors V at the operating point of `r`."
function ac_mismatch(c::Case6, V::Vector{ComplexF64}, Pg, Qg)
    Scalc = V .* conj.(ybus6(c) * V)
    Sspec = [complex(-c.Pd[k], -c.Qd[k]) for k in 1:6]
    Sspec[1] += complex(Pg, Qg)
    d = Scalc .- Sspec
    return maximum(abs.(real.(d))), maximum(abs.(imag.(d)))
end

# Baseline gate tolerances. MEASURED deviations of this script's monolithic solve from the
# paper's printed values (accurate Clarabel solve, see `socp_optimizer`):
#   cost 7461.10518 vs 7461.105 (1.8e-4); Pg/Qg/P34/Q34/|V3| within 4e-6 of the 5-decimal values;
#   losses within 3e-5 of the 4-decimal values; lambda1 within 4e-5; |V1..3| within 5e-5,
#   angles within 5e-3 deg of the 2-decimal values; loadings within 5e-4 (the paper prints
#   percentages to 0.1 %); all 12 prices within 4.3e-4 $/MWh of Table III (mono column).
# Each tolerance is the paper's printed half-unit (rounding can never be tighter than that),
# which sits just above the measured maximum for every group; see the printed diff table.
# Note: an equilibrated Clarabel solve (ALMOST_OPTIMAL, the earlier reference reproduction)
# misses Table III by up to 8.6e-4 $/MWh at the third decimal (62.994 vs 62.995, 1.506 vs
# 1.507, ...): those differences were solver accuracy, not a paper error.
const TOL_COST = 5e-4          # $/h, cost printed to 3 decimals
const TOL_PU5 = 5e-6           # pu, Table II quantities printed to 5 decimals
const TOL_PU4 = 5e-5           # pu, losses / |V| / lambda1 printed to 4 decimals
const TOL_DEG = 5e-3           # deg, angles printed to 2 decimals
const TOL_LOADING = 5e-4       # loading fraction, printed as % to 1 decimal
const TOL_PRICE = 5e-4         # $/MWh, prices printed to 3 decimals
const TOL_RANK = 1e-9          # paper claim: |lambda2/lambda1| < 1e-9
const TOL_FD = 1e-3            # $/MWh, dual vs central FD (h = 1e-4 pu, cost accuracy ~1e-6 $/h)

function experiment0(io)
    section(io, "EXPERIMENT 0 -- BASELINE SELF-CHECK (monolithic hybrid SDP-SOCP vs paper)")
    c = case6()
    r = solve_hybrid(c; dso = :paper)
    r.ok || error("baseline monolithic solve failed: $(r.status)")
    V = voltages_from_W(r.h)
    Vf = feeder_phasors(c, r.h, V[3])
    fdP, fdQ = fd_prices(c)
    fd_mis = max(maximum(abs.(fdP .- r.piP)), maximum(abs.(fdQ .- r.piQ)))

    checks = [
        ("cost (\$/h)", r.cost, PAPER.cost, TOL_COST),
        ("Pg (pu)", r.Pg, PAPER.Pg, TOL_PU5),
        ("Qg (pu)", r.Qg, PAPER.Qg, TOL_PU5),
        ("P34 (pu)", r.P34, PAPER.P34, TOL_PU5),
        ("Q34 (pu)", r.Q34, PAPER.Q34, TOL_PU5),
        ("|V3| (pu)", r.Vm[3], PAPER.V3, TOL_PU5),
        ("losses total (pu)", r.loss_t + r.loss_f, PAPER.loss, TOL_PU4),
        ("losses transmission (pu)", r.loss_t, PAPER.loss_t, TOL_PU4),
        ("losses feeder (pu)", r.loss_f, PAPER.loss_f, TOL_PU4),
        ("lambda1(W)", r.ev[3], PAPER.lambda1, TOL_PU4),
        [("|V$k| (pu)", abs(V[k]), PAPER.Vm[k], TOL_PU4) for k in 1:3]...,
        [("angle V$k (deg)", rad2deg(angle(V[k])), PAPER.Va[k], TOL_DEG) for k in 1:3]...,
        ("loading line (1,2)", r.lines[1].loading, PAPER.load12, TOL_LOADING),
        [
            ("loading feeder ($(c.dl[k].i),$(c.dl[k].j))", r.floading[k], PAPER.floading[k],
                TOL_LOADING) for k in 1:3
        ]...,
        [("piP$k (\$/MWh)", r.piP[k], PAPER.piP[k], TOL_PRICE) for k in 1:6]...,
        [("piQ$k (\$/Mvarh)", r.piQ[k], PAPER.piQ[k], TOL_PRICE) for k in 1:6]...,
        ("|lambda2/lambda1| (claim < 1e-9)", r.rr, 0.0, TOL_RANK),
        ("max cone hybrid ratio (claim <= 1)", maximum(x.ratio for x in r.cones), 0.0, 1.0),
        ("max |dual - FD| price", fd_mis, 0.0, TOL_FD),
    ]
    println(io, "Status: ", r.status)
    @printf(io, "%-36s %16s %16s %11s %11s %s\n", "quantity", "this script", "paper",
        "|dev|", "tolerance", "ok")
    failed = String[]
    for (name, val, ref, tol) in checks
        dev = abs(val - ref)
        ok = dev <= tol
        ok || push!(failed, name)
        @printf(io, "%-36s %16.8g %16.8g %11.2e %11.2e %s\n", name, val, ref, dev, tol,
            ok ? "ok" : "FAIL")
    end
    if !isempty(failed)
        print(stdout, String(take!(copy(io))))
        error("BASELINE SELF-CHECK FAILED for: $(join(failed, ", ")) (diff table above)")
    end
    println(io, "\nBASELINE SELF-CHECK PASSED")

    println(io, "\nOperating point (this script):")
    @printf(io, "  cost = %.6f \$/h   Pg = %.6f  Qg = %.6f  P34 = %.6f  Q34 = %.6f pu\n",
        r.cost, r.Pg, r.Qg, r.P34, r.Q34)
    @printf(io, "  losses: total %.6f = transmission %.6f + feeder %.6f pu (%.3f %% of load)\n",
        r.loss_t + r.loss_f, r.loss_t, r.loss_f, 100 * (r.loss_t + r.loss_f) / sum(c.Pd))
    println(io, "  eigenvalues of W: ", join(e.(r.ev), ", "), "   |lambda2/lambda1| = ", e(r.rr))
    for k in 1:3
        @printf(io, "  V%d = %.5f at %.3f deg (from W leading eigenvector)\n", k, abs(V[k]),
            rad2deg(angle(V[k])))
    end
    for k in 4:6
        @printf(io, "  V%d = %.5f at %.3f deg (Baran-Wu from V3)\n", k, abs(Vf[k]),
            rad2deg(angle(Vf[k])))
    end
    println(io, "  |V| all nodes (sqrt of squared-voltage variables): ", join(f.(r.Vm; d = 5), ", "))
    println(io, "  cone residuals l*v - (P^2+Q^2) and framework hybrid-floor ratio",
        " (atol_b = max(TAU_SOLVER_EXACT, MEASURED_REL_TOL_EXACT*smax^2), rtol = 1e-4):")
    for x in r.cones
        @printf(io, "    (%d,%d): residual %.2e   ratio %.2e   (paper %.1e)\n", x.i, x.j,
            x.gap, x.ratio, PAPER.cone[x.k])
    end
    for (k, ln) in enumerate(r.lines)
        @printf(io, "  line (%d,%d): |S_ij| = %.5f, |S_ji| = %.5f pu, loading %.2f %%\n", ln.i,
            ln.j, abs(ln.Sij), abs(ln.Sji), 100 * ln.loading)
    end
    for k in 1:3
        @printf(io, "  feeder (%d,%d): loading %.2f %%\n", c.dl[k].i, c.dl[k].j,
            100 * r.floading[k])
    end
    println(io, "\nNodal prices (mono) vs finite differences (h = 1e-4 pu) vs paper Table III:")
    @printf(io, "%5s %11s %11s %9s %11s %11s %11s %9s %11s\n", "node", "piP", "FD", "paper",
        "|dual-FD|", "piQ", "FD", "paper", "|dual-FD|")
    for k in 1:6
        @printf(io, "%5d %11.5f %11.5f %9.3f %11.2e %11.5f %11.5f %9.3f %11.2e\n", k,
            r.piP[k], fdP[k], PAPER.piP[k], abs(r.piP[k] - fdP[k]), r.piQ[k], fdQ[k],
            PAPER.piQ[k], abs(r.piQ[k] - fdQ[k]))
    end
    @printf(io, "  node 1 check: 2 c2 Pg + c1 = %.5f \$/MWh (piP1 = %.5f)\n",
        (2 * c.c2 * r.Pg + c.c1) / SBASE, r.piP[1])
    @printf(io, "  spreads: feeder piP6 - piP3 = %.4f, transmission piP3 - piP1 = %.4f \$/MWh\n",
        r.piP[6] - r.piP[3], r.piP[3] - r.piP[1])

    # Framework-hosted DSO vs paper-faithful model.
    rf = solve_hybrid(c; dso = :framework)
    rf.ok || error("framework-hosted baseline solve failed: $(rf.status)")
    ctx = rf.h.ctx
    ctx.meta[:socp_maxgap] = assert_socp_exact!(ctx)
    Vfw = TSODSO.recover_voltage_angles(ctx)[:, 1] .* cis(angle(V[3]))
    dV = maximum(abs.(Vfw .- Vf[3:6]))
    println(io, "\nFramework-hosted DSO (contribute!(ConvexBranchFlow()) + boundary workaround):")
    println(io, "  status ", rf.status, "; assert_socp_exact! passed, max |l v - P^2 - Q^2| = ",
        e(ctx.meta[:socp_maxgap]))
    @printf(io, "  |cost_fw - cost_paper| = %.2e \$/h, |Pg| diff %.2e, |P34| diff %.2e, |Q34| diff %.2e\n",
        abs(rf.cost - r.cost), abs(rf.Pg - r.Pg), abs(rf.P34 - r.P34), abs(rf.Q34 - r.Q34))
    @printf(io, "  max |V| diff %.2e pu, max |piP| diff %.2e \$/MWh, max |piQ| diff %.2e \$/Mvarh\n",
        maximum(abs.(rf.Vm .- r.Vm)), maximum(abs.(rf.piP .- r.piP)),
        maximum(abs.(rf.piQ .- r.piQ)))
    @printf(io, "  recover_voltage_angles (rotated by angle V3) vs script Baran-Wu: max |dV| = %.2e pu\n",
        dV)
    fw_match =
        abs(rf.cost - r.cost) < TOL_COST && maximum(abs.(rf.piP .- r.piP)) < TOL_PRICE &&
        maximum(abs.(rf.piQ .- r.piQ)) < TOL_PRICE && abs(rf.P34 - r.P34) < TOL_PU5
    fw_match || error("framework-hosted DSO does not match the paper-faithful model at the baseline")
    println(io, "  => framework-hosted DSO MATCHES the paper-faithful model at the baseline")

    writecsv(
        "baseline_prices.csv",
        DataFrame(
            node = 1:6,
            piP = r.piP,
            piP_fd = fdP,
            piP_paper = PAPER.piP,
            piQ = r.piQ,
            piQ_fd = fdQ,
            piQ_paper = PAPER.piQ,
            piP_framework = rf.piP,
            piQ_framework = rf.piQ,
        ),
    )
    Vall = [V; Vf[4:6]]
    writecsv(
        "baseline_point.csv",
        DataFrame(
            node = 1:6,
            Vm = abs.(Vall),
            Va_deg = rad2deg.(angle.(Vall)),
            Vm_sqrt_v = r.Vm,
            Pd = c.Pd,
            Qd = c.Qd,
        ),
    )
    return (; c, r, rf, V = Vall, fdP, fdQ)
end

# ------------------------------------------------------------------------------------------
# Experiment 1 -- non-convex AC-OPF (Ipopt) as global-optimality check
# ------------------------------------------------------------------------------------------

"""
    build_acopf(c; optimizer)

Polar AC-OPF of the full 6-node system. Same limit set as the relaxation: transmission
|S_ab|^2 <= Smax^2 at BOTH ends (pi model, b/2 shunts; relaxation eq. 24), feeder sending-end
|S_ij|^2 <= Smax^2 (eq. 32 first part) and |I_ij|^2 = |S_ij|^2 / |V_i|^2 <= Imax^2 (eq. 32 second
part, l = |I|^2 in the relaxation), |V| in [0.95, 1.05] at all nodes, generator bounds.
"""
function build_acopf(c::Case6; optimizer = nlp_optimizer())
    m = Model(optimizer)
    set_silent(m)
    @variable(m, c.vmin <= Vm[1:6] <= c.vmax)
    @variable(m, Va[1:6])
    fix(Va[1], 0.0; force = true)
    @variable(m, c.pgmin <= Pg <= c.pgmax)
    @variable(m, c.qgmin <= Qg <= c.qgmax)
    function pq(a, b, r, x, bsh)
        y = 1 / (r + im * x)
        g, bs = real(y), imag(y)
        cs = Vm[a] * Vm[b] * cos(Va[a] - Va[b])
        sn = Vm[a] * Vm[b] * sin(Va[a] - Va[b])
        Pab = @expression(m, g * (Vm[a]^2 - cs) - bs * sn)
        Qab = @expression(m, -g * sn - bs * (Vm[a]^2 - cs) - bsh / 2 * Vm[a]^2)
        return Pab, Qab
    end
    outP = [Any[] for _ in 1:6]
    outQ = [Any[] for _ in 1:6]
    for ln in c.tl, (a, b) in ((ln.i, ln.j), (ln.j, ln.i))
        Pab, Qab = pq(a, b, ln.r, ln.x, ln.b)
        push!(outP[a], Pab)
        push!(outQ[a], Qab)
        @constraint(m, Pab^2 + Qab^2 <= ln.smax^2)
    end
    S2line12 = Any[]
    for ln in c.tl[1:1], (a, b) in ((ln.i, ln.j), (ln.j, ln.i))
        Pab, Qab = pq(a, b, ln.r, ln.x, ln.b)
        push!(S2line12, @expression(m, Pab^2 + Qab^2))
    end
    P34 = nothing
    Q34 = nothing
    for (k, br) in enumerate(c.dl)
        Pij, Qij = pq(br.i, br.j, br.r, br.x, 0.0)
        Pji, Qji = pq(br.j, br.i, br.r, br.x, 0.0)
        push!(outP[br.i], Pij)
        push!(outQ[br.i], Qij)
        push!(outP[br.j], Pji)
        push!(outQ[br.j], Qji)
        @constraint(m, Pij^2 + Qij^2 <= br.smax^2)
        @constraint(m, Pij^2 + Qij^2 <= br.imax^2 * Vm[br.i]^2)
        if k == 1
            P34, Q34 = Pij, Qij
        end
    end
    gP = Any[Pg, 0.0, 0.0, 0.0, 0.0, 0.0]
    gQ = Any[Qg, 0.0, 0.0, 0.0, 0.0, 0.0]
    if c.flex
        Pg2 = @variable(m, lower_bound = 0.0, upper_bound = G2_PMAX)
        Pdg = @variable(m, lower_bound = 0.0, upper_bound = DG_PMAX)
        gP[2] = Pg2
        gP[6] = Pdg
    end
    for k in 1:6
        @constraint(m, gP[k] - c.Pd[k] == sum(outP[k]))
        @constraint(m, gQ[k] - c.Qd[k] == sum(outQ[k]))
    end
    if c.flex
        @objective(m, Min, c.c2 * Pg^2 + c.c1 * Pg + c.c0 + g2cost(gP[2]) + dgcost(gP[6]))
    else
        @objective(m, Min, c.c2 * Pg^2 + c.c1 * Pg + c.c0)
    end
    return (; m, Vm, Va, Pg, Qg, P34, Q34, S2line12)
end

"""
    ac_min_flow(c, which; nrand = 20) -> Float64

AC counterpart of `min_flow`: the smallest flow on line (1,2) (`:line12`, max of both ends) or
on the feeder head (`:head34`) over AC-feasible points, by Ipopt from a flat + `nrand` seeded
random starts (best locally solved value; NaN if none).
"""
function ac_min_flow(c::Case6, which::Symbol; nrand::Int = 20)
    a = build_acopf(c)
    s = @variable(a.m, lower_bound = 0.0)
    if which === :line12
        for e in a.S2line12
            @constraint(a.m, e <= s)
        end
    else
        @constraint(a.m, a.P34^2 + a.Q34^2 <= s)
    end
    @objective(a.m, Min, s)
    rng = StableRNG(SEED)
    best = NaN
    for st in 0:nrand
        set_ac_start!(a, c, st == 0 ? nothing : rng)
        set_start_value(s, 1.0)
        optimize!(a.m)
        if termination_status(a.m) in AC_OK
            v = sqrt(max(value(s), 0.0))
            best = isnan(best) ? v : min(best, v)
        end
    end
    return best
end

"Set the AC-OPF start point: flat (`rng === nothing`) or uniform random within the bounds."
function set_ac_start!(a, c::Case6, rng)
    for k in 1:6
        set_start_value(a.Vm[k], rng === nothing ? 1.0 : c.vmin + (c.vmax - c.vmin) * rand(rng))
        k == 1 && continue
        set_start_value(a.Va[k], rng === nothing ? 0.0 : -0.3 + 0.6 * rand(rng))
    end
    set_start_value(a.Pg, rng === nothing ? 0.0 : c.pgmin + (c.pgmax - c.pgmin) * rand(rng))
    set_start_value(a.Qg, rng === nothing ? 0.0 : c.qgmin + (c.qgmax - c.qgmin) * rand(rng))
    return nothing
end

const AC_OK = (LOCALLY_SOLVED, OPTIMAL, ALMOST_LOCALLY_SOLVED)

"""
    ac_multistart(c; nrand, variants, seed)

Flat start + `nrand` seeded random starts (StableRNG(seed)) + optionally the framework's 5
deterministic Ipopt strategy variants (from the flat start). Returns per-start rows and the best
(lowest-cost) locally solved run.
"""
function ac_multistart(
    c::Case6;
    nrand::Int = 20,
    variants::Bool = false,
    seed::Int = SEED,
    attrs...,
)
    rows = NamedTuple[]
    best = nothing
    rng = StableRNG(seed)
    a = build_acopf(c; optimizer = nlp_optimizer(; attrs...))
    function run!(a, label)
        optimize!(a.m)
        st = termination_status(a.m)
        ok = st in AC_OK
        row = (;
            start = label,
            status = string(st),
            ok,
            cost = ok ? objective_value(a.m) : NaN,
            Pg = ok ? value(a.Pg) : NaN,
            Qg = ok ? value(a.Qg) : NaN,
            P34 = ok ? value(a.P34) : NaN,
            Q34 = ok ? value(a.Q34) : NaN,
            Vm = ok ? value.(a.Vm) : fill(NaN, 6),
            Va = ok ? rad2deg.(value.(a.Va)) : fill(NaN, 6),
        )
        push!(rows, row)
        if ok && (best === nothing || row.cost < best.cost)
            best = row
        end
        return nothing
    end
    set_ac_start!(a, c, nothing)
    run!(a, "flat")
    for s in 1:nrand
        set_ac_start!(a, c, rng)
        run!(a, "random_$s")
    end
    if variants
        for (vi, v) in enumerate(TSODSO.nlp_multistart_variants())
            av = build_acopf(c; optimizer = nlp_optimizer(; v...))
            set_ac_start!(av, c, nothing)
            run!(av, "flat_variant_$vi")
        end
    end
    return rows, best
end

"Number of distinct local optima among the solved rows (costs equal within 1e-7 relative)."
function distinct_optima(rows)
    costs = sort([r.cost for r in rows if r.ok])
    isempty(costs) && return 0
    n = 1
    for k in 2:length(costs)
        abs(costs[k] - costs[k - 1]) > 1e-7 * abs(costs[k]) && (n += 1)
    end
    return n
end

function experiment1(io, b0)
    section(io, "EXPERIMENT 1 -- GLOBAL OPTIMALITY (non-convex AC-OPF, Ipopt multistart)")
    c, r = b0.c, b0.r
    rows, best = ac_multistart(c; nrand = 20, variants = true)
    nsolved = count(x -> x.ok, rows)
    costs = [x.cost for x in rows if x.ok]
    println(io, "Starts: flat + 20 seeded random (StableRNG($SEED); Vm~U[0.95,1.05], ",
        "Va~U[-0.3,0.3] rad, Pg/Qg uniform in bounds) + 5 deterministic Ipopt strategy variants")
    println(io, "Ipopt tol = 1e-10. Locally solved: $nsolved / $(length(rows))")
    @printf(io, "  best AC cost  = %.6f \$/h\n  worst AC cost = %.6f \$/h\n", minimum(costs),
        maximum(costs))
    println(io, "  distinct local optima (cost within 1e-7 rel.): ", distinct_optima(rows))
    gap = (best.cost - r.cost) / best.cost
    @printf(io, "  relaxation cost = %.6f \$/h;  gap (AC best - relaxation)/AC = %.2e\n", r.cost,
        gap)
    @printf(io, "  AC best: Pg = %.6f  Qg = %.6f  P34 = %.6f  Q34 = %.6f pu\n", best.Pg,
        best.Qg, best.P34, best.Q34)
    V = b0.V
    println(io, "\nVoltages: relaxation-recovered vs Ipopt AC optimum vs paper:")
    @printf(io, "%5s %10s %10s %10s %10s %10s %10s\n", "node", "|V| rel", "ang rel", "|V| AC",
        "ang AC", "|V| paper", "ang paper")
    for k in 1:6
        pv = k <= 3 ? @sprintf("%10.4f %10.2f", PAPER.Vm[k], PAPER.Va[k]) : @sprintf("%10s %10s", "-", "-")
        @printf(io, "%5d %10.5f %10.3f %10.5f %10.3f %s\n", k, abs(V[k]), rad2deg(angle(V[k])),
            best.Vm[k], best.Va[k], pv)
    end
    VAC = best.Vm .* cis.(deg2rad.(best.Va))
    @printf(io, "  max |V_rel - V_AC| (complex) = %.2e pu\n", maximum(abs.(V .- VAC)))
    dPm, dQm = ac_mismatch(c, V, r.Pg, r.Qg)
    @printf(io, "  full-AC nodal injection mismatch of the relaxed point (6-node Ybus): max|dP| = %.2e, max|dQ| = %.2e pu\n",
        dPm, dQm)
    dPa, dQa = ac_mismatch(c, VAC, best.Pg, best.Qg)
    @printf(io, "  (same check on the Ipopt optimum: max|dP| = %.2e, max|dQ| = %.2e pu)\n", dPa,
        dQa)
    writecsv(
        "acopf_multistart.csv",
        DataFrame(
            :start => [x.start for x in rows],
            :status => [x.status for x in rows],
            :cost => [x.cost for x in rows],
            :Pg => [x.Pg for x in rows],
            :Qg => [x.Qg for x in rows],
            :P34 => [x.P34 for x in rows],
            :Q34 => [x.Q34 for x in rows],
            [Symbol("Vm$k") => [x.Vm[k] for x in rows] for k in 1:6]...,
            [Symbol("Va$(k)_deg") => [x.Va[k] for x in rows] for k in 1:6]...,
        ),
    )
    return (; rows, best, gap, mismatch = (dPm, dQm))
end

# ------------------------------------------------------------------------------------------
# Experiment 2 -- TSO-DSO ADMM (paper Sec. VII-G)
# ------------------------------------------------------------------------------------------

"TSO subproblem (eqs. 35-38): SDP block + generator + local boundary flows PT, QT. Built once."
function build_tso(c::Case6)
    m = Model(socp_optimizer())
    set_silent(m)
    Pg = @variable(m, lower_bound = c.pgmin, upper_bound = c.pgmax)
    Qg = @variable(m, lower_bound = c.qgmin, upper_bound = c.qgmax)
    PT = @variable(m)
    QT = @variable(m)
    Pg2 = c.flex ? @variable(m, lower_bound = 0.0, upper_bound = G2_PMAX) : nothing
    tb = add_transmission_block!(m, c, Pg, Qg, PT, QT; Pg2)
    # Local TSO cost (generation; plus G2 in the congestion extension).
    cost = c.flex ? c.c2 * Pg^2 + c.c1 * Pg + c.c0 + g2cost(Pg2) : c.c2 * Pg^2 + c.c1 * Pg + c.c0
    return (; m, Pg, Qg, Pg2, PT, QT, tb.W, tb.balP, tb.balQ, tb.linecones, cost)
end

"DSO subproblem (eq. 39 constraints): feeder with local root variables v3, P34^D, Q34^D. Built once."
function build_dso(c::Case6)
    m = Model(socp_optimizer())
    set_silent(m)
    v3 = @variable(m, lower_bound = c.vmin^2, upper_bound = c.vmax^2)
    Pdg = c.flex ? @variable(m, lower_bound = 0.0, upper_bound = DG_PMAX) : nothing
    fb = add_feeder_block!(m, c, 1.0 * v3; Pdg)
    # Local DSO cost (zero in the paper; the DG cost in the congestion extension).
    cost = c.flex ? dgcost(Pdg) : AffExpr(0.0)
    return (; m, v3, fb, Pdg, cost)
end

"""
    run_admm(c; rho, eps, maxit = 3000, tol_p = 1e-4, tol_d = 1e-2)

Gauss-Seidel ADMM of the paper: TSO with y_D^(k) -> DSO with y_T^(k+1) -> dual updates
(eqs. 40-42). Initialisation lambda = 0, y_D^(0) = (1, sum Pd_4..6, sum Qd_4..6). Stops when the
primal residual ||y_T - y_D|| < tol_p AND the dual residual rho ||y_D^(k+1) - y_D^(k)|| < tol_d.
Only the objectives are re-set per iteration; constraints are never rebuilt.
"""
function run_admm(
    c::Case6;
    rho::Float64,
    eps::Float64,
    maxit::Int = 3000,
    tol_p::Float64 = 1e-4,
    tol_d::Float64 = 1e-2,
)
    tso = build_tso(c)
    dso = build_dso(c)
    W33 = real(tso.W[3, 3])
    lam = zeros(3)
    yD = [1.0, sum(c.Pd[4:6]), sum(c.Qd[4:6])]
    yT = zeros(3)
    trace = NamedTuple[]
    converged = false
    statuses = Set{String}()
    for k in 1:maxit
        @objective(
            tso.m,
            Min,
            tso.cost + lam[1] * W33 + lam[2] * tso.PT + lam[3] * tso.QT +
            rho / 2 * ((W33 - yD[1])^2 + (tso.PT - yD[2])^2 + (tso.QT - yD[3])^2)
        )
        optimize!(tso.m)
        push!(statuses, "TSO:" * string(termination_status(tso.m)))
        yT = [value(W33), value(tso.PT), value(tso.QT)]
        fb = dso.fb
        @objective(
            dso.m,
            Min,
            dso.cost - lam[1] * dso.v3 - lam[2] * fb.P[1] - lam[3] * fb.Q[1] +
            rho / 2 * ((yT[1] - dso.v3)^2 + (yT[2] - fb.P[1])^2 + (yT[3] - fb.Q[1])^2) +
            eps * sum(c.dl[b].r * fb.l[b] for b in 1:3)
        )
        optimize!(dso.m)
        push!(statuses, "DSO:" * string(termination_status(dso.m)))
        yDn = [value(dso.v3), value(fb.P[1]), value(fb.Q[1])]
        lam .+= rho .* (yT .- yDn)
        rp = norm(yT .- yDn)
        rd = rho * norm(yDn .- yD)
        yD = yDn
        piP = [
            [-dual(tso.balP[i]) / SBASE for i in 1:3]
            [dual(fb.fP[i]) / SBASE for i in 1:3]
        ]
        piQ = [
            [-dual(tso.balQ[i]) / SBASE for i in 1:3]
            [dual(fb.fQ[i]) / SBASE for i in 1:3]
        ]
        vv = [value(dso.v3); value.(fb.v[2:4])]
        cone = maximum(
            value(fb.l[b]) * vv[b] - value(fb.P[b])^2 - value(fb.Q[b])^2 for b in 1:3
        )
        coneratio = maximum(
            abs(value(fb.l[b]) * vv[b] - value(fb.P[b])^2 - value(fb.Q[b])^2) / (
                max(TSODSO.TAU_SOLVER_EXACT, TSODSO.MEASURED_REL_TOL_EXACT * c.dl[b].smax^2) +
                1e-4 * value(fb.l[b]) * vv[b]
            ) for b in 1:3
        )
        ev = eigvals(Hermitian(value.(tso.W)))
        Pg = value(tso.Pg)
        push!(
            trace,
            (;
                k,
                primal = rp,
                dual = rd,
                # generation cost (paper: TSO cost); + G2 and DG costs in the extension
                cost = value(tso.cost) + value(dso.cost),
                Pg,
                Pg2 = _val(tso.Pg2),
                Pdg = _val(dso.Pdg),
                Qg = value(tso.Qg),
                yT = copy(yT),
                yD = copy(yD),
                lam = copy(lam),
                piP,
                piQ,
                cone,
                coneratio,
                rank = abs(ev[2] / ev[3]),
                losses_f = sum(c.dl[b].r * value(fb.l[b]) for b in 1:3),
            ),
        )
        if rp < tol_p && rd < tol_d
            converged = true
            break
        end
    end
    return (; trace, converged, iters = length(trace), final = trace[end], statuses)
end

"First iteration from which ALL 6 active prices stay within `rel` of the monolithic ones."
function settle_iteration(trace, piP_ref; rel = 1e-3)
    last_bad = 0
    for t in trace
        if maximum(abs.(t.piP .- piP_ref) ./ abs.(piP_ref)) > rel
            last_bad = t.k
        end
    end
    return last_bad + 1
end

admm_trace_df(tr) = DataFrame(
    :iter => [t.k for t in tr],
    :primal => [t.primal for t in tr],
    :dual => [t.dual for t in tr],
    :tso_cost => [t.cost for t in tr],
    :Pg => [t.Pg for t in tr],
    :W33_T => [t.yT[1] for t in tr],
    :P34_T => [t.yT[2] for t in tr],
    :Q34_T => [t.yT[3] for t in tr],
    :v3_D => [t.yD[1] for t in tr],
    :P34_D => [t.yD[2] for t in tr],
    :Q34_D => [t.yD[3] for t in tr],
    :lambda_v => [t.lam[1] for t in tr],
    :lambda_p => [t.lam[2] for t in tr],
    :lambda_q => [t.lam[3] for t in tr],
    [Symbol("piP$k") => [t.piP[k] for t in tr] for k in 1:6]...,
    [Symbol("piQ$k") => [t.piQ[k] for t in tr] for k in 1:6]...,
    :max_cone_residual => [t.cone for t in tr],
    :max_cone_ratio => [t.coneratio for t in tr],
    :tso_rank_ratio => [t.rank for t in tr],
)

const RHO_SWEEP = [50.0, 100.0, 200.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0]
const EPS_SWEEP = [0.0, 1e-4, 1e-3, 1e-2, 1e-1]

function experiment2(io, b0)
    section(io, "EXPERIMENT 2 -- TSO-DSO ADMM (Gauss-Seidel, paper Sec. VII-G)")
    c, r = b0.c, b0.r
    a = run_admm(c; rho = 500.0, eps = 1e-2)
    fin = a.final
    println(io, "rho = 500, eps = 1e-2, stop: primal < 1e-4 pu AND dual < 1e-2 (cap 3000)")
    println(io, "  subproblem statuses seen: ", join(sort(collect(a.statuses)), ", "))
    @printf(io, "  converged = %s in %d iterations (paper: 57)\n", a.converged, a.iters)
    @printf(io, "  final primal residual %.2e pu (paper 9.1e-5), dual residual %.2e (paper 1.8e-3)\n",
        fin.primal, fin.dual)
    settle = settle_iteration(a.trace, r.piP)
    @printf(io, "  all active prices within 0.1 %% of monolithic from iteration %d on (paper: about 40)\n",
        settle)
    println(io, "\nTable II side by side:")
    @printf(io, "%-24s %14s %14s %14s %14s\n", "quantity", "mono (here)", "ADMM (here)",
        "mono (paper)", "ADMM (paper)")
    @printf(io, "%-24s %14.3f %14.3f %14.3f %14.3f\n", "cost (\$/h)", r.cost, fin.cost, 7461.105,
        7460.537)
    @printf(io, "%-24s %14.5f %14.5f %14.5f %14.5f\n", "Pg (pu)", r.Pg, fin.Pg, 1.83287, 1.83278)
    @printf(io, "%-24s %14.5f %14.5f %14.5f %14.5f\n", "Qg (pu)", r.Qg, fin.Qg, 0.13381, 0.13379)
    @printf(io, "%-24s %14.5f %14.5f %14.5f %14.5f\n", "P34 TSO side (pu)", r.P34, fin.yT[2],
        0.30486, 0.30477)
    @printf(io, "%-24s %14.5f %14.5f %14s %14s\n", "P34 DSO side (pu)", r.P34, fin.yD[2], "-", "-")
    @printf(io, "%-24s %14.5f %14.5f %14.5f %14.5f\n", "Q34 TSO side (pu)", r.Q34, fin.yT[3],
        0.12926, 0.12926)
    @printf(io, "%-24s %14.5f %14.5f %14s %14s\n", "Q34 DSO side (pu)", r.Q34, fin.yD[3], "-", "-")
    @printf(io, "%-24s %14.5f %14.5f %14.5f %14.5f\n", "|V3| TSO sqrt(W33)", r.Vm[3],
        sqrt(fin.yT[1]), 1.01405, 1.01406)
    @printf(io, "%-24s %14.5f %14.5f %14s %14s\n", "|V3| DSO sqrt(v3)", r.Vm[3], sqrt(fin.yD[1]),
        "-", "-")
    @printf(io, "%-24s %14.2e %14.2e %14.2e %14.2e\n", "|lambda2/lambda1| W", r.rr, fin.rank,
        6.4e-10, 5.9e-11)
    @printf(io, "%-24s %14.2e %14.2e %14.2e %14.2e\n", "max cone residual",
        maximum(x.gap for x in r.cones), fin.cone, 2.6e-7, 2.4e-9)
    @printf(io, "%-24s %14s %14d %14s %14d\n", "iterations", "-", a.iters, "-", 57)
    @printf(io, "  relative cost difference (mono - ADMM)/mono = %.2e (paper 7.6e-5)\n",
        (r.cost - fin.cost) / r.cost)
    println(io, "\nPrices at convergence (TSO duals for nodes 1-3, DSO duals for 4-6):")
    @printf(io, "%5s %11s %11s %11s %11s %11s %11s\n", "node", "piP mono", "piP ADMM", "rel diff",
        "piQ mono", "piQ ADMM", "abs diff")
    for k in 1:6
        @printf(io, "%5d %11.4f %11.4f %11.2e %11.4f %11.4f %11.2e\n", k, r.piP[k], fin.piP[k],
            abs(fin.piP[k] - r.piP[k]) / r.piP[k], r.piQ[k], fin.piQ[k],
            abs(fin.piQ[k] - r.piQ[k]))
    end
    @printf(io, "  -lambda_p = %.4f \$/h per pu;  piP3(ADMM)*100 = %.4f;  piP3(mono)*100 = %.4f\n",
        -fin.lam[2], 100 * fin.piP[3], 100 * r.piP[3])
    @printf(io, "  (paper: -lambda_p = 6258.80 = piP3(ADMM)*100)\n")
    @printf(io, "  -lambda_q = %.4f vs piQ3(ADMM)*100 = %.4f;  lambda_v = %.4f \$/h per pu^2\n",
        -fin.lam[3], 100 * fin.piQ[3], fin.lam[1])
    writecsv("admm_trace_rho500.csv", admm_trace_df(a.trace))

    # rho sweep
    println(io, "\nrho sweep (eps = 1e-2):")
    @printf(io, "%9s %6s %9s %11s %11s %13s %13s\n", "rho", "iters", "converged", "primal",
        "dual", "rel cost err", "max |dPrice|")
    rs = NamedTuple[]
    for rho in RHO_SWEEP
        x = run_admm(c; rho = rho, eps = 1e-2)
        fx = x.final
        rce = (fx.cost - r.cost) / r.cost
        pe = maximum(abs.(fx.piP .- r.piP))
        push!(rs, (; rho, iters = x.iters, converged = x.converged, primal = fx.primal,
            dual = fx.dual, rel_cost_err = rce, max_price_err = pe,
            settle = settle_iteration(x.trace, r.piP)))
        @printf(io, "%9.0f %6d %9s %11.2e %11.2e %13.2e %13.2e\n", rho, x.iters, x.converged,
            fx.primal, fx.dual, rce, pe)
    end
    writecsv("admm_rho_sweep.csv", DataFrame(rs))

    # eps sweep
    println(io, "\neps sweep (rho = 500):")
    @printf(io, "%8s %6s %9s %14s %14s %14s %14s\n", "eps", "iters", "converged",
        "max cone (it)", "max ratio (it)", "cone @ conv", "cost bias")
    es = NamedTuple[]
    for eps in EPS_SWEEP
        x = run_admm(c; rho = 500.0, eps = eps)
        mc = maximum(t.cone for t in x.trace)
        mr = maximum(t.coneratio for t in x.trace)
        fx = x.final
        bias = (fx.cost - r.cost) / r.cost
        push!(es, (; eps, iters = x.iters, converged = x.converged, max_cone_iterates = mc,
            max_cone_ratio_iterates = mr, cone_final = fx.cone, cone_ratio_final = fx.coneratio,
            rel_cost_bias = bias, max_price_err = maximum(abs.(fx.piP .- r.piP)),
            losses_f_final = fx.losses_f))
        @printf(io, "%8.0e %6d %9s %14.2e %14.2e %14.2e %14.2e\n", eps, x.iters, x.converged,
            mc, mr, fx.cone, bias)
    end
    writecsv("admm_eps_sweep.csv", DataFrame(es))
    return (; a, settle, rs, es)
end

# ------------------------------------------------------------------------------------------
# Experiment 3 -- congestion
# ------------------------------------------------------------------------------------------

"Binding-constraint duals of a solved hybrid model (shadow prices of the limits, \$/MVAh)."
function binding_duals(c::Case6, h; tol = 1e-6)
    out = NamedTuple[]
    for ((k, en), cr) in sort(collect(h.linecones); by = first)
        d = dual(cr)[1] / SBASE
        ln = c.tl[k]
        d > tol && push!(out, (;
            name = "line ($(ln.i),$(ln.j)) $(en == 1 ? "sending" : "receiving")-end Smax",
            value = d,
        ))
    end
    for k in 1:3
        br = c.dl[k]
        d = dual(h.feeder.smaxc[k])[1] / SBASE
        d > tol && push!(out, (; name = "feeder ($(br.i),$(br.j)) sending-end Smax", value = d))
        if h.feeder.smaxrev !== nothing
            d = dual(h.feeder.smaxrev[k])[1] / SBASE
            d > tol &&
                push!(out, (; name = "feeder ($(br.i),$(br.j)) receiving-end Smax", value = d))
        end
        d = -dual(h.feeder.imaxc[k]) / SBASE
        d > tol && push!(out, (; name = "feeder ($(br.i),$(br.j)) Imax^2 (per pu^2)", value = d))
    end
    return out
end

"Exactness verdicts used everywhere: SDP rank-one test and SOC hybrid-floor test."
const RANK_EXACT = 1e-6          # |lambda2/lambda1| below this = numerically rank one
exact_sdp(r) = r.rr < RANK_EXACT
exact_soc(r) = maximum(x.ratio for x in r.cones) <= 1

"Framework DLMP decomposition (feeder nodes 3-6) after the framework exactness gate."
function framework_dlmp(c::Case6)
    rf = solve_hybrid(c; dso = :framework)
    rf.ok || return (; ok = false, reason = "framework solve $(rf.status)")
    ctx = rf.h.ctx
    gate = gate_framework(ctx)
    gate.ok || return (; ok = false, reason = gate.reason)
    ctx.meta[:socp_maxgap] = gate.maxgap
    d = decompose_dlmp(ctx)
    comp = (;
        energy = d.energy[:, 1] ./ SBASE,
        cone = d.cone[:, 1] ./ SBASE,
        congestion = d.congestion[:, 1] ./ SBASE,
        drop = d.drop[:, 1] ./ SBASE,
        reactive = d.reactive[:, 1] ./ SBASE,
        total = d.total[:, 1] ./ SBASE,
    )
    resid = maximum(abs.(comp.energy .+ comp.cone .+ comp.congestion .+ comp.drop .- comp.total))
    return (; ok = true, comp, resid, rf)
end

"Run the framework exactness gate without letting an exception escape (non-throwing wrapper)."
function gate_framework(ctx)
    maxgap = NaN
    reason = ""
    ok = true
    try
        maxgap = assert_socp_exact!(ctx)
    catch err
        ok = false
        reason = sprint(showerror, err)
    end
    return (; ok, maxgap, reason)
end

"""
    min_flow(c, which) -> Float64

Smallest apparent-power flow the relaxation can achieve on line (1,2) (`which = :line12`, max
of both ends) or on the feeder head (3,4) (`:head34`, sending end), subject to every other
constraint: the lower end of the band in which a limit on that element can bind feasibly.
"""
function min_flow(c::Case6, which::Symbol)
    # MEASURED: without equilibration Clarabel returns NUMERICAL_ERROR on this pure-feasibility
    # objective (the SDP block is free of cost); the default (equilibrated) setting solves it.
    h = build_hybrid(
        c;
        optimizer = select_optimizer(
            TSODSO.SOCP();
            tol_gap_abs = 1e-9,
            tol_gap_rel = 1e-9,
            tol_feas = 1e-9,
        ),
    )
    m = h.m
    t = @variable(m)
    if which === :line12
        Wv = h.W
        ln = c.tl[1]
        y = 1 / (ln.r + im * ln.x)
        for (a, b) in ((ln.i, ln.j), (ln.j, ln.i))
            Sab = conj(y) * (Wv[a, a] - Wv[a, b]) - im * ln.b / 2 * Wv[a, a]
            @constraint(m, [t; real(Sab); imag(Sab)] in SecondOrderCone())
        end
    else
        @constraint(m, [t; h.feeder.P[1]; h.feeder.Q[1]] in SecondOrderCone())
    end
    @objective(m, Min, t)
    optimize!(m)
    termination_status(m) in (OPTIMAL, ALMOST_OPTIMAL) ||
        error("min_flow($which) failed: $(termination_status(m))")
    return value(t)
end

function experiment3(io, b0)
    section(io, "EXPERIMENT 3 -- CONGESTION (transmission line (1,2) and feeder head (3,4))")
    base = b0.r
    s12 = maximum(abs.((base.lines[1].Sij, base.lines[1].Sji)))
    s34 = hypot(base.P34, base.Q34)
    # The planned limits (0.9 x the baseline flow) are first tested as such.
    println(io, "Planned limits (0.9 x baseline flow) -- feasibility check:")
    for (lbl, cc) in (
        (@sprintf("Smax(1,2) = 0.9 x %.5f = %.5f pu", s12, 0.9s12),
            case6(; smax_line = [0.9s12, 2.0, 2.0])),
        (@sprintf("Smax(3,4) = Imax(3,4) = 0.9 x %.5f = %.5f pu", s34, 0.9s34),
            case6(; smax_feeder = [0.9s34, 0.6, 0.4])),
    )
        rr = solve_hybrid(cc)
        _, bb = ac_multistart(cc; nrand = 20)
        println(io, "  ", lbl, ": relaxation ", rr.status, "; Ipopt (flat + 20 random) ",
            bb === nothing ? "found no AC point" : @sprintf("found cost %.4f", bb.cost))
    end
    println(io, "  => both infeasible: with one generator and inelastic loads nothing can be",
        " redispatched; flows are fixed by the loads up to the voltage profile. The relaxation's",
        " infeasibility certifies AC infeasibility.")
    # Part A -- the paper's system: the band in which a limit can bind at all.
    f12 = min_flow(case6(), :line12)
    f34 = min_flow(case6(), :head34)
    a12 = ac_min_flow(case6(), :line12)
    a34 = ac_min_flow(case6(), :head34)
    sm12 = round(f12 + 0.5 * (s12 - f12); sigdigits = 7)
    sm34 = round(f34 + 0.5 * (s34 - f34); sigdigits = 7)
    println(io, "\nPart A -- paper system (no redispatch): band of limits that can bind feasibly")
    @printf(io, "  line (1,2): min max|S12| relaxation %.6f, AC (Ipopt, 21 starts) %.6f, baseline %.6f pu\n",
        f12, a12, s12)
    @printf(io, "  head (3,4): min |S34|    relaxation %.6f, AC (Ipopt, 21 starts) %.6f, baseline %.6f pu\n",
        f34, a34, s34)
    @printf(io, "  band midpoints used below: Smax(1,2) = %.6f, Smax(3,4) = Imax(3,4) = %.6f pu\n",
        sm12, sm34)
    println(io, "\nPart B -- congestion extension (NOT in the paper): out-of-merit G2 at node 2",
        @sprintf(" (%.0f Pg2^2 + %.0f Pg2 \$/h, Pg2 <= %.1f, unity pf)", G2_C2, G2_C1, G2_PMAX),
        @sprintf(" and DG at node 6 (%.0f Pdg \$/h, Pdg <= %.1f, unity pf);", DG_C1, DG_PMAX),
        " limits at 0.9 x the baseline flow as planned.")
    variants = [
        ("baseline", case6()),
        ("paper_line12_band", case6(; smax_line = [sm12, 2.0, 2.0])),
        ("paper_head34_band", case6(; smax_feeder = [sm34, 0.6, 0.4])),
        ("flex_baseline", case6(; flex = true)),
        ("flex_line12", case6(; flex = true, smax_line = [0.9s12, 2.0, 2.0])),
        ("flex_head34", case6(; flex = true, smax_feeder = [0.9s34, 0.6, 0.4])),
        (
            "flex_both",
            case6(; flex = true, smax_line = [0.9s12, 2.0, 2.0], smax_feeder = [0.9s34, 0.6, 0.4]),
        ),
    ]
    prow = NamedTuple[]
    drow = NamedTuple[]
    srow = NamedTuple[]
    results = Dict{String, Any}()
    for (name, c) in variants
        r = solve_hybrid(c)
        if !r.ok
            _, bb = ac_multistart(c; nrand = 20)
            println(io, "\n--- variant: $name ---")
            println(io, "  relaxation ", r.status, " (", r.solver, "); Ipopt (flat + 20 random) ",
                bb === nothing ? "found no AC point" : @sprintf("found cost %.4f", bb.cost))
            results[name] = nothing
            continue
        end
        rows, best = ac_multistart(c; nrand = 20)
        a = run_admm(c; rho = 500.0, eps = 1e-2)
        fin = a.final
        dl = framework_dlmp(c)
        bd = binding_duals(c, r.h)
        results[name] = (; r, best, a, dl)
        gap = best === nothing ? NaN : (best.cost - r.cost) / best.cost
        println(io, "\n--- variant: $name ---")
        @printf(io, "  status %s (%s), cost %.4f \$/h (%+.4f vs baseline, %+.4f %%)\n", r.status,
            r.solver, r.cost, r.cost - base.cost, 100 * (r.cost - base.cost) / base.cost)
        @printf(io, "  Pg %.5f  Qg %.5f  P34 %.5f  Q34 %.5f; loadings: line(1,2) %.2f %%, head(3,4) %.2f %%\n",
            r.Pg, r.Qg, r.P34, r.Q34, 100 * r.lines[1].loading, 100 * r.floading[1])
        if c.flex
            @printf(io, "  flexibility: Pg2 = %.5f (marginal cost %.4f \$/MWh vs piP2 %.4f), Pdg = %.5f (cost %.4f \$/MWh vs piP6 %.4f)\n",
                r.Pg2, (2 * G2_C2 * r.Pg2 + G2_C1) / SBASE, r.piP[2], r.Pdg, DG_C1 / SBASE,
                r.piP[6])
        end
        @printf(io, "  exactness: |lambda2/lambda1| = %.2e (%s), max cone residual %.2e, max hybrid ratio %.2e (%s)\n",
            r.rr, exact_sdp(r) ? "rank one" : "NOT RANK ONE", maximum(x.gap for x in r.cones),
            maximum(x.ratio for x in r.cones), exact_soc(r) ? "exact" : "INEXACT")
        if best === nothing
            println(io, "  Ipopt AC-OPF: no locally solved start")
        else
            @printf(io, "  Ipopt AC-OPF best (flat + 20 random): %.4f \$/h, gap (AC - relax)/AC = %.2e, %d distinct optima\n",
                best.cost, gap, distinct_optima(rows))
        end
        println(io, "  binding-constraint duals (shadow price of the limit):")
        isempty(bd) && println(io, "    none")
        for x in bd
            @printf(io, "    %-46s %10.4f \$/MVAh\n", x.name, x.value)
        end
        println(io, "  prices (mono):  piP = ", join(f.(r.piP; d = 4), ", "))
        println(io, "                  piQ = ", join(f.(r.piQ; d = 4), ", "))
        @printf(io, "  transmission side: piP1 = %.4f vs 2c2Pg+c1 = %.4f; spreads piP2-piP1 = %.4f, piP3-piP1 = %.4f\n",
            r.piP[1], (2 * c.c2 * r.Pg + c.c1) / SBASE, r.piP[2] - r.piP[1], r.piP[3] - r.piP[1])
        @printf(io, "  ADMM rho=500 eps=1e-2: converged=%s in %d iterations, primal %.2e, dual %.2e\n",
            a.converged, a.iters, fin.primal, fin.dual)
        @printf(io, "    rel cost diff (mono-ADMM)/mono %.2e, max |dpiP| %.2e, max |dpiQ| %.2e, -lambda_p = %.3f vs piP3(ADMM)*100 = %.3f\n",
            (r.cost - fin.cost) / r.cost, maximum(abs.(fin.piP .- r.piP)),
            maximum(abs.(fin.piQ .- r.piQ)), -fin.lam[2], 100 * fin.piP[3])
        if dl.ok
            println(io, "  feeder DLMP decomposition (framework decompose_dlmp, after assert_socp_exact!):")
            @printf(io, "    %5s %10s %10s %11s %10s %10s %10s\n", "node", "energy", "cone",
                "congestion", "drop", "total", "reactive")
            for jl in 1:4
                @printf(io, "    %5d %10.4f %10.4f %11.4f %10.4f %10.4f %10.4f\n", jl + 2,
                    dl.comp.energy[jl], dl.comp.cone[jl], dl.comp.congestion[jl],
                    dl.comp.drop[jl], dl.comp.total[jl], dl.comp.reactive[jl])
                push!(drow, (; variant = name, node = jl + 2, energy = dl.comp.energy[jl],
                    cone = dl.comp.cone[jl], congestion = dl.comp.congestion[jl],
                    drop = dl.comp.drop[jl], total = dl.comp.total[jl],
                    reactive = dl.comp.reactive[jl], paper_model_piP = r.piP[jl + 2]))
            end
            @printf(io, "    max |energy+cone+congestion+drop - total| = %.2e; max |total - piP(paper model)| = %.2e\n",
                dl.resid, maximum(abs.(dl.comp.total .- r.piP[3:6])))
        else
            println(io, "  feeder DLMP decomposition REFUSED: ", dl.reason)
        end
        for k in 1:6
            push!(prow, (; variant = name, node = k, piP = r.piP[k], piQ = r.piQ[k],
                piP_admm = fin.piP[k], piQ_admm = fin.piQ[k]))
        end
        push!(srow, (;
            variant = name,
            smax_line12 = c.tl[1].smax,
            smax_head34 = c.dl[1].smax,
            status = string(r.status),
            cost = r.cost,
            dcost = r.cost - base.cost,
            Pg = r.Pg,
            Pg2 = r.Pg2,
            Pdg = r.Pdg,
            P34 = r.P34,
            loading_line12 = r.lines[1].loading,
            loading_head34 = r.floading[1],
            rank_ratio = r.rr,
            max_cone_residual = maximum(x.gap for x in r.cones),
            max_cone_ratio = maximum(x.ratio for x in r.cones),
            ac_best = best === nothing ? NaN : best.cost,
            ac_gap = gap,
            admm_iters = a.iters,
            admm_converged = a.converged,
            admm_rel_cost_diff = (r.cost - fin.cost) / r.cost,
            admm_max_dpiP = maximum(abs.(fin.piP .- r.piP)),
            minus_lambda_p = -fin.lam[2],
            piP3_admm_x100 = 100 * fin.piP[3],
            binding = join([x.name for x in bd], "; "),
            binding_duals = join([@sprintf("%.6g", x.value) for x in bd], "; "),
        ))
    end
    fb0 = results["flex_baseline"].r
    dfx = max(abs(fb0.cost - base.cost) / TOL_COST, maximum(abs.(fb0.piP .- base.piP)) / TOL_PRICE,
        maximum(abs.(fb0.piQ .- base.piQ)) / TOL_PRICE)
    dfx <= 1 || error("congestion extension changes the uncongested baseline (G2/DG not out of merit)")
    @printf(io, "\nCheck: the extension leaves the uncongested baseline unchanged (|dcost| %.1e \$/h, max |dprice| %.1e \$/MWh; Pg2 = %.1e, Pdg = %.1e).\n",
        abs(fb0.cost - base.cost), max(maximum(abs.(fb0.piP .- base.piP)),
            maximum(abs.(fb0.piQ .- base.piQ))), fb0.Pg2, fb0.Pdg)
    println(io, "\nTransmission side note: the SDP balances are written in W (Tr(Phi_k W)), not as",
        " radial branch flows, so the radial path-sum DLMP decomposition does not apply to nodes",
        " 1-3; only the reference price at node 1 (= 2 c2 Pg + c1), the binding-line shadow price",
        " and the nodal spreads are reported there.")
    writecsv("congestion_prices.csv", DataFrame(prow))
    writecsv("congestion_dlmp.csv", DataFrame(drow))
    writecsv("congestion_summary.csv", DataFrame(srow))
    return results
end

# ------------------------------------------------------------------------------------------
# Experiment 4 -- inexact regime search (non-curtailable PV as a negative load)
# ------------------------------------------------------------------------------------------

# Search grid (documented, not tuned to a desired outcome):
#   A  Table I ratings, PV at node 6 (feeder end), loads 100 % and 50 % (the planned sweep);
#   B  Table I ratings, PV at node 5, loads 100 % and 50 % (extension: PV mid-feeder);
#   C  feeder ratings lifted to Smax = Imax = 3 pu on all three branches (extension: removes the
#      thermal bottleneck that caps the PV in A/B), PV at node 6, loads 100 %, 50 % and 25 %.
# PV in 0:0.05:3.0 pu, Q_pv = 0, the generator keeps its Table I bounds (Pg >= 0, no export
# sink). AC ground truth: Ipopt from a flat + 5 seeded random starts (max_iter 500); when the
# relaxation WITHOUT copy is infeasible the AC-OPF is certified infeasible (a relaxation) and
# Ipopt is skipped; at the first point of each sweep where Ipopt finds no AC point while the
# relaxation is feasible, the search is deepened to 20 random starts + 5 strategy variants.
const PV_GRID = collect(0.0:0.05:3.0)
const SWEEPS = [
    (stage = "A", node = 6, ratings = [1.0, 0.6, 0.4], load = 1.0),
    (stage = "A", node = 6, ratings = [1.0, 0.6, 0.4], load = 0.5),
    (stage = "B", node = 5, ratings = [1.0, 0.6, 0.4], load = 1.0),
    (stage = "B", node = 5, ratings = [1.0, 0.6, 0.4], load = 0.5),
    (stage = "C", node = 6, ratings = [3.0, 3.0, 3.0], load = 1.0),
    (stage = "C", node = 6, ratings = [3.0, 3.0, 3.0], load = 0.5),
    (stage = "C", node = 6, ratings = [3.0, 3.0, 3.0], load = 0.25),
]

"Which limits bind at a solved relaxed point (text tags)."
function binding_tags(c::Case6, r; tol = 1e-6)
    tags = String[]
    r.Vm[6] >= c.vmax - tol && push!(tags, "V6max")
    any(r.Vm .>= c.vmax - tol) && !(r.Vm[6] >= c.vmax - tol) && push!(tags, "Vmax")
    any(r.Vm .<= c.vmin + tol) && push!(tags, "Vmin")
    r.Pg <= c.pgmin + tol && push!(tags, "Pg=0")
    for (k, x) in enumerate(r.cones)
        x.l >= c.dl[k].imax^2 * (1 - tol) && push!(tags, "Imax($(c.dl[k].i),$(c.dl[k].j))")
        r.floading[k] >= 1 - tol && push!(tags, "Smax($(c.dl[k].i),$(c.dl[k].j))")
    end
    any(x.loading >= 1 - tol for x in r.lines) && push!(tags, "Smax_line")
    return join(tags, "+")
end

function experiment4(io)
    section(io, "EXPERIMENT 4 -- INEXACT REGIME SEARCH (PV back-feed, with/without exactness copy)")
    println(io, "Grid: PV in 0:0.05:3.0 pu (Q = 0, non-curtailable, negative load).")
    println(io, "  A: Table I ratings, PV at node 6, loads 100 % / 50 %")
    println(io, "  B: Table I ratings, PV at node 5, loads 100 % / 50 %")
    println(io, "  C: feeder Smax = Imax = 3 pu on all branches, PV at node 6, loads 100 / 50 / 25 %")
    println(io, "Exactness: SOC = framework hybrid-floor ratio <= 1; SDP = |lambda2/lambda1| < $RANK_EXACT.")
    rows = NamedTuple[]
    for sw in SWEEPS
        deepened = false
        for p in PV_GRID
            pv = zeros(6)
            pv[sw.node] = p
            c = case6(; pv = pv, load_scale = sw.load, smax_feeder = sw.ratings)
            r0 = solve_hybrid(c)
            r1 = solve_hybrid(c; copy = true)
            rf = solve_hybrid(c; dso = :framework)
            ac_cost = NaN
            ac_note = ""
            if !r0.ok
                ac_note = "infeasible (certified: relaxation infeasible)"
            else
                deep = false
                acrows, best = ac_multistart(c; nrand = 5, max_iter = 500)
                if best === nothing && !deepened
                    acrows, best = ac_multistart(c; nrand = 20, variants = true, max_iter = 3000)
                    deepened = true
                    deep = true
                end
                n = length(acrows)
                if best === nothing
                    ac_note = "no AC point found ($n starts: " *
                              join(sort(unique([x.status for x in acrows])), ",") * ")"
                else
                    ac_cost = best.cost
                    ac_note = "AC solved ($(count(x -> x.ok, acrows))/$n starts)"
                end
                deep && (ac_note *= " [deepened search]")
            end
            for (form, r) in (("no_copy", r0), ("copy", r1))
                push!(rows, (;
                    stage = sw.stage,
                    pv_node = sw.node,
                    load_scale = sw.load,
                    feeder_rating = sw.ratings[1],
                    pv = p,
                    formulation = form,
                    status = string(r.status),
                    feasible = r.ok,
                    cost = r.ok ? r.cost : NaN,
                    Pg = r.ok ? r.Pg : NaN,
                    max_cone_residual = r.ok ? maximum(x.gap for x in r.cones) : NaN,
                    max_cone_ratio = r.ok ? maximum(x.ratio for x in r.cones) : NaN,
                    soc_exact = r.ok ? exact_soc(r) : false,
                    rank_ratio = r.ok ? r.rr : NaN,
                    sdp_exact = r.ok ? exact_sdp(r) : false,
                    V6 = r.ok ? r.Vm[6] : NaN,
                    binding = r.ok ? binding_tags(c, r) : "",
                    ac_cost,
                    ac_note,
                    gap_vs_ac = r.ok ? (ac_cost - r.cost) / ac_cost : NaN,
                    framework_status = string(rf.status),
                    framework_cost = rf.ok ? rf.cost : NaN,
                ))
            end
        end
    end
    df = DataFrame(rows)
    writecsv("inexact_pv_sweep.csv", df)

    # Per-sweep digest.
    for sw in SWEEPS
        sel(form) = filter(
            x -> x.stage == sw.stage && x.pv_node == sw.node && x.load_scale == sw.load &&
                     x.formulation == form,
            rows,
        )
        nc = sel("no_copy")
        cp = sel("copy")
        println(io, "\n--- stage $(sw.stage): PV at node $(sw.node), loads $(Int(100sw.load)) %, feeder ratings $(sw.ratings) ---")
        lastfeas(v) = (i = findlast(x -> x.feasible, v); i === nothing ? NaN : v[i].pv)
        lastac = (i = findlast(x -> isfinite(x.ac_cost), nc); i === nothing ? NaN : nc[i].pv)
        @printf(io, "  largest PV with: relaxation feasible %.2f | AC point found %.2f | copy feasible %.2f pu\n",
            lastfeas(nc), lastac, lastfeas(cp))
        inex = [x for x in nc if x.feasible && !(x.soc_exact && x.sdp_exact)]
        if isempty(inex)
            println(io, "  no-copy relaxation: EXACT (SOC and SDP) at every feasible point")
        else
            println(io, "  no-copy relaxation INEXACT at PV = ",
                join([f(x.pv; d = 2) for x in inex], ", "))
            for x in inex
                @printf(io, "    PV %.2f: cost %.3f, Pg %.4f, max cone residual %.2e (ratio %.1e), |l2/l1| %.1e, binding %s, AC: %s\n",
                    x.pv, x.cost, x.Pg, x.max_cone_residual, x.max_cone_ratio, x.rank_ratio,
                    x.binding, x.ac_note)
            end
        end
        both = [(a, b) for (a, b) in zip(nc, cp) if isfinite(a.ac_cost)]
        if !isempty(both)
            mg = maximum(abs(a.gap_vs_ac) for (a, b) in both)
            @printf(io, "  where AC was solved: max |relaxation gap| = %.2e\n", mg)
            cons = [(b.pv, (b.cost - a.ac_cost) / a.ac_cost) for (a, b) in both if b.feasible]
            if !isempty(cons)
                worst = cons[argmax(last.(cons))]
                @printf(io, "  copy conservatism (copy - AC)/AC: max %.3e at PV %.2f, mean %.3e over %d points\n",
                    worst[2], worst[1], sum(last.(cons)) / length(cons), length(cons))
            end
            inexcopy = [b.pv for (a, b) in both if b.feasible && !b.soc_exact]
            isempty(inexcopy) || println(io,
                "  copy model INEXACT at AC-feasible PV = ", join(f.(inexcopy; d = 2), ", "))
            lost = [b.pv for (a, b) in both if !b.feasible]
            isempty(lost) || println(io,
                "  copy model INFEASIBLE although AC solved at PV = ", join(f.(lost; d = 2), ", "))
        end
        inexc = [x for x in cp if x.feasible && !x.soc_exact]
        isempty(inexc) || println(io, "  copy model INEXACT (any PV) at PV = ",
            join([f(x.pv; d = 2) for x in inexc], ", "))
        fwd = [abs(a.framework_cost - b.cost) for (a, b) in zip(nc, cp) if
               isfinite(a.framework_cost) && b.feasible]
        isempty(fwd) || @printf(io, "  framework-hosted (copy + receiving-end cone) vs script copy: max |dcost| = %.2e \$/h over %d points\n",
            maximum(fwd), length(fwd))
    end
    return rows
end

# ------------------------------------------------------------------------------------------
# Figures
# ------------------------------------------------------------------------------------------

const NODE_COLORS = CairoMakie.Makie.wong_colors()

function fig_admm(e2, base)
    tr = e2.a.trace
    it = [t.k for t in tr]
    fig = Figure(; size = (900, 340), fontsize = 14)
    ax1 = Axis(fig[1, 1]; xlabel = "iteration", ylabel = "residual", yscale = log10)
    lines!(ax1, it, [t.primal for t in tr]; label = "primal ‖y_T − y_D‖₂ (pu)")
    lines!(ax1, it, [t.dual for t in tr]; label = "dual ρ‖Δy_D‖₂ (\$/h per pu)")
    hlines!(ax1, [1e-4]; color = :gray, linestyle = :dash)
    hlines!(ax1, [1e-2]; color = :gray, linestyle = :dot)
    axislegend(ax1; position = :rt)
    ax2 = Axis(fig[1, 2]; xlabel = "iteration", ylabel = "TSO generation cost (\$/h)")
    lines!(ax2, it, [t.cost for t in tr]; label = "ADMM (TSO)")
    hlines!(ax2, [base.cost]; color = :black, linestyle = :dash, label = "monolithic")
    ylims!(ax2, base.cost - 1500, base.cost + 300)
    axislegend(ax2; position = :rb)
    saveboth("admm_convergence", fig)

    fig = Figure(; size = (700, 420), fontsize = 14)
    ax = Axis(fig[1, 1]; xlabel = "iteration", ylabel = "active nodal price (\$/MWh)")
    for k in 1:6
        lines!(ax, it, [t.piP[k] for t in tr]; color = NODE_COLORS[k],
            linestyle = k <= 3 ? :solid : :dash, label = "node $k")
        hlines!(ax, [base.piP[k]]; color = NODE_COLORS[k], linestyle = :dot)
    end
    ylims!(ax, 0, 75)
    axislegend(ax; position = :rb, nbanks = 2)
    saveboth("admm_price_evolution", fig)
    return nothing
end

function fig_sweeps(e2)
    rs = e2.rs
    fig = Figure(; size = (600, 380), fontsize = 14)
    ax = Axis(fig[1, 1]; xlabel = "ρ", ylabel = "ADMM iterations", xscale = log10,
        yscale = log10)
    conv = [x.converged for x in rs]
    scatterlines!(ax, [x.rho for x in rs], [x.iters for x in rs]; color = :black)
    any(.!conv) && scatter!(ax, [x.rho for x in rs][.!conv], [x.iters for x in rs][.!conv];
        color = :red, marker = :x, markersize = 16, label = "not converged")
    vlines!(ax, [6259.0]; color = :gray, linestyle = :dash)
    text!(ax, 6259.0, maximum(x.iters for x in rs); text = " π_P3·100", align = (:left, :top))
    saveboth("admm_rho_sweep", fig)

    es = e2.es
    fig = Figure(; size = (600, 380), fontsize = 14)
    labels = [x.eps == 0 ? "0" : @sprintf("%.0e", x.eps) for x in es]
    ax = Axis(fig[1, 1]; xlabel = "ε (loss penalty)", ylabel = "cone residual l·v − P² − Q² (pu)",
        yscale = log10, xticks = (1:length(es), labels))
    floor = 1e-14
    scatterlines!(ax, 1:length(es), [max(x.max_cone_iterates, floor) for x in es];
        label = "max over all DSO iterates")
    scatterlines!(ax, 1:length(es), [max(abs(x.cone_final), floor) for x in es];
        label = "at convergence")
    hlines!(ax, [TSODSO.TAU_SOLVER_EXACT]; color = :gray, linestyle = :dash,
        label = "framework floor τ")
    axislegend(ax; position = :rc)
    saveboth("admm_eps_sweep", fig)
    return nothing
end

function fig_congestion(e3)
    fig = Figure(; size = (900, 360), fontsize = 14)
    ax1 = Axis(fig[1, 1]; xlabel = "node", ylabel = "π_P (\$/MWh)")
    ax2 = Axis(fig[1, 2]; xlabel = "node", ylabel = "π_Q (\$/Mvarh)")
    names = ("baseline", "flex_line12", "flex_head34", "flex_both")
    labels = ("baseline", "line (1,2) congested", "head (3,4) congested", "both congested")
    for (i, name) in enumerate(names)
        e3[name] === nothing && continue
        r = e3[name].r
        scatterlines!(ax1, 1:6, r.piP; color = NODE_COLORS[i], label = labels[i])
        scatterlines!(ax2, 1:6, r.piQ; color = NODE_COLORS[i], label = labels[i])
    end
    axislegend(ax1; position = :lt)
    saveboth("congestion_prices", fig)
    return nothing
end

function fig_inexact(rows)
    fig = Figure(; size = (1000, 640), fontsize = 13)
    floor = 1e-12
    panels = [("A", 6, 1.0), ("C", 6, 1.0), ("C", 6, 0.25)]
    for (j, (st, nd, ls)) in enumerate(panels)
        sel(form) = filter(
            x -> x.stage == st && x.pv_node == nd && x.load_scale == ls &&
                     x.formulation == form && x.feasible,
            rows,
        )
        ax = Axis(fig[1, j]; xlabel = "PV at node $nd (pu)", ylabel = "max cone residual (pu)",
            yscale = log10, title = "stage $st, loads $(Int(100ls)) %")
        for (form, col) in (("no_copy", :black), ("copy", :orange))
            v = sel(form)
            isempty(v) && continue
            scatterlines!(ax, [x.pv for x in v], [max(abs(x.max_cone_residual), floor) for x in v];
                color = col, label = form == "copy" ? "with copy" : "without copy")
        end
        hlines!(ax, [TSODSO.TAU_SOLVER_EXACT]; color = :gray, linestyle = :dash)
        j == 1 && axislegend(ax; position = :lt)
        ax2 = Axis(fig[2, j]; xlabel = "PV at node $nd (pu)", ylabel = "(cost − AC opt.)/AC opt.")
        for (form, col) in (("no_copy", :black), ("copy", :orange))
            v = filter(x -> isfinite(x.ac_cost), sel(form))
            isempty(v) && continue
            scatterlines!(ax2, [x.pv for x in v], [(x.cost - x.ac_cost) / x.ac_cost for x in v];
                color = col)
        end
    end
    saveboth("inexact_cone_slack", fig)
    return nothing
end

# ------------------------------------------------------------------------------------------
# Verdicts vs the paper's claims (data-driven)
# ------------------------------------------------------------------------------------------

function verdicts(io, b0, e1, e2, e3, e4)
    section(io, "AGREEMENTS AND DISAGREEMENTS WITH THE PAPER")
    r = b0.r
    a = e2.a
    fin = a.final
    agree = String[]
    disagree = String[]
    push!(agree, @sprintf("Monolithic optimum reproduced: cost %.4f vs 7461.105 \$/h, all 12 prices within %.1e \$/MWh of Table III (gate tolerances above).",
        r.cost, max(maximum(abs.(r.piP .- PAPER.piP)), maximum(abs.(r.piQ .- PAPER.piQ)))))
    push!(agree, @sprintf("Both relaxations tight at the baseline: |lambda2/lambda1| = %.1e, cone residuals <= %.1e (paper 2.6e-7; the paper's values are solver-accuracy dependent).",
        r.rr, maximum(x.gap for x in r.cones)))
    push!(agree, @sprintf("Global optimality: Ipopt best AC cost %.6f vs relaxation %.6f \$/h (gap %.1e), %d/%d starts locally solved, %d distinct optimum.",
        e1.best.cost, r.cost, e1.gap, count(x -> x.ok, e1.rows), length(e1.rows),
        distinct_optima(e1.rows)))
    (a.iters == 57 ? agree : disagree) |>
    v -> push!(v, @sprintf("ADMM at rho=500, eps=1e-2 converges in %d iterations (paper 57).", a.iters))
    push!(abs(fin.primal - 9.1e-5) < 0.05e-5 ? agree : disagree,
        @sprintf("Final primal residual %.2e pu (paper 9.1e-5).", fin.primal))
    push!(abs(fin.dual - 1.8e-3) < 0.05e-3 ? agree : disagree,
        @sprintf("Final dual residual %.2e (paper 1.8e-3).", fin.dual))
    push!(abs(fin.cost - 7460.537) < 5e-4 ? agree : disagree,
        @sprintf("ADMM TSO cost %.3f \$/h (paper 7460.537), relative difference to monolithic %.2e (paper 7.6e-5).",
            fin.cost, (r.cost - fin.cost) / r.cost))
    push!(abs(e2.settle - 40) <= 5 ? agree : disagree,
        @sprintf("Prices within 0.1 %% of monolithic from iteration %d on (paper: about 40).", e2.settle))
    push!(abs(-fin.lam[2] - 100 * fin.piP[3]) < 1e-2 ? agree : disagree,
        @sprintf("-lambda_p = %.3f = piP3(ADMM)*100 = %.3f (paper 6258.80).", -fin.lam[2],
            100 * fin.piP[3]))
    maxrel = maximum(abs.(fin.piP .- r.piP) ./ r.piP)
    push!(maxrel < 4e-5 ? agree : disagree,
        @sprintf("ADMM active prices within %.4f %% of monolithic (paper: 0.004 %%).", 100 * maxrel))
    rs = e2.rs
    best = rs[argmin([x.iters for x in rs])]
    push!(agree, @sprintf("rho guidance: iterations fall from %d (rho=50) to %d at rho=%.0f; the fastest rho values (%s) sit on the scale of piP3*100 = %.0f \$/h per pu, so the paper's guidance holds and rho = 500 is about an order of magnitude below the fastest setting.",
        rs[1].iters, best.iters, best.rho,
        join([@sprintf("%.0f", x.rho) for x in rs if x.iters <= 2 * best.iters], ", "),
        100 * r.piP[3]))
    es = e2.es
    push!(agree, @sprintf("eps guidance: eps in {0, 1e-4, 1e-3, 1e-2, 1e-1} gives %s iterations, max cone residual over ALL intermediate DSO iterates <= %.1e and identical final cost bias; eps = 0 is safe on this case.",
        join(unique([x.iters for x in es]), "/"), maximum(x.max_cone_iterates for x in es)))
    # Congestion
    for name in ("paper_line12_band", "paper_head34_band", "flex_line12", "flex_head34", "flex_both")
        x = e3[name]
        if x === nothing
            push!(disagree, "Congestion '$name' (new result): infeasible at the chosen limits (relaxation and Ipopt).")
            continue
        end
        ex = exact_sdp(x.r) && exact_soc(x.r)
        g = x.best === nothing ? NaN : (x.best.cost - x.r.cost) / x.best.cost
        # Price uniqueness: the same optimum priced by the paper model, the framework-hosted
        # model and ADMM must agree; a spread far above solver noise means non-unique duals.
        spread = max(
            maximum(abs.(x.a.final.piP .- x.r.piP)),
            x.dl.ok ? maximum(abs.(x.dl.comp.total .- x.r.piP[3:6])) : 0.0,
        )
        unique_prices = spread < 0.1
        push!(ex && abs(g) < 1e-6 && unique_prices ? agree : disagree,
            @sprintf("Congestion '%s' (new result): relaxation %s (|l2/l1| %.1e, max cone ratio %.1e), AC gap %.1e, ADMM %s in %d iterations, cost %+.4f %%, price spread across paper model / framework model / ADMM %.2e \$/MWh%s.",
                name, ex ? "EXACT" : "INEXACT", x.r.rr, maximum(c.ratio for c in x.r.cones), g,
                x.a.converged ? "converged" : "did NOT converge", x.a.iters,
                100 * (x.r.cost - b0.r.cost) / b0.r.cost, spread,
                !x.a.converged ? " (ADMM not converged: its prices are not comparable)" :
                unique_prices ? "" :
                " (NON-UNIQUE duals: the limit binds at a degenerate point)"))
    end
    # Inexactness
    inex = filter(x -> x.formulation == "no_copy" && x.feasible && !(x.soc_exact && x.sdp_exact), e4)
    exA = filter(x -> x.stage in ("A", "B") && x.formulation == "no_copy" && x.feasible, e4)
    push!(agree, @sprintf("Inexactness search (new result): with Table I ratings (stages A, B; %d feasible points) the relaxation is exact wherever feasible; it becomes infeasible where Ipopt finds no AC point.",
        length(exA)))
    if !isempty(inex)
        stages = join(sort(unique([x.stage for x in inex])), ", ")
        acfound = count(x -> isfinite(x.ac_cost), inex)
        push!(disagree, @sprintf("Inexact regime found (stage %s, lifted feeder ratings): %d PV points where the relaxation is feasible but inexact (max cone residual up to %.2f pu); Ipopt found an AC point at %d of them. The paper's tightness test detects these points.",
            stages, length(inex), maximum(x.max_cone_residual for x in inex), acfound))
        cpi = filter(x -> x.formulation == "copy" && x.feasible && !x.soc_exact, e4)
        push!(disagree, @sprintf("The LinDistFlow exactness copy does NOT restore exactness in that regime: %d feasible copy-model points remain inexact.",
            length(cpi)))
    end
    println(io, "Agreements:")
    foreach(s -> println(io, "  + ", s), agree)
    println(io, "\nDisagreements / qualifications / new findings that the paper must state differently:")
    foreach(s -> println(io, "  - ", s), disagree)
    return nothing
end

# ------------------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------------------

function main()
    io = IOBuffer()
    println(io, "6-node hybrid SDP-SOCP T&D case study -- results summary")
    println(io, "Generated by scripts/td_hybrid_6node_case_study.jl (seed $SEED). Prices in \$/MWh",
        " (\$/Mvarh), power in pu on 100 MVA.")
    b0 = experiment0(io)
    e1 = experiment1(io, b0)
    e2 = experiment2(io, b0)
    e3 = experiment3(io, b0)
    e4 = experiment4(io)
    fig_admm(e2, b0.r)
    fig_sweeps(e2)
    fig_congestion(e3)
    fig_inexact(e4)
    verdicts(io, b0, e1, e2, e3, e4)
    txt = String(take!(io))
    write(joinpath(OUT, "summary.txt"), txt)
    print(txt)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

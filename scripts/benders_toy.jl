# scripts/benders_toy.jl
#
# A visual, step-by-step toy of Benders decomposition — the SAME algorithm the planning
# layer uses (`src/planning/benders.jl` `solve_stackelberg!`), but reduced to ONE scalar
# decision so the geometry can be drawn.
#
# The toy mirrors the repo's structure 1:1:
#   • MASTER   — an LP `min c_y·y + α_op + α_x` over leader investment `y` and import `z`,
#                with `α_op`/`α_x` as epigraph (cost-to-go) variables, tightened by cuts.
#   • ORACLE   — the "operational welfare" subproblem: given a trial `z_k`, returns its
#                cost `α_op(z_k)` and gradient `α_op'(z_k)`  → an OPTIMALITY cut on α_op.
#   • FOLLOWER — the "transmission reinforcement" subproblem: given `z_k`, returns its
#                cost `α_x(z_k)` + gradient (feasible branch → optimality cut on α_x) or a
#                Farkas certificate (infeasible branch → FEASIBILITY cut on z).
#
# The loop: master proposes z_k → subproblems evaluate → cuts accumulate → LB rises, UB
# falls → converge on the relative gap (UB−LB)/max(1,|UB|) ≤ tol. Exactly `solve_stackelberg!`.
#
# Run:
#     julia --project=. scripts/benders_toy.jl
# Figures land in  results/benders_toy/  (PDF + PNG).

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using JuMP
using JuMP: value
using CairoMakie
using Printf

const OUT = projectdir("results", "benders_toy")
mkpath(OUT)
saveboth(name, fig) = (save(joinpath(OUT, "$name.pdf"), fig); save(joinpath(OUT, "$name.png"), fig))

# -------------------------------------------------------------------------------------------
# The TRUE problem (hidden from the master — it learns it only via cuts).
#
#   min_{y ≥ 0, z}   c_y·y  +  α_op(z)  +  α_x(z)
#   s.t.  0 ≤ z ≤ y ≤ y_max
#         z ≤ z_cap_max          (follower feasibility — enforced by feasibility cuts)
#
# where:
#   α_op(z) = a·(z − z*)²          convex "welfare loss" (min at the welfare-optimal import z*)
#   α_x(z)  = s·max(0, z − z_free) "transmission reinforcement": free up to z_free, then linear
#
# With the parameters below the unconstrained optimum is z ≈ 0.50; z_cap_max = 0.50 makes the
# feasibility limit bind exactly there, so the loop exhibits BOTH an optimality cut AND a
# feasibility cut before converging.
# -------------------------------------------------------------------------------------------
const c_y       = 1.0      # flex-investment unit cost
const y_max     = 1.0      # max leader investment
const Z_STAR    = 0.70     # welfare-optimal import (α_op minimized here)
const A_OP      = 10.0     # α_op curvature
const Z_FREE    = 0.30     # free corridor capacity (α_x = 0 below this)
const S_X       = 3.0      # α_x slope above z_free
const Z_CAP_MAX = 0.50     # HARD feasibility limit (follower can't deliver more)

α_op(z)    = A_OP * (z - Z_STAR)^2
α_op′(z)   = 2 * A_OP * (z - Z_STAR)
α_x(z)     = z ≤ Z_FREE ? 0.0 : S_X * (z - Z_FREE)
α_x′(z)    = z <  Z_FREE ? 0.0 : S_X
true_cost(z) = c_y * z + α_op(z) + α_x(z)

# --- the two subproblems (return cost + gradient, or a Farkas-style feasibility cut) -------
oracle(z_k)   = (cost = α_op(z_k),  grad = α_op′(z_k))
function follower(z_k)
    if z_k > Z_CAP_MAX + 1e-9
        # INFEASIBLE: follower can't deliver z_k. Return a Farkas-style cut coefficient.
        # In 1-D the infeasible region z > z_cap_max is excluded by the cut  z ≤ z_cap_max.
        return (feasible = false, cost = NaN, grad = NaN)
    end
    return (feasible = true, cost = α_x(z_k), grad = α_x′(z_k))
end

# -------------------------------------------------------------------------------------------
# BENDERS LOOP — master LP built once, cuts appended as @constraint rows (mirrors master.jl).
# -------------------------------------------------------------------------------------------
const TOL = 1e-6
const MAXITER = 20

master = Model(select_optimizer(LP()))
set_silent(master)
@variable(master, y ≥ 0)
@variable(master, z ≥ 0)
@variable(master, α_op_var ≥ 0)
@variable(master, α_x_var ≥ 0)
@constraint(master, z ≤ y)
@constraint(master, y ≤ y_max)
@objective(master, Min, c_y * y + α_op_var + α_x_var)

# per-iteration log for plotting
trace = (; z = Float64[], LB = Float64[], UB = Float64[], kind = Symbol[],
         op_cuts = Tuple{Float64,Float64,Float64}[],   # (cost, grad, z_k) for α_op cuts
         x_cuts = Tuple{Float64,Float64,Float64}[],    # (cost, grad, z_k) for α_x cuts
         feas_cuts = Float64[])                        # z_cap_max bounds added

UB = Inf
z_best, y_best = NaN, NaN
converged = false
println("=" ^ 64)
println("Toy Benders — min  c_y·y + α_op(z) + α_x(z)   (true optimum z = $(Z_CAP_MAX))")
println("=" ^ 64)
for k in 1:MAXITER
    optimize!(master)
    LB = objective_value(master)
    z_k = value(z)
    y_k = value(y)

    # (a) FOLLOWER feasibility check FIRST (WR-01: never send an undeliverable z to the oracle)
    fres = follower(z_k)
    if !fres.feasible
        push!(trace.feas_cuts, Z_CAP_MAX)
        @constraint(master, z ≤ Z_CAP_MAX)
        push!(trace.z, z_k); push!(trace.LB, LB); push!(trace.UB, UB); push!(trace.kind, :feas)
        @printf("iter %2d  FEASIBILITY cut  z_k=%.4f > z_cap=%.2f  (LB=%.4f, UB=Inf)\n",
                k, z_k, Z_CAP_MAX, LB)
        continue
    end

    # (b) FEASIBLE → oracle optimality cut + follower optimality cut
    ores = oracle(z_k)
    # α_op cut:  α_op ≥ cost + grad·(z − z_k)
    @constraint(master, α_op_var ≥ ores.cost + ores.grad * (z - z_k))
    # α_x cut:   α_x  ≥ cost + grad·(z − z_k)
    @constraint(master, α_x_var  ≥ fres.cost + fres.grad * (z - z_k))
    push!(trace.op_cuts, (ores.cost, ores.grad, z_k))
    push!(trace.x_cuts, (fres.cost, fres.grad, z_k))

    # (c) true cost of this iterate → candidate upper bound + incumbent
    cost_k = c_y * y_k + α_op(z_k) + α_x(z_k)
    if cost_k < UB
        global UB = cost_k
        global z_best, y_best = z_k, y_k
    end
    gap = (UB - LB) / max(1, abs(UB))
    push!(trace.z, z_k); push!(trace.LB, LB); push!(trace.UB, UB); push!(trace.kind, :optim)
    @printf("iter %2d  z_k=%.4f  LB=%.4f  UB=%.4f  gap=%.2e\n", k, z_k, LB, UB, gap)
    if gap ≤ TOL
        global converged = true
        println("CONVERGED at z* = ", round(z_best; digits = 4),
                "  (true optimum ", Z_CAP_MAX, "),  cost = ", round(UB; digits = 4))
        break
    end
end
converged || error("Benders toy did not converge in $MAXITER iterations")

# -------------------------------------------------------------------------------------------
# PLOTS
# -------------------------------------------------------------------------------------------
zs = range(0, 1; length = 400)
iters = 1:length(trace.z)

# === Panel figure: the geometry of Benders ============================================
let
    fig = Figure(; size = (1100, 820))
    fig[0, 1:2] = Label(fig,
        "Benders decomposition — a 1-D toy of the planning layer's Stackelberg solve";
        fontsize = 16, font = :bold)

    # (a) α_op(z) + its accumulating optimality cuts
    ax1 = Axis(fig[1, 1];
        xlabel = "import z", ylabel = "α_op(z)  (welfare cost)",
        title = "(a) operational-welfare subproblem: optimality cuts on α_op",
        titlealign = :left, limits = ((0, 1), nothing))
    lines!(ax1, zs, α_op.(zs); color = :black, linewidth = 2.2, label = "true α_op(z)")
    for (i, (c, g, zk)) in enumerate(trace.op_cuts)
        col = (:crimson, 0.35 + 0.5 * i / max(1, length(trace.op_cuts)))
        lab = i ≤ 2 ? "cut @ z=$(round(zk; digits=2))" : nothing
        lines!(ax1, zs, c .+ g .* (zs .- zk); color = col, linewidth = 1.4, label = lab)
    end
    scatter!(ax1, [t for (c, g, t) in trace.op_cuts],
             [α_op(t) for (c, g, t) in trace.op_cuts]; color = :crimson, markersize = 9)
    axislegend(ax1; position = :rt, framevisible = false)

    # (b) α_x(z) + its cuts + the feasibility wall
    ax2 = Axis(fig[1, 2];
        xlabel = "import z", ylabel = "α_x(z)  (transmission cost)",
        title = "(b) transmission-follower subproblem: optimality + feasibility cuts",
        titlealign = :left, limits = ((0, 1), nothing))
    lines!(ax2, zs, α_x.(zs); color = :black, linewidth = 2.2, label = "true α_x(z)")
    for (i, (c, g, zk)) in enumerate(trace.x_cuts)
        col = (:dodgerblue, 0.35 + 0.5 * i / max(1, length(trace.x_cuts)))
        lab = i ≤ 2 ? "cut @ z=$(round(zk; digits=2))" : nothing
        lines!(ax2, zs, c .+ g .* (zs .- zk); color = col, linewidth = 1.4, label = lab)
    end
    # the feasibility wall (z_cap_max) — any z beyond it is ruled out by a feasibility cut
    if !isempty(trace.feas_cuts)
        vlines!(ax2, [Z_CAP_MAX]; color = :purple, linewidth = 2, linestyle = :dash,
                label = "feasibility wall  z ≤ $Z_CAP_MAX")
    end
    scatter!(ax2, [t for (c, g, t) in trace.x_cuts],
             [α_x(t) for (c, g, t) in trace.x_cuts]; color = :dodgerblue, markersize = 9)
    axislegend(ax2; position = :lt, framevisible = false)

    # (c) Master's TOTAL cost approximation vs the true total, with trial points
    ax3 = Axis(fig[2, 1];
        xlabel = "import z", ylabel = "total cost",
        title = "(c) master's piecewise-linear approximation (lower bound) vs true cost",
        titlealign = :left, limits = ((0, 1), nothing))
    lines!(ax3, zs, true_cost.(zs); color = :black, linewidth = 2.2, label = "true total cost")
    # master approximation at each z = c_y·z + max_cuts(α_op) + max_cuts(α_x)
    function master_approx(zv)
        aop = isempty(trace.op_cuts) ? 0.0 : maximum(c + g * (zv - zk) for (c, g, zk) in trace.op_cuts)
        axv = isempty(trace.x_cuts) ? 0.0 : maximum(c + g * (zv - zk) for (c, g, zk) in trace.x_cuts)
        return c_y * zv + aop + axv
    end
    lines!(ax3, zs, master_approx.(zs); color = :seagreen, linewidth = 1.8,
           label = "master approximation (final)")
    # trial points colored by kind
    opt_idx = findall(==(:optim), trace.kind)
    feas_idx = findall(==(:feas), trace.kind)
    isempty(opt_idx)  || scatter!(ax3, trace.z[opt_idx],  true_cost.(trace.z[opt_idx]);
                                  color = :crimson, markersize = 11, label = "optimality-cut trial z_k")
    isempty(feas_idx) || scatter!(ax3, trace.z[feas_idx], fill(minimum(true_cost.(zs)) - 0.5, length(feas_idx));
                                  color = :purple, markersize = 13, marker = :utriangle, label = "infeasible trial z_k")
    vlines!(ax3, [z_best]; color = :gold, linewidth = 2, linestyle = :dot, label = "incumbent z*")
    axislegend(ax3; position = :rt, framevisible = false)

    # (d) UB/LB convergence
    ax4 = Axis(fig[2, 2];
        xlabel = "Benders iteration k", ylabel = "bound",
        title = "(d) bound convergence: LB ↑ from below, UB ↓ from above",
        titlealign = :left)
    # UB is Inf during early feasibility iterations; clamp for plotting
    ub_plot = [isfinite(u) ? u : NaN for u in trace.UB]
    lines!(ax4, iters, trace.LB; color = :dodgerblue, linewidth = 2, label = "LB (master obj)")
    lines!(ax4, iters, ub_plot;  color = :crimson,   linewidth = 2, label = "UB (best true cost)")
    scatter!(ax4, iters, trace.LB; color = :dodgerblue, markersize = 8)
    scatter!(ax4, iters, ub_plot;  color = :crimson,   markersize = 8)
    hlines!(ax4, [UB]; color = :grey, linestyle = :dash, label = "converged cost")
    # mark feasibility-cut iterations
    isempty(feas_idx) || vlines!(ax4, feas_idx; color = :purple, linestyle = :dot,
                                 label = "feasibility cut")
    axislegend(ax4; position = :rt, framevisible = false)

    saveboth("benders_toy", fig)
    println("\n✓ benders_toy.{pdf,png}")
end

# === Per-iteration step figure (small multiples) =======================================
# Show the master approximation GROWING cut-by-cut, so the "step-by-step" is literal.
let
    niter = length(trace.op_cuts)
    ncol = min(3, niter)
    nrow = cld(niter, ncol)
    fig = Figure(; size = (380 * ncol, 320 * nrow))
    fig[0, 1:ncol] = Label(fig, "Benders step-by-step: the master's lower bound tightens each iteration";
        fontsize = 14, font = :bold)
    for (i, (c, g, zk)) in enumerate(trace.op_cuts)
        r, col = fldmod1(i, ncol)
        ax = Axis(fig[r, col];
            xlabel = "z", ylabel = "total cost", title = "iter $i: trial z_k=$(round(zk; digits=2))",
            titlealign = :left, limits = ((0, 1), (0, 6)))
        lines!(ax, zs, true_cost.(zs); color = :black, linewidth = 2)
        # approximation using only the cuts seen so far (1..i)
        aop(zv) = maximum(c + g * (zv - zk) for (c, g, zk) in trace.op_cuts[1:i])
        axv(zv) = isempty(trace.x_cuts) ? 0.0 :
                  maximum(c + g * (zv - zk) for (c, g, zk) in trace.x_cuts[1:min(i, end)])
        approx(zv) = c_y * zv + aop(zv) + axv(zv)
        lines!(ax, zs, approx.(zs); color = :seagreen, linewidth = 1.6)
        vlines!(ax, [zk]; color = :crimson, linestyle = :dash)
    end
    saveboth("benders_toy_steps", fig)
    println("✓ benders_toy_steps.{pdf,png}")
end

println("\nTrue optimum: z* = ", Z_CAP_MAX, ",  cost = ", round(true_cost(Z_CAP_MAX); digits = 4))
println("Benders found: z* = ", round(z_best; digits = 4),
        ",  cost = ", round(UB; digits = 4),
        "  in ", length(trace.z), " iterations")
println("Figures written to: ", OUT)

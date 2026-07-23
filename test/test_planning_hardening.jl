# test/test_planning_hardening.jl
#
# Seam: phase-12 cut-store & Benders master robustness hardening pass — deepens
# PLAN-05 (persistent cut accumulation) and PLAN-06 (UB/LB gap convergence
# detection) from Phase 11 at realistic scale; owns NO new requirement IDs.
# Items tagged `[:planning]`, names contain "planning" and "hardening"
# (occursin filter convention, mirrors test_planning_master.jl).
#
# Each `@testitem` here operates at the MASTER level (via `build_master`/
# `add_feasibility_cut!`/`add_optimality_cut!`/`solve_master!` and
# `build_follower`/`solve_follower!` directly) — NOT the full `solve_stackelberg!`
# loop, per 12-CONTEXT.md's scope for these degenerate feasibility-cut edge cases.
#
# Fixture note: cases (a)/(c) reuse test_planning_benders.jl's own WR-04 fixture
# (corridor_cap=2.0, x_inv_max=0.25 ⇒ deliverable cap 0.5) so the near-boundary trial
# z=0.5±1e-6 straddles a KNOWN, already-certified feasible/infeasible boundary. The
# offset is 1e-6, NOT 1e-9: MEASURED this session (not assumed — 10-RESEARCH.md
# Pitfall 4 "measure, don't guess" convention) that HiGHS's own default feasibility
# tolerance accepts a 1e-9 boundary violation as still feasible on this fixture, so it
# does not reliably split into a feasible/infeasible pair; 1e-6 does.

@testitem "planning hardening: near-boundary z — deliverable-cap ± 1e-6 stays valid, cut store finite" tags =
    [:planning] begin
    using TSODSO
    using JuMP: termination_status, MOI

    # Deliverable cap = corridor_cap * x_inv_max = 2.0 * 0.25 = 0.5 (the WR-04 fixture's
    # own cap, test_planning_benders.jl). MEASURED (not assumed — 10-RESEARCH.md
    # Pitfall 4 "measure, don't guess" convention): HiGHS's own default feasibility
    # tolerance (~1e-7/1e-8) accepts a boundary violation of 1e-9 as still feasible, so
    # a ±1e-9 offset does NOT reliably split into a feasible/infeasible pair on THIS
    # fixture. Empirically verified this session: ±1e-6 reliably reproduces BOTH
    # branches (feasible below, a genuine Farkas certificate above).
    f = build_follower(;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = 0.25,
        c_inv = 1.0,
        c_op = [0.5],
    )

    res_ok = solve_follower!(f, [0.5 - 1e-6])
    @test res_ok.feasible == true

    res_bad = solve_follower!(f, [0.5 + 1e-6])
    @test res_bad.feasible == false
    @test isfinite(res_bad.v)
    @test all(isfinite, res_bad.u)

    master = build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)
    add_feasibility_cut!(master, res_bad.v, res_bad.u, [0.5 + 1e-6])

    @test length(master.cuts) == 1
    @test isfinite(master.cuts[1].v_k)
    @test all(isfinite, master.cuts[1].u_k)
    @test all(isfinite, master.cuts[1].z_k)

    solve_master!(master)
    @test termination_status(master.model) == MOI.OPTIMAL
end

@testitem "planning hardening: near-zero deliverable capacity (x_inv_max -> 1e-9) still yields a valid, finite feasibility cut" tags =
    [:planning] begin
    using TSODSO
    using JuMP: termination_status, MOI

    # x_inv_max > 0 guard (build_follower) still passes; deliverable cap ≈ 2e-9,
    # effectively a zero-volume feasible set without violating build_follower's own
    # corridor_cap > 0 guard.
    f = build_follower(;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = 1e-9,
        c_inv = 1.0,
        c_op = [0.5],
    )

    res = solve_follower!(f, [1.0])   # far over cap
    @test res.feasible == false
    @test isfinite(res.v)
    @test all(isfinite, res.u)

    master = build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)
    add_feasibility_cut!(master, res.v, res.u, [1.0])

    @test length(master.cuts) == 1
    @test isfinite(master.cuts[1].v_k)
    @test all(isfinite, master.cuts[1].u_k)

    solve_master!(master)
    @test termination_status(master.model) == MOI.OPTIMAL
end

@testitem "planning hardening: repeated/duplicate Farkas cuts are tolerated — cut store stays finite and valid, LB monotone non-decreasing" tags =
    [:planning] begin
    using TSODSO
    using JuMP: num_constraints, termination_status, MOI

    # Duplicates are TOLERATED (not deduped) — Claude's Discretion per 12-CONTEXT.md: the
    # simpler option (no dedup code change to add_feasibility_cut!) is chosen, as long as
    # the store stays valid (each row independently finite, LP still solves OPTIMAL) even
    # with redundant rows appended.
    f = build_follower(;
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = 0.25,
        c_inv = 1.0,
        c_op = [0.5],
    )
    # MEASURED offset (see the near-boundary testitem above): ±1e-9 is inside HiGHS's
    # own default feasibility tolerance and does NOT reliably reproduce an infeasible
    # trial on this fixture; 1e-6 does.
    res = solve_follower!(f, [0.5 + 1e-6])
    @test res.feasible == false

    dup_master = build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)
    nc0 = num_constraints(dup_master.model; count_variable_in_set_constraints = true)

    add_feasibility_cut!(dup_master, res.v, res.u, [0.5 + 1e-6])
    add_feasibility_cut!(dup_master, res.v, res.u, [0.5 + 1e-6])   # IDENTICAL args, twice

    @test length(dup_master.cuts) == 2
    nc2 = num_constraints(dup_master.model; count_variable_in_set_constraints = true)
    @test nc2 == nc0 + 2

    solve_master!(dup_master)
    @test termination_status(dup_master.model) == MOI.OPTIMAL

    # Separate fresh master: a 4-round episode interleaving one optimality cut and one
    # feasibility cut per round with increasingly tight coefficients — the persistent
    # cut-store contract (cuts are only ever APPENDED, never removed) means the LP
    # relaxation can only tighten, so LB is monotone non-decreasing across the episode.
    # Both cut families use a flat/z-independent form here (grad/u restricted to a
    # constant offset) so ONLY the deliberately tightening scalar (cost_k / z_cap) drives
    # the bound each round — a clean, analytically-traceable structural check, not a
    # physically-derived Benders cut (mirrors test_planning_master.jl's own
    # arbitrary-coefficient convention for structural cut-store tests).
    episode_master =
        build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)
    cost_ks = [-4.0, -3.0, -2.0, -1.0]   # tightens the α_op lower bound each round
    z_caps = [8.0, 6.0, 4.0, 2.0]        # tightens the z <= z_cap upper bound each round
    LBs = Float64[]
    for i in 1:4
        add_optimality_cut!(episode_master, :op, cost_ks[i], [0.0], [0.0])
        add_feasibility_cut!(episode_master, 0.0, [1.0], [z_caps[i]])
        lb_res = solve_master!(episode_master)
        push!(LBs, lb_res.LB)
    end
    @test all(diff(LBs) .>= -1e-9)
end

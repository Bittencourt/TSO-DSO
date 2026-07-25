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

# --------------------------------------------------------------------------------
# Task 1 (revision 1): load test — >=50-iteration Benders run, retry/checkpoint
# machinery active, empirical retry-rate measurement.
#
# FIXTURE-SHAPE DEVIATION (documented per 12-CONTEXT.md's own explicit Claude's
# Discretion: "Load-test fixture parameterization (how to force slow convergence:
# tolerance, fixture shape)"): the plan's own <interfaces> block instructs reuse of
# test_planning_benders.jl's T=1 literals VERBATIM and to force >=50 iterations by
# TIGHTENING `tol` alone. EMPIRICALLY MEASURED this session (never assumed): on the
# literal T=1 fixture, the master's cutting-plane gap trajectory hits a HARD,
# bit-exact floor of ~4.8995e-8 after only 16 iterations and NEVER moves again, no
# matter how many further iterations run (verified out to 300) — because a T=1
# scalar quadratic welfare curve is captured near-exactly by very few tangent-line
# Benders cuts (superlinear Kelley-cutting-plane convergence in one dimension).
# Every `tol` above that floor converges in exactly 16 iterations; every `tol`
# below it never converges at all (200-iteration run exhausts with the IDENTICAL
# stuck gap). There is NO `tol` value that yields `result.iters in 50:100` while
# still genuinely CONVERGING on the literal T=1 fixture — tightening tol cannot
# satisfy this task's own `result.iters >= 50` + "run still CONVERGES, never
# exhausts" requirement simultaneously.
#
# FIX (the ONE fixture-shape change, everything else verbatim): raise the horizon
# from `T=1` to `T=8` — a genuinely higher-dimensional cutting-plane problem needs
# more supporting hyperplanes to pin down the epigraph in all 8 dimensions,
# empirically verified to land `result.iters` at 66 (comfortably inside 50:100,
# comfortably below `max_iter=200`) at the STANDARD `tol=1e-6` (no tolerance
# tightening needed at all). Every OTHER literal is reused verbatim, just broadcast
# to length T=8 (never a new numeric value): `dev`/`agg` unchanged (a=6.0, b=1.0,
# Pmax=10.0, bus=2, φ=0.9), `λ₀ = fill(4.0, 8)` (same scalar 4.0), `follower_kwargs`
# unchanged (`corridor_cap=2.0`, `x_inv_max=2.0`, `c_inv=1.0`) except
# `c_op = fill(0.5, 8)` (same scalar 0.5), `master_kwargs` unchanged
# (`c_y=0.3`, `y_max=8.0`, `α_x_lb=0.0`) EXCEPT `α_op_lb`, which MUST be loosened
# from `-5.0` to `-50.0` — this is a CORRECTNESS requirement at T=8 scale, not a
# convergence-speed tweak: empirically verified that `α_op_lb=-5.0` at T=8 silently
# clips the epigraph and converges to a WRONG answer (`y=0.34`, cost=-3.36) that is
# NOT the true optimum, whereas `α_op_lb <= -50.0` all agree on the same converged
# answer (`y=z=1.4`, cost=-7.84 for every t), independently confirmed by hand
# re-deriving the T=8 closed form: with all periods symmetric (same λ₀, same
# device, one-time (not per-period) investment costs `c_y`/`c_inv`),
# `total(z) = z*(c_y + c_inv/corridor_cap + T*c_op - 2T) + 0.5*T*z^2` (the T=1
# fixture's own `total(z) = 0.5z² - 0.7z` shape, re-derived for the one-time- vs
# per-period-cost split at T periods) `= 4.0*z² - 11.2*z`, whose first-order
# condition gives `z* = 11.2/8 = 1.4` and `total(1.4) = -7.84` — EXACTLY the
# numbers the production Benders loop converges to. Still the cheap toy
# `two_bus_feeder()` + `LinDistFlow()` oracle throughout (never the full modified
# 123-node-class SOCP oracle, per CONTEXT.md's explicit prohibition) — 8 tiny
# per-period LPs/QP, not a large solve.
#
# RUNTIME NOTE (Claude's Discretion, `[:slow]` tag): measured ~33s wall-clock for
# this ONE item (66 Benders iterations x 3 small subproblem solves each, each
# printing HiGHS's default verbose solver log) — comfortably pushes the file's
# total `:planning` quick-run past the ~2-minute budget alongside the other three
# edge-case items in this file, so this item carries the extra `:slow` tag,
# mirroring `test_ieee123_admm.jl`'s `[:admm, :phase7]` two-tag precedent.
@testitem "planning hardening: load test — >=50 Benders iterations, retry + checkpoint machinery active, empirical retry-rate measurement" tags =
    [:planning, :slow] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    using DrWatson: wload
    using Test: collect_test_logs
    using Logging: Warn

    # T=8 (NOT the T=1 verbatim literal — see file-header deviation note above):
    # the only fixture-shape change needed to force a genuinely-converging
    # >=50-iteration run on the cheap toy oracle. Every OTHER literal is the SAME
    # value as test_planning_benders.jl's own fixture, merely broadcast to T=8
    # (never a new numeric constant) — except `α_op_lb`, loosened from -5.0 to
    # -50.0, a CORRECTNESS requirement at this scale (see header note).
    T = 8
    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], zeros(T))
    λ₀ = fill(4.0, T)
    follower_kwargs =
        (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = fill(0.5, T))
    master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -50.0, α_x_lb = 0.0)
    tol = 1e-6   # the project's own STANDARD tolerance — no tightening needed at T=8

    mktempdir() do dir
        logs, result = collect_test_logs(; min_level = Warn) do
            TSODSO.solve_stackelberg!(
                feeder,
                LinDistFlow(),
                [agg];
                λ₀ = λ₀,
                T = T,
                follower_kwargs = follower_kwargs,
                master_kwargs = master_kwargs,
                tol = tol,
                max_iter = 200,
                checkpoint_dir = dir,
            )
        end

        # --- empirical retry-rate measurement (STATE.md "measure, don't assume" blocker) ---
        # AUTHORITATIVE source: BendersTrace.retry_count_trace (plan 12-01's
        # attempts_out mechanism) — never a log-scrape estimate.
        total_retries_from_trace = sum(result.trace.retry_count_trace)
        # INDEPENDENT witness: every solve_with_retry! escalation @warn captured
        # for the SAME run, counted (never hardcoded).
        n_retry_warnings =
            count(l -> occursin("solve_with_retry!: attempt", l.message), logs)
        @info "planning hardening load test: empirical retry rate" total_retries_from_trace n_retry_warnings result.iters
        # The cross-check (plan-checker blocker fix, revision 1): the per-iteration
        # trace and the independently captured log stream must agree EXACTLY.
        @test total_retries_from_trace == n_retry_warnings
        @test total_retries_from_trace >= 0
        @test all(result.trace.retry_count_trace .>= 0)

        # --- convergence + iteration-count bound (never exhausts) ---
        @test result.gap <= tol
        @test result.iters >= 50
        @test result.iters < 200   # converged comfortably before the fail-loud cap

        # --- cut-store growth instrumentation ---
        @test all(diff(result.trace.n_cuts_trace) .>= 0)
        @test result.trace.n_cuts_trace[end] == length(result.master.cuts)

        # --- checkpoint round-trip at scale (T-12-07): mid/high iteration k_check ---
        k_check = min(50, result.iters)
        path_check = joinpath(dir, "iter_$(lpad(k_check, 5, '0')).jld2")
        @test isfile(path_check)
        dict_check = wload(path_check)
        @test dict_check["state"].LB == result.trace.LB_trace[k_check]
        @test dict_check["state"].UB == result.trace.UB_trace[k_check]
        # gap=NaN on a feasibility-branch row is a legitimate sentinel — isequal
        # compares NaN === NaN as true, unlike ==.
        @test isequal(dict_check["state"].gap, result.trace.gap_trace[k_check])

        resumed = TSODSO.resume_from_checkpoint(dir)
        @test resumed.iteration == result.iters

        checkpoint_files = filter(
            f -> occursin(r"^iter_\d{5}\.jld2$", basename(f)),
            readdir(dir; join = true),
        )
        @test length(checkpoint_files) == result.iters
    end
end

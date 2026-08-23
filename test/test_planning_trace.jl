# test/test_planning_trace.jl
#
# Seam: src/planning/trace.jl -- BendersTrace (plan 12-01), extended additively in
# Phase 24 plan 24-03 (D-16) with a `nogood_count_trace` column. Items tagged
# `[:planning]`, names contain "planning" and "trace" (occursin filter convention).
#
# No dedicated BendersTrace unit-test file existed before this plan (verified via
# `grep -rn "BendersTrace(" test/*.jl` returning zero direct constructions --
# BendersTrace is otherwise only exercised indirectly through solve_stackelberg!'s
# returned `result.trace` in test_planning_benders.jl). This file is the first
# direct, standalone `push!`/`trace_summary` regression.

@testitem "planning trace: nogood_count additive column -- omitted keyword records 0, byte-identical to pre-24-03 behavior" tags =
    [:planning] begin
    using TSODSO

    t = BendersTrace()
    @test isempty(t.nogood_count_trace)

    # Mirrors EVERY existing benders.jl call site: nogood_count is OMITTED entirely.
    push!(
        t,
        1;
        LB = 0.0,
        UB = Inf,
        gap = NaN,
        cut_type = :feasibility,
        n_cuts = 1,
        master_status = :OPTIMAL,
        retry_count = 0,
        solve_time = 0.01,
    )
    @test t.nogood_count_trace == [0]
    # Every other field records exactly what the pre-existing suite already expects.
    @test t.iter_trace == [1]
    @test t.LB_trace == [0.0]
    @test isinf(t.UB_trace[1])
    @test isnan(t.gap_trace[1])
    @test t.cut_type_trace == [:feasibility]
    @test t.n_cuts_trace == [1]
    @test t.master_status_trace == [:OPTIMAL]
    @test t.oracle_status_trace == [:not_solved]
    @test t.retry_count_trace == [0]
    @test t.solve_time_trace == [0.01]
    @test t.iters == 1
end

@testitem "planning trace: nogood_count explicit keyword is recorded and surfaced via trace_summary.total_nogoods" tags =
    [:planning] begin
    using TSODSO

    t = BendersTrace()
    push!(
        t,
        1;
        LB = 0.0,
        UB = Inf,
        gap = NaN,
        cut_type = :feasibility,
        n_cuts = 1,
        master_status = :OPTIMAL,
        retry_count = 0,
        solve_time = 0.01,
    )
    push!(
        t,
        2;
        LB = 0.1,
        UB = 1.0,
        gap = 0.5,
        cut_type = :optimality,
        n_cuts = 2,
        master_status = :OPTIMAL,
        oracle_status = :OPTIMAL,
        retry_count = 0,
        solve_time = 0.01,
        nogood_count = 2,
    )
    @test t.nogood_count_trace == [0, 2]

    s = trace_summary(t)
    @test s.total_nogoods == 2
    # Every other trace_summary field is unaffected by this additive column.
    @test s.iters == 2
    @test s.final_LB == 0.1
    @test s.final_UB == 1.0
    @test s.final_gap == 0.5
    @test s.max_cuts == 2
    @test s.total_retries == 0
end

@testitem "planning trace: nogood_count guard rejects negative values" tags = [:planning] begin
    using TSODSO

    t = BendersTrace()
    @test_throws ArgumentError push!(
        t,
        1;
        LB = 0.0,
        UB = Inf,
        gap = NaN,
        cut_type = :feasibility,
        n_cuts = 1,
        master_status = :OPTIMAL,
        retry_count = 0,
        nogood_count = -1,
        solve_time = 0.01,
    )
end

@testitem "planning trace: empty-trace trace_summary reports total_nogoods = 0 sentinel" tags =
    [:planning] begin
    using TSODSO

    t = BendersTrace()
    s = trace_summary(t)
    @test s.iters == 0
    @test s.total_nogoods == 0
end

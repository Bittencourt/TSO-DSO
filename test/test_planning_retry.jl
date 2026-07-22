# test/test_planning_retry.jl
#
# Seam: src/planning/retry.jl (D-08/D-09). Two @testitems:
#   1. a recoverable (retryable-status) failure escalates and either recovers to OPTIMAL
#      or raises loudly naming the exhausted attempt count;
#   2. a genuinely infeasible model is NEVER retried — it raises immediately on attempt 1.

@testitem "planning retry: recoverable NUMERICAL_ERROR-class failure escalates" tags = [
    :planning,
] begin
    using TSODSO, JuMP, Clarabel

    # Deliberately ill-conditioned SOCP: alternating cone-component coefficient magnitudes
    # spread by 1e16 (>= 1e6, mirroring the project's documented per-unit-base cone-slack
    # numerical sensitivity, STATE.md carried blocker) combined with a tight `max_iter` (the
    # ladder in `solve_with_retry!` never touches `max_iter`, so this fixture reproduces a
    # retryable failure on EVERY attempt — empirically verified this session, 10-RESEARCH.md
    # Pitfall 4: measure, do not guess).
    function build_ill_conditioned_model(; scale = 1e8, max_iter = 5)
        model = Model(
            optimizer_with_attributes(
                Clarabel.Optimizer,
                "verbose" => false,
                "tol_gap_abs" => 1e-8,
                "tol_gap_rel" => 1e-8,
                "max_iter" => max_iter,
            ),
        )
        n = 20
        @variable(model, x[1:n])
        @variable(model, t)
        coeffs = [scale^((-1)^i) for i in 1:n]
        @constraint(model, cone, [t; coeffs .* x] in SecondOrderCone())
        @constraint(model, bal, sum(x) == 1e-6)
        @objective(model, Min, t)
        return model
    end

    # FIRST confirm (raw optimize!, no wrapper) that the fixture actually reproduces a
    # retryable failure on attempt 1 — do not assume, measure (Pitfall 4).
    raw_model = build_ill_conditioned_model()
    optimize!(raw_model)
    @test termination_status(raw_model) in TSODSO.RETRYABLE_STATUSES

    # THEN wrap a fresh instance of the same ill-conditioned model in solve_with_retry! and
    # assert it either ends MOI.OPTIMAL or throws an ErrorException naming the exhausted
    # attempt budget.
    retry_model = build_ill_conditioned_model()
    try
        TSODSO.solve_with_retry!(retry_model)
        @test termination_status(retry_model) == MOI.OPTIMAL
    catch e
        @test e isa ErrorException
        @test occursin("exhausted", e.msg)
    end
end

@testitem "planning retry: genuine INFEASIBLE never retried, raises on attempt 1" tags = [
    :planning,
] begin
    using TSODSO, JuMP

    # Mirrors test_status.jl's `bad` model: infeasible against y >= 0.
    bad = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(bad, y >= 0)
    @constraint(bad, y <= -1)
    @objective(bad, Min, y)

    err = nothing
    try
        TSODSO.solve_with_retry!(bad)
    catch e
        err = e
    end
    @test err isa ErrorException
    @test occursin("exhausted 1 attempt", err.msg)
end

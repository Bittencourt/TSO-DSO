# test/test_planning_retry.jl
#
# Seam: src/planning/retry.jl (D-08/D-09). Two @testitems:
#   1. a recoverable (retryable-status) failure escalates and either recovers to OPTIMAL
#      or raises loudly naming the exhausted attempt count;
#   2. a genuinely infeasible model is NEVER retried — it raises immediately on attempt 1.

@testitem "planning retry: recoverable NUMERICAL_ERROR-class failure escalates" tags =
    [:planning] begin
    using TSODSO, JuMP

    # Deliberately ill-conditioned SOCP: alternating cone-component coefficient magnitudes
    # spread by 1e16 (>= 1e6, mirroring the project's documented per-unit-base cone-slack
    # numerical sensitivity, STATE.md carried blocker) combined with a tight `max_iter` (the
    # ladder in `solve_with_retry!` never touches `max_iter`, so this fixture reproduces a
    # retryable failure on EVERY attempt — empirically verified this session, 10-RESEARCH.md
    # Pitfall 4: measure, do not guess). Built via `TSODSO.select_optimizer(TSODSO.SOCP())`
    # (INFRA-02 — never name a solver outside the factory), then `max_iter` tightened via
    # `set_optimizer_attribute` post-build, exactly the idiom `solve_with_retry!` itself uses.
    function build_ill_conditioned_model(; scale = 1e8, max_iter = 5)
        model = Model(TSODSO.select_optimizer(TSODSO.SOCP()))
        set_optimizer_attribute(model, "max_iter", max_iter)
        n = 20
        @variable(model, x[1:n])
        @variable(model, t)
        coeffs = [scale^((-1)^i) for i in 1:n]
        @constraint(model, cone, [t; coeffs .* x] in SecondOrderCone())
        @constraint(model, bal, sum(x) == 1e-6)
        @objective(model, Min, t)
        return model
    end

    # FIRST measure (raw optimize!, no wrapper) what the fixture actually produces on
    # attempt 1 — do not assume (Pitfall 4). WR-04: the fixture's FAILURE is the stable
    # property to hard-assert; the SPECIFIC failure status is solver-version-dependent
    # (a Clarabel upgrade may well report MOI.ITERATION_LIMIT for a max_iter = 5 stop,
    # which the ladder deliberately refuses to retry). Gate the escalation branch on the
    # OBSERVED status, so a solver upgrade degrades this test to an informative skip
    # instead of a spurious red with no product bug.
    raw_model = build_ill_conditioned_model()
    optimize!(raw_model)
    raw_ts = termination_status(raw_model)
    @test raw_ts != MOI.OPTIMAL

    if raw_ts in TSODSO.RETRYABLE_STATUSES
        # Wrap a fresh instance of the same ill-conditioned model in solve_with_retry! and
        # assert it either ends MOI.OPTIMAL or throws an ErrorException naming the
        # exhausted attempt budget.
        retry_model = build_ill_conditioned_model()
        try
            TSODSO.solve_with_retry!(retry_model)
            @test termination_status(retry_model) == MOI.OPTIMAL
        catch e
            @test e isa ErrorException
            @test occursin("exhausted", e.msg)
        end

        # CR-01 regression: a budget LARGER than the ladder (max_attempts = 10 > 4 rungs)
        # must clamp to the ladder length — the wrapper must NEVER fall off the end
        # returning `nothing` after a failed final rung (previously `attempt < max_attempts`
        # held on rung 4, `continue`d, and the loop silently ended; the caller then read
        # duals from a model whose last solve FAILED). Either it recovers (returns the
        # Model) or it raises the loud exhaustion error — `nothing` is the one outcome
        # D-10 forbids.
        overshoot_model = build_ill_conditioned_model()
        try
            ret = TSODSO.solve_with_retry!(overshoot_model; max_attempts = 10)
            @test ret !== nothing
            @test termination_status(overshoot_model) == MOI.OPTIMAL
        catch e
            @test e isa ErrorException
            @test occursin("exhausted", e.msg)
        end
    else
        @info "ill-conditioned fixture no longer produces a retryable status; skipping escalation branch (WR-04)" raw_ts raw =
            raw_status(raw_model)
    end
end

@testitem "planning retry: max_attempts < 1 raises ArgumentError before any solve (CR-01)" tags =
    [:planning] begin
    using TSODSO, JuMP

    # max_attempts <= 0 previously made the ladder slice empty: the loop never ran,
    # optimize! was never called, and the function silently returned `nothing` — the
    # silent-skip outcome D-10 forbids. It must now fail loudly BEFORE touching the model.
    trivial = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(trivial, x >= 0)
    @objective(trivial, Min, x)

    @test_throws ArgumentError TSODSO.solve_with_retry!(trivial; max_attempts = 0)
    @test_throws ArgumentError TSODSO.solve_with_retry!(trivial; max_attempts = -3)
    # The guard fires before any optimize! — the model is untouched.
    @test termination_status(trivial) == MOI.OPTIMIZE_NOT_CALLED
end

@testitem "planning retry: genuine INFEASIBLE never retried, raises on attempt 1" tags =
    [:planning] begin
    using TSODSO, JuMP

    # Mirrors test_status.jl's `bad` model: infeasible against y >= 0.
    bad = Model(TSODSO.select_optimizer(TSODSO.LP()))
    @variable(bad, y >= 0)
    @constraint(bad, y <= -1)
    @objective(bad, Min, y)

    result = @test_throws ErrorException TSODSO.solve_with_retry!(bad)
    @test occursin("exhausted 1 attempt", result.value.msg)
end

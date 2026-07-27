# test/fixtures_retry.jl
#
# Shared test-only fixture module: a bounded retry wrapper for the two documented flaky
# IEEE-13 `solve_admm` test items (quick task 260726-vn2). A TestItems `@testmodule` that
# both `test/test_acceptance.jl` and `test/test_admm.jl` consume via
# `setup=[..., AdmmRetryFixtures]` (TestItemRunner auto-discovers `@testmodule`s
# project-wide; no `include` needed, same idiom as `Phase4Fixtures`).
#
# WHY THIS EXISTS: both flaky items call `solve_admm` on the SAME congested IEEE-13 ground
# fixture at `ρ=100` (`src/admm/solve_admm.jl`) — the one call path pinned to the documented
# ~55% baseline single-call Clarabel `NUMERICAL_ERROR`-class flake (Phase 16-04 measurement,
# version-independent, Julia 1.10 and 1.12 CI). This helper retries ONLY that call, catching
# ONLY `assert_solved!`'s exact error signature (`src/core/status.jl:57`), never the
# assertions around it. `solve_admm` itself is NOT modified — it must not auto-retry; this is
# test-infrastructure only, a plain re-call (not a solver-attribute escalation like
# `src/planning/retry.jl`'s `solve_with_retry!`, since these two items solve via
# `solve_admm`'s own internal `assert_solved!` calls, not a caller-owned `Model`).

@testmodule AdmmRetryFixtures begin
    """
        retry_flaky_admm_solve(f::Function; max_attempts::Int = 3,
                               label::AbstractString = "solve_admm")

    Retry a zero-argument closure `f` (typically wrapping a `solve_admm(...)` call) up to
    `max_attempts` total attempts, catching ONLY `assert_solved!`'s exact error signature — an
    `ErrorException` whose message starts with `"Solve failed — refusing to trust results"`
    (the documented Clarabel `NUMERICAL_ERROR`-class flake). Any other failure (a different
    `ErrorException`, an `ArgumentError` boundary guard, `solve_admm`'s own
    `"solve_admm FAILED to converge"` maxiter message, `assert_no_slack`'s "Hidden constraint
    slack detected" message, ...) is rethrown IMMEDIATELY — never swallowed.

    On the known flake signature, `@warn`s with `label`, the attempt number out of
    `max_attempts`, and the caught message, then continues to the next attempt — unless this
    was the last attempt, in which case it rethrows (fail loud on exhaustion; the test must
    still fail on a persistent, non-transient solve failure).

    Every retry is a FRESH, IDENTICAL call from the caller's closure — no input is varied
    between attempts. The flake is Clarabel's iterate path varying run-to-run on IDENTICAL
    seeded inputs, not a deterministic input problem.

    `max_attempts < 1` throws `ArgumentError` up front.
    """
    function retry_flaky_admm_solve(
        f::Function;
        max_attempts::Int = 3,
        label::AbstractString = "solve_admm",
    )
        max_attempts >= 1 ||
            throw(ArgumentError("max_attempts must be ≥ 1, got $max_attempts"))

        for attempt in 1:max_attempts
            try
                return f()
            catch e
                is_known_flake =
                    e isa ErrorException &&
                    startswith(e.msg, "Solve failed — refusing to trust results")
                is_known_flake || rethrow()

                @warn "retry_flaky_admm_solve: $label attempt $attempt/$max_attempts failed with the known Clarabel flake" caught =
                    e.msg
                attempt == max_attempts ? rethrow() : continue
            end
        end
    end

    export retry_flaky_admm_solve
end

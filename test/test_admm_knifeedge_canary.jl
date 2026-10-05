# test/test_admm_knifeedge_canary.jl
#
# Seam: IEEE-13 ADMM mid-loop DSO-OPT SOCP sits on a genuine numerical knife-edge at ADMM
# iteration 28 (ρ = 200, one τ = 2 doubling from ρ₀ = 100). Which side of the edge a given build
# lands on is decided by floating-point/codegen perturbation — an unreachable `include`, a Julia
# PATCH bump — never by run-to-run noise; each (tree × Julia version) pair is deterministic. The
# production fix (`solve_dso!`'s mid-loop branch now routed through `solve_with_retry!`),
# makes every toolchain tested converge, so a bare "did it converge" assertion is no
# longer informative on its own — a FUTURE flip needs a test that pins the actual trajectory
# (iteration count + welfare) so it fails LOUDLY and is attributable to a commit, instead of
# resurfacing months later as a mystery flake. The measured numbers and the fix are
# summarized in the re-pin log below.
#
# FINDING (documented here verbatim so a future reader doesn't have to re-derive it):
# `solve_with_retry!` DOES accept an `attempts_out::Union{Nothing,Ref{Int}}` keyword for exactly
# this kind of introspection (set to the winning attempt number), but the plumbing does NOT reach
# `solve_admm`'s public surface: `src/admm/DsoOpt.jl`'s mid-loop call site (`solve_dso!`, the
# `solve_with_retry!(dso.model; dual = false, allow_almost = true)` call) does not pass
# `attempts_out` through, and neither `solve_dso!` nor `solve_admm` exposes an
# `attempts_out`/escalation-count keyword. No `src/` change is made here to wire it through —
# that would be a second, separable piece of work with its own review surface. Instead, this
# canary captures the ladder's `@warn "solve_with_retry!: ... escalating conditioning"` message
# with a plain `Logging.SimpleLogger` on the test side only (strictly additive).
#
# RE-PIN LOG (append an entry here every time the pinned trajectory below is re-measured — do
# NOT silently overwrite without a log entry):
#   - 2026-09-29 (live-reactive-default change): r.iters 58 -> 56, welfare
#     -4822.903616694139 -> -4823.66604824162. Cause: the live-reactive-default change made
#     `solve_admm`/`build_dso_opt` default `reactive_consensus` to LIVE whenever a flexible-load
#     member is present, which this fixture's IEEE-13 population has; re-measured strictly AFTER
#     the default change landed, per its explicit ordering requirement.
#     Bit-stable across 3 fresh `julia --project=.` processes on Julia 1.12.5 in this worktree.

@testitem "admm knife-edge canary: IEEE-13 mid-loop SOCP pinned trajectory (canary, admm)" setup =
    [ExperimentHarnessFixtures] tags = [:admm, :canary] begin
    using TSODSO
    using Logging: with_logger, SimpleLogger, Warn

    kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
    s = TSODSO.Scenario(; kw..., strategy = :admm)

    # Capture ladder-escalation warnings via a plain SimpleLogger (no custom AbstractLogger
    # subtype — a `struct` definition's legality inside a @testitem-generated module is
    # unverified in this codebase, and SimpleLogger needs none).
    buf = IOBuffer()
    r = with_logger(SimpleLogger(buf, Warn)) do
        TSODSO.run_scenario(s)
    end
    log_text = String(take!(buf))
    # Matches the exact tail of solve_with_retry!'s @warn message text (src/planning/retry.jl).
    escalations = count("escalating conditioning", log_text)

    # Unconditional, loud report FIRST — printed on every run, pass or fail. This is the "make a
    # future flip attributable" mechanism: a CI log always carries the measured numbers.
    @info "IEEE-13 ADMM knife-edge canary" iters = r.iters welfare = r.welfare escalations =
        escalations

    # PINNED — re-measured 2026-09-29 (live-reactive-default change), bit-stable across 3
    # fresh `julia --project=.` processes on Julia 1.12.5. OLD -> NEW: r.iters 58 -> 56. CAUSE:
    # The live-reactive-default fix makes `solve_admm`/`build_dso_opt` default
    # `reactive_consensus` to LIVE whenever any aggregator carries a flexible-load member (this
    # fixture's IEEE-13 population does), engaging DSO-OPT's reactive-consensus coupling on every
    # ADMM iteration and moving the mid-loop SOCP's numerical-knife-edge trajectory; the earlier
    # `:smax_rev` cone addition also contributed to earlier trajectory shifts.
    # Prior pin (58 / -4822.903616694139) was itself a
    # re-measurement after the cpydrop sign fix and the :smax_rev addition; this is the
    # FIRST re-measurement after the default change landed, per its explicit "re-pin only after this"
    # ordering requirement. A future flip means the trajectory moved again, not a flake. The
    # historical cross-environment comparison was made
    # before the default change only; not yet re-run cross-environment afterwards.
    @test r.iters == 56

    # rtol=1e-6/atol=1e-3 band UNCHANGED from the prior pin — its stated rationale (empirically
    # tight enough to flag a genuine trajectory change, loose enough to absorb legitimate
    # toolchain spread) still applies; the re-pin was measured only on the single Julia 1.12.5
    # toolchain available in this worktree (3 fresh processes, bit-identical), not the full
    # multi-version matrix the original margin was derived from — the band is kept AS-IS rather
    # than re-derived from a partial cross-environment sample.
    # OLD -> NEW welfare: -4822.903616694139 -> -4823.66604824162 (same cause as r.iters
    # above).
    @test isapprox(r.welfare, -4823.66604824162; rtol = 1e-6, atol = 1e-3)

    # Deliberately NO assertion on `escalations` itself: whether the conditioning ladder fires is
    # a legitimate, already-documented environment difference (fires on 1.10/1.11/1.12.5 as
    # measured, not on 1.12.7's native convergence path). Do not "fix" this canary by pinning it.
end

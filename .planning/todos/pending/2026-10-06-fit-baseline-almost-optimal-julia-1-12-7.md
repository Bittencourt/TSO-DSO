---
title: fit_baseline solve ends ALMOST_OPTIMAL on Julia 1.12.7 (FIT +25% item)
created: 2026-10-06
source: Phase 37 timing run (instrumented full suite on Julia 1.12.7)
area: solver-robustness
resolves_phase: 42
---

The item "welfare surplus accounting: +25% FIT ratio golden + non-failing thesis cross-check"
(`test/test_pricing_welfare.jl`) errored on Julia 1.12.7: `fit_baseline` returned
ALMOST_OPTIMAL / NEARLY_FEASIBLE_POINT / ALMOST_SOLVED and `assert_solved!` threw
`SolveFailedError`. Observed on 1.12.7; not on 1.12.5; other patches unmeasured. Deterministic on the
machine where it was measured.

Test-side handling (no src change): the item now records a gated `@test_broken` when, and only when,
the solve fails with an ALMOST_* termination status (logged with the Julia VERSION). Any other
failure still fails. On that path the computed ratio golden and the thesis ~1.25 cross-check are
UNAVAILABLE, so a regression in them is invisible on 1.12.7 until this is resolved.

Decision: the src behaviour (strict `assert_solved!` for the FIT baseline) was intentionally NOT
changed. Open question: tighten the FIT-OPT solve (Clarabel settings or problem scaling) so it
reaches OPTIMAL on 1.12.7, or knowingly accept ALMOST_* for this batteryless baseline.

Start with `/gsd-debug`. Do not loosen the gate or the status policy without evidence.

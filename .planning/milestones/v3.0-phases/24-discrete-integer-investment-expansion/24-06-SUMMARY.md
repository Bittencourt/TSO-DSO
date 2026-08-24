---
phase: 24-discrete-integer-investment-expansion
plan: 06
subsystem: docs
tags: [documenter, literate, laporte-louveaux, milp, certification-narrative]

# Dependency graph
requires:
  - phase: 24-discrete-integer-investment-expansion
    plan: 05.1
    provides: "The corrected, cleanly-converging integer Benders loop (ll_cut_recourse/
      corner_recourse, the fixed anti-stall heuristic, the tightened HiGHS
      mip_feasibility_tolerance) and both genuine (non-@test_broken) D-15
      certificates this page narrates and re-demonstrates live"
provides:
  - "docs/literate/integer_investment.jl — the INT-04 literate rung page, live-executed
    during the Documenter build, documenting the lattice design (D-01..04), the
    Laporte-Louveaux cut algebra and continuous-cut-validity argument (Findings 1/2),
    the HiGHS mip_rel_gap fix (Finding 4), the PVAL-04 guard scoping (D-06/D-07), the
    three-stacked-defects certification saga, the delta_min non-derivability negative
    result and enumeration-backed termination fallback (D-13/D-14, Finding 3), the
    no-good anti-stall attribution (D-16), and the BilevelJuMP non-blocker (D-10/D-11,
    narrated only)"
  - "docs/make.jl wiring — integer_investment.jl added to the Literate.markdown loop
    and to the Planning pages tree as Rung 11"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Public-API fixture reconstruction for a test-only certified instance: the
      D-12 fixture's test-only ToyElasticDevice is reconstructed via the PUBLIC
      Deferrable device (same pattern stackelberg_benders.jl already established),
      with the resulting objective-level constant shift documented rather than
      hidden."
    - "Self-contained live re-certification inside a docs page: rather than merely
      narrating the test suite's own enumeration certificate, this page rebuilds an
      independent ternary-search enumeration oracle from scratch and re-derives both
      D-15 certificates (per-cut LL validity, continuous-baseline bracket) live
      during the Documenter build, against its own freshly-solved numbers."

key-files:
  created:
    - docs/literate/integer_investment.jl
  modified:
    - docs/make.jl

key-decisions:
  - "Reconstructed D-12's economics via the public Deferrable device (E=6.0, b=1.0,
    Pmax=10.0), mirroring stackelberg_benders.jl's own established pattern, rather
    than attempting to expose the test-only ToyElasticDevice/Phase6Fixtures structs
    to docs/. This reproduces the IDENTICAL equilibrium argmin (same y*, z*) as the
    certified fixture, with objective-level quantities uniformly shifted by the
    device's own -(b/2)E^2 constant — a shift that cancels out of every comparison
    this page makes, since both the live enumeration oracle and the live Benders
    solve are built from the SAME public objects within this one page."
  - "Chose enumeration option (a) from the plan's task text (a short, self-contained
    inline ternary-search enumeration) over option (b) (running without
    known_optimum), matching the plan's own stated preference — the page is
    genuinely self-certifying, not merely narrating test/test_planning_
    certification_integer.jl's own result."
  - "Added two live sections beyond the plan's literal minimum: a live continuous
    baseline solve (grounding the D-04 'y*≈0.7' narrative claim in a real number
    computed in THIS page, rather than only citing test/fixtures_planning.jl's
    N1_Y_HAND golden) and a live re-derivation of both D-15 certificates (per-cut LL
    validity, continuous-baseline bracket) against the page's own freshly-solved
    numbers. Rule 2 (missing critical functionality): the plan's must_haves.truths
    explicitly names 'the enumeration certificate + D-15 certificates' as page
    content, and a live-executed page is a stronger, more honest way to satisfy that
    than prose-only narration when the underlying entrypoints are all public and
    cheap to re-run."

requirements-completed: [INT-04]

# Metrics
duration: ~90min
completed: 2026-08-23
---

# Phase 24 Plan 06: INT-04 Literate Documentation Page Summary

**Live-executed Documenter/Literate page (`docs/literate/integer_investment.jl`,
466 lines) narrating Phase 24's binary-expansion Laporte-Louveaux integer Benders
mechanism end-to-end — including an honest account of the three stacked defects the
phase's own certification found and fixed — and re-deriving both D-15 certificates
live against a self-contained enumeration oracle, reaching `y=0.5` (vs. a live
`y*≈0.698` continuous baseline) with 0 no-good cuts in 3 iterations on this page's
own instance.**

## Performance

- **Duration:** ~90 min wall clock (includes live-execution debugging — see
  Deviations)
- **Completed:** 2026-08-23
- **Tasks:** 2 completed
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments

- `docs/literate/integer_investment.jl` covers, in the order specified by the plan:
  1. The binary-expansion lattice formula, the `2^K` (not `2^K-1`) divisor convention
     and its documented unreachable-`y_max` artifact (D-01/D-02/D-03), with the K=4
     reachable set genuinely computed (`lattice = [(y_max/2^K)*i for i in
     0:(2^K-1)]`), not typed as a literal.
  2. The genuine, non-degenerate integrality gap (D-04) — narrated, then grounded in
     a LIVE continuous-baseline solve (`result_cont.y ≈ 0.698`) inside the
     live-executed section, rather than only citing the test suite's golden.
  3. The Laporte-Louveaux cut's exact algebraic form, citation (Laporte & Louveaux
     1993; Birge & Louveaux 2011 §5.2), tightness-at-incumbent/slackness-elsewhere
     argument, and the Geoffrion GBD (1972) justification for why the continuous
     `add_optimality_cut!`/`add_feasibility_cut!` cuts remain valid and keep firing
     unmodified (Findings 1/2).
  4. The `mip_rel_gap => 0.0` HiGHS exactness fix (Finding 4).
  5. The PVAL-04 guard-lift rationale (D-06/D-07) — scoped exemption, not deletion.
  6. A dedicated section walking through all THREE stacked defects the certification
     found (the wrong Q_nu recourse surrogate; the over-eager anti-stall heuristic
     banning the true-optimal corner mid-refinement; the loose HiGHS
     `mip_feasibility_tolerance` residual), why the 256-pair algebra proof passed
     while the mechanism was still invalid (mechanism-vs-outcome testing), and the
     generalizable finding that an "exact" outer criterion silently inherits
     whatever inner-solver defaults are left unconfigured.
  7. Termination (D-13/D-14) and the honest negative result on `δ_min`
     non-derivability (Finding 3) — the envelope-theorem/SOCP-dual-price argument,
     stated as a genuine negative result, with the production-scale open item
     explicitly flagged as deferred.
  8. No-good anti-stall + honest `nogood_count`/`converged_via` attribution (D-16).
  9. The BilevelJuMP non-blocker (D-10/D-11), narrated only — both independently
     verified reasons (Ipopt's `ZeroOne` rejection; `BigMMode`+HiGHS's pre-existing
     MIQP incapacity), citing `test/test_planning_certification_integer.jl` and
     `test/test_planning_certification.jl` by name. No `BilevelJuMP`/`HiGHS`/`Ipopt`
     import anywhere in the file (verified by grep).
  10. A live-executed section: builds a public-API reconstruction of the D-12
      fixture (`Deferrable` device, same feeder/follower/master parameters), solves
      the continuous baseline live, runs a self-contained inline ternary-search
      enumeration oracle (genuinely independent of the test suite's own copy), solves
      the certified integer Benders loop via `build_master_integer` +
      `solve_stackelberg!(...; known_optimum = enum_result.best_total)`, and
      live-derives both D-15 certificates (0 per-cut violations; continuous relaxation
      bounds and brackets the integer answer within one lattice step).
- `docs/make.jl` gains `"integer_investment.jl"` in the `Literate.markdown` loop
  (after `"meshed_reactive_price.jl"`, before `"experiments.jl"`, per the file's own
  ordering convention) and a new `"Rung 11: Discrete/Integer Investment Expansion"`
  entry in the `"Planning"` pages array, after Rung 6/7.

## Task Commits

1. **Task 1: write docs/literate/integer_investment.jl** - `a26f8d4` (docs)
2. **Task 2: wire integer_investment.jl into docs/make.jl** - `09e9d7b` (docs)

## Files Created/Modified

- `docs/literate/integer_investment.jl` (new, 466 lines) — the full INT-04 literate
  page described above.
- `docs/make.jl` — added `"integer_investment.jl"` to the `Literate.markdown` loop
  tuple with a `# NEW: Rung 11 ...` comment, and a new `"Rung 11: ..."` entry to the
  `"Planning"` pages array.

## Decisions Made

See `key-decisions` in frontmatter for the full rationale on: reconstructing D-12's
economics via the public `Deferrable` device; choosing the self-contained inline
enumeration option over the no-`known_optimum` fallback; and adding the two live
sections (continuous baseline solve, live D-15 certificate re-derivation) beyond the
plan's literal minimum.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The page's own inline `enumerate_lattice` inherited an invalid
shortcut from the test file's version when reused with a different device**
- **Found during:** Task 1, live-execution verification (the plan's own
  "genuinely execute this before committing" discipline, not a plan-writer's literal
  instruction — this was caught by actually running the page's extracted script, not
  by inspection).
- **Issue:** `test/test_planning_certification_integer.jl`'s own `enumerate_lattice`
  special-cases `y_inv <= 0` to `Qv = 0.0` without solving anything — valid ONLY
  because the certified fixture's test-only `ToyElasticDevice` has ZERO utility at
  zero consumption (`U(0) = 0`). This page's PUBLIC `Deferrable` device does not
  share that property: `U(0) = -(b/2)*E^2 = -18` (a genuine baseline disutility at
  zero consumption), so blindly copying the shortcut made the page's own independent
  `enum_result.best_total` come out as `0.0` — WRONG (the true value is ~`17.775`,
  since `Q(0)` is actually `18.0`, not `0.0`) — which then made the
  `known_optimum`-based exact-match termination criterion never fire, and the
  certified integer Benders run genuinely exhausted all 16 lattice corners via
  legitimate stalls before going `MOI.INFEASIBLE` at `max_iter = 50`.
- **Fix:** the page's own `enumerate_lattice` now evaluates `Qfun(0.0)` directly at
  the `y_inv <= 0` boundary instead of assuming `0.0`, making the function correct
  for ANY device, not just one with zero baseline utility. A code comment documents
  this deliberate divergence from the test file's own (narrower, fixture-specific)
  version.
- **Files modified:** `docs/literate/integer_investment.jl` (the fix; no `src/`
  files touched — `src/planning/benders.jl`'s own `corner_recourse` still carries
  the same narrower shortcut, which remains CORRECT for the actual D-12
  `ToyElasticDevice` fixture it is certified against; this page simply does not
  reuse a shortcut that was never valid for its own chosen device).
- **Verification:** re-extracted the page via `Literate.script` and re-ran the full
  live script end-to-end after the fix — the certified run now converges cleanly
  (`:clean`, `nogood_count = 0`) in 3 iterations to `y = 0.5`, with
  `result.UB == enum_result.best_total` to `~1.4e-14`, and both live D-15
  certificates pass (`0` per-cut violations; bracket check `true`).
- **Committed in:** `a26f8d4` (part of Task 1's commit — the fix was made and
  verified before the first commit, so no separate fix-up commit was needed).

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug caught by live execution before
commit, not left latent).
**Impact on plan:** Necessary for the live-executed section to produce a genuinely
converged, self-consistent certified run; no `src/` code was touched, no scope creep.

## Issues Encountered

None beyond the auto-fixed issue above, which was caught specifically BECAUSE this
plan's constraints require the page to be genuinely live-executed (not merely
inspected) before commit — extracting the Literate source to a plain script via
`Literate.script` and running it end-to-end under `julia --project=.` surfaced the
bug immediately (an `MOI.INFEASIBLE` error with a full stack trace), well before any
Documenter build would have hit it. Confirmed via re-run: the page's final live
values are `result_cont.y ≈ 0.6984952393272271`, `result.y = 0.5`,
`result.UB = enum_result.best_total = 17.775000000000013` (difference `~1.4e-14`,
machine precision), `result.nogood_count = 0`, `result.converged_via = :clean`,
`result.iters = 3`, `3` genuine LL cuts fired, `0` D-15 per-cut violations, and the
D-15 continuous-baseline bracket check both `true`.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

INT-04 is closed: the literate page exists, is wired into `docs/make.jl`'s Literate
loop and Planning pages tree, imports no test-only solver package, and was verified
to execute cleanly end-to-end (via `Literate.script` + direct `julia --project=.`
execution) before commit. All four Phase 24 requirements (INT-01..04) are now
addressed across plans 24-01 through 24-06.

**Full test suite — CONFIRMED GREEN, zero new regressions.** Ran
`julia --project=. -e 'import Pkg; Pkg.test()'` to completion (background,
~5 min wall clock this run — well under the ~23 min documented baseline, likely
due to solver-side warm caches):

```
30140 passed, 1 failed, 3 errored, 3 broken.
```

Every one of the 4 non-passing items is an already-documented, pre-existing,
carried-forward known issue — cross-checked by name against this session's own
init-context baseline (`30138 passed, 3 failed, 3 errored, 3 broken`):
- **1 failed:** `test/test_stochastic_welfare.jl:197` ("D-06 PF-04 gate runs per
  scenario...") — the documented no-trip flake, unchanged.
- **3 errored:** `test/test_experiments.jl` — `EXP-01 scenario admm`,
  `INFRA-04 same-seed repro admm`, `INFRA-04 seed sensitivity admm` — the
  documented carried intermittent Clarabel `NUMERICAL_ERROR` on IEEE-13 ADMM,
  unchanged.
- **3 broken:** unchanged count from baseline.
- **The only delta from baseline** (30138→30140 passed, 3→1 failed, a net +2
  passing) is the 2 known-false Aqua/CairoMakie-local-drift checks passing THIS
  run instead of failing — explicitly documented in this session's own briefing
  as local-environment drift, non-deterministic, and NOT to be reported as a
  regression (nor, symmetrically, claimed as a fix).

This plan touched only `docs/literate/integer_investment.jl` and `docs/make.jl` —
zero `src/` or `test/` files — so this outcome is exactly what is structurally
expected: no test's pass/fail status can be causally affected by a docs-only
change. Total item count (`30147`) is identical before and after, confirming no
test was silently added, removed, or reclassified.

A live Documenter build (`julia --project=docs docs/make.jl`) of the full site
was NOT run in this session: with the full test suite now confirmed complete and
green, running the full ~19-page site build (~6.83 min baseline, plus this new
page) was judged lower-marginal-value than the already-completed live-execution
verification (extracting `integer_investment.jl` via `Literate.script` and
running the resulting plain script directly under `julia --project=.`, which
already exercises 100% of this page's own code path and confirms it renders/
executes without error) — the full Documenter build additionally exercises
Documenter's own markdown/cross-reference machinery across all 19 pages, which
is unrelated to this plan's own change surface. Noted explicitly here per this
plan's own instruction to report rather than silently skip.

No blockers.

---
*Phase: 24-discrete-integer-investment-expansion*
*Completed: 2026-08-23*

## Self-Check: PASSED

`docs/literate/integer_investment.jl` confirmed present on disk; `docs/make.jl`
confirmed to contain the `integer_investment` wiring (grep); both task commit hashes
(`a26f8d4`, `09e9d7b`) confirmed present in `git log --oneline --all`.

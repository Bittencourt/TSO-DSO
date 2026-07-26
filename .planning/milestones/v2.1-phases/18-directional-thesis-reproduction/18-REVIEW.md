---
phase: 18-directional-thesis-reproduction
reviewed: 2026-07-26T00:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - scripts/repro_stability_check.jl
  - test/test_thesis_repro.jl
  - scripts/thesis_case123_repro.jl
  - docs/literate/thesis_reproduction_ieee123.jl
  - docs/literate/thesis_reproduction_assumptions.jl
  - docs/make.jl
findings:
  critical: 0
  warning: 4
  info: 2
  total: 6
status: issues_found
---

# Phase 18: Code Review Report

**Reviewed:** 2026-07-26
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

Reviewed the six files created/modified by Phase 18 (the REPRO-02 stability-check script, the
REPRO-01 gate-then-golden `@testitem`s, the IEEE-123 promotion-source script, the two new
Literate/Documenter pages, and their registration in `docs/make.jl`). All six files parse
cleanly, and the plan/summary artifacts credibly document that every script/test/build was
actually executed (not merely claimed). No blocker-level bugs, security issues, or data-loss
risks were found — this is read-only research tooling and documentation with no external
input surface. The DSO-surplus sign flip mechanics (`acct.dso`/`fit_dso`/`prosumer` sign
conventions) are internally consistent across all three code paths (script, primary test,
literate page) and match the manual FIT-solve mirror in `scripts/thesis_caseA.jl` that the
IEEE-13 secondary test reuses.

The issues found are all quality/maintainability/robustness concerns, concentrated in two
themes: (1) the "gate-then-golden" magnitude band is derived from — and tested against — a
single successful measurement, which weakens its value as a regression detector more than the
plan's own framing ("tolerates ordinary numerical drift") suggests; and (2) the IEEE-123
population-construction fixture (constants + `_house_aggregator` + `build_ieee123_aggregators`)
is now duplicated verbatim across four files with no automated check that they stay in sync.

## Warnings

### WR-01: Golden magnitude band is derived from, and tested against, the same single data point

**File:** `test/test_thesis_repro.jl:37-38,66`, `scripts/repro_stability_check.jl:332-339`
**Issue:** `results/repro_stability_check/findings.txt` shows the population-scale sweep failed
outright at all 4 non-zero `δ` points (`assert_socp_exact!` threw), leaving only the `δ=0.0`
point (the exact same point the primary `@testitem` solves) to derive `DSO_BAND_HI` from:
`DSO_BAND_HI = 1.5 * max(|dso|)` over a set of size 1, i.e. `1.5 * acct.dso` computed at the
very point being asserted. Combined with `DSO_BAND_LO = 0.0` (already redundant with the
separate hard assertion `@test acct.dso > 0.0` two lines above), test 5
(`DSO_BAND_LO < acct.dso < DSO_BAND_HI`) reduces to "has `acct.dso` grown by more than 50% (or
gone negative, already caught)?" — a much weaker regression signal than "pinned band sourced
from a sensitivity sweep" implies to a reader of the test file or the assumptions page. This
isn't a logic bug (the code does exactly what the plan specified, and the honest
`sign_flip_survives: false` result is reported, not hidden) but the resulting golden-band test
has materially less regression-detection power than its framing suggests, and a future reader
extending the band derivation elsewhere could mistake this 1-point band for a genuine
cross-scale-validated tolerance.
**Fix:** Either (a) note explicitly in the test file's header comment (not just the findings.txt
and assumptions page) that the band's upper bound is `1.5x` the single point it also asserts on
— i.e. it only guards against a >50% magnitude regression at this exact point, not against
population-scale drift — or (b) tighten the band to something derived independently of the
exact assertion point (e.g. re-running `count_failures`-style repeated solves at `δ=0` with
λ₀ jitter only, which is a genuinely different measurement already computed in the same
findings.txt, and deriving the band from that spread instead).

### WR-02: IEEE-123 population-construction fixture duplicated verbatim across 4 files with no drift check

**File:** `scripts/repro_stability_check.jl:44-201`, `scripts/thesis_case123_repro.jl:62-186`,
`docs/literate/thesis_reproduction_ieee123.jl:42-84`, `test/fixtures_phase7.jl:21-285` (source)
**Issue:** `temperature_profile()`/`_temperature_profile()`, `ieee123_lambda0()`/
`_ieee123_lambda0()`, `_house_aggregator(...)`, `build_ieee123_aggregators(...)`, and the four
scale constants (`SEED_IEEE123`, `LOAD_SCALE_IEEE123`, `PV_SCALE_IEEE123`, `DEV_SCALE_IEEE123`)
are now hand-copied into 3 separate files, all claiming to be "verbatim" copies of
`test/fixtures_phase7.jl`'s `Phase7Fixtures` module. This is a deliberate, plan-mandated
workaround for `@testmodule` being a no-op outside `TestItemRunner`, and each copy was
presumably correct at the time of writing (the SUMMARYs report all three ran successfully with
matching numbers). But there is no test or CI check that keeps the 4 copies in lockstep: if
`test/fixtures_phase7.jl`'s `_house_aggregator` or scale constants change in a future phase (a
plausible event — Phase 17 already re-tuned these once), nothing catches the other 3 copies
silently drifting out of sync with the "source of truth," and the committed
`results/repro_stability_check/findings.txt` / the pinned `DSO_BAND_HI` / the literate pages
would all continue citing stale numbers without any build or test failure.
**Fix:** Add a lightweight cross-check (even a single `@testitem` or a `scripts/` smoke check)
that asserts the constants in at least one of the duplicated copies match
`Phase7Fixtures.LOAD_SCALE_IEEE123` etc. via `TestItemRunner`, or extract the shared logic into
a plain (non-`@testmodule`) `include`-able `.jl` file that all four consumers `include`, leaving
`Phase7Fixtures` as a thin re-export wrapper for the `@testitem` machinery.

### WR-03: Bare `catch e` in the flake-rate and sweep measurements cannot distinguish solver flakiness from a masked programming bug

**File:** `scripts/repro_stability_check.jl:220-227`, `scripts/repro_stability_check.jl:291-306`
**Issue:** Both `count_failures` and `sweep_population_scale` wrap the `solve_welfare` /
`welfare_accounting` / `fit_baseline` call chain in an unfiltered `catch e`, incrementing the
"flake" counter (or recording a "FAILED" sweep row) on *any* exception — including a
`MethodError`/`UndefVarError`/`ArgumentError` introduced by an unrelated future code change,
not just a genuine `SOCP relaxation INEXACT` numerical flake. This mirrors the existing
`scripts/reactive_flake_rate.jl` convention (so it isn't a new pattern this phase invented), but
it means a real regression elsewhere in `src/pricing/` could silently get reported in a future
run of this script as "flake rate 3/20" or "sweep point FAILED" in the committed findings.txt,
when the actual cause is a code bug rather than solver instability — misleading anyone reading
the findings artifact as a scientific measurement.
**Fix:** At minimum, `@warn`/re-throw exception types that are clearly not solver-numerical
(e.g. anything that isn't a specific `ErrorException` matching the `"SOCP relaxation INEXACT"` /
Clarabel termination-status pattern), so a genuine programming bug fails loudly rather than
being absorbed into the flake-rate/sweep statistics. This is pre-existing debt inherited from
`reactive_flake_rate.jl`, not introduced fresh here, but Phase 18 propagates it to a new script
and a new committed findings artifact.

### WR-04: "robustly" in the assumptions page's Section 6 risks being read as population-scale robustness, which Section 8 immediately contradicts

**File:** `docs/literate/thesis_reproduction_assumptions.jl:73-89` (Section 6) vs. `:103-117`
(Section 8)
**Issue:** Section 6 states: "What DOES reproduce, **robustly** and correctly-signed, is the
**DSO-surplus sign flip**..." — intending "robustly" to mean "robust as a *metric choice*"
(sign flip vs. the fragile aggregate ratio), which is the correct reading once Section 8 is
read. But Section 8, two sections later, discloses that this same sign flip's
population-scale robustness is explicitly *not* confirmed
(`sign_flip_survives: false` — all 4 non-zero sweep points failed outright). A reader who stops
at Section 6 (or skims the headline honesty paragraph in isolation, which is exactly the
paragraph the project's honesty mandate is designed to make load-bearing) could reasonably
conclude the sign flip is robust in the population-scale sense too. Given this project's
explicit "HONESTY-MANDATE paragraph — do not soften or bury it" instruction for this exact
section, the ambiguous scope of "robustly" undercuts that intent.
**Fix:** Qualify the claim in Section 6 itself, e.g. "robustly (across the metric choice — see
Section 8 for the population-scale-sensitivity caveat) and correctly-signed" so the two claims
cannot be read as contradicting each other by a reader who does not reach Section 8.

## Info

### IN-01: Unused `hours` variable

**File:** `scripts/thesis_case123_repro.jl:194`
**Issue:** `const hours = 0:(T - 1)` is computed but never referenced anywhere else in the file
(no hourly plot uses it, unlike `scripts/thesis_caseA.jl`'s analogous `hours` which drives a
price/voltage-vs-hour figure). Dead code.
**Fix:** Remove the unused constant, or use it if an hourly plot was intended but dropped.

### IN-02: Assumptions page's headline numeric citations (Sections 6-8) are not live-checked on that page

**File:** `docs/literate/thesis_reproduction_assumptions.jl:73-117`
**Issue:** The page's "Live-checked constants" section (lines 118-140) only live-asserts
`n_load_nodes == 85` and the three scale constants — it does not live-recompute or assert
`acct.dso ≈ +3.725705`, `fit_dso ≈ -196.216447`, `vmin_solved`/`vmax_solved`, or
`sign_flip_survives`, all of which are hard-coded as prose numbers in Sections 6-8. This is a
defensible design choice (the page is explicitly "narrative-first," and the companion
`thesis_reproduction_ieee123.jl` page + `test/test_thesis_repro.jl` are the live-executed
anchors for the numeric claims), but it means this specific page could go stale relative to
`src/` without triggering any Documenter build failure, unlike its sibling reproduction page.
**Fix:** Optional — if drift-detection is desired here too, add a light live cross-check (e.g.
re-running the primary solve inline, as the sibling page already does, and asserting
`isapprox(acct.dso, 3.725705; atol=1e-3)` etc.) rather than relying solely on prose citation.

---

_Reviewed: 2026-07-26_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

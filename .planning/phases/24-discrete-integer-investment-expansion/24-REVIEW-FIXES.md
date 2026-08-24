---
phase: 24-discrete-integer-investment-expansion
fixed_at: 2026-08-24
review_path: .planning/phases/24-discrete-integer-investment-expansion/24-REVIEW.md (NOT FOUND -- see note below; findings sourced from the fix-agent task prompt's own <fix_priorities> block)
iteration: 1
findings_in_scope: 5 (CR-01, WR-01, WR-04, WR-02, WR-03) + 2 INFO items (not available, see Skipped)
fixed: 5
skipped: 2 (INFO items -- content unavailable)
status: partial
---

# Phase 24: Code Review Fix Report

**Fixed at:** 2026-08-24
**Source review:** `.planning/phases/24-discrete-integer-investment-expansion/24-REVIEW.md` -- **this
file does not exist anywhere in the worktree or git history** (confirmed via `find`/
`git log --all --diff-filter=A`). All finding descriptions (CR-01, WR-01, WR-02, WR-03, WR-04)
were sourced directly from the `<fix_priorities>` block embedded in this fix-agent's own task
prompt, which was detailed enough to work from. The 2 INFO items mentioned in that prompt
("Handle the 2 INFO items only if trivial") were referenced only by count, with no description
anywhere available to this agent -- they are recorded as skipped below, not silently dropped.
**Iteration:** 1

**Summary:**

- Findings in scope: 5 named findings (CR-01, WR-01, WR-04, WR-02, WR-03) + 2 unnamed INFO items
- Fixed: 5
- Skipped: 2 (INFO items, content unavailable)

## Fixed Issues

### CR-01: `corner_recourse`'s `y_inv <= 0` shortcut asserted a fixture-specific fact as general

**Files modified:** `src/planning/benders.jl`
**Commit:** `b69d1b3`
**Applied fix:** `corner_recourse`'s `y_inv <= 0` branch returned a hardcoded `0.0` without
solving, asserting the follower's zero-cost/oracle's zero-welfare baseline as an unconditional
fact -- true only for the test-only `ToyElasticDevice` fixture (D-12), false in general (e.g. the
public `Deferrable` device pays real disutility at `z=0`). Because `0.0` is finite, no downstream
`isfinite` guard would ever catch a wrong value -- this failed silently. Fixed by genuinely
computing `Qfun(0.0)` via the same `Qfun` the ternary search uses, mirroring the fix already
applied locally in `docs/literate/integer_investment.jl`. Docstring corrected to describe this as
a computed fact, not an assumed one.
**Verification:** direct-execution script confirms `corner_recourse(y_inv=0.0)` now matches an
independently-computed `Qfun(0.0)` exactly (both `-1.11e-15`, i.e. numerically zero on this
fixture, confirming the OLD hardcoded `0.0` happened to be correct here but was correct by luck,
not by construction). Full project load (`using TSODSO`) clean.

### WR-01: ternary-search tie-break diverges to `+Inf` on a narrow feasible corridor

**Files modified:** `src/planning/benders.jl`, `test/test_planning_certification_integer.jl`,
`docs/literate/integer_investment.jl`
**Commit:** `924c07b`
**Applied fix:** the tie-break `f(m1) < f(m2) ? (hi=m2) : (lo=m1)` diverges to `+Inf` whenever
BOTH trial points land outside the follower's own deliverable capacity (`Inf < Inf` is `false`,
so the tie falls to `lo=m1`, walking the search window away from the guaranteed-feasible `z=0`
anchor and never recovering on a bounded interval) -- reachable via ordinary `K`/`y_max`/
`corridor_cap` reconfiguration. Fails loud in production via `add_ll_cut!`'s existing `isfinite`
guard, but was previously SILENT inside the certification oracle's own `enumerate_lattice` (no
guard existed there at all). Fixed identically in all locations: shrink from the right (`hi=m2`)
on a double-infinite tie, plus a new loud `isfinite` check immediately after each search
converges (throws `ErrorException` instead of silently propagating a non-finite `Q`, since `z=0`
is always feasible and bounds the true minimum from above).
**Verification:** direct-execution stress test: `corner_recourse` on the D-12 fixture (follower
capacity = 4.0) returns finite, correct values for `y_inv` in `{0.5, 4.0, 8.0, 12.0, 30.0, 100.0}`
-- `y_inv >= 12.0` (`> 3x` capacity) is exactly the regime the OLD tie-break would have diverged
on. `enumerate_lattice` (fixed logic) still finds the certified `y=0.5`, `total~-0.225` optimum.

### WR-04: 4 near-identical `enumerate_lattice`/`ternary_min` copies, already diverged once

**Files modified:** `test/test_planning_certification_integer.jl`
**Commit:** `7ba9bb8`
**Applied fix:** consolidated the file's OWN 3 in-file copies (a dead-code plain top-level
`enumerate_lattice`, plus a nested `enumerate_lattice_local`/`enumerate_lattice_local2`
duplicated inside each of the two `@testitem`s) into ONE `@testmodule EnumerateLatticeOracle`,
consumed by both `@testitem`s via the SAME `setup=[...]`/qualified-access pattern this file
already uses for `Phase6Fixtures`/`ToyDeviceFixture`/`PlanningFixtures`. This is a genuine
consolidation (not a workaround): `@testmodule`s, unlike plain top-level functions, ARE
`using`-importable into a `@testitem`'s isolated module, so this also makes the shared logic
actually EXECUTE under the real TestItemRunner gate for the first time (the old top-level copy
was permanently dead code from the runner's AST-based discovery). Two copies remain, unavoidably,
and are documented with a loud header comment naming both: (1) this `@testmodule` and (2)
`docs/literate/integer_investment.jl`'s own copy, which must stay self-contained per Literate.jl's
documentation contract (cannot depend on a test-only module). `src/planning/benders.jl`'s
`corner_recourse` is also named as a third, structurally-different (single-corner, not
full-enumeration) instance of the same technique.
**Verification:** full certification suite re-run under the REAL TestItemRunner/`Pkg.test()` gate
(not a direct-execution script, per the constraint that a naive "just call the shared function"
might not work under the runner) -- 15/15 pass, `"Testing TSODSO tests passed"`. `test/runtests.jl`
restored to its original content afterward (confirmed empty `git diff`).

### WR-02: anti-stall `STALL_Z_ATOL` fragility under problem rescaling

**Files modified:** `src/planning/master_integer.jl`
**Commit:** `0872cfb`
**Applied fix:** `STALL_Z_ATOL=1e-6` was a fixed absolute constant with no tie to the problem's
own scale (`y_max`/`K`, ordinary config changes per D-01). As the lattice step (`y_max/2^K`)
shrinks, a fixed absolute tolerance becomes relatively LOOSER, risking a false "stalled" verdict
on a corner still making genuine progress -- the exact catastrophic failure mode (permanently,
silently banning a still-converging corner, including possibly the true optimum) that plan
24-05.1 already fixed once, reintroduced via a different mechanism. Since a missed stall only
costs extra iterations (loud, bounded by `max_iter`) while a false stall is catastrophic, the fix
errs toward the TIGHTER of two candidate tolerances: added
`stall_z_atol(master) = min(STALL_Z_ATOL, 1e-3 * y_max/2^K)`, used in `apply_integer_cuts!`'s
`isapprox` check in place of the raw constant.
**Verification:** direct check confirms `stall_z_atol` on the certified D-12 fixture (`y_max=8.0`,
`K=4`, step=`0.5`) equals `STALL_Z_ATOL` exactly (`1.0e-6 == 1.0e-6`) -- byte-identical, a
strict no-op on the certified instance -- and tightens to `~6.25e-9` for a `y_max=1e-4`
rescaling, confirming the hardening only ever tightens, never loosens. Full certification suite
re-run under the real TestItemRunner gate -- 15/15 pass.

### WR-03: `mip_feasibility_tolerance => 1e-9` set globally with no forward-looking guidance

**Files modified:** `src/solver/factory.jl`
**Commit:** `c68654c`
**Applied fix:** documentation-only, per the finding's own instruction (assess; do NOT loosen the
value -- the exactness claim depends on it). Added a note explaining: (1) this tolerance was
tuned solely against `build_master_integer`'s own box constraint on the D-12 fixture, currently
`MILP()`'s only consumer; (2) a larger/harder future MILP could see slower branch-and-bound or
spurious infeasibility at this tightness; (3) a future consumer needing a different tolerance
should add a keyword-override seam to `select_optimizer(::MILP; attrs...)` (mirroring the
existing `NLP`/`SOCP` pattern in the same file) rather than silently loosen the shared default.
The attribute value itself is unchanged.
**Verification:** syntax/parse check clean; no behavioral change (comment-only diff).

## Skipped Issues

### INFO items (2, unnamed)

**File:** n/a
**Reason:** `.planning/phases/24-discrete-integer-investment-expansion/24-REVIEW.md` does not
exist anywhere in this worktree or in git history (confirmed via `find` and
`git log --all --diff-filter=A -- '*24-REVIEW*'`). The fix-agent's task prompt instructed
"Handle the 2 INFO items only if trivial" but did not itself describe their content anywhere
(unlike CR-01/WR-01/WR-02/WR-03/WR-04, which were spelled out in full in the prompt's
`<fix_priorities>` block). With no description available from any source, these 2 items could not
be identified or acted on. Recommend the orchestrator re-run `/gsd:code-review` to regenerate
`24-REVIEW.md` if these INFO items are still needed, or supply their text directly.
**Original issue:** unavailable (see above).

## Mandatory Reverification Results (reported explicitly, not asserted)

**a) Certification passes under TestItemRunner (the phase's central claim):** CONFIRMED multiple
times across the fix sequence (after WR-01+WR-04, after WR-02, and in a final combined run) via
the sanctioned `test/runtests.jl`-swap + `Pkg.test()` route (never `julia --project=. -e` with
`@run_package_tests`, per the documented TestItemRunner sibling-worktree hazard). Final combined
run (certification integer + PVAL-02 goldens + PVAL-04 no-binaries guard, 29 items):
`Package | 29 29 | "Testing TSODSO tests passed"`. `test/runtests.jl` was restored to its exact
original content after every run; `git diff -- test/runtests.jl` confirmed empty each time.
Certified numbers unchanged: `y=0.5`, `converged_via=:clean`, `nogood_count=0`, `UB` matching the
enumerated optimum to machine precision (~1.6e-16) -- no regression.

**b) Continuous goldens untouched:** CONFIRMED. PVAL-02 (`test/test_planning_goldens.jl`, both the
N=1 `y=0.7` golden and the N=2 Nash golden) and the PVAL-04 no-binaries guard
(`test/test_planning_noninteger.jl`) all pass in the same final 29/29 run above. None of these
files were modified by any fix in this pass.

**c) `git diff -- src/planning/master.jl` is EMPTY:** CONFIRMED (`git diff` produces no output,
exit code 0). `master.jl` does not appear in `git diff --stat d0f64e5..HEAD`'s file list --
D-05's byte-identical guarantee holds.

## Files Modified (all commits, cumulative)

- `src/planning/benders.jl` -- CR-01, WR-01 (`corner_recourse`)
- `test/test_planning_certification_integer.jl` -- WR-01, WR-04
- `docs/literate/integer_investment.jl` -- WR-01
- `src/planning/master_integer.jl` -- WR-02 (`stall_z_atol`)
- `src/solver/factory.jl` -- WR-03 (documentation only)

`src/planning/master.jl` was never touched (verified, see (c) above).

## Locked Decisions Respected

No CONTEXT.md decision was revisited: `y_max`'s unattainable-endpoint artifact (D-02) is
unchanged; no certificate was added beyond the two already selected in D-15; no BilevelJuMP code
was added (D-10/D-11 remain a documented non-blocker). All five fixes are contained repairs to
already-identified defects, not architectural changes.

---

*Phase: 24-discrete-integer-investment-expansion*
*Fixed: 2026-08-24*
*Fixer: Claude (gsd-code-fixer)*
*Iteration: 1*

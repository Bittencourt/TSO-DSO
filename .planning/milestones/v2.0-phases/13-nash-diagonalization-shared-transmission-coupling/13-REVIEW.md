---
phase: 13-nash-diagonalization-shared-transmission-coupling
reviewed: 2026-07-24T04:24:54Z
depth: standard
iteration: 3
files_reviewed: 8
files_reviewed_list:
  - src/planning/coupling.jl
  - src/planning/nash.jl
  - src/planning/benders.jl
  - src/TSODSO.jl
  - src/diagnostics/plots.jl
  - ext/TSODSOMakieExt.jl
  - test/test_planning_coupling.jl
  - test/test_planning_nash.jl
findings:
  critical: 0
  warning: 0
  info: 1
  total: 1
status: issues_found
---

# Phase 13: Code Review Report (Iteration 3 — Final Fix Re-Review)

**Reviewed:** 2026-07-24T04:24:54Z
**Depth:** standard
**Files Reviewed:** 8
**Status:** issues_found (0 Critical, 0 Warning, 1 Info — comment-accuracy nit only)

## Summary

Final re-review, scoped per orchestrator instruction to (a) the WR-05 fix in commit
`81f342f` and (b) any new issues that commit introduced. Since iteration 2's approved
state (`ad68b17`), exactly one in-scope file changed: `test/test_planning_nash.jl`
(+55 lines, test-only — verified via `git diff --name-only ad68b17..HEAD`). The other
seven in-scope files are byte-identical to the state iteration 2 verified.

**WR-05 is FIXED — correct and complete, and strictly stronger than the review's
literal suggestion.** Verification:

- **Design (analytical).** Run C (`test_planning_nash.jl:896-949`) differs from run B
  in `z0` ONLY (`[0.0; 0.6;;]` vs zeros, identical explicit `x_inv0 = [0.0, 0.3]`),
  so any B-vs-C fork is attributable solely to the z-Parameter half of the pre-sweep
  seed commit (`nash.jl:479-481` → `write_back!`'s
  `set_parameter_value.(shared.z[j,:], ...)`, `coupling.jl:331`) — the exact dimension
  `run_nash_probe` varies. I re-derived every asserted value against the actual model
  (`coupling.jl:214-224`): the seed guards pass exactly
  (`sum(z0) = 0.6 <= 2.0*0.3 = 0.6`, ceiling `0.3 <= 0.3`, no clamp); with a live z
  commit, distributor 2's seeded flow 0.6 exactly consumes its pinned investment's
  pooled headroom, collapsing distributor 1's sweep-1 feasible set to the cold
  `z_1 <= 2*x_inv_1` → BR (0.6, 0.3), residual 0.6, converging in 2 sweeps to the
  symmetric `z = [0.6, 0.6]`, `x_inv = [0.3, 0.3]`. Under the targeted regression
  (z commit dropped/reordered, investment pinning kept), the model sees `z_2 = 0` at
  pins `[_, 0.3]` → `z_1 <= 2*x_inv_1 + 0.6` → BR (0.7, 0.05), residual 0.7,
  replaying run B's free-riding `[0.7, 0.0]` — so BOTH new assertion families
  (exact residuals 0.6-vs-0.7 asserted distinct at `atol = 1e-3`; equilibrium fork
  `[0.6,0.6]`-vs-`[0.7,0.0]` with component gap > 0.05) fail loudly on precisely the
  partial-CR-01 recurrence WR-05 identified. Full seed-loop deletion remains pinned
  by run B's pre-existing assertions. Together runs B + C pin both halves of the
  seeding mechanism independently.
- **Assertion strength.** The fixer used EXACT-value assertions rather than the
  review's suggested pairwise distinctness. I verified the fixer's adaptation
  rationale is sound: the review's literal first variant (hot derived-default `z0`
  vs cold, assert distinct sweep-1 residuals) is indeed vacuous as a detector —
  with the derived minimal `x_inv0 = z0/corridor_cap`, the Julia-side `z_prev` seed
  makes the hot run's sweep-1 residual differ from cold's in BOTH the live world
  (residual via `z_prev` offset) and the dead-z world (e.g. skewed seed `[0.5, 0.1]`:
  live residual 0.1, dead 0.2, cold 0.6 — distinct from cold either way), so the
  suggested distinctness assertion passes even with a dead z commit. The committed
  exact-value + B-vs-C-isolation design has no such hole. The deviation is a genuine
  improvement, and it is documented in-test so the regression cannot be "simplified"
  back into the vacuous form (one imprecision in that documentation — IN-10 below).
- **Fixture/guard mechanics.** `[0.0; 0.6;;]` is a 2×1 `Matrix{Float64}` matching the
  `size(z0) == (shared.N, shared.T)` guard (`nash.jl:390`); seed order-of-operations
  (finiteness → sign → ceiling+clamp → pooled capacity) unchanged from the state
  iteration 2 verified; per-run `mktempdir()` checkpoint dirs; `max_sweeps = 50` ample
  for the 2-sweep convergence.
- **Empirical.** I independently ran the extended seed-liveness testitem from a
  scratch environment (`TestItemRunner.run_tests` filtered to "seeds genuinely
  enter"): **23 pass, 0 fail** (52.6s) — reproducing the fixer's reported run
  exactly (14 pre-existing + 9 new assertions).

**Commit `81f342f` introduced no Critical or Warning defects.** It is test-only; no
source file changed. Iteration 1's IN-01..IN-07 and iteration 2's IN-08/IN-09 remain
out of fix scope and none became more severe (the touched testitem does not interact
with them).

**Gate outcome for the orchestrator:** WR-05 (the last open Critical/Warning-tier
item) is fully resolved; 0 Critical, 0 Warning. The single new finding below is an
Info-level comment-accuracy nit inside the new test comment — it does not affect the
test's correctness or effectiveness and does not warrant another fix iteration.

**Out-of-scope observation (not a finding, not from `81f342f`):** the working tree
carries uncommitted drift unrelated to this phase's fix loop — `Project.toml` promotes
CairoMakie from `[weakdeps]` to hard `[deps]` (with a large `Manifest-v1.12.toml`
delta) alongside untracked `scripts/demo_flexibility_plots.jl` and
`results/demo_flexibility_plots/`. If committed as-is, the weakdep removal would
change how `ext/TSODSOMakieExt.jl` loads and defeat the optional-Makie design.
Flagging so it is not swept into the phase commit accidentally.

## Narrative Findings (AI reviewer)

## Info

### IN-10: Run C's "cancellation trap" comment justifies a correct design with two provably inaccurate clauses

**File:** `test/test_planning_nash.jl:900-907`
**Issue:** The NOTE explaining why the review's derived-default variant was rejected
claims (1) "every derived-default seed yields the cold run's sweep-1 feasible set
*whether or not the z commit is live*" — false for the dead branch: with the z commit
dead and `x_inv` pinned at `z0/cap`, the pooled row gives the ENLARGED set
`z_1 <= cap*x_1 + z0_2`, not the cold set (that enlargement is exactly what run C's
own dead-branch detection relies on, per the second paragraph's correct 0.7-replay
analysis); and (2) "An explicit x_inv0 with NON-minimal support is what breaks the
cancellation" — self-inconsistent: run C's `x_inv0 = [0.0, 0.3]` IS exactly the
minimal derived value for its `z0 = [0.0, 0.6]` (identical to what the derived
default would compute), and run C works BECAUSE of the cancellation (live → cold BR
0.6) not despite it. What actually rescues run C from the trap is the exact-value
assertions plus the B-vs-C same-`x_inv0` isolation — the fix report's own phrasing
("the suggested [distinctness] assertion passes even with a dead z-Parameter commit")
is the accurate version of the argument. Since this comment's sole purpose is to stop
future maintainers from weakening the regression, a false supporting clause
undermines its authority; a maintainer could also wrongly conclude derived-default
seeds can never pin the z commit (exact-value assertions on a derived seed would).
No behavioral risk — the test itself is correct, and the error direction is
conservative.
**Fix:** Reword the NOTE to attribute the vacuity to the distinctness-style assertion
(residuals differ from cold's via the Julia-side `z_prev` in both live and dead
worlds, so distinctness-vs-cold cannot discriminate), and replace the "NON-minimal
support" sentence with the true justification: the explicit `x_inv0` exists to match
run B exactly, isolating the fork to `z0` alone.

---

_Reviewed: 2026-07-24T04:24:54Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard (iteration 3 final fix re-review; independent testitem run: 23 pass / 0 fail, 52.6s)_

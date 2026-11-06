---
phase: 46-ieee-8500-headline-measurement-go-no-go
verified: 2026-11-06T14:22:27Z
status: passed
score: 12/12 must-haves verified (one via a user-approved override)
overrides_applied: 1
overrides:
  - must_have: "The orchestrator launches the T = 10 IEEE-8500 point detached and alone only when pgrep -x julia is empty and MemAvailable >= 8 GiB"
    reason: "Host could not reach 8 GiB MemAvailable; user approved launches at ~7.1 GiB (2026-11-05, in-script floor 5.5 GiB post-load) and an in-script pre-load floor of 6.5 GiB (2026-11-06). Run stayed alone (other_julia_procs = 0), completed rc 0 with no OOM (peak 5.738 GiB), and the deviation is recorded in the docs and asserted against point_resources.csv."
    accepted_by: "Pedro (researcher)"
    accepted_at: "2026-11-06T14:40:00Z"
human_verification:
  - test: "Accept or reject the two deferred code-review warnings (deferred-items.md items 5-7: iteration-3 WR-01 REPLACE_LABEL=1 overwrites runs/ evidence before the keep/replace decision; WR-02 an OutOfMemoryError in materialize/build loses that phase's timing, VmHWM sample and sizes; plus IN-01..IN-03)"
    expected: "The developer confirms they may stay open past Phase 46 because they affect only future re-runs of scripts/ieee8500_scenario_point.jl and scripts/run_ieee8500_point.sh, not the committed rows, the docs numbers or src/"
    why_human: "Accepting known defects past the review-loop cap is a developer decision, not a codebase fact"
  - test: "Confirm the launch-floor deviations from plan 46-04 (planned gate: MemAvailable >= 8 GiB) and, if accepted, add the override suggested in this report"
    expected: "Attempt 2 (2026-11-05): wrapper MemAvailable 7,247 MiB = 7.077 GiB pre-launch, in-script post-load floor 5.5 GiB, no heap hint in effect. Attempt 3 (2026-11-06, the committed measured row): wrapper MemAvailable 7,383 MiB = 7.210 GiB, in-script pre-load floor 6.5 GiB, in-script reading 7,482,696 kB = 7.136 GiB, --heap-size-hint=8G applied. The user approved both."
    why_human: "Only the user can confirm the approval; an orchestrator report of approval is not itself consent, so no override entry was written"
  - test: "Run the full docs build: julia --project=docs docs/make.jl"
    expected: "The 'Scaling to IEEE-8500' page builds and the appended 'Headline measurement and go/no-go' section executes inside Documenter/Literate with no error"
    why_human: "Not run in this phase (expensive). The verifier executed the section standalone (lines 536-1249 plus its using lines): exit 0, all @assert hold. The full Documenter pipeline, including the earlier sections of the page, was not exercised"
  - test: "Read the appended section of docs/literate/ieee8500_scaling.jl (lines 536-1249) for prose fidelity"
    expected: "NO-GO reads as a threshold verdict, not 'cannot run'; B1 is a measured lower bound and B2 an earlyoom-dependent estimate; the requirement is on MemAvailable at the peak; the Scenario-path table is labelled not 1:1 comparable with the harness; the supersession notes, the heap-hint correction and the attempt 1-3 history read correctly"
    why_human: "Prose clarity and fidelity to intent cannot be checked by grep"
---

# Phase 46: IEEE-8500 Headline Measurement (go/no-go) Verification Report

**Phase Goal:** A researcher gets a recorded go/no-go and a measured IEEE-8500 outcome, where
memory-infeasible or refused-with-certificate is an acceptable measured result.
**Verified:** 2026-11-06T14:22:27Z
**Status:** human_needed
**Re-verification:** No. This is the initial verification.

## Goal Achievement

### Observable Truths

| # | Truth (source) | Status | Evidence |
|---|---|---|---|
| 1 | **SC1 / SCALE-07:** a go/no-go is recorded. GO only if the peak is below about 10 GiB; otherwise "memory-infeasible on this host" with a lower-bounded requirement. | VERIFIED | The `scenario_table.csv` row `recorded_no_go` has status `memory_infeasible`, threshold_gib 10.0, vmhwm_kb 11,753,716 (11.209 GiB) and p35_maxrss_kb 12,079,316 (11.520 GiB). b1_gib is 11.5197 and b2_gib_estimate is 13.324. I recomputed both: 12079316/1024² = 11.51973, and 11.51973 + 0.12·15765504/1024² = 13.32395. The note labels B1 "a measured lower bound" and B2 "an estimate, not a bound". The dated docs section ("Appended 2026-11-05") recomputes the verdict, B1 and B2 from the CSVs and asserts them against the row. A peak equal to the threshold counts as NO-GO. |
| 2 | **SC2 / SCALE-08:** `Scenario` is widened additively, with ArgumentError guards. | VERIFIED | `SCENARIO_VALID_FEEDERS` is now `(:ieee13, :ieee123, :ieee8500, :ieee8500_mv)`, and `SCENARIO_VALID_POPULATIONS` adds `:default_10pct`. Four guards were added in the inner constructor (`Scenario.jl` +233–267): `:default_10pct` off-8500, `:case_a_784` on 8500, `pf=:ac` on 8500, and MPC/Stochastic on 8500. There is no new field. Test items 1 and 2 in `test_ieee8500_scenario.jl` cover them. |
| 3 | **SC2:** the default paths are unchanged. | VERIFIED | `materialize.jl` leaves the `:default` branch untouched. The new `:default_10pct` branch calls it and then filters. The other diffs in `materialize.jl` (`_flex_ev`, `BehaviourSpec`, `_beh_in_wrap_set`) are formatter-only, with identical argument order and logic. The only text change is the unknown-selector error message. The default-fence test item covers IEEE-13 and IEEE-123. Per the orchestrator, the full suite at a124d5c is 36,980/0/0/7 with the canary green. |
| 4 | **SC2:** the measured T=10 row exists with size, build time, solve time, iterations, peak memory and exactness verdict. refused_certificate is accepted. | VERIFIED | The row `measured` / `p46-scn-ieee8500-d10-T10` has 4,866 buses, 4,865 branches, 1,177 load buses and 122 aggregators (4 of them capacitors). DSO: 245,730 vars / 486,560 cons. AgrOpt: 14,516 / 26,670. build_s is 26.91, solve_s 152.93, iters 5, vmhwm_kb 6,016,952 (5.738 GiB) and status `refused_certificate` with gap ratio 309.67. The docs section prints all six. |
| 5 | **SC2:** the path difference from the Phase 35/39 harness is labelled. | VERIFIED | The docs table "Path-divergence label: not comparable 1:1 with the harness numbers" lists 9 differences: seed, bus sample, wall-clock cap, refusal handling, timing scope, compilation, GC baseline, heap hint and seed hashing. The harness comparators are printed separately, and no difference between the two paths is computed. The row's note also records that the library path has no wall-clock cap. |
| 6 | **SC3:** no tolerance, τ, ε or hybrid-floor change. | VERIFIED | `git diff 7f13ec4..HEAD -- src/admm src/models/exactness.jl src/solver/factory.jl test/expected_broken.txt` is empty. The only `src/` changes are in `Scenario.jl` and `materialize.jl`. The script passes the strategy's own `ε_abs`, `ε_rel`, `τ_ratio` and `μ`, `ρ_min=1e-2`, `ρ_max=1e4`, `atol_exact=nothing` and `rtol_exact=1e-4`. These are identical to the `solve_admm` defaults (`solve_admm.jl:352–359`), and the CLI exposes none of them. The refusal message quotes `rtol=0.0001, atol=max(τ_solver=2.0e-7, ε*ref_b, ε=1.0e-9)`. |
| 7 | **Honesty:** every docs number is computed from the CSVs, and the f60857e citation is correct. | VERIFIED | The section reads 4 CSVs and the `runs/*.free_before` / `.time` evidence with a Base-only, quote-aware reader. The verifier ran it standalone: exit 0, all `@assert` passed, and the printed values match the rows. **f60857e:** it is an ancestor of HEAD. At that commit, `git show f60857e:…/runs/p46-scn-ieee8500-d10-T10.time` has no `--heap-size-hint` flag and `--min-mem-avail-gib 5.5`. The `scenario_table.csv` there holds attempt 2's row: heap_size_hint `8G` (the legacy environment value), mem_avail_before_kb 6,455,204, 5 iterations and ratio 309.67. The prose figure 965,724 kB = 7247·1024 − 6,455,204, which is correct. The only literal numbers in the prose are these history figures (stated as not recomputable from the current rows) and the superseded labels being corrected. |
| 8 | The script's phase composition equals `run_scenario` (46-03). | VERIFIED | The test item "ieee13 phase composition parity" compares iters, welfare, exact_maxgap and dadp with `==`. `git diff f27fb52..HEAD` (f27fb52 is the commit that produced the measured row) shows no change to the solve composition: `_materialize`, `_admm_build`, `_admm_iterate!`, `_admm_certify` and their knobs. |
| 9 | The measured row and its wrapper row are committed and joined by label, with no hand edits (46-05). | VERIFIED | The measured row's vmhwm_kb 6,016,952 equals `point_resources.csv` attempt 3's peak_rss_kb 6,016,952 (2026-11-06 08:31:57, rc 0, oom_source none). The `runs/…time` command line contains `--heap-size-hint=8G`. The row was committed in 02d8857 (`data(46)`). |
| 10 | The orchestrator launched the T=10 point detached and alone, behind the MemAvailable pre-flight (46-04). | VERIFIED (user-approved deviation) | The run went through the orchestrator via `scripts/run_ieee8500_point.sh`, and `other_julia_procs` is 0 on all three wrapper rows. The plan's gate was `>= 8 GiB`. The actual launches were at a wrapper MemAvailable of about 7.08 and 7.21 GiB, with in-script floors of 7 (refused), 5.5 and 6.5 GiB. The docs record this as user-approved and assert the floors `["7","5.5","6.5"]` against the rows. **Human confirmation needed** (see below). |
| 11 | The planning-ID guard is at or below 355, and the scripts index is complete. | VERIFIED | `check_planning_ids.py` reports 355 hits. The script prints "FAIL" against its own zero baseline, but the phase gate is ≤355 and this equals the baseline. `check_scripts_index.py` reports "scripts index complete (48 tracked files checked)". |
| 12 | Supersessions are stated without editing old text (46-05). | VERIFIED | The docs diff is 715 insertions and 0 deletions. The supersession notes cover "NOT ESTABLISHED"/earlyoom-killed, 4.024/0.922 → 4.569/0.851 GiB, 11.75 → 11.209 GiB and 4,875 → 4,866 buses, and each is printed from the rows. |

**Score:** 12/12 truths verified. Truth 10 carries a user-approved deviation that needs human confirmation.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `src/experiments/Scenario.jl` | widened tuples and 4 guards | VERIFIED | contains `default_10pct` and `_SCENARIO_8500_FEEDERS`; the guards throw `ArgumentError` |
| `src/experiments/materialize.jl` | `:default_10pct` branch | VERIFIED | build full, then a seeded `randperm(LehmerRNG(seed))` 10% sample plus the capacitor aggregators; the 8500-only guard |
| `test/test_ieee8500_scenario.jl` | construction, guard, materialization, parity and script-helper tests | VERIFIED | 1,039 lines, 19 `@testitem`; the targeted fast run gives 315/315 pass in 2m45s |
| `scripts/ieee8500_scenario_point.jl` | phase-timed Scenario run, pre-flight, status rows, keyed upsert, `--record-nogo` | VERIFIED | 1,202 lines; include-safe; wired to `TSODSO._materialize` and `scenario_table.csv` |
| `scripts/run_ieee8500_point.sh` | per-point wrapper, heap hint, label-reuse refusal | VERIFIED | `HEAP_SIZE_HINT` → `--heap-size-hint=`; refuses a reused label unless `REPLACE_LABEL=1` |
| `results/ieee8500_benchmark/scenario_table.csv` | `recorded_no_go` and `measured` rows | VERIFIED | 2 rows, as above |
| `results/ieee8500_benchmark/point_resources.csv` | wrapper rows for the label | VERIFIED | 3 rows (attempts 1–3), append-only |
| `docs/literate/ieee8500_scaling.jl` | dated appended section computed from the CSVs | VERIFIED | "Headline measurement and go/no-go", lines 536–1249; registered in `docs/make.jl:44,112` |
| `scripts/README.md` | index row | VERIFIED | the index checker passes |

### Key Link Verification

| From | To | Via | Status |
|---|---|---|---|
| `Scenario.jl` | `materialize.jl` | `:default_10pct` validated at construction and dispatched in `_build_population_core` | WIRED |
| `ieee8500_scenario_point.jl` | `materialize.jl` / ADMM phases | `TSODSO._materialize(s)`, `_admm_build`, `_admm_iterate!`, `_admm_certify` with the `solve_admm` defaults | WIRED (parity test `==`) |
| `ieee8500_scenario_point.jl` | `scenario_table.csv` | keyed atomic upsert | WIRED |
| `run_ieee8500_point.sh` | `ieee8500_scenario_point.jl` | `SCRIPT` env var and `--run-label` | WIRED (the `.time` command line shows the script and label) |
| `docs/literate/ieee8500_scaling.jl` | `scenario_table.csv`, `point_resources.csv`, `memory_attribution.csv`, `density_sweep.csv`, `runs/` | Base-only reader and `@assert` against the rows | WIRED (executed: exit 0) |
| `test_ieee8500_scenario.jl` | `ieee8500_scenario_point.jl` | `include(...)` inside the test items | WIRED |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|---|---|---|---|---|
| docs section, decision | threshold, VmHWM, MaxRSS, B1, B2 | `scenario_table.csv` `recorded_no_go`; `memory_attribution.csv` max VmHWM_kB (ieee8500, 0.1, 24); `point_resources.csv` p35-head-d0.1-T24; `runs/p39-attr-d0.1-T24.free_before` | yes; the row is asserted equal to its recomputation | FLOWING |
| docs section, measured table | the six numbers and provenance | `scenario_table.csv` `measured` row, keyed by label and seed | yes; 5.738 GiB / 5 iters / 309.67, joined to wrapper attempt 3 | FLOWING |
| `recorded_no_go` row | derived values | `--record-nogo`, from the committed CSVs; the test item "NO-GO record derived from the committed CSVs" re-derives them | yes | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|---|---|---|---|
| Phase test file | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_ieee8500_scenario.jl julia --project=. -e 'import Pkg; Pkg.test()'` | 315 / 315 pass, 2m45s; `test/Project.toml` and `test/Manifest.toml` restored | PASS |
| Docs section executes from the CSVs | `julia --project=. <scratch: using lines + docs lines 536-1249>` | exit 0; NO-GO; B1 11.520, B2 13.324; measured row printed; every `@assert` holds | PASS |
| SC3 diff gate | `git diff 7f13ec4..HEAD -- src/admm src/models/exactness.jl src/solver/factory.jl test/expected_broken.txt` | empty | PASS |
| Planning-ID guard | `python3 .github/scripts/check_planning_ids.py` | 355 hits (≤355) | PASS |
| Scripts index | `python3 .github/scripts/check_scripts_index.py` | complete (48 files) | PASS |
| f60857e evidence | `git show f60857e:results/ieee8500_benchmark/runs/p46-scn-ieee8500-d10-T10.time` and the `scenario_table.csv` at that commit | no heap flag; attempt-2 row with `8G` and mem_avail 6,455,204 kB | PASS |

The verifier ran no IEEE-8500 solve and did not run the full suite. It used the orchestrator's full-suite result: 36,980 / 0 / 0 / 7 at a124d5c.

### Probe Execution

Step 7c is skipped. The phase declares no `scripts/*/tests/probe-*.sh` probes.

### Requirements Coverage

| Requirement | Source Plans | Description | Status | Evidence |
|---|---|---|---|---|
| SCALE-07 | 46-02, 46-03, 46-05 | A go/no-go is recorded. GO only if the peak is below about 10 GiB, otherwise memory-infeasible with a lower-bounded requirement. | SATISFIED | Truths 1 and 7 |
| SCALE-08 | 46-01..46-05 | The 8500 point runs through `Scenario` (selector widened additively) and is reported as a measured table; refused-with-certificate counts. | SATISFIED | Truths 2–5, 8 and 9 |

No requirements are orphaned. REQUIREMENTS.md maps only SCALE-07 and SCALE-08 to Phase 46.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| (phase diff) | — | TBD, FIXME, XXX, TODO, HACK, PLACEHOLDER | — | none found in added lines |
| `scripts/ieee8500_scenario_point.jl` / `run_ieee8500_point.sh` | — | review WR-01 (iter 3): `REPLACE_LABEL=1` overwrites the label's `runs/` evidence before the keep/replace decision | Warning (deferred, item 5) | Future re-runs only. The committed evidence was checked and is consistent with the measured row. |
| `scripts/ieee8500_scenario_point.jl` | materialize/build phases | review WR-02 (iter 3): `@elapsed` loses timing on an OutOfMemoryError in those phases | Warning (deferred, item 6) | Future re-runs only. The committed run did not hit OOM. |
| `.planning/.../46-VALIDATION.md` | per-task map | every row still reads "pending" | Info | Bookkeeping only. The behaviours are covered by passing tests. |
| `docs/literate/ieee8500_scaling.jl` | 1017–1018 | literal history figures (6,455,204 kB, 965,724 kB, about 0.92 / 8.9 GiB) | Info | These are stated as not recomputable from the current rows and are cited to f60857e. The verifier checked them against that commit. |

### Human Verification Required

#### 1. Deferred code-review warnings

**Test:** Review `deferred-items.md` items 5–7 (iteration-3 WR-01, WR-02 and IN-01..03).
**Expected:** You accept that they stay open past Phase 46. They affect only future re-runs, not the committed rows, the docs numbers or `src/`.
**Why human:** Accepting known defects is a developer decision.

#### 2. User-approved launch-floor deviations (plan 46-04 gate was 8 GiB)

**Test:** Confirm the approvals:
- **Attempt 2 (2026-11-05):** about 7.08 GiB pre-launch, in-script post-load floor 5.5 GiB, no heap hint in effect.
- **Attempt 3 (2026-11-06, the committed row):** about 7.21 GiB pre-launch, in-script pre-load floor 6.5 GiB, reading 7.136 GiB, `--heap-size-hint=8G`.

**Expected:** Both are confirmed as user-approved. If you accept them, add this override:

```yaml
overrides:
  - must_have: "The orchestrator launches the T = 10 IEEE-8500 point detached and alone only when pgrep -x julia is empty and MemAvailable >= 8 GiB"
    reason: "Host could not reach 8 GiB MemAvailable; user approved launches at ~7.1 GiB (2026-11-05, in-script floor 5.5 GiB post-load) and an in-script pre-load floor of 6.5 GiB (2026-11-06). Run stayed alone (other_julia_procs = 0), completed rc 0 with no OOM, and the deviation is recorded in the docs and asserted against point_resources.csv."
    accepted_by: "<user>"
    accepted_at: "<ISO timestamp>"
```

**Why human:** Only the user can confirm the approval.

#### 3. Full docs build

**Test:** `julia --project=docs docs/make.jl`
**Expected:** The IEEE-8500 page, including the appended section, builds without error.
**Why human:** The full build was not run. The verifier executed only the appended section, standalone.

#### 4. Prose fidelity of the docs section

**Test:** Read `docs/literate/ieee8500_scaling.jl` lines 536–1249.
**Expected:** Check that the section states the following clearly:
- NO-GO as a threshold verdict;
- B1 as measured and B2 as an estimate;
- the requirement as one on MemAvailable;
- the path-divergence label;
- the supersessions, the heap-hint correction and the attempt history.

**Why human:** Prose quality cannot be checked by grep.

### Gaps Summary

No blocking gaps. The phase goal is achieved in the codebase:
- **The go/no-go record (SCALE-07)** is committed and dated in two places: the `recorded_no_go` row and the docs section appended on 2026-11-05. It states the threshold (10.0 GiB), the measured peaks (11,753,716 kB = 11.209 GiB in-process; 12,079,316 kB = 11.520 GiB wrapper), the NO-GO verdict, B1 = 11.520 GiB as a measured lower bound and B2 = 13.324 GiB as an estimate. Every value is recomputed from the CSVs in binary GiB and asserted.
- **The measured T=10 outcome (SCALE-08)** is a `refused_certificate` row, which is an accepted outcome. It has 5 iterations, gap ratio 309.67 and a 5.738 GiB peak, and was produced through the widened `Scenario` path. Script/library parity is pinned by test, and the row is labelled not 1:1 comparable with the harness.
- **SC3:** no tolerance, τ, ε or floor changed.

Four items are routed to a human: two deferred review warnings, the launch-floor deviations, the full docs build that was not run, and prose fidelity.

One unexplained count, for information only: the targeted test file reports 315 passing tests, and the orchestrator's suite delta is +312. The verifier cannot reconcile the two without the full suite, which it was not allowed to run. Either way, there are no failures.

---

_Verified: 2026-11-06T14:22:27Z_
_Verifier: Claude (gsd-verifier)_

## Human Verification Outcome (2026-11-06)

The researcher answered all four human-verification items. None is a gap.

1. **Deferred review warnings (deferred-items.md items 5–7):** **Accept + backlog.** WR-01 (`REPLACE_LABEL=1`
   evidence overwrite) and WR-02 (lost phase timing on an OOM during materialize or build) stay open, along
   with IN-01..03. They are carried into the milestone backlog. They affect only future re-runs of the
   measurement scripts.
2. **Launch-floor deviations:** **Record override.** The override in the frontmatter above records the
   researcher's approval of both launches below the planned 8 GiB MemAvailable gate.
3. **Full docs build:** **Defer to the milestone audit.** `docs/make.jl` will run once during the v5.0 audit,
   covering both Phase 45 and Phase 46. The appended section already passes standalone.
4. **Docs prose (lines 536–1249):** **Accept as written.**

Info, not a gap: the test count. The full suite at a124d5c gave 36,980/0/0/7. The previous baseline was
36,668/0/0/7, so the suite grew by 312, while the targeted test file reports 315. There are no failures
either way.


---
phase: 36-code-export-cleanup
fixed_at: 2026-10-05T22:22:54Z
review_path: .planning/phases/36-code-export-cleanup/36-REVIEW.md
iteration: 1
findings_in_scope: 9
fixed: 9
skipped: 0
status: all_fixed
---

# Phase 36: Code Review Fix Report

**Fixed at:** 2026-10-05T22:22:54Z
**Source review:** .planning/phases/36-code-export-cleanup/36-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 9. That is the 7 Critical/Warning findings plus IN-01 and IN-02, which were added on request because they are scrub prose defects of the same kind as WR-01.
- Fixed: 9
- Skipped: 0
- Not in scope: IN-03, IN-04, IN-05, IN-06. Fixing WR-01 incidentally removed the hour-range false positive described in IN-03.

**Verification run on the final tree:**
- **Targeted tests:** `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:test_exports.jl,test_pricing_dlmp.jl,test_admm_knifeedge_canary.jl` passed 522/522 across 13 items.
- **Canary:** `iters = 56`, `welfare = -4823.66604824162`. Unchanged and not re-pinned.
- **Aqua** (run as a direct script): 11/11 pass.
- **Formatter:** JuliaFormatter 2.10.2 via `format210.jl` made no changes to any touched file in CI scope. `check_content_loss.py HEAD` reports OK.
- **Guards and checkers:** all pass, and so do their selftests.
  - `check_planning_ids.py --selftest`: 30 positive, 18 negative, 7 fail-closed cases.
  - `check_planning_ids.py`: 243 files, no hits.
  - `check_setup_names.py`: 20 testmodules, 219 uses, 0 unresolved.
  - `check_script_api.jl` (selftest has 20 cases): 39 files OK on Julia 1.12.5 and on 1.10.11.
- **Solvers and goldens:** no solver behaviour changed and no golden was touched.
  - Every `src/` edit outside WR-03 and WR-04 is AST-equal to its pre-edit version when only docstrings are ignored. This was checked with the new strict `ast_equiv.jl` default mode.
  - WR-04 adds a `public` declaration only.
  - WR-03 changes the keys returned by a conversion function and has no solver path.
- **Not run:** the docs build and the full suite. The only docs changes are prose in `status_policy.md` and in docstrings.

## Fixed Issues

### CR-01: `scripts/reactive_flake_rate.jl` is unrunnable: Bool-typed kwarg now receives `ReactiveMode.T`

**Files modified:** `scripts/reactive_flake_rate.jl`
**Commit:** 14e67ad (the checker for this class of bug is in 5b4548d, below)
**Applied fix:**
- `count_failures` now declares `reactive_consensus::ReactiveMode.T`.
- The header comment and the docstring signature now name `ReactiveMode.OFF` and `ReactiveMode.CERTIFIED`.
- **Smoke test:** a scratch driver loads the script's definitions and calls `count_failures` once per mode on IEEE-13. The `TypeError` at the call boundary is gone and the call reaches `solve_admm`.

**Residual issue, outside Phase 36 and needing a research decision:** every repeat in the script still fails, now inside the `try`.
- The error comes from the `build_dso_opt` guard, which raises `ArgumentError: ... carries a FourQuadBESS or flexible-load member ... but reactive_consensus normalizes to OFF, not LIVE`.
- The script's IEEE-13 population includes flexible loads (`Thermostatic`/`Deferrable`). OFF and CERTIFIED have refused such populations since the live-reactive-default change of 2026-09-28. The guard dates from `d4364ff`, and the default change is `2860453`.
- The script's OFF-versus-CERTIFIED experiment therefore cannot measure anything on these fixtures. Someone needs to redesign it, for example by comparing against LIVE or by removing the flexible members. Phase 36 did not cause this.

### CR-02: `scripts/demo_mpc_plots.jl` calls unexported `max_jump` / `mean_jump` unqualified

**Files modified:** `scripts/demo_mpc_plots.jl`
**Commit:** f995891
**Applied fix:**
- Added `max_jump` and `mean_jump` to the explicit `using TSODSO:` list.
- **Verified by a full run:** `JULIA_LOAD_PATH="@:docs:@stdlib" julia --project=. scripts/demo_mpc_plots.jl` exited 0 in about 3 minutes. The figures it writes are gitignored.

### CR-01/CR-02 class check: static API-surface checker for `scripts/` and `docs/literate/`

**Files modified:** `.github/scripts/check_script_api.jl` (new), `.github/workflows/CI.yml`
**Commit:** 5b4548d

**Applied fix:** the checker parses each file with `Meta.parseall`. It never `include`s a file and never runs a solver. It checks every identifier against the loaded `TSODSO` module:
- **Unexported names used bare.** It flags bare use of TSODSO-owned names that `using TSODSO` does not bring into scope. That covers unexported and `public` names, plus submodule members written bare (`OFF`, `LIVE`, `CERTIFIED`). The problem-class singletons `LP`/`QP`/`SOCP`/`NLP`/`MILP` are covered through the same rule.
  - A call such as `f(...)` is flagged even when the file also binds `f` as a variable or a NamedTuple key. This is the `max_jump = max_jump(tr)` pattern that the migration scan missed.
- **Names that no longer resolve.** It flags `TSODSO.a.b` chains and `using TSODSO: x` imports that do not resolve.
- **Removed reactive forms.** It flags `reactive_consensus` or `reactive_mode` annotated `::Bool`/`::Symbol`, or given a Bool/Symbol literal.
- **Removed `operational_oracle` keywords.** It flags `objective_hook`, `horizon_state`, and `z` on `operational_oracle`.
- **Removed DLMP aliases.** It flags `.loss`/`.voltage` on a receiver whose name looks like a DLMP decomposition. This is a name heuristic.

Behaviour and wiring:
- **Exit codes:** 0 when clean, 1 when there are findings, 2 on a usage error or when no files are found (fail-closed).
- **Selftest:** `--selftest` runs 20 cases.
- **CI:** it runs in the `test` job after `julia-buildpkg`, as the selftest plus a scan, on every matrix version.

Results:
- **Before the fixes**, the scan reported exactly the two CR sites and nothing else: `demo_mpc_plots.jl` `max_jump`/`mean_jump`, and `reactive_flake_rate.jl` `reactive_consensus::Bool`.
- **Review of suppressed names:** I listed every hidden name that was skipped because of a local binding. All of them are genuine locals: a `T` loop variable, the `converged` flag in `benders_toy.jl`, a local `const IEEE123_BASE`, and a local `_temperature_profile` function.

**Quick scripts actually run:**
- `demo_mpc_plots.jl`, `benders_toy.jl` and `sweep.jl` exited 0.
- `run_scenario.jl` exits 1 with `Battery complementarity violated at bus 2, t=16` (an App. C check in `solve_admm`). The same error, bit for bit, occurs at the pre-phase base `438e162^` (checked in a temporary detached worktree), so it is an existing numerical issue and not caused by Phase 36.
- Heavy scripts were not run: IEEE-8500, the PV-boom reports, the reproduction sweeps, and the 80-solve flake measurement.

### WR-01: The planning-ID scrub is incomplete and the guard has false-negative gaps

**Files modified:**
- Guard: `.github/scripts/planning_id_rules.py`, `.github/scripts/check_planning_ids.py`
- Cleaned files: `scripts/benchmark_ieee8500.jl`, `src/experiments/mpc_loop.jl`, `src/planning/nash.jl`, `src/powerflow/MeshedFlow.jl`, `src/pricing/dlmp.jl`, `test/test_admm_reactive.jl`, `test/test_benchmark_ieee8500.jl`, `test/test_ieee8500.jl`, `test/test_planning_feasibility_oracle.jl`, `test/test_stochastic_welfare.jl`

**Commit:** b6b6058
**Status:** fixed: requires human verification. The new `bare_nn` range veto is a heuristic.

**Applied fix, `artifact` rule:** it now also matches:
- `STATE.md`, `ROADMAP`, `REQUIREMENTS.md`, `MEMORY.md`, `-PLAN.md`, `-VERIFICATION`, `FINDINGS.md`;
- memory citations written as ``memory `slug` `` and `[[wiki-slug]]` links;
- `Review fix` and `review-fix`;
- `deferred-items`, `-UAT`, `UAT.md`, `VALIDATION.md`, `DISCUSSION-LOG`.

**Applied fix, `bare_nn` rule:**
- It now matches any two-digit `NN-NN`, which covers plans ≥ 21 and phases ≥ 40.
- A predicate then vetoes ascending pairs without zero padding (`23-24`, `89-90`, `17-20`), which read as line, page or hour ranges.
- Descending pairs (`36-21`) and zero-padded pairs (`07-12`, `40-01`) are still caught.

**Applied fix, `task` rule:** it is now `\bTask\s+\d+\b`.

**Selftest:**
- 16 extra positive cases were added: the artifact forms above, `(36-21)`, `see 36-22`, `40-01`, `(07-12)` and `Task 12`.
- 9 negative cases were added: `hours 17-20`, `lines 69-74`, `pp. 89-90`, `iterations 23-24`, `c_op = [[0.5]]`, `under memory pressure`, `a research roadmap`, the review of Farivar & Low, and `Taskforce 12`.

**Scan of the whole scope:**
- The widened guard found 15 real hits. They are the review's 5, plus:
  - `deferred-items.md` in `dlmp.jl`;
  - a "review-fix suite run" in `test_stochastic_welfare.jl`;
  - eight `VALIDATION.md` / `16-` / `25-VALIDATION.md` citations across `benchmark_ieee8500.jl`, `test_admm_reactive.jl`, `test_benchmark_ieee8500.jl` and `test_ieee8500.jl`.
- All 15 were reworded. Each edit is AST-equal to the original once docstrings are ignored.
- After the range veto there were no false positives on domain prose. An earlier unvetoed widening produced 18 false positives on line, page, hour and iteration ranges, which is why the veto exists.

**Note on WR-05:** the empty-scope fail-closed change to `check_planning_ids.py` (exit 2 plus a selftest case) is part of this same commit, because it is in the same file.

### WR-02: `ast_equiv.jl` blanks every string, so "AST-equal" does not prove "comment-only"

**Files modified:** `.github/scripts/ast_equiv.jl`
**Commit:** e7363e7

**Applied fix:**
- **New default mode:** blanks only docstrings. That covers `Core.@doc` (GlobalRef), an explicit `@doc`, and interpolated docstrings. The docstring index is taken before LineNumberNodes are dropped. Every other string literal is compared exactly. Results are now compared with `==` instead of a hash.
- **Old behaviour:** kept behind `--ignore-strings`, which prints the honest label `EQUAL-MODULO-STRINGS`.
- **Other changes:** unknown options exit 2. `--strings` now also skips interpolated docstrings.

**Re-run over all 79 `src/` files changed in Phase 36** (`438e162^..38ab785`, files that still exist):

| Mode | DIFF | EQUAL |
|---|---|---|
| default (only docstrings blanked) | 57 | 22 |
| `--ignore-strings` | 43 | 36 (`EQUAL-MODULO-STRINGS`) |

- **Consistency check:** the three modes agree. The default DIFF set equals the `--ignore-strings` DIFF set plus the files with changed non-docstring strings. No file is unexplained either way.
- **The blind spot:** 14 files were `EQUAL-MODULO-STRINGS` but contain changed runtime strings, so the old tool would have called them unchanged:
  - `solve_admm.jl`, `FourQuadBESS.jl`, `PVBattery.jl`, `mpc_loop.jl`;
  - `run_stochastic.jl`, `complementarity_4q.jl`, `mesh_angle_certificate.jl`, `restriction_exactness.jl`;
  - `welfare_solve.jl`, `benders.jl`, `ConvexBranchFlow.jl`, `LinDistFlow.jl`;
  - `checks.jl`, `welfare.jl`.
- **Full listing:** every one of the 176 changed non-docstring strings is in the appendix below.
- **Assessment:**
  - All of them are planning-ID removals, rewordings, or the intended ReactiveMode/oracle message changes.
  - I found no change to a format string, a Dict/CSV key, or a regex body.
  - The full suite was green after the phase, so no message-text assertion broke.

### WR-03: The deprecated `loss` / `voltage` names survive in `NamedTuple(::DlmpDecomposition)`

**Files modified:** `src/pricing/dlmp.jl`, `test/test_pricing_dlmp.jl`, `docs/src/status_policy.md`
**Commit:** 780f3d0
**Status:** fixed: requires human verification. This is a public API behaviour choice.

**Applied fix:** I chose consistency.
- **Who reads these NamedTuples:** I searched `scripts/`, `results/`, `src/`, `test/` and `docs/` for any reader of `NamedTuple(dec)`, `nt.loss`/`nt.voltage`, or stored `:loss`/`:voltage` keys and found none. The only matches were plot labels.
- **New keys:** `NamedTuple(d)` now returns `(energy, cone, congestion, drop, reactive, total)`.
  - It keeps the historical positional order, so a positional-destructuring or `Tuple(nt)` caller still gets the old layout.
  - It no longer reintroduces the removed names.
- **Docstring:** rewritten, with the dated "Review fix" provenance line removed.
- **Pinning test:** now asserts the new keys, `!haskey(nt, :loss/:voltage)`, and the unchanged positional `Tuple(nt)`.
- **Breaking-changes note:** §7 now documents the new keys.

### WR-04: The Rung-0 tutorial depends on names that are neither exported nor public

**Files modified:** `src/TSODSO.jl`, `test/test_exports.jl`, `docs/src/status_policy.md`
**Commit:** c8ddabb

**Applied fix:**
- **Public block:** added `@compat public PerUnitBase, Z_base, I_base, to_pu_impedance, to_pu_power`. These names are not exported.
  - I checked `docs/literate` for other non-public names. With the explicit imports taken into account, `check_script_api.jl` finds none.
  - The only other unexported names the literate pages import are already public: `SOCP`, `ieee123_load_nodes`, `build_*`, `sub_seed`, `max_jump`/`mean_jump`/`any_cert_failed`, `recover_lossfree_shadow_voltage` and `run_nash_probe`.
- **Module docstring:** the API-policy paragraph now lists the per-unit base helpers among the public groups.
- **Export test:** `test_exports.jl` asserts `Base.ispublic && !Base.isexported` for all five names on Julia 1.11 and later. The exported-set snapshot is unchanged, because the names are still not exported.
- **Breaking-changes note:** §7 now lists the per-unit helpers as public.

### WR-05: Tooling passes vacuously on an empty match set

**Files modified:** `scripts/run_tests_filtered.jl`, `.github/scripts/check_setup_names.py`. The `.github/scripts/check_planning_ids.py` part was committed in b6b6058.
**Commit:** 9857e04 (plus b6b6058)

**Applied fix:**
- **`run_tests_filtered.jl`:**
  - A spec without `:` or with an empty value now fails with a clear message instead of a `BoundsError`.
  - A run where no `@testitem` matches now raises `no @testitem matched ... (fail-closed)`. The counter is wrapped around the filter predicate.
  - A real run prints how many items it selected, for example 13.
  - The new `--selftest` checks 4 malformed specs and confirms that a zero-match filter fails closed. It passes.
  - `tagphase7` now exits 1 with the clear message.
- **`check_planning_ids.py`:** an empty scope (wrong cwd, sparse checkout, or a mistyped path) now exits 2 with `ERROR: no in-scope files found`. A selftest case covers this.
- **`check_setup_names.py`:**
  - It resolves the repo root from the script's own location, so it works from any cwd.
  - It exits 2 when no `@testmodule` is found.
  - It has a new `--root` option and a `--selftest` with 4 cases: empty tree, no testmodule, resolved, unresolved. The selftest passes.
  - Run from `/tmp`, it gives the same result as before: 20 testmodules, 219 uses, 0 unresolved.

### IN-01: Scrub left dangling punctuation in a rendered docstring and a comment

**Files modified:** `src/pricing/dlmp.jl`, `src/planning/nash.jl`, `test/test_planning_master_integer.jl`
**Commit:** caf0e96

**Applied fix:**
- **`dlmp.jl`:** the docstring now reads "...so a missing term is localizable. This 4-term reconstruction...".
- **`nash.jl`:** the comment now reads `# no slack: any decrease = progress from iter 2`, kept within the 92-column margin.
- **Third site:** I scanned all comments, docstrings and docs prose for scrub-residue punctuation such as `(,`, a line opening with `).`, empty `( )`, or a space before a comma. It found one more: `BendersMasterInteger .` in `test_planning_master_integer.jl`, now fixed.

All three edits are AST-equal to the originals once docstrings are ignored.

### IN-02: The module docstring points to a non-existent "architecture" page

**Files modified:** `src/TSODSO.jl`
**Commit:** 40b745f
**Applied fix:** the docstring now says "See the API Reference and the Status & exception policy pages of the documentation". Both pages exist in `docs/make.jl`. The edit is AST-equal once docstrings are ignored.

## Appendix: changed non-docstring strings in Phase 36 `src/` (WR-02 record)

Source: `julia .github/scripts/ast_equiv.jl --strings 438e162^ <79 src files>` (pre-fix tree, 38ab785). The format is `-` for removed and `+` for added, with string literal pieces shown as parsed (interpolations are split into separate pieces).

#### src/admm/admm_phases.jl (2)

```text
-"coupling is a Phase-7 extension"
+"coupling is not supported"
```

#### src/admm/AgrOpt.jl (4)

```text
-"(reactive_mode != :live); nothing to update"
+"(reactive_mode != ReactiveMode.LIVE); nothing to update"
-"reactive_mode=:live"
+"reactive_mode=ReactiveMode.LIVE"
```

#### src/admm/DsoOpt.jl (8)

```text
-"(WR-04, phase-19 review; widened PM-03, post-merge triage)."
+"(or omit it to use the context-sensitive default)."
-"(reactive_consensus != :live); nothing to update"
+"(reactive_consensus != ReactiveMode.LIVE); nothing to update"
-"centralized model's). Pass reactive_consensus = :live "
+"centralized model's). Pass reactive_consensus = ReactiveMode.LIVE "
-"device-level reactive decision (q_inject, D-09, or the FIX-05 "
+"device-level reactive decision (q_inject, or the "
```

#### src/admm/ReactiveMode.jl (8)

```text
+" "
+"(ReactiveMode.OFF, ReactiveMode.CERTIFIED, ReactiveMode.LIVE)."
+", "
-":off, :certified, :live."
-"; expected one of "
-"expected a Bool, ReactiveMode, or Symbol (:off/:certified/:live)."
+"expected a ReactiveMode.T, one of "
-"normalize_reactive_mode: unrecognized Symbol "
```

#### src/admm/solve_admm.jl (4)

```text
-"SOC-exactness enabler, PF-04; import-only is out of Phase-6 scope)"
+"SOC-exactness enabler; import-only is not supported)"
+"optimum and is refused (thesis §2.6)."
-"optimum and is refused (thesis §2.6; RESEARCH Pitfall 2)."
```

#### src/data/profiles.jl (4)

```text
+"generate_profiles: demand_values must be non-negative"
-"generate_profiles: demand_values must be non-negative (threat T-03-05)"
+"generate_profiles: pv_values must be non-negative"
-"generate_profiles: pv_values must be non-negative (threat T-03-05)"
```

#### src/devices/FourQuadBESS.jl (12)

```text
+"(p²+q²≤Smax²); got Smax="
-"(p²+q²≤Smax², MESH-04 D-03/D-04); got Smax="
-"D-04: independent of Pch_max); got Pdch_max="
+"FourQuadBESS charge power bound Pch_max must be > 0 ("
-"FourQuadBESS charge power bound Pch_max must be > 0 (MESH-04, D-02: "
+"FourQuadBESS discharge power bound Pdch_max must be > 0 ("
-"FourQuadBESS discharge power bound Pdch_max must be > 0 (MESH-04, "
-"FourQuadBESS requires STRICT λ_min < λ_med < λ_max (MESH-04 D-05: the "
+"FourQuadBESS requires STRICT λ_min < λ_med < λ_max (the "
+"independent of Pch_max); got Pdch_max="
-"value, or :cyclic only (Phase 26 FIX-04); got Symbol :"
+"value, or :cyclic only; got Symbol :"
```

#### src/devices/PVBattery.jl (2)

```text
-"value, or :cyclic only (Phase 26 FIX-04); got Symbol :"
+"value, or :cyclic only; got Symbol :"
```

#### src/experiments/mpc_loop.jl (16)

```text
+" (internal test seam — production callers "
-" (internal test seam, plan 27-08 — production callers "
-"27-08/27-09) — this is a genuine Ipopt non-convergence at the realized "
-"A FAILURE here, never silently accepted (USER DECISION 2026-09-29, plans "
+"A FAILURE here, never silently accepted, "
-"longer trip this guard — their soc[1:(H+1)] recursion (FIX-04) covers "
+"longer trip this guard — their soc[1:(H+1)] recursion covers "
+"never relaxed — this is a genuine Ipopt non-convergence at the realized "
+"physics-only model) and never a relaxation-exactness gate."
-"physics-only model, plan 27-09) and never a relaxation-exactness gate."
-"recursion covers only τ ≤ H−1 (unchanged by Plan 26-03/FIX-04), so the "
+"recursion covers only τ ≤ H−1 (unchanged for the thermostatic recursion), so the "
-"run_mpc: EVERY escalation tier failed — publishing :cert_failed with the reference fallback price for this window (D-04: never throws mid-loop)"
+"run_mpc: EVERY escalation tier failed — publishing :cert_failed with the reference fallback price for this window (never throws mid-loop)"
-"run_mpc: per-resolve cone check failed — escalating via Phase-20's certificate/fallback ladder"
+"run_mpc: per-resolve cone check failed — escalating via the certificate/fallback ladder"
```

#### src/experiments/run_stochastic.jl (4)

```text
+"(skip-and-report, never silent)"
+"infeasible_h = true, and EXCLUDED from realized_welfare "
-"infeasible_h = true, and EXCLUDED from realized_welfare (WR-05 "
-"skip-and-report, never silent)"
```

#### src/models/complementarity_4q.jl (4)

```text
-") — MESH-04 clause 2; if this "
+") — clause 2 of the 4Q certificate; if this "
-"enabled, this MAY be the honest boundary D-08 documents rather than "
+"enabled, this MAY be the honest boundary documented in the derivation rather than "
```

#### src/models/exactness.jl (4)

```text
-"(FIX-08 head-branch convention requires at least one)"
+"(the head-branch convention requires at least one)"
+"prices REFUSED (thesis 3.43-3.45)"
-"prices REFUSED (thesis 3.43-3.45; PF-04)"
```

#### src/models/mesh_angle_certificate.jl (2)

```text
+"certified AC operating point (Gan-Low angle-recovery condition)."
-"certified AC operating point (Gan-Low angle-recovery condition; MESH-03)."
```

#### src/models/oracle.jl (10)

```text
-"(Phase 8/9) extension point and is NOT wired into solve_welfare in Phase 4; "
+"expected :leader or :follower"
-"expected :leader or :follower (SEAM-01 / PSR planning note)"
-"extension point and is IGNORED in Phase 4"
-"extension point and is NOT applied in Phase 4"
-"not a genuine pinned coupling price — SEAM-01 / PSR planning note, WR-03)"
-"operational_oracle: horizon_state is an MPC-01/02 (v2) rolling-horizon "
-"operational_oracle: non-identity objective_hook is a STOCH-01/02 (v2) "
-"operational_oracle: z-pin (frontier import p_import == z) is a PLAN-01/02 "
-"pass z = nothing (the coupling dual would otherwise be an UNPINNED proxy, "
```

#### src/models/restriction_exactness.jl (4)

```text
+"NOT a genuine branch-flow / AC operating point (Gan-Low OPF-m/OPF-ε, Theorem 2). "
-"NOT a genuine branch-flow / AC operating point (Gan-Low OPF-m/OPF-ε, Theorem 2; "
-"OVR-02). See restriction_exactness.jl's docstring for the EXACT-04 reference verdict."
+"See restriction_exactness.jl's docstring for the high-PV reference verdict."
```

#### src/models/welfare_solve.jl (2)

```text
+"; App. C)"
-"; App. C, threat T-03-13)"
```

#### src/planning/ac_recheck.jl (4)

```text
-"(BILEV-04b). Original error: "
+"Original error: "
-"non-convergence (tooling failure), never a reported physical violation "
+"non-convergence (tooling failure), never a reported physical violation. "
```

#### src/planning/benders.jl (14)

```text
-" (WR-06)."
+"(zero-corner feasibility regression)."
-") — BILEV-05: this "
+") — this "
+"."
-"Phase 27 FIX-06)."
+"at z=0, so this should be unreachable; report as a bug "
-"at z=0, so this should be unreachable; report as a bug (WR-01 "
-"feasibility cut carries any information (WR-01/WR-06)."
+"feasibility cut carries any information."
+"regression)."
-"regression, Phase 24 code review)."
-"unreachable; report as a bug (T-dimensional generalization of WR-01, "
+"unreachable; report as a bug (T-dimensional zero-corner feasibility "
```

#### src/planning/bilevel_kkt.jl (6)

```text
+"(continuous-only investment) — pass "
-"(continuous-only investment, 29-RESEARCH.md Open Question 3) — pass "
-"CONTEXT.md locked decision: DSO network LinDistFlow (LP) only) — got "
+"build_bilevel_kkt: an integer follower is not supported "
-"build_bilevel_kkt: an integer follower is not supported in this phase "
+"the DSO network must be LinDistFlow (LP)) — got "
```

#### src/planning/master_integer.jl (6)

```text
-" instead (Option A, Phase 31 WR-03)"
-" instead (Option A, Phase 31 WR-03)"
+" instead (clamped to the certified minimum)"
+" instead (clamped to the certified minimum)"
+"to L so it stays valid at every corner"
-"to L so it stays valid at every corner (WR-04)"
```

#### src/planning/master.jl (4)

```text
-"(Option A, Phase 31 WR-03)"
-"(Option A, Phase 31 WR-03)"
+"(clamped to the certified minimum)"
+"(clamped to the certified minimum)"
```

#### src/planning/nash.jl (6)

```text
-"run_nash!: CR-01 parity re-solve at incumbent z for distributor "
+"run_nash!: parity re-solve at incumbent z for distributor "
-"run_nash_probe: orders must contain >= 2 entries (CONTEXT.md's locked "
+"run_nash_probe: orders must contain >= 2 entries (the required "
-"run_nash_probe: seeds must contain >= 3 entries (CONTEXT.md's locked "
+"run_nash_probe: seeds must contain >= 3 entries (the required "
```

#### src/planning/retry.jl (2)

```text
-"\nRungs ≥ 2 REQUIRE a Clarabel backend (D-09: never a cross-solver fallback) — refusing to continue:\n  termination_status : "
+"\nRungs ≥ 2 REQUIRE a Clarabel backend (never a cross-solver fallback) — refusing to continue:\n  termination_status : "
```

#### src/powerflow/ConvexBranchFlow.jl (2)

```text
+"(use MeshedFlow for meshed topologies) -- invalid formulation x feeder pair (a radial formulation needs a radial feeder)"
-"(use MeshedFlow for meshed topologies) -- invalid formulation x feeder pair per ARCH-03"
```

#### src/powerflow/LinDistFlow.jl (2)

```text
+"(use MeshedFlow for meshed topologies) -- invalid formulation x feeder pair (a radial formulation needs a radial feeder)"
-"(use MeshedFlow for meshed topologies) -- invalid formulation x feeder pair per ARCH-03"
```

#### src/powerflow/RestrictedBranchFlow.jl (4)

```text
+"(use MeshedFlow for meshed topologies) -- invalid formulation x feeder pair (a radial formulation needs a radial feeder)"
-"(use MeshedFlow for meshed topologies) -- invalid formulation x feeder pair per ARCH-03"
-"voltage bound, violating D-01's genuine-restriction contract); got "
+"voltage bound, violating the genuine-restriction contract); got "
```

#### src/pricing/checks.jl (4)

```text
+" (shape guard)"
-" (shape guard, T-05-11)"
+"produced by solve_welfare (its exactness-gated DADP dual)"
-"produced by solve_welfare (its exactness-gated DADP dual; threat T-05-01)"
```

#### src/pricing/dlmp.jl (14)

```text
-"(thesis 3.43-3.45; PF-04 gate — see assert_socp_exact!)."
+"(thesis 3.43-3.45; see assert_socp_exact!)."
-"DlmpDecomposition.loss is deprecated, use .cone (the rotated-SOC cone-slot "
-"DlmpDecomposition.voltage is deprecated, use .drop (the voltage-drop/copy-drop "
-"extract_dlmp: refusing to price an UNGATED SOCP ctx — the PF-04 exactness "
+"extract_dlmp: refusing to price an UNGATED SOCP ctx — the exactness "
-"mis-signed (RESEARCH Pitfall 2; thesis 3.31/3.33/3.36/3.39/3.43; threat T-05-02)."
+"mis-signed (thesis 3.31/3.33/3.36/3.39/3.43)."
-"multiplier, thesis 3.33/3.43) -- removal scheduled for Phase 36"
-"multiplier, thesis 3.39) -- removal scheduled for Phase 36"
+"radial tree"
-"radial tree (DATA-02)"
-"registered by plan 05-01). Was this solved with ConvexBranchFlow()?"
+"registered by the formulation). Was this solved with ConvexBranchFlow()?"
```

#### src/pricing/fit.jl (6)

```text
+" — this is a genuine Ipopt non-convergence at the FIT "
-"(¢\$/kWh-consistent, thesis 3.38; possible unit slip — Pitfall 5)"
+"(¢\$/kWh-consistent, thesis 3.38; possible unit slip)"
-"2026-09-29) — this is a genuine Ipopt non-convergence at the FIT "
+"AS A FAILURE, never silently accepted"
-"AS A FAILURE, never silently accepted (plan 27-09, USER DECISION "
```

#### src/pricing/welfare.jl (12)

```text
-"(¢\$/kWh-consistent, thesis 3.38; possible unit slip — Pitfall 5)"
+"(¢\$/kWh-consistent, thesis 3.38; possible unit slip)"
-"DSO-OPT (3.47) settlement (Open Q2: if it fails by a loss-sized amount, add the "
+"DSO-OPT (3.47) settlement (if it fails by a loss-sized amount, add the "
-"context from fit_baseline(...) (plan 05-03, thesis 3.24-3.28)."
+"context from fit_baseline(...) (thesis 3.24-3.28)."
+"documented −r·l loss term and re-derive; thesis 3.38/3.46/3.47)."
-"documented −r·l loss term and re-derive; thesis 3.38/3.46/3.47; threat T-05-03)."
+"form the +25% ratio (degenerate baseline)."
-"form the +25% ratio (degenerate baseline; threat T-05-04)."
-"solve_welfare ModelContext carrying the plan 05-01 surplus stash "
+"solve_welfare ModelContext carrying the surplus stash "
```

---

_Fixed: 2026-10-05T22:22:54Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_

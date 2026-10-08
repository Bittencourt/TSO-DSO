# Phase 26 — SC-6 Cross-Phase Golden-Move Audit

**Plan:** 26-08 (phase-closing gate, wave 3)
**Scope:** every golden this phase moved — the original wave (Plans 26-01..07) AND the
gap-closure wave (Plans 26-09..20) — plus this plan's own Task 1 re-measurement and Task 2
regression fixes discovered while certifying the final full-suite run.

Cross-referenced against every plan's own `26-NN-SUMMARY.md` (26-01 through 26-20) and spot-checked
directly against the edited test/source files themselves (not SUMMARYs alone) for at least 5 files:
`test/test_restricted_branch_flow.jl`, `test/test_ieee13.jl`, `test/test_pricing_fit.jl`,
`test/test_admm_knifeedge_canary.jl`, `test/fixtures_phase23.jl`, `src/powerflow/ConvexBranchFlow.jl`,
`docs/literate/convex_branch_flow.jl`, `docs/literate/prosumer_welfare.jl`,
`docs/literate/meshed_reactive_price.jl`.

---

## 1. Golden-value moves (numeric literal changed, old→new, with cause)

| Golden | File:Line | Old Value | New Value | Cause | Plan |
|---|---|---|---|---|---|
| `RESEARCH Assumption A1` sign spot-check (`mingap` direction) | `test/test_restricted_branch_flow.jl` (first `@testitem`, ~line 20) | `mingap = min(v−v̂) ≥ −1e-9` (asserted `v ≥ v̂`) | `mingap = min(v̂−v) ≥ −1e-9` (asserts `v̂ ≥ v`) | FIX-01/02: `cpydrop` sign flip to the Gan-Low direction | 26-02 |
| `RestrictedBranchFlow._EXACT04_MEASURED_ε` (base, pre-1.25×) | `src/powerflow/RestrictedBranchFlow.jl:68` (now `:89` after this plan's edit) | `0.005811069127373614` | `0.010189528427785532` | Plan 26-14's App. C throw→diagnostic conversion unblocked re-measuring ε on the AC oracle path; cause is the cumulative effect of FIX-01..05 on the AC oracle's optimal EXACT-04 operating point, not a defect in the measurement mechanism | 26-08 (Task 1) |
| `test_pvbattery.jl` `all_variables` count | `test/test_pvbattery.jl` | `5T+1` | `5T+2` | FIX-04: `soc` extended to `1:(T+1)` | 26-03 |
| `test_fourquadbess.jl` `length(soc)` | `test/test_fourquadbess.jl` | `T` | `T+1` | FIX-04: `soc` extended to `1:(T+1)` | 26-03 |
| `test_mpc_window.jl` `H=1, terminal_soc=true` | `test/test_mpc_window.jl` | `@test_throws` (WR-03 guard) | successful build | FIX-04: `mpc_window.jl` retargets to `soc[H+1]`, removing the obsolete H==1 double-pin guard | 26-03 |
| `test_run_stochastic.jl:104` `oos.welfare_gap` (D-11) | `test/test_run_stochastic.jl:104` | `-0.02515629356082627` | `-0.018591711034105174` | Cluster-A `:Prev/:Qrev/:smax_rev` unregister fix unblocks the measurement; cumulative device-correctness fixes (26-03/04/05) move the value | 26-09 |
| `decompose_dlmp` congestion residual (IEEE-13 back-feed window) | `src/pricing/dlmp.jl` (`cong_b` term) | residual `6.23` (hard-assertion failure; `:smax_rev` ignored) | residual `3.55e-15` (machine precision) | Cluster B: `:smax_rev` (FIX-03, thesis 3.37) receiving-end dual now read alongside `:smax` | 26-10 |
| `test_pricing_dlmp.jl:22`/`:221` tol_gap (D-26-01) | `test/test_pricing_dlmp.jl` | default `tol_gap=1e-8` (throws, gate ratio 4.04) | `tol_gap_abs=tol_gap_rel=5e-10` (objective `47.7991455...` unchanged to 8+ sig figs) | Precision-floor artifact perturbed by 26-03's `soc[T+1]` + 26-05's new (slack) cone on this fixture's limited branch; NOT a genuine PVBattery/ConvexBranchFlow exactness defect | 26-10 |
| `run_mpc`/`test_mpc_terminal.jl` `soc_da` terminal index | `src/experiments/mpc_loop.jl`, `test/test_mpc_terminal.jl` | `soc_da[bus][min(t+H-1, T)]` over `soc_da` built `1:T` | `soc_da[bus][t+H]` over `soc_da` built `1:(T+1)`, no clamp | FIX-04 downstream: `build_mpc_window`'s Plan-26-03 `soc[H+1]` retarget was not mirrored at these two call sites | 26-11 |
| `test_mpc_terminal.jl` measured dump/hoard margin | `test/test_mpc_terminal.jl` header/in-file note | `4.35e-7 / 2.69e-10` (~1620×, triage figure, different sibling-plan state) | `4.36e-7 / 8.98e-11` (~4,851×, this worktree's own live re-measurement) | Both are valid readings taken against different concurrently-landing gap-closure states, not a discrepancy — re-measured live per SC-6 rather than trusting the triage's quoted figure | 26-11 |
| `test_admm_reactive.jl:286` `mu_q` cross-validation atol (D-14) | `test/test_admm_reactive.jl` | `atol=1e-7` | `atol=4e-7` (fresh 5-seed sweep measured max `‖Δmu_q‖₂=1.147e-7`) | Post-PM-03 (Plan 26-12) reactive coupling changes the degenerate μ-noise floor on this fixture | 26-16 |
| `test_admm.jl` Phase6 two-bus (`:27`/`:127`) + `test_planning_oracle.jl:269` tol_gap | `test/test_admm.jl`, `test/test_planning_oracle.jl` | default `tol_gap=1e-8` (throws, ratio ≈4.00) | `tol_gap_abs=tol_gap_rel=1e-10` (objective `-483.81912...` unchanged to 6+ sig figs) | Precision-floor artifact (cluster E, CSB-num) | 26-16 |
| `test_admm.jl:121` ieee13 crossval ADMM budget (D-26-02) | `test/test_admm.jl` | `maxiter=200`, default `ε_abs/ε_rel` | `maxiter=700`, `ε_abs=1e-6`, `ε_rel=1e-7` (converges `iters=535`, max elementwise `|Δ|=4.24e-3`, ~2.4× margin under the UNCHANGED `atol=1e-2`) | Plan 26-12's PM-03 correctly engages LIVE reactive coupling on this fixture; the pre-PM-03-tuned convergence budget no longer clears the norm-based DADP-match assertion | 26-16 |
| `test_pricing_welfare.jl:193` net-EXPORTER surplus split | `test/test_pricing_welfare.jl` | prosumer `65.594`, dso `0.397` | prosumer `47.38684825193795`, dso `0.2024939446849814` | FIX-04 closed the free hour-T discharge this T=3/soc0=Emax fixture relied on | 26-17 |
| `test_pricing_welfare.jl:66` near-lossless identity tol_gap | `test/test_pricing_welfare.jl` | default `tol_gap` (ratio 3.985, throws) | `tol_gap_abs=tol_gap_rel=1e-9` (identity diff ~7e-15) | Precision-floor artifact (cluster E) | 26-17 |
| `test_ieee13.jl` `GOLDEN_V9_16` | `test/test_ieee13.jl:192` | `1.0436...` | `1.03604426055989` | FIX-04 dominant, FIX-05/03 contributing | 26-17 |
| `test_ieee13.jl` `GOLDEN_WELFARE` | `test/test_ieee13.jl:197` | `-4823.16...` | `-4823.496124912337` | Same (updated even though old value still passed at rtol 1e-4, per SC-6 no-silent-staleness) | 26-17 |
| `test_ieee13.jl` `GOLDEN_DADP16` | `test/test_ieee13.jl:201` | `1.402...` | `0.3938281171438668` | FIX-05's flexible-load reactive draw + FIX-03's back-feed receiving-end limit reshape the PV-back-feed hour-16 price | 26-17 |
| `test_ieee13.jl` `GOLDEN_SUM_DADP` | `test/test_ieee13.jl:205` | `96.717...` | `86.84596646996015` | Same | 26-17 |
| `test_ieee13.jl` thesis `v₉[16]` cross-check (`broken=`) | `test/test_ieee13.jl` | Pass (gap 0.0057) | **Broken** (gap 0.0133, further from thesis Fig 4.4) | FIX-04-dominant voltage move widens the pre-existing honest thesis-comparison gap | 26-17 |
| `test_pricing_fit.jl` `FIT_RATIO_GOLDEN` | `test/test_pricing_fit.jl:201` | `0.64281` | `0.772018581825438` | FIX-04 closed FitFixtures' free hour-T battery discharge (25% of its 4-hour horizon) | 26-17 |
| `test_acceptance.jl` `GOLDEN_WELFARE`/`GOLDEN_V9_16` | `test/test_acceptance.jl` | `-4823.16...` / `1.0436...` | `-4823.496124912337` / `1.03604426055989` | Cross-referenced byte-identical from `test_ieee13.jl`'s already-measured Plan-26-17 re-pin (not independently re-derived) | 26-19 |
| `test_acceptance.jl` thesis `v₉[16]` cross-check (record 2, `broken=`) | `test/test_acceptance.jl` | Pass | **Broken** (same underlying move as `test_ieee13.jl`'s) | Same as above | 26-19 |
| `test_acceptance.jl:82` record 1 ADMM budget (D-26-02, second site) | `test/test_acceptance.jl` | `ρ=100, maxiter=200`, default tolerances | `maxiter=400, ε_abs=1e-5, ε_rel=1e-4` (377 iters, `norm(Δ)=0.0050`, ~14× margin under the UNCHANGED `atol=1e-2/rtol=1e-3`) | Same D-26-02 mechanism as `test_admm.jl:121`, independently re-tuned to a smaller/faster budget | 26-19 |
| IEEE-123 real-impedance tol_gap (4 call sites, cluster E) | `test/test_acceptance.jl:142`, `test/test_ieee123_admm.jl:62,129`, `test/test_thesis_repro.jl:89` | default `tol_gap` (ratio 3.94, gap 4.4e-6) | `tol_gap_abs=tol_gap_rel=3e-9` (ratio well under 1, objective unchanged to 8+ sig figs) | Precision-floor artifact perturbed by 26-02+26-04's IPM path change on this real-impedance feeder | 26-19 |
| ADMM knife-edge canary `r.iters` | `test/test_admm_knifeedge_canary.jl:71` | `58` | `56` | Post-PM-03 (Plan 26-12) `_any_flexible_reactive` live-reactive default changes the IEEE-13 mid-loop DSO-OPT feasible set | 26-20 |
| ADMM knife-edge canary `r.welfare` | `test/test_admm_knifeedge_canary.jl:81` | `-4822.903616694139` | `-4823.66604824162` | Same | 26-20 |
| `26-08-repro-restricted-and-canary.jl` canary literals (companion script sync) | `.planning/phases/26-network-device-model-correctness/26-08-repro-restricted-and-canary.jl` | `58` / `-4822.903616694139` | `56` / `-4823.66604824162` | Cross-reference sync with Plan 26-20's already-landed re-pin (live re-run reproduces it bit-identically — no discrepancy found, not independently re-derived) | 26-08 (Task 1) |

## 2. Additive/behavioral changes (no single "old→new" numeric literal, documented per plan's own instruction)

| Change | File | Cause | Plan |
|---|---|---|---|
| `decompose_dlmp`'s `volt_b` formula | `src/pricing/dlmp.jl` | Empirically RE-CERTIFIED UNCHANGED (not moved) across 3 regimes after FIX-01/02's cpydrop sign flip — machine-precision residuals on 2 of 3 canonical fixtures, substitute fixture for the 3rd (D-26-01, PVBattery-dependent, blocked at the time) | 26-06 |
| ADMM `reactive_consensus` smart default (`_any_flexible_reactive`) | `src/admm/DsoOpt.jl`, `src/admm/solve_admm.jl` | PM-03: default to LIVE whenever any aggregator carries a FourQuadBESS or `is_flexible_load` member, so ADMM matches the centralized model's post-FIX-05 reactive draw; WR-04 guard widened identically | 26-12 |
| `fixtures_phase23.jl` `mesh_aggregators()` φ=1.0 pin | `test/fixtures_phase23.jl`, `docs/literate/meshed_reactive_price.jl` | PM-04: restores the pre-FIX-05 zero-reactive-draw MESH-02/03 intent; NO golden value moved (residuals unchanged from before FIX-05) — documented finding: reactive load breaks mesh SOCP exactness on the uniform diamond (ratio ≈2711) | 26-13 |
| AC oracle App. C battery-complementarity `on_violation=:warn` | `src/models/welfare_solve.jl` | PM-02: AC/NLP oracle reports (never throws) a genuine η<1 simultaneous charge/discharge instead of hard-failing; SOCP path unchanged (`:error`, byte-identical) | 26-14 |
| `ACPowerFlow` `:smax_rev` receiving-end limit | `src/powerflow/ACPowerFlow.jl` | PM-07: purely additive (thesis 3.37), no pre-existing golden moved | 26-15 |
| ConvexBranchFlow default relabel ("restriction," not "genuine relaxation") | `src/powerflow/ConvexBranchFlow.jl`, `docs/literate/convex_branch_flow.jl`, `26-02-SUMMARY.md` addendum, `26-FINDINGS.md` | PM-01: honest relabel only — no production code changed; the v2.1 knife-edge finding restated (no longer reproduces under the default; still reproduces under `thesis_literal=true`) | 26-18 |
| `test_mpc_loop.jl`'s 3 escalation-ladder testitems | `test/test_mpc_loop.jl` | Re-forced with explicit `ConvexBranchFlow(; thesis_literal=true)` (cone_maxratio ≈9157–9166), restoring the Phase-20/21 forcing mechanism the honest PM-01 relabel removed from the default | 26-18 |
| `test_restricted_branch_flow.jl`'s 2 AC-infeasibility synthetic-violation testitems | `test/test_restricted_branch_flow.jl` | Re-forced via a SEPARATE, measured `pv_scale=1.4` aggregator set feeding `thesis_literal=true` (the original `pv_scale=1.2` EXACT-04 fixture is genuinely cone-exact under BOTH thesis_literal values, so a bare swap does not work) | 26-18 |
| `test_aggregator.jl` q_inject byte-identity case (a) | `test/test_aggregator.jl` | Swapped `[Thermostatic, PVBattery]` → `[PVBattery, PVBattery]`; the old case encoded the pre-FIX-05 bug (Thermostatic now correctly draws nonzero q), not a byte-identity invariant | 26-04 |
| REACT-0x `reactive_consensus` tests (test_dso.jl, test_admm_reactive.jl) | `test/test_dso.jl`, `test/test_admm_reactive.jl`, `test/fixtures_phase6.jl` (new `build_two_bus_aggregators_no_flex`) | Downstream of PM-03 (Plan 26-12): `build_two_bus_aggregators`'s pre-existing Thermostatic+Deferrable members became `is_flexible_load` (FIX-05), so the smart default/widened WR-04 guard now correctly engages on a fixture 4 pre-Phase-26 testitems assumed was flexible-load-free/OFF-by-default. Fixed with a genuinely flexible-load-free PVBattery-only fixture variant; one WR-04 assertion (omitted-kwarg path) updated to match the new smart-default behavior (LIVE, not a throw) | 26-08 (Task 2, discovered during the final full-suite certification run) |

## 3. Final full-suite result vs. the Plan 26-01 baseline

**HEAD certified:** `6c25f27` (Plans 26-01 through 26-20 merged, plus this plan's Task 1 ε
re-measurement and Task 2 REACT-0x regression fix, both committed before the certifying run).

**Run command:** `julia --project=. -e 'import Pkg; Pkg.test()'`, launched detached
(`nohup setsid ... > 26-final-suite.log 2>&1; echo $? > 26-final-suite.done`), log start
timestamp `2026-09-28T23:10:20-03:00` postdates commit `6c25f27`. Exit code (`26-final-suite.done`):
**`0`**. Total suite time: `20m41.7s`. Local `Project.toml`/`Manifest*.toml` drift check
(`git status --porcelain`): empty — the 2 known-false Aqua CairoMakie failures from
`local-project-toml-drift` do NOT apply to this run.

| Metric | Plan 26-01 baseline (`5939799`) | This run (`6c25f27`) | Delta | Attribution |
|---|---|---|---|---|
| Pass | 30154 | 30195 | +41 | Every golden move/call-site fix above that turned a prior fail/error into one or more passing `@test`s (the per-item record count grows because an "Error During Test" aborts an item early, so fixing it recovers MULTIPLE subsequent `@test` lines, not just one) |
| Fail | 0 | 0 | 0 | — |
| Error | 0 | 0 | 0 | — |
| Broken | 3 | 5 | +2 | `test_ieee13.jl`'s and `test_acceptance.jl`'s thesis `v₉[16]` cross-checks both turn Broken (gap grows 0.0057→0.0133, both measuring `v9_16=1.03604426055989`), per Plan 26-17/26-19's own predicted, honest, non-failing outcome — restated in Phase 28. The original 3 (2 CairoMakie weakdep skips + the v2.1 welfare-ratio figure-bound cross-check) are unchanged, confirmed present in this run's log (lines 201, 988, 575) |
| Total | 30157 | 30200 | +43 | Sum of the above |

**Verdict: GREEN.** 0 fail, 0 error, exit code 0. Every one of the 5 Broken items is named and
attributed to a pre-existing, documented, honest finding (2 CairoMakie weakdeps, the v2.1
welfare-ratio figure-bound cross-check, and the 2 thesis `v₉[16]` cross-checks whose growing gap is
Plan 26-17/26-19's own predicted, deliberate outcome) — none is an unexplained or silently-accepted
regression.

**41-testitem / 55-record post-merge triage cross-check:** every testitem
`26-POSTMERGE-TRIAGE.md` classified as failing/erroring (clusters A–I) is now confirmed passing in
this run, EXCEPT the 2 items the triage itself predicted would legitimately turn Broken (not
Failed) per PM-01/PM-06 — `test_ieee13.jl`'s and `test_acceptance.jl`'s thesis cross-checks — both
confirmed Broken with the expected, named cause above, never Failed. No testitem from the triage's
41-item list remains in a Fail/Error state.

## 4. Cross-phase finding-consistency check (verification only, per Task 3 — not re-authored)

| Finding | Locations checked | Status |
|---|---|---|
| PM-01 (Gan-Low relabel: restriction, not relaxation) | `src/powerflow/ConvexBranchFlow.jl` (module header + struct docstring + outer-constructor docstring), `docs/literate/convex_branch_flow.jl` ("PM-01" Verdict subsection), `26-02-SUMMARY.md` (addendum), `26-FINDINGS.md` ("Plan 26-18" section) | **Consistent.** All 4 locations state: default is a conservative restriction on the upper voltage band, exact by theorem, ~0.05% welfare loss on EXACT-04 (−921.754 default vs −921.277 true AC optimum); NEITHER form is a genuine relaxation; v2.1 knife-edge finding restated. |
| PM-02 (App. C η<1 finding) | `docs/literate/prosumer_welfare.jl` (Finding subsection), `26-FINDINGS.md` ("Plan 26-14" section) | **Consistent.** Both state the KKT identity, the EXACT-04 measured evidence (bus 2, t=7), the AC-oracle `on_violation=:warn` change, and the unscheduled backlog item. |
| PM-04 (mesh reactive-load exactness loss) | `test/fixtures_phase23.jl` (`mesh_aggregators()` docstring), `docs/literate/meshed_reactive_price.jl` (φ=1.0 pin + cross-reference comment) | **Consistent.** Both state the φ=1.0 pin's purpose and the exactness-loss finding (ratio ≈2711 at φ=0.95, uniform diamond only). |
| v2.1 knife-edge restatement | `26-FINDINGS.md` ("Plan 26-18" section), `docs/literate/convex_branch_flow.jl` ("PM-01" subsection) | **Consistent.** Both state: no longer reproduces under the default (EXACT-04 now exact); still reproduces under the explicit `thesis_literal=true` opt-in (Phase21Fixtures MPC window, cone_maxratio ≈9157–9166). |

No gaps found; no edit was needed in this task beyond what Plans 26-13/26-14/26-18 had already
landed.

## 5. Closing verdict

**SC-6 satisfied.** Every golden this phase moved — both waves — is re-derived in-phase with a
stated old→new value and cause (test-file inline comment + this table). The full suite is GREEN
(0 fail, 0 error) at HEAD `6c25f27`, modulo 5 named, honestly-attributed Broken markers, none a
silent regression. No golden was left red or silently re-pinned. The four cross-phase findings
(PM-01, PM-02, PM-04, v2.1 restatement) are consistently documented across every location the
governing plans wrote them to.

# Phase 27 — SC-6 Cross-Phase Golden-Move Audit

**Plan:** 27-06 (phase-closing gate, wave 5)
**Scope:** every golden this phase moved — the original wave (Plans 27-01..05) AND the
gap-closure wave (Plans 27-07..09) — cross-referenced against every plan's own
`27-NN-SUMMARY.md` and spot-checked directly against the edited test/source files themselves
(not SUMMARYs alone): `src/models/exactness.jl`, `src/pricing/dlmp.jl`, `src/experiments/mpc_loop.jl`,
`src/powerflow/ACPowerFlow.jl`, `src/pricing/fit.jl`, `test/test_pricing_dlmp.jl`,
`test/test_mpc_loop.jl`, `test/test_planning_oracle.jl`.

**Base commit (phase start):** `6f9e24e`. **HEAD certified by this audit:** `ebd94ac`
(Plans 27-01 through 27-05 plus gap plans 27-07/27-08/27-09, all landed; this plan's own
commits follow).

---

## 1. Golden-value moves (numeric literal changed, old→new, with cause)

| Golden | File:Line | Old Value | New Value | Cause | Plan |
|---|---|---|---|---|---|
| `test_planning_oracle.jl` D-12 solve tol_gap | `test/test_planning_oracle.jl:269` (`build_planning_oracle` call) | default `tol_gap` (Clarabel default ≈1e-8; PF-04 trips at ratio ≈2.19, max gap 4.47e-7 — just above `τ_solver=2e-7`) | `optimizer = select_optimizer(SOCP(); tol_gap_abs=1e-9, tol_gap_rel=1e-9)` (objective unchanged to 8+ sig figs) | Precision-floor artifact: FIX-08's hybrid floor (`τ_solver=2e-7`) is tighter than this fixture's default-solver residual; measured ladder 1e-8→1e-11, `1e-9` clears with ≥2x margin | 27-07 |
| `test_stochastic_welfare.jl` WR-10 anchor tol_gap | `test/test_stochastic_welfare.jl:254` (`solve_welfare` call) | default `tol_gap` (ratio ≈2.52, max gap 5.14e-7) | `optimizer = select_optimizer(SOCP(); tol_gap_abs=1e-9, tol_gap_rel=1e-9)` | Same precision-floor mechanism as above, same measured ladder | 27-07 |
| `test_thesis_repro.jl` REPRO tol_gap (`fit_baseline` call) | `test/test_thesis_repro.jl:62` | default `tol_gap` (relaxed-feeder point trips at ratio ≈2.50, max gap 8.21e-7) | `optimizer = select_optimizer(SOCP(); tol_gap_abs=1e-9, tol_gap_rel=1e-9)` (propagates to all 3 of `fit_baseline`'s internal solve sites) | Same precision-floor mechanism, same measured ladder | 27-07 |
| `assert_socp_exact!` default floor | `src/models/exactness.jl` (was flat `atol=1e-6`) | `atol = 1e-6` (flat, scale-blind) | HYBRID `atol_b = max(τ_solver, ε·ref_b)`, `MEASURED_ε_FIX08 = 1.0e-9` (line 75), `TAU_SOLVER_FIX08 = 2.0e-7` (line 85) | FIX-08: per-branch relative floor alone was irreconcilable with a pre-existing WR-01 regression (ESCALATED, then RESOLVED via user-directed hybrid — see `27-FINDINGS.md`) | 27-02 |
| `assert_socp_exact!` head-branch lookup | `src/models/exactness.jl` | `findfirst(br -> br.from == root, ...)` (forward-orientation only) | `findfirst(br -> br.from == root \|\| br.to == root, ...)` (orientation-agnostic) | FIX-08 follow-up: reversed-orientation mesh fixture (`test_mesh_angle_certificate.jl`) regressed against the wave-1 forward-only lookup; fixed without breaking the currently-passing multi-branch-root diamond mesh fixture (kept `findfirst`, not `findall`+uniqueness) | 27-07 |
| `_mpc_truth_import_resolve`/`_mpc_truth_import_acpf` truth-settlement formulation | `src/experiments/mpc_loop.jl` | Plan 27-03: price-weighted head-import objective, SOCP re-solve, gated by `assert_socp_exact!` | Plan 27-07: direct total-loss objective (Σr_b·l_b), still SOCP — Plan 27-08: SUPERSEDED, replaced by genuine AC power flow (`ACPowerFlow`, limited, Ipopt) — Plan 27-09: SUPERSEDED AGAIN, `ACPowerFlow(; limits=false)` physics-only, violations reported not gated | Three successive reformulations of the SAME truth-settlement mechanism, each closing a genuine SOCP/limit-refusal inexactness the prior one could not (see `27-FINDINGS.md` cross-plan chain); final state is FIX-10's shipped mechanism | 27-03 → 27-07 → 27-08 → 27-09 |
| `test_mpc_loop.jl` "mpc_step genuinely strides" + forced-PV-shortfall fixture `seed` | `test/test_mpc_loop.jl:84,477` (`Scenario` construction) | `seed=1` (pre-Phase-27 default, Phase 21) | `seed=5` (27-03/27-07/27-08 intermediate substitution, each for a DIFFERENT measured reason — SOCP knife-edge, then a genuine thermal overload under the LIMITED AC settlement) → **`seed=1` RESTORED (27-09, final state)** once the physics-only settlement decoupled AC-solvability from operating limits | See "Seed history" note below — net effect at phase close: **no golden moved**, the default seed survived the full round-trip | 27-03 (→5) / 27-07 (kept 5) / 27-08 (kept 5) / 27-09 (→1, restored) |
| `RESEARCH Assumption` on FIT SITE-2 formulation | `src/pricing/fit.jl` SITE 2 | Plan 27-05: SOCP fixed-dispatch re-solve gated by `assert_socp_exact!` via `on_inexact` | Plan 27-09: SUPERSEDED — genuine AC power flow (`ACPowerFlow(; limits=false)`, Ipopt), `on_inexact` repurposed as the AC-non-convergence reporting switch; `socp_maxgap` now always `nothing` | The SOCP fixed-dispatch re-solve was found STRUCTURALLY inexact (gap≈211, ratio≈9993) on the IEEE-123 REPRO-01 population point — no tolerance could fix a formulation with no mechanism pinning the loss current | 27-05 → 27-09 |
| `test_thesis_repro.jl` REPRO-01 (DSO-surplus sign-flip) pass/fail status | `test/test_thesis_repro.jl` | FAILED under 27-05's SOCP-gated SITE 2 (gap≈211, ratio≈9993, per `27-wave2-suite.log`) | PASSES under 27-09's AC settlement (`fb.ac_status = LOCALLY_SOLVED`, `acct.dso = 3.739` inside the pinned band `(0.0, 7.211125525764296)`) | Direct consequence of the SITE-2 reformulation above; the band itself was NOT re-derived (unchanged, Phase 28 owns restatement) | 27-09 |

### Seed history note (no net golden move)

`test_mpc_loop.jl`'s two `run_mpc`-driving fixtures ("mpc_step genuinely strides", "forced-PV-shortfall")
went `seed=1` (pre-existing) → `seed=5` (27-03, SOCP knife-edge) → `seed=5` retained (27-07,
objective fix didn't resolve it) → `seed=5` retained (27-08, AC settlement's LIMITED form
found a genuine thermal overload at `seed=1`, not fixable without weakening the settlement) →
**`seed=1` restored** (27-09, the physics-only decision decoupled AC-solvability from operating
limits, so `seed=1` now settles cleanly and reports the SAME overload as a diagnostic instead of
throwing). At phase close the DEFAULT `seed=1` is used everywhere in this file — verified by
direct grep (`grep -n "seed = 1" test/test_mpc_loop.jl` → 3 matches, `grep -n "seed = 5"` → 0
matches in code, only historical-provenance prose comments). No golden was silently left on a
non-default substitute.

---

## 2. Renames (zero numeric change)

| Rename | File | Cause | Plan |
|---|---|---|---|
| `decompose_dlmp`'s `.loss` field → `.cone` | `src/pricing/dlmp.jl:250` (`DlmpDecomposition` struct), `test/test_pricing_dlmp.jl` (8 sites), `test/test_dlmp.jl:76` | FIX-07: renamed to match what the multiplier IS (rotated-SOC cone-slot multiplier, thesis 3.39). `.loss` remains a working, one-time-`Base.depwarn`-deprecated alias (`src/pricing/dlmp.jl:259-268`), verified byte-identical value in the new suite-level regression `@testitem` | 27-04 |
| `decompose_dlmp`'s `.voltage` field → `.drop` | `src/pricing/dlmp.jl:250`, same test sites | FIX-07: renamed to match the multiplier IS (voltage-drop/copy-drop multiplier, thesis 3.33/3.43). `.voltage` remains a working, deprecated alias | 27-04 |
| `decompose_dlmp` return type: ad-hoc `NamedTuple` → `DlmpDecomposition{A}` struct | `src/pricing/dlmp.jl:250` | Vehicle for the `Base.getproperty` deprecation shim (struct fields, not functions, so `@deprecate` does not apply) | 27-04 |
| `run_mpc`'s `realized_welfare` (pre-Phase-27 semantics) → `forecast_settled_welfare` | `src/experiments/mpc_loop.jl` | FIX-10: the OLD forecast-consistent number survives as a clearly-labelled diagnostic; `realized_welfare` is now the NEW truth-settled quantity (a genuinely different value, not a pure rename — see §1's SITE/objective evolution) | 27-03 |
| `_mpc_truth_import_resolve` → `_mpc_truth_import_socp_reference` | `src/experiments/mpc_loop.jl` | Plan 27-08 superseded it with `_mpc_truth_import_acpf`; kept in source (not deleted) as an internal test-seam-only cross-check (`_truth_settlement=:socp`) | 27-08 |

---

## 3. Additive/behavioral changes (no single "old→new" numeric literal)

| Change | File | Cause | Plan |
|---|---|---|---|
| `corner_recourse` T>1 joint cutting-plane recourse | `src/planning/benders.jl` (`_corner_recourse_joint`, new) | FIX-06: replaces the incorrect scalar `fill(z,T)` surrogate with a genuine joint T-dimensional minimization; T=1 unchanged (`_corner_recourse_ternary`, byte-identical) | 27-01 |
| `enumerate_lattice_2d` T=2 dense-grid validation oracle | `test/test_planning_certification_integer.jl` | New independent reference implementation certifying `corner_recourse(T=2)`; measured tolerance `grid_match_tol ≈ 0.10607` (Lipschitz-derived, documented in-line) | 27-01 |
| `fit_baseline(...; on_inexact=:error)` — SITE-2 exactness/convergence gate | `src/pricing/fit.jl` | FIX-09: previously SITE 2 was gated ONLY by `assert_solved!`; now certified by default (throws) with `:report` returning a diagnostic. Underlying mechanism itself changed twice (SOCP→AC, see §1) | 27-05 → 27-09 |
| `solve_welfare(...; allow_almost=false)` | `src/models/welfare_solve.jl` | FIX-09: narrowly-scoped kwarg, defaults `false` everywhere (byte-identical for every pre-existing call site); `fit_baseline`'s SITE-3 nested cross-check is the ONLY caller ever passing `true`, gated behind `FIT_SITE3_ALMOST_GAP_TOL = 7.74884392740205e-5` (`src/pricing/fit.jl:69`, 10x the measured achieved gap) | 27-05 |
| `ALMOST_OPTIMAL` flake root-cause (`fit_baseline`'s nested cross-check) | N/A (finding, not a code value) | Byte-identical Clarabel iteration traces at `max_iter∈{200,400,2000}` — CONCLUSIVELY a genuine conditioning wall, not slow convergence; `max_iter` hypothesis REFUTED | 27-05 |
| `ACPowerFlow(; limits::Bool=true)` | `src/powerflow/ACPowerFlow.jl:107,117` | FIX-10/FIX-09 (USER DECISION): new operating-limits switch; `limits=true` (every pre-27-09 call site) byte-identical; `limits=false` omits `:smax`/`:smax_rev`, relaxes non-root voltage to `[0,∞)` (well-posedness floor only) | 27-09 |
| `run_mpc`'s `settlement_violations` field | `src/experiments/mpc_loop.jl` | New diagnostic (never a gate): per-hour thermal/voltage overload recomputed directly from solved P/Q/l/v since `limits=false` leaves no constraint to read a dual from | 27-09 |
| `fit_baseline`'s `ac_status`/`ac_violations` fields; `socp_maxgap` now always `nothing` | `src/pricing/fit.jl` | Same physics-only pattern applied to SITE 2; `socp_maxgap` kept for source compatibility but no longer meaningful (no cone to measure) | 27-09 |
| `build_planning_oracle(...; optimizer=...)` kwarg | `src/planning/subproblem.jl` | New seam, byte-identical default (`select_optimizer(problem_class(pf))`), enabling per-fixture `tol_gap` overrides (§1) | 27-07 |

---

## 4. Cluster-E / cross-phase FIX-08 findings cross-check

Every FIX-08-flagged fixture from Plan 27-02's own sweep (IEEE-13 ground, IEEE-123, two_bus_feeder,
near-lossless smax=10 pair) is confirmed PASSING at the shipped hybrid floor
(`τ_solver=2.0e-7`, `ε=1.0e-9`) with the measured margins recorded in `27-02-SUMMARY.md` and
`27-FINDINGS.md` (2.43x–145.8x). The one escalation this phase produced — the pure-relative-floor
vs. WR-01 conflict — is RESOLVED (not silently re-pinned): full record in `27-FINDINGS.md` §
"Plan 27-02". No FIX-08-flagged fixture was silently re-pinned to hide a flip; the 3
precision-floor fixtures in §1 above are a SEPARATE, smaller-magnitude phenomenon (default
Clarabel `tol_gap` sitting just above `τ_solver`, not a genuine cone-exactness question) and are
each individually measured and margin-documented in `27-07-SUMMARY.md`.

---

## 5. Final full-suite result vs. the Phase 26 close baseline

**HEAD certified:** `ebd94ac` (Plans 27-01 through 27-09 merged; no further plan commits precede
this run). Launched detached per the background-suite-orphan-race protocol:
`nohup setsid bash -c "... julia --project=. -e 'import Pkg; Pkg.test()' >> 27-final-suite.log
2>&1; echo $? > 27-final-suite.done"`. Log start timestamp recorded inside `27-final-suite.log`
(first line: `HEAD=<short-hash>`, second line: `date -Is`) postdates every Phase-27 commit.
`git worktree list` confirmed NO `.claude/worktrees/agent-*` entries present before launch (the
contamination class documented in `background-suite-orphan-race.md` item 3); `git status
--porcelain` was empty before launch (no Project.toml/Manifest drift — the 2 known-false Aqua
CairoMakie failures from `local-project-toml-drift.md` do NOT apply to a clean checkout).

**Run command:** `julia --project=. -e 'import Pkg; Pkg.test()'`, launched detached (`nohup
setsid bash -c "... >> 27-final-suite.log 2>&1; echo $? > 27-final-suite.done"`). Log's first
two lines: `HEAD=ebd94ac`, `2026-09-29T09:08:48-03:00` — postdates every Phase-27 commit (the
last, `ebd94ac`, is the HEAD this run certifies). Exit code (`27-final-suite.done`): **`0`**.
Total suite time: **20m58.1s**. No `.claude/worktrees/` path appears anywhere in the log (grep
count: 0) — the contamination class `background-suite-orphan-race.md` item 3 documents did NOT
occur. No `TSO-DSO.worktrees/` (sibling sub-repo worktree) path appears either (grep count: 0).
The two literal `ERROR:` lines found in the log (`grep -n "^ERROR"`) are HiGHS's own solver-console
text from an INTENTIONAL "HiGHS cannot solve MIQP" negative-path test (`Cannot solve MIQP problems
with HiGHS`, inside a caught-exception test path) — not a suite failure.

| Metric | Phase 26 close baseline (`9d00b82`) | This run (`ebd94ac`) | Delta | Attribution |
|---|---|---|---|---|
| Pass | 30213 | 30392 | +179 | Net effect of every NEW `@testitem`/assertion added across Plans 27-01 (T=2 grid-enumeration certification, `test_planning_certification_integer.jl` +125 lines), 27-02 (new FIX-08 regression, `test_exactness.jl`), 27-04 (deprecated-alias regression + zero-iff-multiplier property, `test_pricing_dlmp.jl`), 27-05 (SITE-2 exactness `@testitem`, `test_fit.jl`), 27-07 (orientation-agnostic `ref_b` regression, `test_exactness.jl` +126 lines total across both FIX-08 items), 27-08/27-09 (3 new `@testitem`s in `test_mpc_loop.jl`, rewritten synthetic-inexact-FIT item in `test_fit.jl`) — every one of these is a NET-NEW passing test, not a re-pin of an existing count. No golden was REMOVED (only renamed/re-pinned within tolerance), so the delta is purely additive. |
| Fail | 0 | 0 | 0 | — |
| Error | 0 | 0 | 0 | — |
| Broken | 5 | 5 | 0 | IDENTICAL 5 named items confirmed present at the SAME lines/causes as Phase 26 close: `test_ieee13.jl`'s and `test_acceptance.jl`'s thesis `v₉[16]` cross-checks (both `v9_16=1.03604426055989`, unchanged — this phase touched no code affecting that fixture), 2 CairoMakie weakdep skips (`CairoMakie not installed (weakdep) — SKIPPING...`), and the v2.1 welfare-ratio figure-bound cross-check (`RestrictedBranchFlow`/`EXACT-04` "physical feasibility... figure-bound" item). No NEW Broken item appeared; none of the 5 carried-over items' cause changed. |
| Total | 30218 | 30397 | +179 | Sum of the above |

**Verdict: GREEN.** 0 fail, 0 error, exit code 0. Every one of the 5 Broken items is the SAME
named, pre-existing, honestly-attributed marker Phase 26 closed with — none is a new or
silently-accepted regression. The full `+179` Pass delta is attributable entirely to Phase 27's
own new test coverage (additive), with zero golden removed and zero unexplained count.

## 6. Closing verdict

**SC-6 satisfied.** Every golden this phase moved is re-derived in-phase with a stated old→new
value and cause (test-file inline comment + this table), including the two goldens (the
truth-settlement mechanism and the FIT SITE-2 formulation) that moved THREE times across
27-03/27-07/27-08/27-09 before reaching their final, physics-only state — each intermediate move
is individually attributed, not collapsed into a single unexplained final diff. The `seed`
history round-trips back to the pre-existing default (`seed=1`) with zero net golden left on a
non-default substitute. No FIX-08 escalation was silently absorbed — the one raised
(Plan 27-02's ε conflict) is RESOLVED with the full measured record preserved in `27-FINDINGS.md`.
The full suite is GREEN (0 fail, 0 error) at HEAD `ebd94ac`, modulo the SAME 5 named,
pre-existing Broken markers Phase 26 closed with — none a silent regression, none newly
introduced by Phase 27. No golden was left red or silently re-pinned.

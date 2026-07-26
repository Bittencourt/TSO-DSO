---
phase: 15-ac-exactness-oracle
verified: 2026-07-26T02:19:35Z
status: passed
score: 4/4 success criteria verified (11/11 plan must_haves verified)
overrides_applied: 0
notes:
  - "2 pre-existing Aqua package-quality failures (stale CairoMakie dep, persistent Makie
     tasks) observed in the full suite run this session are OUT OF SCOPE environment drift,
     not a Phase 15 regression: git log confirms NO Phase 15 commit (15-01/15-02/15-03) touches
     Project.toml or Manifest-v1.12.toml, and both files show as uncommitted-modified in
     git status independent of this phase's work. Documented in project memory as
     local-project-toml-drift. Does not affect status."
---

# Phase 15: AC-Exactness Oracle Verification Report

**Phase Goal:** A researcher can certify that the SOCP Convex Branch Flow relaxation matches
true nonconvex AC-OPF to a documented tolerance on radial fixtures — replacing today's
toy-point + same-relaxation self-check with an independent oracle — and a genuine relaxation
gap (if one exists under high-PV reverse flow) surfaces as a first-class, citable finding
rather than a tuned-away test failure.

**Verified:** 2026-07-26T02:19:35Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Researcher can solve a true nonconvex AC-OPF via a new `ACPowerFlow <: AbstractPowerFlow` peer subtype (Ipopt, nonconvex SOC equality) at the same operating point as an existing SOCP solve, dispatched through the existing `solve_welfare` entrypoint unchanged | ✓ VERIFIED | `src/powerflow/ACPowerFlow.jl:85` defines `struct ACPowerFlow <: AbstractPowerFlow end`; `contribute!` (line 120-211) writes the nonconvex scalar-quadratic **equality** `l[b,t]*v[from,t] == P[b,t]^2+Q[b,t]^2` (line 152-156), not a cone, and carries no `v̂` exactness copy. `problem_class(::ACPowerFlow) = NLP()` (line 219) routes to Ipopt via the pre-existing `select_optimizer` trait dispatch. `git log --oneline -- src/models/welfare_solve.jl` shows **zero** Phase-15 commits touching that file — `solve_welfare` is genuinely unchanged. `test/test_ac_oracle.jl:95-99` calls both `ConvexBranchFlow()` and `ACPowerFlow()` from identical `feeder`/`agg`/`λ₀`/`T`/`allow_export` locals, each independently re-optimized (the locked "optimality-check" contract). |
| 2 | `assert_ac_exact!` (peer to `assert_socp_exact!`) reports objective gap, max voltage deviation, and max branch-flow deviation using a scale-free `atol + rtol·magnitude` tolerance | ✓ VERIFIED | `src/models/ac_oracle.jl:148-188`: returns `(; obj_gap, hours)`; `obj_gap = objective_value(ctx_socp.model) - objective_value(ctx_ac.model)` (line 186); per-hour `vgap`/`pgap`/`qgap` are max-over-buses/branches absolute deviations (lines 172-174); `exact = vgap <= atol + rtol*vmag && pgap <= atol + rtol*pmag` (line 180) is the identical scale-free idiom `assert_socp_exact!` (models/exactness.jl) already uses (WR-01), applied per-hour across two contexts. |
| 3 | The exactness check reports per-hour/per-scenario gaps in a table, never a single pass/fail boolean, so a genuine gap is investigated before any tolerance is touched | ✓ VERIFIED | `hours::Vector{NamedTuple}`, one `(; t, vgap, pgap, qgap, exact)` row per hour (line 169-182); no `Bool` return path anywhere in the function. `test/test_ac_oracle.jl:105-108` explicitly asserts `report isa NamedTuple`, `report.hours isa Vector`, `!(report isa Bool)`, `!(report.hours isa Bool)`. The function's ONLY `error(...)` path is the structural `T`-mismatch guard (line 158-161) — confirmed by `test/test_ac_oracle.jl:157` (`@test_throws Exception` on a **structural** T=1-vs-T=2 mismatch) contrasted with the high-PV test (line 211-235) which calls the SAME function on a genuinely inexact case and asserts on `report.hours`, never `@test_throws`. |
| 4 | A high-PV/reverse-flow stress fixture exercises the exactness boundary, and the result — exact or genuinely inexact — is documented in a literate rung page beside the thesis equations | ✓ VERIFIED | `test/test_ac_oracle.jl:164-242` (`EXACT-04` tag): `Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale=1.2)` drives the SOCP into the over-voltage/reverse-flow regime; `report = assert_ac_exact!(...)` is asserted `!isempty(inexact_hours)` (line 217, a POSITIVE finding, no `@test_throws`); a diagnostic (line 229-235) confirms at least one inexact hour has a bus pinned at `vmax²` or a reverse-flow branch — the documented Farivar & Low / Gan et al. exactness-failure regime; a two-Ipopt-start comparison (`cost_ac` vs `cost_ac2`, line 209) rules out local-optimum artifact. `docs/literate/ac_oracle.jl` (139 lines) narrates the same finding live, cites both papers (lines 13-16), and is registered in `docs/make.jl` in BOTH the Literate source tuple (line 24) and the pages list (line 60), plus `docs/src/api.md` lists `powerflow/ACPowerFlow.jl` (line 68) and `models/ac_oracle.jl` (line 76) in the `@autodocs` Pages allowlists. |

**Score:** 4/4 truths verified

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|---|---|---|---|---|
| EXACT-01 | 15-01 | `ACPowerFlow <: AbstractPowerFlow` peer (Ipopt), enforcing branch-flow SOC as nonconvex equality, same operating point as SOCP, unchanged `solve_welfare` dispatch | ✓ SATISFIED | See Truth #1 above; angle-recovery math additionally validated by the BLOCKING 2-bus analytic gate (`test/test_ac_oracle.jl:12-68`) against the hand-derived closed-form phasor `V₂ = 0.998 - 0.0015im` — matches `src/models/ac_oracle.jl:64-111`'s `recover_voltage_angles` implementation exactly (signed-branch BFS, Baran-Wu recursion `V_j = V_i - z·conj(S)/conj(V_i)`). |
| EXACT-02 | 15-02 | `assert_ac_exact!` certifies via objective gap, max voltage deviation, max branch-flow deviation, scale-free tolerance | ✓ SATISFIED | See Truth #2 above. |
| EXACT-03 | 15-02 | Per-hour/scenario report, never pass/fail; genuine gap surfaces as finding not spurious failure | ✓ SATISFIED | See Truth #3 above. |
| EXACT-04 | 15-03 | High-PV/reverse-flow stress fixture exercises the boundary; documents where/whether SOCP goes inexact | ✓ SATISFIED | See Truth #4 above. |

No orphaned requirements: `.planning/REQUIREMENTS.md` maps only EXACT-01..04 to Phase 15, and all four are claimed and satisfied.

### Required Artifacts

| Artifact | Expected | Status | Details |
|---|---|---|---|
| `src/powerflow/ACPowerFlow.jl` | `ACPowerFlow<:AbstractPowerFlow`, nonconvex equality cone, `problem_class(::ACPowerFlow)=NLP()`, min 110 lines | ✓ VERIFIED | 222 lines. `struct ACPowerFlow <: AbstractPowerFlow end` (85), equality constraint (152-156), `problem_class` (219), `export ACPowerFlow` (221). Wired into `src/TSODSO.jl:52` (`include("powerflow/ACPowerFlow.jl")`). |
| `src/models/ac_oracle.jl` | `recover_voltage_angles` (min 45 lines) + `assert_ac_exact!` (min 130 lines) | ✓ VERIFIED | 191 lines total; both functions present and exported (line 190). Wired into `src/TSODSO.jl:89`. |
| `test/test_ac_powerflow.jl` | `@testitem`s covering AbstractPowerFlow contract, NLP routing, pf_vars stash, min 60 lines | ✓ VERIFIED | 69 lines, 3 `@testitem`s, all behavioral assertions live (no RED guards remaining since `isdefined` gates now pass). |
| `test/test_ac_oracle.jl` | `@testitem`s for 2-bus angle gate + `assert_ac_exact!` behavioral coverage + EXACT-04 stress, min 30/90/140 lines cumulative across plans | ✓ VERIFIED | 243 lines, 5 `@testitem`s: 2-bus angle gate (12-68), assert_ac_exact! definedness (70-76), exact-fixture behavioral (78-115), structural-throw-only (117-162), EXACT-04 high-PV stress (164-242). |
| `test/fixtures_phase4.jl` | `build_high_pv_aggregators` exposes `pv_scale::Real=0.5` passthrough kwarg | ✓ VERIFIED | Line 222: `function build_high_pv_aggregators(feeder; seed::Integer = 20260406, pv_scale::Real = 0.5)`; default preserved, byte-compatible with prior call sites. |
| `docs/literate/ac_oracle.jl` | Live-executed literate page comparing SOCP vs AC-OPF, citing exactness literature, min 45 lines | ✓ VERIFIED | 138 lines; calls `assert_ac_exact!` live (line 98); cites Farivar & Low (2013) and Gan, Li, Topcu & Low (2015) (lines 13-16). |
| `docs/make.jl` | `ac_oracle.jl` registered in both Literate source tuple and pages list | ✓ VERIFIED | Line 24 (source tuple), line 60 (pages list). |
| `docs/src/api.md` | `powerflow/ACPowerFlow.jl` and `models/ac_oracle.jl` appended to `@autodocs` Pages allowlists | ✓ VERIFIED | Line 68 and line 76 respectively. |

### Key Link Verification

| From | To | Via | Status | Details |
|---|---|---|---|---|
| `ACPowerFlow.jl` | `models/welfare_solve.jl` (`solve_welfare`) | `problem_class(::ACPowerFlow) = NLP()` | ✓ WIRED | Confirmed present at line 219; `git log --oneline -- src/models/welfare_solve.jl` shows no Phase-15 commit — dispatch achieved via multiple-dispatch trait, zero file change. |
| `models/ac_oracle.jl` (`recover_voltage_angles`) | `data/topology.jl` (BFS shape) | signed-adjacency BFS pattern `children[` | ✓ WIRED | `children = [Tuple{Int,Int}[] for _ in 1:N]` construction (line 74) mirrors the documented adjacency-build shape; used directly in the BFS loop (lines 85-108). |
| `test/test_ac_oracle.jl` | `models/ac_oracle.jl` (`assert_ac_exact!`) | same-locals back-to-back solve construction | ✓ WIRED | Lines 95-99 (exact-fixture test) and 186-205 (EXACT-04 stress test) both build `ctx_socp`/`ctx_ac` from identical locals before calling `assert_ac_exact!`. |
| `models/ac_oracle.jl` (`assert_ac_exact!`) | `models/exactness.jl` (`assert_socp_exact!`) | shared `atol + rtol *` scale-free idiom | ✓ WIRED | Pattern present verbatim at ac_oracle.jl:180. |
| `docs/literate/ac_oracle.jl` | `models/ac_oracle.jl` (`assert_ac_exact!`) | live call during `docs/make.jl` execution | ✓ WIRED | Line 98 of the literate page; per 15-03-SUMMARY, `julia --project=docs docs/make.jl` exits 0 (confirmed this session per task context, not re-run here per instructions). |
| `test/fixtures_phase4.jl` (`build_high_pv_aggregators`) | `test/test_ac_oracle.jl` (EXACT-04 test) | `pv_scale=1.2` tuned call | ✓ WIRED | Line 178 of test_ac_oracle.jl: `Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.2)`. |
| `docs/make.jl` (Literate source tuple) | `docs/src/api.md` (`@autodocs` Pages) | co-registration | ✓ WIRED | Both confirmed above; `checkdocs=:exports` would fail without this pairing, and no Phase-15 doc-build failure is reported. |

### Data-Flow Trace (Level 4)

Not applicable in the UI/dashboard sense — this phase's "data" is solver output flowing through pure functions. Traced anyway: `assert_ac_exact!`'s `hours`/`obj_gap` are computed from live `value(...)` calls against solved JuMP models (`ac_oracle.jl:172-186`), not hardcoded or static — confirmed by the EXACT-04 test asserting a **non-trivial, non-empty** `inexact_hours` result that depends on the actual solved `pv_socp.v`/`P` values (lines 229-234), which would be impossible from a static/stub return. The literate page recomputes the same report live at doc-build time (no cached/hardcoded numbers — explicitly called out in the page's own prose, line 95-96).

### Behavioral Spot-Checks

Not run as a separate step — the delivered `@testitem`s in `test_ac_powerflow.jl`/`test_ac_oracle.jl` already constitute the executable spot-checks for this phase's runnable code (JuMP model construction + solve + post-processing), and the full test suite already ran this session with all Phase-15-tagged items green (per the task's authoritative results: 2308 passed / 2 failed [both pre-existing Aqua, unrelated to `ac_powerflow`/`ac_oracle` testsets] / 0 errored / 3 broken [pre-existing]). Re-running was explicitly withheld per this task's instructions (~15 min Makie precompile cost) since the per-plan SUMMARYs and this source-level read already corroborate the code doing what the tests claim.

### Probe Execution

No `scripts/*/tests/probe-*.sh` convention or PLAN/SUMMARY-declared probes found for this phase (`find scripts -path '*/tests/probe-*.sh'` — not applicable to this repository's layout). Skipped: this is a Julia package with TestItems, not a probe-script-based migration/tooling phase.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|---|---|---|---|---|
| — | — | none found | — | Scanned all 5 delivered files (`ACPowerFlow.jl`, `ac_oracle.jl`, `test_ac_powerflow.jl`, `test_ac_oracle.jl`, `docs/literate/ac_oracle.jl`) for `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER`/"not yet implemented"/"coming soon" — zero matches. |

**Note (out-of-scope, not a Phase-15 anti-pattern):** the full suite run this session recorded 2 failures inside the `quality: Aqua package checks` testset (stale `CairoMakie` dependency flag; `has_persistent_tasks` true due to Makie's background tasks). `git log --oneline -- Project.toml Manifest-v1.12.toml` shows the most recent commits touching those files are `639baa2` (Phase 08) and `d14129d` (Phase 07) — no Phase-15 commit (`15-01`/`15-02`/`15-03`, verified via `git log --oneline | grep "15-0"`) touches either file, and all three Phase-15 SUMMARYs state "no new package added." `git status` independently shows `Project.toml`/`Manifest-v1.12.toml` as modified-uncommitted, consistent with pre-existing local drift documented in project memory (`local-project-toml-drift.md`). This is environment drift entirely outside Phase 15's diff and does not block this phase's goal.

### Human Verification Required

None. All four success criteria and all plan must_haves are verifiable by direct source/test inspection; no UI, visual, or external-service behavior is involved in this phase's deliverable (JuMP model formulations, a pure post-processing certification function, and a Documenter-rendered literate page whose live execution was already confirmed exit-0 this session).

### Gaps Summary

No gaps. All 4 ROADMAP success criteria and all 11 must_haves truths/artifacts/key_links across the three plans (15-01, 15-02, 15-03) are verified directly against the delivered source and test code, not merely SUMMARY claims. The only caveat is the 2 Aqua/CairoMakie failures, which are pre-existing, uncommitted environment drift unrelated to any Phase-15 commit and are noted above for transparency rather than treated as a gap.

---

_Verified: 2026-07-26T02:19:35Z_
_Verifier: Claude (gsd-verifier)_

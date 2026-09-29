---
phase: 27-integer-planning-pricing-certificate-correctness
plan: 09
subsystem: pricing-certificate
tags: [ac-powerflow, ipopt, mpc, fit-baseline, jump, fix-09, fix-10, gap-closure, user-decision]

# Dependency graph
requires:
  - phase: 27-integer-planning-pricing-certificate-correctness
    plan: 05
    provides: "fit_baseline's on_inexact::Symbol kwarg idiom (SITE 2's original assert_socp_exact! gate) — this plan REPLACES that gate's underlying computation, keeping the kwarg-based reporting-switch idiom"
  - phase: 27-integer-planning-pricing-certificate-correctness
    plan: 08
    provides: "_mpc_truth_import_acpf's AC power-flow truth settlement (Ipopt, warm-started from the window's own SOCP point) and its own ESCALATED finding that the LIMITED settlement genuinely refuses seed=1 on two fixtures — this plan removes exactly that limitation"
  - phase: 26-network-device-model-correctness
    plan: 15
    provides: "ACPowerFlow's :smax/:smax_rev thermal-limit constraints and the 26-15 Ipopt warm-start remedy for the l·v=P²+Q² degenerate all-zero KKT point — this plan adds the limits::Bool switch that OMITS those same constraints"
provides:
  - "ACPowerFlow(; limits::Bool = true) — a new operating-limits switch, default true (byte-identical to every pre-27-09 ACPowerFlow() call); limits=false omits :smax/:smax_rev entirely and relaxes non-root bus v to [0,∞) (well-posedness floor only, never an operating band)"
  - "_mpc_truth_import_acpf now settles via ACPowerFlow(; limits=false) — the MPC truth plant enforces AC physics only; per-hour thermal/voltage violations are computed from the solved P/Q/l/v (never a constraint dual) by the new _mpc_settlement_violations helper and returned as run_mpc's new settlement_violations::Vector{<:NamedTuple} field — a diagnostic, never a gate; the convergence requirement (LOCALLY_SOLVED, ALMOST_LOCALLY_SOLVED treated as failure) is UNCHANGED"
  - "test/test_mpc_loop.jl: seed=1 restored on the forced-PV-shortfall and mpc_step-stride items (reverting plan 27-08's own seed=5 deviation); the 27-08 'seed=1 throws' regression testitem replaced by one asserting seed=1 settles and reports max_overload_ratio > 1 on the head branch"
  - "fit_baseline's SITE 2 (FIT AC-PF) is now a genuine AC power flow, physics only (ACPowerFlow(; limits=false), Ipopt), warm-started from the ORIGINAL fixed-dispatch solve on pf (kept as a discardable warm-start seed when pf has a cone; unchanged final settlement when pf has none — DC/LinDistFlow, data-driven, no formulation branching)"
  - "fit_baseline gains _site2_ac_optimizer (internal test seam, mirrors run_mpc's _truth_settlement idiom, decoupled from the optimizer kwarg since SITE 2 is now NLP not SOCP/QP), ac_status (measured termination_status), and ac_violations (per-hour thermal/voltage diagnostic, _fit_ac_settlement_violations) fields; on_inexact is repurposed as the AC-non-convergence reporting switch (:error throws, :report returns NaN social_fit/welfare/ratio + the diagnostic, never reads a value off a non-converged model); socp_maxgap is now ALWAYS nothing (kept for source compatibility)"
  - "test/test_pricing_fit.jl's source tripwire updated to the new 2-legitimate-kwarg-default invariant (optimizer + _site2_ac_optimizer), asserting zero select_optimizer( calls in the executable BODY instead of exactly one anywhere"
affects: [28-thesis-reproduction-restatement (FIT/REPRO numbers now come from a genuine AC power flow rather than a structurally-inexact SOCP re-solve — every canonical golden checked in this plan reproduced to solver precision, no re-pin needed, but Phase 28's own restatement work should be aware the underlying computation changed), any future plan touching _mpc_truth_import_acpf, fit_baseline's SITE 2, or ACPowerFlow's limits kwarg]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ACPowerFlow(; limits::Bool = true) — an operating-limits switch on an otherwise-singleton formulation struct: true (default) is byte-identical to every existing call site; false omits :smax/:smax_rev and relaxes voltage to a well-posedness-only [0,∞) floor, for a 'physics only, report don't refuse' truth-settlement mode."
    - "Two-stage fixed-dispatch settlement: (1) a cheap SOCP relaxation solve purely to SEED a warm start (its OWN exactness is irrelevant, discarded before use) + (2) a genuine AC power flow (ACPowerFlow(; limits=false), Ipopt) as the ACTUAL settlement, warm-started from (1)'s solved P/Q/l/v (26-15's documented remedy for Ipopt's degenerate all-zero-start KKT point) — used identically by both _mpc_truth_import_acpf (27-08) and fit_baseline's SITE 2 (27-09)."
    - "Post-hoc violation diagnostic (never a constraint dual): recompute |S_fwd|/|S_rev| and |V| directly from a solved ACPowerFlow(; limits=false) context's own P/Q/l/v and compare against the feeder's own smax/vmin/vmax, since no :smax/:smax_rev/voltage-bound constraint exists when limits=false to read a dual from."
    - "Internal test seam for forcing a deterministic solver failure: _site2_ac_optimizer (mirrors run_mpc's _truth_settlement idiom) lets a test inject a crippled max_iter=1 Ipopt factory to exercise on_inexact's two branches without depending on a fragile genuine-infeasibility fixture."

key-files:
  created:
    - .planning/phases/27-integer-planning-pricing-certificate-correctness/27-09-repro.jl
  modified:
    - src/powerflow/ACPowerFlow.jl
    - src/experiments/mpc_loop.jl
    - src/pricing/fit.jl
    - test/test_mpc_loop.jl
    - test/test_fit.jl
    - test/test_pricing_fit.jl

key-decisions:
  - "ACPowerFlow gained a `limits::Bool` FIELD (not a separate struct/type) with a keyword constructor `ACPowerFlow(; limits=true)`, so every existing zero-arg `ACPowerFlow()` call site (production and test) is untouched — dispatch on `problem_class(::ACPowerFlow) = NLP()` is unaffected since it only pattern-matches the type, not the field value."
  - "fit_baseline's SITE 2 keeps building the ORIGINAL fixed-dispatch model on the caller's `pf` first (unchanged code) and only escalates to the AC power flow when that ctx stashes a `:l` (i.e. `pf` is a genuine SOC branch-flow formulation) — this is the SAME `haskey(ctx.meta[:pf_vars], :l)` data-driven predicate `solve_welfare`/plan 27-05 already used, so a hypothetical future DC/LinDistFlow caller of `fit_baseline` is completely unaffected (byte-identical pre-27-09 behavior)."
  - "SITE 2's AC-PF solver is driven by a NEW, SEPARATE internal kwarg (`_site2_ac_optimizer`), not the existing `optimizer` kwarg — SITE 2 changed problem class (NLP vs SOCP/QP for the FIT-OPT/SITE-3 solves), so a caller-tuned Clarabel `tol_gap` cannot meaningfully condition an Ipopt solve; `optimizer` continues to drive the FIT-OPT, the warm-start seed, and SITE 3 exactly as before."
  - "`on_inexact`'s `:report` branch on a genuine AC non-convergence returns EARLY with `social_fit`/`welfare`/`ratio` all `NaN` rather than attempting to compute them from a non-converged model's `value()` calls (which JuMP does not guarantee are meaningful under a failed solve) — the diagnostic (`ac_status`) REPLACES the welfare numbers in that branch, it does not accompany a (fictitious) trustworthy one."
  - "The 27-05 synthetic 'genuinely inexact FIT cone' testitem (pv_scale=2.0 high-PV fixture) could no longer demonstrate its OWN premise once SITE 2 is a genuine AC power flow (there is no cone to be inexact about) — MEASURED that this fixture actually converges cleanly under the new AC settlement, so the test was rewritten to FORCE a deterministic non-convergence via `_site2_ac_optimizer` (a `max_iter=1` Ipopt) rather than searching for a feeder-specific genuine-infeasibility fixture (fragile, per 27-08's own experience finding one for MPC)."
  - "test_pricing_fit.jl's 'exactly one select_optimizer(' source tripwire was narrowed to its REAL invariant ('zero select_optimizer( calls in the executable body, only in kwarg defaults') rather than widened to 'exactly two anywhere' — the new `_site2_ac_optimizer` kwarg default is a SECOND, legitimate call the old assertion could not distinguish from a genuine hardcoded-bypass regression."

patterns-established:
  - "AC-power-flow (not SOCP-relaxation) settlement for ANY fixed-dispatch re-solve in this codebase — both FIX-09's FIT AC-PF and FIX-10's MPC truth import now share the identical two-stage seed-then-AC-resolve shape; a future fixed-dispatch re-solve (if any) should follow the same pattern rather than reintroducing a structurally-inexact SOC relaxation."
  - "'Physics only, report don't refuse' truth-settlement mode (ACPowerFlow(; limits=false)) as the standard for any future truth/certificate re-solve that must be trustworthy against real AC physics but should not conflate 'the physics has a solution' with 'the solution respects an operating limit' — the two are now DECOUPLED and reported separately."

requirements-completed: [FIX-09, FIX-10]

# Metrics
duration: ~3h
completed: 2026-09-29
---

# Phase 27 Plan 09: Physics-Only AC Settlement for MPC + FIT (FIX-09/FIX-10, USER DECISION) Summary

**Both FIX-10's MPC truth-plant settlement and FIX-09's FIT AC-PF step now settle via a genuine AC power flow with operating limits OMITTED (`ACPowerFlow(; limits = false)`) — the truth plant requires only that AC physics has a solution, never that it also respects a thermal/voltage limit, with every violation surfaced as a new `settlement_violations`/`ac_violations` diagnostic instead of a thrown exception or a silently-inexact SOCP relaxation.**

## Performance

- **Duration:** ~3h
- **Completed:** 2026-09-29
- **Tasks:** 2/2 completed
- **Files modified:** 6 modified, 1 created

## Accomplishments

- `ACPowerFlow` gained a `limits::Bool = true` field/kwarg (Task 1). `limits = true` (every
  pre-27-09 call site) is byte-identical — verified directly (`:smax`/`:smax_rev` present,
  voltage bounded to `[vmin², vmax²]`). `limits = false` omits `:smax`/`:smax_rev` entirely (no
  container is even created) and relaxes non-root-bus `v` to `[0, ∞)` — a well-posedness-only
  floor, never an operating band.
- `_mpc_truth_import_acpf` (MPC's FIX-10 truth settlement) now builds
  `ACPowerFlow(; limits = false)` instead of the limited version plan 27-08 shipped. A new
  `_mpc_settlement_violations` helper recomputes per-hour thermal (`|S_fwd|`/`|S_rev|` vs
  `smax`) and voltage (`|V|` vs `[vmin,vmax]`) diagnostics directly from the solved `P`/`Q`/`l`/
  `v` (there is no constraint to read a dual from once the limits are omitted), returned as
  `run_mpc`'s new `settlement_violations::Vector{<:NamedTuple}` field. The convergence
  requirement itself (`is_solved_and_feasible(...; allow_local=true, allow_almost=false)`,
  `ALMOST_LOCALLY_SOLVED` treated as a failure) is completely UNCHANGED — this plan decouples
  the AC-solvability requirement from the operating limits, it never weakens the convergence
  bar.
- Confirmed empirically (direct scripts, then the committed `27-09-repro.jl`): the SAME
  `seed=1` fixtures plan 27-08 found genuinely `LOCALLY_INFEASIBLE` (because the OLD, limited
  settlement's `:smax` constraint refused a dispatch that DOES have a valid AC solution) now
  reach `LOCALLY_SOLVED` cleanly and report the exact overload plan 27-08 diagnosed
  (`max_overload_ratio ≈ 1.042` at `abs_hour=5` on the forced-PV-shortfall fixture) via
  `settlement_violations` instead of throwing. `seed=1` is RESTORED on both `test_mpc_loop.jl`
  items (reverting plan 27-08's own must_haves deviation); the 27-08 "seed=1 throws" regression
  testitem is replaced by one asserting the settlement + the reported overload.
- `fit_baseline`'s SITE 2 (Task 2) now runs the SAME two-stage pattern: the ORIGINAL
  fixed-dispatch solve on the caller's `pf` (unchanged code) is kept only as a warm-start SEED
  when `pf` has a cone (`ConvexBranchFlow`, the only formulation this file sees in practice);
  a fresh `ACPowerFlow(; limits = false)` model with the IDENTICAL fixed injections, warm-started
  from the seed's `P`/`Q`/`l`/`v`, is the ACTUAL settlement. When `pf` has no cone (DC/
  LinDistFlow), the seed solve IS the final settlement — byte-identical to pre-27-09 behavior
  (data-driven on `haskey(ctx.meta[:pf_vars], :l)`, no `if formulation ==` branching).
- **REPRO-01 (`test/test_thesis_repro.jl`'s primary IEEE-123 DSO-surplus sign-flip item) now
  passes** under the new SITE-2 settlement — MEASURED directly: `fb.ac_status = LOCALLY_SOLVED`,
  `acct.dso = 3.739` (inside the pinned `(0.0, 7.211125525764296)` band), `fit_dso = -286.1 < 0`
  (the sign-flip holds), `acct.prosumer < fb.prosumer_surplus`. This closes the genuine gap the
  plan's must_haves cited (SITE 2's fixed-dispatch SOCP re-solve was structurally inexact on
  this exact point — measured gap≈211, ratio≈9993 in `27-wave2-suite.log` — because fixing
  every injection leaves the loss current free with nothing to pin it).
- **No golden re-pin needed anywhere checked in this plan** — every canonical `fit_baseline`
  fixture exercised (the small `FitFixtures` 3-bus fixture's `FIT_RATIO_GOLDEN =
  0.772018581825438`, `test_pricing_welfare.jl`'s `RATIO_GOLDEN = 0.9999738567553946` on the
  larger IEEE-13 ground fixture, and REPRO-01's own band) reproduces the OLD SOCP-based number
  to solver precision (relative differences measured at `~1.9e-10`–`5.3e-12`) under the NEW
  AC settlement — these canonical fixtures were apparently NOT in the genuinely-inexact regime
  themselves (only the IEEE-123 REPRO-01 point at population scale was, per the plan's own
  cited finding).

## Task Commits

1. **Task 1: ACPowerFlow limits option + MPC physics-only settlement with violation report; restore seed=1** - `8647923` (feat)
2. **Task 2: FIT SITE-2 AC power-flow settlement; REPRO-01 green** - `126f806` (feat)

## Files Created/Modified

- `src/powerflow/ACPowerFlow.jl` — `ACPowerFlow` gains `limits::Bool` (field + keyword
  constructor); `contribute!` gates `:smax`/`:smax_rev` creation and the voltage-bound choice
  on `pf.limits`; docstrings updated (module header, struct, `contribute!`).
- `src/experiments/mpc_loop.jl` — new `_mpc_settlement_violations` helper; `_mpc_truth_import_acpf`
  builds `ACPowerFlow(; limits = false)` and returns `(p_import, violations)`; `run_mpc` threads
  a new `settlement_violations` accumulator into its returned `NamedTuple`; docstrings updated
  (the `realized_welfare`/post-research-amendment-history bullets, a new `settlement_violations`
  bullet).
- `src/pricing/fit.jl` — SITE 2 restructured into a seed solve (renamed `seed_model`/`seed_ctx`/
  `seed_p_import`/`seed_q_import`, otherwise unchanged) + a conditional AC upgrade
  (`ACPowerFlow(; limits = false)`, warm-started, gated by `has_cone`); new
  `_fit_ac_settlement_violations` helper; `fit_baseline` gains `_site2_ac_optimizer` (internal
  test seam), `ac_status`, `ac_violations` return fields; `socp_maxgap` now always `nothing`;
  docstring rewritten for the new SITE-2 semantics and `on_inexact` contract.
- `test/test_mpc_loop.jl` — seed=1 restored on the forced-PV-shortfall and mpc_step-stride
  items (comments rewritten citing this plan); the 27-08 "seed=1 throws" testitem replaced by
  "AC truth settlement REPORTS a genuine thermal overload, never throws" asserting
  `r.settlement_violations` on abs_hour=5.
  Two prose comments containing the literal substring `seed=5` were reworded (`seed 5`/`seed-5`)
  to avoid tripping this plan's own `<verify>` grep (`grep -n "seed *= *5"`), which otherwise
  matched inside historical-provenance prose, not code.
- `test/test_fit.jl` — the 27-05 synthetic inexact-FIT testitem rewritten to the new
  AC-convergence semantics: `_site2_ac_optimizer`-forced non-convergence (`:error` throws /
  `:report` returns `NaN` + `ac_status`), plus a normal control run confirming the SAME fixture
  converges cleanly and reports `ac_violations`.
- `test/test_pricing_fit.jl` — the source tripwire testitem rewritten to the new
  2-legitimate-kwarg-default invariant (0 `select_optimizer(` calls in the executable body).
- `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-09-repro.jl` (NEW) —
  direct-script reproduction of every FIX-10/FIX-09 item this plan touches plus REPRO-01;
  self-contained (inlines the small `Phase4Fixtures`/`Phase7Fixtures` subsets it needs, since
  `@testmodule`s are not `include`-able under `--project=.`); exits 0.

## Decisions Made

See `key-decisions` in the frontmatter above for the full rationale on each. Briefly:
the `limits` field (not a new type) on `ACPowerFlow`; the two-stage seed-then-AC pattern reused
identically for both FIX-10 and FIX-09; the SEPARATE `_site2_ac_optimizer` kwarg (SITE 2 is a
different problem class than the `optimizer` kwarg's SOCP/QP factory); `:report`'s early-`NaN`
return on a genuine AC non-convergence; the FORCED-failure rewrite of the 27-05 synthetic
inexact-FIT test; and the narrowed source-tripwire invariant.

## Deviations from Plan

### Auto-fixed Issues

**None required beyond the plan's own anticipated branches.** The plan's own `<action>` text
anticipated exactly the two SITE-2 outcomes this session implemented (a cone-bearing `pf` gets
the AC upgrade; a coneless `pf` keeps the old behavior) and explicitly instructed rewriting the
27-05 synthetic test — both are plan-anticipated work, not deviations under Rules 1-3.

One micro-fix, logged here for completeness rather than as a formal deviation: two prose
comments in `test/test_mpc_loop.jl` contained the literal substring `seed=5` inside
historical-provenance narration (describing why plans 27-03/27-07 ORIGINALLY chose that seed),
which accidentally matched Task 1's own `<verify>` grep (`grep -n "seed *= *5"`, intended to
catch the seed literally used in a `Scenario(...)` call, not prose). Reworded to `seed 5`/
`seed-5` — no code or test semantics changed, purely a comment-wording fix to satisfy the
plan's own literal verification command. (Rule 3 — blocking issue for the plan's own `<verify>`
step; trivial, no behavior change.)

---

**Total deviations:** 1 trivial (Rule 3, comment-wording only — no code/test semantics changed).
**Impact on plan:** None on behavior. Both tasks' acceptance criteria are met exactly as
specified, including the literal `grep -n "seed *= *5" test/test_mpc_loop.jl` returning nothing.

## Findings (for the orchestrator / Phase 28 awareness)

### Finding 1 — Fixed-dispatch SOC relaxations are structurally, not incidentally, inexact

Both FIX-10 (MPC truth import, plan 27-08) and FIX-09 (FIT AC-PF, this plan) independently hit
the SAME root cause: a SOCP relaxation whose OWN objective does not pin the loss current `l`
(because every device/aggregator injection is FIXED to an externally-determined value, leaving
the network with nothing left to optimize over except `l` itself) has NO mechanism forcing its
relaxation tight. This is qualitatively DIFFERENT from a genuine welfare solve's SOC relaxation,
where the network's own choice of `l` is disciplined by the objective. Any FUTURE fixed-dispatch
re-solve in this codebase should default to the AC-power-flow pattern established here (never a
SOCP re-solve gated by `assert_socp_exact!`), per the `patterns-established` note above.

### Finding 2 — Decoupling AC-solvability from operating limits cleanly resolves plan 27-08's own escalation

Plan 27-08 found (and did NOT paper over) that its LIMITED AC settlement genuinely refused
`seed=1` on two `test_mpc_loop.jl` fixtures because the realized dispatch exceeded the head
branch's thermal rating — a real finding, but one that conflated two DISTINCT questions: "does a
physical AC operating point exist for this dispatch?" (yes) and "does that operating point
respect the feeder's rating?" (no, by ~4-5%). This plan's physics-only decision cleanly
separates them: the settlement now answers ONLY the first question as a hard requirement, and
reports the second as a diagnostic — resolving plan 27-08's own `seed=5` deviation without
weakening any convergence bar (the LOCKED "never relax the convergence bar" policy is untouched
end to end; only the OPERATING LIMITS, a separate concept, are relaxed).

### Finding 3 — REPRO-01's genuine SITE-2 inexactness was population-scale-specific, not universal

Every SMALLER canonical `fit_baseline` fixture checked in this plan (the `FitFixtures` 3-bus
fixture, `test_pricing_welfare.jl`'s IEEE-13 ground fixture) reproduces its pre-27-09 SOCP-based
number to solver precision under the new AC settlement — meaning SITE 2's fixed-dispatch cone
was ALREADY essentially exact on those fixtures, and the plan's cited genuine inexactness
(gap≈211, ratio≈9993) is specific to the LARGER, population-scale IEEE-123 REPRO-01 point. This
is consistent with FIX-08/FIX-09's own prior findings (27-05-SUMMARY.md) that population-scale
sweep points are where genuine cone slack first appears on this codebase's fixtures.

## Known Stale Artifact (not modified, documented instead)

`.planning/phases/27-integer-planning-pricing-certificate-correctness/27-08-repro.jl` (plan
27-08's OWN repro script, NOT in this plan's `files_modified`) contains a testset — "27-08
ESCALATED FINDING: forced-PV-shortfall's default seed=1 genuinely throws under strict AC
settlement" — that asserts `run_mpc` THROWS at `seed=1` on the forced-PV-shortfall fixture. This
is now FALSE under plan 27-09's physics-only settlement (that exact scenario now settles cleanly
and reports the overload instead of throwing) — re-running `27-08-repro.jl` standalone will fail
that ONE testset. This is EXPECTED and NOT a regression: it is plan 27-08's own historical
record of the settlement's PRE-27-09 behavior, superseded by this plan's own `27-09-repro.jl`
(which documents and asserts the NEW behavior on the SAME fixture). Per this plan's own scope
(`files_modified` does not include `27-08-repro.jl`), it was left untouched rather than edited to
match the new behavior — a future session touching MPC settlement again should be aware this
file is stale on that one testset.

## Known Stubs

None — every new field (`settlement_violations`, `ac_status`, `ac_violations`) is fully wired
and exercised by both the updated `test/test_mpc_loop.jl`/`test/test_fit.jl` and the committed
`27-09-repro.jl`.

## Threat Flags

None — this plan touches only existing internal power-flow-formulation and pricing-counterfactual
logic (no new network endpoint, auth path, or schema surface). The new internal test seams
(`_site2_ac_optimizer` on `fit_baseline`) mirror the project's existing `_truth_settlement`
idiom (`run_mpc`) and are unexported, documented as "production callers never set this."

## GOLDEN-AUDIT

| Golden | Fixture | Old value (pre-27-09) | New value (post-27-09) | rel. diff | Moved? |
|---|---|---|---|---|---|
| `FIT_RATIO_GOLDEN` (`test_pricing_fit.jl`) | `FitFixtures` 3-bus, seed=20260718, T=4 | 0.772018581825438 | 0.7720185818295165 (measured) | 5.28e-12 | NO — within `rtol=1e-4`, not re-pinned |
| `RATIO_GOLDEN` (`test_pricing_welfare.jl`) | IEEE-13 ground fixture, T=24 | 0.9999738567553946 | 0.9999738569409319 (measured) | 1.86e-10 | NO — within `rtol=1e-4`, not re-pinned |
| `DSO_BAND_LO`/`DSO_BAND_HI` (`test_thesis_repro.jl` REPRO-01) | IEEE-123 real-impedance | band `(0.0, 7.211125525764296)` | `acct.dso = 3.7393744862531797` (measured) | inside band | NO — band unchanged, not re-derived (Phase 28 owns restatement) |

No golden was moved by this plan. All three were RE-MEASURED under the new AC settlement and
confirmed to still clear their existing tolerance — the plan's own must_haves text anticipated
a possible re-pin ("any moved FIT/REPRO goldens re-pinned old→new + cause") but none was needed.

## Issues Encountered

- `TestItemRunner`/`TestItems` `@testmodule`s (`Phase4Fixtures`, `Phase7Fixtures`) are not
  directly `include`-able under `julia --project=.` (per project memory
  `gsd-plan-verify-testitemrunner-trap.md` — the root `Project.toml` does not carry `TestItems`
  as a dependency). Worked around by inlining the small subset of each fixture module's code
  `27-09-repro.jl` needs directly into the script (two small internal modules,
  `ReproPhase4`/`ReproPhase7`), verified byte-identical to the corresponding
  `test/fixtures_phase{4,7}.jl` functions at the time of this plan. All temporary diagnostic
  scripts used DURING investigation (module-stripping experiments, golden-diff measurements)
  were written to the session scratchpad directory, never the repository.
- REPRO-01's IEEE-123 solves (DADP ~20-40s, `fit_baseline` ~17-20s including the new AC step)
  dominate `27-09-repro.jl`'s runtime (~1 min total measured, well under the plan's own ~3-6 min
  budget estimate) — no performance concern.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- FIX-09 and FIX-10 are both closed under the USER DECISION physics-only settlement: the MPC
  truth plant and the FIT AC-PF step both settle via genuine AC power flow with operating
  limits reported, never enforced as a refusal gate.
- `27-09-repro.jl` exits 0, covering both tasks' full acceptance criteria plus REPRO-01.
- **Carried forward for Phase 28 (thesis-reproduction restatement) awareness:** `fit_baseline`'s
  SITE 2 is now a genuine AC power flow rather than a SOCP relaxation — every canonical golden
  checked in this plan is unaffected (solver-precision agreement), but any Phase 28 work that
  re-derives FIT/REPRO numbers from first principles should cite THIS plan's settlement
  (AC power flow, physics only) as the current ground truth, not the pre-27-09 SOCP re-solve.
- **Carried forward:** `.planning/.../27-08-repro.jl`'s "seed=1 genuinely throws" testset is now
  stale (documented above, not modified) — a future MPC-touching plan re-running it standalone
  should expect that ONE testset to fail and should not treat it as a new regression.
- Orchestrator should re-run the full post-merge suite to confirm no other `fit_baseline`/
  `run_mpc` call site elsewhere in the suite is affected by SITE 2's/the truth plant's new
  return-field additions (both are purely additive `NamedTuple` fields; no removed field, no
  changed field semantics on any PRE-EXISTING field other than `socp_maxgap` now always being
  `nothing`, which no test outside `test_fit.jl`/`test_pricing_fit.jl` reads).

---
*Phase: 27-integer-planning-pricing-certificate-correctness*
*Completed: 2026-09-29*

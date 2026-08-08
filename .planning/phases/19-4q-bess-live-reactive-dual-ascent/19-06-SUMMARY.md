---
phase: 19-4q-bess-live-reactive-dual-ascent
plan: 06
subsystem: admm
tags: [julia, jump, admm, reactive-power, dual-ascent, mesh-05]

# Dependency graph
requires:
  - phase: 19-01
    provides: "ReactiveMode 3-state enum + normalize_reactive_mode (OFF/CERTIFIED/LIVE)"
  - phase: 19-03
    provides: "build_dso_opt's mirrored LIVE reactive coupling block on the DSO-OPT side (qag_dso, rho_q, set_rho_q!)"
  - phase: 19-04
    provides: "Aggregator.contribute! returning (;vars,p_inject,q_inject,utility) with the summed device q_inject term"
  - phase: 19-05
    provides: "assert_4q_complementarity!(ctx; rtol, atol, T, report) — the 4Q-BESS peer certificate"
provides:
  - "build_agr_opt's new reactive_mode kwarg (Bool/Symbol/ReactiveMode via normalize_reactive_mode) and rho_q::Real = rho, mirroring build_dso_opt's promotion at AGR-OPT scale"
  - "AgrOpt.qag_live::Union{Nothing,Vector{VariableRef}} — nothing under OFF/CERTIFIED, a genuine coupling variable pinned to qag[t]+res.q_inject[t] under LIVE, carrying its own rho_q-scaled quadratic penalty"
  - "solve_agr!'s new mu_j/d_j/rho_q kwargs driving qag_live's linear coefficient in the SAME loop as pag's, throwing ArgumentError if mu_j is supplied on a non-LIVE AgrOpt"
  - "solve_agr!'s new check_4q/rtol_4q/atol_4q kwargs invoking assert_4q_complementarity! in the same post-solve block as check_battery"
  - "set_rho_q!(agr::AgrOpt, rho_q) — the set_rho! peer for the qag_live block, throwing ArgumentError on a non-LIVE AgrOpt"
affects: ["19-07", "19-08"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "AGR-OPT's LIVE branch is a single `if mode == LIVE ... end` (not DsoOpt's 3-explicit-branch pattern) because AGR-OPT has no CERTIFIED-specific pin semantics to preserve — OFF and CERTIFIED are genuinely identical for this subproblem."
    - "qag_live's pinning target is qag[t] + res.q_inject[t] — the exact expression Aggregator.contribute! writes into :Rq (thesis 3.23 + the D-10 additive device term), mirroring pag's pin to res.p_inject[t] - agg.Pdc[t] exactly."
    - "The mu/d coefficient update for qag_live lives in the SAME per-hour loop as pag's lambda/c update (never a second loop), mirroring the file's existing build-once/re-solve discipline."
    - "check_4q is gated in the SAME post-solve block as check_battery, with the SAME convergence-only discipline (mid-loop iterates are legitimately off-consensus)."

key-files:
  created: []
  modified:
    - src/admm/AgrOpt.jl

key-decisions:
  - "Re-verified against the ACTUAL Aggregator.jl (plan 19-04) rather than assuming: res.q_inject is ONLY the summed device reactive injection (zero(AffExpr) per t when no member device carries an optional q_inject) — the aggregator's own inelastic -Pdc*tanphi term (qag) is NOT included. qag_live therefore pins to qag[t] + res.q_inject[t], matching the Interfaces note's fallback exactly (T-19-13's mandated re-verification)."
  - "AGR-OPT's reactive-mode branching is a single `if mode == LIVE` (not DsoOpt's 3 explicit OFF/CERTIFIED/LIVE branches with an unreachable-guard): AGR-OPT never had a CERTIFIED-specific one-shot-pin semantic to preserve (unlike DSO-OPT's :qag_pin), so OFF and CERTIFIED are structurally identical here — collapsing them into one non-LIVE path is not a scope reduction, it correctly reflects that this subproblem has only two genuinely distinct behaviors."
  - "Did not create or modify any file under test/ — the plan's files_modified scope is strictly src/admm/AgrOpt.jl (mirroring plan 19-03's precedent for the DsoOpt-side LIVE mode work). TDD RED/GREEN verification was done via a throwaway ad-hoc Julia/Test.jl script (not committed) that reproduces test_agr.jl's existing 4 @testitem bodies verbatim plus new acceptance-criteria assertions for both tasks, run before and after each task's edit."
  - "Verified check_4q's wiring with a genuine full-stack fixture (Aggregator + build_agr_opt + solve_agr!, not just complementarity_4q.jl's standalone-ModelContext harness): a deliberately-violating FourQuadBESS (Pch_max=Pdch_max=8, tight Emax, eta=0.5, lambda_test=9.0, mirroring test_fourquadbess.jl's honest-boundary fixture) co-activates p_ch*p_dch~15.2 at t=1, and check_4q=true on solve_agr! surfaces the SAME ErrorException message THROUGH solve_agr! — proving the call site is genuinely wired (T-19-14), not merely present in source."

requirements-completed: [MESH-05]

# Metrics
duration: ~40min
completed: 2026-08-08
---

# Phase 19 Plan 06: AGR-OPT Live Reactive Coupling + 4Q Certificate Wiring Summary

**`build_agr_opt` gains a `reactive_mode` kwarg mirroring `build_dso_opt`'s promotion: a genuine `qag_live` coupling variable pinned to the aggregator's total reactive injection under `LIVE`, `solve_agr!`'s new `mu_j`/`d_j`/`rho_q` update path and `check_4q` wiring for the 4Q-BESS certificate, and a `set_rho_q!` peer of `set_rho!`.**

## Performance

- **Duration:** ~40 min
- **Tasks:** 2/2 completed
- **Files modified:** 1 (`src/admm/AgrOpt.jl`)

## Accomplishments

- `build_agr_opt` accepts a new `reactive_mode = false` kwarg (normalized via `normalize_reactive_mode` as the first computed line — `Bool`/`Symbol`/`ReactiveMode` all accepted, mirroring `build_dso_opt`'s D-12 back-compat) and `ρ_q::Real = ρ`.
- `AgrOpt` gained a `qag_live::Union{Nothing,Vector{VariableRef}}` field (positioned immediately after `qag`): `nothing` under `OFF`/`CERTIFIED` (byte-identical to pre-Phase-19 — no new variable/constraint, objective unchanged), or a genuine coupling variable under `LIVE`, PINNED via an equality constraint (`qag_coupling`, registered as `:agr_qag_coupling`) to the aggregator's TOTAL reactive injection `qag[t] + res.q_inject[t]` — re-verified against the actual `Aggregator.jl` diff (plan 19-04) rather than assumed, per the plan's T-19-13 mandate.
- The `LIVE`-only `0.5·ρ_q·Σ qag_live[t]²` penalty is folded into the SAME `obj_expr` accumulator as `pag`'s existing `0.5·ρ·Σ pag[t]²` term before the single `@objective` call, so `OFF`/`CERTIFIED` never construct or touch it.
- `solve_agr!` accepts new `μ_j`/`d_j`/`ρ_q` kwargs (all `nothing` by default): when `μ_j !== nothing`, `qag_live[t]`'s linear coefficient is updated to `−μ_j[t] − ρ_q·d_j[t]` in the SAME per-hour loop as `pag[t]`'s `−λ_j[t] − ρ·c_j[t]` update (never a second loop). Supplying `μ_j` on a non-LIVE `AgrOpt` throws `ArgumentError` (fail loud, never a silent no-op).
- `solve_agr!` accepts new `check_4q::Bool = false` (plus `rtol_4q`/`atol_4q` passthrough at plan 19-05's measured defaults): when `true`, invokes `assert_4q_complementarity!` in the SAME post-solve block as `check_battery`, with the SAME convergence-only discipline.
- Added `set_rho_q!(agr::AgrOpt, ρ_q::Real)`, mirroring `set_rho!`'s exact batch-flatten-then-one-call shape on `qag_live`; throws `ArgumentError` on a non-LIVE `AgrOpt`. Exported alongside the file's existing exports — coexists with `DsoOpt`'s own `set_rho_q!` via Julia's normal multiple-dispatch method table (no collision).

## Task Commits

Both tasks were committed atomically:

1. **Task 1: qag_live coupling variable + ρ_q objective term under LIVE** - `c1e59eb` (feat)
2. **Task 2: solve_agr!'s μ/d coefficient update, set_rho_q!, and the check_4q wiring point** - `f9a66e6` (feat)

## Files Created/Modified

- `src/admm/AgrOpt.jl` — `build_agr_opt` signature promoted with `reactive_mode`/`ρ_q` kwargs + `LIVE`-only branch declaring/pinning `qag_live` and folding its objective penalty; `AgrOpt` struct gained `qag_live` field; `solve_agr!` extended with `μ_j`/`d_j`/`ρ_q` (qag_live coefficient update) and `check_4q`/`rtol_4q`/`atol_4q` (4Q-BESS certificate wiring); new `set_rho_q!(agr::AgrOpt, ...)`, exported.

## Verification Evidence

The plan's literal `<verify>` commands (`julia --project=. -e 'using TestItemRunner; ...'`) do not resolve under `--project=.` (`TestItemRunner` is a `test/Project.toml`-only dependency), consistent with every prior Phase-19 plan's identical finding. Per the orchestrator's guidance, verification was done via a direct Julia/Test.jl script (`/tmp/.../verify_agropt.jl`, not committed — outside the plan's `src/admm/AgrOpt.jl`-only scope) that:

1. Reproduces `test/test_agr.jl`'s 4 pre-existing `@testitem` bodies verbatim (build, solve, build-once, price-shift, `set_rho!` equivalence) — all pass unmodified, proving zero regression on the OFF/default path.
2. Proves Task 1's acceptance criteria: `qag_live === nothing` under the default and under `reactive_mode = true` (CERTIFIED); `qag_live isa Vector{VariableRef}` of length `T` under `reactive_mode = :live`; `num_variables`/`num_constraints` are IDENTICAL between OFF and CERTIFIED builds and are each `+T` under LIVE; the LIVE build solves OPTIMAL at the default zero price; `:agr_qag_coupling` is registered.
3. Proves the pinning target is genuinely `qag[t] + res.q_inject[t]` two ways: (a) with a device-less-of-reactive aggregator, `qag_live` exactly equals the constant `qag` (device term is genuinely zero); (b) with a `FourQuadBESS`-only aggregator, `qag_live` exactly equals `qag[t] + value(q[t])` (the device's own free reactive decision) at a solved point.
4. Proves Task 2's acceptance criteria: `solve_agr!` with only `(λ_j, c_j, ρ)` on an OFF-built `AgrOpt` is unaffected (baseline re-check); `μ_j` on an OFF-built `AgrOpt` throws `ArgumentError`; `μ_j`/`d_j`/`ρ_q` on a LIVE-built `AgrOpt` genuinely moves `qag_live`'s solved value between two different `μ_j` price vectors, with `num_variables`/`num_constraints` unchanged before/after (no rebuild); `set_rho_q!` throws on a non-LIVE `AgrOpt` and mutates a LIVE one without changing shape.
5. **`check_4q` wiring proof (T-19-14)**: builds a full `Aggregator` + `build_agr_opt` + `solve_agr!` stack around a deliberately-violating `FourQuadBESS` fixture (mirroring `test_fourquadbess.jl`'s honest-boundary fixture: `Pch_max=Pdch_max=8`, `Emax` only `0.2` above `soc0`, `η=0.5`, price `9.0`) that genuinely co-activates `p_ch·p_dch ≈ 15.2` at `t=1`; `check_4q = true` on `solve_agr!` surfaces the EXACT SAME `ErrorException` message from `assert_4q_complementarity!` THROUGH `solve_agr!` — proving the call site is genuinely wired, not merely present in source.
6. `import Pkg; Pkg.precompile()` ran clean (0 warnings/errors) after all edits.

Per the orchestrator's explicit instruction, the full `Pkg.test()` baseline was NOT re-run in this plan (the last recorded in-worktree baseline after wave 3's 19-05 was 2439 passed / 0 failed / 3 pre-existing broken); `git diff --diff-filter=D` was checked after each commit and found no unexpected deletions, and `git status --short` confirms only `src/admm/AgrOpt.jl` was touched across both commits.

## Decisions Made

See `key-decisions` in the frontmatter above — summarized: (1) re-verified `res.q_inject`'s exact composition against the real `Aggregator.jl` rather than assuming; (2) collapsed AGR-OPT's reactive-mode branching to a single `LIVE`-only `if` (not DsoOpt's 3-explicit-branch pattern), since AGR-OPT has no CERTIFIED-specific pin semantics to preserve; (3) no `test/` file created or modified, per the plan's strict `files_modified` scope and the orchestrator's note reserving this wave to `AgrOpt.jl` only.

## Deviations from Plan

None — plan executed exactly as written. Both tasks' `<action>`/`<behavior>` specifications were followed precisely, including the interfaces note's mandated re-verification of `res.q_inject`'s composition before writing the pinning constraint.

## Issues Encountered

- The plan's literal `<verify>` commands (`TestItemRunner.runtests(...)`) do not resolve under `--project=.`, consistent with every prior Phase-19 plan's identical, already-documented finding. Resolved with a direct Julia/Test.jl verification script per the orchestrator's guidance (see Verification Evidence above).
- The first attempt to prove `μ_j`/`d_j` genuinely move `qag_live` used the plan's own 2-bus fixture aggregator (Thermostatic+Deferrable+PVBattery, no reactive-capable device); since that aggregator's `res.q_inject` is identically zero, `qag_live` is correctly PINNED to a price-independent constant and does not move under `μ_j` — this is correct behavior, not a bug, but meant the test needed a `FourQuadBESS`-carrying aggregator (a genuine free reactive decision) to actually exercise the coefficient update path. Switched to a small standalone `FourQuadBESS` aggregator for that specific assertion.

## User Setup Required

None — no external service configuration required.

## Known Stubs

None. `qag_live`'s `LIVE` branch is structurally complete (declared, pinned, its own `ρ_q` penalty, driven by `solve_agr!`'s new `μ_j`/`d_j` path) but is intentionally NOT yet driven by any outer dual-ascent loop — that consumer is plan 19-07, explicitly out of scope here (mirrors plan 19-03's identical DSO-OPT-side note).

## Next Phase Readiness

- `build_agr_opt(...; reactive_mode = :live, ρ_q = ...)` and `solve_agr!(...; μ_j, d_j, ρ_q, check_4q)` are ready for plan 19-07's outer μ-dual-ascent loop, which will drive `qag_live` (AGR-OPT side) and `qag_dso` (DSO-OPT side, plan 19-03) in lockstep, exactly mirroring the existing `pag`/`pag_dso` `λ` dual-ascent pattern.
- `AgrOpt.qag_live` and `set_rho_q!` are exported and discoverable; OFF/CERTIFIED remain byte-identical to pre-Phase-19, so `solve_admm`'s existing calls (which never pass `reactive_mode`/`μ_j`/`check_4q`) are entirely unaffected.
- `check_4q` is proven genuinely wired through `solve_agr!` (not merely present in source) — plan 19-07/19-08 can enable it on the final converged re-solve exactly as `check_battery` already is.

---
*Phase: 19-4q-bess-live-reactive-dual-ascent*
*Completed: 2026-08-08*

## Self-Check: PASSED

- FOUND: src/admm/AgrOpt.jl
- FOUND: commit c1e59eb (Task 1)
- FOUND: commit f9a66e6 (Task 2)
- Verified via direct Julia/Test.jl script: all Task 1/Task 2 acceptance-criteria assertions pass, pre-existing test_agr.jl bodies reproduce unmodified, check_4q wiring proven end-to-end through solve_agr!, `Pkg.precompile()` clean.

---
phase: 11-single-distributor-stackelberg-benders-certified
plan: 03
subsystem: testing
tags: [bileveljump, mpec, ipopt, benders, planning-layer, certification]

# Dependency graph
requires:
  - phase: 11-single-distributor-stackelberg-benders-certified (plan 11-01)
    provides: "FollowerLP/solve_follower! (empirically-pinned positive coupling-dual sign), BendersMaster (multi-cut α_op/α_x epigraph)"
  - phase: 11-single-distributor-stackelberg-benders-certified (plan 11-02)
    provides: "solve_stackelberg! (build-once Benders orchestration loop), the re-derived analytic optimum (y*=z*=0.7, total=-0.245)"
provides:
  - "test/test_planning_certification.jl: permanent [:planning]-tagged BilevelJuMP certification gate (PLAN-07, PVAL-01) — empirically confirms the leader/follower role assignment and coupling-dual sign convention chosen in plans 11-01/11-02, with NO code changes required"
  - "BilevelJuMP 0.6.3 wired as a test-only dependency (test/Project.toml), never touching src/"
  - "Documented, permanent negative regression: BilevelJuMP.BigMMode + HiGHS cannot solve MIQP (mixed-integer quadratic) instances — a genuine solver-capability gap, not a bound-tuning issue"
affects: []

# Tech tracking
tech-stack:
  added: [BilevelJuMP (test-only, 0.6.3), HiGHS (promoted to direct test dep), Ipopt (promoted to direct test dep)]
  patterns:
    - "BilevelJuMP Upper()/Lower() MPEC construction, mirrored twice (StrongDualityMode + ProductMode) via a @testmodule-provided build function, never build-once (each BilevelModel owns its own solver instance)"
    - "Documented NEGATIVE regression pattern: assert a known solver-incapability status (MOI.OTHER_ERROR) rather than silently omitting a non-working code path"

key-files:
  created:
    - test/test_planning_certification.jl
  modified:
    - test/Project.toml
    - test/Manifest.toml

key-decisions:
  - "BigMMode+HiGHS cannot solve this instance: BigMMode's Fortuny-Amat/Big-M reformulation introduces binary complementarity indicators; combined with the instance's genuinely quadratic Upper-level welfare term, the single-level reformulation is a MIQP, a problem class HiGHS categorically does not support (measured: optimize! returns termination_status=MOI.OTHER_ERROR, HiGHS prints \"Cannot solve MIQP problems with HiGHS\", at ANY Big-M bound). BilevelJuMP.ProductMode (already shipped in the installed 0.6.3 package, no new dependency) substitutes as the second, structurally-independent reformulation (epsilon-relaxed bilinear-product complementarity vs. StrongDualityMode's strong-duality equality)."
  - "No sign flip required: StrongDualityMode, ProductMode, hand enumeration, and solve_stackelberg! all independently converge to y*=z*=0.7, total=-0.245 (the re-derived analytic optimum from 11-02-SUMMARY.md, NOT 11-01-PLAN.md's stated incorrect y*=1.0/z*=1.0/-0.2) — the leader/follower role assignment and coupling-dual sign convention chosen in plans 11-01/11-02 are empirically CONFIRMED CORRECT, with zero changes to follower.jl/benders.jl."

requirements-completed: [PLAN-07, PVAL-01]

# Metrics
duration: ~75min
completed: 2026-07-22
---

# Phase 11 Plan 03: BilevelJuMP Certification Summary

**Independent BilevelJuMP MPEC certification (StrongDualityMode + ProductMode, cross-checked against a hand-worked enumeration) empirically CONFIRMS the leader/follower role assignment and coupling-dual sign convention chosen in plans 11-01/11-02 — no code changes required — while documenting, as a permanent regression, that BigMMode+HiGHS cannot solve this instance (a genuine MIQP solver-capability gap, not a bound-tuning issue).**

## Performance

- **Duration:** ~75 min
- **Started:** 2026-07-22 (session start, after worktree base correction to `7ae82d6`)
- **Completed:** 2026-07-22T22:11:44Z
- **Tasks:** 2 completed
- **Files modified:** 3 (1 created, 2 modified — `test/Project.toml`, `test/Manifest.toml`)

## Accomplishments

- `test/Project.toml`: `BilevelJuMP` added as a test-only dependency (registry-verified, exact version `0.6.3` matching 11-RESEARCH.md's Package Legitimacy Audit), plus `HiGHS`/`Ipopt` promoted to direct test-environment dependencies (previously only transitive via `TSODSO` itself); a NEW `[compat]` section introduced (the file previously had none), pinning all three exact versions per CONTEXT.md's supply-chain-integrity guidance.
- `test/test_planning_certification.jl`: two permanent `[:planning]`-tagged `@testitem`s (105 planning items → 125) plus a shared `BilevelCertFixture` `@testmodule`:
  1. `StrongDualityMode`(Ipopt) + `ProductMode`(Ipopt) independently converge to the re-derived hand-enumerated optimum (`y*=z*=0.7`, `total=-0.245`) and agree with each other within `rtol=1e-4`; `BigMMode`(HiGHS) is exercised and asserted to fail with the documented `MOI.OTHER_ERROR` status (a permanent negative regression, not a silent omission).
  2. `solve_stackelberg!` (the production Benders loop, plan 11-02) on the IDENTICAL toy instance is cross-checked against both successfully-solving BilevelJuMP reformulations and the hand enumeration — all agree within documented tolerance, certifying PLAN-07/PVAL-01 with NO sign flip needed.
- Full `[:planning]`-tagged suite (125 items: 99 wave-1 + 6 wave-2 + 20 new) green; full project suite (4028 tests: 4024 passed, 4 pre-existing documented `broken` items unrelated to this plan, 0 failures) green — no Phase 1-11 regression.

## Task Commits

Each task was committed atomically:

1. **Task 1: BilevelJuMP test-only dependency + BigMMode/StrongDualityMode vs hand enumeration** - `ff90c6b` (feat)
2. **Task 2: Benders vs BilevelJuMP cross-check — certify (or flip) the leader/follower sign convention as a permanent invariant** - `ce944ba` (test)

_Note: no TDD RED/GREEN split commits were made — tests were authored alongside the BilevelJuMP model construction and verified green before each commit, mirroring plans 11-01/11-02's own noted TDD framing without a separate failing-test commit, since this is greenfield certification code with no pre-existing behavior to regress against._

## Files Created/Modified

- `test/test_planning_certification.jl` — `BilevelCertFixture` `@testmodule` (hand-enumerated constants + `build_toy_bilevel`/`build_toy_bilevel_bigm` builders) + two `@testitem`s (StrongDualityMode/ProductMode/BigMMode cross-check; Benders-vs-BilevelJuMP permanent invariant)
- `test/Project.toml` — `BilevelJuMP = "0.6.3"` added to `[deps]`; `HiGHS`/`Ipopt` promoted to direct `[deps]`; new `[compat]` block pinning all three exact versions
- `test/Manifest.toml` — regenerated by `Pkg.add`/`Pkg.resolve` to reflect the new/promoted dependencies (`BilevelJuMP`, `Dualization` transitive, `HiGHS`, `Ipopt`, and their own transitive closures)

## Decisions Made

- **BigMMode+HiGHS substituted with ProductMode+Ipopt as the second independent reformulation** — see Deviations below; this is the plan's single largest deviation and is documented extensively in the test file's own header comment for future re-discovery prevention.
- **No sign flip required in `follower.jl`/`benders.jl`** — all three independent certification paths (StrongDualityMode, ProductMode, Benders) converge to the SAME `y*=z*=0.7`, `total=-0.245` without any code change, confirming plan 11-01's empirically-pinned positive coupling-dual sign and plan 11-02's UB formula/cut-sign wiring are correct as implemented.
- **`result.UB` reused directly for the Benders-side "total objective" comparison** (Task 2), rather than re-solving `solve_planning_oracle!`/`solve_follower!` a second time at `result.z` — since `result.gap <= 1e-6` already certifies `UB≈LB≈` the converged total, and `benders.jl`'s own UB formula (`master.c_y*y + follower_cost - oracle_cost`) is exactly the quantity needed; avoids any redundant-re-solve determinism question.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug in the plan's own assumed approach] BigMMode+HiGHS cannot solve this instance (MIQP incapacity) — substituted BilevelJuMP.ProductMode as the second reformulation**
- **Found during:** Task 1, first attempt to build the `BigMMode(HiGHS.Optimizer)` model per the plan's own `<interfaces>` code shape.
- **Issue:** The plan's `<interfaces>` block specifies `BilevelModel(HiGHS.Optimizer, mode = BilevelJuMP.BigMMode(...))` on an instance whose Upper-level objective is genuinely quadratic (`-(2z - 0.5z^2)`, the same closed-form oracle welfare the production `PlanningOracle` computes — not something that can be dropped or linearized without breaking the certification's fidelity to the real fixture). Measured directly: `BigMMode`'s Fortuny-Amat/Big-M reformulation of the follower LP's KKT/complementarity conditions introduces BINARY indicator variables; combined with the quadratic Upper objective, the resulting single-level reformulation is a MIQP (mixed-integer quadratic program) — a problem class HiGHS categorically does not support, at ANY Big-M bound (`optimize!` does not throw; it returns normally with `termination_status(model) == MOI.OTHER_ERROR`, and HiGHS itself prints "Cannot solve MIQP problems with HiGHS"). Confirmed this is NOT a Big-M-bound tuning issue (11-RESEARCH.md's Pitfall B1 warning sign — two DIFFERENT solved answers disagreeing — does not apply; BigMMode+HiGHS never reaches a solved answer at all).
- **Fix:** Verified no Gurobi license is present in this environment (no `gurobi.lic`/`GRB_*` env vars — CLAUDE.md reserves Gurobi for a licensed fallback only, not usable here). Confirmed `BilevelJuMP.ProductMode` (an epsilon-relaxed bilinear-product complementarity reformulation, solved via Ipopt) is already shipped in the installed BilevelJuMP 0.6.3 package — no new test-only dependency required. Substituted `ProductMode`+Ipopt for `BigMMode`+HiGHS's role as the second, structurally-independent reformulation (empirically verified: converges to `y=z=0.7000000091`, `obj=-0.2450000053`, matching `StrongDualityMode` and the hand enumeration within `rtol=1e-4`/`atol=1e-3`). `BigMMode`+HiGHS is RETAINED in the test file as a documented, asserted NEGATIVE regression (`@test termination_status(r_bigm.model) == MOI.OTHER_ERROR`) so this finding is never silently rediscovered by a future plan, rather than silently dropped.
- **Files modified:** `test/test_planning_certification.jl` only — no `src/` changes.
- **Verification:** Re-ran the full `[:planning]`-tagged suite (125/125 green) and the full project suite (4024/4028 passed, 4 pre-existing `broken`, 0 failed) after the substitution.
- **Committed in:** `ff90c6b` (Task 1 commit)

**2. [Rule 1 - Bug in a prior plan's own `<interfaces>` code shape] `value(var, model)` two-argument call signature does not exist for `BilevelVariableRef`**
- **Found during:** Task 1, initial probe of the plan's own `<interfaces>` block code (`isapprox(value(y_inv, model_bigm), value(y_inv, model_sd); rtol = 1e-4)`).
- **Issue:** `JuMP.value(v::BilevelVariableRef; result::Int=1)` takes only the variable reference — the owner model is embedded in the variable ref itself (`owner_model(v)`) — there is no `value(var, model)` two-argument method. The plan's `<interfaces>` block's literal code would raise a `MethodError` if run as written.
- **Fix:** Used the correct one-argument form `value(var)` throughout `test/test_planning_certification.jl`.
- **Files modified:** `test/test_planning_certification.jl` only.
- **Verification:** Confirmed via direct probe against the installed BilevelJuMP 0.6.3 source (`~/.julia/packages/BilevelJuMP/.../src/jump_variables.jl`); all assertions pass with the corrected call form.
- **Committed in:** `ff90c6b` (Task 1 commit)

---

**Total deviations:** 2 auto-fixed (1 solver-capability substitution requiring extensive documentation, 1 API-signature correction) — both Rule 1 (plan's own assumed approach didn't work as literally specified), zero `src/` changes, zero new test-only dependencies beyond what the plan itself specified (BilevelJuMP; `ProductMode` is part of that same package).
**Impact on plan:** The BigMMode substitution preserves PLAN-07/PVAL-01's actual success criterion — "two independent reformulations cross-checked against hand enumeration" — via `ProductMode` instead of `BigMMode`, both structurally distinct from `StrongDualityMode`. The literal acceptance-criteria text ("BigMMode vs StrongDualityMode agreement assertions pass") is NOT met by a live BigMMode solve (impossible on this instance with HiGHS); it is instead met by a documented negative regression plus `ProductMode` filling BigMMode's functional role. No scope creep; no change to any `src/` file.

## Issues Encountered

- **Background full-suite test runs in this sandboxed environment require the Bash tool's own `run_in_background: true` parameter, not raw shell `&`/`nohup`+`disown`** — two earlier attempts to background the ~9-minute full-suite run via plain `&` and via `nohup ... & disown` both appeared to terminate early (log growth stalled, no `ps aux` visibility) when checked from a SUBSEQUENT Bash tool call; in fact the `nohup` attempt (`full_run_3.log`) DID complete successfully in the background across multiple tool calls (confirmed via a `until grep -q "Test Summary"` monitor that eventually returned exit 0), while a separate `timeout 590`-wrapped attempt was killed by its own inner timeout at 590s (not by session teardown). The reliable, tool-native mechanism is `Bash(..., run_in_background: true)` with a generous `timeout` parameter (up to the 600000ms/10min tool max) and NO additional shell-level `timeout` wrapper — the full suite (~9 min) fits within that window. No product-code impact; a verification-tooling timing/mechanism note for future plans in this phase.
- **`TestItemRunner.runtests(filter=...)` (as used in the plan's own `<verify>` automated commands) does not exist in the installed TestItemRunner 1.1.5** — same finding as plans 11-01/11-02; the correct API is `@run_package_tests filter=...`. A temporary merged Julia environment (`Pkg.develop` on the package root + `test/Project.toml`'s own deps, built fresh in the scratchpad this session since the environment is not persisted across plans) was used for all filtered/full-suite runs.

## User Setup Required

None — no external service configuration required. `BilevelJuMP`/`HiGHS`/`Ipopt` are all test-only dependencies (`test/Project.toml`); `Project.toml`/`Manifest.toml` (the shipped package's own dependency files) are unchanged.

## Next Phase Readiness

- PLAN-07 and PVAL-01 are both complete: the leader/follower role assignment and coupling-dual sign convention from plans 11-01/11-02 are empirically certified against an independent BilevelJuMP MPEC reduction, encoded as a permanent, passing `[:planning]` regression (125 items, all green).
- Phase 11's full success-criteria set (PLAN-04 through PLAN-07, PVAL-01) is now complete across plans 11-01/11-02/11-03. The Stackelberg-Benders single-distributor equilibrium solves end-to-end (`solve_stackelberg!`), certified correct by an independent reformulation, with zero unresolved sign/role ambiguity carried forward.
- **Flag for future phases (13, Nash diagonalization):** if a future phase needs a similar BilevelJuMP certification on an instance with a genuinely quadratic Upper-level objective, `BigMMode`+HiGHS will hit the SAME MIQP incapacity documented here — reuse `ProductMode`(Ipopt) or `StrongDualityMode`(Ipopt) instead; do not re-attempt `BigMMode`+HiGHS on a quadratic-objective instance without first checking whether the instance can be kept purely linear.
- No other blockers.

---
*Phase: 11-single-distributor-stackelberg-benders-certified*
*Completed: 2026-07-22*

## Self-Check: PASSED

- FOUND: test/test_planning_certification.jl
- FOUND: test/Project.toml
- FOUND: .planning/phases/11-single-distributor-stackelberg-benders-certified/11-03-SUMMARY.md
- FOUND commit: ff90c6b
- FOUND commit: ce944ba

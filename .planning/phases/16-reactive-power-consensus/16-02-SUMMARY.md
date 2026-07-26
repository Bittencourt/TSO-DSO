---
phase: 16-reactive-power-consensus
plan: 02
subsystem: infra
tags: [julia, jump, admm, socp, reactive-power, dso-opt, clarabel]

# Dependency graph
requires:
  - phase: 16-reactive-power-consensus (plan 01)
    provides: qag_dso/reactive/mu_q naming decision + RED @testitem harness (test/test_admm_reactive.jl) pinning the REACT-01/02/03 contract
provides:
  - "build_dso_opt gains reactive_consensus::Bool=false kwarg: default path byte-identical, true path promotes the per-load-node reactive draw to a pinned qag_dso[j,t] JuMP coupling variable (ctx.meta[:qag_dso]) via a new registered :qag_pin equality"
  - "solve_admm gains reactive_consensus::Bool=false kwarg, threaded to build_dso_opt, and certifies :balance_q via assert_no_slack (mirroring :balance_p) whenever reactive_consensus=true"
  - "REACT-01/03's RED harness (test/test_admm_reactive.jl items 1/2) now GREEN; item 3 (solve_admm certificate) also GREEN"
affects: [16-03-dlmp-reactive-pricing]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "one-shot certified dual read via a PINNED coupling variable (qag_dso[j,t] == q_draw[j][t]) instead of a live mu dual-ascent loop -- promotes a constant to a JuMP variable purely to make its shadow price/dual recoverable, with zero new objective penalty and zero new residual trace (thesis A3: the pinned target never moves)"
    - "gated no-slack certificate: assert_no_slack reused verbatim on a second constraint (:balance_q), gated behind the same feature flag that introduces the coupling variable, mirroring an existing certificate block exactly rather than writing a new helper"

key-files:
  created: []
  modified:
    - src/admm/DsoOpt.jl
    - src/admm/solve_admm.jl
    - test/test_dso.jl
    - test/test_admm_reactive.jl

key-decisions:
  - "qag_dso is PINNED via an explicit equality (:qag_pin, qag_dso[j,t] == q_draw[j][t]) rather than left unconstrained -- an unpinned free variable would let the solver discard the physical reactive demand entirely (zero objective cost, no other tie to the true draw), which is a genuine correctness regression the threat model (T-16-03) explicitly calls out."
  - "No new quadratic penalty or residual trace for qag_dso -- Assumption A1/A3 (reactive is not a consensus quantity; q_draw never moves) means this is a one-shot certified dual read, not a live mu-ascent loop. Confirmed empirically: a zero-price solve with reactive_consensus=true reproduces the default-path objective/q_import to atol=1e-8."
  - "Fixed an inverted RED-guard assertion in test/test_admm_reactive.jl (created in plan 16-01, outside this plan's declared files_modified) -- items (1)/(3) asserted `!has_kwarg`, which permanently fails once the guarded kwarg lands; flipped to the positive `has_kwarg` form already used elsewhere (test_dso.jl's `isdefined(TSODSO, :set_rho!)` idiom). Applied as a Rule 1 bugfix since the failure was directly triggered by this task's own kwarg addition."

patterns-established:
  - "RED-guard kwarg-detection assertions should always be POSITIVE (`@test has_kwarg`), never negated (`@test !has_kwarg`) -- a negated guard is RED before the feature lands and becomes a NEW permanent failure once it lands, inverting the intended RED-to-GREEN transition."

requirements-completed: [REACT-01, REACT-03]

# Metrics
duration: ~90min
completed: 2026-07-26
---

# Phase 16 Plan 02: DSO-OPT Reactive-Power Consensus Summary

**Promoted the ADMM `DSO-OPT`'s per-load-node reactive draw from a hand-summed `Float64` constant to a genuine, pinned JuMP coupling variable `qag_dso[j,t]`, gated behind a `reactive_consensus::Bool=false` kwarg (default preserves today's behavior byte-for-byte), and added the `assert_no_slack` certificate on `:balance_q` so its dual becomes trustworthy/publishable whenever the flag is on.**

## Performance

- **Duration:** ~90 min (including a long full-suite `Pkg.test()` verification run, ~12 min alone)
- **Tasks:** 2
- **Files modified:** 4 (`src/admm/DsoOpt.jl`, `src/admm/solve_admm.jl`, `test/test_dso.jl`, `test/test_admm_reactive.jl`)

## Accomplishments

- `build_dso_opt(feeder, aggregators, T; ρ, λ₀, reactive_consensus=false)`: at the default, the reactive injection into `:Rq[j]` is the byte-identical constant `q_draw[j][t]` (no `ctx.meta[:qag_dso]` key). At `reactive_consensus=true`, allocates `qag_dso[j=load_nodes, t=1:T]`, injects it into `:Rq[j]` in place of the constant, adds and registers a new pinning equality `:qag_pin` (`qag_dso[j,t] == q_draw[j][t]`), and stashes `ctx.meta[:qag_dso] = qag_dso`. `:balance_q`'s own registration is unchanged either way.
- `solve_admm(...; reactive_consensus=false)` threads the flag into the sole `build_dso_opt` call site and, whenever `true`, runs `assert_no_slack` over every `:balance_q[j,t]` entry after the final consolidation solve — mirroring the existing `:balance_p` certificate exactly, same `let`-scoping idiom, placed directly after it in the same "WR-01 PUBLISHED-PRIMAL CERTIFICATE" section.
- Added a new `@testitem` to `test/test_dso.jl` asserting: no `qag_dso` key on the default path, `qag_dso` shape `(length(load_nodes), T)` and `:balance_q` intact on the reactive path, and a zero-price primal-equivalence proof (objective value and `q_import` match to `atol=1e-8` between the default and `reactive_consensus=true` builds on the 2-bus fixture) — empirical confirmation the pin serves the true reactive demand exactly, not approximately.
- Fixed an inverted RED-guard bug in `test/test_admm_reactive.jl` (from plan 16-01) that would have permanently failed once the kwarg landed; see Deviations.
- Verified: `dso`-filtered suite 65/65 pass, `admm`-filtered suite 94/94 pass, `reactive`-filtered suite 141/141 pass, and the FULL `Pkg.test()` suite: **2325 passed, 3 broken (pre-existing markers), 0 failed** in ~12 min — the wave-merge regression gate per 16-VALIDATION.md.

## Task Commits

Each task was committed atomically:

1. **Task 1: Promote q_draw to a pinned qag_dso coupling variable in build_dso_opt** - `d33f0bd` (feat)
2. **Task 2: Thread reactive_consensus through solve_admm + certify :balance_q** - `5d69795` (feat)

**Plan metadata:** (this commit, docs: complete plan)

## Files Created/Modified

- `src/admm/DsoOpt.jl` - `build_dso_opt` gains `reactive_consensus::Bool=false`; step (4b) branches between the byte-identical constant injection (default) and the new pinned `qag_dso[j,t]` coupling variable + `:qag_pin` equality + `ctx.meta[:qag_dso]` stash (when `true`). Header comment block and docstring extended to document the new conditional path.
- `src/admm/solve_admm.jl` - `solve_admm` gains `reactive_consensus::Bool=false`, threaded into the sole `build_dso_opt` call; a new certificate block (gated `if reactive_consensus`) runs `assert_no_slack` on every `:balance_q[j,t]` entry after the final consolidation solve, appended directly after the existing `:balance_p` certificate in the same section. Docstring extended with a new "Reactive consensus" section.
- `test/test_dso.jl` - New `@testitem` ("reactive_consensus=true pins qag_dso coupling variable, zero-price primal-equivalent to default") asserting the shape/registration contract and the zero-price primal-equivalence proof; header comment extended to document the new kwarg contract.
- `test/test_admm_reactive.jl` - Fixed the inverted RED-guard assertions in items (1) and (3) (`!has_kwarg` → `has_kwarg`), a bugfix directly triggered by this plan's kwarg addition (see Deviations). No behavioral assertions were weakened; only the guard's polarity was corrected to match the `isdefined(...)` idiom used elsewhere.

## Decisions Made

- **`qag_dso` is pinned, not free-floating:** an explicit `:qag_pin` equality (`qag_dso[j,t] == q_draw[j][t]`) prevents the solver from silently discarding the physical reactive demand — a genuine correctness regression the threat model (T-16-03) flags as a mitigation requirement. Verified empirically via the new zero-price primal-equivalence test.
- **No live μ dual-ascent for `qag_dso`:** per Assumption A1/A3 (`q_draw` never moves — it is not a consensus quantity), `qag_dso` carries no quadratic penalty and needs no residual trace; this is a one-shot certified dual read only, as specified by 16-RESEARCH.md/16-PATTERNS.md.
- **Fixed the RED-harness guard polarity (Rule 1 bugfix):** `test/test_admm_reactive.jl` items (1)/(3), written in plan 16-01 (outside this plan's `files_modified`), asserted `@test !has_kwarg` — a form that necessarily flips to a PERMANENT failure the moment the guarded kwarg exists, since `has_kwarg` becomes `true`. This directly contradicts the file's own stated intent ("Plan 16-02 ... turns items (1)/(3) GREEN by IMPLEMENTING the code") and diverges from the correct idiom already established elsewhere in the codebase (`test_dso.jl`'s `@test isdefined(TSODSO, :set_rho!)`, a POSITIVE assertion that stays true forever once implemented). Flipped both occurrences to `@test has_kwarg`. This is directly caused by this task's own change (adding the kwarg is what flips `has_kwarg` from `false` to `true`), so it falls within Rule 1's scope despite the file not being in this plan's declared `files_modified`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed inverted RED-guard assertion in test/test_admm_reactive.jl**
- **Found during:** Task 1 verification (first `dso`-filtered test run after adding the kwarg)
- **Issue:** Items (1) and (3) in `test/test_admm_reactive.jl` (created in plan 16-01) asserted `@test !has_kwarg`, a negated form that is RED (correctly) before the `reactive_consensus` kwarg exists, but becomes a NEW PERMANENT failure the instant the kwarg is added — the opposite of the intended RED-to-GREEN transition documented in the file's own header ("Plan 16-02 ... turns items (1)/(3) GREEN"). This is a direct consequence of this plan's own change (adding the kwarg flips `has_kwarg` to `true`).
- **Fix:** Flipped both `@test !has_kwarg` assertions to `@test has_kwarg`, matching the established positive-guard idiom (`@test isdefined(TSODSO, :set_rho!)` in `test_dso.jl`). The behavioral `if has_kwarg ... end` bodies were left untouched.
- **Files modified:** `test/test_admm_reactive.jl`
- **Verification:** Re-ran `@run_package_tests filter=ti->occursin("reactive", ti.name)` after each task; item (1) reported GREEN after Task 1, item (3) reported GREEN after Task 2 (141/141 total pass on the full reactive-filtered run).
- **Committed in:** `d33f0bd` (Task 1 commit, item 1's fix) and carried through unchanged for item 3 (fixed in the same commit since both items share the identical bug pattern).

---

**Total deviations:** 1 auto-fixed (1 bugfix, Rule 1)
**Impact on plan:** Necessary for the RED harness to reach its documented GREEN terminal state; no behavioral assertions were weakened, no scope creep — the fix only corrected an assertion's polarity in a file whose own header explicitly anticipated this plan turning it green.

## Issues Encountered

- **`TestItemRunner`/`TSODSO` are not both resolvable from a single `--project` invocation** in this worktree (root `Project.toml` has `TSODSO`'s own deps but not `TestItemRunner`; `test/Project.toml` has `TestItemRunner` but not `TSODSO`, which is normally injected only inside `Pkg.test()`'s internal temp-environment mechanism). Resolved by stacking both as ABSOLUTE paths in `JULIA_LOAD_PATH` (`"$ROOT/test:$ROOT:@stdlib"`) — relative paths break because `TestItemRunner.run_tests` internally `cd`s into each test file's directory before evaluating it, which re-resolves relative `LOAD_PATH` entries against the new working directory and silently drops the root project reference.
- **Full `Pkg.test()` runtime (~12 min) exceeds a single synchronous Bash budget** and, in this session, the system was under heavy memory/swap pressure that caused one run (wrapped in a shell-level `timeout 590`) to be killed before completion (exit 124). Re-ran fully backgrounded with no artificial timeout cap; it completed successfully: **2325 passed, 3 broken (pre-existing, unrelated markers), 0 failed**, confirming REACT-03's full-suite non-regression gate is satisfied.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- REACT-01 is fully implemented and REACT-03 (default-path non-regression) is re-confirmed by both the targeted filtered suites and the full `Pkg.test()` run.
- `ctx.meta[:qag_dso]` and the certified `:balance_q` dual (via `assert_no_slack`, gated on `reactive_consensus=true`) are now available for plan 16-03 to consume in `decompose_dlmp`'s new `reactive` field (REACT-02) — no further `DsoOpt.jl`/`solve_admm.jl` changes anticipated for that plan.
- `src/experiments/Scenario.jl` was not touched, preserving the phase-wide DrWatson golden-hash non-perturbation constraint.
- No blockers.

---
*Phase: 16-reactive-power-consensus*
*Completed: 2026-07-26*

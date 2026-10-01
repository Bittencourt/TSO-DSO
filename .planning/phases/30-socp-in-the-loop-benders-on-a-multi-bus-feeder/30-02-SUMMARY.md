---
phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder
plan: 02
subsystem: optimization
tags: [jump, clarabel, highs, benders, epigraph-bounds, planning]

# Dependency graph
requires:
  - phase: 11-01
    provides: "BendersMaster/build_master (src/planning/master.jl), the epigraph-lower-bound-at-build-time pattern (Pitfall M1) this plan extends"
  - phase: 10-02/11-01
    provides: "build_planning_oracle/contribute!/ModelContext wiring (src/planning/subproblem.jl) reused verbatim by make_relaxed_oracle_model; build_follower (src/planning/follower.jl)/FollowerLP reused by make_relaxed_follower_model and the new FollowerLP dispatch"
provides:
  - "build_master's :auto alpha_op_lb/alpha_x_lb resolution + opt-in bounds_ctx build-time rejection (src/planning/master.jl) — consumed by plan 30-04's solve_stackelberg! wiring"
  - "make_relaxed_oracle_model/derive_alpha_op_lb/make_relaxed_follower_model/derive_alpha_x_lb (src/planning/master.jl) — one-time, discard-after-use relaxed-solve derivation helpers, including a derive_alpha_x_lb(::FollowerLP) dispatch"
  - "30-ALPHA-AUDIT.md — the repo-wide T>1 alpha-bound audit (BILEV-05 Pitfall 4), covering both test/ and src/ call sites"
affects: [30-04, 30-05, 30-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Opt-in bounds_ctx keyword gating new build-time derivation/rejection logic — every pre-existing explicit-bound build_master call site (no bounds_ctx) stays byte-identical, avoiding a retrofit of ~90 existing call sites"
    - "One-time relaxed model (boxed p_import, no Parameter pin) built via build_planning_oracle's exact contribute!/aggregator-loop/balance-closure assembly, discarded after a single solve_with_retry! solve — never a reuse of the live PlanningOracle/FollowerLP Parameter machinery, which cannot be 'freed' from its equality pin"
    - "Derivation helpers deliberately named WITHOUT a build_ prefix so PVAL-04's source-scan tripwire never discovers them as planning-layer subproblem builders"

key-files:
  created:
    - .planning/phases/30-socp-in-the-loop-benders-on-a-multi-bus-feeder/scripts/audit_alpha_bounds.jl
    - .planning/phases/30-socp-in-the-loop-benders-on-a-multi-bus-feeder/30-ALPHA-AUDIT.md
  modified:
    - src/planning/master.jl
    - test/test_planning_master.jl
    - test/test_planning_noninteger.jl

key-decisions:
  - "ALPHA_LB_MARGIN = ALPHA_LB_REJECTION_TOL = 1e-6 (measured): probed make_relaxed_oracle_model/make_relaxed_follower_model on Phase6Fixtures.two_bus_feeder() + ToyElasticDevice(2,6.0,1.0,10.0) at T=1 — oracle primal/dual gap ~2.85e-9, follower gap 0.0 exactly (trivial x_inv=x_op=0 LP optimum); max(1e-6, 10*max_gap) is dominated by the 1e-6 floor."
  - "Repo-wide T>1 audit (independently re-verified, not copy-pasted from RESEARCH.md): the ONLY T>1 alpha_op_lb/alpha_x_lb call site across all 10 planning test files AND every src/-level solve_stackelberg!/build_master call site is test_planning_hardening.jl's own T=8 fixture (alpha_op_lb=-50.0, alpha_x_lb=0.0), reached via solve_stackelberg!'s master_kwargs. The new derivation formula ACCEPTS it (derived alpha_op_lb=-16.000001). No previously-unknown invalid bound found."

requirements-completed: ["BILEV-05"]

# Metrics
duration: ~75min
completed: 2026-10-01
---

# Phase 30 Plan 02: build_master `:auto` Alpha-Bound Derivation + Build-Time Rejection Summary

**`build_master`'s `α_op_lb`/`α_x_lb` gain an opt-in `:auto` default, resolved by a genuine one-time relaxed solve (never a closed-form shortcut), with build-time rejection of an over-high explicit bound when `bounds_ctx` is supplied — zero regression on every one of the ~90 pre-existing explicit-bound call sites, and a repo-wide T>1 audit (test/ and src/) finds no previously-unknown invalid bound.**

## Performance

- **Duration:** ~75 min
- **Completed:** 2026-10-01
- **Tasks:** 3/3 completed
- **Files modified:** 5 (2 created, 3 modified)

## Accomplishments

- `src/planning/master.jl` gains `make_relaxed_oracle_model`/`derive_alpha_op_lb` (reusing `build_planning_oracle`'s exact assembly with a genuinely BOXED, non-pinned `p_import`) and `make_relaxed_follower_model`/`derive_alpha_x_lb` (the follower's `invest_op`-only relaxation, no coupling constraint) — both routed through `solve_with_retry!` (D-08), never a closed-form `0.0` shortcut.
- A second `derive_alpha_x_lb(f::FollowerLP; margin)` dispatch method extracts `corridor_cap`/`x_inv_max`/`T`/`c_inv`/`c_op` directly off a pre-built `FollowerLP` (via JuMP's `coefficient(objective_function(...), ...)`), confirmed to agree with the `follower_kwargs`-NamedTuple method to within `1e-8` on identical parameters.
- `build_master`'s `α_op_lb`/`α_x_lb` are now `Union{Symbol,Real}`, defaulting to `:auto`, resolved via a new opt-in `bounds_ctx` keyword; an explicit bound exceeding the derived minimum + `ALPHA_LB_REJECTION_TOL` throws `ArgumentError` at build time. When `bounds_ctx === nothing` (every pre-existing call site), the resolution is the byte-identical explicit-value path — confirmed by code inspection (no `derive_*` call on that path) and by re-running `test_planning_master.jl`'s/`test_planning_hardening.jl`'s/`test_planning_benders*.jl`'s/`test_planning_certification*.jl`'s/`test_planning_goldens.jl`'s/`test_planning_master_integer.jl`'s/`test_planning_nash.jl`'s own pre-existing `@testitem`s (all green, see Deviations/verification below).
- `α_x_lb`'s build-time validation is honestly SKIPPED (never silently "passed") when `bounds_ctx.follower_kwargs === nothing` — the documented `DistributorView` scope limit — while `α_op_lb` on the SAME call remains fully resolved/validated.
- `test/test_planning_master.jl` gains 7 new `@testitem`s covering: the byte-identical regression guard, genuine `:auto` resolution, build-time rejection of an over-high `α_op_lb`/`α_x_lb`, a direct numeric cross-check of `test_planning_hardening.jl`'s own T=8 finding (`-5.0` rejected, `-50.0` valid) via `TSODSO.derive_alpha_op_lb` called directly, the `FollowerLP`-dispatch agreement, and the honest-skip scope limit.
- `test/test_planning_noninteger.jl`'s PVAL-04 header comment documents the 4 non-`build_`-prefixed derivation helpers as intentionally out of the registry's scope (registry Dict/`EXEMPT` set unchanged).
- `.planning/phases/.../scripts/audit_alpha_bounds.jl` independently re-verifies the T>1 census (test/ AND src/ call sites, including `run_nash!`'s indirection) and runs the new derivation formula against the one T>1 shape found, exiting 0; `30-ALPHA-AUDIT.md` consolidates the finding: **no previously-unknown invalid bound**.

## Task Commits

Each task was committed atomically:

1. **Task 1: `:auto` α-bound derivation + `build_master` rejection logic** - `32eb115` (feat)
2. **Task 2: Extend `test_planning_master.jl` for `:auto`, rejection, and no-regression** - `ac4c5cf` (test)
3. **Task 3: Repo-wide T>1 α-bound audit (BILEV-05 Pitfall 4)** - `e414981` (test)

**Plan metadata:** (this commit)

## Files Created/Modified

- `src/planning/master.jl` - adds `ALPHA_LB_MARGIN`/`ALPHA_LB_REJECTION_TOL` (measured constants), `make_relaxed_oracle_model`/`derive_alpha_op_lb`/`make_relaxed_follower_model`/`derive_alpha_x_lb` (+ `FollowerLP` dispatch), and extends `build_master`'s signature/body for `:auto`/`bounds_ctx`/rejection
- `test/test_planning_master.jl` - 7 new `@testitem`s (BILEV-05 coverage)
- `test/test_planning_noninteger.jl` - PVAL-04 header comment documents the 4 derivation helpers' registry exemption (no registry/EXEMPT Dict change)
- `.planning/phases/30-socp-in-the-loop-benders-on-a-multi-bus-feeder/scripts/audit_alpha_bounds.jl` - standalone repo-wide T>1 audit script
- `.planning/phases/30-socp-in-the-loop-benders-on-a-multi-bus-feeder/30-ALPHA-AUDIT.md` - the audit report (census + verdict table + honest finding)

## Decisions Made

- **Measured constants, single shared probe:** `ALPHA_LB_MARGIN = ALPHA_LB_REJECTION_TOL = 1e-6`, both derived from ONE probe (the toy two-bus/`ToyElasticDevice` fixture at T=1, mirroring `test_planning_master.jl`'s own fixture) rather than two independent derivations, since both constants bound the same solver-tolerance-scale quantity on the same fixture.
- **No closed-form `0.0` shortcut for `α_x_lb`:** per RESEARCH.md Open Question 3's resolution, `derive_alpha_x_lb` always solves the relaxed LP (cheap, HiGHS) rather than assuming the trivial `x_inv=x_op=0` point is always optimal — robust to a future negative-cost fixture.
- **`derive_alpha_x_lb(::FollowerLP)` as an additive dispatch method** (not a new function name): keeps the PVAL-04 non-`build_`-prefix exemption scoped to one function identity with two sound call shapes.
- **`DistributorView` deliberately excluded:** no `derive_alpha_x_lb(::DistributorView)` method exists anywhere in `src/planning/` — its pooled per-distributor capacity constraint has no sound per-object relaxed minimum (full argument preserved for plan 30-04 Task 2). `build_master` treats `bounds_ctx.follower_kwargs === nothing` as the honest skip signal.
- **Audit scope widened to `src/`:** beyond the plan's own `test/`-only framing, the audit explicitly covers `src/planning/benders.jl`'s `build_master` call site and `src/planning/nash.jl`'s `run_nash!` indirection site, per the checker's BLOCKER 1/2 resolution baked into this plan.

## Deviations from Plan

### Auto-fixed Issues

None — no Rule 1/2/3 auto-fixes were needed; the implementation matched the plan's `<interfaces>`/`<action>` blocks closely enough that no bug, missing-critical-functionality, or blocking issue arose during execution.

### Other Deviations

**1. Audit script's `src/` call-site description corrected mid-task (documentation-only)**
- **Found during:** Task 3, writing `scripts/audit_alpha_bounds.jl`'s `src/`-census output.
- **Issue:** The first draft's printed description of `src/planning/benders.jl:741`'s `build_master` call site assumed it already passed `bounds_ctx` (anticipating plan 30-04's future wiring), which would misrepresent the CURRENT (pre-30-04) state of that line.
- **Resolution:** Corrected to describe today's actual call (`build_master(; master_kwargs..., T = T)`, no `bounds_ctx`) and separately note what plan 30-04 will change. Re-ran the script after the fix; output unchanged in substance (exit 0, same verdicts), only the descriptive text corrected.
- **Files affected:** `.planning/phases/30-socp-in-the-loop-benders-on-a-multi-bus-feeder/scripts/audit_alpha_bounds.jl`, `30-ALPHA-AUDIT.md`.
- **Committed in:** `e414981` (Task 3 commit — caught and fixed before commit).

---

**Total deviations:** 1 (documentation-only, no behavior/scope impact).
**Impact on plan:** None on substance — the audit's numeric findings and honest-finding statement are unaffected; only a descriptive sentence was corrected before committing.

## Issues Encountered

None beyond the one documentation deviation above. Broader regression verification (beyond the plan's own `<verify>` scripts) was run across `test_planning_benders.jl`, `test_planning_certification.jl`, `test_planning_goldens.jl`, `test_planning_master_integer.jl`, `test_planning_benders_integer.jl`, and `test_planning_nash.jl` via the project's `@testitem` emulator (TestItemRunner does not resolve under `--project=.` in this repo) — all pre-existing items remain green under the new `build_master` signature, confirming the byte-identical opt-out path holds repo-wide, not just in the files this plan directly touched.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- Plan 30-04 can now wire `solve_stackelberg!` to ALWAYS construct and pass `bounds_ctx` into its internal `build_master(...)` call (including through `run_nash!`), making `α_op_lb` live-validated at build time on every invocation, and `α_x_lb` live-validated wherever a sound derivation exists (a `FollowerLP`-shaped follower or explicit `follower_kwargs`) or honestly skipped for `DistributorView`.
- `30-ALPHA-AUDIT.md` gives plan 30-04 a ready-made, independently-verified list of every T>1 call site to carry forward (currently: just the one, already-valid, `test_planning_hardening.jl` T=8 fixture).
- No blockers.

---
*Phase: 30-socp-in-the-loop-benders-on-a-multi-bus-feeder*
*Completed: 2026-10-01*

## Self-Check: PASSED

All 6 claimed files found on disk; all three task commit hashes (32eb115, ac4c5cf,
e414981) found in `git log --oneline --all`.

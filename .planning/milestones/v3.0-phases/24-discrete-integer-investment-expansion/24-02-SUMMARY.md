---
phase: 24-discrete-integer-investment-expansion
plan: 02
subsystem: planning
tags: [jump, highs, milp, benders, cut-reuse, pval-04, test-guard]

# Dependency graph
requires:
  - phase: 24-discrete-integer-investment-expansion
    plan: 01
    provides: "BendersMasterInteger struct + build_master_integer builder (K-binary-
      expansion MILP master), with .b (raw binaries) and .L (pinned recourse lower
      bound) already exposed on the struct"
provides:
  - "add_optimality_cut!(::BendersMasterInteger, ...)/add_feasibility_cut!(::BendersMasterInteger, ...)
    methods — the continuous Benders cuts REUSED unmodified, verified valid at every
    binary corner (RESEARCH.md Finding 2 / Geoffrion GBD)"
  - "test_planning_noninteger.jl's PVAL-04 registry + EXEMPT list closing the cross-wave
    gap left by 24-01 (build_master_integer now registered, source-scan tripwire
    satisfied, exemption self-verified)"
affects: [24-03-cut-algebra-trace, 24-04-benders-loop-integration, 24-05-certification,
  24-06-literate-docs]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "New struct, new methods of the SAME generic function (add_optimality_cut!/
      add_feasibility_cut!) — option (a) from RESEARCH.md Pattern 2, chosen over an
      abstract-supertype retrofit, keeping master.jl/BendersMaster at zero touch."
    - "Per-builder EXEMPT allowlist inside a source-scan tripwire test, self-verified
      by a subset-of-registry-keys assertion so the allowlist cannot silently go
      stale (name renamed/removed without updating the list)."
    - "Exemption is a VERIFIED statement, not a skip: the exempt builder's own
      no-binaries check is inverted to `!isempty(offenders)`, so an accidental
      regression to binary-free would itself fail loudly."

key-files:
  created: []
  modified:
    - src/planning/master_integer.jl
    - test/test_planning_master_integer.jl
    - test/test_planning_noninteger.jl

key-decisions:
  - "Cut method bodies are a byte-for-byte transcription of master.jl's
    add_optimality_cut!/add_feasibility_cut! (same guard order/wording, same
    @constraint form, same push! NamedTuple shape), re-typed only on the first
    argument — per the plan's own <rationale>/<interfaces> blocks, this is
    deliberately a duplication, not a factoring, to keep master.jl untouched (D-05)."
  - "EXEMPT is a bare Set(['build_master_integer']), not a Dict/struct with metadata
    — kept minimally structured per the plan, but paired with its own
    subset-of-registry-keys self-check so drift (rename/removal) fails loudly
    rather than silently no-op'ing."
  - "The source-scan tripwire's `found == Set(keys(registry))` assertion and its
    exported-symbol semantic channel needed ZERO code changes — build_master_integer
    is exported from master_integer.jl (24-01) and lives under src/planning/, so both
    discovery channels already found it automatically once it became a registry key."

requirements-completed: [INT-01, INT-04]

# Metrics
duration: ~50min (includes a cwd-drift debugging detour, see Deviations)
completed: 2026-08-23
---

# Phase 24 Plan 02: Cut Mechanics + PVAL-04 Guard Scoping Summary

**Reused the continuous Benders optimality/feasibility cut algebra verbatim on the new
binary-expansion MILP master via two overloaded methods, and closed the deliberate
cross-wave PVAL-04 tripwire gap left by plan 24-01 with a self-verifying EXEMPT
allowlist.**

## Performance

- **Duration:** ~50 min wall clock (includes a cwd-drift verification detour — see
  Deviations)
- **Completed:** 2026-08-23T22:06:27Z
- **Tasks:** 2 completed
- **Files modified:** 3 (0 created, 3 modified)

## Accomplishments

- `src/planning/master_integer.jl` gains `add_optimality_cut!(::BendersMasterInteger, ...)`
  and `add_feasibility_cut!(::BendersMasterInteger, ...)` — new methods of the
  ALREADY-EXPORTED generic functions (no new export), with bodies transcribed verbatim
  from `master.jl`'s continuous methods (same `ArgumentError` guard order, same
  `@constraint` form, same `push!` `NamedTuple` shape tagged `kind = :optimality`/
  `:feasibility`). Each docstring cites RESEARCH.md Finding 2 by name: `Q(y_inv)` is a
  partial minimization of a jointly-convex function over a jointly-convex, monotonically
  expanding feasible set, hence convex in the continuous relaxation of `y_inv`; because
  `y_inv` is linear in the binary vector `b`, any subgradient cut derived at a trial `z_k`
  is a globally valid supporting hyperplane at every one of the `2^K` binary corners
  (Geoffrion's GBD, 1972).
- `test/test_planning_master_integer.jl` gains a new cut-row-growth regression mirroring
  `test_planning_master.jl`'s own pattern: builds a `BendersMasterInteger`, appends one
  optimality cut and one feasibility cut via the new methods, and asserts
  `num_constraints` grows by exactly 2 while `num_variables` is unchanged (cuts append
  rows, never columns) — the MILP analog of the continuous regression.
- `test/test_planning_noninteger.jl`'s PVAL-04 registry now includes
  `"build_master_integer"` (D-12 fixture parameters) alongside the four continuous
  builders, satisfying D-07's source-scan tripwire (the builder MUST be discovered/
  registered, never omitted, to dodge the guard). An explicit
  `EXEMPT = Set(["build_master_integer"])` (D-06: a per-builder carve-out, never a
  conditional one) is introduced immediately after the registry, with a NEW
  self-verifying assertion (`EXEMPT ⊆ Set(keys(registry))`) that fails loudly if the
  allowlist ever drifts out of sync with the registry. The per-builder loop branches on
  `name in EXEMPT`: the exempt entry asserts `!isempty(offenders)` (T-24-05 mitigation —
  a VERIFIED statement that this builder genuinely has binaries, not a blind skip), while
  every other (non-exempt) entry runs the EXISTING unmodified
  `@test isempty(offenders) || error(...)` check. The source-scan tripwire and its
  exported-symbol semantic channel needed zero edits — both discovery channels already
  find `build_master_integer` automatically (exported, lives under `src/planning/`).

## Task Commits

Each task was committed atomically:

1. **Task 1: add_optimality_cut!/add_feasibility_cut! for BendersMasterInteger** —
   `0651555` (feat)
2. **Task 2: PVAL-04 registry + EXEMPT scoping for build_master_integer** — `5bb1f31`
   (test)

_No plan-metadata commit — STATE.md/ROADMAP.md/REQUIREMENTS.md updates are owned by the
orchestrator per this plan's execution constraints._

## Files Created/Modified

- `src/planning/master_integer.jl` — appended `add_optimality_cut!`/
  `add_feasibility_cut!` methods for `BendersMasterInteger`, after the existing
  `solve_master!` (struct → builder → solve → cuts section order preserved). No export
  line changes (methods of already-exported generics).
- `test/test_planning_master_integer.jl` — new `@testitem` "persistent cut-row growth"
  mirroring `test_planning_master.jl`'s own regression.
- `test/test_planning_noninteger.jl` — registry gains `"build_master_integer"`; new
  `EXEMPT` set + self-verifying subset assertion; per-builder loop branches on
  membership in `EXEMPT`.

## Decisions Made

- **Verbatim transcription over factoring.** The two new methods duplicate ~20 lines of
  algebra each from `master.jl` rather than introducing a shared helper or an abstract
  supertype — the plan's own `<rationale>` explicitly chose this to keep `master.jl`
  completely untouched (verified: `git diff 937ae74 HEAD -- src/planning/master.jl` is
  empty), the strictest reading of D-05.
- **EXEMPT is self-verifying, not a bare list.** Added a dedicated assertion
  (`EXEMPT ⊆ Set(keys(registry))`) beyond what the plan's literal task text described,
  because the plan's own `<plan_specific_requirements>` explicitly called for the
  allowlist to be "self-verifying ... don't just add a bare string to an array." This is
  a Rule 2 (missing critical functionality per an explicit requirement) addition, not
  scope creep — the plan text asked for it, my first draft under-delivered it, corrected
  before committing.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] Bash tool cwd drifted to the main checkout instead of the
worktree during verification, producing a false MethodError**
- **Found during:** Task 1 verification (the plan's own `<verify>` automated script).
- **Issue:** The plan's `<verify>` blocks are written as `cd /home/pedro/programming/TSO-DSO && julia ...`. Running that literally from this worktree-isolated agent silently
  operated on the MAIN checkout (`/home/pedro/programming/TSO-DSO`), not this agent's
  worktree (`/home/pedro/programming/TSO-DSO/.claude/worktrees/agent-a8420b6bd7457c3b5`).
  Both directories are named similarly but are DIFFERENT git worktrees with different
  file contents. The `julia` invocation there loaded the UNMODIFIED `master_integer.jl`
  (no cut methods yet), producing a genuine `MethodError: no method matching
  add_optimality_cut!(::BendersMasterInteger, ...)` that looked exactly like a real bug
  in my new code.
- **Fix:** Diagnosed via `grep -rn "function add_optimality_cut!" <path>` run against
  BOTH directories, confirming the edit was correctly present in the worktree but absent
  from the main checkout being queried. All subsequent verification commands ran with an
  explicit `cd` (or bare, relying on the tool's persisted cwd) to the worktree path only.
  No code was changed as a result — this was purely a verification-environment
  diagnostic, not a code defect.
- **Files modified:** None (diagnostic only).
- **Verification:** Re-ran the identical `<verify>` script content, this time confirmed
  to execute inside the worktree (`pwd` checked immediately beforehand); both Task 1's
  and Task 2's `<verify>` scripts, plus a full inline reproduction of the PVAL-04
  `@testitem` body (fixtures manually inlined, since `Phase6Fixtures`/`ToyDeviceFixture`
  are TestItems `@testmodule`s unreachable from a raw script — same workaround 24-01
  documented), all passed.
- **Committed in:** N/A (no code change; documented here per the deviation-tracking
  requirement since it consumed meaningful verification time and is a useful trap
  record for future plans in this same phase).

---

**Total deviations:** 1 (Rule 3 — a verification-environment trap, not a code fix).
**Impact on plan:** None on the delivered code — both tasks' `<verify>` scripts and the
full PVAL-04 `@testitem` logic were confirmed passing once run against the correct
worktree path. No scope creep, no algebra change.

## Issues Encountered

None beyond the cwd-drift verification detour documented above. The known,
deliberately-red `test_planning_noninteger.jl` gap inherited from 24-01 is now CLOSED:
the full `@testitem` body (registry membership, EXEMPT self-check, per-builder no-
binaries/has-binaries assertions, source-scan tripwire, exported-symbol semantic
channel) was reproduced end-to-end in a standalone script (fixtures inlined, mirroring
24-01's own workaround for TestItems `@testmodule` unreachability from raw scripts) and
confirmed to pass in full: `ALL PVAL-04 checks passed`.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

`BendersMasterInteger` now fully participates in the Benders cut mechanics alongside
`BendersMaster`: `add_optimality_cut!`/`add_feasibility_cut!` fire identically on both
master types, `master.b` (raw binaries) and `master.L` (pinned recourse lower bound) are
both already exposed (from 24-01) and untouched by this plan, and the PVAL-04 guard is
fully green and closed (no cross-wave gap remains). Plan 24-03 can now add the genuinely
new Laporte-Louveaux/no-good cut algebra directly against `master.b`/`master.L` without
any further scaffolding, and 24-04 can wire the `master = nothing` injection into
`solve_stackelberg!` knowing both cut families already coexist correctly on the integer
master.

No blockers.

---
*Phase: 24-discrete-integer-investment-expansion*
*Completed: 2026-08-23*

## Self-Check: PASSED

All 4 created/modified files confirmed present on disk; both task commit hashes
(`0651555`, `5bb1f31`) confirmed present in `git log --oneline`.

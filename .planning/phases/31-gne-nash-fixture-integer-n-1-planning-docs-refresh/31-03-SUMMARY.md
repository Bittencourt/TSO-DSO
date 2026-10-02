---
phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
plan: 03
subsystem: planning
tags: [julia, jump, nash-equilibrium, gne, game-theory, benders]

requires:
  - phase: 13 (v2.0)
    provides: SharedTransmission / run_nash! / run_nash_probe (Gauss-Seidel diagonalization, NASH-01..04)
  - phase: 30 (v4.0)
    provides: solve_joint_reference pattern (monolithic joint-model cross-check), inexact_policy/certificates on solve_stackelberg!/run_nash!
provides:
  - run_nash_probe's seeds accept a (; z0, x_inv0) NamedTuple (additive, backward-compatible) alongside the original bare z0 matrix
  - interior-cap toy fixture (x_inv_max=[1.0,1.0]) demonstrating a genuine 1-D investment-split GNE continuum, probed and regression-pinned
  - solve_variational_equilibrium(specs; T, corridor_cap, x_inv_max, c_inv, c_op) — monolithic joint-solve VE selector with no-profitable-deviation certification
affects: [31-04, 31-05, 31-06, docs/writeups/stackelberg_vs_psr_n1n2.typ, docs/writeups/modelo_stackelberg_dso_unico.typ]

tech-stack:
  added: []
  patterns:
    - "Seed-shape dispatch (bare matrix OR NamedTuple) for backward-compatible API extension"
    - "Monolithic joint JuMP model generalizing a per-player builder from N=1 to N via a per-distributor ModelContext over one shared Model, with JuMP object-dictionary unregister() to avoid formulation-level name collisions"

key-files:
  created: []
  modified:
    - src/planning/nash.jl (run_nash_probe seed dispatch; new solve_variational_equilibrium)
    - test/test_planning_nash.jl (interior-cap GNE fixture + probe test; control regression tightened; 2 new VE certification testitems)

key-decisions:
  - "Interior-cap fixture uses x_inv_max=[1.0,1.0] (margin 0.3 above the derived S_min=0.7) — safely non-binding everywhere on the GNE interval, not a de facto Inf"
  - "solve_variational_equilibrium writes the shared capacity[t] row directly over z[i,t] (not a separate x_op), dropping build_shared_transmission's per-distributor-dualizable x_op as unnecessary for a single monolithic solve"
  - "JuMP object-dictionary unregister() after each distributor's power-flow contribute! call — the formulation-generic fix for sharing one Model across N distributors (every AbstractPowerFlow.contribute! registers fixed names like :v/:P/:Q directly on the model)"

requirements-completed: ["BILEV-06"]

duration: 55min
completed: 2026-10-02
---

# Phase 31 Plan 03: GNE Nash Fixture — Continuum Exposure + Variational Equilibrium Summary

**`run_nash_probe` now exposes investment-split GNE multiplicity via `(;z0,x_inv0)` seeds, and a new `solve_variational_equilibrium` selects the VE via one monolithic joint JuMP solve, certified by a no-profitable-deviation re-solve against `solve_stackelberg!`.**

## Performance

- **Duration:** ~55 min
- **Tasks:** 2 completed
- **Files modified:** 2 (`src/planning/nash.jl`, `test/test_planning_nash.jl`)

## Accomplishments

- `run_nash_probe`'s `seeds` entries now accept EITHER a bare `z0` matrix (unchanged,
  byte-identical default) OR a `(; z0, x_inv0)` NamedTuple that also forwards
  `run_nash!`'s own pre-existing `x_inv0` keyword — additive, backward-compatible.
- A new interior-cap toy fixture (`x_inv_max=[1.0,1.0]`, margin 0.3 above the derived
  `S_min=0.7`) demonstrates the genuine 1-D GNE continuum this probe extension exists to
  expose: 8-run probe (`x_inv0 ∈ {0.0,0.2,0.5,0.7}` × 2 orders) measured
  `x_inv_spread ≈ 0.6999` (> the 0.5 floor) while `z_spread ≈ 5.8e-4` stays near-zero —
  documented explicitly as a correct property of an investment-split continuum, not a
  probe bug. Every converged run's `(x_inv_1, x_inv_2)` sums to `S_min=0.7` within
  `atol=1e-3`.
- The pre-existing corner-cap control fixture (`x_inv_max=[0.3,0.3]`, unique equilibrium)
  is re-asserted as a tightened regression: `x_inv_spread < 1e-6`, `z_spread < 1e-6`
  (measured ~0.0 / ~1.11e-16).
- New `solve_variational_equilibrium(specs; T, corridor_cap, x_inv_max, c_inv, c_op)`:
  builds ONE monolithic joint model (generalizing
  `fixtures_planning_ieee13_short.jl`'s `solve_joint_reference` from N=1 to N players
  sharing one pooled `capacity[t]` row, writing it directly over each distributor's
  `z[i,t]`). Certified on the interior-cap fixture: VE's `(x_inv_1,x_inv_2)` sums to
  `S_min=0.7` with `z ≈ (0.7,0.7)`; the single shared multiplier `π_capacity` is finite
  by construction (one row, written once); a no-profitable-deviation re-solve against a
  freshly pinned `SharedTransmission` confirms neither distributor can improve by
  unilateral deviation (`solve_stackelberg!`'s own `UB` matches `cost_per_distributor` to
  ~4.3e-8). Agrees with the corner-cap control's pinned unique equilibrium
  (`z=[0.6,0.6]`, `x_inv=[0.3,0.3]`) when the equilibrium IS unique.

## Task Commits

Each task was committed atomically:

1. **Task 1: `run_nash_probe` seed-dispatch extension (x_inv0) + interior-cap GNE
   fixture** - `edd9731` (feat)
2. **Task 2: `solve_variational_equilibrium` — monolithic joint model selecting the
   VE** - `1f16a24` (feat)

_Note: both tasks touch the SAME two files (`src/planning/nash.jl`,
`test/test_planning_nash.jl`), as declared in the plan's own `files_modified`. Each
commit was split by reconstructing the exact Task-1-only intermediate state from
`git show HEAD:<path>` plus the precise edit text applied, re-formatted with the SAME
JuliaFormatter settings, and verified both content-identical (whitespace/comma-ignoring
diff) and functionally correct (full `planning nash` suite re-run) before each commit —
so each commit is a genuinely atomic, individually-revertable, individually-buildable
unit, not an artificial split of one combined diff._

## Files Created/Modified

- `src/planning/nash.jl` - `run_nash_probe`'s seed-dispatch extension + docstring
  (Task 1); new `solve_variational_equilibrium` function + docstring (Task 2)
- `test/test_planning_nash.jl` - interior-cap GNE fixture + probe testitem, tightened
  corner-cap control regression (Task 1); two new VE certification testitems (Task 2)

## Decisions Made

- `x_inv_max = [1.0, 1.0]` for the interior-cap fixture (margin 0.3 above the derived
  `S_min=0.7`) — Claude's discretion per CONTEXT.md, chosen to be safely non-binding
  everywhere on the GNE interval without being a de facto `Inf` (31-RESEARCH.md
  Pitfall 4).
- `solve_variational_equilibrium` writes the shared `capacity[t]` row DIRECTLY over
  `z[i,t]`, dropping `build_shared_transmission`'s separate `x_op[i,t]` identity-coupled
  variable — documented in the function's own header as a deliberate simplification
  (the dualizable `x_op` row only exists for `DistributorView`'s per-distributor Benders
  iteration, which a single monolithic solve does not need).
- Measured tolerances (not guessed): `x_inv_spread` floor `0.5` (measured ~0.6999,
  margin ~0.2); `z_spread` ceiling `0.01` (measured ~5.8e-4); no-profitable-deviation
  tolerance `1e-4` (measured diff ~4.3e-8).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] JuMP object-dictionary name collision across distributors sharing
one `Model`**
- **Found during:** Task 2 (first execution of `solve_variational_equilibrium` on N=2)
- **Issue:** Every `AbstractPowerFlow.contribute!` method (e.g. `LinDistFlow`) registers
  its OWN formulation-level variables/constraints under FIXED, NAMED symbols (`:v`,
  `:P`, `:Q`, `:vdrop`, ...) directly on the model's object dictionary — a SECOND
  distributor's `contribute!` call on the SAME shared `model` collided with
  `"An object of name v is already attached to this model"`. (`Aggregator`'s own device
  loop had already hit and fixed this exact class of bug in Phase 21 by switching to
  anonymous registration — the power-flow `contribute!` methods were not touched by that
  fix and still register named symbols.)
- **Fix:** Capture `JuMP.object_dictionary(model)`'s keys immediately before/after each
  distributor's own `contribute!(pf, ...)` call and `JuMP.unregister(model, name)` every
  newly-added name (JuMP's own sanctioned mechanism — removes only the `model[:name]`
  lookup, never the underlying variable/constraint objects, which stay fully live via
  `ctx_i.residuals`/`ctx_i.meta[:pf_vars]`). Formulation-generic: no hardcoded name list.
- **Files modified:** `src/planning/nash.jl`
- **Verification:** `solve_variational_equilibrium` now solves cleanly for N=2 on both
  the interior-cap and corner-cap fixtures (scratch probes + the 2 new testitems, all
  passing).
- **Committed in:** `1f16a24` (Task 2 commit)

**2. [Rule 1 - Bug] `cost_per_distributor` omitted the `-λ₀·z` pricing term**
- **Found during:** Task 2's own Test 3 (no-profitable-deviation certification) — the
  measured gap between `solve_stackelberg!`'s independently-computed `UB` and the VE's
  own `cost_per_distributor` was `2.8` (not noise-scale), exactly equal to
  `λ₀[1]*z[i,1] = 4.0*0.7`.
- **Issue:** The returned `cost_per_distributor[i]` subtracted `ctxs[i].meta[:objective]`
  alone (the device/aggregator utility only), but `solve_stackelberg!`'s own `UB`
  (`benders.jl`'s `cost_k = master.c_y*lb_res.y + follower_res.cost - oracle_res.cost`)
  subtracts the FULL oracle welfare `ctx.meta[:objective] - Σ_t λ₀[t]*p_import[t]` — the
  `-λ₀[t]*z[i,t]` pricing term lives in THIS function's own joint `@objective` assembly,
  never inside any per-distributor `ctx`.
- **Fix:** `cost_per_distributor[i]` now subtracts
  `(value(ctxs[i].meta[:objective]) - sum(specs[i].λ₀[t]*value(z[i,t]) for t in 1:T))`.
  After the fix, both distributors' `cost_per_distributor` matched the KNOWN, previously
  pinned single-distributor Stackelberg optimum `-0.245` (see PROJECT.md's own
  "y*=z*=0.7, cost −0.245" certification) to within ~4.3e-8.
- **Files modified:** `src/planning/nash.jl`
- **Verification:** Test 3's no-profitable-deviation assertion now passes with a
  solver-precision-scale margin (~4.3e-8, well inside the `1e-4` tolerance).
- **Committed in:** `1f16a24` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 — genuine bugs discovered and fixed
during implementation, both load-bearing for Test 3's own certification correctness).
**Impact on plan:** Both auto-fixes were necessary for `solve_variational_equilibrium`
to work AT ALL for N>1 (fix 1) and for its own certification test to be meaningful
rather than silently wrong (fix 2). No scope creep — both fixes are internal to the new
function this plan introduces.

## Issues Encountered

- **TestItemRunner top-level-const landmine (caught before committing):** an early draft
  of the interior-cap testitem defined its `S_MIN = 0.7` constant as a bare file-level
  `const` between `@testitem` blocks. TestItemRunner executes each `@testitem` body in an
  isolated module, so a top-level `const` outside any `@testitem`/`@testmodule` form is
  never guaranteed to be defined inside a testitem's own scope under the real runner
  (this file's own established convention is to inline fixture construction per
  `@testitem`, never share file-level state). Fixed before committing by moving `S_MIN`
  to a `let`-scoped local inside the testitem body itself.
- **DrWatson `gitpatch` noise in every checkpoint write (pre-existing, not fixed):**
  `run_nash!`'s `checkpoint_iteration!` calls DrWatson's `@tagsave` with its default
  `gitpatch=true`, which repeatedly attempts `git diff --no-index` against this
  worktree's own `.git` file (not a directory) and fails loudly on every single
  checkpoint — harmless (caught, logged, returns `nothing`) but extremely verbose
  (megabytes of git-usage-text output per scratch run). Pre-existing, out of this plan's
  scope (not touched by either task); noted here only because it made interactive
  debugging of scratch probes slow and noisy.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `run_nash_probe`'s seed-dispatch extension and `solve_variational_equilibrium` are
  both available for Plan 31-04 (BILEV-07, integer N>1) and Plan 31-06 (BILEV-08, docs
  refresh) to cite/build on.
- `docs/literate/nash_diagonalization.jl` executed end-to-end in the foreground after
  this plan's changes (exit 0) — no regression to the existing literate rung page.
- `test_planning_coupling.jl` (55/55) and `test_planning_noninteger.jl` (PVAL-04,
  43/43) both re-run clean — no new unregistered `build_*`-prefixed planning builder was
  introduced (`solve_variational_equilibrium` is intentionally NOT `build_`-prefixed).
- No blockers for Plan 31-04/31-05/31-06.

---
*Phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh*
*Completed: 2026-10-02*

## Self-Check: PASSED

- FOUND: `src/planning/nash.jl`
- FOUND: `test/test_planning_nash.jl`
- FOUND: `solve_variational_equilibrium` defined in `src/planning/nash.jl`
- FOUND: commit `edd9731` (Task 1)
- FOUND: commit `1f16a24` (Task 2)

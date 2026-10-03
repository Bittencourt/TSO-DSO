---
phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
fixed_at: 2026-10-02T20:00:00Z
review_path: .planning/phases/31-gne-nash-fixture-integer-n-1-planning-docs-refresh/31-REVIEW.md
iteration: 2
findings_in_scope: 3
fixed: 3
skipped: 0
status: all_fixed
---

# Phase 31: Code Review Fix Report (iteration 2)

**Fixed at:** 2026-10-02T20:00:00Z
**Source review:** .planning/phases/31-gne-nash-fixture-integer-n-1-planning-docs-refresh/31-REVIEW.md
**Iteration:** 2 (the iteration-1 report is kept at `31-REVIEW-FIX.iter1.md`)

**Summary:**
- Findings in scope (Critical + Warning): 3
- Fixed: 3
- Skipped: 0
- Also fixed (Info, trivial): IN-01 and IN-02. IN-03 is a liveness note and needed no code change (see below).

## Fixed Issues

### CR-01: `_integer_cycle_hit` still flags converging runs as CYCLED (oscillatory contraction)

**Files modified:** `src/planning/nash.jl`, `test/test_planning_nash_integer.jl`
**Commit:** deb70be
**Status:** fixed: requires human verification (this is a logic change to the predicate)

**Applied fix:**
- **Predicate:** condition 3 is now `residual >= h.residual`, with no `- atol` slack. Any strict decrease in residual between the matched sweeps now vetoes the match.
- **Docstring rewritten to cover:**
  - why the slack had to go: the history is scanned for any earlier sweep, and an oscillatory contraction `s_k = s* + c^k e` returns within `atol` of the state two sweeps earlier;
  - the corrected ω < 1 argument: only `z` is damped and `x_inv` is re-solved at the damped `z`, so `atol = ω·tol_outer/2` is a recurrence tolerance, not a guaranteed separation;
  - the ties caveat: the potential-game argument rules out cycles only when there are no ties, and the interior-cap fixtures do have tied best responses.
- **Consistency edits:** the "Cycle detection" section of `run_nash!` and the test-file comment now carry the same caveat.
- **Regression test (case 7):** the reviewer's sign-flipping geometric history (c = −0.9, ω = 1, tol_outer = 1e-4, fixed `b`), wrapped in a function to avoid TestItem scoping problems. The test asserts:
  - no prefix of the history is flagged;
  - the history really converges;
  - it is at least 44 sweeps long, past the point where the old predicate fired, so the pass is not vacuous.
- **Other tests:** added a residual drop of `1e-12` as a must-not-fire case. The existing period-1 and period-2 genuine-cycle cases still fire.
- **Check:** the scratch `cycle_osc.jl` now reports `converged at sweep 51` instead of a false cycle at sweep 44.

### WR-01: false claim "the VE set equals the GNE set" on the symmetric interior-cap fixture

**Files modified:**
- `src/planning/nash.jl`
- `test/test_planning_nash.jl`
- `docs/writeups/stackelberg_vs_psr_n1n2.typ` and `.pdf`
- `docs/writeups/modelo_stackelberg_dso_unico.typ` and `.pdf`

**Commit:** f852b9f

**Applied fix:**
- **Corrected statement, used everywhere:**
  - The VE set is the whole split segment `x_inv_1 + x_inv_2 = 0.7`, `z = (0.7, 0.7)`, with common multiplier 0.5. It is non-unique, and the returned point depends on the solver.
  - The GNE set is strictly larger. It also contains free-riding GNEs `x_inv_j = 0`, `z_j = 1.2 − p`, `p ∈ [0, 0.5]`, `x_inv_i = (1.9 − p)/2`, which have unequal multipliers. An example is `x = (0.95, 0)`, `z = (0.7, 1.2)`, multipliers `(0.5, ≈0)`.
  - So the VE still selects on this fixture, just not a single point.
- **`src/planning/nash.jl`:** corrected in the GNE caveat of `run_nash!`, in the section header of `solve_variational_equilibrium`, and in the uniqueness paragraph of its docstring.
- **`test/test_planning_nash.jl`:**
  - the interior-cap comment now says "the GNE set contains …" and notes the free-riding branch;
  - the CR-02 section comments no longer say "nothing is selected" or "VE set EQUALS the GNE set";
  - the testitem name now reads "(a strict subset of the GNE set)" instead of "(VE set = GNE set)".
- **Writeups (Portuguese kept):**
  - `stackelberg_vs_psr_n1n2.typ`, around line 227: a note that the segment does not cover every GNE (the free-riding branch).
  - same file, around line 233: replaced "o conjunto de VEs É o conjunto de GNEs … não há seleção" with the corrected statement.
  - `modelo_stackelberg_dso_unico.typ:192`: clarified that the VE continuum is a strict subset of the GNEs.
- **PDFs:** both recompiled with `~/.local/bin/typst compile` (exit 0) and staged with `git add -f`.

### WR-02: `integer.α_op_lb` / `α_x_lb` not validated at the boundary of `run_nash!`

**Files modified:** `src/planning/nash.jl`, `test/test_planning_nash_integer.jl`
**Commit:** fa10f5c

**Applied fix:**
- **`α_op_lb`:** must be `:auto` or a finite `Real`. Anything else raises `ArgumentError`.
- **`α_x_lb` (when the key is present):** must be a finite `Real`, with no `:auto`, because a `DistributorView` follower has no derivation for it. Anything else raises `ArgumentError`.
- **Order:** both checks run before any solve. This replaces the old `isfinite(get(...))` check, which threw a `MethodError` on `:auto`.
- **Docs:** updated the docstring guard list and the `# Throws` section.
- **Tests added to the WR-06 guard testitem:**
  - `α_op_lb ∈ (NaN, -Inf, Inf, :foo, "auto")`;
  - `α_x_lb ∈ (NaN, -Inf, :auto, "0.0")`.
  - Each must raise `ArgumentError`.
- **Testitem name:** updated to mention WR-02.

### IN-01 (Info): the own-multiplier check reparametrizes the `z` check

**Files modified:** `test/test_planning_nash.jl`
**Commit:** d7cdb34
**Applied fix:** comment only. It now states that `own_multiplier(z) = 1.2 − z`, so the check is a reparametrization of the `z ≈ 0.7` assertion and not independent evidence. The same holds for `μ_gne`.

### IN-02 (Info): stale test-file header describing the pre-WR-01 NaN-sentinel flow

**Files modified:** `test/test_planning_nash_integer.jl`
**Commit:** a82ce93
**Applied fix:** the header now describes the current flow, matching the docstring of `solve_follower!(::DistributorView, ...)` in `coupling.jl`:
1. re-solve once with presolve off;
2. return the NaN sentinel only if that re-solve still gives neither a feasible point nor a certificate;
3. with T > 1, route to the depth-bounded bisection;
4. otherwise raise a named error before `add_feasibility_cut!`.

### IN-03 (Info): no code change

The review itself calls the current behaviour sound: it fails loudly. None of the certified batches hit this case, and the alternative (bisecting toward `z_best`) is already documented in the review. Nothing was changed.

## Verification

Verification used the top-level `@testitem` emulator in the foreground. Each batch also loaded `fixtures_phase6.jl`, `fixtures_planning.jl` and `test_planning_oracle.jl`, so the counts below include the oracle testitems.

| Batch | Files | Pass | Fail | Notes |
|---|---|---|---|---|
| 1 | `test_planning_nash.jl` | 182 | 0 | 1 broken: the pre-existing `@test_skip` for CairoMakie, which is not installed |
| 2 | `test_planning_nash_integer.jl`, `test_planning_coupling.jl` | 108 | 0 | |
| 3 | `test_planning_certification.jl`, `test_planning_goldens.jl` | 67 | 0 | no golden moved |
| 4 | `test_planning_benders_integer.jl`, `test_planning_certification_integer.jl`, `test_planning_master_integer.jl` | 504 | 0 | |

- `docs/literate/nash_diagonalization.jl` ran in the foreground and exited 0.
- No new numerical tolerance was introduced. The only tolerance change removes the `atol` slack from the residual comparison.

**Process note:** as the launcher instructed, I worked directly on `main` with no worktree or recovery sentinel. The working tree is clean apart from this report, which is not committed.

---

_Fixed: 2026-10-02T20:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 2_

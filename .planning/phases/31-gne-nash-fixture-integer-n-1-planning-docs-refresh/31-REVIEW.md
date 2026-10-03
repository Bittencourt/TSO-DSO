---
phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
reviewed: 2026-10-02T23:30:00Z
depth: standard
iteration: 3
files_reviewed: 8
files_reviewed_list:
  - src/planning/nash.jl
  - src/planning/coupling.jl
  - src/planning/benders.jl
  - src/planning/master_integer.jl
  - test/test_planning_nash.jl
  - test/test_planning_nash_integer.jl
  - docs/writeups/stackelberg_vs_psr_n1n2.typ
  - docs/writeups/modelo_stackelberg_dso_unico.typ
findings:
  critical: 0
  warning: 0
  info: 2
  total: 2
status: issues_found
---

# Phase 31: Code Review Report (iteration 3, final)

**Reviewed:** 2026-10-02 · **Depth:** standard (fix range `deb70be..d7cdb34`) · **Status:** issues_found (Info only)

## Summary

This pass re-reviewed the iteration-2 fixes (CR-01, WR-01, WR-02, IN-01, IN-02). Resolved items are not raised again. No BLOCKER or WARNING remains. Two Info items cover documentation precision only.

### CR-01: cycle predicate with no slack — verified

The predicate is `residual >= h.residual || continue` at `nash.jl:356`.

**Missed cycles are always safe.**
- When the predicate does not fire, the loop continues to the `max_sweeps` `error(...)` at `nash.jl:1021`.
- `run_nash_probe` deliberately does not catch that error (T-13-10).
- So a missed genuine cycle still fails loudly. It is never returned as a silent non-converged result.
- An exact period-p recurrence of a deterministic sweep map has an identical per-sweep residual, so `>=` still fires on it. Only noise-perturbed cycles can slip through, and those hit `max_sweeps`.

**False flags on converging runs: none found for this game's structure.**
- I simulated linear Gauss-Seidel using `run_nash!`'s residual, damping, state and `atol` semantics, with best-response slopes derived from an SPD quadratic potential.
  - Setup: N ∈ {3, 4}, ω ∈ {1, 0.7, 0.5}, clamped to [0, 2].
  - Result: 300k trials, zero false flags.
  - Script: scratch `gs_sim3.jl`. It uses a verbatim copy of `_integer_cycle_hit`.
- The general claim does fail outside potential games (see IN-01).

**The new regression test discriminates.**
- The oscillatory history with c = −0.9 converges at sweep 51, because r_k = 0.019·0.9^(k−1) ≤ 1e-4 first holds there. The ≥ 44 sweep guard is therefore met.
- The old `- atol` slack fires at sweep 44, so the test fails on the old predicate and passes on the new one.
- The ω < 1 caveat (`x_inv` is re-solved, not interpolated) and the ties caveat in the docstring are accurate.

### WR-01: free-riding equilibria — verified mathematically

I re-derived the full equilibrium set of the symmetric fixture from the per-player KKT conditions:
- z_i = 1.2 − μ_i
- c_inv ≥ 2μ_i, with equality when 0 < x_i < 1
- capacity row z_1 + z_2 ≤ 2(x_1 + x_2)

**GNE set.** It is exactly the union of:
- the segment x_1 + x_2 = 0.7, z = (0.7, 0.7), μ = (0.5, 0.5);
- two free-riding branches: x_j = 0, μ_j = p ∈ [0, 0.5], z_j = 1.2 − p, x_i = (1.9 − p)/2 ∈ [0.7, 0.95].

**Other cases are infeasible.**
- If any x_i = 1, then μ_i ≥ 0.5, so z_1 + z_2 ≤ 1.9 < 2(1 + x_j). The row is slack, which forces μ = 0, a contradiction.
- If both x = 0 with p < 0.5, then z > 0 cannot satisfy z_1 + z_2 ≤ 0, so it is infeasible.

**VE set.** A common μ forces μ = 0.5, so the VE set is exactly the segment.

**Wording.** The corrected wording is correct in:
- `nash.jl` at all 3 sites
- both test files
- `stackelberg_vs_psr_n1n2.typ`
- `modelo_stackelberg_dso_unico.typ` ("subconjunto ESTRITO dos GNEs … equilíbrios de carona com multiplicadores desiguais")

**Leftovers.** A grep for the old "VE set = GNE set", "nothing is selected" and "seleção alguma" wording finds nothing in src, test, docs or scripts.

**Minor imprecision.** See IN-02 (endpoint p = 0.5).

### WR-02: boundary validation of `α_op_lb` and `α_x_lb` — verified

- Both guards (`nash.jl:615-632`) run inside the `integer !== nothing` block. That block comes before the seed `write_back!` and before any `optimize!` or `solve_*` call.
- Rejected inputs:
  - `α_op_lb`: NaN, ±Inf, any Symbol other than `:auto`, and Strings.
  - `α_x_lb`: NaN, ±Inf, `:auto`, and Strings. Previously `:auto` hit `MethodError: isfinite(::Symbol)`.
- An omitted `α_x_lb` still uses the derived default `_integer_alpha_x_lb`.
- A finite `α_op_lb` above the derived optimum is still rejected downstream in `build_master_integer`'s explicit branch (`master_integer.jl:285`), and no solve happens before that rejection either.
- The tests cover all of these cases.

### IN-01 and IN-02 of iteration 2 — resolved

- The test comment now states the reparametrization.
- The test-file header describes the presolve-off re-solve flow, consistent with `coupling.jl`.

## Info

### IN-01: The docstring's "on a contracting trajectory the residual strictly decreases" is stated too broadly

**File:** `src/planning/nash.jl:324-325` (and "the residual … of a converging run decreases", `:311-312`)

**Issue:**
- **Not a property of contraction:** a strictly decreasing ∞-norm residual is not a property of contracting Gauss-Seidel trajectories in general.
- **Counterexample (verbatim predicate copy, scratch `gs_sim2.jl`):**
  - N = 3, linear best responses, ω = 1, residual and state built exactly as in `run_nash!`.
  - Slopes `S = [-0.783 0.557 0.48; -0.704 0.241 -1.108; 0.91 0.998 -0.912]`, `z0 = [0.7339, 0.7154, 0.6945]`.
  - The trajectory converges at sweep 24.
  - At sweep 21 the state is within `atol` of sweep 19, and the residual has grown from 1.07e-4 to 2.15e-4.
  - The predicate therefore reports a false CYCLED at sweep 21.
- **Why it does not happen in `run_nash!`:**
  - Those slopes are not potential-consistent: sign(S_ij) ≠ sign(S_ji).
  - `run_nash!`'s game is a generalized potential game: separable costs, coupling only through the shared row.
  - With potential-consistent slopes, 300k trials gave no false flag.
- **Not proven in general:** this is evidence, not a proof. Inexact inner best responses also break the exact-potential argument. The docstring itself notes about 2e-4 deviations of the Benders best response on flat optima.

**Fix:** scope the sentence. For example: "for exact best responses of this generalized-potential game the residual has not been observed to rise near convergence (empirically, no false flag across 300k potential-consistent linear Gauss-Seidel trials). It is NOT a general property of contracting maps: non-potential N ≥ 3 sweeps can transiently increase the ∞-norm residual."

### IN-02: The free-riding branch is described as "off the segment" with "unequal multipliers" for p ∈ [0, 0.5], but p = 0.5 lies on the segment with equal multipliers

**Files:**
- `src/planning/nash.jl:386-389, 1281-1284, 1328-1331`
- `docs/writeups/stackelberg_vs_psr_n1n2.typ:227, 233`
- `test/test_planning_nash.jl:697-700, 1183-1185`

**Issue:** at p = 0.5 the branch gives x_j = 0, z_j = 0.7, x_i = 0.7. That is the segment's endpoint, with μ = (0.5, 0.5). The statements are true of every point except that endpoint.

**Fix:** write `p ∈ [0, 0.5)` wherever the text says "off the segment" or "unequal multipliers". Alternatively, add a note that the branch meets the segment at its endpoint p = 0.5.

---

_Reviewed: 2026-10-02_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Scratch evidence (not committed): `/tmp/claude-1000/-home-pedro-programming-TSO-DSO/981f784b-8b89-4fdd-b64d-2c7c39f9b271/scratchpad/gs_sim2.jl`, `gs_sim3.jl`, `cycle_iter3_fast2.jl`_

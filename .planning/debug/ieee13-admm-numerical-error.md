---
slug: ieee13-admm-numerical-error
status: investigating
trigger: "IEEE-13 ADMM mid-loop DSO SOCP fails with Clarabel NUMERICAL_ERROR at iteration 28, breaking 4 CI test items. Root cause is characterized and a fix is experimentally confirmed; this session is to land the fix (C1) and investigate the underlying conditioning (C2)."
created: 2026-08-25
updated: 2026-08-25
---

# Debug: IEEE-13 ADMM mid-loop DSO SOCP `NUMERICAL_ERROR`

## Symptoms

**Expected behavior**
`run_scenario(Scenario(name="phase8-fixture", feeder=:ieee13, strategy=:admm, seed=7, T=24))`
converges. Measured good behavior: **58 ADMM iterations**, welfare ≈ `-4822.9036`.

**Actual behavior**
The mid-loop DSO-OPT solve throws at ADMM **iteration 28**:

```
Solve failed — refusing to trust results:
  termination_status : NUMERICAL_ERROR
  primal_status      : OTHER_RESULT_STATUS
  dual_status        : OTHER_RESULT_STATUS
  raw_status         : NUMERICAL_ERROR
```

Throw site: `assert_solved!` at `src/core/status.jl:57`, called from `solve_dso!` at
`src/admm/DsoOpt.jl:457`, from `solve_admm` at `src/admm/solve_admm.jl:439`.

State at iteration 27 (the last successful one) — NOT diverging, nearly converged:
`ρ = 200.0`, `‖r‖ = 0.002011277584511157` vs `ε_pri = 0.001643856930878517`,
`‖s‖ = 0.13358114963308557` vs `ε_dual = 0.0755309888770254`.

**CI impact** (run 32791955335, commit `304db38`) — 4 items across the matrix:
- Julia 1.10 & 1.11: `test/test_experiments.jl` — "EXP-01 scenario admm" (:53),
  "INFRA-04 same-seed repro admm" (:175), "INFRA-04 seed sensitivity admm" (:196)
- Julia 1.12: those pass; `test/test_admm_adaptive.jl:56` fails instead with the SAME
  `NUMERICAL_ERROR` signature.

**Timeline**
Last green CI run: `baaa94f` (2026-07-27). `git bisect` over 225 commits (clean worktrees,
byte-identical committed Manifests across the whole range) returned first-bad =
**`3077a02` feat(20-04): ac_dual_fallback_price**.

**Reproduction**
Clean detached worktree at `d8e8999`, then:
`julia +1.10 --project=. -e 'using TSODSO; TSODSO.run_scenario(TSODSO.Scenario(name="t", feeder=:ieee13, strategy=:admm, seed=7, T=24))'`
Deterministic — 5/5 failures observed on a failing toolchain.

## Evidence

- timestamp: 2026-08-25 — **Bisect first-bad `3077a02` is PURELY ADDITIVE and never called on
  this path.** It adds `src/models/ac_dual_fallback.jl` (one new function, one export, one
  `const`; no method extension of any existing generic, no type piracy) plus a 1-line
  `include(...)` in `src/TSODSO.jl`. `run_scenario(:admm)` never calls it.
  A/B at that exact commit:
  | `src/TSODSO.jl` at `3077a02`            | Result                                   |
  |-----------------------------------------|------------------------------------------|
  | with `include("models/ac_dual_fallback.jl")` | `NUMERICAL_ERROR` at iter 28        |
  | that one line commented out              | converges, 58 iters, `-4822.903620476632` |
  => Adding UNREACHABLE code flips the outcome. This is a codegen/precompile-level
  floating-point perturbation, NOT a logic regression in Phase 20-04.

- timestamp: 2026-08-25 — **Julia version matrix** (clean checkout @ `d8e8999`):
  | Julia   | Result                                  |
  |---------|-----------------------------------------|
  | 1.10.11 | `NUMERICAL_ERROR`                       |
  | 1.11.9  | `NUMERICAL_ERROR`                       |
  | 1.12.7  | converges, 58 iters, `-4822.903625595291` |
  | 1.12.5  | `NUMERICAL_ERROR`                       |
  The flip happens at a **patch** bump inside 1.12. Matches CI exactly (CI runs 1.12.7, where
  `test_experiments` passes and `test_admm_adaptive` fails instead). Each (tree x version) pair
  is STABLE — this is not run-to-run noise.

- timestamp: 2026-08-25 — **The existing retry ladder rescues it at rung 2.** Patched
  `solve_dso!`'s mid-loop branch with the 4-rung `solve_with_retry!` ladder inline (preserving
  `allow_almost = true` semantics) in a throwaway worktree:
  ```
  PATCHED julia +1.11 : RETRY_RESCUED at rung 2  PROBE OK iters=58 welfare=-4822.903616694139
  PATCHED julia +1.10 : RETRY_RESCUED at rung 2  PROBE OK iters=58 welfare=-4822.903616694139
  ```
  Rung 2 is `static_regularization_constant => 1e-6`. The rescued answer is the SAME optimum —
  every converging environment agrees to ~9 significant figures (relative spread ~2e-9), at an
  identical 58 iterations. The ladder recovers the solution Clarabel was already converging to;
  it does not paper over a divergence.

- timestamp: 2026-08-25 — **`MOI.NUMERICAL_ERROR` is ALREADY in `RETRYABLE_STATUSES`**
  (`src/planning/retry.jl`). The infrastructure exists and is already deemed appropriate for
  exactly this status; `solve_dso!` simply bypasses it by calling `assert_solved!` directly.

- timestamp: 2026-08-25 — **`assert_solved!` calls `optimize!` internally**
  (`src/core/status.jl:44`), so each ladder rung genuinely re-solves rather than re-reading a
  stale result. The retry design is sound for this call site.

- timestamp: 2026-08-25 — **The duals objection does not apply to the failing solve.** The
  failure is the MID-LOOP call (`check_exact = false, strict = false`), which runs
  `assert_solved!(dso.model; dual = false, allow_almost = true)`. `solve_admm.jl`'s own comment
  confirms the DSO dual is never read mid-loop — the transactive price is the outer multiplier
  λ, not `dual(balance_p)`. So escalating regularization there cannot contaminate published
  prices.

## Eliminated

- hypothesis: "This is the documented ~55% Clarabel flake that `test/fixtures_retry.jl`
  was built for." — ELIMINATED. It fails 5/5 deterministically on a failing toolchain, not
  ~55%. The `retry_flaky_admm_solve` helper never fired anywhere in CI run 32791955335
  (`grep` for its `@warn` returns 0 hits on all three Julia jobs). It also re-calls with NO
  input perturbation, so by construction it cannot rescue a deterministic failure.

- hypothesis: "A dependency/solver version changed." — ELIMINATED. All committed Manifests
  (`Manifest.toml`, `-v1.10`, `-v1.11`, `-v1.12`) are byte-identical between the last-green
  `baaa94f` and `304db38`. Clarabel is 0.11.1 on both sides.

- hypothesis: "Phase 20-04 introduced a logic bug in the ADMM/pricing path." — ELIMINATED by
  the additive-include A/B above: the offending commit's only reachable effect on this code
  path is that its code EXISTS in the module.

## Current Focus

hypothesis: The IEEE-13 ADMM configuration sits on a numerical knife-edge: at iteration 28
  (ρ = 200, residuals near tolerance) the DSO SOCP is ill-conditioned enough that Clarabel's
  default regularization fails, and any perturbation of the compiled code (an unreachable
  `include`, a Julia patch bump) decides which side of the edge a given build lands on. The
  mid-loop solve has no conditioning-escalation path even though the project already ships one.

test: Wire the mid-loop DSO solve through `solve_with_retry!` and confirm the previously
  failing toolchains converge; separately characterize WHY the iteration-28 SOCP is
  ill-conditioned.

expecting: Rescue at rung 2 on Julia 1.10/1.11, 58 iterations, welfare agreeing with the
  known-good value to ~1e-9 relative.

next_action: |
  C1 (land the fix):
    1. Add an additive `allow_almost::Bool = false` kwarg to `solve_with_retry!`
       (`src/planning/retry.jl`) and thread it into its internal
       `assert_solved!(model; dual = dual, allow_almost = allow_almost)` call. Default `false`
       keeps every existing planning-layer caller BYTE-IDENTICAL — verify that claim, don't
       assume it.
    2. Route `solve_dso!`'s MID-LOOP branch (`src/admm/DsoOpt.jl:457`, the `strict = false`
       path) through `solve_with_retry!(dso.model; dual = false, allow_almost = true)`.
    3. Decide DELIBERATELY whether the `strict = true` FINAL solve also gets the ladder. It
       reads duals (`dual = true`) and those duals ARE the published transactive prices;
       rung 4's `static_regularization_constant = 1e-5` could perturb them. Default position:
       do NOT change the final solve in this task; if changed, prove price impact is below the
       project's own DADP tolerances.
    4. Confirm INFRA-04 bit-for-bit reproducibility still holds — `test_experiments.jl`'s
       "INFRA-04 same-seed repro admm" asserts `r1.welfare == r2.welfare` EXACTLY. Note
       `solve_with_retry!` mutates optimizer attributes PERMANENTLY and never restores them
       (documented sticky-escalation contract), so two `run_scenario` calls in one process
       build fresh models and should each escalate identically — but MEASURE it.
  C2 (investigate the conditioning): characterize why the iteration-28 SOCP is ill-conditioned
    (dump Clarabel's coefficient/RHS ranges at that iterate; examine how the ρ-scaled quadratic
    penalty scales the Hessian as adaptive-ρ climbs to 200). C1 is robustness; C2 is the
    explanation. Do not let C2 block C1.

## Resolution

root_cause:
fix:
verification:
files_changed:

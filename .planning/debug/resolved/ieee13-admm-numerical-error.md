---
slug: ieee13-admm-numerical-error
status: resolved
trigger: "IEEE-13 ADMM mid-loop DSO SOCP fails with Clarabel NUMERICAL_ERROR at iteration 28, breaking 4 CI test items. Root cause is characterized and a fix is experimentally confirmed; this session is to land the fix (C1) and investigate the underlying conditioning (C2)."
created: 2026-08-25
updated: 2026-08-25
archived: 2026-08-25
archived_reason: "CI run 32910604313 on 9ed6185 green across all 5 jobs — Julia 1.10 and 1.11 (the toolchains that reproduced NUMERICAL_ERROR deterministically) and 1.12 (which failed test_admm_adaptive with the same signature) all pass on the real runners."
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

- timestamp: 2026-08-25 (C1 landing) — **REFINEMENT of the duals-objection entry above: the
  escalation IS sticky, and it DOES reach the final strict solve.** `solve_with_retry!`'s WR-01
  contract mutates optimizer attributes PERMANENTLY, and `dso` is BUILD-ONCE — so once the
  mid-loop rescue escalates to rung 2, the remaining mid-loop iterations *and* the final
  `strict = true` solve all run at `static_regularization_constant = 1e-6`. The original entry's
  conclusion still stands, but for a different reason than "the escalated model is never used
  for prices": the published ADMM price is `dadp == λ`, the OUTER multiplier
  (`src/admm/solve_admm.jl:828,889`), never a dual of `dso.model`; the escalation only ever
  fires where the alternative is a hard crash; and the measured impact is below the
  cross-environment noise floor (rescued welfare `-4822.903616694139` vs `-4822.903620476632`
  and `-4822.903625595291`, i.e. 7.8e-10 / 1.8e-9 relative, inside the ~2e-9 spread the
  natively-converging builds already show among themselves, at an identical 58 iterations).
  Documented inline at the call site rather than papered over.

- timestamp: 2026-08-25 (C1 landing) — **The test environment cannot be used on a FAILING
  toolchain.** `test/Manifest.toml` is unversioned and resolves only on Julia 1.12 (on 1.10/1.11
  it dies with `UndefVarError: StaticData` from PrecompileTools), and TestItemRunner cannot run
  under `--project=.` in this repo. Verification on 1.10 therefore ran the `@testitem` bodies
  VERBATIM through a minimal `@testitem`/`@testmodule` macro shim under `--project=.`
  (hoisting `using`/`import` to module top level, mapping `setup=[X]` to `import Main: X`).
  No test source or expectation was modified. Separately, `julia +1.11 --project=.` is blocked
  on this working tree by the pre-existing uncommitted `Project.toml` drift (CairoMakie promoted
  to a hard dep, absent from `Manifest-v1.11.toml`) — hence 1.10 as the failing-toolchain
  reference.

- timestamp: 2026-08-25 (C2) — **The DSO-OPT constraint matrix is WELL scaled; the
  ill-conditioning comes entirely from the ρ-weighted objective, and it is ANISOTROPIC.**
  Measured on the exact model `run_scenario(:ieee13, seed = 7, T = 24)` builds
  (`build_dso_opt(feeder, aggs, 24; ρ, λ₀)`), read-only:
  ```
  Scenario ρ0 = 100.0  τ_ratio = 2.0  μ = 10.0
  CONSTRAINT MATRIX (ρ-INDEPENDENT — build_dso_opt puts ρ only in the objective):
    |a_ij| min = 0.028124999999999997   max = 1.2   nnz = 5136
    spread max/min = 42.66666666666667
  MODEL SIZE: nvar = 1536  ncon = 2520
  OBJECTIVE COEFFICIENTS vs ρ (quadratic diag = 0.5ρ on every pag_dso[j,t]):
  ρ         q_min         q_max         lin_min         lin_max         q_max / |a_ij|_min
  2.0       1.0           1.0           3.6             9.0             35.5556
  12.5      6.25          6.25          3.6             9.0             222.222
  50.0      25.0          25.0          3.6             9.0             888.889
  100.0     50.0          50.0          3.6             9.0             1777.78
  200.0     100.0         100.0         3.6             9.0             3555.56
  (nq = 240 quadratic terms, nl = 24 linear terms)
  ```
  Readings:
    * The constraint matrix has a magnitude spread of only ~43× (0.028 … 1.2 pu) — it is NOT
      the source of the trouble, and it does not move with ρ at all.
    * The objective Hessian is a PURE DIAGONAL `0.5ρ`, and it sits on only **240 of the 1536
      variables** (the `pag_dso[j,t]` coupling block). The other 1296 variables — voltages,
      squared currents, branch flows, cone slacks — carry **exactly zero curvature**.
    * So the KKT system is strongly ANISOTROPIC and gets worse LINEARLY in ρ: a curvature-100
      block (at ρ = 200) adjacent to a curvature-0 block whose only diagonal support is
      Clarabel's static regularization.

- timestamp: 2026-08-25 (C2) — **Clarabel's measured defaults, and why rung 2 is exactly the
  right lever.** `Clarabel.Settings()` on this pinned build (0.11.1) reports:
  `static_regularization_constant = 1.0e-8`, `static_regularization_proportional = 4.93e-32`,
  `dynamic_regularization_eps = 1.0e-13`, `dynamic_regularization_delta = 2.0e-7`,
  `iterative_refinement_max_iter = 10`, `equilibrate_max_iter = 10`.
  MECHANISM (strongly supported, not solver-internally certified — see next_action): the
  curvature-0 variable block is held up in the quasi-definite KKT factorization by the
  `1e-8` static regularization, while the coupling block carries `0.5ρ = 100`. That is a
  ~1e10 diagonal spread at ρ = 200, doubling with every ρ climb step. It is marginal rather
  than fatal, which is exactly why an arbitrarily small perturbation of the emitted code (an
  unreachable `include`, a Julia patch bump) decides the outcome. Retry rung 2 raises
  `static_regularization_constant` to `1e-6` — a 100× reduction of precisely that spread, and
  the ONLY thing it changes — and that alone converts every observed failure into the same
  optimum at the same 58 iterations. The lever that fixes it is the lever this mechanism
  predicts.
  CAVEAT — ρ = 200 is one τ = 2 doubling of ρ₀ = 100, NOT a clamp (`ρ_max = 1e4`,
  `src/admm/solve_admm.jl:237`). An earlier draft of the fix comment mis-stated this as "its
  cap"; corrected in the follow-up commit.

- timestamp: 2026-08-25 (RESET-01, quick task 260825-eme) — **CORRECTION to the C1-landing
  "reaches the final strict solve" entry above, and the fix that follows from it.** That entry
  (2026-08-25, C1 landing) stated the sticky escalation "reaches the final `strict = true`
  solve." That premise about WHICH BRANCH RUNS was wrong: direct source read of
  `src/admm/solve_admm.jl` plus a grep over the whole file confirms `solve_dso!` is called with
  `strict = false` at BOTH call sites — the mid-loop call (L438-ish) and the actual
  final-consolidation call (L768-ish, whose `welfare`/`dadp` are published). `strict = true` is
  dead code from `solve_admm`'s perspective; only `test/test_dso.jl`'s direct calls reach it.
  So the sticky mid-loop escalation DID leak into the published solve — via the shared
  `strict = false` branch, not via a `strict = true` branch that never actually runs — and the
  entry's conclusion ("measured impact below noise floor") happened to still hold, but for the
  wrong stated reason.

  **The fix (RESET-01).** `build_dso_opt` snapshots the 4 Clarabel conditioning-ladder
  attributes (`src/planning/retry.jl`'s new `LADDER_ATTR_NAMES`) into
  `ctx.meta[:ladder_baseline]` exactly once, immediately after the model is built and before
  any solve can touch it. `solve_dso!` restores that snapshot onto the model immediately
  before every `check_exact = true` call — gated on `check_exact` (this function's own
  pre-existing "is this the final/converged call" flag), NOT on `strict`, precisely because
  gating on `strict` would be a no-op on the production path this fix exists to protect.
  Mid-loop (`check_exact = false`) iterations are untouched, so an escalation rescued mid-loop
  stays STICKY across the remaining mid-loop iterations exactly as before — only the published
  FINAL/converged solve is now guaranteed to run at the as-built baseline.

  **Measured, Julia 1.10.11 (the same failing toolchain as the C1 verification above), this
  session:**

  1. `reset01_probe.jl` (direct `solve_admm` call, `dso_ctx.model` inspected post-return):
     ```
     ┌ Warning: solve_with_retry!: attempt 1 failed (NUMERICAL_ERROR); escalating conditioning
     │   raw = "NUMERICAL_ERROR"
     └ @ TSODSO ~/programming/TSO-DSO/src/planning/retry.jl:201
     PROBE OK iters=58 welfare=-4822.90361661042
     FINAL static_regularization_constant = 1.0e-8
     RESET-01 CHECK: OK (baseline restored)
     ```
     `iters = 58` — identical to every prior measurement in this file. `welfare =
     -4822.90361661042` vs the known-good `-4822.903616694139` — 1.7e-11 relative, well inside
     the ~2e-9 cross-environment spread already documented above. Exactly **one**
     `escalating conditioning` line for the whole run (`grep -c` on the tee'd log: `1`). The
     LOAD-BEARING check: `static_regularization_constant` read back off the SAME build-once
     `dso_ctx.model` after `solve_admm` returns is `1.0e-8` — the as-built Clarabel baseline,
     NOT the `1e-6` a rung-2 escalation would have left in force under the pre-RESET-01
     behaviour. This directly proves the restore fired on the published solve.
  2. `reset01_infra04.jl` (two in-process `run_scenario` calls, same `Scenario`):
     ```
     ┌ Warning: solve_with_retry!: attempt 1 failed (NUMERICAL_ERROR); escalating conditioning
     ┌ Warning: solve_with_retry!: attempt 1 failed (NUMERICAL_ERROR); escalating conditioning
     INFRA-04 CHECK: OK
     ```
     `welfare == welfare`, `dadp == dadp`, `exact_maxgap == exact_maxgap`, `iters == iters`
     (all `==`, not `≈`) held across both calls — bit-for-bit reproducibility (INFRA-04)
     survives the RESET-01 change. Exactly **two** `escalating conditioning` lines (`grep -c`:
     `2`) — one per independent `run_scenario` call, each building a fresh `DsoOpt` and hitting
     the same iteration-28 knife-edge, matching this file's own established INFRA-04 evidence
     pattern (C1 landing, item 2 above).
  3. `git diff HEAD~1 HEAD -- src/planning/retry.jl` (Task A) shows ONLY the new
     `LADDER_ATTR_NAMES` const/docstring and the updated final `export` line — zero changes to
     the `ladder` vector, `RETRYABLE_STATUSES`, or `solve_with_retry!`'s body — so the other
     existing `solve_with_retry!` call sites (`planning/subproblem.jl`, `planning/master.jl`,
     `planning/master_integer.jl`, `models/stochastic_welfare.jl`, `models/mpc_window.jl`) are
     unaffected by construction.

  **Files changed:** `src/planning/retry.jl` (additive `LADDER_ATTR_NAMES` constant, exported),
  `src/admm/DsoOpt.jl` (`_snapshot_ladder_attrs`/`_restore_ladder_attrs!` helpers,
  `ctx.meta[:ladder_baseline]` populated once in `build_dso_opt`, restore call gated on
  `check_exact` in `solve_dso!`, corrected HONEST CAVEAT + SCOPE comments, updated docstrings).

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
  DONE — C1 landed and verified (see ## Resolution). C2 partially done: the coefficient-range
  measurement and the anisotropy mechanism are recorded in Evidence below. The one piece NOT
  done is a direct dump of Clarabel's INTERNAL KKT condition number at the iteration-28 iterate
  (would need product-code instrumentation of the ADMM loop); the mechanism below is therefore
  strongly supported but not solver-internally certified.

  --- original plan, retained for the record ---
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

root_cause: |
  The IEEE-13 mid-loop DSO-OPT SOCP sits on a NUMERICAL KNIFE-EDGE at ADMM iteration 28, once
  adaptive-ρ has doubled from ρ₀ = 100 to ρ = 200 (τ = 2 — NOT the `ρ_max = 1e4` clamp, just
  one climb step) and both residuals are within ~1.5–2× of their tolerances. At that iterate Clarabel's DEFAULT static regularization is marginal: the solve
  terminates `NUMERICAL_ERROR` rather than OPTIMAL. Which side of the edge a given build lands
  on is decided by pure floating-point/codegen perturbation, NOT by any logic:
    * adding an UNREACHABLE `include("models/ac_dual_fallback.jl")` flips converge → fail at
      the bisect's first-bad commit `3077a02` (A/B verified);
    * a Julia PATCH bump flips it (1.10.11 / 1.11.9 / 1.12.5 fail; 1.12.7 converges);
    * each (tree × Julia version) pair is STABLE — 5/5 deterministic, not run-to-run flake.
  So `3077a02` is not a regression and there is no dependency change (all committed Manifests
  are byte-identical across the whole bisect range). The ACTIONABLE defect is a ROBUSTNESS GAP:
  `solve_dso!`'s mid-loop branch called `assert_solved!` DIRECTLY, so a marginal-conditioning
  failure was fatal — even though the project already ships `solve_with_retry!`, whose
  `RETRYABLE_STATUSES` already includes `MOI.NUMERICAL_ERROR`, and whose rung 2 recovers the
  very optimum the failing builds were converging to.

fix: |
  Two additive edits, no tolerance/gate/assertion weakened, no test expectation changed:
  1. `src/planning/retry.jl` — new `allow_almost::Bool = false` kwarg on `solve_with_retry!`,
     forwarded verbatim into its internal
     `assert_solved!(model; dual = dual, allow_almost = allow_almost)`. The `false` default is
     `assert_solved!`'s own default, so every pre-existing caller is semantically unchanged
     (verified by grep: no call site anywhere in src/ or test/ passes the new kwarg).
     Docstring updated (incl. the `ALMOST_OPTIMAL ∈ RETRYABLE_STATUSES` interaction).
  2. `src/admm/DsoOpt.jl` — the MID-LOOP (`strict = false`) branch of `solve_dso!` now calls
     `solve_with_retry!(dso.model; dual = false, allow_almost = true)` instead of the bare
     `assert_solved!(dso.model; dual = false, allow_almost = true)`. `allow_almost = true`
     preserves that branch's pre-existing near-feasible acceptance exactly.

  DELIBERATELY OUT OF SCOPE: the `strict = true` FINAL/converged solve keeps its bare STRICT
  `assert_solved!(…; dual = true)` gate — it is the published solve and must still hard-fail
  rather than escalate.

  HONEST CAVEAT (documented inline at the call site, not hidden): escalation is STICKY by
  `solve_with_retry!`'s own WR-01 contract, and `dso` is build-once — so after a rung-2 rescue
  the remaining mid-loop iterations AND the final strict solve run at
  `static_regularization_constant = 1e-6`. This is bounded and measured:
    * the ADMM transactive price is the OUTER multiplier λ (`dadp == λ` in `solve_admm.jl`),
      never a dual of this model, so no published price is read off an escalated dual;
    * escalation only fires where the alternative is a hard crash (no result at all); where
      default conditioning suffices no rung ≥ 2 is applied and behaviour is bit-identical;
    * measured impact is BELOW the cross-environment noise floor (see verification);
    * the final solve still runs the full STRICT gate AND the PF-04 exactness gate.

verification: |
  All measured on Julia **1.10.11** — a FAILING toolchain (1.11 could not be used: the tree's
  pre-existing uncommitted Project.toml drift promoting CairoMakie to a hard dep makes
  `julia +1.11 --project=.` die with the documented CairoMakie `KeyError`; 1.12.7 was avoided
  because it converges natively and would prove nothing).

  0. BASELINE, same tree, BEFORE the fix (proves the toolchain is a failing one):
       `PROBE FAIL NUMERICAL_ERROR`

  1. PROBE, after the fix, on the exact committed source state
     (`julia +1.10 --project=. probe.jl`):
       ```
       ┌ Warning: solve_with_retry!: attempt 1 failed (NUMERICAL_ERROR); escalating conditioning
       │   raw = "NUMERICAL_ERROR"
       └ @ TSODSO ~/programming/TSO-DSO/src/planning/retry.jl:181
       PROBE OK iters=58 welfare=-4822.903616694139
       ```
     EXACTLY ONE escalation warning for the whole 58-iteration run (iteration 28; stickiness
     then carries rung 2 forward, so iterations 29–58 never re-fail).
     iters = 58 — IDENTICAL to every natively-converging environment.
     welfare = -4822.903616694139 vs the known-good references
       -4822.903620476632 (1.10, unreachable-include A/B) → 7.8e-10 relative
       -4822.903625595291 (1.12.7, native convergence)    → 1.8e-9  relative
     i.e. inside the ~2e-9 spread the natively-converging builds already show among themselves.

  2. INFRA-04 BIT-FOR-BIT REPRODUCIBILITY — HOLDS (measured, not reasoned):
     "INFRA-04 same-seed repro admm" (which asserts `r1.welfare == r2.welfare` with `==`)
     passes 8/8. The log shows EXACTLY TWO escalation warnings — one per `run_scenario` — i.e.
     both in-process runs build a fresh model and escalate identically at the same iteration.

  3. The three previously-failing `test/test_experiments.jl` items, on Julia 1.10:
       EXP-01 scenario admm             | Pass 7  Total 7   34.6s
       INFRA-04 same-seed repro admm    | Pass 8  Total 8   16.6s
       INFRA-04 seed sensitivity admm   | Pass 3  Total 3   17.1s
     (Run via a minimal `@testitem`/`@testmodule` shim under `--project=.`, because
     `test/Manifest.toml` resolves only on Julia 1.12 — PrecompileTools `StaticData`
     UndefVarError on 1.10/1.11 — and TestItemRunner cannot be used under `--project=.` here.)

  4. EXISTING `solve_with_retry!` CALLERS UNAFFECTED. Grep over `src/` + `test/`: the call
     sites are `planning/subproblem.jl:283`, `planning/master.jl:269`,
     `planning/master_integer.jl:247`, `models/stochastic_welfare.jl:431` and `:766`,
     `models/mpc_window.jl:304`, and the `test/test_planning_retry.jl` direct calls — NONE
     passes `allow_almost`, so all take the `false` default ≡ prior behaviour. Green on 1.10:
       planning retry (4 items)   7+3+2+2 pass
       planning master (7 items)  3+2+7+1+4+8+1 pass
       planning oracle (7 items)  3+3+7+5+1+2+10 pass

  5. REGRESSION SWEEP on Julia 1.10 — `test_mpc_window.jl`, `test_dso.jl`, `test_admm.jl`,
     `test_admm_dualresid.jl`:
       `SHIM SUMMARY: items=21 pass=115 fail/error=0`
     and `test_admm_adaptive.jl` (the item that fails on 1.12 with the same signature), 3/3:
       set_rho! build-once invariant                 | Pass 4 Total 4  17.1s
       scale-invariant convergence 2-bus AND ieee13  | Pass 5 Total 5  32.7s
       transit dso zero-injection accepted           | Pass 2 Total 2   0.2s

  6. `JuliaFormatter.format(...; overwrite = true)` returns `true` (already formatted) for both
     edited files.

files_changed:
  - src/planning/retry.jl: additive `allow_almost::Bool = false` kwarg threaded into the
    internal `assert_solved!` call; docstring updated.
  - src/admm/DsoOpt.jl: mid-loop (`strict = false`) DSO solve routed through
    `solve_with_retry!(dso.model; dual = false, allow_almost = true)`, with the full
    knife-edge/stickiness rationale inline; `solve_dso!` docstring updated.

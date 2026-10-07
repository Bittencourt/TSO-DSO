# Phase 38: Close v4.0 Audit Gaps - Context

**Gathered:** 2026-10-07
**Status:** Ready for planning
**Source:** `.planning/v4.0-MILESTONE-AUDIT.md` (status gaps_found) + user decisions 2026-10-07

<domain>
## Phase Boundary

Close the cross-phase gaps the v4.0 milestone audit found. Every phase passed on its own; these are
places where an earlier fix or refactor never reached older code:

- **Blocker 1 (FIX-08, FIX-10, ARCH-02).** MPC's first-tier certificate `_mpc_certify_and_price`
  (`src/experiments/mpc_loop.jl:866-875`) re-implements the cone check inline with a flat
  `tol = 1e-6 + 1e-4·max(|lhs|,|rhs|)`. The library gate `_cone_row`
  (`src/models/exactness.jl:104-127`) has used `atol_b = max(TAU_SOLVER_EXACT=2e-7, MEASURED_REL_TOL_EXACT·ref_b)`
  since Phase 27. The docstring (795-797) wrongly claims parity.
- **Blocker 2 (ARCH-08, HYG-05, HYG-06).** `test/test_admm_timeout.jl` is a plain Test.jl script
  with no `@testitem`. The test runner never discovers it and CI never runs it, yet it is the only
  test of `solve_admm`'s `:budget_exceeded` status.
- **Warnings taken in scope:** W1, W2, W4, W5, W6 and W7 (see decisions).

Out of scope: the accepted todos (seed 42, LinDistFlow-copy vmax bound, 1.12.7 fit_baseline), the
IEEE-8500 harness, W3 (narrative pages for bilevel/VE/integer Nash), and Phase 29's WR-01/IN-01.
The knife-edge canary (iters = 56, welfare = -4823.66604824162) is never re-pinned.

</domain>

<decisions>
## Implementation Decisions

### MPC first-tier certificate (blocker 1)
- Compute the per-branch ratio through the shared library arithmetic (`_cone_row`, or
  `hybrid_ratios(ctx)` if it applies to the MPC window's `ModelContext`). Use the same defaults as
  `assert_socp_exact!`: `rtol = 1e-4`, `atol = nothing` (hybrid floor), `ε = MEASURED_REL_TOL_EXACT`
  and `τ = TAU_SOLVER_EXACT`. The check stays NON-throwing, and the escalation ladder is unchanged.
- Fix the docstring's parity claim so it describes the shared arithmetic.
- Before changing code, measure every MPC fixture/test/golden's first-tier max ratio under both the
  old and the new tolerance.
- USER: **accept explained moves.** If a resolve that used to certify now escalates (restricted or
  AC-dual tier) and a golden or test value moves, that is accepted when the escalation is correct
  behaviour. Each moved golden is documented in the SUMMARY with its old/new ratio and values. The
  canary is never touched.
- Add a regression test: a constructed or perturbed window point the old flat tolerance accepts
  but the hybrid floor refuses, shown to escalate.

### Orphan ADMM timeout test (blocker 2)
- Convert `test/test_admm_timeout.jl` into `@testitem`(s) that check `:budget_exceeded` under
  `time_limit_s`. Tag `:slow` if measured at 30 s or more. Remove the obsolete
  "deliberately NOT a @testitem" rationale, since discovery has been rooted at `test/` since
  Phase 37. Update `--count-sets --strict` expectations and `expected_broken.txt` only if needed.

### Stale prose and docs (W1, W2, W4)
- W1: `src/TSODSO.jl:265-278`, `docs/literate/mpc_rolling_horizon.jl:24-27` and
  `docs/literate/stochastic_pv_demand.jl:22-25` say run_mpc/run_stochastic are "NOT wired
  through run_scenario's strategy dispatch". Rewrite them to state the current `TSODSO.run(::MPC)` /
  `run(::Stochastic)` dispatch.
- W2, USER: **full API sweep** of `docs/writeups/FRAMEWORK_GUIDE.html`. Check every code
  example and API mention against the current API: export trim (192 → 90; unexported names need
  `TSODSO.`-qualification or `using TSODSO: x`), `ReactiveMode` module form (`ReactiveMode.LIVE`),
  removed kwargs (`objective_hook`, `horizon_state`, `z`, Bool/Symbol reactive modes), removed DLMP
  `loss`/`voltage` aliases (now `cone`/`drop`), renamed fixtures/tags, renamed constants, the
  `Scenario`/strategy API (Phase 32), and typed errors and status vocabulary (Phase 34). Fix every
  stale usage, remove planning IDs, and list the guide in `docs/writeups/README.md`. The file is
  2.9 MB, so edit surgically (scripted search, targeted replacements) and never regenerate it.
  Prefer static checks; snippets may be executed only from the session scratchpad, never as
  `.jl` files under the repo.
- W4: `src/experiments/store.jl:177-178` says only primitives are stored, but line 191 stores a
  `ReactiveMode.T`. Make the docstring match the behaviour (or store the enum as a primitive,
  provided round-trip loading stays compatible; the planner decides, and docs must match).

### Extra hardening (W5, W6, W7)
- W5: `Scenario(strategy=ADMM(), allow_export=false)` must raise `ArgumentError` at construction
  (strategy × setting validation), with a test. The error text is consistent with `solve_admm`'s
  existing message.
- W6: `solve_stochastic_oos_step!` (`src/models/stochastic_welfare.jl:749`) runs no cone gate.
  Add the exactness check (shared gate, same defaults) so the out-of-sample `welfare_gap` is
  certified. If an OOS solve is inexact, the failure must be visible, with no silent pass. The
  planner decides between throwing `CertificateError` and recording a per-scenario status, following
  the Phase 34 status/exception policy (`docs/src/status_policy.md`). Measure every stochastic
  golden/test under the new gate first; explained moves are accepted, the canary never.
- W7: run `.github/scripts/check_setup_names.py` in the CI `format` job (with `--selftest` if it
  has one), after confirming it passes locally.

### Gates
- Full suite sequential on Julia 1.12.5 and 1.12.7 via `suite_detached.sh` + `check_suite_log.py`.
  Baseline: 32224 / 32219 pass, 0/0, Broken 5. Itemize every pass delta. Canary iters = 56.
- JET ratchet (`scripts/jet_check.jl` on 1.12.7) gives 0 NEW. The three guards plus
  `check_setup_names.py`, `--count-sets --strict`, the docs build, `format210.jl` and
  `check_content_loss.py HEAD` all pass.

### Claude's Discretion
- Whether to reuse `_cone_row` directly or `hybrid_ratios`; test fixture construction; OOS-gate
  failure representation within the status policy; FRAMEWORK_GUIDE sweep tooling.

</decisions>

<code_context>
## Existing Code Insights
- `_cone_row(pv, br, b, t, head_b, rtol, atol, ε, τ_solver)` returns `(; lhs, rhs, gap, atol_b, ratio)`.
- MPC escalation ladder: restricted tier `:certified_convex_dual_restricted`, AC-dual tier
  `:local_ac_dual`, and terminal `:cert_failed`. 26 test references to cert statuses.
- Runner recipe: `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:<x>`.
- Memory: never two Julia suites concurrently; no scratch `.jl` with `@testitem` under the repo.
</code_context>

<deferred>
## Deferred Ideas
- W3: literate pages for `solve_bilevel!`, `solve_variational_equilibrium`, integer `run_nash!`.
- Phase 29 WR-01/IN-01 (bilevel certificate recovery reads cached coefficients; `_ub` ignores `is_fixed`).
</deferred>

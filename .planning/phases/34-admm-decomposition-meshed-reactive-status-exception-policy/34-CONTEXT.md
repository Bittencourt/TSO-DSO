# Phase 34: ADMM Decomposition, Meshed Reactive & Status/Exception Policy - Context

**Gathered:** 2026-10-04
**Status:** Ready for planning

<domain>
## Phase Boundary

`solve_admm` is decomposed and formulation-generic, meshed topology + live reactive pricing compose
end-to-end, and every solve entry point follows one consistent status/exception policy
(ARCH-05, ARCH-06, ARCH-08, ARCH-09):

1. `solve_admm` split into named phases (build, iterate, ρ adaptation, certification); reactive-mode
   behaviour dispatched instead of repeated `mode == …` branches; accepts any valid `AbstractPowerFlow`.
2. Meshed topology + live ADMM reactive pricing runs end-to-end, cross-validated against the centralized
   meshed `:balance_q` dual (closes the v3.0 MESH-06 advisory).
3. `solve_admm`, `solve_stackelberg!`, `run_nash!`, `run_mpc`, `run_stochastic` follow one documented,
   consistent status-vs-throw policy.
4. `mpc_loop`'s exception handlers catch only solver-status and certificate exceptions;
   `MethodError`/`BoundsError` propagate.

Baseline: full suite 31915 passed / 0 failed / 0 errored / 5 broken at b955aa4. Every existing numeric
golden must stay bit-identical (ADMM knife-edge canary `iters = 56`, `welfare = -4823.66604824162`).

OUT of scope: IEEE-8500 scale (Phase 35); planning-layer balance-closing copies; narrowing catch blocks
outside `mpc_loop.jl` (only inventoried), except `run_stochastic`'s skip-and-report catch.

</domain>

<decisions>
## Implementation Decisions

### solve_admm Decomposition & Formulation-Generic (ARCH-05)
- Mutable `AdmmState` struct holding iterates; internal phase functions `_admm_build`,
  `_admm_iterate!`, `_adapt_rho!`, `_admm_certify` (named per success criterion); `solve_admm`
  orchestrates. Public signature, kwargs and return NamedTuple UNCHANGED.
- Reactive-mode dispatch: internal singleton types `_ReactiveOff`, `_ReactiveCertified`, `_ReactiveLive`
  with per-phase hook methods (OFF hooks are no-ops); the public `reactive_consensus` kwarg and the
  `ReactiveMode` enum in results stay exactly as today.
- `admm_supported(pf)` trait: accepts SOCP family (`ConvexBranchFlow` both variants,
  `RestrictedBranchFlow`, `MeshedFlow`) + `LinDistFlow` (`exact_maxgap = NaN`, no cone); rejects
  `ACPowerFlow` and `DCPowerFlow` with `ArgumentError`. `DsoOpt` uses the passed `pf` (no hard-coded
  `ConvexBranchFlow()`); Phase 32's `supports_pf(::ADMM, …)` matrix widens to match `admm_supported`.
- Bit-identity: the default ConvexBranchFlow path reproduces every ADMM golden exactly (pure refactor).

### Meshed + Live Reactive ADMM (ARCH-06)
- `solve_admm` accepts `MeshedFeeder` ONLY with `pf = MeshedFlow` (replaces Phase 33's
  always-throw `::MeshedFeeder` method with a pair-checked one); radial formulations × meshed still throw.
- Cross-validation fixture: the existing Phase-23 meshed fixture with `reactive_consensus = LIVE`.
- Tolerance is MEASURED, not picked (memory `highs-exactness-defaults`): record the observed
  ADMM-vs-centralized gap on load-bus `dual(:balance_q)` reactive price and welfare; assert a tolerance
  derived from ADMM stopping criteria (`ε_abs`/`ε_rel`) with documented measured headroom; active price
  checked too.
- Update the Phase-23 meshed literate page: replace the "no meshed ADMM / centralized analog"
  disclaimer with the live meshed ADMM run; MESH-06 advisory closed in docs.

### Status/Exception Policy (ARCH-08)
- Policy (codifies today's behaviour — no flip): THROW for invalid inputs (`ArgumentError`), solver
  failures that make results untrustworthy, and genuine non-convergence of an iterative method; RETURN a
  status for valid-answer outcomes — converged, caller-set wall-clock/iteration budget exhausted,
  documented degradation ladders (MPC certificate tiers), documented skip-and-report (stochastic OOS
  infeasibility).
- Typed exceptions: `abstract type TSODSOError <: Exception`; `SolveFailedError` (carries
  termination/primal/dual/raw status), `CertificateError` (exactness/no-slack), `ConvergenceError`.
  `assert_solved!`, `assert_no_slack`, exactness asserts and non-convergence throws raise them with
  BYTE-IDENTICAL message text (existing `@test_throws`/message assertions keep passing). Exported +
  documented.
- One "Status & exception policy" docs section listing each entry point's status vocabulary + what it
  throws; all five entry-point docstrings link to it; a test checks each entry point's returned
  `status` is within its documented vocabulary.
- Each of the five entry points' results carries `status::Symbol` (per-entry-point vocabulary);
  missing ones (`run_nash!`, `run_stochastic`) get one ADDITIVELY without changing existing fields.

### mpc_loop Exception Narrowing (ARCH-09)
- Catches admit only `SolveFailedError`, `CertificateError` (and `ConvergenceError` where a tier is
  iterative); everything else — `MethodError`, `BoundsError`, `ArgumentError`, `KeyError`,
  `InterruptException` — rethrows immediately.
- Non-TSODSO errors that legitimately surface from a tier (Ipopt/JuMP inside AC fallback, etc.) are
  wrapped AT SOURCE into `SolveFailedError`; no message-string matching.
- Tests use the existing internal seams (`_solve_welfare`, `_ac_dual_fallback_price`) to inject
  `MethodError`/`BoundsError` (must propagate) and `SolveFailedError` (still ledgered/degraded as before).
- Scope: every try/catch in `mpc_loop.jl`; `run_stochastic`'s skip-and-report catch narrowed to the
  same types (behaviour preserved); other files' catch blocks inventoried only.

### Research Refinements (34-RESEARCH.md + user decisions 2026-10-04 — supersede looser wording above)
- Typed exceptions CANNOT subtype `ErrorException` (concrete). USER: accept migration — ordered rollout:
  (1) add `TSODSOError` types + `_is_solver_failure(e)` predicate (no behaviour change); (2) widen the 11
  production `e isa ErrorException || rethrow()` sites (incl. `src/planning/retry.jl:198`, the retry
  ladder the knife-edge canary relies on) to the predicate; (3) convert throw sites; (4) update the ~20
  test lines matching `ErrorException`. Knife-edge canary after every step. "Byte-identical message
  text" still holds; only the exception TYPE changes.
- `ConvergenceError` scope: solve_admm maxiter, `solve_stackelberg!` exhaustion + `:reject` stalled,
  `run_nash!` exhaustion + CYCLED. Other planning `error(...)` modeling-bug asserts stay `ErrorException`
  and are inventoried in the policy doc.
- LinDistFlow ADMM (USER): additive `solve_agr!` kwarg `battery_on_violation::Symbol = :error`
  (existing callers unchanged); `solve_admm` passes `:warn` iff `!(problem_class(pf) isa SOCP)`,
  mirroring `welfare_solve.jl`. LinDistFlow is in `admm_supported`.
- Canary (USER): NEVER re-pin. Any change to `iters = 56` / welfare means FP order drifted; fix the refactor.
- Meshed ADMM: delete the `::MeshedFeeder` throw methods (ambiguity with the generic method) and gate
  pairs via `admm_supported`/pair check instead. Reactive-price cross-check uses a heterogeneous diamond +
  new `φ = 0.95` test helper (committed fixture's reactive price ≈ 0); angle-certificate composition uses
  uniform φ=1 + BESS. Tolerances from the measured table in 34-RESEARCH.md.
- `has_reactive` guard: NOT added (DC + aggregators legitimately solves with unclosed `:Rq`); instead a
  pinning test (objective `-4819.9377763808125`) + a policy-doc sentence.
- `mpc_loop.jl` has exactly two try/catch blocks (in `_mpc_certify_and_price`); no extra source wrapping
  needed; the `boom` test seam must throw `SolveFailedError`.

### Claude's Discretion
- Exact internal function/struct names beyond those listed; file split of `solve_admm.jl`.
- Field set of `ConvergenceError`.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/admm/solve_admm.jl` (927 lines; `function solve_admm` at :239; 17+ `mode == LIVE` sites;
  `solve_admm(::MeshedFeeder, …)` throwing method at :923), `src/admm/DsoOpt.jl`
  (`contribute!(ConvexBranchFlow(), …)` hard-coded), `src/admm/AgrOpt.jl`, `src/admm/ReactiveMode.jl`,
  `src/admm/residuals.jl`.
- `src/core/status.jl` — `assert_solved!`, `assert_no_slack` use `error(...)`.
- `src/models/exactness.jl` (`assert_socp_exact!`), `restriction_exactness.jl`, `mesh_angle_certificate.jl`.
- `src/experiments/mpc_loop.jl` escalation tiers (~L899–990: `catch err; err isa InterruptException && rethrow()`).
- `src/experiments/strategies.jl` `supports_pf` matrix (Phase 32).
- Phase-23 meshed fixture + literate page (docs/literate meshed rung).

### Established Patterns
- `throw(ArgumentError(...))` for input validation; status Symbols on result NamedTuples.
- Typed `ModelContext` (Phase 33): `has_reactive(pf)`, `has_branch_current(ctx)`, `_require_*`.

### Integration Points
- `run(::ADMM, s)` / `ScenarioResult` (Phase 32) — ADMM pf widening flows through `supports_pf`.
- Tests asserting error messages from `assert_solved!`/exactness (keep text identical).

</code_context>

<specifics>
## Specific Ideas

- Certify with the detached full suite (≥ 31915 passes, 0/0/5) + docs build; knife-edge canary unchanged.
- PVAL-04 tripwire: any new exported `build_*` must be allowlisted; docs `checkdocs = :exports`: new
  exports (`TSODSOError`, `SolveFailedError`, `CertificateError`, `ConvergenceError`, `admm_supported`)
  must be surfaced in `docs/src/api.md`.
- Phase-33 deferral lands here: `has_reactive` consistency guard (DC + reactive device leaves `:Rq`
  unclosed silently — pre-existing) — decide under the ARCH-08 policy with a pinning test, without
  changing any currently-solving model.

</specifics>

<deferred>
## Deferred Ideas

- Narrowing catch blocks outside `mpc_loop.jl`/`run_stochastic` (inventoried only).
- Public type-based reactive-mode API.

</deferred>

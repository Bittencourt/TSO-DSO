# Phase 34: ADMM Decomposition, Meshed Reactive & Status/Exception Policy - Research

**Researched:** 2026-10-04
**Domain:** Julia/JuMP research framework internals — refactor of a hand-rolled ADMM loop, formulation-generic
subproblems, a typed exception/status policy, and exception-handler narrowing. No new external packages.
**Confidence:** HIGH on code anatomy and measured probes (all cited file:line were read this session and the
probes were executed); MEDIUM on vocabulary names (discretionary) and on LinDistFlow-ADMM battery-gate behaviour
(one measured case).

## Summary

Phase 34 is a refactor-plus-policy phase on top of Phase 33's typed `ModelContext`. Four things must land
together: (1) `solve_admm` (`src/admm/solve_admm.jl`, 927 lines) becomes `AdmmState` + four phase functions with
singleton-dispatched reactive hooks, bit-identical on the default path; (2) it and `DsoOpt` accept any ADMM-capable
`AbstractPowerFlow`, including `MeshedFlow` on a `MeshedFeeder`; (3) five entry points follow one status-vs-throw
policy with typed exceptions; (4) the two `try/catch` blocks in `mpc_loop.jl` (and the one in `run_stochastic.jl`)
catch only typed solver/certificate errors.

**Three measured findings change how the planner should write this phase** (details in the sections below):

1. **The locked premise "typed exceptions with byte-identical text keep existing `@test_throws` passing" is false
   for `ErrorException`-typed matches.** `ErrorException` is a concrete struct and cannot be subtyped, so a
   `SolveFailedError` is NOT an `ErrorException`. Eleven production sites do `e isa ErrorException || rethrow()`
   (retry ladder, Benders, coupling, ac_recheck, subproblem, fit, run_stochastic). If `assert_solved!` starts
   throwing `SolveFailedError` and those sites are not widened first, **`solve_with_retry!` stops retrying
   (`src/planning/retry.jl:198`), which kills the DsoOpt mid-loop conditioning ladder that the ADMM knife-edge
   canary depends on**. About 20 test assertions also match `ErrorException` on converted families and must be
   edited. This is the largest risk in the phase and needs an explicit decision (Open Question Q1).
2. **Meshed live-reactive ADMM works today with only a type loosening.** I ran `DsoOpt` + `solve_admm` on the
   Phase-23 diamond with `MeshedFlow` and `reactive_consensus = LIVE` (probe, unmodified math, `Feeder` →
   `AbstractFeeder`, `ConvexBranchFlow` → passed `pf`). Converges in 4 to 21 iterations, and ADMM-vs-centralized
   `:balance_q` / `:balance_p` / welfare gaps are measured below, so tolerances can be derived rather than picked.
   ADMM's `dso_ctx` also certifies identically to the centralized ctx under `certify_angle_recoverable!`.
3. **The existing `::MeshedFeeder` throwing methods must be deleted, not coexisted with.** Keeping
   `solve_admm(::MeshedFeeder, args...; kwargs...)` next to a generic `solve_admm(feeder::AbstractFeeder, pf::AbstractPowerFlow, …)`
   produced a `kwcall … is ambiguous` MethodError in the probe (and would trip Aqua's ambiguity check). The pair
   check moves into the generic body.

**Primary recommendation:** Land in this order: typed-exception types + widened catch predicate (pure addition) →
convert throw sites + update the listed tests → `status` fields + policy tests → ADMM decomposition as a pure
refactor gated by the knife-edge canary after every plan → formulation-generic + meshed → mpc/run_stochastic catch
narrowing (+ seam-test migration) → docs → detached full-suite certification.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### solve_admm Decomposition & Formulation-Generic (ARCH-05)
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

#### Meshed + Live Reactive ADMM (ARCH-06)
- `solve_admm` accepts `MeshedFeeder` ONLY with `pf = MeshedFlow` (replaces Phase 33's
  always-throw `::MeshedFeeder` method with a pair-checked one); radial formulations × meshed still throw.
- Cross-validation fixture: the existing Phase-23 meshed fixture with `reactive_consensus = LIVE`.
- Tolerance is MEASURED, not picked (memory `highs-exactness-defaults`): record the observed
  ADMM-vs-centralized gap on load-bus `dual(:balance_q)` reactive price and welfare; assert a tolerance
  derived from ADMM stopping criteria (`ε_abs`/`ε_rel`) with documented measured headroom; active price
  checked too.
- Update the Phase-23 meshed literate page: replace the "no meshed ADMM / centralized analog"
  disclaimer with the live meshed ADMM run; MESH-06 advisory closed in docs.

#### Status/Exception Policy (ARCH-08)
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

#### mpc_loop Exception Narrowing (ARCH-09)
- Catches admit only `SolveFailedError`, `CertificateError` (and `ConvergenceError` where a tier is
  iterative); everything else — `MethodError`, `BoundsError`, `ArgumentError`, `KeyError`,
  `InterruptException` — rethrows immediately.
- Non-TSODSO errors that legitimately surface from a tier (Ipopt/JuMP inside AC fallback, etc.) are
  wrapped AT SOURCE into `SolveFailedError`; no message-string matching.
- Tests use the existing internal seams (`_solve_welfare`, `_ac_dual_fallback_price`) to inject
  `MethodError`/`BoundsError` (must propagate) and `SolveFailedError` (still ledgered/degraded as before).
- Scope: every try/catch in `mpc_loop.jl`; `run_stochastic`'s skip-and-report catch narrowed to the
  same types (behaviour preserved); other files' catch blocks inventoried only.

### Claude's Discretion
- Exact internal function/struct names beyond those listed; file split of `solve_admm.jl`.
- Field set of `ConvergenceError`.

### Deferred Ideas (OUT OF SCOPE)
- Narrowing catch blocks outside `mpc_loop.jl`/`run_stochastic` (inventoried only).
- Public type-based reactive-mode API.

Also from CONTEXT "Specifics": certify with the detached full suite (>= 31915 passes, 0/0/5) + docs build;
knife-edge canary unchanged (`iters = 56`, `welfare = -4823.66604824162`); PVAL-04 tripwire (new exported `build_*`
must be allowlisted); `checkdocs = :exports` (new exports must be surfaced in `docs/src/api.md`); the Phase-33
`has_reactive` consistency-guard deferral is decided here under ARCH-08 with a pinning test and NO change to any
currently-solving model. OUT of scope: IEEE-8500 scale (Phase 35); planning-layer balance-closing copies.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ARCH-05 | `solve_admm` split into named phases (build, iterate, ρ adaptation, certification); reactive-mode behaviour dispatched, not repeated `mode == …` branches; accepts any valid `AbstractPowerFlow` | Anatomy + hook map (Section "solve_admm Anatomy"); formulation-generic changes (Section "Formulation-generic ADMM"); probes show Convex/Restricted/Meshed/LinDist all run through a type-loosened DsoOpt |
| ARCH-06 | Meshed topology plus live ADMM reactive pricing runs end-to-end and is cross-validated against the centralized meshed `:balance_q` dual (closes MESH-06) | Measured probe table (Section "Meshed live-reactive probe"); fixture + tolerance recommendation; literate page edits |
| ARCH-08 | One documented status policy for `solve_admm`, `solve_stackelberg!`, `run_nash!`, `run_mpc`, `run_stochastic` | Status/exception inventory (Section "Status & exception inventory"); typed-exception strategy and blast radius; vocabulary proposal |
| ARCH-09 | `mpc_loop` handlers catch only solver-status and certificate exceptions; `MethodError`/`BoundsError` propagate | catch inventory (Section "mpc_loop catch inventory"); seam-test migration list |
</phase_requirements>

## Architectural Responsibility Map

This is a single-process Julia library; "tiers" are the library's own layers.

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Typed exceptions + status vocabulary | Core (`src/core/`) | Every solve layer | Types must exist before `status.jl`, `retry.jl`, exactness files raise them; included right before `core/status.jl` (`src/TSODSO.jl:56`) |
| ADMM state + phase functions + reactive hooks | ADMM layer (`src/admm/`) | — | Orchestration only; subproblem builders stay in `AgrOpt.jl`/`DsoOpt.jl` |
| Formulation-genericity (`admm_supported`, pair check) | ADMM layer | Power-flow layer (`has_branch_current`, `problem_class`) | Data-driven on existing traits, never `if pf isa …` in the loop |
| Scenario `supports_pf` matrix | Experiment harness (`experiments/strategies.jl`) | — | Symbol-level mirror of `admm_supported` |
| Exception narrowing | Experiment/MPC layer (`mpc_loop.jl`, `run_stochastic.jl`) | Core exceptions | Depends on sources raising typed errors |
| Policy documentation | Docs (`docs/src/*.md`, `api.md`) | Entry-point docstrings | `checkdocs = :exports` gates surfacing |

## Standard Stack

No new packages. Everything uses the already-pinned stack from CLAUDE.md (JuMP 1.30.x, Clarabel, HiGHS, Ipopt,
TestItems/TestItemRunner, Documenter 1.17, Literate 2.21). [VERIFIED: CLAUDE.md + `docs/Project.toml`, Julia 1.12.5
running locally]

### Package Legitimacy Audit

No external packages are installed or recommended by this phase, so the slopcheck gate does not apply.
**Packages removed due to slopcheck [SLOP] verdict:** none. **Packages flagged [SUS]:** none.

## Architecture Patterns

### System Architecture Diagram (target state)

```
 solve_admm(feeder::AbstractFeeder, pf::AbstractPowerFlow, aggs; kwargs…)      <- public, signature/kwargs unchanged
   │  guards: _check_admm_pair!(:solve_admm, feeder, pf)   (FIRST: before empty-aggs check)
   │          admm_supported(pf) || ArgumentError ;  existing T/λ₀/maxiter/allow_export guards
   ▼
 _admm_build(...)  ──► dso::DsoOpt (uses passed pf)  +  agr_by_bus  +  AdmmState  +  AdmmResiduals
   │                    reactive state allocated by hook:  _ReactiveLive → μq,d,b,qag_dso_prev ; Off/Certified → none
   ▼
 ┌─ _admm_iterate!(state, …) for k = 1:maxiter ─────────────────────────────────────────┐
 │  1 AGR solves (hook: LIVE threads μq/d/ρ_q, collects b)                              │
 │  2 DSO coefficient update (hook: LIVE sets qag coefficients) → solve_dso!            │
 │  3 residual accumulation  (active loop; hook: reactive accumulators)                 │
 │  4 stacked norms → record! → converged? ──yes──► break                               │
 │  5 wall-clock budget? ──yes──► break (status = :budget_exceeded)                      │
 │  6 dual ascent (λ ; hook: μq, d, qag_dso_prev)                                       │
 │  7 _adapt_rho!(state)  (active ρ ; hook: ρ_q adapt)                                   │
 └──────────────────────────────────────────────────────────────────────────────────────┘
   ▼
 not converged & no budget exit ──► throw ConvergenceError (byte-identical message)
 budget exit                    ──► return (…nothing…, status = :budget_exceeded)
   ▼
 _admm_certify(state, …):  final AGR (battery + 4Q certs) → final solve_dso!(check_exact)
                           → :balance_p no-slack → hook: :balance_q no-slack (mode ≠ OFF)
                           → welfare from primals → λ_mat / mu_q / q_devices (hook) → NamedTuple (status = :converged)
```

### Recommended file layout

```
src/core/errors.jl            # TSODSOError, SolveFailedError, CertificateError, ConvergenceError, _is_solver_failure   (include BEFORE core/status.jl)
src/admm/admm_state.jl        # AdmmState, _ReactiveOff/_ReactiveCertified/_ReactiveLive + all hook methods, admm_supported
src/admm/admm_phases.jl       # _admm_build, _admm_iterate!, _adapt_rho!, _admm_certify
src/admm/solve_admm.jl        # public docstring + thin orchestrator (keeps the file the docs page and tests know)
```
`docs/src/api.md` `@autodocs` blocks list `Pages = [...]` by file path (`docs/src/api.md`, "Core" and "ADMM
Decomposition" sections): **every new file must be added to the matching `Pages` list** or exported symbols in it
fail `checkdocs = :exports` (`docs/make.jl:115`). Include order in `src/TSODSO.jl`: `errors.jl` between line 55
(`core/balance.jl`) and 56 (`core/status.jl`); ADMM files after `admm/DsoOpt.jl` (`src/TSODSO.jl` ADMM block).

### Pattern: singleton-dispatched reactive hooks
**What:** `abstract type _ReactiveMode end; struct _ReactiveOff <: _ReactiveMode end` etc.; `_react_mode(::ReactiveMode)`
maps the public enum once, right after `normalize_reactive_mode`. The `ReactiveMode` enum in results and the
`reactive_consensus` kwarg do not change (CONTEXT).
**When to use:** each of the 16 `mode`-conditioned sites below becomes one hook; OFF/CERTIFIED share no-op loop hooks
and differ only in `_react_certify!` (`mode != OFF` at `solve_admm.jl:833`).
**Hook map (every site, current line numbers):**

| Line(s) | Today | Hook (dispatch on `_ReactiveMode`) |
|---------|-------|------------------------------------|
| 357-376 | `μq, d, b, qag_dso_prev = mode == LIVE ? Dict(zeros) : Dict()` (4 sites) + `ρ_q_frozen` (377) | `_react_state(m, load_nodes, T, ρ_q)` returns `nothing` or a `_LiveState` |
| 407-426 | AGR solve call with/without `μ_j, d_j, ρ_q`; `b[j] = value.(qag_live)` | `_react_agr_solve!(m, st, agr, j, …)` |
| 445-457 | `set_objective_coefficient(dso.model, dso.qag[j,t], -μq-ρ_q*b)`; `qag_dso = value.(dso.qag)` | `_react_dso_prepare!(m, …)` / `_react_dso_read(m, dso)` |
| 483-500 | reactive accumulators `sq_r_q, sq_ds_q, sq_b, sq_qd, sq_μq` inside the shared `(j,t)` loop | `_react_accumulate!(m, acc, …)` (separate loop is bit-safe, see FP section) |
| 519-523 | `p_total = p_p*(LIVE ? 2 : 1)`, stacked `r_norm/s_norm/ε_pri/ε_dual` | `_react_stack(m, active, reactive)` |
| 559-570 | LIVE: `qag_dso_prev`, `μq +=`, `d = -qag_dso` inside the dual-ascent loop | `_react_dual_step!(m, …)` |
| 625-651 | `if mode == LIVE && !ρ_q_frozen` independent ρ_q adaptation (calls `set_rho_q!`) | `_react_adapt_rho!(m, …)` |
| 742-784 | final AGR re-solve (LIVE variant adds `μ_j,d_j,ρ_q`) + final `qag` coefficient re-assert | `_react_agr_solve!` (same hook, `final = true`) + `_react_dso_prepare!` |
| 833-839 | `if mode != OFF` certify `:balance_q` no-slack | `_react_certify_q!(m, dso)` (Off no-op; Certified/Live active) |
| 869-902 | `mu_q_mat`, `q_devices` (LIVE only) | `_react_outputs(m, st, agr_by_bus)` → `(mu_q, q_devices)` or `(nothing, nothing)` |

15 sites compare `== LIVE`, 1 is `!= OFF`; CONTEXT's "17+" over-counts slightly. Build-time `ReactiveMode` branches in
`DsoOpt.jl` (418-449, 323, 476, 485) and `AgrOpt.jl:159` are outside `solve_admm` and may stay as enum branches
(out of this phase's stated scope; a Phase 36 candidate).

### Anti-Patterns to Avoid
- **Re-opening arithmetic in the LIVE path.** Move code, do not rewrite it (FP section).
- **Putting `pf isa …` branches inside the loop.** Use `has_branch_current(ctx)` / `admm_supported(pf)` like
  `welfare_solve.jl:264` already does.
- **Leaving the `::MeshedFeeder` throw methods in place** (ambiguity, measured).
- **Matching error messages to classify failures** (CONTEXT forbids; wrap/convert at source).

## solve_admm Anatomy (Section 1 of the brief)

`function solve_admm` is `src/admm/solve_admm.jl:239-921`; docstring 54-238; `::MeshedFeeder` throw method 923-925.

| Region | Lines | Becomes |
|--------|-------|---------|
| Guards | 262-279 | stay in `solve_admm` (plus new pair/`admm_supported` guards first) |
| Mode normalize | 290 | stays; then `_react_mode(mode)` |
| Build (DSO, AGR per bus, 1:1 guards, `N`, `AdmmResiduals`) | 296-327 | `_admm_build` |
| State init | 336-394 | `AdmmState` constructor |
| Iterate (steps 1-4 + budget + dual ascent) | 395-570 | `_admm_iterate!` |
| ρ adaptation (active, then reactive) | 572-651 | `_adapt_rho!` (+ hook for ρ_q) |
| Post-loop: ConvergenceError / budget return | 654-690 | stays in orchestrator |
| Certification (final AGR, final DSO, no-slack, welfare, outputs) | 692-920 | `_admm_certify` |

**State carried across iterations (→ `AdmmState` fields):** `λ, c, a, pag_dso_prev, util :: Dict{Int,Vector/Float64}`,
`p_import::Vector{Float64}`, `ρf::Float64`, `ρ_frozen::Bool`, `exact_maxgap` (`nothing` until final),
`converged_flag`, `budget_exceeded_flag`, `t0_wall_ns::UInt64`; LIVE only: `μq, d, b, qag_dso_prev`, `ρ_qf`, `ρ_q_frozen`.
Loop-local only (do not store): `pag_dso`, `qag_dso`, all `sq_*`, `r_norm*`, `s_norm*`, `ε_*`, `price_gap`.
Used after the loop: `residuals`, `ρf` (ConvergenceError text, line 665), `λ, c, a, μq, b, util`.

**No closures/captures complicate extraction.** The only anonymous constructs are generators
(`has_4q_by_bus` 738-740, `sum(util[j] …)` 842, `reduce(vcat, (permutedims(-λ[j]) …))` 856/888) and `let` blocks (814, 834);
none capture a variable that is rebound across iterations. kwarg defaults depend on other args
(`reactive_consensus = _any_flexible_reactive(aggregators) ? LIVE : false`, `ρ_q = ρ`, lines 255-256): keep them on the
public method.

**Floating-point order that must be preserved (bit-identity):**
- Accumulation loop order `for j in load_nodes, t in 1:T` (j outer) with `+=` into `sq_r, sq_ds, sq_a, sq_pd, sq_λ`
  (483-490). The reactive accumulators are independent variables, so moving them to a separate loop is bit-safe; do NOT
  fuse or reorder the active ones.
- `r_norm = sqrt(sq_r + sq_r_q)`, `s_norm = ρf*sqrt(sq_ds) + ρ_qf*sqrt(sq_ds_q)`,
  `ε_pri = sqrt(p_total)*ε_abs + ε_rel*max(sqrt(sq_a+sq_b), sqrt(sq_pd+sq_qd))`, `ε_dual = … ε_rel*sqrt(sq_λ+sq_μq)`
  (519-523). Under OFF/CERTIFIED the `+ 0.0` terms are exact no-ops, so a hook may skip them; under LIVE keep the exact
  expressions. `price_gap = ρf * r_norm_p` (528) uses the ACTIVE-only norm even under LIVE.
- Active ρ adaptation uses active-only `r_norm_p, s_norm_p, ε_pri_p, ε_dual_p` (506-510, 596-618); `p_p = length(load_nodes)*T`
  is an `Int`.
- Dual step `λ[j][t] += ρf * (a[j][t] - pag_dso[j, t])`, `c[j][t] = -pag_dso[j, t]` (562-563): `c[j]` is mutated in place
  and re-passed to `solve_agr!`; keep `Dict{Int,Vector{Float64}}` storage.
- Statement order inside an iteration: AGR → (LIVE `set_objective_coefficient` on `dso.qag`) → `solve_dso!` → accumulate →
  `record!` → converged? → budget? → dual step → ρ adapt → ρ_q adapt. `set_rho!` order: `dso` first, then each AGR in
  `load_nodes` order (612-615). Preserve the order of `set_objective_coefficient` calls.
- Final: `welfare = sum(util[j] for j in load_nodes) - sum(λ₀[t]*p_import[t] for t in 1:T)` (842) and
  `λ_mat = reduce(vcat, (permutedims(-λ[j]) for j in load_nodes))` (856) verbatim; `mu_q_mat` uses `-μq[j]` (888).
- Final-solve constants stay literal: `τ_batt = 1e-3`, `rtol_4q = 1e-3`, `atol_4q = 1e-7`, `atol=1e-6` no-slack (816, 836).

**Bit-identity evidence (measured):** a renamed copy of `DsoOpt.jl`+`solve_admm.jl` (types loosened) run on the IEEE-13
Scenario (`Scenario(feeder=:ieee13, seed=7, T=24)`, `ρ=100`, Convex) gave `iters = 56` and
`welfare = -4823.66604824162` — exactly the canary pins (`test/test_admm_knifeedge_canary.jl`). So code duplication and
renaming did not flip the knife-edge. [VERIFIED: probe3, this session]

**Knife-edge risk (still real):** the canary header says an *unreachable `include`* or a Julia patch bump flips which side
of the iteration-28 numerical edge a build lands on. Run `test_admm_knifeedge_canary.jl` after EVERY plan that touches
`src/admm/`, `src/core/status.jl`, or `src/planning/retry.jl`. If it flips: do not re-pin silently — the file's own
RE-PIN LOG protocol applies; first bisect for an accidental change in model build order or solve-call kwargs.

## Formulation-generic ADMM (Section 2)

**What assumes `ConvexBranchFlow` / radial today:**

| Site | Assumption | Change |
|------|-----------|--------|
| `solve_admm.jl:239-241` | `feeder::Feeder`, `pf::ConvexBranchFlow` | `AbstractFeeder`, `AbstractPowerFlow` (+ `admm_supported` guard) |
| `solve_admm.jl:296-304` | calls `build_dso_opt` without `pf` | pass `pf = pf` |
| `DsoOpt.jl:~396` | `contribute!(ConvexBranchFlow(), ctx, feeder; T)` hard-coded; `build_dso_opt(feeder::Feeder, …)` | new kwarg `pf::AbstractPowerFlow = ConvexBranchFlow()` (keeps `hasmethod(build_dso_opt, Tuple{Feeder,Vector{Aggregator},Int})` true — asserted in `test/test_abstract_feeder.jl:140`); `feeder::AbstractFeeder` |
| `DsoOpt.jl:495-497`, `solve_admm.jl:923-925` | always-throw `::MeshedFeeder` methods | DELETE; add `_check_admm_pair!(fname, feeder, pf)` called first in both |
| `DsoOpt.jl solve_dso!` (~663-666) | `if check_exact` always runs `assert_socp_exact!` (reads `pf_vars.l`) | `if check_exact && has_branch_current(dso.ctx)`; LinDistFlow carries no `l` |
| `solve_admm.jl:796` | `exact_maxgap = dres_final.exact_maxgap` (`nothing` when not gated) | for non-cone formulations return `NaN` (CONTEXT; `run(::ADMM)` does `Float64(r.exact_maxgap)`, `run.jl:~145`) |
| `DsoOpt.jl:465` | `close_balance!(…; reactive = true)` | fine for all four admitted formulations (all `has_reactive == true`); DC is rejected anyway |
| `experiments/strategies.jl:184` | `supports_pf(::ADMM…)` convex non-literal only | widen (below); update `test/test_strategies.jl:72-86` |

**Not radial-dependent (verified):** `AgrOpt` never touches the feeder; `load_nodes`/`transit_nodes` in `DsoOpt` are
computed from aggregator buses and `N`, with no parent map (`DsoOpt.jl` ~323-336). `assert_socp_exact!` reads
`feeder.branches`/`feeder.root` duck-typed and already works on meshed ctxs (probe: `maxgap ≈ 1e-10`). The meshed
diamond's bus 4 (no aggregator) is handled as a transit node. The `:socp_maxgap` stash is only written when the gate runs.

**Per-formulation measured behaviour** (IEEE-13, `Scenario(seed=7,T=24)`, `allow_export=true`, `ρ₀=100`, type-loosened probe):

| pf | Centralized W | ADMM W | iters | maxgap | note |
|----|---------------|--------|-------|--------|------|
| ConvexBranchFlow | -4823.678196 | -4823.666048 | 56 | 4.6e-10 | equals canary |
| ConvexBranchFlow(thesis_literal=true) | -4823.678200 | -4823.666043 | 56 | 6.6e-10 | works |
| RestrictedBranchFlow | -4823.678197 | -4823.666044 | 56 | 7.7e-10 | works |
| LinDistFlow | -4821.184112 | -4821.177368 | 15 | `nothing` → must become `NaN` | **final AGR battery gate throws at default `τ_batt=1e-3`**: `bus 11, t=10: p_ch·p_dch = 6.51e-9 ≥ τ·Pmax² = 6.25e-9` (4% over). Passed once `τ_batt` was probe-loosened to 1e-2. The centralized LinDist solve also co-activates (6.07e-9, but only `@warn`s because `welfare_solve.jl` uses `on_violation = problem_class(pf) isa SOCP ? :error : :warn`). See Q3. |

Max |ΔDADP| vs centralized on IEEE-13 is 0.17 (Convex/Restricted) and 0.88 (LinDist) over all 24×10 entries at the
default stopping criteria. The existing IEEE-13 cross-validation test already tolerates this class of gap
(`test_admm.jl` atol 1e-2 after a tuned tighter stop; its comment cites max |Δ| = 0.139). Do NOT assert IEEE-13 DADP
equality for LinDist/Restricted without re-tuning; assert welfare (rtol 1e-4 held: LinDist 1.4e-6 relative, others 2.5e-6)
and use the small fixtures for price equality.

**`admm_supported` trait:** `admm_supported(::AbstractPowerFlow) = false`; `true` for `ConvexBranchFlow`,
`RestrictedBranchFlow`, `MeshedFlow`, `LinDistFlow`. `solve_admm`/`build_dso_opt` reject others with an `ArgumentError`
naming the function and the type. `supports_pf(::ADMM, pf::Symbol, tl)` becomes
`pf in (:convex_branch_flow, :restricted_branch_flow, :lindistflow)` (thesis-literal allowed for convex — measured OK above;
`:ac` still rejected: `test_strategies.jl:159` asserts `with_strategy(Scenario(pf=:ac), ADMM())` throws).
`supported_pfs(::ADMM)` must change in lockstep (`test_strategies.jl:84` pins the old tuple). MeshedFlow is not a
`Scenario` selector (`SCENARIO_VALID_PFS` at `Scenario.jl:38` excludes it); meshed ADMM is reachable only through
`solve_admm` directly.

**Pair checking.** Existing radial-only guards live in `contribute!(::{Convex,Restricted,LinDist}, ::ModelContext, ::MeshedFeeder)`
(`ConvexBranchFlow.jl:215`, `RestrictedBranchFlow.jl:210`, `LinDistFlow.jl:56`) but their messages do not name `solve_admm`.
`test/test_abstract_feeder.jl:115-141` requires the error to be an `ArgumentError` whose `.msg` contains both the function
name (`solve_admm` / `build_dso_opt`) and `MeshedFeeder`, **with an empty aggregator vector** — so the pair check must run
BEFORE the `isempty(aggregators)` guard (`solve_admm.jl:262`, `DsoOpt.jl` boundary guards). Valid meshed pair is exactly
`(MeshedFeeder, MeshedFlow)`; `(Feeder, MeshedFlow)` stays valid (MeshedFlow is drop-in for radial in the centralized path).

## Meshed live-reactive probe (ARCH-06)

**Method (reproducible):** copies of `DsoOpt.jl`/`solve_admm.jl` with `Feeder→AbstractFeeder`, `ConvexBranchFlow→pf`, the
`::MeshedFeeder` throw methods removed, functions renamed `*_g` (scratchpad `probe1/2/6.jl`), loaded into `TSODSO` via
`Base.include`. Fixture: the committed Phase-23 diamond (`test/fixtures_phase23.jl`: root 1 → buses 2,3 → merge bus 4,
`T=1`, `λ₀=4.0`, pinned Thermostatic loads 0.30/0.05, `φ=1.0` pins), `solve_welfare(…, MeshedFlow(), …)` as the centralized
reference. The Thermostatic members are `is_flexible_load`, so the smart default already resolves to `LIVE`
(`mode=LIVE` printed on every run). ρ₀=10.

| Case (profile, devices) | Centralized `dual(:balance_q)` buses 2,3 | note |
|-------------------------|------------------------------------------|------|
| uniform, φ=1 (+FourQuadBESS bus 2) | 5.5e-10, 2.07e-3 | near-degenerate μ (≈0); **angle-certified**; matches literate Section 3 |
| uniform, φ=0.95 | — | centralized solve itself throws `SOCP relaxation INEXACT` (ratio 3181; the Plan 26-13 finding, with or without BESS) → unusable fixture |
| heterogeneous, φ=1 (+BESS) | 3.2e-10, -2.31e-2 | non-degenerate at bus 3; angle-**un**recoverable (expected) but cone exact |
| heterogeneous, φ=0.95 (Thermostatic only) | 0.2511, 0.1354 | clearly non-degenerate reactive price; cone exact (maxgap 6.5e-11) |
| heterogeneous, φ=0.95 + BESS | 0.0551, 0.0320 | non-degenerate |

**ADMM vs centralized, het φ=0.95 (no BESS) and het φ=1 + BESS** (`ε` = `(ε_abs, ε_rel)`; max over buses 2,3):

| ε_abs, ε_rel | ρ₀ | iters (φ=.95 / BESS) | max abs ΔP price | max abs ΔQ price | abs ΔW |
|--------------|----|----------------------|------------------|------------------|--------|
| 1e-4, 1e-3 (defaults) | 10 | 7 / 7 | 3.6e-3 / 7.3e-4 | 2.9e-3 / 1.0e-3 | 4.4e-4 / 3.7e-4 |
| 1e-5, 1e-4 | 10 | 11 / 10 | 5.0e-4 / 8.3e-5 | 4.0e-4 / 1.9e-4 | 6.9e-5 / 1.9e-7 |
| 1e-6, 1e-5 | 10 | 16 / 14 | 3.2e-5 / 2.0e-5 | 4.1e-5 / 1.2e-5 | 5.8e-6 / 1.8e-6 |
| 1e-7, 1e-6 | 10 | 21 / 17 | 2.9e-5 / 1.1e-5 | 1.1e-5 / 9.4e-6 | 4.2e-7 / 2.9e-7 |
| 1e-6, 1e-5 | 1 | 37 / 23 | 5.4e-5 / 7.2e-6 | 5.3e-5 / 1.7e-5 | 4.1e-7 / 4.3e-6 |
| 1e-6, 1e-5 | 100 | 6 / 17 | 5.5e-5 / 1.7e-5 | 6.1e-5 / 1.9e-5 | 7.5e-6 / 1.2e-6 |

Timings: ≈0.04-0.2 s per solve after compilation (first call ≈9 s including compilation). The gap shrinks ~linearly with
`ε` until it hits a ≈1e-5 floor (interior-point dual accuracy, matches the project's `highs-exactness-defaults` lesson:
do not assert below the measured floor). At default `ε` the observed gap (3.6e-3) is of the order of the final `ε_dual`
(6.4e-3); the gap tracks `ε_dual`, not `ε_pri`.

**Recommended assertion set (planner picks; all derived from the table):**
- Run at `ε_abs = 1e-6, ε_rel = 1e-5` (cheap: 16 iterations, < 0.1 s); assert active and reactive price match with
  `atol = 5e-4` (≈8x headroom over the worst observed 6.1e-5 across ρ₀ ∈ {1,10,100}) and welfare
  `rtol = 1e-4` (observed ≈4e-6 relative; ≈25x headroom). Record the measured numbers in a comment (precedent:
  `test_admm_knifeedge_canary.jl` header).
- Use the **heterogeneous φ=0.95** variant for the reactive-price check (non-degenerate μ ≈ 0.25/0.135; a tolerance on a
  ≈1e-10 centralized value would be vacuous) — needs a small fixture addition (`Thermostatic(...; φ=0.95)` in a new
  helper; the committed `mesh_aggregators()` pins φ=1.0).
- Add the **uniform φ=1 + BESS** run for the composition claim: ADMM's `r.dso_ctx` passed to
  `certify_angle_recoverable!(…; report=true)` returns `:angle_certified` with `worst_residual = 0.0071997` vs
  centralized `0.0071986`; heterogeneous returns `:angle_unrecoverable` `0.0712808` vs `0.0712824` (verdicts agree). This
  proves meshed ADMM output is a first-class `ModelContext`.
- Assert `exact_maxgap < 1e-6` and `status == :converged`, `reactive_consensus_mode == LIVE`.
- Also assert (negative) that radial formulations × `MeshedFeeder` still throw (`test_abstract_feeder.jl` already; extend
  with `(MeshedFeeder, MeshedFlow)` valid).

## Status & exception inventory (Section 3)

| Entry point | Return `status` today | Throws today | Notes |
|-------------|-----------------------|--------------|-------|
| `solve_admm` | `status ∈ {:converged, :budget_exceeded}` (`solve_admm.jl:688,919`); `:budget_exceeded` returns `nothing` price fields | `ArgumentError` (guards 262-279, 310-324 incl. 1:1 guard; DsoOpt guards: bus range/root/WR-04 reactive); `ErrorException` on maxiter (`:661`); `ErrorException` from `assert_solved!`, `assert_battery_complementarity!`, `assert_4q_complementarity!`, `assert_socp_exact!`, `assert_no_slack` | has `status` already |
| `solve_stackelberg!` | **none**; has `converged_via ∈ {:clean, :nogood_assisted}` (`benders.jl:~1753`), `ub_relaxation_only` | `ArgumentError`; `ErrorException`: exhaustion (`benders.jl:1795`), `:reject` stalled (`~1508`), feas-oracle failure/`:disagree`/weak stall (`1417-1441`), epigraph floor (`784`), corner-recourse bugs (`381,541,590,659,680`), `assert_solved!`/exactness | single return site `:1755` |
| `run_nash!` | **none**; `converged = true` always (`nash.jl:1006`) | `ArgumentError`; `ErrorException`: exhaustion (`1020`), integer CYCLED (`954`), lattice/parity/damped guards (`833,863,890`), final consistency re-solve (`996`) | single return site `:1002` |
| `run_mpc` | **none** overall; per-resolve `trace.cert_status_trace ∈ {:certified_convex_dual, :certified_convex_dual_restricted, :local_ac_dual, :cert_failed}` (`mpc_loop.jl:497-510, 735, 997`) | `ArgumentError`; `ErrorException`: true-state out-of-band (`1267`), AC truth settlement non-convergence (`1640`), `error` size guards (`1356,1363`); `assert_solved!` via window `solve_with_retry!` | return NamedTuple at `:767` |
| `run_stochastic` | **none**; `oos.infeasible_h::Vector{Bool}` marks skip-and-report | `ArgumentError` (Scenario guards); `ErrorException` from solves/gates; documented catch in `_stoch_solve_held_out!` (`run_stochastic.jl:66-82`) | return NamedTuple `(; in_sample, oos)` |

**Proposed status vocabulary (discretionary names; all additive, no existing field changes):**

| Entry point | `status` values | Meaning |
|-------------|-----------------|---------|
| `solve_admm` | `:converged`, `:budget_exceeded` (existing) | unchanged |
| `solve_stackelberg!` | `:converged`, `:converged_relaxation_only` (iff `ub_relaxation_only`) | latter = documented `:certify_incumbent` degradation |
| `run_nash!` | `:converged`, `:converged_relaxation_only` (iff `any_relaxation_only`) | keep `converged = true` field |
| `run_mpc` | `:certified` (all steps first-tier), `:degraded` (≥1 step used `:certified_convex_dual_restricted`/`:local_ac_dual`, none `:cert_failed`), `:cert_failed` (≥1 `:cert_failed`; mirrors `any_cert_failed`) | derived from `trace.cert_status_trace` |
| `run_stochastic` | `:solved`, `:oos_infeasible_skipped` (any `infeasible_h`) | the documented skip-and-report |

Add `status` as a NamedTuple field to each return (`(; in_sample, oos, status)` etc.). No test inspects `keys`/`propertynames`
of these results (grep: only `haskey(res.q_devices, …)`), and `run_stochastic` reproducibility tests compare values, which
remain deterministic. A test asserting each entry point's returned `status` is in its documented vocabulary (a
module-level `const` table the docs page also renders) satisfies the CONTEXT requirement.

### Typed exceptions: strategy and blast radius (the Q1 finding)

**Types** (`src/core/errors.jl`): `abstract type TSODSOError <: Exception end`; each concrete type carries
`msg::String` and defines `Base.showerror(io, e) = print(io, e.msg)` so `sprint(showerror, e)` equals what the old
`ErrorException` printed, and `e.msg` keeps working (tests use `.msg` at ≥ 30 sites, listed below).
`SolveFailedError(msg, termination_status, primal_status, dual_status, raw_status[, attempts])`;
`CertificateError(msg)` (+ optional `kind::Symbol` e.g. `:socp_exact`, `:no_slack`, `:battery`, `:4q`, `:angle`);
`ConvergenceError(msg[, iterations])` (fields discretionary). Add helper
`_is_solver_failure(e) = e isa ErrorException || e isa TSODSOError` for legacy catch sites.

**What cannot be kept:** `@test_throws ErrorException` and `e isa ErrorException` on any converted source. `ErrorException`
is concrete [CITED: Julia Base `struct ErrorException <: Exception`; a concrete type has no subtypes]. CONTEXT's
"existing assertions keep passing" holds only for message-text assertions.

**Production catch sites that depend on `ErrorException` (must be widened to `_is_solver_failure` BEFORE any source is
converted; these are widenings that preserve behaviour, not the deferred narrowings):**
`src/planning/retry.jl:198` (the ladder — critical), `planning/benders.jl:318, 825, 1387, 1416`,
`planning/coupling.jl:487`, `planning/ac_recheck.jl:122` (also rewraps as `ErrorException` at 124),
`planning/subproblem.jl:358` (`on_inexact === :report` swallow of the exactness verdict → should become
`e isa CertificateError`), `pricing/fit.jl:692` (`occursin("ALMOST_OPTIMAL", e.msg)`; fit's own `ErrorException` at 612
is a separate non-converted error), `experiments/run_stochastic.jl:69` (narrowed in this phase). `planning/master.jl:194`
and `retry.jl:179` catch other things (Interrupt only / attribute rejection) and are unaffected. Other `catch` sites
(`DsoOpt.jl:118,145` attribute snapshot/restore with no solve inside; `scripts/*`) are inventoried only.

**Recommended conversion set (keep it minimal; everything else stays `ErrorException` and is inventoried):**

| New type | Sources |
|----------|---------|
| `SolveFailedError` | `assert_solved!` (`core/status.jl:57`); `solve_with_retry!` exhaustion (`retry.jl:206`) and attribute-rejection (`retry.jl:180`); `run_nash!` final consistency re-solve (`nash.jl:996`) |
| `CertificateError` | `assert_no_slack` (`status.jl:85`); `assert_socp_exact!` (`exactness.jl:264`); `assert_battery_complementarity!` (`welfare_solve.jl:373`); `assert_4q_complementarity!` (`complementarity_4q.jl:151`); `assert_restriction_exact!` (`restriction_exactness.jl:306`); `certify_angle_recoverable!` (`mesh_angle_certificate.jl:293`) |
| `ConvergenceError` | `solve_admm` maxiter (`solve_admm.jl:661`); `solve_stackelberg!` exhaustion (`benders.jl:1795`) and `:reject` stalled; `run_nash!` exhaustion (`nash.jl:1020`) and integer CYCLED (`954`) |

`assert_ac_exact!`'s `T`-mismatch (`ac_oracle.jl:310`) is a structural programmer error, unreachable inside the MPC tiers
(same `H`); recommend `ArgumentError` per the policy (invalid input) — but note the `_mpc_certify_and_price` docstring
(`mpc_loop.jl:828-832`) lists "`assert_ac_exact!`'s structural guards" as a documented tier thrower, so update that
docstring in the same plan. Modeling-bug asserts (`_assert_epigraph_floor`, `add_ll_cut!` Q_nu, `add_to_residual!`,
`close_balance!`, `welfare_accounting`, `_mpc_assert_true_state_inband`, AC truth settlement `mpc_loop.jl:1640`)
stay `ErrorException` (inventoried): they are not solver-status/certificate outcomes. The AC truth-settlement throw is
outside every try block (it propagates today and still will).

**Test assertions that match `ErrorException` on a converted family and must be edited** (enumerated by grep; update to
`SolveFailedError`/`CertificateError`/`ConvergenceError`/`TSODSOError`, or to the legacy-union helper where the test just
wants "some solver failure"):

| File:line | Converted family |
|-----------|------------------|
| `test_planning_retry.jl:54,71,86,138` (+ `.msg` 55,72,87,139) | `SolveFailedError` |
| `test_planning_benders.jl:253` (+ `.msg` 254,257) | `ConvergenceError` |
| `test_planning_nash.jl:519` (+`.msg` 520,521), `:873` (`run_nash_probe` exhaustion), `:1152` (+ `.msg` 1153 `SOCP relaxation INEXACT`) | `ConvergenceError` / `CertificateError` |
| `test_fourquadbess.jl:546,549,587` | `CertificateError` |
| `test_mesh_angle_certificate.jl:46` | `CertificateError` |
| `test_planning_inexact_policy.jl:82,198,318,342,361,494,499` | `CertificateError` / `ConvergenceError` (`:reject stalled`) |
| `test_planning_benders_integer.jl:132,178,199,218,228,235` | `_oracle_or_infeasible` rethrow semantics; injected fakes may remain `ErrorException` if the helper uses `_is_solver_failure` |
| `test_stochastic_welfare.jl:160,171,176` | `e isa ErrorException || rethrow()` → widen; `.msg` text assertions keep working |
| `test_mpc_loop.jl:~582` | `boom = (args…) -> error("forced tier failure (test seam)")` throws a plain `ErrorException`; after narrowing it would PROPAGATE and fail `test_mpc_loop.jl:515-612`. Change `boom` to throw `SolveFailedError` (CONTEXT intends this) |
| NOT converted (leave): `test_fit.jl:100,103`, `test_close_balance.jl:191`, `test_context.jl:114,119`, `test_feeder.jl:21`, `test_pricing_welfare.jl:137`, `test_planning_alpha_bounds_stackelberg.jl:199,211`, `test_planning_master_integer.jl:286,309`, `test_planning_ac_recheck.jl:93`, `test_mpc_loop.jl:126,132`, `test_planning_certification_integer.jl:176,561`, `test_planning_bilevel.jl:203` (KKT-cert solve; decide with Q1) | |

Tests using `@test_throws Exception` (e.g. `test_status.jl:17`, `test_admm.jl:222`, `test_admm_timeout.jl:53`) are unaffected.
A full-suite grep for `ErrorException` is the executor's checklist; this table is the static enumeration.

## mpc_loop catch inventory (Section 4)

`src/experiments/mpc_loop.jl` contains exactly **two** `try/catch` blocks, both inside `_mpc_certify_and_price`
(`:922-962` tier 2, `:970-982` tier 3); both are `catch err; err isa InterruptException && rethrow(); push!(tier_reasons, …)`.
Everything else in the file (`run_mpc` loop, `_mpc_truth_import_acpf`, state propagation) has no catch.

What each tier can legitimately raise (all verified by reading the callees):
- **Tier 2** (`_solve_welfare(RestrictedBranchFlow, rtol_exact = Inf)`, `_solve_welfare(ACPowerFlow, allow_local = true)`,
  `assert_restriction_exact!(…; report = true)`): `assert_solved!` failure → `SolveFailedError`;
  `assert_battery_complementarity!` (`on_violation = :error` for SOCP-class; `:warn` for AC) → `CertificateError`;
  `assert_socp_exact!` is neutralized by `rtol_exact = Inf` on the restricted solve; `assert_restriction_exact!(report=true)`
  reports instead of throwing, except the `assert_ac_exact!` T-mismatch (unreachable).
- **Tier 3** (`ac_dual_fallback_price` → `solve_welfare(ACPowerFlow, allow_local = true, optimizer = variant)` ×
  `n_seeds`): `assert_solved!` → `SolveFailedError`; `ArgumentError` for a bad `n_seeds` (programmer error, now propagates).
- Ipopt/JuMP do not throw raw exceptions for non-convergence: failures surface through `termination_status`, which
  `assert_solved!` converts. So **no extra wrapping beyond the `assert_solved!` conversion is needed** to keep behaviour; the
  "wrap non-TSODSO errors at source" clause has no live instance in `mpc_loop.jl` (a `KeyError` from a missing
  `:balance_p`, a `FieldError` on `fallback.dadp`, or `DomainError` would all be programming errors and now propagate, which
  is the intent). `sqrt` calls in the file are guarded with `max(·, 0)` (`mpc_loop.jl:1459`).
- Solver-factory `error(...)` (`solver/factory.jl:197,224`) and `solve_with_retry!`'s attribute rejection are
  configuration errors. The latter is converted to `SolveFailedError` for completeness; the former stays and propagates.
- `InterruptException` keeps its explicit `rethrow()` (it is not a `TSODSOError` so narrowing covers it, but keep the
  explicit line for readability).

**Narrowed catch form:**
```julia
catch err
    err isa Union{SolveFailedError, CertificateError} || rethrow()
    push!(tier_reasons, "restricted tier threw: " * sprint(showerror, err))
end
```
(`ConvergenceError` is not raised by either tier today; CONTEXT says add it "where a tier is iterative" — neither is.)

**`run_stochastic`** (`_stoch_solve_held_out!`, `run_stochastic.jl:66-82`): narrow `e isa ErrorException || rethrow()` to
`e isa SolveFailedError || rethrow()`; keep the `termination_status(h_oos.model) ∈ (INFEASIBLE, INFEASIBLE_OR_UNBOUNDED,
LOCALLY_INFEASIBLE)` check (it does not match strings). The path is `solve_stochastic_oos_step!` → `solve_with_retry!` →
`assert_solved!`, so it raises `SolveFailedError` after conversion. Existing test coverage: `test_run_stochastic.jl`,
`test_stochastic_oos_harness.jl` (confirm the WR-05 infeasible-held-out case there still passes).

**Existing seams for injection:** `_mpc_certify_and_price(…; _solve_welfare, _ac_dual_fallback_price)`. New tests: seams
throwing `MethodError`, `BoundsError`, `ArgumentError`, `KeyError` → `@test_throws` (propagate); seams throwing
`SolveFailedError`/`CertificateError` → result `:cert_failed` / `:local_ac_dual` exactly as `test_mpc_loop.jl:515-612` assert today.
Reuse the `Phase21Fixtures.mpc_high_pv_feeder()` setup in that test item (it needs `ConvexBranchFlow(thesis_literal=true)` to force
escalation — see the PM-01 comment at `:546`).

## The deferred `has_reactive` guard (Section 5)

**What happens today (measured):** `solve_welfare(ieee13 feeder, DCPowerFlow(), default aggregators; T=24, allow_export=true)`
solves `OPTIMAL` (obj -4819.94). `has_reactive(DCPowerFlow()) == false` (`DCPowerFlow.jl:67`) so `close_balance!` runs with
`reactive = false`: `ctx.residuals[:Rq]` exists and 240 of 264 entries are non-trivial (aggregators write reactive terms
unconditionally, `welfare_solve.jl:~182-190` comment), but no `:balance_q` constraint is registered
(`keys(ctx.constraints) == [:balance_p]`). So the reactive terms are silently dropped — the documented "DC is active-only"
behaviour (`welfare_solve.jl:170-182`), identical before Phase 33. A hard guard would change every DC+aggregator solve
(10/10 IEEE-13 aggregators carry flexible loads), exactly what the Phase-33 review refused to do.

**Recommendation (non-behaviour-changing):** do NOT add a throw. Add a pinning test (`test/test_status_policy.jl` or the
existing `test_model_context_traits.jl`) asserting for DC + aggregators: solves optimal; `has_reactive(pf) == false`;
`haskey(ctx.residuals, :Rq)` true; `!haskey(ctx.constraints, :balance_q)`; objective equals the pre-change value to full
precision (record it in the test; the 10 IEEE-13 aggregators with seed 7 give `-4819.9377763808125`). Document the rule
in the policy page as "documented degradation, no throw/no status" (reactive terms of aggregators on an active-only
formulation are intentionally unclosed). An optional `@debug`/helper `unclosed_reactive_terms(ctx)` diagnostic is allowed
but not required; do not emit a `@warn` from `solve_welfare` (it fires on every DC solve and would flood logs).
Closing this item under ARCH-08 requires only the pin and the doc sentence.

## Docs (Section 6)

- **Policy page location:** new hand-written `docs/src/status_policy.md` (peer of `docs/src/index.md`/`api.md`, which are
  already hand-written), added to `docs/make.jl` `pages` (e.g. `"Status & Exception Policy" => "status_policy.md"` after
  "Experiments"). Give it an `@id status-policy` anchor; the five entry-point docstrings link with
  ``[status & exception policy](@ref status-policy)``. `:cross_references` is in `warnonly` (`docs/make.jl:116`), so a broken
  ref is non-fatal but still check the build log. Render the vocabulary from the same `const` table the status test uses
  (an `@eval`/`@example` block) so docs cannot drift.
- **`docs/src/api.md`:** add `core/errors.jl` to the "Core: Model Context & Status" `Pages` list; add
  `admm/admm_state.jl`, `admm/admm_phases.jl` to "ADMM Decomposition". New exports needing a docstring AND surfacing:
  `TSODSOError`, `SolveFailedError`, `CertificateError`, `ConvergenceError`, `admm_supported`. Internal `_admm_*`/`_react_*`
  are unexported (no `checkdocs` pressure, and no PVAL-04 allowlist entry: the tripwire only watches exported `build_*`
  names, `test_planning_noninteger.jl:244`).
- **Meshed page:** edit `docs/literate/meshed_reactive_price.jl`: header line 14-15 ("no meshed ADMM is built this rung"),
  Section 3 text at ~232-240 ("the CENTRALIZED analog … no meshed ADMM built this rung (D-04)"), and the "Explicit scope"
  note. Add a live `solve_admm(feeder, MeshedFlow(), aggs; reactive_consensus = :live, …)` call next to the centralized
  `dual.(ctx_bess.constraints[:balance_q][2, :])`, show the measured gaps as live `@example` output, and a self-checking
  `|| error("Rung 10 doc regression …")` line like the existing WR-02 pattern (`:228-230`). This page is executed during
  `makedocs`; a meshed ADMM run adds well under a second of solve time. Also a one-line pointer in `docs/literate/admm.jl`
  (radial-only 3-bus text at :51-90) that ADMM now accepts any `admm_supported` formulation.
- **Build:** CI runs `julia --project=docs docs/make.jl` (`.github/workflows/CI.yml:131`); locally Literate pages need the
  docs env (memory `gsd-plan-verify-testitemrunner-trap`: `JULIA_LOAD_PATH="docs:.:@stdlib"`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Classifying solver failure vs bug in handlers | message-string matching | `isa` on the typed exceptions | CONTEXT forbids; strings drift |
| Exactness gating by formulation | `if pf isa ConvexBranchFlow` | `has_branch_current(ctx)` (Phase 33 trait with data cross-check) | already how `welfare_solve.jl:264` does it |
| Meshed network math | new meshed ADMM subproblem | `MeshedFlow` delegation inside `DsoOpt` | probe proves the existing set is graph-generic |
| Per-mode `if` chains in the loop | more `mode == …` branches | singleton hook dispatch | success criterion 1 |
| Angle recoverability for meshed ADMM output | custom check | `certify_angle_recoverable!(r.dso_ctx)` | measured to work on the DSO ctx |
| Solve retry/conditioning | new ladder | existing `solve_with_retry!` (widen its catch) | knife-edge canary depends on it |

## Common Pitfalls

### Pitfall 1: Typed errors silently disable the retry ladder
**What goes wrong:** converting `assert_solved!` without widening `retry.jl:198` (`e isa ErrorException || rethrow()`) makes
every retryable status rethrow immediately; DsoOpt's mid-loop ladder (`solve_dso!`) never escalates; IEEE-13 ADMM throws
`NUMERICAL_ERROR` on toolchains where it previously converged (canary history in the canary file header).
**Prevention:** Plan order: (a) types + `_is_solver_failure` + widen all listed catch sites with NO source conversion,
(b) convert sources. Add a unit test that `solve_with_retry!` still retries when `assert_solved!` throws `SolveFailedError`
(use the existing `test_planning_retry.jl` bad-model pattern).
**Warning signs:** `test_planning_retry.jl`, `test_admm_knifeedge_canary.jl`, `test_experiments.jl` failures.

### Pitfall 2: Method ambiguity from keeping the MeshedFeeder throw methods
Measured: `kwcall(…, solve_admm, ::MeshedFeeder, ::MeshedFlow, …) is ambiguous` between
`solve_admm(feeder::AbstractFeeder, pf::AbstractPowerFlow, aggs)` and `solve_admm(::MeshedFeeder, args…)`. Delete both
throwing methods (`solve_admm.jl:923`, `DsoOpt.jl:495`); keep the `hasmethod` assertions true.

### Pitfall 3: Pair-check ordering
`test_abstract_feeder.jl:115-141` calls with `Aggregator[]`; if the empty-aggregators guard runs first the message is wrong.
Put `_check_admm_pair!` first.

### Pitfall 4: Fused or reordered accumulations flip the knife-edge
See FP section. Run the canary after every ADMM plan.

### Pitfall 5: LinDistFlow ADMM final battery gate (measured, Q3)
Default `τ_batt = 1e-3` throws at IEEE-13 seed 7 (6.51e-9 vs 6.25e-9). Needs a decision before LinDist is advertised through
`supports_pf`; otherwise `Scenario(pf=:lindistflow, strategy=ADMM())` on `:ieee13` errors at runtime.

### Pitfall 6: New file not listed in api.md Pages
Exported symbol in an unlisted file → `checkdocs = :exports` build failure.

### Pitfall 7: Background/stale full-suite runs and worktree contamination
From memory: full suite 16-36 min, a 10-min Bash tool timeout kills it; launch detached with a DONE marker; no
`.claude/worktrees/agent-*` may exist during a certifying run; compare against baseline 31915/0/0/5 at b955aa4.

### Pitfall 8: TestItem scoping
`try x = …` / for-loop reassignment of outer vars break under `@testitem` top-level scope (memory); wrap in functions
(as `test_abstract_feeder.jl:118` does with `_check()`).

## Code Examples

### Typed exception with preserved text and `.msg`
```julia
# src/core/errors.jl   (design sketch; field set of ConvergenceError is discretionary)
abstract type TSODSOError <: Exception end

struct SolveFailedError <: TSODSOError
    msg::String
    termination_status::MOI.TerminationStatusCode
    primal_status::MOI.ResultStatusCode
    dual_status::MOI.ResultStatusCode
    raw_status::String
end
Base.showerror(io::IO, e::SolveFailedError) = print(io, e.msg)
# assert_solved!: build the SAME multi-line string it passes to error() today, then
#   throw(SolveFailedError(msg, termination_status(model), primal_status(model), dual_status(model), raw_status(model)))

_is_solver_failure(e) = e isa ErrorException || e isa TSODSOError   # legacy catch sites only
```

### Pair check + generic signature
```julia
admm_supported(::AbstractPowerFlow) = false
admm_supported(::Union{ConvexBranchFlow,RestrictedBranchFlow,MeshedFlow,LinDistFlow}) = true

function _check_admm_pair!(fname::Symbol, feeder::AbstractFeeder, pf::AbstractPowerFlow)
    admm_supported(pf) || throw(ArgumentError("$fname: power flow $(typeof(pf)) is not ADMM-capable …"))
    feeder isa MeshedFeeder && !(pf isa MeshedFlow) && throw(ArgumentError(
        "$fname is radial-only for $(typeof(pf)) (…); got a MeshedFeeder — use pf = MeshedFlow() …"))  # must contain fname and "MeshedFeeder"
    return nothing
end
```

### Narrowed MPC tier catch
```julia
catch err
    err isa Union{SolveFailedError, CertificateError} || rethrow()
    push!(tier_reasons, "restricted tier threw: " * sprint(showerror, err))
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `error("…")` for every refusal | typed `TSODSOError` hierarchy | this phase | callers can catch precisely; legacy catch sites widened |
| `solve_admm` type-restricted to `ConvexBranchFlow` (audit cites `:224`, now `:241`) | any `admm_supported` pf | this phase | closes MESH-06 |
| DsoOpt hard-codes `ConvexBranchFlow()` | passed `pf` | this phase | Restricted/LinDist/Meshed ADMM |

## Runtime State Inventory

Not a rename/migration phase. None — no stored data, service config, OS registrations, secrets, or build artifacts embed
a renamed string. (Verified: the phase renames only internal Julia symbols; `Scenario`-serialized fields are unchanged;
`status` fields are additive. `ScenarioResult`/store schema is untouched.)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Status vocabulary names (`:certified/:degraded/:cert_failed`, `:solved/:oos_infeasible_skipped`, `:converged_relaxation_only`) | Status inventory | Cosmetic; CONTEXT leaves per-entry vocabulary to us. Confirm in plan review |
| A2 | `thesis_literal = true` should be allowed through `supports_pf(::ADMM)` | Formulation-generic | Probe shows it converges (56 iters), but CONTEXT says only "both variants" for `admm_supported`, not the Scenario matrix; confirm |
| A3 | `assert_ac_exact!` T-mismatch becomes `ArgumentError` | Typed exceptions | If a caller relies on it being caught by the tier, behaviour changes; unreachable in production (same `H`) |
| A4 | Keeping `SOCP()` solver factory for LinDist DsoOpt | Formulation-generic | Probe used it and converged; `problem_class(LinDistFlow)=QP()` might select different tolerances |
| A5 | Docs build locally via `julia --project=docs docs/make.jl` | Docs | CI uses exactly this; local env may need instantiate |

## Open Questions (RESOLVED)

1. **Q1 (needs user confirmation, highest impact): ErrorException break.** CONTEXT assumes existing `@test_throws`
   assertions keep passing; they do not for `ErrorException`-typed matches (≈20 test lines + 11 production catch sites, listed
   above). Recommendation: keep the locked typed-exception decision; widen catch sites first via `_is_solver_failure`; edit the
   listed tests to the new types. Alternative (zero test edits) would be to NOT convert, which defeats ARCH-09. Planner should
   surface this at plan-check. RESOLVED (user 2026-10-04): ACCEPT migration — ordered rollout types+predicate → widen 11 catch sites → convert throw sites → update ~20 tests; canary after each step.
2. **Q2: Scope of `ConvergenceError` conversions.** Recommended set: solve_admm maxiter, `solve_stackelberg!` exhaustion +
   `:reject` stalled, `run_nash!` exhaustion + CYCLED. The other planning `error(...)` sites (corner-recourse, KKT cert, epigraph
   floor, add_ll_cut!) are modeling-bug asserts; recommend leaving as `ErrorException` and inventorying them in the policy doc. RESOLVED: adopt the recommended set.
3. **Q3: LinDistFlow ADMM final battery gate.** Recommended: add an additive `solve_agr!` kwarg
   (`battery_on_violation::Symbol = :error`, existing callers unchanged) and have `solve_admm` pass `:warn` iff
   `!(problem_class(pf) isa SOCP)`, mirroring `welfare_solve.jl`'s centralized rule. Alternative: drop `:lindistflow` from the
   widened `supports_pf(::ADMM)` matrix and keep it direct-call only. Needs one measured decision at plan time (LinDist ADMM on
   the small fixtures was NOT probed; only IEEE-13). RESOLVED (user): warn-gate for non-SOCP via additive `solve_agr!` kwarg; LinDistFlow joins admm_supported.
4. **Q4: Fixture for the reactive-price check.** Committed `mesh_aggregators()` has `φ=1.0` pins so its reactive price is ≈0;
   uniform+φ=0.95 is centrally inexact. Recommended: heterogeneous profile + a `φ=0.95` Thermostatic variant (new test helper)
   for the price check, uniform φ=1+BESS for the angle-certificate composition check. RESOLVED: adopt recommendation.
5. **Q5: Canary re-pin.** If the refactor flips the knife-edge despite identical math, CONTEXT says the pins do not move.
   Decide beforehand: investigate model-build order first; re-pin only through the file's RE-PIN LOG with a user checkpoint. RESOLVED (user): NEVER re-pin; any canary change means FP order drifted and the refactor must be fixed.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | yes | 1.12.5 (juliaup) | — |
| Clarabel/HiGHS/Ipopt (via project env) | probes, tests | yes (probes ran) | pinned Manifest | — |
| TestItemRunner recipe | targeted tests | yes | verified: `JULIA_LOAD_PATH="@:.:test:@stdlib" julia --project=. -e 'using TestItemRunner; TestItemRunner.run_tests(joinpath(pwd(),"test"); filter = ti -> endswith(ti.filename, "test_abstract_feeder.jl"))'` → 33/33 in 24 s | — |
| docs env (Documenter, Literate, CairoMakie) | docs build | assumed instantiated | docs/Manifest 1.12.5 | instantiate |
| `ctx7`, slopcheck, web | not needed | n/a | — | — |

No blocking dependencies.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | TestItems/TestItemRunner (`@testitem`), Julia 1.12.5 |
| Config file | `test/runtests.jl`, per-feature `test/test_*.jl`, fixtures `test/fixtures_phase*.jl` (`@testmodule`) |
| Quick run command | `JULIA_LOAD_PATH="@:.:test:@stdlib" julia --project=. -e 'using TestItemRunner; TestItemRunner.run_tests(joinpath(pwd(),"test"); filter = ti -> endswith(ti.filename, "test_<name>.jl"))'` |
| Full suite command | detached: `nohup setsid bash -c "julia --project=. -e 'import Pkg; Pkg.test()' > LOG 2>&1; echo \$? > DONE" </dev/null &` then poll the marker (16-36 min; never in a ≤10-min foreground Bash) |
| Docs gate | `julia --project=docs docs/make.jl` (CI: `.github/workflows/CI.yml:131`) |

Plan `<verify>` blocks must use the TestItemRunner recipe above or direct Test.jl scripts (memory
`gsd-plan-verify-testitemrunner-trap`), not bare `--project=.` TestItemRunner.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command (file) | File Exists? |
|--------|----------|-----------|--------------------------|--------------|
| ARCH-05 | default path bit-identical (iters 56, welfare -4823.66604824162) | integration/canary | `test_admm_knifeedge_canary.jl` | exists |
| ARCH-05 | all ADMM goldens unchanged | integration | `test_admm.jl`, `test_admm_reactive.jl`, `test_admm_adaptive.jl`, `test_admm_dualresid.jl`, `test_admm_timeout.jl`, `test_dso.jl`, `test_agr.jl`, `test_ieee123_admm.jl` | exist |
| ARCH-05 | `AdmmState`/phase functions callable; hook dispatch per `_Reactive*`; grep audit: no `mode == LIVE` outside hook definitions | unit + grep audit | `test_admm_phases.jl` | Wave 0 |
| ARCH-05 | `admm_supported` matrix (Convex both variants, Restricted, Meshed, LinDist true; AC, DC `ArgumentError`); LinDist `exact_maxgap` is `NaN`; Restricted/LinDist welfare vs centralized (rtol 1e-4) on a small radial fixture | unit/integration | `test_admm_generic_pf.jl` | Wave 0 |
| ARCH-05 | `supports_pf`/`supported_pfs` widened; `:ac` still rejected | unit | `test_strategies.jl` (edit :72-86), `test_scenario_pf.jl` | exist, edit |
| ARCH-06 | pair check: `(MeshedFeeder, non-Meshed pf)` throws `ArgumentError` naming fn + `MeshedFeeder` (with empty aggs); `(MeshedFeeder, MeshedFlow)` accepted | unit | `test_abstract_feeder.jl` (edit :115-141) | exists, edit |
| ARCH-06 | meshed ADMM LIVE vs centralized: price P/Q atol 5e-4, welfare rtol 1e-4 at ε=(1e-6,1e-5); `exact_maxgap<1e-6`; angle-certificate verdict agrees | integration | `test_admm_meshed.jl` | Wave 0 |
| ARCH-08 | typed exception hierarchy; `.msg`, `showerror` text byte-identical to captured strings; `SolveFailedError` fields | unit | `test_tsodso_errors.jl` | Wave 0 |
| ARCH-08 | each entry point's `status` ∈ documented vocabulary; DC+reactive pin | integration | `test_status_policy.jl` | Wave 0 |
| ARCH-08 | retry ladder still retries on `SolveFailedError` | unit | `test_planning_retry.jl` (edit :54-139) | exists, edit |
| ARCH-09 | MethodError/BoundsError/ArgumentError/KeyError from either tier seam PROPAGATE; `SolveFailedError`/`CertificateError` ledgered as before | unit | `test_mpc_loop.jl` (edit seam `boom` ~:582, add items) | exists, edit |
| ARCH-09 | `_stoch_solve_held_out!` narrowed; infeasible held-out still skip-and-report; other error propagates | unit | `test_run_stochastic.jl` / `test_stochastic_oos_harness.jl` | exist, add item |
| docs | docs build with exports surfaced, meshed page self-check | build | `docs/make.jl` | exists |
| quality | Aqua (ambiguities/exports), no new stale deps | suite | full suite | exists |

### Sampling Rate
- **Per task commit:** the targeted `test_<name>.jl` for the touched seam (≈25-60 s each incl. startup).
- **Per plan / wave merge:** all files in the table touching that wave + `test_admm_knifeedge_canary.jl`.
- **Phase gate:** detached full suite ≥ 31915 passed / 0 failed / 0 errored / 5 broken (plus new tests) with clean
  `git worktree list`, plus docs build, before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/test_tsodso_errors.jl` — covers ARCH-08 (types, text fidelity, `.msg`)
- [ ] `test/test_status_policy.jl` — vocabulary table per entry point + DC/reactive pin (ARCH-08)
- [ ] `test/test_admm_phases.jl` — phase functions, hook dispatch, grep audit (ARCH-05)
- [ ] `test/test_admm_generic_pf.jl` — `admm_supported`, Restricted/LinDist (ARCH-05)
- [ ] `test/test_admm_meshed.jl` + a φ=0.95 heterogeneous-diamond helper in a fixtures module (ARCH-06)
- [ ] Update (not new): `test_strategies.jl`, `test_abstract_feeder.jl`, `test_mpc_loop.jl`, the ~12 files in the ErrorException table
- Framework install: none.

## Security Domain

`security_enforcement` is not set to false, so it is included, but this is an offline research library (no network,
auth, sessions, or persistence of secrets).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication / V3 Session / V4 Access Control | no | n/a (library) |
| V5 Input Validation | yes | `ArgumentError` boundary guards (pair check, `admm_supported`, existing T/λ₀/maxiter checks); never `@assert` (elided under `-O`) |
| V6 Cryptography | no | n/a |
| V7 Error handling / logging | yes | typed exceptions carry diagnostics without secrets; no message-string parsing |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Certificate laundering (a published price from an uncertified solve) | Tampering | keep `atol_exact/rtol_exact` seam semantics; certificates raise `CertificateError`; narrowed catches must never convert a *programming* error into a "certified" ledger entry |
| Swallowing programmer errors in broad catches | Repudiation | ARCH-09 narrowing; tests inject `MethodError`/`BoundsError` |
| Silent mis-pairing of topology and formulation | Tampering | up-front pair check with named error |

## Sources

### Primary (HIGH confidence — read or executed this session)
- `src/admm/solve_admm.jl` (full), `src/admm/DsoOpt.jl` (full), `src/admm/AgrOpt.jl` (signature/solve path), `src/admm/ReactiveMode.jl`, `src/core/status.jl`, `src/planning/retry.jl`, `src/powerflow/MeshedFlow.jl`, `src/models/welfare_solve.jl:170-300`, `src/experiments/{run,strategies,mpc_loop,run_stochastic}.jl`, `src/planning/{benders,nash}.jl` return/throw sites, `docs/make.jl`, `docs/src/api.md`, `docs/literate/meshed_reactive_price.jl`, `.github/workflows/CI.yml`
- Tests: `test_abstract_feeder.jl`, `test_strategies.jl`, `test_mpc_loop.jl`, `test_admm.jl`, `test_admm_knifeedge_canary.jl`, `fixtures_phase23.jl`, grep of all `ErrorException`/`.msg` uses
- Executed probes (scratchpad, not committed): meshed ADMM (probe1/2/6), radial Restricted/LinDist/thesis-literal ADMM (probe3/4/7), DC+reactive (probe5); TestItemRunner recipe run
- `.planning/{34-CONTEXT,REQUIREMENTS,milestones/v3.0-MILESTONE-AUDIT,33-REVIEW-FIX}.md`, project memory notes named in the brief

### Secondary / Tertiary
- None. No web sources were needed; the one external fact (`ErrorException` is a concrete struct) is Julia Base language semantics [ASSUMED from training; trivially re-checkable with `isconcretetype(ErrorException)`].

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages
- Architecture (decomposition, hooks, FP order): HIGH — read line by line; bit-identity evidenced by the renamed-copy canary reproduction
- Meshed cross-validation numbers: HIGH for this fixture and these settings (executed); MEDIUM for generalizing the tolerances to other fixtures
- Typed-exception blast radius: HIGH for production catch sites (grep-complete in `src/`), MEDIUM for the test list (static grep; the executor's full-suite grep is the net)
- LinDist ADMM: MEDIUM (one measured case, IEEE-13 seed 7)

**Research date:** 2026-10-04
**Valid until:** until `src/admm/`, `src/core/status.jl`, or `src/planning/retry.jl` change on `main` (currently clean at a89fc86); otherwise 30 days.

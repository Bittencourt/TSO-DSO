# Phase 21: MPC / Rolling-Horizon / Real-Time Pricing - Research

**Researched:** 2026-08-09
**Domain:** JuMP build-once/re-solve mechanics for a receding-horizon closed loop over stateful
devices, layered on the existing centralized welfare solve + Phase-20 overvoltage certificate.
**Confidence:** HIGH on JuMP mechanics and existing-code seams (all claims below are grounded in
files read this session, cited by path:line); MEDIUM on the recommended MPC loop architecture
(a NEW design, following the closest existing precedent — `PlanningOracle`); LOW/flagged where
the codebase has no precedent at all (window-boundary shrinkage, Scenario.jl savename-hash
tension) — both resolved inline below with a recommendation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Rolling-Horizon Architecture**
- **D-01:** The MPC loop lives in a **new sibling orchestrator module** (v2.0 `PlanningOracle`
  orchestrator precedent), wiring the SEAM-01 `horizon_state` stub (src/models/oracle.jl) —
  `welfare_solve.jl` stays untouched. Module location/name at Claude's discretion (e.g.
  `src/models/mpc_loop.jl` or `src/experiments/`).
- **D-02:** Each window solves the **centralized `solve_welfare`** problem — not ADMM. ADMM-in-the-
  loop is explicitly deferred.
- **D-03:** Horizon `H` and step size are **researcher-supplied kwargs with sane defaults** on the
  24h fixture. No auto-tuning. Window problem is **built once and re-solved per step via JuMP
  `Parameter` injection** of the measured state (MPC-01, locked by ROADMAP).
- **D-04:** Overvoltage boundary mid-simulation: **per-step certificate check using the Phase-20
  machinery**; on certificate failure at a step, record the status + Phase-20 fallback path in the
  trace and continue — **never throw mid-loop**.

**State Propagation & Terminal Condition**
- **D-05:** "Measured" state comes from a **nominal plant**: apply each step's first-interval
  optimal controls to the ground-truth device dynamics (same device models, true realization).
  Model mismatch enters only via forecast error.
- **D-06:** Terminal-SOC condition (MPC-02): **hard equality to the day-ahead optimal SOC
  trajectory value at each window's end** — information-set-fair vs the benchmark. The MPC-02
  regression must demonstrate the dump/hoard artifact present when disabled, absent when enabled.
- **D-07:** **No terminal condition on thermostatic temperature** — the comfort band suffices.
- **D-08:** Forecast error: **seeded bounded perturbation** of PV + demand ground truth
  (magnitude kwarg, e.g. ±5–10%), constant within a window, regenerated per step. No
  horizon-decaying error sophistication (deferred).

**RTP Trace & Benchmark Semantics**
- **D-09:** New exported **trace struct following the `AdmmResiduals`/`BendersTrace` convention**
  (name at Claude's discretion, e.g. `MpcTrace`): per-step published DADPs, step-to-step price
  jumps, cumulative deviation vs the day-ahead DADP path, per-step certificate/fallback status.
- **D-10:** Exact price-consistency norms (max/mean jump etc.) at Claude's discretion, provided
  both MPC-03 metrics (step-to-step jumps, cumulative deviation) are recorded and documented.
- **D-11:** Benchmark framing (MPC-04): **regret** — closed-loop realized welfare vs the
  perfect-foresight day-ahead optimum computed on the same realized truth (information-set-fair),
  plus the price-deviation path, under seeded synthetic forecast error, in a live-executed
  literate rung page.
- **D-12:** `Scenario.jl` extension: **minimal additive `@kwdef` fields with defaults that
  preserve existing golden hashes** (schema-fragile, golden-hash-bearing file), explicitly
  documented to compose with Phase 22's coming scenario-tree fields (coordinated-diff note).

### Claude's Discretion
- Module/struct/function/kwarg names throughout (loop orchestrator, trace struct, terminal-SOC
  kwarg, forecast-error kwargs).
- Exact default values for H, step, forecast-error magnitude (measure what makes the fixture
  demonstrative), and the exact price-consistency norm definitions (D-10).
- Which fixture drives CI (small radial per Phase-19 D-13 precedent) vs quarantined evidence.

### Deferred Ideas (OUT OF SCOPE)
- ADMM-in-the-loop (per-window decomposition) — deferred.
- Plant-model mismatch beyond forecast error — deferred.
- Horizon-decaying forecast-error models — deferred (natural Phase-22 composition point).
- Soft/penalized terminal-SOC variants — this rung is the hard terminal target only.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MPC-01 | Deterministic receding-horizon closed-loop solve, window `[t,t+H]` initialized from measured state via JuMP `Parameter` injection, build-once/re-solve, never rebuilt | §"The central seam: device IC constraints are NOT Parameter-ready today", §"Recommended architecture", §Code Examples — exact device-file changes + build-once regression idiom (`num_variables`/`num_constraints` invariance, the `test_planning_oracle.jl:72-87` precedent) |
| MPC-02 | Hard terminal-SOC condition preventing end-of-horizon dump/hoard, regression showing artifact present/absent | §"Terminal-SOC wiring", §"Pitfall: shrinking terminal window" |
| MPC-03 | Rolling re-computed DADP published per step as RTP, trace struct (`AdmmResiduals`/`BendersTrace` convention) recording jumps + cumulative deviation + certificate status | §"Price extraction per window", §"Trace struct convention" (mirrors `src/admm/residuals.jl`) |
| MPC-04 | Closed-loop benchmarked as regret vs perfect-foresight day-ahead optimum under seeded forecast error, live literate page | §"Per-step Phase-20 boundary handling", §"Regret benchmark", §Validation Architecture |
</phase_requirements>

## Summary

The phase's single hardest technical question is **not** the MPC control loop itself — it is
whether the codebase's existing model-building code (`solve_welfare`, `PVBattery.contribute!`,
`Thermostatic.contribute!`, `FourQuadBESS.contribute!`) is actually **Parameter-ready** for a
build-once/re-solve loop. It is **not**, today. `solve_welfare` builds a brand-new `Model` on
every call (`welfare_solve.jl:117`) and the stateful devices bake their initial condition as a
literal `Float64` in an **anonymous, unregistered, immediately-discarded** `@constraint`
(`PVBattery.jl:253`: `@constraint(m, soc[1] == d.soc0)`; `Thermostatic.jl:237`: `@constraint(m,
Tin[1] == d.Tin0)`; `FourQuadBESS.jl:300`: `@constraint(m, soc[1] == d.soc0)`). There is no
handle anywhere in the current tree to re-target that value without rebuilding.

The one genuine build-once/re-solve precedent that *does* exist is the v2.0 planning layer's
`PlanningOracle` (`src/planning/subproblem.jl`): it builds a welfare-shaped model exactly once
with `z[t] in Parameter(0.0)`, pins it via a named `p_import[t] == z[t]` constraint, and re-solves
via `set_parameter_value.(o.z, z_trial)` + `solve_with_retry!` — **without ever touching
`welfare_solve.jl`**. Its docstring is explicit that this is possible only because `z` combines
with `p_import` **affinely** (`p_import[t] == z[t]`, no product of two decision-like quantities).
The SAME pattern generalizes directly to MPC-01's `soc0`/`Tin0`/terminal-SOC/profile-slice
Parameters, because every one of those quantities enters the device models as a pure **additive**
constant — never multiplied by a decision variable. The one quantity that does **not** generalize
this way is the frontier wholesale price `λ₀[t]`, which multiplies the decision variable
`p_import[t]` in the objective (`welfare_solve.jl:237`) — exactly the "Parameter × variable
indefinite bilinear the conic backend rejects" pitfall the ADMM code already documents twice
(`AgrOpt.jl:23-24`, `DsoOpt.jl:27,131`). Sliding the window's `λ₀` slice therefore MUST use
`set_objective_coefficient`, mirroring `AgrOpt`/`DsoOpt`, never a `Parameter`.

`solve_welfare`'s own SOCP-exactness gate (`assert_socp_exact!`) has **no `report` kwarg — it
always throws** on an inexact cone. D-04's "never throw mid-loop" therefore cannot be satisfied by
calling `solve_welfare` (or its internal gate) bare inside the per-step loop; the orchestrator must
either wrap the call in `try`/`catch` or (cleaner, and the pattern Phase 20's own
`assert_restriction_exact!` uses) re-implement the cheap per-branch cone-residual check **inline**,
in report style, exactly as `assert_restriction_exact!` already does instead of delegating to
`assert_socp_exact!` (`restriction_exactness.jl:245-270`).

**Primary recommendation:** build a new, additive `src/models/mpc_window.jl` (or
`src/experiments/mpc_loop.jl`) mirroring `solve_welfare`'s SHAPE exactly like `PlanningOracle`
mirrors it — reusing `contribute!(pf,...)`/`contribute!(agg,...)` verbatim, never calling
`solve_welfare` itself inside the per-step loop. Widen `PVBattery`/`Thermostatic`/`FourQuadBESS`
in three small, additive, byte-identical-by-default edits: replace each device's bare IC
constraint with a `Parameter`-backed one and return the Parameter handle in `vars` (a widening of
the SAME optional-field contract MESH-04's `q_inject` already established). Use
`set_objective_coefficient` for the sliding `λ₀` slice. Use the day-ahead SOC trajectory, sliced
at each window's end, as the terminal-SOC Parameter target. Use the `test_planning_oracle.jl`
`num_variables`/`num_constraints`-invariance idiom (not `objectid`) as MPC-01's build-once
regression.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Window model build (contribute! reuse, Parameter wiring) | Model/Optimization (`src/models/`) | Device (`src/devices/`) | Mirrors `solve_welfare`'s own tier split: model assembly in `src/models/`, device physics in `src/devices/` unchanged except for the new Parameter handles |
| Receding-horizon orchestration (loop, state hand-off, forecast draw) | Experiment/Orchestration (`src/experiments/` or a new `src/models/` sibling) | — | Pure orchestration over already-validated builders — the `PlanningOracle`/`operational_oracle` precedent; no new solve math |
| Nominal-plant state propagation | Device (`src/devices/`) | Orchestration | The "ground truth" recursion is the SAME device equation (3.6/3.2), just evaluated outside the optimizer on realized (not optimized) inputs |
| Per-step certificate / fallback dispatch | Model/Optimization (Phase-20 machinery: `src/models/exactness.jl`, `restriction_exactness.jl`, `ac_dual_fallback.jl`) | Orchestration (dispatch decision only) | Certificates already live in `src/models/`; the loop only DECIDES which one to call and records the outcome |
| Price/trace reporting (`MpcTrace`) | Diagnostics (mirrors `src/admm/residuals.jl`) | — | Pure data ledger, JuMP-free, consumed by the literate page / CairoMakie exactly like `AdmmResiduals` |
| Regret benchmark (day-ahead perfect-foresight solve) | Model/Optimization (`solve_welfare` called ONCE, unmodified) | Orchestration | This IS a legitimate `solve_welfare` call site — a single monolithic day-ahead solve, not a re-solved loop |

## Standard Stack

No new runtime packages. Per `.planning/REQUIREMENTS.md`'s v3.0 preamble: "Zero new runtime
packages for four of five axes" — MPC is one of the four. Everything needed (JuMP `Parameter`,
`set_parameter_value`, `set_objective_coefficient`, Clarabel, `solve_with_retry!`,
`assert_socp_exact!`, `RestrictedBranchFlow`, `ac_dual_fallback_price`, `StableRNGs` for seeded
forecast error) already exists in the pinned `Manifest.toml` and is `[VERIFIED: codebase]` by
direct read this session.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | 1.30.1 (pinned, `Project.toml`) | `Parameter`-typed variables, `set_parameter_value`, `set_objective_coefficient` | Already the project's sole modeling layer; `Parameter()` is a JuMP 1.x-native primitive, already exercised in `src/planning/subproblem.jl:194` |
| Clarabel | 0.11.1 (pinned) | Re-solve backend for the window SOCP/QP | Unmodified — the window model routes through `select_optimizer(problem_class(pf))`, same as `solve_welfare` |
| StableRNGs | (pinned, already a dep via `generate_profiles`) | Seeded forecast-error perturbation (D-08) | `src/experiments/materialize.jl` already backs `generate_profiles` with a `StableRNGs.LehmerRNG`; the forecast-error draw should derive an INDEPENDENT `sub_seed` stream (`materialize.jl:17-25` pattern), never the global RNG |

### Supporting
None beyond the above — `CairoMakie` (already a dep) for the literate page's price/regret plots,
mirroring `docs/literate/restricted_branch_flow.jl`'s convention.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Reusing `solve_welfare` verbatim per window | A NEW mirror builder (recommended) | `solve_welfare` rebuilds a fresh `Model` every call — using it literally inside the per-step loop would violate MPC-01's own "never rebuilt" acceptance criterion and CLAUDE.md's hard build-once rule. D-02's "solves the centralized `solve_welfare` problem" is read here as describing the MATH shape (centralized welfare, not ADMM), exactly as D-01 already reads for `PlanningOracle` vs `welfare_solve.jl` — **(RESOLVED)**, see Open Questions #1 |
| `try`/`catch` around `solve_welfare`'s throwing gate | Inline report-style cone check (recommended) | `assert_socp_exact!` has no `report` kwarg; wrapping in `try/catch` works but re-throws on ANY error (masking genuine bugs, not just cone slack). `assert_restriction_exact!` already establishes the "reimplement the cheap residual inline in report style" idiom (`restriction_exactness.jl:245-270`) — cheaper (no second solve) and distinguishes cone-inexactness from a genuine solver failure |

## Package Legitimacy Audit

Not applicable — no new packages are installed by this phase (confirmed above: zero new runtime
dependencies, everything reused from the pinned `Manifest.toml`).

## Architecture Patterns

### System Architecture Diagram

```
seeded ground-truth generation (materialize.jl-style, independent sub_seed stream)
        │
        ▼
day-ahead perfect-foresight solve  ──────────────────────────────┐  (ONE call, T=24,
   solve_welfare(feeder, pf, aggs; T=24, λ₀, allow_export)        │   solve_welfare UNMODIFIED)
        │                                                          │
        ▼                                                          │
day-ahead SOC trajectory soc*[1..24]  ──────────► terminal-SOC     │  MPC-04 regret
        │                                          target per      │  benchmark input
        │                                          window (D-06)   │
        ▼                                                          │
┌───────────────────── MPC LOOP (t = 1 .. T-H+1) ─────────────────┼──────────────┐
│  measured state (soc0_t, Tin0_t)  ◄── nominal-plant propagation │              │
│         │         (device recursion eq. 3.6/3.2 on REALIZED     │              │
│         │          first-interval controls, D-05)                │              │
│         ▼                                                        │              │
│  set_parameter_value!(window.soc0_param, soc0_t)                 │              │
│  set_parameter_value!(window.terminal_param, soc*[min(t+H-1,T)]) │              │
│  set_parameter_value!(window.Ppv_param/.Tout_param, forecast slice + seeded error, D-08)
│  set_objective_coefficient(window.model, p_import[τ], -λ₀[t+τ-1])  ∀τ=1:H       │
│         │                                                        │              │
│         ▼                                                        │              │
│  solve_with_retry!(window.model; dual=true)  ── SAME model object every step ───┤ build-once
│         │                                                        │              │ regression:
│         ▼                                                        │              │ num_variables/
│  cheap inline cone-residual check (report style, mirrors         │              │ num_constraints
│  assert_restriction_exact!'s inline gap loop) ──fail──► escalate │              │ invariant
│         │pass                    to RestrictedBranchFlow one-off │              │
│         │                        solve + assert_restriction_exact!(report=true) │
│         │                        → ac_dual_fallback_price if that also fails    │
│         ▼                                                        │              │
│  publish dadp[t] = dual.(balance_p[agg_bus,:])[1]  (FIRST step of window only)  │
│  record!(trace, t, dadp[t], certificate_status, ...)             │              │
└────────────────────────────────────────────────────────────────────────────────┘
        │
        ▼
MpcTrace (jumps, cumulative deviation, certificate log) + realized welfare
        │
        ▼
regret = realized_welfare − day_ahead_welfare  (MPC-04, information-set-fair)
```

### Recommended Project Structure
```
src/models/
├── mpc_window.jl        # NEW: build_mpc_window / solve_mpc_window! (mirrors PlanningOracle)
src/experiments/
├── mpc_loop.jl           # NEW: run_mpc(...) orchestrator — the receding-horizon driver
src/devices/
├── PVBattery.jl          # MODIFIED (additive): soc[1]==d.soc0 → Parameter-backed, +vars.soc0
├── Thermostatic.jl       # MODIFIED (additive): Tin[1]==d.Tin0 → Parameter-backed, +vars.Tin0
├── FourQuadBESS.jl       # MODIFIED (additive): soc[1]==d.soc0 → Parameter-backed, +vars.soc0
src/models/
├── mpc_trace.jl          # NEW: MpcTrace struct + record!, mirrors src/admm/residuals.jl
docs/literate/
├── mpc_rolling_horizon.jl  # NEW literate rung page (MPC-04)
```

### Pattern 1: Widening a device's IC constraint into a `Parameter` (additive, byte-identical default)

**What:** Replace the bare `@constraint(m, soc[1] == d.soc0)` with a genuine JuMP `Parameter`
defaulting to the SAME value, and return the Parameter handle so an outer builder can
`set_parameter_value!` it without a rebuild.

**When to use:** Any device whose state IC must move window-to-window without rebuilding —
today: `PVBattery.soc0`, `Thermostatic.Tin0`, `FourQuadBESS.soc0`.

**Why it is safe (no Pitfall-1 bilinear issue):** the IC term never multiplies a decision
variable — it is a pure additive constant on the RHS of an equality. This is the SAME shape as
`PlanningOracle`'s `z[t] in Parameter(0.0)` / `p_import[t] == z[t]` pin
(`src/planning/subproblem.jl:194-195`), not the SAME shape as ADMM's price coefficient (which DOES
multiply a variable and is therefore explicitly forbidden as a `Parameter`,
`AgrOpt.jl:23-24`/`DsoOpt.jl:131`).

**Example (verified pattern, adapted from `src/planning/subproblem.jl:194-195` + `PVBattery.jl:253`):**
```julia
# Source: src/planning/subproblem.jl:194-195 (the SAME idiom, applied to soc0 instead of z)
@variable(m, soc0 in Parameter(d.soc0))       # defaults to the OLD literal — byte-identical
@constraint(m, soc[1] == soc0)                 # was: @constraint(m, soc[1] == d.soc0)
# ... later, per MPC step, no rebuild:
set_parameter_value(vars.soc0, measured_soc)
```
Return `(; vars = (; p_ch, p_dch, soc, pv_used, soc0), p_inject, utility)` — additive key, mirrors
MESH-04's `q_inject` widening precedent (`AbstractDevice.jl:67-80`: "no existing device file needs
to change" for consumers that don't look for the new key; `Aggregator.contribute!` never inspects
unknown `vars` keys, so this is safe for every non-MPC caller of these three devices).

### Pattern 2: Sliding price coefficients via `set_objective_coefficient`, NEVER a `Parameter`

**What:** The frontier price `λ₀[t]` (and any other coefficient that multiplies a decision
variable in the objective) must be updated via `set_objective_coefficient`, mirroring
`AgrOpt`/`DsoOpt`'s ADMM price update — not via a `Parameter`.

**Example (verified pattern, from `AgrOpt.jl:22`, `DsoOpt.jl:128-131`):**
```julia
# Source: src/admm/AgrOpt.jl:22 / DsoOpt.jl:128-131 — the ALREADY-DOCUMENTED Pitfall-1 avoidance
set_objective_coefficient(model, p_import[τ], -λ₀_window[τ])   # per window-local τ = 1:H
```

### Pattern 3: Build-once regression idiom (MPC-01's hard acceptance criterion)

**What:** Assert the SAME model object is re-solved, never rebuilt, via `num_variables`/
`num_constraints` invariance across `set_parameter_value!` + re-solve cycles — NOT `objectid`
(CONTEXT.md's own "Specific Ideas" floats `objectid`, but the codebase's actual precedent is
stronger and already used at scale).

**Example (verified, from `test/test_planning_oracle.jl:72-87`):**
```julia
# Source: test/test_planning_oracle.jl:72-87
nv0 = num_variables(window.model)
nc0 = num_constraints(window.model; count_variable_in_set_constraints = true)
# ... N solve_with_retry! + set_parameter_value! cycles at different measured states ...
@test num_variables(window.model) == nv0
@test num_constraints(window.model; count_variable_in_set_constraints = true) == nc0
```
`count_variable_in_set_constraints = true` is REQUIRED — `Parameter`s are implemented as
variable-in-`MOI.Parameter`-set constraints, so omitting this flag silently hides exactly the
constraint count a rebuild would change (verified against the SAME test file's usage — this is
not a training-data guess, it is the literal kwarg already in the codebase's own regression).

### Pattern 4: Cheap, non-throwing per-step certificate check (D-04)

**What:** Reimplement the SAME per-branch cone-residual computation `assert_socp_exact!` uses,
inline, in report style — exactly as `assert_restriction_exact!` already does instead of
delegating to `assert_socp_exact!` (whose only mode is throw).

**Example (verified pattern, from `src/models/restriction_exactness.jl:245-270`):**
```julia
# Source: src/models/restriction_exactness.jl:251-270 (inline reimplementation, NOT a delegated call)
pv = ctx.meta[:pf_vars]; feeder = ctx.meta[:feeder]; T = ctx.meta[:T]
cone_maxratio = 0.0
for (b, br) in enumerate(feeder.branches), t in 1:T
    lhs = value(pv.l[b, t]) * value(pv.v[br.from, t])
    rhs = value(pv.P[b, t])^2 + value(pv.Q[b, t])^2
    gap = abs(lhs - rhs)
    tol = cone_atol + cone_rtol * max(abs(lhs), abs(rhs))
    cone_maxratio = max(cone_maxratio, gap / tol)
end
step_certified = cone_maxratio <= 1     # NEVER throws — the caller decides escalation (D-04)
```
On `step_certified == false`, escalate per Phase-20's OWN ladder (never invent a new one):
1. one-off `RestrictedBranchFlow()` solve on the SAME window data (a fresh, non-build-once model
   — acceptable, this path is the RARE/exceptional branch, not the hot loop) +
   `assert_restriction_exact!(ctx_restricted, ctx_ac; report = true)` (`restriction_exactness.jl:228-322`);
2. if that ALSO fails, `ac_dual_fallback_price(feeder, aggregators; T=H, λ₀=window_slice,
   allow_export=true)` (`ac_dual_fallback.jl:79-124`), publishing `price_status = :local_ac_dual`
   with its `agreement_report` caveat (D-09's "record the fallback path in the trace").

### Anti-Patterns to Avoid
- **Calling `solve_welfare` inside the per-step loop:** rebuilds a fresh `Model` every step
  (`welfare_solve.jl:117`), violating MPC-01's own "never rebuilt" criterion. Reserve the actual
  `solve_welfare` call for the ONE-TIME day-ahead perfect-foresight benchmark (MPC-04).
- **Making `λ₀` a `Parameter`:** reproduces the exact "Parameter × variable indefinite bilinear"
  failure the ADMM code twice warns against (`AgrOpt.jl:23-24`, `DsoOpt.jl:27,131`). Use
  `set_objective_coefficient`.
- **Wrapping `solve_welfare`'s exactness gate in a bare `try`/`catch Exception`:** masks genuine
  bugs (a `KeyError`, an `ArgumentError` from a shape mismatch) as if they were cone-inexactness.
  Use the inline report-style reimplementation (Pattern 4) so only the SPECIFIC cone-residual
  condition is caught.
- **Putting a variable's availability bound (`upper_bound = d.Ppv[t]`) behind a `Parameter`
  directly:** JuMP variable bounds must be `Real` literals at `@variable` construction time — a
  `Parameter` cannot be passed as `upper_bound=`. Convert to an explicit constraint
  `pv_used[t] <= Ppv_param[t]` instead (Parameter appears alone on the RHS, still purely additive,
  no bilinear issue) — see Pitfall "PV/ambient profile slices need a constraint rewrite, not just
  a bound swap" below.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Escalating Clarabel numerical-conditioning retries | A custom retry loop around `optimize!` | `solve_with_retry!` (`src/planning/retry.jl:92`) | Already handles the documented intermittent Clarabel `NUMERICAL_ERROR` (STATE.md carried blocker), which the MPC loop's REPEATED re-solves will amplify exactly as `PlanningOracle`'s docstring already anticipates |
| Overvoltage-regime AC feasibility / fallback pricing | A new ad-hoc "is this still exact enough" check | `assert_socp_exact!`'s inline residual shape (Pattern 4) + `RestrictedBranchFlow`/`assert_restriction_exact!`/`ac_dual_fallback_price` (Phase 20, D-04's explicit mandate) | Phase 20 already built and measured the exact escalation ladder this phase's D-04 references; a NEW ad-hoc tolerance would be "certificate laundering" (the standing v3.0 cross-cutting rule in STATE.md) |
| DADP dual extraction | Re-deriving the balance-constraint dual by hand | `dual.(ctx.constraints[:balance_p][bus, :])`, the SAME accessor `solve_welfare`/`PlanningOracle`/`operational_oracle` already use | One trusted dual-read seam, gated everywhere by `assert_solved!(...; dual=true)` first |
| Seeded, non-global-RNG-touching randomness (forecast error, D-08) | `Random.seed!` / a raw `MersenneTwister` | `sub_seed(master, tag)` + a fresh `StableRNGs.LehmerRNG` per draw (`materialize.jl:17-25`, already used for `:profiles`/`:population` streams) | Preserves INFRA-04 reproducibility and avoids accidentally coupling the forecast-error stream to the ground-truth profile stream |

**Key insight:** every piece this phase needs — build-once re-solve, escalating retry, overvoltage
certificate/fallback, seeded independent RNG streams, trace-struct convention — already has ONE
canonical implementation in this codebase. The phase's actual work is wiring, not new algorithms.

## Common Pitfalls

### Pitfall 1: Device IC constraints are not Parameter-ready today (the central blocker)
**What goes wrong:** Assuming `horizon_state` (SEAM-01, `oracle.jl:76-80`) is already load-bearing
because its docstring describes the `Parameter` idiom. It is NOT wired into anything — Phase 4
left it an inert, ignored kwarg (`oracle.jl:119-121`), and the actual device builders
(`PVBattery.jl:253`, `Thermostatic.jl:237`, `FourQuadBESS.jl:300`) bake the IC as a literal,
anonymous, discarded `ConstraintRef` with no retrievable handle.
**Why it happens:** These three files were built for a single-shot day-ahead solve, never a
re-solved loop; nothing in Phase 3/19 needed to move `soc0`/`Tin0` after construction.
**How to avoid:** Modify `PVBattery.jl`/`Thermostatic.jl`/`FourQuadBESS.jl` per Pattern 1 above —
additive, byte-identical default, verified safe by construction (no Pitfall-1 bilinear risk).
**Warning signs:** Any plan that treats `horizon_state` as "already load-bearing, just needs
threading through" without touching the three device files will discover this only when the
build-once regression (Pattern 3) fails or the loop silently re-solves the SAME `soc0` every step.

### Pitfall 2: `λ₀` as a `Parameter` reproduces the ADMM "Pitfall 1" bilinear failure
**What goes wrong:** Making the frontier price a `Parameter` so it can slide with the window looks
symmetric with `soc0`, but it multiplies `p_import[t]` in the objective — an indefinite bilinear
the conic backend (Clarabel) rejects, per the SAME failure mode `AgrOpt.jl`/`DsoOpt.jl` already
hit and fixed by switching to `set_objective_coefficient`.
**Why it happens:** `soc0` and `λ₀` FEEL like the same kind of "per-step input," but one is
additive (safe as `Parameter`) and the other multiplies a decision variable (unsafe).
**How to avoid:** Use `set_objective_coefficient(model, p_import[τ], -λ₀_window[τ])` (Pattern 2).
**Warning signs:** A `MOI.Bridges` error mentioning a nonconvex/indefinite quadratic term, or a
solve that reports `DUAL_INFEASIBLE`/`NUMERICAL_ERROR` only after the price-`Parameter` change.

### Pitfall 3: `solve_welfare`'s exactness gate always throws — it cannot be D-04's per-step check as-is
**What goes wrong:** Calling `solve_welfare` (or `assert_socp_exact!` directly) inside the per-step
loop and expecting to "catch" an inexactness gracefully — `assert_socp_exact!` has NO `report`
kwarg (`exactness.jl:78`) and always `error(...)`s on failure.
**Why it happens:** It is the project's headline correctness gate (PF-04), deliberately
unconditional everywhere else it is used.
**How to avoid:** Use Pattern 4's inline reimplementation for the per-step check; reserve the
throwing `assert_socp_exact!` for contexts where a hard failure IS the desired behavior (e.g. the
one-time day-ahead benchmark solve, where D-04's tolerance does not apply).
**Warning signs:** An uncaught `ErrorException` crashing the MPC loop instead of a recorded
`:cert_failed` trace entry.

### Pitfall 4: PV/ambient profile slices need a constraint rewrite, not just a bound swap
**What goes wrong:** `PVBattery`'s `pv_used` variable declares `upper_bound = d.Ppv[t]` directly
at `@variable` construction (`PVBattery.jl:251`). A JuMP variable bound must be a `Real` literal —
you cannot pass a `Parameter`-typed `VariableRef` as `upper_bound=`.
**Why it happens:** Bounds are baked at variable-construction time in MOI; only CONSTRAINTS (not
bounds) can reference another variable/Parameter on the RHS.
**How to avoid:** Drop the `upper_bound` kwarg, declare `pv_used[t] >= 0` only, and add an
explicit `@constraint(m, pv_used[t] <= Ppv_param[t])` where `Ppv_param` is a `Parameter`. Same
treatment needed anywhere a per-step-varying quantity currently lives in a variable bound rather
than a constraint RHS. `Thermostatic`'s `Tout[t]` is SAFER here — it already enters as an additive
term inside an equality constraint (`Tin[t+1] == Tin[t] + α*(Tout[t]-Tin[t]) - β*p[t]`,
`Thermostatic.jl:241`), not a bound, so it converts to a `Parameter` with no structural rewrite.
**Warning signs:** A `MethodError`/`TypeError` on `@variable(..., upper_bound = some_parameter)`.

### Pitfall 5: Window-boundary shrinkage vs a fixed build-once horizon length
**What goes wrong:** A textbook receding horizon shrinks its final windows as `t → T` (window
`[t, T]` has length `< H` near the end of the day). A build-once model has a FIXED number of time
steps baked into its variable arrays (`@variable(m, [t=1:H], ...)`) — you cannot shrink `H` without
rebuilding.
**Why it happens:** MPC-01's "never rebuilt" criterion and the textbook shrinking-horizon
convention are in tension unless resolved explicitly.
**How to avoid — (RESOLVED, see Open Questions #2):** run the closed loop for steps
`t = 1, ..., T-H+1` only (a FIXED window length `H` throughout, never shrinking); this keeps every
window the SAME size (true build-once) and every window's terminal index `t+H-1` always in
`1:T` by construction, matching D-06's "terminal-SOC target at each window's end" without any
special-casing. This yields `T-H+1` published price/action steps, not `T` — document this
explicitly as the loop's step count in MPC-03's trace.
**Warning signs:** An off-by-one `BoundsError` indexing the day-ahead SOC trajectory or the
ground-truth profile past hour `T`.

### Pitfall 6: `Scenario.jl`'s DrWatson `savename` schema is NOT hash-stable under ANY new field
**What goes wrong:** D-12 asks for "additive `@kwdef` fields with defaults that preserve existing
golden hashes." DrWatson's `savename`/`struct2dict(s)` (`store.jl:53`) serializes **every** field
of `Scenario` regardless of whether it equals its default — `default_allowed` only filters by
TYPE (`Real, String, Symbol, ...`), never by "is this the default value" (confirmed: `Scenario.jl:8-9`
"ZERO `DrWatson.default_allowed` overloading" is a deliberate design invariant, not an oversight).
Phase 16 hit this directly and, rather than accept it, kept `reactive_consensus` OUT of `Scenario`
entirely — "adding a `reactive_consensus` field there — even defaulted — would perturb that hash
for every existing pinned experiment" (`test/test_admm_reactive.jl:57-63`).
**Why it happens:** `savename` is a pure structural serialization, not a diff-aware one.
**How to avoid — (RESOLVED, see Open Questions #3):** add the MPC fields to `Scenario` per D-12
(the locked decision), but document explicitly that this changes the `savename` STRING for EVERY
`Scenario` (old and new alike) — confirmed harmless for this phase because (a) no test in the repo
pins an exact `savename` string literal (verified: `grep -rn "@test.*savename"` returns zero
matches), and (b) no committed `.jld2` artifact is keyed by an old `Scenario`'s `savename` (the
only committed `.jld2, data/pv_boom/results.jld2`, is unrelated pv-boom showcase data, not a
`Scenario`-savename artifact). NUMERIC golden test results (welfare/dadp values from existing
`Scenario(...)` calls) are unaffected because new fields default to a no-op value for the
`:centralized`/`:admm` strategies. Treat "preserve golden hashes" as "preserve golden NUMERIC
results," not "preserve the exact savename string" — the latter is structurally impossible given
this project's own zero-`default_allowed`-override design invariant.
**Warning signs:** A researcher's local, gitignored `data/sims/` cache silently orphaning old
`.jld2` files after this phase lands — an accepted, documented cost, not a bug.

### Pitfall 7: `SCENARIO_VALID_STRATEGIES` has no `:mpc` selector
**What goes wrong:** `Scenario.strategy` is constructor-validated against `(:centralized, :admm)`
only (`Scenario.jl:32,135-141`). If the plan wires MPC through `run_scenario`'s dispatch, a THIRD
strategy value is a real schema change (not just new fields) — a bigger blast radius than D-12
anticipates.
**How to avoid — (RESOLVED, see Open Questions #4):** do NOT dispatch MPC through
`run_scenario`'s `strategy` enum this phase. Add the MPC kwargs (H, step, terminal-SOC toggle,
forecast-error magnitude, seed) as additive `Scenario` fields (satisfying D-12's coordination
note with Phase 22) but drive the actual MPC loop from the NEW orchestrator's OWN entry point
(e.g. `run_mpc(scenario::Scenario)` in the new module), reading those fields directly — never
adding `:mpc` to `SCENARIO_VALID_STRATEGIES`/`run_scenario`'s `if`/`elseif`. This keeps `run.jl`'s
existing two-branch dispatch completely untouched (mirrors D-01's "`welfare_solve.jl` stays
untouched" discipline one level up) and avoids a THIRD blast-radius surface interacting with
Phase 22's own scenario-tree fields.
**Warning signs:** A `run_scenario` diff that adds an `elseif s.strategy === :mpc` branch —
a signal the design drifted from D-01's "new sibling orchestrator" framing.

### Pitfall 8: Deferrable's within-window energy budget does not carry state across windows
**What goes wrong:** If the MPC CI fixture's aggregator includes a `Deferrable` device (not just
`PVBattery`/`Thermostatic`), its `total_energy <= d.E` constraint (`Deferrable.jl:202-204`) is
defined over the CURRENT window's `T` only — under a rolling window this budget silently RESETS
every step rather than tracking a persistent daily energy requirement, which is physically wrong
for a genuine deferrable load (e.g. an EV charge target) but is NOT flagged anywhere as a bug.
**Why it happens:** `Deferrable` has no inter-temporal recursion equation (unlike `soc[t+1]` or
`Tin[t+1]`) — CONTEXT.md's phase scope (D-05/D-06/D-07) only names battery SOC and thermostatic
temperature as state to propagate, and Deferrable genuinely has none in the current model.
**How to avoid:** Keep the MPC CI fixture to `Thermostatic` + `PVBattery` (and optionally
`FourQuadBESS`) only, matching the phase description's explicit stateful-device scope; if a future
fixture adds `Deferrable`, document the reset-per-window behavior as an explicit, honest
limitation rather than silently letting it look like genuine energy tracking.
**Warning signs:** A regret benchmark that looks suspiciously good because a `Deferrable` device
is "cheating" by getting a fresh energy allowance every window.

## Code Examples

### Terminal-SOC wiring (MPC-02, D-06)
```julia
# Day-ahead benchmark (ONE solve_welfare call, T = 24, UNMODIFIED file):
ctx_da, welfare_da, _ = solve_welfare(feeder, pf, aggs; T = T, λ₀ = λ₀_full, allow_export = true)
# Extract the day-ahead SOC trajectory per battery bus (value.() of the stashed device vars,
# ctx.meta[:agg_device_vars] — same stash assert_battery_complementarity! already reads,
# src/models/welfare_solve.jl:310-311):
soc_da = Dict(bus => [value(v.soc[t]) for t in 1:T]
              for (bus, varlist) in ctx_da.meta[:agg_device_vars] for v in varlist if haskey(v, :soc))

# Inside the window builder, per battery:
@variable(m, soc0 in Parameter(d.soc0))
@variable(m, soc_terminal_target in Parameter(soc_da[bus][H]))   # window 1's end
@constraint(m, soc[1] == soc0)
terminal_pin = @constraint(m, soc[H] == soc_terminal_target)      # MPC-02's hard equality

# Per step t (window ends at absolute hour t+H-1, always ≤ T by Pitfall 5's fixed-H convention):
set_parameter_value(soc0_handle, measured_soc)
set_parameter_value(terminal_target_handle, soc_da[bus][t + H - 1])
```
`terminal_pin` is toggleable per MPC-02's own acceptance criterion by making its RHS a
`Parameter` bounded ONLY by the device's own `Emin`/`Emax` when the terminal condition is
"disabled" for the regression's negative-control run — e.g. relax by setting the target Parameter
to the device's own unconstrained free-choice bound is not directly expressible as a toggle on an
equality; the cleaner toggle (Claude's discretion, D-06 leaves the mechanism open) is to build TWO
window variants (terminal-pin present / absent) sharing every other line, or to guard the
`@constraint` behind a `terminal_soc::Bool` kwarg at build time (one rebuild per regression run,
not per MPC step — acceptable, since the regression is a one-shot A/B comparison, not the hot
per-step loop).

### Price extraction per window (MPC-03)
```julia
# Source pattern: welfare_solve.jl:266-268 / oracle.jl:185-187 (dual.() of :balance_p)
dadp_window = dual.(ctx.constraints[:balance_p][agg_bus, :])   # length H
published_price_t = dadp_window[1]      # ONLY the first step's price is published (D-09's
                                          # "per-step published DADPs" — elapsed hours are final)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `horizon_state` accepted-but-ignored kwarg (`oracle.jl:76-80,119-121`) | `horizon_state` made load-bearing via a NEW window builder + widened device `Parameter`s | This phase (MPC-01) | The SEAM-01 stub finally does something; `operational_oracle`/`welfare_solve.jl` remain untouched per D-01 |
| Single-shot day-ahead pricing only | Rolling re-computed DADP as an RTP signal | This phase (MPC-03) | First real-time-pricing capability in the framework; day-ahead DADP becomes one input to a regret comparison rather than the only price output |

No external literature/library API changed underneath this phase — this is purely an internal
architecture extension. The two standard MPC textbook references worth citing on the literate
page (light-touch per the task brief, no deep theory pass): Rawlings, Mayne & Diehl, *Model
Predictive Control: Theory, Computation, and Design* (terminal equality constraint vs terminal
cost function — this phase implements the terminal-EQUALITY variant, D-06) — `[ASSUMED]`,
training-knowledge citation, not verified against a live source this session; flag for the
literate page author to confirm the edition/chapter at write time.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Rawlings/Mayne/Diehl (or an equivalent standard MPC text) is the right citation for terminal-equality vs terminal-cost framing | State of the Art | Low — cosmetic, a literate-page citation only; does not affect any code or test |
| A2 | "Nominal plant" (D-05) realized-state propagation should re-evaluate the SAME device recursion equation (3.6/3.2) outside the optimizer, not re-solve a mini-optimization | Architecture Patterns / Pitfall diagram | Medium — if wrong, the "measured state" definition changes and MPC-02's regression semantics shift; D-05's own wording ("apply each step's first-interval optimal controls to the ground-truth device dynamics") strongly supports this reading, so risk is LOW in practice despite the ASSUMED tag |

## Open Questions

1. **Does D-02's "each window solves the centralized `solve_welfare` problem" mean literally
   calling the `solve_welfare` function per step, or mirroring its formulation shape in a new
   build-once builder?**
   - What we know: D-01 explicitly frames the new module on "the v2.0 `PlanningOracle`
     orchestrator precedent" and locks "`welfare_solve.jl` stays untouched"; `PlanningOracle`
     itself mirrors `solve_welfare`'s SHAPE in a NEW file rather than calling the function, for
     exactly the build-once reason MPC-01 also needs.
   - What's unclear: D-02's literal wording ("solves the centralized `solve_welfare` problem")
     could be read as requiring the actual function call.
   - **(RESOLVED)** — Read as describing the MATH problem (centralized welfare formulation, not
     ADMM decomposition), not the literal function call, for consistency with D-01/D-03's
     explicit build-once/never-rebuilt requirement and CLAUDE.md's hard build-once rule. Literally
     calling `solve_welfare` per step would rebuild a fresh `Model` every window
     (`welfare_solve.jl:117`), directly violating MPC-01's own acceptance criterion. Recommend
     the planner confirm this reading explicitly in the plan's `must_haves`, citing this
     resolution, rather than re-opening it with the user.

2. **Should the receding horizon shrink near the end of the day (`T-H+1 < t ≤ T`, windows of
   length `< H`) or should the loop simply stop issuing new windows once a full-length window no
   longer fits?**
   - What we know: a fixed-size build-once model cannot shrink its own variable count without
     rebuilding; CONTEXT.md's D-03 locks "built once and re-solved per step ... never a rebuild."
   - What's unclear: whether MPC-03's "published per step" implies exactly `T` published prices.
   - **(RESOLVED)** — Fixed window length `H` throughout; loop runs for `t = 1..T-H+1`, yielding
     `T-H+1` published steps (Pitfall 5). This is the ONLY reading compatible with a literal
     "never a rebuild" build-once model. Document the resulting step count explicitly in
     `MpcTrace`/the literate page so it is never mistaken for a bug.

3. **Does adding MPC fields to `Scenario.jl` (D-12) actually preserve "golden hashes," given the
   Phase-16 precedent found that DrWatson's `savename` is not default-value-aware?**
   - What we know: `struct2dict(s)` serializes ALL fields regardless of default value
     (`Scenario.jl:8-9`'s deliberate zero-`default_allowed`-override design); Phase 16 avoided
     this entirely by keeping `reactive_consensus` OUT of `Scenario`.
   - What's unclear: whether D-12's "preserve existing golden hashes" is about the `savename`
     string specifically or about numeric reproducibility.
   - **(RESOLVED)** — No test or committed artifact pins an exact `savename` string (verified by
     grep, zero matches); numeric golden results are preserved because new fields default to a
     no-op for `:centralized`/`:admm`. Proceed with D-12's additive fields as locked, but the
     plan's documentation should explicitly note the `savename` STRING changes for every
     `Scenario` (a cosmetic, accepted cost) rather than silently implying it is fully hash-stable.

4. **Should the new MPC entry point be wired through `run_scenario`'s `strategy` dispatch
   (`:centralized`/`:admm`/`:mpc`) or live as an independent orchestrator function?**
   - What we know: `SCENARIO_VALID_STRATEGIES` is a constructor-validated closed enum
     (`Scenario.jl:32,135-141`); D-01 frames the new module as a "sibling orchestrator," not a
     `run_scenario` branch.
   - What's unclear: CONTEXT.md's `<specifics>`/`<code_context>` do not explicitly rule out
     wiring `:mpc` into `run_scenario`.
   - **(RESOLVED)** — Independent orchestrator entry point (e.g. `run_mpc(scenario)`), reading
     the additive `Scenario` fields directly, never adding `:mpc` to
     `SCENARIO_VALID_STRATEGIES`/`run_scenario`'s dispatch (Pitfall 7). This keeps `run.jl`
     untouched, mirrors D-01's "sibling orchestrator" framing literally, and avoids a THIRD
     schema-blast-radius surface on top of Phase 22's coordinated scenario-tree diff.

## Environment Availability

Skipped — this phase has no external dependencies beyond the already-verified Julia/JuMP/Clarabel
toolchain already present and exercised by every prior phase in this repository (no new tools,
services, or runtimes are introduced).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `Test` (stdlib) + `TestItemRunner`/`TestItems` via `@testitem`, discovered by `test/runtests.jl`'s `@run_package_tests` |
| Config file | none dedicated — `test/runtests.jl` is the sole entrypoint |
| Quick run command | `julia --project=. -e 'include("test/test_mpc_loop.jl")'` style direct-include ONLY (per this repo's MANDATORY testing constraint: **never** `julia --project=test -e '...@run_package_tests...'`, and **never** TestItemRunner invoked under `--project=.` for a quick loop — write plan `<verify>` blocks as plain `Test.jl` scripts, `@testitem` blocks are for the FULL suite only) |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (~13-18 min, run in background; green reference after Phase 20: 2563 passed / 0 failed / 3 pre-existing broken) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MPC-01 | Build-once/re-solve invariant (`num_variables`/`num_constraints` unchanged across N re-solves at different measured states) | unit | direct `Test.jl` script mirroring `test/test_planning_oracle.jl:72-87` | ❌ Wave 0 — new `test/test_mpc_window.jl` |
| MPC-01 | `set_parameter_value!` on soc0/Tin0/terminal-target actually moves the solved trajectory (not a no-op) | unit | same file, a second `@testset` | ❌ Wave 0 |
| MPC-02 | Dump/hoard artifact present when terminal condition disabled, absent when enabled (regression pair) | unit/regression | same file or `test/test_mpc_terminal.jl` | ❌ Wave 0 |
| MPC-03 | `MpcTrace` records per-step DADP, jumps, cumulative deviation, certificate status; sequential-`k` guard mirrors `AdmmResiduals` | unit | `test/test_mpc_trace.jl` mirroring `test/test_admm_residuals.jl`-style tests (check `record!`'s `_assert_sequential` idiom) | ❌ Wave 0 |
| MPC-04 | Regret = realized − day-ahead welfare on realized truth, information-set-fair; live literate page executes end-to-end | integration + literate | small radial CI fixture (2-3 bus, short `T`, small `H`) run in seconds; the full 24h demonstration is QUARANTINED evidence / the literate page, never the CI fixture | ❌ Wave 0 |
| MPC-04 | Per-step certificate/fallback dispatch never throws mid-loop; a forced-inexact step is caught and recorded | unit | `test/test_mpc_loop.jl`, forcing an overvoltage fixture window (reuse Phase-4/20's `high_pv_feeder`-style fixture at a SHORT `T`) | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the direct `Test.jl` script for the file(s) touched by that task (quick,
  seconds-scale, per the mandatory small-fixture constraint).
- **Per wave merge:** full suite green (`Pkg.test()`, background, ~13-18 min).
- **Phase gate:** full suite green before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/test_mpc_window.jl` — covers MPC-01 (build-once invariant, Parameter re-solve
  correctness for soc0/Tin0/terminal-target/profile-slice, `λ₀` via `set_objective_coefficient`)
- [ ] `test/test_mpc_terminal.jl` (or folded into the above) — covers MPC-02 (dump/hoard
  present/absent regression pair)
- [ ] `test/test_mpc_trace.jl` — covers MPC-03 (`MpcTrace` struct + `record!` + convergence-style
  query, mirroring `src/admm/residuals.jl`'s own test file's sequential-`k` guard pattern)
- [ ] `test/test_mpc_loop.jl` — covers MPC-04 (end-to-end small-fixture closed loop, regret
  computation, per-step certificate/fallback dispatch under a forced-inexact window)
- [ ] Small MPC CI fixture — a 2-3 bus radial feeder with `Thermostatic` + `PVBattery` at a SHORT
  `T` (e.g. `T=6..8`) and small `H` (e.g. `H=2..3`), likely a NEW `fixtures_phase21.jl` mirroring
  `fixtures_phase19.jl`/`fixtures_phase4.jl`'s convention — no framework install needed (`Test`/
  `TestItemRunner` already present).

## Security Domain

No `security_enforcement` key is present in `.planning/config.json` (absent = enabled per this
agent's mandate), but this phase has no attack surface in the ASVS sense: it is a closed research
computation over researcher-supplied, in-process data — no network input, no authentication, no
user-supplied untrusted strings reaching a shell/SQL/deserialization boundary. The only
"correctness-as-safety" concern is the SAME one every prior phase in this milestone already
treats as a first-class certificate: **never publish a price whose provenance certificate did not
pass** (D-04's per-step gate). This is already covered under Common Pitfalls #3 and Architecture
Pattern 4, not a distinct ASVS category. No new ASVS-category table is warranted; skipping it here
is a deliberate, documented "N/A for this domain" rather than an omission.

## Sources

### Primary (HIGH confidence — direct file reads this session)
- `.planning/phases/21-mpc-rolling-horizon-real-time-pricing/21-CONTEXT.md` — locked decisions
- `.planning/REQUIREMENTS.md` — MPC-01..04 exact wording, v3.0 "zero new packages" preamble
- `.planning/STATE.md` — cross-cutting certificate-laundering rule, Clarabel NUMERICAL_ERROR
  carried blocker
- `src/models/oracle.jl:1-191` — SEAM-01 `horizon_state` stub, confirmed inert
- `src/models/welfare_solve.jl:1-332` — `solve_welfare`'s per-call model rebuild, throwing
  exactness gate, `λ₀`-as-objective-coefficient shape
- `src/planning/subproblem.jl:1-316` — `PlanningOracle`/`build_planning_oracle`/
  `solve_planning_oracle!`, the ONLY existing build-once/`Parameter`-re-solve precedent
- `src/admm/AgrOpt.jl:1-130`, `src/admm/DsoOpt.jl:1-140` — the documented "never model price as a
  Parameter" pitfall (`set_objective_coefficient` idiom)
- `src/devices/PVBattery.jl`, `src/devices/Thermostatic.jl`, `src/devices/FourQuadBESS.jl`,
  `src/devices/Aggregator.jl`, `src/devices/AbstractDevice.jl` — device IC constraints, `vars`
  NamedTuple contract, `q_inject` widening precedent
- `src/models/restriction_exactness.jl:1-325`, `src/models/ac_dual_fallback.jl:1-127`,
  `src/models/exactness.jl:1-100` — Phase-20 certificate/fallback exact signatures and the
  inline-reimplementation-vs-delegation idiom
- `src/core/ModelContext.jl:1-162` — `ctx.meta`/`ctx.constraints`/`ctx.residuals` mechanics
- `src/admm/residuals.jl:1-195` — `AdmmResiduals` trace-struct convention (`MpcTrace`'s model)
- `src/experiments/Scenario.jl:1-217`, `src/experiments/run.jl:1-150`,
  `test/test_admm_reactive.jl:1-75` — Scenario schema, `savename` hash tension, Phase-16 precedent
- `test/test_planning_oracle.jl:59-87,232-264` — build-once regression idiom
  (`num_variables`/`num_constraints` invariance)
- `test/runtests.jl` — test discovery mechanism confirmation
- `CLAUDE.md` — build-once-re-solve hard rule, testing-invocation hazard warning

### Secondary (MEDIUM confidence)
None — this research relied entirely on direct codebase reads; no WebSearch/Context7 lookups were
needed since the phase is a pure internal-architecture extension with zero new external
dependencies.

### Tertiary (LOW confidence)
- Rawlings/Mayne/Diehl MPC textbook citation (State of the Art) — `[ASSUMED]`, training knowledge,
  not verified against a live source this session; flag for literate-page-time confirmation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new packages, every mechanism (`Parameter`, `set_parameter_value`,
  `set_objective_coefficient`, `solve_with_retry!`) verified present and already exercised in the
  pinned `Manifest.toml`/codebase.
- Architecture: MEDIUM — the recommended design (new `mpc_window.jl` mirroring `PlanningOracle`,
  widened device files) is a NEW synthesis, not a copy of an existing phase; individual mechanics
  are HIGH-confidence, the overall shape is the planner's to confirm.
- Pitfalls: HIGH — every pitfall is grounded in an actual code excerpt or an actual prior-phase
  precedent (Phase 16's Scenario.jl decision, Phase 20's certificate ladder), not speculation.

**Research date:** 2026-08-09
**Valid until:** 30 days (stable internal codebase, no external API drift risk) — re-verify sooner
if Phase 22's Scenario.jl diff lands first (coordinated-pair risk per D-12/STATE.md).

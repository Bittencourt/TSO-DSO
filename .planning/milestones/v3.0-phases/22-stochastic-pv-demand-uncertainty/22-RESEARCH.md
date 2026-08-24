# Phase 22: Stochastic PV/Demand Uncertainty - Research

**Researched:** 2026-08-09
**Domain:** Two-stage extensive-form stochastic convex optimization (JuMP/Clarabel), scenario-indexed
model construction, probability-weighted convex duals
**Confidence:** HIGH (construction mechanics, dual de-scaling, device/pf composition — all
empirically verified in this session against the pinned project environment) / MEDIUM (exact
scenario-count capacity ceiling — measured on one fixture/population, not exhaustively swept)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** One monolithic scenario-indexed JuMP model solved by Clarabel (CLAUDE.md's
  "extensive form first" prescription; criterion 1's "within measured capacity").
  Lagrangian/PH decomposition explicitly deferred.
- **D-02:** The builder lives in a new sibling module (e.g. `src/models/stochastic_welfare.jl`,
  name at Claude's discretion). The SEAM-01 `objective_hook` stub cannot express per-scenario
  duplication of network + devices (it only transforms the objective) — document this honestly
  as the SEAM-01 resolution note. REQUIREMENTS explicitly allows the sibling-orchestrator route.
- **D-03:** First-stage vs recourse split: battery schedule (and deferrable commitments) are
  first-stage (shared across scenarios); network flows, imports, and thermostatic response are
  per-scenario recourse. Research may refine the exact split within this framing (battery
  first-stage and network recourse are fixed).
- **D-04:** Explicit probabilities kwarg, default uniform; the CI fixture must use non-uniform
  probabilities to prove the weighting plumbing.
- **D-05:** Per-scenario DADP = the dual of scenario s's own nodal balance, de-scaled by its
  probability p_s (in a probability-weighted objective the raw dual is p_s-scaled), restoring
  the standard price interpretation per scenario. Derivation documented in the docstring.
- **D-06:** PF-04 exactness gate per scenario block — each scenario's cone checked separately
  (`assert_socp_exact!`-family), never aggregated.
- **D-07:** The probability-weighted expected price is a derived summary field with an
  unmistakable name and docstring caveat — never presented as a constraint-backed price
  primitive.
- **D-08:** Degenerate reduction regression: a 1-scenario extensive form must reproduce the
  deterministic `solve_welfare` result (welfare + DADPs within solver tolerance). CI-gated.
- **D-09:** Held-out evaluation Parameter-pins the first-stage decisions (Phase-21 build-once
  convention) and solves recourse-only per held-out scenario; reports realized-vs-in-sample
  welfare gap.
- **D-10:** Held-out scenario budget at Claude's discretion within a small seeded budget
  (e.g. 5–10, seeds disjoint from in-sample); CI keeps a cheap subset, fuller sweep quarantined.
- **D-11:** Measurement-before-golden (v2.1 pattern, locked): repeated-run stability check
  before pinning any golden.
- **D-12:** Small radial CI fixture (Phase-19/20/21 precedent); the 3–5-scenario IEEE-13
  demonstration lives in the literate page / quarantined evidence, not CI.

### Claude's Discretion

- Module/struct/function/kwarg names (builder, result struct, probability kwarg, harness entry).
- Exact scenario counts within the locked bands (3–5 in-sample, 5–10 held-out).
- Whether deferrable commitments join the battery in first-stage (D-03 allows refinement).
- Result-struct shape, provided per-scenario DADPs are primary and the expectation clearly
  derived.

### Deferred Ideas (OUT OF SCOPE)

- Lagrangian/progressive-hedging scenario decomposition (DualDecomposition.jl evaluation) — later
  milestone per CLAUDE.md.
- Multi-stage (>2) scenario trees and horizon-decaying forecast composition with Phase 21 — later.
- Risk measures (CVaR etc.) on the objective — out of this rung.
- InfiniteOpt.jl continuous random-domain formulation — evaluation deferred per CLAUDE.md.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| STOCH-01 | Two-stage extensive-form welfare over 3–5 seeded Markov scenarios, shared first-stage + per-scenario recourse, solved by Clarabel within measured capacity | Architecture Patterns 1–3 (construction mechanics, `JuMP.unregister` workaround, nonanticipativity), Clarabel capacity measurement below, Common Pitfalls 1–3 |
| STOCH-02 | Per-scenario DADPs primary (PF-04-gated per scenario); expectation a derived summary, never a constraint-backed primitive | Architecture Pattern 4 (de-scaled dual, empirically verified), D-06/D-07 mechanics, Code Examples |
| STOCH-03 | Out-of-sample harness: held-out scenarios, realized-vs-in-sample welfare gap, measurement-before-golden | Architecture Pattern 5 (Parameter-pin harness mirroring `build_mpc_window`), Validation Architecture |
| STOCH-04 | Live-executed literate rung page: extensive form, price semantics, out-of-sample result | State of the Art, `docs/literate/mpc_rolling_horizon.jl` precedent cited in Architecture Patterns |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Model in JuMP directly (never Convex.jl) — this phase's builder is a JuMP model, consistent.
- Clarabel is the default conic solver; never hardcode a concrete solver in a model file —
  the sibling builder must route through `select_optimizer(problem_class(pf))` exactly like
  `solve_welfare`/`build_mpc_window`/`build_planning_oracle`, never naming Clarabel directly.
- Build-once, re-solve via `Parameter`s / `set_normalized_rhs` / `set_objective_coefficient` —
  never rebuild a JuMP model inside an outer loop. Directly load-bearing for the out-of-sample
  harness (D-09): it must be built once and re-solved per held-out scenario via
  `set_parameter_value`, mirroring `MpcWindow`/`PlanningOracle`.
- Hand-roll decomposition only when actually decomposing; the in-sample extensive form here is
  explicitly NOT decomposed (D-01) — it is one monolithic model, so this constraint mostly
  informs the deferred Lagrangian/PH axis, not this phase.
- No project skills found under `.claude/skills/` etc. — none apply beyond the GSD workflow
  enforcement note (already honored: this is a `/gsd:plan-phase` research step).

## Summary

The extensive-form builder is straightforward to assemble from existing, already-validated
building blocks (`contribute!` for `ConvexBranchFlow` and every device, `ModelContext`,
`assert_solved!`, `assert_socp_exact!`, `solve_with_retry!`) — **but one genuinely new pitfall
was discovered and empirically confirmed this session**: `ConvexBranchFlow.contribute!` (unlike
every Phase-21-widened device) still registers its variables/constraints under **named** JuMP
containers (`v`, `v̂`, `P`, `Q`, `l`, `cone`, `vdrop`, `cpydrop`, `smax`). Calling it more than
once against the same `Model` — which the extensive-form builder must do, once per scenario —
throws `"An object of name v is already attached to this model"` (verified live against this
project's own pinned environment). The fix requires **zero modification** to
`ConvexBranchFlow.jl`: calling `JuMP.unregister(model, name)` for each of the nine names between
scenario blocks is sufficient and was verified to produce byte-identical, independently-usable
per-scenario variable/constraint handles. This is the direct network-layer analogue of Phase 21's
device-Parameter-container collision, but the fix is *external* (orchestration-only), not a
device-file edit.

The shared first-stage (battery, optionally deferrable) is recommended as **explicit
nonanticipativity equality constraints across S independently-built device copies**, not a
single shared JuMP variable threaded through S scenario blocks. Rationale: every device
`contribute!` call (including the battery) bundles its OWN per-step data Parameter
(`Ppv_param`) into the SAME call that creates its control variables (`p_ch`, `p_dch`, `soc`,
`pv_used`) — there is no existing seam to build a battery's controls once and rebind its data
input per scenario. Building S independent battery copies (one per scenario, each seeing its
own scenario's `Ppv_param`) and then tying `p_ch_s[t] == p_ch_1[t]` / `p_dch_s[t] ==
p_dch_1[t]` / `soc_s[t] == soc_1[t]` for `s = 2..S` is a purely additive orchestration pattern
that reuses every device file unmodified — the standard extensive-form nonanticipativity idiom
(Birge & Louveaux, *Introduction to Stochastic Programming*, 2nd ed., Springer 2011) applied
literally.

Per-scenario DADP de-scaling (D-05) was verified numerically, not merely derived: a
non-uniform two-scenario extensive form (p₁=0.35, p₂=0.65, identical scenario data) built with
the exact `solve_welfare`-shaped residual-closure pattern reproduces the deterministic baseline
DADP to within ~3×10⁻⁵ pu (absolute) after dividing each scenario's raw `:balance_p` dual by its
own probability — no sign flip is needed (unlike the `PlanningOracle` `pin` constraint, whose
raw dual IS negated relative to naive expectation; that is a *different* constraint shape and
its sign convention must not be pattern-matched onto `:balance_p`, which behaves like
`solve_welfare`'s own DADP because it is structurally the identical closure).

The seeded Markov data layer (`generate_profiles`) already returns exactly the `(; demand, pv)`
pair a "scenario" needs; a scenario in this phase's vocabulary is one `generate_profiles(seed=
...)` draw (a demand vector + a PV vector over the horizon), used to build one scenario's
aggregator population via the existing `build_population`/`sub_seed` materialize.jl seam — no
new data-layer code is needed, only a loop over S disjoint seeds.

Clarabel capacity was measured (not assumed) on IEEE-13 with the project's own default
10-aggregator population at T=9: S=1 → 1,396 vars / 2,765 constraints; S=3 → 4,188 / 8,295;
S=5 → 6,980 / 13,825 — all `OPTIMAL`, warm solves 0.2–0.4s (the first solve's 14.5s is Julia JIT
compilation overhead, not solver cost — do not misread it as an S=1-is-slow artifact). This is
comfortably within capacity for 3–5 scenarios even at this "full default population" scale; the
locked-in small CI fixture (D-12, mirroring Phase 4's 3-bus `high_pv_feeder` precedent) will be
smaller still and should be re-measured once chosen (Wave-0 gap below).

The out-of-sample harness (D-09) is recommended as a *separate*, much simpler build-once model
than the in-sample extensive form: a single-scenario, `solve_welfare`-shaped model whose
first-stage device controls are tied via equality constraints to fresh `Parameter`s (mirroring
`build_mpc_window`'s own `terminal_param` idiom exactly — an anonymous Parameter plus an
equality constraint against a decision variable, already an established pattern in this
codebase, not a new one), pinned once to the in-sample optimum, then re-solved per held-out
scenario by sliding each held-out scenario's own `Ppv_param`/`Pdc_param`/`Tout_param` (the
Phase-21 widened per-step Parameters) via `set_parameter_value`.

**Primary recommendation:** build the extensive form as S independently-`contribute!`d,
`JuMP.unregister`-decoupled scenario blocks on one shared `Model`; couple first-stage battery
(and, at Claude's discretion, deferrable) controls via explicit equality constraints across
blocks; de-scale each scenario's `:balance_p`/`:balance_q` dual by its own probability for the
primary DADP; gate each scenario block through `assert_socp_exact!` independently (a plain loop,
no new certificate); and build the out-of-sample harness as a second, Parameter-pinned,
build-once single-scenario model reusing the `build_mpc_window` idiom rather than reusing the
in-sample extensive-form model itself.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Scenario data generation (PV/demand draws) | Data layer (`src/data/profiles.jl`) | Orchestration (`src/experiments/materialize.jl` for population build) | `generate_profiles` is pure/JuMP-free by design (DATA-04); each scenario is one seeded draw consumed as parameters, never a decision |
| Extensive-form model assembly (network + devices × S scenarios) | Model-builder layer (new `src/models/stochastic_welfare.jl`) | Device layer (`src/devices/*.jl`, `src/powerflow/ConvexBranchFlow.jl`) reused verbatim | New sibling builder orchestrates existing `contribute!` seams; it owns scenario indexing and nonanticipativity, devices/pf stay untouched |
| Nonanticipativity coupling (shared first-stage) | Model-builder layer (new module) | — | Equality constraints are assembled once, in the new builder, over device return-tuple handles — no device-file change |
| Per-scenario price recovery + de-scaling | Model-builder layer (new module's result-reading code) | Certification layer (`src/models/exactness.jl`, reused per scenario) | Dual recovery and de-scaling are pure post-solve reads on the already-solved model; the PF-04 gate must run BEFORE any dual read, exactly as `solve_welfare` already does |
| Out-of-sample harness (Parameter-pin + re-solve) | Orchestration layer (new sibling, e.g. `src/experiments/run_stochastic.jl`) | Model-builder layer (a second, smaller build-once model) | Mirrors `run_mpc`/`MpcWindow`'s existing split: orchestrator drives materialize + loop, a dedicated builder owns the build-once model |
| Scenario declarative spec (`stoch_*` fields) | Experiment schema (`src/experiments/Scenario.jl`) | — | Additive `@kwdef` fields, mirrors the `mpc_*` precedent exactly; consumed only by this phase's own entry point, never `run_scenario`'s `:centralized`/`:admm` dispatch |
| Literate rung page | Docs layer (`docs/literate/`) | — | Live-executed page mirrors `mpc_rolling_horizon.jl`'s structure (build a `Scenario`, call the phase's one entry point, show real numbers) |

## Standard Stack

No new runtime packages. Every construction primitive this phase needs already exists in the
pinned environment: `JuMP` 1.30.1 (`Parameter`, `unregister`, anonymous variable/constraint
construction), `Clarabel` 0.11.1 (native SOCP/QP with accurate duals — `[VERIFIED: local
Clarabel/JuMP run against this project's Manifest.toml, this session]`), `StableRNGs` 1.0.4
(via `generate_profiles`'s existing `sub_seed` discipline). No `[ASSUMED]` package names in this
phase — nothing new is being installed.

### Core (unchanged from prior phases)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | 1.30.1 | Algebraic modeling layer | `[VERIFIED: Project.toml compat + live run this session]` — already the project's sole modeling layer |
| Clarabel | 0.11.1 | SOCP/QP solve + duals | `[VERIFIED: local run this session]` — reused via `select_optimizer(problem_class(pf))`, never named directly |
| StableRNGs | 1.0.4 | Seeded, cross-version-stable RNG | `[VERIFIED: Project.toml compat]` — reused via `generate_profiles`/`sub_seed`, no new RNG discipline needed |

**Installation:** none — zero new dependencies.

## Package Legitimacy Audit

Not applicable — this phase installs no new packages. No `Pkg.add` call is part of any
recommended implementation; slopcheck/registry verification is skipped for this reason (per the
protocol's own scope: "whenever this phase installs external packages").

## Architecture Patterns

### System Architecture Diagram

```
generate_profiles(seed_s) ──► (demand_s, pv_s)  [S disjoint seeds, S = 3..5 in-sample]
        │
        ▼
build_population(:default, feeder, ..., seed_s) ──► aggregators_s  (devices: battery/thermostatic/deferrable)
        │
        ▼
┌─────────────────────────── ONE shared JuMP Model ───────────────────────────┐
│  for s in 1:S:                                                              │
│     ctx_s = ModelContext(model)                                            │
│     contribute!(pf::ConvexBranchFlow, ctx_s, feeder; T)   ─┐ NAMED containers│
│     JuMP.unregister(model, :v/:v̂/:P/:Q/:l/:cone/:vdrop/    │ (v,P,Q,l,cone…) │
│                     :cpydrop/:smax)  [skip after LAST s]  ─┘ freed for s+1  │
│     contribute!(agg, ctx_s; T) for agg in aggregators_s   (anonymous, safe) │
│     close :balance_p_s / :balance_q_s  (register_constraint! into ctx_s)   │
│     accumulate p_s * (ctx_s.meta[:objective] − λ₀ᵀp_import_s) into Σ obj   │
│                                                                              │
│  battery (+ deferrable, discretion) nonanticipativity:                     │
│     p_ch_s[t] == p_ch_1[t]  ∀ s=2..S, t   (+ p_dch, soc equality pairs)    │
└───────────────────────────────────────────────────────────────────────────┘
        │  @objective(Max, Σ_s p_s·(utility_s − λ₀ᵀp_import_s))
        ▼
   assert_solved!(model; dual=true)
        │
        ▼
   for s in 1:S: assert_socp_exact!(ctx_s; rtol)   ← D-06, per-scenario, never aggregated
        │
        ▼
   dadp_s = dual.(balance_p_s[bus,:]) ./ p_s        ← D-05 de-scaling, PRIMARY output
   expected_dadp = Σ_s p_s · dadp_s                  ← D-07 derived SUMMARY only
        │
        ▼ (separate, smaller model — D-09 out-of-sample harness)
   build a single-scenario welfare-shaped model ONCE, tie battery controls to
   pin Parameters (mirrors build_mpc_window's terminal_param idiom) fixed to
   the in-sample optimum; for each held-out scenario h in 1:H_budget:
       set_parameter_value.(Ppv_param_h, pv_h); set_parameter_value.(Pdc_param_h, demand_h)
       solve_with_retry!(...)  →  welfare_h
   realized_welfare = Σ_h q_h · welfare_h  vs  in_sample_welfare  →  welfare gap
```

### Recommended Project Structure
```
src/models/stochastic_welfare.jl     # NEW: build_stochastic_welfare(feeder, pf, scenario_aggs;
                                      #      probabilities, λ₀, T) -> StochasticWelfareResult
src/experiments/run_stochastic.jl    # NEW: run_stochastic(s::Scenario) -> (; in_sample, oos, trace)
                                      #      mirrors run_mpc(s::Scenario)'s single-entry-point shape
docs/literate/stochastic_pv_demand.jl  # NEW literate rung page (mirrors mpc_rolling_horizon.jl)
test/fixtures_phase22.jl             # NEW: small radial CI fixture (mirrors fixtures_phase19/21)
test/test_stochastic_welfare.jl      # NEW
test/test_run_stochastic.jl          # NEW
```
`src/models/welfare_solve.jl`, `src/models/oracle.jl`, `src/devices/*.jl`,
`src/powerflow/ConvexBranchFlow.jl` are all **byte-for-byte unmodified** — every new pattern
below is additive orchestration in the two new files above.

### Pattern 1: Scenario-indexed network contribution via the `JuMP.unregister` workaround
**What:** `ConvexBranchFlow.contribute!` uses named containers (`@variable(m, v[...])`, etc.)
and would collide if called twice on one `Model`. Calling `JuMP.unregister(model, name)` for
each of the nine names it registers (`:v, :v̂, :P, :Q, :l, :cone, :vdrop, :cpydrop, :smax`)
between scenario blocks removes only the model's convenience name→object lookup, NOT the
underlying `VariableRef`/`ConstraintRef` objects already captured in `ctx_s.meta[:pf_vars]` /
`ctx_s.constraints`. This was verified empirically this session (see Code Examples).
**When to use:** every scenario block after the first, immediately after that block's
`contribute!(pf, ctx_s, feeder; T)` call and before the next block's call.
**Confidence:** `[VERIFIED: live Julia run against this project's pinned environment, this
session — reproduced the exact collision error and confirmed the unregister fix produces
independent, byte-identical, separately-usable per-scenario handles: `num_variables(m) == 208`
for 2 scenarios at T=2 on IEEE-13, `pfvars1.v !== pfvars2.v`, and `pfvars1.v` remained usable in
a fresh constraint after the second `contribute!` call]`.

### Pattern 2: Nonanticipativity via explicit equality constraints (recommended over a shared variable)
**What:** Build the first-stage device (battery, optionally deferrable) independently in EVERY
scenario block via its normal `contribute!` call (so each block sees its own scenario's
`Ppv_param`/data), then add `@constraint(model, [t=1:T], p_ch_s[t] == p_ch_1[t])` (and the
`p_dch`/`soc` analogues) for `s = 2:S`.
**When to use:** for every device D-03 designates first-stage.
**Rationale (why not a literally-shared JuMP variable):** every device's `contribute!` bundles
its control variables and its own per-step data `Parameter` into ONE call
(`PVBattery.contribute!` creates `p_ch`/`p_dch`/`soc`/`pv_used` AND `Ppv_param` together, and
bounds `pv_used[t] <= Ppv_param[t]`). There is no existing seam to build a battery's *controls*
once while rebinding its *data* per scenario — doing so would require restructuring
`PVBattery.contribute!` into two calls (a device-file change outside this phase's stated scope,
and a materially bigger, riskier change than an additive equality constraint). The equality-
constraint approach is purely additive at the orchestration layer, reuses every device file
unmodified, and is the standard textbook extensive-form nonanticipativity idiom (Birge &
Louveaux 2011, Ch. 1) — `[CITED: Birge, J.R. & Louveaux, F., Introduction to Stochastic
Programming, 2nd ed., Springer Series in Operations Research and Financial Engineering,
Springer 2011, DOI 10.1007/978-1-4614-0237-4]`.
**Cost:** S× more variables/constraints for the shared devices than a literally-shared variable
would need. Negligible at S=3–5 on a small fixture (see capacity measurement below).
**Confidence:** MEDIUM-HIGH — the mechanics (equality constraints between independently-built
JuMP variables in one model) are standard JuMP and were not separately re-verified beyond the
project's own established idiom (e.g. `build_mpc_window`'s `soc[H] == terminal_param`), but the
"why not shared-variable" reasoning is a direct reading of `PVBattery.contribute!`'s actual
source, not training-data recall.

### Pattern 3: Per-scenario PF-04 gating (no new certificate)
**What:** Call `assert_socp_exact!(ctx_s; rtol=rtol_exact)` once per scenario `ctx_s` in a plain
loop, AFTER `assert_solved!(model; dual=true)` and BEFORE any `dual()` read — exactly
`solve_welfare`'s own ordering, just repeated S times over S independent `ctx.meta[:pf_vars]`
stashes.
**When to use:** always, for every scenario block, before reading that scenario's DADP.
**Why this is not certificate laundering:** the physical quantity being checked (`l·v ≈
P²+Q²` on THIS scenario's own branch-flow copy) is identical in kind to every prior use of
`assert_socp_exact!` — it is the SAME mathematical regime applied S times, not a new regime
reusing an old tolerance. D-06's "never aggregated" requirement is satisfied by construction:
each call only ever sees one scenario's `ctx_s`.
**Confidence:** HIGH — `[CITED: src/models/exactness.jl docstring + solve_welfare's own call
ordering]`, reused verbatim.

### Pattern 4: De-scaled per-scenario DADP (empirically verified)
**What:** `dadp_s[t] = dual(balance_p_s[bus, t]) / p_s`. In a `Max`-sense JuMP/Clarabel
objective `Σ_s p_s·f_s(x)` subject to per-scenario equality constraints `g_s(x) = 0`, scaling
scenario s's contribution to the objective by the positive constant `p_s` scales that
scenario's own dual by `p_s` (standard convex-duality sensitivity result: the optimal primal
`x*` is unaffected by a positive objective rescale, so KKT stationarity forces
`dual_p(g_s) = p_s · dual_1(g_s)`). This was verified NUMERICALLY (not just derived) this
session:
**Confidence:** `[VERIFIED: two-scenario extensive form built with `solve_welfare`'s own
residual-closure shape, p₁=0.35/p₂=0.65, identical underlying data for both scenarios, IEEE-13
default population, T=9 — max|d₁/p₁ − dadp₀| = 3.2e-5, max|d₂/p₂ − dadp₀| = 2.0e-5 against the
deterministic `solve_welfare` baseline `dadp₀`, and `objective_value(model) ≈ welfare₀` to 7
significant figures. No sign flip needed — the raw dual already has the correct sign, unlike
`PlanningOracle`'s unrelated `pin` constraint, whose negation is a DIFFERENT constraint shape
and must not be pattern-matched here.]`
**Anchor test (D-08 generalization):** two IDENTICAL scenarios with `p₁+p₂=1` collapse to the
deterministic answer — this is the mechanism the locked 1-scenario degenerate reduction test
exercises at its simplest (`S=1, p₁=1.0`); the 2-identical-scenario measurement above is
additional, stronger evidence of the same mechanism.
**Expected tolerance band:** ~1e-4 absolute on a per-unit DADP at this fixture scale (T=9,
IEEE-13, Clarabel default `tol_gap`) — consistent with, and no tighter than, the project's own
`rtol_exact = 1e-4` PF-04 default; do not pin a tighter golden tolerance than this without
re-measuring on the actual chosen CI fixture (measurement-before-golden, D-11).

### Pattern 5: Out-of-sample harness as a Parameter-pinned single-scenario build-once model
**What:** Do NOT reuse the S-scenario extensive-form model itself for the out-of-sample
harness. Build a SEPARATE, single-scenario, `solve_welfare`-shaped model ONCE, mirroring
`build_mpc_window`'s own idiom exactly: for each first-stage device, add an anonymous pin
`Parameter` and an equality constraint `p_ch[t] == pin_p_ch[t]` (mirrors
`build_mpc_window`'s `soc[H] == terminal_param` line-for-line). Set every pin Parameter ONCE to
the in-sample optimum (`value.(p_ch_1)` etc. from the solved extensive form). Then, for each
held-out scenario `h`, slide that scenario's own `Ppv_param`/`Pdc_param`/`Tout_param` (the
Phase-21-widened per-step device Parameters — already exist, zero new device code) via
`set_parameter_value.` and re-solve via `solve_with_retry!` — never rebuilding.
**When to use:** the out-of-sample harness (STOCH-03/D-09).
**Why a separate model, not the in-sample one:** the in-sample extensive form's per-scenario
network/device blocks are sized for the IN-SAMPLE scenario count S; a held-out evaluation is
conceptually a single new scenario's recourse problem, which is a materially smaller and
simpler model (no cross-scenario equality constraints, no S-way objective sum) — building it
fresh, once, and re-solving H times is both simpler to reason about and mirrors an existing,
already-tested pattern (`MpcWindow`) rather than inventing a new one.
**Confidence:** HIGH for the mechanism (`build_mpc_window`'s exact idiom, read directly from
source) / MEDIUM for "reuse this as the recommended shape" since it has not been built and run
for this specific harness in this session — flag for empirical confirmation at implementation
time (Wave-0 gap below).

### Anti-Patterns to Avoid
- **Calling `contribute!(pf::ConvexBranchFlow, ...)` twice on one `Model` without
  `unregister`:** throws immediately (`"An object of name v is already attached..."`) —
  verified this session.
- **Reusing ONE `ModelContext` across scenarios:** `ctx.residuals[:Rp]`/`ctx.meta[:pf_vars]`
  are single accumulators/slots — a second `contribute!` call into the SAME `ctx` would either
  error (WR-04's accumulator-kind guard) or silently overwrite the previous scenario's stash.
  Always give each scenario its OWN `ModelContext` wrapping the shared `model`.
- **Sharing a battery's `Ppv_param`/`pv_used` across scenarios while trying to keep `p_ch`
  shared "for free":** `pv_used`'s bound is scenario-specific (`Ppv_param` differs per
  scenario); a genuinely shared `p_ch` must be feasible under every scenario's own `pv_used`
  bound — the equality-constraint pattern above handles this naturally (S independent `pv_used`
  copies, S equality-tied `p_ch` copies); a naive "just don't call contribute! again for the
  battery" approach silently drops the PV-availability coupling for scenarios 2..S.
- **Reading `dadp_s` before calling `assert_socp_exact!(ctx_s; ...)` for that scenario:**
  identical hazard to `solve_welfare`'s own documented ordering requirement, just per-scenario.
- **Reusing the in-sample extensive-form model for out-of-sample evaluation by fixing
  everything except one scenario's blocks:** wastes S-1 scenario blocks' worth of unused
  variables/constraints per held-out evaluation and complicates the "recourse-only" framing —
  build the smaller, dedicated harness model instead (Pattern 5).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Seeded scenario generation | A bespoke Markov-chain sampler | `generate_profiles(; seed, T)` (existing, DATA-04) | Already reproducible bit-for-bit across Julia versions (`StableRNGs.LehmerRNG`); a new sampler would need to re-earn that guarantee |
| Per-scenario/held-out RNG independence | Manually offsetting a single seed | `sub_seed(master, tag)` (existing, materialize.jl) | Already the project's established independent-stream discipline (RESEARCH Pitfall 5 from prior phases); reinventing it risks correlated draws |
| Scenario-tree / stochastic-programming data structures | A `ScenarioTree` type or `StochasticPrograms.jl`-style abstraction | A flat `Vector{NamedTuple}` of `(; seed, probability, demand, pv)` | 2-stage, 3–5 in-sample scenarios needs no tree; `StochasticPrograms.jl`/`InfiniteOpt.jl` were already evaluated and rejected project-wide (REQUIREMENTS.md "Out of Scope") |
| Retry/conditioning ladder on `NUMERICAL_ERROR` | A bespoke per-scenario retry loop | `solve_with_retry!` (existing, `src/planning/retry.jl`) | Already handles the documented intermittent Clarabel `NUMERICAL_ERROR`/`SLOW_PROGRESS`/`ALMOST_OPTIMAL` ladder without ever falling back to a different solver (D-09/CLAUDE.md) |
| SOC exactness certification per scenario | A new "multi-scenario" exactness checker | `assert_socp_exact!` called S times, once per `ctx_s` | The same physical cone check, S independent invocations — a new function would be certificate-laundering risk in reverse (inventing complexity, not reusing a tolerance) |

**Key insight:** this phase needs essentially zero new primitives — its entire job is
orchestration (loop S times, wire nonanticipativity, de-scale duals, reuse the harness idiom).
The one genuinely new mechanical fact (the `ConvexBranchFlow` named-container collision) has an
existing, documented JuMP escape hatch (`unregister`), not a new abstraction.

## Common Pitfalls

### Pitfall 1: `ConvexBranchFlow.contribute!` named-container collision on repeated calls
**What goes wrong:** the second (and every subsequent) `contribute!(::ConvexBranchFlow, ctx_s,
feeder; T)` call on the same `Model` throws.
**Why it happens:** `@variable(m, v[j=1:N,t=1:T])` etc. register the symbol in the model's
JuMP object dictionary; a second call with the same symbol collides. This formulation file was
never previously exercised with more than one call per model (every prior phase builds exactly
one network per model).
**How to avoid:** `JuMP.unregister(model, name)` for each of the nine names, between scenario
blocks — verified this session to be sufficient and safe.
**Warning signs:** the exact error string `"An object of name v is already attached to this
model"` (or `v̂`/`P`/`Q`/`l`/`cone`/`vdrop`/`cpydrop`/`smax`).

### Pitfall 2: Reusing one `ModelContext` across scenarios silently corrupts the balance
**What goes wrong:** `ctx.residuals[:Rp]` is a single accumulator; a second scenario's
`contribute!` calls into the SAME `ctx` either error (the WR-04 accumulator-kind guard in
`add_to_residual!`) or ADD scenario 2's flows into scenario 1's balance, producing a physically
meaningless combined network with no exception raised in the indexed-matrix growth path.
**Why it happens:** `ModelContext.residuals`/`.meta` are `Dict{Symbol,Any}` scoped to the
`ModelContext` instance, not the `Model` — but it is easy to assume "one context per model"
since every prior phase built exactly one context per model.
**How to avoid:** one fresh `ModelContext(model)` per scenario, always.
**Warning signs:** a `size(...) == (N,T)` residual-shape guard failure, or (worse) a
successful-looking solve whose balance is silently wrong.

### Pitfall 3: Deferrable's absolute-hour window constraint at small T
**What goes wrong:** `materialize.jl`'s `:default` population's `Deferrable` device throws
`ArgumentError` at population-materialization time (not solve time) at small `T` — e.g. `T=8`
fails for `:ieee13`, `T=9` is the smallest value that constructs successfully (measured, Phase
21 discovery, re-confirmed this session while measuring capacity).
**Why it happens:** `Deferrable`'s energy-budget window `[t_start,t_end]` is baked at
construction against the full horizon `T`; at small `T` the window can shrink to
`window_length=1`, which the device's own `E <= Pmax·window_length` guard rejects.
**How to avoid:** if the small CI fixture uses `:default`-style population data (or any
Deferrable-bearing population) at a small `T`, use `T ≥ 9` for `:ieee13`, or build a
Deferrable-free small fixture (mirrors Phase 4's `high_pv_feeder`/`build_high_pv_aggregators`,
which has no Deferrable at all) — the latter is the lower-risk choice for a CI fixture the
planner controls end-to-end.
**Warning signs:** an `ArgumentError` from `Deferrable`'s inner constructor, thrown before any
model assembly begins.

### Pitfall 4: Misreading Julia JIT warm-up as "S=1 is slower than S=5"
**What goes wrong:** the very first Clarabel/JuMP solve in a fresh Julia process measured
14.5s; S=3 (0.215s) and S=5 (0.381s) in the SAME process were dramatically faster. A naive
reading suggests "smaller S is somehow slower," which is false and would misdirect a capacity
investigation.
**Why it happens:** Julia's JIT compiles `Clarabel`/`JuMP`/`MOI` dispatch paths on first use per
process; every subsequent call in the same process reuses compiled code.
**How to avoid:** always run a throwaway warm-up solve (any tiny model) before measuring
per-scenario-count solve time, or measure only the second-and-later solves in a process, exactly
as this session's own measurement had to be read.
**Warning signs:** a "smaller model solved slower" result that doesn't reproduce across repeated
runs in the same warm process.

### Pitfall 5: Pattern-matching a dual's sign convention from an unrelated constraint
**What goes wrong:** `src/planning/subproblem.jl`'s own documentation states the `pin`
constraint's raw dual is NEGATED relative to naive `∂objective/∂z` expectation under this
project's `Max`-sense objective. It would be easy to assume the SAME negation applies to the
per-scenario `:balance_p` dual in the stochastic builder.
**Why it happens:** both are equality-constraint duals inside the same `Max`-sense JuMP model
family; superficially they look like "the same kind of thing."
**How to avoid:** `:balance_p`/`:balance_q` in this phase are structurally IDENTICAL to
`solve_welfare`'s own `:balance_p`/`:balance_q` closure (`ctx.residuals[:Rp][j,t] == 0`), which
is already validated (no negation) — and this session's own numeric verification confirms no
sign flip is needed for the per-scenario de-scaled dual. Never assume a sign convention;
verify against the SPECIFIC constraint shape in question (this project's own established
discipline, per `10-RESEARCH.md Pitfall 1`).
**Warning signs:** a degenerate-reduction test (D-08) that is off by a factor of exactly −1.

### Pitfall 6: Amplified intermittent Clarabel `NUMERICAL_ERROR` under repeated re-solves
**What goes wrong:** the project has a long-documented, version-independent, intermittent
Clarabel `NUMERICAL_ERROR`/`SLOW_PROGRESS` flake (`~55% baseline single-call rate` measured on
IEEE-123 ADMM, Phase 16-04) that prior phases (MPC's per-step re-solve, this phase's
out-of-sample per-held-out-scenario re-solve) explicitly expect to AMPLIFY, not just persist,
because each adds a new repeated-re-solve outer loop (STATE.md carried blocker).
**Why it happens:** cone-slack numerical sensitivity, per-unit-base dependent; not fixed
upstream, not fixed in this project.
**How to avoid:** route every solve (in-sample AND every held-out re-solve) through
`solve_with_retry!` (never a bare `optimize!`), and re-measure the observed flake rate on the
ACTUAL chosen fixture/scenario count rather than assuming the Phase 16-04 IEEE-123 ADMM rate
transfers unchanged to a IEEE-13/SOCP extensive form.
**Warning signs:** a CI flake that reproduces on re-run at a different rate than expected;
`termination_status(model) ∈ RETRYABLE_STATUSES` observed at all on the chosen fixture.

## Code Examples

### The verified `unregister` workaround (Pattern 1)
```julia
# Source: verified live against this project's pinned Manifest.toml, this session.
# (src/powerflow/ConvexBranchFlow.jl's contribute! is UNMODIFIED — this is orchestration-only.)
model = Model(select_optimizer(problem_class(pf)))
ctxs = ModelContext[]
for s in 1:S
    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder; ctx.meta[:T] = T
    contribute!(pf, ctx, feeder; T = T)          # ConvexBranchFlow: NAMED containers
    if s < S
        for name in (:v, :v̂, :P, :Q, :l, :cone, :vdrop, :cpydrop, :smax)
            JuMP.unregister(model, name)          # frees the NAME only, not the objects
        end
    end
    push!(ctxs, ctx)
end
# Verified this session: num_variables(model) == 208 for S=2, T=2, IEEE-13 (byte-identical to
# 2 × the single-scenario count); ctxs[1].meta[:pf_vars].v !== ctxs[2].meta[:pf_vars].v; and
# ctxs[1]'s variables remained usable in a NEW constraint after ctxs[2]'s contribute! call.
```

### Nonanticipativity equality constraints (Pattern 2)
```julia
# Battery contribute!'d independently per scenario (each sees its own Ppv_param):
batt_vars = Vector{NamedTuple}(undef, S)
for s in 1:S
    res = contribute!(battery, ctxs[s]; T = T)     # fresh p_ch_s/p_dch_s/soc_s/pv_used_s
    batt_vars[s] = res.vars
end
# Tie every scenario's schedule to scenario 1's (the shared first-stage decision):
for s in 2:S
    @constraint(model, [t = 1:T], batt_vars[s].p_ch[t] == batt_vars[1].p_ch[t])
    @constraint(model, [t = 1:T], batt_vars[s].p_dch[t] == batt_vars[1].p_dch[t])
    @constraint(model, [t = 1:T], batt_vars[s].soc[t] == batt_vars[1].soc[t])
end
```

### De-scaled per-scenario DADP + degenerate anchor (Pattern 4)
```julia
# Source: verified live this session (2-scenario, p₁=0.35/p₂=0.65, IEEE-13, T=9).
@objective(model, Max,
    sum(probabilities[s] * (ctxs[s].meta[:objective] -
                             sum(λ₀[t] * p_imports[s][t] for t in 1:T)) for s in 1:S))
assert_solved!(model; dual = true)
for s in 1:S
    assert_socp_exact!(ctxs[s]; rtol = rtol_exact)     # D-06: per-scenario, never aggregated
end
dadp = [dual.(balance_ps[s][priced_bus, :]) ./ probabilities[s] for s in 1:S]   # D-05, PRIMARY
expected_dadp = sum(probabilities[s] .* dadp[s] for s in 1:S)                    # D-07, DERIVED ONLY
# Verified: with S=2 identical-scenario data, max(|dadp[1] .- dadp_deterministic|) ≈ 3.2e-5.
```

### Out-of-sample Parameter-pin harness (Pattern 5, mirrors `build_mpc_window`)
```julia
# Source: idiom read directly from src/models/mpc_window.jl (soc[H] == terminal_param pattern),
# NOT re-implemented/re-verified this session — flagged for Wave-0 confirmation.
res = contribute!(battery, ctx; T = T)               # fresh p_ch/p_dch/soc/pv_used
pin_p_ch = @variable(model, [t = 1:T], set = Parameter.(in_sample_p_ch))
@constraint(model, [t = 1:T], res.vars.p_ch[t] == pin_p_ch[t])
# ... analogous pin_p_dch / pin_soc (or pin only p_ch/p_dch and let soc recursion follow) ...
for h in 1:H_budget
    set_parameter_value.(res.vars.Ppv_param, held_out_scenarios[h].pv)
    set_parameter_value.(agg_pdc_param, held_out_scenarios[h].demand)
    solve_with_retry!(model; dual = true)
    welfare_h[h] = objective_value(model)
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| One deterministic day-ahead welfare solve, one DADP path | Two-stage extensive form over 3–5 seeded scenarios, per-scenario DADPs primary, expectation a derived summary | This phase (STOCH-01/02) | Prices become honestly scenario-conditional rather than a single point estimate; requires the de-scaling step (D-05) to remain interpretable as a genuine dual |
| Deterministic MPC forecast perturbation (Phase 21, ±5–10% bounded noise on one realized path) | Explicit multi-scenario Markov-chain draws with distinct probabilities | This phase | Different uncertainty representation (discrete scenario tree vs. continuous bounded perturbation around one realized path) — the two axes are complementary, not a replacement of one by the other |
| `objective_hook` stub (SEAM-01, inert since Phase 4) | Confirmed genuinely insufficient for this axis; a sibling module supersedes it | This phase (D-02) | `[CITED: src/models/oracle.jl:72-75 docstring — "Reserved to compose the per-scenario welfare into the extensive-form objective... wiring it into assembly is the stochastic-extension point"]` — the hook only ever transforms `ctx.meta[:objective]` on ONE ctx; it has no argument for per-scenario network/device duplication, confirming the CONTEXT.md D-02 resolution by direct source inspection |

**Deprecated/outdated:** none — this phase adds a new capability rather than replacing one.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Equality-constraint nonanticipativity (Pattern 2) generalizes cleanly from the battery to `Deferrable` if Claude's discretion includes it in first-stage | Architecture Pattern 2 | Deferrable's own energy-budget/window mechanics were not re-verified under the equality-constraint pattern this session (only the battery was); if Deferrable's constraint shape interacts badly with duplicated+tied copies, the planner should test this specifically before committing |
| A2 | The out-of-sample harness's `build_mpc_window`-mirrored Parameter-pin idiom (Pattern 5) will compose cleanly for a `solve_welfare`-shaped (not MPC-window-shaped) single-scenario model | Architecture Pattern 5 | Not built/run this session (time-boxed); if `PVBattery`'s `contribute!` return shape or the pin-equality idiom doesn't compose as cleanly outside the `MpcWindow` struct, the harness may need a small additional builder — this is a Wave-0-verifiable risk, not a fundamental blocker |
| A3 | Clarabel capacity headroom measured on the DEFAULT 10-aggregator IEEE-13 population transfers favorably to whatever SMALLER dedicated CI fixture the planner builds per D-12 | Summary / Clarabel capacity measurement | Low risk (smaller fixture ⇒ fewer variables ⇒ if anything, MORE headroom) but not independently measured on the actual chosen CI fixture — re-measure once that fixture exists (Wave-0 gap) |
| A4 | Birge & Louveaux (2011, 2nd ed.) is the correct standard citation for two-stage stochastic programming with recourse, and Zavala/Kim/Anitescu/Birge (2017, Operations Research 65(3), 557–576) is an apt standard citation for probability-weighted duals in stochastic market clearing | Architecture Pattern 2 / Summary | `[CITED: WebSearch this session, cross-checked across arXiv/OSTI/ResearchGate — MEDIUM-HIGH confidence, not independently read cover-to-cover]`; if wrong, only the literate page's citation text needs correction, no code/model impact |

## Open Questions

1. **Should `ConvexBranchFlow.jl` be modified to use anonymous containers instead of relying on
   the orchestration-side `unregister` workaround?**
   - What we know: the `unregister` workaround was verified to work correctly and requires zero
     device/pf-file changes.
   - What's unclear: whether a future phase (e.g. meshed networks, Phase 23) will ALSO need
     multiple `contribute!` calls per model, in which case anonymizing `ConvexBranchFlow`
     directly (mirroring Phase 21's own device fix) might be the more durable investment.
   - **(RESOLVED — use the `unregister` workaround for this phase; it is fully additive,
     verified, and in scope. Anonymizing `ConvexBranchFlow.jl` itself is a larger, riskier,
     out-of-scope change this phase does not need — leave it as a note for whichever future
     phase first needs it, if any.)**

2. **Shared JuMP variable vs. explicit equality-constraint nonanticipativity for the first-stage
   battery?**
   - What we know: the equality-constraint approach is additive, reuses every device file
     unmodified, and is the standard textbook idiom.
   - What's unclear: whether a literally-shared-variable approach (requiring a `PVBattery`
     contract change to decouple controls from data) would be materially cheaper at scale.
   - **(RESOLVED — recommend explicit equality constraints; see Architecture Pattern 2's full
     rationale. At S=3–5 the extra variable/constraint count is negligible per the measured
     capacity numbers above.)**

3. **(RESOLVED — CONTEXT.md Claude's-Discretion grant; planner fixed counts in plans.)
   Exact scenario counts (3–5 in-sample, 5–10 held-out) and whether Deferrable joins the
   battery in first-stage** — both explicitly left to Claude's discretion in CONTEXT.md; this
   research does not further narrow them. Recommendation: default to 3 in-sample (cheapest CI
   still proving the D-04 non-uniform-probability plumbing) with 5 quarantined for the literate
   demonstration; 5 held-out for CI, 10 quarantined; include Deferrable in first-stage alongside
   the battery only if the chosen small CI fixture's population includes it (Pitfall 3 governs
   feasibility at small T). **(RESOLVED — CONTEXT.md Claude's-Discretion grant; planner fixed
   counts in plans: `stoch_S=3`/`stoch_H_oos=5` in `Phase22Fixtures` (plan 22-01),
   `stoch_S=5`/`stoch_H_oos=10` in the literate demonstration (plan 22-05), Deferrable excluded
   from first-stage entirely — the fixture is Deferrable-free per D-12/Pitfall 3.)**

4. **(RESOLVED — 22-02-PLAN.md Task 1 measures num_variables/num_constraints for S=1,3,5 as
   acceptance criteria.) Will the measured Clarabel capacity/warm-solve-time numbers transfer to
   the actual, not-yet-built, small CI fixture?**
   - What we know: the default 10-aggregator IEEE-13 population handles S=5 comfortably
     (6,980 vars / 13,825 constraints, 0.38s warm).
   - What's unclear: the planner's chosen small fixture will almost certainly be smaller (fewer
     aggregators, per D-12/Phase-4 precedent) — likely even more comfortable, but unmeasured.
   - **(RESOLVED — 22-02-PLAN.md Task 1 measures num_variables/num_constraints for S=1,3,5 as
     acceptance criteria — its own `<verify>` script prints `num_variables(model)` for S=1,3,5
     on the actual small CI fixture shape, closing the Wave-0 measurement gap below.)**

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | all model code | ✓ | 1.10+ (project floor) | — |
| JuMP | model assembly | ✓ (verified live this session) | 1.30.1 | — |
| Clarabel | SOCP/QP solve + duals | ✓ (verified live this session) | 0.11.1 | — |
| StableRNGs | scenario seeding | ✓ (already used by `generate_profiles`) | 1.0.4 | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none — this phase needs nothing beyond the existing
pinned environment.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `Test` (stdlib) + `TestItems`/`TestItemRunner` (`@testitem`), project standard |
| Config file | `test/runtests.jl` (`@run_package_tests`) — the SOLE full-suite entry point |
| Quick run command | direct Julia script under `--project=.` (per this project's own mandatory testing constraint — NEVER `TestItemRunner` under `--project=.`, NEVER a bare `include()` of an `@testitem` file) |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (~12–20 min, background; reserved for the final acceptance plan) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| STOCH-01 | S-scenario extensive form solves `OPTIMAL` on the small CI fixture with non-uniform probabilities (D-04) | unit/integration | direct script calling `build_stochastic_welfare(...)`, `--project=.` | ❌ Wave 0 |
| STOCH-01 | Degenerate reduction: S=1 reproduces `solve_welfare` (D-08) | regression | direct script comparing welfare/DADP within solver tolerance | ❌ Wave 0 |
| STOCH-02 | Per-scenario DADP de-scaling matches deterministic baseline under 2-identical-scenario construction (generalizes the S=1 anchor) | regression | direct script (mirrors this session's own verification) | ❌ Wave 0 |
| STOCH-02 | PF-04 gate runs per scenario, never aggregated (D-06) | unit | direct script asserting `assert_socp_exact!` is called once per `ctx_s`, and a forced-inexact single scenario does not silently pass via another scenario's exactness | ❌ Wave 0 |
| STOCH-03 | Out-of-sample harness Parameter-pins first-stage decisions and reports a realized-vs-in-sample welfare gap | integration | direct script, small held-out budget | ❌ Wave 0 |
| STOCH-03 | Measurement-before-golden: repeated-run stability check precedes any pinned golden (D-11) | regression | direct script re-running the same `Scenario`/seed N times, asserting bit-for-bit or tolerance-bounded stability before any `@test welfare ≈ <pinned literal>` is written | ❌ Wave 0 |
| STOCH-04 | Live-executed literate rung page builds a `Scenario`, calls the phase's one entry point, shows real per-scenario DADPs + the out-of-sample gap | manual (Documenter build) | `julia --project=docs docs/make.jl` (project convention) | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** direct Julia script under `--project=.` exercising the specific
  construction/mechanism just implemented (mirrors Phase 19–21's own `<verify>` script
  convention).
- **Per wave merge:** the new `@testitem`s for that wave, run as standalone plain scripts (per
  this project's mandatory testing constraint), plus `Pkg.precompile()`.
- **Phase gate:** full `Pkg.test()` green before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/fixtures_phase22.jl` — small radial CI fixture (recommend a Deferrable-free,
  Phase-4-`high_pv_feeder`-style 3-bus fixture, or a measured-safe `T ≥ 9` `:default`-population
  IEEE-13 slice if Deferrable inclusion is desired) — covers STOCH-01/02/03.
- [ ] Re-measure Clarabel capacity (`num_variables`, `num_constraints`, warm solve time,
  observed `termination_status` distribution across a handful of repeated runs) on the ACTUAL
  chosen CI fixture at S=1,3,5 — the numbers in this research are measured on the DEFAULT
  10-aggregator IEEE-13 population, not the smaller dedicated fixture the planner will build.
- [ ] Build and run the out-of-sample harness's Parameter-pin mechanism once (Pattern 5) to
  confirm it composes cleanly outside the `MpcWindow` struct shape it mirrors — flagged as
  Assumption A2, not independently verified this session.
- [ ] `test/test_stochastic_welfare.jl`, `test/test_run_stochastic.jl` — new files.
- [ ] Framework install: none — `Test`/`TestItems`/`TestItemRunner` already present.

## Security Domain

This is a research computational library with no network-facing surface, no authentication, no
session state, and no externally-supplied untrusted input beyond scenario/config selectors
already validated at construction time (`Scenario`'s own `ArgumentError`-throwing inner
constructor, project convention). Most ASVS categories do not apply.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | n/a — not a networked system |
| V3 Session Management | no | n/a |
| V4 Access Control | no | n/a |
| V5 Input Validation | yes | `ArgumentError`-throwing inner constructors (project convention, never `@assert`) — the new `stoch_*` `Scenario` fields (probabilities vector length/sum-to-1, scenario count within the locked 3–5/5–10 bands, seed positivity) must follow the SAME pattern already established by `mpc_*` fields |
| V6 Cryptography | no | n/a — no secrets/crypto in this phase |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed/mismatched `probabilities` vector (wrong length, doesn't sum to 1, contains a non-positive entry) silently mis-weights the objective | Tampering (of correctness, not security in the adversarial sense) | Validate at construction (length == S, `sum(probabilities) ≈ 1` within a tolerance, all entries `> 0`) and throw `ArgumentError` loudly — mirrors every other `Scenario`/device guard in this codebase |
| Reading a per-scenario DADP before that scenario's PF-04 gate has run | Tampering (physically-meaningless price silently returned) | D-06's own per-scenario gate ordering, enforced by construction (loop order in the builder), exactly as `solve_welfare` already enforces for the deterministic case |

## Sources

### Primary (HIGH confidence)
- `[VERIFIED: live Julia execution against this project's pinned `Manifest.toml`/`Project.toml`,
  this session]` — the `ConvexBranchFlow.contribute!` named-container collision, the
  `JuMP.unregister` workaround, and the per-scenario de-scaled-dual numeric verification were all
  reproduced directly, not recalled from training data.
- `src/models/welfare_solve.jl`, `src/models/oracle.jl`, `src/models/mpc_window.jl`,
  `src/models/exactness.jl`, `src/planning/subproblem.jl`, `src/planning/retry.jl`,
  `src/data/profiles.jl`, `src/experiments/Scenario.jl`, `src/experiments/run.jl`,
  `src/experiments/materialize.jl`, `src/devices/PVBattery.jl`, `src/devices/Aggregator.jl`,
  `src/powerflow/ConvexBranchFlow.jl`, `src/solver/ProblemClass.jl`, `src/core/ModelContext.jl`
  — read directly this session.
- `.planning/phases/21-mpc-rolling-horizon-real-time-pricing/21-01-SUMMARY.md`,
  `21-05-SUMMARY.md` — the anonymized-container lesson and its precedent-setting fix.
- `.planning/phases/22-stochastic-pv-demand-uncertainty/22-CONTEXT.md`,
  `.planning/REQUIREMENTS.md`, `.planning/STATE.md` — locked decisions, requirement text, carried
  blockers.

### Secondary (MEDIUM confidence)
- Birge, J.R. & Louveaux, F., *Introduction to Stochastic Programming*, 2nd ed., Springer 2011
  (DOI 10.1007/978-1-4614-0237-4) — `[CITED: WebSearch, cross-checked across Springer/Amazon/
  Google Books listings]`, standard two-stage-with-recourse reference for the literate page.
- Zavala, V.M., Kim, K., Anitescu, M., Birge, J.R., "A Stochastic Electricity Market Clearing
  Formulation with Consistent Pricing Properties," *Operations Research*, 65(3), 557–576, 2017
  (extends Pritchard, Zakeri & Philpott 2010) — `[CITED: WebSearch, cross-checked across arXiv/
  OSTI/ResearchGate]`, a standard reference for probability-weighted duals in stochastic market
  clearing, for the literate page's price-semantics citation.

### Tertiary (LOW confidence)
- None — every claim above was either directly verified against the codebase/live execution or
  cross-checked across multiple independent search results.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new packages, all versions read from the pinned `Project.toml`.
- Architecture (construction mechanics): HIGH — the load-bearing collision and its fix, and the
  dual de-scaling, were both empirically reproduced this session against the actual project
  environment, not assumed.
- Architecture (nonanticipativity recommendation, out-of-sample harness shape): MEDIUM-HIGH —
  reasoned from direct source inspection and established precedent, but not fully built/run in
  this session (flagged as Assumptions A1/A2 and Wave-0 gaps).
- Pitfalls: HIGH — five of six are either directly reproduced or read verbatim from the
  project's own carried-blocker/precedent documentation; only the "amplified NUMERICAL_ERROR
  under repeated re-solve" pitfall is a documented expectation, not yet measured for THIS phase's
  specific access pattern.
- Capacity measurement: MEDIUM — measured on the default 10-aggregator IEEE-13 population, not
  the (not-yet-built) small dedicated CI fixture; directionally strong evidence, not a final
  number.

**Research date:** 2026-08-09
**Valid until:** 2026-09-08 (30 days — stable local codebase/pinned Manifest; re-verify sooner if
`Project.toml`/`Manifest-v1.12.toml` changes materially, e.g. a Clarabel/JuMP version bump)

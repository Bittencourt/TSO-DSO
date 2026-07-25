# Phase 15: AC-Exactness Oracle - Research

**Researched:** 2026-07-25
**Domain:** Independent nonconvex AC-OPF exactness certification for a radial SOCP branch-flow relaxation (Julia/JuMP)
**Confidence:** HIGH (all claims grounded in the actual `src/` files read this session, plus a pre-existing, unusually deep v2.1 research pass — `.planning/research/{ARCHITECTURE,PITFALLS,FEATURES,STACK,SUMMARY}.md`, researched the same day and independently converging with this session's own code reading)

## Summary

Phase 15 adds a **second, structurally independent** way to certify that the project's SOCP
Convex Branch Flow relaxation (`ConvexBranchFlow`, `src/powerflow/ConvexBranchFlow.jl`) is exact —
replacing today's self-referential check (re-solving the *same* relaxed cone through Ipopt via an
MOI bridge, in `test_ieee13.jl`/`test_welfare_solve.jl`) with a genuinely different nonconvex
model. The codebase's own architecture makes this close to free: `AbstractPowerFlow` is already an
open dispatch contract (`contribute!`, `problem_class`), `solve_welfare` is already
formulation-agnostic and already threads `allow_local`/an alternate `optimizer` for exactly this
kind of cross-solver check, and `NLP() → Ipopt` is already wired in `solver/factory.jl` as a main
dependency. No new package, no `Project.toml` change, no change to `ModelContext.jl`,
`solver/factory.jl`, `solver/problem_class_trait.jl`, `welfare_solve.jl`, or `exactness.jl` is
required.

The new work is: (1) a peer `ACPowerFlow <: AbstractPowerFlow` that mirrors
`ConvexBranchFlow.contribute!` variable-for-variable but replaces the rotated-SOC inequality
`l·v ≥ P²+Q²` with the true nonconvex **equality** `l·v = P²+Q²` (dropping the exactness copy
`v̂`, which exists only to force an inequality tight — nothing to force here); (2) a **new sibling
file** `src/models/ac_oracle.jl` holding `assert_ac_exact!`, which — unlike `assert_socp_exact!` —
must NOT throw on a genuine gap: it returns a per-hour comparison table (objective/voltage/branch
gaps against a scale-free `atol + rtol·magnitude` bound), because a genuine relaxation failure
under high-PV reverse flow is this milestone's most valuable possible finding, not a defect to
refuse; (3) a post-solve **voltage-angle recovery** utility (a standard radial branch-flow phasor
recursion, `V_j = V_i - z_ij·conj(S_ij)/conj(V_i)` walked from the root by BFS), needed because the
SOCP model is voltage-**magnitude**-only and this is the first place in the codebase angles become
load-bearing — flagged by the project's own STATE.md as genuinely new math requiring validation on
a trivial 2-bus fixture first; and (4) a deliberately-tuned high-PV stress fixture (a `pv_scale`
increase on the existing `Phase4Fixtures.high_pv_feeder`) engineered to pin the voltage at `V²max`
— the one documented regime where the SOC relaxation is known to go genuinely inexact — so a real
gap can surface and be written up rather than suppressed.

**Primary recommendation:** Add `ACPowerFlow` in `src/powerflow/ACPowerFlow.jl` (peer to
`ConvexBranchFlow.jl`, included immediately after it in `TSODSO.jl`), dispatched through
`solve_welfare` UNCHANGED (`solve_welfare(feeder, ACPowerFlow(), aggregators; λ₀, T,
optimizer=select_optimizer(NLP()), allow_local=true, allow_export)`); add `assert_ac_exact!` in a
new `src/models/ac_oracle.jl` that takes BOTH solved `ModelContext`s and returns a per-hour
`Vector{NamedTuple}`/`DataFrame` report, never throwing on disagreement; add angle recovery as a
pure post-processing function over a solved `ctx`'s `pf_vars`, validated first on the 2-bus
fixture already used throughout `test_convex_branch_flow.jl`/`test_exactness.jl`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Nonconvex AC-OPF formulation (`ACPowerFlow.contribute!`) | Modeling (`powerflow/`) | — | Exactly the `AbstractPowerFlow` contract's job: write per-bus/time branch/voltage terms into `ctx.residuals[:Rp]`/`[:Rq]`. No new tier. |
| Problem-class routing (`problem_class(::ACPowerFlow) = NLP()`) | Solver abstraction (`solver/`) | Modeling (`powerflow/`) | Defined INSIDE `ACPowerFlow.jl` itself (mirrors `ConvexBranchFlow.jl`'s own `problem_class` line), not in `solver/problem_class_trait.jl` — same file-locality convention already established. |
| Centralized re-solve dispatch | Modeling (`models/welfare_solve.jl`) | — | Reused verbatim, zero changes — this is the entire reason the AC oracle is architecturally "free." |
| Cross-solution certification (`assert_ac_exact!`) | Modeling (`models/ac_oracle.jl`, NEW) | — | A new sibling to `models/exactness.jl`, not a modification of it — the SOCP self-consistency gate and the AC cross-check are different invariants with different failure semantics (throw vs. report). |
| Voltage-angle recovery | Modeling (`models/ac_oracle.jl`, NEW) | Documentation (`docs/literate/`) | Pure post-processing over solved `pf_vars`; no new JuMP variable, no solver involvement — a Julia-side complex-arithmetic recursion. |
| High-PV stress fixture | Test fixtures (`test/fixtures_phase4.jl` or a Phase-15-owned fixtures module) | — | Data-only; reuses the existing `high_pv_feeder`/`_house_aggregator` fixture-building pattern with a tuned `pv_scale`. |
| Literate rung page | Documentation (`docs/literate/`) | — | Reuses the established Documenter+Literate rung convention (`docs/make.jl`), executed live so numbers can't drift from code. |

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| EXACT-01 | Researcher can solve a true nonconvex AC-OPF on a radial fixture via a new `ACPowerFlow <: AbstractPowerFlow` peer subtype (Ipopt), enforcing the branch-flow SOC as a nonconvex equality, at the same operating point (loads/PV) as the SOCP solve. | `ACPowerFlow` design (mirrors `ConvexBranchFlow.contribute!`, equality not cone), dispatch via `solve_welfare(feeder, ACPowerFlow(), aggregators; ...)` unchanged — "same operating point" = same `feeder`/`aggregators`/`λ₀`/`T`/`allow_export` inputs, each solver independently optimizing (the "optimality check" mode the literature treats as the headline claim — see Common Pitfalls / FEATURES.md Capability A). `NLP()→Ipopt` already wired. |
| EXACT-02 | Framework certifies exactness via `assert_ac_exact!` (peer to `assert_socp_exact!`) by comparing SOCP vs AC-OPF on objective gap, max voltage deviation, and max branch-flow deviation, using a scale-free `atol + rtol·magnitude` tolerance. | `assert_ac_exact!(ctx_socp, ctx_ac; atol, rtol)` design reusing the EXACT `atol + rtol·max(|lhs|,|rhs|)` idiom `assert_socp_exact!` already established (WR-01) — same philosophy, applied to a two-context comparison instead of a single-context cone residual. |
| EXACT-03 | The exactness check reports per-hour/per-scenario gaps in a table, never a single pass/fail boolean, so a genuine gap is investigated before any tolerance is touched. | Explicit divergence from `assert_socp_exact!`'s throw-on-failure pattern, documented below (Common Pitfalls, Pitfall 1) — `assert_ac_exact!` returns a per-hour report structure and does not throw on disagreement (only on structural mismatches, e.g. differing `T`/feeder). |
| EXACT-04 | A high-PV/reverse-flow stress fixture exercises the exactness boundary, and the result — exact or genuinely inexact — is documented in a literate rung page beside the thesis equations. | Reuse + tune `Phase4Fixtures.high_pv_feeder`/`_house_aggregator`'s existing `pv_scale` knob (calibration note in `test/fixtures_phase4.jl:209-216` already documents the exact mechanism: `pv_scale ≫ 0.5` pins voltage at `V²max`, the one regime where the LinDistFlow exactness copy cannot force the SOCP relaxation tight). Literate page follows the established `docs/literate/*.jl` + `docs/make.jl` convention. |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **JuMP, not Convex.jl** for the new model — direct access to named constraints and the branch-flow
  variables is required for the SOCP-vs-AC comparison; this phase adds no Convex.jl usage.
- **Ipopt for NLP** — `select_optimizer(NLP())` already resolves to Ipopt (`optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0)`, `src/solver/factory.jl:66`); this phase must not introduce a second NLP backend.
- **No model names a concrete solver (INFRA-02)** — `ACPowerFlow.jl` must add `problem_class(::ACPowerFlow) = NLP()` exactly as `ConvexBranchFlow.jl` adds `problem_class(::ConvexBranchFlow) = SOCP()`; never hard-code `Ipopt.Optimizer` inside a model file.
- **From-scratch model, numbered thesis equations** — `ACPowerFlow.contribute!` must cite the same thesis equation numbers `ConvexBranchFlow.contribute!` cites (3.31-3.34, 3.36) since it is the SAME physical model, just unrelaxed; do not build on PowerModels(Distribution) for this (CLAUDE.md explicitly rules this out, and the project's own STACK.md research independently reaches the same conclusion for this exact phase — see Alternatives Considered).
- **Documenter + Literate for docs** — a new `docs/literate/ac_oracle.jl` page is required (mirrors `docs/literate/convex_branch_flow.jl`), added to `docs/make.jl`'s literate-source tuple and `pages` list.
- **Clarity/correctness over premature optimization** — do not hand-roll a Newton-Raphson/forward-backward-sweep AC solver; Ipopt is already validated and available (FEATURES.md explicitly flags a custom AC solver as scope creep / anti-feature for this milestone).
- **Fail loudly, never `@assert`** (project convention, `src/core/status.jl`) — any genuine coding-level mismatch in `assert_ac_exact!` (mismatched `T`, mismatched feeder) must `error(...)`; a genuine relaxation gap must NOT `error(...)` (see EXACT-03 above — this is the one place in the project where "fail loudly" does NOT mean "throw").

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Ipopt | 1.15.0 (existing main dep — `[deps]`/`[compat]` in `Project.toml`, unchanged) | Nonconvex NLP backend for the AC-OPF oracle | Already wired behind `select_optimizer(NLP())` (`src/solver/factory.jl:66`); the missing piece for this phase is a JuMP *formulation*, not a solver `[VERIFIED: npm registry — n/a, verified directly against Project.toml and factory.jl in this repo]`. |
| JuMP | 1.30.1 (existing main dep, unchanged) | Model-building layer for `ACPowerFlow.contribute!` | Same modeling layer as every other formulation; a bilinear/quadratic equality (`l*v == P^2+Q^2`) and quadratic inequality (`P^2+Q^2 <= smax^2`) are both plain `@constraint` scalar-quadratic constraints — no cone macro, no bridge needed for Ipopt (confirmed: the existing `RSOCtoNonConvexQuadBridge`/`SOCtoNonConvexQuadBridge` registered in `welfare_solve.jl:130-131` exist PRECISELY to turn a `RotatedSecondOrderCone`/`SecondOrderCone` constraint into this same scalar-quadratic form for Ipopt — `ACPowerFlow` writes that scalar-quadratic form directly, so it needs neither the cone macro nor the bridge). |

**No new packages.** `[VERIFIED: Project.toml + src/solver/factory.jl, read directly this session]` — Ipopt, JuMP, HiGHS, Clarabel are all already `[deps]`; nothing in this phase touches `Project.toml`.

### Supporting
None new. `DataFrames.jl` (existing dep) is a reasonable, idiomatic return type for `assert_ac_exact!`'s per-hour report table (the project already uses it for tabular result collation elsewhere), but a plain `Vector{NamedTuple}` is equally acceptable and avoids adding a DataFrames dependency to a file that might otherwise not need one — planner's discretion.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled branch-flow AC equality model (mirrors `ConvexBranchFlow`, no angle variables in-model) | Bus-injection polar/rectangular AC-OPF with explicit `θ_j`/`(e_j,f_j)` JuMP variables (the project's own pre-existing STACK.md research explicitly floats this as "Stack Patterns by Variant") | The bus-injection variant is the textbook "true AC-OPF" shape and puts angle recovery INSIDE the solve (no post-processing needed) — but it requires either (a) re-deriving nodal net injections as fixed constants from the SOCP solve (a "feasibility check," not an "optimality check" — see FEATURES.md's explicit distinction), which does NOT dispatch through `solve_welfare` unchanged and does not let Ipopt independently re-optimize device dispatch, or (b) building a second, parallel aggregator-injection assembly path duplicating `Aggregator.contribute!`. The branch-flow-equality variant is recommended PRIMARILY because it is the only one that satisfies the phase's own stated constraint verbatim ("dispatched through the existing `solve_welfare` entrypoint unchanged") with zero new assembly code — see Roadmap phase-15 Success Criterion 1's exact wording. |
| Ipopt-only AC-OPF oracle | PowerModels.jl `ACPPowerModel` / PMD `ACPUPowerModel` as the independent oracle | Rejected as the default (CLAUDE.md, STACK.md, this session's independent reading all converge): PowerModels'/PMD's generator/bus/branch data model doesn't map onto this project's aggregator-driven net nodal injections without a translation layer that defeats the point of an oracle whose entire value is per-branch traceability to thesis eqs. 3.31-3.39. Usable later as a cheap secondary no-DER-baseline smoke-check, never the primary certification path. |
| Single re-solve, best-effort | Multi-start Ipopt (≥2-3 initializations, including the SOCP solution as a warm start) | Nonconvex AC-OPF is not guaranteed global from a single Ipopt run; a single-start comparison risks reporting a false "gap" that is actually Ipopt local-optimum sensitivity, not a relaxation failure (FEATURES.md Capability A point 4, PITFALLS.md Pitfall 1 item 1). Recommended as a MUST-have guard, not a nice-to-have, given how load-bearing "certified exact" is as a claim. |

**Installation:** none — no `Pkg.add` needed for this phase.

**Version verification:** `Ipopt 1.15.0` / `JuMP 1.30.1` confirmed directly against the checked-in `Project.toml` `[compat]` section and `src/solver/factory.jl` this session (not re-queried against the registry — unnecessary, since nothing changes).

## Package Legitimacy Audit

**Not applicable — this phase installs zero external packages.** No `slopcheck`/registry verification was run because there is nothing to verify: Ipopt, JuMP, HiGHS, Clarabel are pre-existing `[deps]` in `Project.toml`, confirmed present by direct inspection this session.

## Architecture Patterns

### System Architecture Diagram

```
                    ┌─────────────────────────────────────────────┐
                    │  feeder, aggregators, λ₀, T, allow_export    │
                    │  (SAME inputs for both solves — the         │
                    │   "same operating point" contract)           │
                    └───────────────┬───────────────┬─────────────┘
                                    │                │
                     pf = ConvexBranchFlow()   pf = ACPowerFlow()   <- NEW peer subtype
                                    │                │
                                    ▼                ▼
                       ┌─────────────────────────────────────────┐
                       │      solve_welfare(feeder, pf, aggs;     │   <- UNCHANGED entrypoint
                       │        λ₀, T, optimizer, allow_local,    │      (dispatches by trait:
                       │        allow_export)                     │       problem_class(pf))
                       └───────────────┬───────────┬───────────────┘
                                       │           │
                         SOCP (Clarabel,     NLP (Ipopt,
                         cone inequality,    equality l·v=P²+Q²,
                         assert_solved!      assert_solved!
                         allow_local=false)  allow_local=true)
                                       │           │
                                       ▼           ▼
                              ctx_socp        ctx_ac
                     (pf_vars: v,v̂,P,Q,l) (pf_vars: v,P,Q,l — no v̂)
                                       │           │
                                       └─────┬─────┘
                                             ▼
                          ┌──────────────────────────────────────┐
                          │  assert_ac_exact!(ctx_socp, ctx_ac;   │   <- NEW, src/models/ac_oracle.jl
                          │    atol, rtol)                        │      peer to assert_socp_exact!
                          │  -> per-hour report (obj/v/P/Q gaps)  │      but NEVER throws on a
                          │     NEVER a single pass/fail bool     │      genuine gap (EXACT-03)
                          └──────────────────┬────────────────────┘
                                             ▼
                          ┌──────────────────────────────────────┐
                          │  recover_voltage_angles(ctx)          │   <- NEW, post-processing only,
                          │  (BFS from root, complex phasor       │      no new JuMP variable,
                          │   recursion V_j = V_i - z·conj(S)/    │      validated on 2-bus fixture
                          │   conj(V_i))                          │      FIRST (STATE.md flag)
                          └──────────────────┬────────────────────┘
                                             ▼
                          docs/literate/ac_oracle.jl (executed live by Documenter;
                          reports exact/inexact result beside thesis equations)
```

### Recommended Project Structure
```
src/
├── powerflow/
│   ├── ConvexBranchFlow.jl     # existing — UNCHANGED
│   └── ACPowerFlow.jl          # NEW — peer AbstractPowerFlow subtype (this phase)
├── models/
│   ├── exactness.jl            # existing — UNCHANGED (assert_socp_exact!)
│   ├── welfare_solve.jl        # existing — UNCHANGED (solve_welfare)
│   ├── oracle.jl               # existing — UNCHANGED (operational_oracle)
│   └── ac_oracle.jl            # NEW — assert_ac_exact! + recover_voltage_angles (this phase)
test/
├── test_convex_branch_flow.jl  # existing — pattern to mirror
├── test_exactness.jl           # existing — pattern to mirror (throw-vs-report divergence!)
├── test_ac_powerflow.jl        # NEW — contribute!-level unit tests
├── test_ac_oracle.jl           # NEW — solve_welfare + assert_ac_exact! + angle-recovery tests
└── fixtures_phase4.jl          # existing — extend with a stress `pv_scale` variant, OR add
                                 #            a Phase-15-owned fixtures module (planner's call)
docs/
├── make.jl                     # existing — add "ac_oracle.jl" to literate tuple + pages list
└── literate/
    └── ac_oracle.jl             # NEW — literate rung page
```

### Pattern 1: Peer `AbstractPowerFlow` subtype, contract-identical to `ConvexBranchFlow`
**What:** `ACPowerFlow <: AbstractPowerFlow` implements `contribute!(::ACPowerFlow, ctx, feeder; T)`
writing the SAME variable names (`v`, `P`, `Q`, `l`) into the SAME `ctx.residuals[:Rp]`/`[:Rq]`
seam, so `assert_ac_exact!` can index both solved contexts identically by variable name.
**When to use:** Any time a formulation needs to be a genuine drop-in swap for `ConvexBranchFlow`
through `solve_welfare`.
**Example (differences from `ConvexBranchFlow.contribute!`, `src/powerflow/ConvexBranchFlow.jl:116-234`):**
```julia
# Source: mirrors src/powerflow/ConvexBranchFlow.jl (this session, read in full)
function contribute!(::ACPowerFlow, ctx::ModelContext, feeder; T::Int = 1)
    m = ctx.model
    B = feeder.branches
    N = length(feeder.buses)
    nB = length(B)

    @variable(m, v[j = 1:N, t = 1:T])          # |V_j|^2 — SAME name as ConvexBranchFlow
    # NO v̂ — the exactness copy exists only to force a RELAXED inequality tight;
    # there is nothing to force when the cone is already an equality.
    @variable(m, P[b = 1:nB, t = 1:T])
    @variable(m, Q[b = 1:nB, t = 1:T])
    @variable(m, l[b = 1:nB, t = 1:T] >= 0)

    fix.(v[feeder.root, :], 1.0; force = true)
    for j in 1:N, t in 1:T
        j == feeder.root && continue
        vb = feeder.buses[j]
        set_lower_bound(v[j, t], vb.vmin^2)
        set_upper_bound(v[j, t], vb.vmax^2)
    end

    # thesis 3.34 UNRELAXED: nonconvex EQUALITY, not the rotated-SOC inequality (3.39).
    # This is a plain scalar quadratic constraint (l*v is bilinear, P^2+Q^2 is quadratic) —
    # JuMP builds it as a ScalarQuadraticFunction-in-EqualTo(0.0) MOI constraint, which
    # Ipopt's MOI wrapper accepts NATIVELY (no cone, no bridge needed — this is exactly the
    # form the project's existing SOCtoNonConvexQuadBridge/RSOCtoNonConvexQuadBridge already
    # reformulate a RELAXED cone INTO for Ipopt; ACPowerFlow writes it directly).
    @constraint(
        m, cone[b = 1:nB, t = 1:T],
        l[b, t] * v[B[b].from, t] == P[b, t]^2 + Q[b, t]^2,
    )
    register_constraint!(ctx, :cone, cone)

    # thesis 3.33 — TRUE voltage drop, IDENTICAL to ConvexBranchFlow (unaffected by the cone
    # relaxation choice — this equation is exact either way).
    @constraint(
        m, vdrop[b = 1:nB, t = 1:T],
        v[B[b].to, t] == v[B[b].from, t]
                          - 2 * (B[b].r * P[b, t] + B[b].x * Q[b, t])
                          + (B[b].r^2 + B[b].x^2) * l[b, t],
    )
    register_constraint!(ctx, :vdrop, vdrop)

    # thesis 3.36 — apparent-power limit. A CONVEX quadratic inequality (a disk); write it
    # directly as a scalar constraint (no SecondOrderCone macro — Ipopt takes it natively).
    @constraint(
        m, smax[b = 1:nB, t = 1:T; B[b].smax < _SMAX_NO_LIMIT],
        P[b, t]^2 + Q[b, t]^2 <= B[b].smax^2,
    )
    register_constraint!(ctx, :smax, smax)

    # :Rp/:Rq accumulation — IDENTICAL to ConvexBranchFlow (same loss-at-child convention).
    for j in 1:N, t in 1:T
        pin = sum(P[b, t] - br.r * l[b, t] for (b, br) in enumerate(B) if br.to == j; init = 0.0)
        pout = sum(P[b, t] for (b, br) in enumerate(B) if br.from == j; init = 0.0)
        add_to_residual!(ctx, :Rp, j, t, pin - pout)
        qin = sum(Q[b, t] - br.x * l[b, t] for (b, br) in enumerate(B) if br.to == j; init = 0.0)
        qout = sum(Q[b, t] for (b, br) in enumerate(B) if br.from == j; init = 0.0)
        add_to_residual!(ctx, :Rq, j, t, qin - qout)
    end

    # SAME key names as ConvexBranchFlow (minus v̂) so assert_ac_exact! can index both
    # solved ctxs identically. NOTE: because :l IS present, solve_welfare's OWN
    # `haskey(ctx.meta[:pf_vars], :l)` gate will ALSO fire assert_socp_exact! on this ctx —
    # harmlessly: the cone is already an equality by construction, so the reported residual
    # is ~0 (a free, incidental self-consistency check, not a bug — document this in the
    # docstring so a future reader doesn't "fix" it).
    ctx.meta[:pf_vars] = (; v, P, Q, l)
    return ctx
end

problem_class(::ACPowerFlow) = NLP()   # defined HERE, mirrors ConvexBranchFlow's own SOCP() line
```

### Pattern 2: Dispatch through `solve_welfare` unchanged (EXACT-01's literal wording)
**What:** The AC oracle is invoked with the EXACT same call shape as any other formulation —
only `pf` and the solver-routing kwargs change.
**When to use:** Whenever comparing SOCP vs AC on "the same operating point" (same problem
DATA — feeder, aggregators, λ₀, T, allow_export — each solver independently finds its own optimum;
this is the "optimality check" mode FEATURES.md's own literature review calls the headline claim,
as distinct from a "feasibility check" that fixes injections and only re-solves power flow).
```julia
# Source: mirrors the EXISTING cross-solver-check pattern in test_ieee13.jl:155-170 and
# test_welfare_solve.jl:71-83, but with a GENUINELY independent formulation instead of the
# SAME relaxed cone bridged to Ipopt.
ctx_socp, cost_socp, dadp_socp = solve_welfare(
    feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ₀, allow_export = true,
)

ctx_ac, cost_ac, dadp_ac = solve_welfare(
    feeder, ACPowerFlow(), aggs; T = T, λ₀ = λ₀,
    optimizer = select_optimizer(NLP()),   # Ipopt — problem_class(ACPowerFlow()) already says NLP()
    allow_local = true,                    # Ipopt reports LOCALLY_SOLVED, not OPTIMAL (nonconvex)
    allow_export = true,                   # MUST match the SOCP call's allow_export exactly
)

report = assert_ac_exact!(ctx_socp, ctx_ac; rtol = 1e-4, atol = 1e-6)
```
Note `optimizer = select_optimizer(problem_class(pf))` is `solve_welfare`'s OWN default
(`src/models/welfare_solve.jl:105`), so passing `optimizer` explicitly above is actually
redundant once `problem_class(::ACPowerFlow) = NLP()` is defined — included here only for
clarity; the planner may omit it.

### Pattern 3: Report, don't throw — `assert_ac_exact!`'s divergence from `assert_socp_exact!`
**What:** `assert_socp_exact!` (`src/models/exactness.jl:78-107`) computes ONE scalar `maxratio`
and `error(...)`s if it exceeds 1 — a REFUSAL gate (the SOCP solve's own duals are meaningless if
its cone is strict, so prices must never be returned). `assert_ac_exact!` compares TWO independent,
individually-trusted solves; a disagreement between them is not a "refuse this data" situation —
it may be the textbook high-PV/reverse-flow SOC exactness failure the literature predicts (Farivar &
Low 2013; Gan, Li, Topcu & Low 2015), which is exactly the finding EXACT-04's stress fixture is
DESIGNED to surface.
**When to use:** Any comparison gate whose failure mode is "investigate," not "refuse."
```julia
# Illustrative signature and return shape — not verified against an implementation (none exists
# yet); this is the RESEARCH-recommended contract synthesizing EXACT-02/03 and the project's own
# atol+rtol idiom (assert_socp_exact!, WR-01).
function assert_ac_exact!(
    ctx_socp::ModelContext, ctx_ac::ModelContext;
    rtol::Real = 1e-4, atol::Real = 1e-6,
)
    T = ctx_socp.meta[:T]
    T == ctx_ac.meta[:T] || error("assert_ac_exact!: T mismatch ($T vs $(ctx_ac.meta[:T])) — " *
        "the two solves are not the same operating point")   # structural mismatch: OK to throw

    pv_s, pv_a = ctx_socp.meta[:pf_vars], ctx_ac.meta[:pf_vars]
    N, nB = length(pv_s.v[:, 1]), length(pv_s.P[:, 1])

    rows = NamedTuple[]
    for t in 1:T
        vgap = maximum(abs(value(pv_s.v[j, t]) - value(pv_a.v[j, t])) for j in 1:N)
        pgap = maximum(abs(value(pv_s.P[b, t]) - value(pv_a.P[b, t])) for b in 1:nB)
        qgap = maximum(abs(value(pv_s.Q[b, t]) - value(pv_a.Q[b, t])) for b in 1:nB)
        vmag = maximum(abs(value(pv_s.v[j, t])) for j in 1:N)
        pmag = maximum(abs(value(pv_s.P[b, t])) for b in 1:nB)
        exact = vgap <= atol + rtol * vmag && pgap <= atol + rtol * pmag
        push!(rows, (; t, vgap, pgap, qgap, exact))
    end
    obj_gap = objective_value(ctx_socp.model) - objective_value(ctx_ac.model)
    # NEVER throw here on a genuine per-hour gap (EXACT-03) — return the full report so the
    # CALLER investigates reverse-flow/voltage-binding state before touching any tolerance.
    return (; obj_gap, hours = rows)
end
```

### Pattern 4: Voltage-angle recovery on a radial network (post-processing, no new JuMP variable)
**What:** The SOCP model (and the AC oracle above, by design) carries only the SQUARED voltage
magnitude `v = |V|²` — no angle. Recovering the true complex phasor `V_j` from a solved
`(P, Q, v, l)` point is the standard Baran-Wu branch-current recursion, walked from the root
outward:

```math
S_{ij} = P_{ij} + jQ_{ij} \qquad I_{ij} = \overline{S_{ij}/V_i} \qquad V_j = V_i - z_{ij} I_{ij}
```
i.e. `V_j = V_i - (r_ij + j x_ij) * conj(P_ij - j Q_ij) / conj(V_i)`, seeded at the root with
`V_root = sqrt(v_root) ∠ 0°` (the reference angle). This is EXACT on a radial network at a point
where `l_ij·v_i = P_ij² + Q_ij²` holds (i.e. at the AC oracle's own solved point, or at an SOCP
point the cone gate certified tight) — it reproduces `|V_j|² = v_j` and is the standard derivation
underlying the true (non-relaxed) DistFlow voltage-drop equation (thesis 3.33) itself.
`[ASSUMED — standard Baran & Wu 1989 branch-flow derivation, textbook/training-data knowledge, NOT
independently re-verified against a citable page this session; MUST be validated numerically on the
2-bus fixture per STATE.md's own flag before trusting it on IEEE-13/123.]`
```julia
# Illustrative — not verified against an implementation (none exists yet). BFS-general (does
# NOT assume `feeder.branches` is pre-sorted parent-before-child — `assert_radial`
# (src/data/topology.jl) only guarantees a tree, not a topological branch ordering).
function recover_voltage_angles(ctx::ModelContext)
    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]
    pv = ctx.meta[:pf_vars]
    N = length(feeder.buses)

    # Build a root->child adjacency (branch index + direction) via BFS, independent of the
    # branches array's storage order.
    children = [Tuple{Int,Int}[] for _ in 1:N]   # bus -> [(child_bus, branch_idx), ...]
    for (b, br) in enumerate(feeder.branches)
        push!(children[br.from], (br.to, b))
        push!(children[br.to], (br.from, -b))     # traverse the OTHER direction if needed
    end

    Vphasor = Matrix{ComplexF64}(undef, N, T)
    for t in 1:T
        Vphasor[feeder.root, t] = sqrt(value(pv.v[feeder.root, t]))   # angle = 0 reference
        visited = falses(N); visited[feeder.root] = true
        queue = [feeder.root]
        while !isempty(queue)
            i = popfirst!(queue)
            for (j, bsigned) in children[i]
                visited[j] && continue
                b = abs(bsigned)
                br = feeder.branches[b]
                z = Complex(br.r, br.x)
                # bsigned > 0: i->j is the branch's OWN (from,to) direction; else flip S's sign.
                S = bsigned > 0 ? Complex(value(pv.P[b, t]), value(pv.Q[b, t])) :
                                  -Complex(value(pv.P[b, t]), value(pv.Q[b, t]))
                Vphasor[j, t] = Vphasor[i, t] - z * conj(S) / conj(Vphasor[i, t])
                visited[j] = true
                push!(queue, j)
            end
        end
    end
    return Vphasor
end
```
**Validation-first requirement (STATE.md flag, PITFALLS.md Pitfall 1 item 4):** before trusting
this on IEEE-13/123, hand-derive the expected phasor on the SAME 2-bus, single-branch fixture
already used throughout `test_convex_branch_flow.jl`/`test_exactness.jl`
(`Bus(1,0.95,1.05,true), Bus(2,0.95,1.05,false)`, `Branch(1,2,0.01,0.02,10.0)`) at a fixed,
hand-computable `(P,Q)` and confirm `|Vphasor[2,t]|² ≈ v[2,t]` AND the angle satisfies the
small-angle sanity identity `θ_2 ≈ -(x·P - r·Q)` (radians, per-unit) that PITFALLS.md's own
warning-signs list names.

### Anti-Patterns to Avoid
- **Treating `assert_ac_exact!` as a refusal gate (throwing on disagreement):** this is the single
  most important design divergence from `assert_socp_exact!` — see EXACT-03 and Pattern 3 above. A
  planner that copies `assert_socp_exact!`'s `error(...)`-on-violation shape verbatim will silently
  suppress exactly the finding this phase exists to surface.
- **Building a fresh/re-sampled scenario for the AC solve:** the AC oracle MUST consume the
  identical `feeder`/`aggregators`/`λ₀`/`T`/`allow_export` the SOCP call used — any drift (a
  different seed, a different `allow_export`, a rebuilt aggregator list) makes the two models solve
  DIFFERENT problems that happen to look similar, and any resulting "gap" is uninformative
  (PITFALLS.md Pitfall 1 item 2).
- **Single-start Ipopt with no local-optimum guard:** nonconvex AC-OPF is not globally solved by a
  single Ipopt run; report the best of ≥2 starts (a flat/default start plus a warm start AT the
  SOCP solution) and flag if they disagree (a local-optimum finding in its own right, distinct from
  an exactness finding).
- **Fixing a units/per-unit bug in the ORACLE and calling it a relaxation fix:** `ACPowerFlow` must
  use `v = |V|²` (same convention as `ConvexBranchFlow`), not `v = |V|` — a natural place to
  reintroduce a `V_base²`/`S_base` mismatch precisely because it is new code (PITFALLS.md Pitfall 1
  item 3). Assert the same magnitude bands (`v ∈ [vmin², vmax²]`) on the AC solve's own output
  BEFORE ever comparing it to the SOCP solve.
- **Building the oracle on PowerModels(Distribution):** ruled out by CLAUDE.md and independently by
  this milestone's own prior STACK.md research — the aggregator-driven net-injection data model
  doesn't map onto PM's generator/bus/branch template without a translation layer that defeats the
  oracle's traceability purpose.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Nonconvex NLP solving | A bespoke Newton-Raphson/forward-backward-sweep AC power-flow solver | Ipopt via `select_optimizer(NLP())` (already wired) | Ipopt is an already-validated, already-available interior-point NLP solver; a hand-rolled solver is explicit scope creep against the project's own "clarity over premature optimization" constraint and FEATURES.md's own anti-feature list. |
| Comparison tolerance philosophy | A new, ad-hoc absolute-only threshold | The SAME `atol + rtol·max(|lhs|,|rhs|)` scale-free idiom `assert_socp_exact!` already established (WR-01) | Reinventing the tolerance style risks the exact scale-dependence hazard `assert_socp_exact!`'s own docstring already documents fixing once; one philosophy, reused, is more defensible and easier to review. |
| Symmetric-component / Kron reduction machinery | N/A for this phase (that is Phase 17's concern) | N/A | Out of scope — flagged only so the planner does not conflate Phase 15's AC-OPF oracle with Phase 17's OpenDSS impedance reduction; they are unrelated except for both touching "AC" in the name. |

**Key insight:** every piece of new machinery this phase needs (NLP solving, tolerance philosophy,
radial-tree traversal) already has an established, tested, reusable answer somewhere else in this
codebase (`solver/factory.jl`, `models/exactness.jl`, `data/topology.jl`'s BFS respectively) — the
work is almost entirely composition, not invention, with the ONE genuinely new piece being the
angle-recovery formula (Pattern 4), which is why it is called out explicitly by name in
`.planning/STATE.md`.

## Common Pitfalls

### Pitfall 1: `assert_ac_exact!` copies `assert_socp_exact!`'s throw-on-failure shape
**What goes wrong:** A planner/implementer builds `assert_ac_exact!` as a mechanical copy of
`assert_socp_exact!` — computes one ratio, `error(...)`s past a threshold — and the phase's entire
point (surfacing a genuine relaxation gap as a first-class, investigated finding, EXACT-03) is
silently defeated the moment any high-PV hour disagrees even slightly.
**Why it happens:** `assert_socp_exact!` is the ONLY existing precedent in this codebase for a
post-solve numerical certificate; its "peer" framing (EXACT-02's own wording) invites literal
imitation of its throw behavior, not just its tolerance philosophy.
**How to avoid:** Design `assert_ac_exact!` to return a per-hour report structure (Pattern 3) and
reserve `error(...)` for STRUCTURAL mismatches only (different `T`, different feeder/bus count,
`ctx.meta[:pf_vars]` missing a key) — never for a numerical disagreement, however large.
**Warning signs:** Any test asserting `@test_throws Exception assert_ac_exact!(...)` on a
HIGH-PV/inexact fixture (as opposed to `@test_throws` on a structural-mismatch fixture) is a signal
the design has drifted toward the wrong shape.

### Pitfall 2: Ipopt local-optimum artifact reported as a relaxation gap
**What goes wrong:** A single Ipopt run from a default start converges to a locally-optimal (not
globally-optimal) AC-OPF point; the "gap" against the SOCP solution is then measuring Ipopt's
initialization sensitivity, not the SOCP relaxation's exactness.
**Why it happens:** Every other solver in this project (Clarabel for QP/SOCP, HiGHS for LP/MILP) is
globally optimal by convexity — there is no existing local-optimum instinct anywhere else in the
codebase to draw on.
**How to avoid:** Multi-start Ipopt (≥2 starts: a default/flat start, and a warm start AT the SOCP
solution — natural since it should already be near-global if exactness holds); report the
best-objective (highest-welfare) result found, and separately flag if different starts land on
materially different objectives (a local-optimum finding in its own right).
**Warning signs:** AC-OPF objective value that changes materially between repeated Ipopt runs on
identical data.

### Pitfall 3: The two solves quietly diverge on problem data (`allow_export`, seed, aggregator population)
**What goes wrong:** The AC oracle is assembled from a re-derived or re-sampled `feeder`/
`aggregators` rather than literally the SAME objects the SOCP call used; the resulting "gap"
reflects a data mismatch, not a relaxation property.
**Why it happens:** It is tempting to build the AC-side call independently (e.g., in a separate test
item) rather than threading the exact same fixture-construction call through both solves.
**How to avoid:** Write both `solve_welfare` calls back-to-back from the SAME local variables
(`feeder`, `aggs`, `λ₀`, `T`, `allow_export`) in the same test/literate scope — never rebuild either
side independently. `allow_export` in particular must match: the high-PV fixture is INFEASIBLE at
`allow_export=false` (per `Phase4Fixtures.high_pv_feeder`'s own existing usage in
`test_exactness.jl:159-167`), so a mismatched default would make the AC call fail for reasons
unrelated to exactness.
**Warning signs:** The AC oracle solve throws (INFEASIBLE / not `LOCALLY_SOLVED`) rather than
reporting a numeric gap — check for a data mismatch before assuming the AC formulation itself is
wrong.

### Pitfall 4: A genuine SOCP inexactness under high-PV gets tolerance-adjusted away
**What goes wrong:** The stress fixture (EXACT-04) genuinely disagrees at the pinned-voltage hour;
the fix applied is "loosen `rtol`/`atol` until it passes" rather than investigating whether reverse
flow and a binding upper voltage bound are present at that hour.
**Why it happens:** Loosening a tolerance is a one-line green-CI fix; diagnosing genuine physical
inexactness (checking reverse power flow, checking whether `v[j,t]` is AT `V²max`) is more work, and
there is no existing fixture in the test suite where the relaxation is KNOWN to fail, so there is no
local precedent distinguishing "genuine" from "comparison bug."
**How to avoid:** Before touching any tolerance on a disagreeing hour, check: (1) is there reverse
(net-injection, `P<0`) flow at any bus that hour; (2) is `v[j,t]` at or near `vmax²`? If YES to
either, treat the disagreement as a CANDIDATE genuine inexactness and document it (this is a
citable milestone finding, not a bug) rather than adjusting `rtol`/`atol`.
**Warning signs:** A "fix" that changes only a numeric tolerance constant with no accompanying
investigation note; a milestone report claiming "100% exact" with the high-PV stress fixture never
actually exercised at a genuinely-pinned voltage.

### Pitfall 5: Per-unit/units mismatch reintroduced in the new AC model
**What goes wrong:** `ACPowerFlow` accidentally uses `v = |V|` instead of `v = |V|²` (or a
different `S_base`/`V_base`), producing a clean multiplicative-factor "gap" that looks like a
relaxation failure but is a units bug in the new code.
**Why it happens:** It's new code, and the SQUARED-voltage convention (`Pitfall 1` in
`ConvexBranchFlow.jl`'s own docstring: "off-by-square voltage") is exactly the kind of easy-to-forget
convention a from-scratch model reintroduces.
**How to avoid:** Assert `v[j,t] ∈ [vmin²,vmax²]` on the AC solve's OWN output before ever comparing
to the SOCP solve; mirror `ConvexBranchFlow.jl`'s variable-naming and bound-setting code verbatim
(Pattern 1) rather than re-deriving it independently.

## Code Examples

### Full end-to-end comparison shape (illustrative — synthesizes Patterns 1-3, none of this exists yet)
```julia
# Source: synthesized from src/models/welfare_solve.jl (read in full), src/powerflow/
# ConvexBranchFlow.jl (read in full), and test/test_exactness.jl (read in full) — this
# exact composition is not yet implemented anywhere in the repo.
using TSODSO, JuMP

feeder = Phase4Fixtures.high_pv_feeder()
aggs   = Phase4Fixtures.build_high_pv_aggregators(feeder; pv_scale = 1.5)  # STRESS variant
λ₀     = Phase4Fixtures.mem_price_profile()

ctx_socp, cost_socp, _ = solve_welfare(
    feeder, ConvexBranchFlow(), aggs; T = Phase4Fixtures.T, λ₀ = λ₀, allow_export = true,
)
ctx_ac, cost_ac, _ = solve_welfare(
    feeder, ACPowerFlow(), aggs; T = Phase4Fixtures.T, λ₀ = λ₀,
    allow_local = true, allow_export = true,
)

report = assert_ac_exact!(ctx_socp, ctx_ac; rtol = 1e-4, atol = 1e-6)
inexact_hours = [row.t for row in report.hours if !row.exact]
# `inexact_hours` non-empty at the pinned-voltage stress point is the EXPECTED, documented
# finding (Pitfall 4 above) — write it up in docs/literate/ac_oracle.jl, do not suppress it.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Re-solve the SAME relaxed SOCP cone through Ipopt via `RSOCtoNonConvexQuadBridge`/`SOCtoNonConvexQuadBridge` (existing, `test_ieee13.jl:155-170`, `test_welfare_solve.jl:71-83`) | An independently-formulated nonconvex AC equality model (`ACPowerFlow`) | This phase (v2.1 Phase 15) | The existing check only certifies "a different solver enforces the same inequality" — it cannot detect a genuine relaxation gap because the model being solved is, by construction, the same relaxed feasible set. The new oracle enforces the true unrelaxed physics, so a disagreement is now meaningful. |

**Deprecated/outdated:** The existing bridge-based cross-check (`RSOCtoNonConvexQuadBridge`/
`SOCtoNonConvexQuadBridge` re-solve) is NOT deprecated by this phase — it remains a valid, cheap
"does a different solver agree on the SAME relaxed model" sanity check and should stay in place
(`test_ieee13.jl`, `test_welfare_solve.jl` are unaffected by this phase). It is simply no longer
sufficient on its own as an exactness CERTIFICATION, which is exactly the gap this phase closes.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The Baran-Wu branch-current phasor recursion `V_j = V_i - z_ij·conj(S_ij)/conj(V_i)` exactly recovers voltage phasors on a radial network at a point satisfying the branch-flow equations | Architecture Patterns, Pattern 4 | If the formula has a sign/conjugate error, angle-recovery output is silently wrong; the 2-bus validation-first requirement is the designed mitigation — if that validation fails, the formula (not the fixture) is the first suspect. |
| A2 | `l*v == P^2+Q^2` and `P^2+Q^2 <= smax^2` are accepted by Ipopt's MOI wrapper as plain `ScalarQuadraticFunction`-in-`{EqualTo,LessThan}` constraints without needing the `RSOCtoNonConvexQuadBridge`/`SOCtoNonConvexQuadBridge` (inferred from the fact that those bridges' documented OUTPUT is exactly this scalar-quadratic form — `src/models/welfare_solve.jl:119-131` comments — but not independently confirmed by running Ipopt against this exact constraint shape this session) | Architecture Patterns, Standard Stack | If Ipopt's MOI wrapper actually requires the bridge machinery even for a directly-written scalar quadratic constraint, `ACPowerFlow` would need to also register the bridges (harmless if unnecessary, but should be verified empirically in the first implementation plan rather than assumed). |
| A3 | "Same operating point" (EXACT-01's wording) is satisfied by passing the SAME `feeder`/`aggregators`/`λ₀`/`T`/`allow_export` to both `solve_welfare` calls (the "optimality check" mode), rather than requiring the AC solve to consume FIXED, pinned dispatch values from the SOCP's own solved primal (the "feasibility check" mode STACK.md's prior research also floats) | Standard Stack (Alternatives Considered), Architecture Patterns Pattern 2 | If the phase's actual intent is the feasibility-check (fixed-injection) mode, the recommended design here under-delivers on independence (Ipopt re-optimizes device dispatch too) — but it is the only mode literally consistent with "dispatched through solve_welfare unchanged" (Roadmap SC1's exact wording), which is why it is the primary recommendation. Flag for discuss-phase/planning confirmation if there is any doubt. |

**If this table is empty:** N/A — see rows above.

## Open Questions

1. **Fixture ownership: extend `test/fixtures_phase4.jl` or add a new Phase-15 fixtures module?**
   - What we know: `Phase4Fixtures.high_pv_feeder`/`build_high_pv_aggregators` already have the
     exact `pv_scale` knob needed for the stress fixture (EXACT-04), calibrated at `pv_scale=0.5`
     for the currently-exact case.
   - What's unclear: whether the project convention (one `@testmodule` per originating phase, e.g.
     `Phase4Fixtures`, `Phase7Fixtures`) means a NEW `Phase15Fixtures` module should wrap/extend the
     existing one, or whether extending `Phase4Fixtures` directly (adding a `pv_scale` kwarg
     passthrough, which already exists) is idiomatic.
   - Recommendation: extend `Phase4Fixtures.build_high_pv_aggregators`'s existing `pv_scale` kwarg
     call site (it is ALREADY parametrized — no new fixture code needed, just a different call with
     `pv_scale` tuned higher, e.g. 1.0-2.0) rather than adding a new fixtures module; confirm the
     exact scale value empirically (the one that pins `v[j,t]` at `vmax²` for THIS feeder) during
     implementation rather than guessing a number here.

2. **`assert_ac_exact!` return type: `Vector{NamedTuple}` or `DataFrame`?**
   - What we know: `DataFrames.jl` is an existing project dependency, used for tabular result
     collation elsewhere; a plain `Vector{NamedTuple}` needs no import and is equally inspectable.
   - What's unclear: no existing project convention definitively favors one over the other for a
     per-hour report table specifically (as opposed to sweep/scenario collation, where DataFrames is
     clearly used).
   - Recommendation: planner's/implementer's discretion; either satisfies EXACT-02/03's requirement
     of "a table, never a single boolean."

3. **Does `ACPowerFlow` need its own `docs/literate/ac_oracle.jl` methodology note citing Farivar-Low
   / Gan-Li-Topcu-Low by name (FEATURES.md's "written methodology note" table-stakes item), or is
   documenting the equations/results sufficient?**
   - What we know: EXACT-04 requires "documented in a literate rung page beside the thesis
     equations" — this is a hard requirement already in the roadmap.
   - What's unclear: whether a citation of the underlying exactness-theory papers (not just the
     project's own thesis equations) is required for EXACT-04's bar, or optional polish.
   - Recommendation: include the citation (Farivar & Low 2013; Gan, Li, Topcu & Low 2015) — it costs
     one paragraph and directly supports the "citable finding" framing both the roadmap and
     FEATURES.md use.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Ipopt.jl | `ACPowerFlow`'s NLP solve | ✓ (confirmed `[deps]`/`[compat]` in `Project.toml`) | 1.15.0 | — |
| JuMP.jl | Model building | ✓ | 1.30.1 | — |
| Julia | Runtime | not independently re-probed this session (assumed available — this is an active, buildable checkout with `2276 tests passing` per STATE.md) | ≥1.10 (project floor) | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none — this phase needs zero new external tools.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `TestItemRunner.jl` + `TestItems.jl` (`@testitem`/`@testmodule`, existing project convention) |
| Config file | `test/runtests.jl` (`@run_package_tests`, no config file beyond this) |
| Quick run command | `julia --project -e 'using TestItemRunner, TSODSO; @run_package_tests filter=ti->occursin("ac", ti.name)'` (mirrors the project's own documented per-feature filter convention, e.g. `occursin("exact", ti.name)` in `test_exactness.jl`'s header comment) — NOTE: pick a filter substring specific enough to exclude unrelated hits (`"ac"` may over-match; `"ac_powerflow"`/`"ac_oracle"` in the `@testitem` names themselves, filtered via `occursin("ac_powerflow", ti.name)` or a dedicated tag, is safer) |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` (also what `julia-actions/julia-runtest@v1` runs in CI, `.github/workflows/CI.yml`) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| EXACT-01 | `ACPowerFlow` is a defined `AbstractPowerFlow` subtype; `contribute!` stashes `(;v,P,Q,l)`; `problem_class(::ACPowerFlow) isa NLP`; `solve_welfare(feeder, ACPowerFlow(), aggs; ..., allow_local=true)` reaches `LOCALLY_SOLVED`/`OPTIMAL` on the 2-bus fixture | unit + integration | `julia --project -e 'using TestItemRunner, TSODSO; @run_package_tests filter=ti->occursin("ac_powerflow", ti.name)'` | ❌ Wave 0 — `test/test_ac_powerflow.jl` does not exist yet |
| EXACT-02 | `assert_ac_exact!(ctx_socp, ctx_ac; atol, rtol)` returns `(; obj_gap, hours)` with per-hour `vgap`/`pgap`/`qgap`/`exact` fields, using the scale-free `atol+rtol·magnitude` idiom | unit | `julia --project -e 'using TestItemRunner, TSODSO; @run_package_tests filter=ti->occursin("ac_oracle", ti.name)'` | ❌ Wave 0 — `test/test_ac_oracle.jl` does not exist yet |
| EXACT-03 | On a KNOWN-exact fixture (e.g. the 2-bus toy or the existing `pv_scale=0.5` high-PV case), `assert_ac_exact!` reports `all(row.exact for row in report.hours)`; the function signature/return type never resolves to a `Bool` (must be inspectable per-hour) | unit | same test file as above | ❌ Wave 0 |
| EXACT-04 | On a DELIBERATELY over-scaled `pv_scale` stress fixture, `assert_ac_exact!` reports at least one hour with `exact=false`, AND the report's `t` for that hour corresponds to an hour where `v[j,t]` is at/near `vmax²` (reverse-flow/voltage-binding diagnostic) — this is a POSITIVE test (the gap is EXPECTED, not a failure to fix) | unit + literate (executed by Documenter) | test file above; `julia --project=docs docs/make.jl` (executes `docs/literate/ac_oracle.jl` live) | ❌ Wave 0 — both `test/test_ac_oracle.jl`'s stress case and `docs/literate/ac_oracle.jl` do not exist yet |

### Sampling Rate
- **Per task commit:** the relevant filtered `@run_package_tests` command above (fast — seconds on
  the 2-bus/small feeder fixtures).
- **Per wave merge:** full `Pkg.test()` (includes the IEEE-13/123 regression suite, so a new
  `ACPowerFlow` include doesn't silently break an unrelated existing item via a stray `include`-order
  issue in `TSODSO.jl`).
- **Phase gate:** full `Pkg.test()` green, PLUS `julia --project=docs docs/make.jl` succeeding (the
  literate rung page must execute live — project convention, `docs/make.jl`'s own header comment:
  "the rendered numbers cannot drift from the real `src/` code").

### Wave 0 Gaps
- [ ] `test/test_ac_powerflow.jl` — covers EXACT-01 (mirrors `test/test_convex_branch_flow.jl`'s
      structure: `isdefined` RED-guard items, then behavioral asserts once `ACPowerFlow` lands)
- [ ] `test/test_ac_oracle.jl` — covers EXACT-02/03/04 (mirrors `test/test_exactness.jl`'s
      structure, but with the throw-vs-report divergence from Pattern 3/Pitfall 1 built in from the
      start — do not copy `test_exactness.jl`'s `@test_throws` pattern for the genuine-gap case)
- [ ] `docs/literate/ac_oracle.jl` — new literate rung page (mirrors
      `docs/literate/convex_branch_flow.jl`'s style); `docs/make.jl`'s literate-source tuple and
      `pages` list both need the new entry
- [ ] Framework install: none — `TestItemRunner`/`TestItems` are already project dev-deps

## Security Domain

> `security_enforcement` is absent from `.planning/config.json` — treated as enabled per the
> instruction, but this phase is a pure numerical-research/optimization-modeling change with no
> network, auth, session, or untrusted-input surface, so ASVS applicability is uniformly low.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A — no user-facing auth surface in this codebase at all |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A |
| V5 Input Validation | Marginal | `Feeder`/`Branch`/`Bus` construction already enforces radial-topology and per-unit magnitude invariants (`assert_radial`, `assert_magnitudes`) at construction time — `ACPowerFlow.contribute!` inherits these for free by consuming the same validated `Feeder` struct; no new external/untrusted input path is introduced by this phase. |
| V6 Cryptography | No | N/A |

### Known Threat Patterns for {stack}
Not applicable — this is a local, offline, single-researcher numerical-optimization codebase with
no network-facing component; STRIDE-style threat modeling (as used for web-facing ASVS categories)
does not meaningfully apply. The project's own "threat" numbering (`T-04-01`, `T-04-12`, etc., seen
throughout `src/models/welfare_solve.jl`/`oracle.jl`) tracks CORRECTNESS threats (e.g. "a physically
meaningless dual returned as a price") rather than security threats; this phase's own correctness
threat surface is exactly EXACT-03's gate (a genuine inexactness silently suppressed) — already
covered in Common Pitfalls above, not duplicated here.

## Sources

### Primary (HIGH confidence)
- Direct source reads this session (all file paths and line numbers cited above are from files
  read in full or in relevant part during this research pass): `src/powerflow/AbstractPowerFlow.jl`,
  `src/powerflow/ConvexBranchFlow.jl`, `src/models/exactness.jl`, `src/models/welfare_solve.jl`,
  `src/models/oracle.jl`, `src/solver/ProblemClass.jl`, `src/solver/factory.jl`,
  `src/solver/problem_class_trait.jl`, `src/data/Feeder.jl`, `src/data/topology.jl`,
  `src/data/ieee13.jl`, `src/devices/Aggregator.jl`, `src/TSODSO.jl`, `Project.toml`,
  `test/test_convex_branch_flow.jl`, `test/test_exactness.jl`, `test/test_ieee13.jl`,
  `test/test_welfare_solve.jl`, `test/fixtures_phase4.jl`, `docs/make.jl`,
  `docs/literate/convex_branch_flow.jl`, `test/runtests.jl`, `.github/workflows/CI.yml`.
- `.planning/STATE.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` (v2.1 phase scope,
  Phase 15 success criteria, the angle-recovery research flag).
- `.planning/research/ARCHITECTURE.md`, `.planning/research/PITFALLS.md`,
  `.planning/research/FEATURES.md`, `.planning/research/STACK.md`, `.planning/research/SUMMARY.md`
  — a full, independent v2.1 research pass completed the same day (2026-07-25) by a prior GSD
  research session, read and cross-checked against this session's own direct source reading; treated
  as HIGH confidence where it agrees with (and is corroborated by) the live code, explicitly flagged
  where this session's own reading surfaced a design tension (Assumption A3).
- CLAUDE.md (project tech-stack prescription, read and enforced above under "Project Constraints").

### Secondary (MEDIUM confidence)
- Baran-Wu branch-flow phasor-recovery derivation (Pattern 4) — standard textbook power-systems
  result (M. E. Baran & F. F. Wu, "Optimal sizing of capacitors placed on a radial distribution
  system," IEEE Trans. Power Delivery, 1989, and the companion load-flow paper) corroborated by
  `.planning/research/PITFALLS.md`'s independent citation of the same small-angle sanity identity;
  not independently re-verified against a citable page THIS session (training-data knowledge) —
  hence tagged `[ASSUMED]` in the Assumptions Log and gated behind the 2-bus validation-first
  requirement per project policy.
- Farivar & Low 2013 ("Branch Flow Model: Relaxations and Convexification"), Gan, Li, Topcu & Low
  2015 ("Exact Convex Relaxation of Optimal Power Flow in Radial Networks") — cited via
  `.planning/research/FEATURES.md`'s literature review, not independently re-fetched this session.

### Tertiary (LOW confidence)
- None — every claim in this document traces to either a direct source-code read this session or a
  same-day prior research artifact in `.planning/research/`, itself citing named, checkable sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies; every claim verified against the checked-in
  `Project.toml` and `src/solver/factory.jl` directly.
- Architecture: HIGH on the peer-subtype/unchanged-entrypoint design (directly matches the actual
  `AbstractPowerFlow`/`solve_welfare`/`ModelContext` contracts read this session); MEDIUM on the
  exact `assert_ac_exact!` return-type/signature (illustrative, not yet implemented — planner has
  discretion within the "report, don't throw" constraint) and on the "same operating point =
  optimality check" interpretation (Assumption A3 — flagged for confirmation).
- Pitfalls: HIGH — five pitfalls sourced from a converging prior research pass PLUS this session's
  own direct reading of the exact fixture/gate code they reference (`fixtures_phase4.jl`'s own
  `pv_scale` calibration comment, `assert_socp_exact!`'s own throw semantics).

**Research date:** 2026-07-25
**Valid until:** 30 days (stable, internal-architecture research on an already-shipped, slow-moving
codebase; no external API/library surface that could drift faster than that).
</content>

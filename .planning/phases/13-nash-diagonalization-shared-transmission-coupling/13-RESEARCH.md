# Phase 13: Nash Diagonalization & Shared-Transmission Coupling - Research

**Researched:** 2026-07-23
**Domain:** Multi-leader-common-follower equilibrium computation (Gauss-Seidel diagonalization
over hand-rolled Benders best-responses); shared-resource (transmission-corridor) coupling
modeling in JuMP.
**Confidence:** MEDIUM — the diagonalization theory is well-established general literature
(HIGH confidence on the literature itself) but has **no general convergence guarantee** and
**no project-specific numerical precedent** (per STATE.md's carried blocker); the
`coupling.jl`/`nash.jl` design is a genuine research decision made in this session, not a
literature lookup, and the N-distributor cost-allocation convention is explicitly flagged
`[ASSUMED]` pending user confirmation.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Shared coupling model `coupling.jl` (NASH-01)**
- One shared transmission-reinforcement follower: all distributors' import profiles flow
  through a common corridor/reinforcement capacity. Distributor `i`'s best response sees
  `z_{-i}` **fixed** — the aggregate loading of the others enters its follower's RHS. Faithful
  to the PSR N1↔N2 interconnection-flow coupling (coupling variable = interconnection flow;
  linking price = interconnection dual).
- `z_{-i}` as JuMP `Parameter`s in the shared follower — build-once, `set_parameter_value`
  per sweep (Gauss-Seidel standard). No per-best-response rebuild of the follower model.
- API shape: `SharedTransmission` struct in `src/planning/coupling.jl` — build-once,
  per-distributor views, `update_coupling!` called after each atomic best-response.
- Test scale: N=2 baseline (hand-checkable equilibrium) + N=3 probe.

**Diagonalization loop mechanics (NASH-02/03)**
- Convergence metric: outer Nash residual = max over distributors of
  `‖z_i^(k+1) − z_i^(k)‖∞` (plus investment change). Inner Benders tolerance strictly
  tighter than the outer Nash tolerance (e.g. inner 1e-6 vs outer 1e-4) — the nesting is
  asserted in code (`ArgumentError` if violated), not just documented.
- Fresh cut store per best-response (correctness-first): optimality/feasibility cuts
  computed at old `z_{-i}` are generally invalid once neighbors move. Each atomic
  best-response starts with a clean master cut store. Instrument the rebuild cost in the
  trace; cut-reuse across sweeps is deferred until a proven validity argument exists (surface
  as a research finding, do not silently retain).
- Two-level diagnostics: purpose-built `NashTrace` — per-sweep rows embedding per-distributor
  Benders summaries (final gap, iterations, retries, cut counts) plus the outer Nash residual.
  Include one CairoMakie convergence-plot helper (criterion 3 requires "plottable"; the
  project already uses CairoMakie for publication figures).
- Guardrails: fail-loud max-sweeps cap (never silent); atomic best-response = full
  `solve_stackelberg!` convergence per distributor per sweep — no partial/inexact passes.

**Non-uniqueness probing (NASH-04)**
- Probe matrix: ≥3 seeds × 2 sweep orders (forward/reverse) as a **gating test** — every
  probe run must converge for the phase to pass.
- Asserted vs reported: convergence of all probe runs is asserted; the equilibrium spread
  (max pairwise distance in `z`, investment, and total cost across probe runs) is measured
  and REPORTED, never asserted equal across runs.
- Structural reporting language: the summary API emits "a converged equilibrium
  (spread: …)" — the never-"the"-equilibrium rule (STATE.md blocker) is encoded in code, not
  left as prose convention.

### Claude's Discretion
- Exact `SharedTransmission`/`NashTrace` field names, the corridor fixture parameterization
  for N=2/N=3 (must admit a hand-checkable N=2 equilibrium), seed values, and the plot
  helper's exact output format (PDF/SVG per thesis-grade conventions).
- How `solve_stackelberg!` is parameterized for per-distributor reuse (e.g. a
  `BestResponse` wrapper vs keyword plumbing) — keep Phase 11/12 call sites unchanged.
- Where the plotting helper lives (`src/diagnostics/` vs `src/planning/`) — follow whatever
  analog `src/diagnostics/` offers.

### Deferred Ideas (OUT OF SCOPE)
- Cut-reuse across sweeps under a proven validity argument (e.g. cuts valid globally in `z_i`
  if the follower is jointly convex in `(z_i, z_{-i})` with `z_{-i}` only in the RHS —
  research finding to surface, not implement silently).
- MCP/VI recast of the equilibrium (PLAN-MCP-01) — only if diagonalization proves unreliable.
- Integer investment (PVAL-04, continuous-only this milestone), stochastic scenarios,
  regression-hardening of validation oracles (Phase 14).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-------------------|
| NASH-01 | A shared transmission-reinforcement coupling model (`src/planning/coupling.jl`) links the distributors, giving the diagonalization loop a shared signal to iterate on. | "coupling.jl Design" (Architecture Patterns, Pattern 1) gives a concrete build-once `SharedTransmission` JuMP model (one model, N indexed `coupling[i,t]` constraints, one shared `capacity[t]` row) with a documented cost-allocation assumption flagged in the Assumptions Log. |
| NASH-02 | Gauss-Seidel diagonalization across N distributors converges to a fixed point, each distributor's Benders solve treated as an atomic best-response. | "Diagonalization Theory" (Summary + Pattern 2) documents what convergence structure this game does/does not have (aggregative-but-not-known-potential, congestion-coupled), the honest "no general guarantee" literature finding, and the nested-tolerance rationale. |
| NASH-03 | Two-level convergence diagnostics (inner Benders UB/LB gap + outer Nash residual) are reported and plottable. | "NashTrace design" (Pattern 3) mirrors `BendersTrace`'s established shape (Phase 12 precedent); "CairoMakie plotting" (Code Examples) extends `ext/TSODSOMakieExt.jl`'s established weakdep pattern. |
| NASH-04 | Nash convergence is probed across multiple seeds and sweep orders; results report "a converged equilibrium" with the observed spread, never "the" equilibrium. | "Multi-seed/multi-order probing" (Pattern 4) gives a concrete seed/order design and spread-metric definitions, directly grounded in the Hu & Ralph (2005) finding that congestion-coupled games exhibit non-unique/continuum equilibria — i.e., the probe is not a defensive formality but addresses a documented real phenomenon in this exact problem class. |
</phase_requirements>

## Summary

Phase 13 nests a **second, outer** fixed-point loop (Gauss-Seidel diagonalization across `N`
distributors) on top of the already-hardened Benders loop (Phases 11-12), coupled through a
genuinely new shared-resource model (`coupling.jl`): a single transmission/reinforcement
corridor whose aggregate loading is the sum of all distributors' delivered flows. This is a
**multi-leader-common-follower** structure (each distributor is its own Stackelberg leader;
all leaders share one follower/corridor), which the literature treats as an
Equilibrium-Problem-with-Equilibrium-Constraints (EPEC) solved by "diagonalization"
(economics literature) / "nonlinear Gauss-Seidel" (optimization literature) — cyclically
re-solving each player's bilevel best-response while holding the others fixed, until the
strategy profile stops moving.

The literature is unambiguous on one point that matches this project's own carried blocker
(STATE.md, "no general guarantee"): **diagonalization has no general convergence guarantee**,
and the failure mode is specifically correlated with **non-uniqueness of the underlying Nash
equilibrium** — exactly the situation a shared, congestible transmission corridor creates. Hu
& Ralph (2005) show analytically that a two-node network with a *congested* shared
transmission line has a **continuum of Nash equilibria** (not isolated points), while an
*uncongested* network or one with symmetric/uniform benefit functions has existence and
(generically) uniqueness. Their own numerical diagonalization experiments on games where
equilibria are locally non-unique converge in **0 of 27 problem instances** within a generous
400-iteration cap, versus reliable convergence (>96%) on games with unique equilibria. This is
the closest published analog to this phase's own corridor-congestion coupling, and it directly
justifies CONTEXT.md's NASH-04 design: the multi-seed/multi-order probe is not a formality, it
is the field's own documented substitute for a convergence proof that does not exist for this
problem class.

Practically, this means: (1) the N=2 fixture should be designed to sit **near but not at** the
congestion boundary of the corridor — congested-enough to make the coupling real (so the
phase's "shared signal to iterate on" claim is genuinely exercised) but with symmetric
distributor data so the analytically-tractable symmetric-equilibrium case (Hu & Ralph
Proposition 6/Corollary 10 analog) gives a hand-checkable target; (2) the diagonalization loop
must have a fail-loud max-sweep cap (already locked) and a damped/relaxed update as an
available remedy for cycling, even if not needed on the N=2/N=3 fixtures; (3) the honest
non-uniqueness report (NASH-04) is the project's real correctness gate, not an
afterthought — the phase should be planned so that gate is exercised, not just implemented.

**Primary recommendation:** Build `coupling.jl`'s `SharedTransmission` as **one** build-once
JuMP model holding all `N` distributors' `x_op[i,t]` variables and coupling constraints plus a
single shared `capacity[t]` row (`Σᵢ x_op[i,t] <= corridor_cap * x_inv`); expose a
per-distributor "view" that fixes every `z_j`, `j≠i`, as `Parameter`s and leaves `z_i` as the
one being driven by that distributor's own `solve_stackelberg!` Benders trial. Build `nash.jl`
as a thin outer Gauss-Seidel sweep over `N` independent, freshly-cut-stored
`solve_stackelberg!` calls, instrumented by a `NashTrace` that mirrors `BendersTrace`'s
established shape (Phase 12 precedent), with a nested-tolerance `ArgumentError` assertion and
a `run_nash_probe` driver that gates on ≥3 seeds × 2 orders all converging and reports spread,
never a single "the" equilibrium.

## Architectural Responsibility Map

> This project has no browser/API/CDN tiers — it is a single-process Julia optimization
> research framework. The table below maps capabilities to this project's own architectural
> layers (per `src/TSODSO.jl`'s include-graph and CLAUDE.md's stack).

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Shared corridor JuMP model (capacity/coupling constraints, duals) | `src/planning/coupling.jl` (new, model-building layer) | — | Owns the ONE new JuMP model this phase introduces; mirrors `follower.jl`'s build-once/`Parameter` idiom. |
| Per-distributor atomic best-response | `src/planning/benders.jl` (existing, UNCHANGED call sites) | `coupling.jl` (supplies the per-distributor follower view) | Phase 11/12 already own this; Phase 13 reuses it verbatim per CONTEXT.md's explicit "keep Phase 11/12 call sites unchanged." |
| Outer Gauss-Seidel sweep orchestration | `src/planning/nash.jl` (new, orchestration layer) | — | Mirrors `benders.jl`'s own "build subproblems once, iterate, fail-loud cap" shape one level up — an outer loop over already-validated best-response units (RESEARCH Pattern 4 precedent from `admm/solve_admm.jl`, `benders.jl`). |
| Two-level convergence ledger | `src/planning/trace.jl` (extend) or a new `nash_trace.jl` | — | `BendersTrace` is JuMP-free and purpose-built per-struct (Phase 12 precedent: "mirror shape, document what's NOT copied"); `NashTrace` should follow the same discipline as a sibling, not a subclass. |
| Multi-seed/multi-order probe + spread reporting | `src/planning/nash.jl` (driver function) | `test/test_planning_nash*.jl` (gating test) | The probe is BOTH a library-level honesty mechanism (the summary API must literally emit "a converged equilibrium... spread: ...") AND a phase-gating regression test (NASH-04's own acceptance criterion is a test, per ROADMAP.md criterion 4). |
| Two-level convergence plot | `src/diagnostics/plots.jl` (generic stub) + `ext/TSODSOMakieExt.jl` (CairoMakie method) | — | Exact precedent: `plot_convergence`/`plot_price_convergence` already follow this weakdep-extension split for `AdmmResiduals`; a `plot_nash_convergence(trace::NashTrace)` generic + Makie method is the direct analog. |
| Checkpointing per sweep/best-response | `src/planning/checkpoint.jl` (existing, reused) | — | `checkpoint_iteration!` is already generic over `state` (any `NamedTuple`); no new checkpoint primitive needed — call it once per outer sweep (or once per best-response, Claude's Discretion) with a Nash-shaped state tuple. |

## Standard Stack

### Core

No new external packages are required for this phase. Every capability builds on
already-vendored, already-pinned dependencies:

| Library | Version (pinned, Project.toml) | Purpose | Why Standard |
|---------|-------|---------|--------------|
| JuMP | 1.30.1 | `SharedTransmission`'s JuMP model, `Parameter`s for `z_{-i}` | Already the project's sole modeling layer (CLAUDE.md); `coupling.jl` is architecturally identical to `follower.jl`, just with `N` indexed coupling rows instead of 1. |
| HiGHS | 1.24.1 (`= 1.24.1` in test/Project.toml) | LP solve for `SharedTransmission` (via `select_optimizer(LP())`, INFRA-02) | Same solver-factory seam every other planning-layer LP already uses (`follower.jl`, `master.jl`); the follower's genuine-Farkas-certificate behavior (WR-05 in `follower.jl`'s docstring) is version-pinned to this exact HiGHS build — `coupling.jl` inherits that pin, no new pin needed. |
| CairoMakie | 0.15.13 (weakdep) | `plot_nash_convergence` | Exact precedent already exists (`ext/TSODSOMakieExt.jl`); no new extension package, just a new method in the SAME extension module. |
| DrWatson | 2.19.1 | `checkpoint_iteration!` reuse for per-sweep state | Already the sole checkpoint mechanism (`checkpoint.jl`); generic over `state`, no change needed. |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| StableRNGs | 1.0.4 (already a hard dep) | Deterministic seed generation, IF seeds are randomized rather than hand-picked | Only if the "seed" axis of the multi-seed probe is implemented as randomized initial `z^(0)` draws (see Pattern 4) rather than hand-picked corner/perturbed vectors — either is defensible; hand-picked is recommended for hand-checkability (Claude's Discretion per CONTEXT.md). |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled Gauss-Seidel diagonalization (`nash.jl`) | PATHSolver/Complementarity.jl MCP recast | Deferred explicitly (PLAN-MCP-01) — "only if diagonalization proves unreliable" per REQUIREMENTS.md; not evaluated this phase by design. |
| One shared `SharedTransmission` JuMP model with per-distributor views | N independent `FollowerLP`-style models, one per distributor, manually synchronized via a struct outside JuMP | Rejected implicitly by CONTEXT.md's locked "one shared follower" API shape — N independent models would duplicate the capacity constraint N times with no single source of truth for the corridor's aggregate loading, inviting drift bugs. |
| Fresh cut store per best-response (locked) | Retained/warm-started cut store across sweeps | Deferred (see Deferred Ideas) — would require a formal joint-convexity argument in `(z_i, z_{-i})` this session does not attempt to prove; CONTEXT.md's own "correctness-first" framing rejects it for v2.0. |

**Installation:** None — no `Pkg.add` needed this phase.

**Version verification:** No new packages to verify. `HiGHS = "= 1.24.1"` in `test/Project.toml`
already pins the exact build whose Farkas-certificate behavior `follower.jl`'s WR-05 note
documents; `coupling.jl`'s new capacity/coupling constraints inherit that pin automatically
(same `Model(select_optimizer(LP()))` factory call) — no separate pin action needed.

## Package Legitimacy Audit

**Not applicable this phase.** No new external packages are introduced — `coupling.jl`,
`nash.jl`, and the new `NashTrace`/plot-extension code build entirely on already-audited,
already-pinned dependencies (JuMP, HiGHS, CairoMakie, DrWatson, StableRNGs) that passed their
own legitimacy gates in earlier phases (Phase 1 INFRA-02, Phase 7 ADMM-05, Phase 10-12
planning-layer phases). The slopcheck/registry-verification protocol is skipped by design
(nothing to check) — do not run it against a phase that adds zero `Pkg.add` calls.

**Packages removed due to slopcheck `[SLOP]` verdict:** none (n/a — no packages evaluated).
**Packages flagged as suspicious `[SUS]`:** none (n/a).

## Architecture Patterns

### System Architecture Diagram

```
                         ┌─────────────────────────────────────────────┐
                         │        nash.jl: run_nash!(distributors)      │
                         │  (outer Gauss-Seidel sweep, build-once loop) │
                         └───────────────┬───────────────────────────────┘
                                         │  k = 1 .. max_sweeps (fail-loud cap)
                                         ▼
        ┌────────────────────────────────────────────────────────────────────┐
        │  for i in sweep_order(k)  (forward 1..N or reverse N..1, probe axis)│
        │                                                                    │
        │   1. neighbors' CURRENT z_{-i} read from SharedTransmission state  │
        │   2. update_coupling!(shared, i, z_minus_i)  — sets Parameters     │
        │           ┌───────────────────────────────────────────┐           │
        │           │      coupling.jl: SharedTransmission        │          │
        │           │  (build-once JuMP model, N x_op[i,t] vars,  │          │
        │           │   N coupling[i,t] rows, ONE capacity[t] row) │          │
        │           └───────────────────────────────────────────┘           │
        │   3. FRESH master cut store for distributor i's Benders loop      │
        │   4. solve_stackelberg!(... follower view of shared[i] ...)       │
        │           ┌───────────────────────────────────────────┐           │
        │           │   benders.jl: solve_stackelberg! (UNCHANGED) │         │
        │           │   PlanningOracle ↔ FollowerLP-view ↔ Master  │         │
        │           └───────────────────────────────────────────┘           │
        │   5. z_i^(k) = result.z  →  written back into SharedTransmission  │
        │   6. push!(nash_trace, k, i; benders_summary, ...)                │
        └────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
                  outer Nash residual = maxᵢ ‖z_i^(k+1) − z_i^(k)‖∞  (+ Δinvestment)
                                         │
                          converged? ────┼──── no → next sweep k+1
                                         │ yes
                                         ▼
        ┌────────────────────────────────────────────────────────────────────┐
        │  run_nash_probe: repeat the WHOLE loop above for ≥3 seeds ×        │
        │  2 orders (6+ independent runs) — assert ALL converge; compute     │
        │  spread = max pairwise distance in (z, investment, cost) across    │
        │  runs; report "a converged equilibrium (spread: …)", never "the"  │
        └────────────────────────────────────────────────────────────────────┘
                                         │
                                         ▼
                    plot_nash_convergence(nash_trace) → CairoMakie Figure
                    (two-level: outer Nash residual + embedded inner Benders
                     UB/LB gap per sweep, ext/TSODSOMakieExt.jl)
```

### Recommended Project Structure

```
src/planning/
├── retry.jl          # (existing, unchanged) escalating retry ladder
├── checkpoint.jl      # (existing, unchanged) per-iteration checkpoint/resume
├── trace.jl           # (existing, unchanged) BendersTrace — inner-level ledger
├── subproblem.jl       # (existing, unchanged) PlanningOracle
├── follower.jl         # (existing, unchanged) single-distributor FollowerLP
├── master.jl           # (existing, unchanged) BendersMaster
├── benders.jl          # (existing, unchanged) solve_stackelberg! atomic best-response
├── coupling.jl         # NEW (NASH-01): SharedTransmission + per-distributor views
└── nash.jl             # NEW (NASH-02/03/04): outer Gauss-Seidel loop, NashTrace,
                         #     run_nash_probe (multi-seed/multi-order gate)

src/diagnostics/
└── plots.jl            # EXTEND: add plot_nash_convergence generic stub (mirrors
                         #     plot_convergence/plot_price_convergence)

ext/
└── TSODSOMakieExt.jl    # EXTEND: add the CairoMakie plot_nash_convergence method

test/
├── test_planning_coupling.jl   # NEW: SharedTransmission unit tests (N=2/N=3)
└── test_planning_nash.jl       # NEW: diagonalization convergence + probe gate
```

### Pattern 1: `coupling.jl` — one shared follower, per-distributor views

**What:** A single build-once JuMP model holding all `N` distributors' delivered flows
through one physical corridor, with `N` individually-dualizable coupling rows and one shared
capacity row. Each distributor's Benders best-response is handed a thin "view" that pins
every OTHER distributor's flow as a fixed `Parameter` and leaves this distributor's own flow
free to be driven by its own Benders trial.

**When to use:** Whenever `N` leaders share exactly one convex follower/resource whose
capacity constraint couples them additively (a genuinely "aggregative" structure — each
player only cares about the AGGREGATE of the others, not their individual identities).

**Design (this session's own derivation, not from a published source — flagged `[ASSUMED]`
for the cost-allocation convention specifically; see Revision 1 note below — the
cost-allocation convention this sketch shows is SUPERSEDED by CONTEXT.md's locked
per-distributor-ownership decision):**

> **Revision 1 note (plan-checker pass, 2026-07-23):** the `cost_share` sketch below (one
> shared scalar `x_inv` with an equal-split cost vector) is the ORIGINAL research sketch and
> is now superseded — see Open Questions #2 (RESOLVED) below. `coupling.jl` (13-01-PLAN.md)
> implements the per-distributor-ownership model instead: `x_inv::Vector{VariableRef}` of
> length `N`, one investment variable per distributor, each paying its own `c_inv[i]*x_inv[i]`.
> The sketch is retained here unmodified for research traceability (what was considered and
> why it changed), not as the implemented design.

```julia
# src/planning/coupling.jl (sketch — exact field names are Claude's Discretion per CONTEXT.md)
struct SharedTransmission{Z,C}
    model::Model                  # built ONCE via Model(select_optimizer(LP()))  — INFRA-02
    x_inv::VariableRef            # the corridor's SHARED investment (one physical asset)
    x_op::Matrix{VariableRef}     # x_op[i, t] — distributor i's delivered flow, i=1:N, t=1:T
    z::Z                          # z[i, t] in Parameter(0.0) — EVERY distributor's own trial,
                                   # but only the ACTIVE distributor's z[i,:] is driven by its
                                   # own Benders loop each best-response; all others are pinned
                                   # at their last-known iterate via update_coupling!
    coupling::C                   # coupling[i, t]: x_op[i,t] == z[i,t]  — N separate rows,
                                   # each independently dualizable (π_s_i = dual(coupling[i,:]))
    N::Int
    T::Int
    corridor_cap::Float64
    x_inv_max::Float64
    cost_share::Vector{Float64}   # [ASSUMED] equal-split default: fill(c_inv/N, N) — see
                                   # Assumptions Log A1. Any OTHER convention (marginal-cost
                                   # allocation, Shapley-value split, single-payer) is an
                                   # equally defensible modeling choice this research does NOT
                                   # resolve from the PSR source (single-distributor thesis has
                                   # no N-distributor cost-sharing convention to consult).
end

# ONE shared capacity row — the genuinely NEW coupling constraint (NASH-01's whole point):
# capacity[t]: sum(x_op[i, t] for i in 1:N) <= corridor_cap * x_inv
```

```julia
"""
    update_coupling!(shared::SharedTransmission, i::Int, z_i_trial::AbstractVector{<:Real})

Called from INSIDE distributor i's atomic `solve_stackelberg!` Benders loop, at every trial
`z_i^(k)` — the SAME re-solve-via-Parameter idiom `follower.jl` already uses, just scoped to
row `i` of the shared model. Never rebuilds; never touches any OTHER distributor's row `j≠i`
(those stay pinned at whatever `write_back!` last wrote after distributor j's own most recent
completed best-response — Gauss-Seidel's own "use the latest available" semantics).
"""
function update_coupling!(shared::SharedTransmission, i::Int, z_i_trial)
    set_parameter_value.(shared.z[i, :], z_i_trial)
    return shared
end

"""
    write_back!(shared::SharedTransmission, i::Int, z_i_converged::AbstractVector{<:Real})

Called from `nash.jl` AFTER distributor i's atomic best-response converges — freezes
distributor i's z at its converged value so the NEXT distributor in this sweep's order (or
distributor i itself, next sweep) reads the up-to-date z_{-i} (Gauss-Seidel: use the latest
value available, not the value from the START of the sweep — this is what distinguishes
Gauss-Seidel from Jacobi diagonalization).
"""
function write_back!(shared::SharedTransmission, i::Int, z_i_converged)
    set_parameter_value.(shared.z[i, :], z_i_converged)
    return shared
end
```

**Cut-invalidation math argument (to embed verbatim in `coupling.jl`'s/`nash.jl`'s docstrings,
per CONTEXT.md's specifics section):**

> Within ONE atomic best-response (fixed `z_{-i}`), the follower's value function
> `V_i(z_i; z_{-i})` is convex in `z_i` (it is the optimal value of a parametric LP whose RHS is
> affine in `z_i` alone at fixed `z_{-i}`), so Benders cuts computed at successive trial points
> `z_i^(1), z_i^(2), ...` **within that best-response** remain valid supporting hyperplanes of
> `V_i(·; z_{-i})` for every `z_i` — this is exactly why Phase 11/12's persistent
> (never-rebuilt) cut store across BENDERS ITERATIONS is correct, and it is unchanged here.
> However, `V_i(z_i; z_{-i})` is a genuinely DIFFERENT function of `z_i` for a different
> `z_{-i}` — the shared capacity constraint's RHS slack available to distributor `i` shifts
> by exactly `Δ(Σ_{j≠i} z_j)` — so a cut computed at OLD `z_{-i}` is not merely "less tight",
> it can be actively WRONG (non-supporting) for the NEW `V_i(·; z_{-i}^{new})`: e.g., a
> feasibility cut derived from the follower's infeasibility at old, tighter `z_{-i}` may
> incorrectly exclude a `z_i` that is now perfectly feasible once neighbors freed up capacity.
> Retaining stale cuts across a `z_{-i}` change therefore risks a master that converges to a
> POINT THAT IS NOT THE TRUE BEST RESPONSE to the current `z_{-i}` — silently wrong, not just
> slow. This is why every atomic best-response in this phase starts its master's cut store
> EMPTY (CONTEXT.md's locked "correctness-first" decision): validity is certain by
> construction, at the cost of re-deriving cuts on every best-response (instrumented in
> `NashTrace` as the rebuild-cost finding this phase is asked to surface, not silently
> retain). A future phase MAY revisit cut-reuse if it can prove `V_i` is monotonically
> non-decreasing (or otherwise boundable) in `z_{-i}` on this specific corridor model — not
> attempted here (Deferred Ideas).

### Pattern 2: Diagonalization / Gauss-Seidel outer loop structure

**What:** The classic EPEC-solving "diagonalization" algorithm (economics/power-systems
literature) — cyclically re-solve each player's bilevel best-response holding the others
fixed, checking a fixed-point residual after each full sweep (or after each player, for
Gauss-Seidel vs Jacobi).

**When to use:** Multi-leader-common-follower games where no monolithic single-level
reformulation is tractable/desired (this project explicitly defers the MCP/VI alternative,
PLAN-MCP-01).

**What structure THIS game has (reasoned from the literature, not a direct citation — the
project's own game is not analyzed in any source found):**

- It IS an **aggregative game** in the coupling dimension: each distributor's follower-side
  payoff/feasible-region depends on the OTHERS only through the aggregate
  `Σ_{j≠i} z_j` (not their individual identities) — this is the "weakness of externalities"
  structure the literature associates with better (not guaranteed, but empirically more
  reliable) diagonalization convergence [CITED: aggregative-games literature, e.g. Jensen
  2010 "Aggregative games and best-reply potentials", found via WebSearch and cross-checked
  by a second aggregative-games survey result — MEDIUM confidence, general result not
  re-derived for this specific LP/QP game].
- It is **congestion-coupled**: the shared corridor has a hard capacity, which is EXACTLY the
  structural feature Hu & Ralph (2005) show destroys uniqueness (their two-node congested
  example has a continuum of equilibria; their uncongested/symmetric-benefit examples have a
  unique equilibrium) [CITED:
  https://www3.eng.cam.ac.uk/~dr241/Papers/epec-4-05.pdf, read directly this session — HIGH
  confidence, primary source].
- **No potential-game structure is established or assumed** — congestion games in the
  Rosenthal/Monderer-Shapley sense have a potential function when costs are player-agnostic
  functions of aggregate load alone; this project's distributors have DIFFERENT
  investment/operational cost data (asymmetric fixtures are explicitly a research target,
  N=3 "probe"), so a potential-function argument is NOT assumed to exist here — do not claim
  potential-game convergence guarantees in code comments or docs (`[ASSUMED: NOT present]`
  unless a future phase proves otherwise).
- **Practical implication:** the project's own carried blocker ("no general
  uniqueness/convergence guarantee", STATE.md) is the field's OWN honest position for this
  problem class, not a gap in this project's research — Hu & Ralph's own numerical
  experiments show diagonalization succeeding reliably (30/30, 30/30) on their
  single-strategic-dimension (`bid-a-only`, `bid-b-only`) games where equilibria are locally
  unique, but **failing on 27/27 and 0/27 problem instances** (their two harder diagonalization
  variants, "Diag"/"Diag/Reg") on their two-dimensional `bid-a-b` game where equilibria are
  NOT locally unique — a striking, directly-relevant empirical data point that non-uniqueness
  (not problem size or nonlinearity) is the actual driver of diagonalization failure in this
  literature. [CITED, same source, Tables 1-3 and their own discussion: "Difficulties with
  both approaches to bid-a-b games are to be expected if... the bid-a-b games have solutions
  that are not locally unique".]

**Damping/relaxation remedy (standard numerical-analysis practice, `[ASSUMED]` — not
specific to this literature, general fixed-point-iteration knowledge):**

```
z_i^{k+1} = (1 - ω) * z_i^k + ω * BR_i(z_{-i}^k),   0 < ω <= 1
```

Standard successive-under-relaxation remedy for cycling/oscillation in fixed-point iteration;
`ω = 1` recovers plain Gauss-Seidel (the CONTEXT.md-locked default — "atomic best-response =
full `solve_stackelberg!` convergence per distributor per sweep — no partial/inexact passes"
already implies `ω=1`, undamped). **Recommendation: implement plain (`ω=1`) Gauss-Seidel per
the locked decision; note damping as an available remedy in `nash.jl`'s docstring/Open
Questions for if/when the N=3 (or a future larger-N) probe exhibits cycling** — do not
preemptively add an `ω` keyword the phase's own fixtures never exercise (YAGNI, consistent
with this project's "measure, don't guess" convention already established in Phase 12's
retry-budget finding).

> **Revision 1 note (plan-checker pass, 2026-07-23):** 13-02-PLAN.md ultimately DOES add the
> `ω` keyword (default `1.0`, i.e. plain Gauss-Seidel, `0 < ω <= 1` guarded) rather than
> deferring it — this is a deliberate, documented deviation from this Pattern's own YAGNI
> recommendation, made because the keyword doubles as Open Question #1's damping escape
> hatch and is directly exercised by 13-02's own testitem 9 (`ω=0.5` still converges). See
> Open Questions #1 (RESOLVED).

### Pattern 3: `NashTrace` — mirror `BendersTrace`'s shape, document the divergence

**What:** A JuMP-free, purpose-built convergence ledger for the outer loop, following
Phase 12's own explicitly-stated pattern: *"Convergence-ledger structs for future outer loops
(Phase 13's Nash diagonalization) should mirror `BendersTrace`'s shape: JuMP-free,
sequential-push! guarded, with an explicit header comment stating what is deliberately NOT
copied from a sibling ledger and why."*

**Recommended shape (Claude's Discretion on exact field names per CONTEXT.md):**

```julia
mutable struct NashTrace
    sweep_trace::Vector{Int}              # outer sweep index k
    distributor_trace::Vector{Int}        # which i was solved this row (Gauss-Seidel: one row
                                            # per (k, i) pair, not one row per sweep — mirrors
                                            # BendersTrace's own one-row-per-solve-event granularity)
    nash_residual_trace::Vector{Float64}   # ‖z_i^(k+1) - z_i^(k)‖∞ (this distributor's own
                                            # move) — NaN until distributor i has a k-1 row to
                                            # diff against (legitimate sentinel, BendersTrace
                                            # precedent for gap_trace's NaN convention)
    benders_iters_trace::Vector{Int}       # embedded inner-loop summary: result.iters
    benders_gap_trace::Vector{Float64}     # embedded inner-loop summary: result.gap
    benders_retries_trace::Vector{Int}     # embedded: trace_summary(result.trace).total_retries
    cuts_rebuilt_trace::Vector{Int}        # instrumented per CONTEXT.md: rebuild-cost finding
    order_trace::Vector{Symbol}            # :forward / :reverse — which sweep order this row
                                            # belongs to (needed for the multi-order probe to
                                            # slice its own trace back out)
    iters::Int
end
```

**Why NOT a single scalar "outer Nash residual per sweep" row (structurally distinct from a
naive design):** capturing one row PER `(sweep, distributor)` pair — not one row per sweep —
lets the trace embed each distributor's own Benders summary directly (mirrors `BendersTrace`'s
own one-row-per-iteration granularity), and lets `plot_nash_convergence` reconstruct BOTH the
outer per-sweep max-residual curve (by grouping/reducing over `distributor_trace`) AND the
inner Benders gap trajectory per distributor, satisfying criterion 3's "two-level" requirement
without a second parallel struct.

### Pattern 4: Multi-seed / multi-order probe (`run_nash_probe`)

**What:** A driver that repeats the ENTIRE Gauss-Seidel loop `run_nash!` for every
`(seed, order)` combination in a probe matrix, asserts every run converges (the gating test),
and reports the observed spread across runs — never claiming a single equilibrium.

**Seed axis — recommendation:** since every solver in this stack (Clarabel/HiGHS via
`solve_with_retry!`) is deterministic given its inputs, "seed" here means **which initial
`z_i^{(0)}` profile the first sweep starts from**, not an RNG stream. Recommend ≥3 HAND-PICKED
initial profiles rather than `StableRNGs`-drawn random ones, for two reasons: (1) it keeps the
N=2 fixture's hand-checkable equilibrium reasoning tractable (a random draw could land the
first sweep in a numerically awkward corner of the corridor's feasible region, complicating
the by-hand cross-check CONTEXT.md requires); (2) it lets each seed be documented with WHY it
was chosen (e.g. "zero start", "corridor-saturating start", "asymmetric-favoring-distributor-1
start") — directly traceable in test names/docstrings, matching this project's
"traceability to source theory" documentation requirement (CLAUDE.md). Example matrix:

```julia
seeds = (
    zero        = fill(0.0, T),               # the natural "cold start"
    saturating  = fill(corridor_cap * x_inv_max / N, T),   # starts at the shared, symmetric
                                                             # capacity split — a natural
                                                             # candidate equilibrium GUESS for
                                                             # the symmetric N=2 fixture
    skewed      = ...,                        # asymmetric start favoring one distributor
)
orders = (:forward, :reverse)                 # 3 seeds × 2 orders = 6 probe runs (>= 3×2 per
                                                # CONTEXT.md's locked "≥3 seeds × 2 sweep
                                                # orders" minimum)
```

**Spread metric (Claude's Discretion on exact formula, CONTEXT.md only specifies WHAT to
measure, not the formula):**

```julia
spread = (;
    z_spread    = maximum(norm(r1.z .- r2.z, Inf) for (r1, r2) in pairs_of(results)),
    y_spread    = maximum(abs(r1.y - r2.y) for (r1, r2) in pairs_of(results)),
    cost_spread = maximum(abs(total_cost(r1) - total_cost(r2)) for (r1, r2) in pairs_of(results)),
)
```

`pairs_of` = all `C(6,2) = 15` pairwise combinations of the 6 probe runs (or however many the
matrix contains) — a simple, auditable "max pairwise distance" definition, not a statistical
summary (mean/variance) that could understate an outlier run, which would undermine the
honesty goal NASH-04 exists for.

### Anti-Patterns to Avoid

- **Claiming a potential-game or contraction-mapping convergence GUARANTEE in code comments
  or docstrings.** No such structure is established for this project's asymmetric-cost,
  congestion-coupled game — doing so would misrepresent a genuine open research question as
  solved, directly contradicting the STATE.md blocker this phase exists to honestly address.
- **Building `nash.jl` to Jacobi (not Gauss-Seidel) semantics by accident** — i.e., reading
  ALL of `z_{-i}` from the START of the sweep rather than the LATEST available (including
  updates from EARLIER distributors already processed THIS sweep). CONTEXT.md and
  ROADMAP.md both specify "Gauss-Seidel" explicitly; `write_back!` must fire immediately after
  each distributor's atomic best-response, not batched at sweep end.
- **Warm-starting or reusing the master's cut store across best-responses** "for speed" —
  explicitly locked against in CONTEXT.md; the correctness argument in Pattern 1 explains why.
- **Averaging/collapsing the multi-seed/multi-order probe results into a single "canonical"
  equilibrium before reporting** — CONTEXT.md requires reporting spread, not silently picking
  one run as canonical.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-distributor best-response solve | A new bespoke Stackelberg loop inside `nash.jl` | `solve_stackelberg!` (`benders.jl`, unchanged) | CONTEXT.md's explicit "atomic best-response = full `solve_stackelberg!` convergence" — Phase 11/12 already hardened this; re-implementing it inside `nash.jl` would duplicate ~2100 lines of tested retry/checkpoint/trace machinery and reintroduce the exact bugs Phase 12 closed (IN-01..IN-06). |
| Cross-solve retry/conditioning escalation | A separate retry ladder for the outer Nash loop | `solve_with_retry!` (already threaded through every inner solve via `solve_stackelberg!`) | The outer loop has NO solver call of its own (it only orchestrates calls to `solve_stackelberg!`/`update_coupling!`), so there is nothing new to retry — a second retry mechanism at the outer level would be solving a problem that does not exist. |
| Equilibrium uniqueness certification | A custom uniqueness-proof routine or ad hoc "if spread < ε assume unique" heuristic | The multi-seed/multi-order probe (Pattern 4), reported honestly | Uniqueness is a genuinely hard, model-specific mathematical question (Hu & Ralph show it can fail even in a 2-node LP-based network); no cheap heuristic substitutes for the honest empirical probe this phase implements. |
| MCP/complementarity solving | Hand-rolling a variational-inequality solver for the equilibrium | Nothing — explicitly deferred (PLAN-MCP-01) | Out of scope this milestone; PATHSolver/Complementarity.jl already vendored on the shelf for a FUTURE phase if diagonalization proves unreliable. |

**Key insight:** every genuinely new piece of machinery this phase needs (the shared
corridor's capacity coupling, the outer sweep, the two-level trace, the probe) is orchestration
and data-modeling work over ALREADY-VALIDATED lower layers — the only wholly new JuMP model in
this phase is `SharedTransmission` itself (NASH-01's own scope), and even that reuses
`follower.jl`'s build-once/`Parameter`/`INFRA-02`-factory idiom verbatim.

## Common Pitfalls

### Pitfall 1: Confusing Jacobi and Gauss-Seidel update timing
**What goes wrong:** All `N` distributors are solved against the SAME frozen `z_{-i}` snapshot
from the start of the sweep, then all written back simultaneously at sweep end (Jacobi), while
the code/docs call it "Gauss-Seidel" (which requires using each distributor's freshly-updated
`z_i` immediately for the NEXT distributor in the same sweep).
**Why it happens:** Jacobi is the more "obviously parallelizable" and easier-to-reason-about
implementation (no ordering dependency); Gauss-Seidel requires careful sequencing.
**How to avoid:** `write_back!` (Pattern 1) must fire immediately after EACH distributor's
`solve_stackelberg!` returns, before the next distributor in `sweep_order(k)` reads
`z_{-i}` — verify with a regression test asserting distributor 2 (in a forward sweep) sees
distributor 1's JUST-UPDATED `z_1`, not its previous-sweep value.
**Warning signs:** the outer residual converges MORE slowly than expected for a simple N=2
symmetric fixture, or forward/reverse order probes disagree by more than numerical noise on a
SYMMETRIC fixture (where they should agree by symmetry) — this is often traceable to an
accidental Jacobi timing bug rather than genuine non-uniqueness.

> **Revision 1 note (plan-checker pass, 2026-07-23):** 13-02-PLAN.md Task 2 now includes BOTH
> regressions this Pitfall recommends: the forward/reverse agreement test (testitem 7) AND a
> DIRECT intra-sweep timing check (testitem 7b) that inspects the shared model's own
> parameter state mid-sweep, rather than relying solely on the indirect forward/reverse
> agreement signal.

### Pitfall 2: Nested-tolerance violation silently producing a "converged" but wrong answer
**What goes wrong:** `tol_inner >= tol_outer` (or close to it) lets the outer residual test
pass purely because the INNER Benders solve's own approximation error happens to make two
successive best-responses look identical, when the TRUE best-response map has not actually
reached a fixed point.
**Why it happens:** it is tempting to reuse the SAME `tol=1e-6` default from `benders.jl` for
both levels "for consistency," without realizing the outer test needs strictly LOOSER
tolerance headroom above the inner solve's own noise floor.
**How to avoid:** CONTEXT.md already locks this as a CODE-LEVEL assertion
(`ArgumentError` if `tol_inner >= tol_outer`), not just documentation — implement the guard as
a boundary check in `run_nash!`'s argument validation, mirroring `solve_stackelberg!`'s own
"boundary guards BEFORE any build call" discipline (`benders.jl` header comment).
**Warning signs:** the outer loop "converges" in exactly 1-2 sweeps regardless of how far the
initial seed is from any plausible equilibrium — a signature of the outer test being
vacuously satisfied by inner-solve noise, not genuine fixed-point convergence.

### Pitfall 3: Corridor fixture accidentally uncongested (coupling term never binds)
**What goes wrong:** The N=2 fixture's `corridor_cap`/`x_inv_max` are set generously enough
that neither distributor's flow ever approaches the shared capacity constraint — the
`capacity[t]` row never binds, the shared coupling collapses to N independent single-
distributor problems, and the "Nash" loop trivially converges in one sweep because there is
nothing to actually negotiate over (NASH-01's own success criterion — "without it, 'Nash' has
nothing shared to iterate on" — silently fails even though the code path exists).
**Why it happens:** reusing Phase 11's exact toy-fixture numbers (`corridor_cap=2.0,
x_inv_max=2.0`) without checking whether TWO distributors' combined demand under that capacity
still leaves slack.
**How to avoid:** size the N=2 fixture's `corridor_cap`/`x_inv_max` so that the SUM of both
distributors' UNCONSTRAINED (single-distributor) optimal flows exceeds the shared capacity —
i.e., deliberately congest it — then verify (as part of the hand-check) that the resulting
equilibrium's `x_op[1]+x_op[2]` sits AT the capacity bound with a strictly positive shadow
price (`dual(capacity[t]) < 0` in a Min-cost convention, or its sign-convention equivalent —
reuse the empirically-pinned sign convention from Phase 11/PLAN-07, do not re-derive it).
**Warning signs:** `dual(shared.model[:capacity][t])` is exactly `0.0` at the converged
equilibrium — the shared constraint is slack, and the phase has not actually exercised its own
core scope.

### Pitfall 4: Cost-allocation convention silently smuggled in as "obviously correct"
**What goes wrong:** picking equal-split (`c_inv/N`), marginal-cost, or single-payer cost
allocation for the shared corridor's investment WITHOUT flagging it as a modeling assumption,
then having a downstream phase (14, docs) present it as if it were derived from the PSR
source — which has NO N-distributor convention to derive it from (the thesis is
single-distributor).
**Why it happens:** the single-distributor `follower.jl`'s `c_inv` charge is unambiguous (one
payer); generalizing to N payers has no unique "obviously correct" answer, and it is easy to
pick one silently while implementing.
**How to avoid:** document the chosen convention explicitly in `coupling.jl`'s docstring as an
assumption (see Assumptions Log A1), and surface it in the plan/PLAN.md as a decision point
the plan-checker or a discuss-phase pass could flag for explicit user confirmation before
Phase 14 writes it into the literate docs as settled math.
**Warning signs:** a docstring or later PVAL-03 literate doc states the cost-split convention
as fact with no "why this convention, not another" caveat.

> **Revision 1 note (plan-checker pass, 2026-07-23):** superseded — see Open Questions #2
> (RESOLVED). CONTEXT.md's per-distributor-ownership decision resolves this Pitfall
> entirely for this phase (no cost-allocation convention is smuggled in — each distributor
> pays only its own `c_inv[i]*x_inv[i]`, a genuinely unambiguous allocation). Retained here
> for traceability of what was flagged and how it was resolved.

## Code Examples

### JuMP `Parameter` re-solve idiom (verified against `follower.jl`, this repo — HIGH confidence, in-repo precedent)
```julia
# Source: src/planning/follower.jl (this repo, plan 11-01) — the EXACT idiom coupling.jl
# should reuse, just with an extra distributor index.
@variable(model, z[t = 1:T] in Parameter(0.0))   # build ONCE
...
set_parameter_value.(f.z, z_trial)               # re-solve idiom, NO rebuild
optimize!(f.model)
```

### CairoMakie weakdep extension idiom (verified against `ext/TSODSOMakieExt.jl`, this repo — HIGH confidence, in-repo precedent)
```julia
# Source: src/diagnostics/plots.jl + ext/TSODSOMakieExt.jl (this repo, plan 07-01/07-06)
# core stub (JuMP/Makie-free):
function plot_nash_convergence end
export plot_nash_convergence

# ext/TSODSOMakieExt.jl method (added alongside the two existing methods):
function TSODSO.plot_nash_convergence(trace::TSODSO.NashTrace; filename = nothing)
    # group rows by sweep_trace, reduce nash_residual_trace by max per sweep for the outer
    # curve; overlay benders_gap_trace per distributor for the inner curve — mirrors
    # plot_price_convergence's twin-axis idiom (outer residual left axis, inner gap right
    # axis, log-scaled, `_logsafe` guard against exact-zero convergence).
end
```

### JuMP `Parameter` API (Context7/official docs cross-check — CITED, general JuMP docs, not this repo)
```julia
# Source: jump.dev/JuMP.jl/stable/manual/variables/ (WebSearch-verified against JuMP's own
# published docs, not Context7-fetched this session — MEDIUM confidence on this specific
# snippet's exact wording, HIGH confidence on the underlying `Parameter` mechanism, which is
# already proven working in this exact repo via follower.jl/subproblem.jl).
@variable(model, p in Parameter(1.0))
set_parameter_value(p, 2.0)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| EPEC diagonalization solved via ad hoc Newton/fixed-point code (2000s literature, e.g. Hu & Ralph 2005's own SNOPT-based "Diag/Reg") | Modern complementarity solvers (PATH) shown empirically MORE robust than diagonalization on non-unique-equilibrium games | Established by ~2005-2007 in the EPEC literature (Hu & Ralph; a 2024/2025 arXiv paper — "A Gauss-Seidel method for solving multi-leader-multi-follower games" — revisits proximal/regularized Gauss-Seidel variants with GLOBAL convergence guarantees specifically for POTENTIAL games) | Confirms this project's own deferred fallback (PLAN-MCP-01: "MCP/VI recast... only if diagonalization proves unreliable") is the field's own standard escalation path, not a novel idea — but also that a POTENTIAL-game-specific proximal variant exists in very recent literature if this project's game is ever shown to have potential structure (not currently assumed — see Pattern 2). |

**Deprecated/outdated:** none directly relevant — diagonalization itself is not "deprecated," it
remains the standard first attempt for EPECs precisely because (unlike MCP recast) it requires
no reformulation of each player's own bilevel problem, matching this project's "hand-rolled,
reuse validated lower layers" architectural preference (CLAUDE.md §5).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Shared corridor investment cost is split EQUALLY among the `N` distributors (`c_inv/N` default) in the absence of a PSR-source N-distributor convention. | Architecture Patterns, Pattern 1 (`cost_share` field) | **SUPERSEDED (Revision 1, 2026-07-23):** resolved by CONTEXT.md's locked per-distributor-ownership decision — see Open Questions #2 (RESOLVED). Each distributor pays only its own `c_inv[i]*x_inv[i]`; no equal-split allocation is implemented. Retained here for traceability. |
| A2 | The game has aggregative structure (payoffs depend on others only through Σz_{-i}) but NO established potential-function structure, given asymmetric per-distributor cost data. | Architecture Patterns, Pattern 2 | If a potential function DOES exist for this specific LP/QP structure (not ruled out, merely not established here), the project would be foregoing a stronger convergence-guarantee claim it could legitimately make — a missed opportunity, not a correctness risk, since the probe-based honesty approach (NASH-04) remains valid regardless. |
| A3 | "Seed" in the multi-seed probe means hand-picked initial `z^(0)` profiles, not `StableRNGs`-drawn random draws. | Architecture Patterns, Pattern 4 | If the planner/user intended genuinely randomized seeds (closer to a Monte-Carlo robustness check), the hand-picked design under-samples the initial-condition space; low risk since CONTEXT.md leaves this to Claude's Discretion explicitly, and hand-picked seeds are strictly easier to audit/hand-check. |
| A4 | Damping/relaxation (`ω`-parameter) is NOT implemented this phase — plain Gauss-Seidel (`ω=1`) only, per CONTEXT.md's "no partial/inexact passes" framing. | Architecture Patterns, Pattern 2 | **Superseded (Revision 1):** 13-02-PLAN.md DOES implement the `ω` keyword (default `1.0`) as Open Question #1's damping escape hatch, deviating from this row's original recommendation — see Pattern 2's Revision 1 note. |

## Open Questions

> **Revision 1 note (plan-checker pass, 2026-07-23):** Both open questions below are now
> **(RESOLVED)** — annotated inline. Neither blocks planning; both resolutions are load-bearing
> decisions already reflected in CONTEXT.md and the three PLAN.md files.

1. **(RESOLVED)** Does the recommended N=2/N=3 fixture actually exhibit convergence, or does
   it land in the non-unique/cycling regime Hu & Ralph document?
   - What we know: congestion (a binding shared capacity) is what CREATES non-uniqueness risk
     in the closest published analog; symmetric distributor data (per CONTEXT.md's own
     "symmetric distributors → symmetric equilibrium" framing) is what makes a hand-checkable
     target tractable.
   - What's unclear: whether a congested-but-symmetric N=2 fixture is safely inside the
     "reliable convergence" regime (Hu & Ralph's `bid-a-only`/`bid-b-only`, single strategic
     dimension per player, symmetric) or the "unreliable" regime (`bid-a-b`, two-dimensional
     per-player strategy) — this project's per-distributor strategy IS effectively
     multi-dimensional (`y_inv` and `z[1:T]` jointly), which is structurally closer to the
     HARDER `bid-a-b` case in the literature analog, not the easier one.
   - Recommendation: **measure, don't guess** (this project's own established convention,
     Phase 12 precedent) — the planner should budget an explicit "if the N=2 fixture does not
     converge within the locked max-sweep cap, congestion/asymmetry must be dialed back and
     re-measured" escape hatch into the plan, exactly like Phase 12's T=1→T=8 fixture
     escalation and Phase 11/12's own toy-fixture-optimum re-derivation precedent.
   - **Resolution (Revision 1):** mitigated two ways, both now load-bearing in 13-02-PLAN.md:
     (a) the `ω` damping/relaxation escape hatch is built into `run_nash!` (keyword `ω::Real =
     1.0`, `0 < ω <= 1`, guarded before any solve) as an available remedy if the N=2/N=3
     fixtures ever exhibit cycling — tested directly (testitem 9, `ω=0.5` still converges); and
     (b) 13-02 Task 2's action text now explicitly documents the re-tuning contingency this
     Open Question recommended: if the measured N=2 equilibrium does not land on the
     hand-derived target `z≈[0.6,0.6]`, the congestion/asymmetry parameters are re-derived and
     re-measured — mirroring the Phase 12 T=1→T=8 fixture-escalation precedent (Rule-1
     deviation with documented derivation), never a silent tolerance loosening.

2. **(RESOLVED)** Is `Σᵢ x_op[i,t] <= corridor_cap * x_inv`
   (aggregate-flow-limited-by-one-shared-investment) the right physical model, versus each
   distributor investing in and owning its own SHARE of the corridor (`x_op[i,t] <=
   corridor_cap * x_inv[i]`, `x_inv[i]` per-distributor, with only the DELIVERY constraint
   shared)?
   - What we know: CONTEXT.md's own language ("aggregate loading of the others enters its
     follower's RHS") is consistent with either model — both put `Σ_{j≠i} z_j` into
     distributor `i`'s effective RHS.
   - What's unclear: which is more faithful to the PSR N1-N2 interconnection-flow coupling
     this phase is meant to extend — the PSR note itself is single-distributor and
     self-flagged MEDIUM confidence (STATE.md), so there is no authoritative N-distributor
     answer to consult.
   - Recommendation: the ONE-SHARED-INVESTMENT model (Pattern 1's sketch) is recommended
     because it makes the "shared signal to iterate on" (NASH-01's own success-criterion
     language) unambiguous — a per-distributor-owned-share model would let each distributor's
     investment decouple entirely and risks re-collapsing into N independent problems
     (Pitfall 3's failure mode) unless the per-share investment costs are ALSO cross-coupled,
     which adds complexity without a clear benefit. Flag for discuss-phase / plan-checker
     confirmation given both are locked-decision-compatible.
   - **Resolution:** resolved by CONTEXT.md's dated (2026-07-23) per-distributor-ownership
     amendment, which OVERRIDES this question's own tentative one-shared-investment
     recommendation (and Pattern 1's equal-split `cost_share` sketch, and Assumptions Log A1's
     equal-split default): each distributor `i` owns `x_inv[i]` and pays `c_inv[i]*x_inv[i]`
     individually; the genuinely SHARED object is the pooled AGGREGATE capacity row
     (`corridor_cap * Σᵢ x_inv[i]`), not a single jointly-owned `x_inv` scalar. This is
     implemented in `13-01-PLAN.md` Task 1 (`SharedTransmission.x_inv::Vector{VariableRef}`,
     length `N`) and documented as a deliberate departure from this section's sketch directly
     in `coupling.jl`'s own docstring, per CONTEXT.md's own traceability requirement.

## Environment Availability

Skipped — this phase has no new external tool/service dependencies (Bash-probed at the start
of this research session: Julia, HiGHS, Clarabel, CairoMakie are already vendored and proven
working by every prior planning-layer phase's own green test suite; no new runtime, database,
or CLI dependency is introduced by `coupling.jl`/`nash.jl`).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `TestItemRunner.jl` 1.1.5 / `TestItems.jl` 1.0.0 (`@testitem`, project-wide convention) |
| Config file | `test/runtests.jl` (`@run_package_tests`, discovers every `@testitem` under `test/`/`src/`) |
| Quick run command | `julia --project=test -e 'using TestItemRunner; @run_package_tests filter=ti->occursin("planning", ti.name) && occursin("nash", ti.name)'` (mirrors the `occursin` filter convention documented in `test_planning_master.jl`/`test_planning_follower.jl`) |
| Full suite command | `julia --project=test -e 'using Pkg; Pkg.test()'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|---------------------|--------------|
| NASH-01 | `SharedTransmission` build-once model has N coupling rows + 1 capacity row; capacity row genuinely binds on the N=2 fixture (Pitfall 3 regression) | unit | `@testitem` in `test_planning_coupling.jl`, filter `occursin("coupling", ti.name)` | ❌ Wave 0 (new file) |
| NASH-02 | N=2 Gauss-Seidel run converges to the hand-checked symmetric equilibrium within the locked max-sweep cap; nested-tolerance `ArgumentError` fires when `tol_inner >= tol_outer` | unit + boundary-guard | `@testitem` in `test_planning_nash.jl` | ❌ Wave 0 (new file) |
| NASH-03 | `NashTrace` push!/summary round-trip (mirrors `BendersTrace`'s own guard tests, Phase 12 precedent); `plot_nash_convergence` returns a `Figure` when CairoMakie is loaded | unit + smoke (viz) | `@testitem` in `test_planning_nash.jl` (trace) + a CairoMakie-conditional smoke test mirroring how `ext/TSODSOMakieExt.jl`'s methods are exercised elsewhere in the suite | ❌ Wave 0 (new file) |
| NASH-04 | `run_nash_probe` over ≥3 seeds × 2 orders: ALL runs converge (gating assertion); reported spread is a `NamedTuple`/struct whose summary string contains `"a converged equilibrium"` and never the literal `"the equilibrium"` | unit + gating regression | `@testitem` in `test_planning_nash.jl`, e.g. `@test occursin("a converged equilibrium", summary_string) && !occursin("the equilibrium", summary_string)` | ❌ Wave 0 (new file) |

### Sampling Rate

- **Per task commit:** the quick filtered run above (`occursin("planning", ...) &&
  occursin("nash"/"coupling", ...)`), mirroring how Phase 10-12 verified incrementally.
- **Per wave merge:** full `Pkg.test()` — this phase's outer loop calls `solve_stackelberg!`
  many times (N distributors × several sweeps × probe matrix), so a full-suite regression
  check (not just the new files) is warranted before merging, per Phase 12's own precedent of
  running the full suite twice independently after any hardening change.
- **Phase gate:** full suite green, PLUS the NASH-04 gating regression specifically green (its
  own `@testitem` IS the phase's own success criterion 4 — a failing probe gate should be
  treated as a phase-blocking finding, not a soft warning, per CONTEXT.md's "gating test"
  language).

### Wave 0 Gaps

- [ ] `test/test_planning_coupling.jl` — covers NASH-01 (new file, no existing analog beyond
      `test_planning_follower.jl`'s single-distributor precedent to mirror).
- [ ] `test/test_planning_nash.jl` — covers NASH-02/03/04 (new file).
- [ ] `src/planning/coupling.jl` — currently does not exist (comment-only stub per this
      project's Wave-0-then-fill convention, mirroring how every other `planning/*.jl` file
      started, per `src/TSODSO.jl`'s own header comments).
- [ ] `src/planning/nash.jl` — currently does not exist, same convention.
- [ ] No new test-framework install needed — `TestItemRunner`/`TestItems` are already hard
      test-deps (`test/Project.toml`).

## Security Domain

**Not applicable — `security_enforcement` is not a relevant lens for this phase.** This is an
academic optimization research framework with no network-facing surface, no user input beyond
in-process Julia function arguments, no authentication/session/access-control boundary, and no
persisted secrets. The nearest analog to an ASVS category — V5 Input Validation — is already
covered by this project's own established `ArgumentError`-boundary-guard convention
(ArgumentError before any build call, non-finite/negative-value rejection at every cut/trace
append), which `coupling.jl`/`nash.jl` should extend verbatim (see Common Pitfalls and
Architecture Patterns above) rather than adopt any web/API-oriented ASVS control.

## Sources

### Primary (HIGH confidence)
- `src/planning/benders.jl`, `follower.jl`, `master.jl`, `trace.jl`, `retry.jl`,
  `checkpoint.jl`, `subproblem.jl` (this repo) — read in full this session; every
  Architecture Pattern above is grounded directly in these files' own established idioms.
- `src/diagnostics/plots.jl`, `ext/TSODSOMakieExt.jl` (this repo) — read in full; the
  weakdep-extension pattern for `plot_nash_convergence` is a direct structural copy.
- `.planning/phases/12-.../12-01-SUMMARY.md`, `.planning/phases/11-.../11-02-SUMMARY.md`
  (this repo) — the `BendersTrace` mirroring instruction and the `solve_stackelberg!`
  interface contract are read directly from these, not inferred.
- Hu, X. and Ralph, D., "Using EPECs to model bilevel games in restructured electricity
  markets with locational prices" (2005), fetched and read directly this session (32 pages,
  `https://www3.eng.cam.ac.uk/~dr241/Papers/epec-4-05.pdf`) — the congestion→non-uniqueness
  finding (Examples 8-12) and the diagonalization-failure-correlates-with-non-uniqueness
  numerical finding (Tables 1-3, §5.2.2 discussion) are read verbatim from this primary
  source.

### Secondary (MEDIUM confidence)
- Hobbs, Metzler, Pang, "Strategic Gaming Analysis for Electric Power Systems: An MPEC
  Approach" (2000) — WebSearch-surfaced summary confirming "the diagonalization method may
  fail to find a Nash equilibrium even if one exists" — a widely-cited independent
  confirmation of the Hu & Ralph finding, not directly read in full this session (WebSearch
  summary only).
- Aggregative-games/best-response-dynamics literature (Jensen "Aggregative games and
  best-reply potentials" and related survey results) — WebSearch-surfaced, cross-referenced
  across two independent search result sets confirming "weak externalities ⇒ better
  convergence" as an established (if informal) heuristic; not read in primary-source form
  this session.
- JuMP `Parameter`/`set_parameter_value` official-docs summary (jump.dev) — WebSearch-surfaced
  summary of the published JuMP manual; the underlying mechanism itself is HIGH confidence
  (already working in this exact repo), the specific doc wording quoted is MEDIUM (not
  Context7-fetched, no Context7 tool available in this session's environment).

### Tertiary (LOW confidence)
- "A Gauss-Seidel method for solving multi-leader-multi-follower games" (arXiv 2404.02605,
  2024/2025) — WebSearch summary only mentions a proximal/regularized variant with global
  convergence for POTENTIAL games; the PDF itself could not be parsed as text this session
  (binary/compressed stream defeated WebFetch's extraction) — flagged LOW, not used to ground
  any claim in this document beyond the "State of the Art" table's forward-looking note,
  which is explicitly hedged as unconfirmed.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages, every dependency already pinned/proven in this
  exact repo across three prior phases.
- Architecture (coupling.jl/nash.jl design): MEDIUM — a genuine design synthesis grounded in
  this repo's own established idioms (follower.jl, benders.jl, trace.jl) plus one directly-read
  primary source (Hu & Ralph) for the congestion/non-uniqueness structure; the N-distributor
  cost-allocation convention is explicitly LOW/`[ASSUMED]` (Assumptions Log A1) since no
  authoritative N-distributor source exists.
- Pitfalls: MEDIUM-HIGH — Pitfalls 1/2/4 are derived directly from this project's own
  established conventions (Gauss-Seidel-vs-Jacobi correctness, nested-tolerance discipline,
  documentation-of-assumptions discipline already visible in Phase 11/12 summaries); Pitfall 3
  is a novel-to-this-phase finding reasoned from the corridor-congestion literature, not yet
  empirically confirmed against an actual fixture (flagged as an Open Question, not asserted
  as fact).

**Research date:** 2026-07-23
**Valid until:** 30 days (stable domain — the underlying EPEC/diagonalization literature is
decades-old and not fast-moving; the in-repo interfaces this research depends on
(`solve_stackelberg!`, `BendersTrace`, `checkpoint_iteration!`) are locked by Phase 11/12's own
"keep call sites unchanged" discipline and are not expected to shift before Phase 13 executes).

---

## Revision 1 Log (plan-checker pass, 2026-07-23)

Addressed plan-checker warnings against the three PLAN.md files of this phase (0 blockers,
6 warnings). This RESEARCH.md received only the annotations above (Open Questions marked
RESOLVED, superseded sketches/assumptions flagged inline) — no re-research was performed.
See `13-01-PLAN.md`, `13-02-PLAN.md` for the corresponding fixture/test/documentation changes.

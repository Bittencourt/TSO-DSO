# Phase 13: Nash Diagonalization & Shared-Transmission Coupling - Context

**Gathered:** 2026-07-23
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — proposals accepted per area by user

<domain>
## Phase Boundary

Multiple distributors reach a Gauss-Seidel Nash fixed point over a genuinely new shared
transmission-reinforcement coupling model (`src/planning/coupling.jl`), each distributor's
Benders solve treated as an atomic best-response, with honest multi-seed/multi-order
non-uniqueness reporting. Covers NASH-01 (shared coupling model), NASH-02 (Gauss-Seidel
convergence, nested tolerances), NASH-03 (two-level diagnostics, plottable), NASH-04
(multi-seed/multi-order probe, "a" not "the" equilibrium).

Out of scope: integer investment (continuous-only, PVAL-04), stochastic scenarios, MCP/VI
recast (deferred — only if diagonalization proves unreliable), regression-hardening of the
validation oracles (Phase 14).

</domain>

<decisions>
## Implementation Decisions

### Shared coupling model `coupling.jl` (NASH-01)
- **One shared transmission-reinforcement follower**: all distributors' import profiles flow
  through a common corridor/reinforcement capacity. Distributor `i`'s best response sees
  `z_{-i}` **fixed** — the aggregate loading of the others enters its follower's RHS. Faithful
  to the PSR N1↔N2 interconnection-flow coupling (coupling variable = interconnection flow;
  linking price = interconnection dual).
- **`z_{-i}` as JuMP `Parameter`s** in the shared follower — build-once, `set_parameter_value`
  per sweep (Gauss-Seidel standard). No per-best-response rebuild of the follower model.
- **API shape:** `SharedTransmission` struct in `src/planning/coupling.jl` — build-once,
  per-distributor views, `update_coupling!` called after each atomic best-response.
- **Test scale:** N=2 baseline (hand-checkable equilibrium) + N=3 probe.
- **Investment ownership (user decision, post-research):** **per-distributor shares** — each
  distributor `i` owns its reinforcement investment `x_inv[i]` and pays its own cost;
  effective corridor capacity is `corridor_cap · Σᵢ x_inv[i]` (or the model's equivalent
  aggregate form). NOT one jointly-owned equal-split investment. Rationale: resolves the
  N-distributor cost-allocation ambiguity the PSR single-distributor source leaves open
  (research Open Question 2) in favor of the game-theoretically cleaner ownership model —
  each distributor's best response prices only its own investment; the shared object is the
  aggregate capacity, not the cost split. Document the departure from the equal-split default
  in coupling.jl's docstring for thesis traceability.

### Diagonalization loop mechanics (NASH-02/03)
- **Convergence metric:** outer Nash residual = max over distributors of
  `‖z_i^(k+1) − z_i^(k)‖∞` (plus investment change). **Inner Benders tolerance strictly
  tighter than the outer Nash tolerance** (e.g. inner 1e-6 vs outer 1e-4) — the nesting is
  asserted in code (ArgumentError if violated), not just documented.
- **Fresh cut store per best-response (correctness-first):** optimality/feasibility cuts
  computed at old `z_{-i}` are generally invalid once neighbors move. Each atomic
  best-response starts with a clean master cut store. Instrument the rebuild cost in the
  trace; cut-reuse across sweeps is deferred until a proven validity argument exists (surface
  as a research finding, do not silently retain).
- **Two-level diagnostics:** purpose-built `NashTrace` — per-sweep rows embedding
  per-distributor Benders summaries (final gap, iterations, retries, cut counts) plus the
  outer Nash residual. Include **one CairoMakie convergence-plot helper** (criterion 3
  requires "plottable"; the project already uses CairoMakie for publication figures).
- **Guardrails:** fail-loud max-sweeps cap (never silent); atomic best-response = full
  `solve_stackelberg!` convergence per distributor per sweep — no partial/inexact passes.

### Non-uniqueness probing (NASH-04)
- **Probe matrix:** ≥3 seeds × 2 sweep orders (forward/reverse) as a **gating test** — every
  probe run must converge for the phase to pass.
- **Asserted vs reported:** convergence of all probe runs is asserted; the equilibrium spread
  (max pairwise distance in `z`, investment, and total cost across probe runs) is measured
  and REPORTED, never asserted equal across runs.
- **Structural reporting language:** the summary API emits "a converged equilibrium
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

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/planning/benders.jl` — `solve_stackelberg!` (atomic best-response unit; incumbent-
  tracked, trace-instrumented, checkpointed).
- `src/planning/trace.jl` — `BendersTrace` (inner-level diagnostics to embed in `NashTrace`).
- `src/planning/follower.jl` — `FollowerLP` (single-distributor; `coupling.jl` generalizes
  the corridor to shared multi-distributor loading).
- `src/planning/master.jl`, `subproblem.jl`, `retry.jl`, `checkpoint.jl`.
- Toy Stackelberg fixture family (T=1 certification instance, T=8 load-test instance,
  boundary variant) — the N=2 fixture should extend this family.

### Established Patterns
- Build-once/re-solve with `Parameter`s; fail-loud gates; purpose-built trace structs
  (Phase 12's `BendersTrace` shape: sequential-k push! guard, empty-safe queries, export at
  file end); `[:planning]` TestItems; INFRA-02 (BilevelJuMP certification file is the one
  sanctioned exception); JuliaFormatter v2; capture solver statuses BEFORE dirtying models
  (Phase 12 CR-01 lesson); time only solve calls with time_ns() (Phase 12 WR-01 lesson).

### Integration Points
- `src/TSODSO.jl` planning include block (currently 7 files; coupling.jl + nash.jl append).
- `test/test_planning_*.jl` conventions; new `test_planning_nash.jl` (+ coupling tests).
- STATE.md blocker (NASH-04): every reported equilibrium carries the multi-seed/multi-order
  probe — this phase implements that gate.

</code_context>

<specifics>
## Specific Ideas

- Roadmap research note (MEDIUM): research pass needed on Gauss-Seidel/diagonalization
  convergence theory for multi-leader games (general literature — no convergence guarantee
  exists; the probe is the honest substitute) and on the coupling.jl design itself (a genuine
  research decision). Plan-phase should run with a research pass.
- The cut-invalidation reasoning (fresh cut store per best-response) should be documented in
  coupling.jl/nash.jl docstrings with the math argument — researcher-facing traceability.

</specifics>

<deferred>
## Deferred Ideas

- Cut-reuse across sweeps under a proven validity argument (e.g. cuts valid globally in z_i
  if the follower is jointly convex in (z_i, z_{-i}) with z_{-i} only in the RHS — research
  finding to surface, not implement silently).
- MCP/VI recast of the equilibrium (PLAN-MCP-01) — only if diagonalization proves unreliable.

</deferred>

# Phase 26: Network & Device Model Correctness - Context

**Gathered:** 2026-09-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the default SOCP branch-flow formulation and the SOC device models reflect the thesis
physics: fix/verdict the eq. 3.43 exactness-copy direction (FIX-01/02), add the receiving-end
thermal limit eq. 3.37 (FIX-03), link battery SOC across the whole horizon (FIX-04), and give
flexible loads their power-factor reactive draw eq. 3.23 (FIX-05). Every golden moved by these
fixes is re-derived in-phase; suite green at close. Thesis-reproduction restatement is Phase 28.

</domain>

<decisions>
## Implementation Decisions

### Exactness copy (eq. 3.43) — FIX-01/02
- NOTE: the thesis itself (per `.planning/research/THEORY-thesis.md:109`) writes 3.43 as
  `v̂_j = v̂_i − 2{r(P+rl)+x(Q+xl)}` — the current code is thesis-LITERAL; the defect may be in
  the thesis. The verdict must be checked against the PDF (`docs/references/86. Tesis Doctoral
  Juan Pablo Palacios (2).pdf`) and Gan–Low 2015.
- DEFAULT `ConvexBranchFlow` switches to the Gan–Low direction (v̂ ≥ v, a genuine relaxation),
  matching the form already in `RestrictedBranchFlow`. The thesis-literal copy is retained as an
  explicit opt-in variant, clearly labelled a RESTRICTION in docstring and docs.
- Verdict = a docs page with the derivation (which direction, why `v̂ ≤ V²max` is redundant and
  `v̂ ≥ V²min` a restriction under the reversed form), citing thesis PDF + Gan–Low 2015.
- Regression: 3-bus heavy-load low-voltage feeder; Ipopt AC-feasible; default SOCP feasible;
  thesis-literal variant infeasible (documents the restriction); assert v̂ ≥ v at the solution.
- Share ONE cpydrop helper between `ConvexBranchFlow` and `RestrictedBranchFlow` WHERE the forms
  coincide (discretionary); a test checks the docstring's "load-bearing bound" claim against the
  actual constraint.
- [Post-research amendment 2026-09-28] Fix mechanism = RESEARCH Option A: local per-branch sign
  flip inside the existing `cpydrop` constraint (provably yields v̂ ≥ v, keeps MeshedFlow's
  tree-order-free delegation). Option B (Restricted's tree-based shadow machinery) rejected.
  `decompose_dlmp` cpydrop-dual coefficient must be re-derived empirically in THIS phase.
- `Interruptible` converts from self-injecting (Variant-1) to the aggregatable Variant-2 contract
  so the Aggregator stays sole `:Rq` writer (follows from the FIX-05 decision).

### Reverse thermal limit (eq. 3.37) — FIX-03
- Receiving-end cone `‖(P−r·l, Q−x·l)‖ ≤ S̄` on every limited branch in every formulation with a
  sending-end limit (Convex; Meshed via delegation; Restricted). LinDistFlow (l = 0) skipped —
  identical to sending-end.
- Always on for limited branches — thesis physics, not a flag.
- Fixture: PV back-feed through a limited branch; assert receiving-end limit active (nonzero
  dual) while sending-end is slack.

### Battery SOC horizon linking — FIX-04
- `soc[1:T+1]` with Emin/Emax bounds on all entries, for both `PVBattery` and `FourQuadBESS`;
  hour-T charge/discharge changes stored energy.
- No default terminal condition (bounds only); optional `soc_terminal` keyword:
  `nothing` (default) | a value | `:cyclic` (soc[T+1] ≥ soc0).
- Update `src/models/mpc_window.jl` terminal logic to target `soc[H+1]` (drops the WR-03 H==1
  special case) and audit per-scenario copies in `src/models/stochastic_welfare.jl`.
- Regression: soc0 = Emin with incentive to discharge at hour T → zero discharge (or infeasible).

### Flexible-load reactive + golden policy — FIX-05, SC-6
- Aggregator applies its existing `tanφ` to flexible-load (interruptible, thermostatic,
  deferrable) `p_inject` into `:Rq` — Aggregator remains the SOLE `:Rp`/`:Rq` writer. Optional
  per-device φ override field (default: fall back to aggregator φ).
- One test per device type asserting its `:Rq` contribution == `p·tanφ` at the solution.
- Every moved golden: test comment with old→new and cause + table in phase SUMMARY; full suite
  green at phase close; no silent re-pin.

### Claude's Discretion
- Naming of the thesis-literal variant (kwarg vs separate type), exact fixture impedances,
  docs page location.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/powerflow/RestrictedBranchFlow.jl` — already has the correct Gan–Low copy form.
- `src/powerflow/ACPowerFlow.jl` (Ipopt) — AC feasibility oracle for the FIX-01 regression.
- `src/devices/Aggregator.jl` — `reactive_factor(φ)` / `tanφ`, sole `:Rp`/`:Rq` writer.
- `assert_socp_exact!` / PF-04 exactness checker reads `pf_vars = (; v, v̂, P, Q, l)`.

### Established Patterns
- Devices return `(; vars, p_inject, [q_inject], utility)`; Aggregator rolls up.
- `soc0` is a JuMP `Parameter` (MPC-01 seam); `soc[1] == soc0`.
- Every constraint annotated with its thesis equation number.

### Integration Points
- `src/powerflow/ConvexBranchFlow.jl` cpydrop (~line 187, dual feeds the DLMP exactness term).
- `src/powerflow/MeshedFlow.jl` delegates to ConvexBranchFlow constraints.
- `src/models/mpc_window.jl`, `src/models/stochastic_welfare.jl` reference `soc[H]` / `soc[1]`.
- DLMP decomposition consumes the cpydrop dual — sign/direction change affects it.

</code_context>

<specifics>
## Specific Ideas

- Known memories: 2 known-false Aqua failures on main checkout; TestItemRunner worktree trap —
  executors should use direct Test.jl scripts; launch full suite detached (background-suite race).

</specifics>

<deferred>
## Deferred Ideas

- Thesis reproduction restatement (sign flip / magnitude) — Phase 28.
- DLMP loss/voltage label physicality — Phase 27 (pricing certificate).

</deferred>

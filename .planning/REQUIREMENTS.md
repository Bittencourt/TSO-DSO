# Requirements — Milestone v4.0 Correctness & Depth

**Defined:** 2026-09-28
**Core Value:** A researcher can express a scenario and a model variant declaratively, run it
end-to-end with an open-source solver, and get trustworthy, reproducible results and prices — with
every model assumption documented and every layer swappable.

**Goal:** Fix the modeling defects confirmed by the 2026-09-28 full-project quality audit (see
memory `quality-audit-2026-09-28-defects.md`), deepen the planning layer into a genuine bilevel
TSO–DSO game on a real network, then restructure the orchestration layer and clean the codebase.
Sequencing: **Correctness → Planning depth → Architecture → Hygiene** (carry-overs slot in where
their dependencies land).

**Golden policy (applies to every requirement):** the v1–v3 "byte-identical default path" rule is
consciously relaxed. Any pinned golden that moves is re-derived, and the change is explained in the
test comment and in the phase SUMMARY. Nothing is silently re-pinned. Where a fix changes a
published v2.1/v3.0 finding, the finding is restated, not hidden.

## v4.0 Requirements

### Correctness — network model (FIX)

- [ ] **FIX-01**: Researcher can read a documented verdict on thesis eq. 3.43, checked against the
  thesis PDF and Gan–Low (2015): is the default exactness copy a relaxation or a restriction? It is
  backed by a regression in which a heavy-load, low-voltage 3-bus feeder that is AC-feasible
  (Ipopt) is also feasible under the default SOCP formulation.
- [ ] **FIX-02**: The default `ConvexBranchFlow` formulation's lossless-shadow copy satisfies
  v̂ ≥ v (Gan–Low direction) or is clearly relabelled as a restriction. Its `v̂` bounds are never
  redundant or silently tightening, and the docstring's claims about which bound is load-bearing
  match a test that checks them.
- [ ] **FIX-03**: Every limited branch enforces the receiving-end apparent-power limit (thesis
  3.37, `|(P − r·l, Q − x·l)| ≤ S̄`) as well as the sending-end one, and a PV back-feed fixture
  shows the reverse limit binding.

### Correctness — devices (FIX)

- [ ] **FIX-04**: `PVBattery` and `FourQuadBESS` link state of charge across the whole horizon
  (`soc[T+1]` with bounds, plus an optional terminal condition), so hour-T charge and discharge
  change stored energy. The regression "soc0 = Emin, discharge at hour T" must be infeasible or give
  zero discharge.
- [ ] **FIX-05**: Flexible loads (interruptible, thermostatic, deferrable) draw reactive power
  through their power factor, `q = p·tanφ` (thesis 3.23), flowing into `:Rq`. A per-device test
  checks the reactive injection.

### Correctness — integer planning (FIX)

- [ ] **FIX-06**: `corner_recourse` returns the true Q(bᵛ) for T > 1 (a per-hour minimization, not
  a flat `fill(z, T)` profile), or rejects T > 1 with a clear error. A T > 1 test compares the
  Laporte–Louveaux loop against exhaustive enumeration.

### Correctness — pricing & certificates (FIX)

- [ ] **FIX-07**: DLMP decomposition components are named and documented after what they are
  mathematically: cone-slot and drop-constraint multipliers. They are not called "loss" and
  "voltage" unless a derivation justifies it. The test for "voltage component ≈ 0 when no voltage
  bound binds" uses realistic impedances and either passes or is replaced by a correct property.
- [ ] **FIX-08**: The SOCP exactness gate uses a per-branch relative floor (for example relative to
  that branch's thermal limit or head-branch magnitude), so lightly loaded branches are actually
  checked. A test shows a slack cone on a small branch is flagged.
- [ ] **FIX-09**: The FIT-baseline counterfactual is certified: exactness is asserted or reported,
  never skipped. The Phase-18 `fit_baseline` `ALMOST_OPTIMAL` flake at `tol_gap=1e-10` is
  root-caused and fixed or explicitly bounded (carry-over).
- [ ] **FIX-10**: MPC realized welfare and regret are settled against the truth plant: realized PV
  clips charging, true-state propagation is checked for feasibility, and settlement uses the true
  import. The forecast-settled number is kept only as a separately labelled diagnostic.
- [ ] **FIX-11**: After FIX-01..10, every affected golden is re-derived with an explanation, and
  the v2.1 thesis reproduction (DSO-surplus sign flip, welfare-magnitude gap) and the v2.1/v3.0
  SOCP-inexactness findings are re-run and restated in the literate docs and PROJECT.md, including
  any that changed.

### Planning depth (BILEV)

- [ ] **BILEV-01**: Researcher can solve a genuinely bilevel TSO–DSO variant. The TSO follower
  minimizes its own cost, the DSO leader pays a tariff π·z, and the follower's objective differs
  from the leader's view of it. It is solved by the hand-rolled loop, or by an appropriate
  reformulation where plain Benders is no longer valid, with the method documented.
- [ ] **BILEV-02**: The BilevelJuMP certification includes a fixture on which the bilevel optimum
  provably differs from the joint single-level optimum, and the production method matches the
  bilevel answer, not the joint one.
- [ ] **BILEV-03**: `solve_stackelberg!` runs with `ConvexBranchFlow` on a multi-bus feeder
  (IEEE-13 or larger) and T > 1 inside the Benders loop, and converges with a closed LB/UB gap.
- [ ] **BILEV-04**: The planning oracle produces feasibility cuts when a pinned z is
  voltage- or thermally infeasible, and handles SOCP inexactness at a pinned z with a documented
  policy (restricted formulation, AC fallback, or reported cut rejection) instead of crashing the
  loop.
- [ ] **BILEV-05**: The master's α lower bounds (`α_op_lb`, `α_x_lb`) are derived automatically,
  for example from the relaxed oracle or follower optimum. A user-supplied bound above the true
  minimum is detected and rejected.
- [ ] **BILEV-06**: A Nash fixture with interior investment caps exposes a continuum of generalized
  Nash equilibria (the probe reports a nonzero spread). A variational-equilibrium (common shared
  multiplier) selection is available and documented.
- [ ] **BILEV-07**: Researcher can run integer investment in the N > 1 Nash diagonalization path,
  with each best response using the integer master (carry-over).
- [ ] **BILEV-08**: The docs state the game-theoretic nature of each planning variant: the
  integrated problem decomposed by Benders, the genuine bilevel, and the shared-constraint GNE.
  `docs/writeups/stackelberg_vs_psr_n1n2.typ` is refreshed to the current code, including the
  integer master.

### Architecture (ARCH)

- [ ] **ARCH-01**: Researcher can select the power-flow formulation declaratively in `Scenario`,
  and `run_scenario` honours it; nothing is hard-coded to `ConvexBranchFlow()`.
- [ ] **ARCH-02**: Solve strategies are types (`Centralized`, `ADMM`, `MPC`, `Stochastic`)
  dispatched by one `run(strategy, scenario)` entry point that returns results with a common shape.
  `Scenario` no longer carries strategy-specific fields in one flat bag.
- [ ] **ARCH-03**: `Feeder` and `MeshedFeeder` share an `AbstractFeeder` supertype, and consumers
  dispatch on it.
- [ ] **ARCH-04**: One `close_balance!` helper replaces the five copied balance-closing blocks in
  `welfare_solve`, `mpc_window`, `stochastic_welfare`, `DsoOpt` and `linear_solve`.
- [ ] **ARCH-05**: `solve_admm` is split into named phases (build, iterate, ρ adaptation,
  certification). Reactive-mode behaviour is dispatched, not repeated `mode == …` branches. It
  accepts any valid `AbstractPowerFlow`.
- [ ] **ARCH-06**: Meshed topology plus live ADMM reactive pricing runs end-to-end and is
  cross-validated against the centralized meshed `:balance_q` dual (carry-over MESH-06).
- [ ] **ARCH-07**: `ModelContext` carries typed fields for its fixed metadata (power-flow
  variables, objective, feeder, device variables) in place of an untyped `Dict{Symbol,Any}`
  interface. Downstream code dispatches on the formulation type, not on `haskey(pf_vars, :l)`.
- [ ] **ARCH-08**: One documented status policy covers all solve entry points: when they return a
  status and when they throw. `solve_admm`, `solve_stackelberg!`, `run_nash!`, `run_mpc` and
  `run_stochastic` follow it consistently.
- [ ] **ARCH-09**: The `mpc_loop` exception handlers catch only solver-status and certificate
  exceptions. Programming errors such as `MethodError` and `BoundsError` propagate.
- [ ] **ARCH-10**: IEEE-8500 performance and memory work (carry-over SCALE-STRETCH): the final
  consolidation's `assert_socp_exact!` behaves correctly at scale, and at least one converged,
  memory-feasible headline point is measured, or the wall is re-characterized after the
  architecture changes.

### Hygiene (HYG)

- [ ] **HYG-01**: Source comments and docstrings contain no plan, wave, task, decision or
  review-finding IDs (such as `plan 04-02`, `D-09`, `WR-01`, `Pitfall 7`, `byte-identical`), and a
  CI grep guard enforces this. Thesis-equation and literature references stay.
- [ ] **HYG-02**: The inert SEAM-01 stubs (`operational_oracle`'s ignored `objective_hook` and
  `horizon_state`, and the superseded `z` path) and the reactive-mode Bool/Symbol back-compat shim
  are removed.
- [ ] **HYG-03**: The export list is trimmed and generic names (`OFF`, `LIVE`, `CERTIFIED`, `LP`,
  `QP`, `SOCP`, `NLP`, `MILP`, `record!`, `converged`) are namespaced or unexported. The top-module
  docstring describes the module as it is now.
- [ ] **HYG-04**: A JET check runs in CI over the package, in report mode with an agreed baseline.
- [ ] **HYG-05**: Tests carry a `:slow` tag. CI runs a fast job on every push and the slow suite
  in a separate or nightly job.
- [ ] **HYG-06**: Known flakes (Clarabel `NUMERICAL_ERROR` on IEEE-13 ADMM, the stochastic-welfare
  flake) are fixed or quarantined with `@test_broken` or retry-and-report, so a green suite means
  green.
- [ ] **HYG-07**: Test fixture files and tags are named after their content, not the planning
  phase (no `fixtures_phaseN`, `:phaseN`).
- [ ] **HYG-08**: `scripts/` has an index. One-off and superseded scripts are archived, and the
  `pv_boom_report*` duplication is merged into shared code. The redundant root `Manifest.toml`
  is dropped or its purpose documented, and `.planning/tmp/` is untracked.

## Future Requirements (deferred)

- Stochastic Lagrangian / scenario decomposition (DualDecomposition.jl) for large scenario trees.
- Unbalanced three-phase modeling.
- Integer binary-expansion of the interconnection flow z with a MIP second stage and Lagrangian
  cuts (the PSR note's actual integer difficulty), beyond BILEV-07's integer leader investment.

## Out of Scope

| Feature | Reason |
|---------|--------|
| New research axes (beyond deepening existing ones) | This milestone is about correctness and depth; breadth was v3.0 |
| Rewriting `.planning/` history or moving it out of the repo | Process artifact; filtering is handled by `gsd-pr-branch` when needed |
| GUI / dashboards | Research library (unchanged project-level exclusion) |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| *(filled by roadmapper)* | | |

**Coverage:**
- v4.0 requirements: 37 total
- Mapped to phases: 0 (pending roadmap)

---
*Requirements defined: 2026-09-28*
*Last updated: 2026-09-28 at milestone v4.0 start*

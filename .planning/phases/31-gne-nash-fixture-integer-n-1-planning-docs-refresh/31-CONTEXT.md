# Phase 31: GNE Nash Fixture, Integer N>1 & Planning Docs Refresh - Context

**Gathered:** 2026-10-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the shared-constraint Nash layer honest about equilibrium multiplicity and extend it to
integer investment, then refresh the planning docs to the current code:
- BILEV-06: a Nash fixture with INTERIOR investment caps exposes a continuum of generalized Nash
  equilibria (probe reports a nonzero spread), and a variational-equilibrium (common shared
  multiplier) selection is available and documented.
- BILEV-07: integer investment runs in the N>1 Nash diagonalization path, each best response using
  the integer master.
- BILEV-08: docs state the game-theoretic nature of each planning variant (integrated decomposed by
  Benders, genuine bilevel, shared-constraint GNE), with `docs/writeups/stackelberg_vs_psr_n1n2.typ`
  refreshed to current code including the integer master.

Out of scope: integer binary expansion of z with MIP second stage / Lagrangian cuts (deferred in
REQUIREMENTS.md), IEEE-8500 scale (Phase 35), architecture refactors (Phases 32–34).

</domain>

<decisions>
## Implementation Decisions

### GNE fixture with interior caps (BILEV-06a)
- Fixture: a variant of the existing 2-distributor toy (`test/test_planning_nash.jl`, T=1,
  corridor_cap=2.0, c_inv, c_op) with caps chosen so the POOLED corridor capacity constraint binds
  while no individual `x_inv_max[i]` binds — opening a 1-D continuum in how the shared capacity is
  split.
- Ground truth: the equilibrium set is derived ANALYTICALLY (an interval), documented beside the
  fixture; the test asserts the probe's observed spread lies within that interval and exceeds a
  MEASURED floor (not a picked one).
- Probing: reuse `run_nash_probe` with enough seeds/orders that distinct starting points land on
  distinct equilibria.
- The existing corner-cap fixture (`x_inv_max=[0.3,0.3]`) is KEPT as the unique-equilibrium control;
  its spread must remain 0.

### Variational-equilibrium selection (BILEV-06b)
- New standalone `solve_variational_equilibrium(shared; ...)`; `run_nash!` unchanged.
- Method: if research confirms players' costs are separable except through the shared constraint,
  solve ONE joint model containing the shared row once (VE ⇔ equal shared-row multipliers); verify the
  multiplier equality explicitly.
- Certification: assert every player's shared-row multiplier is identical (measured tolerance) AND
  the VE lies inside the analytic GNE interval from the fixture above.
- Fallback if the game is NOT separable: multiplier-equalization inside the diagonalization loop,
  documented — not PATHSolver (no new dependency).

### Integer investment at N>1 (BILEV-07)
- API: `run_nash!(...; integer = (; K, ...))` builds a FRESH `build_master_integer` per best response
  via `solve_stackelberg!`'s existing `master=` keyword.
- Certification: on N=2 with small K, brute-force enumerate the integer grid and assert no profitable
  unilateral deviation at the reported equilibrium.
- Phase-30 open integer-path review warnings are FIXED here (they become load-bearing):
  (WR-01) `ALMOST_INFEASIBLE` in the integer corner search must be classified/confirmed, not mapped
  to +Inf blindly; (WR-02) validate the integer master's `L = α_op_lb + α_x_lb` and enforce the
  Laporte–Louveaux cut validity condition `Q_ν ≥ L` (and correct `add_ll_cut!`'s docstring math);
  see `.planning/phases/30-*/30-REVIEW.md` and `30-FINDINGS.md`.
- Cycling: an integer diagonalization that cycles is detected and reported loudly (with the cycle),
  never claimed converged.

### Planning docs refresh (BILEV-08)
- Scope: full refresh of `docs/writeups/stackelberg_vs_psr_n1n2.typ`, the variant taxonomy in
  `docs/writeups/modelo_stackelberg_dso_unico.typ`, and the Documenter API docstrings of the three
  entry points (`solve_stackelberg!`, `solve_bilevel!`, `run_nash!` / `solve_variational_equilibrium`).
- Content: a taxonomy table — integrated-decomposed-by-Benders (`solve_stackelberg!`), genuine bilevel
  (`solve_bilevel!`), shared-constraint GNE/VE (`run_nash!` / `solve_variational_equilibrium`) — every
  claim citing the backing function and test, including the integer master and the Phase-30
  SOCP/inexactness policy.
- Language: keep each writeup in its current language (Portuguese).
- Build: compile PDFs with `typst compile` and commit them alongside the sources (as today).

### Claude's Discretion
- Exact fixture numbers (must produce the stated binding pattern; derivation documented), tolerance
  values (measured), naming of new result fields.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/planning/nash.jl`: `run_nash!` (Gauss–Seidel diagonalization; fresh oracle/follower/master per
  best response via `solve_stackelberg!(...; follower = DistributorView(shared, i), follower_kwargs =
  NamedTuple())`; since Phase 30: `inexact_policy` default `:strict`, `certificates`,
  `any_relaxation_only`), `run_nash_probe` (multi-seed/multi-order spread: `z_spread`,
  `x_inv_spread`, `cost_spread`), `NashTrace`.
- `src/planning/coupling.jl`: shared transmission model (`build_shared_transmission`, pooled
  `capacity[t]: Σⱼ x_op[j,t] <= corridor_cap·Σⱼ x_inv[j]`), `DistributorView`.
- `src/planning/master_integer.jl`: `build_master_integer` (binary expansion, K levels),
  `add_ll_cut!`; `src/planning/benders.jl`: `corner_recourse`, `_oracle_or_infeasible`,
  `ll_cut_recourse`.
- `docs/writeups/*.typ` (Portuguese Typst), `typst` available at `~/.local/bin/typst`.
- `docs/literate/nash_diagonalization.jl`, `docs/literate/integer_investment.jl`.

### Established Patterns
- Hand-derived toy fixtures with derivation comments beside the constants; measured tolerances.
- Probe honesty: never pick `runs[1]`; report the spread.
- Fail loud on non-convergence; no try/catch around `run_nash!` in the probe (T-13-10).

### Integration Points
- PVAL-04 registry (`test/test_planning_noninteger.jl`) for any new planning `build_*`.
- Phase-30 always-on α validation adds a relaxed solve per best response (~1.9%); integer masters
  per best response add MILP solves — measure Nash runtime impact.

</code_context>

<specifics>
## Specific Ideas

- Executors verify via `JULIA_LOAD_PATH="test:.:@stdlib"` direct scripts / the top-level @testitem
  emulator; never TestItemRunner under `--project=.`; the full suite is run once by the orchestrator.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

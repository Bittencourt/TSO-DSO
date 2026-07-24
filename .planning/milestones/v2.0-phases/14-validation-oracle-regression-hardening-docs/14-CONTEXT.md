# Phase 14: Validation-Oracle Regression Hardening & Docs - Context

**Gathered:** 2026-07-24
**Status:** Ready for planning

<domain>
## Phase Boundary

One-off validation runs (BilevelJuMP certification, diagonalization convergence) become permanent
regression infrastructure, the planning math is literate-documented and traced to code, and
continuous-only scope is enforced automatically rather than by convention. Requirements: PVAL-02,
PVAL-03, PVAL-04 (PVAL-01 already delivered in Phase 11 and retained as a permanent regression).

Deliverables: pinned computed goldens for the canonical N=1 and N=2 planning fixtures, literate
Documenter pages mapping the PSR planning-layer problem numbers / coupling seam / leader-follower
choice to the actual code, and an automated no-binaries guard over every planning-layer subproblem
builder.

</domain>

<decisions>
## Implementation Decisions

### Golden Fixture Pinning (PVAL-02)
- Pin BOTH canonical fixtures: N=1 certified Stackelberg equilibrium (z*=0.7, cost −0.245, coupling
  duals — the Phase 11 certification case) and the N=2 Nash fixture (z, x_inv, per-distributor cost,
  probe spread from Phase 13's hand-checked congested equilibrium).
- Golden values live as hardcoded literals in a new `test/fixtures_planning.jl` — matches the
  existing `fixtures_phaseN.jl` computed-golden convention (reproducibility anchors, commented).
- Two-layer gating semantics: BilevelJuMP agreement (N=1) and diagonalization convergence (N=2)
  are asserted as the GATE first, then value regression against the pinned goldens in the same
  testitems. Goldens are never trusted without the gate re-passing.
- Tolerance policy follows Phase 11 certification: rel 1e-6 on objective/z; looser, explicitly
  documented tolerance on duals; a rationale comment per pinned value.

### Literate Documentation (PVAL-03)
- Two new Literate pages continuing the existing rung-ladder convention:
  "Rung 6: Stackelberg–Benders (planning)" and "Rung 7: Nash Diagonalization & Shared Corridor",
  wired as a new "Planning" section in `docs/make.jl` pages.
- Content contract: PSR problem-number ↔ code-symbol map, coupling-seam table (`z↔p_ag`,
  `λ_j↔π_s`), and the interpretive leader/follower choice INCLUDING the Phase 11 empirical
  certification story (StrongDualityMode / ProductMode / hand enumeration / production Benders
  4-way agreement).
- `@example` blocks execute live on tiny fixtures (seconds-scale), matching existing rung pages —
  real output rendered in the docs build.
- Exported planning symbols get docstrings surfaced via the existing `api.md` `@autodocs`
  (`checkdocs = :exports` already enforces coverage); no manual `@docs` blocks needed.

### No-Binaries Guard (PVAL-04)
- Enforcement is a dedicated `@testitem` that BUILDS every planning-layer model via its public
  builder and asserts zero `is_binary`/`is_integer` variables — semantic check, not a grep lint.
- Builder coverage via an explicit registry (planning oracle, FollowerLP, BendersMaster,
  SharedTransmission) PLUS a tripwire asserting the registry covers all `src/planning/` builder
  entry points, so a future builder cannot silently skip the guard.
- Failure mode is fail-loud: name the offending variables and the owning builder.
- Guard is test-only (no runtime overhead; builders stay clean). No runtime `assert_continuous!`.

### Regression Suite Wiring (PVAL-01 retention + CI gate)
- New `test/test_planning_goldens.jl` with default-on inclusion in the same `Pkg.test` gate as the
  existing acceptance regression — the same CI gate that runs PVAL-01.
- Runtime budget: tiny fixtures only; target <60s for the new golden set.
- PVAL-01 (`test/test_planning_certification.jl`) stays untouched and in-suite; the goldens file
  carries an explicit cross-reference documenting the gate relationship.
- Docs build stays OUT of `Pkg.test` (existing convention — docs CI builds separately); the
  goldens gate remains solver-only.

### Claude's Discretion
- Exact Literate page prose structure, section ordering, and figure choices.
- Naming of the builder-registry tripwire mechanism and its discovery heuristic.
- Whether the N=2 golden pins the probe spread value itself or a bound on it (pick whichever is
  robust to solver noise, with rationale documented).

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- Computed-golden convention: `test/test_acceptance.jl` ("pinned computed golden regression"
  @testitem) and `test/fixtures_phase4.jl` (COMPUTED golden as reproducibility anchor, commented).
- PVAL-01 permanent regression: `test/test_planning_certification.jl` (4-way certification,
  `[:planning]`-tagged).
- Phase 13 fixtures: hand-checked N=2 congested equilibrium (z=[0.6,0.6], x_inv=[0.3,0.3]) and
  seed-liveness fixtures in `test/test_planning_nash.jl`; `run_nash_probe` 6-run gate.
- Literate pipeline: `docs/literate/*.jl` → `docs/src/generated/*.md`; six existing rung pages
  as structural templates (toy_dc.jl is the smallest example).

### Established Patterns
- `docs/make.jl`: pages tree with "Models" rung section; `checkdocs = :exports` (undocumented
  exported symbol FAILS the build); `remotes = nothing` for worktree-safe builds; api.md
  `@autodocs` with raised size_threshold.
- Tests: `@testitem` per concern, TestItemRunner, tags like `[:planning]`; fail-loud ArgumentError
  convention throughout planning layer.
- Known gotcha: bare `@run_package_tests` discovers `.claude/worktrees/` copies — verification
  should use explicit paths/filters from a scratch environment.

### Integration Points
- `docs/make.jl` pages array (add "Planning" section) and `docs/literate/` (new .jl sources).
- `test/runtests.jl` auto-discovers new test files (no wiring needed beyond file creation).
- `src/planning/` public builders: `build_planning_oracle`, `FollowerLP`, `BendersMaster`,
  `build_shared_transmission` — the guard registry's coverage set.

</code_context>

<specifics>
## Specific Ideas

- The "never THE equilibrium" reporting language (Phase 13's structural rule) should carry into
  the Rung 7 docs page verbatim — report "a converged equilibrium (spread: …)".
- Golden regression must remain meaningful under the documented CairoMakie-weakdep broken-test
  skips; the goldens file must not depend on plotting.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

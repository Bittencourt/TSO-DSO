# Phase 9: Documentation & Regression Acceptance Gate - Context

**Gathered:** 2026-07-20
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous) — all four grey areas accepted as recommended

<domain>
## Phase Boundary

Close the v1 milestone with the hard documentation requirement and the acceptance gate:
1. **EXP-03** — literate, reproducible per-model math documentation (Documenter + Literate) stating
   each model's math (thesis equation references), assumptions, and validation.
2. **EXP-04** — regression fixtures that pin reference results (IEEE 13/123, FIT comparison) so
   numerical drift is caught automatically.
3. **SC3 / acceptance gate** — an end-to-end reproduction of the two headline cases: IEEE-13
   congestion + IEEE-123 voltage, each with exact SOC relaxation, recovered DADP, and ADMM matching
   the centralized optimum.

Out of scope: v2 axes (Stackelberg-Nash planning, meshed/4Q-BESS, stochastic/MPC) — SEAM-01 stubs
already delivered in Phase 4. No thesis-figure digitization (the Phase 4/5 welfare-headline
reconciliation) — that remains a documented deferred TODO.

</domain>

<decisions>
## Implementation Decisions

### Literate Documentation Scope (EXP-03)
- One literate page per rung of the abstraction ladder — extend the existing `docs/literate/toy_dc.jl`
  pattern with pages for: LinDistFlow (linear branch flow), SOCP Convex Branch-Flow + exactness,
  Prosumer devices + GLB-CVX social-welfare solve, DADP/DLMP decomposition, and ADMM (~5–6 new pages).
- Math rendered as KaTeX equations inline, each citing the thesis equation number (e.g. "(3.31)",
  "(3.39)", "(3.43–3.45)") beside the corresponding code — per the CLAUDE.md hard requirement that
  every model's equations sit next to the code.
- Numbers in docs come from real `@example` solves executed during `makedocs` (rendered numbers
  cannot drift from the code), extending the toy_dc `documenter = true` pattern.
- Each page follows the structure: math → assumptions → validation (exactness check `l·v ≈ P²+Q²`,
  dual/price recovery, ADMM-vs-centralized), so every modeling decision is documented with its math.

### v1 Acceptance Gate (SC3)
- Form: a dedicated `test/test_acceptance.jl` @testitem that runs both headline cases end-to-end —
  IEEE-13 congestion and IEEE-123 voltage — asserting exact relaxation + recovered DADP + ADMM ≈
  centralized optimum in one place.
- Tolerances: reuse the already-pinned per-phase tolerances (exactness ~1e-6…1e-9, ADMM-vs-centralized
  welfare gap ~1e-6, DADP match) — do not invent new/looser acceptance tolerances.
- Solver path: open-source only (Clarabel / HiGHS / Ipopt), matching the reproducibility requirement.
- Known welfare-headline gaps: gate on the COMPUTED goldens (the reproducibility anchors already
  accepted by the researcher in Phase 4/5). Keep the thesis +$1819 / +25% headline numbers as
  NON-FAILING, documented cross-checks. Do NOT block the gate on thesis-numeric welfare match
  (figure-digitization is a deferred TODO).

### Regression Fixture Strategy (EXP-04)
- Keep the existing, working inline per-phase pins (1933 tests green) and ADD a consolidated
  regression/acceptance layer that references them — do not rip out working pins.
- Pin the FIT-vs-DADP comparison as a regression (extends existing `test_pricing_fit` / `test_fit`)
  on the computed golden.
- Golden storage format: inline typed constants + `rtol` (the established project convention);
  reserve the Phase-8 JLD2/CSV harness for experiment outputs, not unit-test goldens.
- Drift detection: `@test` with `rtol` on pinned constants — numerical drift is caught by the CI
  test run.

### Docs Build & CI
- Docs build runs in CI: `makedocs` with `@example` execution is itself the docs reproducibility gate.
- Tighten `checkdocs` for public API docstrings (from `:none`), keeping `warnonly` for the remainder
  so the build stays green while surfacing missing docs.
- Wire `deploydocs` gated on the `CI` env var (never deploy from a local/worktree checkout — the
  Phase-1 `remotes = nothing` note documents why).
- Include CairoMakie figures (convergence residuals, voltage profiles, DLMP decomposition) in the
  relevant pages — weakdep-gated so the build degrades gracefully when CairoMakie isn't installed.

### Claude's Discretion
- Exact page ordering, filenames, and Documenter `pages` tree layout.
- How the consolidated acceptance/regression testitem is wired relative to the existing per-case tests.
- Whether the docs CI job is a separate workflow file or a step in the existing matrix.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `docs/make.jl` — working Documenter + Literate build; `Literate.markdown(...; documenter = true)`
  emits `@example` blocks that execute during `makedocs`. Currently builds `index.md` + the generated
  `toy_dc.md`. `remotes = nothing`, `checkdocs = :none`, `warnonly = [:missing_docs, :cross_references]`.
- `docs/literate/toy_dc.jl` — the literate page pattern to replicate per model.
- `docs/Project.toml` / `docs/Manifest.toml` — docs environment already pinned.
- Existing IEEE acceptance tests: `test/test_ieee13.jl`, `test/test_ieee123.jl`, `test/test_ieee123_admm.jl`.
- Existing pricing/FIT tests: `test/test_pricing_fit.jl`, `test/test_fit.jl`, `test/test_pricing_dlmp.jl`,
  `test/test_pricing_welfare.jl`, `test/test_economic_direction.jl`.
- Exactness test: `test/test_exactness.jl`; oracle cross-check: `test/test_oracle.jl`.
- CairoMakie plots (weakdep-gated) live in `ext/TSODSOMakieExt.jl` (`plot_convergence`,
  `plot_price_convergence`).

### Established Patterns
- Regression values pinned INLINE as typed constants + `rtol` in `test/fixtures_phaseN.jl` and
  `test/test_*.jl` — not as external golden files.
- Tests use TestItemRunner `@testitem`; suite runs via `julia --project=. -e 'using Pkg; Pkg.test()'`
  (runtests.jl → `@run_package_tests`). Full suite currently 1933 pass / 0 fail / 2 pre-existing broken.
- Solver factory abstracts Clarabel/HiGHS/Ipopt; models never name a solver.

### Integration Points
- New literate pages → `docs/literate/*.jl` + `docs/make.jl` `pages` tree.
- New acceptance test → `test/test_acceptance.jl` (auto-discovered by TestItemRunner).
- Docs CI → `.github/workflows/` (add docs build/deploy job).

</code_context>

<specifics>
## Specific Ideas

- Thesis equation references to cite: LinDistFlow (3.43–3.45 exactness copy), SOC cone (3.39), nodal
  active balance / DADP dual (3.31), aggregator (3.22/3.23/3.46). Source PDFs vendored in
  `docs/references/`.
- The acceptance gate must reproduce: IEEE-13 voltage (thesis v ≈ 1.049 pu at the pinned node,
  matched to ~0.5%) and IEEE-123 voltage-binding ADMM convergence (~17 iters, welfare gap ~1e-6,
  PF-04 exact ~1e-9).

</specifics>

<deferred>
## Deferred Ideas

- Thesis-figure digitization (recover exact MEM price / temperature / house-count inputs to close the
  Phase-4 welfare gap and the Phase-5 +25% headline) — documented TODO in STATE.md, NOT part of v1.
- WR-02 (Phase-8 code review): replace `sub_seed`'s `Base.hash` derivation with a cross-version-stable
  hash and re-tune ADMM ρ / battery τ defaults — researcher decision, tracked in Phase-8 deferred-items.
- IEEE-123 exact thesis App. E per-terminal impedances (current fixture uses representative in-band
  per-unit values at 1 MVA base) — documented Phase-7 follow-up.
- CairoMakie visual-aesthetic eyeball check in a non-headless env (Phase-7 deferred manual item).

</deferred>

---
phase: 18
slug: directional-thesis-reproduction
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-26
---

# Phase 18 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `18-RESEARCH.md` § Validation Architecture.
> **Central finding driving this strategy:** the thesis's aggregate welfare *ratio* (+25%) is NOT
> sign-safe on this framework's real-data fixtures (+0.045% on real IEEE-123; sign-inverted on
> IEEE-13 via a naive ratio). The robust, correctly-signed reproduction is the **DSO-surplus sign
> flip** (thesis's own "DSO surplus X→Y" framing) + prosumer-surplus decrease. Pin the golden on
> THAT, framed "directional, public-data."

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `TestItems` + `TestItemRunner` (`test/runtests.jl` → `@run_package_tests`) |
| **Quick run command** | `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib" julia -e 'using TestItemRunner, TSODSO; TestItemRunner.run_tests(joinpath(pwd(), "test"); filter=ti->occursin("thesis_repro", ti.name))'` — use the EXPLICIT-PATH `run_tests` form (NOT bare `@run_package_tests` via `-e`; `.claude/worktrees/` cross-contamination gotcha, memory `local-project-toml-drift`) |
| **Full suite command** | `julia test/runtests.jl` (real file — unaffected by the worktree-path gotcha) |
| **Docs-executes-live gate** | `julia --project=docs docs/make.jl` (both new literate pages execute live) |
| **Estimated runtime** | quick ~seconds; full suite low single-digit minutes; docs build minutes |

---

## Sampling Rate

- **After every task commit:** quick filtered `thesis_repro` `@testitem`.
- **After every plan wave:** full suite (`julia test/runtests.jl`).
- **Phase gate:** full suite green **PLUS** `docs/make.jl` builds (both literate pages live-execute) before `/gsd:verify-phase`.
- **Baseline:** current suite is **2342 passed / 2 failed (pre-existing Aqua CairoMakie/Makie drift) / 3 broken** — Phase 18 must add ZERO new failures beyond the 2 Aqua.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 18-01-* | 01 | 1 | REPRO-02 | script + findings artifact | `julia --project=. scripts/repro_stability_check.jl` | ❌ W0 (new) | ⬜ pending |
| 18-02-* | 02 | 2 | REPRO-01 | acceptance (gate-then-golden) | `... run_tests(...; filter=occursin("thesis_repro"))` | ❌ W0 `test/test_thesis_repro.jl` | ⬜ pending |
| 18-03-* | 03 | 3 | REPRO-01, REPRO-02 | doc-build gate | `julia --project=docs docs/make.jl` | ❌ W0 (2 literate pages + make.jl) | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

### Requirement → Behavior detail

- **REPRO-02 stability FIRST (Wave 1, BLOCKING before any golden is pinned)**: `scripts/repro_stability_check.jl` (mirror `scripts/reactive_flake_rate.jl`) runs N≥20 repeats for a discrete flake-rate measurement **PLUS a ±2–5% population-scale sweep** probing whether the DSO-surplus sign flip survives near Phase-17's documented exactness knife-edge. Commit `results/repro_stability_check/findings.txt`. The measured spread INFORMS the pinned magnitude band — the golden must not be pinned before this runs.
- **REPRO-01 gate-then-golden (Wave 2)**: `test/test_thesis_repro.jl` on the real-impedance IEEE-123 fixture asserts (a) SOCP exact at the operating point, (b) **DSO surplus sign flip**: FIT DSO surplus < 0 → DADP DSO surplus > 0, (c) prosumer surplus decreases under DADP, (d) the magnitude band (from the Wave-1 stability findings) — never a point value. Do NOT pin on the aggregate welfare ratio (not sign-safe). IEEE-13 as a secondary qualitative cross-check only.
- **REPRO-01 literate page (Wave 3)**: `docs/literate/thesis_reproduction_ieee123.jl` (from a new `scripts/thesis_case123_repro.jl`) live-executes the DADP-vs-FIT comparison with reactive pricing + real impedances active; every cited number carries the fixed **"directional, public-data"** qualifier (grep-checked). Registered in `docs/make.jl` (render + nav).
- **REPRO-02 assumptions page (Wave 3)**: `docs/literate/thesis_reproduction_assumptions.jl` enumerates the full chain (units resolution kft, Fortescue reduction fidelity, omitted regulators/caps/switches, aggregator population re-tune LOAD=0.05/PV=0.12/DEV=0.083, PV scenario, the welfare-ratio-vs-surplus-sign metric caveat, the asymmetric voltage-binding caveat).

---

## Wave 0 Requirements

- [ ] `scripts/repro_stability_check.jl` + `results/repro_stability_check/findings.txt` — REPRO-02 measurement, run and committed BEFORE any golden band is pinned
- [ ] `test/test_thesis_repro.jl` — gate-then-golden `@testitem`(s), written AFTER the stability findings inform the band
- [ ] `scripts/thesis_case123_repro.jl` → `docs/literate/thesis_reproduction_ieee123.jl` — promoted literate page
- [ ] `docs/literate/thesis_reproduction_assumptions.jl` — consolidated assumptions page
- [ ] `docs/make.jl` — 2 new `Literate.markdown` render entries + 2 new `pages=` nav entries
- [ ] Framework install: none

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| "directional, public-data" qualifier present on every cited number | REPRO-01 | Prose-placement is best confirmed by grep + reviewer | `grep -c "directional, public-data"` across the literate pages + any script that prints the reproduction numbers; reviewer confirms no bare cited figure |
| The honest metric caveat reads correctly | REPRO-02 | Pedagogical clarity not machine-checkable | Reviewer confirms the assumptions page explains WHY the golden pins on the DSO-surplus sign flip, not the welfare ratio (ratio not sign-safe on real-data fixtures) |

---

## Validation Sign-Off

- [ ] Stability measurement (Wave 1) run + findings committed BEFORE golden pinned (REPRO-02 ordering)
- [ ] Golden pins on DSO-surplus sign flip + prosumer decrease + band, NOT the welfare ratio
- [ ] "directional, public-data" qualifier grep-verified on every cited number
- [ ] Both literate pages live-execute in `docs/make.jl`
- [ ] ZERO new suite failures beyond the 2 pre-existing Aqua
- [ ] `nyquist_compliant: true` set by plan-checker

**Approval:** pending

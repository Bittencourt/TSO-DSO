---
phase: 14
plan: 03
subsystem: docs
tags: [documenter, literate, planning-layer, stackelberg-benders, nash-diagonalization, api-reference]
requires:
  - src/planning/retry.jl (RETRYABLE_STATUSES, solve_with_retry!)
  - src/planning/checkpoint.jl
  - src/planning/trace.jl (BendersTrace, NashTrace)
  - src/planning/subproblem.jl (PlanningOracle, build_planning_oracle, solve_planning_oracle!)
  - src/planning/follower.jl (FollowerLP, build_follower, solve_follower!)
  - src/planning/master.jl (BendersMaster, build_master, solve_master!)
  - src/planning/benders.jl (solve_stackelberg!)
  - src/planning/coupling.jl (SharedTransmission, build_shared_transmission, activate_distributor!, write_back!, DistributorView)
  - src/planning/nash.jl (run_nash!, run_nash_probe, trace_summary, is_converged)
  - src/devices/Deferrable.jl (public elastic-load substitute for a test-only fixture)
provides:
  - "docs/src/api.md Planning Layer @autodocs section (fixes the standing 33-orphaned-docstring Documenter defect)"
  - "docs/literate/stackelberg_benders.jl — Rung 6 literate page"
  - "docs/literate/nash_diagonalization.jl — Rung 7 literate page"
  - "docs/make.jl wiring for both new pages"
affects:
  - published docs site navigation (new Planning pages subsection)
requirements-completed: [PVAL-03]
tech-stack:
  added: []
  patterns:
    - "Literate @example pages narrate (never re-execute) a test-only validation-oracle story by citing the test file by name — keeps docs/Project.toml dependency-free of test-only packages (BilevelJuMP/HiGHS/Ipopt)"
    - "When a certified test fixture depends on a test-only device struct, reconstruct an economically-equivalent instance from the PUBLIC device library (Deferrable's U(p)=-(b/2)(p-E)^2 expands to a*p-(b/2)p^2 with a=b*E) rather than adding a new docs dependency"
key-files:
  created:
    - docs/literate/stackelberg_benders.jl
    - docs/literate/nash_diagonalization.jl
  modified:
    - docs/src/api.md
    - docs/make.jl
decisions:
  - "Substituted the certified fixture's test-only ToyElasticDevice with the public Deferrable device (E=6.0, b=1.0) for both new Literate pages, since ToyElasticDevice is a @testmodule-scoped struct unreachable from docs/ without introducing a new dependency; verified algebraically and numerically equivalent (converges to the same y*=z*~0.7 Rung 6 answer and the exact hand-checked z=[0.6,0.6]/x_inv=[0.3,0.3] Rung 7 answer)"
metrics:
  duration: "~70 min"
  completed: 2026-07-24
---

# Phase 14 Plan 03: Documenter Planning-Layer Docs — Rung 6/7 + api.md Fix Summary

Turned the standing-red Documenter build green (33 orphaned planning-layer docstrings) and added the two PVAL-03 literate rung pages narrating the Stackelberg-Benders and Nash-diagonalization planning layer, using a public-API-only toy fixture that reproduces the Phase 11/13 certified/hand-checked numbers live.

## What Was Built

**Task 1 — `docs/src/api.md` Planning Layer section.** Added a new `## Planning Layer` `@autodocs` section covering all 9 `src/planning/*.jl` files, using `Order = [:type, :constant, :function]` (deliberately different from every other section's `[:type, :function]`) because `planning/retry.jl`'s exported `RETRYABLE_STATUSES` is a top-level `const` — the first exported constant in the project's whole `src/` tree. Verified the red-to-green transition: `julia --project=docs docs/make.jl` failed with `[:missing_docs]` (33 orphaned docstrings) before this task, and exits 0 after it (with only the original 6-page pages tree, before Tasks 2/3 add anything).

**Task 2 — `docs/literate/stackelberg_benders.jl` (Rung 6).** A new Literate page: a PSR problem-number-to-code-symbol map (follower LP → `build_follower`/`solve_follower!`, Benders master → `build_master`/`add_optimality_cut!`/`add_feasibility_cut!`/`solve_master!`, outer loop → `solve_stackelberg!`); a coupling-seam markdown table (`z` ↔ `p_import`/`p_ag`, `λ_j` ↔ `π_s`); a prose narrative of the Phase 11 empirical certification story (StrongDualityMode + ProductMode agreement, documented BigMMode+HiGHS MIQP incapacity, production-Benders 4-way agreement) citing `test/test_planning_certification.jl` by name — never re-executed live, no `BilevelJuMP`/`HiGHS`/`Ipopt` import anywhere in the page. A live `solve_stackelberg!` call displays `result.gap`/`result.y`/`result.z`/`result.UB` as genuinely computed top-level expressions.

**Task 3 — `docs/literate/nash_diagonalization.jl` (Rung 7) + `docs/make.jl` wiring.** A new Literate page: the shared-corridor coupling model math (pooled `capacity[t]` row), the Gauss-Seidel outer-loop narrative, `NashTrace`'s two-level diagnostics description, and the NASH-04 honesty-gate explanation. Live calls to `build_shared_transmission`/`run_nash!` (displaying `result.converged`/`result.z`/`result.x_inv`) and `run_nash_probe` (displaying `probe.summary`/`probe.spread`), using the phrase "a converged equilibrium" and never the phrase "the equilibrium" anywhere in the page's prose. `docs/make.jl` now includes both new sources in the `Literate.markdown` loop (after `admm.jl`) and a new `"Planning"` pages subsection (before `"API Reference"`).

## Key Design Decision — the Deferrable substitution

Both new pages need to build the SAME toy instance the Phase 11/13 test suite certifies/hand-checks, but that fixture's device is `ToyElasticDevice`, a `@testmodule`-scoped struct defined inside `test/test_planning_oracle.jl` — not reachable from `docs/` without adding a new dependency (and the plan explicitly locks "zero new dependencies, docs or otherwise"). `ToyElasticDevice`'s utility is `U(p) = a·p − (b/2)·p²` (`a=6.0`, `b=1.0`, `Pmax=10.0`). The project's PUBLIC `Deferrable` device's own utility (thesis eq. 3.12) is `U(p) = −(b/2)·(p−E)²`, which expands (dropping a constant, per the device's own docstring RESEARCH A5 note) to `b·E·p − (b/2)·p²` — algebraically IDENTICAL to `a·p − (b/2)·p²` whenever `a = b·E`. Setting `Deferrable(bus, 1, 1, E=6.0, Pmax=10.0, b=1.0)` reproduces the exact same economics using only public `TSODSO` API. Verified directly (scratchpad probe, not committed): Rung 6's `solve_stackelberg!` call converges to `y=z≈0.6985` (matching the certified `y*=z*=0.7` neighborhood), and Rung 7's `run_nash!`/`run_nash_probe` calls converge to the EXACT hand-checked `z=[0.6,0.6]`, `x_inv=[0.3,0.3]` from `test/test_planning_nash.jl`.

## Verification

1. `julia --project=docs docs/make.jl` exits 0 after Task 1 alone (api.md fix only) — confirmed the red→green transition.
2. `julia --project=docs -e "using Literate; Literate.markdown(...)"` on `stackelberg_benders.jl` alone completes without error after Task 2.
3. `julia --project=docs docs/make.jl` exits 0 after Task 3 (full build: api.md fix + both new pages + wiring); both `docs/src/generated/stackelberg_benders.md` and `docs/src/generated/nash_diagonalization.md` render non-empty.

All three verification steps ran and passed directly in this session (not merely inferred from acceptance criteria).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 — blocking issue, adapted per plan's own dependency lock] Substituted `ToyElasticDevice` with the public `Deferrable` device**
- **Found during:** Task 2 (carried into Task 3)
- **Issue:** The plan's `<action>` instructs building "the SAME toy instance as `test_planning_certification.jl` lines 176-181", which uses `ToyDeviceFixture.ToyElasticDevice` — a test-only `@testmodule` struct. Reconstructing it inline in a docs page would require `@variable`/`AffExpr` from JuMP, which is not a `docs/Project.toml` dependency (confirmed absent from `docs/Manifest.toml`) and adding it would violate the plan's own explicit "zero new dependencies, docs or otherwise" lock.
- **Fix:** Used the public `Deferrable` device instead, algebraically tuned (`E=6.0`, `b=1.0`, so `a=b·E=6.0` matches the certified fixture's own `a`) to reproduce IDENTICAL economics. Documented the derivation directly in both Literate pages' own prose (not left implicit).
- **Files modified:** `docs/literate/stackelberg_benders.jl`, `docs/literate/nash_diagonalization.jl`
- **Commits:** d7cba96, 3975dc8

No other deviations — Tasks 1 and 3's `docs/make.jl` wiring followed the plan's exact diff shape from `14-PATTERNS.md`.

## Known Stubs

None — every displayed number in both new pages comes from a live, this-session-executed solve; no stub/placeholder/hardcoded value flows into either page.

## Threat Flags

None — both new pages stay within the plan's own locked threat-model disposition (T-14-05: live-executed only; T-14-06: no new BilevelJuMP/HiGHS/Ipopt dependency). No new network-facing surface, auth path, or schema change was introduced.

## Self-Check: PASSED

- FOUND: docs/src/api.md (Planning Layer section present, verified via grep)
- FOUND: docs/literate/stackelberg_benders.jl
- FOUND: docs/literate/nash_diagonalization.jl
- FOUND: docs/make.jl (wiring present, verified via grep)
- FOUND commit 56f050e (docs/src/api.md)
- FOUND commit d7cba96 (stackelberg_benders.jl)
- FOUND commit 3975dc8 (nash_diagonalization.jl + make.jl wiring)
- FOUND: docs/src/generated/stackelberg_benders.md (non-empty, gitignored build artifact)
- FOUND: docs/src/generated/nash_diagonalization.md (non-empty, gitignored build artifact)

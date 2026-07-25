---
phase: 15
slug: ac-exactness-oracle
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-25
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `15-RESEARCH.md` § Validation Architecture.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `TestItemRunner.jl` + `TestItems.jl` (`@testitem`/`@testmodule`, existing project convention) |
| **Config file** | `test/runtests.jl` (`@run_package_tests`, no config beyond this) |
| **Quick run command** | `julia --project -e 'using TestItemRunner, TSODSO; @run_package_tests filter=ti->occursin("ac_oracle", ti.name) \|\| occursin("ac_powerflow", ti.name)'` |
| **Full suite command** | `julia --project -e 'using Pkg; Pkg.test()'` |
| **Docs-executes-live gate** | `julia --project=docs docs/make.jl` (literate rung page runs against real `src/`) |
| **Estimated runtime** | ~10–30 s quick (2-bus / small feeder); full suite minutes (IEEE-13/123 regression) |

---

## Sampling Rate

- **After every task commit:** Run the quick filtered `@run_package_tests` command.
- **After every plan wave:** Run the full suite (`Pkg.test()`) — a new `ACPowerFlow` include must not break an unrelated existing item via `include`-order issues in `TSODSO.jl`.
- **Before `/gsd:verify-phase`:** Full suite green **PLUS** `docs/make.jl` succeeds (literate page executes live).
- **Max feedback latency:** ~30 s quick loop.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------------|-----------|-------------------|-------------|--------|
| 15-01-* | 01 | 1 | EXACT-01 | N/A (numerical) | unit + integration | `... occursin("ac_powerflow", ti.name)` | ❌ W0 `test/test_ac_powerflow.jl` | ⬜ pending |
| 15-02-* | 02 | 2 | EXACT-02, EXACT-03 | N/A | unit | `... occursin("ac_oracle", ti.name)` | ❌ W0 `test/test_ac_oracle.jl` | ⬜ pending |
| 15-03-* | 03 | 3 | EXACT-04 | N/A | unit + literate | quick cmd + `docs/make.jl` | ❌ W0 stress case + `docs/literate/ac_oracle.jl` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

### Requirement → Behavior detail

- **EXACT-01**: `ACPowerFlow <: AbstractPowerFlow` defined; `contribute!` stashes `(;v,P,Q,l)`; `problem_class(::ACPowerFlow) isa NLP`; `solve_welfare(feeder, ACPowerFlow(), aggs; …)` reaches `LOCALLY_SOLVED`/`OPTIMAL` on the 2-bus fixture — dispatched through the **unchanged** `solve_welfare` entrypoint.
- **EXACT-02**: `assert_ac_exact!(ctx_socp, ctx_ac; atol, rtol)` returns a per-hour report (`obj_gap` + `hours` with `vgap`/`pgap`/`qgap`/`exact`) using the scale-free `atol + rtol·magnitude` idiom (peer to `assert_socp_exact!`).
- **EXACT-03**: On a KNOWN-exact fixture (2-bus toy or `pv_scale=0.5`), report shows `all(row.exact …)`; return type is **never** a bare `Bool` and **never throws** on a genuine gap (positive-finding, not a defect).
- **EXACT-04**: On a deliberately over-scaled `pv_scale` stress fixture, report has ≥1 hour `exact=false`, and that hour's `v[j,t]` is at/near `vmax²` (reverse-flow/voltage-binding diagnostic). **Expected gap — positive test.** Documented in `docs/literate/ac_oracle.jl` beside the thesis equations.

### Analytic gate (angle-recovery new math)

- **2-bus analytic check (BLOCKING, before IEEE-13/123):** validate the phasor/angle-recovery BFS recursion on the existing 2-bus toy feeder against a closed-form hand value **before** trusting it on IEEE-13/123. Per STATE.md's flagged "genuinely new math" and RESEARCH.md Pattern 4.

---

## Wave 0 Requirements

- [ ] `test/test_ac_powerflow.jl` — EXACT-01 (mirror `test/test_convex_branch_flow.jl`: `isdefined` RED-guards, then behavioral asserts)
- [ ] `test/test_ac_oracle.jl` — EXACT-02/03/04 (mirror `test/test_exactness.jl` **but** build in the report-don't-throw divergence from the start — do NOT copy the `@test_throws` genuine-gap pattern)
- [ ] `docs/literate/ac_oracle.jl` — new literate rung page (mirror `docs/literate/convex_branch_flow.jl`); register in `docs/make.jl` literate-source tuple + `pages` list
- [ ] Framework install: none — `TestItemRunner`/`TestItems` already dev-deps

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Literate rung page reads correctly beside thesis equations | EXACT-04 | Prose/pedagogy quality is not machine-checkable | Reviewer reads rendered `docs/build/.../ac_oracle` page; confirms the gap finding is framed as a documented result, with a Farivar-Low / Gan-Li-Topcu-Low citation paragraph |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (3 new files)
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s (quick loop)
- [ ] `nyquist_compliant: true` set in frontmatter (set by plan-checker)

**Approval:** pending

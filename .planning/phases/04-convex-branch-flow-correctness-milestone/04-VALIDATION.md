---
phase: 4
slug: convex-branch-flow-correctness-milestone
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-07-18
---

# Phase 4 — Validation Strategy

> Per-phase validation contract. This is the project's correctness keystone — the exactness
> invariant (PF-04) is a hard price-refusal gate, and the thesis ground-truth reproduction
> (OPT-02/03) is the regression anchor for every later rung.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `Test` (stdlib) + TestItems/TestItemRunner |
| **Config file** | `test/Project.toml` + `test/runtests.jl` |
| **Quick run command** | `julia --project=. -e 'import Pkg; Pkg.test()'` (per-seam `@run_package_tests filter=...`) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~2 minutes (SOCP solves on IEEE-13 are heavier) |

---

## Sampling Rate

- **After every task commit:** relevant per-seam `@testitem` filter
- **After every plan wave:** full suite
- **Before verify:** full suite green
- **Max feedback latency:** ~120 seconds

---

## Per-Task Verification Map

| Task | Requirement | Secure Behavior | Test Type | Command (filter substring) | Status |
|------|-------------|-----------------|-----------|----------------------------|--------|
| socp formulation | PF-03 | ConvexBranchFlow contributes SOC cone + exactness copy via dispatch; interchangeable w/ DC/LinDistFlow | unit | `occursin("socp", ti.name)` | ⬜ pending |
| exactness copy | PF-03 | aux v̂ + affine voltage bounds (3.43/3.45) drive the cone tight | unit | `occursin("socp", ti.name)` | ⬜ pending |
| exactness invariant | PF-04 | assert_socp_exact! throws (refuses prices) when max\|l·v−(P²+Q²)\| ≥ τ; runs after assert_solved!, before dual read | unit+integration | `occursin("exact", ti.name)` | ⬜ pending |
| ieee13 fixture | DATA-03 | modified IEEE-13 feeder as radial-validated per-unit Feeder | unit | `occursin("ieee13", ti.name)` | ⬜ pending |
| welfare SOCP solve | OPT-02, PF-03 | full GLB-CVX solves on IEEE-13 via Clarabel(SOCP), OPTIMAL-gated, exact | integration | `occursin("socp", ti.name)` | ⬜ pending |
| ground-truth regression | OPT-02, OPT-03 | reproduces thesis DADP/voltage (pinned computed golden + thesis cross-check within tol) incl. v₉[16] | integration | `occursin("ground", ti.name)` | ⬜ pending |
| high-PV exactness | PF-04 | exactness holds (or is refused) on a high-PV/over-voltage fixture | integration | `occursin("exact", ti.name)` | ⬜ pending |
| oracle + seam stubs | SEAM-01 | operational_oracle(z)→(cost,π) returns coupling dual; SEAM-01 stub interfaces exist | unit | `occursin("oracle", ti.name)` | ⬜ pending |

---

## Wave 0 Requirements

- [ ] RED `@testitem` stubs: socp formulation, exactness invariant, ieee13 fixture, welfare-SOCP solve, ground-truth regression, high-PV exactness, oracle/seam
- [ ] modified IEEE-13 feeder fixture (thesis Table 4.1) + a high-PV/over-voltage fixture
- [ ] Confirm SOCP/conic ProblemClass routes to Clarabel

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Exact thesis-number match (v₉[16]≈1.0493, welfare≈$1819) | OPT-03 | Thesis inputs (profiles/house-counts) are partly figure-bound — exact reproduction may not be attainable; primary anchor is a pinned computed golden value with the thesis number asserted as an approximate cross-check within a documented tolerance | Compare solve output to the thesis figures; document any gap in SUMMARY |

*The exactness invariant (PF-04) and the pinned-golden regression are fully automated; only the exact thesis-figure match is a documented cross-check.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity maintained
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency reasonable for SOCP
- [ ] `nyquist_compliant: true`

**Approval:** pending

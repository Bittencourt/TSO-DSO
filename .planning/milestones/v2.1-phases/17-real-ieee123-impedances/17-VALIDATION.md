---
phase: 17
slug: real-ieee123-impedances
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-07-25
---

# Phase 17 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.
> Derived from `17-RESEARCH.md` § Validation Architecture. Data fetch confirmed live (HTTP 200).

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | `TestItems.jl` + `TestItemRunner.jl` (existing convention) |
| **Config file** | `test/runtests.jl` (`@run_package_tests`) |
| **Quick run command** | `julia --project -e 'using TestItemRunner, TSODSO; @run_package_tests filter=ti->occursin("ieee123", ti.name)'` |
| **Reduction-script self-check** | `julia --project scripts/reduce_ieee123_impedances.jl --verify` (asserts linecode.1 → R1≈0.05797, X1≈0.11876; exactly 12 linecodes) |
| **Full suite command** | `julia --project -e 'using Pkg; Pkg.test()'` |
| **Estimated runtime** | ~30 s quick (ieee123 filter); full suite minutes (shared IEEE-123 fixture) |

---

## Sampling Rate

- **After every task commit:** quick `ieee123`-filtered `@run_package_tests` (excludes the ~2276-test suite).
- **After every plan wave:** full `Pkg.test()` — the IEEE-123 fixture is shared by `test_dso.jl`, `test_admm_adaptive.jl`, `test_acceptance.jl`; a full run catches downstream regressions from the impedance swap.
- **Phase gate:** full suite green **PLUS** the NEW voltage-binding assertion passing with a documented margin (not merely "solves without error").
- **Max feedback latency:** ~30 s quick loop (the reduction script's `--verify` self-check is seconds).

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 17-01-* | 01 | 1 | IMPED-01 | unit (script self-check) | `scripts/reduce_ieee123_impedances.jl --verify` | ❌ W0 (new script + vendored data) | ⬜ pending |
| 17-02-* | 02 | 2 | IMPED-02 | unit | `... occursin("ieee123", ti.name)` | ✅ extend `test_ieee123.jl` + ❌ W0 new const table | ⬜ pending |
| 17-03-* | 03 | 3 | IMPED-03 | integration | `... occursin("ieee123"/"crossval", ti.name)` | ❌ W0 new voltage-binding `@testitem` | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

### Requirement → Behavior detail

- **IMPED-01**: offline `scripts/reduce_ieee123_impedances.jl` parses the (VENDORED — committed under `scripts/data/` with fetch URL + date, for reproducibility) `IEEE123Master.dss` + `IEEELineCodes.DSS`, reduces per-linecode 3×3 R/X to positive-seq R1/X1 (`R1=mean(diag)-mean(offdiag)`), emits the per-segment `const` table. Self-check pins linecode.1 → R1≈0.05797, X1≈0.11876 and asserts exactly 12 linecodes ingested (not 29). **PMD kept out of runtime `[deps]`** — the dependency-free regex parser introduces no PMD at all (satisfies IMPED-01 trivially; PMD-oracle cross-check optional). Units: neither `.dss` sets `Units=` → no length conversion; implied kft (documented, Assumption A1) — affects citation wording only, not the math.
- **IMPED-02**: `src/data/ieee123.jl` consumes the new per-segment real table (replacing the two uniform scalars `IEEE123_LINE_R=0.005`, `IEEE123_LINE_X=0.0025`) — **topology (`IEEE123_EDGES`) UNTOUCHED**. Existing positivity tripwire (`0 < r,x < 5` pu) re-verified against real data. Reduction caveats documented (transposition, single/two-phase laterals handled by the same reduction or absorbed, regulators/caps/switches out-of-scope per REQUIREMENTS — documented not simulated).
- **IMPED-03**: NEW numeric voltage-binding `@testitem` (none exists today) asserting solved `min(V)` approaches/hits the band with a documented margin. ADMM still converges within existing behavioral bounds (`iters<300`, welfare `isapprox rtol=1e-4`, `exact_maxgap<1e-3`) post-swap. If binding doesn't transfer, re-tune `LOAD_SCALE_IEEE123`/`PV_SCALE_IEEE123`/`DEV_SCALE_IEEE123` and DOCUMENT.

---

## Wave 0 Requirements

- [ ] `scripts/data/IEEE123Master.dss` + `IEEELineCodes.DSS` — VENDORED committed copies (fetch URL + date comment) so "offline, reproducible" holds even if upstream changes
- [ ] `scripts/reduce_ieee123_impedances.jl` — NEW; regex parser + Fortescue reduction + `--verify` self-check (linecode.1 sanity pin, 12-linecode assert)
- [ ] `src/data/ieee123_impedances.jl` (or equivalent `const` table) — NEW; generated output of the reduction script
- [ ] New voltage-binding `@testitem` — no existing test asserts this numerically
- [ ] Literate doc page for the reduction (recommended; matches `docs/src/generated/*` convention)
- [ ] Framework install: none

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Voltage-binding transfer + any re-tune | IMPED-03 | Whether the property transfers can't be known without an actual solve; the re-tune is a design decision | Run the IEEE-123 case on real impedances; if `min(V)` doesn't bind, re-tune the scale knobs and document the before/after (binding, exactness margin, iteration count) |
| Golden handling | IMPED-03/04 | Parallel-regression vs conscious-repin is a judgment call | Preserve synthetic goldens as an independent regression, OR consciously re-pin with an explicit before/after invariant rationale |

---

## Validation Sign-Off

- [ ] All tasks have automated verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references (vendored data, script, const table, binding test)
- [ ] Voltage-binding numeric assertion is a first-class phase gate (not "just solves")
- [ ] Vendored `.dss` provenance (URL + date) committed for reproducibility
- [ ] `nyquist_compliant: true` set by plan-checker

**Approval:** pending

---
phase: 41
slug: settlement-ledger-equity
status: final
nyquist_compliant: true
wave_0_complete: false
created: 2026-10-24
---

# Phase 41 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + `TestItemRunner` (test/runtests.jl), `:slow` tag split |
| **Config file** | `test/Project.toml` (pinned test env) |
| **Quick run command** | `TSODSO_TEST_FILES=<file> julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` |
| **Estimated runtime** | ~30–35 min full suite; targeted files minutes |

---

## Sampling Rate

- **After every task commit:** Targeted test file(s) for the touched seam
- **After every plan wave:** Full suite — 0 fail / 0 error; pricing/accounting goldens unchanged
- **Before phase verification:** Full suite green; ledger identities + metric known-values green
- **Max feedback latency:** ~35 min

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 41-0x-0x | 0x | x | SETL-01 | — | Ledger over DSO/aggregators/households/wholesale sums to zero; explicit merchandising-surplus line | unit (exact identity) | targeted test file | ❌ W0 | ⬜ pending |
| 41-0x-0x | 0x | x | SETL-02 | — | FIT/TOU/flat/DADP compared on same run; flat+TOU revenue-neutral (totals == DADP totals, tested) | unit + harness CSV | targeted test + script | ❌ W0 | ⬜ pending |
| 41-0x-0x | 0x | x | SETL-03 | — | AC feasibility STATUS reported per tariff dispatch (never throws; violations listed) | unit | targeted test file | ❌ W0 | ⬜ pending |
| 41-0x-0x | 0x | x | SETL-04/05 | — | Gini/Theil/Atkinson/Palma known-value tests incl. negative values; breakouts present; no-income statement | unit (known values) | targeted test file | ❌ W0 | ⬜ pending |
| 41-0x-0x | 0x | x | SETL-06 | — | Rebound metric on known-value fixture; per-hour detail | unit | targeted test file | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky — task IDs finalized at planning; planner keeps this coverage.*

---

## Wave 0 Requirements

- [ ] `src/settlement/` module skeleton (ledger + tariffs + feasibility + metrics + rebound)
- [ ] Small multi-house fixture for exact ledger identities and metric known-values
- [ ] Price-taker dispatch builder with `on_violation = :report`

*Existing infrastructure covers: welfare_accounting oracle, fit_baseline, ACPowerFlow diagnostics idiom, household map, TestItemRunner.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Equity writeup plausibility | SETL-04 | Researcher judgment | Read writeup; no-income-data statement present; breakouts readable |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 35 min
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-10-24 (autonomous — finalized at planning)

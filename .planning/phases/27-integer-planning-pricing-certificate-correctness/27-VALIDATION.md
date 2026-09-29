---
phase: 27
slug: integer-planning-pricing-certificate-correctness
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-09-29
---

# Phase 27 — Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Julia `Test` + TestItems/TestItemRunner (`@testitem`, discovered by `test/runtests.jl`) |
| **Config file** | `test/runtests.jl` |
| **Quick run command** | Direct `julia --project=. <script>.jl` reproducing the touched `@testitem` body (NEVER TestItemRunner under `--project=.`) |
| **Full suite command** | `julia --project=. -e 'import Pkg; Pkg.test()'` — DETACHED (`nohup setsid ... </dev/null &`) + polled `.done` marker, HEAD recorded in log line 1 |
| **Estimated runtime** | quick ~60–180 s; full ~20–35 min |

## Sampling Rate

- **After every task commit:** direct-script reproduction of touched `@testitem`(s)
- **After every wave merge:** full suite (orchestrator), triaged by root cause before next wave
- **Before verify:** full suite green vs Phase 26 close (30213 pass / 0 fail / 0 error / 5 broken at 9d00b82)

## Per-Requirement Verification Map

(See `27-RESEARCH.md` → Validation Architecture for the full table.)

| Requirement | Behavior | Test Type | File Exists | Status |
|-------------|----------|-----------|-------------|--------|
| FIX-06 | corner_recourse == T=2 grid enumeration (measured tol); T=1 byte-identical | unit | ❌ W0 T=2 oracle | ⬜ |
| FIX-07 | sum-to-price under new names; component zero iff multiplier zero (IEEE-13 slice); deprecated alias warns once | unit | ⚠️ edit + ❌ W0 | ⬜ |
| FIX-08 | slack cone on small branch flagged; canonical fixtures pass at measured ε | unit+integration | ❌ W0 synthetic | ⬜ |
| FIX-09 | FIT inexact throws by default / reports under :report; ALMOST_OPTIMAL bounded or fixed | unit+integration | ❌ W0 + existing script | ⬜ |
| FIX-10 | truth-settled realized welfare (forced PV shortfall, loss-exact import); SOC violation throws; zero-error fixture unchanged | unit | ❌ W0 | ⬜ |
| SC-6 | every moved golden old→new + cause; GOLDEN-AUDIT; suite green | process | n/a | ⬜ |

## Wave 0 Requirements

- [ ] T=2 grid-enumeration oracle fixture (FIX-06)
- [ ] synthetic slack-cone-on-small-branch fixture (FIX-08)
- [ ] synthetic inexact-FIT fixture (FIX-09)
- [ ] forced-PV-shortfall MPC fixture (FIX-10)

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Golden-move audit (no silent re-pin) | SC-6 | judgment on stated cause | review 27-GOLDEN-AUDIT.md vs `git diff` of test/ |

## Validation Sign-Off

- [ ] All tasks have real `<automated>` verify
- [ ] No 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] `nyquist_compliant: true` set at phase close

**Approval:** pending

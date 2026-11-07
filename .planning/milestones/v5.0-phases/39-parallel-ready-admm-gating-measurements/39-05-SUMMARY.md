---
phase: 39-parallel-ready-admm-gating-measurements
plan: 05
subsystem: measurement
tags: [ieee8500, memory-profiling, rss-staging, admm, scale-06, earlyoom, honesty-policy]

# Dependency graph
requires:
  - phase: 39-parallel-ready-admm-gating-measurements (plans 02/04)
    provides: production solve_admm path with named internal phases and the threaded executor this harness drives through (serial default)
  - phase: 35-ieee8500-scale-after-refactor
    provides: the reconciliation baselines (5.92 GiB peak / 4.56 GiB loop delta T=10; 11.52/10.17 GiB T=24), the profile_ieee8500_memory.jl idioms, and the dated doc-note pattern
provides:
  - scripts/profile_ieee8500_memory_attribution.jl — re-runnable staged RSS attribution harness (anchor-first design, Pitfall-8 isolated stages, keyed CSV upsert, kill-resilient incremental writes)
  - results/ieee8500_benchmark/memory_attribution.csv — committed per-stage attribution rows + reconciliation/residual rows for d=0.1 T=10 and T=24
  - T=10 attribution: ~3.4 GiB unattributed growth split into named components (AgrOpt builds +1.724, first iterate +1.370, per-iterate +0.318) with an explicit 0.620 ± 0.237 GiB honest residual
  - measured refutation of the Phase-35 per-hour DSO solver-state hypothesis as the dominant mechanism
  - T=24: build-stage attribution (+0.922 DSO / +4.024 AgrOpt, ~2.3× T=10 for 2.4× T) and an honest recorded earlyoom kill for the loop stages
  - dated doc note in docs/literate/ieee8500_scaling.jl closing SCALE-06
affects: [40 (POP-05 scaling report), any future IEEE-8500 memory-mitigation or scaling work]

# Tech tracking
tech-stack:
  added: []  # no new packages — /proc/self/status + Sys.maxrss + GC.gc/malloc_trim staging, CSV/DataFrames already pinned
  patterns:
    - "anchor-first staged measurement: the whole-call Sys.maxrss() delta must run before any staged build (monotonic whole-process HWM)"
    - "GC-retained component deltas reconciled against the whole-call delta with per-component tolerances and an explicit honest residual"
    - "kill-resilient CSV: re-upsert after every stage report so an earlyoom kill keeps captured evidence"

key-files:
  created:
    - scripts/profile_ieee8500_memory_attribution.jl
    - results/ieee8500_benchmark/memory_attribution.csv
    - results/ieee8500_benchmark/runs/p39-attr-d0.1-T10.{time,free_before,oom_earlyoom,oom_kernel,pid}
    - results/ieee8500_benchmark/runs/p39-attr-d0.1-T24.{time,free_before,oom_earlyoom,oom_kernel,pid}
    - results/ieee8500_benchmark/runs/p39-attr-d0.1-T24-s2.{time,free_before,oom_earlyoom,oom_kernel,pid}
  modified:
    - docs/literate/ieee8500_scaling.jl
    - results/ieee8500_benchmark/point_resources.csv

key-decisions:
  - "Anchor-first harness design: the full production solve_admm reconciliation anchor always runs before the staged builds because Sys.maxrss() is a monotonic whole-process HWM — the reverse order would zero the anchor delta"
  - "Tolerances stated per component as max(0.05 GiB, 10% of component), residual tolerance = quadrature sum; the residual honestly absorbs churn/allocator/anchor-warm-context noise"
  - "T=24 full run earlyoom-killed at the anchor (7.46 GiB MaxRSS; host had 6.3 GiB available / 10 GiB swap at launch vs Phase-35's 10.3 GiB available): recorded as evidence, ONE reduced build-only attempt made (--stage 2, completed 6.07 GiB), no retry of the full point per the repo's one-attempt protocol"
  - "Kill evidence row (anchor_earlyoom_killed) and the T=24 non-attribution status row were recorded by a documented post-run CSV repair (the process died before it could write) — Phase-35 repair precedent (aa6277e)"
  - "Verdict recorded per Pitfall 8: the Phase-35 per-hour DSO solver-state hypothesis is refuted-as-dominant at T=10 (~0.045 GiB/iter vs 1.7 GiB AgrOpt builds + 1.4 GiB first iterate); what scales with T is measured — the models themselves (T=24 builds 2.26x/2.33x T=10 for 2.4x T)"

patterns-established:
  - "Pattern: SCALE-06 staged attribution (anchor + isolated GC'd components + reconciliation rows in the deliverable CSV)"
  - "Pattern: kB→GiB conversions use /2^20 (bytes /2^30) — a units slip here silently zeroes small deltas (caught by smoke, fixed in Task 1)"

requirements-completed: [SCALE-06]

# Metrics
duration: 51min
completed: 2026-10-24
---

# Phase 39 Plan 05: Parallel-Ready ADMM & Gating Measurements — SCALE-06 Memory Attribution Summary

**IEEE-8500 memory attribution closed honestly: T=10's ~3.4 GiB unattributed solve_admm growth is split into named components (122 AgrOpt builds +1.72 GiB, first iterate +1.37 GiB, per-iterate retention only +0.32 GiB — refuting the per-hour DSO solver-state hypothesis) with a 0.62 GiB documented residual; T=24's loop attribution is an honestly recorded earlyoom kill with build-stage attribution completed (builds scale ~linearly in T).**

## Performance

- **Duration:** 51 min (incl. ~30 min of measured runs: 15 min T=10 full point, 13 min T=24 killed attempt, 2 min T=24 build-only)
- **Started:** 2026-10-24T08:43:50Z
- **Completed:** 2026-10-24T09:34:02Z
- **Tasks:** 3
- **Files modified:** 21 (2 harness/CSV created, 1 doc note modified, 18 run-evidence artifacts)

## Accomplishments
- Staged RSS attribution harness committed and include-safe, reusing the profile_ieee8500_memory.jl idioms (proc_status_kb / report / GC.gc+malloc_trim staging / parse_kv_flag / keyed upsert) with a new anchor-first design and four CLI flags (--fixture/--density/--t-horizon/--stage)
- T=10 boundary point fully attributed and reconciled: anchor delta 4.339 GiB (CertificateError iters=8, ratio 568.9541645248668 — the Phase-35 refusal reproduced exactly), Σ components 3.720 ± 0.237 GiB, residual 0.620 ± 0.237 GiB (~14%)
- The Phase-35 "per-hour DSO solver state" hypothesis replaced by an isolating measurement: retained growth across iterates 2..8 is +0.318 GiB (~0.045 GiB/iter) — an order below the AgrOpt-build and first-iterate components (Pitfall 8: the data names the mechanism)
- T=24: full run earlyoom-killed during the anchor and recorded as evidence (one attempt, no retry); reduced build-only run completed — build_dso_opt +0.922 GiB, 122 AgrOpt builds +4.024 GiB (~2.3× T=10 for 2.4× T: the models themselves scale with T), process peak 6.07 GiB with builds ALONE
- SCALE-06 doc note appended to docs/literate/ieee8500_scaling.jl (dated Appended pattern, source-cited figures, Units paragraph, tolerances, residual, what is NOT established); the prior section's stale "not established"/"hypothesis" sentences updated to point at it

## Task Commits

Each task was committed atomically:

1. **Task 1: Staged RSS attribution harness** - `27219c0` (feat) + `7e70b65` (style: pinned-formatter reflow)
2. **Task 2: Boundary-point runs + reconciliation** - `5091240` (feat; includes runs/ evidence artifacts + point_resources.csv rows)
3. **Task 3: Doc note (dated Appended pattern)** - `3a41cfb` (docs)

## Files Created/Modified
- `scripts/profile_ieee8500_memory_attribution.jl` - staged attribution harness (anchor + isolated components + reconciliation rows; kill-resilient CSV writes)
- `results/ieee8500_benchmark/memory_attribution.csv` - the deliverable: 38 keyed rows (T=10 full attribution + reconciliation/residual; T=24 kill evidence + build stages + honest non-attribution status)
- `docs/literate/ieee8500_scaling.jl` - dated Appended section "Memory attribution of the solve_admm loop (Phase 39, SCALE-06)" + stale-sentence updates in the Phase-35 section
- `results/ieee8500_benchmark/point_resources.csv` + `runs/p39-attr-*` - wrapper-recorded provenance (MaxRSS, free_before, earlyoom/kernel OOM evidence) for all three runs

## Decisions Made
- Anchor-first process design (monotonic-HWM constraint); smoke runs use --stage 2 so the anchor only runs in full attribution runs
- Bounded iteration count N = the anchor's own observed production iteration count (8 at T=10); the 1 + N−1 iterate split resets only the residual ledger's sequential-k bookkeeping (documented; staged certify evidence row carries iterations=7, one less than production — the anchor row carries 8)
- Component tolerances max(0.05 GiB, 10%); residual tolerance = quadrature sum
- T=24: one full attempt (killed — recorded), one reduced build-only attempt (completed), then stop per the one-attempt protocol; the kill evidence row and the T=24 non-attribution row were added by a documented post-run repair (out-of-process by necessity)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] kB→GiB unit slip silently zeroed per-stage deltas**
- **Found during:** Task 1 (first smoke run)
- **Issue:** per-stage delta computed as (kB difference)/2^30 — 2^30 is the bytes-per-GiB factor; kB→GiB is /2^20, so every delta rounded to 0.0
- **Fix:** divided the three kB-value conversion sites by 2^20 (Sys.maxrss() byte sites kept /2^30); re-ran the smoke — deltas read correctly (+0.176 GiB DSO build on ieee8500-mv)
- **Files modified:** scripts/profile_ieee8500_memory_attribution.jl
- **Verification:** smoke run output shows non-zero deltas; committed CSV values match hand-checked KiB arithmetic
- **Committed in:** 27219c0 (Task 1 commit, post-fix)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** none on scope — the fix was within Task 1 before its commit.

## Issues Encountered
- **T=24 full attribution run earlyoom-killed during the anchor** (rc=143, MaxRSS 7.46 GiB; earlyoom SIGTERMs at VmRSS ~5.9 GiB). Host at launch: 6.3 GiB available / 10 GiB swap used — versus ~10.3 GiB available when Phase 35 measured this point (11.52 GiB peak). Handled per the plan's own pre-authorization and the repo's one-attempt protocol: kill recorded as evidence (runs/ artifacts + point_resources row + a post-run CSV repair adding anchor_earlyoom_killed and the T=24 non-attribution status row), then ONE reduced build-only run (--stage 2) completed and delivered the T=24 build-stage attribution. T=24 loop attribution honestly NOT ESTABLISHED.
- **Smoke upsert check**: the re-run replaced its own rows exactly (5 rows, no duplicates) — acceptance criterion confirmed on the second smoke.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- SCALE-06 closed: CSV + doc note committed; the 8500 memory story is attributable (T=10) and honest (T=24 residual = recorded non-measurement)
- For Phase 40 (POP-05 scaling report): the T=10 component table and the T-linear build scaling are the measured inputs; a full T=24 loop attribution needs a host with ~12 GiB genuinely available at launch
- No memory mitigation was adopted: the dominant components are the 123 JuMP models themselves and their first solves — no dominant removable retained consumer was identified

## Known Stubs

None — all deliverables are fully wired (harness runs end-to-end; CSV rows measured; doc note cites measured values).

## Self-Check: PASSED

- FOUND: scripts/profile_ieee8500_memory_attribution.jl
- FOUND: results/ieee8500_benchmark/memory_attribution.csv (38 data rows)
- FOUND: docs/literate/ieee8500_scaling.jl (Appended 2026-10-24 section at line 408)
- FOUND: commit 27219c0 (Task 1)
- FOUND: commit 7e70b65 (Task 1 style)
- FOUND: commit 5091240 (Task 2)
- FOUND: commit 3a41cfb (Task 3)

---
*Phase: 39-parallel-ready-admm-gating-measurements*
*Completed: 2026-10-24*

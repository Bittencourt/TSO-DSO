---
title: Harden the IEEE-8500 point scripts for re-runs (REPLACE_LABEL evidence, OOM timing)
created: 2026-11-06
source: Phase 46 code review iteration 3 (deferred at the loop cap; accepted at verification 2026-11-06)
area: scripts / measurement
---

Two warnings were left open when Phase 46 closed. Both affect only future re-runs of
`scripts/run_ieee8500_point.sh` and `scripts/ieee8500_scenario_point.jl`. The committed rows in
`results/ieee8500_benchmark/` and the docs numbers are not affected. Details are in
`.planning/phases/46-ieee-8500-headline-measurement-go-no-go/deferred-items.md`, items 5–7.

- **WR-01:** with `REPLACE_LABEL=1`, the wrapper overwrites `runs/<label>.*` evidence before the script
  decides whether to keep or replace the existing final row. Fix: write the new run to temporary paths, and
  promote them only after the upsert accepts the row.
- **WR-02:** an `OutOfMemoryError` during materialize or build is recorded without that phase's timing,
  VmHWM sample or sizes. Fix: capture the timing and VmHWM in a `try`/`finally` around each phase, and write
  the values captured so far into the `memory_infeasible_inprocess` row.
- **IN-01..03** (info items) are listed in deferred-items.md, item 7.

Do this before the next 8500 measurement re-run, for example a bigger-RAM host run at T = 24.

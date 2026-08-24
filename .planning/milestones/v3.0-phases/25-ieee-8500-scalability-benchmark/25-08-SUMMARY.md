---
phase: 25-ieee-8500-scalability-benchmark
plan: 08
subsystem: infra
tags: [scs, clarabel, benchmark-harness, ieee8500, memory-wall, socp-exactness, julia]

# Dependency graph
requires:
  - phase: 25-05
    provides: "scripts/benchmark_ieee8500.jl (fixture x density x solver x {centralized,ADMM} density-sweep harness; T_horizon already threaded as an explicit function parameter)"
  - phase: 25-06
    provides: "results/ieee8500_benchmark/density_sweep_full.csv (17-row consolidated cross-fixture curve, incl. OOM-killed headline rows); deferred-items.md item 4 (open, memory wall)"
  - phase: 25-07
    provides: "Re-calibrated IEEE8500_MV_EXACT_ATOL/IEEE8500_EXACT_ATOL (~1e-3 scale, genuinely noise-like)"
provides:
  - "--t-horizon CLI flag on scripts/benchmark_ieee8500.jl, generalizing plan 25-05's T_QUICK precedent beyond --quick, with a validated floor of 10"
  - "bench/Project.toml + bench/Manifest.toml: a dedicated environment with SCS installed, TSODSO Pkg.develop'd in-tree -- root Project.toml stays SCS-free (still only weakdeps/extensions/compat)"
  - "SCS made resolvable from the root-project-active runtime (which DrWatson's @quickactivate always ends up activating, overriding --project=bench) via the machine's global Julia v1.12 environment -- a non-repo, non-committed workaround"
  - "Real (non scs_unavailable) Clarabel-vs-SCS crossover measurements for ieee13 (4 densities), ieee123 (4 densities), and ieee8500-mv (density=0.1) in results/ieee8500_benchmark/density_sweep_full.csv"
  - "A genuine T_horizon=10 headline-fixture (ieee8500, 4,875 buses) measurement at density=0.1: the T=24 memory wall is closed at T=10, but a NEW conditioning wall (ALMOST_OPTIMAL, refused by assert_solved!) blocks SOCP-exactness certification at that same point"
  - "deferred-items.md item 4 updated: PARTIALLY RESOLVED -- memory component closed, new conditioning-wall sub-finding logged, items 2/3 left open"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dedicated bench/ Pkg environment (mirrors docs/Project.toml) for an optional weakdep the root project must never carry in [deps] -- Manifest.toml committed, following this repo's own docs/Manifest.toml precedent"
    - "Global (~/.julia/environments/v1.12) package install as the correct mechanism to make an optional weakdep resolvable AFTER DrWatson's @quickactivate unconditionally re-activates the root project mid-script -- a machine-level, non-repo workaround that never touches TSODSO's own Project.toml/Manifest"
    - "--t-horizon CLI override generalizing a --quick-only constant (T_QUICK) into a general, explicitly-validated (floor-enforced, never-silently-clamped) sweep parameter"

key-files:
  created:
    - bench/Project.toml
    - bench/Manifest.toml
    - .planning/phases/25-ieee-8500-scalability-benchmark/25-08-SUMMARY.md
  modified:
    - scripts/benchmark_ieee8500.jl
    - results/ieee8500_benchmark/density_sweep.csv
    - results/ieee8500_benchmark/density_sweep_full.csv
    - .planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md

key-decisions:
  - "SCS made available via the machine's GLOBAL Julia environment, not via a script change: DrWatson's @quickactivate(@__DIR__) unconditionally calls Pkg.activate() on the project found by searching upward from the SCRIPT's own file location -- which is always the repo ROOT (name=TSODSO), never bench/, regardless of what --project the process was launched with. Verified this live (Base.active_project() before/after quickactivate). Since scripts/benchmark_ieee8500.jl's own quickactivate call was NOT in this task's authorized change (Task 1 only touched the --t-horizon CLI surface), and modifying quickactivate's project-selection behavior project-wide was out of scope and risky, SCS was instead added to the user's global ~/.julia/environments/v1.12 environment -- which Julia's default LOAD_PATH stack (`@`, `@v#.#`, `@stdlib`) still consults as a fallback even after quickactivate switches the ACTIVE project away from bench/. This makes SCS resolvable regardless of which project ends up active, without ever touching TSODSO's own [deps] (verified: root Project.toml/Manifest-v1.12.toml unchanged; SCS still ONLY in [weakdeps]/[extensions]/[compat])."
  - "bench/'s own direct-Julia-e verification (Task 2, using TSODSO; import SCS; alternative_optimizer(...)) is still valid and meaningful evidence that TSODSOSCSExt loads correctly in a dedicated env -- it is the ACTUAL SCRIPT invocation (which always ends up on the root project post-quickactivate) that needed the separate global-env fix to see SCS."
  - "No SCS time_limit override exists in run_scs_comparison (a pre-existing harness gap, out of this task's <files> scope to fix) -- the ieee8500-mv/0.1 SCS solve ran uncapped for several minutes before finishing; this is reported as observed behavior, not silently worked around."
  - "T=10 headline point: NOT re-calibrated, NOT retried, NOT escalated to a higher density after the centralized solve reached ALMOST_OPTIMAL (0.1 did not 'succeed comfortably' per this task's own instruction) -- T-25-12 (no tolerance widened to manufacture a passing verdict) and T-25-11 (no point silently dropped) both honored."
  - "SCALE-04/SCALE-05 left UNCHECKED in REQUIREMENTS.md (no edit made) -- see 'Requirements Decision' below for the reasoning."

requirements-completed: []

# Metrics
duration: ~65min active execution (plus one ~6min one-time bench-env precompile and one ~12min ADMM+SCS run absorbed into that time)
completed: 2026-08-22
---

# Phase 25 Gap Closure (25-08): Real SCS Crossover + T=10 Headline Attempt Summary

**Measured a real (non-degraded) Clarabel-vs-SCS crossover across three fixtures via a dedicated `bench/` environment plus a global-Julia-env workaround for DrWatson's `@quickactivate` override, and closed the IEEE-8500 headline fixture's memory wall at `T_horizon=10` (density=0.1) — only to hit a new, distinct conditioning wall (`ALMOST_OPTIMAL`, refused) that still blocks SOCP-exactness certification at real headline scale.**

## Performance

- **Duration:** ~65 min active execution (bench-env setup absorbed ~6 min of one-time precompilation; the ieee8500-mv SCS+ADMM point absorbed ~12 min of that time; the T=10 headline attempt itself took ~4.5 min wall time)
- **Started:** 2026-08-22T09:09 (worktree base corrected to `51db37a`)
- **Completed:** 2026-08-22T10:20
- **Tasks:** 5
- **Files modified:** 2 created (`bench/Project.toml`, `bench/Manifest.toml`), 4 modified (`scripts/benchmark_ieee8500.jl`, `density_sweep.csv`, `density_sweep_full.csv`, `deferred-items.md`), 1 new (this summary)

## Accomplishments

- **Task 1 — `--t-horizon` CLI flag:** added to `scripts/benchmark_ieee8500.jl`, generalizing plan 25-05's `T_QUICK` precedent (deferred-items.md item 4's own suggestion) beyond `--quick`. Absent, behaviour is byte-identical to today's `quick ? T_QUICK : T`. Rejects (never clamps) values below the floor of 10, naming the `_ieee8500_house` Deferrable-window infeasibility as the reason. Verified: rejection fires correctly for `--t-horizon 5`; `--t-horizon 10` on a cheap fixture runs and records `T_horizon=10` in the CSV.
- **Task 2 — `bench/` environment:** `bench/Project.toml` + committed `bench/Manifest.toml` (mirroring `docs/Project.toml`'s pattern), `TSODSO` resolved via `Pkg.develop(path=".")`, `SCS` added. Root `Project.toml`/`Manifest-v1.12.toml` confirmed byte-unchanged (SCS still ONLY in `[weakdeps]`/`[extensions]`/`[compat]`). Verified directly that `TSODSOSCSExt` loads and `TSODSO.alternative_optimizer(TSODSO.SCSChoice(), TSODSO.SOCP())` returns a real `SCS.Optimizer`, not the `scs_unavailable` degrade path.
- **Discovery (blocking, Rule 3):** running the ACTUAL harness script under `--project=bench` still produced `scs_unavailable`. Root-caused live: `DrWatson.@quickactivate("TSODSO")` unconditionally calls `Pkg.activate()` on the project found by searching upward from the *script's own file location* — always the repo root, never `bench/`, regardless of the launch `--project`. Fixed by installing SCS in the machine's **global** Julia v1.12 environment (`~/.julia/environments/v1.12`), which stays in the default `LOAD_PATH` fallback stack even after `@quickactivate` switches the active project — this touches no repo file at all and keeps the root `[deps]` SCS-free. Verified end-to-end: the real harness script, launched however, now resolves and loads `SCS` for real.
- **Task 3 — real Clarabel-vs-SCS crossover (GAP A):**
  - `ieee13` (4 densities): SCS `OPTIMAL` at 0.1/0.25/0.5 (drift 0.25 → 4.82, growing with density); SCS **errors** at density=1.0 — a real `ErrorException` (battery complementarity tripwire T-03-13 violated), root-caused live: SCS's lower first-order accuracy, vs. Clarabel's interior-point accuracy, is the direct cause — not a harness bug.
  - `ieee123` (4 densities): SCS `OPTIMAL` throughout, small and roughly flat drift (0.0022–0.0050).
  - `ieee8500-mv` density=0.1: SCS `OPTIMAL`, drift=0.112. (ADMM at this point still hits the known item-3 consolidation-gate throw, unrelated to SCS.)
  - **No crossover observed in the measured range**: Clarabel remains fast and numerically robust everywhere SCS also converges; SCS's own drift from Clarabel grows with problem size on `ieee13` but stays small/flat on `ieee123` — inconclusive on one single growth law, but Clarabel dominates on wall time at every point where both solve, and SCS is the one that fails outright at `ieee13`'s highest density. "Clarabel dominates across the measured range" is the honest characterization; no point where SCS overtakes Clarabel was found.
- **Task 4 — T=10 headline attempt (GAP B, partial close):** ran the true 4,875-bus/4,874-branch `ieee8500` fixture at `--t-horizon 10`, density=0.1, Clarabel-only, completely alone on the machine.
  - **The T=24 memory wall IS closed at T=10**: the process completed normally — no SIGKILL, no `journalctl -k` OOM evidence, peak observed anon-rss ≈5.9 GB during live monitoring vs. the previously-measured 6.8–9.75 GB OOM range.
  - **But a NEW conditioning wall appeared**: the centralized (Clarabel) solve reached `ALMOST_OPTIMAL` (not `OPTIMAL`) and was refused by `assert_solved!`'s strict trust policy (no `allow_almost` pass-through) — the same structural limitation plan 25-05's calibration ladder hit, now appearing at real headline network scale for the first time (every prior headline attempt was OOM-killed before ever reaching any numerical status). `model_vars`/`model_cons`/`exact_maxgap`/`exact_verdict` could not be populated; `IEEE8500_EXACT_ATOL` could not be evaluated at all.
  - ADMM ran independently (its own build succeeded, no OOM) for 6 iterations before hitting the 120s D-18 wall-clock budget (`budget_exceeded`) without converging — never reached `solve_admm`'s hardcoded consolidation gate (item 3, still open) because it never got that far.
  - Per this task's own instruction, since density=0.1 did not "succeed comfortably," no higher density was attempted.
- **Task 5 — record updated honestly:** `deferred-items.md` item 4 marked PARTIALLY RESOLVED with the full T=10 finding (memory closed, conditioning found); items 2 and 3 left explicitly open, untouched. `REQUIREMENTS.md` left unchanged (see Requirements Decision below).

## Task Commits

Each task was committed atomically:

1. **Task 1: `--t-horizon` CLI flag** — `c8d4a47` (feat)
2. **Task 2: `bench/` env with SCS** — `582f609` (chore)
3. **Task 3: real Clarabel-vs-SCS crossover measurement** — `0d40b3c` (feat)
4. **Task 4: T=10 headline attempt** — `3db4457` (feat)
5. **Task 5: deferred-items.md update** — `0fc7d66` (docs)

**Plan metadata:** this SUMMARY.md commit (below) — STATE.md/ROADMAP.md/REQUIREMENTS.md intentionally NOT touched, per this task's explicit instruction that the orchestrator owns STATE.md/ROADMAP.md, and per the Requirements Decision below for REQUIREMENTS.md.

## Files Created/Modified

- `scripts/benchmark_ieee8500.jl` — `--t-horizon <int>` CLI flag + `T_HORIZON_FLOOR` constant (Task 1); doc-comment updates only otherwise
- `bench/Project.toml` / `bench/Manifest.toml` — new dedicated environment: `TSODSO` (`Pkg.develop(path=".")`) + `SCS`, mirroring `docs/Project.toml`'s pattern; Manifest committed per this repo's INFRA-01 reproducibility convention
- `results/ieee8500_benchmark/density_sweep.csv` — harness's own raw upsert file, now carrying the fresh Task 3 (`ieee13`×4, `ieee123`×4, `ieee8500-mv`@0.1, plus one standalone `ieee13`@0.1/`scs`-only sanity row) and Task 4 (`ieee8500`@0.1/`clarabel`/`T_horizon=10`) rows
- `results/ieee8500_benchmark/density_sweep_full.csv` — the 9 pre-existing `scs_unavailable` rows (ieee13×4, ieee123×4, ieee8500-mv@0.1) REPLACED with real, freshly-measured SCS crossover data; 1 NEW row appended for the T=10 headline attempt, with an explicit, impossible-to-miss `T_HORIZON=10, NOT T=24` label in its own `error_msg` field
- `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` — item 4 updated: PARTIALLY RESOLVED, full before/after narrative; items 2/3 preserved, untouched

## Decisions Made

See `key-decisions` in frontmatter for the full rationale on the `@quickactivate`-override discovery and its global-env workaround. Additional decisions:

- **No time-limit control added to `run_scs_comparison`**: the SCS solve at `ieee8500-mv`/0.1 ran uncapped for several minutes. Adding a `time_limit` override was judged out of this task's `<files>` scope (Task 3 says "measure," not "fix the harness") — the long, uncapped runtime is itself reported as observed behavior in this summary, not silently worked around or hidden. A future plan could add SCS's own time-limit MOI attribute to `run_scs_comparison` if this proves impractical at larger scale.
- **Root-caused, not worked around, the `ErrorException` at `ieee13`/1.0/SCS**: rather than treating it as an opaque harness failure, a standalone reproduction (`import SCS; solve_welfare(...)`) surfaced the exact battery-complementarity tripwire message, confirming this is SCS's known lower first-order accuracy (CLAUDE.md's own standing "SCS never for exactness certification" caveat), not a bug.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] `DrWatson.@quickactivate` overrides `--project=bench`, defeating the dedicated environment for the actual script invocation**
- **Found during:** Task 3, first sanity-check run of `scripts/benchmark_ieee8500.jl --project=bench --solver scs`, which reported `scs_unavailable` despite `bench/`'s own direct verification passing.
- **Issue:** `DrWatson.quickactivate(path, name)` (`project_setup.jl:131`) calls `Pkg.activate(findproject(path))` unconditionally where `path` is `@__DIR__` of the SCRIPT — always the repo root (name=`TSODSO`), regardless of the launching `--project`. Confirmed live: `Base.active_project()` before quickactivate showed `bench/Project.toml`; after, it showed the root `Project.toml`, and `Base.find_package("SCS")` returned `nothing` there.
- **Fix:** installed `SCS` (plus its dependency tree) in the machine's global Julia v1.12 environment (`~/.julia/environments/v1.12`, via `Pkg.activate(); Pkg.add("SCS")`) — a machine-level, non-repo change. Julia's default `LOAD_PATH` stack (`@`, `@v#.#`, `@stdlib`) still consults this global environment as a fallback even after `@quickactivate` re-activates the root project, so `Base.find_package("SCS")` now resolves regardless of launch `--project`.
- **Files modified:** none in the repo — this is a machine-level Julia environment change, not a git-tracked file.
- **Verification:** re-ran the exact same diagnostic (`using DrWatson; @quickactivate "TSODSO"; Base.find_package("SCS")`) — now resolves to the global-env package path; the full harness script subsequently produced real `scs_status=OPTIMAL`/`ERROR:...` values (never `scs_unavailable`) across all three fixtures measured in Task 3.
- **Committed in:** no repo commit (machine-level change); its effects are visible in Task 3's commit (`0d40b3c`).

---

**Total deviations:** 1 auto-fixed (Rule 3, blocking). **Impact on plan:** required for Task 3's entire deliverable (a real, non-degraded SCS measurement) to be possible at all, without violating the hard constraint that SCS never appears in TSODSO's own `[deps]`. No repo-file scope creep — the fix lives entirely outside the git tree.

## Issues Encountered

- **The ieee8500-mv/0.1 SCS solve took ~5–6 minutes with no visible progress output** (verbose is silenced) before completing — significantly longer than Clarabel's own solve at the same point (~37s). This is itself informative for the crossover characterization (first-order SCS scales far worse in wall time than Clarabel's interior-point method at this problem size) and is reported as observed behavior in Task 3's accomplishments above, not treated as a bug.
- **Shared-machine contention**: several OTHER agents' Julia precompile processes (Makie, JuMP) were running concurrently throughout this task's execution, competing for CPU (confirmed via `pgrep`/`ps`) and adding several minutes of wall-clock delay to precompilation steps. Per the memory-discipline protocol, the T=10 headline attempt (Task 4) was still run with NO other process of this task's own running concurrently, and its own process RSS was monitored directly (not conflated with total system `used` memory, which included other agents' unrelated activity).

## User Setup Required

**A researcher on a fresh checkout who wants to reproduce Task 3's SCS crossover measurements needs one one-time machine-level step** (not a repo file, so not captured by `git clone`):
```
julia -e 'import Pkg; Pkg.activate(); Pkg.add("SCS")'
```
This installs SCS into the Julia global environment, which `scripts/benchmark_ieee8500.jl` (via `DrWatson.@quickactivate`, which always re-activates the root TSODSO project) will pick up as a `LOAD_PATH` fallback regardless of any `--project` flag used to launch the script. No change is required to the committed root `Project.toml`.

Alternatively, `bench/Project.toml` (this task's own new dedicated environment) can be used directly for any DIRECT (non-`@quickactivate`-driven) Julia session that wants `SCS` — e.g. `julia --project=bench -e 'using TSODSO; import SCS; ...'` — but note that invoking `scripts/benchmark_ieee8500.jl` itself will always end up on the root project regardless of `--project`, per the discovery above.

## Requirements Decision — SCALE-04/SCALE-05 left UNCHECKED

Both remain `[ ]` in `.planning/REQUIREMENTS.md`; no edit was made to that file. Reasoning:

- **SCALE-04** ("benchmark itself is the deliverable ... Clarabel-vs-SCS crossover point identified") is now substantively evidenced for the cheap/mid fixtures (`ieee13`, `ieee123`, `ieee8500-mv`), but the crossover diagnostic was never exercised at the TRUE headline scale (the T=10 attempt used `--solver clarabel` only, to keep the memory-critical run as low-risk as possible — see Task 4). A verifier could reasonably ask for the SCS comparison to also be attempted at headline scale before considering SCALE-04 fully met.
- **SCALE-05** ("a live-executed literate page documents the fixture, the assumptions, and the measured scaling curve") — the existing literate page (`docs/literate/ieee8500_scaling.jl`, from plan 25-06) has NOT been updated to reflect this task's new evidence (the real SCS crossover, the T=10 partial headline result). Updating that page was outside this gap-closure task's authorized task list (Tasks 1–5 above); a future plan needs to fold these findings into the literate page before the "measured scaling curve" it documents can be called current.
- **The TRUE headline point (T=24, density=1.0) still has never produced any measurable/certified outcome** — it remains `OOM_KILLED` in `density_sweep_full.csv`, unchanged by this task. The T=10 result is a genuinely new, positive finding (the memory wall is not fundamental — a shorter horizon fits), but it is explicitly a DIFFERENT, non-comparable measurement, not a T=24 substitute, and it also failed to reach a certified exactness verdict for a different (conditioning) reason.

Given all three considerations, ticking either box would overstate what this task closed. Both gaps (A and B) are now measurably BETTER characterized than before — GAP A has real data instead of `scs_unavailable` everywhere, and GAP B has a genuine, positive memory-wall finding instead of six uniform `OOM_KILLED` rows — but neither SCALE-04 nor SCALE-05's full text is met yet. A future plan should (a) fold this task's findings into the literate page, (b) decide whether a headline-scale SCS attempt is required for SCALE-04, and (c) decide whether the T=10 conditioning wall itself needs further characterization (or an `allow_almost`-style relaxation strictly on a measurement/calibration path, never the production gate) before SCALE-05 can be honestly checked off.

## Next Phase Readiness

- `results/ieee8500_benchmark/density_sweep_full.csv` now has 18 rows: the original 17 (9 with real SCS data replacing `scs_unavailable`) plus 1 new T=10 headline row, explicitly labeled non-comparable.
- `bench/` is a reusable, committed environment for any future SCS-dependent measurement work on this repo, without ever touching the root project's `[deps]`.
- The `--t-horizon` flag is now available for any future plan wanting to explore the IEEE-8500 headline fixture at horizons other than the general sweep's `T=24` or `--quick`'s `T_QUICK=10` (which now coincide, by construction, at their shared floor).
- **Flagged for a future plan:** the NEW `ALMOST_OPTIMAL` conditioning wall at headline scale (T=10, density=0.1) is a genuinely new finding requiring its own root-cause investigation (mirroring plan 25-07's near-zero-impedance methodology) before a certified headline exactness verdict — at ANY horizon — becomes possible. `deferred-items.md` item 4 carries the full detail forward.
- No blockers for the phase to be re-verified — both gaps the prior verification (`gaps_found`, 7/9) identified now have real, honestly-characterized evidence in place of the prior "never measured"/"never succeeded" state.

---
*Phase: 25-ieee-8500-scalability-benchmark*
*Completed: 2026-08-22*

## Self-Check: PASSED

- All 7 claimed files (`scripts/benchmark_ieee8500.jl`, `bench/Project.toml`, `bench/Manifest.toml`,
  `results/ieee8500_benchmark/density_sweep.csv`, `results/ieee8500_benchmark/density_sweep_full.csv`,
  `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md`, this summary) verified
  present on disk.
- All 5 task commits (`c8d4a47`, `582f609`, `0d40b3c`, `3db4457`, `0fc7d66`) verified present in
  `git log`.

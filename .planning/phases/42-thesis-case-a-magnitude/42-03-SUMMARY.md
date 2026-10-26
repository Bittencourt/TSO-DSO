---
phase: 42-thesis-case-a-magnitude
plan: 03
subsystem: measurement-runner
tags: [pre-registration, magnitude-runner, agr-ladder, upsert-csv, proxy-certification, julia, tdd]

# Dependency graph
requires:
  - plan: 42-01
    provides: the pre-registered protocol (42-CASE-A-PROTOCOL.md, committed) + the guard/gain/provenance helpers in scripts/lib/case_a_common.jl
  - plan: 42-02
    provides: the compare_tariffs agr_optimizer seam (lens plans) and solve_admm's agr_optimizer conditioning precedent
  - phase: 40-case-a-population
    provides: the AGR_TOL_RUNGS ladder idiom, the :case_a_784 population, the iters=80 refusal precedent
  - phase: 41-settlement-tariffs
    provides: the tariff_comparison.jl upsert/provenance/parse idioms, SEED_GROUND = 20260718, the ieee13-ground FIT INFEASIBLE precedent
provides:
  - scripts/case_a_magnitude.jl — the protocol-gated measurement runner (modes: headline, proxy; --seed validated against the protocol set; AGR_TOL_RUNGS ladder stop-on-first-certified; honest status rows; kill-anytime upsert CSVs; per-row protocol_sha + provenance)
  - results/thesis_case_a_magnitude/proxy.csv — the committed proxy restatement artifact (ieee123-default seed 20260719 gain Δ%=+0.0135% + ieee13-default seed 20260718 same-feeder row with the known FIT INFEASIBLE recorded)
  - 2 fast-lane structural test items: the runner source contract (rungs/seeds/modes/guard/ratio-ban pinned as committed text) and the committed-CSV item (schema, status vocabulary, Δ identity, lens ledger)
affects: [42-04 (runner gains crosscheck/lenses/ablation modes against this registered skeleton), 42-05 (the SAME machinery at 784 houses — certified here at proxy scale), 42-06 (reproducibility band)]

# Tech tracking
tech-stack:
  added: []   # zero new packages (threat register T-42-03-SC: empty by construction)
  patterns: [protocol-gated-runner, pre-planned-values-source-contract, per-row-honest-status-upsert, shared-measure-point, declared-order-ladder-with-dict-drift-guard]

key-files:
  created:
    - scripts/case_a_magnitude.jl
    - results/thesis_case_a_magnitude/proxy.csv
  modified:
    - scripts/README.md
    - test/test_case_a_magnitude.jl

key-decisions:
  - "Upsert key extended with the row-granularity columns — (:mode|fixture, :seed, :t_horizon, :kind, :rung): the plan's bare identity key would make each per-row upsert DELETE the sibling rows of the same run (every rung attempt must survive as its own row; a kill must leave captured rows). All stated upsert truths preserved"
  - "_measure_point(feeder_sym, pop_sym, seed) is THE shared code path for headline and proxy — the protocol §8 same-code-path claim made structural, not narrative"
  - "AGR ladder = AGR_TOL_RUNGS Dict (verbatim) + an explicit declared-order tuple (Julia Dicts are unordered) with a top-level drift guard between the two; stop-on-first-certified; hard stop records error:ladder_exhausted"
  - "ensure_all_schemas is per-mode: each mode writes exactly its own artifact (files_modified contract), and WR-04's header-only-on-every-exit-path guarantee covers the active mode's failure branches"
  - "The banned naive-ratio shape is kept out of the script text entirely (comments spell it uppercase W_DADP/W_FIT), so the source-contract test's literal-absence assertion is simple and robust"
  - "Proxy restatement recorded at Δ% = +0.0135% (seed 20260719) — same order of magnitude as the ≈+0.263% restatement, not equal by design (protocol §8: the seeding differs from thesis_case123_repro's ad-hoc construction; reported, never gated, never tuned)"

patterns-established:
  - "Pattern: source-contract test — pin a runner's pre-planned values (rungs/seeds/modes) as committed TEXT via occursin (never counts, never exact-set on extendable whitelists); silent additions fail until the protocol is amended (the deliberate-act friction, generalized)"
  - "Pattern: honest-status upsert with row-granularity keys — per-row upserts survive kills only when the key carries the row's own identity (kind/rung), not just the provenance identity"
  - "Pattern: fail-loud declared-column guard on the MERGED row (raw rows merge identity+sha+provenance at the write boundary)"

requirements-completed: [REPRO-03, REPRO-04, REPRO-05]   # runner + certified machinery + proxy restatement artifact; the 784-house runs and writeup (42-05/42-06) consume this plan's certified machinery

# Metrics
duration: 28min
completed: 2026-10-26
---

# Phase 42 Plan 03: Case A Magnitude Measurement Runner Summary

**The protocol-gated magnitude runner (`scripts/case_a_magnitude.jl`, 803 lines) — pre-registration guard as the first executed code path, AGR ladder stop-on-first-certified, honest status rows, kill-anytime upsert CSVs — CERTIFIED end-to-end on the small IEEE-123/IEEE-13 fixtures (124 s): ieee123-default certifies at the default rung with a FIT leg (Δ% = +0.0135%, sign-safe), ieee13-default records its known FIT INFEASIBLE; proxy.csv committed.**

## Performance

- **Duration:** 28 min
- **Started:** 2026-10-26T12:38:01Z
- **Completed:** 2026-10-26T13:06Z
- **Tasks:** 3/3 (TDD RED→GREEN pairs)
- **Files modified:** 4 (2 created, 2 modified)

## Accomplishments

- **Source-contract test (RED `f479f1b` → GREEN `72f55cb`)**: a fast-lane `@testitem` reads the runner as TEXT and pins the pre-planned values — the four `AGR_TOL_RUNGS` String keys, the `(42, 43, 44, 45, 46)` protocol seed tuple, `assert_protocol_registered` on the main path, the mode whitelist with CONTAINS-semantics (headline/proxy; extendable by later waves without breaking the contract), `build_population(:case_a_784` at the registered config, the protocol path string, `ADMM().ρ` as the locked ρ source — and bans the naive-ratio shape outright. Silent rung/seed additions now require a protocol amendment + script edit + test-visible text change.
- **The runner (GREEN `72f55cb`)**: `assert_protocol_registered()` is the FIRST executed code path (main + both mains); the 40-hex SHA is stamped on every row. `--mode headline` (one registered seed per invocation, default 42) runs the frozen registered configuration through `run_ladder_outcome` (conditional `agr_optimizer` splat per rung; typed error rows with iters/−1 sentinel; `:budget_exceeded` honest rows; `error:ladder_exhausted` hard stop), then the UNCHANGED `fit_baseline` (`on_inexact = :report`) with the ONE protocol-pinned `tol_gap 1e-10` SOLVER retry, then `welfare_gain` from the shared lib ONLY. `--mode proxy` re-runs the SAME `_measure_point` on the two pinned fixtures. Validation ArgErrors list permitted values; misuse propagates; `--seed` is rejected in proxy mode.
- **Proxy certification (RED `b7b3ccb` → GREEN/fix `83bd6a7`)**: the committed-CSV structural item (schema, honest status vocabulary incl. `reused`/`:budget_exceeded`, algebraic Δ-identity re-derivation at 1e-9 relative, lens-row ledger conservation for 42-05's future `lens_summary.csv`) went RED on the empty directory, then GREEN against the real run. The 124 s proxy run certified the machinery: ieee123-default (85 aggregators, seed 20260719) converged at the default rung (iters=4, 53.1 s), FIT attempt `error:CertificateError` → pinned retry **ok** → gain row **ΔW = +5.5498424509423785, Δ% = +0.013516192967581844** (sign-safe; reported, never gated); ieee13-default (10 aggregators, seed 20260718) converged at the default rung (iters=76, 13.2 s) and recorded the KNOWN FIT INFEASIBLE (`error:SolveFailedError` at attempt AND retry — the committed `tariff_comparison.csv` precedent, exactly as the protocol expects). Every row stamps `protocol_sha = 60e5d549…` + full provenance.

## Task Commits

1. **Task 1: RED — runner source contract** - `f479f1b` (test)
2. **Task 2: GREEN — the runner + README registration** - `72f55cb` (feat)
3. **Task 3a: RED — committed-CSV structural item** - `b7b3ccb` (test)
4. **Task 3b: proxy certification — merge-order guard fix + committed proxy.csv** - `83bd6a7` (fix)

_Tasks 1→2 and 3a→3b are the TDD pairs (each RED commit precedes its GREEN in history)._

## Test Evidence

- **RED 1 (`f479f1b`)**: `TSODSO_TEST_FILES=test_case_a_magnitude.jl julia --project=. -e 'import Pkg; Pkg.test()'` → exit 1; the new item failed on `isfile(src_path)` + `SystemError: … case_a_magnitude.jl: No such file or directory` (the natural RED — runner absent); the 5 pre-existing 42-01 items stayed green.
- **GREEN (`72f55cb`)**: same command → exit 0, **34/34 assertions**; guard passes from the script env (`guard OK: 60e5d549`); `check_scripts_index.py` green; `git diff a1cff12..HEAD -- src/` EMPTY (no src/ file touched).
- **Sanity gate (`72f55cb`)**: `TSODSO_TEST_FILES=test_case_a_magnitude.jl,test_settlement.jl` → exit 0 (settlement suite unbroken).
- **RED 2 (`b7b3ccb`)**: committed-CSV item errored with the clear `no artifacts yet: results/thesis_case_a_magnitude/ has no CSV` message; exit 1.
- **Proxy run (`83bd6a7`)**: `julia --project=. scripts/case_a_magnitude.jl --mode proxy` → **exit 0 in 124 s**, both fixture points measured, 4 honest rows upserted; Δ identity re-derives exactly on the gain row.
- **GREEN 2 (`83bd6a7`)**: fast lane → exit 0, **74/74 assertions** (42-01 guard/gain items + source contract + committed-CSV item against the real artifact).
- **CLI guard discipline**: `--mode headline --seed 999` → exit 1, `ArgumentError: --seed 999 is not a pre-registered seed — the protocol seed set … is: 42, 43, 44, 45, 46`; `--mode bogus` → exit 1 listing registered modes; `--mode proxy --seed 42` → exit 1 (proxy pins its own seeds).
- **CI index guard**: `python3 .github/scripts/check_scripts_index.py` → "scripts index complete (45 tracked files checked)".
- **No `src/` diff**: `git diff a1cff12..HEAD -- src/` empty (re-verified post-commit).

## Files Created/Modified

- `scripts/case_a_magnitude.jl` (803 lines) — the measurement runner (scaffold/imports, pre-planned values with drift guard, kv-flag parsing, `run_rung_outcome`/`run_ladder_outcome`, `run_fit_outcome` with the pinned retry, shared `_measure_point`, upsert machinery with merged-row guard, headline/proxy mains, entry guard).
- `results/thesis_case_a_magnitude/proxy.csv` — the committed proxy artifact (ieee123-default rung+gain rows; ieee13-default rung+gain rows; statuses as measured).
- `scripts/README.md` — `case_a_magnitude.jl` registered (purpose, how-to-run, outputs, "Maintained; long-running").
- `test/test_case_a_magnitude.jl` (246 lines) — +2 fast-lane items (source contract; committed-CSV structure).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The plan's upsert keys would make sibling rows self-destruct**
- **Found during:** Task 2 (design review while writing `write_point_rows`)
- **Issue:** The plan specified upsert keys `(:mode, :seed, :t_horizon)` / `(:fixture, :seed, :t_horizon)`, but the runner emits MULTIPLE rows per run (one per rung attempt + the gain row) and upserts per row (the kill-anytime contract). Per-row upserts under the bare identity key would DELETE all sibling rows of the same run on every subsequent write (`keep = rows whose key matches no new key`), violating "every rung attempt = one CSV row" and "a kill leaves the rows already captured".
- **Fix:** Key extended with the row-granularity columns: `(:mode, :seed, :t_horizon, :kind, :rung)` and `(:fixture, :seed, :t_horizon, :kind, :rung)`. Re-runs still replace exactly their own rows; siblings and other seeds/runs are never dropped.
- **Files modified:** `scripts/case_a_magnitude.jl`
- **Commit:** `72f55cb`

**2. [Rule 1 - Bug] Declared-column guard asserted the RAW row before the identity/sha/provenance merge**
- **Found during:** Task 3 (first proxy run)
- **Issue:** `write_point_rows` checked `all(c in keys(r) for c in cols)` against the RAW measurement row (which carries only the measured columns) BEFORE merging identity + `protocol_sha` + provenance — so the guard fired on every row. The first proxy run measured cleanly (ieee123 certified at the default rung; FIT pinned-retry ok) then died at the CSV write with exit 1. The kill was safe (header-only proxy.csv shipped — the upsert/honesty contract working as designed).
- **Fix:** The guard now checks the MERGED row (the row actually written must carry every declared column); the fail-loud behavior is retained. Re-run → clean exit 0 in 124 s.
- **Files modified:** `scripts/case_a_magnitude.jl`
- **Commit:** `83bd6a7`

### Deliberate Interpretations (within plan discretion)

- **`ensure_all_schemas` is per-mode** (each mode ensures exactly its own artifact): the plan's `files_modified` lists only `proxy.csv`, so a headline never run must not ship a header-only `magnitude.csv` in this plan; WR-04's guarantee (header-only table on every exit path) is scoped to the active mode's failure branches.
- **AGR run order**: `AGR_TOL_RUNGS` is a Julia Dict (unordered), so the declared order lives in an `AGR_RUNG_ORDER` tuple with a top-level drift guard — the protocol §4 table's run order (default → gap_1e-10 → gap_1e-12 → gapfeas_1e-12) is otherwise unenforceable.
- **Banned-literal hygiene**: the script's comments spell the banned ratio uppercase (`W_DADP/W_FIT`), keeping the test's `!occursin("w_dadp / w_fit", src)` assertion simple and comment-proof.

No architectural deviations (Rule 4): none triggered. No authentication gates. No blockers.

## Measured Results (recorded, never gated)

| fixture | rung | status | welfare_dadp | welfare_fit | ΔW | Δ% | iters |
|---------|------|--------|--------------|-------------|----|----|-------|
| ieee123-default (seed 20260719) | default | converged | −41055.14279676705 | −41060.692639217996 | +5.5498424509423785 | +0.013516192967581844 | 4 |
| ieee13-default (seed 20260718) | default | converged | −4822.993417743747 | — (FIT INFEASIBLE, attempt+retry refused) | — | — | 76 |

The ieee123 FIT leg required the protocol-pinned retry (`error:CertificateError` at the registered call → `tol_gap 1e-10` retry ok — both outcomes recorded). Per protocol §8, proximity to the ≈+0.263% restatement is REPORTED, never gated: the pre-registered definition yields +0.0135% on this fixture's seeding, and no constant was tuned toward any target. The ieee13 FIT INFEASIBLE is the KNOWN committed precedent, recorded honestly.

## Known Stubs

None. The runner is fully wired (ladder, FIT retry, gain, upserts, provenance); `reused` status rows are 42-04's emitters — the vocabulary and the structural test admit them, and the protocol's reuse discipline defines them; nothing in this plan ships a placeholder.

## Threat Check

All register entries addressed: T-42-03-1 (ungated run) — the guard is the first executed code path in `main` AND both mains, sha stamped per row, and the source-contract test pins the guard's presence in committed text; T-42-03-2 (silent re-tuning) — rungs/seeds/modes pinned as committed text (occursin-based); T-42-03-3 (row provenance) — every row carries non-empty `protocol_sha` + provenance, enforced by the committed-CSV item; T-42-03-4 (flag misuse) — all three misuse paths verified exiting nonzero with permitted-value ArgErrors; T-42-03-5 (runaway measurement) — `--time-limit-s` forwards to `solve_admm` and `:budget_exceeded` is a recorded outcome in the test vocabulary; T-42-03-SC — zero new packages. No security-relevant surface beyond the plan's threat model (CLI flags validated; CSVs under `results/`; no network/auth paths).

## TDD Gate Compliance

- Task 1/2 pair: `test(42-03)` RED `f479f1b` precedes `feat(42-03)` GREEN `72f55cb` in history — VERIFIED.
- Task 3 pair: `test(42-03)` RED `b7b3ccb` precedes the GREEN `fix(42-03)` `83bd6a7` (the structural item went RED on the empty directory and GREEN on the committed artifact) — VERIFIED.

## Self-Check: PASSED

- `scripts/case_a_magnitude.jl` exists (803 lines > min_lines 150) — FOUND
- `results/thesis_case_a_magnitude/proxy.csv` exists (4 data rows, contains `protocol_sha`) — FOUND
- `scripts/README.md` contains `case_a_magnitude.jl` (index guard green, 45 tracked files) — FOUND
- `test/test_case_a_magnitude.jl` contains both new items — FOUND
- Commits `f479f1b`, `72f55cb`, `b7b3ccb`, `83bd6a7` all present in `git log`, REDs preceding GREENs — FOUND
- Fast lane exit 0 (74/74 assertions) — VERIFIED
- CLI misuse paths exit nonzero with permitted-value ArgErrors — VERIFIED
- `git diff a1cff12..HEAD -- src/` empty — VERIFIED

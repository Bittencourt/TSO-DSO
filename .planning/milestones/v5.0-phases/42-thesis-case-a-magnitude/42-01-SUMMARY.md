---
phase: 42-thesis-case-a-magnitude
plan: 01
subsystem: measurement-infrastructure
tags: [pre-registration, welfare-gain, sign-safe, protocol-guard, julia, tdd]

# Dependency graph
requires:
  - phase: 40-case-a-population
    provides: the certified AGR ladder idiom (AGR_TOL_RUNGS), agreement.csv measured precedents, the :case_a_784 population
  - phase: 41-settlement-tariffs
    provides: tariff_comparison.jl upsert/provenance idioms, the case-a-784 (run) refusal precedent, SEED_GROUND
provides:
  - 42-CASE-A-PROTOCOL.md — the repo's first pre-registration document, committed BEFORE any measurement (success criterion 1)
  - scripts/lib/case_a_common.jl — PROTOCOL_PATH, protocol_sha, assert_protocol_registered, welfare_gain (SIGN-SAFE), provenance_row, flatten_note
  - test/test_case_a_magnitude.jl — 5 fast-lane structural items (sign-safety incl. thesis-ratio-inversion fixture, exact anchor, 3 guard behaviors)
affects: [42-02 (compare_tariffs seam), 42-03/42-04 (runner consumes guard + gain + provenance), 42-05 (writeup), 42-06 (reproducibility band)]

# Tech tracking
tech-stack:
  added: []   # zero new packages (42-RESEARCH Package Legitimacy Audit: empty by construction)
  patterns: [pre-registered-protocol-guard, sign-safe-gain-definition, tmpdir-git-repo-test-hermeticity]

key-files:
  created:
    - .planning/phases/42-thesis-case-a-magnitude/42-CASE-A-PROTOCOL.md
    - scripts/lib/case_a_common.jl
    - test/test_case_a_magnitude.jl
  modified:
    - scripts/README.md

key-decisions:
  - "Gain definition frozen as the SIGN-SAFE form Δ% = 100·(W_DADP−W_FIT)/|W_FIT| + ΔW; the naive ratio W_DADP/W_FIT is banned outright (sign-inverts on negative welfare ≈ −3.78e5 at 784 houses)"
  - "AGR ladder pre-registered as the only refusal answer (default → gap_1e-10 → gap_1e-12 → gapfeas_1e-12, stop-on-first-certified, String keys only); exactness gate/battery τ/ρ never touched"
  - "OFAT axes AND exact values pinned pre-run: fit_params {registered, lam_export_half, lam_export_double}, price_range {registered, scale_0.5, scale_2.0}, population {proxy_ieee123 seed 20260719, ieee13_default seed 20260718, nested rungs (1/78..1.0), full_784 reused}, device_mix {registered, batteries_out, pv_half}"
  - "'reused' added to the honest status vocabulary (provenance-transparent reuse, never re-solved, never fabricated)"
  - "protocol_sha returns a plain String (readchomp's SubString converted) — contract caught by the TDD guard test"
  - "Guard/gain helpers live in a plain-Julia lib (no DrWatson, no TSODSO) so runner and tests include it identically; repo root derived from @__DIR__, not projectdir()"

patterns-established:
  - "Pattern: pre-registration guard — assert_protocol_registered errors ('PRE-REGISTRATION VIOLATION') before any Case A run unless the protocol exists AND is committed; the 40-hex SHA stamps every CSV row (T-42-01-1/2 mitigations)"
  - "Pattern: protocol amendment discipline — append-only after the pre-run commit; post-intermediate-results changes are dated AMENDMENT sections in their own commits"
  - "Pattern: hermetic git-dependent tests — mktempdir + git init + inline -c user.name/email identity"

requirements-completed: [REPRO-03]

# Metrics
duration: 8min
completed: 2026-10-26
---

# Phase 42 Plan 01: Pre-Registered Protocol + Core Helpers Summary

**The repo's first pre-registration document (sign-safe gain `100·(W_DADP−W_FIT)/|W_FIT|`, frozen config, 4-rung AGR ladder, 4 pinned OFAT axes, 5 seeds) committed BEFORE any code, plus the fail-loud protocol guard and provenance helpers with RED→GREEN fast-lane tests.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-10-26T10:38:02Z
- **Completed:** 2026-10-26T10:46Z
- **Tasks:** 3/3
- **Files modified:** 4 (3 created, 1 modified)

## Accomplishments

- **Protocol pre-registered first**: `42-CASE-A-PROTOCOL.md` committed ALONE (`60e5d54`) before any code — sign-safe gain definition with the explicit ratio ban, frozen registered configuration, 4-rung AGR ladder (String keys — `:gap_1e-10` parses as subtraction), FIT-leg + centralized single-sanctioned-retry policies, 4 OFAT axes with exact pinned values, seeds {42, 43–46}, proxy fixture (IEEE-123 `:default` seed 20260719), append-only amendment discipline, no-tuning structural guard, golden policy. Absolute ordering provable from git history (success criterion 1 of ROADMAP Phase 42).
- **Sign-safe gain + guard helpers**: `scripts/lib/case_a_common.jl` — `welfare_gain` (the registered definition; no ratio method exists), `protocol_sha`/`assert_protocol_registered` (fail-loud "PRE-REGISTRATION VIOLATION" gate returning the 40-hex SHA for per-row stamping), `provenance_row`, `flatten_note`. Plain-Julia include-able (no TSODSO/DrWatson) by both the 42-03/42-04 runner and tests.
- **Fast-lane structural tests, RED→GREEN**: 5 `@testitem`s — sign-safety on the exact thesis +25%-ratio shape (naive ratio would read +1.25 for a welfare loss; inversion documented, never asserted), exact plumbing anchor `(Δ = 10.0, Δpct = 10.0)`, and the three guard behaviors (missing file, uncommitted file, committed file → 40-hex SHA) on hermetic tmpdir git repos. No golden on the measured magnitude; no solving; suite runs in seconds.

## Task Commits

Each task was committed atomically:

1. **Task 1: pre-registration protocol (own commit, BEFORE any code)** - `60e5d54` (docs)
2. **Task 2: RED — fast-lane structural tests** - `316c034` (test)
3. **Task 3: GREEN — case_a_common lib + README registration** - `f1eba72` (feat)

_Note: Tasks 2–3 are the TDD pair (RED commit precedes GREEN commit in history)._

## Test Evidence

- **RED** (`316c034`): `TSODSO_TEST_FILES=test_case_a_magnitude.jl julia --project=. -e 'import Pkg; Pkg.test()'` → exit 1; all 5 magnitude items errored with `SystemError: opening file ".../scripts/lib/case_a_common.jl": No such file or directory` (the natural RED — lib absent).
- **GREEN** (`f1eba72`): same command → exit 0; **20/20 tests passed** (5 magnitude items + runner guards), 3.4 s, zero "soft scope is ambiguous" warnings.
- **CI index guard**: `python3 .github/scripts/check_scripts_index.py` → "scripts index complete (44 tracked files checked)".
- **Guard tripwire (live)**: `assert_protocol_registered(joinpath(tempdir(), "nope.md"))` errors with "PRE-REGISTRATION VIOLATION" (verified via `@assert occursin(...)`); the real protocol resolves to SHA `60e5d54969d7944d9398e24d0d1cc6dc2d52ad4d`.
- **No `src/` file touched; no measurement run** (success criteria 4 and 5).

## Files Created/Modified

- `.planning/phases/42-thesis-case-a-magnitude/42-CASE-A-PROTOCOL.md` — the pre-registered protocol (10 sections: gain definition, frozen config, seeds, AGR ladder, FIT-leg policy, centralized cross-check policy, 4 OFAT axes, proxy restatement, no-tuning guard, golden policy; header carries the amendment policy)
- `scripts/lib/case_a_common.jl` — PROTOCOL_PATH + protocol_sha + assert_protocol_registered + welfare_gain + provenance_row + flatten_note (116 lines)
- `test/test_case_a_magnitude.jl` — 5 fast-lane structural items (112 lines)
- `scripts/README.md` — `lib/case_a_common.jl` registered (CI guard green)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `protocol_sha` returned `SubString{String}`, not `String`**
- **Found during:** Task 3 (GREEN run — the TDD test caught it)
- **Issue:** `readchomp` returns a `SubString{String}`, so `assert_protocol_registered`'s return failed the plan-specified `sha isa String` assertion (occursin passed, `isa String` did not) — the contract says a 40-hex String, and later plans stamp this value into every CSV row.
- **Fix:** `String(sha)` conversion in `protocol_sha`'s return path.
- **Files modified:** `scripts/lib/case_a_common.jl`
- **Commit:** `f1eba72` (folded into the GREEN commit)

No other deviations — plan executed exactly as written otherwise. No authentication gates. No blockers.

## Known Stubs

None. Every function in `scripts/lib/case_a_common.jl` is fully implemented and tested; no placeholder text, no unwired data paths.

## Threat Check

All four register entries addressed: T-42-01-1 (guard errors on missing file AND empty git history — tested), T-42-01-2 (full 40-hex SHA returned, String-typed, ready for per-row stamping), T-42-01-3 (tmpdir repos with inline git identity — hermetic), T-42-01-SC (zero new packages). No new security-relevant surface beyond the plan's threat model.

## Self-Check: PASSED

- `42-CASE-A-PROTOCOL.md` exists and has git history (`60e5d54`, only commit touching the file) — FOUND
- `scripts/lib/case_a_common.jl` exists (117 lines, > min_lines 40) — FOUND
- `test/test_case_a_magnitude.jl` exists (112 lines, > min_lines 40; item names contain "magnitude") — FOUND
- `scripts/README.md` contains `case_a_common.jl` — FOUND
- Commits `60e5d54`, `316c034`, `f1eba72` all present in `git log` — FOUND
- Fast lane green (exit 0) — VERIFIED

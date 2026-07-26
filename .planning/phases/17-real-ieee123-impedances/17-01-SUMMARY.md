---
phase: 17-real-ieee123-impedances
plan: 01
subsystem: data-ingestion
tags: [opendss, ieee123, fortescue, offline-reproducibility, dependency-free]
requires: []
provides:
  - "scripts/data/IEEE123Master.dss (vendored, offline-reproducible OpenDSS IEEE-123 master file)"
  - "scripts/data/IEEELineCodes.DSS (vendored, offline-reproducible OpenDSS line-code definitions)"
  - "scripts/reduce_ieee123_impedances.jl (dependency-free parser + Fortescue reducer + --verify + emitter)"
affects:
  - "Plan 17-02 (ieee123.jl impedance ingestion) consumes the emit_output()/main() default-mode
    output of this script (src/data/ieee123_impedances.jl, not committed by this plan)"
tech-stack:
  added: []
  patterns:
    - "Dependency-free regex parsing (Base + stdlib PCRE only, zero `using` statements)"
    - "throw(ArgumentError(...)) tripwires, never @assert (WR-02 convention)"
    - "Committed-vendored-data-over-live-fetch (offline reproducibility)"
key-files:
  created:
    - scripts/data/IEEE123Master.dss
    - scripts/data/IEEELineCodes.DSS
    - scripts/reduce_ieee123_impedances.jl
  modified: []
decisions:
  - "Vendored both upstream .dss files verbatim with a `!`-comment provenance header (URL +
    fetch date 2026-07-25) prepended above the original content, rather than re-fetching live
    at every run — satisfies IMPED-01's 'offline, reproducible' requirement."
  - "Implemented the bus-terminal normalization as a leading-digit-prefix regex (`^(\\d+)`)
    rather than a literal `r`-suffix strip, so it generalizes to any regulator-secondary alias
    the raw file might use, not just the three observed cases (9r/25r/160r)."
  - "Ran the script's default (non-`--verify`) mode once to prove the edge-lookup + emission
    path works end-to-end (117/122 edges resolved, 5 switch edges correctly excluded), then
    deleted the generated src/data/ieee123_impedances.jl — its committed shape is explicitly
    scoped to Plan 17-02 per the plan's own task text ('this task only needs the emission
    function implemented and callable')."
metrics:
  duration: "~35 minutes (excluding worktree-reset overhead)"
  completed: 2026-07-26
---

# Phase 17 Plan 01: Vendor IEEE-123 OpenDSS Data + Dependency-Free Impedance Reducer Summary

Dependency-free Julia regex parser reduces the vendored public OpenDSS IEEE-123 line-code
matrices to positive-sequence R1/X1 via Fortescue-averaging, self-verified against a pinned
sanity value, with zero new package dependencies.

## What Was Built

**Task 1 — Vendored upstream OpenDSS fixture files** (commit `7532a31`):
- `scripts/data/IEEE123Master.dss` and `scripts/data/IEEELineCodes.DSS` fetched verbatim
  (HTTP 200 confirmed live this session) from
  `raw.githubusercontent.com/tshort/OpenDSS/master/Distrib/IEEETestCases/123Bus/` — exact
  case required for `IEEELineCodes.DSS` (lowercase extension 404s).
- Each file carries a `!`-comment provenance header (source URL + fetch date `2026-07-25`)
  prepended above the byte-identical original content.
- Confirmed neither file is excluded by `.gitignore` (only the repo-root `/data/` DrWatson
  output directory is ignored, not `scripts/data/`).
- Content verified: 126 `New Line.*` statements, 29 `New linecode.*` blocks — the full,
  unmodified upstream file content (not pre-trimmed).

**Task 2 — Dependency-free regex parser + Fortescue reduction + `--verify`** (commit `d709b22`):
- `scripts/reduce_ieee123_impedances.jl`: zero `using` statements anywhere in the file
  (`Project.toml [deps]` confirmed byte-identical via `git diff Project.toml`, empty).
- `parse_line_records`: single-line (non-dotall) regex over `New Line.*` statements; lines
  without a `LineCode=` field (the `Sw1`..`Sw8` switch/tie definitions) simply don't match
  and are excluded automatically — no separate switch-filtering pass needed.
- `parse_lower_triangular` + `fortescue_reduce`: parses the OpenDSS pipe-delimited
  lower-triangular `rmatrix=`/`xmatrix=` literals into a full symmetric matrix, then reduces
  via `R1 = mean(diag) - mean(offdiag)` (same for X1), short-circuiting to `mat[1,1]` for
  single-phase (n=1) linecodes.
- `referenced_linecodes` collects the SET of `LineCode=` values actually used (asserts
  exactly 12 via `throw(ArgumentError(...))`), then `parse_all_linecodes` parses only those
  12 of the 29 blocks defined in the shared `IEEELineCodes.DSS` file.
- `--verify` mode: full parse+reduce, asserts `length(linecodes) == 12` and linecode.1's
  `(R1, X1)` matches the pinned sanity pair `(0.057967, 0.118756)` within `atol=1e-5`, writes
  no output file. Confirmed passing: `R1=0.057967171666666664, X1=0.11875631333333338`.
- Default mode: reads `src/data/ieee123.jl` as plain text (never `using TSODSO`) to
  regex-extract `IEEE123_EDGES`/`IEEE123_SWITCH_EDGES` literally, looks up each non-switch
  edge's raw `New Line.*` record in either bus order, computes `z_Ω = R1 × Length` with no
  length-unit conversion (OpenDSS's own no-op default when `Units=` is unset), and emits
  `src/data/ieee123_impedances.jl` declaring `const IEEE123_BRANCH_RX_OHMS`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Regulator-secondary bus-name suffix strip required for 3 edge lookups**
- **Found during:** Task 2, while implementing the edge-lookup step (`find_line_record`).
- **Issue:** The raw `IEEE123Master.dss` file uses internal regulator-secondary node aliases
  (`9r`, `25r`, `160r`) on the `Bus1=` side of three `New Line.*` statements (`L11`, `L25`,
  `L117`), but the existing, already-collapsed `IEEE123_EDGES` fixture keys on the bare
  terminal number (`9`, `25`, `160`). A naive `(Bus1, Bus2)` lookup for edges `(9,14)`,
  `(25,26)`, and `(160,67)` would throw the lookup-miss `ArgumentError` even though these are
  legitimate, resolvable edges — RESEARCH.md's Pitfall 3 flags the existence of these
  regulator-secondary aliases but does not spell out that the lookup itself needs a suffix
  strip to succeed.
- **Fix:** `parse_terminal` extracts the leading integer run via `^(\d+)` from any bus
  token, which transparently resolves `"9r"` -> `9`, `"25r"` -> `25`, `"160r"` -> `160` (and
  the ordinary case `"149"` -> `149` unchanged) — a single, general fix rather than
  special-casing the three observed tokens.
- **Verified:** Ran the script's default mode end-to-end this session — all 117 non-switch
  edges resolved with zero lookup misses (122 total edges − 5 switch edges).
- **Files modified:** `scripts/reduce_ieee123_impedances.jl` (`parse_terminal` function).
- **Commit:** `d709b22`

### Design Choices (not deviations, explicit plan text)

- The plan's Task 2 action text explicitly scopes the emitted `src/data/ieee123_impedances.jl`
  const table's shape to Plan 17-02 ("this task only needs the emission function implemented
  and callable"), and the plan's `files_modified` frontmatter does not list that file. I ran
  the script's default mode once (undocumented as a task requirement, but necessary to prove
  `emit_output`/`build_branch_rx_ohms` work end-to-end rather than merely type-checking), then
  deleted the generated file so this plan's committed file set stays exactly
  `scripts/data/IEEE123Master.dss`, `scripts/data/IEEELineCodes.DSS`,
  `scripts/reduce_ieee123_impedances.jl` — matching the plan's own scope.

## Auth Gates

None — no authentication required; public, unauthenticated `raw.githubusercontent.com` fetch.

## Verification

- `julia scripts/reduce_ieee123_impedances.jl --verify` — exit 0, PASS
  (`R1=0.057967171666666664, X1=0.11875631333333338`, pinned `≈0.057967/≈0.118756`)
- `grep -c '== 12' scripts/reduce_ieee123_impedances.jl` — 3 (>= 1 required)
- `grep -c '@assert' scripts/reduce_ieee123_impedances.jl` — 0
- `grep -c '^using ' scripts/reduce_ieee123_impedances.jl` — 0
- `git diff Project.toml` — empty
- `git check-ignore -q scripts/data/IEEE123Master.dss; echo $?` — 1 (not ignored)
- `git check-ignore -q scripts/data/IEEELineCodes.DSS; echo $?` — 1 (not ignored)
- `git status --porcelain scripts/data/ scripts/reduce_ieee123_impedances.jl` — exactly 3 new
  files, no `Project.toml`/`Manifest.toml` diff

## Known Stubs

None — this plan ships a fully functional, verified parser; no placeholder/stub data paths.

## Threat Flags

None — the threat model's two `mitigate` items (T-17-01 vendored-provenance, T-17-02 parser
self-check tripwires) are both directly implemented as specified; no new surface introduced
beyond what the threat model already anticipated.

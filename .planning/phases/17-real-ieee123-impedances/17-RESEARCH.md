# Phase 17: Real IEEE-123 Impedances - Research

**Researched:** 2026-07-25
**Domain:** OpenDSS distribution-feeder data parsing, Fortescue symmetrical-component reduction, Julia per-unit data ingestion
**Confidence:** HIGH (data reachability, units, reduction formula — all verified against the actual live file content, not just docs) / MEDIUM (whether real impedances preserve voltage-binding — genuinely unverified until the ADMM/centralized solve is re-run)

## Summary

The public OpenDSS IEEE-123 source files ARE reachable right now from this sandbox, over plain
`curl`, with no auth: `IEEE123Master.dss` and `IEEELineCodes.DSS` both returned HTTP 200 from
`raw.githubusercontent.com/tshort/OpenDSS/master/Distrib/IEEETestCases/123Bus/`. **Casing
matters** — `IEEELineCodes.DSS` (exact case) is the only one that resolves; `IEEELineCodes.dss`
(lowercase extension) 404s. The Fortescue-averaging reduction recipe from the known-data-source
brief was independently re-derived from the live file content and reproduces the pinned sanity
value exactly: linecode.1 → R1 = 0.057967 Ω/unit-length, X1 = 0.118756 Ω/unit-length (matches the
memory-pinned ≈0.05797 / ≈0.11876 to 4 significant figures).

The file confirms several things the STATE.md flags asked to be checked live rather than assumed:
the "units trap" resolves cleanly (OpenDSS applies **no length-unit conversion** when `Units=` is
unspecified anywhere in the chain — self-consistent bookkeeping, not a physical-unit lookup), the
per-unit magnitudes of the real reduced impedances land in the **same order of magnitude** as the
current synthetic placeholder (both ~1e-3–1e-2 pu per segment on the existing 1 MVA/4.16 kV base),
and only 12 of the 29 line codes defined in the shared `IEEELineCodes.DSS` file are actually used by
the 123-bus case (the rest belong to the co-located 34-bus/13-bus/4-bus test cases bundled in the
same file — a real parsing trap if the script naively ingests every `linecode.*` block).

The single biggest research finding that changes the phase's likely implementation path: **a
hand-rolled, dependency-free regex/text parser is sufficient and preferable to routing through
PowerModelsDistribution.** The actual `.dss` syntax needed (`New Line.<name> ... Bus1=... Bus2=...
LineCode=... Length=...` and `New linecode.<n> nphases=... ~ rmatrix = [...] ~ xmatrix = [...]`) is
simple, regular, and fully covered by ~50 lines of parsing logic with zero new Julia dependencies
(not even a weakdep). This sidesteps the entire "keep PMD out of runtime `[deps]`" concern raised
in the phase brief — there is no PMD to keep out if it is never introduced. PMD-as-oracle remains
available as an optional secondary cross-check (solve a plain power flow on the reduced network and
compare against a published/PMD-parsed result) but is not required for the primary parse+reduce
path, and per CLAUDE.md's own "PMD as data oracle only, never runtime dep" stance, avoiding it
entirely is the simpler compliant choice.

**Primary recommendation:** Write a small, dependency-free Julia script
(`scripts/reduce_ieee123_impedances.jl`, no new `[deps]` entries) that (1) downloads or reads a
vendored copy of the two `.dss` files, (2) regex-parses only the `New Line.*` statements referencing
LineCode 1–12 and the corresponding `New linecode.{1..12}` `rmatrix`/`xmatrix` blocks, (3) reduces
each 3×3/2×2/1×1 matrix to positive-sequence `R1`, `X1` via Fortescue-averaging, (4) computes
`z_Ω = R1 × Length` per segment with **no unit conversion** (matching OpenDSS's own no-op default),
(5) emits a committed Julia source file with a `const IEEE123_BRANCH_RX` table **in Ohms**, keyed by
the *existing* `(from_terminal, to_terminal)` pairs already in `IEEE123_EDGES` — topology untouched
— and (6) `ieee123_modified()` converts Ω → pu via the already-existing `to_pu_impedance` helper at
ingestion time, exactly mirroring the existing `to_pu_power(IEEE123_HEAD_SMAX_MVA, IEEE123_BASE)`
pattern in the same file.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-------------------|
| IMPED-01 | Offline, reproducible script parses public OpenDSS IEEE-123 case (`IEEE123Master.dss` + `IEEELineCodes.DSS`) and reduces 3-phase line-code matrices to positive-sequence R1/X1 per segment via documented Fortescue-averaging, with PMD kept out of runtime `[deps]` | Reachability confirmed live (HTTP 200, exact casing documented); parsing grammar verified against live file content; recommends a dependency-free regex parser that makes the PMD-out-of-runtime-deps concern moot by not depending on PMD at all (see Standard Stack > Alternatives Considered, Assumption A3); Fortescue reduction formula independently re-derived and verified against the pinned sanity value (Architecture Patterns > Pattern 2) |
| IMPED-02 | `ieee123.jl` consumes committed real positive-sequence impedances as a pure-data `const` table in place of synthetic values (topology untouched), with reduction assumptions/caveats documented | Exact current synthetic structure documented (2 uniform scalars `IEEE123_LINE_R`/`IEEE123_LINE_X`); recommended replacement shape (`IEEE123_BRANCH_RX_OHMS` per-segment Dict keyed by existing `IEEE123_EDGES` tuples) specified in Architecture Patterns > Pattern 1 & 3; topology-preservation lookup strategy specified in Common Pitfalls > Pitfall 3; units/regulators/single-phase-lateral caveats documented in Common Pitfalls > Pitfalls 1-3 |
| IMPED-03 | Real-impedance IEEE-123 case verified to remain voltage-binding; PV/aggregator population re-tuned and documented if required; prior synthetic goldens preserved or consciously re-pinned | Current population-scaling seam identified (`test/fixtures_phase7.jl` `LOAD_SCALE_IEEE123`/`PV_SCALE_IEEE123`/`DEV_SCALE_IEEE123`); current absence of any numeric voltage-binding assertion documented as a Wave 0 gap; existing behavioral (non-numeric-golden) regression bounds identified in `test_ieee123_admm.jl`/`test_acceptance.jl`; quantitative order-of-magnitude comparison between real and synthetic per-segment impedances performed (Common Pitfalls > Pitfall 4) as supporting-but-not-conclusive evidence |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Fetch/parse public OpenDSS `.dss` text | Offline script (`scripts/`) | — | One-time, offline, reproducible; not part of the runtime package |
| Fortescue R1/X1 reduction | Offline script (`scripts/`) | — | Deterministic pure-math transform on parsed matrices; belongs beside the parse, not in `src/` |
| Committed per-segment Ω table | `src/data/` (generated, committed source file or literal `const`) | — | Becomes the framework's citable data, must ship in the package like `IEEE123_EDGES` today |
| Ω→pu conversion | `src/data/ieee123.jl` (`ieee123_modified()`) | `src/units/PerUnit.jl` (`to_pu_impedance`, already exists) | Matches the file's own documented "SI→pu ONCE at ingestion" rule; never convert inside a model builder |
| Voltage-binding verification | `test/` (new assertion) + `scripts/` (diagnostic) | — | Behavioral property of the solved network, checked post-solve, not at data-ingestion time |
| PV/aggregator re-tune (if needed) | `test/fixtures_phase7.jl` (`Phase7Fixtures` constants) | — | Population scaling already lives here (`LOAD_SCALE_IEEE123` etc.); same seam owns any re-tune |

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Network access to `raw.githubusercontent.com` | IMPED-01 fetch step | ✓ (verified this session) | — | Vendor a committed copy of the two raw `.dss` files under `scripts/data/` at research time so the phase never depends on live network access again — recommended regardless of current reachability, since IMPED-01 requires "offline, reproducible" |
| `curl` | one-time fetch | ✓ | — | — |
| Julia | parse/reduce script + `ieee123.jl` | ✓ | 1.12.5 (juliaup) | — |
| PowerModelsDistribution.jl | optional secondary cross-check only | Not installed; not required by primary path | 0.16.0 per Julia General registry (already documented in CLAUDE.md, sourced 2026-07-18) | Skip entirely — hand-rolled parser is the primary path |

**Missing dependencies with no fallback:** None — the primary path has zero external runtime
dependencies beyond what already exists.

**Missing dependencies with fallback:** PowerModelsDistribution (optional oracle) — fallback is to
not use it; hand-rolled parser covers IMPED-01 fully.

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Julia stdlib (`Base`, regex via `PCRE`) | 1.12.5 (repo compat floor 1.10) | Parse `.dss` text | No new dependency; the `.dss` grammar needed here is simple line-oriented text, not full OpenDSS semantics |
| `to_pu_impedance` (existing, `src/units/PerUnit.jl:53`) `[VERIFIED: codebase]` | already in repo | Ω → pu conversion at ingestion | Already the framework's single documented SI→pu seam; reuse, don't reinvent |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| CSV.jl 0.10.16 `[VERIFIED: codebase, Project.toml]` | already in `[deps]` | Optional: emit an intermediate CSV of parsed per-segment R/X for human review before committing the Julia `const` table | If the planner wants a reviewable artifact between "raw parse" and "committed const table" |
| DataFrames.jl 1.8.2 `[VERIFIED: codebase, Project.toml]` | already in `[deps]` | Optional: tabulate parsed linecodes/lines for a sanity-check script | Same as above — convenience, not required |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Hand-rolled regex parser | PowerModelsDistribution.jl `ENGINEERING` model parse | PMD gives a battle-tested parser (handles `Redirect`, per-unit inference, transformer/regulator topology) but forces the weakdep+extension-or-throwaway-env machinery IMPED-01 explicitly worries about, for a parsing job this file's actual grammar doesn't need. Use PMD only if the hand-rolled parser turns out to miss an edge case (e.g., a `like=` inheritance clause in a linecode this project doesn't currently use) or as a belt-and-suspenders cross-validation oracle (solve a plain PF on the reduced network, compare against a PMD-parsed run) — never as the primary parse path, per CLAUDE.md's "PMD as oracle only" rule. |
| Regex parsing of `rmatrix=`/`xmatrix=` blocks | A real DSS tokenizer/grammar | Overkill for 12 well-formed, hand-written linecode blocks that have not changed in this file since a 2010 correction (per its own header comment); a tokenizer is justified only if the project later needs to parse a *different*, less-regular feeder file |

**Installation:** No new packages. `Project.toml [deps]` is unchanged by this phase.

**Version verification:** Not applicable — no new runtime package versions introduced.

## Package Legitimacy Audit

No new external packages are introduced by the recommended (hand-rolled parser) path — `Project.toml`
`[deps]` is unchanged. If the planner instead chooses the PMD-oracle path for a secondary
cross-check, it must be added ONLY behind `[weakdeps]`+extension or in a throwaway
`scripts/`-local `Project.toml` (never runtime `[deps]`), and its legitimacy is already documented
in this project's own `CLAUDE.md` (PowerModelsDistribution.jl 0.16.0, sourced from the Julia
General registry `Versions.toml`, HIGH confidence, dated 2026-07-18) — no new audit needed if that
pin is reused verbatim.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|--------------|-----------|-------------|
| (none — no new packages) | — | — | — | — | — | N/A |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
[Public GitHub raw .dss files]
   IEEE123Master.dss  IEEELineCodes.DSS
             |               |
             v               v
   +-------------------------------------------+
   | scripts/reduce_ieee123_impedances.jl       |
   |  1. read/vendor .dss text                  |
   |  2. regex-extract "New Line.*" (from,to,    |
   |     linecode, length) for linecodes 1-12   |
   |  3. regex-extract rmatrix/xmatrix per       |
   |     linecode 1-12 (skip 300s/400/601s/721s) |
   |  4. Fortescue-average -> R1,X1 (Ω/unit-len) |
   |  5. z_seg[Ω] = R1 x Length  (NO conversion) |
   |  6. write committed const table (Ω)         |
   +-------------------------------------------+
             |
             v
   src/data/ieee123.jl :: ieee123_modified()
      - IEEE123_EDGES  (topology, UNCHANGED)
      - IEEE123_BRANCH_RX[(from,to)] -> (R_Ω, X_Ω)  (NEW, replaces the
        two uniform scalars IEEE123_LINE_R/X)
      - to_pu_impedance(R_Ω, IEEE123_BASE) at ingestion (existing helper)
             |
             v
   Feeder{Float64}  -->  assert_radial / assert_magnitudes (existing gates)
             |
             v
   test/fixtures_phase7.jl :: build_ieee123_aggregators (PV/load population)
             |
             v
   solve_welfare (centralized SOCP)  <-->  solve_admm (ADMM)
             |
             v
   NEW: voltage-binding check (min/max solved V vs [0.9,1.1] band)
             |
             v
   Golden / regression comparison (structural + behavioral, see below)
```

### Recommended Project Structure
```
scripts/
├── reduce_ieee123_impedances.jl   # NEW: offline, reproducible parse+reduce (IMPED-01)
├── data/
│   ├── IEEE123Master.dss          # NEW: vendored copy (offline reproducibility)
│   └── IEEELineCodes.DSS          # NEW: vendored copy
src/data/
├── ieee123.jl                     # MODIFIED: IEEE123_LINE_R/X (2 scalars) -> IEEE123_BRANCH_RX (per-segment table)
└── ieee123_impedances.jl          # NEW (recommended split): the committed const Ω table, generated by the script,
                                    #   included from ieee123.jl — keeps the large data block out of the hand-edited file
test/
├── test_ieee123.jl                # MODIFIED/EXTENDED: add voltage-binding assertion (currently absent)
└── test_ieee123_admm.jl           # existing behavioral bounds (iters, welfare, exact_maxgap) re-verified, possibly re-tuned
docs/literate/
└── ieee123_impedances.jl          # NEW (recommended): literate page documenting the reduction, matching the
                                    #   project's existing Literate.jl convention (docs/src/generated/*.md)
```

### Pattern 1: Committed-data-table over live-fetch-at-load-time
**What:** The reduction script runs ONCE (offline, by a human/CI step), and its OUTPUT (a Julia
`const` table of Ω values keyed by original terminal pairs) is committed to `src/data/`. `ieee123.jl`
never fetches or parses `.dss` text at package-load time.
**When to use:** Always, for this phase — matches DrWatson/reproducibility philosophy (pin
generated data, don't regenerate it live) and keeps `src/` free of HTTP/parsing dependencies.
**Example:**
```julia
# src/data/ieee123_impedances.jl (generated by scripts/reduce_ieee123_impedances.jl — DO NOT
# hand-edit; re-run the script and re-commit if the upstream .dss files change)
#
# Keyed by ORIGINAL IEEE-123 terminal pairs (pre-relabel), matching IEEE123_EDGES exactly.
# Values are per-segment SERIES IMPEDANCE IN OHMS (positive-sequence, Fortescue-averaged),
# NOT per-unit — converted once at ingestion in ieee123_modified() via to_pu_impedance.
const IEEE123_BRANCH_RX_OHMS = Dict{Tuple{Int,Int}, Tuple{Float64,Float64}}(
    (149, 1)  => (0.057967 * 0.4, 0.118756 * 0.4),   # LineCode=1, Length=0.4
    (1, 2)    => (0.251742 * 0.175, 0.255208 * 0.175), # LineCode=10, Length=0.175
    # ... 122 entries total, one per IEEE123_EDGES tuple ...
)
```

### Pattern 2: Fortescue-averaging reduction (verified against live data)
**What:** For an `n×n` symmetric line-code matrix (n=1,2,3), positive-sequence self/mutual
impedance is `R1 = mean(diag) - mean(offdiag)`, `X1 = mean(diag) - mean(offdiag)` (same formula
for X). For `n=1` there is no off-diagonal; `R1 = rmatrix[1,1]` directly (no reduction needed).
**When to use:** Any of the 12 linecodes actually referenced by the 123-bus case (1–12); do NOT
apply this to linecodes 300+/400/601+/721+ in the same file — those belong to the co-bundled
13/34/4-node test cases and are never referenced by a `LineCode=` in `IEEE123Master.dss`.
**Example (verified this session against the live file):**
```julia
# linecode.1, nphases=3 (source: IEEELineCodes.DSS lines 7-13, fetched 2026-07-25)
rmatrix = [0.086666667 0.029545455 0.02907197;
           0.029545455 0.088371212 0.029924242;
           0.02907197  0.029924242 0.087405303]
diag_mean    = (0.086666667 + 0.088371212 + 0.087405303) / 3   # = 0.087481061
offdiag_mean = (0.029545455 + 0.02907197  + 0.029924242) / 3   # = 0.029513889
R1 = diag_mean - offdiag_mean   # = 0.057967 Ω/unit-length  <- matches memory pin (0.05797)

xmatrix = [0.204166667 0.095018939 0.072897727;
           0.095018939 0.198522727 0.080227273;
           0.072897727 0.080227273 0.201723485]
diag_mean_x    = (0.204166667 + 0.198522727 + 0.201723485) / 3  # = 0.201470960
offdiag_mean_x = (0.095018939 + 0.072897727 + 0.080227273) / 3  # = 0.082714646
X1 = diag_mean_x - offdiag_mean_x   # = 0.118756 Ω/unit-length  <- matches memory pin (0.11876)
```

### Pattern 3: Ω→pu at ingestion (existing framework rule, reused not reinvented)
**What:** `ieee123.jl` already has a documented rule ("SI→pu ONCE at ingestion") and already applies
it once for `s_head = to_pu_power(IEEE123_HEAD_SMAX_MVA, IEEE123_BASE)`. Apply the exact same
pattern to the new per-segment Ω table.
**Example:**
```julia
# inside ieee123_modified(), replacing the current uniform IEEE123_LINE_R/X assignment:
for (p, c) in IEEE123_EDGES
    is_switch = (p, c) in IEEE123_SWITCH_EDGES
    if is_switch
        r, x = IEEE123_SWITCH_R, IEEE123_SWITCH_X   # near-ideal regulator/switch segments unchanged
    else
        r_Ω, x_Ω = IEEE123_BRANCH_RX_OHMS[(p, c)]
        r, x = to_pu_impedance(r_Ω, IEEE123_BASE), to_pu_impedance(x_Ω, IEEE123_BASE)
    end
    ...
end
```

### Anti-Patterns to Avoid
- **Applying a feet<->miles<->kft conversion factor to the parsed Length values:** OpenDSS's own
  documented default (`Units=none`, unspecified anywhere in this file chain) means "no conversion —
  Length and the linecode matrix already share the same implicit unit." Multiplying by `5280`,
  `1/5280`, `0.001`, or `1000` here is the exact "classic feet-vs-miles trap" the phase brief warns
  about, and would silently corrupt every impedance by 3-4 orders of magnitude.
- **Parsing every `New linecode.*` block in `IEEELineCodes.DSS`:** the file bundles line codes for
  four different IEEE test feeders (4/13/34/123-node). Only linecodes 1–12 are referenced by a
  `LineCode=` in `IEEE123Master.dss`; blindly reducing all 29 wastes effort and risks accidentally
  keying the wrong linecode if numbering ever collides.
- **Regenerating topology from the raw `.dss` file:** the raw file has MORE structure than the
  fixture needs (internal regulator nodes `150r`/`9r`/`25r`/`160r`, a 61s/610 step-down transformer,
  6 closed + 2 visible open switches vs. the fixture's already-collapsed 5 switch edges) — IMPED-02
  requires topology stay untouched; the reduction script's job is to look UP each `IEEE123_EDGES`
  tuple in the raw data, not to re-derive the tree.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Ω → pu conversion | A new ad-hoc division | `to_pu_impedance` (`src/units/PerUnit.jl:53`, already exists) | Already the framework's single documented ingestion seam; a second implementation would be a silent duplicate-of-truth risk |
| Positive-sequence reduction math | A generic symmetrical-component library dependency | The 3-line Fortescue-averaging formula (verified above) | The formula is trivial for balanced-assumption reduction and is already independently verified against the live data in this session; a full symmetrical-component package would be overkill and adds a dependency for ~3 lines of arithmetic |

**Key insight:** This phase's "don't hand-roll" risk is not in avoiding a library — it's in avoiding
an unnecessary NEW dependency (PMD) for a job the existing per-unit ingestion helper and a small
regex parser already cover completely.

## Runtime State Inventory

Not applicable — this is a data-add/data-swap phase (a new committed const table replacing two
scalar consts), not a rename/refactor/migration. No stored external state, live service config, OS
registrations, or secrets are touched. Build artifacts: none beyond the normal Julia precompile
cache, which self-invalidates on `src/` changes as usual.

## Common Pitfalls

### Pitfall 1: The units trap (STATE.md flag) — resolved, but only if the script matches OpenDSS's own no-op default
**What goes wrong:** Assuming `Length=0.4` means "0.4 miles" or "0.4 feet" and applying an explicit
conversion factor before multiplying by the per-unit-length R/X.
**Why it happens:** OpenDSS's `Units=` property genuinely supports `{none|mi|kft|km|m|ft|in|cm}`
with real conversions — so it is reasonable to assume a conversion is needed. But neither
`IEEE123Master.dss` nor `IEEELineCodes.DSS` sets `Units=` anywhere (verified this session by
grepping the live files: `Units=` never appears, matching the master file's own comment at line 43,
"it is recommended that the units= property be used... to avoid confusion" — i.e., the ORIGINAL
authors flag this exact ambiguity as a known gotcha of their own file). Per the official OpenDSS
LineCode documentation (fetched this session): "If not specified, it is assumed that the units
correspond to the length being used in the Line models" — i.e., self-consistent, zero conversion.
**How to avoid:** Multiply `R1[Ω/unit] × Length[unit]` directly, with NO scale factor. For citation
purposes only (not for the math), the implicit unit is very likely "kft" (1000 ft) — the SAME shared
`IEEELineCodes.DSS` file has an explicit inline comment on `linecode.300` (a *different* feeder's
line code, same file): `! ohms per 1000ft`. Cross-checked for plausibility: summing all 127
`Length=` values in the master file gives 39.383 raw units; interpreted as kft that is ≈7.46 miles
of total conductor — a physically plausible total for a feeder of this scale; interpreted as literal
miles it would be ≈39 miles, implausible for a 4.16 kV feeder. `[CITED: opendss.epri.com/LineCode1.html]` for the no-conversion default; `[ASSUMED]` for the specific "kft" label (numerically irrelevant, only affects the citation wording — see Assumptions Log A1).
**Warning signs:** Reduced per-unit impedances landing 3-4 orders of magnitude off from the current
synthetic placeholder (0.005 pu/segment) should immediately raise suspicion of an accidental unit
conversion, since the real and synthetic numbers are expected to be the same order of magnitude
(verified this session: real single-phase-lateral segments compute to ~0.005-0.01 pu, three-phase
trunk segments to ~0.001-0.003 pu on the existing 1 MVA/4.16 kV base — see Code Examples).

### Pitfall 2: Ingesting the wrong linecodes from the shared file
**What goes wrong:** A naive parser that regex-matches every `New linecode.N` block in
`IEEELineCodes.DSS` will pick up linecodes 300-304 (34-bus feeder), 400 (unused 4-bus placeholder,
explicitly commented "not actually referenced"), and 601-607/721-724 (13-bus feeder) alongside the
12 that the 123-bus case actually uses.
**Why it happens:** OpenDSS ships one shared line-codes file across several IEEE test feeders in
the `tshort/OpenDSS` distribution; nothing in the file's syntax flags which blocks are "used" vs.
"unused" for a given feeder — only comments do (`! These line codes are used in the 34-node test
feeder`, etc.), and comments are not something a regex-based extractor should rely on for
correctness.
**How to avoid:** First collect the SET of `LineCode=` values actually referenced by `New Line.*`
statements in `IEEE123Master.dss` (verified this session: exactly `{1,...,12}`), then only parse
`New linecode.{that set}` blocks from `IEEELineCodes.DSS`. Assert the parsed linecode count equals
12 and fail loudly if not — a natural, cheap tripwire.
**Warning signs:** More than 12 distinct linecodes ingested, or any linecode with `nphases` not in
{1,2,3} (a corrupted parse would likely show up as `nphases=0` or a shape mismatch first).

### Pitfall 3: Topology drift between the raw feeder and the existing fixture
**What goes wrong:** Assuming the reduction script can walk the raw `.dss` topology directly and
that it will line up 1:1 with `IEEE123_EDGES`.
**Why it happens:** The raw OpenDSS feeder has MORE nodes than the existing 123-bus/122-edge
fixture: internal regulator secondary nodes (`150r`, `9r`, `25r`, `160r` — confirmed this session by
fetching `IEEE123Regulators.DSS`, all near-zero-impedance `XHL=.001`/`.01` transformers), the
61s/610 step-down transformer branch (out of scope per REQUIREMENTS, a 480V LV loop), and switch
segments that the fixture has ALREADY collapsed (e.g., the real chain `150 --[reg1a]--> 150r
--[Sw1]--> 149` is represented in the existing fixture as one direct edge `(150, 149)` tagged as a
switch-class near-ideal segment). By contrast, several other "switch" edges in the fixture
(`(13,152)`, `(18,135)`, `(60,160)`, `(97,197)`) correspond to a DIRECT `New Line.SwN` in the raw
data with no intermediate node — no collapsing needed there.
**How to avoid:** Do not attempt to re-derive topology. For each of the 122 tuples already in
`IEEE123_EDGES`, look up the matching `New Line.*` statement by `(Bus1, Bus2)` (in either order) in
the raw master file and pull its `LineCode=`/`Length=`. For the 5 tuples in `IEEE123_SWITCH_EDGES`,
confirm the fixture's existing near-ideal-impedance treatment is still appropriate (regulators are
explicitly out of scope for active modeling, per REQUIREMENTS) rather than trying to look up a
real R/X for them — they should keep `IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` (or an explicitly
near-zero real value if the planner wants exact fidelity there too).
**Warning signs:** A lookup failure (an `IEEE123_EDGES` tuple with no matching `New Line.*` in
either direction) — this must throw loudly at script run time, not silently fall back to a default.

### Pitfall 4: Assuming voltage-binding transfers automatically
**What goes wrong:** Shipping the real-impedance swap without re-running the full ADMM/centralized
solve and checking whether the solved voltages still approach the `[0.9, 1.1]` band, because the
per-segment magnitudes "look similar" to the synthetic placeholder.
**Why it happens:** Per-branch magnitudes are indeed the same rough order (verified this session:
real segments compute to ~0.001–0.01 pu vs. the uniform synthetic 0.005 pu), which is reassuring but
NOT a proof — voltage drop along a radial feeder is a CUMULATIVE, path-dependent sum, and the real
data's R/X distribution across the tree (concentrated on long single-phase laterals with higher
per-unit-length R1/X1, near-zero on regulator/switch segments) differs qualitatively from the
current uniform-scalar synthetic assignment. No existing test currently asserts voltage-binding
numerically at all (verified this session: `test_ieee123.jl`/`test_ieee123_admm.jl` check
magnitude sanity, radial structure, and ADMM-vs-centralized cross-validation, but never assert that
any solved voltage actually reaches within some tolerance of 0.9 or 1.1).
**How to avoid:** Add an explicit new test/assertion (Wave 0 gap, see Validation Architecture) that
reports `min/max` solved per-unit voltage across all hours/buses after the real-data swap, and
compares against the `[0.9, 1.1]` band with an explicit "how close" margin — not just "did it
solve." If it is not binding, re-tune `LOAD_SCALE_IEEE123`/`PV_SCALE_IEEE123`/`DEV_SCALE_IEEE123`
in `test/fixtures_phase7.jl` (the existing, correct seam for this — do not touch impedances again
to "fix" a population-scale problem).
**Warning signs:** Solved voltages that stay comfortably inside `[0.95, 1.05]` at every hour/bus —
the case would then be exercising the SOC cone/voltage machinery only weakly, undermining the
phase's own stated purpose ("the case remains meaningful... voltage-binding").

## Code Examples

### Regex parse of a `New Line.*` statement (verified pattern, matches all 126 lines in the file)
```julia
# Source: manual verification against IEEE123Master.dss fetched 2026-07-25
# e.g. "New Line.L115            Bus1=149        Bus2=1          LineCode=1    Length=0.4"
line_re = r"New\s+Line\.(\S+)\s+.*?Bus1=(\S+?)(?:\.\S+)?\s+Bus2=(\S+?)(?:\.\S+)?\s+LineCode=(\d+)\s+Length=([\d.]+)"i
```
Note the `(?:\.\S+)?` non-capturing group strips phase suffixes like `.1.2.3` or `.2` from bus
names (e.g. `Bus1=1.2` for a single-phase lateral must resolve to bus `1`, not `1.2`).

### Regex parse of an `rmatrix`/`xmatrix` block (verified pattern against linecode.1/7/9)
```julia
# 3-phase (bracket form): rmatrix = [0.086.. | 0.0295.. 0.0883.. | 0.0290.. 0.0299.. 0.0874..]
# 1-phase (paren form, no pipes): rmatrix = (0.251742424)
# Both forms appear in the live file (bracket form for nphases=2,3; paren form for nphases=1),
# so the parser must handle both delimiters and both bracket types.
```

### Ω→pu at ingestion, reusing the existing helper (`src/units/PerUnit.jl:53`)
```julia
to_pu_impedance(z_Ω, b::PerUnitBase) = z_Ω / Z_base(b)   # existing, unmodified
# Z_base(IEEE123_BASE) = 4.16^2 / 1.0 = 17.3056 Ω
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `IEEE123_LINE_R = 0.005`, `IEEE123_LINE_X = 0.0025` (2 scalars, uniform across all 117 non-switch branches) | `IEEE123_BRANCH_RX_OHMS::Dict{Tuple{Int,Int},Tuple{Float64,Float64}}` (122-entry per-segment table, keyed by original terminal pairs, in Ω) | This phase (17) | Every non-switch branch gets its own citable, real R/X instead of one hand-picked representative value; the DATA PROVENANCE note at the top of `ieee123.jl` (lines 13-32) documenting "representative, not thesis-verbatim" values is superseded for these two constants specifically (the topology/relabel/switch-near-ideal documentation above/below it is UNCHANGED) |

**Deprecated/outdated:** The `IEEE123_LINE_R`/`IEEE123_LINE_X` module-level scalar constants become
dead code once the per-segment table lands; remove them (or keep only as a documented historical
comment) rather than leaving two parallel, inconsistent impedance sources in the same file.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The implicit length unit for linecodes 1-12 is specifically "kft" (1000 ft), not some other consistent unit | Common Pitfalls > Pitfall 1 | None numerically (no conversion is applied either way — this only affects how the committed data's doc-comment cites the unit). Purely a documentation/citation-wording risk, not a correctness risk. |
| A2 | The 5 edges in `IEEE123_SWITCH_EDGES` should keep their existing near-ideal synthetic impedance rather than receive a "real" near-zero value from the regulator/switch definitions | Common Pitfalls > Pitfall 3 | Low — regulators/switches are explicitly out of scope for active modeling per REQUIREMENTS ("approximated/absorbed... not simulated"); keeping the existing near-ideal constants is the conservative, already-reviewed choice. If wrong, a planner task would just need to source real switch-resistance values (`r1=1e-3` is actually given directly in the raw `.dss` for Sw1-Sw8!) instead. |
| A3 | A hand-rolled regex parser is sufficient and preferable to PowerModelsDistribution for this phase's narrow parsing need | Standard Stack > Alternatives Considered | Medium — if the planner/user prefers the PMD-oracle path (e.g., for its independent-parser cross-validation value, or because the phase's own success criterion wording anticipated PMD), the weakdep+extension-or-throwaway-env machinery described in the phase brief becomes necessary again. This is a scope/approach decision, not a factual error — flag for discuss-phase or planner confirmation. |
| A4 | Real per-segment impedances will preserve (or come close enough to) voltage-binding without requiring a PV/aggregator re-tune | Common Pitfalls > Pitfall 4 | Medium-High — this is exactly the STATE.md-flagged open question; genuinely unverified without running the actual solve. The phase MUST budget time for a possible re-tune per IMPED-03's own wording ("re-tuned and documented if required"). |

## Open Questions

1. **Does the planner want the PMD-oracle path kept as an explicit secondary validation step, or dropped entirely?**
   - What we know: the phase brief's known-data-source section explicitly named PMD-as-oracle as
     "the cleanest path"; this research found a simpler hand-rolled path sidesteps that need entirely.
   - What's unclear: whether the user/planner still wants a PMD cross-check for extra confidence
     (e.g., solving a plain OPF on the reduced network in PMD and comparing voltage/loss figures
     against the framework's own solve), given CLAUDE.md's "PMD as oracle only" allowance.
   - Recommendation: default to hand-rolled-only (zero new deps) for IMPED-01; leave a PMD
     cross-check as an optional, separately-scoped stretch task the planner can include or defer.

2. **Does IMPED-03's voltage-binding check need to be a new automated `@testitem`, or is a documented one-time diagnostic (script output in a literate doc page) sufficient?**
   - What we know: no existing test currently asserts voltage-binding numerically at all (verified
     this session); the phase's success criterion says "verified," not necessarily "automated
     forever."
   - What's unclear: whether nyquist_validation policy (enabled per `.planning/config.json`) wants
     this as a standing regression test or a one-time documented finding.
   - Recommendation: add it as a standing `@testitem` (cheap to keep, catches future regressions if
     the reduction script is ever re-run against updated upstream data) — see Validation Architecture.

3. **Should the 12 four-tie-switch claim in the current `ieee123.jl` docstring ("54-94, 151-300, 250-251, 450-451") be reconciled against the raw file, which (in the portion fetched this session) shows only 2 visible open switches (`Sw7`: 151-300_OPEN, `Sw8`: 54-94_OPEN)?**
   - What we know: `IEEE123Regulators.DSS` and `IEEE123Loads.DSS` were also fetched but not
     exhaustively cross-checked for additional tie-switch definitions; `250` and `450` both appear
     as ordinary (non-switch) `New Line.*` endpoints in the master file fetched this session.
   - What's unclear: whether `250-251`/`450-451` are tie switches defined elsewhere (e.g., a variant
     of the master file, or simply a documentation inaccuracy already present pre-Phase-17) — this
     does not block Phase 17 (topology is explicitly out of scope for this phase; only impedances
     change) but is worth a one-line note-or-fix if the planner spots it during the lookup step in
     Pitfall 3.
   - Recommendation: not a Phase 17 blocker (topology untouched); flag for the implementer to note
     if the lookup step in Pitfall 3 surfaces a genuine discrepancy, but do not spend phase budget
     re-deriving topology to resolve it.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | TestItems.jl 1.0.0 + TestItemRunner.jl 1.1.5 (already in `test/Project.toml`) |
| Config file | `test/runtests.jl` (`@run_package_tests`, discovers all `@testitem`s under `test/` and `src/`) |
| Quick run command | `julia --project=test -e 'using TestItemRunner; @run_package_tests filter=ti->occursin("ieee123", ti.name)'` |
| Full suite command | `julia --project=test test/runtests.jl` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| IMPED-01 | Parse+reduce script reproduces the pinned linecode.1 sanity value (R1≈0.05797, X1≈0.11876) | unit (script self-check) | `julia --project scripts/reduce_ieee123_impedances.jl --verify` | ❌ Wave 0 (new script) |
| IMPED-01 | Only 12 linecodes ingested (not 29) | unit (script self-check) | same script, assert `length(linecodes) == 12` | ❌ Wave 0 |
| IMPED-02 | `ieee123_modified()` builds without error using the new per-segment table; topology unchanged (`IEEE123_EDGES` untouched) | unit | `julia --project=test -e 'using TestItemRunner; @run_package_tests filter=ti->occursin("ieee123", ti.name)&&!occursin("crossval",ti.name)'` | ✅ `test/test_ieee123.jl` exists, extend it |
| IMPED-02 | Every branch r/x strictly positive, `0 < r,x < 5` pu (existing tripwire, re-verified against real data) | unit | same as above (existing assertion in `test_ieee123.jl`, unmodified) | ✅ exists |
| IMPED-03 | Solved voltages approach/hit the `[0.9,1.1]` band (NEW numeric check, currently absent) | integration | new `@testitem` in `test_ieee123_admm.jl` or `test_acceptance.jl`, asserting `min(V) <= 0.92` or similar margin, not just "solves" | ❌ Wave 0 gap — new assertion needed |
| IMPED-03 | ADMM still converges within the existing behavioral bounds (`iters<300`, `iters<=100`, welfare `isapprox rtol=1e-4`, `exact_maxgap<1e-3`) after the impedance swap | integration | `julia --project=test -e '... filter=ti->occursin("crossval",ti.name)'` | ✅ exists (`test_ieee123_admm.jl`, `test_acceptance.jl`), re-run and re-tune bounds if they break |
| IMPED-03 | If voltage-binding does not transfer, `LOAD_SCALE_IEEE123`/`PV_SCALE_IEEE123`/`DEV_SCALE_IEEE123` re-tuned and documented | manual-only (design decision), verified by the automated check above | — | — |

### Sampling Rate
- **Per task commit:** `julia --project=test -e 'using TestItemRunner; @run_package_tests filter=ti->occursin("ieee123", ti.name)'` (fast — excludes the rest of the ~2276-test suite)
- **Per wave merge:** `julia --project=test test/runtests.jl` (full suite — the IEEE-123 fixture is
  shared by `test_dso.jl`, `test_admm_adaptive.jl`, and `test_acceptance.jl`, so a full run is
  needed to catch any downstream regression from the impedance swap)
- **Phase gate:** Full suite green before `/gsd:verify-work`, PLUS the new voltage-binding assertion
  passing with a documented margin (not just "not erroring")

### Wave 0 Gaps
- [ ] `scripts/reduce_ieee123_impedances.jl` — does not exist yet; must include its own
      self-verification (linecode.1 sanity pin) as a script-level assertion, not just a test file
- [ ] New voltage-binding `@testitem` — no existing test asserts this numerically at all
- [ ] `src/data/ieee123_impedances.jl` (or equivalent const table) — does not exist yet; generated
      output of the reduction script
- [ ] Literate doc page for the reduction (recommended, matches `docs/src/generated/*` convention;
      no `ieee123`-specific page exists today)

## Security Domain

Not applicable in the ASVS sense — this phase parses public, static text files and performs
deterministic arithmetic; there is no authentication, session, network-facing input validation, or
cryptography surface introduced. The one relevant control is data-integrity/provenance, not
security: pin the exact commit/URL the `.dss` files were fetched from (recommended: vendor the raw
files under `scripts/data/` with a comment noting the fetch URL and date, so IMPED-01's "offline,
reproducible" requirement holds even if the upstream GitHub mirror ever changes or disappears).

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Upstream `.dss` source disappears or changes silently, breaking "reproducible" | Tampering (of the data-provenance chain, not a security exploit) | Vendor a committed copy of both `.dss` files at their fetched-2026-07-25 content, rather than re-fetching live at every run |

## Sources

### Primary (HIGH confidence)
- `https://raw.githubusercontent.com/tshort/OpenDSS/master/Distrib/IEEETestCases/123Bus/IEEE123Master.dss` — fetched live this session (HTTP 200), full content read (221 lines)
- `https://raw.githubusercontent.com/tshort/OpenDSS/master/Distrib/IEEETestCases/123Bus/IEEELineCodes.DSS` — fetched live this session (HTTP 200), full content read (213 lines) — **exact case required**, `IEEELineCodes.dss` (lowercase ext) returned HTTP 404
- `https://raw.githubusercontent.com/tshort/OpenDSS/master/Distrib/IEEETestCases/123Bus/IEEE123Regulators.DSS` — fetched live this session (HTTP 200)
- `https://raw.githubusercontent.com/tshort/OpenDSS/master/Distrib/IEEETestCases/123Bus/IEEE123Loads.DSS` — fetched live this session (HTTP 200)
- `/home/pedro/programming/TSO-DSO/src/data/ieee123.jl` — read in full this session (447 lines)
- `/home/pedro/programming/TSO-DSO/src/units/PerUnit.jl` — read in full this session (150 lines)
- `/home/pedro/programming/TSO-DSO/test/test_ieee123.jl`, `test/test_ieee123_admm.jl`, `test/fixtures_phase7.jl`, `test/test_acceptance.jl` — read this session
- `.planning/STATE.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` — read this session

### Secondary (MEDIUM confidence)
- `https://opendss.epri.com/LineCode1.html` (official OpenDSS documentation, fetched this session) — LineCode `Units=` default-behavior quote
- CLAUDE.md's own pre-existing `PowerModelsDistribution 0.16.0` version pin, sourced from the Julia
  General registry `Versions.toml` on 2026-07-18 (reused verbatim if the PMD-oracle path is chosen)

### Tertiary (LOW confidence)
- WebSearch summary claiming "IEEE 123 lengths most likely represent miles" — **contradicted** by
  this session's own live-file evidence (the `linecode.300` inline "ohms per 1000ft" comment plus
  the total-conductor-length plausibility check both point to kft, not miles); not used in the final
  recommendation. Included here only to document that the WebSearch surface-level answer was
  checked and rejected in favor of live-file verification.

## Metadata

**Confidence breakdown:**
- Data reachability + parsing grammar: HIGH — verified by actually fetching and reading the live files this session, not by documentation alone
- Units-trap resolution: HIGH on the "no conversion needed" mechanics (cited official docs + verified no `Units=` anywhere in the file); MEDIUM on the specific "kft" citation label (a plausibility argument, not a certainty — see Assumption A1)
- Fortescue reduction formula: HIGH — independently reproduced the memory-pinned sanity values from the live matrices
- Voltage-binding transfer (IMPED-03): MEDIUM — genuinely unverified without an actual solve; this is the correct, honest status per STATE.md's own flag, not a gap in this research
- Standard stack / don't-hand-roll (avoid PMD): MEDIUM-HIGH — a reasoned recommendation grounded in the actual file's simplicity, not a hard fact; flagged in Assumptions Log A3 for confirmation

**Research date:** 2026-07-25
**Valid until:** ~90 days (static, public, unchanging upstream data; re-check only if the
`tshort/OpenDSS` repository restructures or the file content changes)

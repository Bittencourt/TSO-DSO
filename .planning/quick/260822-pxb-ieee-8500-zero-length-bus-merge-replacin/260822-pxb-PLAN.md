---
quick_id: 260822-pxb
description: Replace impedance fabrication with a principled topological bus-merge reduction for degenerate IEEE-8500 segments, then re-measure SOCP exactness before/after
date: 2026-08-22
mode: quick
---

# Quick Task 260822-pxb: Bus-merge the IEEE-8500 fixture's degenerate zero-length segments (replacing impedance fabrication)

## Why

Quick task 260822-oi7's `--gap-report` diagnostic found the SAME real vendored MV branch,
`"L2674047"->"M1142828"` (`r_pu ≈ 1.5423e-7`, `r_ohm = 4.7967e-5 Ω`), dominates the SOCP
cone-residual worst-offender list on ALL THREE measured IEEE-8500 points, at every density/T/tol
tried (`density=0.1,T=10,tol=1e-6`: gap `0.03250`; `ieee8500-mv,density=0.1,T=24,tol=1e-8`: gap
`0.000578`; `ieee8500-mv,density=0.25,T=24,tol=1e-8`: gap `0.003773`) — the identical STRUCTURAL
fingerprint Item 1 (already resolved) found for the substation busbar-tie connector, but a
DIFFERENT, uncatalogued branch. Direct inspection of the vendored source
(`scripts/data/ieee8500/Lines.dss:749`) shows this is NOT a parsing bug: `New Line.LN5473436-1
bus1=M1142828 bus2=L2674047 length=0.0003048 units=km Linecode=3PH_H-397_...` — `length=0.0003048
km` is EXACTLY 1.000 ft, and the linecode's real `r1=0.157372 Ω/km` gives `r = 4.7967e-5 Ω`,
matching the committed table to 4 significant figures. `LN5473436-1`/`LN5473436-2` are a SPLIT of
one original line, and the inserted midpoint bus `L2674047` is where service transformer
`T5260514C` attaches (`LoadXfmrCodes.dss:1061`). Two buses 1 FOOT apart are electrically the SAME
node — the correct fix is a topological bus MERGE (collapse the pair, reattach the transformer),
not fabricating an impedance value the way `HVMV_Sub_connector`'s prior D-13 override did.

This task (a) implements that merge for BOTH of the fixture's genuinely degenerate 1-ft real-line
splits, (b) re-evaluates whether the EXISTING `HVMV_Sub_connector` D-13 impedance override (plan
25-05/25-07, `deferred-items.md` item 1) should likewise be replaced by a merge (it is a literal
substation busbar tie — a merge is strictly more faithful than inventing an impedance for a
non-physical element), and (c) re-measures SOCP exactness honestly, reporting whatever the result
is — including a null result if exactness does not improve.

**Explicitly NOT in scope** (per the orchestrator's verified findings — do not expand): the 53
`length=0.001 km` records with inline `r1=1.0/x1=1.0` (artificial capacitor-jumper/stub markers,
NOT genuine short real conductors) stay untouched, "next tier"; the 5 other short-but-non-1ft
real segments in the length histogram (`0.000259836`, `0.000383926`, `0.000560638`,
`0.000658611`, `0.000731906`, `0.000842188` km) stay untouched — no evidence ties them to the
measured exactness failure, and Item 5's OTHER offenders (`"M1069310"->"M1069311"`,
`"M1108489"->"P829798"`) are NOT addressed here either (record as still-open "next tier" in
`deferred-items.md`, do not silently fold them in without evidence). No tolerance/gate default in
`src/models/exactness.jl` changes. No T=24 headline (`ieee8500`) solve. One Julia process at a
time (shared 15 GiB machine).

## Context

- `scripts/reduce_ieee8500_impedances.jl` — THE file to change (Tasks 1-2). Read the existing
  `reshape_near_zero_mv_edges!`/`MV_NEAR_ZERO_R_THRESHOLD_OHM`/`D13_NEAR_IDEAL_*` mechanism
  (~lines 71-125, 305-345) before touching it — Task 2 converts its VALUE-REASSIGNMENT semantics
  to a MERGE, reusing Task 1's new machinery, not writing a second one.
- `scripts/data/ieee8500/Lines.dss` — vendored source. Key records already located:
  - Line 749: `New Line.LN5473436-1 bus1=M1142828 bus2=L2674047 length=0.0003048 units=km
    Linecode=3PH_H-397_ACSR397_ACSR397_ACSR2/0_ACSR` (pair 1, the 1-ft split; dominant offender)
  - Line 1672: `New Line.LN5473436-2 bus1=L2674047 bus2=L2692655 ...` (the long continuation —
    NOT touched, stays attached to the survivor)
  - Line 1949: `New Line.LN6291244-1 bus1=L3160865 bus2=M1142828 ...` (M1142828's OTHER real
    edge — must be renamed to `L3160865 -> L2674047` after the merge)
  - Line 1169: `New Line.LN6259981-1 bus1=M1009834.2 bus2=L3178969.2 length=0.0003048 units=km
    Linecode=1PH-x4_ACSRx4_ACSR` (pair 2, the SECOND and ONLY OTHER 1-ft split in the whole file
    — `grep -c "length=0.0003048" Lines.dss` = 2, confirmed)
  - Line 626: `New Line.LN6259981-2 bus1=L3178969.2 bus2=L2729401.2 ...` (long continuation)
  - Line 1550: `New Line.LN5472344-1 bus1=M1009832.2 bus2=M1009834.2 ...` (M1009834's OTHER real
    edge — renamed to `M1009832 -> L3178969` after the merge)
  - Line 4: `New Line.HVMV_Sub_connector bus1=_HVMV_Sub_LSB bus2=HVMV_Sub_48332 length=0.001
    units=km r1=0.001 x1=0.01` (the connector, Task 2 — an `inline_recs` record, r_ohm=1e-6,
    ALREADY caught by the existing `MV_NEAR_ZERO_R_THRESHOLD_OHM = 1e-5` gate)
  - Line 499: `New Line.LN5710794-3 bus1=HVMV_Sub_48332 bus2=D5710794-3_INT ...` (the connector's
    downstream continuation)
- `scripts/data/ieee8500/LoadXfmrCodes.dss` — `line 920: New Transformer.T5355596B
  XfmrCode=CT15 buses=[L3178969.2 X3178969B.1.0 X3178969B.0.2]`; `line 1061: New
  Transformer.T5260514C ... buses=[L2674047.3 X2674047C.1.0 X2674047C.0.2]`. IMPORTANT: both
  transformers' `mv_base` ALREADY equals the bus this plan's degree rule picks as survivor
  (`L2674047`, `L3178969`) — no `xfmr_instances` rename is actually needed for pairs 1/2, but
  implement the rename generically anyway (Task 1 action item 5c) since it is required for
  correctness in general and costs nothing when it is a no-op.
- `scripts/data/ieee8500/Transformers.dss` — the head chain: `New Transformer.HVMV_Sub ...
  buses=(HVMV_Sub_HSB, regxfmr_HVMV_Sub_LSB...)` (the ROOT-touching head edge, in
  `IEEE8500_REGULATOR_EDGES` via `parse_transformer_bus_pairs`) then 3×
  `New Transformer.FEEDER_REG{A,B,C} buses=(regxfmr_HVMV_Sub_LSB.N, _HVMV_Sub_LSB.N)` (the
  regulator bank, ALSO in `IEEE8500_REGULATOR_EDGES`, collapsing the 3 phase-records to 1 logical
  edge) then the connector (`_HVMV_Sub_LSB -> HVMV_Sub_48332`) then the rest of the MV feeder.
  **Neither `IEEE8500_ROOT_BUS` ("HVMV_Sub_HSB") nor `regxfmr_HVMV_Sub_LSB` is touched by the
  connector merge** — the substation-transformer head edge (the one `is_head(a,b) = a ==
  IEEE8500_ROOT_BUS || b == IEEE8500_ROOT_BUS` in `src/data/ieee8500.jl` flags for the 55 pu head
  `smax`) is untouched by this task; Task 2 still explicitly re-verifies this rather than assuming
  it (per the constraint's own instruction).
- `src/data/ieee8500.jl` — fixture builders. `include("ieee8500_impedances.jl")` (line 50);
  `IEEE8500_ROOT_BUS = "HVMV_Sub_HSB"` (line 92); `ieee8500_relabel_map`/`ieee8500_mv_relabel_map`
  (lines 130-155, 272-292) union bus names from the generated tables dynamically — NO code change
  needed there, only the file-header doc comment (lines 8-15) stating "4,875"/"2,521" buses needs
  correcting once the new counts are measured (Task 3).
- `src/data/Feeder.jl` — `Feeder(buses, branches, root)` runs `assert_radial` + `assert_magnitudes`
  in its inner constructor; simply calling `TSODSO.ieee8500_modified()` /
  `TSODSO.ieee8500_mv_modified()` after regeneration is a full structural sanity check.
- `test/test_ieee8500.jl` — audited: every hard-equality count assertion in this file
  (`length(cap)==4`, `length(loads)==1177`) is scoped to LV/capacitor buses (`SX*`, `R*`-prefixed
  names) untouched by this task's 3 MV-level merges; the fixture-count assertions
  (`length(branches)==N-1`, single root, contiguous ids) are invariants, not literals — expected
  to require NO changes, but Task 3 must actually run the file to confirm, not assume.
- `test/test_benchmark_ieee8500.jl` — the D-16 goldens `model_vars=137594`/`model_cons=275118` on
  the `ieee8500-mv --quick` point WILL move (MV-only bus count drops from 2521 to a new, smaller
  count) — Task 3 must re-measure and re-pin both, following the file's own documented
  STABILITY-BEFORE-GOLDEN convention (run `--quick` enough times to confirm stability before
  pinning, exactly as the file's Test 1 already does for a fresh pair of runs).
- `src/models/exactness.jl` — `socp_gap_report` (the diagnostic, untouched — read-only reference)
  returns `(b, from, to, r_pu, x_pu, l, v_from, P, Q, t, gap, ratio, reverse_flow, loading)` rows;
  `scripts/benchmark_ieee8500.jl`'s `run_gap_report_mode` (~line 873) joins bus names via
  `ieee8500_relabel_map`/`ieee8500_mv_relabel_map` and appends to
  `results/ieee8500_benchmark/socp_gap_report.csv`, UPSERTING by a `point` string key — re-running
  the SAME 3 points will OVERWRITE their pre-merge rows in place (Task 3 action item 1 addresses
  preserving the pre-merge values before this happens).
- `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` — Item 1 (RESOLVED
  2026-08-21, the D-13 reshape) needs a superseding entry (Task 2); Item 5 (the still-OPEN
  fingerprint investigation that led to this task) should be updated with this task's outcome
  (Task 3).
- `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md` — "Deviation from
  verbatim transcription" section documents the connector's PRIOR (D-13 reshape) treatment; needs
  updating to describe the NEW (merge) treatment, plus the 2 new length-based merges (Task 1/2),
  plus the non-comparability note for pre-existing CSVs (Task 3).
- The pre-merge baseline (already measured, cite directly — do not re-derive):
  `results/ieee8500_benchmark/socp_gap_report.csv` rows for the 3 points below, `point` column
  values `ieee8500|density=0.1|T=10|tol=1.0e-6`, `ieee8500-mv|density=0.1|T=24|tol=1.0e-8` (implied
  by Item 5's table, not directly re-read here — Task 3 must re-derive its exact pre-merge row
  from `git show HEAD:...` since only the `ieee8500` T=10 row was directly inspected this
  session), `ieee8500-mv|density=0.25|T=24|tol=1.0e-8`:

  | Point | termination_status | top-1 gap (BEFORE) | dominant branch (BEFORE) |
  |---|---|---|---|
  | `ieee8500,density=0.1,T=10,tol=1e-6` | OPTIMAL | `0.0325015512` | `L2674047`(144)`->M1142828`(2047) |
  | `ieee8500-mv,density=0.1,T=24,tol=1e-8` | OPTIMAL | `0.0005781162` | same fingerprint per Item 5 (re-verify exact from/to via `git show`) |
  | `ieee8500-mv,density=0.25,T=24,tol=1e-8` | OPTIMAL | `0.0037728310` | same fingerprint per Item 5 (re-verify exact from/to via `git show`) |

## Tasks

### Task 1 — implement the generic zero-length bus-merge mechanism, apply to the 2 real 1-ft splits

- **files:** `scripts/reduce_ieee8500_impedances.jl`
- **action:**
  1. Add a length-based degenerate-segment detector operating on `parse_mv_lines`'s
     `linecode_recs::Vector{MVLinecodeRef}` return (BEFORE any per-km linecode impedance
     resolution — length is the cleanest key here because it needs no linecode lookup and
     `0.0003048` km is an EXACT, suspicious imperial round-trip (1.000 ft) that fingerprints an
     artificial bus-split marker, unlike the file's other 5 short-but-non-round real lengths):
     filter for `isapprox(length_km, 0.0003048; atol = 1e-9)`, collect `canonical_pair(bus1_base,
     bus2_base)` for each match, and throw a loud `ArgumentError` unless EXACTLY 2 match —
     mirroring `reshape_near_zero_mv_edges!`'s existing assert-exactly-1 pattern, with a message
     instructing a future maintainer not to silently widen the set on a data refresh. Name the
     threshold `MV_ZERO_LENGTH_KM = 0.0003048` with a comment stating why length (not r_ohm) is
     the key for this class, and explicitly listing the 5 other short real lengths this threshold
     deliberately does NOT catch (out of scope, no evidence, "next tier").
  2. Reorder `main()`'s parse sequence so `parse_mv_lines` (MV lines/switches), `parse_xfmr_codes`
     + `parse_xfmr_instances` (`LoadXfmrCodes.dss`), and `parse_transformer_bus_pairs` on BOTH
     `Regulators.dss` and `Transformers.dss` (giving `reg_pairs`) all run BEFORE any degenerate-pair
     resolution. Build the LOGICAL (phase-deduplicated) regulator/switch edge set via the existing
     `build_regulator_edges(reg_pairs, switch_pairs)` at this earlier point too (this Set — not the
     raw 3-per-bank phase records — is what degree counting in step 3 must use, or a 3-phase
     regulator bank will be counted 3x relative to an ordinary single MV line record).
  3. Implement a bus-degree calculator over the fully-parsed-but-not-yet-merged topology: a bus
     name's degree is the count of DISTINCT logical connections touching it — canonical MV
     bus-pairs from the COMBINED `linecode_recs` + `inline_recs` (each already exactly one raw
     record per physical line at this fixture's phase-collapse convention), membership count in
     the logical regulator/switch edge Set from step 2, and the count of `xfmr_instances` whose
     `mv_base` equals it (each already one raw record per physical transformer). Do NOT count raw
     un-deduplicated phase records for regulator/switch banks.
  4. Implement a generic merge-pair resolver taking a `Vector{Tuple{String,String}}` of canonical
     degenerate pairs: assert the pairs are pairwise disjoint (no bus name appears in more than
     one pair — throw loudly otherwise; chained/transitive merges are explicitly unhandled and out
     of scope for this task). For each pair, compute each endpoint's degree MINUS 1 (excluding the
     pair's own edge/attachment contribution to itself), and select the SURVIVOR as the endpoint
     with the strictly greater remaining degree; on an exact tie, the LEXICOGRAPHICALLY SMALLER
     bus name survives (Julia's default `String` ordering) — fully deterministic, no bus-name
     special-casing. Return a `Dict{String,String}` merge map (casualty => survivor). Expected
     result for this task's 2 pairs (verify your implementation reproduces this, do not hardcode
     it): `M1142828` (degree 1: only `LN6291244-1`) merges into `L2674047` (degree 2:
     `LN5473436-2` + the `T5260514C` transformer attachment); `M1009834` (degree 1: only
     `LN5472344-1`) merges into `L3178969` (degree 2: `LN6259981-2` + the `T5355596B`
     transformer attachment).
  5. Implement a rename-and-drop step applying the merge map: (a) DROP the 2 degenerate
     `linecode_recs` entries entirely (they never reach the impedance-computation loop — this is
     how the edges disappear, never via a self-loop); (b) rename `bus1_base`/`bus2_base` on every
     REMAINING `linecode_recs`/`inline_recs`/`switch_pairs`/`disabled_switch_pairs` entry through
     the merge map (no-op for names absent from the map); (c) rename `mv_base` only (never
     `lv_base`) on every `xfmr_instances` entry; (d) rename both elements of every entry in the
     logical regulator/switch edge Set from step 2. After renaming, assert NO entry anywhere has
     `bus1_base == bus2_base` (or is a self-referential pair in the Set) — throw loudly if one
     appears (would indicate an undetected pre-existing parallel path this task's disjointness
     analysis did not anticipate; never silently drop it).
  6. Apply this machinery to JUST the 2 length-class pairs. Leave the connector's existing
     `reshape_near_zero_mv_edges!` r_ohm-based value-reassignment COMPLETELY UNTOUCHED for this
     task (Task 2 owns converting it). Continue the existing pipeline (impedance resolution of the
     surviving `linecode_recs`, `mv_edges_raw` assembly, `reshape_near_zero_mv_edges!`,
     `dedupe_edges`, `assert_no_self_loops`) unchanged in shape, operating on the
     renamed/filtered inputs.
  7. Update `emit_output`'s generated-file header comment block to document the 2 new bus-merges:
     which bus pairs, which survived and why (degree rule), and the physical justification ("two
     buses electrically the same node, 1 ft apart, one hosting a real service-transformer
     attachment — merging is more faithful than assigning any impedance value"). Leave the
     EXISTING D-13/connector paragraph in place for now (Task 2 rewrites it).
  8. Add a `println` summary mirroring `reshape_near_zero_mv_edges!`'s existing pattern: "Bus
     merge (length-class): N pairs merged: [(casualty=>survivor), ...]".
- **verify:**
  - `julia scripts/reduce_ieee8500_impedances.jl --verify` still passes (CT5 sanity check
    untouched).
  - `julia scripts/reduce_ieee8500_impedances.jl` (regenerate) prints the new merge summary
    showing exactly the 2 expected pairs and the predicted survivors from action item 4.
  - `julia --project=. -e 'using TSODSO; f=TSODSO.ieee8500_modified(); println(length(f.buses)); g=TSODSO.ieee8500_mv_modified(); println(length(g.buses))'`
    constructs both fixtures without throwing (exercises `assert_radial`+`assert_magnitudes`) and
    prints bus counts; expected `4873` (headline, `4875-2`) and `2519` (MV-only, `2521-2`) — if
    either differs, STOP and investigate before proceeding to Task 2 (a discrepancy means the
    disjointness or degree-rule analysis missed something).
  - `grep -c "M1142828\|M1009834" src/data/ieee8500_impedances.jl` returns `0` (the casualty names
    no longer appear anywhere in the regenerated table).
- **done:** the 2 real 1-ft splits are merged (not value-reassigned), both fixtures still
  construct, bus counts drop by exactly 2 each, and the casualty bus names are gone from the
  generated table.

### Task 2 — evaluate and apply the connector's merge-vs-override decision

- **files:** `scripts/reduce_ieee8500_impedances.jl`, `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md`, `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md`
- **action:**
  1. Confirm `HVMV_Sub_connector` (`bus1=_HVMV_Sub_LSB`, `bus2=HVMV_Sub_48332`, an `inline_recs`
     record, `r_ohm=1e-6 < MV_NEAR_ZERO_R_THRESHOLD_OHM=1e-5`) is still the ONLY entry caught by
     the existing r_ohm-based gate (assert-exactly-1, unchanged). Using Task 1's SAME degree rule
     (do not special-case this pair by name): `_HVMV_Sub_LSB`'s only other connection is the
     logical regulator-bank edge (`FEEDER_REGA/B/C` collapsed to 1); `HVMV_Sub_48332`'s only other
     connection is `LN5710794-3` into the rest of the feeder — degree 1 vs 1, an exact TIE.
     Tie-break: lexicographically smaller wins, and `"HVMV_Sub_48332" < "_HVMV_Sub_LSB"` (`'H'`
     (ASCII 72) sorts before `'_'` (ASCII 95)) — survivor is `"HVMV_Sub_48332"`. Verify your
     implementation reproduces this before proceeding.
  2. DECISION (apply, do not just discuss): merge, not override. Unlike Task 1's pairs, this is
     not a linecode-referencing split of a longer line — it is a named `_connector` record
     representing a literal substation busbar tie, which is by definition a single physical node.
     Bus-merge removes the non-physical element entirely; the prior D-13 near-ideal override
     (assigning it `r=0.09330 Ω`/`x=0.04665 Ω`, a ~93,000x resistance inflation) was a reasonable
     stopgap but is strictly less faithful than removing it. Convert
     `reshape_near_zero_mv_edges!` from VALUE-REASSIGNMENT to a MERGE, reusing Task 1's generic
     merge-pair resolver / rename-and-drop machinery for this ONE r_ohm-caught pair (keep the
     assert-exactly-1 guard, now asserting exactly 1 merge candidate rather than exactly 1 reshape
     candidate). Remove the now-dead constants `D13_NEAR_IDEAL_R_PU`, `D13_NEAR_IDEAL_X_PU`,
     `D13_NEAR_IDEAL_R_OHM_AT_MV_BASE`, `D13_NEAR_IDEAL_X_OHM_AT_MV_BASE`, `IEEE8500_MV_ZBASE_OHM`,
     `IEEE8500_MV_S_BASE_MVA`, `IEEE8500_MV_V_BASE_KV` — `grep` the whole file FIRST to confirm
     none is referenced anywhere else before deleting. Do NOT touch `IEEE123_SWITCH_R`/
     `IEEE123_SWITCH_X` (a separate, unrelated constant pair used by `ieee8500.jl`'s own
     regulator/switch near-ideal treatment). Rename the function to reflect its new semantics
     (e.g. `merge_near_zero_mv_edges!`) and update its docstring; `MV_NEAR_ZERO_R_THRESHOLD_OHM`
     itself is STILL needed (as the r_ohm-based degenerate-pair identification threshold) — keep
     it, just retarget its consumer.
  3. Rewrite the file's header comment block (~lines 71-125, "D-13 near-ideal-branch treatment,
     extended to a degenerate real MV busbar-tie connector") and `emit_output`'s generated-file
     "NOT A VERBATIM TRANSCRIPTION" paragraph to describe the merge treatment, preserving the
     still-valid physical/SOC-exactness-gradient reasoning for WHY this edge needed special
     handling, replacing only the MECHANISM description (merge, not value reassignment).
  4. Append a new, dated sub-entry to `deferred-items.md`'s Item 1 (do not delete the 2026-08-21
     RESOLVED entry — this project's own convention is append-only historical record) stating the
     value-reassignment fix was SUPERSEDED 2026-08-22 by a bus-merge, citing this quick task and
     the tie-break rule/survivor above.
  5. Update `25-DATA-PROVENANCE.md`'s "Deviation from verbatim transcription" section to describe
     the CURRENT (merge) treatment as authoritative, note the D-13 reshape as superseded (not
     deleted from history), and record the degree-tie/lexicographic-tie-break rule used.
  6. Regenerate, run `--verify`, construct both fixtures, and EXPLICITLY verify the D-08 head
     invariant is unbroken (the constraint's own "MUST be verified, not assumed" instruction):
     for each fixture, find the unique branch with an endpoint `== IEEE8500_ROOT_BUS` ("
     HVMV_Sub_HSB") and confirm `isapprox(smax, 55.0; atol=1e-6)` still holds, and that there is
     still exactly one such branch. Measure and record the new bus counts (predicted `4872`
     headline / `2518` MV-only — one fewer than Task 1's end state; verify, don't assume).
- **verify:**
  - `julia scripts/reduce_ieee8500_impedances.jl --verify` passes.
  - `julia --project=. -e 'using TSODSO; f=TSODSO.ieee8500_modified(); h=only(b for b in f.branches if b.from==f.root||b.to==f.root); println(length(f.buses)," ",h.smax); g=TSODSO.ieee8500_mv_modified(); h2=only(b for b in g.branches if b.from==g.root||b.to==g.root); println(length(g.buses)," ",h2.smax)'`
    prints `4872 55.0` and `2518 55.0` (or explains any deviation before continuing).
  - `grep -c "_HVMV_Sub_LSB" src/data/ieee8500_impedances.jl` returns `0`.
  - `grep -n "D13_NEAR_IDEAL" scripts/reduce_ieee8500_impedances.jl` returns no matches.
- **done:** the connector is merged (not value-reassigned), the dead D-13 constants are removed,
  the head-branch S_max invariant is confirmed intact by direct inspection, both fixtures still
  construct, and provenance docs describe the current treatment without erasing history.

### Task 3 — regenerate, re-baseline, and re-measure exactness honestly

- **files:** `test/test_ieee8500.jl`, `test/test_benchmark_ieee8500.jl`, `src/data/ieee8500.jl`
  (docstring bus-count corrections only), `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md`,
  `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md`,
  `results/ieee8500_benchmark/socp_gap_report.csv` (regenerated by the harness)
- **action:**
  1. BEFORE re-running `--gap-report`, preserve the pre-merge baseline: run
     `git show HEAD:results/ieee8500_benchmark/socp_gap_report.csv > /tmp/socp_gap_report_PREMERGE.csv`
     (or equivalent) — the harness's own CSV upsert is keyed by the `point` string and will
     OVERWRITE these exact 3 rows in place once re-run in step 5; this is the only reliable source
     for the exact BEFORE `from_name`/`to_name` on the two `ieee8500-mv` points (only the
     `ieee8500` T=10 point's before-values were directly re-verified this session — see Context).
  2. Confirm the table from Tasks 1-2 is regenerated and `--verify` passes. Report final measured
     bus/branch counts for both fixtures (expected `4872`/`4871` headline, `2518`/`2517` MV-only —
     state plainly if the actual measurement differs and why).
  3. Update `src/data/ieee8500.jl`'s file-header doc comment (lines ~8-15) replacing "4,875"/
     "2,521" with the newly measured counts, with a one-line note pointing to this quick task and
     the 3 merges.
  4. Run `julia --project=. test/test_ieee8500.jl` (the standalone plain-script block — never
     `Pkg.test()`/TestItemRunner, per this project's own recorded sibling-worktree-contamination
     trap). Confirm all assertions pass unmodified. If any hardcoded literal fails (none expected
     per this plan's own audit in Context), update ONLY that literal with an explicit
     justification comment citing the measured value — never rubber-stamp.
  5. Run `julia --project=. test/test_benchmark_ieee8500.jl` (plain-script subprocess test, ~4
     min, one process at a time). It WILL fail on the two pinned literals (`model_vars=137594`,
     `model_cons=275118`) since the `ieee8500-mv --quick` point's bus count changed. Per the
     file's own documented STABILITY-BEFORE-GOLDEN convention (its Test 1 already runs `--quick`
     twice and compares the results to each other), confirm the new values are stable across the
     runs the file itself performs, then update the two pinned literals in Test 2 to the newly
     measured values, adding a dated comment recording the new measurement (append, do not erase
     the 2026-08-21 entry's text — keep it as history with a note that it is superseded). Do not
     touch `termination_status`/`admm_status`/`admm_iters` unless they too changed (report if so,
     with justification, do not silently adjust).
  6. Re-run the SAME 3 gap-report points measured pre-merge, sequentially (one process at a time):
     - `julia --project=. scripts/benchmark_ieee8500.jl --gap-report --fixture ieee8500 --density 0.1 --t-horizon 10 --clarabel-tol 1e-6`
     - `julia --project=. scripts/benchmark_ieee8500.jl --gap-report --fixture ieee8500-mv --density 0.1`
     - `julia --project=. scripts/benchmark_ieee8500.jl --gap-report --fixture ieee8500-mv --density 0.25`
     (The last two rely on `run_gap_report_mode`'s defaults — `T_horizon=24`,
     `clarabel_tol=DEFAULT_CLARABEL_TOL_GAP[:ieee8500_mv]=1e-8` — which byte-identically match the
     pre-merge points; do not pass `--t-horizon`/`--clarabel-tol` for these two so the comparison
     is apples-to-apples.) Never run the true T=24 `ieee8500` headline point (OOM risk).
  7. Build a BEFORE/AFTER table (top-1 gap + dominant offending branch name-pair, per point) using
     the Task-3-preserved pre-merge file (step 1) as BEFORE and the freshly overwritten
     `results/ieee8500_benchmark/socp_gap_report.csv` as AFTER. State plainly which branch is now
     dominant at each point — it can no longer be `L2674047->M1142828` or `M1009834->L3178969`
     (both merged away) or the connector (also merged away); report whatever NEW top-1 offender
     appears, honestly, even if the gap got WORSE or stayed the same order of magnitude. Do not
     tune anything to manufacture an improvement (T-25-12).
  8. Add an explicit non-comparability note — in `25-DATA-PROVENANCE.md`, extending the section
     already updated in Task 2 — stating that `density_sweep_full.csv`, `density_sweep.csv`,
     `noise_floor_calibration.csv`, and every PRE-this-task row of `socp_gap_report.csv` were
     measured on the pre-merge (4875-bus headline / 2521-bus MV-only) topology and are NOT
     directly comparable to any post-task measurement — a fixture-identity change, not a
     solver/tolerance change.
  9. Update `deferred-items.md`'s Item 5 with this task's outcome: was the dominant-offender
     fingerprint pattern (same branch recurring across all 3 points, worsening not replaced) still
     present post-merge with a NEW branch, or did it disappear? Do NOT claim
     `assert_socp_exact!`'s project-default `atol=1e-6` now passes on these points unless it is
     ACTUALLY measured to (Item 5's still-open `"M1069310"->"M1069311"`/`"M1108489"->"P829798"`
     offenders were explicitly left unmerged this pass and remain a plausible explanation if it
     does not) — if it doesn't pass, say so plainly and record the next-tier candidates rather
     than expanding this task's scope to fix them.
- **verify:**
  - `julia --project=. test/test_ieee8500.jl` — `ALL TESTS PASSED` or equivalent zero-failure
    output from the standalone `@testset` block.
  - `julia --project=. test/test_benchmark_ieee8500.jl` prints `ALL TESTS PASSED` after the
    literals are updated to the freshly measured, stable values.
  - The 3 `--gap-report` commands above each complete and print `wrote
    results/ieee8500_benchmark/socp_gap_report.csv (... offender rows for point ...)`.
  - `git diff .planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md` shows the
    non-comparability note and the connector-merge update from Task 2 both present.
- **done:** both fixtures are re-baselined with honestly-measured new counts, both test files pass
  with correctly-justified updated literals, the 3 gap-report points are re-measured with a
  before/after table showing the current dominant offender (whatever it is), and the
  non-comparability of pre-existing CSVs is documented — with an honest verdict on whether
  exactness improved, including if it did not.

## Constraints

- **The reduction script is the ONLY place physics-shaping logic lives.**
  `src/data/ieee8500_impedances.jl` is GENERATED — never hand-edit it; only regenerate via
  `scripts/reduce_ieee8500_impedances.jl`.
- **No tolerance/gate change.** `src/models/exactness.jl`'s `assert_socp_exact!`,
  `socp_relaxation_gap`, `socp_gap_report` stay byte-identical. No `allow_almost` on any
  dual-reading solve.
- **Scope discipline.** Do not merge the 53 `length=0.001 km` artificial stubs. Do not merge
  Item 5's other 2 offender branches (`M1069310->M1069311`, `M1108489->P829798`) or the 5
  non-1ft short real segments — no evidence ties them to the same mechanism this task addresses;
  record them as "next tier" if still relevant after Task 3's re-measurement.
- **Machine discipline.** Shared 15 GiB machine, one Julia process at a time. Never run the full
  density sweep. Never run the true T=24 `ieee8500` headline point (OOM wall, per
  `deferred-items.md` item 6). The T=10 `ieee8500` gap-report point used ~3.2 GB previously —
  budget similarly here.
- **Test-invocation hazards.** `test/test_ieee8500.jl` and `test/test_exactness.jl` are
  TestItemRunner `@testitem` files that do NOT resolve under `--project=.` — but
  `test/test_ieee8500.jl` ALSO has a standalone plain-script block at its bottom
  (`if abspath(PROGRAM_FILE) == @__FILE__`); always invoke it directly
  (`julia --project=. test/test_ieee8500.jl`), never via `@run_package_tests` or
  `julia --project=test -e '... Pkg.develop ...'`. `test/test_benchmark_ieee8500.jl` is a plain
  Test.jl script (not a `@testitem`) invoking real subprocesses; run it directly, budget ~4 min.
- **Provenance honesty.** Every data-shaping decision (which pairs merged, why, survivor choice)
  must be traceable in-code and in `25-DATA-PROVENANCE.md`/`deferred-items.md` — never silent.
  A null exactness-improvement result is a valid, reportable outcome; do not tune tolerances,
  thresholds, or survivor choices to manufacture a passing verdict (T-25-12).

## must_haves

- **truths:**
  - The two genuine 1-ft real-conductor splits (`M1142828<->L2674047`,
    `M1009834<->L3178969`) are represented as a single merged bus each in the generated table,
    with their service transformers correctly reattached to the survivor.
  - The `HVMV_Sub_connector` busbar tie is represented as a merged bus pair, not an impedance
    value, unless Task 2's own re-evaluation concludes otherwise (and if so, says why in-code and
    in `25-DATA-PROVENANCE.md`).
  - Both `ieee8500_modified()` and `ieee8500_mv_modified()` still construct (radial +
    magnitude-valid) after every regeneration, with the head branch's `smax` invariant
    (`≈55.0 pu`, unique branch touching root) explicitly re-verified.
  - The 3 gap-report points are re-measured post-merge and reported honestly against the
    preserved pre-merge baseline, including a null or negative result if that is what is found.
- **artifacts:**
  - `scripts/reduce_ieee8500_impedances.jl` (new generic bus-merge machinery; length-based
    detector for the 2 real splits; r_ohm-based detector, now merging rather than reshaping, for
    the connector; dead D-13 constants removed)
  - `src/data/ieee8500_impedances.jl` (regenerated; casualty bus names absent)
  - `test/test_ieee8500.jl`, `test/test_benchmark_ieee8500.jl` (passing, with any literal changes
    justified by a measured value, never rubber-stamped)
  - `results/ieee8500_benchmark/socp_gap_report.csv` (post-merge rows for the 3 points)
  - `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md`,
    `deferred-items.md` (updated, append-only, non-comparability note present)
- **key_links:**
  - `parse_mv_lines` → length-based degenerate-pair detector → generic merge-pair resolver →
    rename-and-drop applied to `linecode_recs`/`inline_recs`/`switch_pairs`/`xfmr_instances`
    (`mv_base`)/regulator-switch edge Set → `mv_edges_raw` → `dedupe_edges` → `emit_output`
  - `HVMV_Sub_connector`'s `r_ohm < MV_NEAR_ZERO_R_THRESHOLD_OHM` → the SAME generic merge-pair
    resolver (reused, not reimplemented) → survivor `HVMV_Sub_48332` (lexicographic tie-break)
  - `scripts/benchmark_ieee8500.jl --gap-report` → `socp_gap_report` → post-merge
    `results/ieee8500_benchmark/socp_gap_report.csv` rows, compared against the preserved
    pre-merge snapshot

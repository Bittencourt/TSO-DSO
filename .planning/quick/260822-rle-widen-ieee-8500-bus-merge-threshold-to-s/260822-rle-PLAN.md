---
quick_id: 260822-rle
description: Widen the IEEE-8500 zero-length bus-merge threshold from "exactly 1.000 ft" to "sub-metre", merging the remaining line-split artifacts, then re-measure SOCP exactness
date: 2026-08-22
mode: quick
---

# Quick Task 260822-rle: Widen the IEEE-8500 bus-merge threshold to sub-metre

## Why

Quick task 260822-pxb merged 3 degenerate MV segments (2 exact-1.000-ft real-conductor splits +
the `HVMV_Sub_connector` busbar tie) via a generic, reusable bus-merge pipeline
(`compute_bus_degrees`/`resolve_merge_pairs`/`apply_merge!` in
`scripts/reduce_ieee8500_impedances.jl`). Exactness improved substantially (1.5x-5.3x gap
shrinkage at all 3 measured points, one point flipped INEXACT->EXACT) but **dominance
transferred, it did not resolve**: the new top-1 offender at 2 of 3 points is
`M1069310->M1069311` (source line `LN5486729-1`, length 0.560638 m), which carries the SAME `-N`
line-split naming pattern as the already-merged `LN5473436-1`/`LN6259981-1` — direct evidence the
prior threshold (exactly 1.000 ft = 0.0003048 km) was narrower than the phenomenon it targeted.

Direct inspection of `scripts/data/ieee8500/Lines.dss` (this session, verified below) finds
**exactly 8** MV `Linecode=`-referencing segments with `length_km < 0.001` (sub-metre), of which
2 are the ones 260822-pxb already merged and 6 are new:

```
LN5837496-1   0.259836 mm->0.260 m   P829798  <-> M1108489
LN5473436-1   0.305 m               M1142828 <-> L2674047   (ALREADY MERGED, 260822-pxb)
LN6259981-1   0.305 m               M1009834 <-> L3178969   (ALREADY MERGED, 260822-pxb)
LN6268990-2   0.384 m               M1047613 <-> M1047612
LN5486729-1   0.561 m               M1069310 <-> M1069311   (current top-1 offender)
LN5927299-1   0.659 m               M1125974 <-> L3104796
LN5472394-1   0.732 m               M1026708 <-> M1026709
LN5865233-1   0.842 m               M1047744 <-> L3178971
```

7 of 8 carry a `-N` numeric split suffix (independent corroboration that a line-split created an
electrically-identical node pair, not just a naturally short real conductor). All 8 are pairwise
disjoint (16 distinct bus names, confirmed by direct grep against `Lines.dss`, `LoadXfmrCodes.dss`,
`Regulators.dss`, `Transformers.dss` in this session — see Context) so `resolve_merge_pairs`'s
existing pairwise-disjointness assertion should hold; the plan below has the executor CONFIRM this
live (the assertion firing without throwing IS the confirmation) rather than trust this prose.

**53 further records sit at EXACTLY `length=0.001` km and MUST stay excluded**: 43 are `switch=y`
tie segments (a completely different parse bucket — `switch_pairs`/`disabled_switch_pairs`, never
`linecode_recs`) and 9 are `CAP_*` capacitor-jumper stubs with inline fabricated `r1=1.0/x1=1.0`
(`inline_recs`, also never `linecode_recs`; ~20x MORE resistive than any of the 8 target segments,
so not the bottleneck and structurally a different class). The 1 remaining `length=0.001` record,
`HVMV_Sub_connector`, was already merged by 260822-pxb via the SEPARATE r_ohm-based detector
(`merge_near_zero_mv_edges!`) — untouched by this task. None of the 53 can structurally reach the
length-based detector this task widens (confirmed: it only ever scans `linecode_recs`, and CAP_/
switch records never populate that collection) — see Task 1 for a belt-and-braces guard anyway.

**Honest expectation-reconciliation flag (read before Task 2):** this task's own directory name
and the orchestrating description both say "5 remaining artifacts." A direct recount of the 8-item
table above shows only 2 already merged (`LN5473436-1`, `LN6259981-1`), leaving **6**, not 5, new
merges — `LN5837496-1`, `LN6268990-2`, `LN5486729-1`, `LN5927299-1`, `LN5472394-1`, `LN5865233-1`.
This plan carries BOTH numbers forward explicitly; Task 2 must VERIFY the actual measured count
from the regenerated script's own printed summary and the real `length(feeder.buses)`, and
RECONCILE whichever number is wrong (this prose's "6" or the task framing's "5") rather than
silently picking one. Do not force either predicted bus count.

**Explicitly NOT in scope:** the 53 `length=0.001` km stubs (2 classes: 43 switch ties, 9 CAP_
jumpers) stay untouched, recorded as a distinct "next tier" if still relevant afterward. No
tolerance/gate default in `src/models/exactness.jl`/`scripts/benchmark_ieee8500.jl`'s
`EXACTNESS_ATOL` changes. No `allow_almost` on any dual-reading solve. No T=24 headline
(`ieee8500`) solve (OOM wall). One Julia process at a time (shared 15 GiB machine).

## Context

- `scripts/reduce_ieee8500_impedances.jl` — THE file to change (Task 1). Read the existing
  machinery before touching it:
  - `MV_ZERO_LENGTH_KM = 0.0003048` (~line 436) — current threshold, exactly 1.000 ft, checked via
    `isapprox(r.length_km, MV_ZERO_LENGTH_KM; atol = 1.0e-9)`.
  - `detect_length_class_merge_pairs(linecode_recs::Vector{MVLinecodeRef})` (~line 448) — scans
    `linecode_recs` ONLY (never `inline_recs`, where the CAP_ stubs and the connector live);
    asserts `length(pairs) == 2`, throws otherwise. This is the function to widen.
  - `struct MVLinecodeRef` (~line 289): fields `bus1_base::String`, `bus2_base::String`,
    `linecode::String`, `length_km::Float64`. **Does NOT carry the original `New Line.<name>`
    record name** — needed for the new CAP_-prefix guard (see Task 1 action item 2). Exactly 2
    construction sites: `parse_mv_lines` (~line 370, inside the `Linecode=` branch) and
    `apply_merge!`'s `kept_linecode` rebuild (~line 590).
  - `parse_mv_lines(text)` (~line 332): line-by-line dispatch of every `New Line.*` statement into
    4 buckets (enabled switch, disabled switch, `Linecode=`-referencing -> `MVLinecodeRef`, inline
    `r1=`/`x1=` -> `ImpedanceEdge`). The `Linecode=`-referencing branch (~lines 349-371) is where
    a captured record name must be threaded into the new `MVLinecodeRef` field.
  - `compute_bus_degrees`, `resolve_merge_pairs`, `apply_merge!` (~lines 467-651) — the GENERIC
    merge machinery from 260822-pxb. **Do not modify these** — the widened detector must produce a
    `Vector{Tuple{String,String}}` exactly like the current one and hand it to the SAME
    `resolve_merge_pairs`/`apply_merge!` calls already wired in `main()` (~lines 1374-1391).
  - `merge_near_zero_mv_edges!` (~line 668, the SEPARATE r_ohm-based connector merge) — untouched,
    independent detection mechanism on `inline_recs`, reuses the same generic resolver internally.
  - File-header comment block (~lines 1-40) and the "Zero-length bus-merge" section header
    (~lines 413-431) describe the CURRENT 2-pair/1.000-ft scope — needs a new, appended dated
    paragraph (never delete/rewrite the 260822-pxb prose — this project's own convention across
    `deferred-items.md`/`25-DATA-PROVENANCE.md` is append-only historical record; the reduction
    script's header has followed the same layered-commentary pattern across both prior passes).
  - `main()` (~line 1316): parse order already runs `parse_mv_lines`, `parse_xfmr_instances`,
    `build_regulator_edges` BEFORE `compute_bus_degrees`/`detect_length_class_merge_pairs` — no
    reordering needed, this task only widens what already runs at the same point in the pipeline.
- **Verified-this-session degree computations for the 6 NEW pairs** (direct `grep` against
  `Lines.dss`/`LoadXfmrCodes.dss`/`Regulators.dss`/`Transformers.dss` — excluding each pair's own
  degenerate edge from the count, matching `resolve_merge_pairs`'s own "-1" convention; NONE of
  these 12 bus names touches a regulator/switch edge or a load/capacitor bus):

  | Pair | Casualty (remaining degree) | Survivor (remaining degree) | Notes |
  |---|---|---|---|
  | `LN5837496-1` | `P829798` (1: `LN6292600-1`) | `M1108489` (2: `LN5533710-1`, `LN5837496-3`) | |
  | `LN6268990-2` | `M1047612` (1: `LN8961760-1`) | `M1047613` (2: `LN6268990-4`, `LN8961758-1`) | |
  | `LN5486729-1` | `M1069310` (0: no other edge) | `M1069311` (3: `LN5970852-1`, `LN5965099-2`, `LN5637597-1`) | |
  | `LN5927299-1` | `L3104796` (1: xfmr `T5260569C` mv_base) | `M1125974` (2: `LN5651995-1`, `LN6260930-1`) | xfmr `T5260569C`'s `mv_base` MUST rename `L3104796`->`M1125974` |
  | `LN5472394-1` | `M1026708` (1: `LN5472403-2`) | `M1026709` (2: `LN6290233-1`, `LN5655685-1`) | |
  | `LN5865233-1` | `M1047744` (1: `LN5865234-1`) | `L3178971` (2: `LN6138602-1`, xfmr `T5338896A` mv_base) | `T5338896A` already sits on the survivor — no rename needed, but `apply_merge!`'s generic rename is a no-op here, not a special case |

  No tie-break needed for any of the 6 (all strict degree differences) — unlike the connector's
  exact tie in 260822-pxb. Task 1's own verify step must confirm the code reproduces this table,
  not just trust this prose.
- `scripts/data/ieee8500/Lines.dss` — vendored source, unchanged since 260822-pxb. Key records:
  line 943 `New Line.LN5486729-1 bus1=M1069311 bus2=M1069310 length=0.000560638 units=km
  Linecode=3PH_H-2/0_ACSR2/0_ACSR2/0_ACSR2_ACSR`; line 2042 `New Line.LN5837496-1
  bus1=P829798.1 bus2=M1108489.1 length=0.000259836 ...`; line 2064 `New Line.LN6268990-2
  bus1=M1047613.3 bus2=M1047612.3 length=0.000383926 ...`; line 2012 `New Line.LN5927299-1
  bus1=M1125974.3 bus2=L3104796.3 length=0.000658611 ...`; line 923 `New Line.LN5472394-1
  bus1=M1026708 bus2=M1026709 length=0.000731906 ...`; line 1083 `New Line.LN5865233-1
  bus1=M1047744.1 bus2=L3178971.1 length=0.000842188 ...`. The CAP_ exclusion example: line 2526
  `New Line.CAP_1A bus1=L2823592.1 bus2=L2823592_CAP.1 length=0.001 units=km r1=1.0 x1=1.0
  Phases=1` (inline `r1=`/`x1=`, never reaches `linecode_recs`).
- `src/data/ieee8500.jl` — file-header doc comment (~lines 8-16) states current counts "4,872"/
  "2,518" — needs correcting once Task 2 measures the new counts (same pattern as 260822-pxb's own
  correction of "4,875"/"2,521" -> "4,872"/"2,518"). `IEEE8500_ROOT_BUS = "HVMV_Sub_HSB"`.
- `test/test_ieee8500.jl` — audited this session: `length(cap) == 4` and `length(loads) == 1177`
  are LV/capacitor-bus literals; none of the 6 new casualty buses is a load or capacitor bus
  (confirmed by grep against `Loads.dss`/`Capacitors.dss` this session) — expected to need NO
  changes, but Task 2 must actually run the file to confirm, never assume. No MV-bus-count literal
  exists in this file (radiality/root/id-contiguity assertions are all invariants relative to the
  measured `N = length(feeder.buses)`, not hardcoded numbers).
- `test/test_benchmark_ieee8500.jl` — plain `Test.jl` script (NOT a `@testitem`; run directly,
  never via `Pkg.test()`/TestItemRunner — this project's own recorded sibling-worktree hazard).
  The 2 pinned D-16 goldens (`model_vars == 137444`, `model_cons == 274818`, on the
  `ieee8500-mv --quick` point) WILL move again (MV-only bus count drops further). Follow the
  file's own documented STABILITY-BEFORE-GOLDEN convention (its Test 1 already runs `--quick`
  twice and compares the two runs to each other) before re-pinning Test 2's literals.
- `scripts/benchmark_ieee8500.jl` — `EXACTNESS_ATOL` dict (~line 141, `IEEE8500_MV_EXACT_ATOL =
  0.0011460285861373265`, `IEEE8500_EXACT_ATOL = 0.004969145122458496`) — **DO NOT TOUCH**, these
  are the fixed calibration floor this task measures AGAINST, never re-tunes. `run_gap_report_mode`
  (~line 873) is the `--gap-report` entrypoint; confirmed exact CLI forms from 260822-pxb's own
  plan (re-use verbatim, same points, same flags):
  - `julia --project=. scripts/benchmark_ieee8500.jl --gap-report --fixture ieee8500 --density 0.1 --t-horizon 10 --clarabel-tol 1e-6`
  - `julia --project=. scripts/benchmark_ieee8500.jl --gap-report --fixture ieee8500-mv --density 0.1`
    (defaults: `T_horizon=24`, `clarabel_tol=DEFAULT_CLARABEL_TOL_GAP[:ieee8500_mv]=1e-8` — do
    NOT pass `--t-horizon`/`--clarabel-tol` so the point matches exactly)
  - `julia --project=. scripts/benchmark_ieee8500.jl --gap-report --fixture ieee8500-mv --density 0.25`
    (same defaults as above)
  `run_gap_report_mode` UPSERTS `results/ieee8500_benchmark/socp_gap_report.csv` by its `point`
  string key — re-running these 3 points OVERWRITES the current (post-260822-pxb, "pass-1") rows
  in place. Preserve them FIRST via `git show HEAD:results/ieee8500_benchmark/socp_gap_report.csv`
  (the file is currently committed at the pass-1 state — see the literal CSV content already
  inspected this session, reproduced in the before/after table skeleton below).
- **Pass-1 baseline (already committed, cite directly, do not re-derive):**

  | Point | pass-1 top-1 gap | pass-1 dominant branch | pass-1 verdict vs its (unchanged) atol |
  |---|---|---|---|
  | `ieee8500,density=0.1,T=10,tol=1e-6` | `0.0061304` | `M1069310->M1069311` | INEXACT (1.23x over `0.0049691`) |
  | `ieee8500-mv,density=0.1,T=24,tol=1e-8` | `0.0003853` | `M1069310->M1069311` | EXACT (0.34x of `0.0011460`) |
  | `ieee8500-mv,density=0.25,T=24,tol=1e-8` | `0.0008137` | `M1069310->M1069311` | EXACT (0.71x of `0.0011460`) |

  (Original pre-any-merge baseline, for the full 3-column table Task 3 must build: `0.0325016`/
  `0.0005781`/`0.0037728`, all dominated by `L2674047->M1142828` — already committed in
  `deferred-items.md` item 5 / 260822-pxb's own SUMMARY, cite from there rather than re-measuring.)
- `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` — append-only convention
  (never delete/rewrite prior entries); Item 5 already frames the still-open
  `M1069310->M1069311`/`M1108489->P829798` fingerprint investigation this task closes (or doesn't
  — report honestly either way).
- `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md` — has a "SUPERSEDING
  deviation" section from 260822-pxb describing the 3-pair merge; needs a further superseding
  section for this task's widened 8-pair (or however many actually verified) merge class.

## Tasks

### Task 1 — widen the threshold, widen the guard, add the CAP_ belt-and-braces assertion

- **files:** `scripts/reduce_ieee8500_impedances.jl`
- **action:**
  1. Add a `name::String` field to `struct MVLinecodeRef` (append it after `length_km` to keep
     the existing 4-arg call sites' positional order stable for the fields being reused elsewhere).
     In `parse_mv_lines`'s `Linecode=`-referencing branch (~line 349), capture the record name via
     a new `match(r"New\s+Line\.(\S+)"i, raw)` (or reuse an existing name-capture if one already
     exists earlier in the loop — check before adding a duplicate regex) and pass it as the 5th
     positional argument to `MVLinecodeRef(...)`. Update `apply_merge!`'s `kept_linecode` rebuild
     (~line 590, the `push!(kept_linecode, MVLinecodeRef(rn(r.bus1_base), rn(r.bus2_base),
     r.linecode, r.length_km))` line) to also thread `r.name` through unchanged (renaming never
     touches the record's own line name, only its bus endpoints). This is a minimal, additive
     field extension required specifically for the new guard in step 3 below — it does not
     duplicate or reimplement any of the generic merge machinery (`compute_bus_degrees`/
     `resolve_merge_pairs`/`apply_merge!` stay untouched).
  2. Replace `const MV_ZERO_LENGTH_KM = 0.0003048` with a widened sub-metre bound:
     ```
     const MV_SUBMETRE_LENGTH_KM_BOUND = 0.001      # 1 metre, in km (EXCLUSIVE upper bound)
     const MV_SUBMETRE_LENGTH_KM_EPS = 1.0e-6        # 1 mm float-safety margin at the boundary
     ```
     Document, in a comment directly above, WHY a plain `< 0.001` is not float-safe on its own
     (the 53 excluded records are textually `length=0.001`, parsed via the SAME `parse(Float64,
     ...)` path — a bare `<` should already exclude them since `x < x` is false, but a small
     explicit margin removes any dependency on that parsing-determinism assumption holding across
     a future upstream data refresh) and why `1.0e-6` km (1 mm) is a safe margin: the largest
     in-scope target length is `0.000842188` km (0.842 m) and the smallest excluded length is
     `0.001` km (1.0 m) — a `0.157812` km gap, ~158x the chosen margin.
  3. Rewrite `detect_length_class_merge_pairs(linecode_recs::Vector{MVLinecodeRef})`: filter with
     `r.length_km < MV_SUBMETRE_LENGTH_KM_BOUND - MV_SUBMETRE_LENGTH_KM_EPS` instead of the old
     `isapprox` check. For EACH matched record, before collecting its pair, assert
     `!startswith(r.name, "CAP_")`, throwing a loud `ArgumentError` naming the offending record if
     it ever fires (belt-and-braces: CAP_ records are currently `inline_recs`, never
     `linecode_recs`, so this should never trigger today — document that explicitly in the
     docstring, and that the assertion exists specifically so a future upstream data refresh that
     reclassifies a CAP_ stub as a `Linecode=`-referencing record fails LOUDLY here instead of
     silently entering the merge). Change the count assertion from `length(pairs) == 2` to
     `length(pairs) == 8`, with a failure message stating the new expected count, the physical
     justification (sub-metre real-conductor line-split artifacts, corroborated by the `-N` split
     suffix), and instructing a future maintainer investigating a mismatch to re-verify scope
     before silently widening or shrinking the threshold again — mirror the existing message's
     tone and level of detail, do not shorten it.
  4. Do NOT modify `compute_bus_degrees`, `resolve_merge_pairs`, or `apply_merge!` — the widened
     `detect_length_class_merge_pairs` must return the same `Vector{Tuple{String,String}}` shape
     and flow into the SAME `resolve_merge_pairs(length_class_pairs, degree)` /
     `apply_merge!(...)` calls already wired in `main()`. Confirm (read, do not just assume) that
     `resolve_merge_pairs`'s existing pairwise-disjointness assertion will now run over 8 pairs
     instead of 2 — if it throws, STOP: that means the Context table's disjointness claim above is
     wrong and needs live re-investigation before proceeding, not a workaround.
  5. Append a new, dated paragraph to the file's header comment block and to the "Zero-length
     bus-merge" section header (do not delete or rewrite the 260822-pxb prose — append, matching
     this project's own convention in `deferred-items.md`/`25-DATA-PROVENANCE.md`) describing: the
     widened bound, the 6 newly-caught pairs (name each), the 2 already covered by the prior exact
     threshold (now subsumed by the wider one, same detector, same code path), the 7-of-8 `-N`
     split-suffix corroboration, and the CAP_/switch exclusion boundary with the exact counts (43
     switch + 9 CAP_ = 53, all structurally unreachable by this detector).
  6. Update the `println` summary text if needed (the existing "Bus merge (length-class): N pairs
     merged: [...]" pattern already works generically — confirm it prints 8, do not hardcode "8"
     into the string itself).
- **verify:**
  - `julia scripts/reduce_ieee8500_impedances.jl --verify` still passes (CT5 sanity check,
    untouched — note this mode does NOT exercise the merge detector at all, so this alone does not
    validate this task's change).
  - `julia scripts/reduce_ieee8500_impedances.jl` (full regenerate) prints "Bus merge
    (length-class): 8 pairs merged: [...]" and "Bus merge (near-zero-r connector): 1 pair(s)
    merged: [...]" (the connector merge, unaffected, must still fire independently) — inspect the
    printed casualty=>survivor list against the Context table above and confirm it matches exactly
    (all 6 new predictions plus the 2 already-known ones); if the printed count is not 8, or any
    survivor disagrees with the table, STOP and investigate before proceeding to Task 2.
  - `julia --project=. -e 'using TSODSO; f=TSODSO.ieee8500_modified(); g=TSODSO.ieee8500_mv_modified(); println(length(f.buses)," ",length(f.branches)," ",length(g.buses)," ",length(g.branches))'`
    constructs both fixtures without throwing (exercises `assert_radial`+`assert_magnitudes`) and
    prints 4 numbers — expected `4866 4865 2512 2511` if 6 new pairs merged (this plan's own
    recount) or `4867 4866 2513 2512` if only 5 new pairs merged (the task-framing's stated
    expectation); whichever it actually is, record it plainly and do not force either.
  - `grep -v '^#' src/data/ieee8500_impedances.jl | grep -c '"P829798"\|"M1047612"\|"M1069310"\|"L3104796"\|"M1026708"\|"M1047744"'`
    returns `0` (all 6 new casualty names absent from the generated table; `grep -v '^#'` strips
    header prose so this cannot false-positive against a doc-comment mention).
  - `grep -n "startswith.*CAP_\|CAP_" scripts/reduce_ieee8500_impedances.jl | grep -i "detect_length_class\|belt-and-braces"` —
    confirms the new guard is present in the right function (a sanity grep, not a correctness
    proof).
- **done:** the threshold is a documented, float-safe sub-metre bound (not an exact-value match),
  the guard asserts exactly 8 matches with a CAP_-prefix belt-and-braces check, both fixtures
  still construct after a full regeneration, and the 6 new casualty names are confirmed absent
  from the generated table.

### Task 2 — reconcile the measured delta, re-run both test files, re-pin goldens with justification

- **files:** `src/data/ieee8500.jl` (file-header doc-comment counts only), `test/test_ieee8500.jl`
  (only if audit is wrong), `test/test_benchmark_ieee8500.jl` (2 golden literals)
- **action:**
  1. From Task 1's regeneration output, state the ACTUAL measured pair count (8 total merged,
     minus the 2 already known = N new) and the ACTUAL measured bus/branch counts for both
     fixtures. Explicitly reconcile against BOTH candidate predictions in this plan (6-new /
     4866-4865-2512-2511 vs 5-new / 4867-4866-2513-2512) — state which one is correct and, if
     neither matches exactly, investigate why (e.g., a bus name collision this plan's manual grep
     missed) before continuing. Do not silently pick a number to make the plan "look right."
  2. Update `src/data/ieee8500.jl`'s file-header doc comment (the paragraph already citing
     260822-pxb's "4,872"/"2,518" correction) with the newly measured counts, one-line note citing
     this task and the widened threshold.
  3. Run `julia --project=. test/test_ieee8500.jl` (the standalone plain-script block — never
     `Pkg.test()`/TestItemRunner). Confirm the audit above holds (no failure) — if any assertion
     fails, update ONLY that literal with an explicit justification comment citing the measured
     value, never rubber-stamp.
  4. Run `julia --project=. test/test_benchmark_ieee8500.jl` (plain-script subprocess test, ~4
     min, one process at a time). It WILL fail on the two pinned literals (`model_vars=137444`,
     `model_cons=274818`) since the `ieee8500-mv --quick` point's bus count changed again. Per the
     file's own documented STABILITY-BEFORE-GOLDEN convention (Test 1 already runs `--quick` twice
     and compares the two runs to each other), confirm the new values are stable across those two
     runs, then update Test 2's two pinned literals to the newly measured, stable values, adding a
     dated comment (append after the existing 2026-08-21/2026-08-22 entries — do not erase them,
     mark them superseded). Do not touch `termination_status`/`admm_status`/`admm_iters` unless
     they too changed (report if so, with justification, do not silently adjust).
  5. Explicitly re-verify the D-08 head invariant on both regenerated fixtures (never assume it
     survived just because Task 1's construction check didn't throw): for each fixture, find the
     unique branch with an endpoint `== IEEE8500_ROOT_BUS` ("HVMV_Sub_HSB") and confirm
     `isapprox(smax, 55.0; atol=1e-6)` holds and there is still exactly one such branch. Re-verify
     total real load conservation (`sum(values(TSODSO.IEEE8500_LOAD_KW))` still `≈ 10773.17`,
     unchanged since none of the 6 new casualty buses is a load bus — confirmed by this session's
     grep audit) and load-bus counts unchanged (1177 headline / `≤1177` mv, per
     `test_ieee8500.jl`'s own existing assertions in step 3).
- **verify:**
  - `julia --project=. test/test_ieee8500.jl` — `ALL TESTS PASSED` (or the file's equivalent
    zero-failure standalone output).
  - `julia --project=. test/test_benchmark_ieee8500.jl` prints `ALL TESTS PASSED` after the 2
    literals are updated to the freshly measured, stable values.
  - `julia --project=. -e 'using TSODSO; f=TSODSO.ieee8500_modified(); h=only(b for b in f.branches if b.from==f.root||b.to==f.root); println(h.smax); g=TSODSO.ieee8500_mv_modified(); h2=only(b for b in g.branches if b.from==g.root||b.to==g.root); println(h2.smax); println(sum(values(TSODSO.IEEE8500_LOAD_KW)))'`
    prints `55.0`, `55.0`, `10773.17...` (within float tolerance).
- **done:** both fixtures are re-baselined with an honestly-measured and reconciled new count,
  both test files pass with correctly-justified updated literals (or confirmed unchanged), and the
  D-08 head invariant plus total load conservation are explicitly re-verified, not assumed.

### Task 3 — re-measure the 3 SOCP-exactness points, build a 3-column before/after table, report honestly

- **files:** `results/ieee8500_benchmark/socp_gap_report.csv` (regenerated by the harness),
  `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md`,
  `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md`
- **action:**
  1. BEFORE re-running `--gap-report`, preserve the CURRENT ("pass-1", post-260822-pxb) rows for
     the 3 points via `git show HEAD:results/ieee8500_benchmark/socp_gap_report.csv` (grep out the
     3 `point` values below) — the harness's own CSV upsert (keyed by `point`) will overwrite
     these rows in place once re-run. The exact pass-1 top-1 rows are already reproduced in this
     plan's Context section; re-derive the full pass-1 offender rows from `git show` only if a
     deeper cross-check is needed.
  2. Re-run, sequentially (one Julia process at a time, per this machine's memory discipline):
     - `julia --project=. scripts/benchmark_ieee8500.jl --gap-report --fixture ieee8500 --density 0.1 --t-horizon 10 --clarabel-tol 1e-6`
     - `julia --project=. scripts/benchmark_ieee8500.jl --gap-report --fixture ieee8500-mv --density 0.1`
     - `julia --project=. scripts/benchmark_ieee8500.jl --gap-report --fixture ieee8500-mv --density 0.25`
     Never run the true T=24 `ieee8500` headline point (OOM wall, per `deferred-items.md`). The
     T=10 headline point previously used ~3.2 GB — budget similarly; check free memory before and
     after with `free -h`.
  3. Build a 3-COLUMN before/after table (pre-merge original / after-pass-1 (260822-pxb) /
     after-pass-2 (this task)) for all 3 points, each column's top-1 gap AND dominant offending
     branch name-pair, plus the verdict against that point's OWN unchanged atol (`ratio =
     gap/atol`, `IEEE8500_EXACT_ATOL=0.0049691451` for the headline `ieee8500` point,
     `IEEE8500_MV_EXACT_ATOL=0.0011460286` for both `ieee8500-mv` points — read these from
     `scripts/benchmark_ieee8500.jl`, never hardcode a possibly-stale copy). State PLAINLY whether
     the headline `ieee8500,density=0.1,T=10` point — which sat at 1.23x its atol after pass-1 —
     now crosses to EXACT, stays INEXACT, or moves in an unexpected direction; do not presume
     either outcome ahead of the actual measurement.
  4. Identify and name the NEW dominant (rank-1) offender at each point from the freshly
     overwritten CSV, whatever it is — this is the "next tier" candidate regardless of whether
     exactness improved, stayed flat, or worsened. Report its `r_pu`/length if resolvable to a
     source line via `ieee8500_relabel_map`/`ieee8500_mv_relabel_map` (the CSV's `from_name`/
     `to_name` columns already do this join).
  5. Append a new, dated section to `deferred-items.md` (append-only — do not rewrite Item 5's
     existing "still OPEN" framing, add a new dated resolution/update sub-entry under it,
     mirroring 260822-pxb's own "Item 1 addendum — SUPERSEDED" pattern) recording: the widened
     8-pair merge, the 3-column before/after table, the new dominant offender(s), and an EXPLICIT
     honest verdict — if the headline point is STILL inexact, or if dominance simply transferred
     again to a longer segment, say so plainly. Do NOT re-tune any atol, tolerance, or threshold to
     force an EXACT verdict (T-25-12 certificate-laundering).
  6. Update `25-DATA-PROVENANCE.md`'s "SUPERSEDING deviation" section (260822-pxb's) with a further
     dated append describing the widened sub-metre bound, the 6 newly-merged pairs and their
     survivors, the CAP_/switch exclusion boundary (53 records, 2 sub-classes), and a
     non-comparability note: `density_sweep_full.csv`, `density_sweep.csv`,
     `noise_floor_calibration.csv`, and every pass-1-and-earlier row of `socp_gap_report.csv` were
     measured on the PRE-this-task topology and are not directly comparable to any post-task
     measurement (a further fixture-identity change, not a solver/tolerance change).
- **verify:**
  - The 3 `--gap-report` commands each complete and print `wrote
    results/ieee8500_benchmark/socp_gap_report.csv (... offender rows for point ...)`, all with
    `termination_status=OPTIMAL` (an `ALMOST_OPTIMAL`/error result on any of these 3 specific,
    previously-OPTIMAL points would itself be a notable finding to report, not silently retried).
  - `git diff --stat .planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md .planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md`
    shows both files grew (append), never shrank.
- **done:** the 3 points are re-measured with a full pre-merge/pass-1/pass-2 before-after table,
  the current verdict against each fixture's own unchanged atol is stated plainly (including if
  still inexact), the new dominant offender is named at each point, and provenance docs record the
  widened merge class and the further non-comparability boundary — with no tolerance/threshold
  tuned to manufacture a passing result.

## Constraints

- **The reduction script is the ONLY place physics-shaping logic lives.**
  `src/data/ieee8500_impedances.jl` is GENERATED — never hand-edit it; only regenerate via
  `scripts/reduce_ieee8500_impedances.jl`.
- **Reuse, do not rebuild, the generic merge machinery.** `compute_bus_degrees`,
  `resolve_merge_pairs`, `apply_merge!`, and `merge_near_zero_mv_edges!` stay untouched — this task
  only widens `detect_length_class_merge_pairs`'s threshold/guard and adds the minimal `name`
  field needed to support the new CAP_ assertion.
- **No tolerance/gate change.** `src/models/exactness.jl`'s `assert_socp_exact!`,
  `socp_relaxation_gap`, `socp_gap_report`, and `scripts/benchmark_ieee8500.jl`'s `EXACTNESS_ATOL`
  constants stay byte-identical. No `allow_almost` on any dual-reading solve.
- **Scope discipline.** Do not merge the 53 `length=0.001` km records (43 switch ties + 9 CAP_
  stubs) under any circumstance — the widened bound is strictly `< 1 metre`, not `≤`. If the
  regeneration ever reports more than 8 matches, STOP and investigate before proceeding.
- **Machine discipline.** Shared 15 GiB machine, one Julia process at a time. Never run the full
  density sweep. Never run the true T=24 `ieee8500` headline point.
- **Test-invocation hazards.** `test/test_ieee8500.jl` and `test/test_exactness.jl` are
  TestItemRunner `@testitem` files that do NOT resolve under `--project=.` — but
  `test/test_ieee8500.jl` also has a standalone plain-script block at its bottom; always invoke it
  directly (`julia --project=. test/test_ieee8500.jl`), never via `@run_package_tests` or
  `julia --project=test -e '... Pkg.develop ...'`. `test/test_benchmark_ieee8500.jl` is a plain
  Test.jl script (not a `@testitem`) invoking real subprocesses; run it directly, budget ~4 min.
- **Provenance honesty.** Every data-shaping decision (which pairs merged, why, survivor choice,
  the 5-vs-6 reconciliation) must be traceable in-code and in `25-DATA-PROVENANCE.md`/
  `deferred-items.md` — never silent. A null or partial exactness-improvement result is a valid,
  reportable outcome; do not tune tolerances, thresholds, or survivor choices to manufacture a
  passing verdict (T-25-12).
- **Fixture-identity change, again.** Every measurement CSV predating this task is not directly
  comparable to any measurement taken after it — document this explicitly, do not silently treat
  old and new rows as comparable in any table this task builds.

## must_haves

- **truths:**
  - All 6 newly-in-scope sub-metre real-conductor line-split segments (`LN5837496-1`,
    `LN6268990-2`, `LN5486729-1`, `LN5927299-1`, `LN5472394-1`, `LN5865233-1`) are represented as
    a single merged bus each in the generated table, with degree-selected survivors matching the
    Context table (or an honestly-reconciled deviation from it).
  - The 53 `length=0.001` km records (43 switch ties + 9 CAP_ stubs) remain entirely unmerged and
    unaffected.
  - Both `ieee8500_modified()` and `ieee8500_mv_modified()` still construct (radial +
    magnitude-valid) after regeneration, with the D-08 head `smax` invariant (`≈55.0 pu`, unique
    branch touching root) and total load conservation (`≈10773.17` kW) explicitly re-verified.
  - The 3 gap-report points are re-measured post-widening and reported honestly in a 3-column
    (pre-merge / pass-1 / pass-2) before-after table, including if the headline point remains
    INEXACT or if dominance simply transfers to a new branch.
- **artifacts:**
  - `scripts/reduce_ieee8500_impedances.jl` (widened `MV_SUBMETRE_LENGTH_KM_BOUND`, assert-exactly-8
    guard with CAP_-prefix assertion, `MVLinecodeRef.name` field, appended dated header prose)
  - `src/data/ieee8500_impedances.jl` (regenerated; the 6 new casualty bus names absent)
  - `test/test_ieee8500.jl`, `test/test_benchmark_ieee8500.jl` (passing, with any literal changes
    justified by a measured, stability-confirmed value)
  - `results/ieee8500_benchmark/socp_gap_report.csv` (pass-2 rows for the 3 points)
  - `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md`,
    `deferred-items.md` (updated, append-only, with the further non-comparability note)
- **key_links:**
  - `parse_mv_lines` -> widened `detect_length_class_merge_pairs` (sub-metre bound + CAP_ guard) ->
    the SAME `resolve_merge_pairs`/`apply_merge!` from 260822-pxb -> `mv_edges_raw` ->
    `dedupe_edges` -> `emit_output`
  - `scripts/benchmark_ieee8500.jl --gap-report` -> `socp_gap_report` -> pass-2
    `results/ieee8500_benchmark/socp_gap_report.csv` rows, compared against both the pre-merge and
    pass-1 preserved snapshots

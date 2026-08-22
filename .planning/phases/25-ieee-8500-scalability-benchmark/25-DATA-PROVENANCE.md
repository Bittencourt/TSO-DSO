# Phase 25 — IEEE-8500 source-data provenance seed

Captured 2026-08-20 while adding the phase, so SCALE-01's reduction script has a verified
provenance header to copy and the plan step does not re-derive the fetch.

**Source repo:** `dss-extensions/electricdss-tst` (public mirror of the EPRI/OpenDSS distribution)
**Path:** `Version8/Distrib/IEEETestCases/8500-Node/`
**Raw URL base:** `https://raw.githubusercontent.com/dss-extensions/electricdss-tst/master/Version8/Distrib/IEEETestCases/8500-Node`
**Fetched:** 2026-08-20 (ref `master`, initial unpinned discovery fetch)
**Pinned commit SHA:** `3b208397160213cae4a9e2d0a7d1aa3528ce26e1` (resolved from `dss-extensions/electricdss-tst`'s `master` HEAD via `git ls-remote`)
**Fetch-verified:** 2026-08-21 — all 10 files fetched at the pinned SHA into `scripts/data/ieee8500/`; sha256 of the 9 previously-recorded files matches this table exactly (no upstream drift since the 2026-08-20 discovery fetch); `Triplex_Linecodes.dss` fetched and checksummed for the first time.

`Master.dss` is the **balanced load case** — the one this phase uses. `Master-unbal.dss` +
`UnbalancedLoads.DSS` are the unbalanced variant and are OUT OF SCOPE (standing project scope is
balanced positive-sequence).

Note on the redirect set: `Master.dss` redirects `LoadXfmrCodes.dss` and comments out
`LoadXfmrs.dss`, because `LoadXfmrCodes.dss` contains BOTH the 9 `XfmrCode` definitions AND all
1177 service-transformer instances that reference them. `LoadXfmrs.dss` is the equivalent long-form
listing of the same 1177 transformers. The secondaries ARE connected in the balanced case.

Also note `Master.dss` redirects `LineCodes2.DSS` (Ohm matrices, `Units=km`), NOT `LineCodes.dss`.

## Files needed for a full MV + LV positive-sequence reduction

Checksums below are of the 2026-08-20 fetch; re-verify on vendoring.

```
9bd0e17f33e9ec7e0baa46693abeec069b148cbee8477301d77450f95d601ad8  Master.dss
3fec9199a41696a758eaff7065f86a89477f70898b1bee3295de9c74f154121a  LineCodes2.DSS
460eb5e8179bda1926d0d70cf4fc9d8bdd29ab4dd9a101941730749f8a4a663a  Lines.dss
cab397f65f5de08c4d82cf794c03c432b404cd5db7db37ff827869db8344b708  Transformers.dss
422122863efd0268cb125694b0830673baa6ce466157ceea223cb64bcbe0a533  LoadXfmrCodes.dss
abf45521bc05a7f9d5c3fa4c94c4f24f7ea9bc984e7086b303ae4a143d77971d  Triplex_Lines.DSS
4d5b68a8095bbee59a95ba08255f34b74fcf3d89c0e413df2fc669648fb2d18f  Loads.dss
cc05836176a6715b121619079eb6cef96e77468a3368c8ed44815f2e9d684dcf  Capacitors.dss
041f353f55076feaaf751bbb20551226f8727ddfbdfc5101cf1b1f222da38617  Regulators.dss
7dfbfc23e19d8930c9e5ac3302bd9e8e9d52aee9c333e3fc80422f15752a886d  Triplex_Linecodes.dss
```

All 10 files above are now vendored at `scripts/data/ieee8500/` at the pinned commit SHA. Not
fetched (not needed by this phase's reduction): `Buscoords.dss` (215 KB, only needed if bus
coordinates are wanted for figures).

## Counts measured from the fetched files (non-comment lines)

| File | Records | What |
|------|---------|------|
| `Lines.dss` | 2526 | MV primary segments, phase-tagged terminals (`M*`, `L*`), `Linecode=` + `length` |
| `Triplex_Lines.DSS` | 1177 | LV triplex, `X*.1.2` -> `SX*.1.2`, `linecode=4/0Triplex`, `length=50 units=ft` |
| `Loads.dss` | 1177 | balanced loads at `SX*`, `kv=0.208`, `pf=0.97`, `model=1`, `Vminpu=.88` |
| `LoadXfmrCodes.dss` | 9 + 1177 | XfmrCodes (5-100 kVA, `Xhl=2.04`, `%Rs=[0.6 1.2 1.2]`, `%noloadloss=.2`) + instances |
| `Capacitors.dss` | 10 | 3x300 kvar (`R20185`), 3x300 (`R42247`), 3x400 (`R42246`) single-phase + 900 kvar 3-phase (`R18242`) |
| `Regulators.dss` / `Transformers.dss` | 3 + 3 | single-phase regulator banks, 115/12.47 kV substation xfmr, source reactor |

Expect ~4.9k buses after positive-sequence collapse (2526 MV records collapse to ~2.5k MV buses,
+1177 `X*`, +1177 `SX*`). The "8500-node" name counts per-phase nodes — carry the IN-02 caveat that
`ieee13.jl` and `ieee123.jl` already carry.

## Deviation from verbatim transcription: one degenerate MV busbar-tie edge (2026-08-21, phase-25 gap closure)

**The committed `src/data/ieee8500_impedances.jl` is NOT a byte-for-byte verbatim transcription of
the vendored source for ONE edge.** Every other entry in `IEEE8500_MV_BRANCH_RX_OHMS` is computed
directly from the source `.dss` text with no reinterpretation.

**The exception:** `Lines.dss` line 4, `New Line.HVMV_Sub_connector bus1=_HVMV_Sub_LSB
bus2=HVMV_Sub_48332 length=0.001 units=km r1=0.001 x1=0.01 ...` — the substation Low Side Bus
busbar tie. Literal reduction gives `r_ohm=1e-6`, `x_ohm=1e-5` (`length=0.001 km` is the source's
own placeholder minimum, not a surveyed span — this is a MODELING PLACEHOLDER for a busbar tie,
not a physical conductor run). At this fixture's own per-unit base (`S_base=0.5 MVA`,
`V_base=12.47 kV`, `Zbase≈311.0 Ω`), that is `r≈3.2e-9 pu` — six orders of magnitude below this
project's own D-13 near-ideal convention (`IEEE123_SWITCH_R=3e-4 pu`/`IEEE123_SWITCH_X=1.5e-4 pu`).

**Why this required a fix:** plan 25-05's noise-floor calibration (see `deferred-items.md` item 1)
found this SAME branch dominates the SOCP cone-residual scan on BOTH IEEE-8500 fixtures at every
tolerance rung — the LinDistFlow SOC-exactness argument needs a strictly-positive `r·l` loss-cost
gradient to drive the squared-current variable to its tight value, and a near-zero-`r` branch has
essentially no such gradient. This is a STRUCTURAL relaxation failure, not numerical noise.

**The fix (this gap-closure task, `scripts/reduce_ieee8500_impedances.jl`'s
`reshape_near_zero_mv_edges!`):** the ONE MV segment whose parsed `r_ohm < 1e-5 Ω` (an explicit,
documented threshold, not a bus-pair-name match — a loud assert requires EXACTLY 1 match) has its
`r_ohm`/`x_ohm` VALUES reassigned, in place, to the D-13 near-ideal Ω-equivalent of
`IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` at THIS fixture's own MV base: `(r=0.09330 Ω, x=0.04665 Ω)`.
The edge KEEPS its native entry in `IEEE8500_MV_BRANCH_RX_OHMS` (same bus pair, same table, same
connectivity — `IEEE8500_REGULATOR_EDGES` is untouched, still 43 entries) — this is a physically
motivated data-shaping decision (busbar ties are not physical lines, and every regulator bank,
the substation transformer, and 38 switch ties in this same fixture already receive the identical
near-ideal treatment via a different mechanism), not a numerical hack.

**Measured effect** (see `deferred-items.md` item 1 for the full before/after): the `ieee8500-mv`
noise-floor calibration went from `tol=1e-6 gap=0.4960 -> tol=1e-8 gap=0.1796` (STALLING, then NaN
at tighter rungs) to `tol=1e-6 gap=0.03128 -> tol=1e-8 gap=0.001141` (shrinking 27x tighter, a 157x
improvement at `tol=1e-8`, and now behaving like genuine numerical noise rather than a structural
floor).

A reader reproducing this table from the vendored source with a literal transcription will get a
DIFFERENT value for `("HVMV_Sub_48332", "_HVMV_Sub_LSB")` than the committed table — this is
intentional and documented here, in `deferred-items.md`, and in the reduction script's own
in-code comments (all three locations point back to each other).

## SUPERSEDING deviation: zero-length/near-zero bus MERGE, replacing impedance fabrication (2026-08-22, quick task 260822-pxb)

**This section supersedes the value-reassignment mechanism described immediately above for the
`HVMV_Sub_connector` edge (append-only — the prose above remains as historical record of the
2026-08-21 interim fix), and additionally documents 2 NEW merges the 2026-08-21 fix did not
cover.** As of this quick task, the committed table is NOT a byte-for-byte verbatim transcription
for THREE edges, all handled by the SAME topological bus-MERGE mechanism (never an impedance
value assignment):

1. **`LN5473436-1` (`bus1=M1142828 bus2=L2674047`, `length=0.0003048 km`, real linecode
   `3PH_H-397_ACSR...`)** — EXACTLY 1.000 ft, an exact imperial round-trip fingerprinting an
   artificial bus-split inserted to attach service transformer `T5260514C`. `M1142828` (remaining
   degree 0: no other real connection) merges into `L2674047` (remaining degree 1: keeps
   `LN5473436-2`'s continuation plus the transformer attachment).
2. **`LN6259981-1` (`bus1=M1009834.2 bus2=L3178969.2`, `length=0.0003048 km`, real linecode
   `1PH-x4_ACSRx4_ACSR`)** — the fixture's ONLY OTHER exact 1.000-ft real-conductor split
   (confirmed: exactly 2 records in the whole file carry `length=0.0003048`), attaching
   `T5355596B`. `M1009834` merges into `L3178969` by the same degree rule.
3. **`HVMV_Sub_connector` (`bus1=_HVMV_Sub_LSB bus2=HVMV_Sub_48332`)** — the same edge described
   above, RE-CLASSIFIED: a substation busbar tie is not a physical conductor at all (unlike (1)
   and (2), which ARE real conductors, just degenerate-length ones), so a merge is even more
   clearly correct here than for (1)/(2). Detected via the SAME `r_ohm < MV_NEAR_ZERO_R_
   THRESHOLD_OHM = 1e-5 Ω` threshold as the 2026-08-21 fix. `_HVMV_Sub_LSB` and `HVMV_Sub_48332`
   are an EXACT degree tie (both remaining degree 1) — the generic resolver's deterministic
   lexicographic tie-break selects `HVMV_Sub_48332` as survivor (`'H'` sorts before `'_'`).

**Why a merge is more faithful than any impedance value, for all three:** two buses genuinely 1 ft
apart, or two named terminals of the same substation busbar, are electrically the SAME node.
Assigning either endpoint an impedance value — however small, however "near-ideal" — invents a
resistance/reactance that a real 1-ft span of 397_ACSR/x4_ACSR conductor does not have (case 1/2),
or that a non-physical busbar splice never had at all (case 3). The 2026-08-21 reshape for case 3
was a reasonable interim stopgap (documented above) but is a strictly less faithful mechanism than
removing the non-physical edge entirely.

**Mechanism (implemented once, reused for all 3 pairs):** `scripts/reduce_ieee8500_impedances.jl`
gained a generic, reusable bus-merge pipeline — `compute_bus_degrees` (bus-name -> degree over the
fully-parsed-but-not-yet-merged topology), `resolve_merge_pairs` (asserts pairwise disjointness;
survivor = strictly greater remaining degree, lexicographic tie-break on an exact tie), and
`apply_merge!` (drops the degenerate edge; renames the survivor onto every remaining
`linecode_recs`/`inline_recs`/`switch_pairs`/`disabled_switch_pairs`/`xfmr_instances`(`mv_base`
only)/`reg_edges` entry; asserts no self-loop appears post-rename). The length-class pairs
((1),(2)) are detected via `detect_length_class_merge_pairs` (an exact-length threshold,
`MV_ZERO_LENGTH_KM = 0.0003048`, asserting exactly 2 matches); the connector ((3)) is detected via
the renamed `merge_near_zero_mv_edges!` (was `reshape_near_zero_mv_edges!`; same `r_ohm` threshold,
same assert-exactly-1 guard, now merging instead of reassigning). The now-dead D-13
value-reassignment constants (`D13_NEAR_IDEAL_R_PU`, `D13_NEAR_IDEAL_X_PU`,
`D13_NEAR_IDEAL_R_OHM_AT_MV_BASE`, `D13_NEAR_IDEAL_X_OHM_AT_MV_BASE`, `IEEE8500_MV_ZBASE_OHM`,
`IEEE8500_MV_S_BASE_MVA`, `IEEE8500_MV_V_BASE_KV`) were removed (grepped whole-file first —
none referenced elsewhere).

**Explicitly NOT merged in this pass ("next tier," no evidence tying them to the measured
SOCP-exactness failure this task addresses):** the 53 `length=0.001 km` inline `r1=1.0/x1=1.0`
records (`CAP_*`-style capacitor-jumper/stub markers — a deliberately artificial placeholder
class, not real short conductor spans, and ~20x MORE resistive than case (1)/(2)'s real 1-ft
spans); the 5 other short-but-non-round real MV segments (`0.000259836`, `0.000383926`,
`0.000560638`, `0.000658611`, `0.000731906`, `0.000842188` km); and Item 5's (`deferred-items.md`)
other 2 SOCP-offender branches (`"M1069310"->"M1069311"`, `"M1108489"->"P829798"`), which are a
DIFFERENT, uncatalogued near-zero-`r` class not addressed by this task.

**Measured effect on bus/branch counts:** MV edge count moved `2477 -> 2474` (3 fewer real MV
edges: 2 length-class drops + 1 connector drop). Headline fixture (`ieee8500_modified()`) moved
`4875/4874 -> 4872/4871` buses/branches; MV-only fixture (`ieee8500_mv_modified()`) moved
`2521/2520 -> 2518/2517`. Both service transformers (`T5260514C`, `T5355596B`) are confirmed
reattached to their survivors (`L2674047`, `L3178969`) with load intact (total `IEEE8500_LOAD_KW`
sum unchanged — no `SX*` load bus is touched by any of the 3 merges). The D-08 head `smax`
invariant (`≈55.0 pu`, the unique branch touching `IEEE8500_ROOT_BUS = "HVMV_Sub_HSB"`) was
explicitly re-verified on both fixtures post-merge and confirmed unbroken — neither merge touches
the root bus or `regxfmr_HVMV_Sub_LSB`. Radiality (`branches == buses - 1`) holds on both fixtures
(`Feeder`'s own `assert_radial` inner-constructor check), confirming no self-loop or parallel edge
was silently introduced by any of the 3 merges.

**NON-COMPARABILITY of pre-existing measurement CSVs (a fixture-identity change, not a
solver/tolerance change):** `results/ieee8500_benchmark/density_sweep_full.csv`,
`density_sweep.csv`, `noise_floor_calibration.csv`, and every row of
`results/ieee8500_benchmark/socp_gap_report.csv` predating this quick task were all measured on
the PRE-merge topology (4875-bus headline / 2521-bus MV-only). They are NOT directly comparable to
any measurement taken after this task — the underlying network itself changed (3 fewer buses),
not the solver, tolerance, or model formulation. See this quick task's `SUMMARY.md` for the
re-measured 3-point `socp_gap_report` before/after table on the NEW (post-merge) topology.

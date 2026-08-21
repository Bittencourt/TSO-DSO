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

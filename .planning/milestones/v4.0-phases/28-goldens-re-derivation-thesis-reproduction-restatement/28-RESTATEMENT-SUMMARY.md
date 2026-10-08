# Phase 28 Restatement Summary

One table of every headline old->new value restated this phase (FIX-11), with the named cause
of each change. "Old" is the pre-Phase-26/27 (v2.1/v3.0-era) value or characterization; "New"
is the value measured this session against the corrected Phase 26/27 model. See
`28-FINDINGS.md` for full per-plan narrative and `28-CROSS-PHASE-AUDIT.md` for the mechanical
golden-move audit this restatement is built on.

| Finding | Old | New | Cause | Phase/Plan |
|---|---|---|---|---|
| REPRO-01 DSO-surplus sign flip (`fit_dso<0`, `acct.dso>0`) | Holds | **Still holds, unchanged** | N/A — re-measured, not affected by any Phase 26/27 fix | 28-02 |
| REPRO-01 prosumer-surplus decrease | Holds | **Still holds, unchanged** | N/A — re-measured, not affected | 28-02 |
| `acct.dso` (DADP DSO surplus) | ≈ +3.725705 | ≈ +3.739374 | FIX-01/FIX-02 (Phase 26): default `ConvexBranchFlow` switched from thesis-literal lower-band restriction to Gan-Low upper-band restriction | 28-02 |
| `fit_dso` (FIT DSO surplus) | ≈ -196.216447 | ≈ -286.107696 | FIX-09/FIX-10 (Phase 27, plan 27-09): `fit_baseline`'s internal settlement moved to a genuine physics-only `ACPowerFlow(; limits=false)`; `fit_prosumer` itself essentially unchanged | 28-02 |
| Aggregate welfare gap (DADP vs FIT, `welfare_dadp` vs `fb.social_fit`) | ≈ +0.045% | ≈ +0.2630% | CODE REVIEW FIX (CR-01, plan 28-05): plan 28-02 restated the three surplus figures above but never recomputed this DERIVED percentage — it moved ~5.9x because `fit_dso`'s magnitude moved (FIX-09/FIX-10). Recomputed by actually running `scripts/thesis_case123_repro.jl`'s live `welfare_delta_pct`; direction unchanged (small, positive, fragile), thesis's own +25% still does not transfer | 28-05 |
| REPRO-01 exactness gate at default `tol_gap=1e-8` | Untested at this exact point pre-Phase-27 | THROWS on `solve_welfare` (gap=4.384e-6) and `fit_baseline` SITE-3 (gap=8.207e-7); verdict PRECISION-ARTIFACT, resolved by the pre-existing `tol_gap` overrides | FIX-08's tighter hybrid exactness floor (Phase 27) | 28-02 |
| REPRO-01 flake rate (20-repeat, `REPRO_TOL_GAP=1e-9`) | 13/20 = 0.650 (all `fit_baseline`) | 1/20 = 0.050 | FIX-09/FIX-10 closed the dominant fragility source | 28-02 |
| REPRO-01 5-point sweep `sign_flip_survives` | `false` (2/5 points) | `true` (5/5 points) | Same cause — v2.1's "knife-edge-fragile" population-scale-sensitivity characterization is **retired by measurement**, not softened or dropped | 28-02 |
| EXACT-04 gate 1 (`assert_socp_exact!`, cone-residual) | Not previously disambiguated from gate 2 | **Exact under BOTH formulations** at the EXACT-04 control point (`pv_scale=1.2`) | Consistent with, citing not re-deriving, PM-01/26-18 | 28-03 |
| EXACT-04 gate 2 (`assert_ac_exact!`, AC-dispatch) | Comment claimed default drives genuine gate-1 inexactness | Default is genuinely gate-2 **INEXACT** (`inexact_hours=6:15`, restriction-induced dispatch-suboptimality); `thesis_literal=true` is gate-2 **EXACT** there — the OPPOSITE of the stale framing | Measured mechanism correction; stale test comment conflated the two gates | 28-03 |
| Default `ConvexBranchFlow()` unconditional gate-1 cone-exactness | Assumed "exact by theorem, always" (Gan-Low Theorem 2) in an early, self-caught draft | **NOT unconditional** — 3/150 highpv sweep grid points genuinely cone-inexact (ratio 8196-9746), rarer than `thesis_literal=true`'s 5/150 (ratio 9727-9872) but real | Full 150-point dual-mode sweep measurement, corrected before commit | 28-03 |
| IEEE-123 formulation dependence (gate 1) | Not previously swept dual-mode | No measurable formulation-dependent difference — near-identical classification counts/ratio ranges under both formulations | Directional choice only matters on the high-impedance-ratio 3-bus substrate, not real (low-impedance) IEEE-123 | 28-03 |
| MPC `realized_welfare`/regret settlement semantics | Pre-27-09 SOCP-based interim settlement prose | Restated to describe FIX-10's truth-settled `realized_welfare` + `forecast_settled_welfare` + `settlement_violations` diagnostic (physics-only `ACPowerFlow(; limits=false)`) | FIX-10 (Phase 27, plan 27-09) | 28-04 |
| MPC fixture overload count (24h `:ieee13` fixture) | Not previously measured/published | **3 of 19 published hours** (abs_hour 10, 13, 14) report a genuine head-branch thermal overload (`max_overload_ratio` ≈ 1.02/1.004/1.001); zero voltage violations | Measured live before publishing (never assumed zero) | 28-04 |
| DLMP `.cone`/`.drop` naming (FIX-07) restatement | Deferred from Phase 27 | **Confirmed already complete** — verification only, no edit needed | FIX-07 (Phase 27, plan 27-04), already fully applied | 28-04 |
| `docs/literate/prosumer_welfare.jl` SOC plot | `DimensionMismatch` crash (undiscovered until this session) | Fixed — truncated to `bvars.soc[1:T]`, matching established convention | Phase 26 FIX-04's `soc[T+1]` extension, never propagated to this page; caught regenerating the full docs build | 28-05 |
| `docs/make.jl` `api.md` HTML size | 600 KiB `size_threshold` (set once, post-v1) | Page organically grew to 676.24 KiB, exceeding it; raised to 1024/800 KiB with headroom | Organic API-surface growth across Phases 9-27 | 28-05 |
| SC-1 audit closing-gate re-run | N/A | 12 attributed + 1 allowlisted (cited, investigated false negative) + 0 unattributed, exit code 0 | Detector's own ±5-line window heuristic; documented allowlist, not a widened window or a test-file edit | 28-05 |
| Full-suite health | Phase 27 close: 30703 pass / 0 fail / 0 error / 5 broken | **Unchanged: 30703 / 0 / 0 / 5** | No regression across any Phase 28 plan's edits | 28-05 |
| Documenter/Literate docs build | Not certified at Phase 27 close | **Green (exit 0)** at Phase 28 close, all 6 phase-touched pages confirmed non-throwing | Two genuine pre-existing bugs found and fixed (see above) | 28-05 |

## Closing paragraph

Every headline result this phase re-measured reproduces its pre-Phase-26/27 qualitative
claim unchanged (the DSO-surplus sign flip, the prosumer-surplus decrease, and — after
disambiguating which of the two exactness gates each historical claim actually referred to —
the EXACT-04 cone-exactness result PM-01/26-18 established). Where a number moved, the cause
is a named, already-shipped Phase 26/27 fix (FIX-01/02's Gan-Low default, FIX-08's tighter
hybrid exactness floor, FIX-09/10's physics-only AC settlement), never an unexplained drift.
Two genuinely positive findings emerged from re-measurement rather than assumption: the v2.1
"knife-edge-fragile" thesis-reproduction characterization is retired (flake rate 13/20->1/20,
sign-flip survival 2/5->5/5), and the EXACT-04 gate-2 mechanism under the default formulation
is the OPPOSITE of what the stale test comment claimed. One genuinely cautionary finding was
also surfaced and NOT softened: the default `ConvexBranchFlow()` is not unconditionally
gate-1 cone-exact (3/150 highpv sweep points), correcting an over-strong claim before it was
ever committed. The phase closes with the full suite at an exact match to the Phase 27
baseline (30703/0/0/5) and a green, exception-free Documenter/Literate docs build.

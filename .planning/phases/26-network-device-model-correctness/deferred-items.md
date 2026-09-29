# Phase 26 — Deferred Items

Discoveries made during plan execution that are real defects but fall outside the discovering
plan's declared file scope. Logged here per the executor's SCOPE BOUNDARY discipline rather than
auto-fixed.

## D-26-01 — Plan 26-03's battery SOC-horizon fix (FIX-04) broke a pre-existing SOCP-exactness
regression on `test/test_pricing_dlmp.jl`'s "uncongested in-bound 2-bus" fixture

**Discovered during:** Plan 26-06 (DLMP `decompose_dlmp` voltage-coefficient re-certification).

**Symptom:** `test/test_pricing_dlmp.jl`'s `@testitem` "dlmp: decompose_dlmp has ≈0
congestion/voltage on an uncongested in-bound 2-bus (PRICE-02)" (lines 219-272) no longer
solves. `solve_welfare` throws inside `assert_socp_exact!`:

```
SOCP relaxation INEXACT: worst gap/(atol+rtol·|cone|)=2.358926267706093 > 1
(rtol=0.0001, atol=1.0e-6; max abs |l·v−(P²+Q²)|=4.38761373278973e-5) — prices REFUSED
(thesis 3.43-3.45; PF-04)
```

This throw happens BEFORE `decompose_dlmp` is ever reached — it is unrelated to
`decompose_dlmp`'s own hard sum-to-price assertion or to `src/pricing/dlmp.jl` in any way.

**Root cause, confirmed by bisection** (extracted each revision via `git archive` into an
isolated scratch dir and re-ran the exact fixture with `julia --project=.`):

| Revision | Result |
|---|---|
| `5939799` (pre-wave-1, before any Phase 26 fix) | PASSES, residual `7.1e-15` |
| `f677965` (26-02 Task 1 — cpydrop sign flip ONLY, FIX-01/02) | PASSES, residual `0.0` |
| `cfa7e6e` (26-03 — "extend battery soc to T+1 with full-horizon recursion", FIX-04) | **FAILS** with the exactness throw above |
| `3d808d4` (current wave-1 base — 26-02/03/04 merged) | **FAILS** identically |

The cpydrop sign flip (26-02, FIX-01/02) is conclusively NOT the cause — it leaves this exact
fixture exact to residual `0.0`. The regression is introduced specifically by 26-03's battery
SOC-horizon change (`PVBattery`'s `soc` vector extended to `1:(T+1)` with the recursion now
covering `t=1:T`, closing on `soc[T+1]`). The fixture's `PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0,
1.0, 1.0, 2.0, 3.0, fill(0.2, T))` (soc0=1.0, Emin=0.0, Emax=2.0 — nominally mid-range headroom)
apparently drives the SOCP relaxation to a genuinely inexact optimum once the new `soc[T+1]`
constraint is added; the exact mechanism (why this specific near-lossless r=x=1e-6, T=3 fixture
loses exactness) was not further diagnosed — out of scope for plan 26-06.

**Why this is out of scope for Plan 26-06:** Plan 26-06's declared `files_modified` is
`src/pricing/dlmp.jl` only. The fix (if any) belongs in `src/devices/PVBattery.jl` or
`src/powerflow/ConvexBranchFlow.jl` (Plan 26-03's or 26-02's territory), or in re-tuning the
test fixture's battery parameters — none of which this plan's scope covers.

**How Plan 26-06 worked around it:** the `decompose_dlmp` voltage-coefficient re-certification
that this specific `@testitem` exists to exercise (the "uncongested in-bound" regime — both
congestion and voltage components ≈0) was independently re-confirmed using a substitute fixture
that avoids `PVBattery` entirely (a `Deferrable` load on a genuinely non-degenerate r=0.01/x=0.02
2-bus feeder — the SAME fixture as plan 26-06's own `<verify>` smoke test): residual `2.2e-16`,
congestion/voltage both `≈1e-13`. See `26-06-SUMMARY.md` and `src/pricing/dlmp.jl`'s header
comment for the full re-certification record.

**Action needed (NOT done here):** before Phase 26 closes (SC-6 "full suite green" policy),
either (a) re-tune `test/test_pricing_dlmp.jl`'s "uncongested in-bound 2-bus" fixture's battery
parameters so it clears the exactness gate again under the corrected `PVBattery`, or (b)
investigate whether 26-03's FIX-04 SOC-horizon change has a genuine, unintended interaction with
SOCP exactness that needs its own fix in `PVBattery.jl`/`ConvexBranchFlow.jl`. This will also
surface in the phase's full `Pkg.test()` run (`test/test_pricing_dlmp.jl` will show a failure or
error at this specific `@testitem`) — the wave-merge/phase-close full-suite step should catch and
route this to whichever plan owns the fix.

**Confidence:** HIGH — reproduced via direct bisection across 4 isolated codebase snapshots, not
inferred from reading code alone.

---

**RESOLVED (Plan 26-10).** Confirmed a precision-floor artifact, NOT a genuine
`PVBattery`/`ConvexBranchFlow` interaction: Clarabel's default `tol_gap=1e-8` on this
near-lossless (`r=x=1e-6`) fixture stops with the SOCP exactness-gate ratio at `4.04` (`>1`,
throws), but the TRUE optimum IS exactly cone-tight — tightening the solver's convergence
tolerance (not the gate) resolves it cleanly with the objective value unchanged to 8+
significant digits across the whole ladder (`47.7991455494916` at `tol_gap=5e-10` vs
`47.79914555186326` at `tol_gap=1e-12`). Both `test_pricing_dlmp.jl` testitems using this
fixture (`:22` "extract_dlmp on a lossless 2-bus", `:221` "decompose_dlmp has ≈0
congestion/voltage on an uncongested in-bound 2-bus") now pass an explicit
`optimizer = select_optimizer(SOCP(); tol_gap_abs = 5e-10, tol_gap_rel = 5e-10)` keyword,
mirroring the `stochastic_welfare.jl` precedent (`5e-10`, already sufficient — no further
sweep needed). `assert_socp_exact!`'s own `atol`/`rtol` gate in `src/models/exactness.jl` is
UNCHANGED (confirmed via `git diff`).

Measured tol_gap ladder on the D-26-01 fixture (this plan's own sweep):

| `tol_gap_abs/rel` | Result | Objective | `socp_maxgap` |
|---|---|---|---|
| `1e-8` (base) | THROWS (ratio 4.04) | — | — |
| `5e-10` (chosen) | OK | `47.7991455494916` | `6.339e-6` |
| `3e-10` | OK | `47.799145551735904` | `3.233e-7` |
| `1e-10` | OK | `47.799145551735904` | `3.233e-7` |
| `3e-11` | OK | `47.799145551735904` | `3.233e-7` |
| `1e-12` | OK | `47.79914555186326` | `6.064e-9` |

Also corrected this deferred item's own stale "uncongested" fixture label (flagged in
`26-POSTMERGE-TRIAGE.md`'s "Latent issues found"): the fixture's `smax=10` head branch is
actually a `:smax`/`:smax_rev`-bearing LIMITED branch (`smax=10 < SMAX_NO_LIMIT=99.0`), not an
interior/unconstrained one — it is merely UN-BINDING (both cones slack) at this fixture's tiny
flow magnitudes. `test_pricing_dlmp.jl`'s own comment for the `:221` item is updated to match.

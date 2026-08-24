---
phase: 19-4q-bess-live-reactive-dual-ascent
reviewed: 2026-08-08T14:23:56Z
depth: standard
files_reviewed: 16
files_reviewed_list:
  - src/TSODSO.jl
  - src/admm/ReactiveMode.jl
  - src/admm/DsoOpt.jl
  - src/admm/AgrOpt.jl
  - src/admm/solve_admm.jl
  - src/devices/AbstractDevice.jl
  - src/devices/FourQuadBESS.jl
  - src/devices/Aggregator.jl
  - src/models/complementarity_4q.jl
  - src/models/welfare_solve.jl
  - test/fixtures_phase19.jl
  - test/test_admm_reactive.jl
  - test/test_aggregator.jl
  - test/test_fourquadbess.jl
  - test/test_ieee123_admm.jl
  - test/test_reactive_mode.jl
findings:
  critical: 1
  warning: 4
  info: 6
  total: 11
status: issues_found
fixes:
  fixed_at: 2026-08-08
  scope: critical_warning
  fixed:
    CR-01: 8c7b455 + 14ed32e
    WR-01: b8b0c64
    WR-02: "3866537"
    WR-03: e304edb
    WR-04: d4364ff
  info_findings: out_of_fix_scope
---

# Phase 19: Code Review Report

**Reviewed:** 2026-08-08T14:23:56Z
**Depth:** standard
**Files Reviewed:** 16
**Status:** issues_found

## Summary

Phase 19 adds the `FourQuadBESS` 4Q device, the widened `q_inject` aggregator contract, the
3-state `ReactiveMode` enum, the LIVE μ-dual-ascent block in `solve_admm`, and the
`assert_4q_complementarity!` certificate. The core ADMM mirror construction (AGR/DSO coupling,
sign derivation, joint stacked stopping rule, independent ρ/ρ_q adaptation) was traced against
the augmented-Lagrangian derivation and is internally consistent; boundary guards are thorough
and fail-loud throughout; no debug artifacts, no hardcoded secrets, no `@assert` violations of
the project convention.

However, the review found one Critical defect — the new 4Q complementarity certificate is
effectively non-protective at the per-unit device scales the committed fixtures actually use
(its absolute `atol` floor dominates the scale-relative term by up to ~5 orders of magnitude) —
plus four Warnings: a composability crash in `FourQuadBESS.contribute!` (named `:cone`
container, only partially documented), a completely untested μ sign convention on a
load-bearing published price, a naming collision between the `μ` kwarg and the new `μ` return
key that violates the phase's own grep-audit rule, and a silent semantic mismatch when
`OFF`/`CERTIFIED` modes are combined with a `q_inject`-carrying device.

## Critical Issues

### CR-01: `assert_4q_complementarity!`'s absolute `atol = 1e-6` floor defeats the certificate at per-unit device scale

> **FIXED — commits `8c7b455` + `14ed32e`.** Defaults re-derived by measurement at the
> committed per-unit scales: `rtol = 1e-4`, `atol = 1e-8` (with `solve_agr!`'s
> `rtol_4q`/`atol_4q` pass-through defaults updated in lockstep, and a new regression test
> pinning the review's two cited escapes — 40%-of-rating legs at IEEE-13 scale, 5% at 2-bus
> scale — as THROWS). Follow-up `14ed32e`: `solve_admm`'s FINAL consolidation re-solve
> (ρ-penalty, `strict = false`) measures a deterministic ≈1.41e-8 product on the IEEE-13 4Q
> fixture (≈2.3e-3·scale² — IPM face co-activation under the penalty), so that call site
> passes the interior-point-loosened `rtol_4q = 1e-3, atol_4q = 1e-7` explicitly, mirroring
> the existing `τ_batt = 1e-3` discipline at the same call site (7.5× margin; still flags
> legs above ~13%/3.5% of rating vs the ~40% pre-fix escape).
> **Deviation from the suggested fix, with measurement:** the literal suggestion
> (`rtol = 1e-6`, `atol = 1e-12`) would FALSELY REJECT the committed fixtures. The docstring's
> ≤1.1e-10 relative floor was measured on a strictly-App.-C-dominated standalone device (both
> legs pinned hard to one face); re-measured at the realistic centralized 2-bus + 4Q network
> optimum (where the effective price sits near the device's indifference point and both legs
> are interior-near-zero) the noise floor is ≈1.2–1.8e-9 ABS at scale 0.02 (rel ≈2.9–4.4e-6),
> ≈4.2–6.3e-8 at scale 0.1 (rel ≈4.2–6.3e-6), and ≈1.9–6.2e-10 at scale 0.0025 (rel up to
> ≈9.9e-5). The new defaults size each term ≈16× above its own measured floor; full provenance
> table in the certificate docstring.

**File:** `src/models/complementarity_4q.jl:96,112`
**Issue:** The violation threshold is `tol = atol + rtol·scale²` with defaults
`atol = rtol = 1e-6` and `scale = max(Pch_max, Pdch_max)`. The defaults were measured on a
fixture with `Pch_max = 4, Pdch_max = 5` (`scale² = 25`), where the relative term
(`rtol·scale² = 2.5e-5`) dominates. But every committed *production-path* fixture is per-unit
scaled far below 1:

- `test/fixtures_phase19.jl` 2-bus fixture: `Pch_max = 0.02` → `scale² = 4e-4` →
  `rtol·scale² = 4e-10`, so `tol ≈ atol = 1e-6`. Simultaneous legs of `p_ch = p_dch ≈ 1e-3`
  (5% of rating each) pass.
- `test/test_ieee123_admm.jl:190` IEEE-13 4Q fixture: `Pch_max = 0.0025` → `scale² = 6.25e-6` →
  `rtol·scale² = 6.25e-12`, so `tol ≈ 1e-6`. Simultaneous legs of ≈`1e-3` — **40% of the device
  rating on each leg** — pass the certificate.

For comparison, `assert_battery_complementarity!` at its loosest (SOCP path, `τ = 1e-3`) would
flag the IEEE-13-scale device at `1e-3·6.25e-6 = 6.25e-9` — the 4Q gate is ~160× more permissive
than the check it claims to be *tighter* than (docstring: "remaining independent of, and TIGHTER
than, `assert_battery_complementarity!`'s SOCP-path τ = 1e-3"). This re-introduces exactly the
scale-dependence failure `welfare_solve.jl`'s WR-02 docstring documents (an absolute threshold
whose protective strength varies with the per-unit base), just in the small-base direction. The
D-08 "honest boundary" regime this certificate exists to catch (round-trip energy-burning under
a negative effective price) would slip through silently on any per-unit-scaled fixture, and the
resulting physically-distorted schedule would flow into published welfare/prices with a clean
certificate.

Note the measured noise-floor data in the docstring itself shows the *relative* floor is
≤ ~1.1e-10 of `scale²` — meaning a purely relative tolerance is fully supported by the
measurement, and the large `atol` is not needed to clear solver noise.

**Fix:** Make the tolerance scale-relative with only a true numerical floor, e.g.:

```julia
function assert_4q_complementarity!(ctx::ModelContext; rtol::Real = 1e-6,
                                    atol::Real = 1e-12, ...)
    ...
    tol = atol + rtol * scale^2   # atol now a genuine machine-noise floor, not the dominant term
```

and re-run the D-07 measurement sweep at the committed fixture scales (0.02 / 0.0025 pu) to
confirm the noise floor clears — the docstring's own relative-floor data (≤1.1e-10·scale²)
indicates `rtol = 1e-6` alone clears it with ~4 orders of margin.

## Warnings

### WR-01: `FourQuadBESS.contribute!` registers a named `:cone` container — device is non-composable (crashes with the network formulation AND with a second `FourQuadBESS` in the same model)

> **FIXED — commit `b8b0c64`.** Cone made anonymous (the `PVBattery` idiom); the test-only
> `JuMP.unregister` workaround in `fixtures_phase19.jl` retired (the `centralized_welfare_4q`
> replica itself is kept — the D-14 measured tolerances were pinned against it); the deferred
> item marked resolved. Verified: two 4Q devices compose in one model, direct `solve_welfare`
> on 4Q-bearing aggregators runs green, and the `:live` cross-validation still matches at the
> pinned tolerances (|ΔW| = 2.19e-5, matching the documented measurement). NOTE: IN-01
> (last-4Q-per-bus overwrite in `q_devices` extraction) is now REACHABLE and remains open
> (Info findings were out of fix scope).

**File:** `src/devices/FourQuadBESS.jl:315`
**Issue:** `@constraint(m, cone[t = 1:T], ...)` claims the JuMP object-dictionary name `:cone`
on the shared model. Two distinct crash surfaces:

1. **ConvexBranchFlow collision** (documented in `deferred-items.md`): any centralized
   `solve_welfare(feeder, ConvexBranchFlow(), aggs)` with a 4Q device throws
   `"An object of name cone is already attached to this model"`. Phase 19-08 chose a test-only
   `JuMP.unregister` workaround (`fixtures_phase19.jl:230`) instead of the source fix the
   deferred item itself says should land "before relying on solve_welfare with a FourQuadBESS".
2. **Self-collision (UNDOCUMENTED):** two `FourQuadBESS` devices in the *same* model — one
   aggregator with two 4Q members (crashes even on the ADMM AGR-OPT path), or ≥2 4Q-bearing
   aggregators in one centralized model (the test workaround unregisters `:cone` only once,
   before the aggregator loop, so the second device still collides). No test, docstring, or
   deferred item mentions this.

The docstring's claim "Mirroring `PVBattery`'s device-level constraints" is inaccurate:
`PVBattery.contribute!` uses *anonymous* constraints (`@constraint(m, [t = 1:T], ...)`), which is
exactly why multiple `PVBattery` instances compose. `FourQuadBESS` already uses anonymous
`@variable` calls — the named constraint is the sole deviation.

**Fix:**

```julia
# anonymous, like every other device-level constraint in this file and in PVBattery:
cone = @constraint(m, [t = 1:T], [d.Smax, p_net[t], q[t]] in SecondOrderCone())
```

This also retires the test-only `JuMP.unregister` workaround in `fixtures_phase19.jl` and lets
`solve_welfare` run directly on 4Q-bearing aggregators.

### WR-02: The μ sign convention is protected by zero committed assertions — a sign flip in `μ_mat` would pass every test

> **FIXED — commit `3866537`.** Committed a real-impedance (`r = x = 0.05`) 2-bus fixture with
> a BINDING apparent-power cone (`Smax = 0.008` < the ~0.0097 pu peak reactive draw) — real
> impedance alone is not enough: an interior free-`q` 4Q device drives its own bus's μ → 0 by
> first-order optimality. New regression item asserts `sign.(res μ) == sign.(dual(:balance_q))`
> on every `|μ_c| > 1e-5` hour (13 at the default seed; 2–13 across a 5-seed sweep, all
> agreeing), plus a magnitude discrimination pin: correct orientation max|Δμ| ≤ 5.5e-5 vs
> flipped ≥ 2.3e-3 (≥42×). Uses the direct `solve_welfare` path unlocked by WR-01.

**File:** `src/admm/solve_admm.jl:750`; `test/test_admm_reactive.jl:285`
**Issue:** `μ_mat = reduce(vcat, (permutedims(-μq[j]) for j in load_nodes))` publishes the
negated internal multiplier as the reactive price. The docstring says this sign was "empirically
verified this plan, on a 2-bus + FourQuadBESS fixture with REAL — non-near-lossless —
impedance", but that fixture was never committed. The only committed test that compares μ values
(`test_admm_reactive.jl:285`, `isapprox(vec(res.μ), μ_c; atol = 1e-7)`) runs on the near-lossless
2-bus fixture where both sides are ≈1e-8 — i.e. `|μ| ≪ atol`, so the assertion passes identically
whether the negation is present, absent, or doubled. The quarantined IEEE-13 item
(`test_ieee123_admm.jl:231`) only checks `res.μ !== nothing`. The λ sign, by contrast, is pinned
by the 2-bus analytic `+λ₀ > 0` regression. A published price whose sign is verified only in an
uncommitted scratch session is exactly the drift risk the project's measurement-before-golden
discipline exists to prevent.
**Fix:** Commit the real-impedance 2-bus sign-pinning fixture from the Task-1 measurement as a
regression test: assert `sign.(res.μ)` matches `sign.(dual.(balance_q))` (centralized) at a
consensus point where `|μ|` is materially above solver noise, mirroring how the λ sign was
pinned.

### WR-03: Return key `μ` collides with the `μ::Real = 10.0` kwarg in the same `solve_admm` signature, violating the phase's own naming-audit rule

> **FIXED — commit `e304edb`.** Return key renamed to the audit's reserved handle `mu_q`
> (internal local `μ_mat` → `mu_q_mat`); docstrings and all four test consumers updated
> (`test_admm_reactive.jl` ×3 + the new WR-02 item, `test_ieee123_admm.jl` ×1). No deprecation
> alias (none suggested; the only consumers were in-repo tests). Verified LIVE returns the
> renamed key and OFF/CERTIFIED keep the stable-`nothing` contract.

**File:** `src/admm/solve_admm.jl:186` (kwarg), `src/admm/solve_admm.jl:774` (return)
**Issue:** `solve_admm(...; μ = 10.0)` — the adaptive-ρ residual-balancing imbalance band —
now returns a NamedTuple whose `μ` key is the converged *reactive price matrix*. The identifier
`μ` therefore means two unrelated quantities in one public signature. This directly contradicts
the convention pinned in `test_admm_reactive.jl:44-55` ("No file in this phase may bind a NEW
value to bare `μ`/`mu`/`MU`; that identifier continues to mean ONLY the adaptive-rho band") —
the internal state was carefully named `μq` to comply, but the public return key was not. The
header even reserves `mu_q` for exactly this purpose ("a scalar/vector CODE HANDLE for the
extracted reactive price"). Any future threading of the reactive price into
`experiments/Scenario.jl` (whose serialized `μ::Float64` field is the band, per the same audit)
would produce a genuine field collision in the DrWatson `savename` schema.
**Fix:** Rename the return key to `μ_q` (or `mu_q`, the audit's reserved handle) alongside
`q_devices`, before external call sites accrete on `res.μ`. The three test reads
(`test_admm_reactive.jl:229,285,354`; `test_ieee123_admm.jl:231`) are the only current consumers.

### WR-04: `OFF`/`CERTIFIED` modes silently drop a `q_inject`-carrying device's reactive injection from the DSO network model — no guard, diverges from centralized

> **FIXED — commit `d4364ff`.** `build_dso_opt` now throws `ArgumentError` (fail-loud, the
> stronger of the review's two options) when `mode != LIVE` and any aggregator carries a
> `FourQuadBESS`, with a message directing the caller to `:live`; `solve_admm` inherits the
> guard through its `build_dso_opt` call. LIVE behavior and all non-4Q OFF/CERTIFIED paths
> verified unchanged; regression item added covering all three non-LIVE spellings (default,
> `:certified`, Bool back-compat `true`).

**File:** `src/admm/DsoOpt.jl:213-228,266-284`; `src/devices/Aggregator.jl:185`
**Issue:** `Aggregator.contribute!` now writes `−Pdc·tanφ + q_inject` into `:Rq` (the device's
reactive decision enters the centralized model), but `build_dso_opt` computes its reactive
closure target `q_draw` from `−Pdc·tanφ` alone in every mode, and under `CERTIFIED` pins
`qag_dso == q_draw` (`DsoOpt.jl:282`) — the device's `q_inject` never reaches the DSO network
model. Consequences when a `FourQuadBESS` is present under `OFF`/`CERTIFIED`:

- The `CERTIFIED` published reactive dual (`dual(:balance_q)`, certified via `assert_no_slack`
  at `solve_admm.jl:698-704`) is priced against a reactive closure that no longer matches the
  centralized model's — welfare/dual cross-validation against `solve_welfare` (or
  `centralized_welfare_4q`) would silently diverge.
- Nothing fails loud: `solve_admm` happily accepts `reactive_consensus = false/true` with
  4Q-bearing aggregators (the final consolidation even runs `check_4q = true` for them,
  `solve_admm.jl:616-617`, signalling the combination is expected to be supported).

This is a semantic trap in a codebase whose stated convention is "genuinely invalid inputs still
fail loud". `CERTIFIED`'s byte-identity to pre-Phase-19 is a fine goal, but pre-Phase-19 had no
device that could carry `q_inject`; the combination is new and undefined.
**Fix:** In `build_dso_opt` (or `solve_admm`), when `mode != LIVE` and any aggregator device
carries a reactive decision (`any(dv -> dv isa FourQuadBESS, agg.devices)` or a
`hasproperty(res, :q_inject)`-based probe), either `throw(ArgumentError(...))` directing the
caller to `:live`, or emit a documented `@warn` that the device's reactive injection is ignored
by the network model under this mode.

## Info

_Info findings were OUT of the `--fix` scope (critical + warning only) and remain open.
Note that IN-01 is now REACHABLE (WR-01's composability fix removed the crash that previously
masked it) — it should be prioritized when Info findings are next triaged._

### IN-01: `q_devices` extraction silently keeps only the last 4Q device per bus

**File:** `src/admm/solve_admm.jl:756-763`
**Issue:** `q_devices[j] = Float64[value(v.q[t]) for t in 1:T]` inside the `for v in ...` loop
overwrites on each matching device — an aggregator with two `FourQuadBESS` members would lose
all but the last trajectory silently. Currently unreachable (two 4Q devices in one AGR model
crash on WR-01's `:cone` self-collision first), but it becomes silent data loss the moment
WR-01 is fixed.
**Fix:** Key by `(bus, device_index)` or collect a `Vector` per bus; or at minimum
`error(...)` on a second match per bus.

### IN-02: Dual residual is a sum of per-block norms, not the documented "ONE stacked norm"

**File:** `src/admm/solve_admm.jl:445`
**Issue:** `s_norm = ρf·sqrt(sq_ds) + ρ_qf·sqrt(sq_ds_q)` is `‖s_p‖ + ‖s_q‖`, while the primal
side (`r_norm = sqrt(sq_r + sq_r_q)`, line 444) and both ε thresholds use genuinely stacked
2-norms. The header and docstring repeatedly claim "ONE stacked norm over BOTH ... coupling
axes". The sum-of-norms upper-bounds the stacked norm, so the stop is conservative (no false
convergence), but the asymmetry contradicts the documentation and slightly tightens the dual
test relative to the stated Boyd form.
**Fix:** `s_norm = sqrt(ρf^2 * sq_ds + ρ_qf^2 * sq_ds_q)`, or amend the comments to say
"sum of per-block dual norms (conservative upper bound on the stacked norm)".

### IN-03: `ρ_q`'s adaptation history is not recorded in the residual ledger

**File:** `src/admm/solve_admm.jl:457,540-566`
**Issue:** `record!` stores `ρf` only (`rho_trace`); under LIVE, `ρ_qf` adapts independently but
leaves no trace, so the ADMM-05 convergence diagnostics cannot show or debug the reactive
penalty schedule (e.g. a ρ_q stuck at `ρ_min` would be invisible).
**Fix:** Extend `AdmmResiduals` with an optional `rho_q_trace` (NaN-padded under OFF/CERTIFIED,
mirroring the existing Phase-6/7 padding idiom), or stash the trace under `dso.ctx.meta`.

### IN-04: Widened contract documents `q_inject::Vector{AffExpr}` but the only implementing device returns `Vector{VariableRef}`

**File:** `src/devices/AbstractDevice.jl:70`; `src/devices/FourQuadBESS.jl:336`
**Issue:** `FourQuadBESS.contribute!` returns `q_inject === vars.q` (a `Vector{VariableRef}`),
not the documented `Vector{AffExpr}`. Harmless today (the aggregator's `AffExpr` accumulator
absorbs it), but a future consumer coded to the documented type (e.g. reading `.terms` directly,
as `test_aggregator.jl:143` does on the *aggregated* value) would `MethodError` on the raw
device return. One of the two should change: document the field as "iterable of affine-compatible
terms (`VariableRef`/`AffExpr`)" or wrap: `q_inject = AffExpr[1.0 * q[t] for t in 1:T]`.

### IN-05: `centralized_welfare_4q` is a weaker gate than the `solve_welfare` it claims to replicate verbatim

**File:** `test/fixtures_phase19.jl:201,269-274`
**Issue:** Two divergences from the "exact step sequence" claim: (a) it passes
`atol_exact = 1e-5` into `assert_socp_exact!`, 10× looser than the `1e-6` default the real
`solve_welfare` path uses; (b) it never runs `assert_4q_complementarity!` on the centralized
solution, so the centralized side of the LIVE cross-validation is uncertified for the very
property the ADMM side gates on. Test-only, but the fixture is the phase's ground truth.
**Fix:** Drop the `atol_exact` override (or default it to `1e-6`) and add
`assert_4q_complementarity!(ctx; T = T)` after the battery check.

### IN-06: Final consolidation refreshes `a` but not `b` under LIVE

**File:** `src/admm/solve_admm.jl:646,654-658`
**Issue:** The final AGR re-solves update `a[j] = r.pag` (fed into the final DSO solve's active
coefficients) but never re-read `value.(qag_live)` into `b[j]` — the final DSO reactive
coefficients (`-μq - ρ_q·b`) use the last *mid-loop* `b`. At consensus the difference is solver
noise, and the comment at 649-653 asserts "a no-op numerically", but the asymmetry with the
active block's own refresh is unexplained and would matter if the final re-solve ever landed on
a different face. Refresh `b[j]` in the same loop that refreshes `a[j]`, for exact symmetry.

---

_Reviewed: 2026-08-08T14:23:56Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

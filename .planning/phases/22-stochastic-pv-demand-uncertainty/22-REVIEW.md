---
phase: 22-stochastic-pv-demand-uncertainty
reviewed: 2026-08-10T00:00:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - src/TSODSO.jl
  - src/experiments/Scenario.jl
  - src/experiments/run_stochastic.jl
  - src/experiments/store.jl
  - src/models/stochastic_welfare.jl
  - src/solver/factory.jl
  - test/fixtures_phase22.jl
  - test/test_stochastic_welfare.jl
  - test/test_stochastic_oos_harness.jl
  - test/test_run_stochastic.jl
  - docs/literate/stochastic_pv_demand.jl
findings:
  critical: 1
  warning: 10
  info: 3
  total: 14
status: issues_found
fixed_at: 2026-08-10
fix_scope: critical_warning
fixed: 11
fix_status: all_in_scope_fixed
---

# Phase 22: Code Review Report

**Reviewed:** 2026-08-10
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

Phase 22 adds a two-stage stochastic extensive-form welfare builder
(`build_stochastic_welfare`), a Parameter-pinned out-of-sample harness
(`StochasticOosHarness`), an independent `run_stochastic` orchestrator, `stoch_*` Scenario
fields, a NAME_MAX filename guard in `store.jl`, and a keyword-override method on
`select_optimizer(::SOCP)`.

The core mathematics were verified against the underlying builders: the nonanticipativity
tie loop (s = 2:S against scenario 1, all `t = 1:T`, transitively tying all S scenarios) is
present; the DADP de-scaling `dual ./ probabilities[s]` is the correct restoration of the
per-scenario price for a `Max Σ p_s·f_s` objective, with the p = 1 degenerate case reducing
to `solve_welfare`'s convention (`priced = aggregators[1].bus`, no sign flip); the PF-04
gate runs per-scenario in a plain loop with per-`ctx` `:pf_vars`, so one scenario's gate
verdict cannot mask another's; the hardcoded 9-name `unregister` list was checked against
all four formulations (`ConvexBranchFlow`, `LinDistFlow`, `DCPowerFlow`, `ACPowerFlow`) and
is currently a superset of every named container each registers, and `JuMP.unregister` is a
`delete!` no-op on absent names.

However, the review found one guaranteed crash on a documented-supported device type
(FourQuadBESS in the OOS harness), a silent nonanticipativity hole reachable through the
public API despite a docstring claiming a guard, a validated-invariant escape via the
aliased `stoch_probabilities` vector, a now-false `savename` uniqueness claim in
`Scenario.jl`, redundant tie constraints that plausibly contribute to the very
interior-point fragility the phase spent a solver-tolerance override fighting, and a D-06
test whose catch-all `ErrorException` handling both permits false passes and makes the
documented `Pkg.test` flake undiagnosable. The central D-05/D-08 pricing math has no
regression test.

## Fix Status (2026-08-10, `/gsd:code-review --fix` pass)

All 11 in-scope findings (1 Critical + 10 Warnings) fixed, one atomic commit each, every
fix verified by a targeted direct `--project=.` script before commit. Info findings
IN-01..IN-03 were OUT of the fix scope and remain open.

| Finding | Status | Commit    | Notes |
|---------|--------|-----------|-------|
| CR-01   | fixed  | `8ffef34` | `haskey(v, :Ppv_param)` guard; FourQuadBESS pinned, no PV handle; regression testitem |
| WR-01   | fixed  | `9263586` | copy-on-construct in the non-empty branch; aliasing regression testitem |
| WR-02   | fixed  | `2816525` | stable FNV-1a `_p<digest>` in `scenario_filename` (non-uniform only, NAME_MAX-guarded); stale docstring claims corrected |
| WR-03   | fixed  | `1bcb8b7` | per-aggregator device-count + per-index device-type congruence; clairvoyant-battery case tested |
| WR-04   | fixed  | `5c4b447` | `q` tied first-stage (D-03); OOS harness `pin_q` + `run_stochastic` pins committed q; PVBattery paths bit-unaffected |
| WR-05   | fixed  | `061f0cb` | `_stoch_solve_held_out!` skip-and-report (NaN + `infeasible_h` mask + @warn); active pins clamped at 0; documented |
| WR-06   | fixed  | `077009e` | trip requires `occursin("SOCP relaxation INEXACT", e.msg)`; per-scale outcomes recorded |
| WR-07   | fixed  | `2cdfbc0` + `de01eb8` | no-trip path logs resolved solver-stack versions; sandbox-resolution diagnosis documented in the test comment (Project/Manifest drift itself is deliberate user-local state, untouched). Follow-up `de01eb8`: the acceptance suite proved the no-trip flake reproduces under `Pkg.test` AND that `import Pkg` is unavailable in the sandbox — introspection now uses `Base.loaded_modules`/`Base.pkgversion`, exception-guarded. A fresh-resolve env was measured resolving JuMP 1.31.1/MOI 1.52.0 vs the root Manifest's 1.30.1/1.51.2 — direct evidence for the resolution-differs mechanism |
| WR-08   | fixed  | `3fb4f9e` | extensive-form solve routed through `solve_with_retry!(model; dual = true)` (allow_local cross-check path keeps direct `assert_solved!`); caller knob documented |
| WR-09   | fixed  | `b816392` | redundant soc tie rows dropped (implied by p_ch/p_dch ties + shared soc0); post-solve soc-agreement testitem (~2.4e-15 dev); D-11 golden re-pinned per measurement-before-golden (`-0.02515629356082627`, 3-run stable) |
| WR-10   | fixed  | `8027c5f` | D-08 S=1 anchor vs `solve_welfare` + D-05 de-scaling probability-invariance testitems |
| IN-01   | open (out of scope) | — | note: WR-02's NEW digest already uses a stable, padded FNV-1a; the pre-existing `Base.hash` fallback suffix remains |
| IN-02   | open (out of scope) | — | |
| IN-03   | open (out of scope) | — | |

Follow-up commit `8a68916` restores JuliaFormatter compliance for the two touched files
that were formatter-clean before the fixes (`store.jl`, `run_stochastic.jl`).

**Full-suite acceptance (2026-08-10, isolated worktree, committed non-drifted env):**
`2752 passed / 0 failed / 4 errored / 3 broken` in 11m22s. Reconciliation against the
phase-22 reference (2708 passed / 1 flaky D-06 fail / 3 pre-existing errored / 3 broken):
the +44 passes are this fix pass's new regression testitems; 3 of the 4 errors are the
documented pre-existing intermittent Clarabel `NUMERICAL_ERROR` items in
`test_experiments.jl` (lines 53/175/196); the 4th was the D-06 no-trip flake REPRODUCING
under `Pkg.test` and then crashing in the new diagnostics branch's `import Pkg` — fixed
in `de01eb8` (on a future no-trip the item now FAILS with full per-scale outcomes +
resolved solver-stack versions, i.e. the reference's known flaky-fail, now
self-diagnosing instead of silent). No Aqua failures (this run used the committed
Manifest, not the drifted developer checkout).

## Critical Issues

### CR-01: `build_stochastic_oos_harness` crashes on FourQuadBESS, a device type its own contract names as supported

**File:** `src/models/stochastic_welfare.jl:610` (also `605-612`, and downstream `src/experiments/run_stochastic.jl:194-196`)
**Issue:** The battery-pin walk selects battery-like devices by `haskey(v, :soc0)` and then
unconditionally reads `v.Ppv_param`:

```julia
if haskey(v, :soc0)
    ...
    push!(ppv_handles, (; bus, Ppv_param = v.Ppv_param))
```

The docstring (lines 487-496) and the struct docs (line 437) explicitly state battery-like
means "`PVBattery`/`FourQuadBESS`". But `FourQuadBESS.contribute!` returns
`vars = (; p_ch, p_dch, soc, q, soc0)` (`src/devices/FourQuadBESS.jl:360`) — there is **no
`Ppv_param` field**. Any aggregator containing a `FourQuadBESS` (a public, exported device
that `Aggregator` accepts, and that `build_stochastic_welfare`'s in-sample tie loop handles
fine) makes `build_stochastic_oos_harness` throw
`ErrorException: type NamedTuple has no field Ppv_param` — a guaranteed crash for an input
the function documents as supported. It is latent only because `build_population(:default)`
happens to construct PVBattery-only populations today; the phase that added FourQuadBESS
(19) exists precisely so populations can carry it. The same walk in
`run_stochastic` (`_stoch_device_with_field(aggs_h, ppv.bus, :Ppv)`) shares the assumption.
**Fix:**
```julia
if haskey(v, :soc0)
    pin_p_ch = @variable(model, [t = 1:T], set = Parameter(0.0))
    pin_p_dch = @variable(model, [t = 1:T], set = Parameter(0.0))
    @constraint(model, [t = 1:T], v.p_ch[t] == pin_p_ch[t])
    @constraint(model, [t = 1:T], v.p_dch[t] == pin_p_dch[t])
    push!(battery_pins, (; bus, pin_p_ch, pin_p_dch))
    if haskey(v, :Ppv_param)                       # PVBattery only; FourQuadBESS has no PV
        push!(ppv_handles, (; bus, Ppv_param = v.Ppv_param))
    end
    ...
```
and in `run_stochastic`, iterate `ppv_handles` as built (already keyed to devices that have
one). Alternatively, narrow the documented contract to PVBattery and throw a clean
`ArgumentError` on a `:soc0`-without-`Ppv_param` device — either way the current
crash-with-confusing-field-error must go.

## Warnings

### WR-01: `Scenario` stores the caller's `stoch_probabilities` vector by reference — post-construction mutation bypasses all validation

**File:** `src/experiments/Scenario.jl:284-309, 330`
**Issue:** The inner constructor validates a non-empty `stoch_probabilities`
(length/positivity/sum-to-1) and then passes the **same array** to `new(...)`. `Scenario` is
an immutable struct, but the field is a mutable `Vector{Float64}` aliased to caller memory:

```julia
p = [0.2, 0.3, 0.5]
s = Scenario(name = "x", stoch_probabilities = p)
p[1] = 99.0        # s.stoch_probabilities now sums to 99.8 — every invariant silently gone
```

This defeats the file's own load-bearing claim ("a `Scenario` can never silently
underdetermine a run", threat T-08-05): `run_stochastic` and `build_stochastic_welfare`
would re-validate and throw, but `savename`/hashing/reproducibility guarantees are keyed to
a value that can change after validation. Every other field is a true primitive; this is
the first mutable field in the struct and the first aliasing hole.
**Fix:** in the inner constructor's non-empty branch, `stoch_probabilities =
copy(stoch_probabilities)` (or `Vector{Float64}(stoch_probabilities)`) before `new(...)`.

### WR-02: `savename` silently drops `stoch_probabilities` — Scenario.jl's "nothing is silently DROPPED" claim is now false, and the filename no longer identifies a Scenario

**File:** `src/experiments/Scenario.jl:8-11, 47-52` (interacts with `src/experiments/store.jl:58-75`)
**Issue:** The file header and struct docstring still claim "every field already sits inside
DrWatson's `default_allowed = (Real, String, SubString, Symbol, TimeType)` filter, so
nothing is silently DROPPED from the generated filename." Phase 22 added
`stoch_probabilities::Vector{Float64}`, which is **not** in `default_allowed` and is
silently omitted from `savename`. Consequence: two `Scenario`s differing only in their
probability vector (exactly the comparison this phase's own D-04 test and literate page
perform — uniform vs `[0.05, 0.15, 0.30, 0.30, 0.20]`) render the **identical** filename
stem. `safe = true` prevents data loss (a `_1` suffix is appended), but
`scenario_filename`'s documented role as "single source of truth" for a run's on-disk
identity is broken: which file is which weighting is no longer recoverable from the name,
and any `collect_results`-style lookup keyed on the name will conflate them.
**Fix:** at minimum, correct the two stale docstring claims and document the dropped field.
Properly: fold a deterministic digest of `stoch_probabilities` into `scenario_filename`
(e.g. append `_p<digest>` when the vector is non-uniform) so filename identity is restored.

### WR-03: Structural-congruence guard is weaker than documented — a device-composition mismatch can produce a SILENT missing nonanticipativity tie (clairvoyant battery)

**File:** `src/models/stochastic_welfare.jl:199-219` vs docstring `132-137` and tie walk `318-328`
**Issue:** The docstring promises `ArgumentError` on "a structural mismatch between
`scenario_aggs[s]` and `scenario_aggs[1]` (differing **device count** or differing bus
order at any aggregator index)". The code checks only the aggregator count and per-index
bus — never the per-aggregator device lists. The tie walk then pairs
`ctxs[s].meta[:agg_device_vars][bus][idx]` blindly against scenario 1's `idx`. Failure
modes for a public-API caller passing composition-mismatched scenarios:

1. scenario s has fewer devices at a bus → `BoundsError` (not the promised `ArgumentError`);
2. reordered devices → `type NamedTuple has no field p_ch` (loud but misleading);
3. **worst**: scenario 1's device at `idx` is a non-battery while scenario s's device at
   `idx` is a battery → `haskey(v1, :soc0)` is false, the loop `continue`s, and scenario
   s's battery is **silently left untied** — that scenario's battery becomes a
   scenario-specific (clairvoyant) recourse variable, and the "two-stage stochastic"
   solution, its welfare, and every de-scaled DADP are quietly wrong.

`run_stochastic`'s populations are congruent by construction, but
`build_stochastic_welfare` is an exported entry point with a documented guard that does not
exist.
**Fix:** extend the congruence loop to compare `length(scenario_aggs[s][k].devices)` and
the battery marker per device index (e.g. `typeof.(devices)` or the `:soc0` marker
positions) against scenario 1, throwing `ArgumentError` on any mismatch.

### WR-04: FourQuadBESS reactive dispatch `q` is NOT nonanticipativity-tied — undocumented partial first-stage

**File:** `src/models/stochastic_welfare.jl:314-328` (doc claims at `29-37`, `111-116`)
**Issue:** The tie loop constrains `p_ch`, `p_dch`, `soc` only. For a `FourQuadBESS`
(`vars = (; p_ch, p_dch, soc, q, soc0)`), the reactive dispatch `q[t]` remains a free
per-scenario recourse variable, so the "battery-like devices are first-stage, SHARED across
scenarios" claim is only true for the active-power half of the device. That may be a
defensible modeling choice (reactive support as real-time recourse), but it is a choice —
and unlike Deferrable, whose exclusion is explicitly documented ("Deferrable is DELIBERATELY
excluded from this tie"), `q`'s exclusion is nowhere stated. A researcher reading "the
battery schedule is tied" will mis-state the information structure of any 4Q-BESS result.
**Fix:** either tie `q` (`@constraint(model, [t = 1:T], vs.q[t] == v1.q[t])` when
`haskey(v1, :q)`) or add one sentence to the D-03 docstring/tie-loop comment declaring
reactive dispatch second-stage recourse by design.

### WR-05: Out-of-sample pin can be infeasible against a held-out draw — `run_stochastic` then throws with no handling or documentation

**File:** `src/experiments/run_stochastic.jl:182-209`; `src/models/stochastic_welfare.jl:605-608`
**Issue:** The in-sample optimal `p_ch[t]` satisfies `p_ch[t] ≤ pv_used_s[t] ≤ Ppv_s[t]` for
every **in-sample** scenario (the tie enforces the min over in-sample PV draws). A held-out
draw whose PV at some hour falls below every in-sample draw makes the pinned equality
`p_ch[t] == pin` collide with `p_ch[t] ≤ pv_used[t] ≤ Ppv_h[t]` — a genuine
`PRIMAL_INFEASIBLE`. `solve_with_retry!` correctly refuses to retry infeasibility and
throws, so a single unlucky held-out draw aborts the whole `run_stochastic` call after the
expensive extensive-form solve. This is the classic committed-first-stage evaluation
problem; the standard treatments (relatively complete recourse, a penalized slack on the
pin, or skip-and-report) are all absent, and neither the docstring's "Guards" section nor
the STOCH-03 accounting mentions the failure mode. On the current small-PV fixtures the
probability is low but nonzero; on high-PV scenarios (`pv_scale` up), it is likely.
(Compounding nit: the pinned values are raw `value.()` reads, so solver noise can pin
`p_ch == -1e-12` against `p_ch ≥ 0` — absorbed by feasibility tolerance today, but
`clamp.(values, 0, Inf)` would be free insurance.)
**Fix:** document the failure mode in `run_stochastic`'s docstring at minimum; better,
catch the infeasible held-out step and either report it (`welfare_h[h] = NaN` + a returned
`infeasible_h` mask) or add a penalized shortfall slack to the pin constraints so realized
welfare honestly prices first-stage overcommitment.

### WR-06: D-06 test accepts ANY `ErrorException` as "PF-04 tripped" — the test can pass for the wrong reason and cannot diagnose its own flake

**File:** `test/test_stochastic_welfare.jl:125-143`
**Issue:** The scan loop's catch is `e isa ErrorException || rethrow()`. But inside
`build_stochastic_welfare`, at least four distinct failures raise `ErrorException`:
`assert_solved!` (any non-OPTIMAL termination — `src/core/status.jl:57`), the internal
residual-size `error(...)`, `assert_socp_exact!` (the one actually under test), and
`assert_battery_complementarity!`. With the new `tol_gap = 5e-10` default making
`ALMOST_OPTIMAL` demonstrably more likely (the phase's own docs page tripped it), a solver
convergence failure at some `pv_scale` sets `tripped = true` and the test **passes without
the PF-04 gate ever firing** — the exact "per-scenario gate isolation" property the item
exists to prove goes unverified. The catch-all also erases the information needed to
diagnose the documented `Pkg.test` flake: when the item fails, nothing records what each
scale actually did (solved-and-exact? almost-optimal? complementarity?).
**Fix:**
```julia
catch e
    e isa ErrorException || rethrow()
    occursin("SOCP relaxation INEXACT", e.msg) || rethrow()   # only the PF-04 gate counts
    tripped = true; trip_pv_scale = pv_scale; break
end
```
and on the no-trip path, collect per-scale outcomes (status / `socp_maxgap`) into the test
failure message.

### WR-07: The D-06 `Pkg.test` flake — the widened scan is a mitigation that cannot address the only mechanism consistent with the observed behavior

**File:** `test/test_stochastic_welfare.jl:106-125` (comment block), repo `Project.toml`/`Manifest-v1.12.toml` (locally modified)
**Issue:** The comment documents that under `Pkg.test()` the scan once tripped at **no**
scale, while identical standalone runs trip at `pv_scale = 2.0` with maxratio ≈ 9688 —
i.e., ~9700× over threshold, a *structural* inexactness, not solver noise. For the widened
scan to still not trip, every 2-scenario solve up to `pv_scale = 1024` must terminate
`OPTIMAL` **and** certify exact under `Pkg.test` — which no amount of Clarabel numerical
jitter explains at that ratio. The only mechanisms consistent with that are (a) materially
different package resolution in the `Pkg.test` sandbox (the working tree has *modified*
`Project.toml`/`Manifest-v1.12.toml`; the project's own memory notes document local
Project.toml drift), changing `generate_profiles`' StableRNG stream or Clarabel itself, or
(b) an in-process state leak the comment says was ruled out but that WR-06's catch-all
makes impossible to actually observe. Widening the scan to 1024× reduces the *chance* of a
repeat only if the mechanism is noise — it does nothing if the sandbox is solving different
data. Classifying this as the "known Clarabel flake class" without evidence risks
normalizing a real determinism defect.
**Fix:** (1) land WR-06's message-discriminating catch plus per-scale outcome logging so the
next occurrence is self-diagnosing; (2) have the test record
`Pkg.dependencies()[...].version` for Clarabel/StableRNGs (or at least
`@info` them) on the no-trip path; (3) reconcile the modified Project/Manifest with what CI
resolves before accepting the flake classification.

### WR-08: `tol_gap = 5e-10` default is fixture-tuned and demonstrably does not generalize; the known-fragile solve bypasses the project's own retry ladder

**File:** `src/models/stochastic_welfare.jl:154-175, 342`; `src/solver/factory.jl:66-90`; `docs/literate/stochastic_pv_demand.jl:36-45`
**Issue:** The factory override itself is clean: `select_optimizer(::SOCP; attrs...)` with
no kwargs is byte-identical to the prior method, later duplicate keys win, and no other
caller is affected — that part is well executed and well documented. The concern is the
chosen default: `5e-10` was selected by sweeping exactly two tiny fixtures (a near-lossless
2-bus and one `r=x=0.05` 3-bus), and the phase's own literate page then demonstrates the
window does not generalize — a perfectly reasonable probability vector
(`[0.1, 0.15, 0.2, 0.25, 0.3]`) trips `ALMOST_OPTIMAL` on `:ieee13`/`T = 9`, and the demo
resorted to hand-selecting a bell-shaped vector that converges. So the shipped default sits
on a knife-edge in both directions (too loose → PF-04 trips; too tight → `ALMOST_OPTIMAL`),
and the one solve empirically known to live on that edge calls `assert_solved!` directly
(`stochastic_welfare.jl:342`) instead of `solve_with_retry!` — the escalating-conditioning
primitive the codebase built (Phase 10) for precisely this failure shape.
**Fix:** route the extensive-form solve through `solve_with_retry!(model; dual = true)` (its
ladder mutates only optimizer attributes, preserving the build-once contract), and/or
document in `build_stochastic_welfare`'s docstring that on `ALMOST_OPTIMAL` the caller's
first knob is `optimizer = select_optimizer(SOCP(); tol_gap_abs = ..., tol_gap_rel = ...)`.

### WR-09: The T redundant `soc` tie rows per scenario make the equality block rank-deficient — a likely contributor to the observed interior-point fragility

**File:** `src/models/stochastic_welfare.jl:321-326`
**Issue:** For each tied battery and each `s in 2:S`, the loop adds `p_ch`, `p_dch`, **and**
`soc` equalities over all `t = 1:T`. But every scenario copy of the same device has the
same `η` and the same `soc0` Parameter value, and each copy carries its own recursion
`soc[t+1] = soc[t] + η·p_ch[t] − p_dch[t]/η` plus `soc[1] == soc0`. Given the `p_ch`/`p_dch`
ties, the entire `soc_s == soc_1` block (T rows per device per scenario) is exactly
linearly dependent on constraints already in the model. Rank-deficient equality blocks are
a classic conditioning hazard for interior-point KKT systems — Clarabel survives them via
static regularization, but at a precision cost. This phase fought two separate
convergence-precision battles (the `tol_gap` knife-edge and the literate page's
`ALMOST_OPTIMAL` probability-vector sensitivity); (S−1)·T·(#batteries) redundant equalities
are a plausible aggravating factor that costs nothing to remove.
**Fix:** drop the `soc` tie (keep `p_ch`/`p_dch`); if belt-and-braces initial-state
agreement is wanted, tie only `soc[1]` (or the `soc0` Parameters), which adds one
non-redundant row instead of T redundant ones. Re-run the tol_gap sweep afterward — the
`5e-10` override may become unnecessary.

### WR-10: The phase's central pricing math — D-05 de-scaling and the D-08 S=1 anchor — has no regression test

**File:** `test/test_stochastic_welfare.jl`, `test/test_run_stochastic.jl` (absence)
**Issue:** Comments throughout `stochastic_welfare.jl` state the D-05 de-scaling and the
D-08 "S=1 with `probabilities = [1.0]` byte-for-byte mirrors `solve_welfare`'s numerical
path" property were "empirically verified this plan" — but no committed test asserts either.
The reviewed test files check: non-uniform probabilities change the objective (item 1),
per-scenario gate isolation (item 2), the congruence guard (item 3), harness build-once and
pin bindingness, seed disjointness, reproducibility, and one welfare-gap golden. Nothing
asserts `build_stochastic_welfare(f, pf, [aggs]; probabilities = [1.0]).dadp[1] ≈
solve_welfare(...)[3]` (the p=1 anchor that pins both the de-scaling denominator and the
no-sign-flip claim), and nothing asserts a de-scaling property under non-uniform weights
(e.g. that `dadp[s]` magnitudes are probability-invariant for identical scenario data). A
future edit to the objective form (say, moving `probabilities[s]` inside
`ctx.meta[:objective]`) would silently corrupt every reported price while passing the whole
current suite.
**Fix:** add one testitem: same fixture, `solve_welfare` vs
`build_stochastic_welfare(...; probabilities = [1.0])`, assert `≈` on welfare and dadp
(tight rtol); optionally a second assertion that duplicating the same scenario data at
`[0.3, 0.7]` yields `dadp[1] ≈ dadp[2]` (de-scaling removes the weights).

## Info

### IN-01: `scenario_filename`'s hash suffix uses `Base.hash` — not stable across Julia versions; minor suffix-length imprecision

**File:** `src/experiments/store.jl:60-74`
**Issue:** `Base.hash(::String)` is deterministic within a Julia version but not guaranteed
across versions (the project tests 1.10 LTS and 1.11+). The same over-length `Scenario`
saved under two Julia versions gets two different fallback filenames, so cross-version
artifact lookup by name silently misses. Also: `string(hash(full); base = 16)` is not
zero-padded (1-16 chars, comment claims 16), and `thisind` snaps to the *start* of the
character containing the budget byte, so the sliced stem can exceed `stem_budget` by up to
3 bytes — both currently absorbed by the 10-byte `safesave_buffer`, so no overflow, just
imprecise accounting.
**Fix:** use a stable digest (`SHA.sha256` prefix, or `bytes2hex`) with explicit padding;
use `prevind(full, ...)` semantics if a strict byte ceiling on the stem is intended.

### IN-02: Hardcoded 9-name `unregister` list couples `stochastic_welfare.jl` to every formulation's private container names

**File:** `src/models/stochastic_welfare.jl:250-254`
**Issue:** The list `(:v, :v̂, :P, :Q, :l, :cone, :vdrop, :cpydrop, :smax)` was verified to
be a superset of the named containers of all four current formulations (LinDistFlow: `v, P,
Q, vdrop`; DCPowerFlow: `P`; ACPowerFlow: `v, P, Q, l, cone, vdrop, smax`), and
`JuMP.unregister` is a `delete!` no-op on absent names — so today this is correct, and a
future drift fails loudly ("An object of name X is already attached"). Still, the coupling
is invisible from the formulation files.
**Fix:** snapshot `keys(object_dictionary(model))` before `contribute!` and unregister the
difference after — removes the hardcoded list and tracks any formulation automatically.

### IN-03: "Held-out PV/demand/ambient draws" over-claims — ambient temperature never varies across scenarios for `:default` populations

**File:** `src/experiments/run_stochastic.jl:16-22, 188-201`; `docs/literate/stochastic_pv_demand.jl:110-112`
**Issue:** `_default_house` builds every scenario's `Thermostatic` from the deterministic
`_TEMPERATURE_PROFILE_24H` (`src/experiments/materialize.jl:134-164`) — no seed dependence.
The Tout re-slide loop in `run_stochastic` therefore re-sets identical values every
held-out iteration (harmless), but the docstring and the literate page both describe the
evaluation as re-scoring against held-out "PV/demand/**ambient**" draws. Only PV and demand
actually vary; ambient is common knowledge across all scenarios.
**Fix:** trim "ambient" from the two claims (or note the Tout channel is plumbed for a
future stochastic-ambient population but currently deterministic).

---

_Reviewed: 2026-08-10_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

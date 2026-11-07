# 42-CASE-A-PROTOCOL — Pre-Registered Case A Welfare-Gain Measurement Protocol

**Phase:** 42-thesis-case-a-magnitude
**Date:** 2026-10-26
**Status:** PRE-REGISTERED (PRE-RUN) — this commit precedes every Case A measurement run of
this phase. No 784-house solve has executed at the time of this commit; no intermediate
result was visible when any constant below was written.

## Amendment policy

This file is **APPEND-ONLY after this pre-run commit**. Any change made after intermediate
results become visible is a new dated `## AMENDMENT (date, reason)` section appended at the
end of this file, committed in its own commit — the original text above it is never edited.
Every CSV row produced by this phase stamps a `protocol_sha` column (the full 40-hex git SHA
of this file's latest commit, returned by `assert_protocol_registered` in
`scripts/lib/case_a_common.jl`), so each measured row is auditable to the exact protocol
version that produced it. Adding a solver rung or an ablation variant value after the pre-run
commit is an amendment, and requires editing the runner script's pre-planned Dict as well —
a deliberate, reviewable act (the `AGR_TOL_RUNGS` friction, generalized).

---

## 1. The welfare-gain definition (the headline, REPRO-03) — SIGN-SAFE

The registered relative welfare gain is **SIGN-SAFE**:

```
Δ%  = 100 · (W_DADP − W_FIT) / |W_FIT|
ΔW  = W_DADP − W_FIT          (reported alongside, every row)
```

This is the `scripts/thesis_case123_repro.jl:337` form. In code (the single definition, in
`scripts/lib/case_a_common.jl`):

```julia
welfare_gain(w_dadp::Real, w_fit::Real) =
    (Δ = w_dadp - w_fit, Δpct = 100 * (w_dadp - w_fit) / abs(w_fit))
```

**THE BAN (explicit):** the naive ratio `W_DADP / W_FIT` is **NEVER reported** — not as the
headline, not as a secondary column, not in a footnote. Welfare is large and NEGATIVE at the
784-house population (≈ −3.78e5, Phase-40 `agreement.csv`), so the naive ratio
**sign-inverts**: with W_FIT = −3.78e5 and W_DADP = −4.725e5 (DADP *worse*), the ratio is
+1.25 — a positive-looking number for a welfare *loss*. This is the PROJECT.md v5.0 Key
Decision ("golden pinned on the sign flip, not the welfare ratio"). The sign-safe form's
denominator is `|W_FIT|`, so the sign of Δ% always equals the sign of ΔW.

**Secondary lenses** (reported, never a replacement for the headline, no new formulation for
any lens):

- the prosumer/DSO surplus split from `welfare_accounting` — including the **DSO-surplus
  sign flip** (FIT DSO surplus negative → DADP positive), the v2.1/v4.0 headline the thesis
  itself frames;
- the DADP-vs-λ₀ price-signal behaviour.

Both are reported as they come out of the existing validated seams. None of them replaces
Δ%/ΔW as the headline, and no new formulation is introduced for any lens.

## 2. Frozen registered configuration (REPRO-04)

Identical to the Phase-40/41 artifacts — **continuity over re-tuning** (POP-06 provenance).
These values are frozen pre-run; none may be re-tuned after any intermediate result is
visible:

| Quantity | Registered value |
|----------|------------------|
| Feeder | `build_feeder(:ieee13)` |
| Power-flow model | `ConvexBranchFlow()` |
| Horizon | T = 24 |
| Price signal | λ₀ = `build_price(:mem, 24, nothing)` |
| Export | `allow_export = true` (both engines — the exactness enabler) |
| Profiles seed | `sub_seed(master, :profiles)` |
| Population seed | `sub_seed(master, :population)` |
| ADMM penalty | ρ = `ADMM().ρ` — **locked, no re-tuning** (a REQUIRED kwarg sourced from the strategy's own default) |
| Population | `build_population(:case_a_784, feeder, :ieee13, profiles, sub_seed(master, :population))` — 784 houses, 10 bus-level aggregators |
| DADP engine | `solve_admm` (published-price path, `dadp == λ`), AGR ladder per §4 |
| FIT leg | `fit_baseline(feeder, pf, aggs; T, λ₀, on_inexact = :report)` — unchanged (batteryless by design, thesis Assumption A4) |
| BLAS | `BLAS.set_num_threads(1)` at every main (row-to-row comparability) |
| Executor defaults | maxiter/tolerances/threads untouched; provenance stamped on every row (`julia_version`, `threads`, `blas_threads`, `seed`, `t_horizon`) |

## 3. Seeds (REPRO-04)

Master seeds **{42 (primary/registered anchor), 43, 44, 45, 46}** — households re-derive via
the POP-02 hash seeding (`sub_seed(master, :profiles)` / `sub_seed(master, :population)`), so
each seed is a full honest re-draw, not a perturbation.

- Reported per seed: absolute gain ΔW and sign-safe relative gain Δ%; plus the mean and
  min–max spread across the seed set.
- **Seed 42 is the continuity anchor** with every prior Case A artifact (Phase-40/41 CSVs).
- **The OFAT ablations (§5) run at seed 42 only.** This is a pre-registered scoping decision:
  spread is measured on the headline; attribution is anchored at the registered seed.

## 4. The AGR solver-precision ladder (the refusal-handling answer)

The 784-house ADMM refusal at iters=80 is a **KNOWN PRECEDENT, not a surprise**: at seed 42
the default rung is REFUSED at iters=80 (battery-complementarity `CertificateError`, twice
committed: `results/case_a_population/scaling_ladder.csv` / `threads_sweep.csv`, and the
Phase-41 `tariff_comparison.csv` case-a-784 `(run)` row — battery complementarity violated at
bus 5, t=16). `gap_1e-10` is the expected certify rung (`agreement.csv`: welfare_admm
−378163.5654, 80 iters, certified, exact_maxgap 2.77e-10, rel-delta 6.22e-7 vs centralized).
**The refusal is DATA, not an exception**: it is recorded as its own status row, then answered
ONLY by this pre-registered ladder — never by loosening a gate, never by re-tuning.

The bounded rung table (exactly `scripts/case_a_agreement.jl:116-126`, `AGR_TOL_RUNGS`):

| step | rung name     | Clarabel attrs on the AGR factory                   | rationale |
|------|---------------|-----------------------------------------------------|-----------|
| 0    | default       | none (byte-identical factory)                       | regression: must reproduce the committed refusal row exactly |
| 1    | gap_1e-10     | tol_gap_abs = 1e-10, tol_gap_rel = 1e-10            | the repo's sanctioned tightening (centralized-leg precedent); expected certify rung at seed 42 |
| 2    | gap_1e-12     | tol_gap_abs = 1e-12, tol_gap_rel = 1e-12            | deepest meaningful gap tightening; tried ONLY if step 1 refused |
| 3    | gapfeas_1e-12 | rung 2 + tol_feas_abs/rel = 1e-12                   | LAST resort; a prior measurement saw tol_feas tightening FAIL — tried ONLY if step 2 refused |

Policy (locked): run in ladder order, **STOP-ON-FIRST-CERTIFIED** (a rung is certified iff
its solve records `converged` with a Real welfare), **HARD STOP after `gapfeas_1e-12`**
regardless of outcome. Invoked via `solve_admm`'s documented `agr_optimizer` seam
(`agr_optimizer = select_optimizer(QP(); rung_attrs...)`; the default rung splats nothing).
Rung keys are plain **String**s — `:gap_1e-10` parses as subtraction (`:gap_1e - 10`) in
Julia and is never used. The exactness gate, the battery τ, and ρ are **NEVER touched**.
Adding a rung requires editing the runner script's Dict (deliberate-act friction). A refused
rung is an honest status row (`error:<Type>`, iters from the error); if every executed rung
refuses, the honest terminal state is the DOCUMENTED NON-CLOSURE.

## 5. FIT-leg refusal policy

A FIT-leg `SolveFailedError` / `CertificateError` / `ConvergenceError` is an **honest status
row** (the committed ieee13-ground FIT INFEASIBLE precedent in
`results/settlement_comparison/tariff_comparison.csv` stands as the example of a recorded
outcome).

The **ONE sanctioned retry**, pre-registered here:

```julia
fit_baseline(feeder, pf, aggs; T, λ₀, on_inexact = :report,
             optimizer = select_optimizer(QP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10))
```

This is the repo's sanctioned solver tightening — the same values as the AGR `gap_1e-10`
rung and the centralized `tol_gap_1e-10` path — and it is a **SOLVER change, never a gate
change**: no exactness-gate tolerance, no battery τ, no magnitude-sanity band is modified.
A still-refused leg after this single retry is a recorded outcome. The **A1/A4
batteryless-FIT asymmetry** (the DADP side carries batteries, the FIT counterfactual is
batteryless by thesis design) is **stated in the writeup, never back-filled**: no battery is
added to the FIT leg, and no correction term is invented.

## 6. Centralized cross-check policy

`solve_welfare` at seed 42 is recorded as the cross-check bound on the headline. On a
`CertificateError` at the default optimizer there is **ONE** sanctioned tightening:

```julia
solve_welfare(feeder, pf, aggs; T, λ₀, allow_export = true,
              optimizer = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10))
```

(the measured sanctioned path — `agreement.csv` records `centralized_optimizer =
"tol_gap_1e-10"`). Every row records **WHICH path** produced it in a
`centralized_optimizer` column (`default` | `tol_gap_1e-10`). The SOC-exactness gate is
never touched; a still-refused centralized solve is a recorded outcome.

## 7. The four REPRO-05 ablation axes — EXACT values, fixed pre-run (no free-form search)

One-factor-at-a-time (OFAT) from the registered configuration. Axis names AND variant values
below are committed pre-run; no other value may be run without a protocol amendment. Recorded
per variant: ΔW and Δ% (the registered sign-safe definition), an honest status, and the
`protocol_sha`.

### (a) `fit_params` — FIT price parameters

| axis | variant | exact value | rationale |
|------|---------|-------------|-----------|
| fit_params | `registered` | FIT_λ_EXPORT = 9.6, FIT_λ_SELF = 5.6 (page-93 constants, `src/pricing/fit.jl:34-36`) | the thesis-faithful registered triple |
| fit_params | `lam_export_half` | λ_export = 4.8 (λ_import = 6.6, λ_self = 5.6 unchanged) | symmetric multiplicative probe (×0.5) |
| fit_params | `lam_export_double` | λ_export = 19.2 (λ_import = 6.6, λ_self = 5.6 unchanged) | symmetric multiplicative probe (×2.0) |

Pre-registered hypothesis: effects are **dispatch-mediated and expected SMALL** — FIT prices
cancel in `social_fit = fa.total_utility − Σ_t λ₀·imports` (`src/pricing/fit.jl:638-643`);
the axis acts only through the FIT-OPT dispatch incentives. Report whatever appears; never
"fix" the definition to make the axis matter.

### (b) `price_range` — λ₀ scalings

| axis | variant | exact value | rationale |
|------|---------|-------------|-----------|
| price_range | `registered` | λ₀ = `build_price(:mem, 24, nothing)` | the registered signal |
| price_range | `scale_0.5` | λ₀ × 0.5, elementwise | symmetric multiplicative probe (×0.5) |
| price_range | `scale_2.0` | λ₀ × 2.0, elementwise | symmetric multiplicative probe (×2.0) |

Unlike axis (a), this changes the **DADP problem itself** → the **full AGR ladder re-runs per
variant**.

### (c) `population` — population scale and fixtures

| axis | variant | exact value | rationale |
|------|---------|-------------|-----------|
| population | `proxy_ieee123` | IEEE-123 `:default`, 1 house per load bus, seed **20260719** = `SEED_IEEE123` of `scripts/thesis_case123_repro.jl:88` — the ≈+0.2630% provenance fixture | the same-fixture restatement of the published proxy figure under the registered definition |
| population | `ieee13_default` | IEEE-13 `:default`, seed **20260718** (the ground-fixture regression seed, `tariff_comparison.jl` `SEED_GROUND`) | the same-feeder proxy point; the committed FIT INFEASIBLE + known battery-certificate refusal statuses are EXPECTED honest rows, recorded as they come |
| population | nested-prefix rungs | seed 42, `_case_a_rung_counts` with fractions `(1/78, 0.125, 0.25, 0.5, 0.75, 1.0)` (`scripts/case_a_scaling.jl:97` `DEFAULT_LADDER_FRACTIONS`), no per-rung re-tuning | the Phase-40 nested-prefix ladder: gain-vs-population-size curve |
| population | `full_784` | the headline row itself — **reused, never re-run** | the 1.0-rung IS the headline measurement |

**Reuse discipline:** rows reused from other CSVs (e.g. `full_784` from `magnitude.csv`,
Phase-40 ladder rungs from `scaling_ladder.csv`) are recorded with `status = "reused"` and a
`note` naming the source CSV/row. `reused` is part of the honest status vocabulary
(provenance-transparent reuse: never re-solved, never fabricated), so this protocol and the
committed-CSV structural tests agree.

### (d) `device_mix` — batteries and PV ownership

| axis | variant | exact value | rationale |
|------|---------|-------------|-----------|
| device_mix | `registered` | the registered 3-device set (Thermostatic + Deferrable + PVBattery), PV 100% | the registered mix |
| device_mix | `batteries_out` | drop `PVBattery` from every house before roll-up | the batteries-out OFAT probe |
| device_mix | `pv_half` | the first 392 houses in `case_a_household_map` order keep the 3-device set; the remaining 392 are Thermostatic+Deferrable only | the PV-ownership-split probe (50%) |

Rebuild mechanics (locked): script-side from the **SAME `_case_a_house` primitives**
(`src/experiments/materialize.jl:456-522`), in `case_a_household_map` order (map-consistent);
the `pv_fraction` kwarg is **NOT used** — it is accepted-for-symmetry only and changes
nothing in that construction. Roll-up stays **10 bus-level aggregators** (the 1:1 guard).
Like axis (b), this changes the DADP problem itself → the **full AGR ladder re-runs per
variant**.

### Leg-independence rule (per axis)

For every axis: the DADP leg is **independent of axis (a)** — axis (a) touches only the FIT
counterfactual, so the seed's certified W_DADP is reused and only `fit_baseline` re-solves.
Axes (b) and (d) re-run the **full ladder per variant**. Axis (c) rungs are their own solves
(no per-rung re-tuning); `full_784` is reused.

## 8. Proxy restatement statement

The **SAME protocol** (same sign-safe gain definition, same code path) re-run on the
IEEE-123 `:default` proxy (`proxy_ieee123`, seed 20260719) reproduces the ≈+0.263% restatement
under the pre-registered definition. Proximity to ≈+0.263% is **REPORTED** (the same order of
magnitude is expected; the underlying seeding differs from `thesis_case123_repro.jl`'s
ad-hoc per-bus construction, so exact equality is neither expected nor required) — **never
gated and never tuned toward**. There is no pass/fail threshold on the proxy figure.

## 9. No-tuning structural guard

1. Axes AND values are committed pre-run (this document, §7).
2. Every intermediate row is committed as an artifact — **no cherry-picking**: refusals,
   infeasibilities, and unremarkable results all land in the CSVs.
3. Any constant introduced after intermediate results are visible requires a
   protocol-amendment commit (§ Amendment policy) AND the corresponding script edit.
4. The phase code review checks that no constant was fit to the +25% target.
5. **"Gap not fully attributed" is an acceptable recorded outcome.** Closing the gap to the
   thesis's +25% is explicitly NOT a success condition — the phase succeeds on the honesty
   of the measurement ("reported honestly, whatever it is", PROJECT.md v5.0), not on the
   size of the gain.

## 10. Golden policy statement

**NO golden is pinned on the measured magnitude.** New goldens only on sign-safe,
reproducible plumbing quantities — e.g. `welfare_gain` known-value algebra anchors (the
`(Δ = 10.0, Δpct = 10.0)` anchor in `test/test_case_a_magnitude.jl`), and the `:slow`
seed-42 REPRODUCIBILITY band planned in 42-06, which is an agreement band between two runs
of the same code — never a magnitude assertion. The knife-edge canary is never re-pinned;
default paths stay byte-identical.

---

## AMENDMENT (2026-10-26, reason: the `gapfeas_1e-12` rung's Clarabel attrs did not exist)

**Trigger.** During the 42-05 price_range/scale_0.5 ladder — the FIRST execution of ladder
step 3 in this repo — the `gapfeas_1e-12` rung crashed with
`FieldError: type Clarabel.Settings has no field tol_feas_abs, available fields: … tol_feas …`
(Clarabel 0.11.1, the pinned solver). The pre-registered attrs
`(tol_feas_abs = 1e-12, tol_feas_rel = 1e-12)` (this file §4, mirroring
`scripts/case_a_agreement.jl:116-126` verbatim) spell feasibility tolerances that the
installed solver's `Settings` struct does not carry.

**Resolution.** The rung's pre-registered INTENT — rung 2's gap tightening PLUS the solver
feasibility tolerance at 1e-12 (the LAST-RESORT rung; §4's rationale column: "a prior
measurement saw tol_feas tightening FAIL") — is executed with the solver's actual field:
`(tol_gap_abs = 1e-12, tol_gap_rel = 1e-12, tol_feas = 1e-12)`. The rung NAME
(`gapfeas_1e-12`), its ladder position (step 3, after `gap_1e-12`), its hard-stop role, and
the stop-on-first-certified policy are UNCHANGED. No exactness gate, no battery τ, no ρ is
touched — this is a SOLVER-factory attribute spelling repair, not a gate change and not a
new rung. The runner script's `AGR_TOL_RUNGS` Dict is edited in the same commit (the
amendment policy's deliberate-act friction). The `default` → `gap_1e-10` → `gap_1e-12`
rungs are untouched and byte-identical. The crashed scale_0.5 attempt's captured rung rows
(default/gap_1e-10/gap_1e-12 refusals at iters=88) were lost to the per-variant write
boundary and are re-measured under this amended protocol version (their `protocol_sha`
stamps this amendment's commit).

---

# Phase 18: Directional Thesis Reproduction - Research

**Researched:** 2026-07-26
**Domain:** Reproducibility/validation of a research welfare result (Julia/JuMP optimization framework), NOT new algorithmic development
**Confidence:** MEDIUM-HIGH on mechanism/seams (all verified by reading + live-executing actual code), MEDIUM on the achievable claim (grounded in fresh empirical probes run this session, but on only one seed/one population draw each)

<user_constraints>
## User Constraints (from CONTEXT.md)

No `CONTEXT.md` exists yet for Phase 18 (`.planning/phases/18-directional-thesis-reproduction/` contained no files before this research pass — confirmed via `ls`). There are therefore no locked decisions, discretion areas, or deferred ideas to copy verbatim. `/gsd:discuss-phase` has not yet run for this phase. The planner should treat everything below as research-derived recommendation, not user-locked decision, until a discuss-phase pass (if any) adds a CONTEXT.md.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REPRO-01 | Literate rung/doc page + gate-then-golden test reproduces the **direction and magnitude-band** of the thesis welfare/surplus result on real data (sign + band, never the exact figure), carrying a fixed "directional, public-data" qualifier phrase | See "Central Research Tension — Answered With Live Numbers" and "Architecture Patterns" (gate-then-golden pattern, welfare/surplus seam). Empirically re-grounds WHICH metric (DSO-surplus sign flip, not aggregate welfare ratio) is actually defensible, and on which fixture. |
| REPRO-02 | Consolidated assumptions/reduction doc page; repeated-run stability checked **before** any new golden is pinned | See "Validation Architecture" (repeated-run stability harness design, informed by a live 8-repeat determinism probe run this session) and "Runtime/Assumptions doc page structure" under Architecture Patterns. |
</phase_requirements>

## Summary

Phase 18 is a **reproducibility/validation** phase, not new modeling work: every seam it needs
(`solve_welfare`, `fit_baseline`, `welfare_accounting`, `extract_dlmp`/`extract_reactive_dlmp`,
`decompose_dlmp`) already exists and is already exercised by `scripts/thesis_caseA.jl` (an
untracked, already-working scaffold) and `test/test_acceptance.jl` (the project's
"gate-then-golden" test convention). No new library, no new solver, no new architecture is
needed. The work is: (1) pick the RIGHT metric and RIGHT fixture to make a defensible
directional claim, (2) promote the scaffold to a literate page + a gate-then-golden test, (3)
write the assumptions/reduction doc page, (4) empirically check repeated-run stability before
pinning a golden band.

**The central finding of this research (obtained by live-executing the actual code this
session, not by inference):** the AGGREGATE social-welfare figure is a **bad, fragile** metric
for the directional claim on this framework's real-data fixtures — on the Phase-17 retuned
real-impedance IEEE-123 fixture the DADP-vs-FIT social-welfare gap is only **+0.045%**
(welfare_dadp=-41035.40 vs social_fit=-41053.71, Δ=+18.31 out of a ~41,000-unit base), and on
the IEEE-13 congestion-driven fixture (both the shipped `:default` population AND the
`ground` calibration `test_acceptance.jl` pins its golden against) the aggregate welfare gap is
**effectively zero-to-negative** (Δ=-1.13 and Δ=-1.08 respectively — the WRONG sign vs the
thesis's claimed +25%). A naive `ratio = welfare_dadp / welfare_fit` on these NEGATIVE-valued
welfare figures is actively misleading: dividing two negative numbers where the numerator is
MORE negative than the denominator still yields `ratio > 1`, the opposite of the intended
"DADP is better" reading — `scripts/thesis_caseA.jl`'s existing `ratio` metric and its
`if ratio < 1.02` branch is not sign-safe.

**However**, this session's live probes found a **much more robust, correctly-signed, and
thesis-faithful** metric that the existing `welfare_accounting` seam already produces for free:
the **DSO-surplus sign flip**. On the real-impedance, Phase-17-retuned IEEE-123 fixture:
FIT's DSO surplus is **-196.22** (a genuine deficit) and DADP's DSO surplus is **+3.73** (a
genuine, if small, surplus) — a true sign flip from negative to positive, exactly mirroring the
thesis's own Case A headline framing ("DSO surplus −$2829→+$439"), not a ratio. Prosumer
surplus simultaneously DECREASES under DADP vs FIT (Δ=-181.63), also matching the thesis's
qualitative direction ("prosumer −68%"). The SAME sign-flip pattern was independently confirmed
on the IEEE-13 congestion fixture (FIT dso=-5.32 → DADP dso=+2.56) even though that fixture's
AGGREGATE welfare gap has the wrong sign — i.e. the DSO-surplus sign flip is the more robust,
cross-fixture-consistent signal, not an IEEE-123-specific artifact.

**Primary recommendation:** target the **real-impedance IEEE-123 fixture** (satisfies the
ROADMAP's literal "real IEEE-123 data ... reactive pricing and real impedances both active"
wording) for the gate-then-golden test, but pin the golden band on the **DSO-surplus sign flip
+ prosumer-surplus decrease** (both already computed by `welfare_accounting`), not on the
aggregate social-welfare ratio. Report the aggregate welfare delta too, but framed as an
absolute (not percentage) delta with an explicit caveat that it is small and comparatively
fragile. Treat the IEEE-13 congestion scaffold (`scripts/thesis_caseA.jl`) as a **secondary,
qualitative-only** cross-check demonstrating the SAME DSO-surplus-flip mechanism on the
congestion-driven regime — not a second gate-then-golden target, since its aggregate-welfare
sign is not currently reproducible and IEEE-13 is out of this milestone's real-impedance scope
(Phase 17 only re-derived IEEE-123 impedances).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| DADP welfare/surplus solve (GLB-CVX SOCP) | Optimization core (`src/models/welfare_solve.jl`) | — | Already exists; Phase 18 only calls it, never modifies it |
| FIT counterfactual baseline | Optimization core (`src/pricing/fit.jl`) | — | `fit_baseline` exists for voltage-relaxed cases; a NEW variant (S_max-relaxed) may be needed for congestion-driven cross-checks |
| Welfare/surplus accounting split | Optimization core (`src/pricing/welfare.jl`) | — | `welfare_accounting` already returns `(social, prosumer, dso[, ratio])`; Phase 18 should consume `dso`/`prosumer` directly, not just `ratio` |
| Reactive DLMP component | Optimization core (`src/pricing/dlmp.jl`) | — | `extract_reactive_dlmp`/`decompose_dlmp(ctx).reactive` already work on a plain `solve_welfare` ctx (no `reactive_consensus` kwarg needed — that kwarg is ADMM-only, see Pitfall 3) |
| Literate doc page (live-executed) | Docs (`docs/literate/*.jl` + `docs/make.jl`) | — | Existing Documenter+Literate pipeline; Phase 18 adds one new source + one new `pages=` entry |
| Gate-then-golden regression test | Test (`test/test_acceptance.jl`-style `@testitem`) | — | Existing convention: hard exactness gate, THEN pinned golden, THEN non-failing thesis cross-check (`broken=`) |
| Repeated-run stability measurement | Scripts (`scripts/*.jl`, DrWatson `results/`) | — | Mirrors `scripts/reactive_flake_rate.jl` + `results/reactive_flake_rate/flake_rate_findings.txt` exactly (N repeats, committed findings artifact) |
| Assumptions/reduction doc page | Docs (`docs/literate/*.jl`, new) | — | No existing convention for a pure-narrative assumptions page (all other literate pages are code-first); recommend a lightly-code-backed page (see Architecture Patterns) |

## Central Research Tension — Answered With Live Numbers

The task poses the central question directly: **is the thesis welfare-improvement SIGN
reproducible on real IEEE-123 data while the SOCP stays exact?** This was answered empirically
this session (not by inference) by running the actual `solve_welfare`/`fit_baseline`/
`welfare_accounting` seams against the exact Phase-17-retuned IEEE-123 fixture
(`test/fixtures_phase7.jl`'s `LOAD_SCALE_IEEE123=0.05`, `PV_SCALE_IEEE123=0.12`,
`DEV_SCALE_IEEE123≈0.0833`, `SEED_IEEE123=20260719`, `φ=0.90`, 85 load-node aggregators from
`ieee123_load_nodes()`) and against the IEEE-13 congestion fixture two ways (the shipped
`:default` DrWatson population AND the `ground` calibration `test_acceptance.jl`'s golden
`GOLDEN_WELFARE=-4823.1598620624` is pinned against — both independently reproduced bit-for-bit
in this session's probes).

### IEEE-123, real impedances, Phase-17-retuned population (`ieee123_modified()` +
`Phase7Fixtures.build_ieee123_aggregators`, `allow_export=true`)

| Quantity | DADP (`solve_welfare`) | FIT (`fit_baseline`) | Δ (DADP − FIT) |
|---|---|---|---|
| Social welfare | -41035.4036 | -41053.7135 | **+18.31 (+0.045%)** — right sign, razor-thin |
| Prosumer surplus | -41039.1293 | -40857.4971 | **-181.63** — decreases under DADP, matches thesis direction |
| DSO surplus | **+3.7257** | **-196.2164** | **+199.94 — genuine sign flip, negative→positive** |
| SOCP exactness (`socp_maxgap`) | 3.060e-07 (exact) | n/a (voltage-relaxed AC-PF) | — |
| Reactive DLMP (mean, hour 12, load buses) | 0.2006 (finite, non-degenerate) | n/a | `decompose_dlmp(ctx).reactive` works directly, no `reactive_consensus` kwarg needed (Pitfall 3) |

`[VERIFIED: live execution, this session]` — reproduced via a throwaway probe script that
copies `test/fixtures_phase7.jl`'s exact population builder inline (the same technique
`scripts/reactive_flake_rate.jl` uses, since `@testmodule` is a no-op outside TestItemRunner)
and calls `solve_welfare`/`fit_baseline`/`welfare_accounting`/`decompose_dlmp` unmodified.

### IEEE-13, congestion-driven (`ieee13_modified()`, two populations)

| Population | DADP social | FIT social | Δ social | DADP dso | FIT dso | Δ dso |
|---|---|---|---|---|---|---|
| `:default` (as shipped in `scripts/thesis_caseA.jl`) | -4823.2755 | -4822.1489 | **-1.13 (wrong sign)** | — | — | — |
| `ground` (`test_ieee13.jl`/`test_acceptance.jl`'s golden calibration) | -4823.1598620624 | -4822.081254 | **-1.08 (wrong sign)** | **+2.5641** | **-5.3222** | **+7.89 — same sign flip** |

`[VERIFIED: live execution, this session]` — the `ground`-population DADP welfare
(-4823.1598620624) matches `test_acceptance.jl:34`'s `GOLDEN_WELFARE` to 10 decimal places,
confirming the probe is a faithful reproduction of the pinned production fixture, not a
divergent reimplementation. Note the congestion-driven fixture's `fit_baseline` (the
voltage-only-relaxed seam) is **INFEASIBLE** on this fixture (thermal/`S_max` also binds — see
Pitfall 2); the numbers above use `thesis_caseA.jl`'s own hand-rolled FIT solve (voltage AND
`S_max` relaxed), which is the ONLY way to get a feasible FIT counterfactual on this
congestion-driven case.

### Interpretation

1. **Aggregate social welfare is NOT a reliable directional metric at current population
   scales on EITHER fixture.** IEEE-123 shows the right sign but a signal (+0.045%) that is
   two-to-three orders of magnitude smaller than the thesis's claimed +25%, and is a similar
   order of magnitude to what a documented near-boundary numerical regime (Phase 17's
   asymmetric voltage-binding finding) could plausibly perturb. IEEE-13 shows the WRONG sign at
   both populations tested. **Do not gate REPRO-01 on the social-welfare ratio.**
2. **The DSO-surplus sign flip (FIT negative → DADP positive) is the robust, correctly-signed,
   cross-fixture-consistent signal**, and it is exactly the thesis's own headline framing (Case
   A: "DSO surplus −$2829→+$439"). It reproduces on BOTH IEEE-13 (congestion, synthetic
   impedances) and IEEE-123 (voltage, real Phase-17 impedances), with a much larger relative
   swing (IEEE-123: -196→+4, a ~200-unit swing; IEEE-13: -5.3→+2.6, a ~8-unit swing) than the
   aggregate welfare delta. Prosumer surplus decreasing under DADP vs FIT is the accompanying,
   also-robust, also-correctly-signed companion fact.
3. **This is a genuinely new finding, not previously documented anywhere in the repo** (Phase
   17's VERIFICATION/SUMMARY only characterize voltage-binding and SOCP exactness, not the
   welfare/surplus direction; `scripts/thesis_caseA.jl`'s own inline comment mischaracterizes
   its IEEE-13 `:default`-population result as "ratio ≈ 1.0, NOT thesis's 1.25" — i.e. "right
   direction, too small," when the live-executed number is actually slightly negative-signed).
   The planner should correct this framing rather than propagate it.
4. **Recommendation for the plan:** target IEEE-123 real-impedance as the PRIMARY gate-then-
   golden fixture (satisfies the literal ROADMAP wording), pin the golden on `(dso_dadp > 0)`
   AND `(dso_fit < 0)` AND `(prosumer_dadp < prosumer_fit)` as the hard sign gates, with a
   PINNED MAGNITUDE BAND on `dso_dadp` (e.g. `0 < dso_dadp < 10` at this population scale,
   informed by the repeated-run stability check below) rather than a percentage. Report the
   aggregate welfare delta as a secondary, explicitly-caveated-as-thin number, never the primary
   gate. Use the IEEE-13 congestion scaffold only as a qualitative, non-gated cross-check
   demonstrating the same mechanism transfers to the (out-of-real-impedance-scope) congestion
   regime — do not attempt to fix its aggregate-welfare sign as part of this phase (that would
   require a population re-calibration exercise the ROADMAP does not scope here).
5. **A genuinely open risk, not resolved by this research:** whether `+18.31`/`+199.94`-scale
   deltas survive a Clarabel/Julia patch bump or a legitimate small population-scale
   perturbation is UNTESTED here (see Validation Architecture — this is exactly what the
   repeated-run/sensitivity check must establish BEFORE the golden band is pinned, per
   REPRO-02).

## Standard Stack

No new libraries are required. This phase composes existing, already-vetted project
dependencies.

### Core (already in `Project.toml`, unchanged by this phase)
| Library | Version (pinned, per CLAUDE.md) | Purpose | Why Standard (here) |
|---------|------|---------|--------------|
| JuMP + Clarabel | 1.30.1 / 0.11.1 | Underlying solve (`solve_welfare`, `fit_baseline`) | Already the project's sole SOCP path; Phase 18 calls it unmodified |
| DrWatson | 2.19.1 | `@quickactivate`, `projectdir`, results provenance | `scripts/thesis_caseA.jl` and `scripts/reactive_flake_rate.jl` both already use this convention |
| CairoMakie | 0.15.13 | Figures for the literate page | `scripts/thesis_caseA.jl` already produces 7 figures this way |
| Documenter + Literate | 1.17.0 / 2.21.0 | Live-executed literate doc page | `docs/literate/ieee123_impedances.jl` is the template (see Architecture Patterns) |
| TestItems/TestItemRunner | 1.0.0 / 1.1.5 | Gate-then-golden `@testitem` | `test/test_acceptance.jl` is the template |

### Package Legitimacy Audit

**Not applicable — this phase introduces zero new external packages.** Every dependency used
(JuMP, Clarabel, DrWatson, CairoMakie, Documenter, Literate, TestItemRunner) is already present
in the committed `Project.toml`/`Manifest-v1.12.toml` and was vetted in prior phases (v1.0/v2.0
milestones). The `slopcheck`/registry-verification gate in the standard research protocol is
skipped per its own instructions ("required whenever this phase installs external packages") —
this phase installs none.

## Architecture Patterns

### System Architecture Diagram

```
                     ┌─────────────────────────────────────────────┐
                     │   ieee123_modified()  (real Phase-17 Ω data) │
                     │   + Phase7Fixtures.build_ieee123_aggregators │
                     │   (85 load-node houses, retuned LOAD/PV/DEV  │
                     │    scale, φ=0.90 non-degenerate PF)          │
                     └───────────────┬───────────────────┬─────────┘
                                     │                     │
                     ┌───────────────▼─────────┐   ┌───────▼──────────────┐
                     │   solve_welfare(...)     │   │   fit_baseline(...)   │
                     │   (DADP / GLB-CVX SOCP)  │   │   (FIT counterfactual,│
                     │   allow_export=true      │   │    voltage-relaxed AC-│
                     │   → ctx, welfare, dadp   │   │    PF, no battery)    │
                     └───────────────┬──────────┘   └───────┬───────────────┘
                                     │                        │
                     ┌───────────────▼──────────┐            │
                     │ welfare_accounting(ctx)   │            │
                     │ → (social, prosumer, dso) │            │
                     └───────────────┬───────────┘            │
                                     │                        │
                     ┌───────────────▼──────────┐   ┌─────────▼─────────────┐
                     │ decompose_dlmp(ctx)       │   │ fb.social_fit,         │
                     │ .reactive (REACT-02 5th   │   │ fb.prosumer_surplus,   │
                     │ DLMP component, no extra  │   │ fit_dso = social_fit − │
                     │ kwarg needed — Pitfall 3) │   │   prosumer_surplus     │
                     └───────────────┬───────────┘   └─────────┬─────────────┘
                                     │                          │
                                     └───────────┬──────────────┘
                                                  ▼
                            ┌─────────────────────────────────────┐
                            │  GATE-THEN-GOLDEN @testitem:          │
                            │  1. socp_maxgap < tol (exactness gate)│
                            │  2. sign(dso_dadp)=+, sign(dso_fit)=− │
                            │  3. prosumer_dadp < prosumer_fit      │
                            │  4. PINNED band on dso_dadp magnitude │
                            │  5. non-failing thesis cross-check    │
                            │     (broken=, mirrors test_acceptance)│
                            └───────────────┬───────────────────────┘
                                             ▼
                     ┌───────────────────────────────────────────────┐
                     │ docs/literate/thesis_reproduction_ieee123.jl   │
                     │ (promoted from scripts/thesis_caseA.jl SHAPE,  │
                     │  live-executed by docs/make.jl; every number   │
                     │  cited carries the "directional, public-data"  │
                     │  qualifier phrase, sourced from one const)     │
                     └───────────────┬────────────────────────────────┘
                                             │
                     ┌───────────────────────▼────────────────────────┐
                     │ docs/literate/thesis_reproduction_assumptions.jl│
                     │ (REPRO-02: units, reduction fidelity, omissions,│
                     │  population re-tune, PV scenario — narrative,  │
                     │  lightly code-backed)                          │
                     └──────────────────────────────────────────────────┘
```

### Recommended file layout
```
scripts/
  thesis_caseA.jl                        # UNCHANGED (existing, IEEE-13 secondary/qualitative)
  thesis_case123_repro.jl                # NEW — IEEE-123 real-impedance version (mirrors
                                          # thesis_caseA.jl's structure; DADP+FIT+DSO-split+
                                          # reactive DLMP; the promotion SOURCE for the literate
                                          # page, exactly like ieee123_impedances.jl mirrors
                                          # reduce_ieee123_impedances.jl)
  repro_stability_check.jl               # NEW — N-repeat stability harness (mirrors
                                          # scripts/reactive_flake_rate.jl's structure/output
                                          # convention: committed findings .txt under results/)
docs/literate/
  thesis_reproduction_ieee123.jl         # NEW — promoted literate rung/doc page (REPRO-01)
  thesis_reproduction_assumptions.jl     # NEW — consolidated assumptions/reduction page (REPRO-02)
docs/make.jl                             # add 2 new render() entries + 2 new pages= entries
test/
  test_thesis_repro.jl                   # NEW — gate-then-golden @testitem(s) (REPRO-01)
results/
  thesis_case123_repro/                  # figures (DrWatson convention, mirrors thesis_caseA)
  repro_stability_check/                 # committed findings.txt (mirrors reactive_flake_rate)
```

### Pattern 1: Gate-then-golden (the project's established acceptance-test shape)
**What:** exactness/precondition gate FIRST (hard `@test`, would legitimately fail if the
underlying physics broke), THEN a pinned computed golden regression (hard `@test`, catches
future code regressions), THEN a non-failing thesis cross-check (`@test ... broken=` pattern)
that documents the gap to the literature figure without ever failing CI on it.
**When to use:** exactly REPRO-01's "gate-then-golden test... never a point value."
**Example (from `test/test_acceptance.jl:53-95`, verbatim structure to mirror):**
```julia
@test ctx.meta[:socp_maxgap] < 1e-5                          # 1. exactness gate
@test isapprox(res.cost, GOLDEN_WELFARE; rtol = 1e-4)        # 2. pinned computed golden
# ...
gap = abs(v9_16 - THESIS_V9_16)
@test gap < 1e-2 broken = (gap >= 1e-2)                      # 3. non-failing thesis cross-check
```
For Phase 18, step 2's "golden" should be the DSO-surplus sign + magnitude band (see Central
Research Tension), not the aggregate welfare ratio:
```julia
@test ctx.meta[:socp_maxgap] < 1e-5                          # exactness gate (IMPED-03 regime)
@test acct.dso > 0.0                                          # DADP DSO surplus sign (hard)
@test fit_dso < 0.0                                           # FIT DSO surplus sign (hard)
@test acct.prosumer < fit_prosumer                            # prosumer decreases (hard)
@test 0.0 < acct.dso < DSO_BAND_HI                             # PINNED magnitude band, not a point
```

### Pattern 2: `welfare_accounting` + `fit_baseline` composition (the actual welfare/surplus seam)
**What:** `solve_welfare(feeder, pf, aggs; ...)` → `ctx` → `welfare_accounting(ctx; T)` gives
`(; social, dso, prosumer)`; `fit_baseline(feeder, pf, aggs; ...)` gives `(; social_fit,
prosumer_surplus, ...)` and `fit_dso = social_fit - prosumer_surplus` (computed manually — no
`fit_dso` field is returned today).
**Source:** `src/pricing/welfare.jl` (full file), `src/pricing/fit.jl:232-399`.
**Caveat:** `fit_baseline`'s `_relax_voltage` (`src/pricing/fit.jl:217-230`) relaxes ONLY the
voltage band, not branch thermal limits — this is FINE for the IEEE-123 voltage-driven case
(confirmed feasible this session) but INFEASIBLE on the IEEE-13 congestion-driven case (also
confirmed this session — see Pitfall 2), which needs `thesis_caseA.jl`'s manual `S_max`-relaxed
FIT solve instead.

### Pattern 3: Reactive DLMP extraction needs NO `reactive_consensus` kwarg on the centralized path
**What:** `decompose_dlmp(ctx).reactive` / `extract_reactive_dlmp(ctx)` (`src/pricing/
dlmp.jl:127-152`) work directly on a plain `solve_welfare(...)` ctx, because `welfare_solve.jl`
(`src/models/welfare_solve.jl:232-233`) ALWAYS registers `:balance_q` when the formulation has a
reactive channel (`ConvexBranchFlow` does). Confirmed live this session: `decompose_dlmp(ctx).
reactive` returned a finite, non-degenerate value (0.2006 mean at hour 12) on the IEEE-123 real-
impedance ctx with zero extra kwargs.
**Why this matters:** `reactive_consensus::Bool` (Phase 16) is a kwarg of `build_dso_opt`/
`solve_admm` ONLY (the ADMM-decomposed per-hour subproblem path) — it does not exist on, and is
not needed for, `solve_welfare`. REPRO-01's "with reactive pricing... active" success criterion
is satisfied by the CENTRALIZED solve alone; wiring `solve_admm(...; reactive_consensus=true)`
into the literate page is optional secondary validation (mirroring `test_acceptance.jl`'s
centralized-vs-ADMM cross-check pattern), not a requirement.

### Pattern 4: Literate doc page conventions (from `docs/literate/ieee123_impedances.jl`)
- `# # Title` (H1), `# ## Section` (H2) comment-prefixed markdown; live Julia code blocks
  execute during `makedocs` (Documenter's `@example`-equivalent via `Literate.DocumenterFlavor()`).
- Cite external claims inline: `` `[CITED: opendss.epri.com/...]` `` — Phase 18 should use the
  SAME bracket convention for the "directional, public-data" qualifier and for any thesis-figure
  citation (e.g. `[CITED: thesis p.98, Case A]`).
- End with a live, executed call to the real production function (never a re-implementation) —
  Phase 18's page must call the ACTUAL `solve_welfare`/`fit_baseline`/`welfare_accounting`, not a
  hand-copied re-derivation, so the rendered numbers cannot drift from `src/`.
- Register in `docs/make.jl`'s render loop (`for src in (...)`) AND its `pages=` nav tree
  (`docs/make.jl:16-31, 55-68`) — both, or `checkdocs=:exports` / the nav tree silently omits it.

### Anti-Patterns to Avoid
- **Naive `ratio = social_dadp / social_fit` as the directional gate:** mathematically inverts
  sign-intuition when both operands are negative (see Central Research Tension) — do not reuse
  `thesis_caseA.jl`'s `ratio`/`if ratio < 1.02` logic verbatim as the PRIMARY gate; keep it only
  as a secondary, explicitly-caveated report line.
- **Assuming `fit_baseline` "just works" for any feeder:** it only relaxes voltage, not thermal
  limits — verify feasibility per-fixture before wiring it in (confirmed INFEASIBLE on IEEE-13
  congestion fixture this session).
- **Threading `reactive_consensus=true` into `solve_welfare`:** the kwarg does not exist there;
  it is `build_dso_opt`/`solve_admm`-only (Pattern 3).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| DADP/FIT welfare split | A new welfare-accounting function | `welfare_accounting(ctx; T, λ₀, baseline)` (`src/pricing/welfare.jl`) | Already returns `(social, prosumer, dso)` with a HARD surplus-identity assertion (`social == prosumer + dso`) — re-deriving this risks silently dropping the price-transfer cancellation term (documented threat T-05-03) |
| FIT counterfactual (voltage-driven fixtures) | A new FIT solve | `fit_baseline(feeder, pf, aggs; T, λ₀)` (`src/pricing/fit.jl:232-399`) | Already deterministic, gated on `assert_solved!`, magnitude-sanity-checked; confirmed feasible on IEEE-123 this session |
| Reactive price citation | A new reactive-dual extraction | `decompose_dlmp(ctx).reactive` / `extract_reactive_dlmp(ctx)` (`src/pricing/dlmp.jl`) | Already gated by the SAME `_assert_priceable` exactness certificate as the active DADP; already root-degeneracy-tested |
| Repeated-run measurement | A bespoke ad hoc script | Mirror `scripts/reactive_flake_rate.jl`'s exact shape (N repeats × committed `results/.../findings.txt`) | Established, reviewed, already-shipped convention for exactly this kind of "measure and record, do not silently fix" finding |
| Gate-then-golden test shape | A new test idiom | Mirror `test/test_acceptance.jl`'s 3-stage shape (Pattern 1) | Established, reviewed convention; reusing it means the plan-checker/verifier already knows how to evaluate it |

**Key insight:** every mechanical seam Phase 18 needs already exists and is already proven on
at least one fixture. The actual research risk in this phase is not "can we wire the pipeline"
— it is "which metric and which fixture produce a claim that is both TRUE (right sign, real
code, real data) and DEFENSIBLE (survives the repeated-run/sensitivity check)." This research
answers the metric/fixture question; REPRO-02's stability check answers the defensibility
question and must run before any number is pinned.

## Common Pitfalls

### Pitfall 1: The ratio-sign-inversion trap on negative-valued welfare
**What goes wrong:** `ratio = welfare_dadp / welfare_fit` looks like a natural "efficiency
ratio," but when BOTH quantities are negative (a net-cost regime, which both the IEEE-13
`:default`/`ground` and IEEE-123 fixtures are at their current population scales — social
welfare is around -4823/-41035, not the thesis's positive $1457-1976), a numerator that is
MORE negative (i.e. objectively WORSE) than the denominator still produces `ratio > 1`.
**Why it happens:** the thesis's own case studies report POSITIVE welfare figures ($1457,
$1819, $1976); this framework's current population/price calibration produces NEGATIVE
aggregate welfare (utility does not exceed MEM import cost at this scale), so the same ratio
formula silently flips meaning.
**How to avoid:** gate on a DIFFERENCE (`welfare_dadp - welfare_fit`, sign-safe regardless of
the operands' own sign) or, better, on the DSO-surplus sign flip (which genuinely crosses zero
and is immune to this trap).
**Warning signs:** any `ratio` printed close to 1.00 alongside negative `welfare`/`social`
values — always sanity-check the raw difference's sign independently before trusting a ratio.

### Pitfall 2: `fit_baseline`'s voltage-only relaxation is insufficient for congestion-driven fixtures
**What goes wrong:** calling `fit_baseline(feeder, pf, aggs; ...)` on the IEEE-13 `ground`
congestion fixture throws `INFEASIBLE` (confirmed live this session).
**Why it happens:** `_relax_voltage` (`src/pricing/fit.jl:217-230`) widens ONLY the voltage
band; it leaves branch thermal limits (`S_max`) untouched. The IEEE-13 Case A fixture is
congestion-driven — its head-branch `S_max` binds under the FIT schedule's network-blind
dispatch, exactly the thesis's own critique of FIT (an infeasible-if-taken-seriously baseline).
**How to avoid:** for a congestion-driven fixture, either (a) reuse `thesis_caseA.jl`'s manual
FIT solve which ALSO relaxes `S_max` (via `SMAX_NO_LIMIT` branches), or (b) if `fit_baseline`
is to be extended for reuse, add an opt-in `relax_thermal::Bool` kwarg. Since IEEE-13/congestion
is only the SECONDARY/qualitative cross-check for this phase (see Central Research Tension),
option (a) — reuse the existing manual mechanism unmodified — is the lower-risk choice.
**Warning signs:** `INFEASIBLE`/`PRIMAL_INFEASIBLE` from `assert_solved!` inside `fit_baseline`.

### Pitfall 3: `reactive_consensus` is an ADMM-only kwarg, irrelevant to the centralized literate page
Covered fully in Architecture Patterns > Pattern 3. **Warning sign:** attempting to pass
`reactive_consensus=true` to `solve_welfare` will raise a `MethodError` (kwarg does not exist
there) — a quick, loud failure, not a silent misconfiguration, but worth flagging so the
planner doesn't budget a task for wiring it in unnecessarily.

### Pitfall 4: The retuned IEEE-123 population sits inside a documented near-boundary numerical regime
**What goes wrong:** Phase 17's own finding (`test/fixtures_phase7.jl:54-91`,
`17-03-SUMMARY.md`) is that small perturbations to `PV_SCALE_IEEE123` (as small as 0.5%) flip
the SOCP relaxation between exact and inexact unpredictably near this population scale. The
welfare-gap signal this research measured (+0.045% social, DSO swing of ~200 units) has NOT
been tested for sensitivity to population-scale perturbations of similar magnitude.
**Why it happens:** the population re-tune (Plan 17-03) optimized for the JOINT
(voltage-binding, exactness) trade-off, not for welfare-gap robustness — welfare-gap stability
was never a Phase-17 concern.
**How to avoid:** before pinning any golden band, run a small population-scale sensitivity
sweep (e.g. ±2-5% on `LOAD_SCALE_IEEE123`/`PV_SCALE_IEEE123`) and confirm the DSO-surplus sign
flip (not necessarily the exact magnitude) survives — this is a natural extension of the
REPRO-02-mandated repeated-run stability check (see Validation Architecture) and should be
budgeted as its own investigative task, not assumed to be free.
**Warning signs:** a golden band pinned at a SINGLE population-scale point with no sensitivity
evidence.

### Pitfall 5: Repeated-run "stability" in the sense of identical-input value jitter is a non-issue here — the real risk is discrete flake rate
**What goes wrong (a naive expectation):** assuming Clarabel gives different numeric answers
across repeated solves of the IDENTICAL problem (population, seed, λ₀ all fixed) and that this
jitter is the thing to measure.
**What actually happens (confirmed live this session):** 8 back-to-back identical re-solves of
`solve_welfare` on the IEEE-123 real-impedance fixture returned a **bit-for-bit identical**
welfare value every time (`std = 7.276e-12`, i.e. floating-point noise floor). Clarabel's IPM
is deterministic given identical inputs in this single-threaded/single-process environment.
**Why it happens:** there is no randomization in the solve path itself (only aggregate
POPULATION construction is seeded/random, and that seed is fixed per-fixture).
**How to avoid:** REPRO-02's "repeated-run stability" check should NOT be framed as "does the
welfare value jitter across identical re-solves" (it does not, at least not in this
environment) — it should be framed as (a) the DISCRETE flake rate (does `assert_socp_exact!`/
`assert_solved!` occasionally THROW rather than return a slightly different number — mirror
`scripts/reactive_flake_rate.jl`'s exact N≥20-repeat convention, which already exists and
already measures exactly this on IEEE-13/IEEE-123, though NOT yet on the Phase-17-retuned
scale) and (b) cross-environment/cross-version drift risk (a Clarabel/Julia patch bump could
plausibly shift a value near the documented Phase-17 exactness knife-edge — Pitfall 4). Both
(a) and (b) are legitimate "transient numerical noise" concerns the REPRO-02 wording anticipates
even though same-session identical-input jitter is not one of them.
**Warning signs:** a Phase-18 plan that budgets time for "measuring value variance across
identical re-solves" without first checking whether that variance exists at all (it likely does
not, per this session's measurement) — the budget should go to flake-RATE + scale-sensitivity
measurement instead.

## Code Examples

### DADP/FIT/DSO-split composition (verified pattern, this session)
```julia
# Source: src/models/welfare_solve.jl (solve_welfare), src/pricing/welfare.jl
# (welfare_accounting), src/pricing/fit.jl (fit_baseline) — all called unmodified.
ctx, welfare_dadp, _ = solve_welfare(feeder, pf, aggs; T=T, λ₀=λ0, allow_export=true)
acct = welfare_accounting(ctx; T=T)              # (; social, prosumer, dso)
fb   = fit_baseline(feeder, pf, aggs; T=T, λ₀=λ0) # (; social_fit, prosumer_surplus, ...)
fit_dso = fb.social_fit - fb.prosumer_surplus     # NOT a field fit_baseline returns directly

# Sign-safe directional gates (Pitfall 1):
@assert acct.dso > 0.0 && fit_dso < 0.0           # the genuine sign flip
@assert acct.prosumer < fb.prosumer_surplus       # prosumer decreases under DADP
```

### Reactive DLMP citation (no reactive_consensus needed — Pattern 3)
```julia
# Source: src/pricing/dlmp.jl:127-152
d = decompose_dlmp(ctx)   # d.reactive is populated on a PLAIN solve_welfare ctx
```

## State of the Art

| Old Approach (in `scripts/thesis_caseA.jl`) | Recommended Approach (this research) | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `ratio = welfare_dadp / welfare_fit` as the headline directional metric | DSO-surplus sign flip (`acct.dso > 0`, `fit_dso < 0`) + prosumer decrease as the primary gate; aggregate welfare delta reported as a secondary, explicitly-thin number | This research session (2026-07-26) | Avoids the sign-inversion trap (Pitfall 1); matches the thesis's own "DSO surplus X→Y" framing more literally than a ratio does |
| IEEE-13 `:default` population implicitly treated as "close to the thesis, just smaller magnitude" | Explicitly documented as WRONG-SIGN at aggregate-welfare level (though right-signed at the DSO-surplus level) | This research session | Prevents the planner from inheriting a subtly incorrect framing from the existing scaffold's own inline comment |

**Deprecated/outdated:** none — no code needs deprecating; this is a framing correction, not a
code regression.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The DSO-surplus sign flip + prosumer-decrease pattern, measured on ONE seed / ONE population draw per fixture this session, will remain stable under the population-scale sensitivity sweep recommended in Pitfall 4 / Validation Architecture | Central Research Tension, Common Pitfalls #4 | If the sign flips back under a small, legitimate perturbation, the "directional" claim is not defensible at this population scale and a population re-calibration (out of this research's scope) becomes a prerequisite task |
| A2 | No CONTEXT.md / discuss-phase constraints exist for this phase; the recommendations here are research-derived, not user-locked | User Constraints | If a discuss-phase pass later adds a CONTEXT.md that locks a DIFFERENT fixture/metric choice, this research's recommendation must be reconciled, not silently overridden |
| A3 | `fit_baseline`'s voltage-only relaxation is feasible on the IEEE-123 real-impedance retuned fixture at the SPECIFIC seed tested this session (`SEED_IEEE123=20260719`) — not verified across a range of seeds | Architecture Patterns Pattern 2, Pitfall 2 | If a different seed/scale combination makes IEEE-123's FIT baseline infeasible too, the phase would need the same S_max-relaxation fallback as IEEE-13 |

**If this table is empty:** N/A — see rows above.

## Open Questions

1. **Does the DSO-surplus sign flip survive a ±2-5% population-scale perturbation on the
   IEEE-123 real-impedance fixture?**
   - What we know: it holds at the exact Phase-17-retuned point (`LOAD_SCALE=0.05`,
     `PV_SCALE=0.12`), and the same qualitative pattern (sign flip, prosumer decrease) also
     holds on the UNRELATED IEEE-13 congestion fixture at its own separately-tuned scale —
     suggesting the mechanism (DADP prices what FIT ignores, transferring surplus to the DSO)
     is structural, not a coincidence of one specific scale.
   - What's unclear: whether the MAGNITUDE stays bounded away from zero across the population-
     scale range Phase 17 characterized as "genuinely non-monotonic/chaotic" near the
     exactness boundary.
   - Recommendation: budget an explicit sensitivity-sweep task (Wave 0, before the golden is
     pinned) — reuse the `scripts/reactive_flake_rate.jl`-style N-repeat harness shape, but
     sweep population scale instead of repeating identical inputs.

2. **Should the assumptions/reduction doc page (REPRO-02) be its own new literate page, or a
   section appended to the promoted rung page?**
   - What we know: no existing convention for a narrative-only (non-code-first) literate page
     exists in this repo; every current `docs/literate/*.jl` page is code-first with narrative
     woven around live execution.
   - What's unclear: whether Documenter/Literate handles a mostly-prose page gracefully (it
     should — Literate.jl supports pure markdown comment blocks with minimal/no code — but this
     was not tested this session).
   - Recommendation: make it a SEPARATE page (as scoped in the file layout above) so it can be
     linked from multiple places (the rung page, `api.md`) without duplicating the rung page's
     live-execution surface; keep a SMALL amount of live code in it (e.g. re-stating
     `ieee123_load_nodes()`'s count, the retuned scale constants) so it stays "cannot silently
     drift from `src/`" per the project's own Documenter+Literate rationale (`docs/make.jl`'s
     header comment).

3. **Exact wording/placement of the "directional, public-data" qualifier phrase.**
   - What we know: REPRO-01 requires the phrase to appear at EVERY citation of the reproduction
     number; the project's convention for reused strings is a single `const` (e.g.
     `BATT_λ_MIN`, `THESIS_V9_16` in existing test/script files).
   - What's unclear: whether the phrase should be a bare string constant interpolated
     everywhere, or a small helper function (`cite(x) = "$x (directional, public-data)"`) that
     GUARANTEES the phrase appears (grep-able, harder to accidentally omit at a new call site).
   - Recommendation: a single `const REPRO_QUALIFIER = "directional, public-data"` plus a thin
     wrapper function is safer than relying on discipline at each call site — recommend the
     wrapper, and have the plan-checker/verifier grep for the qualifier at every printed/
     reported number.

## Environment Availability

Skipped — this phase has no external dependencies beyond the already-installed Julia
environment (JuMP/Clarabel/DrWatson/CairoMakie/Documenter/Literate/TestItemRunner), all
confirmed working this session by live-executing multiple probe scripts against the real
`Project.toml` environment (`julia --project=. ...` succeeded repeatedly, including a full run
of `scripts/thesis_caseA.jl` producing all 7 figures).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | TestItems 1.0.0 / TestItemRunner 1.1.5 (`test/runtests.jl` → `@run_package_tests`) |
| Config file | `test/runtests.jl` (no separate config; TestItemRunner auto-discovers `@testitem`s) |
| Quick run command | `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib" julia -e 'using TestItemRunner, TSODSO; TestItemRunner.run_tests(joinpath(pwd(), "test"); filter=ti->occursin("thesis_repro", ti.name))'` — use the EXPLICIT-PATH `run_tests` form, not bare `@run_package_tests filter=...` via `-e` (the `.claude/worktrees/` cross-contamination gotcha documented in `local-project-toml-drift.md` and re-confirmed by Phase 17's own verification session) |
| Full suite command | `julia test/runtests.jl` (real file, not `-e`; unaffected by the worktree-path gotcha) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REPRO-01 | IEEE-123 real-impedance DADP-vs-FIT: SOCP exact, DSO surplus sign flip, prosumer decrease, pinned magnitude band | acceptance (`@testitem`, gate-then-golden) | `TestItemRunner.run_tests(...; filter=ti->occursin("thesis_repro", ti.name))` | ❌ Wave 0 — new `test/test_thesis_repro.jl` |
| REPRO-01 | Literate page live-executes during doc build | doc-build gate | `julia --project=docs docs/make.jl` (or CI's Documenter job) | ❌ Wave 0 — new `docs/literate/thesis_reproduction_ieee123.jl` + `docs/make.jl` registration |
| REPRO-01 | Every printed/cited reproduction number carries the qualifier phrase | grep-able static check | `grep -c "directional, public-data" <files>` (manual/plan-checker step, not a `@testitem`) | ❌ Wave 0 |
| REPRO-02 | Assumptions/reduction doc page enumerates the full chain | doc-build gate (page exists + builds) | `julia --project=docs docs/make.jl` | ❌ Wave 0 — new `docs/literate/thesis_reproduction_assumptions.jl` |
| REPRO-02 | Repeated-run / population-scale stability measured BEFORE golden is pinned | script + committed findings artifact (mirrors `scripts/reactive_flake_rate.jl`) | `julia --project=. scripts/repro_stability_check.jl` | ❌ Wave 0 — new script + `results/repro_stability_check/findings.txt` |

### Sampling Rate
- **Per task commit:** quick-run filtered `@testitem` (seconds)
- **Per wave merge:** full suite (`julia test/runtests.jl`, ~minutes — the existing suite takes
  low single-digit minutes per Phase 17's own verification session timings)
- **Phase gate:** full suite green + `docs/make.jl` doc build green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `scripts/repro_stability_check.jl` — the REPRO-02-mandated measurement, run and its
  findings committed BEFORE any golden band is pinned in `test/test_thesis_repro.jl`. Mirror
  `scripts/reactive_flake_rate.jl`'s shape exactly: N≥20 repeats for a discrete flake-rate
  measurement PLUS a small (±2-5%) population-scale sweep to probe the DSO-surplus-sign-flip's
  robustness (Pitfall 4/Open Question 1) — this second half is new, not a copy of the existing
  script's scope.
- [ ] `test/test_thesis_repro.jl` — the gate-then-golden `@testitem`(s) (REPRO-01), written
  AFTER the stability check's findings inform the pinned magnitude band.
- [ ] `docs/literate/thesis_reproduction_ieee123.jl` — promoted literate page (REPRO-01),
  sourced from a NEW `scripts/thesis_case123_repro.jl` (mirrors how
  `docs/literate/ieee123_impedances.jl` mirrors `scripts/reduce_ieee123_impedances.jl`).
- [ ] `docs/literate/thesis_reproduction_assumptions.jl` — consolidated assumptions page
  (REPRO-02).
- [ ] `docs/make.jl` — 2 new `Literate.markdown(...)` render entries + 2 new `pages=` nav
  entries (mirror the exact 2-line-per-page pattern already used for `ieee123_impedances`).

*(No existing test infrastructure covers thesis-reproduction-specific requirements — all of
the above are genuinely new artifacts, though every one of them composes only existing,
already-tested `src/` seams.)*

## Sources

### Primary (HIGH confidence — read in full or live-executed this session)
- `scripts/thesis_caseA.jl` (400 lines, read in full) — the existing scaffold, its own
  documented `:default`-population caveat, and its FIT-with-`S_max`-relaxed mechanism
- `src/pricing/welfare.jl` (full file, 207 lines) — `welfare_accounting`
- `src/pricing/fit.jl:217-399` — `_relax_voltage`, `fit_baseline`
- `src/pricing/dlmp.jl:100-152` — `extract_dlmp`, `extract_reactive_dlmp`
- `src/models/welfare_solve.jl:99-233` — `solve_welfare`, confirms `:balance_q` always
  registered when the formulation carries a reactive channel
- `src/admm/DsoOpt.jl:1-60` — confirms `reactive_consensus` is ADMM-only
- `test/test_acceptance.jl` (full file) — the gate-then-golden convention
- `test/fixtures_phase7.jl` (full file) — the Phase-17-retuned IEEE-123 population scale +
  before/after rationale
- `scripts/reactive_flake_rate.jl` + `results/reactive_flake_rate/flake_rate_findings.txt` —
  the repeated-run/flake-rate measurement convention (N=20, committed findings artifact)
- `docs/literate/ieee123_impedances.jl` (full file) — literate page convention
- `docs/make.jl` (full file) — Documenter/Literate render+nav registration convention
- `.planning/phases/17-real-ieee123-impedances/17-VERIFICATION.md`,
  `17-03-SUMMARY.md` — the asymmetric voltage-binding finding (strong lower band, weak/
  boundary-limited upper band)
- `.planning/phases/16-reactive-power-consensus/16-VERIFICATION.md` — confirms
  `reactive_consensus`'s actual scope and the pre-existing reactive-price extraction mechanism
- `.planning/research/THEORY-thesis.md:169-181` — thesis Case A/B numeric figures
- Five live Julia probe scripts run against the real `--project=.` environment this session
  (DADP/FIT/DSO-split on IEEE-123 real-impedance retuned fixture; DADP/FIT/DSO-split on IEEE-13
  `ground` and `:default` populations; an 8-repeat identical-input determinism check; a full
  live run of `scripts/thesis_caseA.jl` itself) — all outputs quoted verbatim in this document

### Secondary (MEDIUM confidence)
- None beyond the above — no WebSearch/Context7 lookups were needed; this phase's domain is
  entirely internal to the existing codebase, not an external library/framework question.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Mechanism/seams (which functions to call, how they compose): HIGH — every claim verified by
  reading the actual source or live-executing it this session.
- Which metric/fixture to target for the directional claim: MEDIUM-HIGH — grounded in fresh,
  live-executed numbers, but on only ONE seed/population draw per fixture; the recommended
  sensitivity sweep (Open Question 1 / Pitfall 4) has NOT yet been run.
- Long-term stability of the pinned numbers across Julia/Clarabel version bumps: LOW/UNKNOWN —
  explicitly flagged as an open risk, not resolved by this research (that is precisely what
  REPRO-02's repeated-run/stability check exists to establish before pinning).

**Research date:** 2026-07-26
**Valid until:** Treat as valid until the next Clarabel/Julia dependency bump, OR until the
Wave-0 stability/sensitivity check (recommended above) actually runs — whichever comes first.
This is a fast-moving-relative-to-itself research artifact (its own central claim is "verify
this doesn't move before you pin it"), so do not treat the specific numbers quoted here as
permanently stable; treat the MECHANISM/METRIC recommendation as the durable part.

---
phase: 44-aggregator-as-actor
reviewed: 2026-11-02T00:00:00Z
depth: standard
files_reviewed: 31
files_reviewed_list:
  - src/actors/Portfolio.jl
  - src/actors/actor_objective.jl
  - src/actors/efficiency.jl
  - src/admm/AgrOpt.jl
  - src/admm/DsoOpt.jl
  - src/admm/admm_phases.jl
  - src/admm/admm_state.jl
  - src/admm/solve_admm.jl
  - src/devices/Behavioural.jl
  - src/devices/CapabilityTraits.jl
  - src/experiments/materialize.jl
  - src/models/stochastic_welfare.jl
  - src/models/welfare_solve.jl
  - src/pricing/fit.jl
  - src/settlement/SettlementLedger.jl
  - src/settlement/run_inputs.jl
  - src/TSODSO.jl
  - scripts/actor_behaviour_sweep.jl
  - scripts/jet_baseline.txt
  - scripts/README.md
  - docs/literate/aggregator_actor.jl
  - docs/make.jl
  - results/actor_behaviour/actor_behaviour_sweep.csv
  - test/test_actor_default_fence.jl
  - test/test_actor_objective.jl
  - test/test_actor_portfolio.jl
  - test/test_actor_settlement.jl
  - test/test_actor_sweep.jl
  - test/test_behaviour.jl
  - test/test_exports.jl
  - test/expected_broken.txt
findings:
  critical: 0
  warning: 7
  info: 6
  total: 13
status: issues_found
---

# Phase 44: Code Review Report

**Reviewed:** 2026-11-02
**Depth:** standard
**Files Reviewed:** 31
**Status:** issues_found

## Summary

The core math holds up under trace. I found no blockers.

- **Sign conventions.** `pag` is net injection. The AGR coefficient `-λ - ρc + m` makes customers face `DADP + m`. Profit is `-Σ m·pag = Σ m·load`. The centralized `welfare += Σ m·net` matches it. `actor_objective_value = social − profit` is consistent in both paths.
- **Welfare honesty.** `ctx.objective` is never mutated, and `AgrOpt` utilities exclude the margin. `welfare` is always social.
- **Default-path identity.** I traced the default branches by hand:
  - `solve_agr!` adds no extra float op when `linear_offset === nothing`.
  - `DsoOpt` index selection reduces to `j`.
  - `λ_mat` and the other result keys iterate in the same order.
  - The default `AdmmState` is the identity `slot_bus`.
  I found no deviation.
- **Ledger.** Each wedge flow is an adjacent mirror pair, so the running residual returns to exactly `0.0` at every pair boundary. The shared-bus summation in both `settlement_input` adapters sums rather than overwrites.
- **Slot routing.** `has_4q_by_bus`, `_react_outputs`, `q_draw`, the `Rp`/`Rq` bus mapping and the `agr_*` keys are consistently slot-keyed.

The defects are around the edges:

- an unmeasured and vestigial tolerance;
- an RNG seed collision for several sites at one bus;
- the byte-identity fence being inert on CI;
- reproducibility of the committed artifact;
- documentation and measurement claims that the CSV does not support.

## Warnings

### WR-01: Slot-lambda agreement certificate uses a superseded, unmeasured tolerance, and does not check what the docs say it checks

**File:** `src/admm/admm_phases.jl:571-583`, `src/admm/solve_admm.jl:548`
**Issue:**
- `slot_lambda_agree = gap <= slot_tol` receives `slot_tol = tol` from `solve_admm`.
  - The `solve_admm` docstring (lines 102-103) says `tol` is "RETAINED for call-site compatibility but is superseded by the per-unit two-residual stop".
  - The convergence test does not use it.
  - The certificate's pass/fail therefore depends on a vestigial keyword with default `1e-5`.
  - A caller who sets `tol = 1e-1` or `1e-12` flips the flag with no change to the solution.
  - This is a picked tolerance, not a measured one.
- Nothing in the code or docs states how `1e-5` relates to the measured gap.
  - Tests pass against `PortfolioFixtures.TOL_FLOOR`, a different constant.
- The docs (`aggregator_actor.jl` section 3) and the CONTEXT decision say every slot "must agree with the DSO's nodal balance dual".
  - The code compares `λ_s` against the primary slot's multiplier `λ_bus`, not against `dual(balance_p)`.
  - Two slots can agree with each other and still be off the nodal dual if consensus is incomplete.

**Fix:**
- Compute the gap against the DSO balance dual.
  - Use `dual(dso.ctx.constraints[:balance_p][bus, t])` with the `-λ` sign convention.
  - Alternatively, fix the docs to say "agrees with the primary slot".
- Replace the `tol` coupling with a named constant measured from the committed fixtures and documented in the docstring. Alternatively, expose the gap only and drop the boolean.

### WR-02: Opt-out RNG stream collides for several sites at one bus

**File:** `src/experiments/materialize.jl:877`
**Issue:** The draw is `_flex_mix(spec.seed, _BEH_TAG_OPTOUT, a.bus, i)`, with `i` the device index inside the aggregator.
- Phase 44 explicitly allows several site aggregators at one bus (ACTOR-03).
- Two sites at the same bus with the same device layout get identical `(bus, i)` keys.
- They therefore receive identical opt-out outcomes: perfectly correlated opt-out across supposedly independent sites.
- The correlation biases any shared-bus behavioural result.
- `apply_behaviour` is the exogenous-seeding entry point, so the stream must be unique per device.

**Fix:** Add a per-site discriminator.
```julia
for (k, a) in enumerate(aggregators)  # in apply_behaviour, pass k
    ...
u = rand(StableRNGs.LehmerRNG(_flex_mix(spec.seed, _BEH_TAG_OPTOUT, a.bus, k, i)))
```
`k` is the aggregator's positional index.
- This changes draws for existing seeds, which is acceptable because the transform is new.
- Re-measure the sweep CSV afterwards, or keep `k` out of the key for the first aggregator at each bus.

### WR-03: The default-path byte-identity fence is skipped on every Julia version except 1.12.5, including CI

**File:** `test/test_actor_default_fence.jl:164-168`, `test/expected_broken.txt:24`
**Issue:**
- The digest assertion is gated on `VERSION == v"1.12.5"` and `@test_skip` elsewhere.
- CI runs JET and the other jobs on 1.12.7, plus the LTS and 1.11.
- The "byte-identical to v4.0" guarantee, the phase's headline constraint, is therefore enforced only on the author's workstation.
- On CI the item asserts only `!haskey(ctx.meta, :actor)` and the knife-edge canary.
  - The canary is an `isapprox` check with `rtol = 1e-6`, not a bit-for-bit check.
- A skip entry in `expected_broken.txt` records the gap, but nothing runs the fence on a gating environment.

**Fix:**
- Make part of the fence version-independent. For example, compare the default `solve_admm` / `solve_welfare` result against the same call routed through `_force_slot_path=true` and `actors=[all-welfare]` (already done for the legacy-vs-slot equality), and compare keys/shapes.
- Alternatively, capture per-Julia-version digests (1.10, 1.11, 1.12.7) once from the pre-phase commit in a worktree. Without those, the claim "byte-identical on CI" is unverified.

### WR-04: JET baseline grew by 8 entries; supporting docs are stale and one justification comment is inaccurate

**File:** `scripts/jet_baseline.txt:38-55`, `scripts/README.md:34,288`
**Issue:**
- The baseline went from 12 to 20 entries.
- `scripts/README.md` lines 34 and 288 still say "12 entries / 12 signature lines".
- The Group 4 comment cites "objective tables in admm_phases.jl" among the eight reports that "pre-date Phase 44".
  - There were no objective tables in `admm_phases.jl` before this phase. `objectives`, `site_objectives` and `slots` are new.
  - The pre-existing `Nothing`-index sites there are `has_4q_by_bus[j]` / `has_4q_by_bus[jj]` (at 1506ef5 lines 207 and 234).
- The 44-07 summary says the pre-phase run was verified in a temporary worktree (20 reports at 1506ef5, 20 now). That is plausible, but nothing committed lets a reviewer check it.
- Adding eight entries with a comment that mis-names their cause makes the ratchet less trustworthy.
  - It could hide a genuine Phase-44 `getindex(::Nothing)` from the new `objectives[...]` code.
  - Whether it does depends on JET's default-argument analysis, which is not recorded.

**Fix:**
- Correct the comment to name `has_4q_by_bus` as the `admm_phases.jl` source.
- Update the two README counts to 20.
- Commit the pre-phase `jet_check.jl` output, or its signature list, in the phase directory as evidence for the "pre-existing" claim.

### WR-05: Committed CSV has nondeterministic column order and wall-clock columns, so the artifact is not reproducible byte-for-byte

**File:** `scripts/actor_behaviour_sweep.jl:311-333`; `results/actor_behaviour/actor_behaviour_sweep.csv:1`
**Issue:**
- `upsert!` builds each row from `Dict{Symbol,Any}` and iterates `(k, v) in allrows[o]`.
- Dict iteration order is hash-dependent, so the column order is scrambled. See the committed header: `cent_welfare,n_increase_hours,dadp_max,runtime_s,fixture,...`.
- The order is not stable across Julia versions or sessions.
- Re-running the sweep, which the docs advertise as "Reproduce", yields a re-ordered file and a spurious full-file diff.
- `runtime_s` is also a wall-clock measurement.
  - The project requires "reproducible results".

**Fix:**
- Emit a fixed column list, for example a `const COLS = (...)` and `select(df, COLS)`.
- Keep `runtime_s` out of the committed data CSV, or write it to a sidecar file.

### WR-06: The IEEE-123 behaviour block does not discriminate any behaviour effect, and the docs offer an invalid "noise reference"

**File:** `docs/literate/aggregator_actor.jl:133-150`; `results/actor_behaviour/actor_behaviour_sweep.csv` (ieee123 rows)
**Issue:**
- The welfare spread over all 18 behaviour points is about 3e-9 relative.
- `dadp_max` is 8.99992… on every row, equal to the λ₀ peak, so the DSO price is pinned by the frontier price on this fixture.
- The mean DADP moves by at most 8e-6.
- ΔW signs are mixed: for example, adding the rebound constraint at ξ=1 raises welfare by 2.2e-6, which is impossible for a true added constraint.
  - The CSV therefore does not show a measurable ACTOR-04 effect.
  - It shows ADMM slack at roughly 1e-5.
- The docs call the repeated ξ=0 rows "the cleanest noise reference". Those rows are bitwise identical because the solve is deterministic.
  - Their spread is therefore exactly 0 and says nothing about ADMM or solver noise.
  - The honest noise floor is the sign-mixed ΔW above, about 1e-5 absolute.
- The "growth then saturation" sentence for the IEEE-13 wedge asserts a mechanism (piecewise-linear response beyond the last kink) that the sweep never tests.
  - The m=1 and m=2 ΔW values differ by 6e-6, below the measured ADMM slack of about 1e-4 (centralized vs ADMM welfare at m=0), so "saturation" is not resolved from noise.

**Fix:**
- Restate the "noise reference" as the measured noise floor, taken from the sign-mixed anchor-vs-rebound ΔW.
- Say in the page, not only the summary, that the IEEE-123 grid shows no resolvable effect at these device scales.
- Either scale the devices so responses are resolvable, or drop the "saturation" mechanism claim.

### WR-07: The wedge acts as a symmetric price shift, so a net-exporting fixture yields negative "profit" at every m > 0; the docs do not say so

**File:** `docs/literate/aggregator_actor.jl:12-18`; `results/actor_behaviour/actor_behaviour_sweep.csv` (`ledger_total_actor_1` = -0.144, -0.289, -0.578)
**Issue:**
- The wedge is added to the `pag` coefficient for both signs of `pag`.
- Exporting customers therefore receive `DADP + m` per unit sold.
- A "retail margin" paid by the actor on exports is a subsidy.
- The IEEE-13 ground fixture is PV-heavy, so the net injection is positive and the reported actor profit is negative on every `m > 0` row.
- `actor_objective` is then higher than social welfare (-4823.354 vs -4823.498 at m=0.5).
- The code comments disclose this (assumption A6). The page does not: it says "a retail margin per unit of net consumption" and plots "actor profit" with no sign comment.

**Fix:**
- State on the page that the offset is symmetric and that the fixture's actor books a loss.
- Alternatively, report a fixture where the portfolio is a net consumer.
- Optionally, add an asymmetric (buy-only) margin variant, which is the standard retail interpretation.

## Info

### IN-01: New `Union`-typed field on the hot ADMM struct

**File:** `src/admm/AgrOpt.jl:76`
**Issue:**
- `linear_offset::Union{Nothing, Vector{Float64}}` is a new `Union` field on `AgrOpt`.
- It is read in the per-iteration loop of `solve_agr!`.
- Julia union-splits this cheaply, and the default path performs no extra float op.
- Still, a new `Union` field is a candidate for type instability and a JET `getindex(::Nothing)` false positive.
- `Portfolio.objective::AbstractActorObjective` and `Vector{Aggregator}` are likewise abstractly typed.

**Fix:** None required. Optionally, store `Float64[]` (empty means no offset) or a zero-length vector, or accept the `Union` with the current guard.

### IN-02: Dead parameters in the sweep script

**File:** `scripts/actor_behaviour_sweep.jl:217, 264, 350`
**Issue:**
- `admm123(feeder, aggs; actors = nothing)` accepts `actors` and never forwards it.
- The `tol = 1e-6` kwarg passed to `solve_admm` is the superseded keyword (see WR-01). The convergence criterion is `ε_abs`/`ε_rel`.

**Fix:** Remove the dead `actors` parameter and the `tol` keyword.

### IN-03: Comment mismatch in `Behavioural.jl`

**File:** `src/devices/Behavioural.jl:29`
**Issue:** The header says Aggregator reads `hasproperty(d, :phi) && d.phi !== nothing`. The real field and the `Aggregator.jl` read are `φ`. The code is correct and the comment is wrong.

**Fix:** Change `phi` to `φ` in the comment.

### IN-04: Markup typo in the literate page

**File:** `docs/literate/aggregator_actor.jl:13`
**Issue:** `` `ProfitObjective``(m)` `` has a doubled backtick and renders broken Markdown.

**Fix:** `` `ProfitObjective(m)` ``.

### IN-05: MPC, stochastic and FIT rejection of actor inputs is by a missing keyword, not a guard

**File:** `test/test_actor_objective.jl` (last testitem)
**Issue:**
- CONTEXT calls for an `ArgumentError` guard.
- The implementation gives a `MethodError`, because those entries do not accept `actors`, and the test asserts that.
- Behaviour wrappers do get a true `ArgumentError`, through `_reject_unsupported_flex_devices`.
- This is a spec deviation, harmless but undocumented in the summaries.

**Fix:** Note it as a deliberate deviation in the phase summary or docs.

### IN-06: `_find_site` returns the first `===` match

**File:** `src/actors/Portfolio.jl:42-60`
**Issue:**
- `_expand_actors` matches sites by `===`, taking the first hit.
- If the same `Aggregator` object is listed twice in `aggregators`, as a shared-bus population might be, the second entry maps to the first, stays at actor 0, and throws "belongs to no Portfolio".
- That is a confusing message for a reachable input.

**Fix:** Reject duplicate aggregator objects up front with a specific message, or match by position.

---

_Reviewed: 2026-11-02_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

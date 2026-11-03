---
phase: 44-aggregator-as-actor
verified: 2026-11-03T10:37:29Z
status: human_needed
score: 4/4 roadmap success criteria verified; 37/37 plan must-have truths verified; 4/4 ACTOR requirements satisfied
overrides_applied: 0
human_verification:
  - test: "IEEE-123 behaviour sweep is a null result"
    expected: "The researcher accepts that at IEEE-123 fixture scale xi/opt-out/rebound move welfare by about 3.4e-9 relative and mean DADP by about 7.9e-6, with sign-mixed dW of at most 1.41e-4 (ADMM slack). This is a measured null outcome, not an observable ACTOR-04 effect."
    why_human: "Whether a null measurement is enough evidence for the 'see their effect' half of ACTOR-04, or a device-scaled fixture is needed, is a research judgement. The plumbing (wrappers, seeded transform, per-row welfare/prices/settlement/rebound) is verified; the effect size is not resolvable on this fixture."
  - test: "Symmetric retail wedge gives negative actor profit on IEEE-13"
    expected: "The researcher accepts assumption A6: m_t is applied to net injection of both signs, so the net-exporting IEEE-13 portfolio books a loss (-0.1438, -0.2889, -0.5777 for m = 0.5, 1, 2)."
    why_human: "Modelling choice (symmetric vs buy-only margin). Documented in src/actors/actor_objective.jl and in docs/literate/aggregator_actor.jl section 1."
  - test: "JET baseline grew from 12 to 20 entries"
    expected: "The researcher accepts that the 8 added signatures (Groups 4 and 5) predate Phase 44. Phase 44's own 2 DsoOpt reports were fixed by a concrete site_slot Dict, not baselined."
    why_human: "Provenance was measured by the executor on a detached 1506ef5 worktree. I spot-checked it statically: the has_4q_by_bus lookups and blas0 exist at 1506ef5, and ElectricVehicle.jl and feasibility.jl are unchanged by the phase. I did not re-run JET, for memory reasons. Accepting baseline growth is a policy call."
  - test: "SLOT_LAMBDA_AGREE_TOL = 1e-12 is a floor, not 3x the observed value"
    expected: "The researcher accepts the 1e-12 numerical-zero floor. 3x the observed 2.7e-15 would be 8.1e-15. The certificate only reports and never throws."
    why_human: "Deviation from the 'measured, not picked, 3x observed' policy. The rationale is documented next to the constant (src/admm/admm_phases.jl:447-453)."
  - test: "FourQuadBESS as its own slot converges slowly"
    expected: "The researcher accepts that splitting a FourQuadBESS into its own slot at a shared bus needs about 171-189 ADMM iterations versus 4 merged. No parity is claimed."
    why_human: "Performance and usability judgement. Documented in the test/test_actor_portfolio.jl header and the solve_admm docstring ('no parity is claimed'). It is not on the literate page."
  - test: "Centralized ProfitObjective(0) pass-through is not bitwise"
    expected: "The researcher accepts that centralized ProfitObjective(0) matches welfare within 9.3e-11 (3x the observed 3.09e-11) with dadp bitwise equal. ADMM ProfitObjective(0) is bitwise on welfare, dadp, iters and primal trace."
    why_human: "Tolerance acceptance. The wedge-term expression adds 0*net terms to the local JuMP objective, so a bitwise match is not structurally guaranteed."
  - test: "Exact digest fence runs only on Julia 1.12.5"
    expected: "The researcher accepts that the FNV goldens assert only on Julia 1.12.5. Other versions get a @test_skip, an allowlisted record, and the weaker version-independent default-vs-all-welfare-actor bitwise check."
    why_human: "CI on another Julia version loses the pre-phase comparison (review IN-02). Pinning per-version goldens is a policy decision."
  - test: "Actors on MPC, stochastic and FIT are rejected by MethodError, not ArgumentError"
    expected: "The researcher accepts that run_mpc, run_stochastic and fit_baseline reject `actors` because the keyword does not exist (a MethodError whose message names `actors`, tested). The locked CONTEXT wording says ArgumentError. Behaviour wrappers ARE rejected with ArgumentError on FIT, MPC and stochastic."
    why_human: "Deviation from the locked decision's exception type. The fail-loud intent holds and no silent route exists (Scenario carries no actors field). Review IN-03 carried this forward as Info."
  - test: "DeltaW is a helper and CSV column, not a solve-result field"
    expected: "The researcher accepts that solve_welfare/solve_admm actor reports carry social_welfare, actor_objective_value, profit_by_actor and retail_wedge, while DeltaW comes from actor_efficiency(W_opt, W_soc). That needs a second welfare solve, and the sweep CSV reports it as dW_abs/dW_rel."
    why_human: "Plan 44-02's truth and CONTEXT say 'every new result carries ... ΔW'. A single solve cannot know W_opt, so the helper design is defensible, but it is a reading of the contract."
---

# Phase 44: Aggregator as Actor Verification Report

**Phase Goal:** A researcher can give each aggregator its own objective, span a portfolio across buses, and apply exogenous behavioural scenarios, with welfare always reported as social welfare.
**Verified:** 2026-11-03T10:37:29Z
**Status:** human_needed
**Re-verification:** No. This is the initial verification.

## Evidence base

- I read the code diff `1506ef5..HEAD` (31 files, +4356/-69) directly. I did not rely on the SUMMARY files.
- Full suite at HEAD 3a61133 (orchestrator run, not re-run here): `35194 pass, 7 broken`.
  - The pre-phase baseline was 34468/0/0/7. runtests fails on any broken or skipped record that `test/expected_broken.txt` does not allowlist.
  - Phase 44 added one allowlisted skip: the fence digest gate on non-1.12.5 Julia.
  - The default Julia here is 1.12.5 (`julia --version`), and the broken count did not rise above the pre-phase 7. So the fence digests were asserted in the full suite, not skipped.
- My own targeted run: `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_actor_default_fence.jl` gave **15/15 pass**. The printed digests `0xc1791cfe86ef6538 / 0xd3ba3a3fbb317158 / 0x27a82704e86fbdd9 / 0x3b8e36e55565b99c` equal the goldens. I restored test/Project.toml and test/Manifest.toml afterwards, and the tree is clean.
- Golden provenance:
  - Commit `ba1ad0e` ("pin pre-change digests") touches only the test file and `expected_broken.txt`. `git diff 1506ef5 ba1ad0e -- src` is empty.
  - The only later commit on the fence file (`dd74dad`) changes no golden hex value.

## Goal Achievement

### Observable Truths (roadmap contract first, then consolidated plan truths)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | A researcher chooses per aggregator between social welfare (default, unchanged) and profit with wedge. | VERIFIED | `src/actors/actor_objective.jl`: `AbstractActorObjective`, `WelfareObjective`, `ProfitObjective(wedge)` (scalar or hourly, finite-guarded). `Portfolio(sites; objective)` in `src/actors/Portfolio.jl`. The `actors` keyword exists on `solve_welfare` (welfare_solve.jl) and `solve_admm` (solve_admm.jl:362). Default `actors = nothing`. |
| SC2 | With zero wedge the profit objective reproduces the welfare optimum, and a nonzero wedge reports its efficiency loss while `welfare` remains social welfare. | VERIFIED | Covered by rows 3-5. On ADMM, `az.welfare == a0.welfare`, plus dadp, iters and primal_trace (`==`), on two-bus with 3 seeds and on IEEE-13. Centralized: `abs(cz-c0) <= 9.3e-11`, `cz[3] == c0[3]`. `actor_efficiency` returns `(delta_abs, delta_rel)`. The sweep CSV m=0 row has `dW_abs = 0.0`; m = 0.5, 1, 2 give dW = 2.03e-3, 2.74e-3, 2.75e-3. |
| SC3 | One aggregator can hold a multi-bus portfolio with consensus keyed by (aggregator, bus), and single-bus aggregators remain byte-identical to v4.0. | VERIFIED | `SlotTable` / `build_slot_table` (Portfolio.jl). `slot_bus` / `slot_actor` result keys. Tests pin `slot_bus == Dict(2=>2, 3=>3, 4=>4, 5=>3)` and `slot_actor == Dict(2=>1, 3=>1, 4=>2, 5=>2)`. The digest fence passes (my run), the canary holds at 56 / -4823.66604824162, and the forced slot path equals legacy bitwise on IEEE-13. |
| SC4 | Partial compliance, opt-out and rebound are seeded scenario parameters, and their effects on welfare, prices and settlement are reported. | VERIFIED (effect size: human) | `BehaviourSpec(; compliance, opt_out, rebound, seed)` and `apply_behaviour` (materialize.jl). Seeding is SplitMix64 `_flex_mix` plus `LehmerRNG`, never `Base.hash`. The CSV reports welfare, dadp_mean/max, ledger totals and rebound_amount/ratio per point. On IEEE-123 the effect is a null result (human item 1). Per the locked decision these are not `Scenario` fields. |
| 1 | Welfare objective leaves the AGR build bit-identical, and the margin survives `solve_agr!`. | VERIFIED | `agr_objective(::AbstractActorObjective, U, pag, T) = U`. `linear_offset === nothing` for welfare. `coef += agr.linear_offset[t]` sits inside the `set_objective_coefficient` update (AgrOpt.jl:326), and the default path does no extra float operation. |
| 2 | Wedge sign is consistent on both paths. | VERIFIED | ADMM `pag` coefficient: `-λ - ρc + m`. Centralized: `welfare += Σ m·net` on a LOCAL expression, and `ctx.objective` is never touched. Profit is `-Σ m·pag = Σ m·load` on both paths. |
| 3 | Reported `welfare` is SOCIAL welfare on both paths. | VERIFIED | ADMM `welfare = Σ util[j] - λ₀ᵀp_import`, where `util = value(agr.ctx.objective)` (utility only, no wedge) (admm_phases.jl:539). Centralized actor path returns `value(ctx.objective) - λ₀ᵀp_import`. Tests check `cm[2] == social == a.social_welfare` and `!= objective_value(model)`. |
| 4 | ΔW ≥ 0 is reported and checked within measured slack, and a violation is flagged. | VERIFIED | Tests assert `dW >= -9.3e-11` (centralized) and `>= -1.24e-7·|W|` (ADMM). The sweep writes the `refused:impossible_dW` verdict when the bound fails. No such row exists among the 22 rows, all `ok`. |
| 5 | DEV-10 cross-validation: centralized and ADMM agree under a nonzero wedge. | VERIFIED | Two-bus: relative welfare gap ≤ 1.24e-7 and dadp gap ≤ 4.1e-5. IEEE-13 (slow item): dadp gap ≤ 1.23e-2. Bands are 3x the observed maximum, recorded in the test header. |
| 6 | A portfolio on distinct buses uses the legacy path and is bitwise equal to legacy. | VERIFIED | The `objectives` Dict is keyed by bus on the 1:1 path. IEEE-13 test: `aw` and `az` equal `a0` on welfare, dadp and iters. |
| 7 | Several sites per bus: automatic slot routing, `:Rp[bus(s)]` injection, per-bus DADP `(n_load_nodes, T)`, slot-λ certificate reported and never thrown. | VERIFIED | `shared_bus` routing (solve_admm.jl). `add_to_residual!(ctx, :Rp, slot_bus[j], …)` (DsoOpt.jl:441). `_primary_slots` publishes one row per bus. `lambda_slots`, `slot_lambda_gap` and `slot_lambda_agree` are emitted only on shared-bus runs. Tests check `size(dadp) == (3, T)`, `dadp[i,:] == lambda_slots[bus]` and `gap ≤ 1e-12`. |
| 8 | Split-bus results equal merged results within measured bands; OFF, CERTIFIED and LIVE plus a FourQuadBESS second site work; p_p counts slots. | VERIFIED | `test_actor_portfolio.jl`, eight items covering 44-05. Header table: ADMM split vs merged \|dW\| ≤ 2.3e-5. `p_p = length(load_nodes)*T`, where `load_nodes` are slot ids on the slot branch (admm_phases.jl:394). |
| 9 | Behaviour wrappers satisfy the device contract with the stated math. | VERIFIED | `src/devices/Behavioural.jl`. PartialCompliance: `p' = (1-ξ)b + ξp`, `U' = ξU + (1-ξ)Ub`. OptOut: `p = b`, `U = Ub`, no variables. Rebound: `u ≥ p - b`, `Σ_{t+1..t+W}(b - p) ≥ r·u`, convex, no binaries. Traits forward through CapabilityTraits.jl. |
| 10 | Seeded transform: default spec returns its input `===`, and the per-device FIT flat-price baseline is computed once at transform time. | VERIFIED | `_is_default_behaviour` makes the transform return `aggregators`. `_device_baseline` runs a single-device QP at `FIT_λ_IMPORT` with the measured 1e-6 tie-break, and `Ub` is unregularised. `fit_baseline` is untouched. A per-bus occurrence rank keeps first-site draws bit-identical (WR-02). |
| 11 | Guards: FIT, MPC and stochastic reject wrappers with ArgumentError and reject `actors`. | VERIFIED (exception type: human item 8) | The `_reject_unsupported_flex_devices` Union is extended (fit.jl). It is called from fit_baseline:121, run_mpc (mpc_loop.jl:292) and build_stochastic_welfare (new guard). Tests: `@test_throws ArgumentError` on each. `actors` on run_mpc, run_stochastic and fit_baseline gives a MethodError whose message names `actors` (tested). |
| 12 | The settlement actor line conserves exactly, and the default ledger is bit-identical. | VERIFIED | Flow (d) in SettlementLedger.jl is a `(:actor,id) <-> (:aggregator,bus)` mirror pair of `m_t·load_t`, and `actor_wedges = nothing` adds no rows. `actor_wedge_rows` exists for both ctx and ADMM results. Adapters accumulate with `+=` per bus (run_inputs.jl:155, 227). The CSV has `ledger_residual == 0.0` on all 22 rows. |
| 13 | Sweep CSV, literate page and registration exist. | VERIFIED | `results/actor_behaviour/actor_behaviour_sweep.csv` has 22 rows in the fixed `COLS` order. `docs/literate/aggregator_actor.jl` is registered at docs/make.jl:38 and :110. It recomputes its figures from the CSV and carries the first-welfare-theorem disclaimer, "not a strategic aggregator", the honest baseline label, the null result and the symmetric-wedge loss. `scripts/README.md:24` has the row. `check_scripts_index.py` passes (47 files). |
| 14 | Default-path digest fence and canary hold. | VERIFIED | See the evidence base: goldens predate the `src/` edits, were never re-pinned, and pass at HEAD (my run, 15/15). |

**Score:** 4/4 roadmap success criteria and 14/14 consolidated truths verified. All 37 plan frontmatter truths across 44-01..44-07 map onto these rows and hold. Nine items need human sign-off (judgement calls, not gaps).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/actors/actor_objective.jl` | objective hierarchy and hooks | VERIFIED | 106 lines, exported, used by AgrOpt, welfare_solve and solve_admm |
| `src/actors/Portfolio.jl` | Portfolio, `_expand_actors`, SlotTable | VERIFIED | 125 lines, used by both solve paths |
| `src/actors/efficiency.jl` | `actor_efficiency` | VERIFIED (size note) | 24 lines against the plan's `min_lines: 40`. The function is complete; the "recompute helpers" the plan mentions live inline in welfare_solve/solve_admm. Not a stub. |
| `src/devices/Behavioural.jl` | wrappers | VERIFIED | 223 lines, exported, included before CapabilityTraits |
| `src/experiments/materialize.jl` | BehaviourSpec, apply_behaviour, `_device_baseline` | VERIFIED | exported |
| `src/settlement/SettlementLedger.jl`, `run_inputs.jl` | actor_wedges, slot-aware adapters | VERIFIED | used by the sweep script |
| `scripts/actor_behaviour_sweep.jl` and the CSV | measurement artifact | VERIFIED | public-API orchestration |
| `docs/literate/aggregator_actor.jl` | literate page | VERIFIED | registered |
| `test/test_actor_{default_fence,objective,portfolio,settlement,sweep}.jl`, `test/test_behaviour.jl` | tests | VERIFIED | substantive assertions (`==` for bitwise checks, measured bands otherwise) |

### Key Link Verification

The `gsd-sdk verify.key-links` tool reported "Source file not found" on links whose `from` holds a function name after the path. That is a tool parsing limit, so I checked every link by hand.

| From | To | Status | Evidence |
|------|----|--------|----------|
| `build_agr_opt` | `agr_objective` | WIRED | AgrOpt.jl:182 |
| `solve_agr!` | `linear_offset` | WIRED | AgrOpt.jl:326 |
| `solve_welfare` | `wedge_term` / `agg_net` | WIRED | welfare_solve.jl actor block |
| `_admm_build` | `build_agr_opt(...; objective)` | WIRED | admm_phases.jl legacy and slot branches |
| `_admm_build` | SlotTable | WIRED | slot branch, `_admm_state_init(..., slots.bus)` |
| `build_dso_opt` | `:Rp[bus(s)]` | WIRED | DsoOpt.jl:441 |
| `apply_behaviour` | `_device_baseline` | WIRED | `_behave_aggregator` |
| `_reject_unsupported_flex_devices` | wrappers | WIRED | fit.jl:84-86 |
| `build_settlement_ledger` | `_push_transfer_pair!` (flow d) | WIRED | SettlementLedger.jl |
| settlement adapters | per-bus `+=` | WIRED | run_inputs.jl:155, 227 |
| sweep script | ledger(actor_wedges) and rebound | WIRED | verified by tool |
| docs/make.jl | aggregator_actor.jl | WIRED | verified by tool |

### Data-Flow Trace (Level 4)

| Artifact | Data | Source | Real data | Status |
|----------|------|--------|-----------|--------|
| ADMM `actor` report | profit_by_actor | `result.agr_dispatch[site_slot or bus]` | yes (solved dispatch) | FLOWING |
| ADMM `welfare` | social welfare | `util[j]` = `value(agr.ctx.objective)`, `p_import` | yes | FLOWING |
| Centralized `ctx.meta[:actor]` | social welfare, profit | `value(ctx.objective)`, `value(agg_net[k].net)` | yes | FLOWING |
| Literate page | every printed figure | committed CSV, parsed live | yes; review IN-03 notes some prose figures are typed beside the live lines | FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Default-path byte-identity fence and canary | `TSODSO_TEST_SET=fast TSODSO_TEST_FILES=test_actor_default_fence.jl julia --project=. -e 'import Pkg; Pkg.test()'` | 15/15 pass, digests equal the goldens | PASS |
| Scripts index gate | `python3 .github/scripts/check_scripts_index.py` | "scripts index complete (47 tracked files checked)" | PASS |
| Full suite (orchestrator, HEAD 3a61133) | not re-run | 35194 pass / 7 broken (allowlisted) | PASS (accepted evidence) |

### Probe Execution

None. No probe scripts are declared, and this is not a migration phase.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| ACTOR-01 | 44-01, 44-02, 44-07 | per-aggregator welfare or profit-with-wedge objective | SATISFIED | SC1, rows 1-2 |
| ACTOR-02 | 44-01, 44-02, 44-06, 44-07 | zero-wedge pass-through; efficiency loss reported; welfare stays social | SATISFIED | SC2, rows 3-5, 12 |
| ACTOR-03 | 44-03, 44-05, 44-07 | multi-bus portfolio, consensus keyed by (aggregator, bus), single-bus byte-identical | SATISFIED | SC3, rows 6-8, 14 |
| ACTOR-04 | 44-04, 44-06, 44-07 | seeded compliance, opt-out and rebound; effect on welfare, prices and settlement | SATISFIED (effect size: human item 1) | SC4, rows 9-13 |

No orphaned requirements: REQUIREMENTS.md maps only ACTOR-01..04 to Phase 44.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| (all 31 phase-modified files) | - | TBD / FIXME / XXX / TODO / HACK / placeholder | none found | - |
| `docs/literate/aggregator_actor.jl` | Section 4 prose | hardcoded figures (3.4e-9, 7.9e-6, 8.9999) next to live lines | Info | would go stale if the sweep is re-run (review IN-03) |
| `scripts/actor_behaviour_sweep.jl` | wedge block | `cent_dadp_gap` compares only `res.dadp[1, :]` (first load bus) | Info | the cross-check column covers one bus, not all |
| `src/admm/AgrOpt.jl` | 76 | `linear_offset::Union{Nothing, Vector{Float64}}` | Info | review iteration-1 IN-01; the JET ratchet is green |
| `.planning/ROADMAP.md` | Phase 44 details | `**Plans**: TBD` although the phase is marked complete | Info | doc bookkeeping only |

### Informational notes (not gaps)

- **Slot granularity is per site.** A slot is one site: (actor, bus) when an actor has at most one site per bus. If ONE portfolio holds two sites at the same bus, they become two slots, each tagged with the same (actor, bus) in `slot_actor` / `slot_bus`. This is strictly finer than (actor, bus) and still shares the nodal price. The tested shared-bus fixtures put the two co-located sites in different portfolios.
- **MPC guard reachability.** The MPC wrapper guard is tested by calling `_reject_unsupported_flex_devices(..., "run_mpc")` directly. `run_mpc` builds its population from `Scenario`, which cannot carry wrappers, so the guard is defensive and has no reachable bypass.

### Human Verification Required

1. **IEEE-123 null behaviour result.** The welfare spread is about 3.4e-9 relative, the mean DADP shift at most 7.9e-6, and dW is sign-mixed (at most 1.41e-4). The literate page section 4 documents this as a null result. Decide whether ACTOR-04's "see their effect" is satisfied by a measured null result, or a device-scaled fixture is wanted.
2. **Symmetric wedge and negative actor profit on IEEE-13.** This is assumption A6, documented in the source and in page section 1.
3. **JET baseline 12 to 20.** I statically spot-checked that the 8 entries predate the phase but did not re-run JET. Phase 44's own 2 reports were fixed.
4. **`SLOT_LAMBDA_AGREE_TOL = 1e-12`** is a floor, not 3x the observed 2.7e-15. It is documented at the constant, and the certificate only reports.
5. **FourQuadBESS split slot** needs 171-189 iterations against 4 merged. This is documented in the test header and the "no parity" docstring, but not on the literate page.
6. **Centralized ProfitObjective(0)** matches within 9.3e-11, not bitwise (dadp is bitwise). The ADMM path is bitwise.
7. **Digest fence is exact only on Julia 1.12.5.** Other versions get the weaker version-independent check (review IN-02).
8. **Actors on MPC, stochastic and FIT raise MethodError**, against the locked CONTEXT's "ArgumentError guard". The behaviour wrappers do raise ArgumentError.
9. **ΔW is not a field of the solve result.** It comes from `actor_efficiency(W_opt, W_soc)` and the sweep CSV, which needs a second welfare solve.

### Gaps Summary

There are no blocking gaps. Every roadmap success criterion and every ACTOR requirement has implementation evidence I read in the code, wired end to end and exercised by substantive tests:

- The full suite is green at HEAD.
- The pre-change digest fence passes in my own process.
- The sweep artifact and the literate page exist and are registered.

The nine items above are judgement calls on tolerances, modelling assumptions, effect size and contract wording. The developer should accept them or turn them into follow-up work. They are not missing implementation.

---

_Verified: 2026-11-03T10:37:29Z_
_Verifier: Claude (gsd-verifier)_

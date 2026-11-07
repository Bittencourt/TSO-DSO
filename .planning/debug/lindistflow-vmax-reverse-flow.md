---
status: diagnosed
trigger: "linDistFlow vmax bound under reverse flow"
created: 2026-11-07
updated: 2026-11-07
goal: find_root_cause_only
source_todo: .planning/todos/pending/2026-10-07-linDistFlow-copy-vmax-bound-breaks-relaxation-under-reverse-flow.md
---

# Debug: LinDistFlow exactness-copy bound v̂ ≤ vmax² under reverse flow

## Symptoms

<!-- DATA_START -->
- **Expected:** the default SOCP model (`ConvexBranchFlow`, the Gan–Low copy direction `v̂ ≥ v`) is
  described as a convex relaxation of AC that is validated exact on radial fixtures. Its welfare optimum should
  therefore be ≥ that of any AC-feasible point (obj_gap = SOCP − AC ≥ 0, both maximizing welfare).
- **Actual:** on the certified 3-bus high-PV stress fixture (pv_scale=1.2, load_scale=0.2, vmax=1.05,
  r=x=0.05; `test/fixtures_ieee13.jl` `high_pv_feeder` / `build_high_pv_aggregators`), obj_gap = −0.4773.
  - The cone is tight: socp_maxgap is 2.6e-8, so the SOC relaxation is not the cause.
  - SOCP and AC differ at 10/24 hours (6–15).
  - The `v̂ ≤ vmax²` bound (`src/powerflow/ConvexBranchFlow.jl:258`, thesis 3.45) is active at hours 9–12 and 15.
  - At those hours the AC point sits at v = vmax². The copy recursion evaluated at the AC point gives v̂ up to
    1.111137, above vmax² = 1.1025, so the AC point is infeasible for the SOCP.
- **Diagnostic (no src change, in `scripts/pv_boom_case_study.jl`):** deleting only the v̂ upper bounds moves
  obj_gap to −9.73e-6, removing 99.998% of the gap, with the cone at 1.66e-7. One hour (7) still differs. The
  residual is above the script's own −1e-6 "not a relaxation" threshold, so it is not fully explained.
- **Errors:** none. This is a measured modelling finding, recorded in `results/pv_boom/findings.txt` (Part A2).
- **Timeline:** recorded 2026-10-07 in a Phase 37 code review. It sits on top of the v4.0 Phase 26 change that
  made the Gan–Low copy direction (`v̂ ≥ v`) the default, with `thesis_literal=true` as opt-in.
- **Reproduction:** `scripts/pv_boom_case_study.jl`, Part A2. The fixture and the AC oracle (`ACPowerFlow`) are
  in the repo.
<!-- DATA_END -->

## Orchestrator notes (context, verify — do not trust blindly)

- **The leading hypothesis is design, not a bug.** The header of `src/powerflow/ConvexBranchFlow.jl` (around
  lines 20–30 and 99–119) already says the default copy follows Gan–Low's *modified* OPF. In it, `v̂ ≤ V²max` is
  load-bearing and conservatively enforces `v ≤ V²max`, which makes it an inner restriction of the voltage
  band. Gan, Li, Topcu & Low (2015) prove exactness for the modified OPF, whose feasible set is a subset of
  the original. If so, "the SOCP is not a relaxation of AC" is the expected cost of the exactness guarantee
  under reverse flow, where v̂ > v by the loss terms, and not a defect. Confirm or refute this from the code,
  the docs and the measurement.
- **Things to establish:**
  - (a) Is the observed gap fully explained by v̂ − v (the loss terms 2(r²+x²)·l summed along the path)? That
    is, is v̂ − v at the AC point at the binding hours equal to that accumulated loss term?
  - (b) What explains the hour-7 residual (−9.73e-6 after deleting the bound)? Candidates: solver tolerance
    (Clarabel tol_gap vs Ipopt), AC local optimality, the v lower bound, or something else. Measure it; do
    not guess.
  - (c) Where else is the "relaxation" claim made: docs pages (`docs/literate`, `docs/src`), the project
    claims, `FRAMEWORK_GUIDE`, comments? Are they consistent with the restriction?
  - (d) How large is the effect on the realistic fixtures (IEEE-13/123 default, `:case_a_784`, the high-PV
    PV-boom sweep)? Is the v̂ bound ever active there? Part A of `results/pv_boom/findings.txt` reports
    exactness gaps of ~1e-8 at pv_mult up to 2.5 on IEEE-13.
  - (e) What are the decision options and their blast radius? Options: keep 3.45 and document it as an
    inner approximation; bound only `v` and drop or condition `v̂ ≤ vmax²`; or offer an opt-in variant.
    For each, list the goldens, canary and digest fences it would move. Note that the knife-edge canary
    (56 iterations / −4823.66604824162) and the v5.0 digest fences pin the default path.

## Constraints

- Diagnose only (`goal: find_root_cause_only`). **No src/ change, no golden or tolerance change.** This is a
  research decision for the user, and the todo says "Do not change silently".
- Any measurement script goes in the session scratchpad or `.planning/debug/`, never as a tracked
  `@testitem`; TestItemRunner scans `.jl` files in the repo.
- Run one julia process at a time, in the foreground, and leave no background processes. No full test suite.
  Nothing on IEEE-8500 or `:case_a_784` at full scale; small fixtures only.
- Run julia with `julia --project=.`. For test-only deps use `JULIA_LOAD_PATH="@:$PWD/test:@stdlib"`.
- No worktrees, branches, checkout, reset or stash.

## Current Focus

- hypothesis: CONFIRMED (with amendment) — v̂ ≤ vmax² is an inner restriction by design (v̂ − v = Σ_path|z|²l), already documented as a restriction; BUT mis-attributed as Gan–Low OPF-m / "exact by theorem": the per-branch copy induces downstream cone slack when binding (measured pv ≥ 1.3).
- test: done (m1–m4)
- expecting: n/a
- next_action: researcher decision among options A/B/C/D in Resolution; no fix applied (find_root_cause_only)

## Evidence

- timestamp: 2026-11-07T10:05
  checked: src/powerflow/ConvexBranchFlow.jl header (l.17-35), type docstring (l.99-119), constructor docstring; docs/literate/convex_branch_flow.jl "Amendment" (l.71-88); docs/literate/ac_oracle.jl (l.179-234); test/test_ac_oracle.jl (l.180-330)
  found: The default copy is ALREADY documented in source and literate docs as a RESTRICTION ("NEVER a genuine relaxation"), citing the SAME numbers as the todo: default SOCP optimum -921.754 vs true AC optimum -921.277 on the high-PV fixture (difference 0.477 = the todo's obj_gap -0.4773). test_ac_oracle.jl asserts !isempty(inexact_hours) and `diagnosed` on this fixture under the default, and its comment attributes it to the `v̂ ≤ V²max` restriction binding. The same comment records that `thesis_literal=true` MATCHES the AC optimum at pv_scale=1.2 (cost -921.27700 vs -921.27699).
  implication: The PV-boom Part A2 finding (2026-10-07) re-discovered an already-documented, test-pinned property (v4.0 P26 amendment). findings.txt calling it "UNRESOLVED" is stale relative to the source docs.

- timestamp: 2026-11-07T10:10
  checked: algebra of 3.33 vs default 3.43 (ConvexBranchFlow.jl l.226-275)
  found: copy drop v̂_j = v̂_i − 2(rP+xQ) + 2|z|²l; true drop v_j = v_i − 2(rP+xQ) + |z|²l. Hence v̂_j − v_j = (v̂_i − v_i) + |z|²l = Σ_{b∈path(j)} (r_b²+x_b²)·l_b ≥ 0 (net coefficient 1·|z|²l, not 2·|z|²l as the orchestrator note wrote).
  implication: v̂ ≤ vmax² ⇒ v ≤ vmax² − Σ_path |z|²l: an inner restriction of the upper band whose tightening equals the accumulated path losses, regardless of flow direction (largest when l is large, i.e. heavy reverse flow).

- timestamp: 2026-11-07T10:20
  checked: (a) scratch m1_stress.jl (scratchpad) — stress fixture, default SOCP (rtol_exact=1.0) + AC (Ipopt default); AC point mapped into the SOCP model (532 non-pf vars, positional map, 0 bound/parameter signature mismatches) and checked with JuMP primal_feasibility_report
  found: SOCP objective at the AC point = AC objective exactly (diff 0.0) — same objective. At the AC point, v̂_rec − v = Σ_path |z|²l to 1.9e-16 at every (j,t). Binding hours: t=9,10,11,12,15 bus 3 has v = vmax²(+1.09e-8) and v̂ − vmax² = +3.93e-3, +5.41e-3, +8.64e-3, +5.76e-3, +6.82e-3 (= the path loss term exactly, since v=vmax²); t=12 bus 2 v̂ − vmax² = +1.40e-3 (v below vmax² by 4.3e-3 but path loss 5.72e-3). AC point violations in the DEFAULT SOCP > 1e-9: the six v̂ ≤ 1.1025 rows above (1.4e-3..8.6e-3) and otherwise only ≤1.09e-8 rows (v ≤ vmax² by 1.09e-8 and linear device rows by 9.7e-9). AC point own true-drop residual 2.2e-16, cone |lv−P²−Q²| 7.7e-13.
  implication: (a) CONFIRMED. The AC optimum is excluded from the SOCP feasible set SOLELY by v̂ ≤ vmax², and the violation equals the accumulated path-loss term Σ|z|²l exactly. Everything else is at Ipopt tolerance level (~1e-8).

- timestamp: 2026-11-07T10:20
  checked: (b) same script — v̂ upper bounds deleted, then solver tolerances varied
  found: bound-deleted SOCP (Clarabel tol_gap 1e-8) obj −921.2770011593, gap −9.7277e-6 (reproduces findings.txt). The AC point in the bound-deleted SOCP violates only ~1e-8 rows (v[3,t] ≤ vmax² by 1.09e-8 at t=9..12,15; ~170 device linear rows by ≤9.7e-9) — Ipopt's default bound_relax_factor=1e-8 / tol 1e-8. Clarabel tightened to 1e-10 / 1e-12 (gap, feas, ktratio): obj −921.2769975371 / −921.2769975310 (+3.63e-6 vs default tol), cone maxgap 7.9e-11. Ipopt tightened (tol 1e-10, constr_viol_tol 1e-10, bound_relax_factor 0), warm from own point: obj −921.2769975320, i.e. −6.100e-6 below the default-tolerance AC point. Gap (tight SOCP_nb − tight AC) = +9.86e-10. Ipopt warm-started from the SOCP_nb point: identical +9.86e-10. All 5 nlp_multistart_variants (tight): gaps +9.9e-10 .. +1.85e-8, all ≥ 0. Decomposition: 6.100e-6 (Ipopt bound relaxation/tolerance super-optimality) + 3.628e-6 (Clarabel tol_gap under-convergence) = 9.728e-6 = the residual.
  implication: (b) The −9.73e-6 residual is entirely solver tolerance, not a model gap: with the v̂ upper bound removed and both solvers converged tightly, SOCP ≥ AC (+1e-9). Not AC local optimality (warm start from SOCP point and 5 strategies agree), not the v lower bound (v − vmin² ≥ 3.3e-2 at hours 1–16 in both solves). Hour 7's dP of 3.3e-6 lies at the assert_ac_exact! atol=1e-6 scale; the same solve emits a battery complementarity warning at bus 2 t=7 (p_ch·p_dch = 7.8e-6), consistent with a flat/degenerate hour (checked further in m2).

- timestamp: 2026-11-07T10:45
  checked: (b) scratch m2_fixtures.jl — stress fixture with BOTH solvers tight from the start (Clarabel tol_gap/feas/ktratio 1e-12; Ipopt tol 1e-10, constr_viol_tol 1e-10, bound_relax_factor 0), assert_ac_exact!(rtol 1e-4, atol 1e-6)
  found: WITH v̂ ≤ vmax²: obj_gap −0.4773333, inexact hours [6..15] (tolerance-independent). v̂ bound deleted: obj_gap +2.64e-9, inexact hours [] (hour 7: pgap 1.8e-8, vgap 2.4e-9). Pinning hour-7 branch P to the AC values changes the SOCP objective by 1.1e-10 → hour 7 sits on a near-flat (battery-degenerate) direction, so the default-tolerance noise shows up there first.
  implication: (b) CLOSED. With the v̂ upper bound removed, SOCP ≥ AC and every hour matches; the hour-7 "difference" and the −9.73e-6 residual are tolerance artefacts (Ipopt bound_relax_factor 1e-8 + Clarabel tol_gap 1e-8) on a flat hour. Nothing else separates the two models on this fixture.

- timestamp: 2026-11-07T10:45
  checked: (d) m2_fixtures.jl — default ConvexBranchFlow on IEEE-13 canary scenario (seed 7, :default, :mem, allow_export), IEEE-13 PV-boom sweep (seed 20260806, pv_mult 0,0.5,1,1.5,2,2.5,4.0), IEEE-123 default (seed 7). Per case: count of (j,t) with v̂ ≥ vmax²−1e-6, max |dual(UpperBoundRef(v̂))|, min(vmax²−v̂), max(v̂−v), Δobj after deleting all v̂ upper bounds and re-solving.
  found: v̂ bound active at 0 points in every case; v ≤ vmax² also never active. Closest approach: IEEE-13 pv_mult=1.0 min(vmax²−v̂)=3.08e-3 (max v̂ 1.09942); all others ≥ 2.1e-2; IEEE-123 2.08e-1. max(v̂−v) ≤ 1.02e-3 on IEEE-13, 1.19e-4 on IEEE-123. max |dual| ≤ 6.7e-7. Δobj(delete) ∈ [−5.4e-6, +5.3e-6] with mixed signs (re-solve noise at Clarabel tol_gap 1e-8), never bitwise equal. IEEE-13 seed 7 welfare −4823.67819561189 (1.3 s); IEEE-123 −41046.468352709 (5.2 s).
  implication: (d) On every default/realistic fixture the v̂ ≤ vmax² bound is slack with zero economic effect. Removing it changes results only at the floating-point/bit level. The effect is confined to the 3-bus high-PV stress regime.

- timestamp: 2026-11-07T10:50
  checked: (e) m2 — IN-SESSION redefinition of TSODSO._contribute_convex! with only the `set_upper_bound(v̂[j,t], vb.vmax^2)` line removed (Base.include_string; on-disk src untouched), then centralized IEEE-13 seed 7, the ADMM knife-edge canary scenario (ieee13, :admm, seed 7, T 24), and the high-PV fixture at default tolerances
  found: centralized IEEE-13 seed 7 welfare −4823.67819571479 vs baseline −4823.67819561189 (Δ −1.03e-7, not bitwise equal). Canary: iters = 56 (unchanged), welfare −4823.66604330511 vs pinned −4823.66604824162 (Δ +4.94e-6; still passes the test's isapprox rtol 1e-6/atol 1e-3, but the "byte-exact" value quoted in v5.0 plans/milestones no longer holds). High-PV fixture: cost_socp −921.277001 vs AC −921.276991, obj_gap −9.73e-6, inexact_hours [7], diagnosed=true, socp_maxgap 1.657e-7 (under the 2e-7 hybrid floor, but close).
  implication: Option B (drop the bound in the default) moves every bitwise digest fence on the default path. The canary iteration count holds and the canary welfare stays within tolerance. test_ac_oracle's high-PV item would still pass, but only because of hour-7 tolerance noise, so its documented mechanism would become false.

- timestamp: 2026-11-07T11:00
  checked: m3_pvscan.jl / m3b_pvscan_tau.jl — stress fixture pv_scale 1.2–2.0 for default, thesis_literal and default-without-v̂-ub (in-session patch); m3b bypasses the battery-complementarity gate (τ=1.0) because the default otherwise throws on that gate at pv ≥ 1.3; cone maxgap and assert_socp_exact! verdict
  found: default: pv 1.2 cone 2.6e-8 PASS, obj_gap −0.477; pv 1.3 cone 0.224 REFUSE, obj_gap −0.628; 1.4 cone 1.44 REFUSE, −0.876; 1.6 cone 3.80 REFUSE, −1.18; 2.0 cone 7.95 REFUSE, −1.61. Without the v̂ ub: pv 1.2 PASS, −9.7e-6; pv 1.3 cone 9.3e-8 PASS, obj_gap −7.6e-6 (= AC); 1.4 cone 1.48 REFUSE, +0.043; 1.6 +0.278; 2.0 +1.43 (genuine relaxation, gap ≥ 0). thesis_literal is identical to the no-ub variant at 1.2/1.3/1.4 (its copy restricts only the lower band).
  implication: The default is NOT "exact by theorem". At pv ≥ 1.3 it is cone-inexact AND scores below AC, so it is neither exact nor a relaxation. At pv 1.3 the v̂ ≤ vmax² bound itself CAUSES the inexactness: the plain relaxation is exact and matches AC there.

- timestamp: 2026-11-07T11:05
  checked: m4_mechanism.jl — default at pv 1.3 (τ=1.0): per-hour, per-branch cone gap, v̂/v, duals of v̂ ub, and recover_lossfree_shadow_voltage (Gan–Low v̂_GL)
  found: The only strict hour is t=12: gap on DOWNSTREAM branch 2→3 = 0.224 (branch 1→2 7.9e-9), with v̂2 = v̂3 = vmax² both binding (duals −23.2, −2.96) and v̂_GL3 = 1.10459 > vmax². Algebra: P_rec12 = P12 − r12·l12 = d2 + d3 + r23·l23 (balance at bus 2), so v̂2 = 1 − 2(r12·P_rec12 + x12·Q_rec12) DECREASES in l23. The per-branch copy subtracts only the branch's OWN loss, not downstream losses; Gan–Low's v̂_GL(s) depends on injections only (independent of l).
  implication: Mechanism confirmed. The default copy is not Gan–Low's OPF-m: it coincides with v̂_GL only on single-branch paths. On deeper paths a binding v̂ ≤ vmax² rewards inflating fictitious downstream current, and Gan–Low's C2 (v̂_GL ≤ v̄) fails at the default's solution, so Theorem 2 gives no guarantee. The repo itself says RestrictedBranchFlow's v̂_GL is "SEPARATE … strictly TIGHTER" (RestrictedBranchFlow.jl l.104-110) and FRAMEWORK_GUIDE §5.1 already reports "3 of 150 cone-inexact points" for the default. Both contradict the "Gan–Low's modified OPF, exact by theorem" label.

- timestamp: 2026-11-07T11:15
  checked: (c) grep of "relaxation/restriction/modified OPF/exact by theorem" across README.md, docs/src/index.md, docs/literate/*.jl, docs/writeups/FRAMEWORK_GUIDE.html, .planning/PROJECT.md, CLAUDE.md, src/**, test comments, results/pv_boom/findings.txt
  found: CONSISTENT (default called a restriction): README.md l.31-32; docs/literate/convex_branch_flow.jl "Amendment" l.71-88; docs/literate/ac_oracle.jl l.179-234; test/test_ac_oracle.jl l.195-225/305-325; FRAMEWORK_GUIDE §5.1 and the "Changed in v4.0" paragraph.
  INCONSISTENT / WRONG:
  (1) "Gan–Low's MODIFIED OPF … exact by theorem" for the DEFAULT copy: src/powerflow/ConvexBranchFlow.jl header l.27-35, type docstring l.83-86 and l.119-127, constructor docstring l.143-152, bound comment l.215-217 ("Bounding v̂ ≤ V²max is what drives the cone tight") and "Why the exactness copy is not decorative" l.99-104; FRAMEWORK_GUIDE §5.1 (and its "presses ℓ down until the cone closes"); .planning/PROJECT.md l.402-404; test/test_convex_branch_flow.jl comment l.98-104. This is a mis-attribution, refuted by m3/m4: the default's v̂ is not v̂_GL, and the default is measured cone-inexact at pv ≥ 1.3.
  (2) Stale sign: src/models/ac_oracle.jl recover_lossfree_shadow_voltage docstring (~l.125-131) still says the project's copy is a LOWER-bound shadow (v ≥ v̂), the "OPPOSITE sign". This has been false since v4.0 P26 (test_convex_branch_flow.jl:70-95 asserts v̂ ≥ v).
  (3) Default treated as an upper bound / relaxation: src/models/restriction_exactness.jl verdict l.196-206 ("below the unrestricted SOCP bound", "looser, inexact bound", "unrestricted relaxation's" set); docs/literate/restricted_branch_flow.jl l.1 title "Overvoltage-Capable Relaxation", l.271-273, l.314-316, l.341-343 ("unrestricted (loose) SOCP relaxation's own bound"); src/models/ac_oracle.jl assert_ac_exact! docstring (~l.266, l.281: obj_gap "between the relaxed and the true nonconvex optimum", which implies ≥ 0).
  (4) v2.1-era wording: docs/src/index.md l.35-38 and l.94-97 ("Where the relaxation is genuinely inexact (high-PV reverse flow with the voltage pinned at its upper bound)"). Under the default the pv 1.2 disagreement is restriction-induced, not inexactness. docs/literate/ac_oracle.jl l.1-8 framing has the same issue (corrected later on the page). .planning/PROJECT.md l.64 (v4.0 target text, "v̂ ≤ v") and l.503 ("relaxation validated exact on radial fixtures") also use it.
  (5) results/pv_boom/findings.txt Part A2 and scripts/pv_boom_case_study.jl Part A2 narrative call the gap "UNRESOLVED" and the residual "not diagnosed". Both are now explained (by design; solver tolerance).
  Generic requirement text ("SOCP relaxation must be validated exact", CLAUDE.md/PROJECT.md Constraints) and "SOC relaxation" used for the cone 3.39 alone (exactness.jl, socp_applicability) are fine.
  implication: The restriction is documented correctly at the main sites. The theorem attribution is wrong, and four other site groups still describe the default as a relaxation/upper bound or carry the pre-P26 sign.

- timestamp: 2026-11-07T11:20
  checked: (e) blast-radius inventory — test/test_admm_knifeedge_canary.jl (l.71 iters==56, l.81 isapprox welfare rtol 1e-6); test/test_actor_default_fence.jl (FNV-1a digests da2,dw2,da,dw of default two-bus + IEEE-13 solve_admm/solve_welfare, bitwise on VERSION==1.12.5; also re-asserts the canary); test/test_flex_market_fence.jl and test/test_flex_population.jl (0x digest literals, default ConvexBranchFlow path); test/test_convex_branch_flow.jl l.105-133 (asserts v̂ ≤ V²max binds); test/test_ac_oracle.jl l.180-330; test/test_restricted_branch_flow.jl l.298-299 (optimality_loss ≤ 1e-6); test/test_planning_goldens.jl (no ConvexBranchFlow refs, atol 1e-3); src/pricing/dlmp.jl (cpydrop dual = exactness-copy DLMP term); results/socp_applicability/highpv_3bus_sweep.csv; local julia = 1.12.5 (= fence GOLDEN_VERSION)
  found: see Resolution (options A/B/C/D).
  implication: Only Option A (and C, if the default path is byte-preserved) leaves goldens, canary and fences untouched.

## Eliminated

- hypothesis: The hour-7 residual (−9.73e-6) is a genuine remaining model difference (the v lower bound, or an AC local optimum)
  evidence: v − vmin² ≥ 3.3e-2 at all hours 1–16 in both solves (v lower bound slack). Tight Ipopt warm-started from the SOCP point and all 5 nlp_multistart_variants converge to the same AC objective (spread 1.8e-8). With both solvers tight the gap is +2.6e-9 and inexact hours = []. The residual decomposes as 6.100e-6 (Ipopt bound_relax_factor/tol) + 3.628e-6 (Clarabel tol_gap) = 9.728e-6.
  timestamp: 2026-11-07T10:45

- hypothesis: SOC cone slack causes the −0.477 gap on the pv 1.2 fixture
  evidence: cone maxgap 2.6e-8 (tight). The AC point violates only v̂ ≤ vmax² (primal_feasibility_report). With tight solvers the gap is −0.4773333, tolerance-independent.
  timestamp: 2026-11-07T10:20

- hypothesis: The default v̂ ≤ vmax² is Gan–Low's OPF-m restriction and therefore guarantees exactness (exact by theorem)
  evidence: m3: the default is cone-inexact at pv 1.3–2.0 (0.22–7.95). m4: the strict branch is the downstream branch 2→3 while v̂ ≤ vmax² binds, with v̂_GL3 = 1.10459 > vmax² (C2 fails). The default's v̂ subtracts only own-branch loss, while v̂_GL is lossless (the repo's own RestrictedBranchFlow docstring calls them distinct, v̂_GL strictly tighter).
  timestamp: 2026-11-07T11:05

## Resolution

- root_cause: |
    BOTH a by-design restriction AND a mis-documented (mis-attributed) design.
    (1) The reported symptom is by design and already documented. Since v4.0 P26 the default exactness copy
    satisfies v̂ − v = Σ_{b∈path} (r_b²+x_b²)·l_b ≥ 0 exactly (measured residual 1.9e-16). The bound v̂ ≤ vmax²
    (ConvexBranchFlow.jl l.214-222, thesis 3.45) therefore enforces v ≤ vmax² − Σ_path|z|²l: an inner restriction
    of the upper voltage band. On the pv 1.2 stress fixture the AC optimum is excluded SOLELY by this bound (AC v
    at vmax² at hours 9–12/15 → v̂ exceeds it by exactly the path-loss term, 1.4e-3..8.6e-3). The resulting
    obj_gap −0.4773 is the same "-921.754 vs -921.277" welfare loss already stated in the ConvexBranchFlow
    docstring, docs/literate/convex_branch_flow.jl (Amendment), docs/literate/ac_oracle.jl and pinned by
    test/test_ac_oracle.jl. The −9.73e-6 residual after deleting the bound is pure solver tolerance (Ipopt
    bound_relax_factor 1e-8 → +6.10e-6, Clarabel tol_gap 1e-8 → +3.63e-6). With tight solvers the bound-free
    SOCP is a true relaxation on this fixture (gap +2.6e-9, 0 inexact hours).
    (2) The design is mis-labelled, and the label hides a real limitation. The default copy is NOT Gan–Low's
    modified OPF (OPF-m uses the lossless shadow voltage v̂_GL(s), implemented separately as
    RestrictedBranchFlow). "Exact by theorem" is false for it: the per-branch copy removes only the branch's own
    loss, so v̂ at a bus decreases with DOWNSTREAM branch currents. A binding v̂ ≤ vmax² then rewards fictitious
    downstream current. Measured on the same fixture, the default is cone-INEXACT at pv ≥ 1.3 (0.22 → 7.95)
    while still scoring below AC (−0.63 → −1.61), and at pv 1.3 the bound itself causes the inexactness (the
    bound-free model is exact and equals AC). The exactness gate refuses those prices, so no silent wrong
    prices; but the default is neither a relaxation nor exactness-guaranteeing beyond single-branch paths.
    (3) On every realistic fixture measured (IEEE-13 seed 7, PV-boom sweep pv_mult 0–4.0, IEEE-123 seed 7) the
    bound is never active (0 points, dual ≤ 6.7e-7, min slack ≥ 3.1e-3): zero economic effect there.
    Stale/inconsistent "relaxation" claims remain in: ac_oracle.jl (pre-P26 sign), restriction_exactness.jl
    and the restricted_branch_flow literate page ("unrestricted relaxation's bound"), assert_ac_exact!
    docstring, docs/src/index.md, PROJECT.md, findings.txt/pv_boom script ("UNRESOLVED").
- fix: not applied (find_root_cause_only)
- decision_options (blast radius measured where noted; for the researcher):
    A. Keep 3.45 as is; re-document it as a per-branch inner approximation (drop "Gan–Low modified OPF / exact by
       theorem", state the cone-inexactness at pv ≥ 1.3 and the v̂−v = Σ|z|²l identity). Numeric blast radius:
       NONE (no golden, canary or fence moves). Text sites: ConvexBranchFlow.jl docstrings/comments,
       src/models/ac_oracle.jl (2 docstrings), src/models/restriction_exactness.jl docstring,
       docs/literate/{convex_branch_flow,ac_oracle,restricted_branch_flow}.jl (+ regenerated docs/src/generated),
       docs/src/index.md, docs/writeups/FRAMEWORK_GUIDE.html §5.1/§6, .planning/PROJECT.md,
       test/test_convex_branch_flow.jl and test/test_ac_oracle.jl comments, scripts/pv_boom_case_study.jl Part A2
       narrative → results/pv_boom/findings.txt.
    B. Drop (or "condition") v̂ ≤ vmax² in the default, keeping v ≤ vmax². Then v̂ ≥ vmin² is implied, so the copy
       becomes dead weight and the model is the plain SOC relaxation (same as thesis_literal on the upper band).
       Measured: pv 1.2/1.3 exact and equal to AC; pv ≥ 1.4 cone-inexact and refused (+0.04..+1.4 genuine
       relaxation gap). Moves: test_actor_default_fence.jl digests (centralized IEEE-13 welfare bits change,
       Δ −1.03e-7; ADMM welfare changes); test_flex_market_fence.jl and test_flex_population.jl digests (likely,
       not run). Canary: iters 56 holds, welfare −4823.66604330511 (Δ +4.9e-6) passes isapprox but is no longer
       byte-exact vs −4823.66604824162 quoted in v5.0 docs. test_convex_branch_flow.jl l.105-133 FAILS by
       construction. test_ac_oracle.jl high-PV item passes only via hour-7 noise. The exactness-copy DLMP term
       (cpydrop dual) goes to 0 → pricing/decompose_dlmp narrative. −921.754 numbers in all docs;
       results/socp_applicability/highpv_3bus_sweep.csv + socp_applicability page; FRAMEWORK_GUIDE.
    C. Opt-in variant (e.g. a kwarg or peer type that omits v̂ ≤ vmax²), default untouched. Blast radius: none on
       goldens/canary/fences IF the default path builds the identical model (same constraint order). Adding a
       struct field changes the positional ConvexBranchFlow(thesis_literal) constructor. Exposing it via Scenario
       adds a pf_* column to sweep.jl output schemas.
    D. (noted, not requested) Replace the per-branch copy with Gan–Low's v̂_GL (i.e. RestrictedBranchFlow/OPF-m
       as the default): theorem-backed restriction, but tighter → larger welfare loss on high-PV; moves
       everything that B moves.
- verification: diagnosis only — scripts in /tmp/claude-1000/-home-pedro-programming-TSO-DSO/fb4d3a0a-3e04-4903-ba56-4b034de53945/scratchpad/ (m1_stress.jl, m2_fixtures.jl, m3_pvscan.jl, m3b_pvscan_tau.jl, m4_mechanism.jl); Julia 1.12.5; no src/test/golden change on disk.
- files_changed: []

## Specialist Review

- specialist_hint: general (maps to engineering:debug)
- result: NOT RUN. The skill invocation tool was unavailable to the session manager; no external review was obtained. The root-cause verdict above rests on the debugger measurements only.
- user fix choice: not requested. Goal is find_root_cause_only; the fix option (A/B/C/D) is deferred to the researcher.

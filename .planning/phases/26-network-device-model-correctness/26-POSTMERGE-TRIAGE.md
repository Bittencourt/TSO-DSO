# Phase 26: Post-merge triage (HEAD cbaf8cb)

**Scope:** every failing or erroring testitem in `26-postwave2-suite.log`. That is 41 testitems
and 55 records (25 fail, 30 error), plus 5 broken against a baseline of 3. Each item is classified by
root cause. This is a diagnosis only: nothing in `src/` or `test/` was changed and nothing was committed.

## Method

- **Harness.** Throwaway `git worktree add --detach` snapshots live under the session scratchpad.
  The 41 testitems were run through `TestItemRunner.run_tests(<snapshot root>; filter = name ∈ list)`
  with `JULIA_LOAD_PATH="@:<snap>/test:@stdlib" julia --project=<snap>`. Paths are explicit, so there is
  no cwd or sibling-worktree resolution. The HEAD snapshot reproduces the suite exactly:
  **25 failed, 30 errored**, with identical messages and numbers.
- **Single-fix reverts, each on top of HEAD:**

  | Snapshot | What was reverted |
  |---|---|
  | `no02` | `ConvexBranchFlow` default changed back to `thesis_literal=true` (the old copy) |
  | `no03` | `PVBattery.jl`, `FourQuadBESS.jl`, `mpc_window.jl` restored from 5939799 |
  | `no0407` | `AbstractDevice`, `Aggregator`, `Thermostatic`, `Deferrable`, `Interruptible`, `linear_solve` restored from 5939799 |
  | `no05` | `ConvexBranchFlow.jl` taken from f677965 (26-02 only, so no `:smax_rev`, `Prev` or `Qrev`) |

- **Combination and verification snapshots:**
  - `c0204`: 26-02 and 26-04/07 both reverted.
  - `fix`: HEAD plus the candidate call-site fixes listed under cluster A and cluster C.
- **Probes** (direct `julia --project=<snap>` scripts):
  - A Clarabel `tol_gap` ladder (1e-8 → 3e-10 / 1e-12) with the PF-04 gate neutralised. It shows
    whether a cone gap is solver precision or a real relaxation gap.
  - An AC battery-dispatch dump on EXACT-04.
  - `:smax` versus `:smax_rev` duals on IEEE-13.
  - The mesh fixture with a φ = 1 override.

### Attribution matrix

`.` means the item passes in that snapshot; `E`/`F` means error/fail with N records. `c0204` only ran
the subset marked `*`.

| testitem (loc) | HEAD | no02 | no03 | no0407 | no05 | c0204 |
|---|---|---|---|---|---|---|
| acceptance:100* | E1 | . | E1 | . | E1 | . |
| acceptance:82* | F2 | F2 | F2 | F1 | F2 | F1 |
| ac_oracle:182* | E1 | E1 | E1 | . | E1 | . |
| admm:121 | F1 | F1 | F1 | . | F1 | – |
| admm:27 / :127* | E1 | E1 | . | E1 | E1 | E1 |
| admm_knifeedge_canary:53 | F2 | F2 | F2 | F2 | . | – |
| admm_reactive:286* | F1 | F1 | . | F1 | F1 | F1 |
| ieee123_admm:22 / :105* | E1 | . | E1 | . | E1 | . |
| ieee13:213* | F3 | F3 | F3 | F3 | F3 | F3 |
| mesh_flow:4, mesh_angle_certificate:4 / :97* | E1 | E1 | E1 | . | E1 | . |
| mpc_loop:17 / :323 | E1 | E1 | . | E1 | E1 | – |
| mpc_loop:95 / :187 / :294 | F2/F4/F5 | . | F | F | F | – |
| mpc_terminal:33* | E1 | E1 | F1 (margin) | E1 | E1 | E1 |
| planning_oracle:269* | E1 | E1 | . | E1 | E1 | E1 |
| pricing_dlmp:128 | E1 | E1 | E1 | E1 | . | – |
| pricing_dlmp:22 / :221* | E1 | E1 | E1 | E1 | E1 | E1 |
| pricing_fit:200 | F1 | F1 | . | F1 | F1 | – |
| pricing_welfare:193 | F2 | F2 | . | F2 | F2 | – |
| pricing_welfare:66* | E1 | E1 | E1 | E1 | E1 | E1 |
| restricted_branch_flow:61 / :145* | E1 | E1 | E1 | . | E1 | . |
| restricted_branch_flow:231 / :398* | E1 | E1 | E1 | F3/F2 | E1 | . |
| run_stochastic:36 / :90 | E1 | E1 | E1 | E1 | . | – |
| run_stochastic:104 | E1 | E1 | E1 | E1 | F1 (golden) | – |
| stochastic_welfare:30/206/254/310/353/418 | E/F | E/F | E/F | E/F | . | – |
| thesis_repro:62* | E1 | . | E1 | . | E1 | . |

In the `fix` snapshot (HEAD plus cluster A and cluster C fixes), these pass:
- mpc_loop:17 and :323, and mpc_terminal:33 (margin 1620×).
- All 6 stochastic_welfare items.
- run_stochastic:36 and :90.

run_stochastic:104 still fails, but now on its pinned golden rather than an error.

## Triage table

Classes:
- **GM:** GOLDEN-MOVE.
- **CSB:** CALL-SITE BUG. **CSB-num** means the gate trips at the solver-precision floor; the true
  optimum is exact.
- **GR:** GENUINE REGRESSION.
- **RF:** RESEARCH FINDING.

| test file:line | testitem | root-cause fix | mechanism | class | recommended action |
|---|---|---|---|---|---|
| test_run_stochastic.jl:36 | run_stochastic: same-seed reproducibility (INFRA-04) | 26-05 | 26-05 registers named `Prev`/`Qrev` expressions and a named `smax_rev` constraint. `build_stochastic_welfare` calls `contribute!(ConvexBranchFlow)` once per scenario on ONE model, and only unregisters `(:v,:v̂,:P,:Q,:l,:cone,:vdrop,:cpydrop,:smax)`. So the second scenario fails with "object of name Prev is already attached". Once `Prev`/`Qrev` are made anonymous, the same failure moves to `smax_rev`. | CSB | Add `:Prev, :Qrev, :smax_rev` to the unregister list in `src/models/stochastic_welfare.jl` (~L296), or make `Prev`/`Qrev` anonymous and add `:smax_rev`. Verified in `fix`: passes. |
| test_run_stochastic.jl:90 | run_stochastic: WR-05 … infeasible_h mask | 26-05 | Same as above. | CSB | Same fix. Verified. |
| test_run_stochastic.jl:104 | run_stochastic: D-11 measurement-before-golden | 26-05 (error); 26-03/04 and 26-05 (golden underneath) | Same error as above. After the fix, the pinned `oos.welfare_gap` moves from −0.025156 to −0.018592. It is −0.019226 in `no05`, so 26-05 accounts for part of the move and the device fixes for the rest. | CSB → GM | Fix the collision first, then re-measure, repeat and re-pin with an old→new+cause note. |
| test_stochastic_welfare.jl:30 | stochastic_welfare: D-04 non-uniform probabilities … | 26-05 | Prev/smax_rev name collision. | CSB | Same fix. Verified. |
| test_stochastic_welfare.jl:206 (2 recs) | stochastic_welfare: D-06 PF-04 gate runs per scenario … | 26-05 | The pv-scale scan never sees the PF-04 throw it expects, because every build errors earlier on the name collision. So `tripped == false` and `trip_pv_scale == NaN`. | CSB | Same fix. Verified. |
| test_stochastic_welfare.jl:254 | … WR-10 D-08 S=1 anchor | 26-05 | Name collision. | CSB | Same fix. Verified. |
| test_stochastic_welfare.jl:310 | … WR-09 soc agrees across scenarios | 26-05 | Name collision. | CSB | Same fix. Verified. |
| test_stochastic_welfare.jl:353 | … WR-04 FourQuadBESS q nonanticipativity | 26-05 | Name collision. | CSB | Same fix. Verified. |
| test_stochastic_welfare.jl:418 | … WR-03 device-composition congruence guard | 26-05 | Name collision. | CSB | Same fix. Verified. |
| test_pricing_dlmp.jl:128 | dlmp: decompose_dlmp four components SUM to the DADP on IEEE-13 | 26-05 | IEEE-13 ground has PV back-feed on the limited head branch at t = 9–16 (P ≈ −0.064). The receiving-end cone now binds there instead of the sending-end one: `|dual smax_rev|` is 8.5–9.3 while `|dual smax|` is about 7e-6. `decompose_dlmp` reads only `:smax`, so the congestion component vanishes (residual 6.23 at bus 10, t = 9). 26-06 re-certified the formula before 26-05 was merged. In the `no05` world the old model violated eq. 3.37 by 1.7% (\|S_recv\| = 0.0698 > smax 0.0686). | CSB | Add the `:smax_rev` dual to `decompose_dlmp`'s congestion term. Its cone is on (P−r·l, Q−x·l), so it enters both the P slot and the l stationarity. Re-derive the sign empirically against the hard sum-to-price assertion, as 26-06 did. |
| test_admm_knifeedge_canary.jl:53 (2 recs) | admm knife-edge canary: IEEE-13 mid-loop SOCP pinned trajectory | 26-05 | The binding `:smax_rev` (see above) changes the DSO-OPT feasible set on IEEE-13: iters 58 → 57, welfare −4822.9036 → −4822.9487. The item passes in `no05`. The trajectory is unchanged by 26-04 only because ADMM ignores FIX-05 (see test_admm.jl:121). | GM (blocked) | Re-pin only after the DsoOpt reactive fix, which will move the trajectory again. Use the repro script `26-08-repro-restricted-and-canary.jl`. |
| test_mpc_loop.jl:17 | mpc_loop: end-to-end closed loop on the happy-path CI fixture | 26-03 | `run_mpc` in `src/experiments/mpc_loop.jl` (outside 26-03's audited `src/models/`) still sets `terminal_param = soc_da[min(t+H-1, T)]`. But `build_mpc_window` now pins `soc[H+1]`, the state after the window, whose day-ahead counterpart is `soc_da[t+H]`. The window's end state is therefore pinned to the day-ahead state from one hour earlier. The resulting drift makes a later window PRIMAL_INFEASIBLE. The drift is inferred; the fix below is verified. | CSB | In `run_mpc`, build `soc_da` over `1:(T+1)` and target `soc_da[t + H]`. Verified in `fix`: passes. |
| test_mpc_loop.jl:323 | mpc_loop: mpc_step genuinely strides the resolve cadence | 26-03 | Same stale index. | CSB | Same fix. Verified. Separately, the WR-02 `mpc_step ≤ H−1` guard's battery rationale ("H-th control uncovered") is obsolete after FIX-04; it remains valid only for Thermostatic. |
| test_mpc_terminal.jl:33 | mpc_terminal: hard terminal-SOC condition prevents end-of-horizon dump/hoard | 26-03 | The test's hand-rolled loop has the same stale target (`soc_da_bus[min(t+H-1, T)]`, with `soc_da` taken over `1:T`) → INFEASIBLE. | CSB | Build `soc_da` over `1:(T+1)` and target `soc_da_bus[t + H]`. Verified: passes with dev_disabled 4.35e-7 and dev_enabled 2.69e-10 (1620×, against the originally measured 35,500×). Update the header's measured-margin note. |
| test_admm.jl:121 | admm: cross-validation ieee13 welfare + DADP | 26-04 (+07) | In OFF/CERTIFIED mode, `build_dso_opt` models the aggregator reactive draw as the constant −Pdc·tanφ (`src/admm/DsoOpt.jl` ~L320). Since FIX-05, the centralized `Aggregator` also writes p_flex·tanφ from Thermostatic/Deferrable/Interruptible into `:Rq`. ADMM therefore solves a different problem from the centralized model, and λ disagrees. The WR-04 fail-loud guard only inspects device-level `q_inject`, so the drop is silent: exactly the failure WR-04 exists to prevent. The item passes in `no0407` and `c0204`. | CSB (design) | Either extend the WR-04 guard to throw when any aggregator has an `is_flexible_load` member under OFF/CERTIFIED, or carry the flexible-load q through AGR→DSO (as `:live` already does via `res.q_inject`). Needs a design choice; see user-decision list, item 5. |
| test_acceptance.jl:82 (2 recs) | acceptance: IEEE-13 congestion — exact relaxation + DADP + ADMM≈centralized | Record 1: 26-04. Record 2: 26-04, 26-05 (26-03 negligible) | Record 1 (L82, ADMM λ ≠ centralized): same DsoOpt reactive drop. Record 2 (L89, `v9_16` golden): same move as ieee13:213 below. | CSB + GM | Record 1: DsoOpt fix. Record 2: re-pin together with ieee13:213. |
| test_ieee13.jl:213 (3 recs) | ieee13 ground: pinned computed golden regression + thesis v₉[16] cross-check | 26-04 (dominant), 26-05, 26-03 (tiny) | Real physics changes. Flexible-load reactive draw lowers voltages and tightens head-branch congestion. The back-feed receiving-end limit binds (26-05). Values: v9_16 1.04361 → 1.03604 (`no0407` 1.04174, `no05` 1.03800); DADP16 1.4024 → 0.3938 (`no0407` 1.3950); ΣDADP 96.717 → 86.846. The welfare golden still passes (−4823.50 against −4823.16 at rtol 1e-4). The gap in the non-failing thesis cross-check grows from 0.0057 to 0.0133, so that check becomes BROKEN. This accounts for +1 of the +2 broken. | GM | Re-derive after the CSB fixes, with an old→new+cause note. Flag the −72% DADP16 move and the larger distance from thesis Fig 4.4 for Phase 28; see user-decision list, item 6. |
| test_pricing_fit.jl:200 | fit: FIT-vs-DADP ratio regression golden (EXP-04) | 26-03 | FitFixtures has T = 4 and a PVBattery. The old model's free hour-T discharge was 25% of the horizon. With it gone, the ratio moves 0.64281 → 0.77202. The item passes in `no03` only. | GM | Re-pin with an old→new+cause note (FIX-04). |
| test_pricing_welfare.jl:193 (2 recs) | welfare surplus accounting: net-EXPORTER earns | 26-03 | T = 3, soc0 = 1, Emin = 0. The old model let the battery discharge at hour 3 for free (≈0.5 × λ = 40 ≈ +20). Prosumer surplus goes 65.594 → 47.387 and DSO surplus 0.397 → 0.202. The item passes in `no03` only. | GM | Re-pin both values with a FIX-04 note. |
| test_pricing_dlmp.jl:22 | dlmp: extract_dlmp on a lossless 2-bus is positive and ≈ λ₀ | 26-03 **and** 26-05, each independently (fails in every single revert; passes at f677965 per D-26-01) | Precision floor, not a relaxation gap. On r = x = 1e-6 the loss current `l` has an objective weight of r·λ ≈ 4e-5. Clarabel's `tol_gap = 1e-8` therefore stops with `l` about 7.5e-5 above the cone (gate ratio 4.04). Any change to the IPM path trips the gate: 26-03's extra `soc[T+1]` and 26-05's extra (slack) cone on this `smax = 10` branch, which is a *limited* branch. The ladder settles it: ratio 4.04 at 1e-8, 0.017 at 1e-10, 3.3e-4 at 1e-12, with the objective fixed at 47.799146. This answers D-26-01: it is not soc[T+1]/Emin blocking cycling. | CSB-num | Pass a tightened SOCP optimizer (`select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)`) in this fixture, or make it less degenerate (r ≥ 1e-3). Never loosen the gate. See user-decision list, item 4. |
| test_pricing_dlmp.jl:221 | dlmp: decompose_dlmp has ≈0 congestion/voltage on an uncongested in-bound 2-bus | Same as :22 (D-26-01) | Same fixture and mechanism. The gate throws before `decompose_dlmp` runs. | CSB-num | Same. |
| test_pricing_welfare.jl:66 | welfare surplus accounting: near-lossless 2-bus identity | 26-03 / 26-05 / 26-02 all perturb (fails in every snapshot, including `c0204`) | r = 1e-6 variant of the same fixture. Ladder: ratio 3.985 at 1e-8 and 3e-9, 0.33 at 1e-9, 0.016 at 3e-10; objective unchanged. | CSB-num | Same as :22. |
| test_admm.jl:27 | admm: cross-validation 2-bus welfare + DADP sign | 26-03 (passes in `no03` only) | Phase6 two-bus (r = x = 1e-3, tiny loads). Ladder: ratio 4.00 at 1e-8, 1.4e-3 at 1e-10, 6.4e-5 at 1e-12; objective −483.819124 unchanged. | CSB-num | Tightened optimizer for the centralized reference solve in this fixture family. |
| test_admm.jl:127 | admm: dual-ascent loop converges + fails loud on the cap | 26-03 | Same fixture and gate. | CSB-num | Same. |
| test_planning_oracle.jl:269 | planning oracle: ConvexBranchFlow solve runs the PF-04 exactness gate | 26-03 | Same Phase6 two-bus free solve. | CSB-num | Same. |
| test_admm_reactive.jl:286 | admm reactive: :live welfare/λ/μ cross-validated … | 26-03 (passes in `no03` only) | μ ≈ 0 on this near-lossless uncongested 4Q fixture (the degeneracy is documented). Elementwise, μ_c ≈ 1–3e-8 and res.mu_q ≈ 1e-9, but the vector norm ‖Δμ‖ ≈ 1.1e-7 exceeds the measured atol of 1e-7 (the earlier measurement was 1.6e-8). The FourQuadBESS `soc[T+1]` change moved the degenerate noise. | CSB-num (measured tolerance) | Re-measure the 5-seed μ sweep (D-14) and re-pin the tolerance with a note; alternatively compare with an elementwise max-abs. |
| test_acceptance.jl:100 | acceptance: IEEE-123 voltage — exact relaxation … | 26-02 **+** 26-04 jointly (cured by reverting either one) | IEEE-123 real-impedance precision floor. Ratio 3.94 and gap 4.4e-6 at 1e-8; ratio 0.084 and gap 9.5e-8 at 3e-9 or tighter. The objective changes by 1.6e-9 relative. This is the same band as the documented v2.1 IEEE-123 noise-floor artifacts (see memory). | CSB-num | Calibrate the IEEE-123 SOCP `tol_gap` (3e-9 is enough here; 1e-10 with tol_feas tightened failed) using the Phase-25 noise-floor ladder. Do not loosen the gate. |
| test_ieee123_admm.jl:22 | ieee123 admm: end-to-end converge + DADP cross-validation | 26-02 + 26-04 | Same centralized IEEE-123 reference solve. | CSB-num | Same. |
| test_ieee123_admm.jl:105 | ieee123 admm: voltage-binding margin | 26-02 + 26-04 | Same. | CSB-num | Same. |
| test_thesis_repro.jl:62 | thesis_repro: IEEE-123 real-impedance DADP-vs-FIT — DSO-surplus sign flip | 26-02 + 26-04 | Same IEEE-123 gate. The REPRO-01 sign-flip result cannot be assessed until the gate is recalibrated. | CSB-num | Same. Then re-check the sign flip (Phase 28). |
| test_mesh_flow.jl:4 | MeshedFlow solves the loop fixture on both impedance profiles | 26-04 (+07) | `mesh_aggregators()` models loads as Thermostatic (p pinned, Pdc = 0), so before FIX-05 they drew no reactive power, matching spike Case A's active-only design. They now draw q = p·tan(acos 0.95). On the uniform-R/X diamond the SOC relaxation becomes **genuinely** inexact: ratio 2711 and gap 0.0147, persistent across the tolerance ladder. The heterogeneous profile stays exact. With the per-device override φ = 1.0 the uniform case is exact again (ratio 0.006). | RF | User decision (item 3): pin φ = 1.0 in the fixture to preserve the MESH-02/03 intent, or adopt and document "meshed SOCP exactness on the uniform diamond is lost once loads draw reactive power". |
| test_mesh_angle_certificate.jl:4 | certify_angle_recoverable!: both fixture profiles … | 26-04 | Same fixture and gate. | RF | Same decision. |
| test_mesh_angle_certificate.jl:97 | certify_angle_recoverable!: reversed-orientation re-encoding | 26-04 | Same. | RF | Same decision. |
| test_ac_oracle.jl:182 | ac_oracle: high-PV stress fixture … (EXACT-04) | 26-04 exposes a latent App. C flaw | The AC (Ipopt) solve on EXACT-04 now has simultaneous charge and discharge at bus 2, t = 7 (p_ch = 0.00256, p_dch = 0.00305). The AC complementarity τ is 1e-6·Pmax², so the gate trips. Both Ipopt strategies agree to 7 digits, so this is an optimum, not noise. The App. C utility gives it exactly. With both legs interior, KKT requires (λ_med − DLMP)(1/η² − 1) = b_dch·p_dch + b_ch·p_ch/η². Observed: 0.1504 against 0.1505 (DLMP 4.809 < λ_med 6.2, η = 0.95). An SOC-neutral round trip earns (λ_med − DLMP)(1 − η²) > 0 whenever DLMP < λ_med and both legs are small. The "strict λ_min < λ_med < λ_max ⇒ p_ch·p_dch = 0" argument ignores η. FIX-05 moved the operating point into that band. SOCP's τ = 1e-3 masks the same effect. | RF (latent model flaw) | User decision (item 2). This is not a 26-04 bug; 26-04 is correct. |
| test_restricted_branch_flow.jl:61 | restricted_branch_flow: measured Gan-Low modification gap ε on EXACT-04 | 26-04 (App. C) | Same AC complementarity throw. The item passes in `no0407`. | RF (via item 2) | Resolves with the App. C decision. Then re-measure `_EXACT04_MEASURED_ε` with the 26-08 repro script. |
| test_restricted_branch_flow.jl:145 | restricted_branch_flow: plain ConvexBranchFlow on EXACT-04 is UNCHANGED … | 26-04 (App. C) | Same throw. Passes in `no0407`. | RF (via item 2) | Same. |
| test_restricted_branch_flow.jl:231 | restricted_branch_flow: assert_restriction_exact! certifies PHYSICAL AC-feasibility … | 26-04 (surface), **26-02** (underneath) | Surface: the AC complementarity throw. Underneath (`no0407`): the test expects the *unrestricted* default to be AC-infeasible and `:cert_failed`. With the Gan–Low copy it is AC-feasible and `:certified_convex_dual`. The item passes only when 26-02 is also reverted (`c0204`). | RF | User decision (item 1). |
| test_restricted_branch_flow.jl:398 | restricted_branch_flow: ac_dual_fallback_price triggers only after an observed certificate failure … | 26-04 (surface), **26-02** (underneath) | Same pattern: `cert_failing.ac_feasible` is now true, so no certificate failure occurs to fall back from. | RF | Item 1. |
| test_mpc_loop.jl:95 (2 recs) | mpc_loop: forced-inexact window escalates through Phase-20's ladder | 26-02 | The Phase-21 high-PV MPC fixture was tuned (`MPC_HIGH_PV_SCALE_MEASURED`) to make the SOC relaxation inexact under the old copy. Under the Gan–Low default the same window is exact (cone ratio 0.0235), so no escalation happens and `cert_status` is `:certified_convex_dual`. The item passes in `no02` only. | RF | Item 1. The test intent (exercising the escalation ladder) needs a new forcing mechanism, e.g. `ConvexBranchFlow(thesis_literal = true)` or a re-measured fixture. |
| test_mpc_loop.jl:187 (4 recs) | mpc_loop: escalation at t > 1 prices the CURRENT window | 26-02 | Same; cone ratios 0.0235 and 0.0059. | RF | Item 1. |
| test_mpc_loop.jl:294 (5 recs) | mpc_loop: ladder terminal failure publishes :cert_failed … | 26-02 | Same precondition (no inexactness), so no `:cert_failed`, no fallback price, and no `:local_ac_dual` at t = 3. | RF | Item 1. |

## Root-cause clusters (41 testitems, 55 records)

| # | Cluster | Fix | Class | Testitems | Records |
|---|---|---|---|---|---|
| A | Named `Prev`/`Qrev`/`smax_rev` collide in the per-scenario stochastic build | 26-05 | CSB (fix verified) | 9 | 10 |
| B | `decompose_dlmp` ignores the binding `:smax_rev` dual (IEEE-13 back-feed) | 26-05 | CSB | 1 | 1 |
| C | MPC terminal target not re-indexed to `soc[H+1]` in `run_mpc` and in the mpc_terminal test | 26-03 | CSB (fix verified) | 3 | 3 |
| D | ADMM DsoOpt OFF/CERTIFIED silently drops the flexible-load reactive draw | 26-04 | CSB (design) | 1 (+ acceptance:82 rec 1) | 2 |
| E | PF-04 gate tripped at the solver-precision floor. Near-lossless 2-bus: 26-03/26-05. Phase6 2-bus and 4Q μ: 26-03. IEEE-123: 26-02 + 26-04. The true optimum is exact in every case (ladder-verified). | mixed | CSB-num | 11 | 11 |
| F | Legitimate physics golden moves: ieee13 (26-04 ≫ 26-05), FIT ratio and exporter surplus (26-03), acceptance:82 rec 2, canary (26-05, blocked on D) | 26-03/04/05 | GM | 4 (+ acceptance:82 rec 2) | 9 |
| G | Mesh diamond genuinely inexact once loads draw reactive power | 26-04 | RF | 3 | 3 |
| H | App. C no-simultaneity argument is false for η < 1 when DLMP < λ_med (EXACT-04 AC) | 26-04 (exposes) | RF | 5 (61, 145, ac_oracle, plus the surface error of 231/398) | 5 |
| I | Gan–Low default makes the high-PV/EXACT-04 fixtures exact and AC-feasible, because v̂ ≤ V²max is a conservative restriction | 26-02 | RF | 3 (+ 231/398 underneath) | 11 |

Record totals: A 10 + B 1 + C 3 + D 2 + E 11 + F 9 + G 3 + H 5 + I 11 = 55.

**No GENUINE REGRESSION was found.** Each fix does what it claims physically. Every failure is one
of: a missed downstream call site (A–D), a numerical gate artifact the fixes perturbed (E), a
legitimate golden move (F), or a substantive research consequence (G–I).

**Broken count 3 → 5.** Two thesis cross-checks (`@test gap < 1e-2 broken = …`) in test_ieee13 and
test_acceptance now report Broken. |V₉[16]| moved from 1.0436 to 1.0360, taking it further from the
thesis value of 1.0493 (the gap grows from 0.0057 to 0.0133). The main driver is 26-04. This is not
a failure, but it is relevant to Phase 28.

### Answer to "does SOCP exactness now fail widely under Gan–Low?"

**No.** Of the 13 PF-04 `SOCP relaxation INEXACT` throws in the log:
- **10 records are precision-floor artifacts (cluster E; the 11th cluster-E record is the μ-tolerance
  item).** A Clarabel `tol_gap` ladder drives every one of them to ratio ≪ 1 with the objective
  unchanged (≤ 1.6e-9 relative). The old copy was not
  what made them exact. They trip the gate because the fixes perturb the interior-point stopping
  point on near-lossless branches and on IEEE-123.
- **3 records are genuine (cluster G, mesh).** They are caused by FIX-05's reactive draw, not by
  Gan–Low: they fail identically in `no02`.

The Gan–Low default moves exactness the **other** way: fixtures that were inexact under the old copy
(EXACT-04, the Phase-21 high-PV MPC window) are now exact (cluster I). That is the substantive
research finding below.

## Anything that needs a USER research decision

1. **The Gan–Low default is a restriction on the upper voltage band, not "a genuine relaxation"** (26-02; cluster I).
   - *Evidence.* On EXACT-04 at pv 1.2:
     - Default SOCP optimum: **−921.754**. It is exact (ratio 0.017) with v̂ at V²max.
     - True AC optimum: **−921.277**. Two Ipopt strategies agree, and the AC formulation does not
       depend on 26-02.
     - The old literal copy gives −921.277 and is also exact.

     A relaxation of a maximisation can never have a *lower* optimum than a feasible AC point. The
     new default does, so on this fixture it is a restriction. This is Gan–Low's modified OPF:
     v̂ ≤ V²max is load-bearing (26-02's own test demonstrates this) and conservatively enforces
     v ≤ V²max. The old copy restricted the *lower* band instead.
   - *Consequences:*
     - The v2.1 "SOCP knife-edge under high-PV reverse flow" finding (EXACT-04; memory
       `v2.1-socp-inexactness…`) no longer reproduces under the default. In the `no02` world it does
       not reproduce even with the old copy.
     - ac_oracle:182, when it does run, now reports "inexact hours" that are really
       restriction-induced dispatch mismatches rather than a relaxation gap.
     - The Phase-20/21 escalation tests lose their forcing fixture.
     - The docstrings and the 26-02 verdict text calling the default a "genuine relaxation" are
       inaccurate.
   - *Decide:* (a) keep Gan–Low as the default. It is exact by theorem, conservative, and its
     welfare loss is measurable (≈0.05% here). If so, restate EXACT-04 and the docs, and re-force the
     escalation tests with `thesis_literal = true` or a new fixture. (b) Make the default a plain SOC
     relaxation with no upper copy bound (a true relaxation, which reinstates overvoltage
     inexactness). (c) Expose both and choose per experiment.
2. **The App. C "no-binary" guarantee is false when η < 1** (cluster H; exposed by 26-04, but pre-existing).
   - *Condition.* Simultaneous charge and discharge is optimal whenever DLMP < λ_med and both legs
     would be small, because an SOC-neutral round trip earns (λ_med − DLMP)(1 − η²). The observed
     EXACT-04 solution satisfies the KKT identity to 4 digits.
   - *Masking.* The SOCP gate's τ = 1e-3 hides it; the AC τ = 1e-6 catches it.
   - *Decide:* (a) accept it and document it, keeping the looser τ for AC; (b) re-parametrise, e.g.
     make the discharge intercept exceed λ_med/η² or add an η-aware round-trip penalty;
     (c) add a complementarity treatment (binary or MPEC) for validation runs.

   This affects every PVBattery result, not just EXACT-04.
3. **The mesh fixture's exactness depended on zero reactive load** (cluster G).
   - *Decide:* pin φ = 1.0 in `Phase23Fixtures.mesh_aggregators()` to keep the MESH-02/03 tests
     about angle recoverability, or treat "meshed SOCP exactness on the uniform diamond is lost at
     pf 0.95" as a finding (and possibly add it as a separate test).
4. **Solver-tolerance policy for PF-04 on near-lossless and large fixtures** (cluster E).
   - *Decide:* per-fixture tightened `tol_gap` (the 22-02 precedent was 5e-10), a global SOCP
     factory default change (risk: 22-02 saw 1e-10 trip ALMOST_OPTIMAL on lossier feeders, and here
     IEEE-123 failed with tol_feas tightened), or de-degenerated fixtures (r ≥ 1e-3). Whichever is
     chosen, it should be a calibrated policy, not an ad hoc loosening of the gate.
5. **ADMM reactive mode after FIX-05** (cluster D).
   - The OFF/CERTIFIED "constant reactive draw" assumption no longer matches the centralized
     physics once flexible loads draw q.
   - *Decide:* (a) default to `:live` when any flexible load is present; (b) fail loud (extend
     WR-04); or (c) keep OFF as an explicitly documented approximation. The IEEE-13 ADMM cross-check
     and the canary golden depend on this choice.
6. **Sign-off on large golden moves before re-pinning.**
   - IEEE-13 hour-16 DADP falls 72% (1.402 → 0.394), mostly from 26-04.
   - IEEE-13 |V₉[16]| moves further from the thesis (the cross-check turns Broken).
   - FIT ratio +20% (26-03).
   - Exporter surplus −28% (26-03).

   These are legitimate physics changes, but they reshape the headline numbers that Phase 28
   restates.

## Latent issues found (not currently failing)

- `ACPowerFlow` has no receiving-end limit (eq. 3.37). 26-05 added `:smax_rev` only to the
  Convex/Meshed/Restricted formulations. On IEEE-13, `:smax_rev` binds under back-feed, so any
  AC-oracle comparison on limited branches now compares different feasible sets.
- The `run_mpc` WR-02 guard's battery rationale ("dynamics-uncovered H-th control") is obsolete after
  FIX-04. It still holds for Thermostatic, whose recursion is still T−1.
- The deferred-items D-26-01 note calls the DLMP 2-bus fixture "uncongested", but its `smax = 10`
  branch is *limited*, so 26-05 adds a (slack) receiving-end cone there.

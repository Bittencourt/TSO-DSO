---
phase: quick-261008-tu1
plan: 01
subsystem: research-scripts
tags: [sdp, socp, td-coupling, admm, ac-opf, congestion, exactness, paper-backing]
requires: [TSODSO solver factory, ConvexBranchFlow, assert_socp_exact!, decompose_dlmp, recover_voltage_angles]
provides: [scripts/td_hybrid_6node_case_study.jl, results/td_hybrid_6node/*.csv, results/td_hybrid_6node/summary.txt, docs/writeups/td_hybrid_6node_case_study.typ]
affects: [scripts/README.md, docs/writeups/README.md]
tech-stack:
  added: []
  patterns: [framework-hosted DSO with unfixed root voltage, build-once/re-objective ADMM, measured-tolerance paper gate, guarded Typst figures via sys.inputs]
key-files:
  created:
    - scripts/td_hybrid_6node_case_study.jl
    - results/td_hybrid_6node/{summary.txt, baseline_prices.csv, baseline_point.csv, acopf_multistart.csv, admm_trace_rho500.csv, admm_rho_sweep.csv, admm_eps_sweep.csv, congestion_prices.csv, congestion_dlmp.csv, congestion_summary.csv, inexact_pv_sweep.csv}
    - docs/writeups/td_hybrid_6node_case_study.typ
  modified:
    - scripts/README.md
    - docs/writeups/README.md
decisions:
  - "Clarabel with equilibrate_enable=false at 1e-9: default equilibration stalls at ALMOST_OPTIMAL with ~7e-4 $/MWh dual error; the accurate solve reproduces Table III exactly (the reference's 3rd-decimal misses were solver accuracy)"
  - "Framework-hosted DSO works via unfix of ConvexBranchFlow's fixed root v/v_hat + v_root == W33; matches the paper model to 1e-6 $/h"
  - "Congestion at 0.9x flows is infeasible on the paper system (no redispatch); added a clearly-labelled out-of-merit G2 (node 2) + DG (node 6) extension, unity pf, baseline unchanged (asserted)"
  - "Inexact-regime search extended to PV at node 5 and lifted feeder ratings after stage A found none"
metrics:
  duration: ~3h
  completed: 2026-10-08
---

# Quick 261008-tu1: 6-node hybrid SDP-SOCP T&D paper case study Summary

One deterministic script reproduces the paper's monolithic optimum and ADMM run (57 iterations, matching the paper), confirms global optimality with Ipopt, measures the rho/eps guidance, and adds congestion and inexact-regime results. An English Typst writeup reports all of it, including disagreements and recommendations for the paper text.

## Commits

| Task | Commit | Content |
|------|--------|---------|
| 1 | eb9d3f9 | script: models, baseline gate, Exp 1 (Ipopt), Exp 2 (ADMM + sweeps); first CSVs + summary |
| 2 | cb4bd14 | Exp 3 (congestion), Exp 4 (inexactness), 6 figures, verdicts; determinism verified |
| 3 | 6963b0f | Typst writeup, README index rows, JuliaFormatter 2.10 formatting |

## Headline numbers

- **Baseline:** the gate PASSED. Cost 7461.1052 $/h (paper 7461.105). All 12 prices are within 4.7e-4 $/MWh of Table III, and the duals agree with finite differences to 3.2e-5. |l2/l1| = 1.0e-11 and cone residuals are <= 4.7e-10. The framework-hosted DSO matches the paper model (cost diff 9.9e-7 $/h).
- **Exp 1:** 26/26 Ipopt starts reach one optimum, 7461.105178 $/h. Gap -4.0e-10 (zero within tolerance). Recovered voltages differ from the AC optimum by at most 1.25e-8 pu, and their AC mismatch is <= 7.9e-10 pu.
- **Exp 2 (rho=500, eps=1e-2):** 57 iterations (paper 57). Primal residual 9.08e-5 (paper 9.1e-5), ADMM cost 7460.537 (paper 7460.537). Prices settle from iteration 39 (paper ~40). -lambda_p = 6258.8038 = piP3*100. **Disagreement:** dual residual 1.02e-3 vs the paper's 1.8e-3.
- **rho sweep:** iterations are 523/264/135/57/31/18/11/8/9 for rho = 50...20000. The fastest settings (5000-20000) bracket piP3*100 = 6259, so the paper's guidance holds. rho=500 is about 10x below the fastest setting.
- **eps sweep:** iterations stay at 57 for every eps including 0. The largest cone residual over all DSO iterates is <= 2.7e-9 and the final bias is identical, so "eps small or zero" holds on this case. The writeup qualifies it as conditional on a positive boundary price.
- **Exp 3, paper system:** the planned 0.9x limits are infeasible on both line (1,2) and the feeder head. The relaxation certifies this, and Ipopt finds no AC point. The feasible bands are degenerate: line (1,2) can drop to 1.137122 in the relaxation but not at all in AC (1.138073), and the head band has zero width. Inside the line band the SDP is not rank-one (1.45e-4), Ipopt finds no AC point and ADMM does not converge. Inside the head band the duals are non-unique (node 4 priced 187 vs 97 vs ~63 $/MWh).
- **Exp 3, out-of-merit G2/DG extension:**
  - Costs: +1.40 % (line), +0.22 % (head), +1.47 % (both).
  - Both relaxations stay exact, and the AC gap is <= 2e-9.
  - ADMM converges in 45/57/46 iterations, and -lambda_p = piP3*100 holds.
  - The DLMP decomposition sums to the price within 1.4e-14 (congestion component 5.51 $/MWh under head congestion).
- **Exp 4:**
  - With Table I ratings (stages A/B), the relaxation is exact at every feasible point. Its infeasibility coincides with AC infeasibility (PV cap 0.45 pu at node 6, 0.80/0.70 pu at node 5).
  - With lifted ratings (stage C), there is an inexact regime beyond the AC hosting limit: 51 points where the relaxation is feasible and priced but no AC point exists. Cone residuals reach 4.81/7.33/5.70 pu.
  - In the surplus case at 25 % load (Pg = 0), the SDP also loses rank one (|l2/l1| 4.2e-4 to 4.6e-3).
  - The exactness copy is conservative by 8e-5 to 5e-4 with Table I ratings and by up to 2.9 % with lifted ratings. It is itself inexact at AC-feasible PV 0.80 (100 % load) and 0.70 (50 % load), and it narrows but does not remove the falsely feasible range.

## Deviations from Plan

1. **[Rule 1 - Bug/accuracy] Clarabel setting.** Default equilibration stalls at ALMOST_OPTIMAL with dual errors of about 7e-4 $/MWh. The script uses `equilibrate_enable=false` at 1e-9 (measured, documented), with a one-time equilibrated retry when a solve fails numerically. As a result the 3rd-decimal Table III differences mentioned in the plan disappear: the paper is right and the earlier reference had a solver-accuracy problem.
2. **[Rule 3 - Blocking] Congestion design.** The planned 0.9x limits are infeasible on the paper's system. Experiment 3 now reports that infeasibility, the feasible-band analysis (relaxation and AC) and the band-midpoint pathologies. It then runs the planned 0.9x limits on a clearly-labelled out-of-merit G2/DG extension. A first G2 version had a free reactive range, which changed the baseline by 7.4 $/h; it was fixed to unity power factor, and baseline invariance is now asserted.
3. **[Plan-sanctioned extension] Exp 4 search.** The search was extended with PV at node 5 (stage B) and lifted feeder ratings (stage C), because stage A found no slack regime. The "with copy" sweep uses the script-local mirror of the framework copy. The framework-hosted model is reported alongside; it adds a receiving-end cone, which differs by 26 $/h only in stage B at 50 % load.
4. **Typst figures.** A plain `typst compile` cannot read `../../results` because the project root is the document directory, and the precedent document fails the same way. Figures are therefore guarded by `--input figures=on` (with `--root .`). The plain compile, as in the plan's verify command, succeeds and shows file references.
5. **check_planning_ids.py scope.** The checker fails closed on `docs/writeups` and `results` (they are out of its scope, exit 2). It was run on `scripts` (clean), and the writeup, summary and READMEs were grepped manually; the only hits were false positives (P34, @quickactivate, a pre-existing v2.0 line).
6. **Worktree base.** The worktree started at fb28fb4 and was hard-reset to a32242f as instructed.

## Known Stubs

None.

## Threat Flags

None. The script is local and offline. The paper text stays in .planning (main tree only), and the writeup quotes numbers only.

## Self-Check: PASSED

- Files exist: script, 11 CSV/TXT outputs, the .typ writeup, and both README rows (check_scripts_index OK; check_script_api OK).
- Commits eb9d3f9, cb4bd14 and 6963b0f are present on branch worktree-agent-a029068154972a35f.
- Two full runs (plus a post-format run) give identical CSV/TXT outputs. src/ is untouched, and no new file contains @testitem.

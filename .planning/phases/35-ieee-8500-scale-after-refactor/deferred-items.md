
## 35-02 (2026-10-04)
- test/test_benchmark_ieee8500.jl Test 2 golden is STALE (pre-existing, verified against HEAD harness before plan 35-02 edits): the `--quick` point now yields model_vars=137258 / model_cons=274570, golden pins 137144 / 274218 (fixture topology drifted after the 2026-08-22 pin). The 2 failing assertions abort the script before the appended 35-02 testset, so that testset was verified in isolation. Re-pin (measure-before-golden, 2-run stability) belongs to a separate task. Also: the existing run_quick() writes into the committed density_sweep.csv (restore with `git checkout -- results/` after running).

## 35-05 (2026-10-04) RESOLVED: the 35-02 stale golden was re-pinned to 137258 / 274570 with a bisected cause (cfa7e6e 26-03 battery soc T+1: +114 vars/+342 cons; 30f53e4 26-05 :smax_rev cone: +10 cons = T). run_quick() now writes to a tmpdir (--results-dir). Whole file passes (10 + 17).

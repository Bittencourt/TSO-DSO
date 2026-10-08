# Phase 38 Final Gates (plan 38-10)

Static gates run at HEAD ab18f3e (plans 38-01..09 complete), clean tree. Pre-flight: `pgrep -af julia` empty
(only the earlyoom daemon and the probing shell), `git worktree list` has no `.claude/worktrees/agent-*`
entry (the two sibling worktrees live under `../TSO-DSO.worktrees/`, outside the repo), no untracked `.jl`
files. The only ignored `.jl` under `.planning/tmp` that mentions `@testitem` is
`.planning/tmp/37/check_tag_only_diff.jl`, as a string literal `Symbol("@testitem")`, not a macro call;
discovery is rooted at `test/` and count-sets reports `outside=0`. Toolchain: `julia +release` = 1.12.5,
`julia +1.12` = 1.12.7.

EXPECTED_COUNT_SETS=count-sets: all=517 fast=480 slow=37 files=99 canary=1 outside=0

The expected line is the ledger's running total (38-MEASUREMENTS.md, 38-07 T2 row): baseline
all=511 fast=474 slow=37 files=98, then +1 (38-02 MPC regression item), +1 (38-04 OOS inexact-refusal item),
+2 items and +1 file (38-06 `test_admm_timeout.jl`), +2 (38-07 ADMM import-only rejection, stored Symbol
reactive mode). All additions are fast items.

## Static and hygiene gates

| Gate | Command | Result |
|---|---|---|
| Formatter | `julia --startup-file=no .github/scripts/format210.jl src ext test docs` (JuliaFormatter 2.10.2) | no changes; `git status --porcelain` empty |
| Content loss | `python3 .github/scripts/check_content_loss.py HEAD` | `OK: no content change` (219 tracked .jl files) |
| Planning-ID guard | `check_planning_ids.py` / `--selftest` | OK, 250 files / selftest OK (42 positive, 24 negative, 10 fail-closed) |
| Scripts index | `check_scripts_index.py` / `--selftest` | complete (37 tracked files) / selftest OK |
| Setup names | `check_setup_names.py --selftest` / plain | selftest OK (4 cases) / 21 testmodules, 222 setup uses, 0 unresolved |
| Script API | `julia +release --project=. --startup-file=no .github/scripts/check_script_api.jl` / `--selftest` | `OK: 40 files checked` / selftest OK (55 cases) |
| Runner selftest | `run_tests_filtered.jl "$PWD" --selftest` (1.12.5) | selftest OK (probe item Broken 2 by design) |
| count-sets | `run_tests_filtered.jl "$PWD" --count-sets --strict` (1.12.5) | `count-sets: all=517 fast=480 slow=37 files=99 canary=1 outside=0`, exit 0; equals `EXPECTED_COUNT_SETS` |
| JET 1.12.7 | `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +1.12 --project=. -t2 scripts/jet_check.jl` / `--selftest` | `12 current, 12 baseline, 0 NEW, 0 FIXED`, exit 0 / selftest OK (`scripts/jet_baseline.txt` not touched in Phase 38) |
| Workflows | `yaml.safe_load` of CI.yml and slow.yml | both parse; CI.yml format job runs `check_setup_names.py --selftest` and plain (lines 166-167) |
| tmp / Manifest | `git ls-files .planning/tmp Manifest.toml` | empty |
| src diff | `git diff --shortstat 4ab43d6 HEAD -- src` | 9 files, 314+/156-: shared cone-check kernel (exactness.jl), MPC first tier (mpc_loop.jl), OOS gate (stochastic_welfare.jl, run_stochastic.jl), ADMM import-only rejection (Scenario.jl, sweep.jl), Symbol reactive mode (store.jl), prose (TSODSO.jl), status vocabulary `:oos_inexact_skipped` (errors.jl). No canary or golden value edited |

## Cross-version checks

Copied from 38-MEASUREMENTS.md. Both measured locally on 1.10.11 and 1.11.9 with the committed code and
unmodified `Manifest-v1.10.toml` / `Manifest-v1.11.toml`, scratch scripts only.

- MPC (plan 38-02): regression point unperturbed `:certified_convex_dual` (ratio 0.0114); with the 5e-7
  slack, old flat ratio 0.4993, hybrid ratio = `cone_maxratio` = 2.4571 (exact equality), cert status
  `:certified_convex_dual_restricted` with 3 finite prices; happy-path scenario A `:certified` with
  7 x `:certified_convex_dual`, worst hybrid ratio 0.9383 (t=4). Identical on 1.10 and 1.11. Every
  assertion of the new item holds.
- Stochastic (plan 38-04): CI golden `:solved`, no draw inexact or infeasible, max ratio 0.3660,
  `welfare_gap` -0.018591711034105174 (rel. diff 0 against the pin); pin-binding fixture at the default
  optimizer throws `CertificateError` (`:socp_exact`, ratio 51.23); tightened-optimizer harness fixtures
  (build-once 0.0119/0.4964/0.0088, pin-binding 0.3889/0.3538, FourQuadBESS q pin 0.0370, infeasible ->
  recover `(NaN, true, false)` then ratio 0.0778); FourQuadBESS at the default optimizer 0.3729. Identical
  on 1.10 and 1.11. Every new assertion holds.

Nothing was recorded as "not measurable locally", so no cross-version item is a CI risk beyond the
Actions run itself (see MANUAL).

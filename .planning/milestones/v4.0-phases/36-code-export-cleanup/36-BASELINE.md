# Phase 36 Baseline (captured before any source edit)

## Numbers

| Item | Value |
|---|---|
| Phase base commit | 801fb0c (docs-only difference to the Phase 35 close commit; HEAD at capture 388b907 plus tooling commits) |
| Phase 35 close suite | 32177 pass / 0 fail / 0 error / 5 broken (STATE.md) |
| Canary (ADMM knife-edge, IEEE-13) | `iters = 56`, `welfare = -4823.66604824162` (re-measured 2026-10-05 via the filtered runner, 2 pass, 1m01s). Never re-pinned. |
| Aqua direct script | 8/8 checks pass on this checkout (ambiguity, unbound params, undefined exports, Project/test Project, stale deps, compat, piracy, persistent tasks) |
| Unique exports | 196 (`length(names(TSODSO))-1`) |
| Classifier total over scope (`classify_planning_ids.py --count`) | 6494 lines (src alone: 2777) |
| Worktrees | none under `.claude/worktrees`; two sibling worktrees under `../TSO-DSO.worktrees/` (not discovered) |

## Golden-bearing test files (never re-pin)

fixtures_phase19.jl, fixtures_phase4.jl, fixtures_planning.jl, test_acceptance.jl, test_admm_phases.jl, test_admm_reactive.jl, test_benchmark_ieee8500.jl, test_fourquadbess.jl, test_ieee13.jl, test_ieee8500.jl, test_planning_benders_integer.jl, test_planning_certification_bilevel_interior.jl, test_planning_certification_bilevel.jl, test_planning_certification_integer.jl, test_planning_goldens.jl, test_planning_master_integer.jl, test_planning_nash_integer.jl, test_pricing_fit.jl, test_pricing_welfare.jl, test_pvbattery.jl, test_restricted_branch_flow.jl, test_run_stochastic.jl, test_thesis_repro.jl, plus test_admm_knifeedge_canary.jl (canary).

Use `ast_equiv.jl --literals HEAD <file>` to prove numeric literals untouched even after renames.

## Reusable recipes (all from the repo root)

```bash
# Fast runner (several specs OR-combined; file: takes comma lists). ~25-30 s startup.
JULIA_LOAD_PATH="@:test:@stdlib" julia --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:test_oracle.jl,test_dso.jl tag:ieee8500

# Aqua (items doing `using Aqua` fail under the fast runner; use this direct script)
JULIA_LOAD_PATH="@:test:@stdlib" julia --project=. -e 'using TSODSO, Aqua, Test; Aqua.test_all(TSODSO)'

# Static oracles
julia --startup-file=no .github/scripts/ast_equiv.jl HEAD <files...>              # EQUAL/DIFF, exit 1 on DIFF
julia --startup-file=no .github/scripts/ast_equiv.jl --strings HEAD <files...>    # added/removed string literals (message changes)
julia --startup-file=no .github/scripts/ast_equiv.jl --literals HEAD <files...>   # numeric literal multiset
python3 .github/scripts/thesis_tokens.py HEAD <files...>                          # OK / DIFF
python3 .github/scripts/classify_planning_ids.py [paths] [--count|--hand]
python3 .github/scripts/check_setup_names.py [--tags]                             # every setup=[X] has a @testmodule X
python3 .github/scripts/unexport_migrate.py scan|apply --names FILE paths...
julia --startup-file=no .github/scripts/format210.jl <paths...>                   # JuliaFormatter 2.10.2 in a temp env
python3 .github/scripts/check_content_loss.py HEAD                                # run BEFORE committing formatter output

# Detached full suite (never foreground; never two Julia suites at once)
pgrep -af julia; git worktree list      # checklist: no stray julia, no .claude/worktrees/agent-*
bash .github/scripts/suite_detached.sh LABEL                                      # Pkg.test; docs: ... LABEL julia --project=docs docs/make.jl
# wait for the background-completion notification, or poll with bounded calls:
python3 .github/scripts/check_suite_log.py LABEL --wait 540                       # exit 3 = still running
python3 .github/scripts/check_suite_log.py LABEL --mode docs                      # docs build
python3 .github/scripts/check_suite_log.py LABEL --same-pass-as OTHERLABEL        # pass counts equal
```

`check_suite_log.py` requires DONE = 0, log and start newer than the HEAD commit, the last Test Summary with fail = 0, error = 0, broken = 5, and the canary lines (`iters = 56`, `welfare = -4823.66604824162`).
Self-test: a failing command leaves DONE = 3 and the checker fails; `true` leaves DONE = 0 and the checker still fails (no Test Summary block).
Scratch output lives in `.planning/tmp/36/` (gitignored).

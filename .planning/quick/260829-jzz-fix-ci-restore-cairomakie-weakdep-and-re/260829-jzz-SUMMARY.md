---
quick_id: 260829-jzz
subsystem: infra
tags: [ci, manifests, weakdeps, cairomakie]
date: 2026-08-29
status: complete
---

# Quick Task 260829-jzz — SUMMARY

**Task:** Fix CI — restore CairoMakie as a weakdep and revert Manifest-v1.12.toml to its
pre-f44ada4 state (CI red on main after "new MPC demo")

**Status:** COMPLETE — Task 1 committed as `bed47c6`; Task 2 verification all green.

## What was done

### Task 1 — revert Project.toml + Manifest-v1.12.toml to f44ada4~1 (commit `bed47c6`)

- `git show f44ada4~1:Project.toml > Project.toml` — CairoMakie back under `[weakdeps]`
  (line 18), `[extensions] TSODSOMakieExt = "CairoMakie"` intact (line 25),
  `[compat] CairoMakie = "0.15"` intact (line 31). No `CairoMakie` under `[deps]`.
- `git show f44ada4~1:Manifest-v1.12.toml > Manifest-v1.12.toml` — the ~1150-line
  hard-dep CairoMakie/Makie tree dropped; 0 `[[deps.CairoMakie]]` entries.
- Identity gate: `git diff --quiet f44ada4~1 -- Project.toml Manifest-v1.12.toml` →
  IDENTICAL. `git diff --name-only f44ada4` → exactly those two files.
- Commit: `bed47c6 fix(quick-260829-jzz): restore CairoMakie weakdep + revert
  Manifest-v1.12 (CI red after f44ada4)`

### Task 2 — verification (all exit 0)

| # | Check | Result |
|---|-------|--------|
| 1 | `julia +1.10 --project=. -e 'Pkg.instantiate()'` | ✅ OK (pre-existing harmless project_hash warning — same warning existed on green CI at 1fabbfe) |
| 2 | `julia +1.11 --project=. -e 'Pkg.instantiate()'` | ✅ OK |
| 3 | `julia +1.12` `using TSODSO` + `@assert "CairoMakie" ∉ keys(Base.loaded_modules)` names | ✅ "TSODSO loads; CairoMakie NOT loaded (weakdep form)" |
| 4 | Aqua testitem on 1.12 (`JULIA_LOAD_PATH` + TestItemRunner, filter "Aqua package checks") | ✅ 11 Pass / 11 Total, 0 "Test Failed" |
| 5 | Manifest drift | ✅ `git status --short` shows only the untracked quick-task dir; no `Manifest*.toml` rewritten |

Notes on check 3: first invocation hit a Julia 1.12 API change — `Base.loaded_modules` is a
`Dict`, not callable (`Base.loaded_modules()` threw `MethodError: objects of type
Dict{Base.PkgId, Module} are not callable`). The check was rewritten as
`[id.name for id in keys(Base.loaded_modules)]` — same assertion, correct API.

Notes on check 4 (two runs):
- Run 1 (plan's verbatim form) FAILED with an **Aqua harness infrastructure flake**, not a
  package regression: `Unexpected error: /tmp/jl_QvCBkjkHO1/done.log was not created, but
  precompilation exited` — the persistent_tasks sandbox package failed to precompile after
  "31 dependencies precompiled but different versions are currently loaded" version-skew
  within the session. **Stale dependencies PASSED even in this run** (the CI root cause was
  already dead). 10/11 passed, only the flaked persistent_tasks failed.
- Run 2 (`delete!(ENV, "JULIA_LOAD_PATH")` variant — cleaner sandbox for the Aqua
  subprocess) **PASSED 11/11**, no Fail column in the Test summary. 12m06.1s total.

## must_haves — all demonstrated

- ✅ `Pkg.instantiate()` succeeds on 1.10, 1.11, 1.12 (1.10/1.11 buildpkg "could not find
  manifest entry" error gone)
- ✅ Loading TSODSO does NOT load CairoMakie (direct `loaded_modules` assertion, 1.12)
- ✅ Aqua item passes on 1.12 — stale_deps AND persistent_tasks green (run 2: 11/11)
- ✅ No manifest other than Manifest-v1.12.toml differs from f44ada4 (identity gate + git status)

## Notes / lessons

- The Aqua `persistent_tasks` check can flake locally as a **harness precompile failure**
  (`done.log was not created`) — distinguishable from a real finding because Aqua prints
  `Unexpected error:` and the temp package `jl_*` fails with `Missing source file`. Retry
  with `delete!(ENV, "JULIA_LOAD_PATH")` gives the subprocess a clean env and it passes.
- CI is the final authority — push and confirm all 5 jobs green (expect the project_hash
  warning on 1.10 to be non-fatal there too, as it was at 1fabbfe).
- `scripts/demo_mpc_plots.jl` (added by f44ada4) untouched — dev-machine artifact relying on
  the global env stack for CairoMakie, exactly like `scripts/demo_flexibility_plots.jl`.

---
quick_id: 260829-jzz
description: Fix CI — restore CairoMakie as a weakdep and revert Manifest-v1.12.toml to its pre-f44ada4 state (CI red on main after "new MPC demo")
date: 2026-08-29
mode: quick
---

# Quick Task 260829-jzz: Restore CairoMakie weakdep + revert Manifest-v1.12 (CI red on main)

## Why

CI run 33259721481 (commit `f44ada4` "new MPC demo") left `main` red in 3 of 5 jobs. Root cause
is fully diagnosed (not re-investigated here):

1. **Julia 1.10 / 1.11 jobs** fail at `julia-buildpkg` with
   `ERROR: could not find manifest entry for package with uuid 13f3f980-...` (CairoMakie).
   `f44ada4` moved CairoMakie from `[weakdeps]` → `[deps]` in `Project.toml` but only
   re-resolved `Manifest-v1.12.toml`. Julia auto-selects `Manifest-v1.10.toml` /
   `Manifest-v1.11.toml` per version — neither has a `[[deps.CairoMakie]]` entry.
2. **Julia 1.12 job** (manifest WAS updated) fails `julia-runtest` with two Aqua failures from
   `Aqua.test_all(TSODSO)` in `test/test_toy_dc.jl` (no ignores):
   - `Stale dependencies`: CairoMakie as a hard dep is referenced only by
     `ext/TSODSOMakieExt.jl` — extensions must use weakdeps, not deps.
   - `Persistent tasks`: loading TSODSO now drags in the whole Makie tree, which leaves
     background tasks alive.

The promotion was accidental: `scripts/demo_mpc_plots.jl` does `using CairoMakie` under
`--project=.`, which only worked on the dev machine because the global env stack
(`~/.julia/environments/v1.12`) provides CairoMakie. CI has no such fallback — and CI never
runs `scripts/` anyway. The deliberate repo design (Phase 07-01: "Makie tree stays OUT") keeps
CairoMakie a weakdep consumed via the `TSODSOMakieExt` extension.

**Fix = exact revert of the two resolution artifacts to their `f44ada4~1` state.** Restoring
the previous files (not re-resolving) is deterministic: it cannot drag unrelated version bumps
into the manifest.

## Scope

Only `Project.toml` and `Manifest-v1.12.toml` change. Nothing else:

- `Manifest.toml`, `Manifest-v1.10.toml`, `Manifest-v1.11.toml`, `test/Manifest.toml` were NOT
  touched by `f44ada4` — they stay byte-identical.
- `scripts/demo_mpc_plots.jl` stays exactly as committed (dev-machine artifact relying on the
  env stack; CI never runs it). Do not "fix" its `using CairoMakie`, do not add header comments.
- `scripts/demo_flexibility_plots.jl` — same story, already worked under the weakdep design.
- No `Pkg.resolve()` / `Pkg.update()` — restore only. No JuliaFormatter runs. No opportunistic
  refactors. No new packages (zero supply-chain change; instantiate uses existing pinned
  manifests only).

## Tasks

### Task 1 — revert Project.toml and Manifest-v1.12.toml to `f44ada4~1`

- **files:** `Project.toml`, `Manifest-v1.12.toml`
- **action:**
  1. From the repo root (currently clean at `f44ada4` on `main`):
     `git show f44ada4~1:Project.toml > Project.toml`
     This puts `CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"` back under `[weakdeps]`
     (first entry, before Gurobi), removes it from `[deps]`, and keeps `[extensions]
     TSODSOMakieExt = "CairoMakie"` and `[compat] CairoMakie = "0.15"` exactly as they already
     are in both revisions.
  2. `git show f44ada4~1:Manifest-v1.12.toml > Manifest-v1.12.toml`
     This drops the ~1150-line hard-dep CairoMakie/Makie tree; CairoMakie survives only as the
     weakdep reference inside TSODSO's own manifest entry (`TSODSOMakieExt = "CairoMakie"` /
     `CairoMakie = "13f3f980-..."` around lines 733–737) — verified present in that revision.
  3. Confirm the restore is exact and isolated:
     - `git diff --quiet f44ada4~1 -- Project.toml Manifest-v1.12.toml && echo IDENTICAL`
       must print `IDENTICAL`.
     - `git diff --name-only f44ada4` must list exactly `Project.toml` and
       `Manifest-v1.12.toml` — nothing else.
     - Semantic spot-checks (comments excluded by fixed-string matching on section content):
       `awk '/^\[deps\]/{f=1} /^\[/{next} f && /^CairoMakie/' Project.toml | wc -l` style
       checks — simplest robust forms:
       `awk '/^\[weakdeps\]/{f=1} /^\[extensions\]/{f=0} f && /^CairoMakie/{print}' Project.toml`
       prints the weakdep line; `awk '/^\[deps\]/{f=1} /^\[weakdeps\]/{f=0} f && /^CairoMakie/' Project.toml`
       prints nothing; `grep -cF '[[deps.CairoMakie]]' Manifest-v1.12.toml` is `0`.
- **verify:**
  1. `git diff --quiet f44ada4~1 -- Project.toml Manifest-v1.12.toml && echo IDENTICAL` →
     `IDENTICAL`.
  2. `git diff --name-only f44ada4` → exactly the two files above.
- **done:** CairoMakie lives only in `[weakdeps]` (referenced by the `TSODSOMakieExt`
  extension), and `Manifest-v1.12.toml` carries no `[[deps.CairoMakie]]` entry.

### Task 2 — verify: cross-version instantiate, weakdep load, and the Aqua gate on 1.12

- **files:** none (verification only)
- **action:** All from the repo root. `juliaup` channels 1.10/1.11/1.12 are available locally
  (`julia +1.10` form). These mirror what CI does per job (INFRA-01 standard):
  1. **1.10 resolve check** (the exact failure mode of the red buildpkg step):
     `julia +1.10 --project=. -e 'using Pkg; Pkg.instantiate()'` — must exit 0 with no
     "could not find manifest entry" error.
  2. **1.11 resolve check**: `julia +1.11 --project=. -e 'using Pkg; Pkg.instantiate()'` —
     exit 0.
  3. **1.12 load check + weakdep proof** (kills both Aqua root causes at once):
     `julia +1.12 --project=. -e 'using Pkg; Pkg.instantiate(); using TSODSO; loaded = [id.name for (id, _) in Base.loaded_modules()]; @assert "CairoMakie" ∉ loaded; println("TSODSO loads; CairoMakie NOT loaded (weakdep form)")'`
     — exit 0 and the confirmation line printed.
  4. **Aqua gate** — the failing testitem is
     `"quality: Aqua package checks (no stale deps / ambiguities / export issues)"` in
     `test/test_toy_dc.jl` (line 31). Run it in isolation on Julia 1.12 (the version CI failed
     on) via the explicit-path TestItemRunner form confirmed working in this repo (quick task
     260824-vdh) — never `julia -e '@run_package_tests'`, never a plain `--project=.`
     TestItemRunner invocation:

     `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib" julia +1.12 -e 'using TestItemRunner, TSODSO; TestItemRunner.run_tests(joinpath(pwd(), "test"); filter=ti->occursin("Aqua package checks", ti.name))' > /tmp/jzz-aqua-run.log 2>&1; echo "exit=$?"`

     Budget a generous timeout (minutes — includes precompilation). `test/Manifest.toml`
     resolves only on 1.12 (STATE.md standing note), which is exactly the version used here.
  5. **No manifest drift:** after all checks, `git status --short` must show NO modification to
     any `Manifest*.toml` or `test/Manifest.toml` (instantiate against a consistent manifest is
     a no-op; a rewrite would signal an inconsistency beyond the two-file restore — STOP and
     investigate, do not commit a Pkg-rewritten manifest).
  6. Optional (not required; CI runs the full suite on push): full `Pkg.test()` on 1.12 in a
     clean detached worktree, per the w5a precedent, if local full-suite confirmation is wanted.
- **verify:**
  1. Steps 1–3 each exit 0; step 3 prints the weakdep-confirmation line.
  2. Step 4's `exit=0`, and `grep -v '^#' /tmp/jzz-aqua-run.log | grep -c "Test Failed"` is `0`,
     with the TestItemRunner summary showing Pass count == Total count for the filtered item.
  3. `git status --short` shows only the two Task-1 files as modified.
- **done:** all three Julia versions instantiate against the restored resolution state,
  `using TSODSO` no longer loads the Makie tree, and the Aqua item (stale_deps +
  persistent_tasks included) passes on Julia 1.12.

## Constraints

- Exact two-file revert — no re-resolve, no reformat, no script edits (see Scope).
- The `f44ada4` additions `scripts/demo_mpc_plots.jl` and `.planning/tmp/docs-work-manifest.json`
  remain committed as-is.
- If any `Pkg.instantiate()` rewrites a manifest, stop and investigate — never commit a
  Pkg-rewritten manifest as part of this fix.
- Local verification on the failing version (1.12) plus the two resolve-failed versions
  (1.10/1.11) is sufficient; the CI matrix re-proves everything on push.

## must_haves

- truths:
  - "`Pkg.instantiate()` succeeds against this repo on Julia 1.10, 1.11, and 1.12 (the 1.10/1.11
    buildpkg 'could not find manifest entry' error is gone)"
  - "Loading TSODSO does NOT load CairoMakie (weakdep form restored; Makie tree stays OUT)"
  - "The Aqua item in test/test_toy_dc.jl passes on Julia 1.12 (stale_deps and persistent_tasks
    both green again)"
  - "No manifest other than Manifest-v1.12.toml differs from f44ada4"
- artifacts:
  - path: "Project.toml"
    state: "byte-identical to f44ada4~1 (CairoMakie under [weakdeps], [extensions] TSODSOMakieExt intact)"
  - path: "Manifest-v1.12.toml"
    state: "byte-identical to f44ada4~1 (no [[deps.CairoMakie]] tree)"
- key_links:
  - from: "Project.toml [weakdeps] CairoMakie"
    to: "ext/TSODSOMakieExt.jl (via [extensions] TSODSOMakieExt = \"CairoMakie\")"
    via: "weakdep extension loading — the ONLY sanctioned way the Makie tree is reachable"

## Verification (overall)

Task 1's identity gates + Task 2's four runtime checks. CI is the final authority: on push, all
five jobs (1.10, 1.11, 1.12, docs, format) must go green again.

## Success criteria

`main` is un-red: the two-file revert makes every Julia version's manifest consistent with
`Project.toml` again and restores the deliberate weakdep/extension design, proved locally by
instantiate ×3, the no-CairoMakie load assertion, and the Aqua item on 1.12.

## Output

Create `260829-jzz-SUMMARY.md` beside this plan when done; orchestrator commits as
`fix(deps): restore CairoMakie weakdep + revert Manifest-v1.12 (CI red after f44ada4)` and
records the row in STATE.md's Quick Tasks table.

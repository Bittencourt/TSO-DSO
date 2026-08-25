---
quick_id: 260825-eme
description: Reset the conditioning-ladder optimizer attributes to their as-built baseline immediately before solve_dso!'s FINAL/converged solve, so the published solve always runs at the factory's own configuration instead of inheriting a mid-loop escalation
date: 2026-08-25
mode: quick
---

# Quick Task 260825-eme: Reset ladder attributes before the final DSO-OPT solve

## Why

Commit `f9d6ed7` routed `solve_dso!`'s MID-LOOP (`strict = false`) solve through
`solve_with_retry!`, fixing a Clarabel `NUMERICAL_ERROR` at ADMM iteration 28 on IEEE-13.
`solve_with_retry!`'s escalation is STICKY by its documented WR-01 contract
(`set_optimizer_attribute` mutates the model permanently, never restored), and `dso` is
BUILD-ONCE — so once a mid-loop rescue escalates to rung 2, every solve after it runs at
`static_regularization_constant = 1e-6` instead of the as-built `1.0e-8`. The user wants the
published solve to always run at the factory's own configuration.

**Load-bearing correction found during planning (read this before touching code):**
`src/admm/DsoOpt.jl`'s inline "HONEST CAVEAT" and its own docstring both claim the escalation
"reaches the final `strict = true` solve." That is not what actually happens today.
`src/admm/solve_admm.jl`'s ACTUAL final-consolidation call (the one whose `welfare`/`dadp` are
published) is:

```
dres_final = solve_dso!(dso, λ, a, ρf; check_exact = true, strict = false, atol_exact, rtol_exact)
```

`strict = false` — verified by direct read of `solve_admm.jl`; grep confirms `solve_dso!` is
NEVER called with `strict = true` anywhere in `solve_admm.jl` (both call sites, mid-loop L438
and final L768-ish, pass `strict = false` explicitly). This is deliberate design (see the
"WR-01 PUBLISHED-PRIMAL CERTIFICATE" comment right after the final call): the final solve relies
on the PHYSICAL `:balance_p` no-slack certificate instead of the bare `dual = true` solver
label, because Clarabel intermittently reports `ALMOST_OPTIMAL` even on genuine convergence
under the ρ-penalty.

Consequence: gating the reset on `strict == true` (as a literal reading of the caavet text
might suggest) would be **dead code for the actual published path** — `run_scenario`/
`solve_admm` would still leak the mid-loop escalation into the published solve, and the
load-bearing verification check below (reading back `static_regularization_constant` after
`solve_admm` returns) would fail. The correct gate is `check_exact == true` — `solve_dso!`'s
OWN pre-existing "is this the final/converged call" flag (mid-loop iterates always pass
`check_exact = false`; the final consolidation call always passes `check_exact = true`,
regardless of `strict`). This plan implements the reset gated on `check_exact`, and documents
this discrepancy explicitly in both files touched (do not silently deviate — explain it inline
so a future reader isn't confused by the stale claim).

## Context

- `src/admm/DsoOpt.jl` — `build_dso_opt` (builds the model, currently ~L171-388) and
  `solve_dso!` (~L435-520) — both edited by this task.
- `src/planning/retry.jl` — `solve_with_retry!`'s 4-rung ladder (~L126-140) touches exactly 4
  Clarabel attribute keys: `static_regularization_constant`, `iterative_refinement_max_iter`,
  `equilibrate_max_iter`, `dynamic_regularization_eps`. This task adds a single named constant
  here so `DsoOpt.jl` never re-lists these 4 strings itself.
- `.planning/debug/ieee13-admm-numerical-error.md` — the debug session that landed the mid-loop
  fix; its "C1 landing" evidence entry (dated 2026-08-25, starting "**REFINEMENT of the
  duals-objection entry above**") makes the now-corrected "reaches the final strict = true
  solve" claim. Append a new dated entry, do not rewrite it.
- Measured factory baseline (Clarabel 0.11.1, this pinned build, `select_optimizer(SOCP())`):
  `static_regularization_constant = 1.0e-8`, `iterative_refinement_max_iter = 10`,
  `equilibrate_max_iter = 0x0000000a` (reads back unsigned), `dynamic_regularization_eps =
  1.0e-13`. Do NOT hardcode these — this task snapshots them from the model itself.
- Reference probe (verified working this session):
  `julia +1.10 --project=. <scratchpad>/probe.jl` prints `PROBE OK iters=58
  welfare=-4822.903616694139` on the pre-this-task tree, where `<scratchpad>` is
  `/tmp/claude-1000/-home-pedro-programming-TSO-DSO/fb15e907-7729-4e8c-8dfc-10ace72db910/scratchpad`.
  Use this exact scratchpad path for the new verification scripts below (Task C).

## Tasks

### Task A — Single source of truth for the ladder key list (`src/planning/retry.jl`)

- **files:** `src/planning/retry.jl`
- **action:**
  1. Immediately after the existing `const RETRYABLE_STATUSES = (...)` definition (and its
     docstring), add a new exported constant:

     ```
     const LADDER_ATTR_NAMES = (
         "static_regularization_constant",
         "iterative_refinement_max_iter",
         "equilibrate_max_iter",
         "dynamic_regularization_eps",
     )
     ```

     with a docstring stating: this is the single source of truth for the 4 Clarabel attribute
     names the `solve_with_retry!` ladder touches (name each rung: rung 2 sets
     `static_regularization_constant`; rung 3 adds `iterative_refinement_max_iter` /
     `equilibrate_max_iter`; rung 4 adds `dynamic_regularization_eps`); any caller that needs to
     snapshot/restore these attributes around the ladder's documented WR-01 stickiness (name
     `src/admm/DsoOpt.jl`'s `build_dso_opt`/`solve_dso!`, quick task 260825-eme) reads this
     constant instead of re-listing the 4 strings.
  2. Update the file's final `export` line from `export solve_with_retry!, RETRYABLE_STATUSES`
     to `export solve_with_retry!, RETRYABLE_STATUSES, LADDER_ATTR_NAMES`.
  3. Do NOT touch the `ladder` vector inside `solve_with_retry!` itself, its rung Dicts, or any
     other existing logic — this task is strictly additive to this file.
- **verify:**
  - `grep -c "const LADDER_ATTR_NAMES" src/planning/retry.jl` → `1`.
  - `grep -n "export solve_with_retry!, RETRYABLE_STATUSES, LADDER_ATTR_NAMES" src/planning/retry.jl` → 1 match.
  - `julia --project=. -e 'include("src/TSODSO.jl"); using .TSODSO; println(TSODSO.LADDER_ATTR_NAMES)'`
    prints the 4-string tuple (proves it parses and is exported; run on whichever Julia is on
    `PATH` — this is a syntax/load check only, not the numerical verification, which is Task C).
- **done:** `LADDER_ATTR_NAMES` exists, is exported, matches the 4 keys the ladder actually
  touches, and no existing `solve_with_retry!` behavior changed (diff is purely additive).

### Task B — Snapshot the as-built baseline; restore it before the final solve (`src/admm/DsoOpt.jl`)

- **files:** `src/admm/DsoOpt.jl`
- **action:**
  1. Add two new private helper functions. Place them between the `struct DsoOpt ... end`
     block and the `build_dso_opt` docstring:

     ```julia
     function _snapshot_ladder_attrs(model::Model)
         baseline = Dict{String, Any}()
         for name in LADDER_ATTR_NAMES
             try
                 baseline[name] = get_optimizer_attribute(model, name)
             catch
                 # Backend doesn't expose this Clarabel-specific attribute — omit it; restore
                 # then no-ops for this key instead of failing the build (graceful degradation,
                 # INFRA-02: solve_dso! must keep working under any factory backend).
             end
         end
         return baseline
     end

     function _restore_ladder_attrs!(model::Model, baseline::Dict{String, Any})
         for (name, value) in baseline
             try
                 set_optimizer_attribute(model, name, value)
             catch
                 # Backend rejected restoring this attribute — degrade gracefully. No solve
                 # happens inside this function, so this catch can never swallow a real solve
                 # error.
             end
         end
         return nothing
     end
     ```

     Give each a docstring per the style already used in this file (see `set_rho!` for the
     length/tone to match): explain `_snapshot_ladder_attrs` is called EXACTLY ONCE, inside
     `build_dso_opt`, before any solve or escalation can have touched the model — so it captures
     the genuine as-built factory configuration, never a hardcoded Clarabel default. Explain
     `_restore_ladder_attrs!` is called from `solve_dso!` immediately before the FINAL/converged
     solve, and that `set_optimizer_attribute` invalidating the prior solution is harmless there
     because the very next statement re-solves.
  2. In `build_dso_opt`, immediately after the existing three-line block
     `ctx = ModelContext(model); ctx.meta[:feeder] = feeder; ctx.meta[:T] = T`, add:

     ```julia
         # RESET-01 (quick task 260825-eme): snapshot the AS-BUILT ladder conditioning NOW —
         # before any solve or `solve_with_retry!` escalation can have touched the model — so
         # `solve_dso!`'s FINAL/converged solve can restore TO THIS later, never to a hardcoded
         # Clarabel default.
         ctx.meta[:ladder_baseline] = _snapshot_ladder_attrs(model)
     ```
  3. Update `build_dso_opt`'s docstring step 1 (the one describing `model =
     Model(select_optimizer(SOCP()))` / bridges / `ModelContext` / `ctx.meta[:feeder]`/`[:T]`) to
     also mention the new `ctx.meta[:ladder_baseline]` snapshot and why it happens at this exact
     point (before any solve).
  4. Update the `DsoOpt` struct's docstring for the `ctx::ModelContext` field to add
     `:ladder_baseline` to the list of keys it names (alongside `:pf_vars`, `:feeder`/`:T`,
     `:socp_maxgap`), one sentence describing what it holds and who reads/writes it.
  5. In `solve_dso!`, immediately after the existing coefficient-update loop
     (`for j in dso.load_nodes, t in 1:dso.T ... set_objective_coefficient(...) ... end`) and
     BEFORE the `# INFRA-03: never trust a dual...` comment / `if strict` dispatch, insert:

     ```julia
         # RESET-01 (quick task 260825-eme): reset the Clarabel conditioning ladder to the
         # AS-BUILT snapshot (`dso.ctx.meta[:ladder_baseline]`, taken once in `build_dso_opt`)
         # immediately before the FINAL/converged solve. Gated on `check_exact`, NOT `strict`:
         # `solve_admm`'s actual production final-consolidation call passes `strict = false`
         # (see the WR-01 PUBLISHED-PRIMAL CERTIFICATE block in `solve_admm.jl` — it
         # deliberately relies on the PHYSICAL `:balance_p` no-slack gate rather than a bare
         # `dual = true` solver label), so gating on `strict` alone would never fire on the path
         # this fix exists to protect. `check_exact` is this function's OWN pre-existing "is
         # this the final/converged call" flag (RESEARCH Pitfall 3 — every mid-loop iterate
         # passes it `false`), so it is the correct signal regardless of which `strict` branch
         # is about to run below, and it fires EXACTLY ONCE per `solve_admm` run — mid-loop
         # iterations (`check_exact = false`) are UNTOUCHED, so a `solve_with_retry!` escalation
         # applied mid-loop stays STICKY across them exactly as before (no wasted per-iteration
         # re-failure; see `.planning/debug/ieee13-admm-numerical-error.md`).
         if check_exact
             _restore_ladder_attrs!(
                 dso.model,
                 get(dso.ctx.meta, :ladder_baseline, Dict{String, Any}()),
             )
         end

     ```
  6. Update `solve_dso!`'s own docstring: immediately after the existing paragraph describing
     the mid-loop `solve_with_retry!` routing (ending "...and `.planning/debug/
     ieee13-admm-numerical-error.md`"), add a new paragraph stating that `check_exact = true`
     (the FINAL/converged consolidation call) ALSO now resets the conditioning ladder to the
     as-built snapshot immediately before the solve, regardless of `strict` (RESET-01, quick
     task 260825-eme), and that mid-loop iterates (`check_exact = false`) are never reset so an
     escalation rescued mid-loop stays in force across the remaining mid-loop iterations.
  7. Rewrite the "HONEST CAVEAT" comment block inside `solve_dso!`'s mid-loop `else` branch
     (the block starting `# HONEST CAVEAT — escalation is STICKY (...)`) to state the CORRECTED
     behavior: escalation is still sticky WITHIN the mid-loop iterations after a rescue
     (intentional, unchanged), but it NO LONGER reaches the final/converged solve — `solve_dso!`
     now resets before every `check_exact = true` call (point to the reset code above). Keep the
     measured evidence that is still accurate (the cross-environment welfare figures: rescued
     IEEE-13 welfare `-4822.903616694139` vs `-4822.903620476632`/`-4822.903625595291`, the
     "escalation only fires where the alternative is a hard crash" point, and the "ADMM
     transactive price is the outer multiplier λ, never `dual(balance_p)`" point). Explicitly
     note that the PREVIOUS text's "reaches the final `strict = true` solve" claim was corrected
     during quick task 260825-eme planning: `solve_admm.jl`'s actual final call passes
     `strict = false`, which is exactly why the reset is gated on `check_exact` rather than
     `strict`.
  8. In the "SCOPE — the LADDER IS WIRED ONLY ON THIS BRANCH" paragraph immediately above the
     HONEST CAVEAT block, add one clarifying sentence after its first sentence: that this
     paragraph describes the `strict = true` branch's OWN behavior for any caller that selects
     it (e.g. direct test calls in `test/test_dso.jl`), and that `solve_admm`'s own
     final-consolidation call in production actually passes `strict = false` (see the reset
     comment above for why the RESET-01 fix does not depend on which branch runs).
  9. Do not weaken, remove, or add `allow_almost`/retry-ladder wrapping to the bare
     `assert_solved!(dso.model; dual = true)` STRICT-branch call itself — it must remain exactly
     as-is, just now preceded (when `check_exact` is true) by the reset above.
- **verify:**
  <automated>
  `julia --project=. -e 'include("src/TSODSO.jl")'` — the module must load without a
  `MethodError`/`UndefVarError` (proves `_snapshot_ladder_attrs`/`_restore_ladder_attrs!`
  resolve `LADDER_ATTR_NAMES` correctly via same-module include ordering, mirroring how
  `solve_dso!` already calls `solve_with_retry!` — defined later in `TSODSO.jl`'s include
  order — today).
  </automated>
  Also `grep -n "_restore_ladder_attrs!" src/admm/DsoOpt.jl` shows exactly one call site inside
  `solve_dso!`, gated by `if check_exact`. Full numerical verification is Task C.
- **done:** `build_dso_opt` snapshots the 4 ladder attributes into
  `ctx.meta[:ladder_baseline]` once, before any solve; `solve_dso!` restores that snapshot
  immediately before every `check_exact = true` call regardless of `strict`; mid-loop
  (`check_exact = false`) calls are untouched; the STRICT `strict = true` branch's bare
  `assert_solved!(...; dual = true)` gate is unchanged; both the HONEST CAVEAT block and the
  SCOPE paragraph read is accurate given `solve_admm.jl`'s actual `strict = false` final call;
  no new dependency, no hardcoded `1e-8`/`10`/`10`/`1e-13` anywhere in `DsoOpt.jl`.

### Task C — Verify on the failing toolchain, then record the corrected evidence

- **files:** `.planning/debug/ieee13-admm-numerical-error.md`
- **action:**
  1. Format-check the two edited source files (mirrors the CI job, run in an isolated temp
     env so no project dependency is added):
     `julia -e 'import Pkg; Pkg.activate(temp=true); Pkg.add(Pkg.PackageSpec(name="JuliaFormatter", version="2.10")); using JuliaFormatter; println(format(["src/admm/DsoOpt.jl", "src/planning/retry.jl"]; overwrite=true))'`
     — must print `true`. If it prints `false`, the files were reformatted; re-run once more
     (must print `true` the second time) and re-read the diff to confirm no logic changed, only
     whitespace.
  2. Write a verification script to
     `/tmp/claude-1000/-home-pedro-programming-TSO-DSO/fb15e907-7729-4e8c-8dfc-10ace72db910/scratchpad/reset01_probe.jl`
     (NOT committed) that mirrors `run_scenario`'s `:admm` branch manually (so the returned
     `dso_ctx.model` is inspectable — `ScenarioResult` normalizes it away) and checks the
     as-built baseline was restored:

     ```julia
     using TSODSO
     using JuMP

     function admm_probe(; seed::Int)
         feeder = TSODSO.build_feeder(:ieee13)
         profiles = TSODSO.generate_profiles(; seed = TSODSO.sub_seed(seed, :profiles), T = 24)
         λ₀ = TSODSO.build_price(:mem, 24, profiles)
         aggs = TSODSO.build_population(
             :default, feeder, :ieee13, profiles, TSODSO.sub_seed(seed, :population),
         )
         pf = TSODSO.ConvexBranchFlow()
         return TSODSO.solve_admm(
             feeder, pf, aggs;
             T = 24, λ₀ = λ₀, ρ = 100.0, maxiter = 200, ε_abs = 1e-4, ε_rel = 1e-3,
             τ = 2.0, μ = 10.0, allow_export = true,
         )
     end

     r = admm_probe(; seed = 7)
     println("PROBE OK iters=", r.iters, " welfare=", r.welfare)

     val = get_optimizer_attribute(r.dso_ctx.model, "static_regularization_constant")
     println("FINAL static_regularization_constant = ", val)
     if !isapprox(val, 1.0e-8; atol = 1e-12)
         error("RESET FAILED: expected as-built baseline 1.0e-8, got $val")
     end
     println("RESET-01 CHECK: OK (baseline restored)")
     ```

     Run it and capture BOTH streams:
     `julia +1.10 --project=. /tmp/claude-1000/-home-pedro-programming-TSO-DSO/fb15e907-7729-4e8c-8dfc-10ace72db910/scratchpad/reset01_probe.jl 2>&1 | tee /tmp/claude-1000/-home-pedro-programming-TSO-DSO/fb15e907-7729-4e8c-8dfc-10ace72db910/scratchpad/reset01_probe.log`

     Required from this run: `PROBE OK iters=58`, welfare within ~1e-9 relative of
     `-4822.903616694139`; `RESET-01 CHECK: OK`; and exactly one `escalating conditioning`
     warning in the log —
     `grep -c "escalating conditioning" /tmp/claude-1000/-home-pedro-programming-TSO-DSO/fb15e907-7729-4e8c-8dfc-10ace72db910/scratchpad/reset01_probe.log`
     must print `1`.
  3. Write a second script to
     `/tmp/claude-1000/-home-pedro-programming-TSO-DSO/fb15e907-7729-4e8c-8dfc-10ace72db910/scratchpad/reset01_infra04.jl`
     for the INFRA-04 bit-for-bit check (two `run_scenario` calls in ONE process):

     ```julia
     using TSODSO

     s = TSODSO.Scenario(; name = "reset01-infra04", feeder = :ieee13, strategy = :admm, seed = 7, T = 24)
     r1 = TSODSO.run_scenario(s)
     r2 = TSODSO.run_scenario(s)

     ok = r1.welfare == r2.welfare &&
          r1.dadp == r2.dadp &&
          r1.exact_maxgap == r2.exact_maxgap &&
          r1.iters == r2.iters
     println("INFRA-04 CHECK: ", ok ? "OK" : "FAIL")
     ok || error("INFRA-04 bit-for-bit reproducibility broken")
     ```

     Run it the same way (`julia +1.10 --project=. ... 2>&1 | tee
     .../reset01_infra04.log`). Required: `INFRA-04 CHECK: OK`, and
     `grep -c "escalating conditioning" .../reset01_infra04.log` must print `2` (one escalation
     per independent `run_scenario` call — each builds a fresh `DsoOpt`, matching the original
     debug session's own INFRA-04 evidence pattern).
  4. Confirm `solve_with_retry!`'s other existing callers are unaffected by reading the diff of
     `src/planning/retry.jl` (Task A) — it must show ONLY the new `LADDER_ATTR_NAMES` const and
     the updated `export` line, zero changes to the `ladder` vector, `RETRYABLE_STATUSES`, or
     `solve_with_retry!`'s body. (The test environment for `planning/subproblem.jl`,
     `planning/master.jl`, etc. cannot run on Julia 1.10/1.11 in this repo — see Constraints —
     so this is a diff-review check, not a runtime test, and that is sufficient given the change
     to `retry.jl` is purely additive.)
  5. Append a NEW dated entry (do not edit or remove the existing "C1 landing" entries) to
     `.planning/debug/ieee13-admm-numerical-error.md`'s `## Evidence` section, timestamped
     2026-08-25, tagged `RESET-01, quick task 260825-eme`. It must:
       - Correct the earlier "C1 landing REFINEMENT" entry's claim that escalation "reaches the
         final `strict = true` solve" — state plainly that `solve_admm.jl`'s actual final
         consolidation call passes `strict = false` (found during this task's planning, verified
         by direct source read + grep), so that entry's factual premise about which branch runs
         was wrong even though its conclusion (measured impact below noise floor) still held.
       - Describe the RESET-01 fix precisely: snapshot in `build_dso_opt`
         (`ctx.meta[:ladder_baseline]`), restore in `solve_dso!` gated on `check_exact` (not
         `strict`), mid-loop stickiness preserved.
       - Record the ACTUAL measured numbers from steps 2-3 above (iters, welfare, the restored
         `static_regularization_constant` value, the escalation counts `1` and `2`, and the
         INFRA-04 pass/fail) — fill in the REAL measured values, never a placeholder or a
         guessed number.
       - List the files changed: `src/planning/retry.jl`, `src/admm/DsoOpt.jl`.
- **verify:**
  - `julia -e '...JuliaFormatter...'` (step 1) prints `true`.
  - `reset01_probe.log` shows `PROBE OK iters=58`, `RESET-01 CHECK: OK`, and exactly 1
    `escalating conditioning` line.
  - `reset01_infra04.log` shows `INFRA-04 CHECK: OK` and exactly 2 `escalating conditioning`
    lines.
  - `git diff src/planning/retry.jl` shows only the additive `LADDER_ATTR_NAMES`
    const/docstring/export change.
  - `grep -c "RESET-01" .planning/debug/ieee13-admm-numerical-error.md` is `>= 1` and the new
    entry contains real measured numbers (no `<fill in>`/placeholder text survives).
- **done:** all four numerical checks pass on Julia 1.10 (a toolchain that fails without the
  original C1 fix), the formatter is clean, and the debug log carries an honest, dated,
  measured correction rather than a silent edit of prior evidence.

## Constraints

- Files in scope: `src/admm/DsoOpt.jl`, `src/planning/retry.jl` (additive only — new exported
  const, no existing logic touched), and `.planning/debug/ieee13-admm-numerical-error.md`
  (append only). Do NOT touch `src/admm/solve_admm.jl` or any test file.
- Do NOT weaken any gate, tolerance, or assertion. The STRICT `strict = true` branch's bare
  `assert_solved!(dso.model; dual = true)` (no `allow_almost`, no retry ladder) must remain
  byte-identical in behavior, just preceded by the reset when `check_exact` is true.
- Do NOT add a reset that fires on every mid-loop (`check_exact = false`) iteration — that would
  reintroduce a wasted failing solve on every iteration and break the "exactly one escalation
  per run" property.
- Do NOT hardcode `1e-8` / `10` / `10` / `1e-13` anywhere — the baseline must be read back from
  the model itself in `build_dso_opt`, once.
- MUST verify on `julia +1.10` — a toolchain that deterministically fails without the original
  C1 fix. A green run on `julia +1.12` proves nothing (it converges natively).
  `julia +1.11 --project=.` is blocked on this working tree by pre-existing uncommitted
  `Project.toml` drift (CairoMakie) — not this task's concern, do not attempt to fix it.
- `test/Manifest.toml` resolves only on Julia 1.12 (`UndefVarError: StaticData` on 1.10/1.11) and
  TestItemRunner cannot run under `--project=.` in this repo — verification MUST be direct
  `julia --project=. <script>.jl` runs against `src/`, never through the test environment.
- Never leave a numeric placeholder in the committed debug `.md` entry — every figure must be
  the actual measured value from this session's own run.

## must_haves

- **truths:**
  - After `solve_admm` (via `run_scenario` or a direct call) returns, the DSO-OPT model's
    `static_regularization_constant` (and the other 3 ladder attributes) reads back at the
    as-built baseline, never an inherited mid-loop escalation value.
  - A single `run_scenario`/`solve_admm` call that needed a mid-loop rescue still shows EXACTLY
    ONE `escalating conditioning` warning for the whole run — the final solve does not
    re-escalate and does not silently absorb a second rescue without logging it.
  - Two `run_scenario` calls with the same `Scenario` in one process remain bit-for-bit
    reproducible (`welfare`, `dadp`, `exact_maxgap`, `iters` all `==`).
  - `solve_dso!`'s STRICT `strict = true` branch still hard-fails loudly on a genuine
    non-convergent final solve — no `allow_almost`, no retry ladder added to it.
- **artifacts:**
  - `src/planning/retry.jl` — `LADDER_ATTR_NAMES` constant, exported, matching the ladder's 4
    keys.
  - `src/admm/DsoOpt.jl` — `_snapshot_ladder_attrs`/`_restore_ladder_attrs!` helpers,
    `ctx.meta[:ladder_baseline]` populated once in `build_dso_opt`, restore call gated on
    `check_exact` in `solve_dso!`, corrected HONEST CAVEAT + SCOPE comments, updated docstrings.
  - `.planning/debug/ieee13-admm-numerical-error.md` — new dated `RESET-01` evidence entry with
    real measured numbers, correcting the superseded "reaches the final strict solve" claim.
- **key_links:**
  - `build_dso_opt` → `_snapshot_ladder_attrs(model)` → `ctx.meta[:ladder_baseline]`
  - `solve_dso!` (when `check_exact == true`) → `_restore_ladder_attrs!(dso.model,
    dso.ctx.meta[:ladder_baseline])` → (either) `assert_solved!(dso.model; dual = true)` (if
    `strict`) or `solve_with_retry!(dso.model; dual = false, allow_almost = true)` (if not)
  - `src/planning/retry.jl`'s `LADDER_ATTR_NAMES` → consumed by both
    `_snapshot_ladder_attrs`/`_restore_ladder_attrs!` in `src/admm/DsoOpt.jl` (single source of
    truth, no duplicated key list)

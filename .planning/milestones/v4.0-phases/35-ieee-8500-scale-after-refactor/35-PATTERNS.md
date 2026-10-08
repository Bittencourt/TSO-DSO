# Phase 35: IEEE-8500 Scale After Refactor - Pattern Map

**Mapped:** 2026-10-04
**Files analyzed:** 13 new/modified
**Analogs found:** 12 / 13

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/admm/solve_admm.jl` (L264 + docstring ~L177) | library API | request-response | `time_limit_s::Union{Nothing, Real} = nothing` line L263 same file | exact |
| `src/admm/DsoOpt.jl` (L558 + docstring ~L498-540) | library API | request-response | same edit as above; target `assert_socp_exact!(...; atol::Union{Nothing,Real}=nothing)` | exact |
| `src/admm/admm_phases.jl` `_admm_certify` (L260-293) | library plumbing | pass-through | itself (untyped positional `atol_exact`, no change needed) | exact |
| `test/test_admm_exactness_default.jl` (new, or items in `test/test_exactness.jl`) | test | assert-level / request-response | `test/test_exactness.jl:138-182` (FIX-08 item) and `test/test_admm.jl:25-75` | exact |
| `scripts/benchmark_ieee8500.jl` (flags, `run_admm_point`, CSV) | script | batch / file-I/O | itself (L138-145, L554-585, L683-691, L815-846) | exact |
| `test/test_benchmark_ieee8500.jl` (extend) | test (plain script) | subprocess integration | itself | exact |
| `scripts/run_ieee8500_point.sh` (new) | script/wrapper | batch | RESEARCH.md Finding 3 skeleton (no repo shell analog) | none |
| `scripts/profile_ieee8500_memory.jl` (new) | script | batch | `scripts/benchmark_ieee8500.jl` setup (`build_feeder`, `density_filtered_population`, `Sys.maxrss`) | role-match |
| `results/ieee8500_benchmark/density_sweep.csv` | data | file-I/O | existing upsert at benchmark L832-844 (`cols = :union`) | exact |
| `docs/literate/ieee8500_scaling.jl` (+ tracked `docs/src/generated/ieee8500_scaling.md`) | docs | transform | same file, "headline point" section ~L178 | exact |
| `.planning/.../25-VERIFICATION.md`, `deferred-items.md`, `STATE.md`, `PROJECT.md`, `REQUIREMENTS.md` | status notes | append-only | prior dated sub-entries (quick 260822-pxb / rle) | role-match |
| optional additive `hybrid_ratios` next to `socp_gap_report` (`src/models/exactness.jl:361`) | library diagnostic | transform | `socp_gap_report` | exact |

## Pattern Assignments

### Library signature change (3 files)

**Analog:** `src/admm/solve_admm.jl:255-266`
```julia
    time_limit_s::Union{Nothing, Real} = nothing,
    atol_exact::Real = 1e-6,          # -> atol_exact::Union{Nothing, Real} = nothing,
    rtol_exact::Real = 1e-4,
```
`src/admm/DsoOpt.jl:551-559` same swap on `solve_dso!` (`atol_exact::Real = 1e-6`). Use the SPACED `Union{Nothing, Real}` (JuliaFormatter 2.10). `_admm_certify` (admm_phases.jl:260-293) forwards positionally and by `atol_exact = atol_exact`; no edit besides docs. Update the docstrings that state the 1e-6 default. `assert_socp_exact!` already takes `atol::Union{Nothing,Real}=nothing`, so nothing flows to the hybrid floor.

### New tests (assert-level A, plumbing B, near-zero-r negative)

**Analog:** `test/test_exactness.jl:138-182` (fixed-variable ctx, `@testitem ... tags = [:exact]`)
```julia
feeder = Feeder([Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
                [Branch(1, 2, 0.01, 0.02, 0.01)], 1)
T, N, B = 1, 2, 1
model = Model(select_optimizer(SOCP()))
@variable(model, v[1:N, 1:T]); @variable(model, v̂[1:N, 1:T])
@variable(model, P[1:B, 1:T]); @variable(model, Q[1:B, 1:T]); @variable(model, l[1:B, 1:T])
fix.(v, 1.0; force = true); fix.(v̂, 1.0; force = true)
fix.(P, 0.0; force = true); fix.(Q, 0.0; force = true); fix.(l, 5.0e-7; force = true)
@objective(model, Max, 0); optimize!(model)
ctx = TSODSO.ModelContext(model)
ctx.feeder = feeder; ctx.T = T; ctx.pf_vars = (; v, v̂, P, Q, l)
maxgap_old_style = TSODSO.assert_socp_exact!(ctx; rtol = 1e-4, atol = 1e-6)   # flat bypass
@test_throws Exception TSODSO.assert_socp_exact!(ctx; rtol = 1e-4)            # hybrid
```
Item A: invert it. `Branch(1,2,0.01,0.02,90.0)`, `l = 5e-6`: flat `atol=1e-6` throws, default returns ≈5e-6 (use `@test_throws CertificateError`). Negative: `Branch(1,2,2.4e-6,5.6e-6,SMAX_NO_LIMIT)`, `l=1.7e-3`, `v=1.06` must throw under the default.

**Analog for B (real ADMM path):** `test/test_admm.jl:25-75` — `setup = [Phase6Fixtures, Phase4Fixtures]`, `Phase6Fixtures.two_bus_feeder()`, `build_two_bus_aggregators`, `two_bus_lambda0()`, `ρ = Phase6Fixtures.RHO_2BUS`:
```julia
res = solve_admm(feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀,
                 ρ = Phase6Fixtures.RHO_2BUS, allow_export = true)
```
Assert default vs `atol_exact = nothing` bit-equal (`iters`, `welfare`, `exact_maxgap` with `==`); `solve_admm(...; atol_exact = 1e-30, rtol_exact = 0.0)` raises `CertificateError`. Wrap try/catch in a function (memory `testitem-try-scoping-trap`); prefer `@test_throws`.

### `scripts/benchmark_ieee8500.jl`

**Flag parsing** (L683-691): reuse `parse_kv_flag(args, flag, default)` and `has_flag(args, flag)` for `--admm-only` and `--admm-atol` (parse as `Float64`; reject non-finite from the CLI).

**`run_admm_point`** (L554-585): change `atol_exact::Real` to `Union{Nothing, Real}`; keep typed-exception capture:
```julia
catch err
    msg = sprint(showerror, err)
    (; admm_status = "ERROR:" * string(nameof(typeof(err))), admm_iters = -1,
       admm_error_msg = replace(first(msg, 200), '\n' => " | "))
end
```
Call site L775 passes `nothing` unless `--admm-atol` is given. Drop use of `EXACTNESS_ATOL` for the ADMM gate (L138-145 stays for the centralized `exact_verdict` column, relabelled). Write `admm_atol_used = "hybrid"` for `nothing`. With `--admm-only`, skip `run_centralized_point` (L774) and release the result (`r = nothing; GC.gc()`); `res.dso_ctx` holds the live DSO model, so do not retain it.

**Incremental CSV upsert** (L832-846; also L422-428, L958-962): copy `key(r)` filter + `vcat(...; cols = :union)`; add `peak_rss_kb`, `oom_source`, `mem_avail_before_mb`, `swap_used_before_mb` columns this way. Write a "started" row first, overwrite on completion.

**Diagnostic bypass row:** `solve_admm(...; atol_exact = Inf)` then per-branch hybrid ratios via `hybrid_ratios(res.dso_ctx)` (RESEARCH.md Code Examples, lines 236-253). Atom pattern to copy for the loop: `socp_gap_report` at `src/models/exactness.jl:361-380` (`pv = _require_pf_vars(ctx)`, `for (b, br) in enumerate(feeder.branches), t in 1:T`, `lhs = l*v_from`, `rhs = P^2+Q^2`, `gap = abs(lhs-rhs)`).

### `scripts/run_ieee8500_point.sh` / `scripts/profile_ieee8500_memory.jl`

No shell analog in repo; use the RESEARCH.md Finding 3 skeleton (lines 193-206): `free -m` before, `/usr/bin/time -v -o`, `journalctl -k --since` AND `journalctl -u earlyoom --since`, classify RC 137/143, quote `"$@"`, no `eval`. Profile script: copy setup from benchmark (`build_feeder(fixture_sym)`, `generate_profiles`, `density_filtered_population`, `build_dso_opt`), print `VmRSS`/`VmHWM` from `/proc/self/status` and `Base.gc_live_bytes()` per stage.

### Docs

`docs/literate/ieee8500_scaling.jl`: add a "Post-refactor measured results (Phase 35)" section after "The headline point, stated plainly" (~L178-210); amend the sentence saying the headline never converged. Use a Base-only CSV read or literal figures (the page reads `density_sweep_full.csv`; new rows live in `density_sweep.csv`). Regenerate the tracked `docs/src/generated/ieee8500_scaling.md` with `JULIA_LOAD_PATH="<abs>/docs:<abs>:@stdlib"`. Status notes: append dated "superseded by Phase 35" entries (never edit the original status).

## Shared Patterns

### Measured, not picked tolerances (anti-laundering T-25-12)
**Source:** `src/models/exactness.jl` (`TAU_SOLVER_FIX08`, `MEASURED_ε_FIX08`, ~L75-84; `assert_socp_exact!` L170). **Apply to:** every task. Never raise τ/ε, never exclude near-zero-r branches, never loosen `assert_solved!`; any override is labelled in the CSV.

### Never re-pin goldens
Knife-edge canary (iters = 56, welfare = -4823.66604824162) in `test_admm_knifeedge_canary.jl`; gate is pass/throw only, so any movement means the edit is wrong.

### Test running
Direct runner file with absolute `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib"`; never `@run_package_tests` via `-e`, never concurrent suites, no suite while an 8500 run is active (memories `gsd-plan-verify-testitemrunner-trap`, `background-suite-orphan-race`). Harness golden: `julia --project=. test/test_benchmark_ieee8500.jl`.

### Typed errors
`CertificateError`, `ConvergenceError`, `SolveFailedError` (Phase 34); harness records `"ERROR:" * string(nameof(typeof(err)))`.

## No Analog Found

| File | Role | Reason |
|---|---|---|
| `scripts/run_ieee8500_point.sh` | wrapper | No shell wrappers in `scripts/`; follow RESEARCH.md skeleton |

## Metadata

**Analog search scope:** `src/admm/`, `src/models/exactness.jl`, `scripts/`, `test/` (exactness, admm, benchmark, phase6 fixtures)
**Pattern extraction date:** 2026-10-04

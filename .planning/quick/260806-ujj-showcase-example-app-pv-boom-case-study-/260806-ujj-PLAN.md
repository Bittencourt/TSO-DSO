---
quick_id: 260806-ujj
description: Build a showcase PV-boom case study (Literate-style script sweeping PV penetration on IEEE-13, both operational and planning layers) plus a self-contained HTML report generator
date: 2026-08-06
mode: quick
---

# Quick Task 260806-ujj: PV-boom case study + self-contained HTML report

## Why

The framework has every seam a showcase needs (`Scenario`/`run_scenario`, the 4-way DLMP
decomposition, the AC-exactness oracle, `run_nash!`) but no single narrative artifact that
walks a reader end-to-end through both layers on one story: rising PV penetration on a
real feeder, how it reshapes prices, where the SOCP relaxation's own documented boundary
sits, and how a stressed distributor responds in the planning layer. This task builds that
narrative script plus a shareable HTML report a collaborator without Julia can open.

## Scope

Two new `scripts/` entry points, both PURE ORCHESTRATION over already-validated public API
(`Scenario`/`run_scenario`, `solve_welfare`, `solve_admm`, `extract_dlmp`/`decompose_dlmp`,
`ACPowerFlow`/`assert_ac_exact!`, `build_shared_transmission`/`run_nash!`) — no `src/`
modification, no new model/solver code. The only new code is glue: a PV-penetration
wrapper around the ALREADY-PARAMETRIZED `TSODSO._default_house` builder (it already accepts
`pv_scale` as a keyword — `build_population(:default, ...)` just never varies it), a
findings/report string renderer, and CairoMakie figure calls.

Everything runs on the modified IEEE-13 feeder (`:ieee13`), seeded, laptop-minutes scale.
Persistence follows the repo's two-tier convention: raw run data via `DrWatson.wsave`/
`wload` under `datadir("pv_boom", ...)` (gitignored, `/data/` rule), diff-friendly
`.txt`/`.csv` summaries under `results/pv_boom/` (committed), regenerable figures/report
embedded as base64 PNG inside one `.html` file (gitignored, new rule alongside the existing
`.png`/`.pdf`/`.svg` exclusions).

**Read first** (already reviewed by the planner — reuse directly, no need to re-explore):
- `src/experiments/materialize.jl` — `build_feeder`, `build_price`, `build_population`,
  `sub_seed`, plus the UNEXPORTED-but-directly-callable `TSODSO._default_house(bus, profiles,
  seed, T; φ, load_scale, pv_scale, dev_scale, batt_pmax, batt_emax, batt_soc0)`,
  `TSODSO._load_buses(feeder, feeder_sym)`, and the constants `TSODSO._IEEE13_LOAD_SCALE`
  (0.005), `TSODSO._IEEE13_PV_SCALE` (0.03), `TSODSO._IEEE13_DEV_SCALE` (1.0) — `_default_house`
  ALREADY takes `pv_scale` as an argument; a PV-penetration sweep is a thin wrapper that calls
  it directly with `pv_scale = TSODSO._IEEE13_PV_SCALE * pv_mult` per bus, mirroring
  `build_population(:default, ...)`'s own body exactly except for that one scaled argument.
- `src/experiments/run.jl`, `src/experiments/Scenario.jl` — the declarative `Scenario`/
  `run_scenario` entry point (feeder/strategy/seed/T/population/price/allow_export/ADMM
  knobs only — no PV-penetration selector exists, hence the wrapper above).
- `src/models/welfare_solve.jl` — `solve_welfare(feeder, pf, aggregators; T, λ₀, optimizer,
  allow_local, τ, rtol_exact, allow_export)`. `rtol_exact` is solve_welfare's OWN internal
  PF-04 gate — it THROWS by default on a genuinely inexact SOCP, so every sweep-point solve
  must be wrapped in `try`/`catch` (mirrors `scripts/socp_applicability_sweep.jl`'s own
  per-point `try`/`catch`/`class` pattern — read that file's `sweep`/`report` functions as the
  template for this task's own sweep loop and findings-file writer).
- `src/admm/solve_admm.jl` — `solve_admm(feeder, pf, aggregators; T, λ₀, ρ, maxiter, tol,
  ε_abs, ε_rel, τ, μ, allow_export, reactive_consensus)` returns `(; welfare, dadp,
  exact_maxgap, iters, residuals, ...)` — `residuals::AdmmResiduals` is the JuMP-free ledger
  `TSODSO.plot_convergence`/`TSODSO.plot_price_convergence` (ext/TSODSOMakieExt.jl) already
  know how to plot; keep it, don't discard it the way `ScenarioResult` does.
- `src/pricing/dlmp.jl` — `extract_dlmp(ctx)`, `decompose_dlmp(ctx)` (returns `(; energy,
  loss, congestion, voltage, reactive, total)`, each an `(N_buses, T)` matrix); both REFUSE
  (throw) on an ungated/inexact SOCP ctx — never call them on a ctx from an `rtol_exact`
  diagnostic override.
- `src/models/ac_oracle.jl`, `test/test_ac_oracle.jl` lines 180-260, `scripts/
  socp_applicability_sweep.jl` lines 130-165 — the CERTIFIED EXACT-04 finding's exact
  substrate: a 3-bus fixture (`Bus(1,0.95,vmax,true)`, `Bus(2,0.95,vmax,false)`,
  `Bus(3,0.95,vmax,false)`, `vmax=1.05`; `Branch(1,2,0.05,0.05,99.0)`, `Branch(2,3,0.05,
  0.05,99.0)`), one seeded `Aggregator` per non-root bus (`Thermostatic`+`Deferrable`+
  `PVBattery`, `pv_scale=1.2`, `load_scale=0.2`), `T=24`. At this EXACT point, `solve_welfare`
  with `ConvexBranchFlow()` and `rtol_exact = 1.0` (a documented diagnostic override — changes
  no `src/` gate) returns a loose-but-usable ctx; `solve_welfare` with `ACPowerFlow()` and
  `allow_local = true` gives the true nonconvex optimum; `TSODSO.assert_ac_exact!(ctx_socp,
  ctx_ac; rtol=1e-4, atol=1e-6)` reports per-hour, never throws on a numeric gap (only on a
  structural `T` mismatch) — this IS the known finding this task showcases, reproduced
  directly, not re-discovered.
- `src/planning/nash.jl` (`run_nash!`, boundary guards, seeding contract), `src/planning/
  coupling.jl` (`build_shared_transmission`), `src/planning/benders.jl` (`solve_stackelberg!`
  spec fields: `feeder`, `pf`, `aggregators`, `λ₀`, `master_kwargs`, optional `tol`/
  `max_iter`), `src/planning/master.jl` (`build_master`'s `c_y`/`y_max`/`α_op_lb`/`α_x_lb`
  contract — `α_op_lb`/`α_x_lb` are finite epigraph LOWER bounds that must sit BELOW the true
  minimum cost-to-go; an aggressively low value is always safe, only slower to tighten),
  `test/test_planning_nash.jl` lines 257-325 — the ONE known-converging N=2 worked example
  (toy 2-bus feeder, `T=1`, `corridor_cap=2.0`, `x_inv_max=[0.3,0.3]`, `c_inv=[1.0,1.0]`,
  `c_op=[[0.5],[0.5]]`, `master_kwargs=(;c_y=0.3,y_max=8.0,α_op_lb=-5.0,α_x_lb=0.0)`) — the
  starting-point scale to adapt, not to copy verbatim, for the IEEE-13-scale game in Task 2.
- `src/experiments/store.jl` — `DrWatson.wsave`/`wload` idiom (`using DrWatson: wsave, wload,
  datadir`); this task uses these directly (NOT `@tagsave`/`run_and_store`, which are
  `Scenario`-shaped) to persist a plain `Dict{String,Any}` between the two scripts.
- `scripts/run_scenario.jl` — the `@quickactivate "TSODSO"` + `using TSODSO` script header
  convention every script in this repo uses; copy it verbatim at the top of both new files.
- `ext/TSODSOMakieExt.jl` — `TSODSO.plot_convergence(res::AdmmResiduals; filename=nothing)`
  returns a `Figure`; Task 3 needs `Figure` objects (not files) to embed as base64, so call it
  with `filename = nothing` and read the `Figure` back, or save to a `mktempdir()` PNG and
  read those bytes — either is fine, pick whichever is less code.
- `.gitignore` lines 36-39 — the existing "generated figures are regenerable, exclude them"
  block this task extends with one more line for `.html`.

## Tasks

### Task 1 — PV-penetration operational sweep + centralized/ADMM cross-check

- **files:** `scripts/pv_boom_case_study.jl` (new)
- **action:** Write a Literate-style narrative script (`#` section-header comments explaining
  each step in prose, mirroring `docs/literate/pricing_dlmp.jl`'s and `scripts/
  socp_applicability_sweep.jl`'s comment density — this is a `scripts/` entry point, NOT
  registered in `docs/make.jl`, since it is heavier than a doc-build page should be).
  Start with the `@quickactivate "TSODSO"` header. Define a module-level `const
  PV_MULTS = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5]` (0.0 = pre-solar baseline, 1.0 = the existing
  documented `:ieee13`/`:default` calibration, 2.5 = the boom scenario) and a `const
  BASE_SEED = 20260806`. Define `pv_boom_population(feeder, feeder_sym, profiles, seed,
  T, pv_mult)` that mirrors `TSODSO.build_population`'s body exactly (same `_load_buses`,
  same `_IEEE13_LOAD_SCALE`/`_IEEE13_DEV_SCALE`, same battery sizing) but passes `pv_scale =
  TSODSO._IEEE13_PV_SCALE * pv_mult` to `TSODSO._default_house` — this is the one new "glue"
  function this task adds (document it as such, citing that `_default_house` already exposes
  `pv_scale`). For each `pv_mult` in `PV_MULTS`: build `feeder = build_feeder(:ieee13)`,
  `profiles = generate_profiles(; seed = sub_seed(BASE_SEED, :profiles), T = 24)`, `λ₀ =
  build_price(:mem, 24, profiles)`, `aggs = pv_boom_population(feeder, :ieee13, profiles,
  sub_seed(BASE_SEED, :population), 24, pv_mult)`, then `try` `solve_welfare(feeder,
  ConvexBranchFlow(), aggs; T=24, λ₀=λ₀, allow_export=true)` (default `rtol_exact` — do NOT
  loosen it here, a refusal at an extreme `pv_mult` IS informative), `extract_dlmp(ctx)`, and
  `decompose_dlmp(ctx)`; on success record `(; pv_mult, status="ok", welfare, exact_maxgap =
  ctx.meta[:socp_maxgap], dlmp, decomp)`; on a caught exception record `(; pv_mult,
  status="failed", reason = sprint(showerror, e))` and `continue` — never let one bad
  penetration point kill the sweep (mirrors `socp_applicability_sweep.jl`'s own per-point
  `try`/`catch`). ALSO run the declarative entry point once, at the `pv_mult=1.0` baseline
  point, via `Scenario(name="pv_boom_baseline", feeder=:ieee13, strategy=:centralized,
  seed=BASE_SEED, T=24)` + `run_scenario` (or `run_and_store` into `datadir("pv_boom",
  "sims")`), and assert its `welfare`/`dadp` agree with this task's own direct `pv_mult=1.0`
  point (same population, same seed derivation) — this is the "declarative Scenario" leg
  the case study is asked to demonstrate; state in a comment why the sweep itself cannot use
  `Scenario` directly (no PV-penetration selector in its schema, per `materialize.jl`'s read
  above). Then, AT `pv_mult = 1.0` ONLY (the one point `ρ=100.0` is already documented/
  validated for, per `Scenario.jl`'s own docstring), call `solve_admm(feeder,
  ConvexBranchFlow(), aggs; T=24, λ₀=λ₀, ρ=100.0, allow_export=true)` directly (same
  `feeder`/`aggs`/`λ₀` as the sweep point, not re-materialized) and compute/print the
  relative welfare gap and `maximum(abs, admm_dadp .- centralized_dlmp)` — keep the full
  `admm_result.residuals::AdmmResiduals` object for Task 3's convergence plot, do not discard
  it. Persist everything with `DrWatson.wsave(datadir("pv_boom", "results.jld2"),
  Dict{String,Any}("pv_mults" => PV_MULTS, "sweep" => sweep_rows, "admm_crosscheck" => (;
  pv_mult=1.0, welfare_centralized, welfare_admm, dadp_maxgap, residuals =
  admm_result.residuals)))` — `sweep_rows` is the `Vector` of per-point `NamedTuple`s above.
  Also write a diff-friendly `results/pv_boom/summary.csv` (one row per swept `pv_mult`:
  columns `pv_mult, status, welfare, exact_maxgap, welfare_delta_vs_baseline` — the last
  column relative to the `pv_mult=0.0` row) via `CSV.write`/`DataFrame` (both already
  project deps, per `src/experiments/sweep.jl`'s own precedent).
- **verify:** `julia --project=. scripts/pv_boom_case_study.jl` exits 0, prints one line per
  `pv_mult` with its `status`, prints the ADMM-vs-centralized welfare/price agreement numbers
  at `pv_mult=1.0`, and leaves `data/pv_boom/results.jld2` + `results/pv_boom/summary.csv` on
  disk (`test -f data/pv_boom/results.jld2 && test -f results/pv_boom/summary.csv`).
- **done:** the script runs end-to-end on a clean checkout in well under 10 minutes, at least
  4 of the 6 `pv_mult` points solve successfully (a genuine `status="failed"` point is an
  acceptable, honestly-reported outcome — never silently dropped or hidden), the declarative
  `Scenario`/`run_scenario` leg's `welfare`/`dadp` match the direct `pv_mult=1.0` point to
  floating-point tolerance, and `results.jld2`/`summary.csv` exist with the schema above.

### Task 2 — AC-oracle exactness stress + planning-layer Stackelberg-Nash investment response

- **files:** `scripts/pv_boom_case_study.jl` (append)
- **action:** In the SAME script, after Task 1's sweep, add a clearly-labeled "## Part A2 —
  the known SOCP/AC exactness boundary (EXACT-04)" section that reproduces the certified
  3-bus stress substrate verbatim (per the read-first section above: local `pvboom_stress_
  feeder()`/`pvboom_stress_house(bus; pv_scale, load_scale)` functions, `pv_scale=1.2`,
  `load_scale=0.2`, `vmax=1.05`, `T=24`, using `build_price(:mem, 24, nothing)` for `λ₀` since
  `:mem` ignores its `profiles` argument). Solve `ctx_socp` with `ConvexBranchFlow()` and
  `rtol_exact=1.0` (documented diagnostic override, changes no gate in `src/`), `ctx_ac` with
  `ACPowerFlow()` and `allow_local=true`, call `TSODSO.assert_ac_exact!(ctx_socp, ctx_ac;
  rtol=1e-4, atol=1e-6)`, and print/record `report.obj_gap`, the count of `!row.exact` hours
  in `report.hours`, and `ctx_socp.meta[:socp_maxgap]` — label this in every printed/written
  string as "the documented EXACT-04 finding, reproduced" (never re-derived/re-tuned; if the
  reproduction does NOT show any inexact hour, that is a signal something drifted from the
  certified fixture — stop and report the discrepancy rather than silently accepting a
  different-looking result). Then add "## Part B — feeding the boom into the planning layer"
  (NASH-02/NASH-01): build TWO IEEE-13-scale distributor specs from the ALREADY-SWEPT Task-1
  populations at `pv_mult=0.0` (distributor "baseline") and `pv_mult=2.5` (distributor
  "boom") — do NOT re-materialize or re-draw profiles; instead pick a short contiguous
  sub-horizon `T_planning` (e.g. hours `13:18`, spanning the afternoon PV-peak window
  documented in `materialize.jl`'s own comments) and build NEW `Thermostatic`/`Deferrable`/
  `PVBattery`/`Aggregator` instances per bus by slicing the ALREADY-CONSTRUCTED Task-1
  aggregator objects' own time-series fields (`Ppv`, `Pdc`, the thermostatic `Tout` profile)
  to that range, keeping every scalar device parameter identical — this reuses the exact
  already-drawn seeded realization with no new profile draw (`generate_profiles` is a Markov
  transition, not a re-sliceable pure function of `T`, so re-calling it with a smaller `T`
  would NOT reproduce the same hours). Slice `λ₀` to the same range. For each distributor,
  build `spec = (; feeder = build_feeder(:ieee13), pf = ConvexBranchFlow(), aggregators =
  sliced_aggs, λ₀ = sliced_λ₀, master_kwargs = (; c_y, y_max, α_op_lb, α_x_lb))`. Anchor the
  calibration to already-known quantities rather than guessing blind: read each distributor's
  own `welfare` at those hours from a quick `solve_welfare` call on the sliced data, set
  `α_op_lb` to at least `-2 * abs(welfare)` (a safe-but-not-absurd finite epigraph lower
  bound per `master.jl`'s own Pitfall M1 contract — always safe to set too low, only slower to
  tighten), `α_x_lb = 0.0` (follower LP cost is nonnegative by construction), `y_max` and
  `build_shared_transmission`'s `corridor_cap`/`x_inv_max` to 2-3x each distributor's own peak
  import magnitude at those hours (so the boxes are never spuriously binding), `c_y` and
  `c_inv`/`c_op` starting from the `test_planning_nash.jl` toy-fixture values (`c_y=0.3`,
  `c_inv=[1.0,1.0]`), scaling `c_op[i]` toward each distributor's own local energy-price level
  from Task 1 so investment and operating costs are commensurate. Build `shared =
  build_shared_transmission(; N=2, T=T_planning, corridor_cap, x_inv_max=[...], c_inv=[...],
  c_op=[[...],[...]])`, `z0 = zeros(2, T_planning)`, and call `run_nash!([spec_baseline,
  spec_boom], shared; z0=z0, tol_outer=1e-4, max_sweeps=100, checkpoint_dir=mktempdir())`. If
  `run_nash!`/`solve_stackelberg!` raises (max-iter/max-sweeps exhaustion, an infeasible
  follower trial), that is EXPECTED first-pass calibration friction at this new (never
  before exercised at this scale) operating point — each raised error names the exhausted
  bound/gap; iterate `α_op_lb`/`α_x_lb`/`y_max`/`corridor_cap`/`x_inv_max` until it converges,
  and add a one-paragraph "Deviation" comment directly above the final working values
  recording what was tried and why (mirrors `Scenario.jl`'s own documented `ρ=100.0`
  discovery precedent — this is normal, not a plan failure). On convergence, print/record
  `result.z` (converged coupling flow per distributor), `result.x_inv` (converged
  investment — the "investment response" the case study promises), and `result.trace`
  summary. Append `"nash_result" => (; z=result.z, x_inv=result.x_inv, converged=
  result.converged, sweeps=result.sweeps)` and `"ac_stress" => (; obj_gap=report.obj_gap,
  n_inexact_hours=count(!r.exact for r in report.hours), socp_maxgap=ctx_socp.meta
  [:socp_maxgap])` to the SAME `Dict` from Task 1 and re-`wsave` the whole thing to
  `data/pv_boom/results.jld2` (load it back with `wload` first, merge in, save — never
  overwrite Task 1's own keys). Extend `results/pv_boom/findings.txt` (new file, mirrors
  `socp_applicability_sweep.jl`'s `report()` function: plain `println`s to an `open(path,
  "w") do io ... end` block) with a short human-readable paragraph covering both the
  EXACT-04 reproduction and the Nash investment-response numbers.
- **verify:** re-running `julia --project=. scripts/pv_boom_case_study.jl` end-to-end (Task 1
  + Task 2 in one execution) exits 0, prints `result.converged == true` for the Nash game,
  prints at least one `!row.exact` hour for the AC-oracle stress reproduction, and leaves
  `results/pv_boom/findings.txt` on disk containing the literal substring `"EXACT-04"`.
- **done:** the AC-oracle stress block reproduces a genuine SOCP/AC gap (not silently exact —
  if it comes back all-exact, the task is NOT done; the fixture must be fixed to match the
  documented substrate, never the finding text edited to match a wrong result), the Nash game
  converges and reports a nonzero, distributor-differentiated `x_inv` (the boom distributor's
  investment need should differ from the baseline's — if it does not, note that explicitly as
  an honest finding rather than forcing a difference), and `data/pv_boom/results.jld2` carries
  every key from both tasks.

### Task 3 — self-contained HTML report generator

- **files:** `scripts/pv_boom_report.jl` (new), `.gitignore` (append one line)
- **action:** Add `/results/**/*.html` to `.gitignore`'s existing "generated figures are
  regenerable" block (next to the `.pdf`/`.png`/`.svg` lines) — the report is regenerable
  from `scripts/pv_boom_report.jl` + the committed `data/pv_boom/results.jld2`... actually
  `data/` itself is gitignored, so state in a comment that a reader must run
  `scripts/pv_boom_case_study.jl` first if `data/pv_boom/results.jld2` is absent. Write
  `scripts/pv_boom_report.jl` with the `@quickactivate "TSODSO"` header, `using CairoMakie`
  (already a project dependency, not a weakdep-only extension — safe to `using` directly in a
  script even though `src/` only reaches it via the `TSODSOMakieExt` weakdep) and `using
  Base64` (stdlib, zero new dependency). Load `results = DrWatson.wload(datadir("pv_boom",
  "results.jld2"))`. Build THREE `CairoMakie.Figure`s: (1) price curves — one line per
  successful `pv_mult` sweep point, `decomp.total` (or `dlmp`) at a representative stressed
  bus (e.g. the bus with the largest total-price spread across `pv_mult` levels) versus hour
  1:24; (2) a stacked decomposition (energy/loss/congestion/voltage) at the SAME bus for the
  highest successful `pv_mult`, versus hour; (3) `TSODSO.plot_convergence(results[
  "admm_crosscheck"].residuals)` (call it directly — this generic function already exists,
  do not reimplement residual plotting). For each `Figure`, write it to a `mktempdir()` PNG
  via `CairoMakie.save`, `read` the bytes, and `Base64.base64encode` them into a `data:
  image/png;base64,...` URI usable directly in an `<img src="...">` tag — no external image
  files, no JS image-loading library. Build a small exactness-gap table (one row per swept
  `pv_mult`: `pv_mult`, `status`, `welfare`, `exact_maxgap`) and a Nash-equilibrium table
  (`distributor`, `x_inv`, final `z`) as plain HTML `<table>` markup generated by string
  interpolation over `results["sweep"]`/`results["nash_result"]` — no templating library,
  matches the "no external template engine dependency" constraint. Assemble ONE self-
  contained HTML string: a minimal inline `<style>` block (no external CSS/JS/CDN links,
  everything inline or embedded), a title, the three embedded `<img>` figures each preceded
  by a one-paragraph caption drawn from `results/pv_boom/findings.txt`'s own text, and the two
  tables. Write it with `write(joinpath(mkpath(projectdir("results", "pv_boom")),
  "report.html"), html_string)` (`projectdir`/`mkpath` from DrWatson, matching every other
  script's `OUT = projectdir("results", ...); mkpath(OUT)` idiom, e.g. `socp_applicability_
  sweep.jl` line 93-94).
- **verify:** `julia --project=. scripts/pv_boom_report.jl` exits 0 after
  `scripts/pv_boom_case_study.jl` has been run at least once, and `results/pv_boom/
  report.html` opens in a browser with zero network requests (verify by grepping the file for
  the ABSENCE of any `http://`/`https://`/`<link `/`<script src=` reference: `! grep -E
  "https?://|<link |<script src=" results/pv_boom/report.html`).
- **done:** `results/pv_boom/report.html` is a single file, under a few MB, containing 3
  embedded `data:image/png;base64,` figures and 2 HTML tables, openable offline in any
  browser with no console errors from a missing external resource, and `.gitignore` excludes
  it from version control alongside the other regenerable figure formats.

## Constraints

- No `src/` file is modified — every task is orchestration over the existing public API
  (`Scenario`/`run_scenario`, `solve_welfare`, `solve_admm`, `extract_dlmp`/`decompose_dlmp`,
  `ACPowerFlow`/`assert_ac_exact!`, `build_shared_transmission`/`run_nash!`,
  `TSODSO.plot_convergence`). The only new logic is the `pv_boom_population` PV-penetration
  wrapper (parametrizes an argument `_default_house` already accepts), the sliced-aggregator
  helper in Task 2, and HTML/figure-rendering glue in Task 3.
- Never loosen a PF-04/exactness gate outside the two documented diagnostic-override call
  sites this plan names explicitly (`rtol_exact=1.0` on the main sweep's own points is
  FORBIDDEN — only the dedicated EXACT-04 stress substrate in Task 2 uses that override,
  exactly as `test_ac_oracle.jl`/`socp_applicability_sweep.jl` already do).
- A failed/inexact sweep point, a non-differentiated Nash investment response, or any other
  "surprising" numeric outcome is reported honestly in `findings.txt`/the HTML report — never
  silently dropped, hidden, or hand-tuned away to look cleaner (mirrors the project's own
  EXACT-04/thesis-reproduction honesty precedent, `.planning/STATE.md`).
- No new Project.toml dependency: `DrWatson` (`wsave`/`wload`/`datadir`/`projectdir`),
  `CairoMakie`, `CSV`/`DataFrames`, and stdlib `Base64` are all already available; the HTML
  report has zero templating-library dependency (string interpolation only).
- Seeded and reproducible throughout (`sub_seed`, fixed `BASE_SEED`) — a second run of
  `scripts/pv_boom_case_study.jl` reproduces byte-identical `welfare`/`dadp` values at every
  successful sweep point.

## must_haves

- **truths:** a reader can run `scripts/pv_boom_case_study.jl` then `scripts/
  pv_boom_report.jl` and get one shareable `.html` file telling the full PV-boom story
  (price reshaping, 4-way decomposition, centralized-vs-ADMM agreement, the EXACT-04 finding,
  the Nash investment response) without opening Julia again; every number in that file traces
  to a real solve, never a placeholder.
- **artifacts:** `scripts/pv_boom_case_study.jl` (new), `scripts/pv_boom_report.jl` (new),
  `data/pv_boom/results.jld2` (new, gitignored), `results/pv_boom/summary.csv` (new,
  committed), `results/pv_boom/findings.txt` (new, committed), `results/pv_boom/report.html`
  (new, gitignored), `.gitignore` (one new line).
- **key_links:** `scripts/pv_boom_case_study.jl` → `TSODSO.build_feeder`/`build_price`/
  `TSODSO._default_house`/`solve_welfare`/`solve_admm`/`extract_dlmp`/`decompose_dlmp`/
  `ACPowerFlow`/`TSODSO.assert_ac_exact!`/`build_shared_transmission`/`run_nash!` (the
  production entry points, never re-implemented); `scripts/pv_boom_case_study.jl` →
  `data/pv_boom/results.jld2` (via `DrWatson.wsave`); `scripts/pv_boom_report.jl` →
  `data/pv_boom/results.jld2` (via `DrWatson.wload`) → `results/pv_boom/report.html` (via
  `CairoMakie.save` + `Base64.base64encode` + string interpolation, zero external
  dependency at render time).

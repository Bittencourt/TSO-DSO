# # The Experiment Harness — Declarative Scenarios, Runs & Sweeps
#
# This page is the user-facing tour of the Phase-8 experiment harness (EXP-01/EXP-02/
# INFRA-04): declare a [`Scenario`](@ref) as a handful of primitive selectors, run it
# end-to-end with [`run_scenario`](@ref), persist it with provenance via
# [`run_and_store`](@ref), and fan out a Cartesian parameter sweep with
# [`run_sweep`](@ref) + [`collate_summary`](@ref). Every solve below EXECUTES during the
# Documenter build over the real `src/` code — the displayed welfare/gap/price numbers
# can never silently drift from the implementation (the `toy_dc.jl` reproducibility-proof
# pattern, threat T-01-09).
#
# ## Why a declarative `Scenario`?
#
# A [`Scenario`](@ref) holds ONLY primitive selectors (`Symbol`/`Int`/`Float64`/`Bool`/
# `String`) — never a constructed `Feeder`, aggregator vector, or price array. That one
# design decision buys three guarantees for free:
#
#  1. **Validation at construction** — the inner constructor `throw`s `ArgumentError` on
#     any unknown `feeder`/`strategy`/`price`/`population` selector or out-of-range
#     `T`/`seed`/`maxiter`, so a `Scenario` can never silently underdetermine a run
#     (threat T-08-05). There is no "half-configured" state to debug later.
#  2. **Deterministic materialization** — the heavy objects (feeder fixture, MEM price
#     shape, seeded residential aggregator population) are reconstructed from the
#     selectors + the master `seed` by `build_feeder`/`build_price`/`build_population`,
#     with independent sub-streams derived via `sub_seed` (never the global RNG). The
#     SAME `Scenario` in the SAME process reproduces bit-for-bit (INFRA-04).
#  3. **`savename`/provenance for free** — because every field sits inside DrWatson's
#     `default_allowed` scalar filter, the on-disk artifact name, hashing, and diffing
#     all fall out with zero customization.
#
# No solver is named anywhere in the harness (INFRA-02) — `run_scenario` routes through
# the framework's own `solve_welfare`/`solve_admm`, which pick their optimizer via the
# central solver factory.

using TSODSO

# ## A single declarative run
#
# Declare the scenario. Everything not named here takes its validated `@kwdef` default
# (`price = :mem`, `population = :default`, `allow_export = true`, the ADMM knobs, ...):

s = Scenario(name = "docs-demo", feeder = :ieee13, strategy = :centralized, seed = 1, T = 24)

# [`run_scenario`](@ref) materializes the feeder/price/population from the selectors +
# seed, dispatches on `s.strategy` (`:centralized` → `solve_welfare` + `extract_dlmp`),
# and normalizes the outcome into a strategy-independent [`ScenarioResult`](@ref). It is
# PATH-FREE — nothing touches the disk here; persistence is a separate seam below.

res_c = run_scenario(s)

# The social-welfare objective (thesis eq. 3.38) at the solved optimum:

res_c.welfare

# The PF-04 SOC-cone exactness certificate — the max `l·v − (P² + Q²)` gap across all
# (branch, hour). A tiny value means the relaxation is EXACT, so the recovered duals
# below are trustworthy prices, not artifacts of a slack cone:

res_c.exact_maxgap

# The day-ahead dynamic price (DADP) — the dual of the nodal active balance (eq. 3.31) —
# normalized to a `(n_load_nodes, T)` matrix with rows in ascending load-bus order, the
# SAME shape for every strategy so results stay directly comparable:

res_c.dadp

# Wall-clock for the full materialize+solve is recorded on the result (`res_c.elapsed`)
# for reporting, but it is NON-REPRODUCIBLE and never enters an equality/reproducibility
# comparison.
#
# ## Plot 1 — DADP price curves vs hour
#
# The `:mem` selector materializes the pinned 24-hour wholesale price shape (overnight
# trough → morning ramp → evening peak); each nodal DADP is that root price PLUS the
# network uplift (marginal loss / congestion / voltage terms — see the Rung-4 pricing
# page for the four-way decomposition). A few representative load buses against λ₀:

feeder13 = build_feeder(:ieee13)
load_buses = sort([b.id for b in feeder13.buses if !b.is_root])
λ₀ = build_price(:mem, s.T, nothing)

if Base.find_package("CairoMakie") !== nothing
    using CairoMakie
    CairoMakie.activate!(type = "png")

    fig1 = Figure(size = (900, 420), backgroundcolor = :white)
    ax1 = Axis(
        fig1[1, 1];
        title = "DADP vs hour — ieee13, centralized, seed 1",
        xlabel = "hour t",
        ylabel = "price λ_j[t]",
        xticks = 0:4:24,
    )
    lines!(
        ax1,
        1:s.T,
        λ₀;
        color = :black,
        linestyle = :dash,
        linewidth = 2.5,
        label = "λ₀ (MEM root price)",
    )
    for row in (1, cld(length(load_buses), 2), length(load_buses))
        lines!(
            ax1,
            1:s.T,
            res_c.dadp[row, :];
            linewidth = 2,
            label = "bus $(load_buses[row])",
        )
    end
    axislegend(ax1; position = :lt, framevisible = false)
    fig1
end

# ## Validation is a construction invariant
#
# A bogus selector never reaches a solver — the `Scenario` constructor itself throws a
# loud `ArgumentError` naming the valid set (threat T-08-05; caught here only so the
# page can display the message):

bad = try
    Scenario(name = "docs-bogus", feeder = :ieee14)
catch err
    err
end
sprint(showerror, bad)

# The same guard covers `strategy`/`price`/`population` selectors and the numeric ranges
# (`T ≥ 1`, `seed ≥ 1`, `maxiter ≥ 1`, positive ADMM knobs, the MPC/stochastic bands).
#
# ## The `:admm` strategy — same Scenario schema, decomposed solve
#
# Switching the ONE `strategy` selector re-runs the IDENTICAL materialized problem
# through the Rung-5 hand-rolled 2-block dual-ascent loop (`solve_admm`) instead of the
# monolithic solve. The result lands in the SAME `ScenarioResult` schema, now with the
# ADMM-only fields populated:

s_admm = Scenario(name = "docs-demo", feeder = :ieee13, strategy = :admm, seed = 1, T = 24)
res_a = run_scenario(s_admm)

(iters = res_a.iters, final_r = res_a.final_r, final_s = res_a.final_s)

# The decomposed welfare agrees with the centralized ground truth to a relative gap of

abs(res_a.welfare - res_c.welfare) / abs(res_c.welfare)

# and carries its own PF-04 exactness certificate from the final converged DSO-OPT
# re-solve:

res_a.exact_maxgap

# ## Plot 2 — centralized vs ADMM DADP at one bus
#
# `ScenarioResult` deliberately carries only the FINAL residual norms (the full
# per-iteration trace lives on `solve_admm`'s own result — see the Rung-5 page for the
# convergence figure), so the cross-strategy check displayed here is the one the
# normalized schema is built for: the two strategies' DADP overlaid at the load bus with
# the largest daily price spread, plus the per-hour absolute deviation on a log axis.

if Base.find_package("CairoMakie") !== nothing
    spread = vec(maximum(res_c.dadp; dims = 2) .- minimum(res_c.dadp; dims = 2))
    row = argmax(spread)

    fig2 = Figure(size = (1000, 400), backgroundcolor = :white)
    ax2a = Axis(
        fig2[1, 1];
        title = "DADP at bus $(load_buses[row]) — centralized vs ADMM",
        xlabel = "hour t",
        ylabel = "price λ[t]",
        xticks = 0:4:24,
    )
    lines!(ax2a, 1:s.T, res_c.dadp[row, :]; linewidth = 3, label = "centralized")
    lines!(
        ax2a,
        1:s.T,
        res_a.dadp[row, :];
        linewidth = 2,
        linestyle = :dash,
        color = :crimson,
        label = "ADMM ($(res_a.iters) iters)",
    )
    axislegend(ax2a; position = :lt, framevisible = false)

    ax2b = Axis(
        fig2[1, 2];
        title = "per-hour |Δλ| (same bus)",
        xlabel = "hour t",
        ylabel = "|λ_admm − λ_central|",
        xticks = 0:4:24,
        yscale = log10,
    )
    Δ = abs.(res_a.dadp[row, :] .- res_c.dadp[row, :])
    lines!(ax2b, 1:s.T, max.(Δ, 1e-16); linewidth = 2, color = :gray30)
    fig2
end

# The curves are visually indistinguishable — the ADMM coupling price converged onto the
# centralized dual, which is exactly the ADMM-04 cross-validation the normalized
# `ScenarioResult` schema exists to make routine.
#
# ## Provenance storage — `run_and_store`
#
# [`run_and_store`](@ref) runs the scenario and `@tagsave`s a self-describing JLD2 under
# `dir` (default `datadir("sims")`, gitignored): EVERY `Scenario` selector, the scalar
# results, the DADP matrix, `:julia_version`, AND — stamped by DrWatson itself —
# `:gitcommit` (+ `:gitpatch` on a dirty tree). The commit + the committed
# `Manifest.toml` at that commit fully pin the environment that produced the artifact.
# `dir` is an explicit keyword precisely so hermetic runs (tests, this docs build) can
# point it at a throwaway directory instead of the repo's `data/sims`:

store_dir = mktempdir()
res_stored = run_and_store(s; dir = store_dir)

# [`scenario_filename`](@ref) is the single source of truth for the artifact's name —
# `savename(s, "jld2"; digits = 10)`, hash-suffix-truncated when the fully descriptive
# stem would exceed the filesystem's 255-byte basename ceiling (the content itself
# always carries every selector, so nothing is lost):

fname = scenario_filename(s)

# The artifact is on disk and loads back as a plain string-keyed dict:

loaded = TSODSO.DrWatson.wload(joinpath(store_dir, fname))
sort(collect(keys(loaded)))

# The stamped git-commit provenance anchor (a `_dirty`-suffixed commit means `:gitpatch`
# also holds the uncommitted diff — the run is still fully reconstructible):

loaded["gitcommit"]

# And the stored numbers round-trip exactly — the loaded artifact IS the in-memory
# result:

loaded["welfare"] == res_stored.welfare

# ## A parameter sweep — `run_sweep` + `collate_summary`
#
# [`run_sweep`](@ref) expands a `Dict` via DrWatson's `dict_list`: Vector-valued entries
# expand the Cartesian product, scalars stay fixed. Here `2 strategies × 2 seeds = 4`
# scenarios, each run + stored (with the same provenance stamping as above) into a
# throwaway directory:

params = Dict(
    :name => "docs-sweep",
    :feeder => :ieee13,
    :strategy => [:centralized, :admm],
    :seed => [1, 2],
    :T => 24,
)
sweep_dir = mktempdir()
sweep_results = run_sweep(params; dir = sweep_dir)
length(sweep_results)

# [`collate_summary`](@ref) reads every per-run JLD2 under the directory back into ONE
# diff-friendly summary table (fixed column order, deterministic row order, no
# machine-local path column — so re-collating the same runs is byte-identical, no git
# churn) and writes it as a CSV; the committed home for real sweeps is
# `results/sweeps/`:

csvpath = joinpath(sweep_dir, "docs-sweep.csv")
df = collate_summary(sweep_dir, csvpath)
df[:, [:strategy, :seed, :welfare, :exact_maxgap, :iters, :final_r, :final_s]]

# ## Plot 3 — sweep welfare by (strategy, seed)
#
# The collated DataFrame feeds analysis/figures directly. Grouped bars of welfare by
# seed, dodged by strategy — the centralized/ADMM pairs coincide at each seed (the
# cross-strategy agreement above, now holding across the seed axis), while the two seeds
# land on genuinely different welfare levels (different seeded populations — the
# INFRA-04 seed-sensitivity flip side):

if Base.find_package("CairoMakie") !== nothing
    seeds = sort(unique(df.seed))
    strategies = [:centralized, :admm]
    xpos = [findfirst(==(sd), seeds) for sd in df.seed]
    grp = [findfirst(==(Symbol(st)), strategies) for st in df.strategy]
    cols = [RGBf(0.13, 0.42, 0.72), RGBf(0.85, 0.44, 0.13)]

    fig3 = Figure(size = (750, 420), backgroundcolor = :white)
    ax3 = Axis(
        fig3[1, 1];
        title = "Sweep — welfare by (strategy, seed)",
        xlabel = "master seed",
        ylabel = "social welfare (eq. 3.38)",
        xticks = (1:length(seeds), "seed " .* string.(seeds)),
    )
    barplot!(ax3, xpos, df.welfare; dodge = grp, color = cols[grp])
    Legend(
        fig3[1, 2],
        [PolyElement(color = c) for c in cols],
        string.(strategies);
        framevisible = false,
    )
    fig3
end

# ## Where to go from here
#
# The editable entry points mirroring this page live under `scripts/`:
#
#   - `scripts/run_scenario.jl` — edit the `Scenario(...)` call, run
#     `julia --project=. scripts/run_scenario.jl` for a single provenance-stamped run
#     into `data/sims` (gitignored).
#   - `scripts/sweep.jl` — edit the `params` Dict, run it to launch a sweep and collate
#     the committed CSV summary under `results/sweeps/`.
#
# The `mpc_*` and `stoch_*` fields a `Scenario` also carries are NO-OPS for the
# `:centralized`/`:admm` strategies shown here — they are consumed only by the separate
# `run_mpc` (Rung-8 rolling horizon) and `run_stochastic` (Rung-9 uncertainty) entry
# points, which read the same declarative `Scenario` schema.

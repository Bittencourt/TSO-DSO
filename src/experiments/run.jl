# src/experiments/run.jl
#
# SEAM: ScenarioResult + run_scenario strategy dispatch + normalization (EXP-01 / INFRA-04).
# OWNER: plan 08-03 (this plan).
#
# THE FIRST TRUE END-TO-END CAPABILITY of the phase: `run_scenario(s::Scenario)` materializes
# the heavy objects (08-02's `build_feeder`/`build_price`/`build_population`/`sub_seed`) and
# DISPATCHES on `s.strategy` — `:centralized` -> `solve_welfare` + `extract_dlmp`, `:admm` ->
# `solve_admm` — then NORMALIZES both into one comparable `ScenarioResult` (welfare, node×T
# DADP, exactness certificate, iters/final residuals for ADMM, timings). An unknown strategy
# throws `ArgumentError`. This is PURE ORCHESTRATION over already-validated Phase 3-7 builders
# (RESEARCH Summary / Pattern 1) — no new model, no new solver named anywhere (INFRA-02).
#
# Because the seed is threaded end-to-end (08-02's `sub_seed`) and the Clarabel path is
# single-threaded, a same-Scenario same-seed run is bit-for-bit identical within one process —
# the load-bearing INFRA-04 reproducibility gate goes GREEN here. Timings are recorded on the
# result but EXCLUDED from every equality comparison (RESEARCH Anti-Pattern: wall-clock is
# non-deterministic and must never enter a reproducibility check).
#
# `run_scenario` is PATH-FREE — it returns a `ScenarioResult`, never writes a file (persistence
# is a separate seam, 08-04's `store.jl`).
#
# Task 1 landed the `ScenarioResult` record + the `:centralized` branch (end-to-end slice +
# the INFRA-04 same-seed reproducibility gate). THIS TASK (Task 2) adds the `:admm` branch
# (dispatching to `solve_admm`, whose `dadp` is ALREADY node×T — RESEARCH A5 — matching the
# `:centralized` shape) and the terminal `else` strategy guard (throws `ArgumentError` naming
# the two valid strategies; threat T-08-08). No solver is named anywhere in this file
# (INFRA-02) — `solve_admm`/`solve_welfare` route through `select_optimizer` internally.

"""
    ScenarioResult

The normalized, comparable outcome of [`run_scenario`](@ref) — the SAME schema for both the
`:centralized` and `:admm` strategies (EXP-01), so results are directly comparable across
strategies and across sweep runs (EXP-02).

# Fields

  - `scenario::Scenario` — the input spec this result was produced from (provenance).
  - `welfare::Float64` — the social-welfare objective (thesis eq. 3.38) at the converged/solved
    optimum.
  - `dadp::Matrix{Float64}` — the day-ahead dynamic price, normalized to `(n_load_nodes, T)`
    with rows in ASCENDING load-bus order — the SAME shape for `:centralized`
    (`extract_dlmp(ctx)[load_buses, :]`) and `:admm` (already node×T, RESEARCH A5), making the
    two strategies' DADP directly comparable.
  - `exact_maxgap::Float64` — the PF-04 SOC-cone exactness certificate (`ctx.meta[:socp_maxgap]`
    for `:centralized`, `r.exact_maxgap` for `:admm`).
  - `iters::Union{Missing,Int}` — ADMM iteration count; `missing` for `:centralized` (no
    iteration — a single monolithic solve).
  - `final_r::Union{Missing,Float64}`, `final_s::Union{Missing,Float64}` — the FINAL ADMM
    primal/dual residual norms (`last(residuals.primal_trace)`/`last(residuals.dual_trace)`);
    `missing` for `:centralized`.
  - `elapsed::Float64` — wall-clock seconds for the full materialize+solve (`@elapsed`).
    NON-REPRODUCIBLE: recorded for reporting only, NEVER compared in a reproducibility/equality
    check (RESEARCH Anti-Pattern; threat T-08-07).
"""
struct ScenarioResult
    scenario::Scenario
    welfare::Float64
    dadp::Matrix{Float64}
    exact_maxgap::Float64
    iters::Union{Missing, Int}
    final_r::Union{Missing, Float64}
    final_s::Union{Missing, Float64}
    elapsed::Float64
end

"""
    run_scenario(s::Scenario) -> ScenarioResult

Materialize the heavy Phase 1-7 objects from `s`'s primitive selectors + master seed, then
DISPATCH on `s.strategy`:

  - `:centralized` -> [`solve_welfare`](@ref) + [`extract_dlmp`](@ref), normalized to the
    sorted-load-bus node×T shape; `iters`/`final_r`/`final_s` are `missing` (no ADMM iteration).
  - `:admm` -> [`solve_admm`](@ref); `dadp` is ALREADY node×T (RESEARCH A5) and `iters`/
    `final_r`/`final_s` are populated from the converged residual trace.
  - any other selector -> throws `ArgumentError` naming the two valid strategies (a `Scenario`
    itself already guards this at construction — 08-02 — so this is defensive-in-depth, threat
    T-08-08).

PATH-FREE (INFRA-04 Pitfall 6): returns a `ScenarioResult`, never writes to disk — persistence
is [`run_and_store`](@ref) (08-04). Because the seed is threaded end-to-end via `sub_seed`
(08-02) and the Clarabel solve path is single-threaded, two calls with the SAME `Scenario` in
the SAME process return `==`-identical `welfare`/`dadp`/`exact_maxgap` (INFRA-04, the
load-bearing same-seed reproducibility gate); a different `seed` changes the profile-driven
population and hence the result (INFRA-04 seed sensitivity). Wall-clock is recorded on the
result under `elapsed` but is EXCLUDED from every such comparison (RESEARCH Anti-Pattern).
"""
function run_scenario(s::Scenario)
    elapsed = @elapsed begin
        # --- 1. MATERIALIZE (deterministic in s.seed; RESEARCH Pattern 1 / 08-02) -------------
        feeder = build_feeder(s.feeder)
        profiles = generate_profiles(; seed = sub_seed(s.seed, :profiles), T = s.T)
        λ₀ = build_price(s.price, s.T, profiles)
        aggs = build_population(
            s.population,
            feeder,
            s.feeder,
            profiles,
            sub_seed(s.seed, :population),
        )
        pf = ConvexBranchFlow()

        # --- 2. DISPATCH on s.strategy, normalized to a common (welfare, dadp, exact_maxgap,
        # iters, final_r, final_s) shape (EXP-01 / RESEARCH Pattern 1 / threat T-08-09). --------
        if s.strategy === :centralized
            ctx, welfare, _ = solve_welfare(
                feeder,
                pf,
                aggs;
                T = s.T,
                λ₀ = λ₀,
                allow_export = s.allow_export,
            )
            load_buses = sort!([a.bus for a in aggs])
            dadp = extract_dlmp(ctx)[load_buses, :]           # normalize to sorted node×T
            maxgap = ctx.meta[:socp_maxgap]

            result = (;
                welfare = Float64(welfare),
                dadp = Matrix{Float64}(dadp),
                exact_maxgap = Float64(maxgap),
                iters = missing,
                final_r = missing,
                final_s = missing,
            )
        elseif s.strategy === :admm
            r = solve_admm(
                feeder,
                pf,
                aggs;
                T = s.T,
                λ₀ = λ₀,
                ρ = s.ρ,
                maxiter = s.maxiter,
                ε_abs = s.ε_abs,
                ε_rel = s.ε_rel,
                τ = s.τ_ratio,
                μ = s.μ,
                allow_export = s.allow_export,
            )
            result = (;
                welfare = Float64(r.welfare),
                dadp = Matrix{Float64}(r.dadp),               # already node×T (RESEARCH A5)
                exact_maxgap = Float64(r.exact_maxgap),
                iters = Int(r.iters),
                final_r = Float64(last(r.residuals.primal_trace)),
                final_s = Float64(last(r.residuals.dual_trace)),
            )
        else
            # Terminal strategy guard (threat T-08-08): a Scenario already validates its own
            # `strategy` field at construction (08-02), so this branch is DEFENSIVE-IN-DEPTH —
            # it never fires via a normally-constructed Scenario, but keeps run_scenario safe
            # if ever called against a hand-built/mutated selector.
            throw(
                ArgumentError(
                    "run_scenario: unknown strategy $(repr(s.strategy)); expected " *
                    ":centralized or :admm",
                ),
            )
        end
    end

    return ScenarioResult(
        s,
        result.welfare,
        result.dadp,
        result.exact_maxgap,
        result.iters,
        result.final_r,
        result.final_s,
        elapsed,
    )
end

export ScenarioResult, run_scenario

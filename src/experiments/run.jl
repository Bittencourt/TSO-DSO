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
# THIS TASK (Task 1): the `ScenarioResult` record + the `:centralized` branch (end-to-end
# slice + the INFRA-04 same-seed reproducibility gate). The `:admm` branch + the terminal
# strategy guard land in Task 2 — until then, any non-`:centralized` strategy falls through to
# a TEMPORARY `error` (not faked as a real dispatch) rather than silently doing nothing.

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
    iters::Union{Missing,Int}
    final_r::Union{Missing,Float64}
    final_s::Union{Missing,Float64}
    elapsed::Float64
end

"""
    run_scenario(s::Scenario) -> ScenarioResult

Materialize the heavy Phase 1-7 objects from `s`'s primitive selectors + master seed, then
DISPATCH on `s.strategy`:

- `:centralized` -> [`solve_welfare`](@ref) + [`extract_dlmp`](@ref), normalized to the
  sorted-load-bus node×T shape; `iters`/`final_r`/`final_s` are `missing` (no ADMM iteration).
- `:admm` -> [`solve_admm`](@ref) (Task 2 — NOT YET implemented in this commit).
- any other selector -> throws (Task 2 lands the final `ArgumentError` guard; a `Scenario`
  itself already guards unknown strategies at construction — 08-02).

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
        aggs = build_population(s.population, feeder, profiles, sub_seed(s.seed, :population))
        pf = ConvexBranchFlow()

        # --- 2. DISPATCH on s.strategy, normalized to a common (welfare, dadp, exact_maxgap,
        # iters, final_r, final_s) shape (EXP-01 / RESEARCH Pattern 1 / threat T-08-09). --------
        if s.strategy === :centralized
            ctx, welfare, _ = solve_welfare(
                feeder, pf, aggs; T = s.T, λ₀ = λ₀, allow_export = s.allow_export,
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
        else
            # TEMPORARY (Task 1 only): the :admm branch + the terminal ArgumentError guard land
            # in Task 2. Do not fake either here — fail loudly instead.
            throw(
                ErrorException(
                    "run_scenario: strategy $(repr(s.strategy)) not yet implemented in this " *
                    "commit (Task 2 adds :admm + the terminal strategy guard)",
                ),
            )
        end
    end

    return ScenarioResult(
        s, result.welfare, result.dadp, result.exact_maxgap,
        result.iters, result.final_r, result.final_s, elapsed,
    )
end

export ScenarioResult, run_scenario

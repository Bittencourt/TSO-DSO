# src/experiments/run.jl
#
# SEAM: ScenarioResult + run_scenario strategy dispatch + normalization (EXP-01 / INFRA-04).
# OWNER: plan 08-01 (this plan) wires this STUB into the include graph; plan 08-03 FILLS it.
#
# STUB (this plan): comment-only seam so the include graph is complete and file-disjoint for
# Wave 3 (depends on 08-02's Scenario + materialize.jl). Plan 08-03 fills:
#
#     struct ScenarioResult
#         scenario, welfare, dadp, exact_maxgap, iters, final_r, final_s, elapsed
#     end
#
#     function run_scenario(s::Scenario) -> ScenarioResult
#         # materialize (build_feeder/build_price/build_population from selectors + seed),
#         # then dispatch on s.strategy:
#         #   :centralized -> solve_welfare + extract_dlmp[load_buses,:] (iters/final_r/final_s = missing)
#         #   :admm        -> solve_admm (dadp already node×T; iters/final_r/final_s populated)
#         #   else         -> throw(ArgumentError(...))  # strategy guard
#     end
#
# `run_scenario` is PATH-FREE (persistence is a separate seam, 08-04's store.jl). Because the
# seed is threaded end-to-end (08-02) and the Clarabel path is single-threaded, a same-Scenario
# same-seed run is bit-for-bit identical — the load-bearing INFRA-04 reproducibility gate goes
# GREEN in this plan. Timings are recorded but EXCLUDED from every equality comparison.
#
# Filled by plan 08-03 (EXP-01 / INFRA-04 — RESEARCH §Pattern 1 dispatch body / §Code Examples
# reproducibility gate / §Anti-Patterns).

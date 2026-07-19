# src/pricing/fit.jl
#
# SEAM: flat feed-in-tariff (FIT) baseline (PRICE-04).
# OWNER: plan 05-03.
#
# Empty (comment-only) stub wired onto the include graph in plan 05-01. Plan 05-03 fills
# it and declares its own `export`s. It will export:
#   - `fit_baseline(feeder, pf, aggregators; λ_fit, T, ...)` — re-solve the operational
#     welfare problem under a FLAT feed-in tariff λ_fit (the static-pricing counterfactual)
#     and return the baseline welfare / prices, plus the DLMP-vs-FIT efficiency ratio the
#     thesis reports.
#
# Consumes the operational solve (`solve_welfare` / `operational_oracle`) and the DLMP
# extraction (plan 05-02) — no change to the Phase-4 seam.

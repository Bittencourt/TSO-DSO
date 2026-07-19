# src/pricing/dlmp.jl
#
# SEAM: DLMP extraction + four-way decomposition (PRICE-02).
# OWNER: plan 05-02.
#
# Empty (comment-only) stub wired onto the include graph in plan 05-01. Plan 05-02 fills
# it and declares its own `export`s. It will export:
#   - `extract_dlmp(ctx; bus, T)`      — read the distribution price λ_j[t] (the dual of the
#                                        registered `:balance_p` active nodal balance) at a bus.
#   - `decompose_dlmp(ctx; bus, T)`    — split the DLMP into its energy / loss / voltage /
#                                        congestion components using the branch-flow constraint
#                                        duals registered in plan 05-01 (`:cone` 3.39, `:vdrop`
#                                        3.33, `:cpydrop` 3.43, `:smax` 3.36) summed over the
#                                        root→bus tree path, with the sum-to-nodal-price identity
#                                        (Σ components == λ_j) as the correctness net.
#
# Consumes ONLY the additive Phase-4 seam from plan 05-01 (registered duals) — no change to
# `solve_welfare` or the power-flow formulations.

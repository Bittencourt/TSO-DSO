# src/pricing/checks.jl
#
# SEAM: economic-direction price checks (PRICE-05).
# OWNER: plan 05-04.
#
# Empty (comment-only) stub wired onto the include graph in plan 05-01. Plan 05-04 fills
# it and declares its own `export`s. It will export:
#   - `economic_direction_checks(ctx; ...)` — assert the DLMP moves in the ECONOMICALLY
#     CORRECT direction in the canonical regimes: prices rise into a congestion / import
#     window and fall (can go negative) in a PV-glut / reverse-flow / over-voltage window,
#     i.e. the congestion and voltage DLMP components carry the expected sign.
#
# Consumes the decomposed DLMP (plan 05-02) — pure post-processing over a solved ctx.

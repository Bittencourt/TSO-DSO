# src/models/complementarity_4q.jl
#
# SEAM: 4Q-BESS post-solve complementarity certificate (MESH-04 clause 2).
# OWNER: plan 19-05.
#
# WHAT IT WILL BECOME: a new named certificate function, a peer of `assert_socp_exact!` and
# `assert_battery_complementarity!`, that post-solve-checks the 4Q-BESS apparent-power cone
# binding/complementarity condition against its own WR-01 tolerance — never a reused tolerance
# from an existing certificate (project-wide certificate-laundering guard). Throw-by-default
# with a `report` kwarg to opt into report-don't-throw mode, per D-06/D-07. This file is
# intentionally comment-only — no `struct`, no `function`, no `export` — until plan 19-05
# fills it.

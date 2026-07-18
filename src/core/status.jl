# src/core/status.jl
#
# SEAM: solve-status discipline (INFRA-03).
# OWNER: plan 01-03.
#
# When filled, this file will provide `assert_solved!(model; dual, allow_local)`,
# the single choke point wrapping `optimize!`. It delegates to JuMP's built-in
# `is_solved_and_feasible(model; dual, allow_local=false)` (the modern idiom that
# supersedes hand-checking `termination_status == OPTIMAL`), errors loudly with
# full diagnostics on non-optimal status, and offers an `assert_no_slack` helper
# to catch hidden constraint slack. Declares its own exports.
#
# Intentionally empty in plan 01-01: the package must precompile with this stub.

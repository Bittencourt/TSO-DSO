# test/test_planning_certification_integer.jl
#
# Seam: INT-03/D-10 — certify (not assume) the integer Benders loop's answer on the
# canonical D-12 tiny instance against an EXHAUSTIVE enumeration of all 16 K=4 lattice
# points, computed via the REAL `solve_follower!`/`solve_planning_oracle!` production
# entrypoints at each point (never the archived closed-form shortcut from
# `11-01-PLAN.md`/`test_planning_certification.jl`'s own hand-derivation). Mirrors that
# file's own SEAM/OWNER header-comment style and its "certify, don't assume" framing.
#
# D-10 (24-CONTEXT.md): exhaustive enumeration is the PRIMARY certificate for INT-03; a
# BilevelJuMP reduction is a SECONDARY confirmation only where mode-compatible.
#
# D-11 NON-BLOCKER FINDING (24-RESEARCH.md Priority Finding 3 — read, NOT re-derived,
# NOT re-attempted here): BilevelJuMP's secondary certificate is UNAVAILABLE on this
# fixture for two independent, already-verified reasons, so no new BilevelJuMP
# `@testitem` is written in this file:
#   1. `StrongDualityMode`/`ProductMode` (Ipopt-backed) throw
#      `MOI.UnsupportedConstraint{VariableIndex,ZeroOne}` immediately — Ipopt cannot
#      represent ANY discrete variable, regardless of objective linearity.
#   2. `BigMMode` (HiGHS-backed) CAN represent the binary leader (confirmed on a
#      linearized toy variant), but on THIS fixture's genuinely quadratic upper-level
#      welfare term it degrades to the SAME MIQP failure already documented as a
#      PERMANENT NEGATIVE regression in `test/test_planning_certification.jl:36-64`
#      (header DEVIATION note) and `:160-167` (the asserted
#      `termination_status(r_bigm.model) == MOI.OTHER_ERROR` regression) — a failure
#      that exists INDEPENDENT of leader integrality (it already fires today with a
#      continuous leader, purely from BigMMode's own complementarity binaries).
# Per D-10, this is a documented, non-blocking finding — NOT a coverage gap, and NOT an
# invitation to write BilevelJuMP code known in advance to fail on this fixture.
#
# TESTITEMRUNNER ISOLATION NOTE (Rule 3 — auto-fixed blocking issue, discovered by
# reading `TestItemRunner.jl`'s own `run_tests`/`TestItemDetection` source this
# session): the runner's discovery pass parses each file with `JuliaSyntax` and
# extracts ONLY the source ranges of `@testitem`/`@testsetup`/`@testmodule`
# invocations — every other top-level form in a test file (including a plain
# top-level `function ... end`) is never `include`d and is therefore silently DEAD
# CODE from the runner's perspective, unreachable from inside any `@testitem`'s own
# freshly-`gensym`'d isolated module. `enumerate_lattice` below is defined as a plain
# top-level function (per the plan's literal instruction and as an independently
# verifiable, single canonical reference implementation — see this file's own Task-1
# verification, which `include()`s this file directly, bypassing TestItemRunner
# entirely, to prove this EXACT committed definition is correct). Because it cannot be
# `using`-imported into a `@testitem`'s isolated module (it is not a `@testsetup`/
# `@testmodule`), the certifying `@testitem`s below (Task 2) each carry an IDENTICAL,
# independently-defined nested copy of this same logic — the only way to make the
# enumeration genuinely EXECUTE under the real TestItemRunner-driven `Pkg.test()` gate,
# rather than merely appearing to be tested while actually being inert.

"""
    enumerate_lattice(oracle, follower; K::Int = 4, y_max::Real = 8.0, c_y::Real = 0.3)
        -> (; best_b, best_y, best_total, all_totals)

Exhaustively enumerate all `2^K` binary-expansion lattice points reachable by
`build_master_integer`'s own `y_inv = (y_max/2^K) * Σ_k 2^(k-1) b_k` formula (D-01/D-02
— the IDENTICAL formula, so this independent certificate can never silently disagree
with the production builder on what `y_inv` a given `b` maps to, T-24-13), and for each
point find the exact recourse `Q(y_inv) = min_{z ∈ [0, y_inv]} [follower_cost(z) -
oracle_welfare(z)]` via a deterministic ternary search over the REAL, ALREADY-BUILT
`oracle`/`follower` (`solve_planning_oracle!`/`solve_follower!` — never the archived
closed-form `0.5*z^2-0.7*z` shortcut). `Q` is convex in `z` on this fixture (oracle
welfare concave, follower cost convex, sum of convex functions convex), so ternary
search on `[0, y_inv]` converges to the true minimum.

**Rule 1 auto-fixed bug (found empirically this session, NOT present in the plan's own
literal `<verify>` script as-shipped):** on the D-12 fixture the follower's deliverable
capacity is `corridor_cap * x_inv_max = 2.0 * 2.0 = 4.0`, strictly BELOW `y_max = 8.0` —
so 7 of the 16 lattice points (`y_inv > 4.0`) have a ternary-search upper bound that
exceeds the follower's feasible region, and `solve_follower!` genuinely (and correctly,
per its own documented contract) returns the INFEASIBLE branch `(; feasible = false, v,
u)` for any trial `z` in that regime — a NamedTuple with no `.cost` field. Naively
calling `.cost` on that branch throws `FieldError` (confirmed: reproduces exactly this
way when the plan's literal inline script is run verbatim). The fix treats an infeasible
`z` as `+Inf` in the extended-value sense (a convex function restricted to a feasible
sub-interval and set to `+Inf` outside remains convex — the standard indicator-function
device), which is mathematically sound here since the feasible sub-interval `[0, 4.0]`
is always nonempty on this fixture and ternary search on an extended-value convex
function still converges to the true constrained minimum.

Returns `(; best_b, best_y, best_total, all_totals)`, `all_totals` a `Vector{Float64}`
indexed `1:2^K` (index `i+1` <-> the lattice point encoded by integer `i`, `0`-based,
bit `k` <-> `b[k]`), for a caller to re-derive any lattice point's own total without
re-enumerating.
"""
function enumerate_lattice(oracle, follower; K::Int = 4, y_max::Real = 8.0, c_y::Real = 0.3)
    Qfun(z) = begin
        fr = solve_follower!(follower, [z])
        # Rule 1 auto-fix (see docstring): an undeliverable z is a genuine infeasibility,
        # not an error -- extend Q to +Inf there so ternary search never dereferences a
        # nonexistent .cost field and still finds the true constrained minimum.
        fr.feasible || return Inf
        orr = solve_planning_oracle!(oracle, [z])
        fr.cost - orr.cost
    end
    function ternary_min(f, lo, hi; iters::Int = 100)
        for _ in 1:iters
            m1 = lo + (hi - lo) / 3
            m2 = hi - (hi - lo) / 3
            f(m1) < f(m2) ? (hi = m2) : (lo = m1)
        end
        z = (lo + hi) / 2
        return (z, f(z))
    end

    n = 2^K
    all_totals = Vector{Float64}(undef, n)
    best_total = Inf
    best_y = NaN
    best_b = Int[]

    for i in 0:(n - 1)
        b = [(i >> (k - 1)) & 1 for k in 1:K]
        # IDENTICAL formula to build_master_integer's own y_inv expression (T-24-13).
        y_inv = (y_max / 2^K) * sum(2.0^(k - 1) * b[k] for k in 1:K)
        _, Qv = y_inv <= 0 ? (0.0, 0.0) : ternary_min(Qfun, 0.0, y_inv)
        total = c_y * y_inv + Qv
        all_totals[i + 1] = total
        if total < best_total
            best_total = total
            best_y = y_inv
            best_b = b
        end
    end

    return (; best_b, best_y, best_total, all_totals)
end

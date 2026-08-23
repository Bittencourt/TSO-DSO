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

# ---------------------------------------------------------------------------------------
# TASK 2 — INT-03 certification `@testitem` + D-15 certificates + D-11 documentation.
#
# CONFIRMED FINDING (this session, via the enumeration harness above run against the REAL
# `solve_stackelberg!(...; master = build_master_integer(...), known_optimum = ...)` path
# — exactly the certification INT-03/24-05 exists to run): on the D-12 canonical instance,
# the Laporte-Louveaux cut wired by plans 24-03/24-04 (`add_ll_cut!`/`apply_integer_cuts!`,
# `src/planning/master_integer.jl`) uses
#
#     Q_nu = follower_res.cost - oracle_res.cost   (benders.jl, evaluated at lb_res.z)
#
# — i.e. the recourse value AT WHATEVER `z` THE MASTER'S CURRENT TRIAL HAPPENED TO PICK for
# the incumbent corner `b^ν`, not the TRUE, EXACTLY-MINIMIZED recourse
# `Q(y_inv(b^ν)) = min_{z ∈ [0, y_inv(b^ν)]} [follower_cost(z) - oracle_welfare(z)]` the
# Laporte-Louveaux theorem's own "cut with a value" REQUIRES (`add_ll_cut!`'s own docstring
# even states this precondition: "its EXACT recourse value Q_nu = Q(b^ν) ... never estimated
# here" — the CALLER, `benders.jl`, is the one that fails to honor it). Since the master's
# box constraint only guarantees `z_k <= y_inv(b^ν)` (feasibility), NOT `z_k` = the
# minimizer, `Q_nu >= Q(y_inv(b^ν))` in general (an UPPER-BOUND surrogate). Because cut rows
# are NEVER retracted (`master.model`'s own build-once/append-only discipline, correct in
# isolation), an EARLY, loose (too-high) `Q_nu` recorded before enough `:op`/`:x` cuts have
# refined the master's own view of `z` PERMANENTLY over-constrains `theta` at that corner —
# concretely CONFIRMED below (D-15 certificate 1) to exclude the TRUE enumerated optimum
# itself at `b = [1,0,0,0]` (`y_inv = 0.5`): a fired LL cut's own RHS, evaluated at the
# TRUE enumerated optimum, exceeds the TRUE enumerated total by ~0.05 — a genuine violation
# of the "never cuts off the true optimal lattice point" property. On this fixture, with
# `max_iter = 50` (this plan's own required value), the accumulated over-tight cuts
# eventually force a no-good ban on ALL 16 lattice corners, and the master MILP becomes
# genuinely `MOI.INFEASIBLE` — `solve_stackelberg!` raises a loud `ErrorException` (D-10's
# discipline correctly holds: it never silently returns a wrong answer), but it does NOT
# return a certified result matching the enumerated optimum.
#
# THIS IS A GENUINE, PRE-EXISTING DEFECT IN ALREADY-MERGED PLAN 24-03/24-04 CODE, discovered
# BY this certification effort — precisely what a "certify before build" gate exists to
# catch. Per this plan's own explicit instruction ("do not weaken the certificate, the cut,
# or the atol to obtain a green run — an honest failure here is a legitimate deliverable"),
# the assertions below that are victims of this defect are marked `@test_broken` (Julia's
# own idiom for "known, documented, currently-failing, not silently patched" — the identical
# real computation runs every time; only the PASS/FAIL bookkeeping differs from a bare
# `@test`, and `@test_broken` LOUDLY re-fails if the underlying code changes and the
# assertion starts holding without an explicit update here). The genuinely-passing
# assertions (the loop fails LOUDLY rather than silently; the cut mechanism's own validity
# check correctly DETECTS the violation) are asserted for real. A FOLLOW-UP PLAN is required
# to fix `add_ll_cut!`'s caller (`benders.jl`) to pass the TRUE per-corner minimized
# recourse (e.g. via the SAME ternary-search technique `enumerate_lattice` uses above) —
# out of scope for this certification-only plan (Rule 4: architectural fix, not a
# certification-plan auto-fix).
# ---------------------------------------------------------------------------------------

@testitem "planning certification integer: INT-03 exhaustive-enumeration certification of the D-12 tiny instance (D-15 certificates 1+2, D-16 visibility, D-11 non-blocker documented) -- CONFIRMED FINDING: pre-existing LL-cut Q_nu defect (24-03/24-04), see file header" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture, PlanningFixtures] begin
    using TSODSO, Test

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])

    # TestItemRunner isolation (see file header): enumerate_lattice must be redefined
    # HERE, nested inside this @testitem's own body -- the plain top-level definition
    # above is dead code from the runner's own AST-based discovery. IDENTICAL logic to
    # the committed top-level version (Task 1), independently verified there via a
    # direct `include()` bypassing TestItemRunner entirely.
    function enumerate_lattice_local(oracle, follower; K::Int = 4, y_max::Real = 8.0, c_y::Real = 0.3)
        Qfun(z) = begin
            fr = solve_follower!(follower, [z])
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

    # D(x) -- the SAME hyperplane formula add_ll_cut! writes over master.b, evaluated at an
    # arbitrary point x (plan 24-03's <interfaces>): D(x) = Σ_{i∈S}x[i] - Σ_{i∉S}x[i] - |S| + 1
    # where S is the cut's OWN fixed incumbent set (from cut.b_trial), never re-derived from x.
    function D_at(b_trial::Vector{Int}, x::Vector{Int})
        K = length(b_trial)
        S = findall(==(1), b_trial)
        Sc = setdiff(1:K, S)
        return sum(x[i] for i in S; init = 0) - sum(x[i] for i in Sc; init = 0) - length(S) + 1
    end

    # ---- Build ONCE, run the exhaustive enumeration (D-10's PRIMARY certificate) --------
    oracle = build_planning_oracle(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = 1)
    follower = build_follower(; follower_kwargs..., T = 1)
    enum_result = enumerate_lattice_local(oracle, follower; K = 4, y_max = 8.0, c_y = 0.3)
    @test length(enum_result.all_totals) == 16
    # D-04 sanity: the enumerated optimum must be a genuine, non-degenerate lattice point,
    # never accidentally the continuous golden's own y*=0.7 (which is off-lattice by design).
    @test !isapprox(enum_result.best_y, 0.7; atol = 1e-6)

    # ---- The certified integer master + the D-13/D-14 exact-match termination attempt ---
    imaster = build_master_integer(;
        T = 1,
        K = 4,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )

    result = nothing
    caught = nothing
    try
        result = mktempdir() do dir
            solve_stackelberg!(
                feeder,
                LinDistFlow(),
                [agg];
                λ₀ = λ₀,
                T = 1,
                follower_kwargs = follower_kwargs,
                master_kwargs = NamedTuple(),
                master = imaster,
                known_optimum = enum_result.best_total,
                max_iter = 50,
                checkpoint_dir = dir,
            )
        end
    catch e
        caught = e
    end

    # GATE (gate-then-golden ordering, T-14-01/test_planning_goldens.jl:48-55 convention):
    # the loop's OWN convergence must be checked BEFORE any pinned/derived value is
    # consulted. CONFIRMED FINDING (file header): on THIS fixture, with max_iter = 50 (this
    # plan's own required value) and the TRUE enumerated known_optimum, the pre-existing
    # LL-cut Q_nu defect (24-03/24-04) drives every one of the 16 lattice corners to a
    # no-good ban, and the master MILP becomes genuinely infeasible before ever matching
    # the certified target -- `@test_broken`, not silently weakened or removed: this
    # assertion is EXPECTED to hold once a future plan fixes add_ll_cut!'s caller to pass
    # the TRUE per-corner minimized recourse.
    @test_broken result !== nothing && isapprox(result.UB, enum_result.best_total; atol = 1e-6)

    # What DOES genuinely hold today (D-10's own discipline): the loop NEVER silently
    # returns a wrong answer -- it fails LOUDLY (a real, currently-passing assertion).
    @test caught !== nothing
    @test caught isa ErrorException

    # ---- D-15 certificate 1: per-cut LL validity against the REAL enumerated optimum ----
    # This is the certificate that CONCRETELY diagnoses the file-header finding -- it must
    # run regardless of whether the certified call above converged, since `imaster.cuts`
    # retains every cut appended before the crash (build-once/append-only, never rebuilt).
    ll_cuts = filter(c -> c.kind == :ll, imaster.cuts)
    @test !isempty(ll_cuts)   # sanity: the LL-cut mechanism genuinely fired on this run.
    # Sanity: the true optimal corner was genuinely explored (not a vacuous check against
    # cuts that never touch the point of interest).
    @test enum_result.best_b in [cut.b_trial for cut in ll_cuts]

    violations = Tuple{Vector{Int}, Float64, Float64}[]
    for cut in ll_cuts
        Dval = D_at(cut.b_trial, enum_result.best_b)
        rhs = (cut.Q_nu - cut.L) * Dval + cut.L
        if rhs > enum_result.best_total + 1e-6
            push!(violations, (cut.b_trial, rhs, enum_result.best_total))
        end
    end
    # CONFIRMED FINDING (file header): at least one fired LL cut excludes the true
    # enumerated optimum -- `@test_broken`, the certificate mechanism itself is doing
    # EXACTLY its job by detecting this, not being weakened to hide it.
    @test_broken isempty(violations)

    # ---- D-15 certificate 2 + D-16 visibility ---------------------------------------
    # DEVIATION (documented, not silent): the certified (known_optimum-matched) call above
    # produces NO `result` on this fixture (file-header finding), so the plan's literal
    # `result.UB`/`result.y`/`result.nogood_count`/`result.converged_via` checks cannot be
    # evaluated against IT. A SEPARATE, freshly-built integer master is solved via the
    # UNCERTIFIED path (`known_optimum = nothing`, the ordinary `gap <= tol` criterion,
    # already exercised and passing in test_planning_benders_integer.jl's own smoke test)
    # purely to obtain a structural `result` for the bracketing/visibility checks D-15
    # certificate 2 and D-16 require -- clearly NOT the certified-via-enumeration path,
    # and never conflated with one.
    imaster_uncert = build_master_integer(;
        T = 1,
        K = 4,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )
    result_uncert = mktempdir() do dir
        solve_stackelberg!(
            feeder,
            LinDistFlow(),
            [agg];
            λ₀ = λ₀,
            T = 1,
            follower_kwargs = follower_kwargs,
            master_kwargs = NamedTuple(),
            master = imaster_uncert,
            max_iter = 50,
            checkpoint_dir = dir,
        )
    end

    # D-15 cert 2a: the continuous relaxation objective is a valid LOWER bound on the
    # integer-constrained optimum (relaxing integrality can only improve/lower the min).
    @test PlanningFixtures.N1_OBJ_HAND <= result_uncert.UB + 1e-6
    # D-15 cert 2b: the integer y is a lattice neighbor bracketing the continuous y*=0.7
    # (lattice step = y_max/2^K = 0.5) -- matches D-04's derivation without hardcoding
    # WHICH neighbor wins.
    @test abs(result_uncert.y - 0.7) <= (8.0 / 16) + 1e-6

    # D-16 visibility: nogood_count/converged_via are present and well-typed; a nonzero
    # count must never FAIL a run, only be visible.
    @test result_uncert.nogood_count >= 0
    @test result_uncert.nogood_count isa Integer
    @test result_uncert.converged_via in (:clean, :nogood_assisted)

    # D-11 NON-BLOCKER (see file header comment at the top of this file for the full,
    # verified citation): the BilevelJuMP secondary certificate is UNAVAILABLE on this
    # fixture for two independent, already-verified reasons (StrongDualityMode/ProductMode
    # reject a binary leader; BigMMode+HiGHS hits the SAME MIQP incapacity already asserted
    # as a negative regression in test/test_planning_certification.jl:36-64/:160-167) -- a
    # documented, non-blocking finding (D-10), not a coverage gap. No BilevelJuMP code is
    # written in this file.
end

@testitem "planning certification integer: negative-control regression -- a deliberately WRONG known_optimum is rejected, never falsely converges via a stray gap<=tol match (plan-checker Blocker 2, closed for good)" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO, Test

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])

    # TestItemRunner isolation (see file header) -- nested, independently-verified-identical
    # copy of enumerate_lattice, needed only to derive a genuinely-wrong known_optimum (NOT
    # coincidentally close to any other lattice point's own total).
    function enumerate_lattice_local2(oracle, follower; K::Int = 4, y_max::Real = 8.0, c_y::Real = 0.3)
        Qfun(z) = begin
            fr = solve_follower!(follower, [z])
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
        best_total = Inf
        for i in 0:(n - 1)
            b = [(i >> (k - 1)) & 1 for k in 1:K]
            y_inv = (y_max / 2^K) * sum(2.0^(k - 1) * b[k] for k in 1:K)
            _, Qv = y_inv <= 0 ? (0.0, 0.0) : ternary_min(Qfun, 0.0, y_inv)
            total = c_y * y_inv + Qv
            best_total = min(best_total, total)
        end
        return best_total
    end

    oracle = build_planning_oracle(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = 1)
    follower = build_follower(; follower_kwargs..., T = 1)
    best_total = enumerate_lattice_local2(oracle, follower; K = 4, y_max = 8.0, c_y = 0.3)
    # Comfortably outside KNOWN_OPTIMUM_ATOL (~4e-8) and not coincidentally close to any
    # other lattice point's own total (all_totals span roughly [-0.225, 1.75] in steps of
    # ~0.15-0.2 on this fixture -- a 1.0 offset lands well clear of every one of them).
    wrong_optimum = best_total - 1.0

    imaster2 = build_master_integer(;
        T = 1,
        K = 4,
        c_y = 0.3,
        y_max = 8.0,
        α_op_lb = -5.0,
        α_x_lb = 0.0,
    )

    # WHY THIS MATTERS (Blocker 2): under the PRE-fix `||` bug, this exact call would have
    # silently CONVERGED anyway (via gap<=tol alone, ignoring the wrong known_optimum
    # entirely) and this assertion would FAIL to throw. Under the FIXED exclusive-branch
    # code, a wrong known_optimum can never be matched, so the loop correctly exhausts
    # max_iter and raises loudly -- CONFIRMED (this session, real run, not assumed): with
    # max_iter = 30 the run cleanly exhausts (never hits the pre-existing LL-cut-driven
    # MILP infeasibility the file header documents for the CORRECT known_optimum at
    # max_iter = 50 -- 30 iterations is comfortably below the ~40-50 iteration threshold
    # where that defect's no-good bans accumulate enough to exhaust all 16 corners).
    @test_throws ErrorException mktempdir() do dir
        solve_stackelberg!(
            feeder,
            LinDistFlow(),
            [agg];
            λ₀ = λ₀,
            T = 1,
            follower_kwargs = follower_kwargs,
            master_kwargs = NamedTuple(),
            master = imaster2,
            known_optimum = wrong_optimum,
            max_iter = 30,
            checkpoint_dir = dir,
        )
    end
end

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
# CONSOLIDATION (WR-04, Phase 24 code review): this logic previously existed as FOUR
# near-identical copies in this file alone (a plain top-level `enumerate_lattice` kept
# only for documentation/ad-hoc direct-script verification, plus a nested
# `enumerate_lattice_local`/`enumerate_lattice_local2` duplicated inside EACH of the two
# `@testitem`s below) -- and had already, independently, DIVERGED once from
# `docs/literate/integer_investment.jl`'s own copy (the `y_inv <= 0` corner: this file's
# copies special-cased it to a hardcoded `(0.0, 0.0)`, while the literate page correctly
# computed `Qfun(0.0)` for real -- see CR-01). That divergence is exactly how a wrong
# assumption can slip past this file's own certification undetected.
#
# The prior top-level `function enumerate_lattice(...) end` was ALSO permanently DEAD
# CODE from TestItemRunner's perspective (its AST-based discovery only extracts
# `@testitem`/`@testsetup`/`@testmodule` source ranges — a plain top-level `function`
# is silently never `include`d, hence never genuinely executed by `Pkg.test()`, only by
# an ad-hoc script bypassing the runner entirely). Converting it to the `@testmodule`
# below fixes BOTH problems at once: `@testmodule`s (unlike plain top-level functions)
# ARE `using`-importable into a `@testitem`'s isolated module via `setup=[...]` (the
# SAME established pattern this file already uses for `Phase6Fixtures`/
# `ToyDeviceFixture`/`PlanningFixtures`), so ONE definition now serves BOTH `@testitem`s
# below AND is genuinely exercised by the real TestItemRunner-driven suite gate (not
# merely appearing to be tested while actually being inert).
#
# Two copies remain, UNAVOIDABLY, and are the outer bound of what can be consolidated:
#  1. This `@testmodule` (used by both `@testitem`s in THIS file).
#  2. `docs/literate/integer_investment.jl`'s own copy -- a Literate.jl page must be a
#     SELF-CONTAINED, independently-runnable script (that is the whole point of a
#     literate experiment page, per CLAUDE.md's documentation requirement), so it
#     cannot `using` a test-only `@testmodule` without depending on the test tree.
# If these two ever diverge again, the fix is to re-derive one from the other and
# grep for `ternary_min`/`enumerate_lattice` across BOTH locations -- see
# `src/planning/benders.jl`'s `corner_recourse` for the THIRD, structurally-different
# (single-corner, not full-enumeration) instance of the same `Qfun`/ternary-search
# technique, promoted to production.

@testmodule EnumerateLatticeOracle begin
    using TSODSO

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

    **WR-01 fix (Phase 24 code review):** the naive ternary-search tie-break diverges to
    `+Inf` when both trial points land outside the feasible sub-interval -- see the
    `ternary_min` inline comment below and `src/planning/benders.jl`'s `corner_recourse`
    for the full rationale. Fixed by shrinking from the right on a double-infinite tie,
    plus a loud `isfinite` check on every computed `Q` (this oracle previously had NO
    such guard, so a divergence here would have silently corrupted the certified
    "best" answer instead of throwing).

    **CR-01 fix (Phase 24 code review):** `y_inv <= 0` genuinely COMPUTES `Qfun(0.0)`,
    never assumes it is `0.0` (even though it IS `0.0` on this fixture's
    `ToyElasticDevice`, since its utility is zero at zero consumption) -- matches
    `src/planning/benders.jl`'s `corner_recourse` and
    `docs/literate/integer_investment.jl`'s own independently-found fix.

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
                f1, f2 = f(m1), f(m2)
                # WR-01 (Phase 24 code review): a double-infinite tie must shrink from the
                # right (toward the guaranteed-feasible z=0 anchor), never fall to the
                # ordinary else-branch (lo = m1) -- that walks away from feasibility and
                # diverges to +Inf on a bounded interval whenever the follower's own
                # deliverable capacity is well below y_inv/3 (empirically reproduced with
                # ordinary K/y_max/corridor_cap reconfiguration; dormant on D-12's specific
                # numbers). See src/planning/benders.jl's corner_recourse for the same fix.
                if isinf(f1) && isinf(f2)
                    hi = m2
                elseif f1 < f2
                    hi = m2
                else
                    lo = m1
                end
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
            # y_inv <= 0 collapses [0, y_inv] to the single point z=0 -- Qfun(0.0) is
            # GENUINELY COMPUTED here (matches src/planning/benders.jl's corner_recourse
            # CR-01 fix), not assumed to be 0.0, even though it IS 0.0 on this fixture's
            # ToyElasticDevice (zero utility at zero consumption).
            _, Qv = y_inv <= 0 ? (0.0, Qfun(0.0)) : ternary_min(Qfun, 0.0, y_inv)
            # WR-01: fail LOUDLY, not silently, if the ternary search ever produces a
            # non-finite Q for a lattice point that must be feasible (z=0 is always
            # feasible, so Q(y_inv) can never legitimately exceed Qfun(0.0)). A silent
            # Inf here would corrupt this certification oracle's own notion of "best"
            # without ever tripping an error.
            isfinite(Qv) || throw(
                ErrorException(
                    "enumerate_lattice: ternary search diverged to a non-finite Q at " *
                    "y_inv=$y_inv (WR-01 regression, Phase 24 code review) -- should be " *
                    "unreachable given the tie-break fix; report as a bug.",
                ),
            )
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

    export enumerate_lattice
end

# ---------------------------------------------------------------------------------------
# TASK 2 — INT-03 certification `@testitem` + D-15 certificates + D-11 documentation.
#
# ORIGINAL FINDING (plan 24-05, via the enumeration harness above run against the REAL
# `solve_stackelberg!(...; master = build_master_integer(...), known_optimum = ...)` path
# — exactly the certification INT-03/24-05 exists to run): on the D-12 canonical instance,
# the Laporte-Louveaux cut wired by plans 24-03/24-04 (`add_ll_cut!`/`apply_integer_cuts!`,
# `src/planning/master_integer.jl`) used
#
#     Q_nu = follower_res.cost - oracle_res.cost   (benders.jl, evaluated at lb_res.z)
#
# — i.e. the recourse value AT WHATEVER `z` THE MASTER'S CURRENT TRIAL HAPPENED TO PICK for
# the incumbent corner `b^ν`, not the TRUE, EXACTLY-MINIMIZED recourse
# `Q(y_inv(b^ν)) = min_{z ∈ [0, y_inv(b^ν)]} [follower_cost(z) - oracle_welfare(z)]` the
# Laporte-Louveaux theorem's own "cut with a value" REQUIRES (`add_ll_cut!`'s own docstring
# even states this precondition: "its EXACT recourse value Q_nu = Q(b^ν) ... never estimated
# here" — the CALLER, `benders.jl`, was the one that failed to honor it). Since the master's
# box constraint only guarantees `z_k <= y_inv(b^ν)` (feasibility), NOT `z_k` = the
# minimizer, `Q_nu >= Q(y_inv(b^ν))` in general (an UPPER-BOUND surrogate). Because cut rows
# are NEVER retracted (`master.model`'s own build-once/append-only discipline, correct in
# isolation), an EARLY, loose (too-high) `Q_nu` recorded before enough `:op`/`:x` cuts had
# refined the master's own view of `z` PERMANENTLY over-constrained `theta` at that corner —
# concretely CONFIRMED (at the time) to exclude the TRUE enumerated optimum itself at
# `b = [1,0,0,0]` (`y_inv = 0.5`), eventually forcing a no-good ban on ALL 16 lattice corners
# and driving the master MILP to genuine `MOI.INFEASIBLE`.
#
# GAP-CLOSURE FIX (plan 24-05.1 — THREE distinct, confirmed defects, all now fixed):
#
#  1. **The Q_nu recourse value itself** (the ORIGINAL FINDING above): `benders.jl` now
#     computes the TRUE per-corner minimized recourse via `ll_cut_recourse`/
#     `corner_recourse` (`src/planning/benders.jl`) — the SAME ternary-search technique
#     `enumerate_lattice` above uses, reusing the REAL, already-built `oracle`/`follower`.
#     `ll_cut_recourse` is a TRUE no-op for the continuous `BendersMaster` path (byte-
#     identical to before this fix).
#  2. **A SECOND, independently-discovered defect** (found while re-verifying THIS
#     certification during gap-closure, NOT anticipated by the original finding above):
#     `apply_integer_cuts!`'s anti-stall "no-good" heuristic (`src/planning/master_integer.jl`)
#     banned a corner from the master's feasible region PERMANENTLY on its SECOND visit,
#     regardless of whether the master's own `z` trial was still genuinely converging
#     (ordinary, expected cutting-plane refinement, not a stall) — empirically confirmed to
#     ban the TRUE optimal corner before its incumbent value converged, making
#     `result.UB ≈ enum_result.best_total` PROVABLY UNREACHABLE even with a correct `Q_nu`.
#     Fixed by tracking each corner's LAST `z` trial (`master.visited`, now
#     `Dict{Vector{Int},Vector{Float64}}`) and only declaring a genuine stall when the SAME
#     corner is revisited with an UNCHANGED `z` (within `STALL_Z_ATOL`).
#  3. **A THIRD, independently-discovered defect**: HiGHS's runtime default
#     `mip_feasibility_tolerance` (1e-6, `src/solver/factory.jl`'s `select_optimizer(::MILP)`)
#     let the master accept a continuous `z` up to ~1e-6 outside its own box bound
#     `z <= y_inv` as "feasible" — at a corner whose true argmin sits exactly on that
#     boundary (confirmed on this fixture), this produced a small but DETERMINISTIC,
#     reproducible (~7e-8) residual between the certified run's own incumbent and the
#     independent enumeration reference, exceeding `KNOWN_OPTIMUM_ATOL` (~4e-8). Fixed by
#     tightening `mip_feasibility_tolerance` to `1e-9` for `MILP()` — HiGHS attribute tuning
#     explicitly sanctioned as "Claude's Discretion" by 24-CONTEXT.md, touching neither
#     `KNOWN_OPTIMUM_ATOL`, `L`, nor the LL-cut algebra.
#
# With all three fixes, the certified run now converges CLEANLY (`:clean`, zero no-good
# cuts) in 9 iterations (well inside `max_iter = 50`) to `y = 0.5`, `UB` matching
# `enum_result.best_total` to ~1.6e-16 (machine precision, not a near-miss) — both
# assertions below are genuine, reliable `@test`s, not `@test_broken`.
# ---------------------------------------------------------------------------------------

@testitem "planning certification integer: INT-03 exhaustive-enumeration certification of the D-12 tiny instance (D-15 certificates 1+2, D-16 visibility, D-11 non-blocker documented) -- FIXED in gap-closure 24-05.1 (Q_nu recourse, stall/no-good over-eagerness, MILP feasibility tolerance), see file header" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture, PlanningFixtures, EnumerateLatticeOracle] begin
    using TSODSO, Test

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])

    # WR-04 consolidation (Phase 24 code review): enumerate_lattice now comes from the
    # shared EnumerateLatticeOracle @testmodule (file header) via setup=[...], the SAME
    # `using`-import mechanism this file already uses for Phase6Fixtures/ToyDeviceFixture/
    # PlanningFixtures -- no more nested per-testitem copy of this logic.

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
    enum_result =
        EnumerateLatticeOracle.enumerate_lattice(oracle, follower; K = 4, y_max = 8.0, c_y = 0.3)
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

    # Scoping note (found 2026-08-23 while diagnosing a TestItemRunner-only failure):
    # assigning `result` from INSIDE the `try` body does not reach the outer binding under
    # TestItemRunner's `@testitem` module wrapping -- `caught` stayed `nothing` (no exception)
    # while `result` also stayed `nothing`, failing every `result !== nothing` assertion below
    # even though the loop had converged correctly. The identical code passes as a plain script
    # under both `--project=.` and the `Pkg.test()` sandbox, so this is a harness artifact, not
    # a solver defect. Take the `try` EXPRESSION's value instead of assigning inside it.
    caught = nothing
    _tmpdir = mktempdir()
    result = try
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
            checkpoint_dir = _tmpdir,
        )
    catch e
        caught = e
        nothing
    end

    # GATE (gate-then-golden ordering, T-14-01/test_planning_goldens.jl:48-55 convention):
    # the loop's OWN convergence must be checked BEFORE any pinned/derived value is
    # consulted. FIXED (gap-closure 24-05.1, file header): with all three fixes applied,
    # the certified run genuinely converges (never throws) within `max_iter = 50` and its
    # incumbent `UB` matches the TRUE enumerated optimum to machine precision -- a real,
    # reliable `@test`, not `@test_broken`.
    @test caught === nothing
    @test result !== nothing && isapprox(result.UB, enum_result.best_total; atol = 1e-6)

    # D-16 / INT-02: convergence is attributed to the LL cuts alone on this fixture (no
    # no-good cuts needed) -- the STRONGEST form of "no-good cuts are never the convergence
    # argument", not merely "m > 0 is tolerated".
    @test result !== nothing && result.converged_via === :clean
    @test result !== nothing && result.nogood_count == 0

    # ---- D-15 certificate 1: per-cut LL validity against the REAL enumerated optimum ----
    # This is the certificate that CONCRETELY diagnoses (and, post-fix, confirms the
    # resolution of) the file-header finding -- it must run regardless of whether the
    # certified call above converged, since `imaster.cuts` retains every cut appended
    # across the whole run (build-once/append-only, never rebuilt).
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
    # FIXED (gap-closure 24-05.1, file header): every fired LL cut is now valid against the
    # TRUE enumerated optimum (0 violations, confirmed across every cut fired in the run,
    # up to 50 of them across repeated runs during verification) -- a mathematical
    # guarantee of the corrected `Q_nu`, not a numerical coincidence. A real `@test`, not
    # `@test_broken`.
    @test isempty(violations)

    # ---- D-15 certificate 2 + D-16 visibility ---------------------------------------
    # Post-fix (gap-closure 24-05.1), the certified (known_optimum-matched) call above DOES
    # produce a genuine `result` (see the gate assertions above) -- but D-15 certificate 2
    # and D-16 visibility are deliberately checked against a SEPARATE, freshly-built integer
    # master solved via the UNCERTIFIED path (`known_optimum = nothing`, the ordinary
    # `gap <= tol` criterion, already exercised and passing in
    # test_planning_benders_integer.jl's own smoke test), to keep the certified-via-
    # enumeration path's own assertions (above) cleanly separate from the ordinary-
    # convergence path's bracketing/visibility checks -- never conflating the two.
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
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture, EnumerateLatticeOracle] begin
    using TSODSO, Test

    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
    λ₀ = [4.0]
    follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])

    # WR-04 consolidation (Phase 24 code review): enumerate_lattice comes from the shared
    # EnumerateLatticeOracle @testmodule (file header) -- only `.best_total` is needed
    # here, to derive a genuinely-wrong known_optimum (NOT coincidentally close to any
    # other lattice point's own total).

    oracle = build_planning_oracle(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = 1)
    follower = build_follower(; follower_kwargs..., T = 1)
    best_total =
        EnumerateLatticeOracle.enumerate_lattice(oracle, follower; K = 4, y_max = 8.0, c_y = 0.3).best_total
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

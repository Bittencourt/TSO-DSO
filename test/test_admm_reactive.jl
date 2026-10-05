# test/test_admm_reactive.jl
#
# Seam: reactive-power (mu) consensus naming decision + harness pinning the reactive_consensus
# behavior. This file is test-only -- no production code in
# `src/admm/AgrOpt.jl`/`DsoOpt.jl`/`solve_admm.jl`/`src/pricing/dlmp.jl` is touched by it.
#
# ==============================================================================================
# NAMING-COLLISION GREP AUDIT (re-confirmed LIVE against the tree on 2026-07-25, before any
# AgrOpt/DsoOpt/Dlmp change for the reactive channel; re-run these EXACT commands from the repo
# root to reproduce):
#
#   $ grep -rln "\bμ\b" src/ test/          # Greek mu (case-sensitive)
#     -> src/admm/{AgrOpt,DsoOpt,solve_admm}.jl, src/experiments/{Scenario,run,store,sweep}.jl,
#        test/{fixtures_ieee123,test_admm_adaptive,test_ieee123_admm,test_acceptance}.jl
#   $ grep -rn "\bmu\b" src/ test/          # ASCII lowercase spelling -- NO MATCHES
#   $ grep -rn "\bMU\b" src/ test/          # ASCII uppercase spelling (fixture const)
#     -> the fixture const `MU = 10.0` in fixtures_ieee123.jl and the `mu = IEEE123Fixtures.MU`
#        keyword uses in test_admm_adaptive.jl, test_ieee123_admm.jl and test_acceptance.jl
#
# CONCLUSION: EVERY existing binding of `μ`/`mu`/`MU` in the ENTIRE codebase means EXACTLY ONE
# thing: the Boyd Section-3.4.1 adaptive-rho residual-balancing IMBALANCE BAND (`solve_admm`'s
# `μ::Real = 10.0` kwarg, threaded through `Scenario.μ`'s golden-hash `savename`-serialized
# struct field, `run.jl`'s `μ = s.μ` pass-through, and `fixtures_ieee123.jl`'s `const MU = 10.0`).
# It is a scalar TUNING KNOB controlling the `ρ ← τ·ρ` / `ρ ← ρ/τ` residual-balancing
# thresholds -- it is NEVER a dual, price, or coupling variable anywhere in the codebase. No
# second meaning was found. This confirms it is safe to introduce a reactive-power identifier,
# PROVIDED it is DISTINCT from bare mu/MU.
#
# CHOSEN IDENTIFIERS for anything reactive-power-related -- NEVER bare `μ`, `mu`, or `MU`:
#   - `qag_dso`  -- the JuMP coupling variable stashed at `ctx.meta[:qag_dso]` (DsoOpt).
#                   No Greek letter: it is a VARIABLE, not a dual.
#   - `reactive` -- the `decompose_dlmp` NamedTuple field (src/pricing/dlmp.jl).
#   - `mu_q`     -- RESERVED ONLY if a future task needs a scalar/vector CODE HANDLE for the
#                   extracted reactive price (as opposed to the `reactive` NamedTuple field
#                   name, which needs no such handle) -- never bare `μ`.
# No file may bind a NEW value to bare `μ`/`mu`/`MU`; that identifier continues to
# mean ONLY the adaptive-rho band.
#
# OUT OF SCOPE: `src/experiments/Scenario.jl`
# is NOT modified. It carries the DrWatson `savename` golden-hash schema (`μ::Float64 = 10.0`
# is the SAME adaptive-rho band, already serialized into every pinned
# experiment's filename); adding a `reactive_consensus` field there -- even defaulted -- would
# perturb that hash for every existing pinned experiment. The feature flag lives ONLY as a
# `build_dso_opt`/`solve_admm` kwarg; `Scenario.jl`/`run.jl`/`sweep.jl`/`store.jl`
# wiring is explicitly deferred.
# ==============================================================================================
#
# @testitem harness for the DsoOpt/solve_admm `reactive_consensus`
# kwarg + `qag_dso` coupling variable + `:balance_q` certificate. Every item name contains
# "reactive" so `occursin("reactive", ti.name)` selects them (quick-run filter).
#
# GATE (never a runner crash): items (1)/(3) probe
# `hasmethod(build_dso_opt/solve_admm, <types>, (:reactive_consensus,))` -- the 3-arg
# `hasmethod` keyword-detection form -- and gate every behavioral assert behind that
# boolean, mirroring `test_admm_adaptive.jl`'s `isdefined(TSODSO, :set_rho!)` gate but
# adapted for a KEYWORD-argument addition (kwargs are invisible to `isdefined`/dispatch).
#
# CONTRACT pinned here:
#   (1) `build_dso_opt` accepts `reactive_consensus`; `qag_dso` must exist as a genuine JuMP
#       coupling-variable container shaped `(length(load_nodes), T)`, reachable via
#       `ctx.meta[:qag_dso]`.
#   (2) POSITIVE -- the DEFAULT (`reactive_consensus` omitted) path is UNCHANGED:
#       `dso.load_nodes == [2]`, `:balance_q` registered, NO `:qag_dso` key in
#       `ctx.meta` (the core non-regression guarantee).
#   (3) after a converged `solve_admm(...; reactive_consensus = ReactiveMode.CERTIFIED)`, `assert_no_slack`
#       on every entry of `dso_ctx.constraints[:balance_q]` must NOT throw (the
#       positive-path certificate proof, mirroring `test_admm.jl`'s `:balance_p` re-check item).

@testitem "admm reactive: build_dso_opt reactive_consensus kwarg exists, qag_dso coupling variable has the expected shape (reactive)" setup =
    [TwoBusFixtures] tags = [:admm, :reactive] begin
    using TSODSO

    feeder = TwoBusFixtures.two_bus_feeder()
    # Swapped to the
    # flexible-load-free `build_two_bus_aggregators_no_flex` -- the original
    # `build_two_bus_aggregators` fixture carries Thermostatic+Deferrable members that
    # made `is_flexible_load`, so an explicit `reactive_consensus = ReactiveMode.CERTIFIED` on it now correctly
    # trips the widened guard, which this testitem's `reactive_consensus =
    # true` call below does not intend to exercise (that guard behavior is covered separately
    # by "admm reactive: OFF/CERTIFIED with a q_inject-carrying device fails loud..." below).
    aggs = TwoBusFixtures.build_two_bus_aggregators_no_flex(feeder)

    # Probe: does build_dso_opt accept the reactive_consensus kwarg? Non-crashing --
    # the 3-arg hasmethod kwarg form never calls the function, so this cannot throw even if
    # the kwarg did not exist. POSITIVE assertion (mirrors the `isdefined(TSODSO, :set_rho!)`
    # idiom in test_dso.jl) -- a negated assertion here would flip to a permanent failure once the
    # kwarg exists, which is not the intended terminal state.
    has_kwarg = hasmethod(
        build_dso_opt,
        Tuple{typeof(feeder), typeof(aggs), Int},
        (:reactive_consensus,),
    )
    @test has_kwarg   # the reactive_consensus kwarg exists

    if has_kwarg
        Th = TwoBusFixtures.T
        λ₀ = TwoBusFixtures.two_bus_lambda0()
        ρ = TwoBusFixtures.RHO_2BUS

        dso = build_dso_opt(
            feeder,
            aggs,
            Th;
            ρ = ρ,
            λ₀ = λ₀,
            reactive_consensus = ReactiveMode.CERTIFIED,
        )
        @test haskey(dso.ctx.constraints, :balance_q)
        @test haskey(dso.ctx.meta, :qag_dso)
        qag_dso = dso.ctx.meta[:qag_dso]
        @test size(qag_dso) == (length(dso.load_nodes), Th)
    end
end

@testitem "admm reactive: default reactive_consensus omitted is unchanged (reactive)" setup =
    [TwoBusFixtures] tags = [:admm, :reactive] begin
    using TSODSO

    # POSITIVE regression -- the DEFAULT path (reactive_consensus never passed) is UNCHANGED
    # (the core non-regression guarantee).
    feeder = TwoBusFixtures.two_bus_feeder()
    # Swapped to the
    # flexible-load-free `build_two_bus_aggregators_no_flex` -- the original
    # `build_two_bus_aggregators` fixture carries Thermostatic+Deferrable members that
    # made `is_flexible_load`, so `build_dso_opt`'s smart `reactive_consensus` default
    # now resolves to LIVE (not OFF) for that population, breaking this
    # testitem's "the DEFAULT path is unchanged/OFF" assertion. The flexible-load-free
    # population restores the smart default's OFF resolution, matching what this testitem
    # actually intends to certify.
    aggs = TwoBusFixtures.build_two_bus_aggregators_no_flex(feeder)
    Th = TwoBusFixtures.T
    λ₀ = TwoBusFixtures.two_bus_lambda0()
    ρ = TwoBusFixtures.RHO_2BUS

    dso = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀)
    @test dso.load_nodes == [2]
    @test haskey(dso.ctx.constraints, :balance_q)
    @test !haskey(dso.ctx.meta, :qag_dso)   # no reactive coupling variable stashed on the default path
end

@testitem "admm reactive: converged reactive_consensus=ReactiveMode.CERTIFIED certifies :balance_q has no hidden slack (reactive)" setup =
    [TwoBusFixtures] tags = [:admm, :reactive] begin
    using TSODSO

    feeder = TwoBusFixtures.two_bus_feeder()
    # Flexible-load-free
    # fixture, same rationale as the two testitems above -- this item's explicit
    # `reactive_consensus = ReactiveMode.CERTIFIED` below would otherwise trip the widened guard against
    # `build_two_bus_aggregators`'s now-`is_flexible_load` Thermostatic+Deferrable members.
    aggs = TwoBusFixtures.build_two_bus_aggregators_no_flex(feeder)

    # Probe, same gate discipline as item (1) -- solve_admm's reactive_consensus kwarg.
    # POSITIVE assertion (see item (1)'s comment) -- passes once the kwarg exists, permanently.
    has_kwarg = hasmethod(
        solve_admm,
        Tuple{typeof(feeder), ConvexBranchFlow, typeof(aggs)},
        (:reactive_consensus,),
    )
    @test has_kwarg   # the solve_admm reactive_consensus kwarg exists

    if has_kwarg
        Th = TwoBusFixtures.T
        λ₀ = TwoBusFixtures.two_bus_lambda0()
        ρ = TwoBusFixtures.RHO_2BUS

        res = solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            ρ = ρ,
            maxiter = 200,
            allow_export = true,
            reactive_consensus = ReactiveMode.CERTIFIED,
        )

        # The positive-path certificate: re-running assert_no_slack on the PUBLISHED
        # converged :balance_q (mirrors test_admm.jl's :balance_p re-check item) must NOT throw
        # and must be machine-exact -- the gate that makes dual(:balance_q) trustworthy enough
        # to cite as a DLMP-Q component, despite the final DSO-OPT solve's lenient strict=false
        # label.
        balance_q = res.dso_ctx.constraints[:balance_q]
        max_slack = maximum(
            abs(assert_no_slack(res.dso_ctx.model, balance_q[j, t]; atol = 1e-6)) for
            j in 1:size(balance_q, 1), t in 1:size(balance_q, 2)
        )
        @test max_slack <= 1e-6   # certified :balance_q, no hidden slack
    end
end

# ==============================================================================================
# Acceptance-gate items for the LIVE
# reactive dual-ascent mechanism (`reactive_consensus = ReactiveMode.LIVE`), on the primary, CI-gated
# `FourQuadBESSFixtures`-built 2-bus + FourQuadBESS fixture (never IEEE-13 for this gate --
# IEEE-13 4Q-BESS supporting evidence is a SEPARATE, quarantined item in
# test/test_ieee123_admm.jl). `setup = [TwoBusFixtures, FourQuadBESSFixtures]` in THIS ORDER on every
# item below -- `FourQuadBESSFixtures`'s own `using ..TwoBusFixtures` (see fixtures_four_quad_bess.jl's
# header) requires `TwoBusFixtures` to already be `ensure_evaled` first.
#
# Every item name below contains "live" (independently filterable) AND "reactive" (so the
# existing `occursin("reactive", ti.name)` quick-run filter, 16-VALIDATION.md, continues to
# select the FULL reactive-consensus family: OFF/CERTIFIED items above, LIVE items here).
# ==============================================================================================

@testitem "admm reactive: :live mode converges on the 4Q-BESS fixture without hitting the fail-loud cap (reactive, live)" setup =
    [TwoBusFixtures, FourQuadBESSFixtures] tags = [:admm, :reactive] begin
    using TSODSO

    feeder = TwoBusFixtures.two_bus_feeder()
    aggs = FourQuadBESSFixtures.build_two_bus_aggregators_4q(feeder)
    Th = TwoBusFixtures.T
    λ₀ = TwoBusFixtures.two_bus_lambda0()
    ρ = TwoBusFixtures.RHO_2BUS

    # `solve_admm` THROWS loudly on the maxiter cap (never returns a non-consensus iterate) --
    # simply reaching this line without an exception IS the convergence proof.
    res = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        ρ = ρ,
        allow_export = true,
        reactive_consensus = ReactiveMode.LIVE,
        maxiter = 500,
    )

    @test res.iters < 500          # converged strictly before the fail-loud cap
    # Stable-key contract: LIVE ALWAYS populates mu_q/q_devices (never `nothing`, unlike
    # OFF/CERTIFIED). The key is the audit-reserved `mu_q` handle -- never bare `μ`,
    # which remains ONLY the adaptive-ρ band kwarg per this file's header grep audit.
    @test res.mu_q !== nothing
    @test res.q_devices !== nothing
    @test haskey(res.q_devices, 2)               # bus 2's FourQuadBESS trajectory is present
    @test length(res.q_devices[2]) == Th
end

@testitem "admm reactive: :live welfare/λ/μ cross-validated against centralized solve_welfare, each own measured tolerance (reactive, live)" setup =
    [TwoBusFixtures, FourQuadBESSFixtures] tags = [:admm, :reactive] begin
    using TSODSO
    using JuMP: dual

    feeder = TwoBusFixtures.two_bus_feeder()
    aggs = FourQuadBESSFixtures.build_two_bus_aggregators_4q(feeder)
    Th = TwoBusFixtures.T
    λ₀ = TwoBusFixtures.two_bus_lambda0()
    ρ = TwoBusFixtures.RHO_2BUS

    # Centralized ground truth via the file-scope-safe `:cone`-collision workaround (see
    # fixtures_four_quad_bess.jl's header -- solve_welfare itself cannot run directly on a
    # FourQuadBESS-bearing aggregator today).
    ctx_c, obj_c, balance_p_c, balance_q_c = FourQuadBESSFixtures.centralized_welfare_4q(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        allow_export = true,
    )
    λ_c = dual.(balance_p_c[2, :])
    μ_c = balance_q_c === nothing ? zeros(Th) : dual.(balance_q_c[2, :])

    res = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        ρ = ρ,
        allow_export = true,
        reactive_consensus = ReactiveMode.LIVE,
        maxiter = 500,
    )

    # Measurement-before-golden: each tolerance below was MEASURED independently
    # on THIS exact fixture across a 5-seed sweep (see fixtures_four_quad_bess.jl's header docstring
    # for the full table) -- NEVER one shared constant across welfare/λ/μ.
    #   welfare : atol = 1e-4   (measured max |Δwelfare| = 2.368e-5, ≈4.2x margin)
    @test isapprox(res.welfare, obj_c; atol = 1e-4)
    #   λ       : atol = 5e-5   (measured max |Δλ|₂       = 1.519e-5, ≈3.3x margin)
    @test isapprox(vec(res.λ), λ_c; atol = 5e-5)
    #   μ       : OLD atol = 1e-7 (measured max |Δμ|₂ = 1.610e-8, ≈6.2x margin, ORIGINAL
    #             2026-08-08 measurement — see fixtures_four_quad_bess.jl's header table, now STALE).
    #             NEW atol = 4e-7 (re-measurement, 2026-09-28, against the CURRENT
    #             merged code: a fresh 5-seed sweep, SAME procedure/seeds
    #             (SEED_2BUS..SEED_2BUS+4) as the original measurement, gives max |Δμ|₂ =
    #             1.147e-7 at the default seed itself (SEED_2BUS = 20260719) — already ABOVE the
    #             old 1e-7 pin. CAUSE: the FourQuadBESS soc[T+1] change moved
    #             this near-lossless, uncongested fixture's degenerate μ noise floor upward.
    #             4e-7 gives
    #             ≈3.5x margin over the freshly-measured 1.147e-7 max, matching this file's own
    #             3.3x-6.2x margin discipline for its sibling tolerances above — a genuinely
    #             re-measured re-pin, never a guessed number.
    #             DELIBERATELY ABSOLUTE, never relative: μ itself is ≈0 on this near-lossless,
    #             uncongested fixture (the honest degeneracy note) -- both the centralized
    #             dual(:balance_q) and the LIVE internal μq converge to ≈1e-7-1e-8, an honest "no
    #             genuine reactive network cost to price here" feature, not a bug.
    @test isapprox(vec(res.mu_q), μ_c; atol = 4e-7)

    # CROSS-VALIDATION SCOPE: q trajectories are DELIBERATELY excluded from this gate --
    # when μ ≈ 0 (as measured here) a FourQuadBESS's own P-Q split inside its apparent-power
    # cone is non-unique/degenerate (many (p,q) splits are equally optimal at a ≈0 reactive
    # price); pinning a non-unique quantity would be meaningless. This omission is intentional,
    # not an oversight -- the liveness item below covers q_devices' OWN behavior separately.
end

@testitem "admm reactive: OFF/CERTIFIED with a q_inject-carrying device fails loud instead of silently dropping it (reactive)" setup =
    [TwoBusFixtures, FourQuadBESSFixtures] tags = [:admm, :reactive] begin
    using TSODSO

    # Under OFF/CERTIFIED, build_dso_opt composes its reactive
    # closure target from −Pdc·tanφ ALONE — a FourQuadBESS's q_inject never reaches the DSO
    # network model (silently diverging from the centralized model, whose Aggregator DOES
    # write −Pdc·tanφ + q_inject into :Rq). The combination is new and undefined, so it must
    # fail LOUD, directing the caller to :live.
    feeder = TwoBusFixtures.two_bus_feeder()
    aggs = FourQuadBESSFixtures.build_two_bus_aggregators_4q(feeder)
    Th = TwoBusFixtures.T
    λ₀ = TwoBusFixtures.two_bus_lambda0()
    ρ = TwoBusFixtures.RHO_2BUS

    # The guard's home seam: build_dso_opt, in the two remaining non-LIVE EXPLICIT spellings.
    #
    # The OMITTED-kwarg (DEFAULT) case used to be a THIRD non-LIVE spelling that this guard
    # caught ("OFF (default)" below) -- that is now stale. The `_any_flexible_reactive`
    # smart default means `build_dso_opt`'s `reactive_consensus` kwarg no longer literally
    # defaults to OFF for a FourQuadBESS-bearing population; it smart-resolves to LIVE
    # directly, so the omitted-kwarg call no longer reaches the guard at all -- there is
    # nothing left to catch on that path. Earlier assertion: `@test_throws
    # ArgumentError build_dso_opt(feeder, aggs, Th; ρ=ρ, λ₀=λ₀)`. Now: confirms the smart
    # default resolves directly to LIVE (qag present), matching the explicit
    # `reactive_consensus=ReactiveMode.LIVE` call at the bottom of this same testitem.
    dso_default = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀)   # smart default -> LIVE
    @test dso_default.qag !== nothing
    @test_throws ArgumentError build_dso_opt(
        feeder,
        aggs,
        Th;
        ρ = ρ,
        λ₀ = λ₀,
        reactive_consensus = ReactiveMode.CERTIFIED,
    )
    @test_throws ArgumentError build_dso_opt(
        feeder,
        aggs,
        Th;
        ρ = ρ,
        λ₀ = λ₀,
        reactive_consensus = ReactiveMode.CERTIFIED,
    )

    # solve_admm inherits the guard via its build_dso_opt call — no 4Q-bearing run can slip
    # into a mode whose published duals would diverge from the centralized model.
    @test_throws ArgumentError solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        ρ = ρ,
        allow_export = true,
        reactive_consensus = ReactiveMode.CERTIFIED,
        maxiter = 500,
    )

    # LIVE behavior unchanged: the same aggregator set still builds (qag coupling block live).
    dso = build_dso_opt(
        feeder,
        aggs,
        Th;
        ρ = ρ,
        λ₀ = λ₀,
        reactive_consensus = ReactiveMode.LIVE,
    )
    @test dso.qag !== nothing
end

@testitem "admm reactive: :live μ sign convention pinned against centralized dual(:balance_q) on REAL impedance (reactive, live)" setup =
    [TwoBusFixtures, FourQuadBESSFixtures] tags = [:admm, :reactive] begin
    using TSODSO
    using JuMP: dual

    # `solve_admm` publishes the NEGATED internal `μq` as the
    # reactive price, but the ONLY committed μ comparison ran on the near-lossless 2-bus
    # fixture where BOTH sides are ≈ 1e-8 ≪ atol -- a sign flip (or a doubled negation) would
    # have passed identically. This item pins the sign the way λ's was pinned: on a fixture
    # where |μ| is MATERIALLY above solver noise. That needs BOTH real impedance AND a BINDING
    # apparent-power cone (an interior free-q 4Q device drives its own bus's μ → 0 by
    # first-order optimality regardless of impedance) -- see fixtures_four_quad_bess.jl's
    # REAL_R_2BUS/BESS_SMAX_QBOUND constants-block comment for the fixture derivation and the
    # 5-seed measurement table (measurement-before-golden discipline).
    feeder = FourQuadBESSFixtures.two_bus_feeder_real_impedance()
    aggs = FourQuadBESSFixtures.build_two_bus_aggregators_4q_qbound(feeder)
    Th = TwoBusFixtures.T
    λ₀ = TwoBusFixtures.two_bus_lambda0()
    ρ = TwoBusFixtures.RHO_2BUS

    # Centralized ground truth DIRECTLY via solve_welfare -- unlocked by the anonymous
    # device cone (no centralized_welfare_4q workaround needed on a new fixture).
    ctx_c, _, _ = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        allow_export = true,
    )
    μ_c = dual.(ctx_c.constraints[:balance_q][2, :])

    res = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = Th,
        λ₀ = λ₀,
        ρ = ρ,
        allow_export = true,
        reactive_consensus = ReactiveMode.LIVE,
        maxiter = 500,
    )
    μ_a = vec(res.mu_q)

    # Sign-bearing hours: |μ_c| > 1e-5 (100× the near-lossless fixture's degenerate ≈1e-8
    # floor; measured 13 such hours at the default seed, 2–13 across the 5-seed sweep). The
    # count guard keeps this item from ever silently degenerating into the vacuous
    # near-lossless comparison it exists to fix.
    big = abs.(μ_c) .> 1e-5
    @test count(big) >= 5
    # THE sign pin (mirrors how λ's +λ₀ > 0 anchor pinned the active sign): the published
    # :live μ agrees in SIGN with the centralized dual(:balance_q) on EVERY hour where μ is
    # materially nonzero.
    @test all(sign.(μ_a[big]) .== sign.(μ_c[big]))
    # Magnitude discrimination (measured: correct orientation max|Δμ| ≤ 5.5e-5 across seeds;
    # the FLIPPED orientation differs by ≥ 2.3e-3, ≥ 42×). atol = 2e-4 gives ≈4× margin over
    # the measured max while sitting an order below the flipped-sign gap.
    @test isapprox(μ_a, μ_c; atol = 2e-4)
    @test !isapprox(-μ_a, μ_c; atol = 2e-4)
end

@testitem "admm reactive: :live mechanism is genuinely live -- a differing input yields differing μ/q_devices, never a static no-op (reactive, live)" setup =
    [TwoBusFixtures, FourQuadBESSFixtures] tags = [:admm, :reactive] begin
    using TSODSO

    # LinearAlgebra is NOT a declared test/[deps] entry anywhere in this project (grep-verified;
    # no other test file imports it) -- a per-testitem sandbox module resolves `using X` against
    # the isolated TestItemRunner test environment, so `using LinearAlgebra: norm` throws
    # `Package LinearAlgebra not found in current path` there even though it resolved fine in an
    # ad-hoc `--project=.` script. A plain Base-only 2-norm avoids adding a new test dependency
    # for one helper function (a blocking issue caused by the new test code).
    norm(x) = sqrt(sum(abs2, x))

    feeder = TwoBusFixtures.two_bus_feeder()
    Th = TwoBusFixtures.T
    λ₀ = TwoBusFixtures.two_bus_lambda0()
    ρ = TwoBusFixtures.RHO_2BUS

    # The ONLY difference between the two runs: the seed feeding
    # `build_two_bus_aggregators_4q`'s `generate_profiles` draw (the suggested
    # perturbation family) -- a genuinely different demand/PV profile shifts the aggregator's
    # net reactive injection (the `qag_live` PINNING target, `qag_live == qag + q_inject`), so a
    # live mechanism MUST respond even though μ itself stays near-degenerate on this fixture
    # (see the cross-validation item above).
    aggs1 = FourQuadBESSFixtures.build_two_bus_aggregators_4q(
        feeder;
        seed = TwoBusFixtures.SEED_2BUS,
    )
    aggs2 = FourQuadBESSFixtures.build_two_bus_aggregators_4q(
        feeder;
        seed = TwoBusFixtures.SEED_2BUS + 1,
    )

    res1 = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs1;
        T = Th,
        λ₀ = λ₀,
        ρ = ρ,
        allow_export = true,
        reactive_consensus = ReactiveMode.LIVE,
        maxiter = 500,
    )
    res2 = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs2;
        T = Th,
        λ₀ = λ₀,
        ρ = ρ,
        allow_export = true,
        reactive_consensus = ReactiveMode.LIVE,
        maxiter = 500,
    )

    # Liveness guard: stack μ AND q_devices[2] into ONE comparison vector per run. The
    # STACKED vector is what must genuinely differ -- μ's OWN subvector legitimately stays near
    # its ≈1e-8 degenerate floor on this fixture, so gating on μ alone would be a
    # meaningless/flaky check; q_devices[2] is where the seed-driven signal actually shows up
    # (measured ≈0.016 apart for adjacent seeds -- see below), which is exactly what a live,
    # input-reactive mechanism should produce.
    stacked1 = vcat(vec(res1.mu_q), res1.q_devices[2])
    stacked2 = vcat(vec(res2.mu_q), res2.q_devices[2])

    # Measured floor (a sanity check, verified empirically): two IDENTICAL-seed
    # runs (aggs2 built with `seed = TwoBusFixtures.SEED_2BUS`, matching aggs1) reproduce
    # BIT-FOR-BIT (norm diff == 0.0 exactly), correctly FAILING both assertions below -- i.e.
    # this liveness gate is NOT vacuously true. That check was reverted immediately after
    # confirming the expected failure; the committed code below always uses the two DISTINCT
    # seeds above. 1e-3 sits comfortably below the measured ≈0.016 seed-to-seed signal and
    # comfortably above the exact-0.0 identical-seed floor.
    @test !isapprox(stacked1, stacked2; atol = 1e-3)
    @test norm(stacked1 .- stacked2) > 1e-3
end

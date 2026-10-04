# test/test_admm_reactive.jl
#
# Seam: reactive-power (mu) consensus naming decision + RED harness pinning REACT-01/02/03
# (Phase 16, plan 16-01). THIS FILE IS TEST-ONLY -- no production code in
# `src/admm/AgrOpt.jl`/`DsoOpt.jl`/`solve_admm.jl`/`src/pricing/dlmp.jl` is touched by this plan.
#
# ==============================================================================================
# NAMING-COLLISION GREP AUDIT (REACT-03 Success Criterion #1 -- re-confirmed LIVE against the
# CURRENT tree this session, 2026-07-25, BEFORE any AgrOpt/DsoOpt/Dlmp diff lands in this phase;
# re-run these EXACT commands from the repo root to reproduce):
#
#   $ grep -rln "\bμ\b" src/ test/          # Greek mu (case-sensitive)
#   src/admm/AgrOpt.jl
#   src/admm/DsoOpt.jl
#   src/admm/solve_admm.jl
#   src/experiments/Scenario.jl
#   src/experiments/run.jl
#   src/experiments/store.jl
#   src/experiments/sweep.jl
#   test/fixtures_phase7.jl
#   test/test_admm_adaptive.jl
#   test/test_ieee123_admm.jl
#   test/test_acceptance.jl
#
#   $ grep -rn "\bmu\b" src/ test/          # ASCII lowercase spelling -- NO MATCHES
#   $ grep -rn "\bMU\b" src/ test/          # ASCII uppercase spelling (fixture const)
#   test/fixtures_phase7.jl:49:    const MU = 10.0   # residual-balancing imbalance band
#   test/fixtures_phase7.jl:245:        MU,
#   test/test_admm_adaptive.jl:68:      mu = Phase7Fixtures.MU,
#   test/test_ieee123_admm.jl:73:       mu = Phase7Fixtures.MU,
#   test/test_acceptance.jl:132:        mu = Phase7Fixtures.MU,
#
# CONCLUSION (re-confirmed; matches 16-RESEARCH.md's "The mu Naming Collision -- Full Grep
# Audit" section exactly -- nothing shifted since the same-day research pass): EVERY existing
# binding of `μ`/`mu`/`MU` in the ENTIRE codebase means EXACTLY ONE thing TODAY: the Boyd
# Section-3.4.1 adaptive-rho residual-balancing IMBALANCE BAND (`solve_admm`'s
# `μ::Real = 10.0` kwarg at solve_admm.jl:58,128, threaded through `Scenario.μ`'s golden-hash
# `savename`-serialized struct field at Scenario.jl:106,190,211, `run.jl:140`'s
# `μ = s.μ` pass-through, and `fixtures_phase7.jl:49`'s `const MU = 10.0`). It is a scalar
# TUNING KNOB controlling the `ρ ← τ·ρ` / `ρ ← ρ/τ` residual-balancing thresholds -- it is
# NEVER a dual, price, or coupling variable anywhere in the codebase today. No second meaning
# was found -- a clean, live grep, re-run directly against the CURRENT tree this session, not
# merely re-cited from the prior research pass. Per REACT-03, this confirms it is safe to
# introduce a reactive-power identifier now, PROVIDED it is DISTINCT from bare mu/MU.
#
# CHOSEN IDENTIFIERS for anything reactive-power-related in this phase (16-01/02/03/04) --
# NEVER bare `μ`, `mu`, or `MU`:
#   - `qag_dso`  -- the JuMP coupling variable stashed at `ctx.meta[:qag_dso]` (DsoOpt,
#                   plan 16-02). No Greek letter: it is a VARIABLE, not a dual.
#   - `reactive` -- the new `decompose_dlmp` NamedTuple field (src/pricing/dlmp.jl, plan 16-03).
#   - `mu_q`     -- RESERVED ONLY if a future task needs a scalar/vector CODE HANDLE for the
#                   extracted reactive price (as opposed to the `reactive` NamedTuple field
#                   name, which needs no such handle) -- never bare `μ`.
# No file in this phase may bind a NEW value to bare `μ`/`mu`/`MU`; that identifier continues to
# mean ONLY the adaptive-rho band, exactly as it does today.
#
# OUT OF SCOPE (this entire phase, ALL 4 plans -- 16-01/02/03/04): `src/experiments/Scenario.jl`
# is NOT modified. It carries the DrWatson `savename` golden-hash schema (`μ::Float64 = 10.0` at
# lines 106/190/211 is the SAME adaptive-rho band, already serialized into every pinned
# experiment's filename); adding a `reactive_consensus` field there -- even defaulted -- would
# perturb that hash for every existing pinned experiment. The feature flag lives ONLY as a
# `build_dso_opt`/`solve_admm` kwarg (plan 16-02); `Scenario.jl`/`run.jl`/`sweep.jl`/`store.jl`
# wiring is explicitly deferred to a future milestone, never a task in this phase.
# ==============================================================================================
#
# RED @testitem harness (Wave 0 of Phase 16). Plan 16-02 (DsoOpt/solve_admm `reactive_consensus`
# kwarg + `qag_dso` coupling variable + `:balance_q` certificate) turns items (1)/(3) GREEN by
# IMPLEMENTING the code -- these tests are NEVER edited to go green. Every item name contains
# "reactive" so `occursin("reactive", ti.name)` selects them (16-VALIDATION.md's quick-run
# filter).
#
# RED SIGNAL (never a runner crash): items (1)/(3) probe
# `hasmethod(build_dso_opt/solve_admm, <types>, (:reactive_consensus,))` -- the 3-arg
# `hasmethod` keyword-detection form (verified working this session against the CURRENT
# `build_dso_opt`/`solve_admm` signatures) -- and gate every behavioral assert behind that
# boolean, mirroring `test_admm_adaptive.jl`'s `isdefined(TSODSO, :set_rho!)` RED gate but
# adapted for a KEYWORD-argument addition (kwargs are invisible to `isdefined`/dispatch).
#
# CONTRACT pinned here:
#   (1) RED  -- `build_dso_opt` does NOT yet accept `reactive_consensus`; once it does
#       (plan 16-02), `qag_dso` must exist as a genuine JuMP coupling-variable container shaped
#       `(length(load_nodes), T)`, reachable via `ctx.meta[:qag_dso]`.
#   (2) POSITIVE, NOT RED -- the DEFAULT (`reactive_consensus` omitted) path is BYTE-IDENTICAL
#       to TODAY: `dso.load_nodes == [2]`, `:balance_q` registered, NO `:qag_dso` key in
#       `ctx.meta`. Passes NOW, before plan 16-02, and must keep passing UNCHANGED afterward
#       (REACT-03's core non-regression guarantee).
#   (3) RED  -- after a converged `solve_admm(...; reactive_consensus = true)`, `assert_no_slack`
#       on every entry of `dso_ctx.constraints[:balance_q]` must NOT throw (REACT-02's
#       positive-path certificate proof, mirroring `test_admm.jl`'s `:balance_p` re-check item).

@testitem "admm reactive: build_dso_opt reactive_consensus kwarg absent today, qag_dso coupling variable pinned once landed (reactive)" setup =
    [Phase6Fixtures] tags = [:admm, :reactive] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    # Phase 26 gap-closure (Plan 26-08, downstream of PM-03/Plan 26-12): swapped to the
    # flexible-load-free `build_two_bus_aggregators_no_flex` -- the original
    # `build_two_bus_aggregators` fixture carries Thermostatic+Deferrable members that FIX-05
    # made `is_flexible_load`, so an explicit `reactive_consensus = true` on it now correctly
    # trips the widened WR-04 guard (Plan 26-12), which this testitem's `reactive_consensus =
    # true` call below does not intend to exercise (that guard behavior is covered separately
    # by "admm reactive: OFF/CERTIFIED with a q_inject-carrying device fails loud..." below).
    aggs = Phase6Fixtures.build_two_bus_aggregators_no_flex(feeder)

    # RED probe: does build_dso_opt accept the reactive_consensus kwarg yet? Non-crashing --
    # the 3-arg hasmethod kwarg form never calls the function, so this cannot throw even though
    # the kwarg does not exist. POSITIVE assertion (mirrors the `isdefined(TSODSO, :set_rho!)`
    # idiom in test_dso.jl) -- RED (fails) before plan 16-02 lands the kwarg, GREEN (passes)
    # permanently afterward; a negated assertion here would flip to a permanent failure once the
    # kwarg exists, which is not the intended terminal state (Rule 1 bugfix, plan 16-02).
    has_kwarg =
        hasmethod(build_dso_opt, Tuple{typeof(feeder), typeof(aggs), Int}, (:reactive_consensus,))
    @test has_kwarg   # RED until plan 16-02 lands the kwarg; GREEN and permanent afterward

    if has_kwarg
        Th = Phase6Fixtures.T
        λ₀ = Phase6Fixtures.two_bus_lambda0()
        ρ = Phase6Fixtures.RHO_2BUS

        dso = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀, reactive_consensus = true)
        @test haskey(dso.ctx.constraints, :balance_q)
        @test haskey(dso.ctx.meta, :qag_dso)
        qag_dso = dso.ctx.meta[:qag_dso]
        @test size(qag_dso) == (length(dso.load_nodes), Th)
    end
end

@testitem "admm reactive: default reactive_consensus omitted is byte-identical to today (reactive)" setup =
    [Phase6Fixtures] tags = [:admm, :reactive] begin
    using TSODSO

    # POSITIVE regression -- passes NOW (no RED gate) and MUST stay green after plan 16-02/16-03
    # land: the DEFAULT path (reactive_consensus never passed) is UNCHANGED (REACT-03's core
    # non-regression guarantee, re-checked at every future plan's commit).
    feeder = Phase6Fixtures.two_bus_feeder()
    # Phase 26 gap-closure (Plan 26-08, downstream of PM-03/Plan 26-12): swapped to the
    # flexible-load-free `build_two_bus_aggregators_no_flex` -- the original
    # `build_two_bus_aggregators` fixture carries Thermostatic+Deferrable members that FIX-05
    # made `is_flexible_load`, so `build_dso_opt`'s smart `reactive_consensus` default
    # (Plan 26-12, PM-03) now resolves to LIVE (not OFF) for that population, breaking this
    # testitem's "the DEFAULT path is unchanged/OFF" REACT-03 assertion. The flexible-load-free
    # population restores the smart default's OFF resolution, matching what this testitem
    # actually intends to certify.
    aggs = Phase6Fixtures.build_two_bus_aggregators_no_flex(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

    dso = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀)
    @test dso.load_nodes == [2]
    @test haskey(dso.ctx.constraints, :balance_q)
    @test !haskey(dso.ctx.meta, :qag_dso)   # no reactive coupling variable stashed on the default path
end

@testitem "admm reactive: converged reactive_consensus=true certifies :balance_q has no hidden slack (reactive)" setup =
    [Phase6Fixtures] tags = [:admm, :reactive] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    # Phase 26 gap-closure (Plan 26-08, downstream of PM-03/Plan 26-12): flexible-load-free
    # fixture, same rationale as the two testitems above -- this item's explicit
    # `reactive_consensus = true` below would otherwise trip the widened WR-04 guard against
    # `build_two_bus_aggregators`'s now-`is_flexible_load` Thermostatic+Deferrable members.
    aggs = Phase6Fixtures.build_two_bus_aggregators_no_flex(feeder)

    # RED probe, same gate discipline as item (1) -- solve_admm's reactive_consensus kwarg.
    # POSITIVE assertion (see item (1)'s comment) -- RED before plan 16-02, GREEN permanently
    # afterward.
    has_kwarg = hasmethod(
        solve_admm,
        Tuple{typeof(feeder), ConvexBranchFlow, typeof(aggs)},
        (:reactive_consensus,),
    )
    @test has_kwarg   # RED until plan 16-02 lands the kwarg; GREEN and permanent afterward

    if has_kwarg
        Th = Phase6Fixtures.T
        λ₀ = Phase6Fixtures.two_bus_lambda0()
        ρ = Phase6Fixtures.RHO_2BUS

        res = solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = Th,
            λ₀ = λ₀,
            ρ = ρ,
            maxiter = 200,
            allow_export = true,
            reactive_consensus = true,
        )

        # REACT-02's positive-path certificate: re-running assert_no_slack on the PUBLISHED
        # converged :balance_q (mirrors test_admm.jl's :balance_p re-check item) must NOT throw
        # and must be machine-exact -- the gate that makes dual(:balance_q) trustworthy enough
        # to cite as a DLMP-Q component, despite the final DSO-OPT solve's lenient strict=false
        # label (16-RESEARCH.md Pitfall 1).
        balance_q = res.dso_ctx.constraints[:balance_q]
        max_slack = maximum(
            abs(assert_no_slack(res.dso_ctx.model, balance_q[j, t]; atol = 1e-6)) for
            j in 1:size(balance_q, 1), t in 1:size(balance_q, 2)
        )
        @test max_slack <= 1e-6   # REACT-02: certified :balance_q, no hidden slack
    end
end

# ==============================================================================================
# Phase 19 (MESH-04/MESH-05, plan 19-08 Task 2): the phase acceptance-gate items for the LIVE
# reactive dual-ascent mechanism (`reactive_consensus = :live`), on the primary, CI-gated
# `Phase19Fixtures`-built 2-bus + FourQuadBESS fixture (D-13: NEVER IEEE-13 for this gate --
# IEEE-13 4Q-BESS supporting evidence is a SEPARATE, quarantined item in
# test/test_ieee123_admm.jl). `setup = [Phase6Fixtures, Phase19Fixtures]` in THIS ORDER on every
# item below -- `Phase19Fixtures`'s own `using ..Phase6Fixtures` (see fixtures_phase19.jl's
# header) requires `Phase6Fixtures` to already be `ensure_evaled` first.
#
# Every item name below contains "live" (independently filterable) AND "reactive" (so the
# existing `occursin("reactive", ti.name)` quick-run filter, 16-VALIDATION.md, continues to
# select the FULL reactive-consensus family: OFF/CERTIFIED items above, LIVE items here).
# ==============================================================================================

@testitem "admm reactive: :live mode converges on the 4Q-BESS fixture without hitting the fail-loud cap (reactive, live)" setup =
    [Phase6Fixtures, Phase19Fixtures] tags = [:admm, :reactive] begin
    using TSODSO

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase19Fixtures.build_two_bus_aggregators_4q(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

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
        reactive_consensus = :live,
        maxiter = 500,
    )

    @test res.iters < 500          # converged strictly before the fail-loud cap
    # D-11 stable-key contract: LIVE ALWAYS populates mu_q/q_devices (never `nothing`, unlike
    # OFF/CERTIFIED). The key is the audit-reserved `mu_q` handle (WR-03) -- never bare `μ`,
    # which remains ONLY the adaptive-ρ band kwarg per this file's header grep audit.
    @test res.mu_q !== nothing
    @test res.q_devices !== nothing
    @test haskey(res.q_devices, 2)               # bus 2's FourQuadBESS trajectory is present
    @test length(res.q_devices[2]) == Th
end

@testitem "admm reactive: :live welfare/λ/μ cross-validated against centralized solve_welfare, each own measured tolerance (reactive, live)" setup =
    [Phase6Fixtures, Phase19Fixtures] tags = [:admm, :reactive] begin
    using TSODSO
    using JuMP: dual

    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase19Fixtures.build_two_bus_aggregators_4q(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

    # Centralized ground truth via the file-scope-safe `:cone`-collision workaround (see
    # fixtures_phase19.jl's header -- solve_welfare itself cannot run directly on a
    # FourQuadBESS-bearing aggregator today).
    ctx_c, obj_c, balance_p_c, balance_q_c = Phase19Fixtures.centralized_welfare_4q(
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
        reactive_consensus = :live,
        maxiter = 500,
    )

    # D-14 measurement-before-golden (T-19-18): each tolerance below was MEASURED independently
    # on THIS exact fixture across a 5-seed sweep (see fixtures_phase19.jl's header docstring
    # for the full table) -- NEVER one shared constant across welfare/λ/μ.
    #   welfare : atol = 1e-4   (measured max |Δwelfare| = 2.368e-5, ≈4.2x margin)
    @test isapprox(res.welfare, obj_c; atol = 1e-4)
    #   λ       : atol = 5e-5   (measured max |Δλ|₂       = 1.519e-5, ≈3.3x margin)
    @test isapprox(vec(res.λ), λ_c; atol = 5e-5)
    #   μ       : OLD atol = 1e-7 (measured max |Δμ|₂ = 1.610e-8, ≈6.2x margin, ORIGINAL
    #             2026-08-08 measurement — see fixtures_phase19.jl's header table, now STALE).
    #             NEW atol = 4e-7 (PM-05/26-16 re-measurement, 2026-09-28, against the CURRENT
    #             merged code through Plan 26-12: a fresh 5-seed sweep, SAME procedure/seeds
    #             (SEED_2BUS..SEED_2BUS+4) as the original D-14 measurement, gives max |Δμ|₂ =
    #             1.147e-7 at the default seed itself (SEED_2BUS = 20260719) — already ABOVE the
    #             old 1e-7 pin. CAUSE: Plan 26-03's FIX-04 FourQuadBESS soc[T+1] change moved
    #             this near-lossless, uncongested fixture's degenerate μ noise floor upward, per
    #             26-POSTMERGE-TRIAGE.md cluster E / test_admm_reactive.jl:286 row. 4e-7 gives
    #             ≈3.5x margin over the freshly-measured 1.147e-7 max, matching this file's own
    #             3.3x-6.2x margin discipline for its sibling tolerances above — a genuinely
    #             re-measured re-pin, never a guessed number.
    #             DELIBERATELY ABSOLUTE, never relative: μ itself is ≈0 on this near-lossless,
    #             uncongested fixture (D-03's honest degeneracy note) -- both the centralized
    #             dual(:balance_q) and the LIVE internal μq converge to ≈1e-7-1e-8, an honest "no
    #             genuine reactive network cost to price here" feature, not a bug.
    @test isapprox(vec(res.mu_q), μ_c; atol = 4e-7)

    # D-03 CROSS-VALIDATION SCOPE: q trajectories are DELIBERATELY excluded from this gate --
    # when μ ≈ 0 (as measured here) a FourQuadBESS's own P-Q split inside its apparent-power
    # cone is non-unique/degenerate (many (p,q) splits are equally optimal at a ≈0 reactive
    # price); pinning a non-unique quantity would be meaningless. This omission is intentional,
    # not an oversight -- the liveness item below covers q_devices' OWN behavior separately.
end

@testitem "admm reactive: OFF/CERTIFIED with a q_inject-carrying device fails loud instead of silently dropping it (WR-04) (reactive)" setup =
    [Phase6Fixtures, Phase19Fixtures] tags = [:admm, :reactive] begin
    using TSODSO

    # WR-04 (phase-19 code review): under OFF/CERTIFIED, build_dso_opt composes its reactive
    # closure target from −Pdc·tanφ ALONE — a FourQuadBESS's q_inject never reaches the DSO
    # network model (silently diverging from the centralized model, whose Aggregator DOES
    # write −Pdc·tanφ + q_inject into :Rq). The combination is new and undefined, so it must
    # fail LOUD, directing the caller to :live.
    feeder = Phase6Fixtures.two_bus_feeder()
    aggs = Phase19Fixtures.build_two_bus_aggregators_4q(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

    # The guard's home seam: build_dso_opt, in the two remaining non-LIVE EXPLICIT spellings.
    #
    # Phase 26 gap-closure (Plan 26-08, downstream of PM-03/Plan 26-12): the OMITTED-kwarg
    # (DEFAULT) case used to be a THIRD non-LIVE spelling that this WR-04 guard caught
    # ("OFF (default)" below) -- that is now STALE. Plan 26-12's `_any_flexible_reactive`
    # smart default means `build_dso_opt`'s `reactive_consensus` kwarg no longer literally
    # defaults to OFF for a FourQuadBESS-bearing population; it smart-resolves to LIVE
    # directly, so the omitted-kwarg call no longer reaches the guard at all -- there is
    # nothing left to catch on that path. OLD (pre-PM-03) assertion: `@test_throws
    # ArgumentError build_dso_opt(feeder, aggs, Th; ρ=ρ, λ₀=λ₀)`. NEW: confirms the smart
    # default resolves directly to LIVE (qag present), matching the explicit
    # `reactive_consensus=:live` call at the bottom of this same testitem.
    dso_default = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀)   # smart default (PM-03) -> LIVE
    @test dso_default.qag !== nothing
    @test_throws ArgumentError build_dso_opt(
        feeder,
        aggs,
        Th;
        ρ = ρ,
        λ₀ = λ₀,
        reactive_consensus = :certified,
    )
    @test_throws ArgumentError build_dso_opt(
        feeder,
        aggs,
        Th;
        ρ = ρ,
        λ₀ = λ₀,
        reactive_consensus = true,   # Bool back-compat → CERTIFIED
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
        reactive_consensus = :certified,
        maxiter = 500,
    )

    # LIVE behavior unchanged: the same aggregator set still builds (qag coupling block live).
    dso = build_dso_opt(feeder, aggs, Th; ρ = ρ, λ₀ = λ₀, reactive_consensus = :live)
    @test dso.qag !== nothing
end

@testitem "admm reactive: :live μ sign convention pinned against centralized dual(:balance_q) on REAL impedance (reactive, live)" setup =
    [Phase6Fixtures, Phase19Fixtures] tags = [:admm, :reactive] begin
    using TSODSO
    using JuMP: dual

    # WR-02 (phase-19 code review): `solve_admm` publishes the NEGATED internal `μq` as the
    # reactive price, but the ONLY committed μ comparison ran on the near-lossless 2-bus
    # fixture where BOTH sides are ≈ 1e-8 ≪ atol -- a sign flip (or a doubled negation) would
    # have passed identically. This item pins the sign the way λ's was pinned: on a fixture
    # where |μ| is MATERIALLY above solver noise. That needs BOTH real impedance AND a BINDING
    # apparent-power cone (an interior free-q 4Q device drives its own bus's μ → 0 by
    # first-order optimality regardless of impedance) -- see fixtures_phase19.jl's
    # REAL_R_2BUS/BESS_SMAX_QBOUND constants-block comment for the fixture derivation and the
    # 5-seed measurement table (measurement-before-golden, D-14's discipline).
    feeder = Phase19Fixtures.two_bus_feeder_real_impedance()
    aggs = Phase19Fixtures.build_two_bus_aggregators_4q_qbound(feeder)
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

    # Centralized ground truth DIRECTLY via solve_welfare -- unlocked by WR-01's anonymous
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
        reactive_consensus = :live,
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
    [Phase6Fixtures, Phase19Fixtures] tags = [:admm, :reactive] begin
    using TSODSO

    # LinearAlgebra is NOT a declared test/[deps] entry anywhere in this project (grep-verified;
    # no other test file imports it) -- a per-testitem sandbox module resolves `using X` against
    # the isolated TestItemRunner test environment, so `using LinearAlgebra: norm` throws
    # `Package LinearAlgebra not found in current path` there even though it resolved fine in an
    # ad-hoc `--project=.` script. A plain Base-only 2-norm avoids adding a new test dependency
    # for one helper function (Rule 1/3 fix — a blocking issue caused directly by this task's own
    # new test code).
    norm(x) = sqrt(sum(abs2, x))

    feeder = Phase6Fixtures.two_bus_feeder()
    Th = Phase6Fixtures.T
    λ₀ = Phase6Fixtures.two_bus_lambda0()
    ρ = Phase6Fixtures.RHO_2BUS

    # The ONLY difference between the two runs: the seed feeding
    # `build_two_bus_aggregators_4q`'s `generate_profiles` draw (CR-01's own suggested
    # perturbation family) -- a genuinely different demand/PV profile shifts the aggregator's
    # net reactive injection (the `qag_live` PINNING target, `qag_live == qag + q_inject`), so a
    # live mechanism MUST respond even though μ itself stays near-degenerate on this fixture
    # (see the cross-validation item above).
    aggs1 = Phase19Fixtures.build_two_bus_aggregators_4q(
        feeder;
        seed = Phase6Fixtures.SEED_2BUS,
    )
    aggs2 = Phase19Fixtures.build_two_bus_aggregators_4q(
        feeder;
        seed = Phase6Fixtures.SEED_2BUS + 1,
    )

    res1 = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs1;
        T = Th,
        λ₀ = λ₀,
        ρ = ρ,
        allow_export = true,
        reactive_consensus = :live,
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
        reactive_consensus = :live,
        maxiter = 500,
    )

    # T-19-19 liveness guard: stack μ AND q_devices[2] into ONE comparison vector per run. The
    # STACKED vector is what must genuinely differ -- μ's OWN subvector legitimately stays near
    # its ≈1e-8 degenerate floor on this fixture (D-03), so gating on μ alone would be a
    # meaningless/flaky check; q_devices[2] is where the seed-driven signal actually shows up
    # (measured ≈0.016 apart for adjacent seeds -- see below), which is exactly what a live,
    # input-reactive mechanism should produce.
    stacked1 = vcat(vec(res1.mu_q), res1.q_devices[2])
    stacked2 = vcat(vec(res2.mu_q), res2.q_devices[2])

    # Measured floor (this task's own sanity check, verified this session): two IDENTICAL-seed
    # runs (aggs2 built with `seed = Phase6Fixtures.SEED_2BUS`, matching aggs1) reproduce
    # BIT-FOR-BIT (norm diff == 0.0 exactly), correctly FAILING both assertions below -- i.e.
    # this liveness gate is NOT vacuously true. That check was reverted immediately after
    # confirming the expected failure; the committed code below always uses the two DISTINCT
    # seeds above. 1e-3 sits comfortably below the measured ≈0.016 seed-to-seed signal and
    # comfortably above the exact-0.0 identical-seed floor.
    @test !isapprox(stacked1, stacked2; atol = 1e-3)
    @test norm(stacked1 .- stacked2) > 1e-3
end

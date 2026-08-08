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
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)

    # RED probe: does build_dso_opt accept the reactive_consensus kwarg yet? Non-crashing --
    # the 3-arg hasmethod kwarg form never calls the function, so this cannot throw even though
    # the kwarg does not exist. POSITIVE assertion (mirrors the `isdefined(TSODSO, :set_rho!)`
    # idiom in test_dso.jl) -- RED (fails) before plan 16-02 lands the kwarg, GREEN (passes)
    # permanently afterward; a negated assertion here would flip to a permanent failure once the
    # kwarg exists, which is not the intended terminal state (Rule 1 bugfix, plan 16-02).
    has_kwarg =
        hasmethod(build_dso_opt, Tuple{Any, typeof(aggs), Int}, (:reactive_consensus,))
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
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
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
    aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)

    # RED probe, same gate discipline as item (1) -- solve_admm's reactive_consensus kwarg.
    # POSITIVE assertion (see item (1)'s comment) -- RED before plan 16-02, GREEN permanently
    # afterward.
    has_kwarg = hasmethod(
        solve_admm,
        Tuple{Any, ConvexBranchFlow, typeof(aggs)},
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
    # D-11 stable-key contract: LIVE ALWAYS populates μ/q_devices (never `nothing`, unlike
    # OFF/CERTIFIED).
    @test res.μ !== nothing
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
    #   μ       : atol = 1e-7   (measured max |Δμ|₂       = 1.610e-8, ≈6.2x margin) --
    #             DELIBERATELY ABSOLUTE, never relative: μ itself is ≈0 on this near-lossless,
    #             uncongested fixture (D-03's honest degeneracy note, confirmed empirically in
    #             Task 1's measurement -- both the centralized dual(:balance_q) and the LIVE
    #             internal μq converge to ≈1e-8, an honest "no genuine reactive network cost to
    #             price here" feature, not a bug).
    @test isapprox(vec(res.μ), μ_c; atol = 1e-7)

    # D-03 CROSS-VALIDATION SCOPE: q trajectories are DELIBERATELY excluded from this gate --
    # when μ ≈ 0 (as measured here) a FourQuadBESS's own P-Q split inside its apparent-power
    # cone is non-unique/degenerate (many (p,q) splits are equally optimal at a ≈0 reactive
    # price); pinning a non-unique quantity would be meaningless. This omission is intentional,
    # not an oversight -- the liveness item below covers q_devices' OWN behavior separately.
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
    aggs1 =
        Phase19Fixtures.build_two_bus_aggregators_4q(feeder; seed = Phase6Fixtures.SEED_2BUS)
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
    stacked1 = vcat(vec(res1.μ), res1.q_devices[2])
    stacked2 = vcat(vec(res2.μ), res2.q_devices[2])

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

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
    # the kwarg does not exist.
    has_kwarg = hasmethod(build_dso_opt, Tuple{Any, typeof(aggs), Int}, (:reactive_consensus,))
    @test !has_kwarg   # RED until plan 16-02 lands the kwarg

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
    has_kwarg =
        hasmethod(solve_admm, Tuple{Any, ConvexBranchFlow, typeof(aggs)}, (:reactive_consensus,))
    @test !has_kwarg   # RED until plan 16-02 lands the kwarg

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

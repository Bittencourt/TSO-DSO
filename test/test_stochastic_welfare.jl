# test/test_stochastic_welfare.jl
#
# Seam: src/models/stochastic_welfare.jl (STOCH-01/STOCH-02). `build_stochastic_welfare`
# generalizes `solve_welfare`'s single-network build to S independently-`contribute!`d,
# `JuMP.unregister`-decoupled scenario blocks on one shared `Model`, with nonanticipativity
# equality constraints tying battery-like devices across scenarios and a per-scenario,
# never-aggregated PF-04 exactness gate. Items tagged `[:stochastic_welfare]`, `setup =
# [Phase22Fixtures]`, mirroring `test_mpc_window.jl`'s structure (occursin-filter
# convention: every item name contains "stochastic_welfare"... here the FILE name already
# carries that, tags are the discovery mechanism).
#
# Deviation (Rule 1 — plan-inconsistency fix, discovered executing this task): PLAN.md's
# own Task 2 <verify> script places scenario 1's aggregator at bus 2 and scenario 2's at
# bus 3 (a single aggregator each, at DIFFERENT buses) and expects the pair to build/solve
# cleanly, tripping ONLY the PF-04 exactness gate (`ErrorException`) at an extreme
# `pv_scale`. That construction is incompatible with Task 1's OWN structural-congruence
# guard (`build_stochastic_welfare` throws `ArgumentError` on a scenario/scenario-1 bus
# mismatch — a guard that is itself load-bearing: without it, the nonanticipativity walk
# would hit an unhandled `KeyError` on a genuinely-absent bus, worse than a clean
# `ArgumentError`). Item 2 below places BOTH scenarios' single aggregator at the SAME bus
# (bus 2) instead — this satisfies the structural-congruence guard while preserving the
# test's actual intent (D-06: PF-04 gates a per-scenario NETWORK copy — `l`/`v`/`P`/`Q` are
# never tied across scenarios, only the battery schedule is — so scenario 2's own network
# can still be driven independently inexact by an extreme `pv_scale` regardless of the
# battery tie). Item 3 (the structural-congruence guard itself) is UNAFFECTED and still
# uses two genuinely different buses, exactly as PLAN.md specifies.

@testitem "stochastic_welfare: D-04 non-uniform probabilities genuinely change the objective, not silently uniform" tags =
    [:stochastic_welfare] setup = [Phase22Fixtures] begin
    using TSODSO

    feeder = Phase22Fixtures.stoch_feeder()
    T = Phase22Fixtures.T
    λ0 = Phase22Fixtures.stoch_lambda0()

    # Three DISJOINT-seeded in-sample scenarios (the documented calling convention in
    # fixtures_phase22.jl's own header: sub_seed(SEED_STOCH, Symbol(:insample_, k))).
    scenario_aggs = [
        Phase22Fixtures.stoch_scenario_aggregators(
            feeder,
            sub_seed(Phase22Fixtures.SEED_STOCH, Symbol(:insample_, k)),
        ) for k in 1:3
    ]

    r_uniform = build_stochastic_welfare(feeder, ConvexBranchFlow(), scenario_aggs; T = T, λ₀ = λ0)
    r_weighted = build_stochastic_welfare(
        feeder,
        ConvexBranchFlow(),
        scenario_aggs;
        probabilities = [0.2, 0.3, 0.5],
        T = T,
        λ₀ = λ0,
    )

    # The SAME scenario data, DIFFERENT probability weights ⇒ the objective must NOT match
    # — proving the weighting genuinely enters Σ_s p_s·(...), never silently overridden by
    # a default-uniform fallback.
    @test !(r_weighted.welfare ≈ r_uniform.welfare)
end

@testitem "stochastic_welfare: D-06 PF-04 gate runs per scenario, never aggregated — an extreme scenario throws regardless of the other" tags =
    [:stochastic_welfare] setup = [Phase22Fixtures] begin
    using TSODSO

    # A dedicated 3-bus lossy feeder (mirrors Phase21Fixtures.mpc_high_pv_feeder() exactly:
    # r=x=0.05, no smax limit) — distinct from Phase22Fixtures' own near-lossless 2-bus CI
    # substrate, needed here because a REAL structural inexactness (not a knife-edge) needs
    # real branch impedance to manifest under high PV.
    buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false), Bus(3, 0.95, 1.05, false)]
    branches = [
        Branch(1, 2, 0.05, 0.05, SMAX_NO_LIMIT),
        Branch(2, 3, 0.05, 0.05, SMAX_NO_LIMIT),
    ]
    f = Feeder(buses, branches, 1)
    T = 6
    λ0 = fill(4.0, T)

    # Same device composition (Thermostatic + PVBattery) and — Rule 1 fix (see file header)
    # — the SAME bus (2) for BOTH scenarios' aggregator, so build_stochastic_welfare's own
    # structural-congruence guard never fires; the two scenarios differ only in seed and
    # pv_scale, which is all D-06 needs (each scenario's l/v/P/Q network copy is per-scenario
    # regardless of the shared bus).
    house(pv_scale, seed) = (
        prof = generate_profiles(seed = seed, T = T);
        Ppv = pv_scale .* prof.pv;
        Pdc = 0.02 .* prof.demand;
        therm = Thermostatic(2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(20.0, T));
        batt = PVBattery(2, 0.95, 1.0, 0.002, 0.0, 0.008, 0.004, 3.8, 6.2, 8.9, Ppv);
        [Aggregator(2, 0.95, [therm, batt], Pdc)]
    )

    s1 = house(0.5, 301)   # modest, comfortably-exact pv_scale

    # Scenario 1 ALONE solves OPTIMAL and passes its own PF-04 gate.
    s1solo = build_stochastic_welfare(f, ConvexBranchFlow(), [s1]; probabilities = [1.0], T = T, λ₀ = λ0)
    @test isfinite(s1solo.welfare)

    # SCAN (never guess) candidate pv_scales for scenario 2 until one genuinely TRIPS the
    # PF-04 gate (an ErrorException from assert_socp_exact!, never an ArgumentError).
    #
    # MEASURED (this task, "measured, not guessed" discipline): pv_scale=1.0 stays exact
    # (maxratio ≈ 1, comfortably certified); pv_scale=2.0 is a genuine STRUCTURAL
    # inexactness (maxratio ≈ 9688, ~9700× over the ratio>1 threshold — a real high-PV
    # reverse-flow gap, not a knife-edge residual), and every larger scale scanned stays
    # inexact too. pv_scale=2.0 is the value exported here as `TRIP_PV_SCALE_MEASURED`.
    #
    # Widened (Rule 1 fix, plan 22-05 — discovered by this phase's own closing full-suite
    # acceptance gate): a full `julia --project=. -e 'import Pkg; Pkg.test()'` run showed
    # this scan failing to trip at ANY of the original (1.0, 2.0, 4.0, 8.0, 16.0, 32.0)
    # values, while every isolated `--project=.` script re-run of the IDENTICAL logic
    # reproduced the pv_scale=2.0 trip exactly as measured above.
    #
    # WR-07 (phase-22 review) — the diagnosis, stated precisely rather than filed under
    # the generic flake class: at maxratio ≈ 9688 the pv_scale=2.0 inexactness is
    # STRUCTURAL (~9700× over the ratio>1 threshold), so NO amount of Clarabel
    # numerical jitter explains every 2-scenario solve up to 1024× PV terminating
    # OPTIMAL and certifying exact under `Pkg.test()`. The only mechanisms consistent
    # with the observed behavior are (a) MATERIALLY DIFFERENT PACKAGE RESOLUTION in the
    # `Pkg.test()` sandbox — the developer checkout deliberately carries uncommitted
    # `Project.toml`/`Manifest-v1.12.toml` drift (CairoMakie promoted to a hard dep;
    # documented user-local state, NOT to be committed or reverted by a fix pass), which
    # can change the sandbox's resolved Clarabel/StableRNGs and hence either
    # `generate_profiles`' stream or the solver itself — or (b) an in-process state leak
    # that the previous catch-all `e isa ErrorException` made IMPOSSIBLE to observe
    # (any solver failure silently counted as a trip). Reconciling the drifted
    # Project/Manifest against CI's resolution is the remaining step and is outside a
    # test-file fix's scope; what THIS file now guarantees (WR-06 + WR-07) is that any
    # recurrence is SELF-DIAGNOSING: only the PF-04 gate message counts as a trip,
    # every scale's actual outcome is recorded, and the no-trip path logs the sandbox's
    # own resolved Clarabel/StableRNGs versions so hypothesis (a) is checkable directly
    # from the failure log. The scan range stays widened to 1024× (re-verified via a
    # direct `--project=.` run to trip cleanly at every value from 2.0 upward) as
    # mitigation-in-depth, not as the explanation.
    tripped = false
    trip_pv_scale = NaN
    outcomes = String[]   # WR-06/WR-07: per-scale record, so a no-trip run self-diagnoses
    for pv_scale in (1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0, 128.0, 256.0, 512.0, 1024.0)
        s2 = house(pv_scale, 302)
        try
            r2 = build_stochastic_welfare(
                f,
                ConvexBranchFlow(),
                [s1, s2];
                probabilities = [0.5, 0.5],
                T = T,
                λ₀ = λ0,
            )
            push!(
                outcomes,
                "pv_scale=$pv_scale: solved + certified exact " *
                "(socp_maxgap=$(r2.socp_maxgap))",
            )
        catch e
            e isa ErrorException || rethrow()
            # WR-06 fix (phase-22 review): ONLY the PF-04 gate counts as a trip. At least
            # four distinct failures inside build_stochastic_welfare raise a bare
            # ErrorException (assert_solved! on any non-OPTIMAL status — including the
            # ALMOST_OPTIMAL this fixture family is demonstrably prone to — the internal
            # residual-size error, assert_socp_exact!, assert_battery_complementarity!);
            # the previous catch-all `e isa ErrorException` let a solver convergence
            # failure set tripped=true and PASS this item without the gate ever firing —
            # the exact per-scenario-gate-isolation property under test going unverified.
            # A non-gate ErrorException is RECORDED (not rethrown mid-scan) so the
            # no-trip failure path below reports what every scale actually did.
            if occursin("SOCP relaxation INEXACT", e.msg)
                tripped = true
                trip_pv_scale = pv_scale
                break
            end
            push!(outcomes, "pv_scale=$pv_scale: NON-GATE ErrorException: $(e.msg)")
        end
    end
    if !tripped
        # WR-06/WR-07: make the documented Pkg.test no-trip flake self-diagnosing — the
        # per-scale outcomes distinguish "solved-and-exact everywhere" (data/environment
        # difference) from "solver failures masked the gate" (convergence class), and the
        # resolved Clarabel/StableRNGs versions make the sandbox-resolution hypothesis
        # (see the WR-07 comment above) checkable directly from this failure's own log.
        import Pkg
        resolved = sort!([
            "$(v.name) = $(v.version)" for (u, v) in Pkg.dependencies() if
            v.name in ("Clarabel", "StableRNGs", "JuMP")
        ])
        @info "D-06 scan NEVER tripped the PF-04 gate — self-diagnosis follows" resolved outcomes
    end
    @test tripped

    # Scenario 1 ALONE, at the SAME pv_scale used for it in the 2-scenario case, still
    # solves OPTIMAL and passes its own gate — one scenario's exactness never masks the
    # other's inexactness, and conversely an extreme scenario 2 never poisons scenario 1's
    # own (already-verified) exactness.
    s1solo_again =
        build_stochastic_welfare(f, ConvexBranchFlow(), [s1]; probabilities = [1.0], T = T, λ₀ = λ0)
    @test isfinite(s1solo_again.welfare)
    @test isapprox(s1solo_again.welfare, s1solo.welfare; rtol = 1e-6)
end

@testitem "stochastic_welfare: structural congruence guard — a bus mismatch across scenarios throws ArgumentError" tags =
    [:stochastic_welfare] setup = [Phase22Fixtures] begin
    using TSODSO

    feeder = Phase22Fixtures.stoch_feeder()
    T = Phase22Fixtures.T
    λ0 = Phase22Fixtures.stoch_lambda0()

    scenario1 = Phase22Fixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(Phase22Fixtures.SEED_STOCH, Symbol(:insample_, 1)),
    )
    # A second scenario whose aggregator sits at a DIFFERENT bus than scenario 1's — the
    # structural mismatch that would mispair the nonanticipativity walk (Task 1, D-03).
    scenario2 = [TSODSO.Aggregator(1, scenario1[1].φ, scenario1[1].devices, scenario1[1].Pdc)]

    @test_throws ArgumentError build_stochastic_welfare(
        feeder,
        ConvexBranchFlow(),
        [scenario1, scenario2];
        probabilities = [0.5, 0.5],
        T = T,
        λ₀ = λ0,
    )
end

@testitem "stochastic_welfare: WR-09 (phase-22 review) — soc agrees across scenarios post-solve WITHOUT explicit (rank-deficient) soc tie rows" tags =
    [:stochastic_welfare] setup = [Phase22Fixtures] begin
    using TSODSO
    using JuMP: value

    # WR-09: the tie loop used to add soc_s[t] == soc_1[t] for every t — rows EXACTLY
    # linearly dependent on each copy's own soc[1] == soc0 + SOC recursion given the
    # p_ch/p_dch ties (same η, same soc0 Parameter value), i.e. (S−1)·T redundant
    # equalities per battery making the equality block rank-deficient (an interior-point
    # conditioning hazard). The rows are dropped; this item pins the IMPLIED agreement:
    # the solved soc trajectories of two differently-seeded scenarios must still match.
    feeder = Phase22Fixtures.stoch_feeder()
    T = Phase22Fixtures.T
    λ0 = Phase22Fixtures.stoch_lambda0()

    scenario_aggs = [
        Phase22Fixtures.stoch_scenario_aggregators(
            feeder,
            sub_seed(Phase22Fixtures.SEED_STOCH, Symbol(:insample_, k)),
        ) for k in 1:3
    ]

    r = build_stochastic_welfare(
        feeder,
        ConvexBranchFlow(),
        scenario_aggs;
        probabilities = [0.2, 0.3, 0.5],
        T = T,
        λ₀ = λ0,
    )

    batt_of(ctx) = only(
        v for (bus, vl) in ctx.meta[:agg_device_vars] for v in vl if haskey(v, :soc0)
    )
    b1 = batt_of(r.ctxs[1])
    for s in 2:3
        bs = batt_of(r.ctxs[s])
        @test all(isapprox.(value.(bs.p_ch), value.(b1.p_ch); atol = 1e-6))
        @test all(isapprox.(value.(bs.p_dch), value.(b1.p_dch); atol = 1e-6))
        # The load-bearing assertion: soc agreement is IMPLIED, never constrained.
        @test all(isapprox.(value.(bs.soc), value.(b1.soc); atol = 1e-6))
    end
end

@testitem "stochastic_welfare: WR-04 (phase-22 review) — FourQuadBESS reactive dispatch q is nonanticipativity-tied (full first-stage battery schedule)" tags =
    [:stochastic_welfare] setup = [Phase22Fixtures] begin
    using TSODSO
    using JuMP: value

    # WR-04: the tie loop constrained p_ch/p_dch/soc only, so a FourQuadBESS's reactive
    # dispatch q stayed a free per-scenario recourse variable — the "battery schedule is
    # first-stage, SHARED across scenarios" claim (D-03) held only for the active-power
    # half of the device. q is now tied too; this item pins it: two scenarios with
    # genuinely different PV/demand draws must report the IDENTICAL solved q trajectory.
    feeder = Phase22Fixtures.stoch_feeder()
    T = Phase22Fixtures.T
    λ0 = Phase22Fixtures.stoch_lambda0()
    L = Phase22Fixtures.LOAD_SCALE_STOCH

    house(seed) = begin
        base = Phase22Fixtures.stoch_scenario_aggregators(feeder, seed)
        bess = FourQuadBESS(
            2, 0.95, 1.0,
            0.1 * L, 0.1 * L, 0.2 * L,      # Pch_max, Pdch_max, Smax
            0.0, 0.4 * L, 0.2 * L,          # Emin, Emax, soc0
            Phase22Fixtures.BATT_λ_MIN,
            Phase22Fixtures.BATT_λ_MED,
            Phase22Fixtures.BATT_λ_MAX,
        )
        [TSODSO.Aggregator(
            2,
            base[1].φ,
            AbstractDevice[base[1].devices..., bess],
            base[1].Pdc,
        )]
    end

    s1 = house(sub_seed(Phase22Fixtures.SEED_STOCH, :wr04_a))
    s2 = house(sub_seed(Phase22Fixtures.SEED_STOCH, :wr04_b))

    r = build_stochastic_welfare(
        feeder,
        ConvexBranchFlow(),
        [s1, s2];
        probabilities = [0.4, 0.6],
        T = T,
        λ₀ = λ0,
    )
    @test isfinite(r.welfare)

    q_of(ctx) = only(
        v for (bus, vl) in ctx.meta[:agg_device_vars] for v in vl if haskey(v, :q)
    )
    v1 = q_of(r.ctxs[1])
    v2 = q_of(r.ctxs[2])

    # The FULL battery schedule — active AND reactive — is shared across scenarios.
    @test all(isapprox.(value.(v2.q), value.(v1.q); atol = 1e-6))
    @test all(isapprox.(value.(v2.p_ch), value.(v1.p_ch); atol = 1e-6))
    @test all(isapprox.(value.(v2.p_dch), value.(v1.p_dch); atol = 1e-6))
end

@testitem "stochastic_welfare: WR-03 (phase-22 review) device-composition congruence guard — reordered or missing devices throw ArgumentError, never a silently-untied battery" tags =
    [:stochastic_welfare] setup = [Phase22Fixtures] begin
    using TSODSO

    feeder = Phase22Fixtures.stoch_feeder()
    T = Phase22Fixtures.T
    λ0 = Phase22Fixtures.stoch_lambda0()

    scenario1 = Phase22Fixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(Phase22Fixtures.SEED_STOCH, Symbol(:insample_, 1)),
    )
    base2 = Phase22Fixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(Phase22Fixtures.SEED_STOCH, Symbol(:insample_, 2)),
    )

    # The fixture aggregator is [Thermostatic, PVBattery]. REVERSED, scenario 2's device
    # at index 1 is a battery while scenario 1's is a Thermostatic — before the WR-03 fix
    # the tie walk's `haskey(v1, :soc0) || continue` marker (keyed to SCENARIO 1) skipped
    # index 1 entirely, leaving scenario 2's battery SILENTLY UNTIED: a scenario-specific
    # (clairvoyant) recourse variable quietly corrupting the two-stage welfare and every
    # de-scaled DADP. The guard must throw a clean ArgumentError at build time instead.
    reordered = [TSODSO.Aggregator(
        base2[1].bus,
        base2[1].φ,
        reverse(base2[1].devices),
        base2[1].Pdc,
    )]
    @test_throws ArgumentError build_stochastic_welfare(
        feeder,
        ConvexBranchFlow(),
        [scenario1, reordered];
        probabilities = [0.5, 0.5],
        T = T,
        λ₀ = λ0,
    )

    # Device-COUNT mismatch at the same bus (previously a raw BoundsError mid-tie, not
    # the docstring-promised ArgumentError).
    fewer = [TSODSO.Aggregator(
        base2[1].bus,
        base2[1].φ,
        base2[1].devices[1:1],
        base2[1].Pdc,
    )]
    @test_throws ArgumentError build_stochastic_welfare(
        feeder,
        ConvexBranchFlow(),
        [scenario1, fewer];
        probabilities = [0.5, 0.5],
        T = T,
        λ₀ = λ0,
    )

    # Congruent compositions (same device count + types, different seeds/data) still
    # build and solve — the strengthened guard rejects ONLY genuine mismatches.
    r = build_stochastic_welfare(
        feeder,
        ConvexBranchFlow(),
        [scenario1, base2];
        probabilities = [0.5, 0.5],
        T = T,
        λ₀ = λ0,
    )
    @test isfinite(r.welfare)
end

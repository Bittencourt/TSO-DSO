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

    r_uniform =
        build_stochastic_welfare(feeder, ConvexBranchFlow(), scenario_aggs; T = T, λ₀ = λ0)
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
    branches =
        [Branch(1, 2, 0.05, 0.05, SMAX_NO_LIMIT), Branch(2, 3, 0.05, 0.05, SMAX_NO_LIMIT)]
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
    s1solo = build_stochastic_welfare(
        f,
        ConvexBranchFlow(),
        [s1];
        probabilities = [1.0],
        T = T,
        λ₀ = λ0,
    )
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
    # ROOT CAUSE (this task, superseding the retracted sandbox-resolution hypothesis
    # below the fold — see git history for the original text): the historical CI no-trip
    # failure (CI run 32791955335) was a Julia **soft-scope bug in this test file**, not a
    # solver/package-resolution flake. `tripped`, `trip_pv_scale`, and `outcomes` were
    # assigned directly inside this `@testitem` body — i.e. at module top level, making
    # them globals. The `for pv_scale in (...)` loop below is a **soft scope**: the
    # `tripped = true` / `trip_pv_scale = pv_scale` assignments inside it (and inside its
    # nested `catch`) therefore created BRAND-NEW LOCALS that died with the loop iteration
    # instead of updating the outer globals — Julia's documented soft-scope-ambiguity rule
    # for top-level code.
    #
    # CI's own log proves this exactly: a `Warning: Assignment to 'tripped' in soft scope
    # is ambiguous ...` (and the identical warning for `trip_pv_scale`) printed immediately
    # before `@test tripped` failed, on every Julia version tested. The self-diagnosis
    # `outcomes` vector showed exactly ONE entry (`"pv_scale=1.0: solved + certified
    # exact ..."`), proving the loop DID `break` on the pv_scale=2.0 trip — the gate fired
    # exactly as measured — only the flag failed to escape the loop.
    #
    # This also explains why every isolated script re-run of the identical logic
    # reproduced the trip: a plain script wraps top-level code in a function body, where
    # the same assignment is an ordinary (unambiguous) local — same code, different scope
    # class, not an environment/package-resolution difference.
    #
    # FIX: the scan's mutable state now lives inside a `let` block (a hard scope), so the
    # loop's assignments resolve unambiguously to the `let`'s own locals. See immediately
    # below.
    tripped, trip_pv_scale, outcomes =
        let tripped = false, trip_pv_scale = NaN, outcomes = String[]
            # WR-06/WR-07: per-scale record, so a no-trip run self-diagnoses
            for pv_scale in
                (1.0, 2.0, 4.0, 8.0, 16.0, 32.0, 64.0, 128.0, 256.0, 512.0, 1024.0)
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
            (tripped, trip_pv_scale, outcomes)
        end
    if !tripped
        # WR-06/WR-07: retained as a general-purpose self-diagnosis in case the gate
        # genuinely fails to trip for an unrelated reason in the future — the per-scale
        # outcomes distinguish "solved-and-exact everywhere" (data/environment
        # difference) from "solver failures masked the gate" (convergence class), and the
        # resolved solver-stack versions are logged for that future diagnosis. The
        # historical failure's real root cause was the soft-scope bug fixed above, not a
        # package-resolution difference.
        # Version introspection via Base.loaded_modules/Base.pkgversion, NOT
        # `import Pkg`: Pkg is not a declared test dependency and the `Pkg.test()`
        # sandbox restricts the load path, so `import Pkg` throws
        # "Package Pkg not found in current path" — measured live when this diagnostics
        # branch first executed under `Pkg.test()` (2026-08-10 review-fix suite run,
        # which ALSO re-confirmed the no-trip flake reproduces in the sandbox). The
        # whole block is exception-guarded: diagnostics must never ERROR the item.
        resolved = try
            sort!([
                "$(k.name) = $(Base.pkgversion(m))" for (k, m) in Base.loaded_modules if
                k.name in ("Clarabel", "StableRNGs", "JuMP", "MathOptInterface")
            ])
        catch err
            ["<version introspection unavailable: $(sprint(showerror, err))>"]
        end
        @info "D-06 scan NEVER tripped the PF-04 gate — self-diagnosis follows" resolved outcomes
    end
    @test tripped
    @test trip_pv_scale == 2.0

    # Scenario 1 ALONE, at the SAME pv_scale used for it in the 2-scenario case, still
    # solves OPTIMAL and passes its own gate — one scenario's exactness never masks the
    # other's inexactness, and conversely an extreme scenario 2 never poisons scenario 1's
    # own (already-verified) exactness.
    s1solo_again = build_stochastic_welfare(
        f,
        ConvexBranchFlow(),
        [s1];
        probabilities = [1.0],
        T = T,
        λ₀ = λ0,
    )
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
    scenario2 =
        [TSODSO.Aggregator(1, scenario1[1].φ, scenario1[1].devices, scenario1[1].Pdc)]

    @test_throws ArgumentError build_stochastic_welfare(
        feeder,
        ConvexBranchFlow(),
        [scenario1, scenario2];
        probabilities = [0.5, 0.5],
        T = T,
        λ₀ = λ0,
    )
end

@testitem "stochastic_welfare: WR-10 (phase-22 review) — D-08 S=1 anchor against solve_welfare and the D-05 de-scaling property" tags =
    [:stochastic_welfare] setup = [Phase22Fixtures] begin
    using TSODSO

    # WR-10: the phase's CENTRAL pricing math — the D-05 de-scaling
    # (dadp[s] = raw dual ./ probabilities[s], no sign flip) and the D-08 degenerate
    # anchor (S=1 with probabilities=[1.0] reproduces solve_welfare) — was 'empirically
    # verified' in comments but had NO committed regression test: moving probabilities[s]
    # inside ctx.meta[:objective], flipping a sign, or breaking the de-scaling
    # denominator would have silently corrupted every reported price while the whole
    # suite passed. Both properties are pinned here.
    feeder = Phase22Fixtures.stoch_feeder()
    T = Phase22Fixtures.T
    λ0 = Phase22Fixtures.stoch_lambda0()
    aggs = Phase22Fixtures.stoch_scenario_aggregators(
        feeder,
        sub_seed(Phase22Fixtures.SEED_STOCH, :wr10_anchor),
    )

    # --- D-08 anchor: the 1-scenario extensive form reproduces the deterministic solve.
    # (Same model shape and construction order by design; the two default optimizers
    # differ only in tol_gap — 1e-8 vs the stochastic builder's 5e-10 — so the comparison
    # is a tight ≈, not ==.)
    ctx_det, welfare_det, dadp_det =
        solve_welfare(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ0)
    r1 = build_stochastic_welfare(
        feeder,
        ConvexBranchFlow(),
        [aggs];
        probabilities = [1.0],
        T = T,
        λ₀ = λ0,
    )
    @test isapprox(r1.welfare, welfare_det; rtol = 1e-6)
    @test all(isapprox.(r1.dadp[1], dadp_det; rtol = 1e-5, atol = 1e-8))
    # With p = 1 the de-scaling denominator is inert and the expectation collapses.
    @test r1.dadp[1] == r1.expected_dadp

    # --- D-05 de-scaling property: the SAME scenario data duplicated at weights
    # [0.3, 0.7] must report (probability-INVARIANT) equal per-scenario prices — the
    # raw duals ARE p_s-scaled, and dividing by probabilities[s] removes exactly that.
    r2 = build_stochastic_welfare(
        feeder,
        ConvexBranchFlow(),
        [aggs, aggs];
        probabilities = [0.3, 0.7],
        T = T,
        λ₀ = λ0,
    )
    @test all(isapprox.(r2.dadp[1], r2.dadp[2]; rtol = 1e-5, atol = 1e-8))
    # And both agree with the deterministic anchor price for the identical data.
    @test all(isapprox.(r2.dadp[1], dadp_det; rtol = 1e-4, atol = 1e-7))
    # The expectation (D-07 derived summary) then equals the common per-scenario price.
    @test all(isapprox.(r2.expected_dadp, r2.dadp[1]; rtol = 1e-5, atol = 1e-8))
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

    batt_of(ctx) =
        only(v for (bus, vl) in ctx.meta[:agg_device_vars] for v in vl if haskey(v, :soc0))
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
            2,
            0.95,
            1.0,
            0.1 * L,
            0.1 * L,
            0.2 * L,      # Pch_max, Pdch_max, Smax
            0.0,
            0.4 * L,
            0.2 * L,          # Emin, Emax, soc0
            Phase22Fixtures.BATT_λ_MIN,
            Phase22Fixtures.BATT_λ_MED,
            Phase22Fixtures.BATT_λ_MAX,
        )
        [
            TSODSO.Aggregator(
                2,
                base[1].φ,
                AbstractDevice[base[1].devices..., bess],
                base[1].Pdc,
            ),
        ]
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

    q_of(ctx) =
        only(v for (bus, vl) in ctx.meta[:agg_device_vars] for v in vl if haskey(v, :q))
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
    reordered = [
        TSODSO.Aggregator(
            base2[1].bus,
            base2[1].φ,
            reverse(base2[1].devices),
            base2[1].Pdc,
        ),
    ]
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
    fewer =
        [TSODSO.Aggregator(base2[1].bus, base2[1].φ, base2[1].devices[1:1], base2[1].Pdc)]
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

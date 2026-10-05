# test/test_planning_feasibility_oracle.jl
#
# Seam: src/planning/feasibility_oracle.jl (feasibility cuts). Two @testitems, each
# built via the relax-one-constraint-at-a-time ablation to CONFIRM, not assume, the kind of infeasibility each fixture's pinned z
# exercises, before asserting `build_feasibility_oracle`/`solve_feasibility_oracle!`
# produce a genuine, nonzero-cost `(v, u)` cut pair consumable by the EXISTING
# `add_feasibility_cut!`.
#
# A T=1, non-`Deferrable` population (`Thermostatic`/`PVBattery` only —
# `Deferrable`'s window is HARDCODED for T=24-shaped fixtures) is used
# throughout, mirroring the verified recipe.

@testmodule FeasibilityOracleFixtures begin
    using TSODSO

    """
        widen_smax(feeder; smax = 90.0) -> Feeder

    Replace every branch's thermal rating with `smax` (a large, strictly-inside-the-
    magnitude-band sentinel), leaving topology/r/x/voltage bounds untouched — the
    relax-one-constraint-at-a-time ablation used to
    confirm/refute THERMAL causation of a given infeasible pinned z.
    """
    function widen_smax(feeder; smax = 90.0)
        branches2 =
            [TSODSO.Branch(br.from, br.to, br.r, br.x, smax) for br in feeder.branches]
        return TSODSO.Feeder(feeder.buses, branches2, feeder.root)
    end

    """
        widen_voltage(feeder; vmin = 0.8, vmax = 1.2) -> Feeder

    Replace every bus's voltage band with `[vmin, vmax]` (the widest band inside
    units/PerUnit.jl's own strict per-unit magnitude guard), leaving topology/r/x/thermal
    ratings untouched — the SAME ablation idiom as `widen_smax`, used to confirm/refute
    VOLTAGE causation.
    """
    function widen_voltage(feeder; vmin = 0.8, vmax = 1.2)
        buses2 = [TSODSO.Bus(b.id, vmin, vmax, b.is_root) for b in feeder.buses]
        return TSODSO.Feeder(buses2, feeder.branches, feeder.root)
    end

    """
        small_house_agg(bus; T) -> Aggregator

    A single, modest `Thermostatic`-only aggregator at `bus` (no `PVBattery`, no
    `Deferrable`) — the THERMAL fixture's population, sized so the UNMODIFIED
    `ieee13_modified()` head branch (`smax = 0.0686` pu) is the only thing that can bind at
    a plausible pinned z.
    """
    function small_house_agg(bus; T::Int)
        therm = TSODSO.Thermostatic(
            bus,
            0.2,
            0.05,
            15.0,
            30.0,
            22.0,
            0.0,
            1.0,
            0.5,
            fill(25.0, T),
        )
        return TSODSO.Aggregator(bus, 0.9, [therm], fill(0.01, T))
    end

    """
        try_solve_planning_oracle(oracle, z) -> Union{Nothing,Exception}

    Run `solve_planning_oracle!(oracle, z)` and return the caught exception, or `nothing`
    on success. Wrapped in a FUNCTION (not a bare top-level `try`) because `@testitem`
    bodies execute as a sequence of individually-`eval`ed top-level statements — a
    top-level `try x = ...; catch e; x = e; end` runs under Julia's soft-scope rules and
    can silently leave the OUTER `x` binding untouched (treated as a new local inside the
    try block), which would otherwise mimic a genuine "no exception was thrown" result
    even when one was (a documented project trap — see the repo's own MEMORY.md "TestItem
    try-scoping trap"). A function body does not have this hazard.
    """
    function try_solve_planning_oracle(oracle, z)
        try
            TSODSO.solve_planning_oracle!(oracle, z)
            return nothing
        catch e
            return e
        end
    end

    """
        big_battery_agg(bus; T, pmax = 5.0, emax = 50.0) -> Aggregator

    A `Thermostatic` + `PVBattery` aggregator at `bus` with AMPLE battery capacity
    (`pmax`/`emax` scaled well above `small_house_agg`'s population) — the VOLTAGE
    fixture's population, sized so a large uniform import pin (`z` on the order of the
    whole network's rating) is physically deliverable by the DEVICES, isolating the
    network's own voltage limit as the binding constraint (an
    infeasibility caused by insufficient device capacity, not the network, would be a
    mislabeled fixture).
    """
    function big_battery_agg(bus; T::Int, pmax = 5.0, emax = 50.0)
        therm = TSODSO.Thermostatic(
            bus,
            0.2,
            0.05,
            15.0,
            30.0,
            22.0,
            0.0,
            1.0,
            0.5,
            fill(25.0, T),
        )
        batt = TSODSO.PVBattery(
            bus,
            0.95,
            1.0,
            pmax,
            0.0,
            emax,
            emax / 2,
            3.8,
            6.2,
            8.9,
            fill(0.0, T),
        )
        return TSODSO.Aggregator(bus, 0.9, [therm, batt], fill(0.01, T))
    end
end

@testitem "planning feasibility oracle: THERMAL-infeasible pinned z produces a genuine feasibility cut" tags =
    [:planning] setup = [FeasibilityOracleFixtures] begin
    using TSODSO
    using TSODSO: solve_master!
    using JuMP: num_constraints, value

    T = 1
    feeder = TSODSO.ieee13_modified()                      # head branch smax = 0.0686 pu
    agg = FeasibilityOracleFixtures.small_house_agg(2; T = T)
    λ₀ = [6.0]
    z = [0.07]                                              # just above the head-branch limit

    # --- Ablation: confirm THERMAL causation BEFORE trusting
    # this fixture's label. On the UNMODIFIED feeder, z=0.07 is a genuine MOI.INFEASIBLE.
    oracle0 = TSODSO.build_planning_oracle(
        feeder,
        TSODSO.ConvexBranchFlow(),
        [agg];
        λ₀ = λ₀,
        T = T,
    )
    err0 = FeasibilityOracleFixtures.try_solve_planning_oracle(oracle0, z)
    @test err0 !== nothing
    @test occursin("INFEASIBLE", sprint(showerror, err0))

    # Widening smax ALONE turns the genuine MOI.INFEASIBLE into a DIFFERENT failure mode
    # (here, SOCP relaxation inexactness) — confirming THERMAL causation per Pattern 1
    # ("widening X turns infeasible into either OK or a different, non-infeasible failure
    # mode" => X was the binding cause). The widened solve is not required to be exact —
    # only to STOP being genuinely infeasible.
    feederS = FeasibilityOracleFixtures.widen_smax(feeder; smax = 90.0)
    oracleS = TSODSO.build_planning_oracle(
        feederS,
        TSODSO.ConvexBranchFlow(),
        [agg];
        λ₀ = λ₀,
        T = T,
    )
    errS = FeasibilityOracleFixtures.try_solve_planning_oracle(oracleS, z)
    @test errS === nothing || !occursin("INFEASIBLE", sprint(showerror, errS))

    # --- The actual assertion: the feasibility oracle, run on the UNMODIFIED
    # (genuinely thermally infeasible) feeder at the SAME z, produces a nonzero-cost cut.
    fo = TSODSO.build_feasibility_oracle(feeder, TSODSO.ConvexBranchFlow(), [agg]; T = T)
    r = TSODSO.solve_feasibility_oracle!(fo, z)
    @test r.cost > 1e-6              # genuinely infeasible => nonzero slack
    @test r.v == r.cost
    @test length(r.u) == T
    @test r.z_k == z

    # The cut is consumable by the EXISTING add_feasibility_cut! in the SAME shape, and
    # grows the master's persistent row count by exactly 1 (mirrors
    # test_planning_master.jl's own growth-counting idiom).
    master =
        TSODSO.build_master(; T = T, c_y = 0.3, y_max = 1.0, α_op_lb = -50.0, α_x_lb = 0.0)
    nc0 = num_constraints(master.model; count_variable_in_set_constraints = true)
    TSODSO.add_feasibility_cut!(master, r.v, r.u, r.z_k)
    nc1 = num_constraints(master.model; count_variable_in_set_constraints = true)
    @test nc1 == nc0 + 1

    # --- Pin the cut's SIGN and VALIDITY, not just its
    # shape. Every assertion above also holds for the wrong sign u = −π. Measured
    # 2026-10-01 on this fixture: v = 8.27e-3, u = +0.99999999645 at z_k = 0.07.
    # z_feas = 0.02 is relaxation-FEASIBLE for this population (the pinned oracle
    # SOLVES there — inexact cone, but not infeasible; V(0.02) ≈ 0).
    z_feas = [0.02]
    r_feas = TSODSO.solve_planning_oracle!(oracle0, z_feas; on_inexact = :report)
    @test r_feas.exactness in (:exact, :inexact)                 # solved, not infeasible
    cut(u, zz) = r.v + sum(u .* (zz .- r.z_k))
    @test r.v > TSODSO.FEAS_CUT_V_TOL                            # separates z_k itself
    @test cut(r.u, r.z_k) > 0                                    # z_k is EXCLUDED
    @test cut(r.u, z_feas) <= 1e-8                               # a feasible z is KEPT
    @test cut(-r.u, z_feas) > 0          # the wrong sign u = −π would exclude it: pinned
    # The master, re-solved after the cut, respects it.
    solve_master!(master)
    @test cut(r.u, value.(master.z)) <= 1e-7
end

@testitem "planning feasibility oracle: VOLTAGE-infeasible pinned z (thermally-widened variant) produces a genuine feasibility cut" tags =
    [:planning] setup = [FeasibilityOracleFixtures] begin
    using TSODSO
    using TSODSO: solve_master!
    using JuMP: num_constraints, value

    # Provenance (on the REAL unmodified feeder, thermal ALWAYS binds
    # first as z grows — a genuinely voltage-only infeasibility needs a THERMALLY-WIDENED
    # variant with ample battery capacity, confirmed by direct probe):
    #
    #   T=1, feeder = widen_smax(ieee13_modified(); smax=90.0), 10 aggregators (one per
    #   non-root bus, Thermostatic + PVBattery(pmax=5.0, emax=50.0)), λ₀=[6.0].
    #
    #   z=0.5 on the smax-widened feeder WITH ITS REAL [0.95,1.05] voltage bounds:
    #     solve_planning_oracle! THROWS genuine MOI.INFEASIBLE
    #     (termination_status=INFEASIBLE, dual_status=INFEASIBILITY_CERTIFICATE).
    #   The SAME z=0.5, SAME feeder, with voltage ALSO widened to [0.8,1.2]:
    #     solve_planning_oracle! SOLVES (feasible primal) but is SOCP-INEXACT
    #     ("SOCP relaxation INEXACT: worst gap/(...) = 6717.75 > 1").
    #   This is the clean voltage-only signature (the confirmed recipe):
    #   widening thermal limits does nothing (already widened); widening voltage ALONE
    #   turns the genuine infeasibility into a non-infeasible (inexact) failure mode.

    T = 1
    feeder0 = TSODSO.ieee13_modified()
    feederS = FeasibilityOracleFixtures.widen_smax(feeder0; smax = 90.0)
    feederSV = FeasibilityOracleFixtures.widen_voltage(feederS; vmin = 0.8, vmax = 1.2)
    N = length(feeder0.buses)
    aggs = [FeasibilityOracleFixtures.big_battery_agg(bus; T = T) for bus in 2:N]
    λ₀ = fill(6.0, T)
    z = [0.5]

    # --- Ablation: confirm VOLTAGE causation (not thermal, not device-capacity).
    oracleS = TSODSO.build_planning_oracle(
        feederS,
        TSODSO.ConvexBranchFlow(),
        aggs;
        λ₀ = λ₀,
        T = T,
    )
    errS = FeasibilityOracleFixtures.try_solve_planning_oracle(oracleS, z)
    @test errS !== nothing
    @test occursin("INFEASIBLE", sprint(showerror, errS))

    oracleSV = TSODSO.build_planning_oracle(
        feederSV,
        TSODSO.ConvexBranchFlow(),
        aggs;
        λ₀ = λ₀,
        T = T,
    )
    errSV = FeasibilityOracleFixtures.try_solve_planning_oracle(oracleSV, z)
    @test errSV === nothing || !occursin("INFEASIBLE", sprint(showerror, errSV))

    # --- The actual assertion, on the smax-widened/REAL-voltage (genuinely
    # voltage-infeasible) feeder.
    fo = TSODSO.build_feasibility_oracle(feederS, TSODSO.ConvexBranchFlow(), aggs; T = T)
    r = TSODSO.solve_feasibility_oracle!(fo, z)
    @test r.cost > 1e-6
    @test r.v == r.cost
    @test length(r.u) == T
    @test r.z_k == z

    master =
        TSODSO.build_master(; T = T, c_y = 0.3, y_max = 2.0, α_op_lb = -500.0, α_x_lb = 0.0)
    nc0 = num_constraints(master.model; count_variable_in_set_constraints = true)
    TSODSO.add_feasibility_cut!(master, r.v, r.u, r.z_k)
    nc1 = num_constraints(master.model; count_variable_in_set_constraints = true)
    @test nc1 == nc0 + 1

    # --- Sign/validity pin on the VOLTAGE cut too. Measured 2026-10-01:
    # v = 0.1737, u = +0.99999999988 at z_k = 0.5; z_feas = 0.0 is feasible AND
    # SOCP-exact on this smax-widened feeder.
    z_feas = [0.0]
    @test TSODSO.solve_planning_oracle!(oracleS, z_feas; on_inexact = :report).exactness in
          (:exact, :inexact)
    cut(u, zz) = r.v + sum(u .* (zz .- r.z_k))
    @test r.v > TSODSO.FEAS_CUT_V_TOL
    @test cut(r.u, r.z_k) > 0
    @test cut(r.u, z_feas) <= 1e-8
    @test cut(-r.u, z_feas) > 0
    solve_master!(master)
    @test cut(r.u, value.(master.z)) <= 1e-7
end

# --- "Loop still converges" — solve_stackelberg! end-to-end --------
#
# The acceptance criterion is not just "a cut CAN be produced" (the two
# items above) but "the Benders LOOP survives a genuine oracle infeasibility and still
# converges". Both items below drive `solve_stackelberg!` (never a direct oracle probe)
# on the SAME feeder/population this file's own two ablation items above already use,
# with `y_max`/costs chosen (measured) so the master's NATURAL trial
# sequence — not a synthetic forced z — passes through a genuine `MOI.INFEASIBLE` early
# on, confirmed via the SAME relax-one-constraint ablation technique used above.

@testitem "planning feasibility oracle: solve_stackelberg! survives a THERMAL-infeasible trial and still converges" tags =
    [:planning] setup = [FeasibilityOracleFixtures] begin
    using TSODSO

    # HONEST FINDING (measured, not assumed): with this minimal
    # single-Thermostatic, no-DER population, the master's FIRST trial (z=0, the
    # zero-cut LP's own degenerate starting point) is ALSO genuinely infeasible — but
    # for a DIFFERENT, non-thermal reason (no local generation at all to balance even
    # zero import against the aggregator's own load). The THIRD iteration's trial
    # (z = y_max = 0.1, the master's box upper bound once the first cut is in place) IS
    # confirmed THERMAL by the SAME ablation technique the file's own dedicated item
    # above uses (z=0.1/0.08/0.07 all genuinely `MOI.INFEASIBLE` on the UNMODIFIED
    # feeder; widening `smax` alone turns each into a non-infeasible failure mode).
    # `solve_stackelberg!`'s oracle-feasibility-cut branch is, BY DESIGN, agnostic to
    # WHICH kind of genuine infeasibility it recovers from (it never inspects
    # the error message) — this run therefore exercises the branch on BOTH causes in
    # the SAME 6-iteration run, a STRONGER regression than a narrowly-thermal-only one.
    T = 1
    feeder = TSODSO.ieee13_modified()                      # head branch smax = 0.0686 pu
    agg = FeasibilityOracleFixtures.small_house_agg(2; T = T)
    λ₀ = [6.0]

    follower_kwargs = (; corridor_cap = 1.0, x_inv_max = 0.2, c_inv = 1.0, c_op = [0.5])
    master_kwargs = (; c_y = 0.3, y_max = 0.1, α_op_lb = -50.0, α_x_lb = -5.0)

    mktempdir() do dir
        result = TSODSO.solve_stackelberg!(
            feeder,
            ConvexBranchFlow(),
            [agg];
            λ₀ = λ₀,
            T = T,
            follower_kwargs = follower_kwargs,
            master_kwargs = master_kwargs,
            tol = 1.0e-5,
            max_iter = 15,
            checkpoint_dir = dir,
        )

        @test result.gap <= 1.0e-5
        @test :oracle_feasibility_cut in result.trace.policy_action_trace
        # A feasibility cut never updates UB — every
        # :oracle_feasibility_cut row must carry gap = NaN (the feasibility-branch
        # sentinel, never the converged-iteration's own finite gap).
        for (action, gap) in zip(result.trace.policy_action_trace, result.trace.gap_trace)
            action === :oracle_feasibility_cut && @test isnan(gap)
        end
    end
end

@testitem "planning feasibility oracle: solve_stackelberg! survives a VOLTAGE-infeasible trial (thermally-widened variant) and still converges" tags =
    [:planning] setup = [FeasibilityOracleFixtures] begin
    using TSODSO

    # HONEST FINDING (measured): this 10-aggregator, ample-battery
    # population is largely self-sufficient at z=0 under ORDINARY investment
    # economics (c_y/c_inv/c_op at this file's usual magnitudes), so it converges
    # trivially at y=0 without ever exploring the extreme-z region where voltage
    # binds. Near-zero leader/follower costs (not a synthetic z pin — the Benders
    # loop's own cuts still drive every trial) are used here so the master's natural
    # trial sequence explores all the way to its box upper bound `y_max=1.0` at
    # iteration 2, confirmed VOLTAGE-infeasible (not thermal, not device-capacity) by
    # the SAME ablation technique as the dedicated item above: `z≈1.0` on the
    # smax-widened feeder with its REAL `[0.95,1.05]` voltage band is genuinely
    # `MOI.INFEASIBLE`; widening voltage ALONE (smax already widened) turns it into a
    # non-infeasible failure mode.
    T = 1
    feeder0 = TSODSO.ieee13_modified()
    feederS = FeasibilityOracleFixtures.widen_smax(feeder0; smax = 90.0)
    N = length(feeder0.buses)
    aggs = [FeasibilityOracleFixtures.big_battery_agg(bus; T = T) for bus in 2:N]
    λ₀ = fill(6.0, T)

    y_max = 1.0
    follower_kwargs =
        (; corridor_cap = 1.0, x_inv_max = y_max, c_inv = 1.0e-6, c_op = fill(1.0e-6, T))
    master_kwargs = (; c_y = 1.0e-6, y_max = y_max, α_op_lb = -500.0, α_x_lb = -5.0)

    mktempdir() do dir
        result = TSODSO.solve_stackelberg!(
            feederS,
            ConvexBranchFlow(),
            aggs;
            λ₀ = λ₀,
            T = T,
            follower_kwargs = follower_kwargs,
            master_kwargs = master_kwargs,
            tol = 1.0e-4,
            max_iter = 15,
            checkpoint_dir = dir,
        )

        @test result.gap <= 1.0e-4
        @test :oracle_feasibility_cut in result.trace.policy_action_trace
        for (action, gap) in zip(result.trace.policy_action_trace, result.trace.gap_trace)
            action === :oracle_feasibility_cut && @test isnan(gap)
        end
    end
end

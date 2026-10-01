# test/test_planning_feasibility_oracle.jl
#
# Seam: src/planning/feasibility_oracle.jl (BILEV-04a, plan 30-01). Two @testitems, each
# built via the relax-one-constraint-at-a-time ablation (30-RESEARCH.md Architecture
# Pattern 1) to CONFIRM, not assume, the kind of infeasibility each fixture's pinned z
# exercises, before asserting `build_feasibility_oracle`/`solve_feasibility_oracle!`
# produce a genuine, nonzero-cost `(v, u)` cut pair consumable by the EXISTING
# `add_feasibility_cut!`.
#
# A T=1, non-`Deferrable` population (`Thermostatic`/`PVBattery` only — 30-RESEARCH.md
# Pitfall 5: `Deferrable`'s window is HARDCODED for T=24-shaped fixtures) is used
# throughout, mirroring the verified recipe in 30-RESEARCH.md's Code Examples section.

@testmodule FeasibilityOracleFixtures begin
    using TSODSO

    """
        widen_smax(feeder; smax = 90.0) -> Feeder

    Replace every branch's thermal rating with `smax` (a large, strictly-inside-the-
    magnitude-band sentinel), leaving topology/r/x/voltage bounds untouched — the
    relax-one-constraint-at-a-time ablation (30-RESEARCH.md Architecture Pattern 1) used to
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
    network's own voltage limit as the binding constraint (30-RESEARCH.md Pitfall 1: an
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
    using JuMP: num_constraints

    T = 1
    feeder = TSODSO.ieee13_modified()                      # head branch smax = 0.0686 pu
    agg = FeasibilityOracleFixtures.small_house_agg(2; T = T)
    λ₀ = [6.0]
    z = [0.07]                                              # just above the head-branch limit

    # --- Ablation (30-RESEARCH.md Pattern 1): confirm THERMAL causation BEFORE trusting
    # this fixture's label. On the UNMODIFIED feeder, z=0.07 is a genuine MOI.INFEASIBLE.
    oracle0 = TSODSO.build_planning_oracle(feeder, TSODSO.ConvexBranchFlow(), [agg]; λ₀ = λ₀, T = T)
    err0 = FeasibilityOracleFixtures.try_solve_planning_oracle(oracle0, z)
    @test err0 !== nothing
    @test occursin("INFEASIBLE", sprint(showerror, err0))

    # Widening smax ALONE turns the genuine MOI.INFEASIBLE into a DIFFERENT failure mode
    # (here, SOCP relaxation inexactness) — confirming THERMAL causation per Pattern 1
    # ("widening X turns infeasible into either OK or a different, non-infeasible failure
    # mode" => X was the binding cause). The widened solve is not required to be exact —
    # only to STOP being genuinely infeasible.
    feederS = FeasibilityOracleFixtures.widen_smax(feeder; smax = 90.0)
    oracleS =
        TSODSO.build_planning_oracle(feederS, TSODSO.ConvexBranchFlow(), [agg]; λ₀ = λ₀, T = T)
    errS = FeasibilityOracleFixtures.try_solve_planning_oracle(oracleS, z)
    @test errS === nothing || !occursin("INFEASIBLE", sprint(showerror, errS))

    # --- The actual BILEV-04a assertion: the feasibility oracle, run on the UNMODIFIED
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
    master = TSODSO.build_master(; T = T, c_y = 0.3, y_max = 1.0, α_op_lb = -50.0, α_x_lb = 0.0)
    nc0 = num_constraints(master.model; count_variable_in_set_constraints = true)
    TSODSO.add_feasibility_cut!(master, r.v, r.u, r.z_k)
    nc1 = num_constraints(master.model; count_variable_in_set_constraints = true)
    @test nc1 == nc0 + 1
end

@testitem "planning feasibility oracle: VOLTAGE-infeasible pinned z (thermally-widened variant) produces a genuine feasibility cut" tags =
    [:planning] setup = [FeasibilityOracleFixtures] begin
    using TSODSO
    using JuMP: num_constraints

    # Provenance (30-RESEARCH.md: "on the REAL unmodified feeder, thermal ALWAYS binds
    # first as z grows" — a genuinely voltage-only infeasibility needs a THERMALLY-WIDENED
    # variant with ample battery capacity, confirmed this session by direct probe):
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
    #   This is the clean voltage-only signature (30-RESEARCH.md's own confirmed recipe):
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
    oracleS = TSODSO.build_planning_oracle(feederS, TSODSO.ConvexBranchFlow(), aggs; λ₀ = λ₀, T = T)
    errS = FeasibilityOracleFixtures.try_solve_planning_oracle(oracleS, z)
    @test errS !== nothing
    @test occursin("INFEASIBLE", sprint(showerror, errS))

    oracleSV =
        TSODSO.build_planning_oracle(feederSV, TSODSO.ConvexBranchFlow(), aggs; λ₀ = λ₀, T = T)
    errSV = FeasibilityOracleFixtures.try_solve_planning_oracle(oracleSV, z)
    @test errSV === nothing || !occursin("INFEASIBLE", sprint(showerror, errSV))

    # --- The actual BILEV-04a assertion, on the smax-widened/REAL-voltage (genuinely
    # voltage-infeasible) feeder.
    fo = TSODSO.build_feasibility_oracle(feederS, TSODSO.ConvexBranchFlow(), aggs; T = T)
    r = TSODSO.solve_feasibility_oracle!(fo, z)
    @test r.cost > 1e-6
    @test r.v == r.cost
    @test length(r.u) == T
    @test r.z_k == z

    master = TSODSO.build_master(; T = T, c_y = 0.3, y_max = 2.0, α_op_lb = -500.0, α_x_lb = 0.0)
    nc0 = num_constraints(master.model; count_variable_in_set_constraints = true)
    TSODSO.add_feasibility_cut!(master, r.v, r.u, r.z_k)
    nc1 = num_constraints(master.model; count_variable_in_set_constraints = true)
    @test nc1 == nc0 + 1
end

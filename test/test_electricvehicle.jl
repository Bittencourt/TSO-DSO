# Seam: devices/ElectricVehicle.jl + models/complementarity_ev.jl.
#
# Phase 43 plan 02 (DEV-06, DEV-07, DEV-10b). The ElectricVehicle is the first FLEXIBLE device of
# the phase: V1G smart charging inside a session window (hard zero-upper bounds, binary-free),
# a convex quadratic-epigraph soft departure-energy target, the whole-horizon T+1 SOC closure,
# and an OPT-IN V2G discharge leg with a strictly positive degradation cost. Because NO
# constraint forbids p_ch·p_dch > 0, V2G correctness rests on the parametrization and a DEDICATED
# post-solve certificate (`assert_ev_complementarity!`, own measured τ_ev) -- exercised here on a
# NEGATIVE-price fixture where the App. C η<1 co-charge optimum is real (honesty policy: the
# report FIRING is the certificate working, so the test asserts it fires).
#
# Every item name contains "electricvehicle" so `occursin("electricvehicle", ti.name)` selects it.
# Fixture params are inline documented constants at two-bus scale (T = 24, per-unit power).
#
# Signature under test (positional, then V2G keywords):
#   ElectricVehicle(bus, η, Δt, Pmax, Emin, Emax, soc0, E_target, κ, λ_min, λ_med, λ_max,
#                   t_arr, t_dep; v2g = false, c_deg = 0.0)

@testitem "electricvehicle: ElectricVehicle constructor guards reject physics / App. C / V2G violations" tags =
    [:electricvehicle] begin
    using TSODSO, JuMP

    # A valid V1G parameterization (STRICT λ ordering, in-window session, target inside band).
    good(;
        η = 0.9,
        Pmax = 5.0,
        Emin = 0.0,
        Emax = 40.0,
        soc0 = 10.0,
        Et = 30.0,
        κ = 10.0,
        lmin = 1.0,
        lmed = 4.0,
        lmax = 9.0,
        ta = 2,
        td = 8,
        v2g = false,
        c_deg = 0.0,
    ) = TSODSO.ElectricVehicle(
        2,
        η,
        1.0,
        Pmax,
        Emin,
        Emax,
        soc0,
        Et,
        κ,
        lmin,
        lmed,
        lmax,
        ta,
        td;
        v2g = v2g,
        c_deg = c_deg,
    )

    @test good() isa TSODSO.AbstractDevice
    @test good() isa TSODSO.ElectricVehicle{Float64}
    @test good(v2g = true, c_deg = 0.05).v2g === true

    # eta outside (0, 1]
    @test_throws ArgumentError good(η = 0.0)
    @test_throws ArgumentError good(η = 1.1)
    # Pmax <= 0
    @test_throws ArgumentError good(Pmax = 0.0)
    @test_throws ArgumentError good(Pmax = -1.0)
    # Emin > Emax
    @test_throws ArgumentError good(Emin = 50.0, Emax = 40.0, soc0 = 45.0, Et = 45.0)
    # soc0 outside [Emin, Emax]
    @test_throws ArgumentError good(soc0 = -1.0)
    @test_throws ArgumentError good(soc0 = 41.0)
    # departure target outside the SOC band (never attainable)
    @test_throws ArgumentError good(Et = 41.0)
    # non-strict / reversed lambda ordering (App. C strictness)
    @test_throws ArgumentError good(lmin = 4.0, lmed = 4.0)
    @test_throws ArgumentError good(lmed = 9.0, lmax = 9.0)
    @test_throws ArgumentError good(lmin = 9.0, lmed = 4.0, lmax = 1.0)
    # negative shortfall penalty
    @test_throws ArgumentError good(κ = -1.0)
    # session indices below 1 (the upper bound T is re-guarded in contribute!)
    @test_throws ArgumentError good(ta = 0)
    @test_throws ArgumentError good(td = 0)
    # arrival == departure: an empty/degenerate session
    @test_throws ArgumentError good(ta = 5, td = 5)
    # V2G requires a STRICTLY positive degradation cost
    @test_throws ArgumentError good(v2g = true, c_deg = 0.0)
    @test_throws ArgumentError good(v2g = true, c_deg = -0.1)

    # A mixed-type call (Int among Float64s) promotes to ONE common type, not a MethodError.
    mixed = TSODSO.ElectricVehicle(2, 0.9, 1, 5, 0, 40, 10, 30, 10, 1, 4, 9, 2, 8)
    @test mixed isa TSODSO.ElectricVehicle{Float64}
    @test mixed.Pmax === 5.0
    @test mixed.t_arr === 2 && mixed.t_dep === 8

    # contribute! re-guards the session against the ACTUAL horizon (Deferrable idiom).
    model = JuMP.Model()
    ctx = TSODSO.ModelContext(model)
    @test_throws ArgumentError TSODSO.contribute!(good(ta = 2, td = 30), ctx; T = 24)
    @test_throws ArgumentError TSODSO.contribute!(good(ta = 30, td = 3), ctx; T = 24)
end

@testitem "electricvehicle: contribute! honors the aggregatable contract and sign convention" tags =
    [:electricvehicle] begin
    using TSODSO, JuMP

    T = 24
    ev = TSODSO.ElectricVehicle(2, 0.9, 1.0, 5.0, 0.0, 40.0, 10.0, 30.0, 10.0, 1.0, 4.0, 9.0, 2, 8)

    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)
    res = TSODSO.contribute!(ev, ctx; T = T)

    # Active-only, aggregatable: exactly the 3-tuple, nothing written to the network seams.
    @test propertynames(res) == (:vars, :p_inject, :utility)
    @test isempty(ctx.residuals)
    @test isempty(ctx.objective.terms) && iszero(ctx.objective.aff)
    @test res.utility isa QuadExpr
    @test length(res.p_inject) == T
    @test all(x -> x isa AffExpr, res.p_inject)

    # V1G vars shape: no p_dch variable at all; soc0 stays under the :soc0 stash key.
    @test propertynames(res.vars) == (:p_ch, :soc, :soc0)
    @test length(res.vars.soc) == T + 1          # whole-horizon closure (soc[T+1] exists)

    # Sign convention: charging at a positive price REDUCES injection (p_inject = -p_ch).
    for t in 1:T
        @test coefficient(res.p_inject[t], res.vars.p_ch[t]) == -1.0
    end

    # Utility keeps the -(kappa/2) s^2 curvature (a quadratic term exists and is concave).
    @test !isempty(res.utility.terms)
    @test all(<=(0.0), values(res.utility.terms))

    # V2G vars shape and injection sign: p_inject = p_dch - p_ch.
    ev2 = TSODSO.ElectricVehicle(
        2, 0.9, 1.0, 5.0, 0.0, 40.0, 10.0, 30.0, 10.0, 1.0, 4.0, 9.0, 2, 8;
        v2g = true, c_deg = 0.05,
    )
    m2 = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx2 = TSODSO.ModelContext(m2)
    r2 = TSODSO.contribute!(ev2, ctx2; T = T)
    @test propertynames(r2.vars) == (:p_ch, :p_dch, :soc, :soc0)
    @test coefficient(r2.p_inject[3], r2.vars.p_dch[3]) == 1.0
    @test coefficient(r2.p_inject[3], r2.vars.p_ch[3]) == -1.0
end

@testitem "electricvehicle: standalone V1G QP charges only inside the window; target soft" tags =
    [:electricvehicle] begin
    using TSODSO, JuMP

    T = 24
    t_arr, t_dep = 2, 8
    Pmax, η = 5.0, 0.9
    E_target, soc0 = 30.0, 10.0

    # Solve a bare EV-only QP against a flat hand price (NO feeder: device is network-agnostic).
    function solve_flat(price::Float64, κ::Float64)
        model = Model(TSODSO.select_optimizer(TSODSO.QP()))
        ctx = TSODSO.ModelContext(model)
        ev = TSODSO.ElectricVehicle(
            2, η, 1.0, Pmax, 0.0, 40.0, soc0, E_target, κ, 1.0, 4.0, 9.0, t_arr, t_dep,
        )
        res = TSODSO.contribute!(ev, ctx; T = T)
        @objective(model, Max, res.utility + sum(price * res.p_inject[t] for t in 1:T))
        TSODSO.assert_solved!(model; dual = true, allow_local = false)
        return res, model
    end

    # Cheap energy + stiff penalty: the departure target is (essentially) reached.
    # Analytic bound on the residual shortfall: s* ≤ (price + λ_med)/(κ η) < 1e-3 here.
    res, model = solve_flat(0.1, 1e4)
    p_ch, soc = res.vars.p_ch, res.vars.soc
    for t in 1:T
        if t_arr <= t <= t_dep
            @test upper_bound(p_ch[t]) == Pmax
        else
            @test upper_bound(p_ch[t]) == 0.0      # window = zero-upper-bound, no binary
            @test abs(value(p_ch[t])) <= 1e-8      # nothing charged outside the session
        end
    end
    @test value(soc[1]) ≈ soc0 atol = 1e-6
    @test value(soc[t_dep + 1]) >= E_target - 1e-2
    # SOC recursion closes the WHOLE horizon, hour T included.
    for t in 1:T
        @test value(soc[t + 1]) ≈ value(soc[t]) + η * value(p_ch[t]) atol = 1e-5
    end

    # Dear energy + soft (small) penalty: the EV BACKS OFF -- the target is genuinely soft.
    res2, _ = solve_flat(50.0, 1.0)
    @test sum(value, res2.vars.p_ch) <= 1e-5
    @test value(res2.vars.soc[t_dep + 1]) <= E_target - 5.0
end

@testitem "electricvehicle: wrap-window session yields union bounds (overnight, still binary-free)" tags =
    [:electricvehicle] begin
    using TSODSO, JuMP

    T = 24
    t_arr, t_dep = 20, 5                 # arrives hour 20, departs hour 5 of the NEXT cycle
    Pmax = 5.0
    ev = TSODSO.ElectricVehicle(
        2, 0.9, 1.0, Pmax, 0.0, 40.0, 10.0, 30.0, 10.0, 1.0, 4.0, 9.0, t_arr, t_dep;
        v2g = true, c_deg = 0.05,
    )
    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)
    res = TSODSO.contribute!(ev, ctx; T = T)
    for t in 1:T
        inwin = (t >= t_arr) || (t <= t_dep)
        @test upper_bound(res.vars.p_ch[t]) == (inwin ? Pmax : 0.0)
        @test upper_bound(res.vars.p_dch[t]) == (inwin ? Pmax : 0.0)   # V2G leg obeys the window
    end
end

@testitem "electricvehicle: zero binary / zero integer variables (V1G and V2G shapes)" tags =
    [:electricvehicle] begin
    using TSODSO, JuMP

    T = 4
    function count_vars(; v2g::Bool)
        ev = TSODSO.ElectricVehicle(
            2, 0.9, 1.0, 5.0, 0.0, 40.0, 10.0, 30.0, 10.0, 1.0, 4.0, 9.0, 1, 3;
            v2g = v2g, c_deg = v2g ? 0.05 : 0.0,
        )
        model = Model(TSODSO.select_optimizer(TSODSO.QP()))
        ctx = TSODSO.ModelContext(model)
        TSODSO.contribute!(ev, ctx; T = T)
        return all_variables(model)
    end

    # V1G: p_ch (T) + soc (T+1) + soc0 Parameter (1) + shortfall s (1) = 2T + 3.
    v1 = count_vars(v2g = false)
    @test length(v1) == 2T + 3
    @test count(is_binary, v1) == 0
    @test count(is_integer, v1) == 0

    # V2G adds p_dch (T): 3T + 3.
    v2 = count_vars(v2g = true)
    @test length(v2) == 3T + 3
    @test count(is_binary, v2) == 0
    @test count(is_integer, v2) == 0
end

@testitem "electricvehicle: two instances contribute to ONE model (anonymous JuMP objects)" tags =
    [:electricvehicle] begin
    using TSODSO, JuMP

    T = 6
    mk() = TSODSO.ElectricVehicle(
        2, 0.9, 1.0, 5.0, 0.0, 40.0, 10.0, 30.0, 10.0, 1.0, 4.0, 9.0, 1, 4,
    )
    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)
    r1 = TSODSO.contribute!(mk(), ctx; T = T)   # would throw on a named-container collision
    r2 = TSODSO.contribute!(mk(), ctx; T = T)
    @test length(all_variables(model)) == 2 * (2T + 3)
    @test r1.vars.soc0 != r2.vars.soc0
    @test isempty(object_dictionary(model))
end

@testitem "electricvehicle: V2G negative-price fixture -- certificate REPORTS co-charge, battery cert silent" tags =
    [:electricvehicle] begin
    using TSODSO, JuMP

    # App. C assumes η = 1; for η < 1 at a DEEPLY NEGATIVE effective price an SOC-neutral round
    # trip earns (1 - η²)(λ_med + |λ|) - η² c_deg > 0, so simultaneous charge/discharge IS the
    # KKT-consistent optimum (welfare_solve.jl:309-321). With c_deg tiny the round trip stays
    # profitable: at p_ch = Pmax = 5, p_dch = η² p_ch ≈ 4.05 ⇒ p_ch·p_dch/Pmax² ≈ 0.8.
    T = 24
    Pmax, η = 5.0, 0.9
    ev = TSODSO.ElectricVehicle(
        2, η, 1.0, Pmax, 0.0, 40.0, 20.0, 20.0, 10.0, 1.0, 4.0, 9.0, 1, 24;
        v2g = true, c_deg = 0.01,
    )
    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)
    ctx.T = T
    res = TSODSO.contribute!(ev, ctx; T = T)
    # Mimic Aggregator's type-paired stash (this standalone fixture has no Aggregator).
    ctx.agg_device_vars[2] = Any[res.vars]
    ctx.agg_device_types[2] = DataType[typeof(ev)]

    price = fill(-50.0, T)
    @objective(model, Max, res.utility + sum(price[t] * res.p_inject[t] for t in 1:T))
    TSODSO.assert_solved!(model; dual = true, allow_local = false)

    @test isdefined(TSODSO, :assert_ev_complementarity!)
    @test TSODSO.storage_kind(typeof(ev)) === :ev

    # The EV certificate FIRES (honesty policy: co-charge is the optimum, the report is the point).
    ratio = TSODSO.assert_ev_complementarity!(ctx; T = T, report = true)
    @test ratio > 1.0
    @test_logs (:warn, r"EV complementarity") match_mode = :any TSODSO.assert_ev_complementarity!(
        ctx; T = T, on_violation = :warn,
    )
    @test_throws TSODSO.CertificateError TSODSO.assert_ev_complementarity!(ctx; T = T)

    # Trait routing: the BATTERY certificate must not run battery semantics on EV vars.
    @test TSODSO.assert_battery_complementarity!(ctx; τ = 1e-6, T = T) === nothing

    # ...whereas WITHOUT type provenance the legacy shape fallback WOULD misclassify the EV as
    # a battery and throw -- the 43-01 regression this plan exists to keep from re-opening.
    ctx_legacy = TSODSO.ModelContext(model)
    ctx_legacy.T = T
    ctx_legacy.agg_device_vars[2] = Any[res.vars]
    @test_throws TSODSO.CertificateError TSODSO.assert_battery_complementarity!(
        ctx_legacy; τ = 1e-6, T = T,
    )
end

@testitem "electricvehicle: V1G entries are a no-op for the EV certificate (no p_dch leg)" tags =
    [:electricvehicle] begin
    using TSODSO, JuMP

    T = 6
    ev = TSODSO.ElectricVehicle(
        2, 0.9, 1.0, 5.0, 0.0, 40.0, 10.0, 30.0, 10.0, 1.0, 4.0, 9.0, 1, 4,
    )
    model = Model(TSODSO.select_optimizer(TSODSO.QP()))
    ctx = TSODSO.ModelContext(model)
    ctx.T = T
    res = TSODSO.contribute!(ev, ctx; T = T)
    ctx.agg_device_vars[2] = Any[res.vars]
    ctx.agg_device_types[2] = DataType[typeof(ev)]
    @objective(model, Max, res.utility + sum(1.0 * res.p_inject[t] for t in 1:T))
    TSODSO.assert_solved!(model; dual = true, allow_local = false)
    @test TSODSO.assert_ev_complementarity!(ctx; T = T) == 0.0
end

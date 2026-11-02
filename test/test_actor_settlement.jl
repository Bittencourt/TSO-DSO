# test/test_actor_settlement.jl
#
# Seam: actor profit line in the Phase-41 settlement layer (plan 44-06, ACTOR-02 profit line,
# ACTOR-03 shared-bus adapters, ACTOR-04 effects on settlement / rebound). Pure post-solve
# accounting: `build_settlement_ledger(...; actor_wedges)` appends one conserving mirror pair
# per (site, hour) `(:actor, id) <-> (:aggregator, bus)` of amount `m_t * load_t`, so
# `balances[(:actor, id)] = sum m*load` (the reported profit) and `ledger_residual == 0.0` EXACTLY.
# Every item name contains "actor settlement".
#
# Tolerances (julia 1.12.5, seeds 20260719..21, centralized SOCP at tol 1e-10 and ADMM at
# eps_abs 1e-7 / eps_rel 1e-8, rho 5; pinned at 3x the observed max or a numerical-zero floor):
#
#   quantity                                              observed max   pinned
#   balances[(:actor,k)] vs independent sum m*load        see TOL_PROFIT  TOL_PROFIT
#   balances[(:actor,k)] vs solve profit_by_actor         see TOL_PROFIT  TOL_PROFIT
#
# Accumulators live in functions / `let` (testitem bodies are top-level scope).

@testmodule ActorSettlementFixtures begin
    using TSODSO
    using TSODSO: SOCP, select_optimizer, SMAX_NO_LIMIT

    const T = 24
    const SEEDS = (20260719, 20260720, 20260721)
    const LAMBDA0 = 4.0
    const TOL_PROFIT = 1e-12

    temp() = Float64[19, 18, 17, 16, 16, 17, 19, 21, 23, 26, 28, 30, 31, 32, 32, 31, 29, 27, 25, 23, 22, 21, 20, 19]
    function feeder2()
        return Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT)],
            1,
        )
    end
    function feeder4(r = 0.05)
        return Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false),
                Bus(3, 0.95, 1.05, false), Bus(4, 0.95, 1.05, false)],
            [Branch(1, 2, r, r, SMAX_NO_LIMIT), Branch(2, 3, r, r, SMAX_NO_LIMIT),
                Branch(3, 4, r, r, SMAX_NO_LIMIT)],
            1,
        )
    end
    function site(bus, seed; flex = false, ls = 0.01, ps = 0.0025)
        prof = generate_profiles(seed = seed + bus, T = T)
        Ppv = Float64[ps * p for p in prof.pv]
        Pdc = Float64[ls * d for d in prof.demand]
        devs = AbstractDevice[]
        if flex
            push!(devs, Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, temp()))
            push!(devs, Deferrable(bus, 8, 16, 1.0, 0.5, 0.5))
        end
        push!(devs, PVBattery(bus, 0.95, 1.0, 0.05, 0.0, 0.1, 0.05, 3.8, 6.2, 8.9, Ppv))
        return Aggregator(bus, 0.90, devs, Pdc)
    end
    lambda0() = fill(LAMBDA0, T)
    cent_opt() = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)
    admm_kw(; ρ = 5.0, maxiter = 800) = (
        T = T, λ₀ = lambda0(), ρ = ρ, allow_export = true, maxiter = maxiter,
        ε_abs = 1e-7, ε_rel = 1e-8,
    )
    # 4-bus population: sites at buses 2, 3, 3, 4 (two sites at bus 3)
    function pop4(seed)
        return [
            site(2, seed; ls = 0.05, ps = 0.01),
            site(3, seed; ls = 0.03, ps = 0.008),
            site(3, seed + 1000; ls = 0.03, ps = 0.008),
            site(4, seed; ls = 0.05, ps = 0.01),
        ]
    end
    # Portfolio A (sites 1-2, margin 0.5), B (sites 3-4, margin 1.5 hourly ramp), C absent.
    function ports4(sites; profit_b = true)
        wb = Float64[1.0 + 0.02 * t for t in 1:T]
        return [
            Portfolio(sites[1], sites[2]; name = :A, objective = ProfitObjective(0.5)),
            Portfolio(
                sites[3], sites[4]; name = :B,
                objective = profit_b ? ProfitObjective(wb) : WelfareObjective(),
            ),
        ]
    end
    function central4(seed; profit_b = true)
        sites = pop4(seed)
        ports = ports4(sites; profit_b = profit_b)
        ctx, W, dadp = solve_welfare(
            feeder4(), ConvexBranchFlow(), sites; T = T, λ₀ = lambda0(),
            allow_export = true, optimizer = cent_opt(), actors = ports,
        )
        return (; sites, ports, ctx, W, dadp)
    end
    function admm4(seed)
        sites = pop4(seed)
        ports = ports4(sites)
        r = solve_admm(feeder4(), ConvexBranchFlow(), sites; admm_kw()..., actors = ports)
        return (; sites, ports, r)
    end
    # sum over a portfolio's wedge rows of m * load, computed from scratch from the rows' own
    # net vectors (independent of the ledger fold order)
    function row_profit(rows, k)
        s = 0.0
        for row in rows
            row.actor == k || continue
            for t in 1:T
                s += row.m[t] * (-row.net[t])
            end
        end
        return s
    end
end

@testitem "actor settlement: default ledger is bit-identical with and without the keyword" setup =
    [ActorSettlementFixtures] tags = [:actors, :settlement] begin
    using TSODSO
    F = ActorSettlementFixtures
    sites = F.pop4(F.SEEDS[1])
    # plain welfare solve: NO actors at all
    ctx, W, dadp = solve_welfare(
        F.feeder4(), ConvexBranchFlow(), sites; T = F.T, λ₀ = F.lambda0(),
        allow_export = true, optimizer = F.cent_opt(),
    )
    input = settlement_input(ctx; T = F.T, λ₀ = F.lambda0())
    l0 = build_settlement_ledger(input)
    l1 = build_settlement_ledger(input; actor_wedges = nothing)
    @test l0.transfers == l1.transfers
    @test l0.balances == l1.balances
    @test l0.merchandising_surplus == l1.merchandising_surplus
    @test l0.wholesale_payment == l1.wholesale_payment
    # no actor row at all on the default path
    @test !any(a -> a isa Tuple && first(a) === :actor, keys(l1.balances))
    @test length(l1.transfers) == 2 * (length(input.buses) * F.T + F.T)
    # same through the primitive entry point
    l2 = build_settlement_ledger(
        input.prices, input.bus_nets, input.bus_utilities, input.p_import, input.λ₀,
        input.buses; T = input.T, source = input.source, actor_wedges = nothing,
    )
    @test l2.transfers == l0.transfers && l2.balances == l0.balances
end

@testitem "actor settlement: wedge rows conserve exactly and the actor line is sum m*load" setup =
    [ActorSettlementFixtures] tags = [:actors, :settlement] begin
    using TSODSO
    F = ActorSettlementFixtures

    function check(seed)
        c = F.central4(seed)
        rows = TSODSO.actor_wedge_rows(c.ctx, c.ports, c.sites; T = F.T)
        input = settlement_input(c.ctx; T = F.T, λ₀ = F.lambda0())
        base = build_settlement_ledger(input)
        led = build_settlement_ledger(input; actor_wedges = rows)
        prof = c.ctx.meta[:actor].profit_by_actor
        return (; rows, base, led, prof, ports = c.ports, input)
    end
    for seed in F.SEEDS
        r = check(seed)
        # exact conservation, asserted with == (never approx)
        @test ledger_residual(r.led) == 0.0
        # one profit row per profit-objective site (both portfolios profit here: 4 sites)
        @test length(r.rows) == 4
        @test all(row -> length(row.m) == F.T && length(row.net) == F.T, r.rows)
        # actor line equals the independent sum of m * load over the portfolio's sites
        for k in 1:2
            @test isapprox(r.led.balances[(:actor, k)], F.row_profit(r.rows, k); atol = F.TOL_PROFIT, rtol = 0)
            # ... and matches the solve's reported profit_by_actor
            @test isapprox(r.led.balances[(:actor, k)], r.prof[k]; atol = F.TOL_PROFIT, rtol = 0)
        end
        # the mirror side: the aggregators pay exactly what the actors earn
        paid = 0.0
        for j in r.input.buses
            paid += r.led.balances[(:aggregator, j)] - r.base.balances[(:aggregator, j)]
        end
        @test isapprox(paid, -(r.led.balances[(:actor, 1)] + r.led.balances[(:actor, 2)]); atol = F.TOL_PROFIT, rtol = 0)
        # existing lines untouched: the base transfers are a prefix of the augmented ledger
        nb = length(r.base.transfers)
        @test r.led.transfers[1:nb] == r.base.transfers
        @test r.led.merchandising_surplus == r.base.merchandising_surplus
    end
    # a welfare-objective portfolio is omitted (documented): no (:actor, 2) line at all
    let c = F.central4(F.SEEDS[1]; profit_b = false)
        rows = TSODSO.actor_wedge_rows(c.ctx, c.ports, c.sites; T = F.T)
        @test all(row -> row.actor == 1, rows) && length(rows) == 2
        led = build_settlement_ledger(
            settlement_input(c.ctx; T = F.T, λ₀ = F.lambda0()); actor_wedges = rows,
        )
        @test !haskey(led.balances, (:actor, 2))
        @test ledger_residual(led) == 0.0
    end
end

@testitem "actor settlement: shared bus sums per bus in the centralized adapter" setup =
    [ActorSettlementFixtures] tags = [:actors, :settlement] begin
    using TSODSO
    using JuMP: value
    F = ActorSettlementFixtures
    c = F.central4(F.SEEDS[1])
    input = settlement_input(c.ctx; T = F.T, λ₀ = F.lambda0())
    # ONE entry per bus, ascending unique
    @test input.buses == [2, 3, 4]
    @test size(input.prices) == (3, F.T)
    @test sort(collect(keys(input.bus_nets))) == [2, 3, 4]
    ents = c.ctx.meta[:agg_net]
    net(k) = Float64[value(ents[k].net[t]) for t in 1:F.T]
    # bus 3 holds sites 2 and 3: the sum, not an overwrite
    @test input.bus_nets[3] == net(2) .+ net(3)
    @test input.bus_nets[3] != net(3)
    @test input.bus_nets[3] != net(2)
    @test input.bus_nets[2] == net(1)
    @test input.bus_nets[4] == net(4)
    @test input.bus_utilities[3] == Float64(value(ents[2].utility)) + Float64(value(ents[3].utility))
    @test input.bus_utilities[2] == Float64(value(ents[1].utility))
    # a valid per-bus ledger
    led = build_settlement_ledger(input)
    @test ledger_residual(led) == 0.0
    @test led.meta.buses == [2, 3, 4]
end

@testitem "actor settlement: shared bus sums per bus in the ADMM adapter (slot keys)" setup =
    [ActorSettlementFixtures] tags = [:actors, :settlement, :admm] begin
    using TSODSO
    F = ActorSettlementFixtures
    a = F.admm4(F.SEEDS[1])
    r = a.r
    @test r.status == :converged
    @test haskey(r, :slot_bus) && haskey(r, :slot_actor)
    input = settlement_input(r; λ₀ = F.lambda0())
    @test input.buses == [2, 3, 4]
    @test size(input.prices) == (3, F.T)
    # dadp rows are per bus, ascending
    @test input.prices == Float64.(r.dadp[1:3, 1:F.T])
    slots_at(b) = sort([s for (s, bb) in r.slot_bus if bb == b])
    @test length(slots_at(3)) == 2 && length(slots_at(2)) == 1 && length(slots_at(4)) == 1
    s3 = slots_at(3)
    @test input.bus_nets[3] == Float64.(r.agr_dispatch[s3[1]]) .+ Float64.(r.agr_dispatch[s3[2]])
    @test input.bus_nets[3] != Float64.(r.agr_dispatch[s3[1]])
    @test input.bus_utilities[3] == Float64(r.agr_utility[s3[1]]) + Float64(r.agr_utility[s3[2]])
    @test input.bus_nets[2] == Float64.(r.agr_dispatch[2])
    # valid ledger, and the wedge rows reproduce the solve's profit_by_actor
    rows = TSODSO.actor_wedge_rows(r, a.ports; T = F.T)
    @test length(rows) == 4
    led = build_settlement_ledger(input; actor_wedges = rows)
    @test ledger_residual(led) == 0.0
    for k in 1:2
        @test isapprox(led.balances[(:actor, k)], r.actor.profit_by_actor[k]; atol = F.TOL_PROFIT, rtol = 0)
        @test isapprox(led.balances[(:actor, k)], F.row_profit(rows, k); atol = F.TOL_PROFIT, rtol = 0)
    end
end

@testitem "actor settlement: legacy 1:1 adapters unchanged on distinct buses" setup =
    [ActorSettlementFixtures] tags = [:actors, :settlement, :admm] begin
    using TSODSO
    using JuMP: value
    F = ActorSettlementFixtures
    sites = [F.site(2, F.SEEDS[1]; ls = 0.05, ps = 0.01), F.site(3, F.SEEDS[1]; ls = 0.03, ps = 0.008)]
    ports = [Portfolio(sites[1]; objective = ProfitObjective(0.5)), Portfolio(sites[2])]
    r = solve_admm(F.feeder4(), ConvexBranchFlow(), sites; F.admm_kw()..., actors = ports)
    @test !haskey(r, :slot_bus)
    input = settlement_input(r; λ₀ = F.lambda0())
    @test input.buses == [2, 3]
    @test input.bus_nets[2] == Float64.(r.agr_dispatch[2])
    rows = TSODSO.actor_wedge_rows(r, ports; T = F.T)
    @test length(rows) == 1 && rows[1].bus == 2 && rows[1].actor == 1
    led = build_settlement_ledger(input; actor_wedges = rows)
    @test ledger_residual(led) == 0.0
    @test isapprox(led.balances[(:actor, 1)], r.actor.profit_by_actor[1]; atol = F.TOL_PROFIT, rtol = 0)
end

@testitem "actor settlement: rebound metric on a wrapped population" setup =
    [ActorSettlementFixtures] tags = [:actors, :settlement, :behaviour] begin
    using TSODSO
    using JuMP: value
    F = ActorSettlementFixtures
    T = F.T
    # a price spike at hour 12 invites curtailment, then recovery under the rebound constraint
    spike = F.lambda0()
    spike[12] = 40.0
    function run(spec)
        raw = [F.site(2, F.SEEDS[1]; flex = true, ls = 0.05, ps = 0.01)]
        aggs = apply_behaviour(raw, spec; T = T)
        ctx, W, dadp = solve_welfare(
            F.feeder2(), ConvexBranchFlow(), aggs; T = T, λ₀ = spike,
            allow_export = true, optimizer = F.cent_opt(),
        )
        base = sum(TSODSO.baseline_net_load(aggs, T))
        real = Float64[-sum(value(e.net[t]) for e in ctx.meta[:agg_net]) for t in 1:T]
        return (; base, real, rb = rebound(base, real))
    end
    out = run(BehaviourSpec(compliance = 0.5, rebound = (W = 4, r = 1.2)))
    @test length(out.base) == T && all(isfinite, out.base)
    @test isfinite(out.rb.rebound_amount)
    @test !isempty(out.rb.reduction_hours)
    # NaN convention: ratio is NaN exactly when no reduction occurs
    @test isnan(out.rb.rebound_ratio) == isempty(out.rb.reduction_hours)
    # no response at all: baseline against itself -> no reduction, NaN ratio, finite amount
    flat = rebound(out.base, out.base)
    @test isempty(flat.reduction_hours) && isnan(flat.rebound_ratio) && flat.rebound_amount == 0.0
end

@testitem "actor settlement: V5 guards on wedge rows are fail-loud" setup =
    [ActorSettlementFixtures] tags = [:actors, :settlement] begin
    using TSODSO
    F = ActorSettlementFixtures
    T = F.T
    c = F.central4(F.SEEDS[1])
    input = settlement_input(c.ctx; T = T, λ₀ = F.lambda0())
    good = TSODSO.actor_wedge_rows(c.ctx, c.ports, c.sites; T = T)
    build(rows) = build_settlement_ledger(input; actor_wedges = rows)
    @test ledger_residual(build(good)) == 0.0
    r1 = good[1]
    # non-finite wedge / net
    nanm = (; r1..., m = vcat(NaN, r1.m[2:end]))
    @test_throws ArgumentError build([nanm])
    infn = (; r1..., net = vcat(Inf, r1.net[2:end]))
    @test_throws ArgumentError build([infn])
    # mismatched lengths
    @test_throws ArgumentError build([(; r1..., m = r1.m[1:(end - 1)])])
    @test_throws ArgumentError build([(; r1..., net = r1.net[1:(end - 1)])])
    # unknown bus
    @test_throws ArgumentError build([(; r1..., bus = 99)])
    # malformed row
    @test_throws ArgumentError build([(; actor = 1, bus = 2)])
    # helper guards: wrong horizon, sites not among the aggregators
    @test_throws ArgumentError TSODSO.actor_wedge_rows(c.ctx, c.ports, c.sites; T = T + 5)
    @test_throws ArgumentError TSODSO.actor_wedge_rows(c.ctx, c.ports, c.sites[1:2]; T = T)
end

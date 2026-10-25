# Seam: settlement/SettlementLedger.jl + settlement/run_inputs.jl. Per-actor settlement
# ledger — conservation (exact double-entry), the MS named line, the welfare_accounting
# oracle cross-check, adapter guards, household refinement, and the real-run identity on
# the IEEE-13 ground fixture (both run kinds). Item names contain "settlement" so the
# `occursin` filters select them; the real-run item is additionally tagged `:slow`.
# Measured pins follow the gate-then-golden discipline (40-06 precedent): every tolerance
# is either algebraically exact or 10× a value measured live on this exact fixture, with
# the measured value cited at the pin site. NEVER invent a constant.

@testitem "settlement ledger: 2-bus DADP run — exact conservation, MS named line, welfare oracle" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # Hand-built minimal fixture (mirrors test_pricing_welfare.jl:30-45): 2-bus radial,
    # one PVBattery aggregator, solve_welfare with a flat λ₀ and priced export.
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
    λ₀ = fill(40.0, T)
    ctx, obj, _dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        allow_export = true,
    )

    input = settlement_input(ctx; T = T, λ₀ = λ₀)
    led = build_settlement_ledger(input)

    @test input.source == :centralized
    @test led.metadata.T == T
    @test led.metadata.buses == [2]

    # THE phase headline identity: money conservation is EXACT — the double-entry fold
    # over the adjacent (+a, -a) mirror pairs is bitwise 0.0 (IEEE-754).
    @test ledger_residual(led) == 0.0
    # The balance-sum echo is ALSO bitwise 0.0 on this fixture (measured 2026-10-25;
    # the real-run item band-pins the same echo — across INDEPENDENT per-actor folds it
    # is NOT bitwise in general).
    @test sum(values(led.balances)) == 0.0

    # MS is a DISTINCT NAMED line == the DSO balance, never silently absorbed.
    @test led.merchandising_surplus == led.balances[:dso]
    @test haskey(led.balances, :wholesale)

    # wholesale_payment folds with welfare_accounting's mem_cost association → bitwise.
    wp_inline = let
        w = 0.0
        for t in 1:T
            w += λ₀[t] * input.p_import[t]
        end
        w
    end
    @test led.wholesale_payment == wp_inline

    # MS ↔ welfare_accounting.dso oracle (gate-then-golden): measured relative gap on
    # this fixture = 0.0 (the two associations coincide bitwise for a single aggregator),
    # so the pin is the 1e-15 floor, not an invented constant.
    acct = welfare_accounting(ctx; T = T, λ₀ = λ₀)
    rel_ms =
        abs(led.merchandising_surplus - acct.dso) /
        max(abs(led.merchandising_surplus), abs(acct.dso))
    @info "settlement: MS vs welfare_accounting.dso (2-bus)" ms = led.merchandising_surplus dso =
        acct.dso rel = rel_ms
    @test led.merchandising_surplus ≈ acct.dso rtol = 1e-15

    # Prosumer-side echo: Σ_j (U_j + balance_j) + MS ≈ acct.social. Measured relative
    # gap on this fixture = 1.4930711435858472e-16 (independent summation associations of
    # the same floats) → pin 10× measured.
    echo =
        sum(input.bus_utilities[j] + led.balances[(:aggregator, j)] for j in input.buses) +
        led.merchandising_surplus
    @test echo ≈ acct.social rtol = 1.4930711435858472e-15
end

@testitem "settlement ledger: exporter-earns / importer-pays signs" tags = [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # Same net-EXPORTING 2-bus fixture as the oracle item (mirrors
    # test_pricing_welfare.jl:154-205): the aggregator net-INJECTS every hour, so at a
    # positive DADP it EARNS the price-transfer.
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
    λ₀ = fill(40.0, T)
    ctx, obj, _dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        allow_export = true,
    )

    input = settlement_input(ctx; T = T, λ₀ = λ₀)
    led = build_settlement_ledger(input)

    # This aggregator net-EXPORTS every hour.
    @test all(input.bus_nets[2][t] > 0 for t in 1:T)

    # Aggregator balance == the exact transfer fold Σ_t p·net (inline recompute with the
    # SAME fold order — t ascending, single entry — so bitwise identical).
    recompute = let
        s = 0.0
        for t in 1:T
            s += input.prices[1, t] * input.bus_nets[2][t]
        end
        s
    end
    @test led.balances[(:aggregator, 2)] == recompute

    # Exporter EARNS: the settlement balance is far ABOVE what pure device utility gives
    # (device utility is NEGATIVE here — consumption cost dominates this calibration).
    @test led.balances[(:aggregator, 2)] > input.bus_utilities[2]

    # Its economic SURPLUS (device utility + settlement balance) reproduces
    # welfare_accounting's per-actor algebra U + Σ λ·net — the same re-association class
    # measured in the oracle item (measured relative gap 1.4930711435858472e-16 on this
    # fixture) → pin 10× measured.
    acct = welfare_accounting(ctx; T = T, λ₀ = λ₀)
    @test (led.balances[(:aggregator, 2)] + input.bus_utilities[2]) ≈ acct.prosumer rtol =
        1.4930711435858472e-15

    # Hand-built importer-only ledger: negative nets ⇒ NEGATIVE balance (the aggregator
    # PAYS) and a POSITIVE bill — exact dyadic hand value.
    led_imp = build_settlement_ledger(
        [10.0 30.0 20.0],
        Dict(2 => [-1.0, -2.0, -0.5]),
        Dict(2 => 1.0),
        [1.0, 1.0, 1.0],
        [40.0, 40.0, 40.0],
        [2];
        T = 3,
        source = :handbuilt,
    )
    @test ledger_residual(led_imp) == 0.0
    @test led_imp.balances[(:aggregator, 2)] < 0
    @test -led_imp.balances[(:aggregator, 2)] > 0
    @test led_imp.balances[(:aggregator, 2)] == -80.0
    @test led_imp.merchandising_surplus == led_imp.balances[:dso]
end

@testitem "settlement ledger: non-vacuous adapter guards" tags = [:settlement] begin
    using TSODSO
    using JuMP

    # (1) A fresh, UNSOLVED ModelContext (empty meta) is refused — ArgumentError naming
    # the missing :agg_net stash (the same guard shape as welfare_accounting's).
    ctx0 = ModelContext(Model())
    err = try
        settlement_input(ctx0; T = 3)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin(":agg_net", sprint(showerror, err))

    # (2) The ADMM adapter refuses any non-:converged status LOUDLY (Pitfall 4: the
    # additive keys exist only on the :converged path; a :budget_exceeded stop carries
    # NO certified price). The message must name :converged.
    bad = (; status = :budget_exceeded, dadp = nothing, welfare = nothing, λ = nothing)
    err2 = try
        settlement_input(bad; λ₀ = fill(40.0, 3))
        nothing
    catch e
        e
    end
    @test err2 isa ArgumentError
    @test occursin(":converged", sprint(showerror, err2))

    # (3) The ADMM adapter REQUIRES λ₀ (the result NamedTuple does not carry it).
    conv = (
        status = :converged,
        dadp = [40.0 40.0; 40.0 40.0],
        agr_dispatch = Dict(2 => [0.0, 0.0]),
        agr_utility = Dict(2 => 1.0),
        agr_prices = Dict(2 => [40.0, 40.0]),
        dso_ctx = (; meta = Dict(:p_import => [1.0, 2.0])),
    )
    err3 = try
        settlement_input(conv)
        nothing
    catch e
        e
    end
    @test err3 isa ArgumentError

    # (4) Happy path on the minimal converged shape: a valid SettlementInput is built and
    # the ledger over it conserves EXACTLY.
    inp = settlement_input(conv; λ₀ = [40.0, 40.0])
    @test inp isa SettlementInput
    @test inp.source == :admm
    @test inp.buses == [2]
    led = build_settlement_ledger(inp)
    @test ledger_residual(led) == 0.0
end

@testitem "settlement ledger: household refinement (synthetic split)" tags = [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
    λ₀ = fill(40.0, T)
    ctx, obj, _dadp = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        allow_export = true,
    )

    input = settlement_input(ctx; T = T, λ₀ = λ₀)

    # Two households at bus 2 splitting the aggregator EXACTLY in half: net_h = net_j/2,
    # U_h = U_j/2 (halving is exact in IEEE-754, so this split is bitwise-faithful).
    households = [
        (
            house_id = 1,
            bus = 2,
            net = input.bus_nets[2] ./ 2,
            utility = input.bus_utilities[2] / 2,
        ),
        (
            house_id = 2,
            bus = 2,
            net = input.bus_nets[2] ./ 2,
            utility = input.bus_utilities[2] / 2,
        ),
    ]
    led = build_settlement_ledger(input; households = households)

    # Conservation is STILL exact with the split present — the household rows are NOT
    # the conservation source (the run numbers are).
    @test ledger_residual(led) == 0.0
    @test led.households !== nothing
    @test length(led.households) == 2
    @test haskey(led.balances, (:house, 1))
    @test haskey(led.balances, (:house, 2))
    @test haskey(led.reconciliation, 2)

    # Reconciliation residuals are EXACTLY 0.0 for this synthetic split (Σ_h net_h == net_j
    # and Σ_h U_h == U_j bitwise — exact halving/doubling).
    @test led.reconciliation[2] == (0.0, 0.0)

    # Per-house bills equal HALF the aggregator's bill, EXACTLY: folding halved terms is
    # the exact halving of the folded terms (scaling by 1/2 commutes with IEEE addition
    # and rounding, per-term and cumulatively).
    bill_agg = let
        b = 0.0
        for t in 1:T
            b += input.prices[1, t] * (-input.bus_nets[2][t])
        end
        b
    end
    for h in led.households
        @test h.bill == bill_agg / 2
        @test h.surplus == (input.bus_utilities[2] - bill_agg) / 2
    end

    # Houses appear as (:house, id) actors and their balances are exactly -bill (they pay).
    @test led.balances[(:house, 1)] == -led.households[1].bill
    @test led.balances[(:house, 2)] == -led.households[2].bill
end

@testitem "settlement ledger: IEEE-13 ground real-run identity — centralized AND ADMM" tags =
    [:settlement, :slow] setup = [IEEE13Fixtures] begin
    using TSODSO
    using JuMP

    feeder = ieee13_modified()
    aggs = IEEE13Fixtures.build_ieee13_ground_aggregators(feeder)
    T = IEEE13Fixtures.T
    λ₀ = IEEE13Fixtures.mem_price_profile()

    # ---- Leg A: centralized solve_welfare (fast leg) --------------------------------
    ctx, obj, _dadp =
        solve_welfare(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ₀, allow_export = true)
    input = settlement_input(ctx; T = T, λ₀ = λ₀)
    led = build_settlement_ledger(input)

    # The headline identity on a REAL run: exact.
    @test ledger_residual(led) == 0.0

    # MS ↔ welfare_accounting.dso (gate-then-golden): measured relative gap on THIS
    # fixture = 1.479974182716057e-16 (2026-10-25, Julia 1.12.5) — independently
    # associated summations of the same floats → pin 10× measured.
    acct = welfare_accounting(ctx; T = T, λ₀ = λ₀)
    rel_ms =
        abs(led.merchandising_surplus - acct.dso) /
        max(abs(led.merchandising_surplus), abs(acct.dso))
    @info "settlement: MS vs welfare_accounting.dso (IEEE-13 T=24 centralized)" ms =
        led.merchandising_surplus dso = acct.dso rel = rel_ms
    @test led.merchandising_surplus ≈ acct.dso rtol = 1.479974182716057e-15

    # Balance-sum echo: NOT bitwise across independent per-actor folds on the real run —
    # measured |Σ values(balances)| = 3.3306690738754696e-16 → 10× absolute band (the
    # EXACT identity is the transfer fold asserted above).
    @test abs(sum(values(led.balances))) <= 3.3306690738754696e-15

    # Prosumer-side echo: Σ_j (U_j + balance_j) + MS ≈ acct.social — measured relative
    # gap 0.0 on this fixture (bitwise) → floor pin 1e-15.
    echo =
        sum(input.bus_utilities[j] + led.balances[(:aggregator, j)] for j in input.buses) +
        led.merchandising_surplus
    @test echo ≈ acct.social rtol = 1e-15

    # ---- Leg B: converged ADMM — DIRECT solve_admm (NEVER run_scenario: the
    # ScenarioResult seam normalizes away the ctx/additive keys the ledger needs).
    r = solve_admm(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = T,
        λ₀ = λ₀,
        ρ = ADMM().ρ,
        allow_export = true,
    )
    # Knife-edge canary precedent: the IEEE-13 ground ADMM converges deterministically
    # at executor defaults on 1.12.5 — a failure here is a loud attributable flip, not a
    # tolerance to loosen (measured 2026-10-25: status :converged, iters 103).
    @test r.status == :converged

    input_b = settlement_input(r; λ₀ = λ₀)
    led_b = build_settlement_ledger(input_b)
    @test ledger_residual(led_b) == 0.0
    @test isfinite(led_b.merchandising_surplus)

    # Published-price sanity on a sample bus: the adapter's price row IS the run's own
    # published agr_prices row (the pinned dadp layout invariant, end to end).
    js = input_b.buses[1]
    @test input_b.prices[1, :] == r.agr_prices[js]

    # OQ2 probe with fallback — BOTH branches documented; @info records which fired.
    # NEVER add the :agg_net stash to ADMM files (golden): the welfare_accounting
    # cross-check applies to the CENTRALIZED leg; on the ADMM leg the dso_ctx carries
    # only :p_import by design, so the oracle is the primal-welfare fallback
    # Σ_j U_j + MS ≈ r.welfare (the ADMM's own primal welfare recomputation).
    if haskey(r.dso_ctx.meta, :agg_net)
        # Unexpected branch (absent at pin time): the ADMM dso_ctx grew a stash it does
        # not have today. Fail LOUD with re-measurement instructions — never settle for
        # an invented tolerance.
        @info "settlement OQ2: :agg_net stash PRESENT on ADMM dso_ctx (unexpected at pin time)"
        error(
            "settlement: the ADMM dso_ctx now carries ctx.meta[:agg_net] — the " *
            "welfare_accounting oracle branch of this test is reachable. Re-measure the " *
            "MS vs welfare_accounting(r.dso_ctx).dso relative gap on this fixture and " *
            "pin it gate-then-golden (was UNMEASURABLE at pin time, 2026-10-25: the " *
            "stash was absent and the primal-welfare fallback branch carried the pin).",
        )
    else
        @info "settlement OQ2: :agg_net stash ABSENT on ADMM dso_ctx — primal-welfare FALLBACK oracle branch (as measured 2026-10-25)"
        u_sum = sum(values(input_b.bus_utilities))
        # Σ_j U_j + MS ≈ r.welfare: the gap is the ADMM's own consensus residual at
        # convergence (an independent association of DIFFERENT solves), measured rel =
        # 7.60218078094535e-5 on this fixture → pin 10× measured.
        @test u_sum + led_b.merchandising_surplus ≈ r.welfare rtol = 7.60218078094535e-4
        # Balance-sum echo band (measured 2.7755575615628914e-17 → 10×).
        @test abs(sum(values(led_b.balances))) <= 2.7755575615628914e-15
    end
end

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
    @test err2 isa UnconvergedAdmmError
    # Typed (WR-05): the refusal is NOT an ArgumentError — a misuse ArgumentError that
    # merely mentions ":converged" must never be absorbable as a budget stop.
    @test !(err2 isa ArgumentError)
    @test occursin(":converged", sprint(showerror, err2))

    # (2b) The CENTRALIZED adapter refuses a too-short λ₀ with the documented loud
    # ArgumentError BEFORE indexing it — a raw BoundsError used to leak here because
    # the old guard ran AFTER the λ₀ comprehension (dead code: λ0 is built with
    # exactly T elements whenever the indexing succeeded).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T3 = 3
    batt_g = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T3))
    agg_g = Aggregator(2, 0.9, [batt_g], fill(0.1, T3))
    ctx_s, _obj_s, _dadp_s = solve_welfare(
        feeder,
        ConvexBranchFlow(),
        [agg_g];
        T = T3,
        λ₀ = fill(40.0, T3),
        allow_export = true,
    )
    err2b = try
        settlement_input(ctx_s; T = T3, λ₀ = fill(40.0, T3 - 1))
        nothing
    catch e
        e
    end
    @test err2b isa ArgumentError
    @test occursin("λ₀ has length 2 < T=3", sprint(showerror, err2b))
    # A λ₀ LONGER than T is still accepted (truncated to T) — the guard is >=, not ==.
    inp_trunc = settlement_input(ctx_s; T = T3, λ₀ = fill(40.0, T3 + 4))
    @test inp_trunc isa SettlementInput
    @test length(inp_trunc.λ₀) == T3

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

# --- Tariffs (41-03 Task 1): revenue-neutral flat/TOU price construction ---------------

@testitem "tariffs: revenue-neutral flat/TOU — hand-computed anchors + no-op guard" tags =
    [:settlement] begin
    using TSODSO

    # Hand-computed 2-bus/2-hour anchor (the new-math known-value certificate):
    # λ = [10 30; 20 40], w = [−1 −1; −1 −3] ⇒ Σλw = −180, Σw = −6 ⇒ flat = 30.0
    # EXACTLY; TOU bins {[1],[2]} ⇒ bin levels [15.0, 37.5] EXACTLY with the global
    # rescale s == 1.0. Every quantity here is exactly representable in IEEE-754, so
    # the totals identity (the comparison's locked fairness condition) asserts
    # literal `==` — no tolerance laundering on the certificate.
    λ = [10.0 30.0; 20.0 40.0]
    w = [-1.0 -1.0; -1.0 -3.0]

    flat = revenue_neutral_flat(λ, w)
    @test flat == [30.0, 30.0]
    dadp_total = sum(λ[j, t] * w[j, t] for j in 1:2, t in 1:2)
    flat_total = sum(flat[t] * w[j, t] for j in 1:2, t in 1:2)
    @test flat_total == dadp_total

    tou = revenue_neutral_tou(λ, w; bins = [[1], [2]])
    @test tou == [15.0, 37.5]
    tou_total = sum(tou[t] * w[j, t] for j in 1:2, t in 1:2)
    @test tou_total == dadp_total

    # Pinned TOU bins are auditable module constants exposed via default_tou_bins
    # (the A4 resolution: 6/12/6 off-peak/shoulder/peak split over the 24-h profile).
    @test default_tou_bins(24) ==
          [collect(1:6), vcat(collect(7:16), [23, 24]), collect(17:22)]

    # Float-noisy weights (irrational-ish values): the constructor's rescale guard
    # holds (the call does NOT throw — s ≈ 1.0 to well within its 1e-9 rtol) and the
    # derived totals match Σλ·w within 1e-12 relative.
    λn = [10.0 * 1.1 30.0 * 1.3; 20.0 * 1.7 40.0 * 1.9]
    wn = [-1.0 -1.0 + 1e-13; -1.0 - 2e-13 -3.0]
    flatn = revenue_neutral_flat(λn, wn)
    tn = sum(λn[j, t] * wn[j, t] for j in 1:2, t in 1:2)
    fn = sum(flatn[t] * wn[j, t] for j in 1:2, t in 1:2)
    @test fn ≈ tn rtol = 1e-12
end

@testitem "tariffs: real-run revenue neutrality on the 2-bus solve_welfare fixture" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # Same fixture shape as the 41-01 ledger items: 2-bus radial, one PVBattery
    # aggregator, solve_welfare with priced export.
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
    flat = flat_prices(input)
    tou = tou_prices(input; bins = [[1, 2], [3]])
    @test length(flat) == T
    @test length(tou) == T
    @test all(isfinite, flat)
    @test all(isfinite, tou)

    # The locked fairness condition on the SAME run: total payments under the derived
    # tariff == total payments under DADP, quantities = the run's OWN signed nets (A2).
    dadp_total = let
        s = 0.0
        for (i, j) in enumerate(input.buses), t in 1:T
            s += input.prices[i, t] * input.bus_nets[j][t]
        end
        s
    end
    flat_total = let
        s = 0.0
        for (i, j) in enumerate(input.buses), t in 1:T
            s += flat[t] * input.bus_nets[j][t]
        end
        s
    end
    tou_total = let
        s = 0.0
        for (i, j) in enumerate(input.buses), t in 1:T
            s += tou[t] * input.bus_nets[j][t]
        end
        s
    end
    rel_flat = abs(flat_total - dadp_total) / abs(dadp_total)
    rel_tou = abs(tou_total - dadp_total) / abs(dadp_total)
    @info "tariffs: real-run revenue neutrality (2-bus)" dadp_total flat_total tou_total rel_flat =
        rel_flat rel_tou = rel_tou
    # Gate-then-golden pins (measured 2026-10-25, Julia 1.12.5, this fixture):
    #   flat rel gap = 2.8658034134118547e-16 (independent summation associations of
    #   the same floats) → 10× measured; TOU rel gap = 0.0 (bitwise on this fixture)
    #   → floor pin 1e-15. NEVER an invented constant.
    @test flat_total ≈ dadp_total rtol = 2.8658034134118547e-15
    @test tou_total ≈ dadp_total rtol = 1e-15
end

@testitem "tariffs: non-vacuous boundary guards" tags = [:settlement] begin
    using TSODSO

    λ = [10.0 30.0; 20.0 40.0]
    w = [-1.0 -1.0; -1.0 -3.0]

    # (1) shape mismatch
    @test_throws ArgumentError revenue_neutral_flat(λ, w[:, 1:1])

    # (2) all-zero weights: Σ|w| == 0 — the message carries the magnitude
    err = try
        revenue_neutral_flat(λ, zeros(2, 2))
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("Σ|w| = 0.0", sprint(showerror, err))

    # (2b) signed-cancel degeneracy: Σw == 0 while Σ|w| > 0 — the weighted mean is
    # undefined; refused loudly, naming both magnitudes.
    wc = [1.0 -1.0; -1.0 1.0]
    err_c = try
        revenue_neutral_flat(λ, wc)
        nothing
    catch e
        e
    end
    @test err_c isa ArgumentError
    @test occursin("Σw = 0.0", sprint(showerror, err_c))

    # (3) bins are not a partition of 1:T — overlap, gap, out-of-range, empty
    @test_throws ArgumentError revenue_neutral_tou(λ, w; bins = [[1, 2], [2]])
    @test_throws ArgumentError revenue_neutral_tou(λ, w; bins = [[1]])
    @test_throws ArgumentError revenue_neutral_tou(λ, w; bins = [[1], [3]])
    @test_throws ArgumentError revenue_neutral_tou(λ, w; bins = Vector{Vector{Int}}())
    @test_throws ArgumentError revenue_neutral_tou(λ, w; bins = [Int[], [2]])

    # (4) T != 24 with the default bins: ArgumentError NAMING default_tou_bins
    err2 = try
        default_tou_bins(3)
        nothing
    catch e
        e
    end
    @test err2 isa ArgumentError
    @test occursin("default_tou_bins", sprint(showerror, err2))
end

# --- Price-taker (41-03 Task 2): penalty-free counterfactual dispatch -------------------

@testitem "price-taker: dispatch at the run's own DADP prices — finite, certificate :ok" tags =
    [:settlement] begin
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

    # Counterfactual dispatch at the run's OWN DADP price row (strictly varying ⇒
    # non-degenerate battery arbitrage ⇒ the App. C certificate passes).
    price = collect(input.prices[1, :])
    res = price_taker_dispatch(agg, price)
    @test res.net isa Vector{Float64}
    @test length(res.net) == T
    @test all(isfinite, res.net)
    @test isfinite(res.utility)
    @test res.battery_certificate == :ok
    @test res.battery_message == ""

    # The aggregator-level shape mirrors the run's own dispatch numbers (the QP is the
    # AGR-OPT mechanism minus the ρ penalty; at the run's prices it reproduces the run's
    # dispatch to solver tolerance — measured band, not bitwise).
    @info "price-taker vs run dispatch (2-bus DADP prices)" max_abs_gap =
        maximum(abs(res.net[t] - input.bus_nets[2][t]) for t in 1:T)

    # Batch map over the one-element vector + the alias at the household level
    # (household_dispatches is deliberately UNEXPORTED — reach it qualified).
    res_batch = price_taker_dispatches([agg], price)
    @test length(res_batch) == 1
    @test res_batch[1].net == res.net
    res_h = TSODSO.household_dispatches([agg], price)
    @test res_h[1].utility == res.utility
end

@testitem "price-taker: flat-price degeneracy is a RECORDED outcome, never a throw" tags =
    [:settlement] begin
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

    # CONSTANT price vector (the :flat tariff degeneracy, Pitfall 1): the call MUST
    # return (never throw); BOTH certificate outcomes are valid recorded results —
    # degeneracy is solver-dependent and the honesty policy forbids tuning it away.
    res = price_taker_dispatch(agg, fill(30.0, T))
    @test all(isfinite, res.net)
    @test isfinite(res.utility)
    @test res.battery_certificate in (:ok, :refused)
    if res.battery_certificate == :refused
        @test !isempty(res.battery_message)
    end
    @info "price-taker flat-price certificate" certificate = res.battery_certificate message =
        res.battery_message
end

@testitem "price-taker: thermostatic-only aggregator reports :not_checked (WR-03 pin)" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    # An aggregator whose devices are ALL non-battery (thermostatic only) registers
    # device vars in ctx.agg_device_vars but carries NO battery vars. The docstring
    # promises ":not_checked when the aggregator carries no battery vars"; the old
    # emptiness-based detection returned :ok here — a complementarity check that
    # never ran, reported as checked-and-passed (review WR-03). Detection now keys
    # on the check's own battery predicate (p_ch ∧ p_dch ∧ ¬q).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 3
    therm = Thermostatic(2, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, fill(25.0, T))
    agg = Aggregator(2, 0.9, [therm], fill(0.1, T))

    res = price_taker_dispatch(agg, fill(30.0, T))
    @test all(isfinite, res.net)
    @test isfinite(res.utility)
    @test res.battery_certificate == :not_checked
    @test res.battery_message == ""
end

@testitem "price-taker: penalty-free arbitrage — charge-low/sell-high at rated bounds" tags =
    [:settlement] begin
    using TSODSO

    # Hand-checked counterfactual-validity certificate (the ρ-penalty would visibly
    # shade this dispatch — production ρ = 100 damps the battery far below its rated
    # bounds): one PVBattery aggregator, T = 2, prices [10.0, 50.0] (wide spread ⇒
    # full arbitrage). soc0 = 0.3 makes the battery ENERGY-scarce: with the ample
    # soc0 = 1.0 the discharge side is POWER-capped and the cheap-hour charge has no
    # receiving capacity (measured 2026-10-25 — stranded SOC discharges into hour 1
    # at net[1] = 0.65), so the full charge-low/sell-high shape needs the scarce
    # initial energy: the battery CHARGES at its PV limit in the cheap hour
    # (net[1] ≈ 0 — no export left over) and DISCHARGES in the dear hour.
    T = 2
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 0.3, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.0, T))   # pure battery, no inelastic load
    res = price_taker_dispatch(agg, [10.0, 50.0])

    @test isfinite(res.utility)
    # Charge-low/sell-high, hand-derived: p_ch[1] at its PV-limited charge bound
    # (0.2) ⇒ net[1] = pv_used − p_ch ≈ 0; p_dch[2] drains the stored energy to
    # Emin ⇒ net[2] = pv_used + p_dch ≈ 0.2 + 0.95·(0.3 + 0.95·0.2) ≈ 0.6655.
    @test res.net[1] < res.net[2]
    @test res.net[1] < 1e-5     # cheap hour exports NOTHING: the full PV is stored
    @test res.net[2] > 0.2      # dear hour exports MORE than PV alone: discharging
    # Rated bounds: |net| within [−Pmax, Ppv + Pmax]. A ρ = 100 penalty would NOT
    # put the charge at its PV limit / the discharge at the drained-Emin level —
    # the assert documents the counterfactual is unshaded.
    @test all(res.net[t] >= -0.5 - 1e-6 && res.net[t] <= 0.2 + 0.5 + 1e-6 for t in 1:T)
    @info "price-taker arbitrage dispatch" net = res.net utility = res.utility
end

@testitem "price-taker: per-house separability reconciles to the aggregator (measured pin)" tags =
    [:settlement] begin
    using TSODSO

    # Two houses on bus 2 rebuilt from the EXACT Phase-40 primitives (identical draw
    # to build_population's own — attribution cannot drift from the population),
    # rolled up per build_population's load-bearing shape (devices vcat, Pdc sum,
    # materialize.jl:578-596). T = 12: `_case_a_house`'s own Deferrable window is
    # `[min(8,T), min(16,T)]` with E/Pmax = 2, so horizons shorter than 9 trip the
    # device's energy-budget guard at construction (thesis eq. 3.4) — T = 12 keeps
    # the production device constants intact.
    T = 12
    seed = 20260718
    houses = [
        TSODSO._case_a_house(
            2,
            h,
            2,
            seed,
            T;
            load_scale = 0.005,
            pv_scale = 0.03,
            dev_scale = 1.0,
            pv_fraction = 1.0,
        ) for h in 1:2
    ]
    agg = Aggregator(
        2,
        0.90,
        reduce(vcat, [h.devices for h in houses]),
        reduce(+, [h.Pdc for h in houses]),
    )

    price = [30.0, 12.0, 45.0, 8.0, 22.0, 17.0, 52.0, 9.0, 31.0, 14.0, 27.0, 41.0]   # strictly varying, non-degenerate
    agg_res = price_taker_dispatch(agg, price)
    house_res = price_taker_dispatches(houses, price)

    net_inf =
        maximum(abs(sum(house_res[h].net[t] for h in 1:2) - agg_res.net[t]) for t in 1:T)
    u_gap = abs(sum(house_res[h].utility for h in 1:2) - agg_res.utility)
    @info "price-taker separability (2 houses, T=4)" net_inf_norm = net_inf utility_gap =
        u_gap
    # At a fixed price the aggregator problem SEPARATES across member houses — the
    # sums reconcile to within solver tolerance, NEVER claimed bitwise (Pitfall 5).
    # Gate-then-golden pins (measured 2026-10-25, Julia 1.12.5, this fixture):
    #   net_inf_norm = 8.302723663710515e-8 → 10× measured = 8.302723663710515e-7;
    #   utility_gap  = 1.9731015754587133e-7 → 10× measured = 1.9731015754587133e-6.
    # (Both above the 1e-9 floor — the measured values govern.) NEVER an invented
    # constant: a tighter bound here is a solver-precision flip, re-measure first.
    @test net_inf <= 8.302723663710515e-7
    @test u_gap <= 1.9731015754587133e-6
end

@testitem "price-taker: non-vacuous boundary guards" tags = [:settlement] begin
    using TSODSO

    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))

    # length(price) != T
    @test_throws ArgumentError price_taker_dispatch(agg, fill(30.0, T + 1))
    # non-finite price
    @test_throws ArgumentError price_taker_dispatch(agg, [30.0, NaN, 30.0])
    @test_throws ArgumentError price_taker_dispatch(agg, [30.0, Inf, 30.0])
    # empty aggregator vector
    @test_throws ArgumentError price_taker_dispatches(Aggregator[], fill(30.0, T))
end

# --- AC feasibility status (41-03 Task 3): report, never throw --------------------------

@testitem "ac-feasibility: benign DADP dispatch is :feasible — reported, never thrown" tags =
    [:settlement] begin
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

    # The run's OWN dispatch through the physics-only AC power flow: within the
    # branch rating and the bus voltage band ⇒ :feasible. The call NEVER throws —
    # a status is the SETL-03 contract.
    st = ac_feasibility_status(feeder, [agg], [input.bus_nets[2]]; T = T)
    @test st isa TSODSO.FeasibilityStatus
    @test st.status == :feasible
    @test st.n_thermal_violations == 0
    @test st.n_voltage_violations == 0
    @test st.max_overload_ratio <= 1.0
    @test all(isfinite, [h.min_voltage for h in st.hours])
    @test all(isfinite, [h.max_voltage for h in st.hours])
    @test length(st.hours) == T
end

@testitem "ac-feasibility: overloaded dispatch is :infeasible with full diagnostics — still no throw" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))

    # Deliberately violating dispatch: 12 pu net injection at bus 2 — ABOVE the
    # 10-pu branch rating (thermal ratio ≈ 1.2) yet within the feeder's AC
    # loadability, so the physics-only power flow CONVERGES and the violation is
    # REPORTED. (The plan's original ~50× the rating = 500 pu sits far beyond the
    # network's loadability ≈ 25 pu — that poison deterministically produces
    # :solve_failed instead, which is Test 4's contract; the STATUS CONTRACT is
    # what asserts, per the plan's own adjust-the-poison note.)
    st = ac_feasibility_status(feeder, [agg], [[12.0, 12.0, 12.0]]; T = T)
    @test st.status == :infeasible
    @test st.n_thermal_violations >= 1
    @test st.max_overload_ratio > 1.0
    # Per-hour rows carry the exact _fit_ac_settlement_violations field set.
    for h in st.hours
        @test hasproperty(h, :t)
        @test hasproperty(h, :n_thermal_violations)
        @test hasproperty(h, :max_overload_ratio)
        @test hasproperty(h, :n_voltage_violations)
        @test hasproperty(h, :min_voltage)
        @test hasproperty(h, :max_voltage)
        @test hasproperty(h, :voltage_violated)
    end
    @test [h.t for h in st.hours] == [1, 2, 3]
    @info "ac-feasibility stress" status = st.status n_thermal = st.n_thermal_violations n_voltage =
        st.n_voltage_violations max_ratio = st.max_overload_ratio
end

@testitem "ac-feasibility: SMAX_NO_LIMIT branch is skip-listed from thermal counting" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    # Same dispatch, but the branch carries the SMAX_NO_LIMIT sentinel (99.0):
    # the diagnostics template's `br.smax < SMAX_NO_LIMIT || continue` excludes it
    # from thermal counting entirely — max_overload_ratio stays 0.0 and no thermal
    # violation is counted (voltage diagnostics still run; the STATUS is whatever
    # the measured outcome is — the assert here is on the thermal skip-list).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, SMAX_NO_LIMIT)],
        1,
    )
    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))

    st = ac_feasibility_status(feeder, [agg], [[12.0, 12.0, 12.0]]; T = T)
    @test st.n_thermal_violations == 0
    @test st.max_overload_ratio == 0.0
    @test all(h.n_thermal_violations == 0 for h in st.hours)
end

@testitem "ac-feasibility: non-convergence is a recorded :solve_failed status, never a throw" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 1
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))

    # An operating point with NO physical AC solution: 500 pu net injection through
    # an x = 0.02 pu branch (loadability ≈ V²/2X ≈ 25 pu) — Ipopt cannot converge,
    # and the status layer RECORDS that as :solve_failed carrying the termination
    # status. (This is the plan's original "~50× the rating" poison, re-derived:
    # beyond loadability it belongs to the solve-failed contract, not the
    # thermally-overloaded one.) Deterministic 2026-10-25, Julia 1.12.5.
    st = ac_feasibility_status(feeder, [agg], [[500.0]]; T = T)
    @test st.status == :solve_failed
    @test !isempty(st.message)
    @test isempty(st.hours)
    @info "ac-feasibility solve-failure" message = st.message
end

@testitem "ac-feasibility: non-vacuous boundary guards" tags = [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder

    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))

    # nets/aggs length mismatch
    @test_throws ArgumentError ac_feasibility_status(
        feeder,
        [agg],
        [fill(0.0, T), fill(0.0, T)];
        T = T,
    )
    # net length != T
    @test_throws ArgumentError ac_feasibility_status(
        feeder,
        [agg],
        [fill(0.0, T + 1)];
        T = T,
    )
    # non-finite net
    @test_throws ArgumentError ac_feasibility_status(
        feeder,
        [agg],
        [[0.0, NaN, 0.0]];
        T = T,
    )
    # empty aggs (checked FIRST — a dispatch needs at least one aggregator)
    @test_throws ArgumentError ac_feasibility_status(feeder, Aggregator[], [[0.0]]; T = 1)
end

# --- Tariff comparison runner (41-04): compare_tariffs -----------------------------------
#
# The runner is pure ASSEMBLY of the four validated settlement layers (ledger/adapters,
# tariffs + price-taker, feasibility status, equity/rebound) over ONE solved DADP run.
# These items pin: the four-leg row contract (statuses, never dropped legs), the
# revenue-neutrality echo at the runner level (same constructors, same input — the 41-03
# fairness condition carries through), equity columns on bills AND surplus + the rebound
# conventions (dadp baseline == itself ⇒ amount 0), the pv/bus/tercile breakouts (fit leg
# excluded — the A1 asymmetry), and the real IEEE-13 ground run (:slow).
# Gate-then-golden pins: every tolerance below carries its measured value at the pin site
# (provisional 1e-12 in the RED commit, re-pinned from live measurement in GREEN).

# 42-02: the `agr_optimizer` passthrough — compare_tariffs threads the caller-supplied AGR
# optimizer factory verbatim into the engine = :admm solve_admm call (the fit_optimizer/
# time_limit_s precedent in the same signature). Default `nothing` = solve_admm's own
# default factory = byte-identical behavior; both items below encode DEFAULT-EQUIVALENCE
# (explicit `select_optimizer(QP())` / explicit `nothing` vs the kwarg-less call), never a
# magnitude pin (golden policy — no fixture welfare value is pinned here).

@testitem "settlement compare_tariffs threads agr_optimizer (default-equivalence, small fixture)" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using DataFrames: eachrow

    # The existing small 2-bus DADP settlement fixture (the neighboring compare_tariffs
    # items' fixture — NOT a full population), with the neighbor's explicit
    # `bins = [[1, 2], [3]]` (default_tou_bins is 24-hour-only). The explicitly-passed
    # factory `select_optimizer(QP())` with NO kwargs is resolve-IDENTICAL to what
    # solve_admm's `agr_optimizer = nothing` default builds, so both calls take the
    # algebraically identical solve path and the certified scalars compare BITWISE
    # (test_settlement.jl:6-8 discipline — the algebraically-exact class, NOT a
    # solver-tolerance comparison).
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
    λ₀ = fill(40.0, T)

    base = compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        engine = :admm,
        ρ = ADMM().ρ,
        bins = [[1, 2], [3]],
    )
    threaded = compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        engine = :admm,
        ρ = ADMM().ρ,
        bins = [[1, 2], [3]],
        agr_optimizer = select_optimizer(TSODSO.QP()),
    )

    # Both runs certify the DADP leg (honest per-leg status rows — a refusal would be a
    # recorded row, never a dropped leg; this small fixture certifies at the default rung).
    row_base = only(filter(r -> r.tariff == "dadp", eachrow(base.summary)))
    row_threaded = only(filter(r -> r.tariff == "dadp", eachrow(threaded.summary)))
    @test row_base.status == "ok"
    @test row_threaded.status == "ok"

    # Same effective factory, same solve ⇒ bitwise-identical certified scalars.
    @test row_threaded.welfare == row_base.welfare
    @test row_threaded.total_payments == row_base.total_payments
    @test row_threaded.merchandising_surplus == row_base.merchandising_surplus
end

@testitem "settlement compare_tariffs agr_optimizer default is nothing (signature contract)" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using DataFrames: eachrow

    # Signature contract: an EXPLICIT `agr_optimizer = nothing` is the kwarg-less call —
    # `nothing` resolves inside solve_admm to the plain `select_optimizer(QP())` factory,
    # exactly as the absent kwarg does. Bitwise welfare equality encodes it.
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
    λ₀ = fill(40.0, T)

    kwargless = compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        engine = :admm,
        ρ = ADMM().ρ,
        bins = [[1, 2], [3]],
    )
    explicit_nothing = compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        engine = :admm,
        ρ = ADMM().ρ,
        bins = [[1, 2], [3]],
        agr_optimizer = nothing,
    )

    row_k = only(filter(r -> r.tariff == "dadp", eachrow(kwargless.summary)))
    row_n = only(filter(r -> r.tariff == "dadp", eachrow(explicit_nothing.summary)))
    @test row_k.status == "ok"
    @test row_n.status == "ok"
    @test row_n.welfare == row_k.welfare
end

@testitem "compare-tariffs: four-leg hermetic run — rows, statuses, CSV writes, granularities, guards" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using DataFrames: DataFrame, eachrow, nrow
    using CSV
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

    # Two hand-built households at bus 2 (distinct device draws → distinct bills; the
    # per-house split is NOT the conservation source — the ledger records reconciliation).
    h1 = Aggregator(
        2,
        0.9,
        [PVBattery(2, 0.95, 1.0, 0.25, 0.0, 1.0, 0.5, 1.0, 2.0, 3.0, fill(0.2, T))],
        fill(0.05, T),
    )
    h2 = Aggregator(
        2,
        0.9,
        [PVBattery(2, 0.95, 1.0, 0.35, 0.0, 1.5, 0.7, 1.0, 2.0, 3.0, fill(0.15, T))],
        fill(0.04, T),
    )
    houses = [h1, h2]
    map_rows = [
        (
            house = k,
            bus = 2,
            aggregator = 2,
            device_set = :test_house,
            pv_group = k == 1 ? :pv : :non_pv,
            house_index = k,
        ) for k in 1:2
    ]

    res = compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        engine = :centralized,
        bins = [[1, 2], [3]],
        houses = houses,
        map_rows = map_rows,
    )

    # Exactly four rows — one per tariff, in the fixed leg order, no leg dropped.
    @test res.summary isa DataFrame
    @test nrow(res.summary) == 4
    @test res.summary.tariff == ["dadp", "flat", "tou", "fit"]
    row_of = Dict(r.tariff => r for r in eachrow(res.summary))
    for t in ("dadp", "flat", "tou", "fit")
        r = row_of[t]
        @test isfinite(r.welfare)
        @test isfinite(r.merchandising_surplus)
        @test isfinite(r.total_payments)
        @test r.feasibility_status in ("feasible", "infeasible", "solve_failed")
        @test r.batt_ok >= 0 && r.batt_refused >= 0 && r.batt_not_checked >= 0
        @test r.engine == "centralized"
        @test r.t_horizon == T
        @test r.bills_granularity in ("house", "bus")
    end
    # Certificate semantics: the counts cover the price-taker dispatches at the row's
    # bills_granularity — with houses supplied that is the per-house re-solves (2 here);
    # each is :ok or a RECORDED :refused (degenerate flat prices are a measured outcome).
    # The fit leg is batteryless by A4 (:not_checked, one per bus row).
    @test row_of["flat"].batt_ok + row_of["flat"].batt_refused == 2
    @test row_of["tou"].batt_ok + row_of["tou"].batt_refused == 2
    @test row_of["dadp"].batt_ok + row_of["dadp"].batt_refused == 2
    @test row_of["fit"].batt_not_checked == 1

    # BL-01 internal-consistency pin: the fit leg's wholesale_total carries the LEDGER
    # convention (+sum_t lambda_0[t]*p_import[t], the same sign as `led.balances[:wholesale]`
    # on the other legs); merchandising surplus = collections − wholesale. On THIS fixture
    # the FIT prosumer is self-sufficient (Ppv == p_h ⇒ imp ≈ solver noise ≈ 0), so the
    # wholesale receipt is ≈ 0 and the SIGN is pinned by the dedicated pure-consumer
    # item below; here the EXACT identities are pinned (bitwise, same-float arithmetic).
    fitr = row_of["fit"]
    @test fitr.merchandising_surplus == fitr.dso_total - fitr.wholesale_total
    @test fitr.dso_total == fitr.total_payments
    @test fitr.aggregators_total == -fitr.total_payments

    # mktempdir hermeticity: every CSV write lands under the temp dir only.
    mktempdir() do dir
        for (name, df) in (
            ("summary", res.summary),
            ("bills", res.household_bills),
            ("breakouts", res.equity_breakouts),
            ("rebound", res.rebound),
        )
            p = joinpath(dir, "$name.csv")
            CSV.write(p, df)
            @test isfile(p)
            @test filesize(p) > 0
        end
    end

    # household_bills: house-granularity rows for dadp/flat/tou (2 houses each); the fit
    # leg is bus-granularity (A1 asymmetry) with honestly-missing surplus (no per-agg FIT
    # device utility exists — fit_baseline returns only the aggregate).
    @test nrow(res.household_bills) == 3 * 2 + 1
    for t in ("dadp", "flat", "tou")
        rows = filter(r -> r.tariff == t, eachrow(res.household_bills))
        @test length(rows) == 2
        @test all(r.granularity == "house" for r in rows)
        @test all(isfinite(r.bill) for r in rows)
        @test all(isfinite(r.surplus) for r in rows)
    end
    fit_rows = filter(r -> r.tariff == "fit", eachrow(res.household_bills))
    @test length(fit_rows) == 1
    @test fit_rows[1].granularity == "bus"
    @test isfinite(fit_rows[1].bill)
    @test ismissing(fit_rows[1].surplus)

    # equity_breakouts is non-empty (structure pinned by its own item below).
    @test nrow(res.equity_breakouts) > 0

    # Guards (T-41-19) — each a loud ArgumentError BEFORE any solving:
    # unknown engine
    @test_throws ArgumentError compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        engine = :bogus,
    )
    # houses without map_rows
    @test_throws ArgumentError compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        houses = houses,
    )
    # map_rows without houses
    @test_throws ArgumentError compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        map_rows = map_rows,
    )
    # houses/map_rows length mismatch
    @test_throws ArgumentError compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        houses = houses,
        map_rows = map_rows[1:1],
    )
end

@testitem "compare-tariffs: fit-leg wholesale sign matches the ledger convention (BL-01 pin)" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using DataFrames: eachrow
    using JuMP

    # A PURE CONSUMER prosumer (Ppv ≡ 0): the batteryless (A4) FIT dispatch must import
    # its entire fixed load (self = exp = 0, imp = p_h = Pdc = 0.1 > 0 each hour), so the
    # wholesale receipt sum_t λ₀[t]·imp[t] = 40·0.3 = 12 is STRICTLY POSITIVE — the SAME
    # sign the dadp/flat/tou legs report from `led.balances[:wholesale]` and the module
    # header spec names ("wholesale = λ₀ times the aggregate import"). The pre-fix code
    # negated this column (−12), inverting cross-tariff wholesale comparisons.
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    T = 3
    batt = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.0, T))
    agg = Aggregator(2, 0.9, [batt], fill(0.1, T))
    λ₀ = fill(40.0, T)

    res = compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        engine = :centralized,
        bins = [[1, 2], [3]],
    )
    row_of = Dict(r.tariff => r for r in eachrow(res.summary))
    fitr = row_of["fit"]
    @test fitr.status == "ok"
    # The sign pin + the measured magnitude (Ipopt solves imp to ~1e-10 of 0.1, so the
    # magnitude carries a measured band pin, never an invented exact constant).
    @test fitr.wholesale_total > 0
    @test fitr.wholesale_total ≈ 12.0 rtol = 1e-6
    # Internal identities hold bitwise at the fixed sign (same-float arithmetic).
    @test fitr.merchandising_surplus == fitr.dso_total - fitr.wholesale_total
    @test fitr.dso_total == fitr.total_payments
    @test fitr.aggregators_total == -fitr.total_payments
end

@testitem "compare-tariffs: revenue-neutrality echo at the runner level (fairness_total)" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using DataFrames: eachrow
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

    res = compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        engine = :centralized,
        bins = [[1, 2], [3]],
    )
    row_of = Dict(r.tariff => r for r in eachrow(res.summary))

    # The dadp row's fairness echo IS its own settlement: same prices, same quantities.
    # Gate-then-golden: measured bitwise on this fixture (rel 0.0, 2026-10-26, Julia
    # 1.12.5) → floor pin 1e-15.
    @test row_of["dadp"].fairness_total ≈ row_of["dadp"].total_payments rtol = 1e-15

    # THE locked fairness condition carried through the runner: flat and TOU are DERIVED
    # by 41-03's own tested constructors from the SAME input, so they settle the SAME
    # total at the DADP quantities. Gate-then-golden pins (measured 2026-10-26, Julia
    # 1.12.5, this fixture): flat rel gap = 2.8658034134118547e-16 (one ulp at this
    # magnitude — the same value 41-03's direct-fold pin measured) → 10× measured;
    # TOU rel gap = 0.0 (bitwise) → floor pin 1e-15. NEVER an invented constant.
    dadp_total = row_of["dadp"].total_payments
    @info "compare-tariffs fairness echo (2-bus)" dadp_total flat_echo =
        row_of["flat"].fairness_total tou_echo = row_of["tou"].fairness_total
    @test row_of["flat"].fairness_total ≈ dadp_total rtol = 2.8658034134118547e-15
    @test row_of["tou"].fairness_total ≈ dadp_total rtol = 1e-15
end

@testitem "compare-tariffs: equity columns on bills AND surplus + rebound conventions" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using DataFrames: eachrow, nrow
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
    h1 = Aggregator(
        2,
        0.9,
        [PVBattery(2, 0.95, 1.0, 0.25, 0.0, 1.0, 0.5, 1.0, 2.0, 3.0, fill(0.2, T))],
        fill(0.05, T),
    )
    h2 = Aggregator(
        2,
        0.9,
        [PVBattery(2, 0.95, 1.0, 0.35, 0.0, 1.5, 0.7, 1.0, 2.0, 3.0, fill(0.15, T))],
        fill(0.04, T),
    )
    houses = [h1, h2]
    map_rows = [
        (
            house = k,
            bus = 2,
            aggregator = 2,
            device_set = :test_house,
            pv_group = k == 1 ? :pv : :non_pv,
            house_index = k,
        ) for k in 1:2
    ]

    res = compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        engine = :centralized,
        bins = [[1, 2], [3]],
        houses = houses,
        map_rows = map_rows,
    )
    row_of = Dict(r.tariff => r for r in eachrow(res.summary))

    # flat/tou rows carry all four metrics on bills AND surplus — each computable or
    # honestly NaN under its documented convention (never missing, never dropped).
    for t in ("flat", "tou")
        r = row_of[t]
        for c in (
            :gini_bills,
            :gini_surplus,
            :theil_bills,
            :theil_surplus,
            :atkinson_bills,
            :atkinson_surplus,
            :palma_bills,
            :palma_surplus,
        )
            v = getproperty(r, c)
            @test !ismissing(v)
            @test isfinite(v) || isnan(v)
        end
        @test isfinite(r.gini_bills)
        @test !ismissing(r.rebound_amount)
        @test !ismissing(r.rebound_ratio)
    end

    # The dadp leg is the rebound BASELINE: rebound vs itself is 0 by construction
    # (identical floats ⇒ delta ≡ 0 ⇒ no reduction hours ⇒ amount exactly 0.0, ratio NaN).
    @test row_of["dadp"].rebound_amount == 0.0
    @test row_of["dadp"].rebound_ratio === NaN

    # The fit leg: bills-side equity present at bus granularity, surplus-side honestly
    # missing (A1 — fit_baseline exposes no per-aggregator device utility), no rebound
    # (the plan pins rebound to the flat/tou vs dadp pair).
    fitr = row_of["fit"]
    @test isfinite(fitr.gini_bills)
    @test ismissing(fitr.gini_surplus)
    @test ismissing(fitr.palma_surplus)
    @test ismissing(fitr.rebound_amount)
    @test ismissing(fitr.rebound_ratio)
    @test fitr.bills_granularity == "bus"

    # Per-hour rebound detail: flat + tou × T hours.
    @test nrow(res.rebound) == 2 * T
    @test Set(res.rebound.tariff) == Set(["flat", "tou"])
end

@testitem "compare-tariffs: equity breakouts by pv_group / bus / load tercile (synthetic two-house)" tags =
    [:settlement] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using DataFrames: eachrow, nrow
    using JuMP

    # The 41-03 separability fixture's exact two-house construction (identical draw to
    # build_population's primitives) at T = 12 — `_case_a_house`'s Deferrable window
    # `[min(8,T), min(16,T)]` trips its energy-budget guard below T = 9.
    T = 12
    seed = 20260718
    houses = [
        TSODSO._case_a_house(
            2,
            h,
            2,
            seed,
            T;
            load_scale = 0.005,
            pv_scale = 0.03,
            dev_scale = 1.0,
            pv_fraction = 1.0,
        ) for h in 1:2
    ]
    agg = Aggregator(
        2,
        0.90,
        reduce(vcat, [h.devices for h in houses]),
        reduce(+, [h.Pdc for h in houses]),
    )
    feeder = Feeder(
        [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
        [Branch(1, 2, 0.01, 0.02, 10.0)],
        1,
    )
    λ₀ = fill(40.0, T)
    map_rows = [
        (
            house = h,
            bus = 2,
            aggregator = 2,
            device_set = :thermostatic_deferrable_pvbattery,
            pv_group = TSODSO._case_a_pv_group(h, 2, 0.5),
            house_index = h,
        ) for h in 1:2
    ]

    res = compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        [agg];
        T = T,
        λ₀ = λ₀,
        engine = :centralized,
        bins = [[collect(1:6);], [collect(7:12);]],
        houses = houses,
        map_rows = map_rows,
    )

    bo = res.equity_breakouts
    for leg in ("dadp", "flat", "tou")
        rows = filter(r -> r.tariff == leg, eachrow(bo))
        @test !isempty(rows)
        # All three proxy groupings present per house-granularity leg.
        groupings = Set(r.grouping for r in rows)
        @test groupings == Set(["pv_group", "bus", "load_tercile"])
        # The pv_group breakout separates BOTH groups (house 1 :pv, house 2 :non_pv).
        pv_rows = filter(r -> r.grouping == "pv_group", rows)
        @test Set(r.group for r in pv_rows) == Set(["pv", "non_pv"])
        # Every (grouping, metric_kind) block covers both houses exactly.
        for g in groupings, kind in ("bills", "surplus")
            block = filter(r -> r.grouping == g && r.metric_kind == kind, rows)
            @test sum(r.n for r in block) == 2
        end
    end
    # A1 asymmetry: the batteryless fit leg emits NO house-granularity breakout rows.
    @test count(==("fit"), bo.tariff) == 0
end

@testitem "compare-tariffs: IEEE-13 ground four-leg run (centralized, T=24) — statuses populated, no throw" tags =
    [:settlement, :slow] setup = [IEEE13Fixtures] begin
    using TSODSO
    using DataFrames: eachrow, nrow

    feeder = ieee13_modified()
    aggs = IEEE13Fixtures.build_ieee13_ground_aggregators(feeder)
    T = IEEE13Fixtures.T
    λ₀ = IEEE13Fixtures.mem_price_profile()

    res = compare_tariffs(
        feeder,
        ConvexBranchFlow(),
        aggs;
        T = T,
        λ₀ = λ₀,
        engine = :centralized,
    )

    # Four rows, fixed leg order, no leg dropped — even when a leg fails.
    @test nrow(res.summary) == 4
    @test res.summary.tariff == ["dadp", "flat", "tou", "fit"]
    row_of = Dict(r.tariff => r for r in eachrow(res.summary))

    # dadp/flat/tou: fully certified rows — populated feasibility statuses, finite
    # welfare/MS/payments, bus-granularity bills (no houses on this fixture).
    for t in ("dadp", "flat", "tou")
        r = row_of[t]
        @test r.status == "ok"
        @test r.feasibility_status in ("feasible", "infeasible", "solve_failed")
        @test isfinite(r.welfare)
        @test isfinite(r.merchandising_surplus)
        @test isfinite(r.total_payments)
        @test r.bills_granularity == "bus"
    end
    @test nrow(res.household_bills) == 3 * length(aggs)   # fit leg infeasible ⇒ no FIT bill rows

    # THE FIT LEG'S MEASURED OUTCOME ON THIS FIXTURE (honesty policy, legs never dropped):
    # the batteryless (A4) FIT dispatch is genuinely INFEASIBLE against the
    # congestion-calibrated head branch (smax = 0.0686 pu) — the seed SOC solve terminates
    # PRIMAL_INFEASIBLE with a certificate. Attributed by probe 2026-10-26: lifting ONLY the
    # head branch to SMAX_NO_LIMIT makes fit_baseline converge (welfare -4822.1488652716525,
    # SITE-2 ac_status LOCALLY_SOLVED) — the thermal rating is the binding constraint, not a
    # solver flake. The runner RECORDS this as an honest status row with the non-certified
    # values missing; it never crashes and never drops the leg.
    fitr = row_of["fit"]
    @test fitr.status != "ok"
    @test fitr.status in (
        "error:SolveFailedError",
        "error:CertificateError",
        "error:ConvergenceError",
        "fit_inexact",
    )
    @test !isempty(fitr.notes)
    @test ismissing(fitr.welfare)
    @test ismissing(fitr.merchandising_surplus)
    @test ismissing(fitr.total_payments)
    @test fitr.feasibility_status == "not_run"
end

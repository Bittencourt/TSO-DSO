# src/pricing/fit.jl
#
# SEAM: feed-in-tariff (FIT) baseline counterfactual (PRICE-03, the baseline half).
# OWNER: plan 05-03.
#
# The ONE genuinely-new optimization of Phase 5: the thesis-faithful FIT-OPT
# (thesis eqs. 3.24-3.28) + a plain AC power flow, used as the welfare BASELINE the
# dynamic-pricing (DADP) solve is compared against to produce the headline +25%
# social-welfare ratio (thesis Case A, page 98). Unlike the rest of `src/pricing/`
# (pure post-processing over a solved ctx), this file BUILDS and SOLVES models — but
# it is a SELF-CONTAINED counterfactual: it never touches the Phase-4 seam and routes
# every solve through `select_optimizer(problem_class(pf))` (INFRA-02, no concrete
# solver named), gated on `assert_solved!`.
#
# The FIT counterfactual is thesis-faithful in three deliberate ways (Assumption A4):
#   1. NO battery — the per-prosumer schedule reuses PV + flexible loads but DROPS the
#      PVBattery storage (only its PV availability `Ppv` is retained as generation).
#   2. FIXED German-FIT prices (page 93) — self-consumption at `FIT_λ_SELF`, exported
#      surplus at `FIT_λ_EXPORT`, residual import at `FIT_λ_IMPORT`, kept in the SAME
#      ¢$/kWh unit as `mem_price_profile()` / λ₀ (RESEARCH Pitfall 5, no second unit).
#   3. VOLTAGE LIMITS NOT ENFORCED — the aggregated schedule is evaluated on a plain AC
#      power flow (the thesis "AC-PF, observe 3.35 not enforced" step). We reuse the
#      exact `ConvexBranchFlow` DistFlow model but on a voltage-RELAXED copy of the
#      feeder (bounds widened to the per-unit sanity band [0.8, 1.2], the maximal
#      relaxation `assert_magnitudes` permits without editing the PF formulation), so
#      the original tighter voltage limit does not bind (RESEARCH Open Q3).

using JuMP

# German-FIT price triple (thesis page 93), in ¢$/kWh — the SAME monetary unit as the
# MEM price profile / λ₀ and the device utility coefficients (RESEARCH Pitfall 5; a
# second unit would scale a surplus by 10×/100×). Named module constants so the
# baseline calibration is auditable (threat T-05-04): a mis-specified FIT price silently
# inflates/deflates the +25% headline.
const FIT_λ_IMPORT = 6.6   # residual import from the grid  (λ_im, page 93)
const FIT_λ_EXPORT = 9.6   # exported PV surplus to the grid (λ_e,  page 93)
const FIT_λ_SELF = 5.6     # self-consumed PV                (λ_s,  page 93)

"""
    _fit_pv_and_flex(agg, ctx; T) -> (; Ppv, consumption, utility, flex_vars)

Split an aggregator's member devices into the FIT-OPT ingredients (Assumption A4, thesis
eqs. 3.24-3.28): retain the PV AVAILABILITY of any `PVBattery` (its `Ppv` profile — the
generation source) but DROP the battery storage, and reuse every OTHER (flexible-load)
device by driving its `contribute!` on `ctx.model`.

Returns, over `t = 1:T`:
- `Ppv::Vector{Float64}`      — summed PV availability of the aggregator's PVBatteries
  (a fixed parameter; the battery's charge/discharge/SOC dynamics are omitted, A4);
- `consumption::Vector{AffExpr}` — the flexible-load draw `Σ_dev (−p_inject_dev)` (each
  flexible device injects a NEGATIVE active power, so `−p_inject` is its consumption);
- `utility::QuadExpr`         — the summed concave device utility of the flexible loads;
- `flex_vars::Vector`         — the flexible-device variable stashes (for inspection).

A PVBattery contributes ONLY its `Ppv` here — `contribute!` is deliberately NOT called on
it, so no storage variable/constraint enters the FIT-OPT (the thesis FIT prosumer has PV +
flexible loads but no battery).
"""
function _fit_pv_and_flex(agg::Aggregator, ctx::ModelContext; T::Int)
    Ppv = zeros(Float64, T)
    consumption = AffExpr[zero(AffExpr) for _ in 1:T]
    utility = zero(QuadExpr)
    flex_vars = Any[]
    for d in agg.devices
        if d isa PVBattery
            # Retain PV availability ONLY; DROP the storage (Assumption A4). The PVBattery
            # bundles PV + battery — the FIT prosumer keeps the PV generation and discards
            # the storage arbitrage.
            length(d.Ppv) >= T || throw(
                ArgumentError(
                    "PVBattery.Ppv length $(length(d.Ppv)) < horizon T=$T " *
                    "(FIT-OPT PV availability, thesis 3.24)",
                ),
            )
            for t in 1:T
                Ppv[t] += d.Ppv[t]
            end
        else
            # A flexible load (Deferrable / Thermostatic / Interruptible): reuse its
            # aggregatable builder. Its `p_inject` is a NEGATIVE injection (a load), so
            # `−p_inject` is the consumption that enters `p_h` below.
            res = contribute!(d, ctx; T = T)
            for t in 1:T
                consumption[t] += -res.p_inject[t]
            end
            utility += res.utility
            push!(flex_vars, res.vars)
        end
    end
    return (; Ppv, consumption, utility, flex_vars)
end

"""
    _fit_opt_solve(aggregators; T, λ_import, λ_export, λ_self, optimizer)
        -> (; ctx, per_agg, total_utility, prosumer_surplus)

Build and solve the per-prosumer FIT-OPT schedule (thesis eqs. 3.24-3.28) as ONE convex
(QP) model — the prosumers are decoupled (no network in the FIT-OPT, thesis 3.24), so a
single model with a separable objective is their joint optimum.

For each aggregator it introduces the THREE German-FIT flow variables per hour — self-
consumption `self[t] ≥ 0`, export `exp[t] ≥ 0`, import `imp[t] ≥ 0` — tied to the flexible
load `p_h[t] = P_dc[t] + Σ_flex consumption[t]` and the PV availability `Ppv[t]` by the
import/self-consume/export split (thesis eqs. 3.25-3.27):

    self[t] + imp[t] == p_h[t]      # load served by self-consumption + import (3.25/3.26)
    self[t] + exp[t] == Ppv[t]      # PV split into self-consumption + export   (3.27)

Both flow identities are EXACT structural equalities, and `imp, exp, self ≥ 0` reproduce
`self ≤ min(Ppv, p_h)` (the `max/min` split of 3.25-3.27) WITHOUT a nonconvex `min`.

It maximizes the prosumer FIT SURPLUS (thesis 3.24) — device utility plus the FIT
settlement, valuing self-consumption at `λ_self`, export revenue at `λ_export`, import cost
at `λ_import`:

    Σ_j [ U_flex,j  +  Σ_t ( λ_self·self + λ_export·exp − λ_import·imp ) ]

Routes through the passed `optimizer` (a `select_optimizer(...)` factory — never a named
solver) and gates on `assert_solved!` before reading any value. Returns the solved ctx and,
per aggregator, the numeric FIT schedule (`Ppv, p_h, self, imp, exp`, the net grid injection
`net = exp − imp = Ppv − p_h`, and the realized device utility).
"""
function _fit_opt_solve(
    aggregators;
    T::Int,
    λ_import::Real = FIT_λ_IMPORT,
    λ_export::Real = FIT_λ_EXPORT,
    λ_self::Real = FIT_λ_SELF,
    optimizer,
)
    isempty(aggregators) &&
        throw(ArgumentError("fit_baseline needs at least one aggregator (thesis 3.24)"))

    model = Model(optimizer)
    ctx = ModelContext(model)
    ctx.meta[:T] = T

    surplus = zero(QuadExpr)          # Σ prosumer FIT surplus (the objective, thesis 3.24)
    total_utility = zero(QuadExpr)    # Σ flexible-device utility (the welfare-relevant part)
    built = Vector{NamedTuple}(undef, length(aggregators))

    for (k, agg) in enumerate(aggregators)
        length(agg.Pdc) >= T || throw(
            ArgumentError(
                "Aggregator Pdc length $(length(agg.Pdc)) < horizon T=$T (FIT-OPT load)",
            ),
        )
        pv_flex = _fit_pv_and_flex(agg, ctx; T = T)

        # Total prosumer load p_h[t] = inelastic demand + flexible-load draw (thesis 3.25).
        p_h = AffExpr[agg.Pdc[t] + pv_flex.consumption[t] for t in 1:T]

        # The three German-FIT flows (thesis 3.25-3.27), all non-negative.
        self = @variable(model, [t = 1:T], lower_bound = 0.0, base_name = "self_$k")
        imp = @variable(model, [t = 1:T], lower_bound = 0.0, base_name = "imp_$k")
        exp = @variable(model, [t = 1:T], lower_bound = 0.0, base_name = "exp_$k")

        # Import/self-consume/export split (3.25-3.27). The two equalities + non-negativity
        # reproduce `self ≤ min(Ppv, p_h)` without a nonconvex min.
        @constraint(model, [t = 1:T], self[t] + imp[t] == p_h[t])          # (3.25/3.26)
        @constraint(model, [t = 1:T], self[t] + exp[t] == pv_flex.Ppv[t])  # (3.27)

        # Prosumer FIT surplus (thesis 3.24): device utility + FIT settlement.
        fit_money = sum(
            λ_self * self[t] + λ_export * exp[t] - λ_import * imp[t] for t in 1:T
        )
        surplus += pv_flex.utility + fit_money
        total_utility += pv_flex.utility

        built[k] = (; bus = agg.bus, φ = agg.φ, Pdc = agg.Pdc, Ppv = pv_flex.Ppv,
            p_h, self, imp, exp)
    end

    @objective(model, Max, surplus)

    # OPTIMAL gate before any value is read (no dual is consumed here — the FIT flows carry
    # no price we recover, so `dual = false`).
    assert_solved!(model; dual = false)

    # Read the numeric FIT schedule per aggregator.
    per_agg = map(built) do b
        self_v = value.(b.self)
        imp_v = value.(b.imp)
        exp_v = value.(b.exp)
        p_h_v = [value(b.p_h[t]) for t in 1:T]
        net = exp_v .- imp_v                        # net grid injection = Ppv − p_h (3.22)
        return (; bus = b.bus, φ = b.φ, Pdc = b.Pdc, Ppv = b.Ppv,
            p_h = p_h_v, self = self_v, imp = imp_v, exp = exp_v, net)
    end

    return (;
        ctx,
        per_agg,
        total_utility = value(total_utility),
        prosumer_surplus = objective_value(model),
    )
end

"""
    _relax_voltage(feeder) -> Feeder

Return a voltage-RELAXED copy of `feeder` for the FIT plain AC power flow: every bus keeps
its id / root flag but its voltage band is widened to the per-unit sanity band
`[VOLTAGE_PU_MIN, VOLTAGE_PU_MAX]` = `[0.8, 1.2]` — the widest `assert_magnitudes` permits.
This is how the FIT AC-PF "does NOT enforce the voltage limit" (thesis eq. 3.35 observed but
not enforced, RESEARCH Open Q3) WITHOUT editing `ConvexBranchFlow` (which reads the bounds
from the feeder): the original tighter limit is replaced by a band so wide it does not bind
on the baseline schedule. Branches (impedance / thermal limit) are unchanged.
"""
function _relax_voltage(feeder)
    buses = [Bus(b.id, VOLTAGE_PU_MIN, VOLTAGE_PU_MAX, b.is_root) for b in feeder.buses]
    return Feeder(buses, feeder.branches, feeder.root)
end

"""
    fit_baseline(feeder, pf, aggregators; T=24, λ_fit=FIT_λ_IMPORT, λ₀=fill(λ_fit, T),
                 λ_import=FIT_λ_IMPORT, λ_export=FIT_λ_EXPORT, λ_self=FIT_λ_SELF, seed=nothing)
        -> (; ctx, social_fit, welfare, ratio, prosumer_surplus, fit_flows)

The FIT (feed-in-tariff) baseline counterfactual (PRICE-03) — the ONE new solve of Phase 5.
It (1) solves the per-prosumer FIT-OPT schedule (thesis eqs. 3.24-3.28) under the FIXED
German-FIT prices with PV + flexible loads and NO battery (Assumption A4), (2) aggregates
each prosumer's net injection to its nodal bus (thesis eqs. 3.22-3.23), and (3) evaluates a
plain AC power flow — reusing `ConvexBranchFlow` on a voltage-RELAXED feeder so the voltage
limit (3.35) is NOT enforced (the thesis FIT "AC-PF" step, RESEARCH Open Q3). Every solve
routes through `select_optimizer(problem_class(pf))` (INFRA-02, no concrete solver named) and
is gated on `assert_solved!`.

Returns a `NamedTuple`:
- `ctx`              — the solved FIT AC-PF `ModelContext` (the baseline ctx; structurally
  DISTINCT from the DADP welfare ctx — no battery, voltage limit relaxed);
- `social_fit`       — the FIT SOCIAL WELFARE: `Σ_j U_flex,j − Σ_t λ₀[t]·p_import[t]` (the
  same welfare functional as the DADP solve, thesis eq. 3.38, evaluated on the FIT schedule;
  the internal FIT transfers cancel in social welfare, leaving utility minus the true MEM
  cost of the imported net energy + losses). This is the DENOMINATOR of the +25% headline
  ratio the welfare-accounting plan (05-05) reports;
- `welfare`          — alias of `social_fit`;
- `ratio`            — an efficiency indicator `social_DADP / social_fit`, where `social_DADP`
  is the dynamic-pricing optimum from `solve_welfare` on the SAME scenario (thesis Case A ≈
  1.25). The AUTHORITATIVE +25% ratio is (re)computed by 05-05 against the real DADP ctx;
  this is the self-contained cross-check the FIT baseline reports;
- `prosumer_surplus` — the FIT-OPT objective (Σ prosumer FIT surplus, thesis 3.24);
- `fit_flows`        — per-aggregator numeric FIT schedule (`Ppv, p_h, self, imp, exp, net`).

Reproducibility (INFRA-04, threat T-05-09): the whole computation is DETERMINISTIC in its
inputs; when the `aggregators` are built from seeded `generate_profiles(seed=…)`, two calls
with the same seed return an identical `social_fit`. `seed` is accepted for provenance.

Throws `ArgumentError` on empty `aggregators` or a `λ₀` length ≠ `T`, and `error`s if the
resulting `social_fit`/`ratio` is non-finite or out of the magnitude-sanity band (a mis-
specified baseline must fail loudly rather than silently skew the headline — threat T-05-04).
"""
function fit_baseline(
    feeder,
    pf::AbstractPowerFlow,
    aggregators;
    T::Int = 24,
    λ_fit::Real = FIT_λ_IMPORT,
    λ₀ = fill(float(λ_fit), T),
    λ_import::Real = FIT_λ_IMPORT,
    λ_export::Real = FIT_λ_EXPORT,
    λ_self::Real = FIT_λ_SELF,
    seed = nothing,
)
    isempty(aggregators) &&
        throw(ArgumentError("fit_baseline needs at least one aggregator (thesis 3.24)"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
    seed === nothing || @debug "fit_baseline: profiles are seeded upstream by the caller " *
                               "(generate_profiles(seed=$seed)); the FIT solve is deterministic"

    # (1) Per-prosumer FIT-OPT schedule (thesis 3.24-3.28) — the solver is chosen by the
    # formulation's problem class, never named (INFRA-02).
    fa = _fit_opt_solve(
        aggregators;
        T = T,
        λ_import = λ_import,
        λ_export = λ_export,
        λ_self = λ_self,
        optimizer = select_optimizer(problem_class(pf)),
    )

    # (2)+(3) Aggregate the net injections (3.22-3.23) and evaluate a plain AC power flow on
    # the voltage-RELAXED feeder (3.35 NOT enforced — RESEARCH Open Q3).
    relaxed = _relax_voltage(feeder)
    model = Model(select_optimizer(problem_class(pf)))
    ctx = ModelContext(model)
    ctx.meta[:feeder] = relaxed
    ctx.meta[:T] = T
    ctx.meta[:fit_baseline] = true      # marks this ctx as the FIT counterfactual (not DADP)

    Np = length(relaxed.buses)

    # Formulation writes branch/voltage terms into :Rp/:Rq (voltage bounds are the relaxed
    # band, so 3.35 does not bind — the FIT "AC-PF, observe 3.35 not enforced" step).
    contribute!(pf, ctx, relaxed; T = T)
    reactive = haskey(ctx.residuals, :Rq)

    # Fix each aggregator's FIT net injection at its bus (3.22) and its power-factor reactive
    # draw (3.23) — both NUMERIC constants from the FIT-OPT solve.
    for a in fa.per_agg
        1 <= a.bus <= Np || throw(
            ArgumentError("aggregator bus=$(a.bus) outside feeder buses 1:$Np"),
        )
        tanφ = sqrt(1 - a.φ^2) / a.φ            # tan(arccos φ) (thesis 3.23)
        for t in 1:T
            add_to_residual!(ctx, :Rp, a.bus, t, a.net[t])          # net active (3.22)
            if reactive
                add_to_residual!(ctx, :Rq, a.bus, t, -a.Pdc[t] * tanφ)  # reactive (3.23)
            end
        end
    end

    # Priced free-sign frontier exchange at the root (buy > 0 / sell < 0), which closes the
    # active balance and, priced at λ₀, drives the loss current down so the DistFlow SOC is a
    # genuine AC power flow (the same export-as-loss-penalty mechanism as the DADP solve).
    @variable(model, p_import[t = 1:T])
    for t in 1:T
        add_to_residual!(ctx, :Rp, relaxed.root, t, p_import[t])
    end
    ctx.meta[:p_import] = p_import
    if reactive
        @variable(model, q_import[t = 1:T])   # free-sign reactive frontier
        for t in 1:T
            add_to_residual!(ctx, :Rq, relaxed.root, t, q_import[t])
        end
        ctx.meta[:q_import] = q_import
    end

    # Close the nodal balances (register so the ctx exposes :balance_p like a normal solve).
    @constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
    register_constraint!(ctx, :balance_p, balance_p)
    if reactive
        @constraint(model, balance_q[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
        register_constraint!(ctx, :balance_q, balance_q)
    end

    # A plain AC-PF: minimize the MEM import cost (= net import + losses) so the SOC cone is
    # tight and the flow is physical. Max −λ₀ᵀ p_import (sign-correct for buy/sell).
    @objective(model, Max, -sum(λ₀[t] * p_import[t] for t in 1:T))
    assert_solved!(model; dual = false)

    imports = value.(p_import)

    # FIT social welfare (thesis 3.38, evaluated on the FIT schedule): flexible-device utility
    # minus the true MEM cost of the net imported energy + losses. The internal FIT transfers
    # (λ_self/λ_export/λ_import) cancel in SOCIAL welfare, so only utility − λ₀ᵀ·import remains.
    social_fit = fa.total_utility - sum(λ₀[t] * imports[t] for t in 1:T)

    # Magnitude-sanity guard (threat T-05-04 / Pitfall 5): a non-finite or wildly out-of-band
    # welfare means a unit slip or a mis-specified baseline — fail loudly, never skew the
    # headline silently. The band is generous (per-unit prices × horizon × buses).
    isfinite(social_fit) || error("fit_baseline: social_fit is non-finite ($social_fit)")
    band = PRICE_MAX * (Np + 1) * T
    abs(social_fit) < band || error(
        "fit_baseline: social_fit=$social_fit out of magnitude-sanity band ±$band " *
        "(¢\$/kWh-consistent, thesis 3.38; possible unit slip — Pitfall 5)",
    )

    # Efficiency ratio social_DADP / social_fit (thesis Case A ≈ 1.25): the dynamic-pricing
    # optimum on the SAME scenario, from the centralized welfare solve (allow_export = true is
    # the SOC-exactness enabler in the reverse-flow regime, PF-04). It is solved on the SAME
    # voltage-relaxed network as the FIT AC-PF so the two welfares are directly comparable and
    # the reference always stays feasible (a tighter DADP voltage limit could make the heavy-
    # load reference infeasible). The AUTHORITATIVE +25% ratio is recomputed by 05-05 against
    # the real DADP ctx; this is the FIT baseline's self-contained cross-check.
    _, social_dadp, _ = solve_welfare(relaxed, pf, aggregators; T = T, λ₀ = λ₀,
        allow_export = true)
    abs(social_fit) > eps(Float64) || error(
        "fit_baseline: social_fit≈0 — cannot form the efficiency ratio (degenerate baseline)",
    )
    ratio = social_dadp / social_fit
    isfinite(ratio) || error("fit_baseline: efficiency ratio is non-finite ($ratio)")

    return (;
        ctx,
        social_fit,
        welfare = social_fit,
        ratio,
        prosumer_surplus = fa.prosumer_surplus,
        fit_flows = fa.per_agg,
    )
end

export fit_baseline, FIT_λ_IMPORT, FIT_λ_EXPORT, FIT_λ_SELF

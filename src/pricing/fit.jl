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
#      power flow (the thesis "AC-PF, observe 3.35 not enforced" step; added in Task 2).

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

export FIT_λ_IMPORT, FIT_λ_EXPORT, FIT_λ_SELF

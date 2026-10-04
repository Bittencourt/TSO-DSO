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

# FIX-09 (Phase 27, plan 27-05; T-27-13/T-27-14): the measured, NAMED gap-bound for the
# SITE-3 nested `solve_welfare` cross-check's bounded `ALMOST_OPTIMAL` fallback.
#
# ROOT-CAUSE PROTOCOL (the untried `max_iter` hypothesis, RESEARCH FIX-09 / Pitfall FIX-09-1):
# `scripts/repro_stability_check.jl`'s `REPRO_MAX_ITER` env var was run at `REPRO_TOL_GAP=1e-10`
# against `max_iter ∈ {200 (default), 400, 2000}` on the documented flaking fixture (the
# Phase-17-retuned IEEE-123 population point). Clarabel's OWN printed iteration trace is
# BYTE-IDENTICAL across all three `max_iter` values — every run terminates at iteration 24
# with `status = solved (reduced accuracy)` (`ALMOST_OPTIMAL`/`NEARLY_FEASIBLE_POINT`), and
# iterations 23-24 show IDENTICAL `pcost`/`dcost`/`gap`/`pres`/`dres` (a genuine STALL, not a
# budget exhaustion — `max_iter=2000` never comes close to being reached). This CONCLUSIVELY
# REFUTES the slow-convergence hypothesis: raising `max_iter` has ZERO effect. The flake is a
# genuine Clarabel numerical-precision conditioning wall at this tight `tol_gap`, matching the
# prior IEEE-8500 precedent (quick task `260822-hld`) — CONTEXT's locked fallback therefore
# applies: bound `ALMOST_OPTIMAL` acceptance behind a measured, named gap tolerance. Full
# iteration traces and the measurement protocol are recorded in `27-FINDINGS.md`.
#
# MEASURED (2026-09-29), same fixture/tolerance, using `solve_welfare(...; allow_almost=true)`
# to reach the near-feasible point and reading Clarabel's OWN certified primal/dual objective
# gap directly (`abs(objective_value(model) - dual_objective_value(model))` — no second
# reference solve needed, mirroring `KNOWN_OPTIMUM_ATOL`'s protocol, `benders.jl:35-60`):
#   objective_value      = -41035.40436349072
#   dual_objective_value = -41035.40435574188
#   gap_measured          = 7.74884392740205e-6
# Per the measurement formula `10 * gap_measured` (KNOWN_OPTIMUM_ATOL's own 10x-margin
# convention), the bound is set to the measured value below, not a hopeful guess. The SAME
# near-feasible point's cone residual (`ctx.meta[:socp_maxgap] = 9.466352679510237e-8`)
# independently PASSES `assert_socp_exact!`'s hybrid floor (FIX-08) with a comfortable margin —
# confirming this specific ALMOST_OPTIMAL point is genuinely cone-exact, only the interior-point
# duality gap itself sits fractionally above `tol_gap=1e-10`.
const FIT_SITE3_ALMOST_GAP_TOL = 7.74884392740205e-5

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
    ctx.T = T

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
        fit_money =
            sum(λ_self * self[t] + λ_export * exp[t] - λ_import * imp[t] for t in 1:T)
        surplus += pv_flex.utility + fit_money
        total_utility += pv_flex.utility

        built[k] = (;
            bus = agg.bus,
            φ = agg.φ,
            Pdc = agg.Pdc,
            Ppv = pv_flex.Ppv,
            p_h,
            self,
            imp,
            exp,
        )
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
        return (;
            bus = b.bus,
            φ = b.φ,
            Pdc = b.Pdc,
            Ppv = b.Ppv,
            p_h = p_h_v,
            self = self_v,
            imp = imp_v,
            exp = exp_v,
            net,
        )
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
                 λ_import=FIT_λ_IMPORT, λ_export=FIT_λ_EXPORT, λ_self=FIT_λ_SELF,
                 optimizer=select_optimizer(problem_class(pf)), on_inexact::Symbol=:error,
                 seed=nothing)
        -> (; ctx, social_fit, welfare, ratio, prosumer_surplus, fit_flows, socp_maxgap,
             ac_status, ac_violations)

The FIT (feed-in-tariff) baseline counterfactual (PRICE-03) — the ONE new solve of Phase 5.
It (1) solves the per-prosumer FIT-OPT schedule (thesis eqs. 3.24-3.28) under the FIXED
German-FIT prices with PV + flexible loads and NO battery (Assumption A4), (2) aggregates
each prosumer's net injection to its nodal bus (thesis eqs. 3.22-3.23), and (3) evaluates a
genuine AC power flow — the thesis FIT "AC-PF" step, RESEARCH Open Q3 — on a voltage-RELAXED
feeder so the voltage limit (3.35) is NOT enforced.

**FIX-09 (Phase 27, plan 27-05) gated SITE 2 on `assert_socp_exact!`; plan 27-09 (USER
DECISION 2026-09-29) REPLACES that gated SOC re-solve with a genuine AC power flow, PHYSICS
ONLY.** Despite its "plain AC power flow" naming, SITE 2's fixed-dispatch step was, before
27-09, a GENUINE SOC relaxation whenever `pf` stashes a squared-current `:l` (i.e.
`ConvexBranchFlow`, the only formulation this file is exercised with in practice) — plan 27-05
found this could be silently inexact; plan 27-09 found it is STRUCTURALLY inexact on the
IEEE-123 REPRO-01 point (measured gap≈211, ratio≈9993, `27-wave2-suite.log`), because FIXING
every injection leaves the loss current `l` free with no objective term able to pin it (unlike
a genuine welfare solve, where the network itself chooses `l`). SITE 2 now (plan 27-09):

  1. Solves the ORIGINAL fixed-dispatch model on `pf` — UNCHANGED code — but ONLY as a
     warm-start SEED for step 2 (its own exactness is irrelevant; it is discarded).
  2. When `pf` has a cone (`:l` stashed), builds a FRESH `ACPowerFlow(; limits = false)`
     model (Ipopt) with the IDENTICAL fixed injections, warm-started from step 1's own solved
     `P`/`Q`/`l`/`v` (26-15's documented remedy for Ipopt's degenerate all-zero-start KKT
     point, `src/experiments/mpc_loop.jl`'s `_mpc_truth_import_acpf` uses the SAME idiom).
     `limits = false` means `:smax`/`:smax_rev`/the operating voltage band are OMITTED — the
     settlement requires only that a genuine AC solution EXISTS, never that it also respect an
     operating limit (any violation is REPORTED via `ac_violations`, never refused).
  3. When `pf` has no cone (DC/LinDistFlow, no `:l` stashed), step 1's own solve IS the final
     settlement — BYTE-IDENTICAL to pre-27-09 behavior (data-driven, no `if formulation ==`
     branching, mirroring `solve_welfare`'s own `has_branch_current(ctx.pf)` gate).

`on_inexact::Symbol` is now the REPORTING switch for a genuine AC non-convergence at step 2
(mirroring the project-standard `on_violation` idiom, `assert_battery_complementarity!`,
`src/models/welfare_solve.jl:284,345-348`):

  - `:error` (default) — throws a loud `ErrorException` naming the full Ipopt solve status if
    step 2 fails to reach `LOCALLY_SOLVED`/`OPTIMAL` (`ALMOST_LOCALLY_SOLVED` is TREATED AS A
    FAILURE, never silently accepted) — refusing the counterfactual outright.
  - `:report` — never throws on a step-2 non-convergence; returns EARLY with
    `social_fit`/`welfare`/`ratio` all `NaN` (never reads a value off a non-converged model)
    and `ac_status` set to the measured `termination_status` — the diagnostic replaces the
    trustworthy welfare number rather than accompanying it.
  - any other value raises a loud `ArgumentError` (project's universal invalid-kwarg convention).

On a genuinely-converged SITE-2 AC solve (the common case), every OTHER `fit_baseline`
behavior — `social_fit`, `ratio`, `prosumer_surplus`, `fit_flows` — proceeds normally; the new
`ac_status`/`ac_violations` fields are additive.

Every solve routes through the `optimizer` keyword, which DEFAULTS to
`select_optimizer(problem_class(pf))` — so INFRA-02 holds (no concrete solver is ever named here,
and the default is the factory), while a caller may supply a differently-CONDITIONED factory for
the same problem class. It drives the per-prosumer FIT-OPT, step 1's warm-start seed, and the
nested `solve_welfare` that forms the efficiency `ratio`. Step 2's AC-PF is a DIFFERENT problem
class (NLP, not SOCP/QP) and is driven by the SEPARATE internal test seam `_site2_ac_optimizer`
(defaults to `select_optimizer(problem_class(ACPowerFlow()))`; production callers never set
this — see that kwarg's own doc comment) — a caller-tuned Clarabel `tol_gap` cannot meaningfully
condition an Ipopt solve. Every solve is gated on `assert_solved!` (step 1, SITE 1, SITE 3) or
`is_solved_and_feasible(...; allow_local=true, allow_almost=false)` (step 2, AC).

Why the `optimizer` kwarg exists (spike 003, `.planning/spikes/003-phase18-fragility-tolerance/`):
the nested `solve_welfare` carries its own PF-04 exactness gate (`assert_socp_exact!`), whose
`atol = 1e-6` sits at Clarabel's achievable cone residual on a large feeder at the default
`tol_gap = 1e-8`. Without a way to tighten the solver, that gate can refuse prices for purely
numerical reasons and the caller has no recourse. Passing e.g.
`optimizer_with_attributes(Clarabel.Optimizer, "tol_gap_abs" => 1e-10, "tol_gap_rel" => 1e-10)`
converges the cone properly at an unchanged optimum.

**FIX-09 root-caused, bounded `ALMOST_OPTIMAL` fallback on SITE 3 ONLY (Phase 27, plan 27-05;
T-27-13/T-27-14).** At a tightened `tol_gap` (e.g. `1e-10`), the NESTED `solve_welfare` cross-
check has a DOCUMENTED, root-caused intermittent `ALMOST_OPTIMAL` flake on some fixtures — a
measured, genuine Clarabel numerical-precision conditioning wall (confirmed via the `max_iter`
root-cause protocol: Clarabel's OWN iteration trace is BYTE-IDENTICAL at `max_iter ∈ {200, 400,
2000}`, ruling out slow convergence; see [`FIT_SITE3_ALMOST_GAP_TOL`](@ref)'s comment and
`27-FINDINGS.md`). SITE 3 (and ONLY SITE 3) now retries once with `allow_almost = true` on that
SPECIFIC failure class and accepts the near-feasible `social_dadp` ONLY if the retry's OWN
measured primal-dual gap clears the named `FIT_SITE3_ALMOST_GAP_TOL`; otherwise the original
exception still propagates. This is safe because `social_dadp`'s underlying `dadp` (the dual
vector) is NEVER read here — only `objective_value`. SITE 1 and SITE 2 are completely unaffected
(threat T-27-14: the new `allow_almost` kwarg on `solve_welfare` defaults `false` everywhere
else).

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
  - `fit_flows`        — per-aggregator numeric FIT schedule (`Ppv, p_h, self, imp, exp, net`);
  - `socp_maxgap`      — ALWAYS `nothing` as of plan 27-09 (kept for source compatibility with
    plan 27-05 callers) — there is no cone residual to report once SITE 2 is a genuine AC power
    flow; see `ac_status`/`ac_violations` instead;
  - `ac_status`        — (plan 27-09) the measured `termination_status` of SITE 2's AC solve
    when `pf` has a cone, `nothing` when `pf` has none (DC/LinDistFlow, data-driven, no
    formulation branching);
  - `ac_violations`    — (plan 27-09) a length-`T` `Vector` of per-hour thermal/voltage
    DIAGNOSTICS (see [`_fit_ac_settlement_violations`](@ref)) recomputed from SITE 2's own
    solved `P`/`Q`/`l`/`v` — NEVER a gate, `fit_baseline` never refuses the counterfactual for
    exceeding an operating limit. `nothing` when `pf` has no cone, or when `on_inexact =
    :report` caught a genuine AC non-convergence (no solved values to compute it from).

Reproducibility (INFRA-04, threat T-05-09): the whole computation is DETERMINISTIC in its
inputs; when the `aggregators` are built from seeded `generate_profiles(seed=…)`, two calls
with the same seed return an identical `social_fit`. `seed` is accepted for provenance.

Throws `ArgumentError` on empty `aggregators`, a `λ₀` length ≠ `T`, or an invalid `on_inexact`
(neither `:error` nor `:report`); `error`s if the resulting `social_fit`/`ratio` is non-finite or
out of the magnitude-sanity band (a mis-specified baseline must fail loudly rather than silently
skew the headline — threat T-05-04); and (plan 27-09, `on_inexact = :error` only) throws an
`ErrorException` if SITE 2's genuine AC power flow fails to reach `LOCALLY_SOLVED`/`OPTIMAL`
(T-27-12).
"""
function fit_baseline(
    feeder::AbstractFeeder,
    pf::AbstractPowerFlow,
    aggregators;
    T::Int = 24,
    λ_fit::Real = FIT_λ_IMPORT,
    λ₀ = fill(float(λ_fit), T),
    λ_import::Real = FIT_λ_IMPORT,
    λ_export::Real = FIT_λ_EXPORT,
    λ_self::Real = FIT_λ_SELF,
    # Defaults to the SAME factory expression each internal site used before this kwarg
    # existed, so the default path is byte-for-byte unchanged (INFRA-02: still no concrete
    # solver named here). A caller may pass a differently-conditioned factory — see the
    # docstring for why (spike 003: the nested solve_welfare's PF-04 gate).
    optimizer = select_optimizer(problem_class(pf)),
    # FIX-09 (Phase 27, plan 27-05, semantics UPDATED by plan 27-09): SITE 2's own reporting
    # mode — mirrors the project's `on_violation::Symbol` idiom
    # (`assert_battery_complementarity!`). `:error` (default) throws on a genuine SITE-2 AC
    # non-convergence; `:report` returns the diagnostic instead (see docstring). Validated
    # below alongside the function's other boundary guards.
    on_inexact::Symbol = :error,
    # Plan 27-09 (USER DECISION 2026-09-29): SITE 2's AC-PF solver — an INTERNAL TEST SEAM
    # (mirrors `run_mpc`'s own `_truth_settlement` idiom, `src/experiments/mpc_loop.jl`), NOT
    # part of the public API (leading underscore). Defaults to the SAME problem-class factory
    # every production caller gets; a test may override it (e.g. a crippled `max_iter=1`
    # Ipopt) to FORCE a deterministic non-convergence and exercise `on_inexact`'s two branches
    # without relying on a fragile genuine-infeasibility fixture. Production callers never set
    # this. Independent of the `optimizer` kwarg above (which still drives the FIT-OPT seed
    # solve and SITE 3) because SITE 2's AC-PF is a DIFFERENT problem class (NLP, not SOCP) —
    # a caller-tuned Clarabel `tol_gap` cannot meaningfully condition an Ipopt solve.
    _site2_ac_optimizer = select_optimizer(problem_class(ACPowerFlow())),
    seed = nothing,
)
    isempty(aggregators) &&
        throw(ArgumentError("fit_baseline needs at least one aggregator (thesis 3.24)"))
    length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
    on_inexact in (:error, :report) || throw(
        ArgumentError(
            "fit_baseline: invalid on_inexact=$(repr(on_inexact)), expected :error or :report",
        ),
    )
    seed === nothing || @debug "fit_baseline: profiles are seeded upstream by the caller " *
           "(generate_profiles(seed=$seed)); the FIT solve is deterministic"

    # (1) Per-prosumer FIT-OPT schedule (thesis 3.24-3.28) — SITE 1 of 3. The solver comes from
    # the `optimizer` kwarg, which defaults to the problem-class factory (INFRA-02).
    fa = _fit_opt_solve(
        aggregators;
        T = T,
        λ_import = λ_import,
        λ_export = λ_export,
        λ_self = λ_self,
        optimizer = optimizer,
    )

    # (2)+(3) Aggregate the net injections (3.22-3.23) and evaluate a plain AC power flow on
    # the voltage-RELAXED feeder (3.35 NOT enforced — RESEARCH Open Q3).
    relaxed = _relax_voltage(feeder)
    Np = length(relaxed.buses)

    # --- SITE 2 of 3 — the FIT AC-PF ------------------------------------------------------
    # Step (a): the fixed-dispatch solve on `pf` (UNCHANGED code from before plan 27-09) — the
    # SAME model this file has always built here. Plan 27-09 (USER DECISION 2026-09-29)
    # demotes this to a WARM-START SEED whenever `pf` stashes a squared-current `:l`
    # (ConvexBranchFlow, the only formulation this file is exercised with in practice): its OWN
    # exactness is now IRRELEVANT (it is discarded before this function returns) — plan 27-05's
    # `assert_socp_exact!` gate on this exact re-solve was measured GENUINELY, STRUCTURALLY
    # inexact on the IEEE-123 REPRO-01 point (gap≈211, ratio≈9993,
    # `27-wave2-suite.log`) because FIXING every injection leaves the loss current `l` free —
    # there is no relaxation-tightening objective that can pin it, unlike a genuine welfare
    # solve where the network itself chooses `l`. When `pf` has NO cone (DC/LinDistFlow, no
    # `:l` stashed), this step IS the final settlement, data-driven and BYTE-IDENTICAL to
    # pre-27-09 behavior (no cone to be inexact about in the first place).
    seed_model = Model(optimizer)
    seed_ctx = ModelContext(seed_model)
    seed_ctx.feeder = relaxed
    seed_ctx.T = T
    seed_ctx.meta[:fit_baseline] = true

    # Formulation writes branch/voltage terms into :Rp/:Rq (voltage bounds are the relaxed
    # band, so 3.35 does not bind — the FIT "AC-PF, observe 3.35 not enforced" step).
    contribute!(pf, seed_ctx, relaxed; T = T)
    seed_reactive = haskey(seed_ctx.residuals, :Rq)

    # Fix each aggregator's FIT net injection at its bus (3.22) and its power-factor reactive
    # draw (3.23) — both NUMERIC constants from the FIT-OPT solve.
    for a in fa.per_agg
        1 <= a.bus <= Np ||
            throw(ArgumentError("aggregator bus=$(a.bus) outside feeder buses 1:$Np"))
        tanφ = sqrt(1 - a.φ^2) / a.φ            # tan(arccos φ) (thesis 3.23)
        for t in 1:T
            add_to_residual!(seed_ctx, :Rp, a.bus, t, a.net[t])          # net active (3.22)
            if seed_reactive
                add_to_residual!(seed_ctx, :Rq, a.bus, t, -a.Pdc[t] * tanφ)  # reactive (3.23)
            end
        end
    end

    # Priced free-sign frontier exchange at the root (buy > 0 / sell < 0), which closes the
    # active balance and, priced at λ₀, drives the loss current down so the DistFlow SOC is a
    # genuine AC power flow (the same export-as-loss-penalty mechanism as the DADP solve).
    @variable(seed_model, seed_p_import[t = 1:T])
    for t in 1:T
        add_to_residual!(seed_ctx, :Rp, relaxed.root, t, seed_p_import[t])
    end
    seed_ctx.meta[:p_import] = seed_p_import
    if seed_reactive
        @variable(seed_model, seed_q_import[t = 1:T])   # free-sign reactive frontier
        for t in 1:T
            add_to_residual!(seed_ctx, :Rq, relaxed.root, t, seed_q_import[t])
        end
        seed_ctx.meta[:q_import] = seed_q_import
    end

    # Close the nodal balances (register so the ctx exposes :balance_p like a normal solve).
    @constraint(seed_model, balance_p[j = 1:Np, t = 1:T], seed_ctx.residuals[:Rp][j, t] == 0)
    register_constraint!(seed_ctx, :balance_p, balance_p)
    if seed_reactive
        @constraint(
            seed_model,
            balance_q[j = 1:Np, t = 1:T],
            seed_ctx.residuals[:Rq][j, t] == 0
        )
        register_constraint!(seed_ctx, :balance_q, balance_q)
    end

    # A plain AC-PF: minimize the MEM import cost (= net import + losses) so the SOC cone is
    # tight and the flow is physical. Max −λ₀ᵀ p_import (sign-correct for buy/sell).
    @objective(seed_model, Max, -sum(λ₀[t] * seed_p_import[t] for t in 1:T))
    assert_solved!(seed_model; dual = false)

    has_cone = has_branch_current(seed_ctx.pf)

    # Step (b) — plan 27-09 (USER DECISION 2026-09-29): when `pf` has a cone, replace the
    # fixed-dispatch SOC relaxation with a genuine AC power flow, PHYSICS ONLY
    # (`ACPowerFlow(; limits = false)`, Ipopt), warm-started from step (a)'s own solved
    # `P`/`Q`/`l`/`v` (mirroring `_mpc_truth_import_acpf`'s identical remedy for Ipopt's
    # degenerate all-zero-start KKT point, `src/experiments/mpc_loop.jl`, 26-15).
    # `on_inexact` is preserved as the REPORTING switch for AC non-convergence: `:error`
    # (default) throws on a genuine Ipopt non-convergence; `:report` returns a diagnostic
    # instead (never reads a value off a non-converged model).
    socp_maxgap = nothing        # kept nothing whenever there is no cone — UNCHANGED semantics
    ac_status = nothing
    ac_violations = nothing
    ctx = seed_ctx
    p_import = seed_p_import

    if has_cone
        ac = ACPowerFlow(; limits = false)
        model = Model(_site2_ac_optimizer)
        ctx = ModelContext(model)
        ctx.feeder = relaxed
        ctx.T = T
        ctx.meta[:fit_baseline] = true

        contribute!(ac, ctx, relaxed; T = T)
        reactive = haskey(ctx.residuals, :Rq)

        for a in fa.per_agg
            tanφ = sqrt(1 - a.φ^2) / a.φ
            for t in 1:T
                add_to_residual!(ctx, :Rp, a.bus, t, a.net[t])
                reactive && add_to_residual!(ctx, :Rq, a.bus, t, -a.Pdc[t] * tanφ)
            end
        end

        @variable(model, p_import[t = 1:T])
        for t in 1:T
            add_to_residual!(ctx, :Rp, relaxed.root, t, p_import[t])
        end
        ctx.meta[:p_import] = p_import
        if reactive
            @variable(model, q_import[t = 1:T])
            for t in 1:T
                add_to_residual!(ctx, :Rq, relaxed.root, t, q_import[t])
            end
            ctx.meta[:q_import] = q_import
        end

        @constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
        register_constraint!(ctx, :balance_p, balance_p)
        if reactive
            @constraint(model, balance_q[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
            register_constraint!(ctx, :balance_q, balance_q)
        end

        # Warm start every P/Q/l/v/p_import/q_import from step (a)'s own solved point (26-15's
        # documented remedy — Ipopt's default all-zero start is a degenerate KKT point of the
        # unrelaxed `l·v = P²+Q²` equality).
        pv_seed = _require_pf_vars(seed_ctx)
        pv_ac = _require_pf_vars(ctx)
        Bf = relaxed.branches
        for b in eachindex(Bf), t in 1:T
            set_start_value(pv_ac.P[b, t], value(pv_seed.P[b, t]))
            set_start_value(pv_ac.Q[b, t], value(pv_seed.Q[b, t]))
            set_start_value(pv_ac.l[b, t], value(pv_seed.l[b, t]))
        end
        for j in 1:Np, t in 1:T
            j == relaxed.root && continue   # root v is fix()ed to 1.0 already
            set_start_value(pv_ac.v[j, t], value(pv_seed.v[j, t]))
        end
        for t in 1:T
            set_start_value(p_import[t], value(seed_p_import[t]))
            if reactive && seed_reactive
                set_start_value(q_import[t], value(seed_q_import[t]))
            end
        end

        @objective(model, Max, -sum(λ₀[t] * p_import[t] for t in 1:T))
        optimize!(model)

        ok = is_solved_and_feasible(
            model;
            dual = false,
            allow_local = true,
            allow_almost = false,
        )
        ac_status = termination_status(model)

        if !ok
            on_inexact === :error && throw(
                ErrorException(
                    "fit_baseline: FIT AC-PF (SITE 2) FAILED to reach LOCALLY_SOLVED — " *
                    "termination_status=$(termination_status(model)), " *
                    "primal_status=$(primal_status(model)), " *
                    "raw_status=\"$(raw_status(model))\". ALMOST_LOCALLY_SOLVED is TREATED " *
                    "AS A FAILURE, never silently accepted (plan 27-09, USER DECISION " *
                    "2026-09-29) — this is a genuine Ipopt non-convergence at the FIT " *
                    "schedule's fixed dispatch, never a thermal/voltage limit (those are " *
                    "OMITTED from this physics-only model).",
                ),
            )
            # on_inexact === :report: never reads a value off a non-converged model — return
            # the diagnostic (ac_status) instead of a trustworthy social_fit/ratio.
            return (;
                ctx,
                social_fit = NaN,
                welfare = NaN,
                ratio = NaN,
                prosumer_surplus = fa.prosumer_surplus,
                fit_flows = fa.per_agg,
                socp_maxgap = nothing,
                ac_status,
                ac_violations = nothing,
            )
        end

        ac_violations = _fit_ac_settlement_violations(relaxed, _require_pf_vars(ctx), T)
    end

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
    # SITE 3 of 3 — and the one the `optimizer` kwarg mainly exists for: THIS solve carries its own
    # PF-04 exactness gate (assert_socp_exact!), which is what refuses prices on numerical grounds
    # when the solver is under-converged on a large feeder (spike 003).
    #
    # FIX-09 (Phase 27, plan 27-05; T-27-13/T-27-14): a bounded ALMOST_OPTIMAL fallback,
    # NARROWLY SCOPED to this one cross-check. `dadp` is ALWAYS discarded (`_`) below,
    # satisfying `assert_solved!`'s own documented precondition for `allow_almost=true` ("an
    # intermediate re-solve whose DUALS are NOT read"). The root-cause protocol (see
    # `FIT_SITE3_ALMOST_GAP_TOL`'s comment / `27-FINDINGS.md`) CONFIRMED this is a genuine
    # solver-precision conditioning wall, not a slow-convergence issue `max_iter` could fix. On
    # the strict attempt's failure, retry ONCE with `allow_almost = true` ONLY for that SPECIFIC,
    # root-caused failure class (never a genuine INFEASIBLE/boundary-guard error — mirrors
    # `solve_with_retry!`'s RETRYABLE_STATUSES discipline of never retrying a real modeling
    # failure), then accept the near-feasible `objective_value` ONLY if this SAME solve's OWN
    # measured primal-dual gap is under `FIT_SITE3_ALMOST_GAP_TOL` — otherwise the ORIGINAL
    # exception still propagates (never silently trust an unbounded near-feasible point).
    _, social_dadp, _ = try
        solve_welfare(
            relaxed,
            pf,
            aggregators;
            T = T,
            λ₀ = λ₀,
            optimizer = optimizer,
            allow_export = true,
        )
    catch e
        (e isa ErrorException && occursin("ALMOST_OPTIMAL", e.msg)) || rethrow(e)
        retry_ctx, retry_obj, retry_dadp = solve_welfare(
            relaxed,
            pf,
            aggregators;
            T = T,
            λ₀ = λ₀,
            optimizer = optimizer,
            allow_export = true,
            allow_almost = true,
        )
        gap = abs(objective_value(retry_ctx.model) - dual_objective_value(retry_ctx.model))
        gap <= FIT_SITE3_ALMOST_GAP_TOL || rethrow(e)
        (retry_ctx, retry_obj, retry_dadp)
    end
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
        socp_maxgap,
        ac_status,
        ac_violations,
    )
end

"""
    _fit_ac_settlement_violations(feeder, pf_vars::NamedTuple, T::Int) -> Vector{<:NamedTuple}

Internal helper (unexported, Phase 27 FIX-09, plan 27-09 — USER DECISION 2026-09-29): the
FIT-AC-PF analogue of `_mpc_settlement_violations` (`src/experiments/mpc_loop.jl`, FIX-10) —
computes SITE 2's per-hour thermal/voltage DIAGNOSTIC from a SOLVED
[`ACPowerFlow`](@ref)`(; limits = false)` context's own `P`/`Q`/`l`/`v`, never a constraint
dual (there is none to read when `limits = false`). A REPORT, never a gate: `fit_baseline`
never refuses the FIT counterfactual for exceeding an operating limit, it only surfaces one
here via the `ac_violations` field.

For every branch with a real thermal rating (`smax < _SMAX_NO_LIMIT`) and every hour `t = 1:T`,
recomputes the forward apparent power `|S_fwd| = sqrt(P²+Q²)` and the receiving-end apparent
power `|S_rev| = sqrt((P−r·l)²+(Q−x·l)²)` directly from the solved values, and counts a branch
as OVERLOADED at hour `t` whenever `max(|S_fwd|, |S_rev|) / smax > 1`. For every non-root bus,
recovers `|V_j| = sqrt(v_j)` and counts it OUT-OF-BAND whenever it falls outside `[vmin, vmax]`.

Returns a length-`T` `Vector` of `(; t, n_thermal_violations::Int, max_overload_ratio::Float64,
n_voltage_violations::Int, min_voltage::Float64, max_voltage::Float64,
voltage_violated::Bool)` — one entry per hour, mirroring `_mpc_settlement_violations`'s field
set (with `t` in place of `abs_hour`, since SITE 2 has no absolute-hour concept). Deliberately
NOT shared code with `_mpc_settlement_violations` (single-hour `T=1` there, general `T` here) —
kept as two small, independently-readable functions rather than one over-parametrized one.
"""
function _fit_ac_settlement_violations(feeder, pf_vars::NamedTuple, T::Int)
    B = feeder.branches
    Np = length(feeder.buses)
    out = Vector{NamedTuple}(undef, T)
    for t in 1:T
        n_thermal = 0
        max_ratio = 0.0
        for (b, br) in enumerate(B)
            br.smax < _SMAX_NO_LIMIT || continue
            Pb = value(pf_vars.P[b, t])
            Qb = value(pf_vars.Q[b, t])
            lb = value(pf_vars.l[b, t])
            s_fwd = sqrt(Pb^2 + Qb^2)
            s_rev = sqrt((Pb - br.r * lb)^2 + (Qb - br.x * lb)^2)
            ratio = max(s_fwd, s_rev) / br.smax
            ratio > 1.0 && (n_thermal += 1)
            max_ratio = max(max_ratio, ratio)
        end

        n_voltage = 0
        min_v = Inf
        max_v = -Inf
        for j in 1:Np
            j == feeder.root && continue
            vb = feeder.buses[j]
            vj = sqrt(max(value(pf_vars.v[j, t]), 0.0))
            (vj < vb.vmin || vj > vb.vmax) && (n_voltage += 1)
            min_v = min(min_v, vj)
            max_v = max(max_v, vj)
        end

        out[t] = (;
            t,
            n_thermal_violations = n_thermal,
            max_overload_ratio = max_ratio,
            n_voltage_violations = n_voltage,
            min_voltage = min_v,
            max_voltage = max_v,
            voltage_violated = n_voltage > 0,
        )
    end
    return out
end

export fit_baseline, FIT_λ_IMPORT, FIT_λ_EXPORT, FIT_λ_SELF

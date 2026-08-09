# src/experiments/mpc_loop.jl
#
# SEAM: receding-horizon closed-loop orchestrator (MPC-01..04).
# OWNER: plan 21-05.
#
# `run_mpc(s::Scenario)` is an INDEPENDENT entry point — it is NOT wired through
# `run_scenario`/`run.jl`'s `:centralized`/`:admm` `strategy` dispatch (D-01, Pitfall 7);
# that dispatch stays byte-for-byte untouched. It materializes the SAME heavy objects
# `run_scenario` does (feeder/profiles/λ₀/aggregators, `src/experiments/materialize.jl`
# verbatim), solves TWO one-time perfect-foresight day-ahead benchmarks via `solve_welfare`
# (the FULL-population reference and the CR-03 comparable benchmark over the
# Deferrable-excluded `mpc_aggs` — both strictly OUTSIDE the per-resolve loop; re-solving
# inside it would rebuild a fresh `Model` every step, violating MPC-01's own build-once
# acceptance bar and CLAUDE.md's hard build-once rule),
# then drives plan 21-03/21-04's `build_mpc_window`/`solve_mpc_window!`/`propagate_soc`/
# `propagate_tin`/`draw_forecast_error` through a FIXED-window receding horizon, re-solving
# every `s.mpc_step` real hours (D-03's step-size kwarg genuinely strides the outer loop's
# header, never a silently-inert field), dispatching Phase-20's OWN non-throwing
# certificate/fallback ladder (`RestrictedBranchFlow`/`assert_restriction_exact!`/
# `ac_dual_fallback_price`) on every resolve, recording every published hour into plan
# 21-02's `MpcTrace`, and reporting the closed-loop's measured regret against the
# information-set-fair day-ahead optimum (D-11).
#
# 21-05 DEVIATION (Rule 3 — blocking issue, generalizes RESEARCH.md Pitfall 8): the
# project's ONLY `:default` population selector (`materialize.jl`'s `build_population`)
# includes a `Deferrable` device per house whose energy-budget window `[t_start, t_end]` is
# baked, at CONSTRUCTION time, against the FULL day-ahead horizon `s.T` (e.g. hours 8-16 of
# a 24h day) — a window that is virtually always LONGER than any sane MPC window length
# `s.mpc_H`. `Deferrable.contribute!`'s own temporal-infeasibility guard (`d.t_end > T`)
# throws whenever `build_mpc_window` tries to contribute it at `T = s.mpc_H`, and
# `Deferrable` has no inter-temporal recursion (unlike `soc[t+1]`/`Tin[t+1]`) to propagate
# across MPC steps in the first place (RESEARCH.md Pitfall 8's own documented reasoning,
# there scoped to "keep the CI fixture Deferrable-free" — this generalizes the SAME
# reasoning one level up: the WINDOW MODEL itself cannot host a `Deferrable`, regardless of
# which population supplied it). `run_mpc` therefore builds a SEPARATE, Deferrable-excluded
# aggregator list (`mpc_aggs`) for the window model and every per-step accumulation, while
# the ONE-TIME full-population day-ahead benchmark still uses the FULL, unfiltered `aggs`
# (Deferrable genuinely contributes to that one-time, full-day welfare number,
# `day_ahead_welfare` in the return tuple). `regret`'s day-ahead comparison side (CR-03) is
# read ENTIRELY from a SECOND one-time day-ahead benchmark solved over `mpc_aggs` itself
# (`ctx_da_cmp`) — utilities AND the frontier `p_import` term — so both sides of the regret
# comparison are evaluated over an IDENTICAL device set AND an identically-populated
# dispatch: never a comparison charged the frontier cost of serving a device whose utility
# it is denied. Discovered running this task's own `<verify>` script against the default
# multi-aggregator `:ieee13` population; the frontier-term half found by review CR-03.
#
# 21-05 DEVIATION (Rule 1 — pre-existing bug, plan 21-01, fixed in `src/devices/PVBattery.jl`
# / `src/devices/Thermostatic.jl` / `src/devices/FourQuadBESS.jl` / `src/devices/Aggregator.jl`,
# NOT in this file): plan 21-01's Parameter-widening used the NAMED `@variable(m, name[...]
# in Parameter.(...))`/`@variable(m, name in Parameter(...))` macro forms, which register a
# symbol in the model's object dictionary — colliding ("An object of name ... is already
# attached to this model") the moment a SECOND instance of the SAME device/aggregator type
# contributes to the SAME model. This broke EVERY multi-aggregator `solve_welfare`/
# `run_scenario`/`solve_admm` call project-wide (not just MPC), discovered running this
# task's own `<verify>` script against the 10-aggregator default `:ieee13` population.
# Fixed at the source (anonymous Parameter construction, mirroring `FourQuadBESS`'s own
# anonymous apparent-power cone) — see each file's own deviation comment for detail.

using JuMP

"""
    run_mpc(s::Scenario) -> NamedTuple

Drive the FULL receding-horizon closed loop for `s` (MPC-01..04): materialize the same heavy
objects [`run_scenario`](@ref) does, solve the TWO one-time perfect-foresight day-ahead
benchmarks via [`solve_welfare`](@ref) (the full-population reference and the CR-03
comparable benchmark over the Deferrable-excluded `mpc_aggs` — both strictly outside the
loop), then re-solve a build-once [`MpcWindow`](@ref) every `s.mpc_step` real hours (never
rebuilding it), dispatching Phase-20's own certificate/fallback ladder on every resolve and
recording every published hour into an [`MpcTrace`](@ref).

# Guards (before any materialization)

`s.mpc_step > s.mpc_H` throws `ArgumentError` — a resolve cannot hold its plan longer than
the window it solved.

# Returns

A `NamedTuple` `(; trace, day_ahead_welfare, realized_welfare, regret, day_ahead_dadp,
steps)`:

  - `trace::MpcTrace` — every published hour's DADP, day-ahead reference DADP, price jump,
    cumulative deviation, and certificate/fallback status (MPC-03). The status is one of
    `:certified_convex_dual` (first-tier inline cone check passed), `:local_ac_dual`
    (nonconvex-AC-dual fallback tier), or the TERMINAL `:cert_failed` (every escalation tier
    failed — the published price for that resolve is the day-ahead reference DADP slice, and
    each tier's failure reason is `@warn`ed; CR-02's genuinely non-throwing D-04 ladder).
  - `day_ahead_welfare::Float64` — the FULL perfect-foresight day-ahead welfare (`s.T` hours,
    the complete materialized population INCLUDING any `Deferrable` device — see this file's
    header deviation note).
  - `realized_welfare::Float64` — the closed-loop's realized welfare, accumulated hour-by-hour
    from each applied step's REALIZED controls (D-05), over the Deferrable-excluded `mpc_aggs`
    device set (see header note) plus the realized frontier cost/revenue.
  - `regret::Float64` — `realized_welfare` MINUS the day-ahead welfare RESTRICTED to the SAME
    published `k`-hour decision horizon and the SAME `mpc_aggs` device set (D-11's
    information-set-fair comparison) — NEVER silently extrapolated to the full `s.T` hours the
    day-ahead optimum spans. The day-ahead side (utilities AND frontier `p_import` cost) is
    read from a SECOND one-time benchmark solved over `mpc_aggs` itself (CR-03), never from
    the full-population context — so the comparison is never charged the frontier cost of a
    device whose utility it is denied. The terminal-SOC targets (D-06) likewise track THIS
    comparable benchmark's own optimal SOC trajectory.
  - `day_ahead_dadp::Vector{Float64}` — the full-length (`s.T`) day-ahead reference DADP path.
  - `steps::Int` — the total published-hour count, ALWAYS `s.T - s.mpc_H + 1` regardless of
    `s.mpc_step` (Pitfall 5's fixed-window convention — only the NUMBER OF RESOLVES shrinks as
    `s.mpc_step` grows, never the published-hour count).

Reproducible: two calls with the SAME `Scenario` (same `seed`) return `==`-identical
`regret`/`day_ahead_welfare`/`realized_welfare` (INFRA-04, mirroring `run_scenario`'s own
same-seed guarantee) — the Clarabel solve path is single-threaded and every random draw
(profiles, population, forecast error) flows through a seeded, independent sub-stream.
"""
function run_mpc(s::Scenario)
    # Boundary guard FIRST, before any materialization (mirrors this file's other
    # boundary-guard idiom, e.g. Scenario.jl's own throw-ArgumentError convention): a resolve
    # cannot hold its plan longer than the window it solved.
    s.mpc_step > s.mpc_H && throw(
        ArgumentError(
            "run_mpc: step size cannot exceed window length H " *
            "(mpc_step=$(s.mpc_step) > mpc_H=$(s.mpc_H))",
        ),
    )

    # --- 1. MATERIALIZE, verbatim per run_scenario's own :centralized block
    # (src/experiments/run.jl:92-103) --------------------------------------------------------
    feeder = build_feeder(s.feeder)
    profiles = generate_profiles(; seed = sub_seed(s.seed, :profiles), T = s.T)
    λ₀ = build_price(s.price, s.T, profiles)
    aggs = build_population(
        s.population,
        feeder,
        s.feeder,
        profiles,
        sub_seed(s.seed, :population),
    )
    pf = ConvexBranchFlow()

    # --- 1b. Deferrable-excluded aggregator list for the WINDOW model (see this file's
    # header deviation note) — the day-ahead benchmark below still uses the FULL `aggs`. ------
    mpc_aggs = [
        Aggregator(agg.bus, agg.φ, filter(d -> !(d isa Deferrable), agg.devices), agg.Pdc) for
        agg in aggs
    ]

    # --- 2. ONE-TIME day-ahead perfect-foresight benchmarks (solve_welfare called EXACTLY
    # TWICE, both at T = s.T, NEVER inside the per-resolve loop):
    #   (a) the FULL-population benchmark — the separately-reported `day_ahead_welfare` and
    #       the published day-ahead reference DADP path (Deferrable included);
    #   (b) the COMPARABLE benchmark over the SAME Deferrable-excluded `mpc_aggs` device set
    #       the closed loop actually controls (CR-03) — the regret comparison's ONLY source:
    #       both the per-device utilities AND the frontier `p_import` term are read from THIS
    #       context, so the day-ahead side of the regret is never charged the frontier cost
    #       of serving a device (Deferrable) whose utility it is denied, and its whole
    #       dispatch reflects the SAME population as the closed loop's. ----------------------
    ctx_da, welfare_da, dadp_da = solve_welfare(
        feeder,
        pf,
        aggs;
        T = s.T,
        λ₀ = λ₀,
        allow_export = s.allow_export,
    )
    ctx_da_cmp, _, _ = solve_welfare(
        feeder,
        pf,
        mpc_aggs;
        T = s.T,
        λ₀ = λ₀,
        allow_export = s.allow_export,
    )
    # D-06/D-11 coherence (CR-03): the terminal-SOC targets track the COMPARABLE benchmark's
    # own optimal SOC trajectory — the trajectory regret is measured against — keeping the
    # terminal pin and the benchmark on the SAME information set (previously sourced from the
    # full-population context, whose trajectory reflects a population the closed loop
    # structurally cannot represent).
    soc_da = Dict(
        bus => [value(v.soc[t]) for t in 1:s.T] for
        (bus, varlist) in ctx_da_cmp.meta[:agg_device_vars] for
        v in varlist if haskey(v, :soc)
    )

    # --- 3. Build the window ONCE (MPC-01), against the Deferrable-excluded mpc_aggs. -------
    o = build_mpc_window(feeder, pf, mpc_aggs; H = s.mpc_H, terminal_soc = s.mpc_terminal_soc)

    # Strictly sequential published-step counter record! requires (distinct from the
    # absolute hour t, which skips by s.mpc_step between resolves).
    k = 0
    trace = MpcTrace()
    realized_welfare = 0.0

    # Measured (nominal-plant) state, keyed by (bus, kind): initialized from each mpc_aggs
    # member device's OWN t=1 literal soc0/Tin0 (the simplest possible source of the initial
    # measured state).
    measured_state = Dict{Tuple{Int, Symbol}, Float64}()
    for agg in mpc_aggs, d in agg.devices
        hasproperty(d, :soc0) && (measured_state[(agg.bus, :soc)] = Float64(d.soc0))
        hasproperty(d, :Tin0) && (measured_state[(agg.bus, :Tin)] = Float64(d.Tin0))
    end

    # Outer loop over window RESOLVE epochs — D-03: s.mpc_step genuinely strides this loop's
    # header (never a hardcoded 1:(s.T - s.mpc_H + 1), the checker-flagged regression this
    # task fixes). Every visited `t` re-solves the SAME build-once window `o`.
    for t in 1:s.mpc_step:(s.T - s.mpc_H + 1)
        fe = draw_forecast_error(s.seed, t, s.mpc_forecast_error)

        # IC + terminal-target Parameters (MPC-01/MPC-02).
        for entry in o.ic_handles
            set_parameter_value(entry.ic_param, measured_state[(entry.bus, entry.kind)])
            if entry.terminal_param !== nothing
                set_parameter_value(
                    entry.terminal_param,
                    soc_da[entry.bus][min(t + s.mpc_H - 1, s.T)],
                )
            end
        end

        # Per-step device forecast slices (D-08): PV/demand perturbed multiplicatively by the
        # SAME seeded forecast-error draw; ambient temperature slides UNPERTURBED (D-05: model
        # mismatch enters only via forecast error, never the deterministic window slide).
        for agg in mpc_aggs
            varlist = o.ctx.meta[:agg_device_vars][agg.bus]
            for (d, v) in zip(agg.devices, varlist)
                if haskey(v, :Ppv_param)
                    set_parameter_value.(
                        v.Ppv_param,
                        Float64[d.Ppv[t + τ - 1] * fe.pv_factor for τ in 1:s.mpc_H],
                    )
                end
                if haskey(v, :Tout_param)
                    set_parameter_value.(
                        v.Tout_param,
                        Float64[d.Tout[t + τ - 1] for τ in 1:(s.mpc_H - 1)],
                    )
                end
            end
        end
        for handle in o.agg_pdc_handles
            agg = only(a for a in mpc_aggs if a.bus == handle.bus)
            set_parameter_value.(
                handle.Pdc_param,
                Float64[agg.Pdc[t + τ - 1] * fe.demand_factor for τ in 1:s.mpc_H],
            )
        end

        # Slide λ₀ via set_objective_coefficient — NEVER a Parameter (Pitfall 2).
        for τ in 1:s.mpc_H
            set_objective_coefficient(o.model, o.p_import[τ], -λ₀[t + τ - 1])
        end

        solve_mpc_window!(o)

        # D-04's per-resolve, non-throwing certificate check + Phase-20 escalation ladder —
        # factored into a small internal helper (below) so a test can drive it DIRECTLY
        # against a non-Scenario feeder/aggregator pair (e.g. Phase21Fixtures' high-PV
        # fixture) without duplicating this logic. `measured_state`/`fe` are threaded in
        # (CR-01) so an escalation prices the SAME window [t, t+H-1] under the SAME
        # propagated state and forecast perturbation this resolve's main window just solved
        # — never the day's first H hours with construction-time initial conditions.
        cert = _mpc_certify_and_price(
            feeder,
            mpc_aggs,
            o,
            λ₀,
            t;
            measured_state = measured_state,
            fe = fe,
            fallback_price = dadp_da,
        )
        cert_status = cert.cert_status
        price_vec = cert.price_vec

        # n_apply: the number of REAL hours THIS resolve's plan is held for before the next
        # resolve — capped by the window length itself (cannot apply more intervals than were
        # solved) and by the remaining published horizon (the final resolve never overruns
        # s.T - s.mpc_H + 1 total published hours). This formula guarantees the TOTAL
        # published-hour count across ALL resolves is exactly s.T - s.mpc_H + 1 for ANY
        # s.mpc_step (only the NUMBER OF RESOLVES shrinks as s.mpc_step grows).
        n_apply = min(s.mpc_step, s.mpc_H, (s.T - s.mpc_H + 1) - t + 1)

        for τ_apply in 1:n_apply
            abs_hour = t + τ_apply - 1

            for agg in mpc_aggs
                varlist = o.ctx.meta[:agg_device_vars][agg.bus]
                for d in agg.devices
                    realized_welfare += _mpc_device_hour_utility(d, varlist, τ_apply)
                    if d isa PVBattery || d isa FourQuadBESS
                        v = only(vv for vv in varlist if haskey(vv, :soc0))
                        p_ch1 = value(v.p_ch[τ_apply])
                        p_dch1 = value(v.p_dch[τ_apply])
                        measured_state[(agg.bus, :soc)] = propagate_soc(
                            measured_state[(agg.bus, :soc)],
                            p_ch1,
                            p_dch1,
                            d.η,
                            d.Δt,
                        )
                    elseif d isa Thermostatic
                        v = only(vv for vv in varlist if haskey(vv, :Tin0))
                        p1 = value(v.p[τ_apply])
                        measured_state[(agg.bus, :Tin)] =
                            propagate_tin(measured_state[(agg.bus, :Tin)], p1, d.α, d.β, d.Tout[abs_hour])
                    end
                end
            end
            realized_welfare -= λ₀[abs_hour] * value(o.p_import[τ_apply])

            k += 1
            record!(trace, k, price_vec[τ_apply], dadp_da[abs_hour], cert_status)
        end
    end
    # After the full double loop (resolves × applied hours), k equals the total number of
    # published hours — ALWAYS s.T - s.mpc_H + 1, independent of s.mpc_step (only the NUMBER
    # OF RESOLVES that produced them shrinks as s.mpc_step grows; the published-hour COUNT
    # never changes, Pitfall 5).

    # D-11: regret is scoped to the PUBLISHED decision horizon (k hours, Pitfall 5's honest
    # step-count convention, invariant to s.mpc_step) — NEVER silently extrapolated to the
    # full s.T hours the day-ahead optimum spans. Both sides are evaluated via the IDENTICAL
    # per-device utility-formula accumulation over the SAME mpc_aggs device set (Deferrable
    # excluded from BOTH sides, see this file's header deviation note) — CR-03: every read
    # (utilities AND the frontier p_import term) comes from ctx_da_cmp, the day-ahead
    # benchmark solved over mpc_aggs ITSELF, so the comparison is never charged the frontier
    # cost of serving a device whose utility it is denied, and its dispatch reflects the
    # SAME population as the closed loop's.
    day_ahead_comparable_welfare = 0.0
    for τ in 1:k
        for agg in mpc_aggs
            varlist = ctx_da_cmp.meta[:agg_device_vars][agg.bus]
            for d in agg.devices
                day_ahead_comparable_welfare += _mpc_device_hour_utility(d, varlist, τ)
            end
        end
        day_ahead_comparable_welfare -= λ₀[τ] * value(ctx_da_cmp.meta[:p_import][τ])
    end
    regret = realized_welfare - day_ahead_comparable_welfare

    return (;
        trace,
        day_ahead_welfare = Float64(welfare_da),
        realized_welfare = Float64(realized_welfare),
        regret = Float64(regret),
        day_ahead_dadp = Vector{Float64}(dadp_da),
        steps = k,
    )
end

"""
    _mpc_certify_and_price(feeder, mpc_aggs, o::MpcWindow, λ₀::AbstractVector{<:Real}, t::Int;
                           measured_state, fe, fallback_price = λ₀,
                           _solve_welfare = solve_welfare,
                           _ac_dual_fallback_price = ac_dual_fallback_price)
        -> (; cert_status::Symbol, price_vec::Vector{Float64}, cone_maxratio::Float64)

Internal helper (unexported): [`run_mpc`](@ref)'s per-resolve, non-throwing certificate check
(D-04) + Phase-20 escalation ladder, factored out so a test can drive it DIRECTLY against a
non-`Scenario` `feeder`/`mpc_aggs` pair (e.g. `Phase21Fixtures`' high-PV fixture) without
duplicating this logic — `run_mpc`'s own loop calls this EXACT function.

An inline REIMPLEMENTATION of [`assert_socp_exact!`](@ref)'s own cone-residual formula, at
ITS SAME `rtol=1e-4`/`atol=1e-6` defaults (the ONE place this file deliberately copies a
tolerance — this is the IDENTICAL physical quantity at the IDENTICAL default, not a new
certificate; NEVER delegates to the throwing `assert_socp_exact!` itself, and NEVER a bare
`try`/`catch` around it). `o` MUST already be solved (i.e. [`solve_mpc_window!`](@ref) called)
at window-local positions `τ = 1:o.H` before calling this. `t` is the resolve's ABSOLUTE start
hour (used to slice `λ₀` AND every device/demand profile for the escalation branch, and to
name the resolve in the `@warn` message — never used to index `o`, which is always
window-local).

`measured_state` (the `(bus, kind) => value` dict of propagated SOC/temperature states) and
`fe` (the resolve's own seeded forecast-error draw, `(; pv_factor, demand_factor)`) are
REQUIRED keyword arguments (CR-01): an escalation must price the SAME window the failed
resolve solved — absolute hours `t:(t+H-1)`, the SAME measured initial state, the SAME
forecast perturbation — so both are threaded from `run_mpc`'s loop into
[`_mpc_escalation_aggregators`](@ref), which rebuilds window-sliced device structs whose
plain fields (hence whose fresh-model Parameter DEFAULTS) carry exactly those values. They
are required (no silent defaults) so a caller can never accidentally price the wrong state.

On a certified step: `cert_status = :certified_convex_dual`, `price_vec =
dual.(o.ctx.constraints[:balance_p][o.agg_bus, :])` (length `o.H`). On a failed inline check:
escalates through Phase-20's OWN ladder (never invents a new tolerance) — a ONE-OFF
[`RestrictedBranchFlow`](@ref)`()` solve + [`ACPowerFlow`](@ref)`()` cross-solve +
[`assert_restriction_exact!`](@ref)`(...; report = true)`; if THAT does not certify,
[`ac_dual_fallback_price`](@ref), publishing `cert_status = :local_ac_dual`. Every escalation
tier solves the window-sliced problem (the ONE documented difference from the main window:
`solve_welfare` has no terminal-SOC hook, so the optional hard terminal pin (D-06) is absent
from the escalation problem — an accepted, rare-path approximation).

# The never-throw contract (CR-02 — D-04 is now genuine, not aspirational)

Each escalation tier runs inside a `catch` that routes its DOCUMENTED failure modes into the
returned status instead of propagating out of `run_mpc` mid-loop: `assert_solved!` retry
exhaustion, `assert_battery_complementarity!`'s legitimate negative-effective-price throw
(`FourQuadBESS.jl`'s step-3 derivation — the very regime that trips the inline cone check),
and `assert_ac_exact!`'s structural guards. `InterruptException` is ALWAYS rethrown. The
restricted-tier `solve_welfare` is called with `rtol_exact = Inf`, neutralizing ITS internal
`assert_socp_exact!` gate on that one solve only: that gate's `rtol = 1e-4` is STRICTER than
`assert_restriction_exact!`'s own independently-measured `cone_rtol = 5e-4`, so leaving it
active would throw out of the ladder in precisely the regime the fallback tier exists for —
the restricted tier's cone verdict is OWNED by `assert_restriction_exact!(report = true)`.

If BOTH tiers fail, the TERMINAL `cert_status = :cert_failed` (the symbol
[`MpcTrace`](@ref)/[`any_cert_failed`](@ref) advertise — genuinely producible, WR-04) is
returned with `price_vec = fallback_price[t:(t+H-1)]` as the documented price policy:
`run_mpc` passes the day-ahead reference DADP path (`dadp_da`) as `fallback_price`; the
default is `λ₀` itself (the MEM price) for direct drivers. Each tier's failure reason is
`@warn`ed (never swallowed silently).

`_solve_welfare`/`_ac_dual_fallback_price` are INTERNAL TEST SEAMS (default to the real
functions): the terminal `:cert_failed` tier is unreachable on any cheap CI fixture by
construction (a fixture where BOTH a restricted SOCP and a multi-start NLP genuinely fail is
not economically buildable in CI), so `test_mpc_loop.jl` injects throwing stand-ins to
deterministically exercise the catch/ledger paths. Production callers NEVER pass them.
"""
function _mpc_certify_and_price(
    feeder,
    mpc_aggs,
    o::MpcWindow,
    λ₀::AbstractVector{<:Real},
    t::Int;
    measured_state::AbstractDict{Tuple{Int, Symbol}, Float64},
    fe::NamedTuple,
    fallback_price::AbstractVector{<:Real} = λ₀,
    _solve_welfare = solve_welfare,
    _ac_dual_fallback_price = ac_dual_fallback_price,
)
    pv = o.ctx.meta[:pf_vars]
    cone_maxratio = 0.0
    for (b, br) in enumerate(feeder.branches), τ in 1:(o.H)
        lhs = value(pv.l[b, τ]) * value(pv.v[br.from, τ])
        rhs = value(pv.P[b, τ])^2 + value(pv.Q[b, τ])^2
        gap = abs(lhs - rhs)
        tol = 1e-6 + 1e-4 * max(abs(lhs), abs(rhs))
        cone_maxratio = max(cone_maxratio, gap / tol)
    end
    step_certified = cone_maxratio <= 1     # NEVER throws here (D-04)

    if step_certified
        cert_status = :certified_convex_dual
        price_vec = dual.(o.ctx.constraints[:balance_p][o.agg_bus, :])
    else
        # Escalate through Phase-20's OWN ladder (never invent a new tolerance): a ONE-OFF
        # RestrictedBranchFlow() solve + AC cross-solve + assert_restriction_exact!(report =
        # true); if THAT also fails, ac_dual_fallback_price. `@warn` once so a researcher
        # running interactively sees the escalation — this function itself NEVER throws (D-04).
        #
        # CR-01: every tier prices the SAME window this resolve just failed on — absolute
        # hours t:(t+H-1), the SAME measured state, the SAME forecast-perturbed profile
        # slices run_mpc fed the main window. `_mpc_escalation_aggregators` rebuilds
        # window-sliced device structs so each tier's fresh `solve_welfare` model DEFAULTS
        # its Parameters to exactly those values — never the day's first H hours with
        # construction-time initial conditions (the wrong-problem bug this replaces).
        # Escalation is rare by design, so the one-off model builds are an accepted cost
        # (correctness over cost). The ONE documented difference from the main window:
        # solve_welfare has no terminal-SOC hook, so the optional hard terminal pin (D-06)
        # is absent from the escalation problem.
        λ₀_window = λ₀[t:(t + o.H - 1)]
        esc_aggs = _mpc_escalation_aggregators(mpc_aggs, t, o.H, fe, measured_state)

        # CR-02 (D-04's ladder is now GENUINELY non-throwing): both escalation tiers run
        # inside a catch that routes each tier's DOCUMENTED failure modes into the ledger
        # instead of propagating out of run_mpc mid-loop (losing the trace accumulated so
        # far). The documented throwers inside a tier: assert_solved! retry exhaustion,
        # assert_battery_complementarity! (LEGITIMATELY throws in the negative-effective-
        # price / high-PV regime — exactly the regime that trips the inline cone check,
        # FourQuadBESS.jl's step-3 derivation), and assert_ac_exact!'s structural guards.
        # InterruptException is ALWAYS rethrown (a user Ctrl-C is never a certificate
        # verdict). If BOTH tiers fail, the terminal `:cert_failed` status (the symbol
        # MpcTrace/any_cert_failed have always advertised) is published with the
        # caller-supplied `fallback_price` window slice as the price policy — run_mpc passes
        # the day-ahead reference DADP path; the default is λ₀ itself.
        cert_status = :cert_failed
        price_vec = Float64[fallback_price[t + τ - 1] for τ in 1:(o.H)]
        tier_reasons = String[]

        # Tier 2 — RestrictedBranchFlow solve + AC cross-solve + Phase-20's own certificate.
        # `rtol_exact = Inf` neutralizes solve_welfare's INTERNAL assert_socp_exact! gate on
        # the restricted solve ONLY (CR-02 point 1): that gate's rtol = 1e-4 is STRICTER
        # than assert_restriction_exact!'s own independently-measured cone_rtol = 5e-4, so
        # leaving it active would throw out of the ladder in precisely the regime the
        # ac_dual_fallback_price tier exists for — the restricted tier's cone verdict is
        # OWNED by assert_restriction_exact! (report = true) below, never by the internal
        # gate.
        try
            ctx_restricted, _, _ = _solve_welfare(
                feeder,
                RestrictedBranchFlow(),
                esc_aggs;
                T = o.H,
                λ₀ = λ₀_window,
                allow_export = true,
                rtol_exact = Inf,
            )
            ctx_ac, _, _ = _solve_welfare(
                feeder,
                ACPowerFlow(),
                esc_aggs;
                T = o.H,
                λ₀ = λ₀_window,
                allow_local = true,
                allow_export = true,
            )
            report = assert_restriction_exact!(ctx_restricted, ctx_ac; report = true)
            if report.ac_feasible
                cert_status = :certified_convex_dual
                price_vec = Vector{Float64}(
                    dual.(ctx_restricted.constraints[:balance_p][o.agg_bus, :]),
                )
            else
                push!(
                    tier_reasons,
                    "restricted tier: ac_feasible = false (the OPF-m restriction did not " *
                    "restore cone tightness)",
                )
            end
        catch err
            err isa InterruptException && rethrow()
            push!(tier_reasons, "restricted tier threw: " * sprint(showerror, err))
        end

        # Tier 3 — nonconvex-AC-dual fallback pricer, only reached when tier 2 did not
        # certify (D-09's trigger discipline: the CALLER invokes the fallback after seeing
        # the certificate fail).
        if cert_status === :cert_failed
            try
                fallback = _ac_dual_fallback_price(
                    feeder,
                    esc_aggs;
                    T = o.H,
                    λ₀ = λ₀_window,
                    allow_export = true,
                )
                cert_status = :local_ac_dual
                price_vec = Vector{Float64}(fallback.dadp)
            catch err
                err isa InterruptException && rethrow()
                push!(tier_reasons, "AC-dual fallback tier threw: " * sprint(showerror, err))
            end
        end

        if cert_status === :cert_failed
            @warn "run_mpc: EVERY escalation tier failed — publishing :cert_failed with the reference fallback price for this window (D-04: never throws mid-loop)" t cone_maxratio cert_status reasons = join(
                tier_reasons,
                " | ",
            )
        else
            @warn "run_mpc: per-resolve cone check failed — escalating via Phase-20's certificate/fallback ladder" t cone_maxratio cert_status
        end
    end

    return (; cert_status, price_vec = Vector{Float64}(price_vec), cone_maxratio)
end

"""
    _mpc_escalation_aggregators(mpc_aggs, t::Int, H::Int, fe, measured_state)
        -> Vector{<:Aggregator}

Internal helper (unexported, CR-01): rebuild `mpc_aggs` as WINDOW-SLICED aggregator structs
whose plain struct fields carry exactly the state the build-once window's Parameters were set
to at resolve hour `t`: `Pdc = agg.Pdc[t:(t+H-1)] .* fe.demand_factor`, and each device
re-created via [`_mpc_window_device`](@ref) with its measured SOC/temperature as the initial
condition and its profiles sliced to the same absolute window (PV forecast-perturbed by
`fe.pv_factor`; ambient temperature slides UNPERTURBED — D-05, mirroring `run_mpc`'s own
per-step Parameter writes verbatim). Because every escalation tier builds a FRESH
`solve_welfare` model whose Parameters DEFAULT to the device structs' own fields
(byte-identical-default invariant, plan 21-01), feeding these sliced structs makes the
escalation solve the SAME problem the failed resolve solved (bar the optional terminal-SOC
pin, documented at the call site). Pure struct construction — no JuMP, no solve.
"""
function _mpc_escalation_aggregators(mpc_aggs, t::Int, H::Int, fe, measured_state)
    return [
        Aggregator(
            agg.bus,
            agg.φ,
            AbstractDevice[
                _mpc_window_device(d, agg.bus, t, H, fe, measured_state) for
                d in agg.devices
            ],
            Float64[agg.Pdc[t + τ - 1] * fe.demand_factor for τ in 1:H],
        ) for agg in mpc_aggs
    ]
end

"""
    _mpc_window_device(d, bus::Int, t::Int, H::Int, fe, measured_state) -> AbstractDevice

Internal helper (unexported, CR-01): re-create device `d` as a window-sliced struct for the
escalation solve at absolute start hour `t` — initial state from `measured_state[(bus,
kind)]`, per-hour profiles sliced to `t:(t+H-1)` (PV multiplied by `fe.pv_factor`, ambient
temperature unperturbed, D-05). The measured state is clamped to the device's own structural
band (`[Emin, Emax]` / `[Tmin, Tmax]`) purely to absorb solver-tolerance noise in the
propagated value (|ε| ≲ 1e-8) — a genuinely out-of-band state is prevented upstream by
`run_mpc`'s stateful-device stride guard (WR-02), so the clamp is never a silent repair of a
real violation. Methods exist for the three window-hostable stateful/aggregatable device
types (`PVBattery`, `FourQuadBESS`, `Thermostatic`); any other type throws a loud
`ArgumentError` (never a cryptic `MethodError`).
"""
function _mpc_window_device(d::PVBattery, bus::Int, t::Int, H::Int, fe, measured_state)
    soc_meas = clamp(measured_state[(bus, :soc)], d.Emin, d.Emax)
    return PVBattery(
        d.bus,
        d.η,
        d.Δt,
        d.Pmax,
        d.Emin,
        d.Emax,
        soc_meas,
        d.λ_min,
        d.λ_med,
        d.λ_max,
        Float64[d.Ppv[t + τ - 1] * fe.pv_factor for τ in 1:H],
    )
end

function _mpc_window_device(d::FourQuadBESS, bus::Int, t::Int, H::Int, fe, measured_state)
    soc_meas = clamp(measured_state[(bus, :soc)], d.Emin, d.Emax)
    return FourQuadBESS(
        d.bus,
        d.η,
        d.Δt,
        d.Pch_max,
        d.Pdch_max,
        d.Smax,
        d.Emin,
        d.Emax,
        soc_meas,
        d.λ_min,
        d.λ_med,
        d.λ_max,
    )
end

function _mpc_window_device(d::Thermostatic, bus::Int, t::Int, H::Int, fe, measured_state)
    tin_meas = clamp(measured_state[(bus, :Tin)], d.Tmin, d.Tmax)
    return Thermostatic(
        d.bus,
        d.α,
        d.β,
        d.Tmin,
        d.Tmax,
        tin_meas,
        d.Pmin,
        d.Pmax,
        d.b,
        Float64[d.Tout[t + τ - 1] for τ in 1:H],
    )
end

function _mpc_window_device(d::AbstractDevice, bus::Int, t::Int, H::Int, fe, measured_state)
    throw(
        ArgumentError(
            "_mpc_window_device: unsupported device type $(typeof(d)) at bus $bus — the " *
            "MPC escalation ladder can window-slice only PVBattery/FourQuadBESS/" *
            "Thermostatic (the window-hostable stateful device set)",
        ),
    )
end

"""
    _mpc_device_hour_utility(d::AbstractDevice, varlist, τ::Int) -> Float64

Internal helper (unexported): the REALIZED per-hour utility contribution of device `d` at
window/day-ahead position `τ`, reading `d`'s OWN documented `contribute!` utility formula off
`d`'s ORIGINAL struct fields (never inventing new math) and the SOLVED value of its decision
variable(s) at `τ` — found in `varlist` (a `Vector{Any}` of device-vars `NamedTuple`s, e.g.
`ctx.meta[:agg_device_vars][bus]`) by the SAME type-specific marker key
[`build_mpc_window`](@ref)'s own `ic_handles` walk uses (`:soc0` for battery-like devices,
`:Tin0` for `Thermostatic`). Used IDENTICALLY for [`run_mpc`](@ref)'s closed-loop
`realized_welfare` accumulation (source: the window's own `ctx`) and its day-ahead
`regret`-comparison accumulation (source: the day-ahead benchmark's `ctx_da`) — the SAME
formula, only the ctx source (and hence the SOLVED values it reads) differs, per D-11's
information-set-fair contract.
"""
function _mpc_device_hour_utility(d::PVBattery, varlist, τ::Int)
    v = only(vv for vv in varlist if haskey(vv, :soc0) && haskey(vv, :Ppv_param))
    a_ch = d.λ_med
    b_ch = (d.λ_med - d.λ_min) / d.Pmax
    a_dch = d.λ_med
    b_dch = (d.λ_max - d.λ_med) / d.Pmax
    p_ch1 = value(v.p_ch[τ])
    p_dch1 = value(v.p_dch[τ])
    return a_ch * p_ch1 - (b_ch / 2) * p_ch1^2 - a_dch * p_dch1 - (b_dch / 2) * p_dch1^2
end

function _mpc_device_hour_utility(d::FourQuadBESS, varlist, τ::Int)
    v = only(vv for vv in varlist if haskey(vv, :soc0) && haskey(vv, :q))
    a_ch = d.λ_med
    b_ch = (d.λ_med - d.λ_min) / d.Pch_max
    a_dch = d.λ_med
    b_dch = (d.λ_max - d.λ_med) / d.Pdch_max
    p_ch1 = value(v.p_ch[τ])
    p_dch1 = value(v.p_dch[τ])
    return a_ch * p_ch1 - (b_ch / 2) * p_ch1^2 - a_dch * p_dch1 - (b_dch / 2) * p_dch1^2
end

function _mpc_device_hour_utility(d::Thermostatic, varlist, τ::Int)
    v = only(vv for vv in varlist if haskey(vv, :Tin0))
    Tin1 = value(v.Tin[τ])
    return -(d.b / 2) * (Tin1 - d.Tmin)^2
end

export run_mpc

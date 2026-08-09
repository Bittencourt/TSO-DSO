# src/experiments/mpc_loop.jl
#
# SEAM: receding-horizon closed-loop orchestrator (MPC-01..04).
# OWNER: plan 21-05.
#
# `run_mpc(s::Scenario)` is an INDEPENDENT entry point — it is NOT wired through
# `run_scenario`/`run.jl`'s `:centralized`/`:admm` `strategy` dispatch (D-01, Pitfall 7);
# that dispatch stays byte-for-byte untouched. It materializes the SAME heavy objects
# `run_scenario` does (feeder/profiles/λ₀/aggregators, `src/experiments/materialize.jl`
# verbatim), solves the perfect-foresight day-ahead benchmark via `solve_welfare` EXACTLY
# ONCE (never inside the per-resolve loop — that would rebuild a fresh `Model` every step,
# violating MPC-01's own build-once acceptance bar and CLAUDE.md's hard build-once rule),
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
# the ONE-TIME day-ahead benchmark still uses the FULL, unfiltered `aggs` (Deferrable
# genuinely contributes to that one-time, full-day welfare number, `day_ahead_welfare` in
# the return tuple). `regret`'s day-ahead comparison term is accumulated over the SAME
# `mpc_aggs` device set (never `aggs`) so both sides of the regret comparison are evaluated
# over an IDENTICAL device set — an apples-to-apples comparison, not one inflated by a
# device the closed loop structurally cannot represent. Discovered running this task's own
# `<verify>` script against the default multi-aggregator `:ieee13` population.
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
objects [`run_scenario`](@ref) does, solve the perfect-foresight day-ahead benchmark ONCE via
[`solve_welfare`](@ref), then re-solve a build-once [`MpcWindow`](@ref) every `s.mpc_step`
real hours (never rebuilding it), dispatching Phase-20's own certificate/fallback ladder on
every resolve and recording every published hour into an [`MpcTrace`](@ref).

# Guards (before any materialization)

`s.mpc_step > s.mpc_H` throws `ArgumentError` — a resolve cannot hold its plan longer than
the window it solved.

# Returns

A `NamedTuple` `(; trace, day_ahead_welfare, realized_welfare, regret, day_ahead_dadp,
steps)`:

  - `trace::MpcTrace` — every published hour's DADP, day-ahead reference DADP, price jump,
    cumulative deviation, and certificate/fallback status (MPC-03).
  - `day_ahead_welfare::Float64` — the FULL perfect-foresight day-ahead welfare (`s.T` hours,
    the complete materialized population INCLUDING any `Deferrable` device — see this file's
    header deviation note).
  - `realized_welfare::Float64` — the closed-loop's realized welfare, accumulated hour-by-hour
    from each applied step's REALIZED controls (D-05), over the Deferrable-excluded `mpc_aggs`
    device set (see header note) plus the realized frontier cost/revenue.
  - `regret::Float64` — `realized_welfare` MINUS the day-ahead welfare RESTRICTED to the SAME
    published `k`-hour decision horizon and the SAME `mpc_aggs` device set (D-11's
    information-set-fair comparison) — NEVER silently extrapolated to the full `s.T` hours the
    day-ahead optimum spans.
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

    # --- 2. ONE-TIME day-ahead perfect-foresight benchmark (solve_welfare called EXACTLY
    # ONCE, T = s.T, never inside the per-resolve loop). --------------------------------------
    ctx_da, welfare_da, dadp_da = solve_welfare(
        feeder,
        pf,
        aggs;
        T = s.T,
        λ₀ = λ₀,
        allow_export = s.allow_export,
    )
    soc_da = Dict(
        bus => [value(v.soc[t]) for t in 1:s.T] for
        (bus, varlist) in ctx_da.meta[:agg_device_vars] for v in varlist if haskey(v, :soc)
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
        # fixture) without duplicating this logic.
        cert = _mpc_certify_and_price(feeder, mpc_aggs, o, λ₀, t)
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
    # excluded from BOTH sides, see this file's header deviation note) on the SAME realized
    # truth (ctx_da's own solved day-ahead trajectory).
    day_ahead_comparable_welfare = 0.0
    for τ in 1:k
        for agg in mpc_aggs
            varlist = ctx_da.meta[:agg_device_vars][agg.bus]
            for d in agg.devices
                day_ahead_comparable_welfare += _mpc_device_hour_utility(d, varlist, τ)
            end
        end
        day_ahead_comparable_welfare -= λ₀[τ] * value(ctx_da.meta[:p_import][τ])
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
    _mpc_certify_and_price(feeder, mpc_aggs, o::MpcWindow, λ₀::AbstractVector{<:Real}, t::Int)
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
hour (used only to slice `λ₀` for the escalation branch and to name the resolve in the `@warn`
message — never used to index `o`, which is always window-local).

On a certified step: `cert_status = :certified_convex_dual`, `price_vec =
dual.(o.ctx.constraints[:balance_p][o.agg_bus, :])` (length `o.H`). On a failed inline check:
escalates through Phase-20's OWN ladder (never invents a new tolerance) — a ONE-OFF
[`RestrictedBranchFlow`](@ref)`()` solve + [`ACPowerFlow`](@ref)`()` cross-solve +
[`assert_restriction_exact!`](@ref)`(...; report = true)`; if THAT also fails,
[`ac_dual_fallback_price`](@ref), publishing `cert_status = :local_ac_dual`. `@warn`s once so
a researcher running interactively sees the escalation — this function itself NEVER throws
(D-04).
"""
function _mpc_certify_and_price(feeder, mpc_aggs, o::MpcWindow, λ₀::AbstractVector{<:Real}, t::Int)
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
        λ₀_window = λ₀[t:(t + o.H - 1)]
        ctx_restricted, _, _ = solve_welfare(
            feeder,
            RestrictedBranchFlow(),
            mpc_aggs;
            T = o.H,
            λ₀ = λ₀_window,
            allow_export = true,
        )
        ctx_ac, _, _ = solve_welfare(
            feeder,
            ACPowerFlow(),
            mpc_aggs;
            T = o.H,
            λ₀ = λ₀_window,
            allow_local = true,
            allow_export = true,
        )
        report = assert_restriction_exact!(ctx_restricted, ctx_ac; report = true)
        if report.ac_feasible
            cert_status = :certified_convex_dual
            price_vec = dual.(ctx_restricted.constraints[:balance_p][o.agg_bus, :])
        else
            fallback = ac_dual_fallback_price(
                feeder,
                mpc_aggs;
                T = o.H,
                λ₀ = λ₀_window,
                allow_export = true,
            )
            cert_status = :local_ac_dual
            price_vec = fallback.dadp
        end
        @warn "run_mpc: per-resolve cone check failed — escalating via Phase-20's certificate/fallback ladder" t cone_maxratio cert_status
    end

    return (; cert_status, price_vec = Vector{Float64}(price_vec), cone_maxratio)
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

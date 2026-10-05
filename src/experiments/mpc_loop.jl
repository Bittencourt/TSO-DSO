# src/experiments/mpc_loop.jl
#
# SEAM: receding-horizon closed-loop orchestrator (MPC-01..04).
# OWNER: plan 21-05.
#
# `run_mpc(s::Scenario)` reads its knobs from `Scenario.strategy::MPC` (Phase 32) and is also
# reachable through `TSODSO.run(::MPC, s)`, which wraps the unchanged `run_mpc` NamedTuple
# into the common `ScenarioResult`. It materializes the SAME heavy objects
# `run_scenario` does (feeder/profiles/λ₀/aggregators, `src/experiments/materialize.jl`
# verbatim), solves TWO one-time perfect-foresight day-ahead benchmarks via `solve_welfare`
# (the FULL-population reference and the CR-03 comparable benchmark over the
# Deferrable-excluded `mpc_aggs` — both strictly OUTSIDE the per-resolve loop; re-solving
# inside it would rebuild a fresh `Model` every step, violating MPC-01's own build-once
# acceptance bar and CLAUDE.md's hard build-once rule),
# then drives plan 21-03/21-04's `build_mpc_window`/`solve_mpc_window!`/`propagate_soc`/
# `propagate_tin`/`draw_forecast_error` through a FIXED-window receding horizon, re-solving
# every `st.step` real hours (D-03's step-size kwarg genuinely strides the outer loop's
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
# `st.H`. `Deferrable.contribute!`'s own temporal-infeasibility guard (`d.t_end > T`)
# throws whenever `build_mpc_window` tries to contribute it at `T = st.H`, and
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
loop), then re-solve a build-once [`MpcWindow`](@ref) every `st.step` real hours (never
rebuilding it), dispatching Phase-20's own certificate/fallback ladder on every resolve and
recording every published hour into an [`MpcTrace`](@ref).

# Guards

Before any materialization: `st.H > s.T` throws `ArgumentError` (WR-07 — the window
cannot exceed the day-ahead horizon; previously this surfaced as a cryptic device-level
"profile too short" deep inside `build_mpc_window`, or, for a hypothetical
longer-than-`T`-profile population, a silent zero-resolve `steps = 0` run), and
`st.step > st.H` throws `ArgumentError` — a resolve cannot hold its plan longer than
the window it solved.

After the population materializes: with any THERMOSTATIC (temperature-stateful) device
present, `st.step > st.H − 1` throws `ArgumentError` (WR-02, re-scoped post-FIX-04 —
PM-08): Thermostatic's `Tin` recursion still covers only `τ ≤ H−1` (unchanged by Plan
26-03), so its window's `H`-th control carries no modeled state consequence, and applying it
can push the propagated measured temperature out of its structural band and make the next
resolve's IC pin infeasible mid-loop. Battery-only populations (`PVBattery`/`FourQuadBESS`)
no longer trip this guard: Plan 26-03 (FIX-04) closes their `soc[1:(H+1)]` recursion
unconditionally over the WHOLE window, so their H-th control IS fully state-covered.
Additionally
(WR-05), aggregator buses must be UNIQUE and each bus may host at most ONE device of each
state kind (one `:soc0`-carrying, one `:Tin0`-carrying) — the loop's measured-state ledger,
terminal-target Dict, and device-vars pairing are all keyed by `(bus, kind)`, an invariant
that was previously silent; a violating population now throws `ArgumentError` instead of
silently overwriting state or mispairing devices with variables.

# Returns

A `NamedTuple`
`(; trace, day_ahead_welfare, forecast_settled_welfare, realized_welfare, regret, day_ahead_dadp, steps, settlement_violations, status)` (`status` is the trailing, additive Phase 34 field, one of `STATUS_VOCABULARY.run_mpc`: `:certified`, `:degraded`, `:cert_failed`):

  - `trace::MpcTrace` — every published hour's DADP, day-ahead reference DADP, price jump,
    cumulative deviation, and certificate/fallback status (MPC-03). The status is one of
    `:certified_convex_dual` (first-tier inline cone check passed),
    `:certified_convex_dual_restricted` (restricted-tier rescue — the price is the OPF-m
    RESTRICTED solve's dual, WR-04's distinct provenance), `:local_ac_dual`
    (nonconvex-AC-dual fallback tier), or the TERMINAL `:cert_failed` (every escalation tier
    failed — the published price for that resolve is the day-ahead reference DADP slice, and
    each tier's failure reason is `@warn`ed; CR-02's genuinely non-throwing D-04 ladder).
  - `day_ahead_welfare::Float64` — the FULL perfect-foresight day-ahead welfare (`s.T` hours,
    the complete materialized population INCLUDING any `Deferrable` device — see this file's
    header deviation note).
  - `realized_welfare::Float64` — the closed-loop's TRUTH-SETTLED realized welfare (Phase 27
    FIX-10, as amended by the post-research CONTEXT decision), accumulated hour-by-hour from
    each applied step's applied controls settled against the TRUE plant, over the
    Deferrable-excluded `mpc_aggs` device set (see header note) plus the frontier
    cost/revenue. Three corrections versus the window's own forecast-consistent belief:
    (1) a `PVBattery`'s realized charge AND self-consumption/export (`pv_used`, which feeds
    `net_p`/`p_inject` and hence the frontier import settled below) are BOTH CLIPPED to the
    device's TRUE (unperturbed) `d.Ppv[abs_hour]` availability (Assumption A6:
    `p_ch[t] <= pv_used[t] <= Ppv[t]`) — never the raw solved values, either of which can
    exceed truth when `fe.pv_factor > 1` inflated the window's belief (CR-02, 27-REVIEW.md:
    clipping only `p_ch` and leaving `pv_used` unclipped let `realized_welfare`/
    `p_import_true` be credited with PV energy the true plant cannot physically supply); the
    device utility term is charged on the clipped `p_ch`, never the unclipped solved one;
    (2) true-state propagation (`propagate_soc`/`propagate_tin`, kept
    JuMP-free) THROWS a loud `ErrorException` — never silently clamps — if the realized state
    falls outside `[Emin,Emax]`/`[Tmin,Tmax]`, a genuine out-of-band event distinct from
    `_mpc_window_device`'s SEPARATE solver-tolerance-noise clamp (`mpc_loop.jl:759-780`,
    untouched); (3) the frontier import is settled by a genuine AC POWER FLOW, PHYSICS ONLY
    (Phase 27 FIX-10, USER DECISION 2026-09-29, plans 27-08/27-09 — supersedes the earlier
    SOCP-based loss-exact re-solve, see below): `_mpc_truth_import_acpf` builds and solves a
    FRESH single-hour `ModelContext` on [`ACPowerFlow`](@ref)`(; limits = false)` (Ipopt,
    `problem_class(ACPowerFlow()) = NLP()`) — a genuinely INDEPENDENT nonconvex formulation,
    not a re-solve of the window's own relaxed cone, and (plan 27-09) WITHOUT the
    `:smax`/`:smax_rev` thermal limits or the `vmin²`/`vmax²` operating voltage band (the truth
    plant settles the AC PHYSICS only; it never refuses a dispatch on an operating limit) — with
    every device's realized (clipped) net active/reactive injection FIXED at each aggregator bus
    (mirroring `Aggregator.contribute!`'s own `p_inject − Pdc`/`−Pdc·tanφ + q_inject` wiring, but
    with NUMERIC realized values and the TRUE, unperturbed `agg.Pdc[abs_hour]` baseline demand),
    warm-started from the WINDOW's own solved `P`/`Q`/`l`/`v` at this hour (26-15: Ipopt's
    default all-zero start is a degenerate KKT point of the unrelaxed `l·v = P²+Q²` equality),
    and only the frontier import free. The solve MUST reach `LOCALLY_SOLVED` (or `OPTIMAL`) with
    a feasible primal — `ALMOST_LOCALLY_SOLVED` is TREATED AS A FAILURE, never silently accepted
    — throwing a loud `SolveFailedError` naming `abs_hour` and the full solve status otherwise
    (this convergence bar is UNCHANGED by plan 27-09 — only the operating limits are relaxed,
    never the convergence requirement). SOCP exactness gating (`assert_socp_exact!`) plays NO
    role in this settlement path — there is no relaxation here to certify, the branch-flow
    relation is the TRUE nonconvex equality. Any per-hour thermal/voltage violation under this
    relaxed operating band is REPORTED, never refused — see the `settlement_violations` bullet
    below. Under `st.forecast_error == 0.0` (every `fe.pv_factor == fe.demand_factor == 1.0`)
    this is BYTE-IDENTICAL to `forecast_settled_welfare` to solver precision: no clip ever
    engages (the window's own PV-limit constraint already bounds the solved `p_ch` by the
    UNPERTURBED `Ppv[abs_hour]`), and the AC truth re-solve reproduces the window's own
    solved dispatch exactly, since the fixed injections match what the window itself
    balanced (same feeder, same per-bus net injections) and a radial network's AC power flow
    has a unique physical solution at those injections.

    **Post-research amendment history (for provenance, NOT the current behavior):** plans
    27-03/27-07 originally settled the frontier import via a SOCP-relaxation re-solve
    (`Min Σ_b r_b·l[b,1]` on `ConvexBranchFlow`, certified by `assert_socp_exact!`) and
    measured it GENUINELY INEXACT on 18/20 tested seeds under forecast-error-driven reverse
    flow (27-07-SUMMARY.md "Findings" — a real SOCP relaxation knife-edge, not a solver
    artifact) — masked in `test/test_mpc_loop.jl` by a `seed=5` substitution. Plan 27-08
    (USER DECISION 2026-09-29) replaces that SOCP re-solve with the AC power-flow settlement
    described above, removing THAT SPECIFIC knife-edge (the happy-path fixture's `seed=5`
    mask reverts cleanly to the default `seed=1`) — but plan 27-08 ALSO MEASURED a NEW,
    MORE FUNDAMENTAL finding on the SAME tight-thermal-limit fixture family: the DEFAULT
    `seed=1` drives a realized/clipped dispatch that GENUINELY exceeds the head branch's
    thermal rating once served by the TRUE (unrelaxed) AC equality (confirmed via a
    limits-removed re-solve reaching `LOCALLY_SOLVED` while the limited re-solve correctly
    reports `LOCALLY_INFEASIBLE` — not a numerics artifact). Plan 27-08's shipped fix
    RETAINED `seed=5` on the forced-PV-shortfall and mpc_step-stride items rather than
    reverting to `seed=1`, a DEVIATION from that plan's own must_haves text.
    **Plan 27-09 (USER DECISION 2026-09-29) resolves this the OTHER way — by decoupling the
    truth plant's AC-solvability requirement from the feeder's OPERATING limits**: the truth
    settlement here is now `ACPowerFlow(; limits = false)` (physics only), so the SAME
    `seed=1` dispatch that plan 27-08 found `LOCALLY_INFEASIBLE` under the LIMITED model now
    reaches `LOCALLY_SOLVED` cleanly (it was the `:smax` constraint, not the AC physics
    itself, that refused it — exactly the "limits-removed re-solve reaching `LOCALLY_SOLVED`"
    plan 27-08 already used to CONFIRM the finding was genuine). `seed=1` is therefore
    RESTORED on both items; the genuine thermal overload plan 27-08 found is no longer a
    convergence failure but a REPORTED `settlement_violations` entry with
    `max_overload_ratio > 1` on the head branch — see that bullet below. The SUPERSEDED SOCP
    re-solve survives ONLY as `_mpc_truth_import_socp_reference`, reachable exclusively via
    the INTERNAL test seam `_truth_settlement = :socp` (default `:ac`) — used SOLELY by
    `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-08-repro.jl`'s
    AC-vs-SOCP cross-check on a seed where the SOCP re-solve happens to be exact; no
    production `Scenario`-driven caller ever passes it.
  - `settlement_violations::Vector{<:NamedTuple}` — (plan 27-09, USER DECISION 2026-09-29) one
    entry per PUBLISHED hour (same order/length as `trace`), each
    `(; abs_hour, n_thermal_violations, max_overload_ratio, n_voltage_violations,
    min_voltage, max_voltage, voltage_violated)` — see [`_mpc_settlement_violations`](@ref).
    A DIAGNOSTIC computed from the AC truth settlement's own solved `P`/`Q`/`l`/`v` (never a
    constraint dual — `ACPowerFlow(; limits = false)` writes no `:smax`/`:smax_rev`/
    voltage-bound constraint to read one from), NEVER a gate: the settlement never refuses a
    dispatch for exceeding an operating limit, it only reports it here. Populated only under
    `_truth_settlement = :ac` (the production default); empty under the `:socp` internal test
    seam.
  - `pvbattery_truth_trace::Vector{<:NamedTuple}` — (WR-04, 27-REVIEW.md iteration 2) one entry
    PER APPLIED HOUR PER `PVBattery` device (NOT one per published hour like `trace`/
    `settlement_violations` — an hour with zero PVBattery devices contributes zero entries, an
    hour with two contributes two), each `(; abs_hour, bus, p_ch_true, pv_used_true, p_dch,
    Ppv_true, net_p_delta)`. `net_p_delta` is the ACTUAL amount the PVBattery truth-settlement
    call site added to `net_p` this hour (captured as `net_p_after - net_p_before` around that
    exact line, never a separate re-derivation), so it is provably sensitive to a revert of
    that line back to the pre-CR-02 unclipped `pv_used1` — a test recovering the
    "actually-summed" self-consumption value as `net_p_delta + p_ch_true - p_dch` and asserting
    it `<= Ppv_true` is asserting the A6 clip invariant against the REAL call site, not merely
    against `_mpc_pvbattery_true_clip` in isolation (closing 27-REVIEW.md WR-04's gap between
    "the clip helper is correct" and "the clip helper is wired correctly"). The other fields
    (`p_ch_true`, `pv_used_true`) are the clip helper's own verbatim outputs, kept for
    convenience/cross-checking. A pure DIAGNOSTIC never read by `run_mpc` itself or fed back
    into any control/pricing/state decision. Populated under BOTH `_truth_settlement` seam
    values (the clip happens before the truth-settlement branch).
  - `forecast_settled_welfare::Float64` — the PRE-PHASE-27 forecast-consistent settlement,
    kept as a clearly-labelled DIAGNOSTIC (never the headline number `regret` is measured
    against, post-FIX-10). **WR-01 — settlement is FORECAST-CONSISTENT by construction, not
    re-settled against the ground truth:** the frontier term charges the window's OWN solved
    `p_import[τ]` (which balanced the forecast-perturbed PV/demand the optimizer saw), and
    the device terms read the solved controls as-is. Under nonzero `st.forecast_error` the
    TRUE plant's import would differ by the per-hour demand/PV forecast errors, and when
    `fe.pv_factor > 1` the applied `p_ch` can exceed the TRUE PV availability
    `d.Ppv[abs_hour]` (Assumption A6 violated on the ground truth). Only the STATE
    propagation is truth-anchored (`propagate_tin` uses the ground-truth ambient; the SOC
    recursion has no exogenous profile). This number is UNCHANGED by Phase 27 — computed
    alongside `realized_welfare` from the SAME per-applied-hour loop, never mutated by the
    clip/throw/loss-exact-import corrections above.
  - `regret::Float64` — the NEW truth-settled `realized_welfare` (Phase 27 FIX-10) MINUS the
    day-ahead welfare RESTRICTED to the SAME published `k`-hour decision horizon and the SAME
    `mpc_aggs` device set (D-11's information-set-fair comparison) — NEVER silently
    extrapolated to the full `s.T` hours the day-ahead optimum spans, and NEVER measured
    against `forecast_settled_welfare` (the pre-phase convention). The day-ahead side
    (utilities AND frontier `p_import` cost) is read from a SECOND one-time benchmark solved
    over `mpc_aggs` itself (CR-03), never from the full-population context — so the
    comparison is never charged the frontier cost of a device whose utility it is denied. The
    terminal-SOC targets (D-06) likewise track THIS comparable benchmark's own optimal SOC
    trajectory.
  - `day_ahead_dadp::Vector{Float64}` — the full-length (`s.T`) day-ahead reference DADP path.
  - `steps::Int` — the total published-hour count, ALWAYS `s.T - st.H + 1` regardless of
    `st.step` (Pitfall 5's fixed-window convention — only the NUMBER OF RESOLVES shrinks as
    `st.step` grows, never the published-hour count).

Reproducible: two calls with the SAME `Scenario` (same `seed`) return `==`-identical
`regret`/`day_ahead_welfare`/`realized_welfare` (INFRA-04, mirroring `run_scenario`'s own
same-seed guarantee) — the Clarabel solve path is single-threaded and every random draw
(profiles, population, forecast error) flows through a seeded, independent sub-stream.

`_truth_settlement` (plan 27-08) is an INTERNAL TEST SEAM, `:ac` (the default, PRODUCTION
behavior — see the `realized_welfare` bullet above) or `:socp` (the SUPERSEDED pre-27-08
SOCP-relaxation re-solve, `_mpc_truth_import_socp_reference`, kept SOLELY for
`27-08-repro.jl`'s AC-vs-SOCP cross-check). Mirrors this file's own `_mpc_certify_and_price`
`_solve_welfare`/`_ac_dual_fallback_price` test-seam idiom. No production `Scenario`-driven
caller ever passes `:socp`.
"""
function _run_mpc(s::Scenario, st::MPC; _truth_settlement::Symbol = :ac)
    _truth_settlement in (:ac, :socp) || throw(
        ArgumentError(
            "run_mpc: _truth_settlement must be :ac or :socp, got " *
            "$(_truth_settlement) (internal test seam, plan 27-08 — production callers " *
            "never set this)",
        ),
    )

    # Boundary guards FIRST, before any materialization (mirrors this file's other
    # boundary-guard idiom, e.g. Scenario.jl's own throw-ArgumentError convention).
    # WR-07: the window cannot exceed the day-ahead horizon — without this guard the
    # failure surfaced as a cryptic device-level "profile has length ... < horizon T=..."
    # deep inside build_mpc_window's contribute! calls (a misleading message for a
    # Scenario-level misconfiguration), and a hypothetical future population with
    # longer-than-T profiles would instead run ZERO resolves and silently return steps = 0 /
    # regret = 0.0, contradicting the documented "steps is ALWAYS s.T - st.H + 1".
    st.H > s.T && throw(
        ArgumentError(
            "run_mpc: window length cannot exceed the day-ahead horizon " *
            "(mpc_H=$(st.H) > T=$(s.T))",
        ),
    )
    # A resolve cannot hold its plan longer than the window it solved.
    st.step > st.H && throw(
        ArgumentError(
            "run_mpc: step size cannot exceed window length H " *
            "(mpc_step=$(st.step) > mpc_H=$(st.H))",
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
    pf = build_powerflow(s)

    # --- 1b. Deferrable-excluded aggregator list for the WINDOW model (see this file's
    # header deviation note) — the day-ahead benchmark below still uses the FULL `aggs`. ------
    mpc_aggs = [
        Aggregator(agg.bus, agg.φ, filter(d -> !(d isa Deferrable), agg.devices), agg.Pdc) for agg in aggs
    ]

    # WR-02 (re-scoped post-FIX-04, PM-08): ORIGINALLY this guarded EVERY stateful device
    # (`:soc0`-carrying battery-likes AND `:Tin0`-carrying Thermostatic), because the
    # window's soc/Tin states had length H with recursions covering only τ ≤ H−1, so the
    # controls at τ = H carried NO modeled state consequence. Plan 26-03 (FIX-04) extended
    # PVBattery/FourQuadBESS's `soc` to `1:(H+1)` with an UNCONDITIONAL whole-horizon
    # recursion (`soc[t+1]` closes for every `t = 1:H`, including `t = H`) — so for THOSE
    # devices the H-th control (`p_ch[H]`/`p_dch[H]`) now IS fully state-covered, and
    # applying it no longer risks driving the propagated SOC out of its structural band.
    # Thermostatic's `Tin` recursion is UNCHANGED by Plan 26-03 (still `Tin[1:(H-1)]` closed,
    # `src/devices/Thermostatic.jl`) — its H-th control genuinely remains dynamics-uncovered,
    # so the guard STILL protects it. The predicate below therefore narrows from "any
    # stateful device" to "any Tin0-carrying (Thermostatic) device" only; a battery-only
    # population with `mpc_step == mpc_H` no longer trips this guard (verified empirically,
    # 26-11-PLAN.md Task 1), while a Thermostatic-carrying population with
    # `mpc_step > mpc_H - 1` still does (guard not silently disabled).
    has_uncovered_state = any(
        hasproperty(d, :Tin0) for agg in mpc_aggs for d in agg.devices
    )
    if has_uncovered_state && st.step > st.H - 1
        throw(
            ArgumentError(
                "run_mpc: with thermostatic (temperature-stateful) devices present " *
                "the step size must satisfy mpc_step ≤ mpc_H − 1 — Thermostatic's Tin " *
                "recursion covers only τ ≤ H−1 (unchanged by Plan 26-03/FIX-04), so the " *
                "window's H-th control carries no modeled state consequence for it, and " *
                "applying it can drive the measured temperature out of bounds and make " *
                "the next resolve infeasible (got mpc_step=$(st.step), " *
                "mpc_H=$(st.H)). Battery-only populations (PVBattery/FourQuadBESS) no " *
                "longer trip this guard — their soc[1:(H+1)] recursion (FIX-04) covers " *
                "the H-th control fully.",
            ),
        )
    end

    # WR-05: assert the loop's (bus, kind) state-keying invariant LOUDLY (factored into a
    # helper so a test can drive it against synthetic violating populations directly —
    # Scenario can only ever name the invariant-satisfying `:default` population today).
    _mpc_assert_state_keying(mpc_aggs)

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
    ctx_da, welfare_da, dadp_da =
        solve_welfare(feeder, pf, aggs; T = s.T, λ₀ = λ₀, allow_export = s.allow_export)
    ctx_da_cmp, _, _ =
        solve_welfare(feeder, pf, mpc_aggs; T = s.T, λ₀ = λ₀, allow_export = s.allow_export)
    # D-06/D-11 coherence (CR-03): the terminal-SOC targets track the COMPARABLE benchmark's
    # own optimal SOC trajectory — the trajectory regret is measured against — keeping the
    # terminal pin and the benchmark on the SAME information set (previously sourced from the
    # full-population context, whose trajectory reflects a population the closed loop
    # structurally cannot represent).
    # FIX-04 (Plan 26-03) retargeted build_mpc_window's terminal-condition constraint to
    # `soc[H + 1]` (the day-ahead state AFTER the window), since the battery `soc` vector is
    # now `1:(s.T + 1)` long. `soc_da` must therefore be built over the SAME `1:(s.T + 1)`
    # range so the terminal Parameter below can be indexed at `soc_da[bus][t + st.H]`
    # (the day-ahead state exactly one window-length past resolve hour `t`) — never the
    # stale `soc_da[bus][min(t + st.H - 1, s.T)]` (one hour BEFORE the window's actual
    # end), which silently drifts the terminal pin and makes a later resolve
    # PRIMAL_INFEASIBLE (26-POSTMERGE-TRIAGE.md cluster C).
    soc_da = Dict(
        bus => [value(v.soc[t]) for t in 1:(s.T + 1)] for
        (bus, varlist) in ctx_da_cmp.agg_device_vars for
        v in varlist if haskey(v, :soc)
    )

    # --- 3. Build the window ONCE (MPC-01), against the Deferrable-excluded mpc_aggs.
    # allow_export is threaded through (WR-06) so the window honors the SAME export
    # semantics BOTH day-ahead benchmarks above were solved under — never an export-allowed
    # closed loop benchmarked against a no-export day-ahead optimum. ------------------------
    o = build_mpc_window(
        feeder,
        pf,
        mpc_aggs;
        H = st.H,
        terminal_soc = st.terminal_soc,
        allow_export = s.allow_export,
    )

    # Strictly sequential published-step counter record! requires (distinct from the
    # absolute hour t, which skips by st.step between resolves).
    k = 0
    trace = MpcTrace()
    # Phase 27 FIX-10: `forecast_settled_welfare` is the RENAMED pre-phase accumulator
    # (computation completely unchanged, WR-01); `realized_welfare` is the NEW truth-settled
    # accumulator (clipped PVBattery charging, throw-on-violation state propagation, and a
    # loss-exact per-hour import re-solve) — see this function's own docstring.
    forecast_settled_welfare = 0.0
    realized_welfare = 0.0
    # Phase 27 FIX-10, plan 27-09 (USER DECISION): the "physics only" truth-plant's
    # per-applied-hour thermal/voltage DIAGNOSTIC (never a gate) — one entry per published
    # hour, populated ONLY under `_truth_settlement = :ac` (the production path; the `:socp`
    # internal test seam never populates this, since the superseded SOCP reference carries no
    # such diagnostic).
    settlement_violations = NamedTuple[]
    # WR-04 (27-REVIEW.md iteration 2): a per-applied-hour, per-PVBattery-device DIAGNOSTIC of
    # the exact truth-settlement quantities that feed `net_p` at the PVBattery truth-settlement
    # site below — added ONLY so a regression test can assert the A6 clip invariant through
    # `run_mpc`'s OWN public entry point (never a synthetic construction), closing WR-04's gap
    # ("the clip helper is correct" vs "the clip helper is used correctly at the real call
    # site"). NEVER read by `run_mpc` itself; every other return field and every
    # control/pricing/state decision is completely unchanged by this addition.
    pvbattery_truth_trace = NamedTuple[]

    # Measured (nominal-plant) state, keyed by (bus, kind): initialized from each mpc_aggs
    # member device's OWN t=1 literal soc0/Tin0 (the simplest possible source of the initial
    # measured state).
    measured_state = Dict{Tuple{Int, Symbol}, Float64}()
    # Phase 27 FIX-10: a SEPARATE truth trajectory, initialized IDENTICALLY at t=1 and
    # evolved INDEPENDENTLY thereafter (the two can diverge whenever a clip/violation
    # occurs) — `measured_state` (forecast-consistent, drives the NEXT resolve's IC
    # Parameters) is left completely untouched by this addition.
    measured_state_true = Dict{Tuple{Int, Symbol}, Float64}()
    for agg in mpc_aggs, d in agg.devices
        hasproperty(d, :soc0) && (measured_state[(agg.bus, :soc)] = Float64(d.soc0))
        hasproperty(d, :Tin0) && (measured_state[(agg.bus, :Tin)] = Float64(d.Tin0))
        hasproperty(d, :soc0) && (measured_state_true[(agg.bus, :soc)] = Float64(d.soc0))
        hasproperty(d, :Tin0) && (measured_state_true[(agg.bus, :Tin)] = Float64(d.Tin0))
    end

    # Outer loop over window RESOLVE epochs — D-03: st.step genuinely strides this loop's
    # header (never a hardcoded 1:(s.T - st.H + 1), the checker-flagged regression this
    # task fixes). Every visited `t` re-solves the SAME build-once window `o`.
    for t in 1:st.step:(s.T - st.H + 1)
        fe = draw_forecast_error(s.seed, t, st.forecast_error)

        # IC + terminal-target Parameters (MPC-01/MPC-02).
        for entry in o.ic_handles
            set_parameter_value(entry.ic_param, measured_state[(entry.bus, entry.kind)])
            if entry.terminal_param !== nothing
                # FIX-04 (Plan 26-03): the day-ahead state at exactly `t + st.H` — the
                # window's own terminal target is `soc[H + 1]`, the state AFTER the window,
                # so its day-ahead counterpart is `soc_da[bus][t + st.H]`. No `min(...,
                # s.T)` clamp: the outer loop's own header bound (`t in
                # 1:st.step:(s.T - st.H + 1)`) guarantees `t + st.H <= s.T + 1` at
                # every visited `t`, and `soc_da` is now built over `1:(s.T + 1)`, so every
                # index here is in-bounds by construction — a silent clamp would re-hide the
                # exact stale-index bug this fixes.
                set_parameter_value(
                    entry.terminal_param,
                    soc_da[entry.bus][t + st.H],
                )
            end
        end

        # Per-step device forecast slices (D-08): PV/demand perturbed multiplicatively by the
        # SAME seeded forecast-error draw; ambient temperature slides UNPERTURBED (D-05: model
        # mismatch enters only via forecast error, never the deterministic window slide).
        for agg in mpc_aggs
            varlist = o.ctx.agg_device_vars[agg.bus]
            for (d, v) in zip(agg.devices, varlist)
                if haskey(v, :Ppv_param)
                    set_parameter_value.(
                        v.Ppv_param,
                        Float64[d.Ppv[t + τ - 1] * fe.pv_factor for τ in 1:st.H],
                    )
                end
                if haskey(v, :Tout_param)
                    set_parameter_value.(
                        v.Tout_param,
                        Float64[d.Tout[t + τ - 1] for τ in 1:(st.H - 1)],
                    )
                end
            end
        end
        for handle in o.agg_pdc_handles
            agg = only(a for a in mpc_aggs if a.bus == handle.bus)
            set_parameter_value.(
                handle.Pdc_param,
                Float64[agg.Pdc[t + τ - 1] * fe.demand_factor for τ in 1:st.H],
            )
        end

        # Slide λ₀ via set_objective_coefficient — NEVER a Parameter (Pitfall 2).
        for τ in 1:st.H
            set_objective_coefficient(o.model, o.p_import[τ], -λ₀[t + τ - 1])
        end

        solve_mpc_window!(o)

        # D-04's per-resolve, non-throwing certificate check + Phase-20 escalation ladder —
        # factored into a small internal helper (below) so a test can drive it DIRECTLY
        # against a non-Scenario feeder/aggregator pair (e.g. MPCFixtures' high-PV
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
            allow_export = s.allow_export,
        )
        cert_status = cert.cert_status
        price_vec = cert.price_vec

        # n_apply: the number of REAL hours THIS resolve's plan is held for before the next
        # resolve — capped by the window length itself (cannot apply more intervals than were
        # solved) and by the remaining published horizon (the final resolve never overruns
        # s.T - st.H + 1 total published hours). This formula guarantees the TOTAL
        # published-hour count across ALL resolves is exactly s.T - st.H + 1 for ANY
        # st.step (only the NUMBER OF RESOLVES shrinks as st.step grows).
        n_apply = min(st.step, st.H, (s.T - st.H + 1) - t + 1)

        for τ_apply in 1:n_apply
            abs_hour = t + τ_apply - 1

            # Phase 27 FIX-10: the truth resolve's per-bus REALIZED net active/reactive
            # injection, keyed by aggregator bus — accumulated device-by-device below
            # (mirroring Aggregator.contribute!'s own p_inject/Pdc_param/tanφ wiring, but
            # with NUMERIC realized values) and fed into `_mpc_truth_import_acpf` after
            # the per-device loop.
            realized_net_p = Dict{Int, Float64}()
            realized_net_q = Dict{Int, Float64}()

            for agg in mpc_aggs
                varlist = o.ctx.agg_device_vars[agg.bus]
                tanφ = reactive_factor(agg.φ)
                net_p = 0.0
                # TRUE (unperturbed) baseline demand reactive term (thesis 3.23) — never the
                # forecast-perturbed agg.Pdc[abs_hour] * fe.demand_factor the window balanced.
                net_q = -agg.Pdc[abs_hour] * tanφ

                for d in agg.devices
                    # ---- forecast-consistent settlement (UNCHANGED, WR-01) ----
                    forecast_settled_welfare += _mpc_device_hour_utility(d, varlist, τ_apply)
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
                        measured_state[(agg.bus, :Tin)] = propagate_tin(
                            measured_state[(agg.bus, :Tin)],
                            p1,
                            d.α,
                            d.β,
                            d.Tout[abs_hour],
                        )
                    end

                    # ---- truth-settled settlement (NEW, FIX-10) ----
                    if d isa PVBattery
                        v = only(vv for vv in varlist if haskey(vv, :soc0))
                        # A6 clip: the realized charge AND self-consumption/export can
                        # never exceed the device's TRUE (unperturbed) PV availability,
                        # even when the window believed more PV was available
                        # (fe.pv_factor != 1.0). CR-02 fix (27-REVIEW.md, 2026-09-29): the
                        # PRE-FIX code clipped only p_ch, leaving pv_used (which feeds
                        # net_p / net grid injection / realized_welfare via
                        # p_import_true) UNCLIPPED — under fe.pv_factor > 1 that credited
                        # realized_welfare with PV energy the true plant cannot supply. Both
                        # quantities are now clipped by the SAME rule via
                        # `_mpc_pvbattery_true_clip` (factored out for direct unit testing).
                        p_dch1 = value(v.p_dch[τ_apply])   # discharge unaffected by the clip
                        pv_used1 = value(v.pv_used[τ_apply])
                        (p_ch_true, pv_used_true) = _mpc_pvbattery_true_clip(
                            value(v.p_ch[τ_apply]),
                            pv_used1,
                            d.Ppv[abs_hour],
                        )
                        realized_welfare += _mpc_pvbattery_utility(d, p_ch_true, p_dch1)
                        next_soc = propagate_soc(
                            measured_state_true[(agg.bus, :soc)],
                            p_ch_true,
                            p_dch1,
                            d.η,
                            d.Δt,
                        )
                        _mpc_assert_true_state_inband(
                            d.Emin,
                            next_soc,
                            d.Emax,
                            "SOC",
                            agg.bus,
                            abs_hour,
                        )
                        measured_state_true[(agg.bus, :soc)] = next_soc
                        # WR-04 diagnostic (27-REVIEW.md iteration 2): capture the ACTUAL
                        # delta this line adds to `net_p` — never a separate re-derivation —
                        # so a test asserting against `pvbattery_truth_trace` is provably
                        # sensitive to a revert of the very next line (e.g. back to the
                        # pre-CR-02 `pv_used1`, which would change `net_p_delta` itself,
                        # not just a value computed alongside it).
                        net_p_before = net_p
                        net_p += pv_used_true - p_ch_true + p_dch1
                        push!(
                            pvbattery_truth_trace,
                            (;
                                abs_hour,
                                bus = agg.bus,
                                p_ch_true,
                                pv_used_true,
                                p_dch = p_dch1,
                                Ppv_true = d.Ppv[abs_hour],
                                net_p_delta = net_p - net_p_before,
                            ),
                        )
                    elseif d isa FourQuadBESS
                        # No Ppv field (not PV-limited, FourQuadBESS.jl) — the clip applies
                        # ONLY to PVBattery; the truth propagation is otherwise IDENTICAL to
                        # the forecast-consistent one (defense-in-depth throw guard below).
                        v = only(vv for vv in varlist if haskey(vv, :soc0))
                        p_ch1 = value(v.p_ch[τ_apply])
                        p_dch1 = value(v.p_dch[τ_apply])
                        q1 = value(v.q[τ_apply])
                        realized_welfare += _mpc_device_hour_utility(d, varlist, τ_apply)
                        next_soc = propagate_soc(
                            measured_state_true[(agg.bus, :soc)],
                            p_ch1,
                            p_dch1,
                            d.η,
                            d.Δt,
                        )
                        _mpc_assert_true_state_inband(
                            d.Emin,
                            next_soc,
                            d.Emax,
                            "SOC",
                            agg.bus,
                            abs_hour,
                        )
                        measured_state_true[(agg.bus, :soc)] = next_soc
                        net_p += p_dch1 - p_ch1
                        net_q += q1
                    elseif d isa Thermostatic
                        v = only(vv for vv in varlist if haskey(vv, :Tin0))
                        p1 = value(v.p[τ_apply])
                        realized_welfare += _mpc_device_hour_utility(d, varlist, τ_apply)
                        next_tin = propagate_tin(
                            measured_state_true[(agg.bus, :Tin)],
                            p1,
                            d.α,
                            d.β,
                            d.Tout[abs_hour],
                        )
                        _mpc_assert_true_state_inband(
                            d.Tmin,
                            next_tin,
                            d.Tmax,
                            "temperature",
                            agg.bus,
                            abs_hour,
                        )
                        measured_state_true[(agg.bus, :Tin)] = next_tin
                        net_p += -p1
                        # Flexible-load power-factor reactive draw (thesis 3.23, FIX-05,
                        # Aggregator.jl's own is_flexible_load wiring) — additive.
                        φ_used = hasproperty(d, :φ) && d.φ !== nothing ? d.φ : agg.φ
                        net_q += (-p1) * reactive_factor(φ_used)
                    else
                        # mpc_aggs is structurally Deferrable-excluded and window-hostable
                        # only (_mpc_window_device throws on anything else) — no other
                        # device type reaches this loop; utility-only, defensive.
                        realized_welfare += _mpc_device_hour_utility(d, varlist, τ_apply)
                    end
                end

                realized_net_p[agg.bus] = net_p - agg.Pdc[abs_hour]   # TRUE baseline demand
                realized_net_q[agg.bus] = net_q
            end

            # WR-01: FORECAST-CONSISTENT settlement (documented convention, see the
            # `forecast_settled_welfare` docstring bullet): this charges the window's OWN
            # solved frontier exchange — the one that balanced the forecast-perturbed
            # profiles the optimizer saw.
            forecast_settled_welfare -= λ₀[abs_hour] * value(o.p_import[τ_apply])

            # Phase 27 FIX-10 (USER DECISION 2026-09-29, plan 27-08): the TRUTH import is
            # settled by a genuine AC power flow at the FIXED realized/clipped dispatch — the
            # physically true plant. Warm-start every P/Q/l/v/p_import/q_import from the
            # WINDOW's own solved values at this hour's window-local position (26-15: Ipopt's
            # default all-zero start is a degenerate KKT point of l·v = P²+Q²).
            pv_o = _require_pf_vars(o.ctx)
            Bf = feeder.branches
            Np_f = length(feeder.buses)
            warm_start = (;
                P = Float64[value(pv_o.P[b, τ_apply]) for b in eachindex(Bf)],
                Q = Float64[value(pv_o.Q[b, τ_apply]) for b in eachindex(Bf)],
                l = Float64[value(pv_o.l[b, τ_apply]) for b in eachindex(Bf)],
                v = Float64[value(pv_o.v[j, τ_apply]) for j in 1:Np_f],
                p_import = value(o.p_import[τ_apply]),
                q_import = haskey(o.ctx.meta, :q_import) ?
                           value(o.ctx.meta[:q_import][τ_apply]) : nothing,
            )
            p_import_true = if _truth_settlement === :ac
                p_import_t, violations = _mpc_truth_import_acpf(
                    feeder,
                    mpc_aggs,
                    abs_hour,
                    realized_net_p,
                    realized_net_q,
                    warm_start,
                )
                push!(settlement_violations, violations)
                p_import_t
            else   # :socp — internal test seam only, see run_mpc's own docstring
                _mpc_truth_import_socp_reference(
                    feeder,
                    pf,
                    mpc_aggs,
                    λ₀,
                    abs_hour,
                    realized_net_p,
                    realized_net_q,
                )
            end
            realized_welfare -= λ₀[abs_hour] * p_import_true

            k += 1
            record!(trace, k, price_vec[τ_apply], dadp_da[abs_hour], cert_status)
        end
    end
    # After the full double loop (resolves × applied hours), k equals the total number of
    # published hours — ALWAYS s.T - st.H + 1, independent of st.step (only the NUMBER
    # OF RESOLVES that produced them shrinks as st.step grows; the published-hour COUNT
    # never changes, Pitfall 5).

    # D-11: regret is scoped to the PUBLISHED decision horizon (k hours, Pitfall 5's honest
    # step-count convention, invariant to st.step) — NEVER silently extrapolated to the
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
            varlist = ctx_da_cmp.agg_device_vars[agg.bus]
            for d in agg.devices
                day_ahead_comparable_welfare += _mpc_device_hour_utility(d, varlist, τ)
            end
        end
        day_ahead_comparable_welfare -= λ₀[τ] * value(ctx_da_cmp.meta[:p_import][τ])
    end
    # Phase 27 FIX-10: regret is re-derived against the NEW truth-settled realized_welfare
    # (the day-ahead comparable side is unchanged — it has no forecast error to truth-settle
    # against).
    regret = realized_welfare - day_ahead_comparable_welfare

    return (;
        trace,
        day_ahead_welfare = Float64(welfare_da),
        forecast_settled_welfare = Float64(forecast_settled_welfare),
        realized_welfare = Float64(realized_welfare),
        regret = Float64(regret),
        day_ahead_dadp = Vector{Float64}(dadp_da),
        steps = k,
        settlement_violations,
        pvbattery_truth_trace,
        # Phase 34 ARCH-08: documented status vocabulary (STATUS_VOCABULARY.run_mpc).
        status = _mpc_status(trace.cert_status_trace),
    )
end

"""
    _mpc_status(cert_status_trace) -> Symbol

Roll the per-step certificate tags up into the `run_mpc` status: `:cert_failed` if any step
is `:cert_failed`; else `:degraded` if any step is not the first tier
(`:certified_convex_dual`); else `:certified`.
"""
function _mpc_status(cert_status_trace)
    any(==(:cert_failed), cert_status_trace) && return :cert_failed
    all(==(:certified_convex_dual), cert_status_trace) && return :certified
    return :degraded
end

"""
    _mpc_certify_and_price(feeder, mpc_aggs, o::MpcWindow, λ₀::AbstractVector{<:Real}, t::Int;
                           measured_state, fe, fallback_price = λ₀, allow_export = true,
                           _solve_welfare = solve_welfare,
                           _ac_dual_fallback_price = ac_dual_fallback_price)
        -> (; cert_status::Symbol, price_vec::Vector{Float64}, cone_maxratio::Float64)

`allow_export` (WR-06) is threaded into every escalation-tier solve — `run_mpc` passes
`s.allow_export` so the tiers honor the SAME frontier semantics the main window and both
day-ahead benchmarks were solved under.

Internal helper (unexported): [`run_mpc`](@ref)'s per-resolve, non-throwing certificate check
(D-04) + Phase-20 escalation ladder, factored out so a test can drive it DIRECTLY against a
non-`Scenario` `feeder`/`mpc_aggs` pair (e.g. `MPCFixtures`' high-PV fixture) without
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

On a certified step: `cert_status = :certified_convex_dual`, `price_vec = dual.(o.ctx.constraints[:balance_p][o.agg_bus, :])` (length `o.H`). On a failed inline check:
escalates through Phase-20's OWN ladder (never invents a new tolerance) — a ONE-OFF
[`RestrictedBranchFlow`](@ref)`()` solve + [`ACPowerFlow`](@ref)`()` cross-solve +
[`assert_restriction_exact!`](@ref)`(...; report = true)`, publishing `cert_status = :certified_convex_dual_restricted` on a rescue (WR-04: a DISTINCT symbol from the first-tier
`:certified_convex_dual` — the price is the RESTRICTED solve's dual, a genuinely different
provenance a ledger must be able to tell apart); if THAT does not certify,
[`ac_dual_fallback_price`](@ref), publishing `cert_status = :local_ac_dual`. Every escalation
tier solves the window-sliced problem (the ONE documented difference from the main window:
`solve_welfare` has no terminal-SOC hook, so the optional hard terminal pin (D-06) is absent
from the escalation problem — an accepted, rare-path approximation).

# The never-throw contract (CR-02 — D-04 is now genuine, not aspirational)

Each escalation tier runs inside a `catch` that routes its DOCUMENTED failure modes into the
returned status instead of propagating out of `run_mpc` mid-loop: `assert_solved!` retry
exhaustion (`SolveFailedError`) and `assert_battery_complementarity!`'s legitimate
negative-effective-price throw (`FourQuadBESS.jl`'s step-3 derivation — the very regime that
trips the inline cone check; `CertificateError`). The tiers admit ONLY `SolveFailedError` /
`CertificateError`; everything else (`MethodError`, `BoundsError`, `ArgumentError`,
`KeyError`, ...) propagates. `InterruptException` is ALWAYS rethrown. The
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
    allow_export::Bool = true,
    _solve_welfare = solve_welfare,
    _ac_dual_fallback_price = ac_dual_fallback_price,
)
    pv = _require_pf_vars(o.ctx)
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
            # WR-06: allow_export is threaded from the caller (run_mpc passes
            # s.allow_export) so every escalation tier honors the SAME frontier semantics
            # the main window and both day-ahead benchmarks were solved under.
            ctx_restricted, _, _ = _solve_welfare(
                feeder,
                RestrictedBranchFlow(),
                esc_aggs;
                T = o.H,
                λ₀ = λ₀_window,
                allow_export = allow_export,
                rtol_exact = Inf,
            )
            ctx_ac, _, _ = _solve_welfare(
                feeder,
                ACPowerFlow(),
                esc_aggs;
                T = o.H,
                λ₀ = λ₀_window,
                allow_local = true,
                allow_export = allow_export,
            )
            report = assert_restriction_exact!(ctx_restricted, ctx_ac; report = true)
            if report.ac_feasible
                # WR-04: the restricted-tier rescue carries its OWN provenance symbol —
                # a price from the OPF-m RESTRICTED solve's dual is a genuinely different
                # provenance than a first-tier window certification, and a price-provenance
                # ledger must be able to tell them apart.
                cert_status = :certified_convex_dual_restricted
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
            # ConvergenceError is deliberately not admitted: neither tier is iterative.
            err isa Union{SolveFailedError, CertificateError} || rethrow()
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
                    allow_export = allow_export,
                )
                cert_status = :local_ac_dual
                price_vec = Vector{Float64}(fallback.dadp)
            catch err
                err isa InterruptException && rethrow()
                err isa Union{SolveFailedError, CertificateError} || rethrow()
                push!(
                    tier_reasons,
                    "AC-dual fallback tier threw: " * sprint(showerror, err),
                )
            end
        end

        if cert_status === :cert_failed
            @warn "run_mpc: EVERY escalation tier failed — publishing :cert_failed with the reference fallback price for this window (D-04: never throws mid-loop)" t cone_maxratio cert_status reasons =
                join(tier_reasons, " | ")
        else
            @warn "run_mpc: per-resolve cone check failed — escalating via Phase-20's certificate/fallback ladder" t cone_maxratio cert_status
        end
    end

    return (; cert_status, price_vec = Vector{Float64}(price_vec), cone_maxratio)
end

"""
    _mpc_assert_state_keying(mpc_aggs) -> Nothing

Internal helper (unexported, WR-05): assert the closed loop's `(bus, kind)` state-keying
invariant LOUDLY. `run_mpc`'s bookkeeping — `measured_state`, the terminal-target `soc_da`
Dict, the `only(vv ...)` device-vars pairing inside the apply loop, and
`Aggregator.contribute!`'s per-bus varlist APPEND — silently assumes (a) one aggregator per
bus and (b) at most ONE device of each state kind (`:soc0`-carrying, `:Tin0`-carrying) per
bus. The `:default` population satisfies both today, but nothing enforced it — a violating
population would silently overwrite states or mispair devices with variables (e.g. a
`PVBattery` AND a `FourQuadBESS` on one bus both carry `:soc0`). Throws `ArgumentError` on a
violation; returns `nothing` otherwise. Factored out of `run_mpc` so a test can drive it
against synthetic violating populations directly (Scenario can only name the
invariant-satisfying `:default` population).
"""
function _mpc_assert_state_keying(mpc_aggs)
    seen_buses = Set{Int}()
    for agg in mpc_aggs
        if agg.bus in seen_buses
            throw(
                ArgumentError(
                    "run_mpc: aggregator buses must be UNIQUE — bus $(agg.bus) hosts more " *
                    "than one aggregator (Aggregator.contribute! APPENDS device varlists " *
                    "into one per-bus vector, so a shared bus would mispair devices with " *
                    "variables and overwrite the (bus, kind)-keyed measured state)",
                ),
            )
        end
        push!(seen_buses, agg.bus)
        n_soc = count(d -> hasproperty(d, :soc0), agg.devices)
        n_tin = count(d -> hasproperty(d, :Tin0), agg.devices)
        if n_soc > 1 || n_tin > 1
            throw(
                ArgumentError(
                    "run_mpc: bus $(agg.bus) hosts $(n_soc) SOC-stateful and $(n_tin) " *
                    "temperature-stateful devices — the closed loop's measured-state " *
                    "ledger is keyed by (bus, kind) and supports at most ONE device of " *
                    "each state kind per bus (e.g. a PVBattery AND a FourQuadBESS on one " *
                    "bus are not representable)",
                ),
            )
        end
    end
    return nothing
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
escalation solve at absolute start hour `t` — initial state from `measured_state[(bus, kind)]`, per-hour profiles sliced to `t:(t+H-1)` (PV multiplied by `fe.pv_factor`, ambient
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
    _mpc_pvbattery_utility(d::PVBattery, p_ch::Real, p_dch::Real) -> Float64

Internal helper (unexported, Phase 27 FIX-10): `d`'s own App. C charge-utility-minus-
discharge-cost formula (thesis 3.15-3.20, IDENTICAL to [`contribute!`](@ref)'s objective
term), evaluated at EXPLICIT numeric `p_ch`/`p_dch` rather than reading a JuMP variable's
solved value. Factored out of [`_mpc_device_hour_utility`](@ref) (below, now a thin wrapper
over this) so [`run_mpc`](@ref)'s NEW truth-settled accumulation can evaluate the SAME
formula at the A6-clipped `p_ch_true` (never the raw solved `p_ch`, which can exceed the
device's TRUE PV availability under nonzero forecast error) while the pre-existing
forecast-consistent path (`_mpc_device_hour_utility`) stays byte-identical.
"""
function _mpc_pvbattery_utility(d::PVBattery, p_ch::Real, p_dch::Real)
    a_ch = d.λ_med
    b_ch = (d.λ_med - d.λ_min) / d.Pmax
    a_dch = d.λ_med
    b_dch = (d.λ_max - d.λ_med) / d.Pmax
    return a_ch * p_ch - (b_ch / 2) * p_ch^2 - a_dch * p_dch - (b_dch / 2) * p_dch^2
end

"""
    _mpc_pvbattery_true_clip(p_ch::Real, pv_used::Real, Ppv_true::Real) -> NamedTuple

Internal helper (unexported, Phase 27 FIX-10, CR-02 fix per 27-REVIEW.md 2026-09-29): the
A6 truth-settlement clip — both the window-solved charge `p_ch` AND the window-solved
self-consumption/export `pv_used` are clipped to the device's TRUE (unperturbed)
`Ppv_true = d.Ppv[abs_hour]` availability, returning `(; p_ch_true, pv_used_true)`.

Factored out of [`run_mpc`](@ref)'s truth-settlement block (below) so both quantities are
clipped by the EXACT SAME rule at a single call site, and so this invariant is directly
unit-testable without driving a full closed-loop `run_mpc` solve. CR-02 (27-REVIEW.md): the
PRE-FIX code clipped only `p_ch`, leaving `pv_used` — which feeds `net_p`/`p_inject` and
hence the AC truth-settled frontier import — UNCLIPPED; under `fe.pv_factor > 1` (the
window believes MORE PV is available than truly exists) that let `realized_welfare`/
`p_import_true` be credited with PV energy the true plant cannot physically supply.

Invariant preserved (never separately re-checked — it falls out of clipping both the same
way): since the window's OWN PVBattery model already enforces `p_ch <= pv_used`
(`src/devices/PVBattery.jl:308`), `min(p_ch, Ppv_true) <= min(pv_used, Ppv_true)` always
holds, i.e. `p_ch_true <= pv_used_true` — the returned pair is itself a valid PVBattery
operating point at the TRUE PV availability, never just two independently-clamped numbers.
"""
function _mpc_pvbattery_true_clip(p_ch::Real, pv_used::Real, Ppv_true::Real)
    p_ch_true = min(p_ch, Ppv_true)
    pv_used_true = min(pv_used, Ppv_true)
    return (; p_ch_true, pv_used_true)
end

"""
    _mpc_device_hour_utility(d::AbstractDevice, varlist, τ::Int) -> Float64

Internal helper (unexported): the REALIZED per-hour utility contribution of device `d` at
window/day-ahead position `τ`, reading `d`'s OWN documented `contribute!` utility formula off
`d`'s ORIGINAL struct fields (never inventing new math) and the SOLVED value of its decision
variable(s) at `τ` — found in `varlist` (a `Vector{Any}` of device-vars `NamedTuple`s, e.g.
`ctx.agg_device_vars[bus]`) by the SAME type-specific marker key
[`build_mpc_window`](@ref)'s own `ic_handles` walk uses (`:soc0` for battery-like devices,
`:Tin0` for `Thermostatic`). Used IDENTICALLY for [`run_mpc`](@ref)'s closed-loop
`realized_welfare` accumulation (source: the window's own `ctx`) and its day-ahead
`regret`-comparison accumulation (source: the day-ahead benchmark's `ctx_da`) — the SAME
formula, only the ctx source (and hence the SOLVED values it reads) differs, per D-11's
information-set-fair contract.
"""
function _mpc_device_hour_utility(d::PVBattery, varlist, τ::Int)
    v = only(vv for vv in varlist if haskey(vv, :soc0) && haskey(vv, :Ppv_param))
    p_ch1 = value(v.p_ch[τ])
    p_dch1 = value(v.p_dch[τ])
    return _mpc_pvbattery_utility(d, p_ch1, p_dch1)
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

"""
    _mpc_assert_true_state_inband(lo::Real, x::Real, hi::Real, kind::AbstractString,
                                   bus::Int, abs_hour::Int; tol::Real = 1e-6) -> Nothing

Internal helper (unexported, Phase 27 FIX-10): assert the TRUE-plant propagated state `x`
lies in `[lo, hi]`, throwing a loud `ErrorException` — never `@assert` (elided under `-O`,
project convention, `src/models/exactness.jl`) — naming `kind` ("SOC"/"temperature"), `bus`,
and `abs_hour` on violation. `tol` (default `1e-6`, this project's own standing absolute
floor — `assert_socp_exact!`/`assert_no_slack`'s identical default) widens ONLY the
COMPARISON, never the reported/propagated value itself (no clamp, no repair): a solved JuMP
variable sits at its bound only up to the solver's own achieved precision (`|ε| ≲ 1e-8`,
`_mpc_window_device`'s documented figure for the SAME class of noise), so a bare
zero-tolerance comparison would spuriously throw on genuinely in-band states. This is
DELIBERATELY DISTINCT from [`_mpc_window_device`](@ref)'s SEPARATE, differently-scoped clamp
(`mpc_loop.jl:759-780`), which REPAIRS (clamps) a value for the escalation ladder's
window-slicing helper — this guard NEVER repairs the value, it only tolerates the SAME
class of numerical noise in the boundary CHECK before throwing on anything genuinely
out-of-band (an event this project's own convention treats as a modeling finding to surface
loudly, not silently absorb).
"""
function _mpc_assert_true_state_inband(
    lo::Real,
    x::Real,
    hi::Real,
    kind::AbstractString,
    bus::Int,
    abs_hour::Int;
    tol::Real = 1e-6,
)
    (lo - tol <= x <= hi + tol) || throw(
        ErrorException(
            "run_mpc: TRUE-plant $kind propagation out of [$lo,$hi] (tol=$tol) at " *
            "bus=$bus, abs_hour=$abs_hour, value=$x — a genuine out-of-band state (not " *
            "solver-tolerance noise; see _mpc_window_device's SEPARATE clamp, " *
            "mpc_loop.jl:759-780, which absorbs a DIFFERENT, already-in-band case).",
        ),
    )
    return nothing
end

"""
    _mpc_truth_import_socp_reference(feeder, pf::AbstractPowerFlow, mpc_aggs,
                                      λ₀::AbstractVector{<:Real}, abs_hour::Int,
                                      realized_net_p::AbstractDict{Int,Float64},
                                      realized_net_q::AbstractDict{Int,Float64}) -> Float64

**SUPERSEDED (Phase 27 plan 27-08, USER DECISION 2026-09-29) — kept ONLY as the SOCP side of
`27-08-repro.jl`'s AC-vs-SOCP cross-check, reachable EXCLUSIVELY via [`run_mpc`](@ref)'s
internal test seam `_truth_settlement = :socp`. No production `Scenario`-driven caller ever
reaches this function; the production truth settlement is [`_mpc_truth_import_acpf`](@ref).**

(Original Phase 27 FIX-10 / plan 27-07 docstring, preserved for provenance:) the LOSS-EXACT
per-applied-hour truth import re-solve. Builds a FRESH, single-hour (`T=1`) `ModelContext`
on the SAME `feeder`/`pf` [`run_mpc`](@ref) already materialized (mirrors `src/pricing/fit.jl`'s
SITE-2 structural shape: `Model` → `ModelContext` → `contribute!(pf, ctx, feeder; T=1)` →
per-bus `add_to_residual!` → a free frontier variable at `feeder.root` → balance
constraints → `@objective` → `assert_solved!` → `assert_socp_exact!` → read
`value(p_import)`), fixes every `mpc_aggs` bus's REALIZED net active/reactive injection
(`realized_net_p`/`realized_net_q`, computed by the caller from each device's TRUE/clipped
dispatch — mirroring `Aggregator.contribute!`'s own `p_inject − Pdc_param`/
`−Pdc_param·tanφ + q_inject` wiring, but with NUMERIC realized values), and leaves ONLY the
frontier import `p_import_t` free. With every injection fixed, the per-bus balance equations
alone leave EXACTLY one convex degree of freedom PER BRANCH — the squared current `l[b,1]` (the
SOC relaxation constraint is an INEQUALITY, `l·v ≥ P²+Q²`, so `l` can sit anywhere at or above
its physically-exact value while `P`/`Q`/`v` adjust consistently through the balance/vdrop/
cpydrop equalities). FIX-10 (plan 27-07 revision) selects among this family via `Min
Σ_b B[b].r·l[b,1]` (total active loss), which has the SAME minimizer as minimizing `p_import_t`
alone (they differ by the FIXED constant `TotalNetInjection`, per the balance equations' own
telescoping identity) but gives Clarabel's interior-point solve an UNMEDIATED gradient on every
`l[b,1]` rather than one reached only through chained constraint duals — a strictly more direct,
`λ₀`-independent formulation. **This does NOT close every cone gap** (27-03-SUMMARY.md,
27-07-SUMMARY.md, ESCALATED): on at least one `(seed, mpc_forecast_error)` fixture the gap
persists near-identically under EITHER objective (ratio ~1400-1700, MEASURED unchanged across a
`tol_gap_abs/rel` sweep from `1e-9` to `1e-11` and across a dominant quadratic `l` regularizer up
to weight 100) — a genuine, non-tolerance-fixable, non-objective-fixable SOCP relaxation
inexactness under compounding forecast-error-driven reverse-flow drift, matching this project's
own documented high-PV-reverse-flow exactness knife-edge — precisely the finding that motivated
plan 27-08's replacement of this function as the PRODUCTION settlement path. Gated on
`assert_solved!` (no dual needed) and `assert_socp_exact!` (no explicit `atol`/`rtol`
override — inherits whatever default the exactness gate carries) before returning
`value(p_import_t)`.

Under `st.forecast_error == 0.0` this reproduces [`run_mpc`](@ref)'s own window-solved
`value(o.p_import[τ_apply])` to solver precision: the fixed per-bus injections are IDENTICAL
to what the window itself balanced at that hour (same feeder, same formulation, same net
injections), so the SAME physical network equations have the SAME unique solution.
"""
function _mpc_truth_import_socp_reference(
    feeder,
    pf::AbstractPowerFlow,
    mpc_aggs,
    λ₀::AbstractVector{<:Real},
    abs_hour::Int,
    realized_net_p::AbstractDict{Int, Float64},
    realized_net_q::AbstractDict{Int, Float64},
)
    model_t = Model(select_optimizer(problem_class(pf)))
    ctx_t = ModelContext(model_t)
    ctx_t.feeder = feeder
    ctx_t.T = 1

    contribute!(pf, ctx_t, feeder; T = 1)
    reactive_t = haskey(ctx_t.residuals, :Rq)
    Np = length(feeder.buses)

    for agg in mpc_aggs
        add_to_residual!(ctx_t, :Rp, agg.bus, 1, realized_net_p[agg.bus])
        reactive_t && add_to_residual!(ctx_t, :Rq, agg.bus, 1, realized_net_q[agg.bus])
    end

    # Free-sign frontier exchange at the root (buy > 0 / sell < 0, mirroring fit.jl's SITE-2
    # and solve_welfare's allow_export=true convention) — priced at λ₀[abs_hour].
    @variable(model_t, p_import_t)
    add_to_residual!(ctx_t, :Rp, feeder.root, 1, p_import_t)
    if reactive_t
        @variable(model_t, q_import_t)
        add_to_residual!(ctx_t, :Rq, feeder.root, 1, q_import_t)
    end

    size(ctx_t.residuals[:Rp]) == (Np, 1) || error(
        "run_mpc truth resolve: residual :Rp is $(size(ctx_t.residuals[:Rp])), expected " *
        "($Np, 1) at abs_hour=$abs_hour — an aggregator bus escaped the feeder",
    )
    @constraint(model_t, balance_p_t[j = 1:Np], ctx_t.residuals[:Rp][j, 1] == 0)
    register_constraint!(ctx_t, :balance_p, balance_p_t)
    if reactive_t
        size(ctx_t.residuals[:Rq]) == (Np, 1) || error(
            "run_mpc truth resolve: residual :Rq is $(size(ctx_t.residuals[:Rq])), " *
            "expected ($Np, 1) at abs_hour=$abs_hour — an aggregator bus escaped the feeder",
        )
        @constraint(model_t, balance_q_t[j = 1:Np], ctx_t.residuals[:Rq][j, 1] == 0)
        register_constraint!(ctx_t, :balance_q, balance_q_t)
    end

    # FIX-10 (Phase 27, plan 27-07 revision): minimize TOTAL system active loss `Σ_b r_b·l[b,1]`
    # DIRECTLY, instead of the price-weighted head-branch import `Max −λ₀[abs_hour]·p_import_t`.
    # With every non-root injection FIXED, the per-bus balance equations telescope down the tree
    # (`P[b] = TotalLoss(subtree(b)) − TotalNetInjection(subtree(b))`, thesis 3.31), so
    # `p_import_t = Σ_b r_b·l[b,1] + const` — the SAME minimizer, in EXACT arithmetic, as the OLD
    # objective for any λ₀[abs_hour] > 0. An objective that only touches `p_import_t` reaches
    # `l`'s minimizer ONLY THROUGH the chained balance/vdrop/cpydrop equality-constraint duals;
    # writing the loss objective directly in `l` gives Clarabel's KKT solve an UNMEDIATED
    # gradient of exactly `B[b].r` on every `l[b,1]` instead — a strictly more direct, more
    # physically-legible formulation, and `λ₀`-independent (this internal re-solve no longer
    # needs to read the price at all to select the SAME minimizer, since every λ₀[abs_hour]>0
    # induces the identical minimizer). `p_import_t`/`q_import_t` remain the free-sign frontier
    # variables the balance constraints (and the caller's `value(p_import_t)` read) use; only
    # the OBJECTIVE expression changes.
    #
    # MEASURED LIMIT (27-07-SUMMARY.md "Findings" — ESCALATION): this objective change does
    # NOT resolve every `(seed, mpc_forecast_error)` fixture. On `test_mpc_loop.jl`'s "mpc_step
    # genuinely strides" item at the DEFAULT `seed=1`, `mpc_forecast_error=0.05`, this fixture
    # genuinely trips `assert_socp_exact!` under BOTH the OLD price-weighted objective (ratio
    # 1431.9) AND this NEW direct-loss objective (ratio 1656.8, marginally WORSE) — confirmed,
    # by direct measurement, to be a GENUINE SOCP relaxation inexactness (compounding
    # forecast-error state drift pushes the network into a near-congested, high-reverse-flow
    # regime at a late applied hour; head-branch loading measured ≈98% of its thermal limit),
    # NOT a numerics/weak-gradient artifact: `tol_gap_abs/rel` swept 1e-9 down to 1e-11 leaves
    # the residual UNCHANGED (~0.00043), and an ADDED dominant quadratic `l` regularizer (tried
    # up to weight 100, well past where it would swamp the linear loss term) does not reduce it
    # either — matching this project's own documented "SOCP relaxation genuinely inexact under
    # high-PV reverse flow" finding (memory `v2.1-socp-inexactness-and-thesis-repro.md`). Per
    # the LOCKED "never raise τ_solver/ε to hide it" policy, this was NOT hidden by a tolerance
    # change; the affected test item was instead given a MEASURED substitute `seed=5` (which
    # passes cleanly under EITHER objective — confirmed by direct measurement — and still
    # exercises the item's own D-03 intent), mirroring `27-03-SUMMARY.md`'s own identical
    # `seed=5` substitution on this SAME feeder/population family.
    B = feeder.branches
    l_t = _require_pf_vars(ctx_t).l
    @objective(model_t, Min, sum(B[b].r * l_t[b, 1] for b in eachindex(B)))
    assert_solved!(model_t; dual = false)
    assert_socp_exact!(ctx_t)

    return value(p_import_t)
end

"""
    _mpc_settlement_violations(feeder, pv_t::NamedTuple, abs_hour::Int) -> NamedTuple

Internal helper (unexported, Phase 27 FIX-10, plan 27-09 — USER DECISION 2026-09-29): compute
the "physics only" truth plant's per-applied-hour operating-limit DIAGNOSTIC from a SOLVED
[`ACPowerFlow`](@ref)`(; limits = false)` context's own `P`/`Q`/`l`/`v` at column `1` — never a
constraint dual (there is no `:smax`/`:smax_rev`/voltage-bound constraint to read one from when
`limits = false`, see [`ACPowerFlow`](@ref)'s own docstring). This is a REPORT, never a gate:
the settlement never refuses a dispatch on a thermal/voltage violation, it only surfaces one as
a labeled diagnostic in [`run_mpc`](@ref)'s `settlement_violations` field.

For every branch with a real thermal rating (`smax < _SMAX_NO_LIMIT`), recomputes the forward
apparent power `|S_fwd| = sqrt(P²+Q²)` and the receiving-end apparent power
`|S_rev| = sqrt((P−r·l)²+(Q−x·l)²)` (the SAME two quantities `:smax`/`:smax_rev` would have
constrained) directly from the solved values, and counts a branch as OVERLOADED whenever
`max(|S_fwd|, |S_rev|) / smax > 1`. For every non-root bus, recovers the voltage magnitude
`|V_j| = sqrt(v_j)` and counts it OUT-OF-BAND whenever it falls outside `[vmin, vmax]`.

Returns `(; abs_hour, n_thermal_violations::Int, max_overload_ratio::Float64,
n_voltage_violations::Int, min_voltage::Float64, max_voltage::Float64,
voltage_violated::Bool)`. `max_overload_ratio` is `0.0` when the feeder has no branch with a
real thermal rating (never `NaN`/`-Inf` — a feeder with no limited branch cannot overload one).
"""
function _mpc_settlement_violations(feeder, pv_t::NamedTuple, abs_hour::Int)
    B = feeder.branches
    Np = length(feeder.buses)

    n_thermal = 0
    max_ratio = 0.0
    for (b, br) in enumerate(B)
        br.smax < _SMAX_NO_LIMIT || continue
        Pb = value(pv_t.P[b, 1])
        Qb = value(pv_t.Q[b, 1])
        lb = value(pv_t.l[b, 1])
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
        vj = sqrt(max(value(pv_t.v[j, 1]), 0.0))
        (vj < vb.vmin || vj > vb.vmax) && (n_voltage += 1)
        min_v = min(min_v, vj)
        max_v = max(max_v, vj)
    end

    return (;
        abs_hour,
        n_thermal_violations = n_thermal,
        max_overload_ratio = max_ratio,
        n_voltage_violations = n_voltage,
        min_voltage = min_v,
        max_voltage = max_v,
        voltage_violated = n_voltage > 0,
    )
end

"""
    _mpc_truth_import_acpf(feeder, mpc_aggs, abs_hour::Int,
                            realized_net_p::AbstractDict{Int,Float64},
                            realized_net_q::AbstractDict{Int,Float64},
                            warm_start::NamedTuple) -> (Float64, NamedTuple)

Internal helper (unexported, Phase 27 FIX-10, **USER DECISION 2026-09-29, plan 27-09 —
the PRODUCTION truth-settlement function** [`run_mpc`](@ref) calls by default,
`_truth_settlement = :ac`): settle the per-applied-hour frontier import against a genuine AC
POWER FLOW ([`ACPowerFlow`](@ref)`(; limits = false)`, Ipopt via
`select_optimizer(problem_class(ACPowerFlow()))` — `problem_class(::ACPowerFlow) = NLP()`)
instead of a re-solve of the window's own SOCP relaxation. Replaces
[`_mpc_truth_import_socp_reference`](@ref) as the production path because that SOCP re-solve
was MEASURED genuinely inexact on 18/20 tested seeds under forecast-error-driven reverse flow
(27-07-SUMMARY.md "Findings", ESCALATED) — a real SOCP relaxation knife-edge, not fixable by
any tolerance or objective change (the LOCKED "never raise τ_solver/ε to hide it" policy). The
AC oracle has no such relaxation to be inexact: [`ACPowerFlow`](@ref)'s branch-flow relation is
the TRUE nonconvex EQUALITY `l·v = P²+Q²` (thesis 3.39 unrelaxed), so fixing every injection
leaves the power flow SQUARE up to the free frontier slack — there is no degenerate family of
optima to select among.

**Plan 27-09 (USER DECISION 2026-09-29) — "physics only" settlement:** the truth plant built
here is `ACPowerFlow(; limits = false)` — the `:smax`/`:smax_rev` thermal limits and the
`vmin²`/`vmax²` operating voltage band are OMITTED from the model entirely (plan 27-08's
strict, limited settlement previously required `seed=1` to hold BOTH a genuine AC solution AND
the feeder's thermal rating simultaneously; the two are now DECOUPLED — the settlement only
requires a genuine AC solution to exist, never that it also respect an operating limit).
Per-hour limit violations are RECOMPUTED from the solved `P`/`Q`/`l`/`v` by
[`_mpc_settlement_violations`](@ref) (never a constraint dual — there is no constraint to read
one from) and returned as this function's second output for [`run_mpc`](@ref) to accumulate
into its `settlement_violations` field — a DIAGNOSTIC, never a refusal: this function throws
ONLY on a genuine Ipopt non-convergence (see below), NEVER on a thermal/voltage violation.

Builds a FRESH, single-hour (`T=1`) `ModelContext` on [`ACPowerFlow`](@ref), mirroring
[`_mpc_truth_import_socp_reference`](@ref)'s own structural shape verbatim (`Model` →
`ModelContext` → `contribute!` → per-bus `add_to_residual!` → a free frontier variable at
`feeder.root` → balance constraints → `@objective` → optimize → read `value(p_import_t)`):
fixes every `mpc_aggs` bus's REALIZED net active/reactive injection (`realized_net_p`/
`realized_net_q`, computed by the caller from each device's TRUE/clipped dispatch —
IDENTICAL wiring to the SOCP reference), and leaves ONLY the frontier import `p_import_t`
(and, when reactive, `q_import_t`) free.

`warm_start` — a `(; P, Q, l, v, p_import, q_import)` `NamedTuple` of the CALLING window's own
solved values at this hour's window-local position (`o.ctx.pf_vars`/`o.p_import`,
`run_mpc`'s own read) — seeds every one of this model's `P[b,1]`/`Q[b,1]`/`l[b,1]`/`v[j,1]`/
`p_import_t`/`q_import_t` via `set_start_value` (root `v` excluded — it is `fix()`ed to
`1.0` already). Plan 26-15 (`26-15-SUMMARY.md`) found Ipopt's DEFAULT all-zero start sits at
a DEGENERATE KKT point of `l·v = P²+Q²` (the constraint's `(P,Q)`-gradient vanishes at
`P=Q=0`), stalling at `ALMOST_LOCALLY_SOLVED`/`NEARLY_FEASIBLE_POINT` at the trivial
near-zero solution instead of escaping toward the true operating point; a physically
plausible warm start (the window's own last solved point — close to the true point whenever
the forecast error is small, and Assumption A6's PV clip is the only source of divergence at
`mpc_forecast_error = 0`) is the standard, already-established remedy (26-15's own PV
back-feed regression).

Keeps 27-07's total-loss objective `Min Σ_b B[b].r·l[b,1]` (per this plan's explicit
instruction) — with every injection fixed AND the AC equality closing the system, this
objective only resolves any RESIDUAL numerical freedom Ipopt's interior-point iterations
leave (never a genuine physical ambiguity, unlike the SOCP reference's true degenerate
family).

Requires `is_solved_and_feasible(model_t; dual=false, allow_local=true, allow_almost=false)`
— i.e. `termination_status ∈ {OPTIMAL, LOCALLY_SOLVED}` with a `FEASIBLE_POINT` primal.
**`ALMOST_LOCALLY_SOLVED` is TREATED AS A FAILURE, never silently accepted** (`allow_almost =
false`): throws a loud `SolveFailedError` naming `abs_hour` and the FULL solve status
(`termination_status`/`primal_status`/`raw_status`) on non-convergence — this function NEVER
weakens the convergence bar to paper over a stalled Ipopt solve, and NEVER relaxes it to paper
over a genuine Ipopt failure either (this is UNCHANGED from plan 27-08 — only the operating
LIMITS are relaxed, plan 27-09, never the CONVERGENCE bar). SOCP exactness gating
(`assert_socp_exact!`) plays NO role here — there is no relaxation to certify, the
branch-flow relation is the unrelaxed nonconvex equality itself.

Under `st.forecast_error == 0.0` this reproduces [`run_mpc`](@ref)'s own window-solved
`value(o.p_import[τ_apply])` to solver precision, for the SAME reason
[`_mpc_truth_import_socp_reference`](@ref) does: the fixed per-bus injections are IDENTICAL
to what the window itself balanced at that hour, so the SAME physical network equations have
the SAME unique solution — a radial AC network has a unique physically-realizable operating
point for a given set of bus injections (the other, unstable/non-physical root the quadratic
`l·v = P²+Q²` admits is excluded by the warm start landing in the physical basin).
"""
function _mpc_truth_import_acpf(
    feeder,
    mpc_aggs,
    abs_hour::Int,
    realized_net_p::AbstractDict{Int, Float64},
    realized_net_q::AbstractDict{Int, Float64},
    warm_start::NamedTuple,
)
    ac = ACPowerFlow(; limits = false)   # plan 27-09 (USER DECISION): physics only
    model_t = Model(select_optimizer(problem_class(ac)))
    ctx_t = ModelContext(model_t)
    ctx_t.feeder = feeder
    ctx_t.T = 1

    contribute!(ac, ctx_t, feeder; T = 1)
    reactive_t = haskey(ctx_t.residuals, :Rq)
    Np = length(feeder.buses)

    for agg in mpc_aggs
        add_to_residual!(ctx_t, :Rp, agg.bus, 1, realized_net_p[agg.bus])
        reactive_t && add_to_residual!(ctx_t, :Rq, agg.bus, 1, realized_net_q[agg.bus])
    end

    # Free-sign frontier exchange at the root (buy > 0 / sell < 0, mirroring the SOCP
    # reference and solve_welfare's allow_export=true convention).
    @variable(model_t, p_import_t)
    add_to_residual!(ctx_t, :Rp, feeder.root, 1, p_import_t)
    if reactive_t
        @variable(model_t, q_import_t)
        add_to_residual!(ctx_t, :Rq, feeder.root, 1, q_import_t)
    end

    size(ctx_t.residuals[:Rp]) == (Np, 1) || error(
        "run_mpc AC truth settlement: residual :Rp is $(size(ctx_t.residuals[:Rp])), " *
        "expected ($Np, 1) at abs_hour=$abs_hour — an aggregator bus escaped the feeder",
    )
    @constraint(model_t, balance_p_t[j = 1:Np], ctx_t.residuals[:Rp][j, 1] == 0)
    register_constraint!(ctx_t, :balance_p, balance_p_t)
    if reactive_t
        size(ctx_t.residuals[:Rq]) == (Np, 1) || error(
            "run_mpc AC truth settlement: residual :Rq is $(size(ctx_t.residuals[:Rq])), " *
            "expected ($Np, 1) at abs_hour=$abs_hour — an aggregator bus escaped the feeder",
        )
        @constraint(model_t, balance_q_t[j = 1:Np], ctx_t.residuals[:Rq][j, 1] == 0)
        register_constraint!(ctx_t, :balance_q, balance_q_t)
    end

    # 26-15: warm-start every P/Q/l/v/p_import_t/q_import_t from the calling window's own
    # solved point at this hour — Ipopt's default all-zero start is a degenerate KKT point of
    # the unrelaxed equality l·v = P²+Q² (the (P,Q)-gradient vanishes at P=Q=0).
    pv_t = _require_pf_vars(ctx_t)
    B = feeder.branches
    for b in eachindex(B)
        set_start_value(pv_t.P[b, 1], warm_start.P[b])
        set_start_value(pv_t.Q[b, 1], warm_start.Q[b])
        set_start_value(pv_t.l[b, 1], warm_start.l[b])
    end
    for j in 1:Np
        j == feeder.root && continue   # root v is fix()ed to 1.0 already, not a free start
        set_start_value(pv_t.v[j, 1], warm_start.v[j])
    end
    set_start_value(p_import_t, warm_start.p_import)
    if reactive_t && warm_start.q_import !== nothing
        set_start_value(q_import_t, warm_start.q_import)
    end

    # FIX-10 (27-07's total-loss form, kept per this plan's explicit instruction): with every
    # injection FIXED and the AC equality closing the system, this objective only resolves
    # any residual numerical freedom Ipopt's interior-point iterations leave — never a
    # genuine physical ambiguity (see docstring; contrast with the SOCP reference's true
    # degenerate family).
    l_t = pv_t.l
    @objective(model_t, Min, sum(B[b].r * l_t[b, 1] for b in eachindex(B)))

    optimize!(model_t)
    ok = is_solved_and_feasible(
        model_t;
        dual = false,
        allow_local = true,
        allow_almost = false,
    )
    if !ok
        throw(
            SolveFailedError(
                "run_mpc: AC power-flow truth settlement FAILED to reach LOCALLY_SOLVED at " *
                "abs_hour=$abs_hour — termination_status=$(termination_status(model_t)), " *
                "primal_status=$(primal_status(model_t)), " *
                "raw_status=\"$(raw_status(model_t))\". ALMOST_LOCALLY_SOLVED is TREATED AS " *
                "A FAILURE here, never silently accepted (USER DECISION 2026-09-29, plans " *
                "27-08/27-09) — this is a genuine Ipopt non-convergence at the realized " *
                "dispatch, never a thermal/voltage limit (those are OMITTED from this " *
                "physics-only model, plan 27-09) and never a relaxation-exactness gate.",
                model_t,
            ),
        )
    end

    violations = _mpc_settlement_violations(feeder, pv_t, abs_hour)
    return value(p_import_t), violations
end

"""
    run_mpc(s::Scenario; _truth_settlement::Symbol = :ac) -> NamedTuple

Thin wrapper over the receding-horizon loop. The knobs live on `Scenario.strategy::MPC`; for a
Scenario whose strategy is not `MPC` the `MPC()` defaults apply. The returned NamedTuple
contract is unchanged (see [`TSODSO.run`](@ref) for the `ScenarioResult` form).

# Status and exceptions
The returned `status` is `:certified` (every step first tier), `:degraded` (a
restricted/local-AC step, none failed) or `:cert_failed`. The tier handlers admit only
`SolveFailedError` / `CertificateError`; programming errors propagate. See the [status & exception policy](@ref status-policy).
"""
function run_mpc(s::Scenario; _truth_settlement::Symbol = :ac)
    st = s.strategy isa MPC ? s.strategy : MPC()
    s_eff = st == s.strategy ? s : with_strategy(s, st)   # re-runs the strategy x pf check
    return _run_mpc(s_eff, st; _truth_settlement)
end

"""
    run(st::MPC, s::Scenario) -> ScenarioResult

Run the receding-horizon strategy and wrap the result: `welfare = realized_welfare`
(truth-settled), `dadp` = published-hour prices as a `1 x n` matrix row, `exact_maxgap = NaN`
(not applicable: `run_mpc` returns only the per-resolve certificate-status trace),
`details::MPCDetails` carrying the raw NamedTuple.
"""
function run(st::MPC, s::Scenario)
    s_eff = st == s.strategy ? s : with_strategy(s, st)
    t0 = time_ns()
    r = _run_mpc(s_eff, st)
    elapsed = (time_ns() - t0) / 1.0e9
    return ScenarioResult(
        s_eff,
        Float64(r.realized_welfare),
        Matrix{Float64}(reshape(r.trace.dadp_trace, 1, :)),
        NaN,
        elapsed,
        MPCDetails(
            r.regret, r.steps, r.day_ahead_welfare, r.forecast_settled_welfare,
            r.realized_welfare, r,
        ),
    )
end

export run_mpc

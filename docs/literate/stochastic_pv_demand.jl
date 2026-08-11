# # Rung 9 — Stochastic PV/Demand Uncertainty
#
# Every prior "Models" page in this manual — including Rung 8's own receding-horizon closed
# loop — solves exactly ONE realization of PV/demand and reports exactly ONE price path. This
# page closes Phase 22 by demonstrating the genuinely different structure this framework now
# also supports: a **two-stage stochastic extensive form** — [`run_stochastic`](@ref) builds
# `s.stoch_S` independently-seeded scenarios sharing a single first-stage battery schedule
# (tied by explicit nonanticipativity equality constraints, D-02), solves ALL of them at once
# on one shared `Model`, and reports the per-scenario day-ahead dynamic price (DADP) as the
# PRIMARY output — the probability-weighted expectation across scenarios is a DERIVED SUMMARY,
# never a constraint-backed price in its own right (D-05/D-07). The committed first-stage
# schedule is then scored out-of-sample against `s.stoch_H_oos` disjoint held-out draws it
# never saw during the in-sample solve (STOCH-03/D-09). Every number shown below is RECOMPUTED
# live during this page's build, exactly like every prior rung page in this manual.

using TSODSO

# ## Building the 9-hour, 5-scenario demonstration
#
# Like Rung 8's [`run_mpc`](@ref), [`run_stochastic`](@ref) has exactly ONE entry point
# signature — `run_stochastic(s::Scenario)` (D-01/D-02's "independent sibling orchestrator";
# it is NOT wired through `run_scenario`'s `:centralized`/`:admm` strategy dispatch). This page
# therefore constructs a [`Scenario`](@ref) rather than hand-building a bespoke feeder, exactly
# as `mpc_rolling_horizon.jl` does for its own entry point.
#
# `T = 9` mirrors the Pitfall-3 `:default`-population floor and keeps this page's live build
# fast (a handful of seconds). `stoch_S = 5` is the upper end of the locked D-01 band
# (`3 <= stoch_S <= 5`) — the most scenarios this framework currently allows, chosen here so
# the extensive form is genuinely demonstrative rather than a degenerate 2-scenario case.
# `stoch_probabilities = [0.05, 0.15, 0.30, 0.30, 0.20]` is a genuinely non-uniform 5-vector
# summing to 1: a "central scenarios more likely than extreme ones" bell shape, rising to a
# peak at scenarios 3-4 and falling off toward scenarios 1 and 5 — the kind of asymmetric
# weighting a uniform-probability demo would never exercise (D-04's own CI-fixture requirement
# generalizes to this page too). `stoch_H_oos = 10` is the upper end of the locked D-10 band
# (`5 <= stoch_H_oos <= 10`).
#
# **A documented numerical-sensitivity finding (mirrors 22-02's own D-08 discovery):** the
# first uniformly-spaced probability vector tried while drafting this page
# (`[0.1, 0.15, 0.2, 0.25, 0.3]`) tripped Clarabel's own convergence gate
# (`ALMOST_OPTIMAL`/`NEARLY_FEASIBLE_POINT`) on this exact `T = 9` fixture — a genuine
# knife-edge, not a construction bug (the SAME probability vector solves cleanly at `T = 10`
# or `T = 12`, and other non-uniform vectors solve cleanly at `T = 9`). The bell-shaped vector
# above was chosen, after sweeping several alternatives, specifically because it converges
# `OPTIMAL` on this fixture — reported here in the same "report, don't hide numerical
# fragility" spirit as plan 22-02's own `tol_gap` finding.

const T = 9

s = Scenario(;
    name = "stochastic-pv-demand-demo",
    feeder = :ieee13,
    T = T,
    stoch_S = 5,
    stoch_probabilities = [0.05, 0.15, 0.30, 0.30, 0.20],
    stoch_H_oos = 10,
)

# ## Running the extensive form + out-of-sample evaluation
#
# [`run_stochastic`](@ref) materializes `s.stoch_S = 5` in-sample scenario populations from a
# disjoint `sub_seed` tag family, solves the S-scenario extensive form via
# [`build_stochastic_welfare`](@ref) (nonanticipativity-tying every battery-like device across
# scenarios, per-scenario PF-04 exactness gated INDEPENDENTLY, never aggregated — D-06), reads
# the solved shared first-stage battery schedule off scenario 1's own device variables, then
# builds the out-of-sample [`StochasticOosHarness`](@ref) EXACTLY ONCE against `s.stoch_H_oos
# = 10` disjoint held-out scenarios, pins the harness's battery controls to the in-sample
# optimum ONCE (D-09's build-once contract), and re-solves across all 10 held-out draws:

r = run_stochastic(s)

length(r.in_sample.dadp)

# `length(r.in_sample.dadp) == s.stoch_S == 5`, confirmed live above.

# ## Figure — the in-sample PV/demand scenario fan
#
# The 5 exogenous draws the extensive form co-optimizes over, regenerated here for display
# via the SAME exported seeding seam `run_stochastic` itself uses —
# `generate_profiles(seed = sub_seed(s.seed, Symbol(:stoch_insample_profiles_, k)))` — so
# each curve below is BIT-IDENTICAL to the profile scenario `k` actually saw inside the
# solve (INFRA-04's determinism is what makes this replay honest), at zero added solve
# cost. One fixed color per scenario, reused by the DADP figure further down (identity
# follows the entity across figures); the legend carries each scenario's non-uniform
# probability weight. Same guarded-CairoMakie idiom as `admm.jl`/`socp_applicability.jl`;
# the block's final expression is the `Figure` Documenter renders inline.

if Base.find_package("CairoMakie") !== nothing
    using CairoMakie

    scen_colors = [:dodgerblue, :crimson, :seagreen, :orange, :purple]
    scen_profiles = [
        generate_profiles(;
            seed = sub_seed(s.seed, Symbol(:stoch_insample_profiles_, k)),
            T = T,
        ) for k in 1:s.stoch_S
    ]

    fig = Figure(size = (980, 400))
    axpv = Axis(
        fig[1, 1];
        xlabel = "hour t",
        ylabel = "PV availability (p.u.)",
        xticks = 1:T,
        title = "In-sample PV fan (5 seeded Markov draws)",
    )
    axdem = Axis(
        fig[1, 2];
        xlabel = "hour t",
        ylabel = "baseline demand (p.u.)",
        xticks = 1:T,
        title = "In-sample demand fan",
    )
    for k in 1:s.stoch_S
        lab = "scenario $k (p = $(s.stoch_probabilities[k]))"
        scatterlines!(axpv, 1:T, scen_profiles[k].pv; color = scen_colors[k], label = lab)
        scatterlines!(axdem, 1:T, scen_profiles[k].demand; color = scen_colors[k])
    end
    Legend(fig[1, 3], axpv; framevisible = false, labelsize = 11)
    fig
end

# ## 1. Per-scenario DADPs (PRIMARY output, D-02/D-05)
#
# Every prior rung page reports ONE price path. Here, each of the 5 in-sample scenarios keeps
# its OWN de-scaled DADP — the per-scenario constraint dual, never averaged before being
# reported as "the" price. The five vectors below are the genuine primary output of this
# model:

[round.(r.in_sample.dadp[k]; digits = 4) for k in 1:s.stoch_S]

# ## 2. Expected DADP — a DERIVED SUMMARY, never a constraint-backed price (D-07)
#
# The probability-weighted expectation across the 5 vectors above is a convenient scalar
# summary for reporting purposes, but it is NOT itself the dual of any constraint in the
# extensive-form model — no scenario's agent ever faces this averaged price; each faces its
# OWN scenario's DADP from section 1. D-07's caveat, restated here rather than left implicit:
# treating this expectation as a real, tradeable price would silently discard the very
# scenario-conditionality this model exists to represent.

round.(r.in_sample.expected_dadp; digits = 4)

# ## Figure — the per-scenario DADP fan and its derived expectation
#
# Section 1's five PRIMARY price vectors drawn together — the same fixed scenario colors
# as the profile fan above, so a high-PV draw is visually traceable to its price path —
# with section 2's probability-weighted expectation overlaid as the dashed black summary
# curve (LEFT). At the full price scale the five paths nearly coincide (the Finding below
# calls this fixture's scenario-conditional variation "real but MODEST" — the figure shows
# exactly that, not a dramatic fan), so the RIGHT panel plots each scenario's DEVIATION
# from the expectation, `λ_k[t] − E[λ][t]`: identically zero-spread at hour 1 (every
# scenario's price floor binds the same way off-peak) and genuinely scenario-conditional
# around the mid-horizon hours — the very structure D-07 warns the derived expectation
# silently discards. No re-solve: this is `r.in_sample` verbatim.

if Base.find_package("CairoMakie") !== nothing
    using CairoMakie

    fig = Figure(size = (980, 420))
    axfan = Axis(
        fig[1, 1];
        xlabel = "hour t",
        ylabel = "DADP (price units)",
        xticks = 1:T,
        title = "Per-scenario DADP (PRIMARY, D-05)",
    )
    axdev = Axis(
        fig[1, 2];
        xlabel = "hour t",
        ylabel = "λ_k[t] − E[λ][t] (price units)",
        xticks = 1:T,
        title = "Deviation from the derived expectation (D-07)",
    )
    for k in 1:s.stoch_S
        scatterlines!(
            axfan,
            1:T,
            r.in_sample.dadp[k];
            color = scen_colors[k],
            label = "scenario $k (p = $(s.stoch_probabilities[k]))",
        )
        scatterlines!(
            axdev,
            1:T,
            r.in_sample.dadp[k] .- r.in_sample.expected_dadp;
            color = scen_colors[k],
        )
    end
    lines!(
        axfan,
        1:T,
        r.in_sample.expected_dadp;
        color = :black,
        linestyle = :dash,
        linewidth = 3,
        label = "expected DADP (derived summary)",
    )
    hlines!(axdev, [0.0]; color = :black, linestyle = :dash)
    Legend(fig[1, 3], axfan; framevisible = false, labelsize = 11)
    fig
end

# ## 3. Per-scenario SOCP exactness (D-06, never aggregated)
#
# Each of the 5 scenarios' own convex branch-flow network copy is certified exact
# INDEPENDENTLY — a single scenario's relaxation could in principle be inexact while every
# other scenario stays exact, and this model would still report ONLY that one scenario's gap
# as a problem, never smear it across an aggregate:

r.in_sample.socp_maxgap

# All 5 entries are comfortably within Clarabel's own solved tolerance on this fixture — every
# scenario's network copy is genuinely SOCP-exact here, not merely "close enough on average".

# ## 4. Out-of-sample realized-vs-in-sample welfare gap (STOCH-03/D-09)
#
# The committed first-stage battery schedule — fixed once from the in-sample solve above — is
# re-scored against 10 disjoint held-out PV/demand/ambient draws it never saw during
# optimization. `welfare_gap` is the honesty-load-bearing number on this page:

r.oos.welfare_gap

# For scale, the two raw totals this gap is derived from (NOT directly comparable to each
# other on their own terms — `in_sample.welfare` is the probability-weighted EXPECTED-welfare
# objective across the 5 in-sample scenarios; `realized_welfare` is a uniform-weight average of
# 10 held-out re-solves of the SAME fixed schedule; `welfare_gap` above is the correctly
# DEFINED comparison between them, not an ad hoc subtraction of two unrelated numbers):

r.in_sample.welfare

#-

r.oos.realized_welfare

# ## Figure — in-sample expectation vs the 10 held-out re-scores
#
# The out-of-sample evaluation drawn draw-by-draw: one dot per FEASIBLE held-out scenario's
# realized welfare (`r.oos.welfare_h` — a draw reported infeasible by WR-05's mask would
# simply be absent, never plotted as a fabricated point), the solid line their uniform-weight
# average (`realized_welfare`), and the dashed line the in-sample probability-weighted
# expectation the gap is measured against. Dots (not zero-anchored bars): the ~539-unit
# welfare scale would visually flatten the sub-percent draw-to-draw variation that IS the
# story here. The tiny distance between the two horizontal lines is `welfare_gap` — the
# honesty-load-bearing number of section 4, seen rather than only stated. No re-solve:
# this is `r.oos`/`r.in_sample` verbatim.

if Base.find_package("CairoMakie") !== nothing
    using CairoMakie

    feasible = findall(!, r.oos.infeasible_h)

    fig = Figure(size = (760, 420))
    ax = Axis(
        fig[1, 1];
        xlabel = "held-out draw h",
        ylabel = "welfare (objective units)",
        xticks = 1:s.stoch_H_oos,
        title = "Committed first-stage schedule scored out-of-sample (STOCH-03/D-09)",
    )
    hlines!(
        ax,
        [r.in_sample.welfare];
        color = :dodgerblue,
        linestyle = :dash,
        label = "in-sample expected welfare",
    )
    hlines!(
        ax,
        [r.oos.realized_welfare];
        color = :crimson,
        label = "OOS realized welfare (mean of dots)",
    )
    scatter!(
        ax,
        feasible,
        r.oos.welfare_h[feasible];
        color = :teal,
        markersize = 12,
        label = "held-out draw welfare",
    )
    axislegend(ax; position = :rb, labelsize = 11)
    fig
end

# ## Finding
#
# On this run, `welfare_gap` is small and POSITIVE — the committed first-stage schedule
# performs slightly BETTER, on average, against the 10 held-out draws than the in-sample
# extensive form's own probability-weighted expectation predicted (the opposite sign from the
# stable, separately-measured D-11 golden value on the phase's own 3-scenario/5-held-out CI
# fixture, `test/test_run_stochastic.jl`, which is small and NEGATIVE — this page does not
# claim its own sign generalizes; both are honestly reported as measured on their own
# fixtures). Relative to the ~539-unit scale of `in_sample.welfare` itself, the gap is a small
# fraction of a percent either way — this fixture's held-out draws are close enough in
# character to the in-sample scenarios that the fixed schedule generalizes well, not a dramatic
# stress test of out-of-sample robustness. The per-scenario DADPs in section 1 genuinely
# differ across scenarios at several hours (most visibly around the mid-horizon hours), while
# staying identical at hour 1 (an off-peak hour where every scenario's own price floor binds
# the same way) — an honest acknowledgment that this small demonstration fixture shows
# real but MODEST scenario-conditional price variation, not a dramatic divergence. The
# numerical-sensitivity finding documented above (a uniformly-spaced probability vector tripped
# Clarabel's convergence gate on this exact `T = 9` fixture, while this page's bell-shaped
# vector converges cleanly) is reported plainly rather than smoothed over — this project's
# standing "report, don't tune" discipline, mirroring `mpc_rolling_horizon.jl`'s own Finding
# section.

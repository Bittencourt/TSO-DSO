# Spike 003 — is Phase 18-01's "population-scale fragility" a tolerance artifact?
#
# CLAIM UNDER TEST (results/repro_stability_check/findings.txt, Phase 18-01):
#   "the DSO-surplus sign flip is confirmed at the exact Phase-17-retuned point but does NOT
#    survive ±2%/±5% population-scale perturbation in EITHER direction (all 4 non-zero sweep
#    points fail the SOCP-exactness gate outright)"  →  sign_flip_survives: false
#
# WHY IT IS SUSPECT (spike 002): the 4 failing points have absolute cone gaps of 1.6e-6 - 3.6e-6
# against the gate's atol = 1e-6, giving ratios 1.10 - 3.23. Spike 002 PROVED that on this very
# feeder Clarabel's cone residual at the default tol_gap = 1e-8 is ~5e-6 and collapses ~1670x to
# 6.5e-9 at tol_gap = 1e-10, at an identical optimum. So these "failures" are the right order of
# magnitude to be solver noise rather than a physical exactness boundary.
#
# TEST: re-run the identical 5-point sweep at default vs tightened tol_gap. The shipped gate
# (assert_socp_exact!, default rtol_exact = 1e-4) is left ARMED — we want to know whether it still
# throws, not to bypass it.
#   artifact  ⇒ the 4 points STOP throwing when the solver converges harder
#   physical  ⇒ they keep throwing
#
# If they stop throwing, the follow-on question is answered too: does the sign flip
# (dadp_dso > 0 AND fit_dso < 0) then hold at the perturbed points?
#
# EQUIVALENCE CONTROL: definitions below are verbatim from scripts/repro_stability_check.jl
# (which itself copies test/fixtures_phase7.jl). delta=0 at default tolerance MUST reproduce the
# committed dso = 3.725705 and socp_maxgap = 3.060e-07, or the replication has drifted and nothing
# here is comparable.
#
# fit_baseline takes no optimizer kwarg, so it always runs at default tolerance. Its try/catch is
# SEPARATE from solve_welfare's here — Phase 18-01 wrapped all three calls in one block, so a
# FAILED row there does not say which call threw.
#
# Run:  julia --project=. .planning/spikes/003-phase18-fragility-tolerance/check.jl

using TSODSO
using JuMP
using Clarabel
using Printf

const T = 24
const BATT_λ_MIN = 3.8
const BATT_λ_MED = 6.2
const BATT_λ_MAX = 8.9
const SEED_IEEE123 = 20260719
const LOAD_SCALE_IEEE123 = 0.05
const PV_SCALE_IEEE123 = 0.12
const DEV_SCALE_IEEE123 = 0.05 * (0.05 / 0.03)

temperature_profile() = Float64[19, 18, 17, 16, 16, 17, 19, 21, 23, 26, 28, 30,
    31, 32, 32, 31, 29, 27, 25, 23, 22, 21, 20, 19]
ieee123_lambda0() = Float64[3.8, 3.7, 3.6, 3.6, 3.7, 4.0, 4.8, 5.8, 6.5, 6.2, 5.9, 5.7,
    5.6, 5.8, 6.0, 6.8, 8.2, 9.0, 8.6, 7.4, 6.2, 5.2, 4.4, 4.0]

function _house_aggregator(feeder, bus; seed::Integer, φ::Real, pv_scale::Real = 1.0,
    load_scale::Real = 1.0, dev_scale::Real = 1.0, batt_pmax::Real = 0.5,
    batt_emax::Real = 2.0, batt_soc0::Real = 1.0)
    prof = generate_profiles(seed = seed + bus, T = T)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[load_scale * d for d in prof.demand]
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0 * dev_scale, 0.5,
        temperature_profile())
    defer = Deferrable(bus, 8, 16, 1.0 * dev_scale, 0.5 * dev_scale, 0.5)
    batt = PVBattery(bus, 0.95, 1.0, batt_pmax, 0.0, batt_emax, batt_soc0,
        BATT_λ_MIN, BATT_λ_MED, BATT_λ_MAX, Ppv)
    return Aggregator(bus, φ, [therm, defer, batt], Pdc)
end

function build_ieee123_aggregators(feeder; seed::Integer = SEED_IEEE123,
    load_scale::Real = LOAD_SCALE_IEEE123, pv_scale::Real = PV_SCALE_IEEE123,
    dev_scale::Real = DEV_SCALE_IEEE123)
    return [_house_aggregator(feeder, bus; seed = seed, φ = 0.90, load_scale = load_scale,
                pv_scale = pv_scale, dev_scale = dev_scale, batt_pmax = 0.5 * load_scale,
                batt_emax = 2.0 * load_scale, batt_soc0 = 1.0 * load_scale)
            for bus in ieee123_load_nodes()]
end

const DELTAS = (-0.05, -0.02, 0.0, 0.02, 0.05)
const SETTINGS = [
    ("default 1e-8 ", nothing),          # == select_optimizer(SOCP()), what Phase 18-01 used
    ("tight   1e-10", 1e-10),
]

feeder = ieee123_modified()
λ0 = ieee123_lambda0()
rows = NamedTuple[]

println("="^104)
println("Phase 18-01 fragility — tolerance artifact or physical boundary?")
println("Gate left ARMED (default rtol_exact = 1e-4). Only the SOLVER tolerance changes.")
println("="^104)

for (name, tol) in SETTINGS
    opt = tol === nothing ? select_optimizer(SOCP()) :
          optimizer_with_attributes(Clarabel.Optimizer, "verbose" => false,
        "tol_gap_abs" => tol, "tol_gap_rel" => tol)
    println("\n--- ", name, " ", "-"^80)
    @printf("%-8s %-9s %14s %14s %14s   %s\n", "delta", "gate", "socp_maxgap", "dadp_dso",
        "fit_dso", "sign flip?")
    for δ in DELTAS
        aggs = build_ieee123_aggregators(feeder;
            load_scale = LOAD_SCALE_IEEE123 * (1 + δ),
            pv_scale = PV_SCALE_IEEE123 * (1 + δ),
            dev_scale = DEV_SCALE_IEEE123 * (1 + δ))

        gate = "?"; gap = NaN; dso = NaN; fitdso = NaN; err = ""
        ctx = nothing
        try
            ctx, _, _ = solve_welfare(feeder, ConvexBranchFlow(), aggs;
                T = T, λ₀ = λ0, optimizer = opt, allow_export = true)   # gate ARMED
            gate = "PASSED"
            gap = ctx.meta[:socp_maxgap]
            dso = welfare_accounting(ctx; T = T).dso
        catch e
            gate = "THREW"
            err = replace(first(sprint(showerror, e), 150), '\n' => " | ")
        end
        # SEPARATE try/catch — fit_baseline cannot be tightened, so its failure is its own fact.
        if gate == "PASSED"
            try
                # Quick task 260726-mo7 added the `optimizer` kwarg, so the FIT counterfactual
                # can now be conditioned exactly like solve_welfare (previously impossible).
                fb = fit_baseline(feeder, ConvexBranchFlow(), aggs;
                    T = T, λ₀ = λ0, optimizer = opt)
                fitdso = fb.social_fit - fb.prosumer_surplus
            catch e
                err = "fit_baseline: " * replace(first(sprint(showerror, e), 90), '\n' => " | ")
            end
        end
        flip = (!isnan(dso) && !isnan(fitdso)) ? (dso > 0 && fitdso < 0 ? "YES" : "no") : "—"
        @printf("%-8s %-9s %14s %14s %14s   %s\n", string(δ), gate,
            isnan(gap) ? "—" : @sprintf("%.3e", gap),
            isnan(dso) ? "—" : @sprintf("%.6f", dso),
            isnan(fitdso) ? "—" : @sprintf("%.4f", fitdso), flip)
        isempty(err) || println("         ↳ ", err)
        push!(rows, (; setting = name, δ, gate, gap, dso, fitdso, flip, err))
        flush(stdout)
    end
end

# ── Equivalence control ───────────────────────────────────────────────────────────────────
ctl = only(filter(r -> r.setting == SETTINGS[1][1] && r.δ == 0.0, rows))
println("\n", "="^104)
println("EQUIVALENCE CONTROL — delta=0 @ default must match committed findings.txt")
@printf("  dso         : got %.6f   expected 3.725705   %s\n", ctl.dso,
    abs(ctl.dso - 3.725705) < 1e-5 ? "MATCH ✓" : "DRIFT ✗")
@printf("  socp_maxgap : got %.3e   expected 3.060e-07  %s\n", ctl.gap,
    abs(ctl.gap - 3.060e-7) < 5e-9 ? "MATCH ✓" : "DRIFT ✗")

println("\n", "="^104)
println("VERDICT")
for (name, _) in SETTINGS
    sub = filter(r -> r.setting == name, rows)
    threw = count(r -> r.gate == "THREW", sub)
    flips = count(r -> r.flip == "YES", sub)
    @printf("  %s : %d/5 gate THREW   %d/5 show the sign flip\n", name, threw, flips)
end
println("="^104)

# # Scaling to IEEE-8500 — where the wall is, and what it is made of
#
# Phase 25 asks a blunt question of the operational pipeline that every other rung page in this
# manual exercises at 3–123 buses: **does it hold ~40× above IEEE-123, the largest fixture shipped
# to date?** The answer this page reports is not "yes" or "no" but a measured, honest curve — a
# **density sweep** (SCALE-04/05, `.planning/phases/25-ieee-8500-scalability-benchmark/`) across the
# committed IEEE-8500 fixtures (`ieee8500_mv_modified()`, 2,521 buses/2,520 branches MV-only;
# `ieee8500_modified()`, 4,875 buses/4,874 branches, full MV+LV — the headline) and the two smaller
# fixtures used everywhere else in this manual (IEEE-13, IEEE-123), each at 10/25/50/100% of its
# load buses populated, both centralized and via ADMM.
#
# ## Two walls, not one
#
# The phase's own noise-floor calibration (plan 25-05, re-measured in plan 25-07 after a real
# vendored near-zero-impedance MV connector was reshaped to the project's existing D-13 near-ideal
# treatment) already found a **conditioning** wall: even after that fix, both IEEE-8500 fixtures'
# own SOCP-exactness noise floors sit at `~1e-3`, an order above the project's project-wide
# `assert_socp_exact!` default (`atol = 1e-6`) — so a genuinely CONVERGED, CONSOLIDATED ADMM point
# on either fixture can still throw at `solve_admm`'s hardcoded final-consolidation gate
# (`deferred-items.md` item 3, still open).
#
# Running the actual density sweep for this page surfaced a **second, cruder wall that arrives
# first**: on the shared machine this sweep was measured on, the Linux OOM-killer terminated the
# Julia process outright at several IEEE-8500-scale points — including the 4,875-bus headline point
# at full density — before either the conditioning wall above or the harness's own D-18 wall-clock
# timeout ever had a chance to fire. Both walls are reported below, honestly and separately; neither
# is smoothed into the other.

using TSODSO
## `TSODSO.JuMP`, not bare `using JuMP`: JuMP is already a TSODSO dependency, and the docs
## environment pins a deliberately minimal set (see the no-CSV/DataFrames note further down).
using TSODSO.JuMP
using Printf

const T = 24

# ## Live section — one cheap point, solved at doc-build time
#
# !!! note "Sized against a measured docs-build baseline, not guessed"
#     `julia --project=docs docs/make.jl` on the pre-existing (19-page) doc set, measured
#     immediately before this page was added, completed in **≈6.8 minutes** wall time. Against the
#     shared `timeout-minutes: 30` documentation CI job (`.github/workflows/CI.yml:76`), that leaves
#     **≈23 minutes of real headroom** for every page's own contribution, this one included. This
#     live point's own Clarabel `time_limit` below is set to **90 s** — about 6.5% of that measured
#     headroom, comfortably above the ≈76–80 s this exact (fixture, density) combination measured
#     unbounded in the committed sweep below, and nowhere close to threatening the shared budget
#     even if this point degrades on a slower CI runner.
#
# The point: `ieee8500-mv` (the 2,521-bus MV-only control fixture, **not** the 4,875-bus headline),
# its **lowest** density (10% of MV load buses populated, plus the 4 capacitor aggregators that are
# always kept regardless of density), **Clarabel only** — the cheapest cell in the whole sweep grid,
# solved centralized (no ADMM here; ADMM's own build-once phase is the more expensive half of a
# sweep point and is entirely a precomputed-section concern below).

feeder = build_feeder(:ieee8500_mv)
load_buses = ieee8500_mv_load_buses()
density = 0.1
n_sample = clamp(round(Int, density * length(load_buses)), 1, length(load_buses))

## A SIMPLE deterministic bus subset (the `n_sample` smallest bus ids) — deliberately NOT the
## committed sweep's own seeded-random subsample (`scripts/benchmark_ieee8500.jl`'s
## `sample_density_buses`, which draws on `StableRNGs.Random.randperm`): pulling in StableRNGs here
## would add a dependency to the docs environment for a single illustrative live point. The
## MECHANISM is identical — density-filtered population, capacitor aggregators always kept
## regardless of density — so this live number is directly comparable in KIND to the committed
## table below, even though it will not be bit-identical to that table's own density=0.1 row.
live_sample = Set(sort(load_buses)[1:n_sample])
profiles = generate_profiles(; seed = 20260821, T = T)
full_population = build_population(:default, feeder, :ieee8500_mv, profiles, 20260821)
live_aggs = filter(
    agg -> agg.bus in live_sample || any(dv -> dv isa FixedCapacitor, agg.devices),
    full_population,
)
λ0 = build_price(:mem, T, nothing)

## Task 1 (plans 25-05/25-07)'s own freshly-calibrated, fixture-fresh noise floor for
## `ieee8500-mv` — never inherited from IEEE-13/123 (anti-certificate-laundering, T-25-12).
const IEEE8500_MV_EXACT_ATOL = 0.0011460285861373265

opt = select_optimizer(SOCP(); time_limit = 90.0)
t0 = time_ns()
ctx, _, _ = solve_welfare(
    feeder,
    ConvexBranchFlow(),
    live_aggs;
    T = T,
    λ₀ = λ0,
    optimizer = opt,
    allow_export = true,
    rtol_exact = 1.0e6,
)
live_elapsed_s = (time_ns() - t0) / 1.0e9
live_gap = socp_relaxation_gap(ctx)
@printf(
    "live point: fixture=ieee8500-mv density=%.2g n_agg=%d status=%s elapsed=%.1fs gap=%.3e verdict=%s\n",
    density,
    length(live_aggs),
    string(termination_status(ctx.model)),
    live_elapsed_s,
    live_gap,
    live_gap <= IEEE8500_MV_EXACT_ATOL ? "exact" : "inexact"
)

# ## Precomputed section — the full cross-fixture density sweep
#
# !!! note "This curve is precomputed, and deliberately so"
#     The full grid — 4 fixtures (`ieee13`, `ieee123`, `ieee8500-mv`, `ieee8500`) × 4 densities
#     (10/25/50/100%) × 2 solver configurations × {centralized, ADMM}, at the full `T = 24` horizon
#     — costs far more than any single docs page's cheap-slice budget, and at IEEE-8500 scale
#     several of its points **exceeded the measurement machine's available RAM outright** (see
#     below) — it cannot be attempted live here at any density. It is therefore **loaded from
#     committed data**, not solved on this page. Regenerate any single point with:
#     ```
#     julia --project=. scripts/benchmark_ieee8500.jl --fixture ieee8500 --density 1.0 --solver both --time-limit 120
#     ```
#     which upserts into `results/ieee8500_benchmark/density_sweep.csv` (one row per
#     `(fixture, density, solver)` key — safe to re-run one point at a time, which is in fact how
#     the IEEE-8500-scale points in the table below were produced, after discovering live that the
#     harness writes an entire invocation's rows in one pass at the end of its density loop, so a
#     mid-run crash on one point can silently discard already-computed sibling points from the SAME
#     invocation). `results/ieee8500_benchmark/density_sweep_full.csv`, read below, is this phase's
#     own consolidated copy across all four fixtures, with full per-point provenance (including the
#     manually-recorded OOM rows this page reports) in
#     `.planning/phases/25-ieee-8500-scalability-benchmark/25-06-SUMMARY.md`.
#
# Parsed with `Base` only, mirroring the `SOC Relaxation Applicability` page's own
# `read_sweep_csv` exactly: the docs environment pins a deliberately minimal dependency set, and a
# numeric table this project generates itself does not justify adding `CSV`/`DataFrames` to it and
# re-resolving `docs/Manifest.toml` (which CI requires to stay in Julia-version lockstep). The one
# adaptation needed here versus that page's parser: this table's trailing `error_msg` column is
# free text that can itself contain commas (and gets CSV-quoted when it does), so the split is
# `limit`ed to the known column count rather than splitting unconditionally on every comma.

function read_sweep_csv(path)
    lines = readlines(path)
    header = split(first(lines), ',')
    idx = Dict(strip(h) => i for (i, h) in enumerate(header))
    ncols = length(header)
    num(s) = (v = tryparse(Float64, s); v === nothing ? NaN : v)
    return map(lines[2:end]) do ln
        f = split(ln, ','; limit = ncols)
        (;
            fixture = strip(f[idx["fixture"]]),
            density = num(f[idx["density"]]),
            solver = strip(f[idx["solver"]]),
            assembly_time_s = num(f[idx["assembly_time_s"]]),
            solve_time_s = num(f[idx["solve_time_s"]]),
            total_time_s = num(f[idx["total_time_s"]]),
            termination_status = strip(f[idx["termination_status"]]),
            exact_verdict = strip(f[idx["exact_verdict"]]),
            admm_status = strip(f[idx["admm_status"]]),
            admm_iters = something(tryparse(Int, f[idx["admm_iters"]]), -1),
            admm_peak_rss_delta_mb = num(f[idx["admm_peak_rss_delta_mb"]]),
        )
    end
end

sweep_rows = read_sweep_csv(
    joinpath(pkgdir(TSODSO), "results", "ieee8500_benchmark", "density_sweep_full.csv"),
)

println(
    "fixture       density  centralized       admm              exact     total_s   admm_iters",
)
for r in sweep_rows
    @printf(
        "%-13s %-8.2g %-17s %-17s %-9s %-9s %-3d\n",
        r.fixture,
        r.density,
        r.termination_status,
        r.admm_status,
        isempty(r.exact_verdict) ? "-" : r.exact_verdict,
        isnan(r.total_time_s) ? "-" : @sprintf("%.1f", r.total_time_s),
        r.admm_iters
    )
end

# ## The headline point, stated plainly
#
# The 4,875-bus/4,874-branch fixture at density = 1.0 — every load bus populated — is this phase's
# central deliverable point. Its measured outcome:

hl = only(filter(r -> r.fixture == "ieee8500" && r.density == 1.0, sweep_rows))
@printf(
    "ieee8500 density=1.0: termination_status=%s admm_status=%s\n",
    hl.termination_status,
    hl.admm_status
)

# `OOM_KILLED` on both columns is the literal, unsmoothed measured outcome: the Linux OOM-killer
# terminated the Julia process (confirmed via `journalctl -k` — `Out of memory: Killed process
# 426898 (julia) total-vm:9791812kB, anon-rss:8393224kB` — on a shared 15 GiB machine whose swap
# was independently near its ceiling from OTHER, unrelated processes at the same moment) before
# `solve_welfare` or `solve_admm` ever reached their OWN convergence check, their OWN D-18
# wall-clock timeout, or the PF-04 SOCP-exactness gate. **The headline point did not converge, did
# not time out, and was never evaluated for exactness — it is memory-bound, not exactness- or
# convergence-bound, on this measurement machine.** The smallest density (0.1) on this SAME fixture
# also OOM-killed, on two separate attempts; the two intermediate densities (0.25, 0.5) were not
# attempted, bracketed as they are by OOM at both grid ends. This is reported as a valid,
# non-retried, non-substituted result (Phase 23 D-10's "honest non-convergence is a valid
# deliverable" carried forward one step further: honest non-completion is too) — never as a
# passing row manufactured by loosening a tolerance or a time budget (T-25-12).
#
# The MV-only control fixture (`ieee8500-mv`, 2,521 buses) fares only somewhat better: its own
# density=0.1 point (the SAME point solved live above) converges centralized and reports
# `exact`, but ADMM there hits its `maxiter` cap without both residuals converging — a genuine
# algorithmic non-convergence, not a bug — and both its density=0.5 and density=1.0 points also
# OOM-killed on this machine.

# ## Synthesis — conditioning, size, or formulation?
#
# Triangulating across every signal Phase 25's plans produced, rather than reading the OOM outcome
# in isolation:
#
# - **Size (network scale) is the first-order driver of the memory wall.** The density sweep's own
#   cost-vs-buses curve (IEEE-13: sub-second to ~29 s; IEEE-123: ~1–26 s; IEEE-8500-MV: ~47–102 s
#   before OOM; IEEE-8500 headline: OOM at every attempted density including the smallest) tracks
#   bus/branch count directly, and the OOM points are exactly the two largest fixtures — never
#   IEEE-13 or IEEE-123, regardless of density. `T = 24` and the JuMP-assembly cost it multiplies
#   are FIXED per fixture regardless of density (the general sweep's own harness comments,
#   `scripts/benchmark_ieee8500.jl`), so this is a network-size effect, not a population-fan-out one.
# - **The MV-only-vs-headline comparison isolates the LV rungs as a genuine SECOND size effect on
#   top of MV alone.** `ieee8500-mv` (2,521 buses, MV only) survives to density=0.25 before OOM;
#   the full `ieee8500` (4,875 buses, MV+LV) OOM's even at its SMALLEST density. Going from
#   MV-only to full MV+LV very nearly doubles bus count and pushes the wall from "survives low/mid
#   density" to "never survives, any density" — attributable to the LV rungs' own added scale, not
#   to their conditioning (D-02's design intent for this control fixture).
# - **Conditioning is a REAL, separate, and worse-than-expected wall — but not the one this
#   session's OOMs are attributable to.** Plans 25-05/25-07 already established, independent of any
#   memory measurement, that the SOCP-exactness noise floor on both IEEE-8500 fixtures (`~1e-3`)
#   sits an order above the project's `1e-6` default — meaning even a point that AVOIDED the memory
#   wall entirely (smaller T, more headroom, a bigger machine) would still risk throwing at
#   `solve_admm`'s hardcoded final-consolidation gate on a genuine convergence (deferred-items.md
#   item 3). The two walls are independent: this session's OOMs fired BEFORE that gate was ever
#   reached, so no OOM'd point in the table above is evidence about conditioning one way or the
#   other — the conditioning finding stands on its own, from the calibration ladder alone.
# - **Formulation (Clarabel vs. SCS) is not implicated by this session's evidence — but the
#   crossover diagnostic HAS since been measured off the headline point.** *(Corrected 2026-08-24,
#   milestone-audit SCALE-04 closure: the earlier text here said SCS "was not installed in the
#   measurement environment" and that `scs_status` on EVERY attempted row read
#   `scs_unavailable`/`skipped_oom`/`not_requested`. That was true when first written, but plan
#   25-08 installed SCS in the dedicated `bench/` environment and re-ran the small fixtures, so it
#   is now factually wrong and is corrected rather than quietly deleted.)*
#   `density_sweep_full.csv` now carries **9 real SCS solves**: `ieee13` at densities 0.1/0.25/0.5
#   (`OPTIMAL`, DADP drift 0.253 → 2.329 → 4.823, i.e. growing with population), `ieee13` at
#   density 1.0 (a genuine `ErrorException` from SCS itself, not a harness failure), `ieee123` at
#   all four densities (`OPTIMAL`, drift flat at ~0.002–0.005), and `ieee8500-mv` at density 0.1
#   (`OPTIMAL`, drift 0.112). Reconfirmed bit-for-bit on 2026-08-24.
#   **No crossover exists anywhere in that measured range** — Clarabel is `OPTIMAL`, exact, and
#   faster at every measured point. That is the honest answer to "identify the crossover," not an
#   extrapolation: the range covered is stated, and nothing beyond it is claimed. Per this script's
#   own Pitfall-5 warning, Clarabel's `tol_gap` and SCS's `eps_abs` are NOT comparable numbers, so
#   the drift column is a diagnostic, never a solver-quality ranking.
#   What remains genuinely UNTESTED is the diagnostic at the **headline** (~40x, full MV+LV) point
#   specifically: those rows read `skipped_oom`/`not_requested` because they OOM'd BEFORE the
#   comparison could run. So whether the memory wall is Clarabel-specific or would recur under
#   SCS's first-order method is still unknown at headline scale — untested there, not "ruled out."
# - **Assembly-vs-solve split (where it was measured, i.e. never on an OOM'd point) shows assembly
#   is already a large, non-time-limit-bounded share of cost** at MV scale (e.g. `ieee8500-mv`
#   density=0.25: ~52 s assembly vs ~50 s solve) — consistent with JuMP model-build cost, not IPM
#   iteration count, being a first-order contributor to the memory footprint that eventually OOMs.
#
# **Honest conclusion: a wall was observed, and it is attributable to network SIZE first (with a
# SEPARATE, independently-established conditioning wall waiting behind it for any point that would
# otherwise survive) — not to solver formulation, which this session's environment could not even
# test at this scale.** This is one of the three explicitly acceptable outcomes this project's own
# standing convention permits (no wall / a wall attributable to X / a wall whose attribution is
# inconclusive) — the middle one, stated without inflating the OOM evidence to also cover the
# formulation question it could not touch.
#
# ## Reproducing this
#
# ```
# julia --project=. scripts/benchmark_ieee8500.jl --fixture ieee8500-mv --density 0.1 --solver both --time-limit 120
# julia --project=. scripts/benchmark_ieee8500.jl --fixture ieee8500 --density 1.0 --solver both --time-limit 120
# ```
#
# Each invocation upserts its own `(fixture, density, solver)` rows into
# `results/ieee8500_benchmark/density_sweep.csv`; run one density at a time on IEEE-8500-scale
# fixtures specifically, per the mid-run-crash discovery noted above. Full provenance, including
# every OOM's `journalctl -k` record and this page's own measured docs-build baseline, is in
# `.planning/phases/25-ieee-8500-scalability-benchmark/25-06-SUMMARY.md`.

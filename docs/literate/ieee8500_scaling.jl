# # Scaling to IEEE-8500 — where the wall is, and what it is made of
#
# This page asks a blunt question of the operational pipeline that every other rung page in this
# manual exercises at 3–123 buses: **does it hold ~40× above IEEE-123, the largest fixture shipped
# to date?** The answer this page reports is not "yes" or "no" but a measured, honest curve — a
# **density sweep** across the
# committed IEEE-8500 fixtures (`ieee8500_mv_modified()`, 2,521 buses/2,520 branches MV-only;
# `ieee8500_modified()`, 4,875 buses/4,874 branches, full MV+LV — the headline) and the two smaller
# fixtures used everywhere else in this manual (IEEE-13, IEEE-123), each at 10/25/50/100% of its
# load buses populated, both centralized and via ADMM.
#
# ## Two walls, not one
#
# The sweep's own noise-floor calibration (re-measured after a real
# vendored near-zero-impedance MV connector was reshaped to the project's existing near-ideal
# treatment) already found a **conditioning** wall: even after that fix, both IEEE-8500 fixtures'
# own SOCP-exactness noise floors sit at `~1e-3`, an order above the project's project-wide
# `assert_socp_exact!` default (`atol = 1e-6`) — so a genuinely CONVERGED, CONSOLIDATED ADMM point
# on either fixture can still throw at `solve_admm`'s hardcoded final-consolidation gate
# (a known open limitation).
#
# Running the actual density sweep for this page surfaced a **second, cruder wall that arrives
# first**: on the shared machine this sweep was measured on, the Linux OOM-killer terminated the
# Julia process outright at several IEEE-8500-scale points — including the 4,875-bus headline point
# at full density — before either the conditioning wall above or the harness's own wall-clock
# timeout ever had a chance to fire. Both walls are reported below, honestly and separately; neither
# is smoothed into the other.

using TSODSO
using TSODSO: SOCP, build_feeder, build_population, build_price, ieee8500_mv_load_buses
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

## The freshly-calibrated, fixture-fresh noise floor for
## `ieee8500-mv` — never inherited from IEEE-13/123 (anti-certificate-laundering).
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
#     invocation). `results/ieee8500_benchmark/density_sweep_full.csv`, read below, is the
#     consolidated copy across all four fixtures, with the manually-recorded OOM rows this page
#     reports.
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
    ## `admm_iters` is written as an Int, but older harness runs wrote it as a Float (`8.0`) and
    ## failure rows as `NaN`/`-1`: accept all three, mapping anything unparsable or non-finite to -1.
    iters_cell(s) = (v = num(s); isfinite(v) ? round(Int, v) : -1)
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
            admm_iters = iters_cell(f[idx["admm_iters"]]),
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
# The 4,875-bus/4,874-branch fixture at density = 1.0 — every load bus populated — is this sweep's
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
# `solve_welfare` or `solve_admm` ever reached their OWN convergence check, their OWN
# wall-clock timeout, or the SOCP-exactness gate. **The headline point did not converge, did
# not time out, and was never evaluated for exactness — it is memory-bound, not exactness- or
# convergence-bound, on this measurement machine.** The smallest density (0.1) on this SAME fixture
# also OOM-killed, on two separate attempts; the two intermediate densities (0.25, 0.5) were not
# attempted, bracketed as they are by OOM at both grid ends. This is reported as a valid,
# non-retried, non-substituted result (honest non-convergence is a valid
# deliverable, and honest non-completion is too) — never as a
# passing row manufactured by loosening a tolerance or a time budget.
#
# *(Update 2026-10-04: after the v4.0 refactor the ADMM-only headline at density 0.1 does run to convergence
# and is then refused by the exactness gate; see "Post-refactor measured results" below.)*
#
# The MV-only control fixture (`ieee8500-mv`, 2,521 buses) fares only somewhat better: its own
# density=0.1 point (the SAME point solved live above) converges centralized and reports
# `exact`, but ADMM there hits its `maxiter` cap without both residuals converging — a genuine
# algorithmic non-convergence, not a bug — and both its density=0.5 and density=1.0 points also
# OOM-killed on this machine.

# ## Post-refactor measured results
#
# *(Appended 2026-10-04; provenance tightened 2026-10-05. The v3.0 text above is kept as
# history; where it says the headline point "did not converge", read it together with this section. Every
# figure below names its source: a file in `results/ieee8500_benchmark/` (`density_sweep.csv`,
# `hybrid_diagnostic.csv`, `point_resources.csv`, `memory_profile.csv`, `memory_wall_recharacterization.csv`,
# `density_sweep_full.csv`, or a per-run file in `runs/`) and, where the file has one, the row's
# `run_label`.)*
#
# **Units.** All memory figures in this section are binary: 1 GiB = 2^30 bytes = 2^20 KiB = 1024 MiB. Raw
# values are KiB for `/usr/bin/time` and `/proc` (`peak_rss_kb`, `VmRSS_kB`, kernel `anon-rss:...kB`) and
# MiB for the harness's `admm_peak_rss_delta_mb`/`peak_rss_mb` (bytes / 2^20), earlyoom's `VmRSS ... MiB`
# and `free -m`; each is converted by the matching power of 2 and the raw value is kept beside it.
#
# **1. Library default change.** `solve_admm`/`solve_dso!` now default `atol_exact` to `nothing`, i.e. the
# ADMM final-consolidation gate uses the same per-branch hybrid floor as the centralized path
# (`atol_b = max(2e-7, 1e-9*ref_b)`, relative term on the cone value). An explicit `Real` `atol_exact` keeps
# its old flat-bypass semantics. The gate logic, `tau` and the comparison epsilon are untouched. The new
# default is stricter than the old flat `1e-6` except on branches with `smax` of 32-99 pu, so a
# `CertificateError` can now newly appear for a gap in (2e-7, 1e-6]. This is a deliberate behaviour change.
#
# **2. SC1 diagnostic (density 0.1, T = 10, gate bypassed with `--admm-diagnostic-bypass`).** Source:
# `density_sweep.csv` row `run_label = p35-diag-d0.1-T10` (`solver = admm_bypass`,
# `admm_atol_used = Inf(DIAGNOSTIC_BYPASS)`), and the 20 `hybrid_diagnostic.csv` rows with the same
# `run_label`. The ADMM run converged in 8 iterations (`admm_iters` of that row). The worst branch is
# `L2916620 -> N1136366` (b = 1325, t = 3; first `hybrid_diagnostic.csv` row): `r_pu = 2.40e-6`, cone gap
# `1.21e-4`, `atol_b = 2.0e-7`, hybrid ratio **568.95** (also the row's `diag_max_ratio`). All 20 recorded
# rows have ratio > 1 (the smallest is 289.06). The largest loss-weighted impact `r_pu * gap` over **all**
# branch-hours is `4.4e-9` pu: the row's `diag_loss_impact_max`, which the harness computes as the maximum
# of `loss_impact = r_pu * gap` over every `hybrid_ratios` row. The 20 rows kept in `hybrid_diagnostic.csv`
# are the 20 largest *ratios*, not the largest impacts; their own `loss_impact` column peaks at `2.9e-10`.
# Either way the economic effect is negligible, but the certificate refusal is **genuine**: these are
# near-ideal (very low resistance) branches where the relaxation gap is not certified at the floor. No
# tolerance was raised and no branch was excluded.
#
# **3. Headline re-measurement (density 0.1, T = 10, ADMM-only, library hybrid gate).**
#
# | metric | v3.0 | post-refactor |
# |---|---|---|
# | source row | `density_sweep.csv`, key `(ieee8500, 0.1, clarabel, T_horizon = 10)`, no `run_label` (written 2026-08-22, commit `262c983`) | `density_sweep.csv`, `run_label = p35-head-d0.1-T10` |
# | centralized | `ALMOST_OPTIMAL`, refused by `assert_solved!` | not run (`--admm-only`) |
# | ADMM gate | flat `atol_exact = 4.97e-3` (`admm_atol_used = 0.004969`, the old `IEEE8500_EXACT_ATOL`) | library hybrid floor (`admm_atol_used = hybrid`, `atol_b` as low as 2e-7) |
# | ADMM outcome | `converged`, passed the flat gate | `ERROR:CertificateError` (prices REFUSED, ratio 568.95) |
# | ADMM iterations | 8 | 8, taken from the `p35-diag-d0.1-T10` row (the gate-bypassed re-run of the same point, section 2); the head row was written before the harness recorded iteration counts for refused points, with `NaN`, normalized to the unknown sentinel `-1` by a later repair (`aa6277e`) |
# | ADMM time (`admm_time_s`) | 227 s | 287 s |
# | peak RSS | no harness-recorded peak (see below) | 5.92 GiB (6,205,808 KiB, `point_resources.csv` `peak_rss_kb`, same `run_label`) |
# | ADMM RSS delta (`admm_peak_rss_delta_mb`) | 3.13 GiB (3,200.4 MiB) | 4.56 GiB (4,672.8 MiB) |
#
# The status change is **partly a gate change, not only a model or solver change**: v3.0 certified this
# point under a flat tolerance about 5,000 times looser than the old `1e-6` default, while the post-refactor run applies
# the per-branch hybrid floor. The commit that wrote the v3.0 row (`262c983`) also records that the same
# point, run under the then-default flat `1e-6` gate, raised "SOCP relaxation INEXACT" (cone gap
# `1.3968e-4`) and converged only with the flat `4.97e-3` override; that failed run left no CSV row. So
# under any gate near `1e-6` this point was already refused in v3.0. The v3.0 row is also NOT the
# IEEE-8500 d = 0.1, T = 10 row printed by the precomputed table above: that one comes from `density_sweep_full.csv` and is an earlier attempt of
# the same point (`budget_exceeded` after 6 iterations, 153 s, under the old 120 s ADMM budget and
# `clarabel_tol_gap = 1e-8`); the 8-iteration row is the re-run after the budget was raised to 1200 s, with
# `clarabel_tol_gap = 1e-7`. The v3.0 "about 5.9 GB" peak sometimes quoted for this point is not a harness
# measurement: it is the "~5.9GB" anon-rss observed by live monitoring during that earlier
# `budget_exceeded` attempt, written into the `error_msg` of its `density_sweep_full.csv` row, with no
# recorded unit convention. Read as GiB it is 5.9 GiB; read as decimal GB it is 5.49 GiB. Against the
# post-refactor peak of 5.92 GiB that is either +0.3% or +8%, from a different metric (anon-rss vs peak RSS) on a
# different run, so **no peak-memory change between v3.0 and the post-refactor run can be claimed from it**; the
# difference is within the units and measurement uncertainty of that note. The two RSS
# deltas are not like-for-like either: the v3.0 delta was taken after a centralized solve in the same
# process, the post-refactor delta in an ADMM-only process. The time and memory difference may also include load
# from other processes on the shared host and extra GC calls added to the harness; it was not isolated.
#
# **4. Ladder and memory wall (15.5 GiB host: `free -m` total 15,908 MiB in `runs/*.free_before`; earlyoom
# `-m 12`, i.e. SIGTERM at or below 12% available memory).** Peak RSS is `point_resources.csv` `peak_rss_kb` (from `/usr/bin/time -v`); process wall is the "Elapsed" line of `runs/<run_label>.time`;
# `admm_time_s` is from `density_sweep.csv` (n/a for the killed point, whose row stayed `started`).
#
# | point (`run_label`) | outcome | peak RSS | process wall | `admm_time_s` |
# |---|---|---|---|---|
# | Original sweep, density 0.1 and 1.0, T = 24 (combined centralized+ADMM process; `density_sweep_full.csv` `OOM_KILLED` rows) | OOM kills | n/a | n/a | n/a |
# | `p35-head-d0.1-T10` | `CertificateError` (ratio 568.95) | 5.92 GiB (6,205,808 KiB) | 335 s | 287 s |
# | `p35-head-d0.1-T24` | ADMM completed, `CertificateError` (ratio 223.68) | 11.52 GiB (12,079,316 KiB) | 728 s | 678 s |
# | `p35-head-d0.25-T24` | earlyoom SIGTERM, `VmRSS 10641 MiB` (10.4 GiB) at the kill (`runs/p35-head-d0.25-T24.oom_earlyoom`) | 12.05 GiB (12,636,180 KiB) | 213 s | n/a |
#
# The wall now sits **between density 0.1 and 0.25 at T = 24**. The original sweep's OOM kills at T = 24 were in a
# combined centralized+ADMM process; its density 0.1 T = 10 point fit (live-monitored anon-rss "~5.9GB", unit
# not recorded, see section 3). **What consumes the memory inside `solve_admm` was not established by the
# measurements below when they were taken — the Phase-39 staged attribution ("Memory attribution of the
# `solve_admm` loop (Phase 39, SCALE-06)" below) now splits it at T = 10 and records honestly what stayed
# unmeasurable at T = 24; the rest of this section is kept as the Phase-35 state it was measured in.**
# Two kinds of figure were measured, with different metrics:
#
# - **Staged profile (VmRSS between stages).** The profile of the SAME fixture and point (`memory_profile.csv`
#   rows with `fixture = ieee8500`, density 0.1, T = 10, written by run `p35-prof-ieee8500-s3` in
#   `point_resources.csv`) shows one `build_dso_opt` adding 0.23 GiB of VmRSS (stage 1 to 2: 1,102,128 to
#   1,340,200 KiB) and the first `optimize!` a further 0.89 GiB (stage 2 to 3: 1,340,200 to 2,269,900 KiB),
#   i.e. 1.12 GiB of VmRSS for one DSO build plus its first solve. Measured as VmHWM over the same stages
#   (1,254,188 to 2,515,692 KiB) it is 1.20 GiB. The profile stops at stage 3; no committed run reached
#   stage 5 (`after_agr_opts`), so the AgrOpt contribution was not measured.
# - **Whole-loop peak-RSS delta.** `admm_peak_rss_delta_mb` (`Sys.maxrss()` after `solve_admm` minus before
#   it) of the two head rows in `density_sweep.csv` is 4.56 GiB (4,672.8 MiB) at T = 10 and 10.17 GiB
#   (10,409.9 MiB) at T = 24. This delta covers everything `solve_admm` allocates: the DSO build and its
#   solves, one `build_agr_opt` per aggregator (122 here) and their solves, any state kept across
#   iterations, and the final `check_exact = true` consolidation.
#
# One DSO build plus its first solve therefore accounts for about a quarter of the T = 10 loop's peak
# growth. The remainder (about 3.4 GiB) was **unattributed** when this section was written; the Phase-39
# staged attribution below now splits it (headline at T = 10: the 122 AgrOpt builds and the first iterate's
# retained state dominate). The guess recorded below — that the remainder is mostly per-hour DSO solver state
# retained across the ADMM loop — was a **hypothesis**, not a measurement, and the Phase-39 isolated
# measurement did NOT confirm it as the dominant mechanism (see below). The only scaling statement the data support is that the
# loop delta grows roughly linearly in T (one pair of points, T = 10 and T = 24, at density 0.1); scaling in
# the number of nodes was not measured, because only density 0.1 completed at T = 24. (The same CSV also
# keeps an earlier profile with `fixture = ieee8500-mv`, the profiler's default, which measured 0.14 / 0.42
# GiB on the 2,521-bus MV-only feeder. It is a different fixture from the loop deltas above and is not used
# for this comparison.) No `src/` memory mitigation was adopted: no consumer was shown to be dominant, and
# none was provably bit-identical.
#
# **5. Protocol.** ADMM-only (`--admm-only`), one measurement point per process, each wrapped with peak-RSS
# capture and earlyoom attribution, with the number of other Julia processes and free memory/swap recorded
# before each point (`point_resources.csv`, `runs/`). One attempt per ladder step; no retry after a kill.

# ## Synthesis — conditioning, size, or formulation?
#
# Triangulating across every signal the original sweep produced, rather than reading the OOM outcome
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
#   to their conditioning (the design intent for this control fixture).
# - **Conditioning is a REAL, separate, and worse-than-expected wall — but not the one this
#   session's OOMs are attributable to.** The calibration ladder already established, independent of any
#   memory measurement, that the SOCP-exactness noise floor on both IEEE-8500 fixtures (`~1e-3`)
#   sits an order above the project's `1e-6` default — meaning even a point that AVOIDED the memory
#   wall entirely (smaller T, more headroom, a bigger machine) would still risk throwing at
#   `solve_admm`'s hardcoded final-consolidation gate on a genuine convergence (the known open
#   limitation noted above). The two walls are independent: this sweep's OOMs fired BEFORE that gate was ever
#   reached, so no OOM'd point in the table above is evidence about conditioning one way or the
#   other — the conditioning finding stands on its own, from the calibration ladder alone.
# - **Formulation (Clarabel vs. SCS) is not implicated by this sweep's evidence — but the
#   crossover diagnostic HAS since been measured off the headline point.** *(Corrected 2026-08-24,
#   audit closure: the earlier text here said SCS "was not installed in the
#   measurement environment" and that `scs_status` on EVERY attempted row read
#   `scs_unavailable`/`skipped_oom`/`not_requested`. That was true when first written, but a later
#   run installed SCS in the dedicated `bench/` environment and re-ran the small fixtures, so it
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
# otherwise survive) — not to solver formulation, which this sweep's environment could not even
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
# fixtures specifically, per the mid-run-crash discovery noted above. The `journalctl -k` record of every OOM
# is kept alongside the sweep results.

# ## Memory attribution of the `solve_admm` loop (Phase 39, SCALE-06)
#
# *(Appended 2026-10-24. Extends the "Post-refactor measured results" section above: the ~3.4 GiB that
# section left unattributed at T = 10 is now split by instrumented staged runs, and the per-hour DSO
# solver-state wording is resolved by an isolated measurement. Every figure below names its source:
# `results/ieee8500_benchmark/memory_attribution.csv` with the row key
# (fixture, density, T, stage, name) — unless another file is named. The two measured points are
# `fixture = ieee8500`, `density = 0.1`, `T = 10` and `T = 24`, the Phase-35 boundary points.)*
#
# **Units.** All memory figures are binary: 1 GiB = 2^30 bytes = 2^20 KiB. Raw KiB come from
# `/proc/self/status` (`VmRSS` instantaneous, `VmHWM` the whole-process high-water) and `/usr/bin/time`
# MaxRSS; `Sys.maxrss()` readings are bytes; each converted value keeps its raw source in the CSV or the
# `runs/` evidence files.
#
# **Method.** `scripts/profile_ieee8500_memory_attribution.jl` (committed this phase) measures ONE point
# per process. First the RECONCILIATION ANCHOR: one full production `solve_admm` call with exactly the
# Phase-35 head-row arguments (`benchmark_ieee8500.jl`'s `run_admm_point`: ρ = 100, `allow_export = true`,
# the library hybrid exactness gate, a 1200 s wall budget) wrapped in a `Sys.maxrss()` before/after delta —
# always FIRST in the process, because maxrss is a monotonic whole-process high-water mark and a staged
# build before it would zero the delta. Then GC'd staged components, each an ISOLATED measurement (this
# project's Pitfall-8 rule — the stages are not arranged around any assumed mechanism): the DSO build
# alone, the 122 AgrOpt builds alone, the first iterate's retained state (iterate 1 contains the DSO
# model's first `optimize!` AND the first AGR solves), iterates 2..N retained, and the
# consolidation/certify. Each component carries a stated measurement tolerance, max(0.05 GiB, 10 % of the
# component) — allocator arena retention and the anchor-warmed process context dominate the run-to-run
# spread for this class of staged snapshot. Components are GC-RETAINED deltas; the anchor's maxrss delta
# additionally includes solve CHURN, so observed − Σ components is reported as an explicit RESIDUAL
# (tolerance: quadrature sum of the component tolerances) — never forced onto a mechanism. Two provenance
# details: the bounded iteration block splits `_admm_iterate!` into a 1-iteration call plus an (N−1)
# continuation, resetting only the residual ledger's sequential-`k` bookkeeping between them (the solve
# statements are the exact production sequence), so the staged certify evidence row's `iterations = 7`
# undercounts the logical count by one — the production number of record is the anchor row's
# `iterations = 8`; and the bounded N is the anchor's own observed production iteration count.
#
# **T = 10, density 0.1 (row keys fixture=ieee8500, density=0.1, T=10; run `p39-attr-d0.1-T10` in
# `point_resources.csv`, 14 m 59 s process, MaxRSS 5,969,080 KiB = 5.69 GiB, `runs/p39-attr-d0.1-T10.time`).**
# The anchor reproduced the Phase-35 refusal exactly: `anchor_after` row, status `ERROR:CertificateError`,
# iterations = 8, the same hybrid ratio 568.9541645248668 that `density_sweep.csv` /
# `hybrid_diagnostic.csv` record for `p35-head-d0.1-T10` / `p35-diag-d0.1-T10` — a genuine gate refusal,
# recorded as evidence, never loosened. Its observed maxrss delta is **4.339 GiB** (row `anchor_after`,
# `gib` column; anchor time 425 s; process peak 5.623 GiB). Phase 35 measured this same point's loop delta
# as 4.56 GiB (4,672.8 MiB, `density_sweep.csv` `p35-head-d0.1-T10`) and peak 5.92 GiB
# (6,205,808 KiB, `point_resources.csv`): the re-measurement sits ~5 % below both, within the combined
# run-to-run/host uncertainty of the two measurements. The staged components (stage-9 rows):
#
# | component (`memory_attribution.csv` stage-9 row) | GiB | tolerance | source rows (stage) |
# |---|---|---|---|
# | `comp_dso_build` | +0.408 | ±0.05 | `pre_staged_gc` → `build_dso_opt` (2) |
# | `comp_agr_builds` | +1.724 | ±0.172 | `build_dso_opt` → `after_agr_opts` (2) |
# | `comp_first_iter_retained` | +1.370 | ±0.137 | `iter_before_gc` → `after_first_optimize_gc` (3-4) |
# | `comp_iter_retained` | +0.318 | ±0.05 | `after_first_optimize_gc` → `iter_after_gc` (4) |
# | `comp_certify` | −0.100 | ±0.05 | `iter_after_gc` → `after_certify_gc` (5) |
# | Σ components | +3.720 | ±0.237 | `reconciliation:components_total` |
# | **residual** | **+0.620** | ±0.237 | `residual` (9) |
#
# The residual (observed 4.339 − Σ 3.720) is ~14 % of the observed delta and is honestly composed of what
# the staged snapshots structurally exclude: solve churn the GC'd snapshots don't retain, allocator
# retention, and the anchor-warmed process context. This is a documented honest residual — the outcome
# class the project's honesty policy accepts — not a fit forced onto the components.
#
# **What the measurements NAME at T = 10 (replacing the Phase-35 hypothesis):** the previously
# unattributed ~3.4 GiB is dominated by the 122 per-aggregator model builds (+1.724 GiB) and the first
# iterate's retained state (+1.370 GiB — the DSO model's first `optimize!` plus the 122 first AGR solves
# plus the consensus state; the Phase-35 "+0.89 GiB first optimize" figure was the DSO model alone,
# measured before any AGR solve existed). The isolated stage-4 test measured the per-hour DSO solver
# state candidate — retained growth across iterates 2..8 — at **+0.318 GiB total, ≈ 0.045 GiB per
# iteration**: an order of magnitude below the build and first-iterate components. The Phase-35
# hypothesis that the growth is mostly per-hour DSO solver state retained across the loop is therefore
# NOT what the isolated measurement shows at T = 10, and is recorded as refuted-as-dominant (it exists,
# it is just small). The consolidation/certify component is ≈ 0 (−0.100 GiB net retained): no large
# retained consolidation state.
#
# **What scales with T (measured, not hypothesized):** the models themselves. The reduced build-only run
# at T = 24 (`p39-attr-d0.1-T24-s2`, stage-2 rows) measured `build_dso_opt` +0.922 GiB and the 122 AgrOpt
# builds +4.024 GiB — 2.26× and 2.33× their T = 10 values for T going 10 → 24 (2.4×), i.e. the build
# components are ~linear in T because each of the 123 JuMP models is ~linear in T. The T = 24 process
# peaked at 6,366,664 KiB = 6.07 GiB with builds ALONE — before any solve — which is the quantitative
# bridge to Phase-35's 11.52 GiB full-solve peak (builds + first-solve retained state + loop churn).
#
# **T = 24, density 0.1: loop attribution honestly NOT ESTABLISHED — the full run was earlyoom-killed.**
# The full staged run (`p39-attr-d0.1-T24`) was SIGTERM'd by earlyoom during the ANCHOR itself (row
# `anchor_earlyoom_killed`, a post-run evidence repair recorded out-of-process because the process died;
# `runs/p39-attr-d0.1-T24.oom_earlyoom`: two SIGTERMs at 06:19:20/06:19:30, VmRSS 5950/5885 MiB at kill;
# MaxRSS 7,820,096 KiB = 7.46 GiB, `runs/p39-attr-d0.1-T24.time`). The host state at launch explains it:
# 6,307 MiB available with 10,057 MiB swap already used (`runs/p39-attr-d0.1-T24.free_before`), versus
# ~10.3 GiB available / 1.5 GiB swap when Phase 35 measured this point successfully (11.52 GiB peak,
# 10.17 GiB loop delta — those Phase-35 figures REMAIN the standing T = 24 observations). Per this file's
# own protocol ("one attempt per ladder step; no retry after a kill", section 5) the full point was not
# retried; one REDUCED build-only attempt (`--stage 2`, no anchor/loop/certify) completed and is the
# source of the T = 24 build numbers above. The stage-1 rows for T = 24 in the CSV come from that
# reduced run (the killed run's load-stage rows share the same keys and were upsert-replaced); the T = 24
# stage-9 `residual` row records the non-attribution status. What the T = 10 attribution predicts for a
# future, quieter-host T = 24 run — builds ~4.95 GiB, first iterate ~3.3 GiB if it scales like the
# builds, per-iterate retention small — is inference, NOT measurement, and is labelled as such.
#
# **Cross-check against the Phase-35 profiler (+0.41 vs +0.23 GiB DSO build).** The Phase-35 staged
# profile (`memory_profile.csv`, fixture=ieee8500, density 0.1, T = 10; runs `p35-prof-ieee8500-s2`/
# `-s3` in `point_resources.csv`) measured `build_dso_opt` at +0.23 GiB (1,102,128 → 1,340,200 KiB) and
# the first `optimize!` at +0.89 GiB. This harness's staged DSO build measures +0.408 GiB on the same
# fixture/point. The build arguments are the same — `build_dso_opt`'s own defaults are already
# `ConvexBranchFlow` and the context-sensitive LIVE reactive resolution, and both runs use the same seed
# and population — so the difference is process context: the staged build runs AFTER the anchor's full
# solve in the same process (warm JuMP/solver runtime, allocator arenas that survive `GC.gc()` +
# `malloc_trim`). The 0.18 GiB gap exceeds the component's ±0.05 GiB tolerance and is absorbed by the
# residual's story; read the two numbers as the same component under two contexts, not as a build
# regression. For the same reason the T = 10 component table above is measured in an anchor-warmed
# process and carries its tolerances for exactly this class of context noise.
#
# **What this section does NOT establish.** No T = 24 loop attribution (earlyoom; Phase-35's whole-call
# figures stand, unsplit). No scaling exponent in T (two points, and the second is build-only). No
# per-stage churn split (would need allocation-site profiling — out of scope). No memory mitigation was
# adopted or evaluated: the two dominant components are the 123 JuMP models themselves (DSO + 122
# AgrOpt) and their first solves — the models must exist to run the algorithm at all, so nothing here
# identifies a dominant REMOVABLE retained consumer, and no consumer was shown to make a bit-identical
# mitigation possible.
#
# **Reproducing this (one point per process; expect ~15 min at T = 10 on this host):**
#
# ```
# julia --project=. scripts/profile_ieee8500_memory_attribution.jl --fixture ieee8500 --density 0.1 --t-horizon 10
# julia --project=. scripts/profile_ieee8500_memory_attribution.jl --fixture ieee8500 --density 0.1 --t-horizon 24 --stage 2
# ```
#
# Each invocation upserts its own `(fixture, density, T, stage, name)` rows into
# `results/ieee8500_benchmark/memory_attribution.csv` (`cols = :union`; re-runs replace their own rows,
# never drop others) and re-writes the CSV after every stage report, so a kill keeps the evidence rows
# captured before it. The full T = 24 point needs a host with ~12 GiB genuinely available at launch;
# on this 15.5 GiB host that means closing other work first — and if earlyoom kills it anyway, the kill
# is the recorded outcome.

# ## Headline measurement and go/no-go
#
# *(Appended 2026-11-05. Records the go/no-go decision for the `ieee8500` headline point (density
# 0.1, ADMM only, T = 24) and the measured T = 10 point run through `Scenario`. Older text above is
# kept as history. Where it disagrees with this section, the supersession notes at the end of this
# section say which statement stands. Nothing above was edited.)*
#
# **Units.** All memory figures are binary: 1 GiB = 2^30 bytes = 1,048,576 KiB. The raw KiB value
# (called kB in the CSV headers, as `/proc` and `/usr/bin/time` name it) is printed beside every GiB
# value.
#
# **Method.** Every number in this section is computed below from committed rows in four files under
# `results/ieee8500_benchmark/`:
# - `scenario_table.csv`: the `recorded_no_go` row and the `measured` row;
# - `memory_attribution.csv`: row key (fixture, density, T, stage, name);
# - `point_resources.csv`: wrapper rows by `run_label`;
# - `density_sweep.csv`: the earlier harness comparators.
#
# Hand-typed results are not used. The few figures quoted in the prose are old labels that this
# section corrects. The files are read with `Base` only. `memory_attribution.csv` and
# `density_sweep.csv` carry quoted free text in columns that are not last, so a split on commas
# limited to the column count is not enough. The reader below is therefore a small quote-aware
# splitter, and it checks the field count of every row against the header.

function hm_split_csv_line(ln::AbstractString)
    fields = String[]
    buf = IOBuffer()
    inq = false
    chars = collect(ln)
    i = 1
    while i <= length(chars)
        c = chars[i]
        if inq && c == '"' && i < length(chars) && chars[i + 1] == '"'
            print(buf, '"')
            i += 1
        elseif c == '"'
            inq = !inq
        elseif c == ',' && !inq
            push!(fields, String(take!(buf)))
        else
            print(buf, c)
        end
        i += 1
    end
    push!(fields, String(take!(buf)))
    return fields
end

function hm_read_rows(file)
    path = joinpath(pkgdir(TSODSO), "results", "ieee8500_benchmark", file)
    lines = filter(!isempty, readlines(path))
    header = strip.(hm_split_csv_line(first(lines)))
    return map(lines[2:end]) do ln
        f = hm_split_csv_line(ln)
        length(f) == length(header) ||
            error("$file: a row has $(length(f)) fields, the header has $(length(header))")
        Dict(String(h) => String(strip(v)) for (h, v) in zip(header, f))
    end
end

hm_num(s) = (v = tryparse(Float64, s); v === nothing ? NaN : v)
hm_gib(kb) = kb / 1024^2
## Same pattern as the script's parser (it accepts exponent notation such as 1.2e3).
hm_ratio(msg) = (
    m = match(r"worst gap/\(atol_b\+rtol·\|cone\|\)=([0-9.eE+-]+)", msg);
    m === nothing ? NaN : something(tryparse(Float64, m[1]), NaN)
)

hm_scn = hm_read_rows("scenario_table.csv")
hm_res = hm_read_rows("point_resources.csv")
hm_attr = hm_read_rows("memory_attribution.csv")
hm_sweep = hm_read_rows("density_sweep.csv")
hm_wrappers(label) = filter(r -> r["run_label"] == label, hm_res)
hm_attr_at(T) = filter(
    r -> r["fixture"] == "ieee8500" && hm_num(r["density"]) == 0.1 && r["T"] == T,
    hm_attr,
)
hm_attr_row(rows, stage, name) =
    only(filter(r -> r["stage"] == stage && r["name"] == name, rows))
hm_nogo = only(filter(r -> r["row_kind"] == "recorded_no_go", hm_scn))
hm_attr24 = hm_attr_at("24")
println(
    "rows read: scenario_table ",
    length(hm_scn),
    ", point_resources ",
    length(hm_res),
    ", memory_attribution ",
    length(hm_attr),
    ", density_sweep ",
    length(hm_sweep),
)

# ### The decision and its threshold
#
# The headline point was to be a GO if its peak resident memory stayed below the threshold recorded
# in the `recorded_no_go` row. The point is not re-run for this decision. Two independent
# observations of its peak exist:
# - the in-process high-water mark (`VmHWM`) of the earlier attribution run, the maximum over the
#   `memory_attribution.csv` rows with fixture `ieee8500`, density 0.1 and T 24;
# - the wrapper's `/usr/bin/time` MaxRSS of the earlier full-solve run, `point_resources.csv` row
#   `p35-head-d0.1-T24`.
#
# The check below also confirms that the committed decision row matches these sources.

hm_threshold_gib = hm_num(hm_nogo["threshold_gib"])
hm_hwm_kb = maximum(parse(Int, r["VmHWM_kB"]) for r in hm_attr24 if !isempty(r["VmHWM_kB"]))
hm_head24 = only(hm_wrappers("p35-head-d0.1-T24"))
hm_maxrss_kb = parse(Int, hm_head24["peak_rss_kb"])
@assert hm_num(hm_nogo["vmhwm_kb"]) == hm_hwm_kb
@assert hm_num(hm_nogo["p35_maxrss_kb"]) == hm_maxrss_kb
## GO needs the point's peak below the threshold, so the LARGER observed peak decides, and a
## peak equal to the threshold is a NO-GO.
hm_verdict =
    max(hm_gib(hm_hwm_kb), hm_gib(hm_maxrss_kb)) >= hm_threshold_gib ? "NO-GO" : "GO"
@assert (hm_verdict == "NO-GO") == (hm_nogo["status"] == "memory_infeasible")
@printf("GO threshold (recorded_no_go row):           %.1f GiB\n", hm_threshold_gib)
@printf(
    "in-process peak VmHWM (memory_attribution):   %d kB = %.3f GiB\n",
    hm_hwm_kb,
    hm_gib(hm_hwm_kb)
)
@printf(
    "wrapper MaxRSS (p35-head-d0.1-T24, rc %s):     %d kB = %.3f GiB\n",
    hm_head24["rc"],
    hm_maxrss_kb,
    hm_gib(hm_maxrss_kb)
)
println("verdict: ", hm_verdict, " (recorded status: ", hm_nogo["status"], ")")

# **What the verdict means.** NO-GO is a threshold verdict: the larger observed peak is above the
# GO threshold, so the headline point is not declared feasible on this host. The
# check above asserts that this recomputed verdict agrees with the status recorded in the row. It does **not** mean the
# point cannot run. The next subsection shows that it completed on this host, and states the
# conditions under which it did.

# ### The lower-bounded requirement
#
# Two quantities bound what the point needs, and they are of different kinds:
# - **B1 is a measured lower bound.** The point's peak resident set is at least the larger of the
#   two observed peaks. B1 uses measured numbers only.
# - **B2 is an estimate, not a bound.** B2 = B1 + 12 percent of the host's total memory. The
#   12 percent comes from this host's earlyoom configuration: it sends SIGTERM when available
#   memory and free swap both fall to 12 percent. B2 is the available memory the process needs so
#   that the host stays above that limit at the peak without relying on swap. It depends on the
#   earlyoom setting, and the swap condition makes it inexact.
#
# The host total in B2 comes from the measurement host's evidence (a `free -m` snapshot the wrapper
# saved), never from the machine that derives the row or builds this page.
#
# The requirement is on **MemAvailable at the peak**, not on installed RAM. The page cache, the
# operating system and every other process share the same physical memory.

hm_b1_kb = max(hm_hwm_kb, hm_maxrss_kb)
hm_b1_gib = hm_gib(hm_b1_kb)
@assert isapprox(hm_b1_gib, hm_num(hm_nogo["b1_gib"]); rtol = 1e-12)
hm_b2_gib = hm_num(hm_nogo["b2_gib_estimate"])
## B2's host total is the measurement host's evidence, not the machine that builds this page: the
## `free -m` total of the attribution run of this point (whose earlyoom log gives the 12 percent).
## B2 is recomputed from it here and checked against the row.
function hm_free_total_mib(label)
    fb = joinpath(
        pkgdir(TSODSO),
        "results",
        "ieee8500_benchmark",
        "runs",
        label * ".free_before",
    )
    return parse(Int, split(only(filter(l -> startswith(l, "Mem:"), readlines(fb))))[2])
end
hm_host_label = "p39-attr-d0.1-T24"
hm_host_mib = hm_free_total_mib(hm_host_label)
hm_b2_calc = hm_b1_gib + 0.12 * hm_host_mib / 1024
@assert isapprox(hm_b2_calc, hm_b2_gib; rtol = 1e-9)
@printf("B1 (measured lower bound): %d kB = %.3f GiB\n", hm_b1_kb, hm_b1_gib)
@printf(
    "B2 (estimate, earlyoom-dependent): %.3f GiB = B1 + 0.12 x %d MiB = %.3f GiB host total (free -m, %s)\n",
    hm_b2_calc,
    hm_host_mib,
    hm_host_mib / 1024,
    hm_host_label
)
## The total `free -m` reported was not constant across the runs on this host; both are printed.
for lbl in ("p35-head-d0.1-T24", "p46-scn-ieee8500-d10-T10")
    @printf("  free -m total at %s: %d MiB\n", lbl, hm_free_total_mib(lbl))
end

# **Counter-fact, stated with the bound.** The point completed on this host twice:
# - the earlier full-solve run `p35-head-d0.1-T24`;
# - the earlier attribution run, whose `anchor_after` row records a full production solve.
#
# The full-solve run started with less available memory than B1. MemAvailable already counts the
# page cache the kernel can reclaim, so the rest of its peak came from memory released during the
# run: swap-out of other pages, or other processes freeing memory. The wrapper did not measure
# which. The neighbouring point at density 0.25 was killed by earlyoom at its measured peak. The
# rows (the asserts keep these statements tied to them):

hm_anchor24 = hm_attr_row(hm_attr24, "1", "anchor_after")
hm_kill25 = only(hm_wrappers("p35-head-d0.25-T24"))
@assert hm_head24["rc"] == "0"
@assert hm_num(hm_head24["mem_avail_before_mb"]) / 1024 < hm_b1_gib
## "Ran to the end": at least one iteration, and not stopped by the wall-clock budget.
@assert parse(Int, hm_anchor24["anchor_iters"]) > 0 &&
        !occursin("budget", lowercase(hm_anchor24["anchor_status"]))
@assert hm_kill25["oom_source"] == "earlyoom"
@printf(
    "p35-head-d0.1-T24:  rc %s, MemAvailable before launch %s MiB = %.3f GiB (B1 = %.3f GiB)\n",
    hm_head24["rc"],
    hm_head24["mem_avail_before_mb"],
    hm_num(hm_head24["mem_avail_before_mb"]) / 1024,
    hm_b1_gib
)
@printf(
    "attribution anchor_after (T 24): %s after %s iterations, loop delta %.4f GiB, gap ratio %.2f\n",
    hm_anchor24["anchor_status"],
    hm_anchor24["anchor_iters"],
    hm_num(hm_anchor24["anchor_delta_gib"]),
    hm_ratio(hm_anchor24["note"])
)
@printf(
    "p35-head-d0.25-T24: rc %s, oom_source %s, MaxRSS %s kB = %.3f GiB\n",
    hm_kill25["rc"],
    hm_kill25["oom_source"],
    hm_kill25["peak_rss_kb"],
    hm_gib(hm_num(hm_kill25["peak_rss_kb"]))
)

# What the T = 24 peak is made of: the staged components of the earlier attribution run
# (stage-9 `reconciliation:` rows, `gib` column):

function hm_print_components(rows)
    for (name, what) in (
        ("comp_agr_builds", "122 AgrOpt builds"),
        ("comp_dso_build", "DSO build"),
        ("comp_first_iter_retained", "first iterate retained"),
        ("comp_iter_retained", "later iterates retained"),
    )
        r = hm_attr_row(rows, "9", "reconciliation:" * name)
        @printf("  %-26s %-25s %.3f GiB\n", name, what, hm_num(r["gib"]))
    end
end
hm_print_components(hm_attr24)

# No memory lever is claimed. The two largest components are the JuMP models themselves and their
# first solves, and the algorithm cannot run without them. Possible levers, such as splitting the DSO
# model by hour or pooling solver state, are future work, unmeasured here.

# ### The Scenario-path measured table at T = 10
#
# The largest point measured as feasible earlier, `ieee8500` at density 0.1 and T = 10, was run
# through the `Scenario` path: first on 2026-11-05, then re-run on 2026-11-06 with the
# corrected script. The row below is the latest final row of its key, which as of 2026-11-06 is
# the re-run (attempt 3 in the wrapper rows further down). It used the population selector
# `:default_10pct`, the ADMM strategy, and `scripts/ieee8500_scenario_point.jl` under the
# per-point wrapper. The script times four steps
# separately: materialize, build, solve (the ADMM loop) and certify. It reads `VmHWM` after each
# step. The run's status is its measured outcome: a refusal, a convergence error, a budget exit, a
# pre-flight refusal or a killed run is printed as such and is not retuned. The six numbers are
# size, build time, solve time, iterations, peak memory and the exactness verdict.
#
# **The times include compilation.** The point runs in one cold Julia process with no warm-up, so
# each phase time includes the first-call compilation of JuMP, MathOptInterface, Clarabel and the
# package's own kernels. Where the row records it, the compilation part of each phase and its share
# of the four phase times are printed beside them.

hm_label = "p46-scn-ieee8500-d10-T10"
# The intended row is selected by its full key (row kind, feeder, population, T, strategy, seed,
# run label). A key holds at most one final row and at most one transient row (`started` or
# `preflight_refused` or `crashed:<Type>`, which never displaces a final row). The final row is the
# measurement; a transient row beside it is a later attempt that did not finish, and it is printed
# as such.
hm_is_transient(status) =
    status in ("started", "preflight_refused") || startswith(status, "crashed:")
hm_meas_all = filter(
    r ->
        r["row_kind"] == "measured" &&
        r["feeder"] == "ieee8500" &&
        r["population"] == "default_10pct" &&
        r["T"] == "10" &&
        r["strategy"] == "ADMM" &&
        r["seed"] == "1" &&
        r["run_label"] == hm_label,
    hm_scn,
)
hm_meas_final = filter(r -> !hm_is_transient(r["status"]), hm_meas_all)
hm_meas = isempty(hm_meas_final) ? hm_meas_all : hm_meas_final
@assert length(hm_meas) <= 1
for r in setdiff(hm_meas_all, hm_meas)
    println("later attempt under the same key, not finished: status ", r["status"])
end

function hm_status_sentence(status)
    status == "ok" && return "converged and certified exact; prices are reported."
    status == "refused_certificate" &&
        return "converged, then refused by the SOCP exactness " *
               "certificate (CertificateError): prices are withheld. This refusal is the measured " *
               "outcome and is accepted as is; no tolerance, tau, epsilon or floor was changed."
    status == "convergence_error" &&
        return "maxiter reached without consensus; no certificate was attempted."
    status == "budget_exceeded" &&
        return "stopped at the wall-clock cap before consensus; certify was skipped."
    status == "preflight_refused" &&
        return "refused by the MemAvailable pre-flight before " *
               "anything was materialized: the host did not have the memory at launch."
    status == "memory_infeasible_inprocess" &&
        return "Julia raised OutOfMemoryError during the run: memory-infeasible in process, " *
               "a measured outcome; the row records the high-water mark at that moment."
    startswith(status, "crashed:") &&
        return "raised a non-solver exception (misuse or a bug, named in the status and the " *
               "note); this is not a measured outcome."
    status == "started" &&
        return "only the started row exists: the process died without raising (for example " *
               "killed by a signal) before writing its final row; the wrapper row below (rc, " *
               "oom_source) is the measured outcome."
    startswith(status, "error:") &&
        return "ended in a solver-layer error of the named type."
    return "unrecognized status."
end

# The `heap_size_hint` column holds the effective hint in bytes (`Base.JLOptions().heap_size_hint`,
# 0 = none). A non-numeric value is the legacy environment-variable text that the first version of
# the script recorded; see the correction note below.
function hm_heap_txt(s)
    b = tryparse(Int, s)
    b === nothing &&
        return "$(s) (legacy environment-variable value, never applied: none in effect)"
    b == 0 && return "none (no --heap-size-hint)"
    return @sprintf("%d bytes = %.3f GiB (--heap-size-hint)", b, b / 1024^3)
end

# Every phase time includes first-call compilation (one cold process, no warm-up). Rows written
# since 2026-11-06 carry the measured compilation time of each phase (`*_compile_s`); older rows do
# not, and that is printed instead of a share.
function hm_print_compile(r)
    phases = ("materialize", "build", "solve", "certify")
    cs = [hm_num(get(r, p * "_compile_s", "")) for p in phases]
    ts = [hm_num(r[p * "_s"]) for p in phases]
    if any(isnan, cs)
        println(
            "  compile: not recorded on this row (the compile columns were added on 2026-11-06); ",
            "the times above include first-call compilation",
        )
    else
        @printf(
            "  compile: materialize %.2f s, build %.2f s, solve %.2f s, certify %.2f s; %.1f %% of the four phase times\n",
            cs[1],
            cs[2],
            cs[3],
            cs[4],
            100 * sum(cs) / sum(ts)
        )
    end
    return nothing
end

function hm_print_measured(rows, label)
    if isempty(rows)
        println("no measured row for run label $label: the point was not launched")
        return nothing
    end
    r = only(rows)
    println(
        "run label ",
        label,
        ": feeder ",
        r["feeder"],
        ", population ",
        r["population"],
        ", T ",
        r["T"],
        ", strategy ",
        r["strategy"],
    )
    @printf(
        "  size:   %s buses, %s branches, %s load buses (feeder total, before sampling); %s aggregators (%s capacitor), %s AgrOpt models\n",
        r["n_buses"],
        r["n_branches"],
        r["n_load_buses"],
        r["n_aggregators"],
        r["n_cap_aggregators"],
        r["n_agr_models"]
    )
    @printf(
        "          DSO %s vars / %s cons; AgrOpt (summed) %s vars / %s cons\n",
        r["dso_vars"],
        r["dso_cons"],
        r["agr_vars"],
        r["agr_cons"]
    )
    @printf("  build:  %.2f s\n", hm_num(r["build_s"]))
    @printf("  solve:  %.2f s (ADMM loop)\n", hm_num(r["solve_s"]))
    @printf("  iters:  %s\n", r["iters"])
    @printf(
        "  peak:   VmHWM %s kB = %.3f GiB; process MaxRSS %.3f GiB\n",
        r["vmhwm_kb"],
        hm_num(r["vmhwm_gib"]),
        hm_num(r["maxrss_gib"])
    )
    @printf("  status: %s, gap ratio %.2f\n", r["status"], hm_num(r["gap_ratio"]))
    @printf(
        "  also:   materialize %.2f s, certify %.2f s\n",
        hm_num(r["materialize_s"]),
        hm_num(r["certify_s"])
    )
    hm_print_compile(r)
    println(
        "  provenance: seed ",
        r["seed"],
        " (population sub-seed ",
        r["sub_seed_population"],
        "), julia ",
        r["julia_version"],
        ", git ",
        r["git_head"],
        ", threads ",
        r["threads"],
        ", heap-size hint ",
        hm_heap_txt(r["heap_size_hint"]),
    )
    println("  outcome: ", hm_status_sentence(r["status"]))
    return nothing
end
hm_print_measured(hm_meas, hm_label)

# **Correction (2026-11-06): the heap-size hint.** The measured row first committed on 2026-11-05
# (attempt 2 below) recorded `heap_size_hint = 8G`. That value was copied from the environment
# variable `JULIA_HEAP_SIZE_HINT`, which julia does not read, and the wrapper did not pass the
# `--heap-size-hint` flag, so that run had **no** heap-size hint. The evidence is that run's
# `/usr/bin/time` command line, which has no such flag. It is in git history, not in the working
# tree, because the re-run below overwrote the label's `runs/` files:
# `git show f60857e:results/ieee8500_benchmark/runs/p46-scn-ieee8500-d10-T10.time`. The script now
# records the effective hint (`Base.JLOptions().heap_size_hint`, bytes, 0 = none), and the wrapper
# passes the flag only when `HEAP_SIZE_HINT` is set.
#
# **Re-run (2026-11-06).** The measured row above is attempt 3, launched on 2026-11-06 with the
# corrected script and `HEAP_SIZE_HINT=8G`, so julia ran with an applied `--heap-size-hint=8G`.
# The provenance line above prints the row's effective hint, and the current `runs/` command line
# is checked below. Its final row replaced attempt 2's under the same key. The `runs/` evidence
# files of this label now belong to attempt 3; the 2026-11-05 copies (attempt 2's) are at commit
# f60857e. The harness comparators in the path-divergence table below all ran without a hint.

function hm_time_heap_flag(label)
    tf = joinpath(pkgdir(TSODSO), "results", "ieee8500_benchmark", "runs", label * ".time")
    isfile(tf) || return "no runs/$(label).time file"
    cmd = filter(l -> occursin("Command being timed", l), readlines(tf))
    isempty(cmd) && return "no command line in runs/$(label).time"
    m = match(r"--heap-size-hint=(\S+)", only(cmd))
    return m === nothing ? "no --heap-size-hint flag" : "--heap-size-hint=" * m[1]
end
println("runs/", hm_label, ".time command line: ", hm_time_heap_flag(hm_label))

# **Wrapper rows and the pre-flight.** `point_resources.csv` is append-only. As of 2026-11-06 it
# holds three rows for this label, printed below as attempts 1 to 3 (any further row is a later
# launch of the same point):
# - **Attempts 1 and 2 (2026-11-05).** Both were launched with the user's explicit approval at
#   about 7.1 GiB MemAvailable, below the planned 8 GiB launch gate, which this host could not
#   reach even after other work was closed. On that day the script read MemAvailable *after* Julia
#   had started and loaded the package, so its reading was lower than the wrapper's pre-launch
#   reading by the process's own startup and package-load footprint. Attempt 1 asked for 7 GiB at
#   that point and was refused by the script's own gate, so nothing was materialized; its
#   `preflight_refused` row was replaced by attempt 2's final row under the same key, and only its
#   wrapper row remains. Attempt 2 lowered the in-script floor to 5.5 GiB, the post-load
#   equivalent of the approved level, and ran with no heap-size hint in effect to a certificate
#   refusal: 5 iterations and ratio 309.67, the same as attempt 3. Its row is no longer in the
#   table; it is at commit f60857e (`git show f60857e:results/ieee8500_benchmark/scenario_table.csv`).
# - **Attempt 3 (2026-11-06).** The re-run with the corrected script, which reads MemAvailable
#   on its first lines, before any package load. The host again had less than 8 GiB available,
#   and the user explicitly approved an in-script floor of 6.5 GiB for this launch, also below
#   the planned 8 GiB gate. Julia ran with `--heap-size-hint=8G`. Its final row is the measured
#   row above.
#
# The checks below tie these statements to the first three wrapper rows (the file is
# append-only, so those rows do not change). The wrapper row whose MaxRSS equals the measured
# row's VmHWM joins the measured row. The difference printed after it is the wrapper's pre-launch
# reading minus the row's in-script reading. For a reading taken before package load it is only
# the bare Julia runtime's startup, plus whatever else the host did in those seconds.
#
# **The 2026-11-05 package-load footprint no longer applies.** On 2026-11-05 the post-load reading
# fell about 0.92 GiB short of the wrapper's reading, so the default 8 GiB in-script gate implied
# about 8.9 GiB at launch on that day. Both figures were properties of the post-load pre-flight
# that attempts 1 and 2 used; with the pre-load pre-flight they no longer apply. They cannot be
# recomputed from the committed rows, because attempt 2's final row was replaced. That row's
# in-script reading (6,455,204 kB, against the wrapper's 7,247 MiB, a difference of 965,724 kB) is
# at commit f60857e.

hm_hist = hm_wrappers(hm_label)
@assert length(hm_hist) >= 3
@assert [startswith(w["started_at"], "2026-11-05") for w in hm_hist[1:3]] == [true, true, false]
@assert startswith(hm_hist[3]["started_at"], "2026-11-06")
@assert [match(r"--min-mem-avail-gib ([0-9.]+)", w["args"])[1] for w in hm_hist[1:3]] == ["7", "5.5", "6.5"]

function hm_print_wrappers(wrappers, rows)
    for (k, w) in enumerate(wrappers)
        m = match(r"--min-mem-avail-gib ([0-9.]+)", w["args"])
        @printf(
            "attempt %d (%s): in-script floor %s GiB; wrapper MemAvailable before %s MiB = %.3f GiB, swap used %s MiB; rc %s, MaxRSS %s kB = %.3f GiB, oom_source %s\n",
            k,
            w["started_at"],
            m === nothing ? "8 (default)" : m[1],
            w["mem_avail_before_mb"],
            hm_num(w["mem_avail_before_mb"]) / 1024,
            w["swap_used_before_mb"],
            w["rc"],
            w["peak_rss_kb"],
            hm_gib(hm_num(w["peak_rss_kb"])),
            w["oom_source"]
        )
    end
    isempty(rows) && return nothing
    r = only(rows)
    ## The wrapper row that joins the measured row is the LAST one whose MaxRSS equals the row's
    ## VmHWM. A later launch of the label that did not replace the measured row (for example a
    ## refused pre-flight, kept beside it) is printed above but does not join it. A row without a
    ## peak (`started`, `preflight_refused`) joins none, and neither does a row whose VmHWM differs
    ## from the wrapper's MaxRSS; then the last wrapper row is named as the launch outcome.
    vm = hm_num(r["vmhwm_kb"])
    joined =
        isnan(vm) ? empty(wrappers) : filter(w -> hm_num(w["peak_rss_kb"]) == vm, wrappers)
    if isempty(joined)
        if isempty(wrappers)
            println("no wrapper row for this label")
        else
            lw = last(wrappers)
            println(
                "no wrapper row joins this row by peak; the last wrapper row (attempt ",
                length(wrappers),
                ", rc ",
                lw["rc"],
                ", oom_source ",
                lw["oom_source"],
                ") is the launch outcome",
            )
        end
        return nothing
    end
    join_w = last(joined)
    k_join = findlast(w -> w === join_w, wrappers)
    footprint_kb =
        hm_num(join_w["mem_avail_before_mb"]) * 1024 - hm_num(r["mem_avail_before_kb"])
    pre_load = occursin("before any package load", r["note"])
    when = pre_load ? "before package load" : "after package load"
    what = pre_load ? "bare runtime startup" : "startup and package load"
    @printf(
        "the measured row joins attempt %d (started %s, MaxRSS = VmHWM = %s kB)\n",
        k_join,
        join_w["started_at"],
        join_w["peak_rss_kb"]
    )
    @printf(
        "in-script MemAvailable (measured row, read %s) %s kB = %.3f GiB; wrapper minus in-script reading (%s) %.0f kB = %.3f GiB\n",
        when,
        r["mem_avail_before_kb"],
        hm_gib(hm_num(r["mem_avail_before_kb"])),
        what,
        footprint_kb,
        hm_gib(footprint_kb)
    )
    @printf(
        "with a reading taken %s, the default 8 GiB in-script gate implies about %.2f GiB MemAvailable at launch\n",
        when,
        8 + hm_gib(footprint_kb)
    )
    return nothing
end
hm_print_wrappers(hm_wrappers(hm_label), hm_meas)

# ### Path-divergence label: not comparable 1:1 with the harness numbers
#
# These T = 10 numbers come from the `Scenario` path. The earlier T = 10 numbers come from the
# benchmark harness (`scripts/benchmark_ieee8500.jl`). The two points have the same feeder, the
# same sampling rule, the same density, the same ADMM knobs and the same exactness gate. They differ
# in the following ways:
#
# | item | harness path | `Scenario` path |
# |---|---|---|
# | population seed | literal harness seed | sub-seed of `Scenario.seed` (the `sub_seed_population` column), so different house draws |
# | bus sample | same rule, harness seed | same rule, sub-seed, so a different set of sampled buses |
# | wall-clock cap | 1200 s | the library path has none; this script passes the harness's 1200 s and records it |
# | certificate refusal | caught into a row | propagates in the library path; this script records it as a row |
# | timing scope | one figure for build, loop and certify | separate materialize, build, solve and certify figures |
# | compilation | included (cold process), not separated | included (cold process); the compile part is recorded per phase on rows since 2026-11-06 |
# | process baseline | `GC.gc()` before ADMM | no forced collection |
# | heap-size hint | none (the wrapper passed no `--heap-size-hint` flag) | the effective hint of the process, printed in the provenance line above: an applied `--heap-size-hint=8G` on the current row (attempt 3, 2026-11-06); none on the replaced 2026-11-05 row (attempt 2, see the correction note) |
# | seed hashing | version-stable generator | `Base.hash`, so it depends on the Julia version (recorded) |
#
# If the two are compared, the reading is "same size and structure, different seed draws". The
# harness comparators are printed below by row key. They are not a re-measurement of the row
# above, and no difference between the two paths is computed.

hm_h10 = only(
    filter(r -> r["run_label"] == "p35-head-d0.1-T10" && r["solver"] == "admm", hm_sweep),
)
hm_a10 = hm_attr_row(hm_attr_at("10"), "1", "anchor_after")
@printf(
    "harness density_sweep.csv p35-head-d0.1-T10: %s, ADMM time %.1f s, gap ratio %.2f\n",
    hm_h10["admm_status"],
    hm_num(hm_h10["admm_time_s"]),
    hm_ratio(hm_h10["admm_error_msg"])
)
@printf(
    "harness memory_attribution.csv (ieee8500, 0.1, 10, 1, anchor_after): %s after %s iterations\n",
    hm_a10["anchor_status"],
    hm_a10["anchor_iters"]
)
function hm_print_harness_peaks(labels)
    for lbl in labels
        w = only(hm_wrappers(lbl))
        @printf(
            "harness point_resources.csv %s: MaxRSS %s kB = %.3f GiB\n",
            lbl,
            w["peak_rss_kb"],
            hm_gib(hm_num(w["peak_rss_kb"]))
        )
    end
end
hm_print_harness_peaks(("p35-head-d0.1-T10", "p39-attr-d0.1-T10"))

# ### Supersession notes
#
# These notes correct statements in the older text above. The older text itself is not edited.
#
# - **The T = 24 loop attribution now exists.** The earlier attribution section says the T = 24
#   loop attribution was "NOT ESTABLISHED" because the full run was "earlyoom-killed". That is
#   superseded: `memory_attribution.csv` now carries a completed later run at T = 24, with an
#   `anchor_after` row, loop rows and stage-9 components (counted below). Its kill row is kept as
#   history.
# - **Build components.** The T = 24 build components quoted there (4.024 GiB for the AgrOpt builds
#   and 0.922 GiB for the DSO build) came from a build-only run. The completed run's components,
#   printed below, replace them.
# - **The "11.75 GiB" label.** A peak written as "11.75 GiB" elsewhere is a decimal division of the
#   raw kB value. The binary value is printed below.
# - **The bus count.** The "4,875 buses / 4,874 branches" in the older prose is stale. The fixture
#   as built measures the counts printed below.

function hm_print_supersessions(rows24, nogo, meas)
    loop_rows = count(r -> r["stage"] in ("3", "4", "5"), rows24)
    a = hm_attr_row(rows24, "1", "anchor_after")
    @printf(
        "T = 24 rows: anchor_after %s after %s iterations; %d loop/certify rows (stages 3-5)\n",
        a["anchor_status"],
        a["anchor_iters"],
        loop_rows
    )
    @printf(
        "T = 24 build components now: AgrOpt builds %.3f GiB, DSO build %.3f GiB\n",
        hm_num(hm_attr_row(rows24, "9", "reconciliation:comp_agr_builds")["gib"]),
        hm_num(hm_attr_row(rows24, "9", "reconciliation:comp_dso_build")["gib"])
    )
    kb = hm_num(nogo["vmhwm_kb"])
    @printf(
        "peak %.0f kB: / 10^6 = %.2f (decimal label), / 1024^2 = %.3f GiB (binary)\n",
        kb,
        kb / 1e6,
        hm_gib(kb)
    )
    if isempty(meas)
        f = build_feeder(:ieee8500)
        @printf(
            "ieee8500 as built: %d buses, %d branches\n",
            length(f.buses),
            length(f.branches)
        )
    else
        r = only(meas)
        println(
            "ieee8500 as built (measured row): ",
            r["n_buses"],
            " buses, ",
            r["n_branches"],
            " branches",
        )
    end
    return nothing
end
hm_print_supersessions(hm_attr24, hm_nogo, hm_meas)

# ### Reproducing this
#
# The measured point needs a quiet host. Run one point at a time, detached, with no other Julia
# process running. The script's pre-flight refuses below its floor (default 8 GiB MemAvailable)
# and writes a `preflight_refused` row; it then exits 0. Since 2026-11-06 that reading is taken on
# the script's first lines, before any package load, so the floor is judged against nearly the
# launch-time MemAvailable (the difference is printed above). The 2026-11-05 launches read it after
# package load (see the footprint note above). `HEAP_SIZE_HINT`
# makes the wrapper pass julia's `--heap-size-hint=` flag (julia reads no environment variable
# for it); drop it to run without a hint.
# `--record-nogo` reads only the committed CSVs and the measurement host's `runs/` evidence, and
# rewrites the decision row.
#
# **Use a fresh label for every launch.** The committed measurement belongs to the label
# `p46-scn-ieee8500-d10-T10`. A reproduction gets its own dated label, so it writes its own row,
# its own wrapper row and its own `runs/` files, and the committed measurement and its evidence
# stay as they are. Since 2026-11-06 a reused label is refused twice:
# - the wrapper refuses a label that already has `runs/` evidence or a `point_resources.csv` row,
#   unless `REPLACE_LABEL=1`;
# - the script refuses a run whose key already holds a final row, unless `--replace`.
#
# ```
# LABEL=p46-scn-ieee8500-d10-T10-$(date +%Y%m%d-%H%M)
# HEAP_SIZE_HINT=8G SCRIPT=scripts/ieee8500_scenario_point.jl nohup setsid \
#     scripts/run_ieee8500_point.sh "$LABEL" -- \
#     --feeder ieee8500 --T 10 --seed 1 --run-label "$LABEL"
# julia --project=. scripts/ieee8500_scenario_point.jl --record-nogo
# ```
#
# Both commands upsert keyed rows into `results/ieee8500_benchmark/scenario_table.csv`. Since
# 2026-11-06 the key is row kind, feeder, population, T, strategy, seed and run label (before, seed
# and run label were not part of it, so a later `started` or `preflight_refused` row could replace
# a completed measurement). A `started` or `preflight_refused` row never displaces a final row of
# the same key; it sits beside it until that attempt's final row replaces both (a launch on a key
# that already holds a final row needs `--replace`, see above). A killed run leaves
# its `started` row as the trace. The wrapper appends one row per launch to
# `point_resources.csv` and keeps its evidence files under `results/ieee8500_benchmark/runs/`. The
# draws depend on the Julia version through `Base.hash`. The measured row was produced on the Julia
# version recorded in it.

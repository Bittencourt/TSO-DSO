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
# not recorded, see section 3). **What consumes the memory inside `solve_admm` is not established by the
# measurements below.** Two kinds of figure were measured, with different metrics:
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
# growth. The remainder (about 3.4 GiB) is **unattributed**: it was not split between AgrOpt construction,
# their solves, per-iteration state and the final consolidation, and no single dominant consumer is
# established by this profile. That the remainder is mostly per-hour DSO solver state retained across the
# ADMM loop is a **hypothesis**, not a measurement. The only scaling statement the data support is that the
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

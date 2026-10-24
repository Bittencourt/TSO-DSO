# scripts/profile_ieee8500_memory_attribution.jl
#
# SCALE-06 (Phase 39): staged RSS memory ATTRIBUTION of one IEEE-8500 point — splits the
# previously unattributed `solve_admm` memory growth (STATE.md deferred item, Phase-35 update:
# ~3.4 GiB at d = 0.1, T = 10) into named components and reconciles them against a whole-call
# production-path anchor. One stage-set per process (HWM resets per process), e.g.:
#
#   julia --project=. scripts/profile_ieee8500_memory_attribution.jl --fixture ieee8500 --density 0.1 --t-horizon 10
#   julia --project=. scripts/profile_ieee8500_memory_attribution.jl --fixture ieee8500 --density 0.1 --t-horizon 24
#
# Prints one TSV line per stage and upserts rows into
# results/ieee8500_benchmark/memory_attribution.csv keyed by (fixture, density, T, stage, name)
# with `cols = :union` — re-runs replace their own rows and never drop others. The CSV is
# re-upserted after EVERY stage report, so a kill mid-run (the T = 24 point sits near the
# earlyoom floor) leaves the evidence rows it had already captured — a kill is a MEASURED
# OUTCOME, not a missing run (honesty policy). Rows from a run with a different
# --max-bounded-iters leave differently-named `iter_*` rows behind; re-run with the same cap to
# replace them.
#
# MEASUREMENT DESIGN (Pitfall 8 — isolate each candidate mechanism INDEPENDENTLY, never stage
# around the assumed linear-in-T story):
#
#   stage 1  data load + population (the Phase-35 baseline stages), then the RECONCILIATION
#            ANCHOR: one full production `solve_admm(...)` call (arguments exactly as
#            benchmark_ieee8500.jl's `run_admm_point`, the Phase-35 head-row measurement)
#            wrapped in a `Sys.maxrss()` before/after delta. The anchor ALWAYS runs before any
#            staged build — see the docstring's monotonic-HWM caveat for why. A
#            `CertificateError` refusal is an EXPECTED, VALID measured outcome at both Phase-35
#            boundary points: it is recorded in evidence rows (status, iterations, message),
#            never dropped.
#   stage 2  builds, split: `build_dso_opt` ALONE, then the AgrOpt build loop ALONE (one
#            `build_agr_opt` per aggregator) — separates the DSO build from the per-aggregator
#            builds (state assembly mirrors `_admm_build` verbatim with report calls inserted).
#   stage 3  per-iteration RETAINED state: the internal iterate phase (`_admm_iterate!`) for a
#            bounded number of REAL iterations, `GC.gc()` before/after (+ `malloc_trim`) with
#            instantaneous VmRSS snapshots — retained growth, not churn.
#   stage 4  per-hour DSO solver state — the Phase-35 HYPOTHESIS, tested ISOLATED: the retained
#            snapshot after iterate 1 (which contains the DSO model's first `optimize!` and the
#            first AGR solves) vs after the remaining bounded iterations. If this delta is NOT
#            the dominant growth, the data — not the hypothesis — names the mechanism.
#   stage 5  consolidation/certify (or the recorded refusal point), then final after_gc /
#            after_malloc_trim.
#   stage 9  reconciliation rows: per-component magnitudes with stated tolerances, the
#            component sum, and the explicit residual (observed anchor delta − Σ components).
#            A documented honest residual is an acceptable outcome.
#
# The bounded iteration block is split into TWO `_admm_iterate!` calls (1 iteration, then the
# remaining N-1) so stage 4 gets its isolated first-iterate snapshot. `_admm_iterate!`'s
# residual ledger enforces a fail-loud sequential-`k` guard (`record!`: k must equal iters+1),
# so the harness resets `st.residuals.iters = 0` before the continuation call — a
# BOOKKEEPING-ONLY adjustment: the ledger's k-index restarts, every SOLVE statement is the
# exact production sequence and order, and the ledger's memory is negligible. The staged
# ledger's final `iters` therefore undercounts the logical iteration count by one; the anchor's
# exception-carried count is the production number of record. The bounded iteration count N is
# the ANCHOR's own observed production count (its `CertificateError`/`ConvergenceError`
# `.iterations`, or `r.iters`) capped by --max-bounded-iters — the flag's value when the anchor
# carried none.
#
# All memory figures are binary GiB (1 GiB = 2^30 bytes); `VmRSS_kB`/`VmHWM_kB` are the raw
# /proc/self/status KiB counters, kept beside the GiB conversions, with per-row deltas
# (report-both convention). Read-only with respect to src/.

using DrWatson
@quickactivate "TSODSO"
using TSODSO, JuMP, CSV, DataFrames, StableRNGs

# Safe to include: the harness only runs `main` when it is the program entry point.
include(joinpath(@__DIR__, "benchmark_ieee8500.jl"))

function proc_status_kb(key::String)
    for line in eachline("/proc/self/status")
        startswith(line, key * ":") && return parse(Int, split(line)[2])
    end
    return -1
end

const ROWS = NamedTuple[]
const LAST_RSS = Ref{Int}(-1)
DENSITY = 0.1
T_H = 10
FIXTURE = "ieee8500-mv"

"""
    attribution_main(args) -> nothing

Staged RSS memory attribution of ONE point (stage map in the file header). `VmRSS` is the
instantaneous resident set; `VmHWM` is the whole-process high-water. `Sys.maxrss()` — used ONLY
for the anchor's before/after delta — is a MONOTONIC, WHOLE-PROCESS high-water mark, not a
per-call current usage: the reported delta is the INCREMENTAL growth in the process's peak RSS
attributable to (at most) this call; once the process has already peaked on an earlier, larger
allocation, a later smaller point's delta legitimately reads ~0 (the caveat copied from
`run_admm_point`'s docstring in benchmark_ieee8500.jl). That is why the anchor always runs
FIRST, before any staged build can inflate the high-water mark.
"""
function attribution_main(args)
    global DENSITY = parse(Float64, parse_kv_flag(args, "--density", "0.1"))
    global T_H = parse(Int, parse_kv_flag(args, "--t-horizon", "10"))
    max_stage = parse(Int, parse_kv_flag(args, "--stage", "99"))
    max_bounded = parse(Int, parse_kv_flag(args, "--max-bounded-iters", "24"))
    time_limit = parse(Float64, parse_kv_flag(args, "--time-limit", "1200.0"))
    fixture_str = parse_kv_flag(args, "--fixture", "ieee8500-mv")
    haskey(FIXTURE_MAP, fixture_str) ||
        throw(ArgumentError("unknown --fixture $fixture_str"))
    global FIXTURE = fixture_str
    T_H < T_HORIZON_FLOOR &&
        throw(ArgumentError("--t-horizon below floor $T_HORIZON_FLOOR"))
    max_bounded >= 1 ||
        throw(ArgumentError("--max-bounded-iters must be ≥ 1 (got $max_bounded)"))
    fixture_sym = FIXTURE_MAP[fixture_str]

    println("stage\tname\tVmRSS_kB\tVmHWM_kB\tgc_live_MB\trss_delta_gib")

    # ---- stage 1: data load + profile generation (the Phase-35 baseline stages) ---------------
    report(1, "after_using")
    feeder = build_feeder(fixture_sym)
    profiles = generate_profiles(; seed = _SWEEP_SEED, T = T_H)
    λ0 = build_price(:mem, T_H, nothing)
    rng = StableRNGs.LehmerRNG(_SWEEP_SEED)
    aggs = density_filtered_population(
        feeder,
        fixture_sym,
        profiles,
        _SWEEP_SEED,
        DENSITY,
        rng,
    )
    report(1, "feeder_population")

    # ---- stage 1 (cont.): the production-path reconciliation anchor ---------------------------
    # Arguments EXACTLY as benchmark_ieee8500.jl's `run_admm_point` (the Phase-35 head rows):
    # ρ0 = 100.0 (pv_boom_case_study.jl's validated initial penalty), allow_export = true,
    # `time_limit_s` wall-clock exit, `atol_exact = nothing` (the library hybrid per-branch
    # floor). Its maxrss delta is the observed total the staged components must reconcile to.
    anchor = nothing
    if max_stage >= 3
        report(1, "anchor_before"; note = "full solve_admm anchor: maxrss watermark before")
        anchor = run_anchor(feeder, aggs, λ0, T_H, time_limit)
        report_anchor_after(anchor)
        GC.gc()
        ccall(:malloc_trim, Cint, (Cint,), 0)
        report(
            1,
            "anchor_after_gc_trim";
            note = "post-anchor GC.gc + malloc_trim (frees the anchor's models before the staged builds)",
        )
    end

    # ---- stage 2: builds, DSO vs AgrOpt split -------------------------------------------------
    # State assembly mirrors `_admm_build` verbatim (build_dso_opt → AgrOpt loop → AdmmState)
    # with report calls inserted; no JuMP model is constructed after this, same contract.
    GC.gc()
    report(2, "pre_staged_gc"; note = "clean GC'd baseline for the build deltas")
    ρf = 100.0
    ρ_qf = 100.0                      # solve_admm's default ρ_q = ρ
    mode = TSODSO.normalize_reactive_mode(TSODSO._default_reactive_consensus(aggs))
    rmode = TSODSO._react_mode(mode)
    pf = ConvexBranchFlow()

    dso = TSODSO.build_dso_opt(
        feeder,
        aggs,
        T_H;
        ρ = ρf,
        λ₀ = λ0,
        reactive_consensus = mode,
        ρ_q = ρ_qf,
        pf = pf,
    )
    report(2, "build_dso_opt"; note = "DSO build ALONE")
    load_nodes = dso.load_nodes
    length(aggs) == length(load_nodes) || throw(
        ArgumentError(
            "1:1 node<->aggregator guard failed ($(length(aggs)) aggs vs " *
            "$(length(load_nodes)) load nodes)",
        ),
    )
    agr_by_bus = Dict{Int, TSODSO.AgrOpt}()
    for agg in aggs
        agr_by_bus[agg.bus] =
            TSODSO.build_agr_opt(agg, T_H; ρ = ρf, reactive_mode = mode, ρ_q = ρ_qf)
    end
    report(
        2,
        "after_agr_opts";
        note = "AgrOpt build loop ALONE ($(length(aggs)) models)",
    )

    # ---- stages 3-5: bounded REAL iterations, isolated first-iterate snapshot, certify --------
    if max_stage >= 3
        n_bounded =
            anchor !== nothing && anchor.iters > 0 ? min(anchor.iters, max_bounded) :
            max_bounded

        GC.gc()
        report(
            3,
            "iter_before_gc";
            note = "clean pre-loop baseline (state built, nothing solved)",
        )

        # (mirrors _admm_build's state assembly)
        residuals = TSODSO.AdmmResiduals(length(feeder.buses), T_H)
        λ = Dict{Int, Vector{Float64}}(j => Float64[-λ0[t] for t in 1:T_H] for j in load_nodes)
        c = Dict{Int, Vector{Float64}}(j => zeros(Float64, T_H) for j in load_nodes)
        a = Dict{Int, Vector{Float64}}(j => zeros(Float64, T_H) for j in load_nodes)
        pag_dso_prev = Dict{Int, Vector{Float64}}(j => zeros(Float64, T_H) for j in load_nodes)
        util = Dict{Int, Float64}(j => 0.0 for j in load_nodes)
        p_import = zeros(Float64, T_H)
        react = TSODSO._react_state(rmode, load_nodes, T_H, ρ_qf)
        st = TSODSO.AdmmState(
            dso,
            agr_by_bus,
            load_nodes,
            T_H,
            residuals,
            λ,
            c,
            a,
            pag_dso_prev,
            util,
            p_import,
            ρf,
            false,               # ρ_frozen
            nothing,             # exact_maxgap
            false,               # converged_flag
            false,               # budget_exceeded_flag
            time_ns(),           # t0_wall_ns
            react,
        )

        # Iteration 1 — contains the DSO model's first `optimize!` and the first AGR solves.
        # solve_admm's own defaults: ε_abs = 1e-4, ε_rel = 1e-3, τ = 2.0, μ = 10.0,
        # ρ_min = 1e-2, ρ_max = 1e4; serial executor (parallel = false).
        TSODSO._admm_iterate!(st, rmode, 1, 1e-4, 1e-3, 2.0, 10.0, 1e-2, 1e4, nothing, false)
        report(
            3,
            "iter_1";
            note = "post-iterate-1 instantaneous VmRSS (churn included, no GC yet)",
        )
        GC.gc()
        report(
            4,
            "after_first_optimize_gc";
            note = "RETAINED after iterate 1: DSO first optimize! + first AGR solves + consensus state (the stage-4 snapshot the Phase-35 first-optimize component maps to)",
        )

        # Continuation: iterates 2..N. The ledger's sequential-k guard is reset first —
        # bookkeeping only (see file header); every solve statement is the production sequence.
        st.residuals.iters = 0
        n_rest = n_bounded - 1
        if n_rest >= 1 && !st.converged_flag && !st.budget_exceeded_flag
            TSODSO._admm_iterate!(
                st,
                rmode,
                n_rest,
                1e-4,
                1e-3,
                2.0,
                10.0,
                1e-2,
                1e4,
                time_limit,
                false,
            )
            report(
                3,
                "iter_$(n_bounded)";
                note = "post-iterate-$(n_bounded) instantaneous VmRSS (converged=$(st.converged_flag) budget_exceeded=$(st.budget_exceeded_flag))",
            )
        end
        GC.gc()
        report(
            3,
            "iter_after_gc";
            note = "RETAINED after the bounded iteration block — per-hour DSO solver state candidate = this minus after_first_optimize_gc",
        )
        ccall(:malloc_trim, Cint, (Cint,), 0)
        report(3, "iter_after_malloc_trim")

        # ---- stage 5: consolidation/certify (or the recorded refusal/skip) --------------------
        if st.converged_flag && !st.budget_exceeded_flag
            cert_status = ""
            cert_msg = ""
            try
                # solve_admm's own call shape (atol_exact = nothing → hybrid floor, rtol 1e-4,
                # serial); the expected CertificateError refusal is recorded, never dropped.
                TSODSO._admm_certify(st, rmode, mode, aggs, λ0, nothing, 1e-4, false)
                cert_status = "certified"
            catch err
                err2 = err
                # mirror solve_admm's re-wrap so the evidence carries the converged count
                if err isa TSODSO.CertificateError && err.iterations === nothing
                    err2 = TSODSO.CertificateError(
                        err.msg;
                        kind = err.kind,
                        iterations = st.residuals.iters,
                    )
                end
                cert_status = "ERROR:" * string(nameof(typeof(err2)))
                cert_msg = first(replace(sprint(showerror, err2), '\n' => " | "), 200)
            end
            report(
                5,
                "certify_result";
                note = "status=$(cert_status) iterations=$(st.residuals.iters) msg=$(cert_msg)",
            )
            GC.gc()
            report(5, "after_certify_gc")
        else
            report(
                5,
                "certify_skipped";
                note = "loop exited converged=$(st.converged_flag) budget_exceeded=$(st.budget_exceeded_flag) — certify assumes a converged iterate (solve_admm's own policy)",
            )
        end
        GC.gc()
        report(5, "after_gc")
        ccall(:malloc_trim, Cint, (Cint,), 0)
        report(5, "after_malloc_trim")

        # ---- stage 9: reconciliation + explicit residual --------------------------------------
        if anchor !== nothing
            reconcile!(anchor; certify_ran = has_row("after_certify_gc"))
        end
    end

    write_rows()
    return nothing
end

"""
    run_anchor(feeder, aggs, λ0, T, time_limit) -> NamedTuple

The production-path reconciliation anchor: one full `solve_admm(...)` call (arguments exactly
as `run_admm_point` in benchmark_ieee8500.jl — the Phase-35 head-row measurement), wrapped in a
`Sys.maxrss()` before/after delta. ANY outcome is evidence: a `CertificateError` refusal (the
expected outcome at the Phase-35 boundary points), a `ConvergenceError`, a budget exit, or a
clean certified return — status, iterations (from the exception when it carries them, -1
sentinel otherwise), wall time and the maxrss delta are all returned. Nothing from the result
is retained, so the models are collectable afterwards.
"""
function run_anchor(feeder, aggs, λ0, T, time_limit)
    t0 = time_ns()
    rss_before = Sys.maxrss()
    status = ""
    iters = -1
    msg = ""
    result = try
        r = solve_admm(
            feeder,
            ConvexBranchFlow(),
            aggs;
            T = T,
            λ₀ = λ0,
            ρ = 100.0,
            allow_export = true,
            time_limit_s = time_limit,
            atol_exact = nothing,
        )
        status = string(r.status)
        iters = Int(r.iters)
        r
    catch err
        msg = first(replace(sprint(showerror, err), '\n' => " | "), 200)
        status = "ERROR:" * string(nameof(typeof(err)))
        iters =
            (err isa TSODSO.ConvergenceError || err isa TSODSO.CertificateError) &&
            err.iterations !== nothing ? Int(err.iterations) : -1
        nothing
    end
    time_s = (time_ns() - t0) / 1.0e9
    rss_after = Sys.maxrss()
    delta_gib = (rss_after - rss_before) / 2^30
    peak_gib = rss_after / 2^30
    println(
        "anchor\t",
        status,
        "\titers=",
        iters,
        "\tdelta=",
        round(delta_gib; digits = 3),
        " GiB\tpeak=",
        round(peak_gib; digits = 3),
        " GiB\ttime=",
        round(time_s; digits = 1),
        " s",
    )
    isempty(msg) || println("anchor_msg\t", msg)
    flush(stdout)
    return (; status, iters, msg, delta_gib, peak_gib, time_s)
end

# Stated measurement tolerance per attributed component: max(0.05 GiB absolute floor, 10% of
# the component) — allocator arena/segment retention and cross-context GC-state differences
# (the staged snapshots run after the anchor + GC in the same process) dominate the noise for
# this class of staged VmRSS snapshot. The residual's tolerance is the quadrature sum.
comp_tol(c) = max(0.05, 0.10 * abs(c))

function report_anchor_after(anchor)
    rss, hwm = proc_status_kb("VmRSS"), proc_status_kb("VmHWM")
    live = Base.gc_live_bytes() / 2^20
    delta = LAST_RSS[] < 0 ? 0.0 : (rss - LAST_RSS[]) / 2^20   # kB → GiB (1 GiB = 2^20 kB)
    LAST_RSS[] = rss
    println(
        1,
        "\tanchor_after\t",
        rss,
        "\t",
        hwm,
        "\t",
        round(live; digits = 1),
        "\t",
        round(delta; digits = 3),
    )
    flush(stdout)
    push!(
        ROWS,
        (;
            fixture = FIXTURE,
            density = DENSITY,
            T = T_H,
            stage = 1,
            name = "anchor_after",
            VmRSS_kB = rss,
            VmHWM_kB = hwm,
            gc_live_MB = live,
            rss_delta_gib = delta,
            gib = anchor.delta_gib,
            tol_gib = missing,
            note = "production solve_admm anchor (run_admm_point arguments): status=$(anchor.status) iterations=$(anchor.iters) peak=$(round(anchor.peak_gib; digits = 3)) GiB msg=$(anchor.msg)",
            anchor_status = anchor.status,
            anchor_iters = anchor.iters,
            anchor_delta_gib = anchor.delta_gib,
            anchor_time_s = anchor.time_s,
        ),
    )
    write_rows()
    return nothing
end

function report(stage::Int, name::String; note::String = "")
    rss, hwm = proc_status_kb("VmRSS"), proc_status_kb("VmHWM")
    live = Base.gc_live_bytes() / 2^20
    delta = LAST_RSS[] < 0 ? 0.0 : (rss - LAST_RSS[]) / 2^20   # kB → GiB (1 GiB = 2^20 kB)
    LAST_RSS[] = rss
    println(
        stage,
        "\t",
        name,
        "\t",
        rss,
        "\t",
        hwm,
        "\t",
        round(live; digits = 1),
        "\t",
        round(delta; digits = 3),
    )
    flush(stdout)
    push!(
        ROWS,
        (;
            fixture = FIXTURE,
            density = DENSITY,
            T = T_H,
            stage = stage,
            name = name,
            VmRSS_kB = rss,
            VmHWM_kB = hwm,
            gc_live_MB = live,
            rss_delta_gib = delta,
            gib = missing,
            tol_gib = missing,
            note = note,
            anchor_status = "",
            anchor_iters = -1,
            anchor_delta_gib = missing,
            anchor_time_s = missing,
        ),
    )
    write_rows()
    return nothing
end

function reconciliation_row(name::String, gib, tol, note::String)
    push!(
        ROWS,
        (;
            fixture = FIXTURE,
            density = DENSITY,
            T = T_H,
            stage = 9,
            name = name,
            VmRSS_kB = missing,
            VmHWM_kB = missing,
            gc_live_MB = missing,
            rss_delta_gib = missing,
            gib = gib,
            tol_gib = tol,
            note = note,
            anchor_status = "",
            anchor_iters = -1,
            anchor_delta_gib = missing,
            anchor_time_s = missing,
        ),
    )
    return nothing
end

has_row(name::String) = findlast(r -> r.name == name, ROWS) !== nothing

function rss_gib_of(name::String)
    idx = findlast(r -> r.name == name, ROWS)
    idx === nothing && error("attribution: missing snapshot row \"$name\"")
    return ROWS[idx].VmRSS_kB / 2^20   # kB → GiB (1 GiB = 2^20 kB)
end

"""
    reconcile!(anchor; certify_ran) -> nothing

Stage-9 rows + console table: per-component magnitudes (each with its stated tolerance),
their sum, and the explicit residual `observed anchor delta − Σ components`. Components are
GC-RETAINED staged deltas; the anchor's maxrss delta additionally includes CHURN (transient
solve allocations the staged GC'd snapshots exclude), allocator retention, and cross-context
GC-state differences — all of that lands in the residual, which is reported honestly, never
forced to fit a mechanism (honesty policy).
"""
function reconcile!(anchor; certify_ran::Bool)
    c_dso_build = rss_gib_of("build_dso_opt") - rss_gib_of("pre_staged_gc")
    c_agr_builds = rss_gib_of("after_agr_opts") - rss_gib_of("build_dso_opt")
    c_first_iter = rss_gib_of("after_first_optimize_gc") - rss_gib_of("iter_before_gc")
    c_iter = rss_gib_of("iter_after_gc") - rss_gib_of("after_first_optimize_gc")
    c_certify =
        certify_ran ? rss_gib_of("after_certify_gc") - rss_gib_of("iter_after_gc") : 0.0
    cert_note =
        certify_ran ?
        "consolidation/certify retained (after_certify_gc − iter_after_gc)" :
        "certify did not run (not converged / budget exit) — 0.0 by absence, not by assumption"

    comps = [
        ("comp_dso_build", c_dso_build, "build_dso_opt alone (stage 2)"),
        ("comp_agr_builds", c_agr_builds, "AgrOpt build loop alone (stage 2)"),
        (
            "comp_first_iter_retained",
            c_first_iter,
            "iterate 1 retained: DSO first optimize! + first AGR solves + consensus state (stages 3-4)",
        ),
        (
            "comp_iter_retained",
            c_iter,
            "iterates 2..N retained — the per-hour DSO solver state candidate (stage 4 isolated test)",
        ),
        ("comp_certify", c_certify, cert_note),
    ]

    total = sum(c for (_, c, _) in comps)
    tol_total = sqrt(sum(comp_tol(c)^2 for (_, c, _) in comps))
    residual = anchor.delta_gib - total
    tol_residual = tol_total  # observed delta is a single maxrss reading; the component
    #                           tolerances dominate the residual's uncertainty

    println("\n== RECONCILIATION (fixture=$(FIXTURE) density=$(DENSITY) T=$(T_H)) ==")
    println(
        "anchor observed solve_admm maxrss delta: ",
        round(anchor.delta_gib; digits = 3),
        " GiB (status=$(anchor.status) iterations=$(anchor.iters))",
    )
    for (nm, c, note) in comps
        println(
            "  ",
            rpad(nm, 26),
            "+",
            rpad(round(c; digits = 3), 8),
            "± ",
            round(comp_tol(c); digits = 3),
            " GiB   ",
            note,
        )
    end
    println("  ", rpad("Σ components", 26), "+", rpad(round(total; digits = 3), 8), "± ", round(tol_total; digits = 3), " GiB")
    println(
        "  ",
        rpad("residual", 26),
        rpad(round(residual; digits = 3), 9),
        "± ",
        round(tol_residual; digits = 3),
        " GiB   observed − Σ (honest residual: includes churn the GC'd staged snapshots exclude)",
    )
    flush(stdout)

    for (nm, c, note) in comps
        reconciliation_row("reconciliation:" * nm, c, comp_tol(c), note)
    end
    reconciliation_row(
        "reconciliation:components_total",
        total,
        tol_total,
        "Σ of the named components",
    )
    reconciliation_row(
        "residual",
        residual,
        tol_residual,
        "observed anchor maxrss delta ($(round(anchor.delta_gib; digits = 3)) GiB, status=$(anchor.status)) − Σ components; includes solve churn, allocator retention and cross-context GC-state differences — documented honest residual, not forced to fit a mechanism",
    )
    write_rows()
    return nothing
end

function write_rows()
    path = joinpath(out_dir(), "memory_attribution.csv")
    mkpath(out_dir())
    df = DataFrame(ROWS)
    if isfile(path)
        old = CSV.read(path, DataFrame)
        # pre-fixture-column rows cannot exist (new file), but keep the guard for safety.
        hasproperty(old, :fixture) || (old.fixture = fill("ieee8500-mv", nrow(old)))
        k(r) = (string(r.fixture), r.density, r.T, r.stage, r.name)
        nk = Set(k(r) for r in eachrow(df))
        df = vcat(filter(r -> !(k(r) in nk), old), df; cols = :union)
    end
    select!(df, :fixture, Not(:fixture))
    CSV.write(path, df)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    attribution_main(ARGS)
end

# scripts/ieee8500_scenario_point.jl
#
# One IEEE-8500 measurement point run through `Scenario` (the library path), with the ADMM
# phases timed separately, a host-memory pre-flight gate and honest status rows; plus a
# `--record-nogo` mode that derives the T = 24 go/no-go record from the committed CSVs.
#
# Usage:
#
#   # measured run (launch through the per-point wrapper, detached and alone on the host):
#   JULIA_HEAP_SIZE_HINT=8G SCRIPT=scripts/ieee8500_scenario_point.jl scripts/run_ieee8500_point.sh <label> -- --feeder ieee8500 --T 10 --run-label <label>
#
#   # NO-GO record from results/ieee8500_benchmark/memory_attribution.csv and point_resources.csv
#   # (reads the committed CSVs only, solves nothing):
#   julia --project=. scripts/ieee8500_scenario_point.jl --record-nogo
#
#   julia --project=. scripts/ieee8500_scenario_point.jl --help
#
# Both modes upsert rows into `<results-dir>/scenario_table.csv` (default
# results/ieee8500_benchmark/, or env TSODSO_IEEE8500_RESULTS_DIR, or --results-dir), keyed by
# (row_kind, feeder, population, T, strategy): a re-run replaces its own row and keeps every
# other row; `cols = :union` lets the schema grow. The free-text `note` column is always LAST.
#
# Measured mode. The `Scenario` is materialized exactly as `TSODSO.run(::ADMM, s)` does
# (`_materialize`, `build_powerflow`), then the `solve_admm` plumbing is composed phase by phase
# (`_admm_build`, `_admm_iterate!`, `_admm_certify`, same arguments and order) so each phase gets
# its own `@elapsed`. The IEEE-8500 feeders use the `:default_10pct` population (density 0.1 of
# the load buses plus the capacitor aggregators); the other feeders use `:default` (IEEE-13 is the
# cheap smoke/parity path). No `GC.gc()` is run between phases, so the recorded peak stays
# comparable with an ordinary `run_scenario` process. The only knob not taken from the `ADMM`
# strategy is the wall-clock cap `--time-limit` (default 1200 s, the benchmark harness default),
# recorded in the row's note; the library path runs without a cap.
#
# Sequence: validate flags -> pre-flight (MemAvailable from /proc/meminfo, before any
# materialization) -> upsert a `started` row -> run the phases -> upsert the final row (same key,
# so it replaces `started`). A process killed mid-run therefore leaves its `started` row, and the
# wrapper's point_resources.csv row (joined by run_label) carries rc and oom_source.
#
# Status vocabulary (one token in the `status` column):
#   ok                   converged and certified
#   refused_certificate  converged, but a certificate (for example SOC exactness) refused the point
#   convergence_error    maxiter reached without consensus (no certificate attempted)
#   budget_exceeded      wall-clock cap reached (certify skipped, no welfare, as solve_admm does)
#   error:<TypeName>     any other TSODSOError (for example error:SolveFailedError)
#   preflight_refused    MemAvailable below --min-mem-avail-gib; nothing was materialized
#   memory_infeasible    the recorded T = 24 NO-GO row (--record-nogo)
#   started              written before the heavy work; still present means the process died
# Any other exception (misuse, a bug) propagates: it is not an outcome to record.
#
# Honesty policy: refusals, nulls and infeasible outcomes are rows, stated plainly. Nothing is
# retuned to make a point fit or pass: no tolerance, tau, epsilon or exactness floor is exposed,
# and a pre-flight refusal or an earlyoom kill is a measured outcome, never retried.
#
# Units: every memory figure is binary GiB (1 GiB = 2^30 bytes = 1,048,576 kB); the raw kB
# counters (/proc/self/status VmHWM, /proc/meminfo MemAvailable, /usr/bin/time MaxRSS) are kept
# beside the GiB conversions.

using DrWatson
@quickactivate "TSODSO"
using TSODSO, JuMP, CSV, DataFrames, StableRNGs

# ---------------------------------------------------------------------------- CLI helpers
# Copied from scripts/benchmark_ieee8500.jl so this script stays standalone (no harness include).

function parse_kv_flag(args, flag::String, default)
    idx = findfirst(==(flag), args)
    idx === nothing && return default
    idx == length(args) && throw(ArgumentError("$flag requires a value (none given)"))
    return args[idx + 1]
end

has_flag(args, flag::String) = flag in args

const VALUE_FLAGS = (
    "--feeder",
    "--T",
    "--seed",
    "--run-label",
    "--time-limit",
    "--min-mem-avail-gib",
    "--results-dir",
)
const BOOL_FLAGS = ("--record-nogo", "--help")

const USAGE = """
Usage: julia --project=. scripts/ieee8500_scenario_point.jl [mode] [flags]

Modes:
  (default)        measured run of one Scenario point (phase-timed ADMM, status rows)
  --record-nogo    derive the T = 24 NO-GO row from memory_attribution.csv and
                   point_resources.csv in the results directory (solves nothing)
  --help           print this message and exit

Measured-run flags:
  --feeder <ieee8500|ieee8500_mv|ieee13|ieee123>   default ieee8500 (8500 feeders use the
                                                   :default_10pct population, others :default)
  --T <int>                  horizon, default 10 (at least 9 on the IEEE-8500 feeders)
  --seed <int>               Scenario master seed, default 1 (at least 1)
  --run-label <str>          label column, [A-Za-z0-9._-]+ (join key with point_resources.csv)
  --time-limit <s>           ADMM wall-clock cap in seconds, default 1200 (recorded in the note)
  --min-mem-avail-gib <f>    pre-flight MemAvailable floor in binary GiB, default 8; 0 disables
  --results-dir <path>       output directory (or env TSODSO_IEEE8500_RESULTS_DIR),
                             default results/ieee8500_benchmark under the project

Launch the measured IEEE-8500 run through the wrapper, detached and alone:
  JULIA_HEAP_SIZE_HINT=8G SCRIPT=scripts/ieee8500_scenario_point.jl scripts/run_ieee8500_point.sh <label> -- --feeder ieee8500 --T 10 --run-label <label>
"""

# The 8500 family: below T = 9 the population's window construction is a loud error downstream.
const FEEDERS_8500 = (:ieee8500, :ieee8500_mv)
const T_MIN_8500 = 9

"""
    parse_options(args) -> NamedTuple

Parse and validate every flag BEFORE any heavy work; each failure is an `ArgumentError` naming
the flag. Unknown `--` flags are rejected so a typo cannot silently fall back to a default.
"""
function parse_options(args)
    i = 1
    while i <= length(args)
        a = args[i]
        if a in VALUE_FLAGS
            i += 2
        elseif a in BOOL_FLAGS
            i += 1
        else
            throw(ArgumentError("unknown argument $(repr(a)); see --help"))
        end
    end
    help = has_flag(args, "--help")
    record_nogo = has_flag(args, "--record-nogo")

    feeder_str = parse_kv_flag(args, "--feeder", "ieee8500")
    feeder = Symbol(feeder_str)
    feeder in TSODSO.SCENARIO_VALID_FEEDERS || throw(
        ArgumentError(
            "--feeder must be one of $(join(string.(TSODSO.SCENARIO_VALID_FEEDERS), ", ")) " *
            "(got $(repr(feeder_str)))",
        ),
    )
    T = _parse_flag(Int, args, "--T", "10")
    if feeder in FEEDERS_8500
        T >= T_MIN_8500 || throw(
            ArgumentError("--T must be >= $T_MIN_8500 on $(feeder_str) (got $T)"),
        )
    else
        T >= 1 || throw(ArgumentError("--T must be >= 1 (got $T)"))
    end
    seed = _parse_flag(Int, args, "--seed", "1")
    seed >= 1 || throw(ArgumentError("--seed must be >= 1 (got $seed)"))
    time_limit = _parse_flag(Float64, args, "--time-limit", "1200")
    (isfinite(time_limit) && time_limit > 0) ||
        throw(ArgumentError("--time-limit must be a finite number > 0 (got $time_limit)"))
    min_gib = _parse_flag(Float64, args, "--min-mem-avail-gib", "8")
    (isfinite(min_gib) && min_gib >= 0) || throw(
        ArgumentError("--min-mem-avail-gib must be a finite number >= 0 (got $min_gib)"),
    )
    label = parse_kv_flag(args, "--run-label", nothing)
    if label !== nothing
        occursin(r"^[A-Za-z0-9._-]+$", label) || throw(
            ArgumentError("--run-label must match [A-Za-z0-9._-]+ (got $(repr(label)))"),
        )
    end
    results_dir = parse_kv_flag(
        args,
        "--results-dir",
        get(ENV, "TSODSO_IEEE8500_RESULTS_DIR", projectdir("results", "ieee8500_benchmark")),
    )
    isempty(results_dir) && throw(ArgumentError("--results-dir must not be empty"))
    return (;
        help,
        record_nogo,
        feeder,
        T,
        seed,
        time_limit,
        min_gib,
        run_label = label,
        results_dir,
    )
end

function _parse_flag(::Type{X}, args, flag, default) where {X}
    s = parse_kv_flag(args, flag, default)
    v = tryparse(X, s)
    v === nothing && throw(ArgumentError("$flag expects a $(X) value (got $(repr(s)))"))
    return v
end

# ---------------------------------------------------------------------------- memory readers

"""`kb_to_gib(kb)`: binary GiB from a kB (KiB) counter, `kb / 1024^2`."""
kb_to_gib(kb) = kb / 1024^2

"""
    proc_status_kb(key) -> Int

The kB value of `key` (for example `"VmHWM"`, the whole-process resident high-water mark) in
/proc/self/status; -1 when absent. Same reader as the earlier attribution script.
"""
function proc_status_kb(key::String)
    for line in eachline("/proc/self/status")
        startswith(line, key * ":") && return parse(Int, split(line)[2])
    end
    return -1
end

"""
    meminfo_kb(key, path = "/proc/meminfo") -> Int

The kB value of `key` in a meminfo-format file; -1 when absent.
"""
function meminfo_kb(key::String, path::AbstractString = "/proc/meminfo")
    for line in eachline(path)
        startswith(line, key * ":") && return parse(Int, split(line)[2])
    end
    return -1
end

"""`mem_available_kb(path = "/proc/meminfo")`: MemAvailable in kB (-1 when absent)."""
mem_available_kb(path::AbstractString = "/proc/meminfo") = meminfo_kb("MemAvailable", path)

"""
    preflight_ok(kb, min_gib) -> Bool

True when the gate is disabled (`min_gib <= 0`) or `kb` (MemAvailable, kB) is at least
`min_gib` binary GiB.
"""
preflight_ok(kb, min_gib) = min_gib <= 0 || kb >= round(Int, min_gib * 1024^2)

# ---------------------------------------------------------------------------- certificate text

const GAP_RATIO_RX = r"worst gap/\(atol_b\+rtol·\|cone\|\)=([0-9.eE+-]+)"

"""
    parse_gap_ratio(msg) -> Float64

The hybrid exactness ratio `worst gap/(atol_b+rtol·|cone|)` quoted in a SOC-exactness refusal
message; `NaN` when the message carries none. Parse BEFORE truncating a message.
"""
function parse_gap_ratio(msg)
    m = match(GAP_RATIO_RX, string(msg))
    m === nothing && return NaN
    v = tryparse(Float64, m.captures[1])
    return v === nothing ? NaN : v
end

"""Free text for the `note` column: no newline (one CSV record per row)."""
one_line(s) = replace(string(s), r"[\r\n]+" => " ")

# ---------------------------------------------------------------------------- row schema

"""
Column order of `scenario_table.csv`. `note` is free text and LAST (the docs page splits each
line with `limit = ncols`, so only the last field may contain commas).
"""
const SCENARIO_TABLE_COLUMNS = (
    :row_kind,
    :feeder,
    :population,
    :T,
    :strategy,
    :seed,
    :sub_seed_population,
    :status,
    :n_buses,
    :n_branches,
    :n_load_buses,
    :n_aggregators,
    :n_cap_aggregators,
    :n_agr_models,
    :dso_vars,
    :dso_cons,
    :agr_vars,
    :agr_cons,
    :materialize_s,
    :build_s,
    :solve_s,
    :certify_s,
    :iters,
    :gap_ratio,
    :vmhwm_kb,
    :vmhwm_gib,
    :maxrss_gib,
    :mem_avail_before_kb,
    :heap_size_hint,
    :julia_version,
    :git_head,
    :threads,
    :run_label,
    :p35_maxrss_kb,
    :p35_maxrss_gib,
    :b1_gib,
    :b2_gib_estimate,
    :anchor_delta_gib,
    :anchor_iters,
    :threshold_gib,
    :note,
)

const ROW_KEY = (:row_kind, :feeder, :population, :T, :strategy)

"""
    scenario_row(; kwargs...) -> NamedTuple

A row with every column of `SCENARIO_TABLE_COLUMNS`, in order; unspecified columns are
`missing`. An unknown keyword is an `ArgumentError` (a typo must not vanish silently).
"""
function scenario_row(; kwargs...)
    for k in keys(kwargs)
        k in SCENARIO_TABLE_COLUMNS ||
            throw(ArgumentError("scenario_row: unknown column $(repr(k))"))
    end
    vals = map(c -> get(kwargs, c, missing), SCENARIO_TABLE_COLUMNS)
    nt = NamedTuple{SCENARIO_TABLE_COLUMNS}(vals)
    return ismissing(nt.note) ? nt : merge(nt, (; note = one_line(nt.note)))
end

_key(r) = Tuple(string(getproperty(r, k)) for k in ROW_KEY)

"""
    upsert_rows!(csv_path, rows) -> DataFrame

Keyed upsert on (row_kind, feeder, population, T, strategy): existing rows with a key present in
`rows` are replaced, every other row is kept; `cols = :union` lets the schema grow. Creates the
directory. Columns are written in `SCENARIO_TABLE_COLUMNS` order, extra columns after them and
`note` last.
"""
function upsert_rows!(csv_path::AbstractString, rows)
    mkpath(dirname(abspath(csv_path)))
    new = reduce((a, b) -> vcat(a, b; cols = :union), (DataFrame([r]) for r in rows))
    df = if isfile(csv_path)
        old = CSV.read(csv_path, DataFrame)
        nk = Set(_key(r) for r in eachrow(new))
        vcat(filter(r -> !(_key(r) in nk), old), new; cols = :union)
    else
        new
    end
    present = Set(propertynames(df))
    known = [c for c in SCENARIO_TABLE_COLUMNS if c in present && c !== :note]
    extra = [c for c in propertynames(df) if !(c in SCENARIO_TABLE_COLUMNS)]
    order = vcat(known, extra, (:note in present ? [:note] : Symbol[]))
    select!(df, order)
    CSV.write(csv_path, df)
    return df
end

# ---------------------------------------------------------------------------- NO-GO record

# earlyoom's SIGTERM limits on this host (results/ieee8500_benchmark/runs/p39-attr-d0.1-T24.oom_earlyoom:
# "low memory! at or below SIGTERM limits: mem 12.00%, swap 12.00%"). Used ONLY for the B2 estimate.
const EARLYOOM_SIGTERM_FRACTION = 0.12
const NOGO_FIXTURE = "ieee8500"
const NOGO_DENSITY = 0.1
const NOGO_T = 24
const NOGO_HEAD_LABEL = "p35-head-d0.1-T24"
const NOGO_KILLED_LABEL = "p35-head-d0.25-T24"

_fmt(x; digits = 3) = string(round(x; digits = digits))

"""
    derive_nogo_row(; attribution_csv, resources_csv, threshold_gib = 10.0,
                    host_total_kb = nothing) -> NamedTuple

The T = 24 go/no-go row (`row_kind = "recorded_no_go"`, `status = "memory_infeasible"`) for the
headline point (feeder ieee8500, density 0.1, ADMM only), computed ONLY from the committed rows:

- `vmhwm_kb`: the largest `VmHWM_kB` over the `memory_attribution.csv` rows with fixture
  ieee8500, density 0.1, T 24 (the in-process high-water mark of the earlier attribution run);
- `p35_maxrss_kb`: `peak_rss_kb` of the `point_resources.csv` row `p35-head-d0.1-T24` (the
  wrapper's /usr/bin/time MaxRSS of the earlier completed head run);
- `anchor_delta_gib`, `anchor_iters`, `gap_ratio`: the attribution row (stage 1,
  `anchor_after`), the ratio parsed from its message;
- `b1_gib`: a MEASURED lower bound, binary GiB of the larger observed peak;
- `b2_gib_estimate`: an ESTIMATE, `b1_gib` plus the earlyoom SIGTERM fraction of MemTotal
  (`host_total_kb`, else /proc/meminfo): the MemAvailable-equivalent needed to stay above the
  host's earlyoom floor at the peak without leaning on swap. It depends on the earlyoom
  configuration and is not a bound.

The verdict compares the measured peaks with `threshold_gib`; it throws (never records) if the
measured peak does not exceed the threshold, because then the row would misstate the data.
"""
function derive_nogo_row(;
    attribution_csv::AbstractString,
    resources_csv::AbstractString,
    threshold_gib::Real = 10.0,
    host_total_kb::Union{Nothing, Integer} = nothing,
)
    att = CSV.read(attribution_csv, DataFrame)
    pts = filter(
        r ->
            string(r.fixture) == NOGO_FIXTURE &&
                r.density == NOGO_DENSITY &&
                r.T == NOGO_T,
        att,
    )
    nrow(pts) > 0 || throw(
        ArgumentError(
            "derive_nogo_row: no $(NOGO_FIXTURE) density $(NOGO_DENSITY) T $(NOGO_T) rows in $attribution_csv",
        ),
    )
    hwm = collect(skipmissing(pts.VmHWM_kB))
    isempty(hwm) && throw(ArgumentError("derive_nogo_row: no VmHWM_kB values in the T = 24 rows"))
    vmhwm_kb = Int(maximum(hwm))

    anchors = filter(r -> r.stage == 1 && string(r.name) == "anchor_after", pts)
    nrow(anchors) == 1 || throw(
        ArgumentError("derive_nogo_row: expected one (stage 1, anchor_after) row, got $(nrow(anchors))"),
    )
    anc = anchors[1, :]
    anchor_delta_gib = Float64(anc.anchor_delta_gib)
    anchor_iters = Int(anc.anchor_iters)
    anchor_status = string(anc.anchor_status)
    gap_ratio = parse_gap_ratio(coalesce(anc.note, ""))

    res = CSV.read(resources_csv, DataFrame)
    head = filter(r -> string(r.run_label) == NOGO_HEAD_LABEL, res)
    nrow(head) == 1 || throw(
        ArgumentError("derive_nogo_row: expected one $(NOGO_HEAD_LABEL) row in $resources_csv"),
    )
    p35_kb = Int(head.peak_rss_kb[1])
    p35_rc = Int(head.rc[1])
    killed = filter(r -> string(r.run_label) == NOGO_KILLED_LABEL, res)

    peak_kb = max(vmhwm_kb, p35_kb)
    b1 = kb_to_gib(peak_kb)
    total_kb = host_total_kb === nothing ? meminfo_kb("MemTotal") : Int(host_total_kb)
    total_kb > 0 || throw(ArgumentError("derive_nogo_row: MemTotal unavailable"))
    total_gib = kb_to_gib(total_kb)
    b2 = b1 + EARLYOOM_SIGTERM_FRACTION * total_gib
    min(kb_to_gib(vmhwm_kb), kb_to_gib(p35_kb)) > threshold_gib || throw(
        ArgumentError(
            "derive_nogo_row: a measured peak does not exceed the $(threshold_gib) GiB threshold; " *
            "the memory_infeasible verdict would misstate the data",
        ),
    )

    killed_txt = if nrow(killed) == 1
        k = killed[1, :]
        " Density 0.25 at T = 24 ($(NOGO_KILLED_LABEL)) ended with rc $(k.rc), " *
        "oom_source $(k.oom_source), at $(k.peak_rss_kb) kB = $(_fmt(kb_to_gib(k.peak_rss_kb))) GiB."
    else
        ""
    end
    note =
        "T = 24 headline point (feeder ieee8500, benchmark-harness density 0.1, ADMM only) " *
        "is memory_infeasible on this host: the measured peak exceeds the $(threshold_gib) GiB GO " *
        "threshold. In-process peak VmHWM $(vmhwm_kb) kB = $(_fmt(kb_to_gib(vmhwm_kb))) GiB " *
        "(memory_attribution.csv, max VmHWM_kB over fixture $(NOGO_FIXTURE), density $(NOGO_DENSITY), " *
        "T $(NOGO_T)); wrapper MaxRSS $(p35_kb) kB = $(_fmt(kb_to_gib(p35_kb))) GiB " *
        "(point_resources.csv $(NOGO_HEAD_LABEL), rc $(p35_rc)). " *
        "B1 = $(_fmt(b1)) GiB is a measured lower bound on the point's peak resident set " *
        "(the larger observed peak, $(peak_kb) kB). " *
        "B2 = B1 + $(round(Int, 100 * EARLYOOM_SIGTERM_FRACTION)) percent of MemTotal " *
        "($(total_kb) kB = $(_fmt(total_gib)) GiB) = $(_fmt(b2)) GiB is an estimate, not a bound: " *
        "the MemAvailable-equivalent needed to stay above earlyoom's SIGTERM limits " *
        "(mem $(round(Int, 100 * EARLYOOM_SIGTERM_FRACTION)) percent and swap " *
        "$(round(Int, 100 * EARLYOOM_SIGTERM_FRACTION)) percent on this host) at the peak without " *
        "relying on swap; it " *
        "depends on the earlyoom configuration. " *
        "Attribution anchor (stage 1, anchor_after): $(anchor_status) after $(anchor_iters) " *
        "iterations, gap ratio $(_fmt(gap_ratio; digits = 2)), maxrss delta " *
        "$(_fmt(anchor_delta_gib; digits = 4)) GiB." *
        killed_txt *
        " Counter-fact: this d = 0.1 T = 24 point completed on this host twice " *
        "($(NOGO_HEAD_LABEL) with rc $(p35_rc), and the attribution run whose anchor_after row is " *
        "cited above) by evicting page cache and using swap; NO-GO means the GO threshold is not " *
        "met, not that the point cannot run. No memory lever is claimed."

    return scenario_row(;
        row_kind = "recorded_no_go",
        feeder = NOGO_FIXTURE,
        population = "harness_density_0.1",
        T = NOGO_T,
        strategy = "ADMM",
        status = "memory_infeasible",
        iters = anchor_iters,
        gap_ratio = gap_ratio,
        vmhwm_kb = vmhwm_kb,
        vmhwm_gib = kb_to_gib(vmhwm_kb),
        p35_maxrss_kb = p35_kb,
        p35_maxrss_gib = kb_to_gib(p35_kb),
        b1_gib = b1,
        b2_gib_estimate = b2,
        anchor_delta_gib = anchor_delta_gib,
        anchor_iters = anchor_iters,
        threshold_gib = Float64(threshold_gib),
        julia_version = string(VERSION),
        git_head = git_head(),
        note = note,
    )
end

"""`git_head()`: short git HEAD of the project, `missing` when git is unavailable."""
function git_head()
    return try
        readchomp(`git -C $(projectdir()) rev-parse --short HEAD`)
    catch
        missing
    end
end

function record_nogo(opts)
    dir = opts.results_dir
    row = derive_nogo_row(;
        attribution_csv = joinpath(dir, "memory_attribution.csv"),
        resources_csv = joinpath(dir, "point_resources.csv"),
    )
    path = joinpath(dir, "scenario_table.csv")
    upsert_rows!(path, [row])
    println(
        "recorded_no_go: status=$(row.status) vmhwm_kb=$(row.vmhwm_kb) " *
        "($(_fmt(row.vmhwm_gib)) GiB) p35_maxrss_kb=$(row.p35_maxrss_kb) " *
        "($(_fmt(row.p35_maxrss_gib)) GiB) b1_gib=$(_fmt(row.b1_gib)) " *
        "b2_gib_estimate=$(_fmt(row.b2_gib_estimate)) -> $path",
    )
    return row
end

# ---------------------------------------------------------------------------- entry point

function main(args)
    opts = parse_options(args)
    if opts.help
        print(USAGE)
        return nothing
    elseif opts.record_nogo
        record_nogo(opts)
        return nothing
    end
    run_measured_point(opts)
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end

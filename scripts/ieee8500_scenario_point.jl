# scripts/ieee8500_scenario_point.jl
#
# One IEEE-8500 measurement point run through `Scenario` (the library path), with the ADMM
# phases timed separately, a host-memory pre-flight gate and honest status rows; plus a
# `--record-nogo` mode that derives the T = 24 go/no-go record from the committed CSVs.
#
# Usage:
#
#   # measured run (launch through the per-point wrapper, detached and alone on the host;
#   # HEAP_SIZE_HINT makes the wrapper pass julia's `--heap-size-hint=` flag, omit it for no hint):
#   HEAP_SIZE_HINT=8G SCRIPT=scripts/ieee8500_scenario_point.jl scripts/run_ieee8500_point.sh <label> -- --feeder ieee8500 --T 10 --run-label <label>
#
#   # Julia reads NO environment variable for the heap-size hint (JULIA_HEAP_SIZE_HINT is ignored);
#   # only the `--heap-size-hint=` command-line flag sets it. The row's `heap_size_hint` column is
#   # the EFFECTIVE value, `Base.JLOptions().heap_size_hint` in bytes (0 = no hint).
#
#   # NO-GO record from results/ieee8500_benchmark/memory_attribution.csv and point_resources.csv
#   # (reads the committed CSVs only, solves nothing):
#   julia --project=. scripts/ieee8500_scenario_point.jl --record-nogo
#
#   julia --project=. scripts/ieee8500_scenario_point.jl --help
#
# Both modes upsert rows into `<results-dir>/scenario_table.csv` (default
# results/ieee8500_benchmark/, or env TSODSO_IEEE8500_RESULTS_DIR, or --results-dir), keyed by
# (row_kind, feeder, population, T, strategy, seed, run_label): a re-run of the same attempt
# identity replaces its own row and keeps every other row; another seed or label is another row.
# A transient row (`started`, `preflight_refused`) never displaces a final row of the same key:
# it is kept beside it until that attempt's final row replaces both. `cols = :union` lets the
# schema grow (rows written before a column existed read as missing). The free-text `note`
# column is always LAST. The file is rewritten atomically (temp file in the same directory, then
# rename).
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
# Sequence: read MemAvailable from /proc/meminfo on the script's first lines (before any package
# load) -> validate flags -> pre-flight on that reading -> upsert a `started` row -> run the phases -> upsert the final row (same key,
# so it replaces `started`, and any earlier final row of the same seed and label). A process
# killed mid-run therefore leaves its `started` row (beside an earlier completed row of the same
# key, which it never replaces), and the wrapper's point_resources.csv row (joined by run_label)
# carries rc and oom_source.
#
# Status vocabulary (one token in the `status` column):
#   ok                   converged and certified
#   refused_certificate  converged, but a certificate (for example SOC exactness) refused the point
#   convergence_error    maxiter reached without consensus (no certificate attempted)
#   budget_exceeded      wall-clock cap reached (certify skipped, no welfare, as solve_admm does)
#   error:<TypeName>     any other TSODSOError (for example error:SolveFailedError)
#   preflight_refused    MemAvailable below --min-mem-avail-gib; nothing was materialized
#   memory_infeasible    the recorded T = 24 NO-GO row (--record-nogo)
#   memory_infeasible_inprocess
#                        Julia raised OutOfMemoryError during the phases (a measured outcome);
#                        the row is written, then the error propagates (nonzero exit)
#   crashed:<TypeName>   any other non-TSODSOError during the phases (misuse or a bug, not a
#                        measured outcome); the row is written, then the error propagates
#   started              written before the heavy work; still present means the process died
#                        without raising (for example killed by a signal)
# `started`, `preflight_refused` and `crashed:*` are transient: they never replace a final row.
#
# Honesty policy: refusals, nulls and infeasible outcomes are rows, stated plainly. Nothing is
# retuned to make a point fit or pass: no tolerance, tau, epsilon or exactness floor is exposed,
# and a pre-flight refusal or an earlyoom kill is a measured outcome, never retried.
#
# Units: every memory figure is binary GiB (1 GiB = 2^30 bytes = 1,048,576 kB); the raw kB
# counters (/proc/self/status VmHWM, /proc/meminfo MemAvailable, /usr/bin/time MaxRSS) are kept
# beside the GiB conversions.

# MemAvailable for the pre-flight, read with Base only BEFORE any package is loaded: a reading
# taken after `using TSODSO` would include this process's own package-load footprint (about
# 0.9 GiB on the measurement host), so the gate would demand that much more at launch than it
# states. -1 when /proc/meminfo or the field is absent.
const MEMAVAIL_AT_START_KB = let v = -1
    if isfile("/proc/meminfo")
        for line in eachline("/proc/meminfo")
            if startswith(line, "MemAvailable:")
                v = parse(Int, split(line)[2])
                break
            end
        end
    end
    v
end

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
                             (MemAvailable is read at script start, before any package load)
  --results-dir <path>       output directory (or env TSODSO_IEEE8500_RESULTS_DIR),
                             default results/ieee8500_benchmark under the project

Launch the measured IEEE-8500 run through the wrapper, detached and alone (HEAP_SIZE_HINT makes
the wrapper pass julia's --heap-size-hint= flag; julia ignores JULIA_HEAP_SIZE_HINT):
  HEAP_SIZE_HINT=8G SCRIPT=scripts/ieee8500_scenario_point.jl scripts/run_ieee8500_point.sh <label> -- --feeder ieee8500 --T 10 --run-label <label>
The heap_size_hint column records the effective hint, Base.JLOptions().heap_size_hint, in bytes
(0 = no hint).
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
    :materialize_compile_s,
    :build_compile_s,
    :solve_compile_s,
    :certify_compile_s,
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

"""
Identity of a row in `scenario_table.csv`: the attempt identity (seed and run label included), so
a later attempt with another seed or label never replaces an earlier measurement.
"""
const ROW_KEY = (:row_kind, :feeder, :population, :T, :strategy, :seed, :run_label)

"""
Statuses of a row that is not a final outcome of its attempt: `started` (the run is under way, or
the process died) and `preflight_refused` (nothing was materialized). Such a row never replaces a
final row of the same key. A `crashed:<TypeName>` row (a non-solver exception, see
`run_measured_point`) is transient too.
"""
const TRANSIENT_STATUSES = ("started", "preflight_refused")

"""`is_transient_status(status)`: true for a status in `TRANSIENT_STATUSES` or `crashed:*`."""
is_transient_status(status) =
    (st = string(status); st in TRANSIENT_STATUSES || startswith(st, "crashed:"))

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

# A key column absent from an older table (written before it joined the key) reads as missing.
_key(r) = Tuple(string(hasproperty(r, k) ? getproperty(r, k) : missing) for k in ROW_KEY)

"""
    upsert_rows!(csv_path, rows) -> DataFrame

Keyed upsert on `ROW_KEY` (row_kind, feeder, population, T, strategy, seed, run_label). For each
new row, the existing rows with the same key are replaced, except that a transient new row
(`is_transient_status`) never displaces a final row: then only the older transient rows of that
key are replaced and the final row stays. Every other row is kept; `cols = :union` lets the
schema grow. Creates the directory. Columns are written in `SCENARIO_TABLE_COLUMNS` order, extra
columns after them and `note` last.
"""
function upsert_rows!(csv_path::AbstractString, rows)
    mkpath(dirname(abspath(csv_path)))
    new = reduce((a, b) -> vcat(a, b; cols = :union), (DataFrame([r]) for r in rows))
    df = if isfile(csv_path)
        old = CSV.read(csv_path, DataFrame)
        okeys = [_key(r) for r in eachrow(old)]
        otrans = [hasproperty(r, :status) && is_transient_status(r.status) for r in eachrow(old)]
        keep = trues(nrow(old))
        for nr in eachrow(new)
            k = _key(nr)
            same = [i for i in eachindex(okeys) if okeys[i] == k]
            protect_final = is_transient_status(nr.status) && any(i -> !otrans[i], same)
            for i in same
                (protect_final && !otrans[i]) || (keep[i] = false)
            end
        end
        vcat(old[keep, :], new; cols = :union)
    else
        new
    end
    present = Set(propertynames(df))
    known = [c for c in SCENARIO_TABLE_COLUMNS if c in present && c !== :note]
    extra = [c for c in propertynames(df) if !(c in SCENARIO_TABLE_COLUMNS)]
    order = vcat(known, extra, (:note in present ? [:note] : Symbol[]))
    select!(df, order)
    write_table_atomic(csv_path, df)
    return df
end

"""
    write_table_atomic(csv_path, df)

Write `df` to a temporary file in the SAME directory as `csv_path`, then rename it over
`csv_path`. A rename within one filesystem is atomic (POSIX `rename(2)`), so a kill or crash
mid-write leaves either the old table or the new one, never a truncated file. `Base.mv(...;
force = true)` is not used, because it deletes the target before renaming. There is no lock:
concurrent writers can still lose each other's update, so measured runs stay one at a time.
"""
function write_table_atomic(csv_path::AbstractString, df)
    dir = dirname(abspath(csv_path))
    tmp = joinpath(dir, "." * basename(csv_path) * ".tmp." * string(getpid()))
    try
        CSV.write(tmp, df)
        Base.Filesystem.rename(tmp, csv_path)
    finally
        isfile(tmp) && rm(tmp; force = true)
    end
    return csv_path
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
# B2's host total comes from the measurement host's evidence, never from the machine that runs
# --record-nogo: the `free -m` snapshot of the attribution run of this headline point (the run
# whose VmHWM is cited and whose earlyoom log gives the 12 percent above).
const NOGO_HOST_EVIDENCE_LABEL = "p39-attr-d0.1-T24"

"""
    free_total_kb(path) -> Int

The total memory on the `Mem:` line of a `free -m` snapshot (a wrapper `runs/<label>.free_before`
file), in kB: the MiB value times 1024 (`free -m` truncates to whole MiB).
"""
function free_total_kb(path::AbstractString)
    for line in eachline(path)
        startswith(line, "Mem:") && return parse(Int, split(line)[2]) * 1024
    end
    throw(ArgumentError("free_total_kb: no Mem: line in $path"))
end

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
- `b2_gib_estimate`: an ESTIMATE, `b1_gib` plus the earlyoom SIGTERM fraction of the host's total
  memory: the MemAvailable-equivalent needed to stay above the host's earlyoom floor at the peak
  without leaning on swap. It depends on the earlyoom configuration and is not a bound. The total
  is `host_total_kb` when given, else the `free -m` total in
  `runs/$(NOGO_HOST_EVIDENCE_LABEL).free_before` beside `resources_csv` (the measurement host's
  evidence); the machine running the derivation is never read.

The verdict compares the LARGER measured peak (B1) with `threshold_gib`: GO needs the point's
peak below the threshold, so one observation above it is enough for NO-GO. It throws (never
records) if no measured peak exceeds the threshold, because then the row would misstate the data.
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
    p35_avail_mib = Int(head.mem_avail_before_mb[1])
    killed = filter(r -> string(r.run_label) == NOGO_KILLED_LABEL, res)
    nrow(killed) == 1 || throw(
        ArgumentError(
            "derive_nogo_row: expected one $(NOGO_KILLED_LABEL) row in $resources_csv, " *
            "got $(nrow(killed)); the record cites it and must not drop it silently",
        ),
    )

    peak_kb = max(vmhwm_kb, p35_kb)
    b1 = kb_to_gib(peak_kb)
    host_src, total_kb = if host_total_kb === nothing
        ev = joinpath("runs", NOGO_HOST_EVIDENCE_LABEL * ".free_before")
        "free -m total in $(ev)", free_total_kb(joinpath(dirname(abspath(resources_csv)), ev))
    else
        "host_total_kb argument", Int(host_total_kb)
    end
    total_kb > 0 || throw(ArgumentError("derive_nogo_row: host total memory unavailable"))
    total_gib = kb_to_gib(total_kb)
    b2 = b1 + EARLYOOM_SIGTERM_FRACTION * total_gib
    b1 > threshold_gib || throw(
        ArgumentError(
            "derive_nogo_row: no measured peak exceeds the $(threshold_gib) GiB threshold " *
            "(larger peak $(_fmt(b1)) GiB); the memory_infeasible verdict would misstate the data",
        ),
    )

    k = killed[1, :]
    killed_txt =
        " Density 0.25 at T = 24 ($(NOGO_KILLED_LABEL)) ended with rc $(k.rc), " *
        "oom_source $(k.oom_source), at $(k.peak_rss_kb) kB = $(_fmt(kb_to_gib(k.peak_rss_kb))) GiB."

    # The counter-fact is derived from the rows, never assumed: a run counts as completed only
    # with rc 0 (head run) or a recorded anchor_after solve with at least one iteration.
    head_done = p35_rc == 0
    anchor_done = anchor_iters > 0
    n_done = Int(head_done) + Int(anchor_done)
    avail_gib = p35_avail_mib / 1024
    head_txt = if head_done
        "$(NOGO_HEAD_LABEL) ended with rc 0 after launching with MemAvailable $(p35_avail_mib) MiB " *
        "= $(_fmt(avail_gib)) GiB (point_resources.csv mem_avail_before_mb), " *
        (avail_gib < b1 ?
         "below B1, so it used memory beyond what was available at launch (MemAvailable already " *
         "counts reclaimable page cache; the rest came from swap-out or from memory other " *
         "processes released, which the wrapper did not measure)" :
         "at or above B1")
    else
        "$(NOGO_HEAD_LABEL) ended with rc $(p35_rc), so no completed run is claimed from it"
    end
    anchor_txt = if anchor_done
        "the attribution run whose anchor_after row is cited above ran its production solve to " *
        "the end ($(anchor_status) after $(anchor_iters) iterations)"
    else
        "the attribution anchor_after row records no iteration, so no completed run is claimed " *
        "from it"
    end
    counter_txt = if n_done > 0
        " Counter-fact: this d = 0.1 T = 24 point completed on this host " *
        "$(n_done == 2 ? "twice" : "once"): $(head_txt); $(anchor_txt). NO-GO means the GO " *
        "threshold is not met, not that the point cannot run."
    else
        " No completed run of this point is recorded: $(head_txt); $(anchor_txt)."
    end
    note =
        "T = 24 headline point (feeder ieee8500, benchmark-harness density 0.1, ADMM only) " *
        "is memory_infeasible on this host: the larger measured peak exceeds the $(threshold_gib) " *
        "GiB GO threshold. In-process peak VmHWM $(vmhwm_kb) kB = $(_fmt(kb_to_gib(vmhwm_kb))) GiB " *
        "(memory_attribution.csv, max VmHWM_kB over fixture $(NOGO_FIXTURE), density $(NOGO_DENSITY), " *
        "T $(NOGO_T)); wrapper MaxRSS $(p35_kb) kB = $(_fmt(kb_to_gib(p35_kb))) GiB " *
        "(point_resources.csv $(NOGO_HEAD_LABEL), rc $(p35_rc)). " *
        "B1 = $(_fmt(b1)) GiB is a measured lower bound on the point's peak resident set " *
        "(the larger observed peak, $(peak_kb) kB). " *
        "B2 = B1 + $(round(Int, 100 * EARLYOOM_SIGTERM_FRACTION)) percent of the host's total " *
        "memory ($(total_kb) kB = $(_fmt(total_gib)) GiB, $(host_src)) = $(_fmt(b2)) GiB is an " *
        "estimate, not a bound: " *
        "the MemAvailable-equivalent needed to stay above earlyoom's SIGTERM limits " *
        "(mem $(round(Int, 100 * EARLYOOM_SIGTERM_FRACTION)) percent and swap " *
        "$(round(Int, 100 * EARLYOOM_SIGTERM_FRACTION)) percent on this host) at the peak without " *
        "relying on swap; it " *
        "depends on the earlyoom configuration. " *
        "Attribution anchor (stage 1, anchor_after): $(anchor_status) after $(anchor_iters) " *
        "iterations, gap ratio $(_fmt(gap_ratio; digits = 2)), maxrss delta " *
        "$(_fmt(anchor_delta_gib; digits = 4)) GiB." *
        killed_txt *
        counter_txt *
        " No memory lever is claimed."

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

# ---------------------------------------------------------------------------- measured run

"""
    scenario_admm_phases(s::Scenario; time_limit_s = 1200.0, sample_mem = true,
                         atol_exact = nothing, rtol_exact = 1e-4) -> NamedTuple

Run the ADMM `Scenario` `s` phase by phase, in the order of `TSODSO.run(::ADMM, s)` plus
`solve_admm` (same calls, same arguments), each phase timed with `@elapsed`:

1. materialize: `_materialize(s)`, `build_powerflow(s)`, the reactive-mode resolution;
2. build: `_admm_build` (the DSO model and one AgrOpt model per aggregator);
3. solve: `_admm_iterate!` with the strategy's knobs and the wall-clock cap `time_limit_s`;
4. certify: `_admm_certify` (skipped on a budget exit or without consensus, as solve_admm does).

No explicit garbage-collection call runs between phases. With `sample_mem`, VmHWM (kB) is read after every phase.

The point runs in one process with no warm-up, so every phase time includes first-call
compilation. The compilation part is measured with `Base.cumulative_compile_time_ns()` (timing is
switched on for the call and off again) and returned as `<phase>_compile_s`.

`atol_exact`/`rtol_exact` are passed to `_admm_certify`; their defaults are `solve_admm`'s own
(`nothing` = the hybrid floor, `1e-4`), which is what `run(::ADMM)` uses. The command line never
sets them, so a measured row is never judged with another tolerance; they exist only so that the
tests can force the certificate-refusal branch on IEEE-13.

Returns row-ready fields (`status`, timings, sizes, `iters`, `gap_ratio`, `vmhwm_kb`,
`hwm_by_phase`, `message`, ...) and `result`: on `status == "ok"` the certified result
NamedTuple with `welfare`, `dadp`, `exact_maxgap` and `iters` converted exactly as
`run(::ADMM, s)` converts them, else `nothing`. Expected solver outcomes become statuses; any
exception that is not a `TSODSOError` propagates.
"""
function scenario_admm_phases(
    s::Scenario;
    time_limit_s = 1200.0,
    sample_mem::Bool = true,
    atol_exact::Union{Nothing, Real} = nothing,
    rtol_exact::Real = 1e-4,
)
    A = s.strategy
    A isa ADMM || throw(ArgumentError("scenario_admm_phases: needs an ADMM strategy, got $(typeof(A))"))
    hwm() = sample_mem ? proc_status_kb("VmHWM") : missing
    hwm_by_phase = Pair{Symbol, Any}[]
    t = Dict{Symbol, Float64}()
    tc = Dict{Symbol, Float64}()   # compilation time inside each phase
    cns() = Int(first(Base.cumulative_compile_time_ns()))
    sizes = Dict{Symbol, Any}()
    local feeder, λ₀, aggs, pf, mode, rmode, st
    have_st = false
    loop_done = false
    status = "started"
    iters = missing
    gap_ratio = missing
    message = ""
    result = nothing
    Base.cumulative_compile_timing(true)
    try
        c0 = cns()
        t[:materialize] = @elapsed begin
            feeder, λ₀, aggs = TSODSO._materialize(s)
            pf = TSODSO.build_powerflow(s)
            TSODSO._check_admm_pair!(:solve_admm, feeder, pf)
            mode = TSODSO.normalize_reactive_mode(TSODSO._default_reactive_consensus(aggs))
            rmode = TSODSO._react_mode(mode)
        end
        tc[:materialize] = (cns() - c0) / 1e9
        push!(hwm_by_phase, :materialize => hwm())
        sizes[:n_buses] = length(feeder.buses)
        sizes[:n_branches] = length(feeder.branches)
        sizes[:n_load_buses] =
            s.feeder in FEEDERS_8500 ? length(TSODSO._load_buses(feeder, s.feeder)) : missing
        sizes[:n_aggregators] = length(aggs)
        sizes[:n_cap_aggregators] =
            count(a -> any(d -> d isa TSODSO.FixedCapacitor, a.devices), aggs)

        ρf = Float64(A.ρ)
        c0 = cns()
        t[:build] = @elapsed begin
            st = TSODSO._admm_build(
                feeder,
                pf,
                aggs,
                s.T,
                λ₀,
                ρf,
                ρf,
                mode,
                rmode;
                agr_optimizer = TSODSO.select_optimizer(TSODSO.QP()),
            )
        end
        tc[:build] = (cns() - c0) / 1e9
        have_st = true
        push!(hwm_by_phase, :build => hwm())
        # Sizes from the models the run already holds (no extra build).
        sizes[:n_agr_models] = length(st.agr_by_bus)
        sizes[:dso_vars] = JuMP.num_variables(st.dso.model)
        sizes[:dso_cons] =
            JuMP.num_constraints(st.dso.model; count_variable_in_set_constraints = true)
        sizes[:agr_vars] = sum(JuMP.num_variables(m.model) for m in values(st.agr_by_bus))
        sizes[:agr_cons] = sum(
            JuMP.num_constraints(m.model; count_variable_in_set_constraints = true) for
            m in values(st.agr_by_bus)
        )

        c0 = cns()
        t[:solve] = @elapsed begin
            TSODSO._admm_iterate!(
                st,
                rmode,
                A.maxiter,
                A.ε_abs,
                A.ε_rel,
                A.τ_ratio,
                A.μ,
                1e-2,
                1e4,
                time_limit_s,
                false,
            )
        end
        tc[:solve] = (cns() - c0) / 1e9
        push!(hwm_by_phase, :solve => hwm())
        loop_done = true
        iters = Int(st.residuals.iters)

        if !st.converged_flag && !st.budget_exceeded_flag
            status = "convergence_error"
            iters = A.maxiter
            message =
                "maxiter=$(A.maxiter) reached without primal and dual residual consensus; " *
                "no certificate attempted"
        elseif st.budget_exceeded_flag
            status = "budget_exceeded"
            message = "wall-clock cap time_limit_s=$(time_limit_s) reached; certify skipped, no welfare"
        else
            local r
            certified = false
            # Timed with time_ns and recorded in `finally`, so a non-certificate error raised by
            # certify (for example a SolveFailedError in a certify re-solve) keeps its timing and
            # its high-water-mark sample.
            t0 = time_ns()
            c0 = cns()
            r = try
                TSODSO._admm_certify(st, rmode, mode, aggs, λ₀, atol_exact, rtol_exact, false)
            catch err
                err isa CertificateError || rethrow()
                err
            finally
                t[:certify] = (time_ns() - t0) / 1e9
                tc[:certify] = (cns() - c0) / 1e9
                push!(hwm_by_phase, :certify => hwm())
            end
            if r isa CertificateError
                status = "refused_certificate"
                iters = Int(st.residuals.iters)
                gap_ratio = parse_gap_ratio(r.msg)   # before truncation
                message = "CertificateError kind=$(r.kind): " * first(string(r.msg), 400)
            else
                status = "ok"
                ratio = get(st.dso.ctx.meta, :socp_maxratio, missing)
                gap_ratio = ratio === nothing ? missing : ratio
                result = (;
                    r...,
                    welfare = Float64(r.welfare),
                    dadp = Matrix{Float64}(r.dadp),
                    exact_maxgap = Float64(r.exact_maxgap),
                    iters = Int(r.iters),
                )
                iters = result.iters
                message = "certified; exact_maxgap=$(result.exact_maxgap) welfare=$(result.welfare)"
            end
        end
    catch err
        err isa TSODSOError || rethrow()
        status = "error:" * string(nameof(typeof(err)))
        if err isa CertificateError
            status = "refused_certificate"
            gap_ratio = parse_gap_ratio(err.msg)
        end
        # Once the loop has finished, its iteration count is known whatever certify raised; -1 is
        # kept for failures before the loop ended.
        iters = if hasproperty(err, :iterations) && err.iterations !== nothing
            Int(err.iterations)
        elseif have_st && loop_done
            Int(st.residuals.iters)
        else
            -1
        end
        message = first(string(err.msg), 400)
    finally
        Base.cumulative_compile_timing(false)
    end
    phase_s(k) = get(t, k, missing)
    return (;
        status,
        iters,
        gap_ratio,
        materialize_s = phase_s(:materialize),
        build_s = phase_s(:build),
        solve_s = phase_s(:solve),
        certify_s = phase_s(:certify),
        materialize_compile_s = get(tc, :materialize, missing),
        build_compile_s = get(tc, :build, missing),
        solve_compile_s = get(tc, :solve, missing),
        certify_compile_s = get(tc, :certify, missing),
        n_buses = get(sizes, :n_buses, missing),
        n_branches = get(sizes, :n_branches, missing),
        n_load_buses = get(sizes, :n_load_buses, missing),
        n_aggregators = get(sizes, :n_aggregators, missing),
        n_cap_aggregators = get(sizes, :n_cap_aggregators, missing),
        n_agr_models = get(sizes, :n_agr_models, missing),
        dso_vars = get(sizes, :dso_vars, missing),
        dso_cons = get(sizes, :dso_cons, missing),
        agr_vars = get(sizes, :agr_vars, missing),
        agr_cons = get(sizes, :agr_cons, missing),
        vmhwm_kb = sample_mem ? proc_status_kb("VmHWM") : missing,
        maxrss_kb = Sys.maxrss() ÷ 1024,
        hwm_by_phase,
        message = one_line(message),
        result,
    )
end

"""The population selector the measured run uses on `feeder`."""
population_for(feeder::Symbol) = feeder in FEEDERS_8500 ? :default_10pct : :default

"""
    effective_heap_size_hint() -> Int

The heap-size hint this Julia process actually runs with, in bytes; 0 means no hint. It is read
from `Base.JLOptions().heap_size_hint`, which only julia's `--heap-size-hint=` flag sets. Julia
reads no environment variable for it, so an environment value is never recorded as provenance.
"""
effective_heap_size_hint() = Int(Base.JLOptions().heap_size_hint)

function _provenance_fields(opts)
    return (;
        heap_size_hint = effective_heap_size_hint(),
        julia_version = string(VERSION),
        git_head = git_head(),
        threads = Threads.nthreads(),
        run_label = opts.run_label === nothing ? missing : opts.run_label,
    )
end

"""
    run_measured_point(opts; phases = scenario_admm_phases) -> NamedTuple

validate (done by `parse_options`) -> pre-flight -> `started` row -> phases -> final row. A
pre-flight refusal writes one `preflight_refused` row and returns normally (exit 0); nothing is
retried or retuned.

An exception that `phases` lets through (anything that is not a `TSODSOError`) is recorded before
it propagates: `OutOfMemoryError` as `memory_infeasible_inprocess` (a measured outcome), any other
type as the transient `crashed:<TypeName>`. `phases` is the phase runner (the default is the real
one; tests pass a stub so that no solve runs).

The pre-flight judges `avail_kb`, by default `MEMAVAIL_AT_START_KB`: MemAvailable read on the
script's first lines, before any package load.
"""
function run_measured_point(
    opts;
    phases = scenario_admm_phases,
    avail_kb::Integer = MEMAVAIL_AT_START_KB,
)
    pop = population_for(opts.feeder)
    key = (;
        row_kind = "measured",
        feeder = string(opts.feeder),
        population = string(pop),
        T = opts.T,
        strategy = "ADMM",
        seed = opts.seed,
        sub_seed_population = TSODSO.sub_seed(opts.seed, :population),
    )
    path = joinpath(opts.results_dir, "scenario_table.csv")
    prov = _provenance_fields(opts)
    cap_txt =
        "wall-clock cap time_limit_s=$(opts.time_limit) (harness default; the library path has " *
        "none); pre-flight MemAvailable read at script start, before any package load"

    # Pre-flight on the reading taken before any package load; nothing is materialized yet.
    if !preflight_ok(avail_kb, opts.min_gib)
        need_kb = round(Int, opts.min_gib * 1024^2)
        row = scenario_row(;
            key...,
            prov...,
            status = "preflight_refused",
            mem_avail_before_kb = avail_kb,
            note = "pre-flight refused: MemAvailable (read at script start, before any package " *
                   "load) $(avail_kb) kB = " *
                   "$(_fmt(kb_to_gib(avail_kb))) GiB is below --min-mem-avail-gib " *
                   "$(opts.min_gib) ($(need_kb) kB); nothing was materialized, not retried",
        )
        upsert_rows!(path, [row])
        println("preflight_refused: ", row.note, " -> ", path)
        return row
    end

    # Constructed before the `started` row: an invalid combination is an ArgumentError with no row.
    s = Scenario(;
        name = "ieee8500-scn",
        feeder = opts.feeder,
        population = pop,
        strategy = ADMM(),
        T = opts.T,
        seed = opts.seed,
    )

    upsert_rows!(
        path,
        [
            scenario_row(;
                key...,
                prov...,
                status = "started",
                mem_avail_before_kb = avail_kb,
                note = "started; " * cap_txt,
            ),
        ],
    )

    ph = try
        phases(s; time_limit_s = opts.time_limit, sample_mem = true)
    catch err
        # Not a solver-layer outcome: record it (best effort), then let it propagate.
        st = if err isa OutOfMemoryError
            "memory_infeasible_inprocess"
        else
            "crashed:" * string(nameof(typeof(err)))
        end
        try
            vm = isfile("/proc/self/status") ? proc_status_kb("VmHWM") : -1
            upsert_rows!(
                path,
                [
                    scenario_row(;
                        key...,
                        prov...,
                        status = st,
                        vmhwm_kb = vm,
                        vmhwm_gib = vm < 0 ? missing : kb_to_gib(vm),
                        mem_avail_before_kb = avail_kb,
                        note = "$(cap_txt); raised $(nameof(typeof(err))) during the phases: " *
                               first(sprint(showerror, err), 400),
                    ),
                ],
            )
        catch werr
            @warn "could not record the in-process failure row" exception = werr
        end
        rethrow()
    end

    hwm_txt = join(("$(k)=$(v)" for (k, v) in ph.hwm_by_phase), " ")
    row = scenario_row(;
        key...,
        prov...,
        status = ph.status,
        n_buses = ph.n_buses,
        n_branches = ph.n_branches,
        n_load_buses = ph.n_load_buses,
        n_aggregators = ph.n_aggregators,
        n_cap_aggregators = ph.n_cap_aggregators,
        n_agr_models = ph.n_agr_models,
        dso_vars = ph.dso_vars,
        dso_cons = ph.dso_cons,
        agr_vars = ph.agr_vars,
        agr_cons = ph.agr_cons,
        materialize_s = ph.materialize_s,
        build_s = ph.build_s,
        solve_s = ph.solve_s,
        certify_s = ph.certify_s,
        materialize_compile_s = ph.materialize_compile_s,
        build_compile_s = ph.build_compile_s,
        solve_compile_s = ph.solve_compile_s,
        certify_compile_s = ph.certify_compile_s,
        iters = ph.iters,
        gap_ratio = ph.gap_ratio,
        vmhwm_kb = ph.vmhwm_kb,
        vmhwm_gib = ismissing(ph.vmhwm_kb) || ph.vmhwm_kb < 0 ? missing : kb_to_gib(ph.vmhwm_kb),
        maxrss_gib = kb_to_gib(ph.maxrss_kb),
        mem_avail_before_kb = avail_kb,
        note = "$(cap_txt); Sys.maxrss $(ph.maxrss_kb) kB; VmHWM kB after each phase: " *
               "$(hwm_txt); $(ph.message)",
    )
    upsert_rows!(path, [row])
    println(
        "measured: feeder=$(row.feeder) population=$(row.population) T=$(row.T) " *
        "seed=$(row.seed) status=$(row.status) iters=$(row.iters) " *
        "buses=$(row.n_buses) aggregators=$(row.n_aggregators) " *
        "materialize_s=$(row.materialize_s) build_s=$(row.build_s) solve_s=$(row.solve_s) " *
        "certify_s=$(row.certify_s) vmhwm_kb=$(row.vmhwm_kb) maxrss_gib=$(row.maxrss_gib) " *
        "gap_ratio=$(row.gap_ratio) -> $path",
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

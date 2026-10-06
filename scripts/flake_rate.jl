# scripts/flake_rate.jl
#
# Fresh-process flake-rate harness. Runs selected @testitems N times, each repeat in a NEW
# Julia process (so solver/JIT state cannot leak between repeats), and records per-repeat
# outcome, solver-status labels and the Julia VERSION.
#
# Usage (from the repo root, with the test directory on the load path):
#   JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia --project=. -t2 scripts/flake_rate.jl \
#       [--repeats N] [--jobs J] [--targets a,b,c] [--inprocess N] \
#       [--outdir results/flake_rate] [--force]
#   julia --project=. scripts/flake_rate.jl --selftest
#   (internal) ... scripts/flake_rate.jl --child <target>
#
# Targets: ieee13_admm, stochastic_welfare, fit_baseline.
# Outputs: <outdir>/<UTC timestamp>_<julia VERSION>.csv and <outdir>/findings.txt (appended).
# The real test items are run, so this measures the current defaults of the live code.

using Dates
using Printf
using Test

const ROOT = normpath(joinpath(@__DIR__, ".."))

# target => (test file, exact item names or a name prefix)
const TARGETS = Dict(
    "ieee13_admm" => (
        "test_ieee123_admm.jl",
        ["ieee13 admm 4q-bess: live reactive dual-ascent supporting evidence, NOT CI-gating (ieee13, 4q)"],
        "",
    ),
    "stochastic_welfare" => ("test_stochastic_welfare.jl", String[], "stochastic_welfare:"),
    "fit_baseline" => (
        "test_pricing_welfare.jl",
        ["welfare surplus accounting: +25% FIT ratio golden + non-failing thesis cross-check"],
        "",
    ),
)
const ADMM_CROSSVAL = (
    "test_admm.jl",
    "admm: cross-validation ieee13 welfare + DADP (crossval, ieee13)",
)
const TARGET_ORDER = ["ieee13_admm", "stochastic_welfare", "fit_baseline"]

# ----------------------------------------------------------------------------------------
# Pure helpers (exercised by --selftest)
# ----------------------------------------------------------------------------------------

"""Status/error tokens searched for in a child log, in reporting order."""
const LABEL_TOKENS = [
    "NUMERICAL_ERROR",
    "ALMOST_OPTIMAL",
    "ALMOST_SOLVED",
    "SLOW_PROGRESS",
    "ConvergenceError",
    "SolveFailedError",
]
const STATUS_TOKENS = ["NUMERICAL_ERROR", "ALMOST_OPTIMAL", "ALMOST_SOLVED", "SLOW_PROGRESS"]

"""Labels present in a child log (ConvergenceError is its own category)."""
labels_in(text::AbstractString) = [t for t in LABEL_TOKENS if occursin(t, text)]

"""`solve_failed:<STATUS>` when the log shows a failed/almost solve, else `solved`."""
function solve_label(text::AbstractString)
    hits = [(first(findfirst(t, text)), t) for t in STATUS_TOKENS if occursin(t, text)]
    if !isempty(hits)
        return "solve_failed:" * last(minimum(hits))
    end
    occursin("SolveFailedError", text) && return "solve_failed:UNKNOWN"
    return "solved"
end

"""Outcome precedence: fail/error > broken > pass."""
function outcome_of(fails::Integer, errors::Integer, broken::Integer)
    errors > 0 && return "error"
    fails > 0 && return "fail"
    broken > 0 && return "broken"
    return "pass"
end

const CSV_HEADER = "timestamp,mode,target,repeat,julia_version,outcome,passes,fails,errors,broken,secs,solve_label,labels"

csvfield(s) = occursin(r"[,\"\n]", s) ? "\"" * replace(s, "\"" => "\"\"") * "\"" : s

function csv_row(r)
    return join(
        csvfield.(
            string.([
                r.timestamp, r.mode, r.target, r.repeat, r.version, r.outcome, r.passes,
                r.fails, r.errors, r.broken, @sprintf("%.1f", r.secs), r.solve_label,
                join(r.labels, "|"),
            ])
        ),
        ",",
    )
end

"""Parse the single machine-readable child line out of a child log; `nothing` if absent."""
function parse_child_line(text::AbstractString)
    m = match(
        r"^FLAKE_RESULT target=(\S+) outcome=(\S+) passes=(\d+) fails=(\d+) errors=(\d+) broken=(\d+) secs=([\d.]+) version=(\S+)$"m,
        text,
    )
    m === nothing && return nothing
    return (
        target = m[1], outcome = m[2], passes = parse(Int, m[3]), fails = parse(Int, m[4]),
        errors = parse(Int, m[5]), broken = parse(Int, m[6]), secs = parse(Float64, m[7]),
        version = m[8],
    )
end

"""Findings text per (target, version, mode) for a vector of row NamedTuples."""
function findings_text(rows, stamp)
    io = IOBuffer()
    println(io, "== flake_rate run $stamp ==")
    keys_ = unique((r.target, r.version, r.mode) for r in rows)
    for (tg, ver, mode) in keys_
        rs = [r for r in rows if r.target == tg && r.version == ver && r.mode == mode]
        n = length(rs)
        np = count(r -> r.outcome == "pass", rs)
        hist = Dict{String,Int}()
        for r in rs, l in r.labels
            hist[l] = get(hist, l, 0) + 1
        end
        nsf = count(r -> r.solve_label != "solved", rs)
        histtxt = isempty(hist) ? "none" : join(("$k=$v" for (k, v) in sort!(collect(hist))), " ")
        @printf(
            io, "%s [julia %s, %s]: n=%d pass=%d rate=%.3f solve_failed=%d labels: %s\n",
            tg, ver, mode, n, np, np / max(n, 1), nsf, histtxt
        )
    end
    return String(take!(io))
end

function selftest()
    bad = "x\nSolveFailedError: ... ALMOST_OPTIMAL\nConvergenceError: foo\n"
    clean = "all fine\nTest Summary: pass\n"
    @assert labels_in(bad) == ["ALMOST_OPTIMAL", "ConvergenceError", "SolveFailedError"]
    @assert labels_in(clean) == String[]
    @assert solve_label(bad) == "solve_failed:ALMOST_OPTIMAL"
    @assert solve_label("SolveFailedError only") == "solve_failed:UNKNOWN"
    @assert solve_label("a NUMERICAL_ERROR then ALMOST_OPTIMAL") == "solve_failed:NUMERICAL_ERROR"
    @assert solve_label(clean) == "solved"
    @assert outcome_of(0, 0, 0) == "pass" && outcome_of(0, 0, 1) == "broken"
    @assert outcome_of(1, 0, 1) == "fail" && outcome_of(0, 1, 1) == "error"
    line = "noise\nFLAKE_RESULT target=fit_baseline outcome=broken passes=9 fails=0 errors=0 broken=1 secs=12.5 version=1.12.5\n"
    p = parse_child_line(line)
    @assert p.outcome == "broken" && p.passes == 9 && p.version == "1.12.5"
    @assert parse_child_line(clean) === nothing
    r = (
        timestamp = "t", mode = "fresh", target = "fit_baseline", repeat = 1, version = "1.12.5",
        outcome = "pass", passes = 3, fails = 0, errors = 0, broken = 0, secs = 1.0,
        solve_label = solve_label(bad), labels = labels_in(bad),
    )
    row = csv_row(r)
    @assert count(==(','), row) == count(==(','), CSV_HEADER)
    @assert endswith(row, "ALMOST_OPTIMAL|ConvergenceError|SolveFailedError")
    f = findings_text([r], "stamp")
    @assert occursin("fit_baseline [julia 1.12.5, fresh]: n=1 pass=1 rate=1.000 solve_failed=1", f)
    println("flake_rate selftest OK")
    return nothing
end

# ----------------------------------------------------------------------------------------
# Item selection and child execution
# ----------------------------------------------------------------------------------------

function target_specs(target)
    haskey(TARGETS, target) || error("unknown target $(repr(target)); choose from $(TARGET_ORDER)")
    file, names, prefix = TARGETS[target]
    specs = [(file, n, "") for n in names]
    isempty(prefix) || push!(specs, (file, "", prefix))
    target == "ieee13_admm" && push!(specs, (ADMM_CROSSVAL[1], ADMM_CROSSVAL[2], ""))
    return specs
end

"""Hard error unless every spec's item name (or prefix) really appears in its test file."""
function verify_targets(targets)
    for t in targets, (file, name, prefix) in target_specs(t)
        text = read(joinpath(ROOT, "test", file), String)
        needle = isempty(name) ? "@testitem \"" * prefix : "@testitem \"" * name * "\""
        occursin(needle, text) ||
            error("target $t: item $(repr(isempty(name) ? prefix : name)) not found in test/$file")
    end
end

function item_filter(target)
    specs = target_specs(target)
    return ti -> any(specs) do (file, name, prefix)
        basename(ti.filename) == file &&
            (isempty(name) ? startswith(ti.name, prefix) : ti.name == name)
    end
end

"""Run a target's items once in THIS process; returns the result NamedTuple."""
function run_items(target)
    Core.eval(Main, :(using TestItemRunner))
    return Base.invokelatest(_run_items, target)
end

function _run_items(target)
    TIR = getfield(Main, :TestItemRunner)
    filt = item_filter(target)
    ts_ref = Ref{Any}(nothing)
    t0 = time()
    try
        Test.@testset "flake_rate" begin
            ts_ref[] = Test.get_testset()
            TIR.run_tests(joinpath(ROOT, "test"); filter = filt)
        end
    catch e
        e isa Test.TestSetException || rethrow()
    end
    secs = time() - t0
    c = Test.get_test_counts(ts_ref[])
    return (
        passes = c.passes + c.cumulative_passes,
        fails = c.fails + c.cumulative_fails,
        errors = c.errors + c.cumulative_errors,
        broken = c.broken + c.cumulative_broken,
        secs = secs,
    )
end

function child_main(target)
    r = run_items(target)
    outcome = outcome_of(r.fails, r.errors, r.broken)
    @printf(
        "FLAKE_RESULT target=%s outcome=%s passes=%d fails=%d errors=%d broken=%d secs=%.1f version=%s\n",
        target, outcome, r.passes, r.fails, r.errors, r.broken, r.secs, string(VERSION)
    )
    return nothing
end

function spawn_child(target, log)
    env = copy(ENV)
    env["JULIA_LOAD_PATH"] = "@:" * joinpath(ROOT, "test") * ":@stdlib"
    script = joinpath(ROOT, "scripts", "flake_rate.jl")
    cmd = `$(Base.julia_cmd()) --project=$ROOT -t2 $script --child $target`
    return run(pipeline(setenv(cmd, env); stdout = log, stderr = log); wait = false)
end

function other_julia_running()
    pids = try
        parse.(Int, split(read(`pgrep -x julia`, String)))
    catch
        Int[]
    end
    me = getpid()
    ppid = Int(ccall(:getppid, Cint, ()))
    return [p for p in pids if p != me && p != ppid]
end

function row_from(mode, target, i, stamp, parsed, log_text)
    return (
        timestamp = stamp, mode = mode, target = target, repeat = i,
        version = parsed === nothing ? string(VERSION) : parsed.version,
        outcome = parsed === nothing ? "error" : parsed.outcome,
        passes = parsed === nothing ? 0 : parsed.passes,
        fails = parsed === nothing ? 0 : parsed.fails,
        errors = parsed === nothing ? 1 : parsed.errors,
        broken = parsed === nothing ? 0 : parsed.broken,
        secs = parsed === nothing ? 0.0 : parsed.secs,
        solve_label = solve_label(log_text), labels = labels_in(log_text),
    )
end

function parent_main(args)
    getopt(flag, default) = (i = findfirst(==(flag), args); i === nothing ? default : args[i+1])
    repeats = parse(Int, getopt("--repeats", "20"))
    jobs = parse(Int, getopt("--jobs", "1"))
    inproc = parse(Int, getopt("--inprocess", "0"))
    targets = String.(split(getopt("--targets", join(TARGET_ORDER, ",")), ","))
    outdir = getopt("--outdir", joinpath("results", "flake_rate"))
    isabspath(outdir) || (outdir = joinpath(pwd(), outdir))
    verify_targets(targets)
    if !("--force" in args)
        others = other_julia_running()
        isempty(others) || error(
            "another julia process is running (pids $(others)); refusing to start (use --force to override)",
        )
    end
    mkpath(outdir)
    stamp = Dates.format(now(UTC), "yyyymmddTHHMMSS")
    scratch = mktempdir()
    rows = NamedTuple[]
    lock_ = ReentrantLock()
    work = [(t, i) for t in targets for i in 1:repeats]
    sem = Base.Semaphore(max(jobs, 1))
    @sync for (t, i) in work
        @async begin
            Base.acquire(sem)
            try
                log = joinpath(scratch, "$(t)_$(i).log")
                p = spawn_child(t, log)
                wait(p)
                text = read(log, String)
                row = row_from("fresh", t, i, stamp, parse_child_line(text), text)
                lock(() -> push!(rows, row), lock_)
                println("[$t #$i] outcome=$(row.outcome) solve=$(row.solve_label)")
            finally
                Base.release(sem)
            end
        end
    end
    for t in targets, i in 1:inproc
        log = joinpath(scratch, "$(t)_inproc_$(i).log")
        local r
        open(log, "w") do io
            redirect_stdout(io) do
                redirect_stderr(io) do
                    r = run_items(t)
                end
            end
        end
        text = read(log, String)
        parsed = (
            target = t, outcome = outcome_of(r.fails, r.errors, r.broken), passes = r.passes,
            fails = r.fails, errors = r.errors, broken = r.broken, secs = r.secs,
            version = string(VERSION),
        )
        push!(rows, row_from("inprocess", t, i, stamp, parsed, text))
    end
    sort!(rows; by = r -> (r.mode, r.target, r.repeat))
    csv = joinpath(outdir, "$(stamp)_$(VERSION).csv")
    open(csv, "w") do io
        println(io, CSV_HEADER)
        foreach(r -> println(io, csv_row(r)), rows)
    end
    txt = findings_text(rows, stamp)
    open(joinpath(outdir, "findings.txt"), "a") do io
        print(io, txt)
    end
    print(txt)
    println("wrote $csv")
    return nothing
end

function main(args)
    if "--selftest" in args
        selftest()
    elseif (i = findfirst(==("--child"), args)) !== nothing
        child_main(args[i+1])
    else
        parent_main(args)
    end
    return nothing
end

abspath(PROGRAM_FILE) == (@__FILE__) && main(ARGS)

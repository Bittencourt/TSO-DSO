# JET ratchet check: static inference reports of TSODSO must equal the committed baseline.
#
# Usage (Julia 1.12 only, JET from the test environment):
#   JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +1.12 --project=. -t2 scripts/jet_check.jl
#   ... scripts/jet_check.jl --update            rewrite the baseline from the current reports
#   ... scripts/jet_check.jl --baseline PATH     use another baseline file (check or --update)
#   julia --project=. scripts/jet_check.jl --selftest   logic test, no JET analysis, any Julia
#
# Each report is reduced to a normalized signature `kind | function | file | message head`
# (no line numbers, `#name#NNN` gensyms stripped, duplicates collapsed). The check fails when
# a current signature is missing from the baseline (NEW) or a baseline signature is no longer
# reported (FIXED: remove it from the baseline so the ratchet only tightens).
# The report accessors used here (`print_report_message`, `vst`, `get_reports`) are JET
# internals pinned by the test manifest (JET 0.11.x).
# Exit: 0 clean, 1 differences, 2 unsupported Julia / usage error.

const BASELINE_DEFAULT = joinpath(@__DIR__, "jet_baseline.txt")
const UNJUSTIFIED_MARK = "# UNJUSTIFIED (new signatures: add a justification or fix the code)"

"""Pure string-level normalization of one report into its signature."""
function normalize_signature(kind::AbstractString, fn::AbstractString, file::AbstractString,
                             msg::AbstractString)
    fn2 = replace(String(fn), r"\.#(.*)#\d+$" => s".\1")
    fn2 = replace(fn2, r"#\d+" => "")
    m = replace(String(msg), r"\s+" => " ")
    head = first(split(m, r"\): |:\s+(?=[A-Za-z@_#])"; limit = 2))
    return string(kind, " | ", fn2, " | ", basename(String(file)), " | ", strip(String(head)))
end

"""Signatures of the current JET reports for TSODSO (needs JET and TSODSO loaded in Main)."""
function current_signatures()
    JET = Base.invokelatest(getfield, Main, :JET)
    TSODSO = Base.invokelatest(getfield, Main, :TSODSO)
    rep = Base.invokelatest(JET.report_package, TSODSO; target_modules = (TSODSO,))
    sigs = String[]
    for r in Base.invokelatest(JET.get_reports, rep)
        kind = string(nameof(typeof(r)))
        fr = r.vst[end]
        mi = fr.linfo
        fn = string(mi.def.module, ".", mi.def.name)
        io = IOBuffer()
        Base.invokelatest(JET.print_report_message, io, r)
        push!(sigs, normalize_signature(kind, fn, string(fr.file), String(take!(io))))
    end
    return sort!(unique(sigs))
end

"""Signature lines of a baseline file (blank and `#` lines ignored)."""
function parse_baseline(lines)
    out = String[]
    for l in lines
        s = strip(l)
        (isempty(s) || startswith(s, "#")) && continue
        push!(out, String(s))
    end
    return out
end

read_baseline(path) = isfile(path) ? parse_baseline(readlines(path)) : String[]

"""`(new, fixed)`: current-minus-baseline and baseline-minus-current, both sorted."""
function diff_signatures(current, baseline)
    c, b = Set(current), Set(baseline)
    return sort!(collect(setdiff(c, b))), sort!(collect(setdiff(b, c)))
end

"""Header (leading `#`/blank lines) plus justification groups of an existing baseline file.

Returns `(lines_out)`: comment/justification lines are kept in place, signature lines still
current are kept in their group, vanished ones dropped, new ones appended under the
UNJUSTIFIED marker."""
function rewrite_baseline_lines(old_lines, current)
    cur = Set(current)
    kept = Set{String}()
    out = String[]
    in_unjust = false
    for l in old_lines
        s = strip(l)
        if s == UNJUSTIFIED_MARK
            in_unjust = true
            continue
        end
        if isempty(s) || startswith(s, "#")
            push!(out, String(l))
        elseif s in cur && !in_unjust
            push!(out, String(s))
            push!(kept, String(s))
        end
    end
    newsigs = sort!(collect(setdiff(cur, kept)))
    if !isempty(newsigs)
        while !isempty(out) && isempty(strip(out[end]))
            pop!(out)
        end
        push!(out, "")
        push!(out, UNJUSTIFIED_MARK)
        append!(out, newsigs)
    end
    return out
end

function write_baseline(path, current)
    old = isfile(path) ? readlines(path) : String[]
    out = rewrite_baseline_lines(old, current)
    if isempty(old)
        out = String[
            "# JET baseline: normalized signatures `kind | function | file | message head`.",
            "# Fixed reports must be removed from this file (the check fails on stale entries).",
            "# Header versions: JET $(jet_version_string()), Julia $(VERSION)",
        ]
        append!(out, ["", UNJUSTIFIED_MARK], current)
    end
    open(io -> foreach(l -> println(io, l), out), path, "w")
    return nothing
end

jet_version_string() = try
    string(pkgversion(Base.invokelatest(getfield, Main, :JET)))
catch
    "unknown"
end

"""Warn when the baseline header states other JET/Julia versions than the running ones."""
function version_warning(path)
    isfile(path) || return nothing
    for l in readlines(path)
        m = match(r"^# Header versions: JET (\S+), Julia (\S+)", l)
        m === nothing && continue
        if m.captures[1] != jet_version_string() || m.captures[2] != string(VERSION)
            println("WARNING: baseline recorded with JET $(m.captures[1]) / Julia ",
                    "$(m.captures[2]); running JET $(jet_version_string()) / Julia $VERSION")
        end
    end
    return nothing
end

function selftest()
    failures = String[]
    chk(c, msg) = c || push!(failures, msg)
    # normalize: line numbers and gensym counters do not matter, messages do
    a = normalize_signature("UndefVarErrorReport", "TSODSO.#f#779", "/x/y/DsoOpt.jl",
                            "`qag_dso` is not defined")
    b = normalize_signature("UndefVarErrorReport", "TSODSO.#f#12", "/other/DsoOpt.jl",
                            "`qag_dso`  is\n not defined")
    c = normalize_signature("UndefVarErrorReport", "TSODSO.f", "DsoOpt.jl", "`other` is not defined")
    chk(a == b, "gensym/whitespace normalization differs: $a vs $b")
    chk(a != c, "different messages must differ")
    chk(!occursin(r"#\d", a) && !occursin("/", a), "signature keeps gensym or path: $a")
    h = normalize_signature("MethodErrorReport", "TSODSO.g", "z.jl",
                            "no matching method found for call signature (Tuple{typeof(f), Int}): f(x::Int)")
    chk(!occursin("f(x::Int)", h), "printed-expression tail not dropped: $h")
    # diff
    new, fixed = diff_signatures(["a", "b"], ["b", "c"])
    chk(new == ["a"] && fixed == ["c"], "diff wrong: $new $fixed")
    n2, f2 = diff_signatures(["a", "b", "a"], ["b", "a"])
    chk(isempty(n2) && isempty(f2), "equal sets must give empty diff")
    # baseline parse
    chk(parse_baseline(["# c", "", "  x  ", "#y", "z"]) == ["x", "z"], "baseline parse wrong")
    # update: preserves comments and justification, drops fixed, marks new
    old = ["# header", "# justification A", "keep", "gone", "", "# justification B", "keep2"]
    r = rewrite_baseline_lines(old, ["keep", "keep2", "fresh"])
    chk(r[1:2] == ["# header", "# justification A"], "comments not preserved")
    chk("gone" ∉ r && "keep" in r && "keep2" in r, "fixed/kept handling wrong")
    ui = findfirst(==(UNJUSTIFIED_MARK), r)
    chk(ui !== nothing && r[ui+1] == "fresh", "new signature not under UNJUSTIFIED marker")
    r2 = rewrite_baseline_lines(r, ["keep", "keep2", "fresh"])
    chk(UNJUSTIFIED_MARK in r2 && "fresh" in r2, "rerun must keep unjustified entry")
    foreach(f -> println("SELFTEST FAIL: ", f), failures)
    isempty(failures) && println("selftest OK: normalize, diff, baseline parse/rewrite")
    return isempty(failures)
end

function main(args)
    "--selftest" in args && return selftest() ? 0 : 1
    if !(VERSION >= v"1.12" && VERSION < v"1.13")
        println(stderr, "jet_check.jl: needs Julia 1.12.x (running $VERSION); JET is pinned for 1.12 only")
        return 2
    end
    path = BASELINE_DEFAULT
    i = findfirst(==("--baseline"), args)
    if i !== nothing
        i < length(args) || (println(stderr, "--baseline needs a PATH"); return 2)
        path = abspath(args[i+1])
    end
    Core.eval(Main, :(using JET, TSODSO))
    cur = current_signatures()
    if "--update" in args
        write_baseline(path, cur)
        println("jet_check: wrote $(length(cur)) signatures to $path")
        return 0
    end
    version_warning(path)
    base = read_baseline(path)
    new, fixed = diff_signatures(cur, base)
    println("jet_check: $(length(cur)) current, $(length(base)) baseline, ",
            "$(length(new)) NEW, $(length(fixed)) FIXED")
    if !isempty(new)
        println("NEW signatures (fix the code, or add to the baseline with a justification):")
        foreach(s -> println("  + ", s), new)
    end
    if !isempty(fixed)
        println("FIXED signatures (no longer reported: remove them from the baseline):")
        foreach(s -> println("  - ", s), fixed)
    end
    if isfile(path) && any(==(UNJUSTIFIED_MARK), strip.(readlines(path)))
        println("WARNING: baseline still contains UNJUSTIFIED entries")
    end
    return (isempty(new) && isempty(fixed)) ? 0 : 1
end

exit(main(ARGS))

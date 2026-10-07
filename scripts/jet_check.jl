# JET ratchet check: static inference reports of TSODSO must equal the committed baseline.
#
# Usage (Julia 1.12 only, JET from the test environment):
#   JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +1.12 --project=. -t2 scripts/jet_check.jl
#   ... scripts/jet_check.jl --update            rewrite the baseline from the current reports
#   ... scripts/jet_check.jl --baseline PATH     use another baseline file (check or --update)
#   julia --project=. scripts/jet_check.jl --selftest   logic test, no JET analysis, any Julia
#
# Each report is reduced to a normalized signature `kind | function | file | message head`
# (no line numbers, `#name#NNN` gensyms stripped). Signatures are compared as MULTISETS: a
# signature listed k times in the baseline allows exactly k current reports with that
# signature, so a second report that normalizes to an already-baselined signature is NEW.
# The check fails when the current count of a signature exceeds its baseline count (NEW), when
# it is lower (FIXED: remove the surplus line(s) so the ratchet only tightens), or when the
# baseline still contains the UNJUSTIFIED marker (every entry must sit in a justified group).
# The report accessors used here (`print_report_message`, `vst`, `get_reports`) are JET
# internals pinned by the test manifest (JET 0.11.x). Signatures embed inferred type strings,
# so the CI job pins the exact Julia patch recorded in the baseline header; bump both together.
# Exit (check): 0 clean; 1 NEW/FIXED differences or UNJUSTIFIED entries; 2 unsupported Julia /
#   usage error.
# Exit (--update): 0 when the rewritten baseline has no UNJUSTIFIED entries; 1 when it does
#   (the file IS written; move those lines into a justified group, or fix the code, before
#   committing, since the check would fail on them).

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
    return sort!(sigs)  # duplicates kept: the ratchet compares multisets
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

"""Multiset of signatures: `Dict(signature => count)`."""
function countmap_sigs(sigs)
    d = Dict{String,Int}()
    for s in sigs
        d[String(s)] = get(d, String(s), 0) + 1
    end
    return d
end

"""`(new, fixed)` as MULTISET differences (current-minus-baseline and baseline-minus-current):
a signature appears once per surplus occurrence. Both sorted."""
function diff_signatures(current, baseline)
    c, b = countmap_sigs(current), countmap_sigs(baseline)
    new, fixed = String[], String[]
    for (s, n) in c
        append!(new, fill(s, max(n - get(b, s, 0), 0)))
    end
    for (s, n) in b
        append!(fixed, fill(s, max(n - get(c, s, 0), 0)))
    end
    return sort!(new), sort!(fixed)
end

"""True iff the baseline lines contain the UNJUSTIFIED marker."""
has_unjustified(lines) = any(l -> strip(l) == UNJUSTIFIED_MARK, lines)

"""Header (leading `#`/blank lines) plus justification groups of an existing baseline file.

Returns `(lines_out)`: comment/justification lines are kept in place, signature lines still
current are kept in their group (one baseline line per current occurrence; surplus lines of a
signature whose count dropped are removed), vanished ones dropped, and the remaining current
occurrences appended under the UNJUSTIFIED marker. Signature lines directly under the marker
are not kept in place (they are re-appended under a fresh marker); a `#` comment line after
the marker ends the unjustified block, so a group justified below the marker keeps its lines."""
function rewrite_baseline_lines(old_lines, current)
    left = countmap_sigs(current)
    out = String[]
    in_unjust = false
    for l in old_lines
        s = strip(l)
        if s == UNJUSTIFIED_MARK
            in_unjust = true
            continue
        end
        if startswith(s, "#")
            in_unjust = false
            push!(out, String(l))
        elseif isempty(s)
            push!(out, String(l))
        elseif !in_unjust && get(left, s, 0) > 0
            push!(out, String(s))
            left[String(s)] -= 1
        end
    end
    newsigs = sort!(reduce(vcat, [fill(s, n) for (s, n) in left]; init = String[]))
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
    n2, f2 = diff_signatures(["a", "b", "a"], ["b", "a", "a"])
    chk(isempty(n2) && isempty(f2), "equal multisets must give empty diff")
    # multiplicity: a duplicate of a baselined signature is NEW; a dropped duplicate is FIXED
    n3, f3 = diff_signatures(["a", "b", "a"], ["b", "a"])
    chk(n3 == ["a"] && isempty(f3), "duplicate current report not NEW: $n3 $f3")
    n4, f4 = diff_signatures(["a"], ["a", "a"])
    chk(isempty(n4) && f4 == ["a"], "dropped duplicate not FIXED: $n4 $f4")
    chk(has_unjustified(["x", "  " * UNJUSTIFIED_MARK]) && !has_unjustified(["x", "# y"]),
        "unjustified marker detection wrong")
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
    # multiset update: a second occurrence is appended as unjustified; a dropped one removed
    r3 = rewrite_baseline_lines(["# g", "keep", "keep"], ["keep", "keep", "keep"])
    chk(count(==("keep"), r3) == 3 && r3[end] == "keep" && UNJUSTIFIED_MARK in r3,
        "extra occurrence not appended as unjustified: $r3")
    r4 = rewrite_baseline_lines(["# g", "keep", "keep"], ["keep"])
    chk(count(==("keep"), r4) == 1 && !(UNJUSTIFIED_MARK in r4), "surplus line not dropped: $r4")
    # a group justified BELOW the marker (marker left in place) keeps its lines
    r5 = rewrite_baseline_lines(["# g", "keep", UNJUSTIFIED_MARK, "# Group 9: why", "late"],
                                ["keep", "late"])
    chk(r5 == ["# g", "keep", "# Group 9: why", "late"], "justified-below-marker group lost: $r5")
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
        if has_unjustified(readlines(path))
            println("UNJUSTIFIED entries written: move them into a justified group (or fix the ",
                    "code) before committing; exit 1")
            return 1
        end
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
    unjust = isfile(path) && has_unjustified(readlines(path))
    if unjust
        println("FAIL: baseline contains UNJUSTIFIED entries (justify each in a group, or fix ",
                "the code)")
    end
    return (isempty(new) && isempty(fixed) && !unjust) ? 0 : 1
end

exit(main(ARGS))

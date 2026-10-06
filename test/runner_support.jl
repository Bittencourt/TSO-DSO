# Shared support for test/runtests.jl, scripts/run_tests_filtered.jl and the flake harness.
# Plain code (no @testitem): selection predicate, Broken-record walker, allowed-list parser.
using Test

const TEST_SETS = ("fast", "slow", "all")

"""Read `TSODSO_TEST_SET` (unset or empty = "all"); any other value than fast|slow|all throws."""
function test_set_from_env()
    s = get(ENV, "TSODSO_TEST_SET", "")
    isempty(s) && return "all"
    s in TEST_SETS ||
        throw(ErrorException("TSODSO_TEST_SET=$(repr(s)) invalid; allowed values: fast|slow|all"))
    return s
end

"""Optional basename restriction from `TSODSO_TEST_FILES` (comma-separated); empty = none."""
function test_files_from_env()
    s = get(ENV, "TSODSO_TEST_FILES", "")
    return isempty(s) ? String[] : String.(split(s, ","))
end

_under(file::AbstractString, dir::AbstractString) =
    startswith(normpath(file), rstrip(normpath(dir), '/') * "/")

"""Select `ti` iff its file lies under `test_dir` and matches the set (and file restriction)."""
function tso_selected(ti, set::AbstractString, test_dir::AbstractString;
                      files::Vector{String} = test_files_from_env())
    _under(ti.filename, test_dir) || return false
    isempty(files) || basename(ti.filename) in files || return false
    set == "all" && return true
    return (set == "slow") == (:slow in ti.tags)
end

"""Recursively collect every `Test.Broken` as `(; where, path, kind, expr)`."""
function broken_records(ts, path::Vector{String} = String[])
    out = NamedTuple[]
    p = vcat(path, ts.description)
    for r in ts.results
        if r isa Test.Broken
            push!(out, (; where = join(p, " / "), path = p, kind = r.test_type === :skipped ? "skipped" : "broken", expr = r.orig_expr))
        elseif r isa Test.DefaultTestSet
            append!(out, broken_records(r, p))
        end
    end
    return out
end

"""Parse expected_broken.txt into a set of `(kind, item name)` pairs."""
function read_expected_broken(path::AbstractString)
    out = Set{Tuple{String,String}}()
    for line in eachline(path)
        l = strip(line)
        (isempty(l) || startswith(l, "#")) && continue
        parts = strip.(split(l, "|"; limit = 3))
        length(parts) == 3 || error("bad expected_broken line: $(repr(line))")
        parts[1] in ("broken", "skipped") || error("bad kind in expected_broken line: $(repr(line))")
        push!(out, (String(parts[1]), String(parts[2])))
    end
    return out
end

"""True iff the record's path contains an item name allowed for its kind."""
is_allowed(rec, allowed) = any(n -> (rec.kind, n) in allowed, rec.path)

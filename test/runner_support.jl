# Shared support for test/runtests.jl, scripts/run_tests_filtered.jl and the flake harness.
# Plain code (no @testitem): selection predicate, Broken-record walker, allowed-list parser.
using Test

const TEST_SETS = ("fast", "slow", "all")

"""
Read `TSODSO_TEST_SET` (unset or empty = "all"); any other value than fast|slow|all throws.
"""
function test_set_from_env()
    s = get(ENV, "TSODSO_TEST_SET", "")
    isempty(s) && return "all"
    s in TEST_SETS || throw(
        ErrorException("TSODSO_TEST_SET=$(repr(s)) invalid; allowed values: fast|slow|all"),
    )
    return s
end

"""
Optional basename restriction from `TSODSO_TEST_FILES` (comma-separated, entries trimmed);
empty = none. An empty entry (e.g. a trailing comma) throws. Callers must also fail when a
requested name matches no item (see `unmatched_files`).
"""
function test_files_from_env()
    s = get(ENV, "TSODSO_TEST_FILES", "")
    isempty(strip(s)) && return String[]
    files = String.(strip.(split(s, ",")))
    any(isempty, files) && throw(
        ErrorException("TSODSO_TEST_FILES=$(repr(s)) has an empty entry; use a.jl,b.jl"),
    )
    return files
end

"""
Requested file names (from `TSODSO_TEST_FILES`) whose hit count is zero, i.e. names none of
whose `@testitem`s under test/ is selected by the active set (a typo, a renamed file, or a file
whose items are all outside `TSODSO_TEST_SET`).
"""
unmatched_files(hits::AbstractDict) = sort!([f for (f, n) in hits if n == 0])

_under(file::AbstractString, dir::AbstractString) =
    startswith(normpath(file), rstrip(normpath(dir), '/') * "/")

"""
Select `ti` iff its file lies under `test_dir` and matches the set (and file restriction).
"""
function tso_selected(
    ti,
    set::AbstractString,
    test_dir::AbstractString;
    files::Vector{String} = test_files_from_env(),
)
    _under(ti.filename, test_dir) || return false
    isempty(files) || basename(ti.filename) in files || return false
    set == "all" && return true
    return (set == "slow") == (:slow in ti.tags)
end

"""
    item_index(path) -> Union{Int, Nothing}

Position of the `@testitem` testset in a Broken record's testset `path`, found structurally
rather than at a fixed depth: the item is the child of the first testset below the root whose
description ends in `.jl` (the per-file testset). This does not depend on the TestItemRunner
version's layout: 1.1.5 (resolved by test/Manifest.toml, Julia 1.12) names each file testset
by its path relative to test/ under a flat `TSODSO / Package / <file> / <item>`, while 1.3.x
(what `Pkg.test` re-resolves to on Julia 1.10, where that manifest is not used) builds a
directory tree (`... / <dir> / <file> / <item>`, or a collapsed `<dir>/<file>`), which puts
the item one level deeper when test/ has a subdirectory with several files. Returns `nothing`
for a record above item level (no file component, or nothing below it).
"""
function item_index(path::AbstractVector{<:AbstractString})
    for i in 2:(length(path) - 1)
        endswith(path[i], ".jl") && return i + 1
    end
    return nothing
end

"""
Recursively collect every `Test.Broken` as `(; where, path, kind, expr)`.
"""
function broken_records(ts, path::Vector{String} = String[])
    out = NamedTuple[]
    p = vcat(path, ts.description)
    for r in ts.results
        if r isa Test.Broken
            push!(
                out,
                (;
                    where = join(p, " / "),
                    path = p,
                    kind = r.test_type === :skipped ? "skipped" : "broken",
                    expr = r.orig_expr,
                ),
            )
        elseif r isa Test.DefaultTestSet
            append!(out, broken_records(r, p))
        end
    end
    return out
end

"""
Identity of one Broken/skipped record: `(kind, item, test)`. `item` is the `@testitem` name
(the path component at `item_depth`, by default located by [`item_index`](@ref); "" when the
record sits above item level) and `test` is the printed test expression, prefixed by any
nested `@testset` names below the item (`nested / ... / expr`).
"""
function record_key(rec; item_depth::Union{Int, Nothing} = item_index(rec.path))
    item_depth === nothing && return (rec.kind, "", string(rec.expr))
    item = length(rec.path) >= item_depth ? rec.path[item_depth] : ""
    nested = length(rec.path) > item_depth ? rec.path[(item_depth + 1):end] : String[]
    test = join(vcat(nested, [string(rec.expr)]), " / ")
    return (rec.kind, item, test)
end

"""
Parse expected_broken.txt (`kind | item | test | reason`, fields separated by " | ") into a
multiset `Dict((kind, item, test) => allowed count)`. Listing the same
`(kind, item, test)` on k lines allows k such records in one run.
"""
function read_expected_broken(path::AbstractString)
    out = Dict{Tuple{String, String, String}, Int}()
    for line in eachline(path)
        l = strip(line)
        (isempty(l) || startswith(l, "#")) && continue
        parts = strip.(split(l, " | "; limit = 4))
        (length(parts) == 4 && all(!isempty, parts[1:3])) || error(
            "bad expected_broken line (need kind | item | test | reason): $(repr(line))",
        )
        parts[1] in ("broken", "skipped") ||
            error("bad kind in expected_broken line: $(repr(line))")
        k = (String(parts[1]), String(parts[2]), String(parts[3]))
        out[k] = get(out, k, 0) + 1
    end
    return out
end

"""
Records not covered by the allowed multiset: each record consumes one allowance for its
exact `(kind, item, test)` key; a record with no allowance left is returned. So a NEW
`@test_broken` (or `broken=` / `@test_skip`) inside an allowed item, a second firing of an
allowed site beyond its listed count, or a record in a nested testset all fail.
"""
function unexpected_records(recs, allowed::AbstractDict)
    left = Dict(allowed)
    bad = eltype(recs)[]
    for r in recs
        k = record_key(r)
        n = get(left, k, 0)
        if n > 0
            left[k] = n - 1
        else
            push!(bad, r)
        end
    end
    return bad
end

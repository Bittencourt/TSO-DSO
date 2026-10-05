# Runner for TestItemRunner with tag/file filters (avoids the `julia -e` trap).
# Usage: julia -t2 scripts/run_tests_filtered.jl <abs-repo-root> SPEC [SPEC...]
#        julia scripts/run_tests_filtered.jl <abs-repo-root> --selftest
#   SPEC = tag:<sym> | file:<basename>[,<basename>...]   (several specs are OR-combined)
# Fails closed: a malformed SPEC, or ANY spec / comma-separated file name that selects zero
# @testitems (e.g. a renamed tag or file), is an error rather than a vacuous green run. Dead
# filters are detected by a discovery-only preflight, before any test item runs.
using TestItemRunner

const SPEC_USAGE = "filter spec must be tag:<sym> or file:<a.jl[,b.jl]>"

"""Parse one SPEC into its atomic filters: `[(label, predicate), ...]` (one per file name)."""
function parse_spec(s::AbstractString)
    occursin(':', s) || error("$SPEC_USAGE, got $(repr(s))")
    kind, val = split(s, ":"; limit = 2)
    isempty(val) && error("$SPEC_USAGE, got $(repr(s)) (empty value)")
    if kind == "tag"
        tag = Symbol(val)
        return [("tag:$val", ti -> tag in ti.tags)]
    elseif kind == "file"
        files = split(val, ",")
        any(isempty, files) && error("$SPEC_USAGE, got $(repr(s)) (empty file name)")
        return [("file:$f", ti -> basename(ti.filename) == f) for f in files]
    else
        error("$SPEC_USAGE, got $(repr(s))")
    end
end

function run_filtered(root, specs)
    isempty(specs) && error("$SPEC_USAGE, got none")
    atoms = reduce(vcat, map(parse_spec, specs))
    testdir = joinpath(root, "test")
    # Preflight: count matches per atomic filter without running anything.
    counts = zeros(Int, length(atoms))
    TestItemRunner.run_tests(testdir; filter = function (ti)
        for (i, (_, p)) in enumerate(atoms)
            p(ti) && (counts[i] += 1)
        end
        return false
    end)
    dead = [atoms[i][1] for i in eachindex(atoms) if counts[i] == 0]
    isempty(dead) ||
        error("no @testitem matched $(join(dead, " ")) (fail-closed: check tag/file names)")
    nmatch = Ref(0)
    filt = function (ti)
        m = any(a -> a[2](ti), atoms)
        m && (nmatch[] += 1)
        return m
    end
    TestItemRunner.run_tests(testdir; filter = filt)
    println("run_tests_filtered: $(nmatch[]) @testitem(s) selected by $(join(specs, " "))")
    return nmatch[]
end

function selftest(root)
    failures = String[]
    for bad in ("tagphase7", "tag:", "suite:x", "", "file:a.jl,", "file:,a.jl")
        try
            parse_spec(bad)
            push!(failures, "malformed spec $(repr(bad)) was accepted")
        catch e
            e isa ErrorException || push!(failures, "malformed spec $(repr(bad)) raised $(typeof(e))")
        end
    end
    zero_err = try
        run_filtered(root, ["file:__no_such_test_file__.jl"])
        nothing
    catch e
        e
    end
    if !(zero_err isa ErrorException && occursin("no @testitem matched", zero_err.msg))
        push!(failures, "zero-match filter did not fail closed (got $(repr(zero_err)))")
    end
    # A dead filter must fail even when combined with a live one (preflight: nothing runs).
    for specs in (
        ["file:test_exports.jl", "file:__no_such_test_file__.jl"],
        ["file:test_exports.jl,__no_such_test_file__.jl"],
        ["file:test_exports.jl", "tag:__no_such_tag__"],
    )
        err = try
            run_filtered(root, specs)
            nothing
        catch e
            e
        end
        if !(err isa ErrorException && occursin("no @testitem matched", err.msg) &&
             occursin("__no_such", err.msg) && !occursin("test_exports.jl", err.msg))
            push!(failures, "dead filter in $(repr(specs)) did not fail closed (got $(repr(err)))")
        end
    end
    foreach(f -> println("SELFTEST FAIL: ", f), failures)
    isempty(failures) &&
        println("selftest OK: malformed specs rejected, zero-match and per-filter dead runs fail")
    return isempty(failures)
end

length(ARGS) >= 1 || error("usage: run_tests_filtered.jl <abs-repo-root> SPEC... | --selftest")
if length(ARGS) >= 2 && ARGS[2] == "--selftest"
    exit(selftest(ARGS[1]) ? 0 : 1)
end
run_filtered(ARGS[1], ARGS[2:end])

# Runner for TestItemRunner with tag/file filters (avoids the `julia -e` trap).
# Usage: julia -t2 scripts/run_tests_filtered.jl <abs-repo-root> SPEC [SPEC...]
#        julia scripts/run_tests_filtered.jl <abs-repo-root> --selftest
#   SPEC = tag:<sym> | file:<basename>[,<basename>...]   (several specs are OR-combined)
# Fails closed: a malformed SPEC, or SPECs that select zero @testitems (e.g. a renamed tag or
# file), is an error rather than a vacuous green run.
using TestItemRunner

const SPEC_USAGE = "filter spec must be tag:<sym> or file:<a.jl[,b.jl]>"

function parse_spec(s::AbstractString)
    occursin(':', s) || error("$SPEC_USAGE, got $(repr(s))")
    kind, val = split(s, ":"; limit = 2)
    isempty(val) && error("$SPEC_USAGE, got $(repr(s)) (empty value)")
    if kind == "tag"
        return ti -> Symbol(val) in ti.tags
    elseif kind == "file"
        files = split(val, ",")
        return ti -> basename(ti.filename) in files
    else
        error("$SPEC_USAGE, got $(repr(s))")
    end
end

function run_filtered(root, specs)
    isempty(specs) && error("$SPEC_USAGE, got none")
    preds = map(parse_spec, specs)
    nmatch = Ref(0)
    filt = function (ti)
        m = any(p -> p(ti), preds)
        m && (nmatch[] += 1)
        return m
    end
    TestItemRunner.run_tests(joinpath(root, "test"); filter = filt)
    nmatch[] == 0 && error("no @testitem matched $(join(specs, " ")) (fail-closed: check tag/file names)")
    println("run_tests_filtered: $(nmatch[]) @testitem(s) selected by $(join(specs, " "))")
    return nmatch[]
end

function selftest(root)
    failures = String[]
    for bad in ("tagphase7", "tag:", "suite:x", "")
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
    foreach(f -> println("SELFTEST FAIL: ", f), failures)
    isempty(failures) && println("selftest OK: malformed specs rejected, zero-match run fails")
    return isempty(failures)
end

length(ARGS) >= 1 || error("usage: run_tests_filtered.jl <abs-repo-root> SPEC... | --selftest")
if length(ARGS) >= 2 && ARGS[2] == "--selftest"
    exit(selftest(ARGS[1]) ? 0 : 1)
end
run_filtered(ARGS[1], ARGS[2:end])

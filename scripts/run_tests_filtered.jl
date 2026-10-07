# Runner for TestItemRunner with tag/file filters (avoids the `julia -e` trap).
# Usage: julia -t2 scripts/run_tests_filtered.jl <abs-repo-root> SPEC [SPEC...]
#        julia scripts/run_tests_filtered.jl <abs-repo-root> --selftest
#        julia -t2 scripts/run_tests_filtered.jl <abs-repo-root> --count-sets [--strict]
#   --count-sets: one discovery-only pass; prints all/fast/slow/files/canary counts and asserts
#     fast+slow==all, nothing outside test/, no :canary item is :slow. --strict also needs
#     slow>0 and fast>0 (use after :slow tags are applied).
#   SPEC = tag:<sym> | file:<basename>[,<basename>...]   (several specs are OR-combined)
# Fails closed: a malformed SPEC, or ANY spec / comma-separated file name that selects zero
# @testitems (e.g. a renamed tag or file), is an error rather than a vacuous green run. Dead
# filters are detected by a discovery-only preflight, before any test item runs.
using TestItemRunner, Test
include(joinpath(@__DIR__, "..", "test", "runner_support.jl"))

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

"""Pure consistency check of a count tally; returns the list of violation messages."""
function check_tally(t; strict::Bool = false)
    errs = String[]
    t.fast + t.slow == t.all || push!(errs, "fast($(t.fast)) + slow($(t.slow)) != all($(t.all))")
    t.outside == 0 || push!(errs, "$(t.outside) item(s) discovered outside test/")
    t.canary_slow == 0 || push!(errs, "$(t.canary_slow) :canary item(s) are tagged :slow")
    if strict
        t.slow > 0 || push!(errs, "strict: no :slow items")
        t.fast > 0 || push!(errs, "strict: no fast items")
    end
    return errs
end

function count_sets(root; strict::Bool = false)
    testdir = joinpath(root, "test")
    all = fast = slow = outside = canary = canary_slow = 0
    files = Set{String}()
    TestItemRunner.run_tests(testdir; filter = function (ti)
        all += 1
        push!(files, ti.filename)
        _under(ti.filename, testdir) || (outside += 1)
        isslow = :slow in ti.tags
        isslow ? (slow += 1) : (fast += 1)
        if :canary in ti.tags
            canary += 1
            isslow && (canary_slow += 1)
        end
        return false
    end)
    t = (; all, fast, slow, outside, canary, canary_slow)
    println("count-sets: all=$all fast=$fast slow=$slow files=$(length(files)) canary=$canary outside=$outside")
    errs = check_tally(t; strict)
    foreach(e -> println("COUNT-SETS FAIL: ", e), errs)
    return isempty(errs)
end

function selftest(root)
    failures = String[]
    withenv("TSODSO_TEST_SET" => "bogus") do
        try
            test_set_from_env()
            push!(failures, "invalid TSODSO_TEST_SET was accepted")
        catch e
            e isa ErrorException || push!(failures, "invalid TSODSO_TEST_SET raised $(typeof(e))")
        end
    end
    good = (; all = 5, fast = 3, slow = 2, outside = 0, canary = 1, canary_slow = 0)
    isempty(check_tally(good; strict = true)) || push!(failures, "consistent tally rejected")
    for bad in (merge(good, (; fast = 4)), merge(good, (; outside = 1)),
                merge(good, (; canary_slow = 1)))
        isempty(check_tally(bad)) && push!(failures, "inconsistent tally $(bad) accepted")
    end
    isempty(check_tally(merge(good, (; slow = 0, fast = 5)); strict = true)) &&
        push!(failures, "strict accepted slow == 0")
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
    append!(failures, guard_selftest())
    foreach(f -> println("SELFTEST FAIL: ", f), failures)
    isempty(failures) && println(
        "selftest OK: malformed specs rejected, zero-match and per-filter dead runs fail, " *
        "expected-broken guard is per test site, TSODSO_TEST_FILES trimmed and fail-closed",
    )
    return isempty(failures)
end

"""
Logic test of the expected-broken guard (`record_key` / `unexpected_records` /
`read_expected_broken`) and of `TSODSO_TEST_FILES` parsing, on synthetic testset trees laid
out like test/runtests.jl's `TSODSO / Package / <file> / <item> [/ nested...]` (TestItemRunner
1.1.5), plus the deeper 1.3.x directory-tree layouts (`.../ <dir> / <file> / <item>` and a
collapsed `<dir>/<file>`), which must yield the same keys.
"""
function guard_selftest()
    failures = String[]
    chk(c, msg) = c || push!(failures, msg)
    # Synthetic tree: entries are (item, nested testset names, Broken test_type, expr).
    function tree(entries; filepath = ["test_x.jl"])
        root = Test.DefaultTestSet("TSODSO")
        pkg = Test.DefaultTestSet("Package")
        push!(root.results, pkg)
        file = pkg
        for comp in filepath
            c = Test.DefaultTestSet(comp)
            push!(file.results, c)
            file = c
        end
        for (item, nested, kind, ex) in entries
            cur = Test.DefaultTestSet(item)
            push!(file.results, cur)
            for n in nested
                c = Test.DefaultTestSet(n)
                push!(cur.results, c)
                cur = c
            end
            push!(cur.results, Test.Broken(kind, ex))
        end
        return root
    end
    A = "allowed item"
    allowed = Dict(
        ("broken", "test_x.jl", A, "gap < 0.01") => 1,
        ("skipped", "test_x.jl", "skip item", "x !== nothing") => 1,
    )
    nbad(entries) = length(unexpected_records(broken_records(tree(entries)), allowed))
    site = (A, String[], :test, :(gap < 1e-2))
    chk(nbad([site]) == 0, "allowed site rejected")
    chk(nbad([]) == 0, "unobserved allowance must be fine")
    chk(nbad([("skip item", String[], :skipped, :(x !== nothing))]) == 0, "allowed skip rejected")
    chk(nbad([site, (A, String[], :test, :(other_check))]) == 1,
        "new @test_broken inside an allowed item was accepted")
    chk(nbad([site, site]) == 1, "second firing beyond the allowed count was accepted")
    chk(nbad([(A, ["inner"], :test, :(gap < 1e-2))]) == 1,
        "record in a nested testset of an allowed item was accepted")
    chk(nbad([("other item", [A], :test, :(gap < 1e-2))]) == 1,
        "nested testset named like an allowed item was accepted")
    chk(nbad([(A, String[], :skipped, :(gap < 1e-2))]) == 1, "skip at a broken-only site accepted")
    chk(nbad([("other item", String[], :test, :(gap < 1e-2))]) == 1, "unlisted item accepted")
    # The same item name in another file does not share the original's allowance.
    chk(length(unexpected_records(broken_records(tree([site]; filepath = ["test_y.jl"])),
            allowed)) == 1, "same-named item in another file used the allowance")
    # Item level is found structurally, so deeper 1.3.x layouts give the same keys.
    for fp in (["sub", "test_x.jl"], ["sub/test_x.jl"], ["a", "b", "test_x.jl"])
        nbad_fp(e) = length(unexpected_records(broken_records(tree(e; filepath = fp)), allowed))
        chk(nbad_fp([site]) == 0, "allowed site rejected under file layout $(fp)")
        chk(nbad_fp([site, (A, String[], :test, :(other_check))]) == 1,
            "new record accepted under file layout $(fp)")
        chk(nbad_fp([(A, ["inner"], :test, :(gap < 1e-2))]) == 1,
            "nested record accepted under file layout $(fp)")
    end
    # A record above item level (no `.jl` component) gets item "".
    above = Test.DefaultTestSet("TSODSO")
    push!(above.results, Test.Broken(:test, :(x)))
    chk(record_key(only(broken_records(above))) == ("broken", "", "", "x"),
        "record above item level not keyed with an empty item")
    # The printed expression of a real `broken=` record matches the documented key format.
    probe = @testset "probe item" begin
        gap = 0.25
        @test gap < 1e-2 broken = (gap >= 1e-2)
        @test_broken false
    end
    keys_ = [record_key(r; item_depth = 1) for r in broken_records(probe)]
    chk(keys_ == [("broken", "", "probe item", "gap < 0.01"),
            ("broken", "", "probe item", "false")],
        "real broken record keys differ from the documented format: $(keys_)")
    # File parsing: duplicate lines add allowances; malformed lines throw.
    mktempdir() do d
        f = joinpath(d, "eb.txt")
        write(f, "# c\nbroken | f.jl | it | a || b | why\nbroken | f.jl | it | a || b | again\n")
        eb = read_expected_broken(f)
        chk(eb == Dict(("broken", "f.jl", "it", "a || b") => 2),
            "expected_broken parse wrong: $(eb)")
        for bad in ("broken | f.jl | it | why\n", "maybe | f.jl | it | x | why\n",
                    "broken | f.jl |  | x | why\n", "broken | it | x | y | why\n")
            write(f, bad)
            ok = try
                read_expected_broken(f)
                false
            catch e
                e isa ErrorException
            end
            chk(ok, "malformed expected_broken line $(repr(bad)) accepted")
        end
    end
    real = read_expected_broken(joinpath(@__DIR__, "..", "test", "expected_broken.txt"))
    chk(!isempty(real), "test/expected_broken.txt parsed to nothing")
    # TSODSO_TEST_FILES: trimmed, empty entries rejected, unmatched names reported.
    withenv("TSODSO_TEST_FILES" => " a.jl, b.jl ") do
        chk(test_files_from_env() == ["a.jl", "b.jl"], "TSODSO_TEST_FILES entries not trimmed")
    end
    withenv("TSODSO_TEST_FILES" => "a.jl,") do
        ok = try
            test_files_from_env()
            false
        catch e
            e isa ErrorException
        end
        chk(ok, "TSODSO_TEST_FILES with an empty entry accepted")
    end
    chk(unmatched_files(Dict("a.jl" => 2, "b.jl" => 0)) == ["b.jl"], "unmatched_files wrong")
    return failures
end

length(ARGS) >= 1 || error("usage: run_tests_filtered.jl <abs-repo-root> SPEC... | --selftest")
if length(ARGS) >= 2 && ARGS[2] == "--selftest"
    exit(selftest(ARGS[1]) ? 0 : 1)
end
if length(ARGS) >= 2 && ARGS[2] == "--count-sets"
    exit(count_sets(ARGS[1]; strict = "--strict" in ARGS[3:end]) ? 0 : 1)
end
run_filtered(ARGS[1], ARGS[2:end])

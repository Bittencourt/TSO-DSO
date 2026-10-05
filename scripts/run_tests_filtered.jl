# Runner for TestItemRunner with tag/file filters (avoids the `julia -e` trap).
# Usage: julia -t2 scripts/run_tests_filtered.jl <abs-repo-root> SPEC [SPEC...]
#   SPEC = tag:<sym> | file:<basename>[,<basename>...]   (several specs are OR-combined)
using TestItemRunner

root = ARGS[1]
specs = ARGS[2:end]
isempty(specs) && error("filter spec must be tag:<sym> or file:<a.jl[,b.jl]>, got none")
preds = map(specs) do s
    kind, val = split(s, ":"; limit = 2)
    if kind == "tag"
        ti -> Symbol(val) in ti.tags
    elseif kind == "file"
        files = split(val, ",")
        ti -> basename(ti.filename) in files
    else
        error("filter spec must be tag:<sym> or file:<a.jl[,b.jl]>, got $s")
    end
end
TestItemRunner.run_tests(joinpath(root, "test"); filter = ti -> any(p -> p(ti), preds))

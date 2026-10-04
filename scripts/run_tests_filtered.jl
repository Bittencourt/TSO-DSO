# Runner for TestItemRunner with a tag/file filter (avoids the `julia -e` trap).
# Usage: julia -t2 scripts/run_tests_filtered.jl <abs-repo-root> tag:<sym> | file:<basename>
using TestItemRunner

root = ARGS[1]
spec = ARGS[2]
kind, val = split(spec, ":"; limit = 2)
flt = if kind == "tag"
    ti -> Symbol(val) in ti.tags
elseif kind == "file"
    ti -> basename(ti.filename) == val
else
    error("filter spec must be tag:<sym> or file:<basename>, got $spec")
end
TestItemRunner.run_tests(joinpath(root, "test"); filter = flt)

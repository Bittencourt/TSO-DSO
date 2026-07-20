# scripts/sweep.jl
#
# Runnable entry point (RESEARCH §Pattern 4): a researcher edits the `params` Dict below and
# runs this script to launch a full parameter sweep + collate the diff-friendly committed
# CSV summary under `results/sweeps/`.
#
# `@quickactivate "TSODSO"` walks UP from this file to find the repo-root `Project.toml`
# (named "TSODSO") and activates it. Do NOT call `initialize_project` (RESEARCH Pattern 4).
using DrWatson
@quickactivate "TSODSO"
using TSODSO

# Edit these selectors to declare a sweep — Vector-valued entries expand (dict_list), scalar
# entries stay fixed (RESEARCH §Pattern 2). Then run:
#     julia --project=. scripts/sweep.jl
params = Dict(
    :name => "sweep-demo",
    :feeder => :ieee13,
    :strategy => [:centralized, :admm],
    :seed => collect(1:2),
    :T => 24,
)

results = TSODSO.run_sweep(params)   # dir defaults to datadir("sims") (gitignored)

csvpath = projectdir("results", "sweeps", "sweep-demo.csv")
df = TSODSO.collate_summary(datadir("sims"), csvpath)

println("Ran $(length(results)) scenarios.")
println("Collated summary written to: ", csvpath)
show(df; allrows = true, allcols = true)
println()

# scripts/run_scenario.jl
#
# Runnable entry point (RESEARCH §Pattern 4): a researcher edits the `Scenario(...)` call
# below and runs this script to launch a single declarative run + provenance-stamped storage.
#
# `@quickactivate "TSODSO"` walks UP from this file to find the repo-root `Project.toml`
# (named "TSODSO") and activates it — so `projectdir()` == repo root and `datadir()` ==
# `<repo>/data`. Do NOT call `initialize_project` (that scaffolds a NEW project and would
# fight this existing package layout, RESEARCH Pattern 4).
using DrWatson
@quickactivate "TSODSO"
using TSODSO

# Edit these selectors to declare a scenario, then run:
#     julia --project=. scripts/run_scenario.jl
s = Scenario(
    name = "demo",
    feeder = :ieee13,
    strategy = :admm,
    seed = 42,
    T = 24,
)

res = TSODSO.run_and_store(s)   # dir defaults to datadir("sims") (gitignored)

println("welfare        = ", res.welfare)
println("exact_maxgap   = ", res.exact_maxgap)
println("iters          = ", res.iters)
println("stored under   = ", datadir("sims", savename(s, "jld2")))

# .planning/phases/26-network-device-model-correctness/26-16-repro-mu-q-sweep.jl
#
# Direct-script reproduction of test/test_admm_reactive.jl's ":live welfare/λ/μ
# cross-validated" testitem's mu_q comparison (Plan 26-16, Task 2) — TestItemRunner traps
# under --project=. (see the gsd-plan-verify-testitemrunner-trap memory), so this script
# reproduces the testitem body directly. It asserts against the CURRENTLY-PINNED tolerance
# PARSED LIVE from the edited test file (never hardcoded here), so a wrong re-pin (or a re-pin
# that never landed) fails this check.
#
# EXECUTOR FIX (Rule 1 — auto-fixed bug, this plan): the original two `include("test/...")`
# calls used paths relative to the process's CURRENT WORKING DIRECTORY, but Julia's `include`
# resolves a relative path against the DIRECTORY OF THE INCLUDING FILE (this script's own
# `.planning/phases/26-network-device-model-correctness/` directory), not the shell's cwd —
# so `test/fixtures_phase6.jl` never resolved from ANY invocation directory. Separately,
# `test/fixtures_phase6.jl`/`fixtures_phase19.jl` are TestItems `@testmodule`s, and `@testmodule`
# is not defined under a plain `--project=.` load (TestItems is test-only; see the
# gsd-plan-verify-testitemrunner-trap memory) — a raw `include` would additionally throw
# `UndefVarError: @testmodule not defined`. `_load_testmodule_as_plain` below fixes BOTH: it
# resolves each fixture file with an absolute, invocation-directory-independent path (relative
# to THIS script's own location via `@__DIR__`) and textually rewrites the `@testmodule Name
# begin` header to a plain `module Name` (no other line changes) before `include_string`-ing
# it — reproducing the IDENTICAL fixture-building code without requiring TestItems.jl.
function _load_testmodule_as_plain(path::AbstractString, modname::AbstractString)
    src = read(path, String)
    pattern = Regex("@testmodule\\s+" * modname * "\\s+begin")
    occursin(pattern, src) ||
        error("Could not find '@testmodule $modname begin' header in $path")
    plain = replace(src, pattern => "module $modname")
    return Base.include_string(Main, plain, path)
end

const REPRO_REPO_ROOT = normpath(joinpath(@__DIR__, "..", "..", ".."))

using TSODSO
using JuMP: dual

_load_testmodule_as_plain(
    joinpath(REPRO_REPO_ROOT, "test", "fixtures_phase6.jl"),
    "Phase6Fixtures",
)
_load_testmodule_as_plain(
    joinpath(REPRO_REPO_ROOT, "test", "fixtures_phase19.jl"),
    "Phase19Fixtures",
)
using .Phase6Fixtures
using .Phase19Fixtures

feeder = Phase6Fixtures.two_bus_feeder()
aggs = Phase19Fixtures.build_two_bus_aggregators_4q(feeder)
Th = Phase6Fixtures.T
λ0 = Phase6Fixtures.two_bus_lambda0()
ρ = Phase6Fixtures.RHO_2BUS

ctx_c, obj_c, balance_p_c, balance_q_c = Phase19Fixtures.centralized_welfare_4q(
    feeder,
    ConvexBranchFlow(),
    aggs;
    T = Th,
    λ₀ = λ0,
    allow_export = true,
)
μ_c = balance_q_c === nothing ? zeros(Th) : dual.(balance_q_c[2, :])

res = solve_admm(
    feeder,
    ConvexBranchFlow(),
    aggs;
    T = Th,
    λ₀ = λ0,
    ρ = ρ,
    allow_export = true,
    reactive_consensus = :live,
    maxiter = 500,
)

Δμ_norm = sqrt(sum(abs2, vec(res.mu_q) .- μ_c))
Δμ_maxabs = maximum(abs.(vec(res.mu_q) .- μ_c))
println("MEASURED: norm(Δmu_q) = ", Δμ_norm, "  maxabs(Δmu_q) = ", Δμ_maxabs)

# Parse the CURRENTLY-PINNED tolerance directly from the edited test file — never hardcode the
# expected atol, so an executor's wrong (or missing) re-pin fails this check. Path fixed
# (Rule 1, same cwd-independence issue as the fixture includes above) to resolve from this
# script's own location via REPRO_REPO_ROOT, not the shell's cwd.
src = read(joinpath(REPRO_REPO_ROOT, "test", "test_admm_reactive.jl"), String)
m = match(r"res\.mu_q\)[\s\S]{0,50}?atol\s*=\s*([0-9.eE+-]+)", src)
m === nothing && error(
    "Could not parse the mu_q comparison's atol from test/test_admm_reactive.jl — " *
    "Plan 26-16 Task 2 must re-pin an atol literal near the mu_q assertion",
)
pinned_atol = parse(Float64, m.captures[1])
println("PARSED pinned atol = ", pinned_atol)

# Reproduce whichever comparison form was chosen: a norm-based isapprox (the file's original
# idiom) or an elementwise max-abs (the triage's suggested alternative) — either way, the
# measured deviation must clear the PINNED tolerance actually committed to the file.
ok = (Δμ_norm <= pinned_atol) || (Δμ_maxabs <= pinned_atol)
ok || error(
    "mu_q re-pin FAILED: measured norm=$(Δμ_norm), maxabs=$(Δμ_maxabs) both exceed the " *
    "pinned atol=$(pinned_atol)",
)
println("OK: mu_q comparison clears the pinned atol=", pinned_atol)

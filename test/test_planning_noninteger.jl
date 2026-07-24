# test/test_planning_noninteger.jl
#
# Seam: PVAL-04 (v2.0 requirement) — the continuous-only-scope invariant that PLAN-INT-01
# (integer/discrete investment) is explicitly deferred to a future milestone. This file
# CONSOLIDATES the existing partial SharedTransmission-only no-binaries checks
# (test/test_planning_coupling.jl ~line 237, test/test_planning_nash.jl ~line 320) into ONE
# registry-based `@testitem` that covers all FOUR planning-layer subproblem builders
# (`build_planning_oracle`, `build_follower`, `build_master`, `build_shared_transmission`),
# per 14-CONTEXT.md's PVAL-04 decision: "a dedicated @testitem that BUILDS every
# planning-layer model via its public builder and asserts zero is_binary/is_integer
# variables — semantic check, not a grep lint."
#
# The two existing partial checks are KEPT, not removed (see the cross-reference comments
# added to those files by this same plan) — test_planning_nash.jl's check additionally
# covers the POST-run_nash!-mutation state, a genuinely different code path than a fresh
# build.
#
# Tripwire: a source-scan over src/planning/*.jl collects every `function build_\w+(`
# definition and asserts the found set equals this registry's key set — so a future new
# builder file/function cannot silently ship without this guard (T-14-04, Repudiation).

@testitem "planning PVAL-04: no-binaries guard covers all four planning-layer builders + source-scan tripwire" tags =
    [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    using JuMP: all_variables, is_binary, is_integer

    # Toy fixture (verbatim from test/test_planning_certification.jl lines 176-181, the
    # SAME instance already used elsewhere in the planning test suite).
    feeder = Phase6Fixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])

    registry = Dict{String, Function}(
        "build_planning_oracle" =>
            () -> build_planning_oracle(feeder, LinDistFlow(), [agg]; λ₀ = [4.0], T = 1).model,
        "build_follower" =>
            () -> build_follower(;
                T = 1,
                corridor_cap = 2.0,
                x_inv_max = 2.0,
                c_inv = 1.0,
                c_op = [0.5],
            ).model,
        "build_master" =>
            () -> build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0).model,
        "build_shared_transmission" =>
            () -> build_shared_transmission(;
                N = 2,
                T = 1,
                corridor_cap = 2.0,
                x_inv_max = [0.3, 0.3],
                c_inv = [1.0, 1.0],
                c_op = [[0.5], [0.5]],
            ).model,
    )

    for (name, build) in registry
        model = build()
        offenders = [v for v in all_variables(model) if is_binary(v) || is_integer(v)]
        # Deviation (Rule 1 - bug): `@test cond "message"` is not valid Test.jl syntax
        # (base Test's @test macro does not accept a bare trailing string as a custom
        # failure message — verified directly against Julia 1.12's Test stdlib). The
        # fail-loud requirement (name the offending builder AND variables) is instead
        # satisfied via `|| error(...)`, which Test.jl reports as an "Error During Test"
        # with the interpolated message printed verbatim.
        @test isempty(offenders) ||
              error("builder $(name) introduced binary/integer variable(s): $(offenders)")
    end

    # Source-scan tripwire (T-14-04): a future new build_* function under src/planning/
    # cannot silently skip this registry — the found-set must equal the registry's keys.
    planning_dir = joinpath(pkgdir(TSODSO), "src", "planning")
    found = Set{String}()
    for f in readdir(planning_dir; join = true)
        endswith(f, ".jl") || continue
        for line in eachline(f)
            m = match(r"^function (build_\w+)\(", line)
            m !== nothing && push!(found, m.captures[1])
        end
    end
    @test found == Set(keys(registry))
end

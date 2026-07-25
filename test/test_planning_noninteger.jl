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
# Tripwire (hardened per Phase 14 review WR-01): a RECURSIVE source-scan over src/planning/
# collects every long- OR short-form `build_\w+` definition (docstring lines excluded),
# unioned with a syntax-independent semantic channel (every EXPORTED `build_*` symbol not on
# the documented operational-layer allowlist), and asserts the found set equals this
# registry's key set — so a future new builder file/function cannot silently ship without
# this guard (T-14-04, Repudiation).

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
            () ->
                build_planning_oracle(feeder, LinDistFlow(), [agg]; λ₀ = [4.0], T = 1).model,
        "build_follower" =>
            () -> build_follower(;
                T = 1,
                corridor_cap = 2.0,
                x_inv_max = 2.0,
                c_inv = 1.0,
                c_op = [0.5],
            ).model,
        "build_master" =>
            () -> build_master(;
                T = 1,
                c_y = 0.3,
                y_max = 8.0,
                α_op_lb = -5.0,
                α_x_lb = 0.0,
            ).model,
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
    #
    # Hardened (Phase 14 review WR-01) against the silent false-negative shapes of the
    # original single-regex `readdir` scan:
    #   1. SHORT-FORM definitions (`build_x(...) = ...`) — the `function` keyword is now
    #      optional in the regex.
    #   2. INDENTED definitions (inside `module`/`if`/`@static` blocks) — leading
    #      whitespace is now allowed.
    #   3. SUBDIRECTORIES — `walkdir` replaces the non-recursive `readdir`.
    #   4. Builders landing OUTSIDE src/planning/ — a second, syntax-independent semantic
    #      channel below unions in every EXPORTED `build_*` symbol not on the documented
    #      operational-layer allowlist.
    # Docstring interiors are skipped via triple-quote state tracking: docstring signature
    # conventions (`    build_follower(; T::Int, ...`) and docstring prose lines beginning
    # with a `build_*(` call (e.g. nash.jl's run_nash_probe algorithm text) would otherwise
    # false-positive under the widened regex. Any REMAINING false positive (a bare
    # `build_*(...)` call statement opening a non-docstring line) fails the set equality
    # LOUDLY — the correct polarity for a tripwire.
    planning_dir = joinpath(pkgdir(TSODSO), "src", "planning")
    found = Set{String}()
    for (root, _, files) in walkdir(planning_dir), fname in files
        endswith(fname, ".jl") || continue
        in_docstring = false
        for line in eachline(joinpath(root, fname))
            if isodd(count("\"\"\"", line))
                in_docstring = !in_docstring
                continue
            end
            in_docstring && continue
            m = match(r"^\s*(?:function\s+)?(build_\w+)\s*\(", line)
            m !== nothing && push!(found, m.captures[1])
        end
    end

    # Semantic channel (syntax-independent): every EXPORTED `build_*` symbol must be
    # either a planning-registry key or on this documented operational-layer allowlist —
    # so a NEW exported builder anywhere in the package, regardless of definition syntax
    # or file location, must land in one of the two, loudly. (A new OPERATIONAL builder
    # failing here is a deliberate, loud prompt to extend this allowlist consciously.)
    operational_builders = Set([
        "build_agr_opt",     # admm/AgrOpt.jl — ADMM aggregator subproblem
        "build_dso_opt",     # admm/DsoOpt.jl — ADMM DSO subproblem
        "build_ieee123",     # data/ieee123.jl — feeder fixture constructor
        "build_feeder",      # experiments/materialize.jl — scenario materializer
        "build_price",       # experiments/materialize.jl — scenario materializer
        "build_population",  # experiments/materialize.jl — scenario materializer
    ])
    exported_builders = Set(filter(n -> startswith(n, "build_"), string.(names(TSODSO))))
    union!(found, setdiff(exported_builders, operational_builders))
    @test found == Set(keys(registry))
end

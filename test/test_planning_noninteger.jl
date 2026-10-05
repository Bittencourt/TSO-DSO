# test/test_planning_noninteger.jl
#
# Seam: the continuous-only-scope invariant for the planning layer (integer/discrete
# investment is handled by the separate integer master). This file
# CONSOLIDATES the existing partial SharedTransmission-only no-binaries checks
# (test/test_planning_coupling.jl ~line 237, test/test_planning_nash.jl ~line 320) into ONE
# registry-based `@testitem` that covers all FOUR planning-layer subproblem builders
# (`build_planning_oracle`, `build_follower`, `build_master`, `build_shared_transmission`),
# per the design decision: "a dedicated @testitem that BUILDS every
# planning-layer model via its public builder and asserts zero is_binary/is_integer
# variables — semantic check, not a grep lint."
#
# The two existing partial checks are KEPT, not removed (see the cross-reference comments
# in those files) — test_planning_nash.jl's check additionally
# covers the POST-run_nash!-mutation state, a genuinely different code path than a fresh
# build.
#
# Tripwire (hardened): a RECURSIVE source-scan over src/planning/
# collects every long- OR short-form `build_\w+` definition (docstring lines excluded),
# unioned with a syntax-independent semantic channel (every EXPORTED `build_*` symbol not on
# the documented operational-layer allowlist), and asserts the found set equals this
# registry's key set — so a future new builder file/function cannot silently ship without
# this guard.
#
# Four one-time, discard-after-use relaxed-derivation helpers exist in
# `src/planning/master.jl` (`make_relaxed_oracle_model`, `derive_alpha_op_lb`,
# `make_relaxed_follower_model`, `derive_alpha_x_lb`). These are deliberately named WITHOUT a
# `build_` prefix and are NOT planning-layer subproblem builders in this registry's sense —
# each is built once, solved once, and discarded; none is ever re-solved or re-used across
# Benders iterations the way `build_planning_oracle`/`build_follower`/`build_master`/
# `build_shared_transmission` are. They are binary-free by construction (plain LP/relaxed-SOCP
# relaxations of already-binary-free builders) and are therefore intentionally OUT of this
# registry's scope — the source-scan's `build_\w+` regex correctly never discovers them, and
# this is not a gap in the tripwire's coverage.

@testitem "planning noninteger: no-binaries guard covers all four planning-layer builders + source-scan tripwire" tags =
    [:planning] setup = [TwoBusFixtures, ToyDeviceFixture, PlanningFixtures] begin
    using TSODSO
    using TSODSO: build_bilevel_kkt, build_feasibility_oracle, build_follower, build_master, build_master_integer, build_planning_oracle
    using JuMP: all_variables, is_binary, is_integer, num_constraints, VariableRef
    import JuMP: MOI

    # Toy fixture (verbatim from test/test_planning_certification.jl, the
    # SAME instance already used elsewhere in the planning test suite).
    feeder = TwoBusFixtures.two_bus_feeder()
    dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
    agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])

    registry = Dict{String, Function}(
        "build_planning_oracle" =>
            () ->
                build_planning_oracle(feeder, LinDistFlow(), [agg]; λ₀ = [4.0], T = 1).model,
        # The slack-minimization feasibility oracle is a genuinely
        # binary-free LP/SOCP (free-sign s_plus/s_minus, no investment/complementarity
        # structure) — NOT added to EXEMPT.
        "build_feasibility_oracle" =>
            () -> build_feasibility_oracle(feeder, LinDistFlow(), [agg]; T = 1).model,
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
        # `build_master_integer` is a
        # PLANNING-layer builder that is DELIBERATELY, correctly NOT binary-free (the
        # binary-expansion investment master) — the opposite case from
        # `operational_builders` below (builders that live outside src/planning/ and are
        # correctly binary-free). It MUST still be registered here (the source-scan
        # tripwire requires it — omission fails the tripwire loudly), but it is carried on
        # the explicit `EXEMPT` allowlist immediately below (a per-builder
        # carve-out, never a conditional one).
        "build_master_integer" =>
            () -> build_master_integer(;
                T = 1,
                K = 4,
                c_y = 0.3,
                y_max = 8.0,
                α_op_lb = -5.0,
                α_x_lb = 0.0,
            ).model,
        # `build_bilevel_kkt` is a PLANNING-layer builder whose
        # follower complementarity is modelled as `MOI.SOS1` pairs, NOT binary/integer
        # variables — the SOS1ToMILPBridge introduces binaries only at solve time. So at
        # the JuMP-model level it is genuinely binary-free and is NOT on `EXEMPT`; the
        # SOS1 assertion after the loop verifies that it is a MILP *via SOS1*, so a future
        # switch to explicit binaries (or a loss of the complementarity) fails loudly.
        "build_bilevel_kkt" =>
            () -> begin
                f = PlanningFixtures.bilevel_toy_fixture()
                build_bilevel_kkt(
                    f.feeder,
                    LinDistFlow();
                    T = f.T,
                    agg_bus = f.agg_bus,
                    corridor_cap = f.corridor_cap,
                    x_inv_max = f.x_inv_max,
                    c_inv = f.c_inv,
                    c_op = f.c_op,
                    pi_tariff = f.pi_tariff,
                    q_op = f.q_op,
                    c_y = f.c_y,
                    y_max = f.y_max,
                    v_d = f.v_d,
                    d_max = f.d_max,
                ).model
            end,
    )

    # The exemption is a per-builder carve-out, not a conditional one.
    # The source-scan tripwire below still discovers "build_master_integer" — this
    # EXEMPT set only changes what the no-binaries assertion DOES with that registry key,
    # never whether it is discovered/registered.
    EXEMPT = Set(["build_master_integer"])

    # Self-verifying allowlist: every name on EXEMPT must actually be a registry key —
    # if `build_master_integer` were ever renamed/removed from the registry without
    # updating this list, this assertion catches the drift loudly rather than letting a
    # stale string silently do nothing.
    @test EXEMPT ⊆ Set(keys(registry)) || error(
        "EXEMPT names a builder not present in the registry: $(setdiff(EXEMPT, Set(keys(registry))))",
    )

    for (name, build) in registry
        model = build()
        offenders = [v for v in all_variables(model) if is_binary(v) || is_integer(v)]
        if name in EXEMPT
            # This is a VERIFIED statement, not a blind
            # skip — this builder genuinely introduces binaries on purpose. If
            # it ever stops being integer, this fails loudly rather than silently masking a
            # regression where build_master_integer accidentally becomes binary-free.
            @test !isempty(offenders) || error(
                "EXEMPT builder $(name) unexpectedly introduced ZERO binary/integer variables — the exemption is now stale/wrong",
            )
        else
            # `@test cond "message"` is not valid Test.jl syntax
            # (base Test's @test macro does not accept a bare trailing string as a custom
            # failure message — verified directly against Julia 1.12's Test stdlib). The
            # fail-loud requirement (name the offending builder AND variables) is instead
            # satisfied via `|| error(...)`, which Test.jl reports as an "Error During Test"
            # with the interpolated message printed verbatim.
            @test isempty(offenders) || error(
                "builder $(name) introduced binary/integer variable(s): $(offenders)",
            )
        end
    end

    # The bilevel builder's complementarity lives in SOS1 constraints.
    @test num_constraints(
        registry["build_bilevel_kkt"](),
        Vector{VariableRef},
        MOI.SOS1{Float64},
    ) > 0

    # Source-scan tripwire: a future new build_* function under src/planning/
    # cannot silently skip this registry — the found-set must equal the registry's keys.
    #
    # Hardened against the silent false-negative shapes of the
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
        "build_powerflow",   # experiments/materialize.jl — pf-selector materializer
        # maps a Scenario's primitive `pf` selector to an
        # AbstractPowerFlow instance; builds no JuMP model, so it is an
        # OPERATIONAL-layer helper, never a planning-layer builder —
        # added here per this file's own tripwire contract.
        "build_mpc_window",  # models/mpc_window.jl — receding-horizon window
        # builder; an OPERATIONAL-layer builder (build-once
        # welfare-shaped window, no binaries/integers by construction,
        # same as every other welfare-shaped builder), never a
        # planning-layer (Benders/Stackelberg-Nash) builder — consciously
        # added here per this file's own documented tripwire contract.
        "build_stochastic_welfare",     # models/stochastic_welfare.jl — S-scenario
        # extensive-form welfare builder; an OPERATIONAL-layer builder (same
        # welfare-shaped, no-binaries-by-construction family
        # as build_mpc_window above), never a planning-layer
        # builder — added here per this file's own tripwire
        # contract (this builder's export alone tripped
        # this test's semantic channel without this entry).
        "build_stochastic_oos_harness",  # models/stochastic_welfare.jl — out-of-
        # sample re-solve harness;
        # same OPERATIONAL-layer disposition and rationale as
        # build_stochastic_welfare immediately above.
    ])
    exported_builders = Set(filter(n -> startswith(n, "build_"), string.(names(TSODSO))))
    union!(found, setdiff(exported_builders, operational_builders))
    @test found == Set(keys(registry))
end

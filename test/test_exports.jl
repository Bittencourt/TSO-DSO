@testitem "exports: curated public surface" tags = [:exports] begin
    using TSODSO, Test

    keep = Set(
        Symbol.(
            split(
                """
                TSODSO ReactiveMode
                AbstractFeeder Branch Bus Feeder MeshedFeeder ieee13_modified ieee123_modified
                ieee8500_modified ieee8500_mv_modified generate_profiles assert_radial
                AbstractDevice Aggregator Deferrable FixedCapacitor FourQuadBESS Interruptible
                PVBattery Thermostatic
                AbstractPowerFlow ACPowerFlow ConvexBranchFlow DCPowerFlow LinDistFlow
                MeshedFlow RestrictedBranchFlow
                ModelContext contribute! add_to_residual! register_constraint! add_to_objective!
                TSODSOError CertificateError ConvergenceError SolveFailedError assert_solved!
                assert_no_slack
                ProblemClass select_optimizer SMAX_NO_LIMIT
                solve_welfare solve_toy_dc solve_linear operational_oracle assert_socp_exact!
                assert_ac_exact! assert_restriction_exact! certify_angle_recoverable!
                assert_4q_complementarity! assert_battery_complementarity! socp_relaxation_gap
                extract_dlmp decompose_dlmp DlmpDecomposition economic_direction_checks
                welfare_accounting fit_baseline
                solve_admm AdmmResiduals build_agr_opt build_dso_opt AgrOpt DsoOpt solve_agr!
                solve_dso!
                Scenario ScenarioResult run_scenario run_and_store scenario_filename run_sweep
                collate_summary run_mpc run_stochastic ADMM Centralized MPC Stochastic
                AbstractStrategy
                solve_stackelberg! run_nash! BendersTrace NashTrace build_shared_transmission
                SharedTransmission DistributorView
                plot_convergence plot_nash_convergence plot_price_convergence
                """,
            ),
        ),
    )

    # `names` also lists `public` names on Julia >= 1.11, so filter to the exported ones.
    exported = Set(filter(n -> Base.isexported(TSODSO, n), names(TSODSO)))
    @test exported == keep

    removed_groups = (
        (
            :LP,
            :QP,
            :SOCP,
            :NLP,
            :MILP,
            :GurobiChoice,
            :MosekChoice,
            :SCSChoice,
            :problem_class,
        ),
        (:record!, :converged, :set_rho!, :set_rho_q!, :admm_supported),
        (:OFF, :CERTIFIED, :LIVE, :normalize_reactive_mode),
        (:I_base, :Z_base, :PerUnitBase, :to_pu_impedance, :to_pu_power),
        (:solve_follower!, :build_master, :solve_master!, :PlanningOracle, :FollowerLP),
        (:build_feeder, :build_population, :build_powerflow, :build_price, :sub_seed),
    )
    @test all(g -> all(n -> n ∉ exported, g), removed_groups)

    # Unexported names remain reachable through qualification.
    @test TSODSO.SOCP() isa TSODSO.ProblemClass
    @test isdefined(TSODSO, :record!)
    @test isdefined(TSODSO, :converged)
    @test all(
        n -> isdefined(TSODSO, n),
        Symbol.(
            readlines(
                joinpath(pkgdir(TSODSO), ".github", "scripts", "unexported_names.txt"),
            ),
        ),
    )

    # No name is exported from two different source files.
    function export_owners(root)
        owners = Dict{Symbol, Set{String}}()
        function walk(e, file)
            e isa Expr || return nothing
            if e.head === :export
                for a in e.args
                    push!(get!(owners, a, Set{String}()), file)
                end
            end
            foreach(x -> walk(x, file), e.args)
            return nothing
        end
        for (r, _, fs) in walkdir(root), f in fs
            endswith(f, ".jl") || continue
            path = joinpath(r, f)
            walk(Meta.parseall(read(path, String)), path)
        end
        return owners
    end
    owners = export_owners(joinpath(pkgdir(TSODSO), "src"))
    @test !isempty(owners)
    @test all(kv -> length(kv.second) == 1, owners)

    # `public` (Julia >= 1.11) is visible without being exported.
    @static if VERSION >= v"1.11"
        @test Base.ispublic(TSODSO, :SOCP)
        @test !Base.isexported(TSODSO, :SOCP)
        @test Base.ispublic(TSODSO, :solve_follower!)
        @test !Base.isexported(TSODSO, :record!)
    end
end

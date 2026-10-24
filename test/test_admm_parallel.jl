# test/test_admm_parallel.jl
#
# Seam: the Phase-39 opt-in threaded AGR executor on `solve_admm` (plan 39-02) —
# PAR-01's fail-loud 1-thread guard, PAR-02's BITWISE serial-vs-threaded equality on the
# multi-aggregator minimal scenario (IEEE-13, 10 aggregators, seed 7, T=24), and PAR-05's
# additive per-aggregator result keys.
#
# GOLDEN POLICY: the equality bar is literal `==` on Float64 traces/welfare/prices — NEVER a
# tolerance-based compare (a tolerance would launder a genuine parallel difference); `isequal`
# only for the NaN-bearing `exact_maxgap`. The default serial path's knife-edge canary
# (test_admm_knifeedge_canary.jl: iters = 56, welfare = -4823.66604824162) is never re-pinned
# here; the canary-after-parallel same-process check lives in Task 3's verify command.
#
# THREAD GATING: the executor is fail-loud under `parallel = true` with
# `Threads.nthreads() == 1` (ArgumentError, no silent serial fallback). The equality item
# therefore emits a LOUD `@test_skip` under the default 1-thread suite (message carries the
# exact 4-thread invocation) — every such skip record is allowlisted by exact key in
# test/expected_broken.txt; an unlisted skip FAILS the run (runtests.jl guard).
#
# BLAS HYGIENE (Pitfall 1): the threaded executor pins `BLAS.set_num_threads(1)`
# process-globally mid-run; `solve_admm` restores it in its own `finally`, and these items
# save/restore around the whole body so no later test item (including the canary) inherits a
# perturbed BLAS config.

@testitem "admm parallel: fail-loud guard (admm_parallel)" setup =
    [ExperimentHarnessFixtures] tags = [:admm, :parallel] begin
    using TSODSO

    # Direct-call recipe mirroring run(::ADMM, s)'s argument derivation
    # (src/experiments/run.jl:107-135) on the minimal multi-aggregator scenario — the same
    # fixture every item in this file uses.
    kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
    s = TSODSO.Scenario(; kw..., strategy = :admm)
    st = s.strategy
    feeder, λ₀, aggs = TSODSO._materialize(s)
    pf = TSODSO.build_powerflow(s)
    solve_kw = (
        T = s.T,
        λ₀ = λ₀,
        ρ = st.ρ,
        maxiter = st.maxiter,
        ε_abs = st.ε_abs,
        ε_rel = st.ε_rel,
        τ = st.τ_ratio,
        μ = st.μ,
        allow_export = s.allow_export,
    )

    if Threads.nthreads() == 1
        # The guard throws BEFORE any build, so this is cheap and always exercised by the
        # default 1-thread suite (fail-loud policy — no silent serial fallback).
        @info "admm parallel guard: 1-thread runtime — parallel=true must throw ArgumentError"
        @test_throws ArgumentError solve_admm(
            feeder,
            pf,
            aggs;
            solve_kw...,
            parallel = true,
        )
    else
        # Multi-threaded: the guard does NOT fire — the same call runs (bonus smoke of the
        # threaded path; bitwise equality is the next item's job).
        r = solve_admm(feeder, pf, aggs; solve_kw..., parallel = true)
        @info "admm parallel guard: multi-threaded — guard silent" iters = r.iters welfare =
            r.welfare
        @test r.status == :converged
    end
end

@testitem "admm parallel: threaded == serial bitwise (admm_parallel)" setup =
    [ExperimentHarnessFixtures] tags = [:admm, :parallel] begin
    using TSODSO
    using LinearAlgebra: BLAS

    if Threads.nthreads() == 1
        @info "admm parallel: equality item SKIPPED — the threaded executor needs JULIA_NUM_THREADS > 1"
        @test_skip "threaded executor equality needs JULIA_NUM_THREADS > 1 — run: JULIA_NUM_THREADS=4 TSODSO_TEST_FILES=test_admm_parallel.jl julia --project=. -e 'import Pkg; Pkg.test()'"
    else
        let
            # Same fixture and argument derivation as the guard item — the two calls below
            # use IDENTICAL kwargs and differ ONLY in `parallel`.
            kw = ExperimentHarnessFixtures.minimal_scenario_kwargs()
            s = TSODSO.Scenario(; kw..., strategy = :admm)
            st = s.strategy
            feeder, λ₀, aggs = TSODSO._materialize(s)
            pf = TSODSO.build_powerflow(s)
            solve_kw = (
                T = s.T,
                λ₀ = λ₀,
                ρ = st.ρ,
                maxiter = st.maxiter,
                ε_abs = st.ε_abs,
                ε_rel = st.ε_rel,
                τ = st.τ_ratio,
                μ = st.μ,
                allow_export = s.allow_export,
            )

            # Process-global BLAS state: snapshot once, restore in `finally` on EVERY exit
            # path (Pitfall 1 — an unrestored pin poisons every later item, incl. the canary).
            blas0 = BLAS.get_num_threads()
            try
                r1 = solve_admm(feeder, pf, aggs; solve_kw..., parallel = false)
                r2 = solve_admm(feeder, pf, aggs; solve_kw..., parallel = true)

                # Loud measured values BEFORE the assertions (canary attribution style), plus
                # the spike-005 gate provenance: the threaded executor is enabled ONLY on that
                # spike's documented PASS (plan 39-01).
                @info "admm parallel: serial-vs-threaded equality (BITWISE bar)" serial_iters =
                    r1.iters threaded_iters = r2.iters serial_welfare = r1.welfare threaded_welfare =
                    r2.welfare gate = "spike 005 verdict PASS — threaded @spawn Clarabel solves bitwise-equal to serial under the production configuration" gate_artifact = ".planning/spikes/005-clarabel-concurrency/README.md"

                # BITWISE, field-wise — never the whole NamedTuple (`AdmmResiduals` is MUTABLE:
                # default `==` is identity), never a tolerance-based compare (golden policy).
                @test r1.iters == r2.iters
                @test r1.residuals.primal_trace == r2.residuals.primal_trace
                @test r1.residuals.dual_trace == r2.residuals.dual_trace
                @test r1.residuals.rho_trace == r2.residuals.rho_trace
                @test r1.welfare == r2.welfare
                @test r1.dadp == r2.dadp
                @test isequal(r1.exact_maxgap, r2.exact_maxgap)    # NaN-safe, still bitwise
                # PAR-05 additive keys ride the same equality bar.
                @test r1.agr_dispatch == r2.agr_dispatch
                @test r1.agr_utility == r2.agr_utility
                @test r1.agr_import == r2.agr_import
                @test r1.agr_prices == r2.agr_prices
                # Price consistency: agr_prices[j] is the bus-j row of the published DADP
                # (rows in ascending load_nodes order — _admm_certify's λ_mat assembly).
                load_nodes = sort(collect(keys(r2.agr_prices)))
                @test all(
                    r2.agr_prices[j] == r2.dadp[i, :] for (i, j) in enumerate(load_nodes)
                )
                # BLAS hygiene: the executor's pin is restored on every exit path.
                @test BLAS.get_num_threads() == blas0
            finally
                BLAS.set_num_threads(blas0)
            end
        end
    end
end

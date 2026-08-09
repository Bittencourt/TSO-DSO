# test/test_mpc_trace.jl
#
# Seam: src/models/mpc_trace.jl (MPC-03). Permanent @testitem coverage for MpcTrace, the
# JuMP-free rolling-horizon price-consistency ledger (mirrors AdmmResiduals's own record!/
# converged @testitem coverage, test_admm_dualresid.jl). Every item name contains "mpc_trace"
# so `occursin("mpc_trace", ti.name)` selects the whole file, tagged `tags = [:mpc_trace]`.

@testitem "mpc_trace: empty ledger predicates and construction (MPC-03)" tags = [:mpc_trace] begin
    using TSODSO

    t = MpcTrace()
    @test t.steps == 0
    @test isempty(t.dadp_trace)
    @test isempty(t.dadp_da_trace)
    @test isempty(t.jump_trace)
    @test isempty(t.cum_deviation_trace)
    @test isempty(t.cert_status_trace)

    # Safe defaults on an empty ledger — never NaN/error.
    @test max_jump(t) == 0.0
    @test mean_jump(t) == 0.0
    @test any_cert_failed(t) == false
end

@testitem "mpc_trace: record! sequential-k fail-loud guard (mirrors AdmmResiduals)" tags =
    [:mpc_trace] begin
    using TSODSO

    t = MpcTrace()
    record!(t, 1, 5.0, 5.0, :certified_convex_dual)

    # A repeated k (double-record) throws.
    @test_throws ArgumentError record!(t, 1, 5.4, 5.1, :certified_convex_dual)

    # A skipped k (missing step) throws.
    @test_throws ArgumentError record!(t, 3, 5.4, 5.1, :certified_convex_dual)

    # The ledger is unmodified by either failed call.
    @test t.steps == 1
    @test t.dadp_trace == [5.0]
end

@testitem "mpc_trace: jump/cumulative-deviation/cert-status derived correctly across N steps (MPC-03 price-consistency metrics)" tags =
    [:mpc_trace] begin
    using TSODSO

    t = MpcTrace()
    record!(t, 1, 4.0, 4.0, :certified_convex_dual)
    record!(t, 2, 4.5, 4.2, :local_ac_dual)
    record!(t, 3, 4.1, 4.3, :cert_failed)
    record!(t, 4, 4.1, 4.1, :certified_convex_dual)

    @test t.steps == 4
    @test t.dadp_trace == [4.0, 4.5, 4.1, 4.1]
    @test t.dadp_da_trace == [4.0, 4.2, 4.3, 4.1]

    # jump[k] = |dadp[k] - dadp[k-1]|, jump[1] = 0.0.
    expected_jump = [0.0, abs(4.5 - 4.0), abs(4.1 - 4.5), abs(4.1 - 4.1)]
    @test t.jump_trace ≈ expected_jump

    # cum_deviation[k] = cum_deviation[k-1] + |dadp[k] - dadp_da[k]|.
    expected_cum = cumsum([abs(4.0 - 4.0), abs(4.5 - 4.2), abs(4.1 - 4.3), abs(4.1 - 4.1)])
    @test t.cum_deviation_trace ≈ expected_cum

    @test t.cert_status_trace == [:certified_convex_dual, :local_ac_dual, :cert_failed, :certified_convex_dual]

    @test max_jump(t) ≈ maximum(expected_jump)
    @test mean_jump(t) ≈ sum(expected_jump) / 4

    # The :cert_failed entry flags the trace as having a genuine failure.
    @test any_cert_failed(t) == true

    # A SEPARATE trace with only :certified_convex_dual and :local_ac_dual (a successful
    # fallback escalation, NOT a failure) must NOT be flagged.
    t2 = MpcTrace()
    record!(t2, 1, 1.0, 1.0, :certified_convex_dual)
    record!(t2, 2, 1.0, 1.0, :local_ac_dual)
    @test any_cert_failed(t2) == false
end

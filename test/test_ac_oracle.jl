# Seam: models/ac_oracle.jl (EXACT-01 angle recovery now; EXACT-02/03 assert_ac_exact! lands
# in plan 15-02 — RED-guarded here). Every item name contains "ac_oracle" so
# `occursin("ac_oracle", ti.name)` selects it.
#
# The 2-bus angle-recovery item is the BLOCKING analytic validation gate flagged in STATE.md:
# `recover_voltage_angles` is the one genuinely-new piece of math this phase adds, so it must
# match a hand-derived closed-form complex phasor on the trivial 2-bus fixture BEFORE any later
# plan trusts it on IEEE-13/123. While RED (plan 15-01 Task 3 not yet landed) the behavioral
# asserts sit behind an `isdefined` guard so they go live automatically; the assert_ac_exact!
# RED-guard is intentionally red until plan 15-02.

@testitem "ac_oracle: recover_voltage_angles matches the hand-derived 2-bus closed-form phasor (EXACT-01, angle-recovery validation gate)" tags = [:ac_oracle] begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    using JuMP

    # RED until plan 15-01 Task 3 defines the phasor recursion.
    @test isdefined(TSODSO, :recover_voltage_angles)

    if isdefined(TSODSO, :recover_voltage_angles)
        # The trivial 2-bus radial fixture (r = 0.01, x = 0.02).
        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 0.01, 0.02, 10.0)],
            1,
        )
        T, N, B = 1, 2, 1

        # A hand-chosen fixed operating point on the equality cone (Baran–Wu, thesis 3.33):
        #   P[1,1] = 0.1, Q[1,1] = 0.05, l[1,1] = (P²+Q²)/v[1,1] = 0.0125, v[1,1] = 1.0 (root).
        #   v[2,1] = v[1,1] − 2(rP+xQ) + (r²+x²)·l
        #          = 1.0 − 0.004 + 0.00000625 = 0.99600625.
        # Closed-form phasor: V₁ = 1.0 + 0.0im; I₁₂ = conj(P+jQ)/conj(V₁) = 0.1 − 0.05im;
        #   V₂ = V₁ − (r+jx)·I₁₂ = 0.998 − 0.0015im. abs2(V₂) = 0.998² + 0.0015² = 0.99600625
        #   (self-consistent with v[2,1]). angle(V₂) ≈ −0.0015003 rad, matching the small-angle
        #   identity θ₂ ≈ −(x·P − r·Q) = −(0.02·0.1 − 0.01·0.05) = −0.0015.
        # An attached optimizer is required for `value(...)` to resolve the fixed variables
        # (mirrors test_exactness.jl's fixed-value construction). Everything is fixed and the
        # objective is 0, so a trivial LP solve suffices — recover_voltage_angles is pure
        # post-processing over the resulting values, no cone involved.
        model = Model(select_optimizer(LP()))
        @variable(model, v[1:N, 1:T])
        @variable(model, P[1:B, 1:T])
        @variable(model, Q[1:B, 1:T])
        @variable(model, l[1:B, 1:T])
        fix(v[1, 1], 1.0; force = true)
        fix(v[2, 1], 0.99600625; force = true)
        fix(P[1, 1], 0.1; force = true)
        fix(Q[1, 1], 0.05; force = true)
        fix(l[1, 1], 0.0125; force = true)
        @objective(model, Max, 0)
        optimize!(model)

        ctx = TSODSO.ModelContext(model)
        ctx.meta[:feeder] = feeder
        ctx.meta[:T] = T
        ctx.meta[:pf_vars] = (; v, P, Q, l)

        Vphasor = TSODSO.recover_voltage_angles(ctx)

        @test Vphasor isa Matrix{ComplexF64}
        @test size(Vphasor) == (N, T)
        @test isapprox(Vphasor[1, 1], 1.0 + 0.0im; atol = 1e-9)            # root reference
        @test isapprox(Vphasor[2, 1], 0.998 - 0.0015im; atol = 1e-6)       # closed-form phasor
        @test isapprox(abs2(Vphasor[2, 1]), 0.99600625; atol = 1e-8)       # magnitude ≡ v[2,1]
        @test isapprox(angle(Vphasor[2, 1]), -0.0015003; atol = 1e-4)      # small-angle identity
    end
end

@testitem "ac_oracle: assert_ac_exact! is defined (RED-guard for plan 15-02)" tags = [:ac_oracle] begin
    using TSODSO

    # Intentionally RED until plan 15-02 defines assert_ac_exact! alongside recover_voltage_angles
    # in this same file — so the Wave-0 gap is visible and the `ac_oracle` filter already
    # discovers this file.
    @test isdefined(TSODSO, :assert_ac_exact!)
end

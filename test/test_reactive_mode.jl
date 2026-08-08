# Seam: admm/ReactiveMode.jl (MESH-05). ReactiveMode 3-state enum + normalize_reactive_mode.
#
# Unit coverage for normalize_reactive_mode's Bool/Symbol/enum/invalid dispatch (plan 19-01).
# Unlike the RED-until-filled harnesses elsewhere in this suite, ReactiveMode is fully
# implemented in this same plan (self-contained, zero dependency on any other Phase-19 file),
# so these assertions are unconditional (no `isdefined` guard).

@testitem "reactive_mode: Bool back-compat (D-12)" tags = [:reactive] begin
    using TSODSO

    @test TSODSO.normalize_reactive_mode(false) == TSODSO.OFF
    @test TSODSO.normalize_reactive_mode(true) == TSODSO.CERTIFIED
end

@testitem "reactive_mode: Symbol dispatch" tags = [:reactive] begin
    using TSODSO

    @test TSODSO.normalize_reactive_mode(:off) == TSODSO.OFF
    @test TSODSO.normalize_reactive_mode(:certified) == TSODSO.CERTIFIED
    @test TSODSO.normalize_reactive_mode(:live) == TSODSO.LIVE
end

@testitem "reactive_mode: ReactiveMode identity" tags = [:reactive] begin
    using TSODSO

    @test TSODSO.normalize_reactive_mode(TSODSO.LIVE) == TSODSO.LIVE
    @test TSODSO.normalize_reactive_mode(TSODSO.OFF) == TSODSO.OFF
    @test TSODSO.normalize_reactive_mode(TSODSO.CERTIFIED) == TSODSO.CERTIFIED
end

@testitem "reactive_mode: invalid input throws ArgumentError" tags = [:reactive] begin
    using TSODSO

    @test_throws ArgumentError TSODSO.normalize_reactive_mode(:bogus)
    @test_throws ArgumentError TSODSO.normalize_reactive_mode(1)
end

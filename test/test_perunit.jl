# Seam: units/PerUnit.jl (INFRA-05). Driven green by plan 01-02.
@testitem "perunit: convert-once at ingestion + magnitude-sanity bands (INFRA-05)" begin
    using TSODSO

    # Documented placeholder base: S_base = 1.0 MVA, V_base = 4.16 kV (IEEE-13-ish).
    base = TSODSO.PerUnitBase(1.0, 4.16)

    # Derived bases (Ω and kA respectively).
    @test TSODSO.Z_base(base) ≈ 4.16^2 / 1.0
    @test TSODSO.I_base(base) ≈ 1.0 / (sqrt(3) * 4.16)

    # Convert-once helpers turn SI quantities into per-unit before struct construction.
    @test TSODSO.to_pu_power(1.0, base) ≈ 1.0
    @test TSODSO.to_pu_power(0.5, base) ≈ 0.5
    @test TSODSO.to_pu_impedance(TSODSO.Z_base(base), base) ≈ 1.0

    # In-band voltages pass quietly (return nothing).
    @test TSODSO.assert_magnitudes_voltage(1.0) === nothing
    @test TSODSO.assert_magnitudes_voltage(0.95) === nothing

    # Magnitude-sanity assertions must FIRE (loud AssertionError tripwire) on
    # out-of-band voltages — both too low (SI leaked in) and too high.
    @test_throws AssertionError TSODSO.assert_magnitudes_voltage(0.1)
    @test_throws AssertionError TSODSO.assert_magnitudes_voltage(1.5)
end

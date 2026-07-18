# Seam: units/PerUnit.jl (INFRA-05). RED until plan 01-02 fills the stub.
@testitem "perunit: convert-once at ingestion + magnitude-sanity bands (INFRA-05)" begin
    using TSODSO

    # Documented placeholder base: S_base = 1.0 MVA, V_base = 4.16 kV (IEEE-13-ish).
    base = TSODSO.PerUnitBase(1.0, 4.16)

    # Convert-once helpers turn SI quantities into per-unit before struct construction.
    @test TSODSO.to_pu_power(1.0, base) ≈ 1.0

    # Magnitude-sanity assertions must FIRE (loud tripwire) on out-of-band voltages.
    @test_throws Exception TSODSO.assert_magnitudes_voltage(0.1)
end

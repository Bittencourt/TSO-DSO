# Seam: data/profiles.jl (DATA-04). Seeded first-order Markov profile generator.
#
# Plan 03-02 fills the generator; this suite drives it GREEN. Every testitem name
# contains "profile" so `occursin("profile", ti.name)` selects the whole seam.
#
# Reproducibility is the contract (INFRA-04 / threat T-03-03): the tests below
# construct `StableRNGs.LehmerRNG` directly and assert that two same-seed streams
# yield `==` (bit-for-bit) results, while distinct seeds diverge. StableRNGs is a
# test dependency (test/Project.toml) precisely so the reproducibility assertion
# can pin an explicit, version-stable RNG stream.

@testitem "profile: markov_path seeded walk + row-stochastic guards (DATA-04)" tags =
    [:profile] begin
    using TSODSO
    using StableRNGs

    @test isdefined(TSODSO, :markov_path)

    # A genuinely mixing 3-state row-stochastic chain (rows sum to 1).
    P = [
        0.6 0.3 0.1
        0.2 0.6 0.2
        0.1 0.3 0.6
    ]

    # Shape: length-`steps` Int path starting at s0.
    path = TSODSO.markov_path(P, 1, 24, StableRNGs.LehmerRNG(11))
    @test path isa Vector{Int}
    @test length(path) == 24
    @test path[1] == 1                       # walk starts at s0
    @test all(s -> 1 <= s <= 3, path)        # every state is a valid row index

    # Determinism (INFRA-04, threat T-03-03): SAME seed → identical path, bit-for-bit.
    a = TSODSO.markov_path(P, 1, 24, StableRNGs.LehmerRNG(11))
    b = TSODSO.markov_path(P, 1, 24, StableRNGs.LehmerRNG(11))
    @test a == b

    # The walk actually consumes randomness: DIFFERENT seeds → different path.
    c = TSODSO.markov_path(P, 1, 64, StableRNGs.LehmerRNG(1))
    d = TSODSO.markov_path(P, 1, 64, StableRNGs.LehmerRNG(999))
    @test c != d

    # Guards (threat T-03-04, input validation V5): reject malformed matrices LOUDLY.
    P_nonsquare = [0.5 0.5 0.0; 0.2 0.3 0.5]          # 2×3, not square
    @test_throws ArgumentError TSODSO.markov_path(
        P_nonsquare,
        1,
        4,
        StableRNGs.LehmerRNG(1),
    )

    P_badrow = [0.6 0.3 0.2; 0.2 0.6 0.2; 0.1 0.3 0.6]  # row 1 sums to 1.1
    @test_throws ArgumentError TSODSO.markov_path(P_badrow, 1, 4, StableRNGs.LehmerRNG(1))
end

@testitem "profile: generate_profiles reproducible demand + PV (DATA-04)" tags = [:profile] begin
    using TSODSO

    @test isdefined(TSODSO, :generate_profiles)

    # T=24 hourly demand + PV vectors in per-unit (Assumption A4: parameters only).
    p = TSODSO.generate_profiles(; seed = 7, T = 24)
    @test hasproperty(p, :demand)
    @test hasproperty(p, :pv)
    @test length(p.demand) == 24
    @test length(p.pv) == 24

    # Magnitude sanity (threat T-03-05): non-negative, within a per-unit band.
    @test all(>=(0), p.demand)
    @test all(>=(0), p.pv)
    @test all(<=(2), p.demand)     # demand stays within a plausible per-unit band
    @test all(<=(2), p.pv)         # PV output stays within a plausible per-unit band

    # Reproducibility (INFRA-04, threat T-03-03): SAME seed → identical profiles ==.
    q = TSODSO.generate_profiles(; seed = 7, T = 24)
    @test p.demand == q.demand
    @test p.pv == q.pv

    # A DIFFERENT seed yields a different profile (randomness is actually consumed).
    r = TSODSO.generate_profiles(; seed = 123456, T = 24)
    @test (r.demand != p.demand) || (r.pv != p.pv)
end

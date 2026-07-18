# Seam: data/profiles.jl (DATA-04). Seeded first-order Markov profile generator.
#
# RED in Wave 0: the profile generator symbol does not exist yet — plan 03-02 turns
# this green. The name contains "profile" so `occursin("profile", ti.name)` selects it.

@testitem "profile: seeded Markov generator exists and is reproducible (DATA-04)" tags = [:profile] begin
    using TSODSO

    # Plan 03-02 will add the hand-rolled first-order Markov walk (RESEARCH Pattern 4).
    @test isdefined(TSODSO, :markov_path)
end

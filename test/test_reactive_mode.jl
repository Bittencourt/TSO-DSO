# Seam: admm/ReactiveMode.jl. ReactiveMode module (enum ReactiveMode.T) + normalize_reactive_mode.
#
# Unit coverage for the enum-only normalisation: identity on ReactiveMode.T, loud ArgumentError
# on every legacy Bool/Symbol spelling and on any other value.

@testitem "reactive_mode: enum identity" tags = [:reactive] begin
    using TSODSO

    for m in instances(ReactiveMode.T)
        @test TSODSO.normalize_reactive_mode(m) === m
    end
    @test ReactiveMode.LIVE isa ReactiveMode.T
    @test length(instances(ReactiveMode.T)) == 3
end

@testitem "reactive_mode: Bool, Symbol and other values throw ArgumentError" tags =
    [:reactive] begin
    using TSODSO

    for bad in (true, false, :live, :certified, :off, :bogus, 1, nothing)
        @test_throws ArgumentError TSODSO.normalize_reactive_mode(bad)
    end
end

@testitem "reactive_mode: error message names OFF, CERTIFIED and LIVE" tags = [:reactive] begin
    using TSODSO

    err = try
        TSODSO.normalize_reactive_mode(:live)
        nothing
    catch e
        e
    end
    @test err isa ArgumentError
    @test occursin("OFF", err.msg)
    @test occursin("CERTIFIED", err.msg)
    @test occursin("LIVE", err.msg)
end

@testitem "reactive_mode: generic names are not exported" tags = [:reactive] begin
    using TSODSO

    exported = names(TSODSO)
    @test :ReactiveMode in exported
    @test !(:OFF in exported)
    @test !(:CERTIFIED in exported)
    @test !(:LIVE in exported)
end

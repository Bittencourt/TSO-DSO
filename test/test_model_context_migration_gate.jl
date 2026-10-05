@testitem "ModelContext migration gate: no legacy meta keys" tags = [:context] begin
    using TSODSO

    # Built from pieces so this file never matches itself.
    legacy_re = Regex(
        "meta(\\[\\s*:|,\\s*:)(" *
        join(["pf_vars", "feeder", "T", "objective", "agg_device_vars"], "|") *
        ")\\b",
    )
    mirror_tag = "TRANSIENT" * "-MIRROR"
    root = abspath(joinpath(dirname(pathof(TSODSO)), ".."))
    me = abspath(@__FILE__)

    function scan(dirs, exts, rx_or_str; skip_generated = false, counter = nothing)
        hits = String[]
        for d in dirs
            dir = joinpath(root, d)
            isdir(dir) || continue
            for (r, _, files) in walkdir(dir)
                skip_generated && occursin("generated", relpath(r, root)) && continue
                for f in files
                    any(e -> endswith(f, e), exts) || continue
                    p = joinpath(r, f)
                    abspath(p) == me && continue
                    counter === nothing || (counter[] += 1)
                    for (i, line) in enumerate(eachline(p))
                        m =
                            rx_or_str isa Regex ? occursin(rx_or_str, line) :
                            occursin(rx_or_str, line)
                        m && push!(hits, "$(relpath(p, root)):$i: $(strip(line))")
                    end
                end
            end
        end
        return hits
    end

    nfiles = Ref(0)
    hits = scan(
        ["src", "test", "docs/literate", "scripts", "docs/src"],
        [".jl", ".md"],
        legacy_re;
        skip_generated = true,
        counter = nfiles,
    )
    # Non-vacuity: a missing directory (`isdir(dir) || continue`) must not make the gate pass.
    @test nfiles[] > 50
    @test isempty(hits) || (@info("legacy meta keys found", hits); false)

    mhits = scan(["src", "test"], [".jl"], mirror_tag)
    @test isempty(mhits) || (@info("mirror tag found", mhits); false)
end

@testitem "ModelContext migration gate: scanner is not vacuous" tags = [:context] begin
    legacy_re = Regex(
        "meta(\\[\\s*:|,\\s*:)(" *
        join(["pf_vars", "feeder", "T", "objective", "agg_device_vars"], "|") *
        ")\\b",
    )
    @test occursin(legacy_re, "x = ctx.meta[:pf_vars]")
    @test occursin(legacy_re, "haskey(ctx.meta, :feeder)")
    @test occursin(legacy_re, "get(ctx.meta, :T, 1)")
    @test occursin(legacy_re, "get!(ctx.meta, :agg_device_vars, Dict())")
    @test occursin(legacy_re, "ctx.meta[:objective] = 0")
    @test occursin(legacy_re, "ctx.meta[ :T]")
    @test !occursin(legacy_re, "ctx.meta[:device_vars]")
end

@testitem "ModelContext migration gate: typed fields exist" tags = [:context] begin
    using TSODSO
    for f in (:pf_vars, :feeder, :T, :objective, :agg_device_vars)
        @test f in fieldnames(TSODSO.ModelContext)
    end
end

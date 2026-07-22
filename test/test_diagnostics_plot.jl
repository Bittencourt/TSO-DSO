# test/test_diagnostics_plot.jl
#
# Seam: the plottable convergence diagnostics API (ADMM-05, RESEARCH Pattern 5 & 6).
#
# Wave 0 of Phase 7. Two concerns, both pinned here:
#   (1) the CORE STAYS PLOT-FREE (threat T-07-01): `plot_convergence` / `plot_price_convergence`
#       are exported generic functions with NO applicable method in the core (the CairoMakie
#       method lives in the TSODSOMakieExt weakdep extension, filled by plan 07-06), and
#       CairoMakie is NOT loaded by the core test suite. This item is GREEN once plan 07-01
#       Task 1 lands the stubs + weakdep wiring.
#   (2) the JuMP-free ledger records the traces the plots CONSUME (RESEARCH Pattern 5). GREEN
#       once plan 07-01 Task 2 lands the extended AdmmResiduals.
#
# Item names carry "plot" / "makie" / "diag" / "resid" so the VALIDATION filters select them.

@testitem "diagnostics plot: core stays plot-free, no applicable method (plot, makie)" begin
    using TSODSO

    # the plotting API symbols are ALWAYS exported by the core (so the ext has methods to extend).
    @test isdefined(TSODSO, :plot_convergence)
    @test isdefined(TSODSO, :plot_price_convergence)

    # ...but the core carries NO method (the CairoMakie-backed methods live in TSODSOMakieExt),
    # so the headless core suite never imports Makie.
    @test isempty(methods(TSODSO.plot_convergence))
    @test isempty(methods(TSODSO.plot_price_convergence))

    # CairoMakie / Makie must NOT be loaded by the core test process (threat T-07-01).
    loaded = string.(collect(keys(Base.loaded_modules)))
    @test !any(m -> occursin("CairoMakie", m), loaded)
    @test !any(m -> occursin("Makie", m), loaded)

    # calling a method-less generic on the ledger is a deliberate MethodError without CairoMakie.
    res = AdmmResiduals(2, 4)
    @test_throws MethodError plot_convergence(res)
    @test_throws MethodError plot_price_convergence(res)
end

@testitem "diagnostics resid: ledger records the traces the plots consume (diag, resid, plot)" begin
    using TSODSO

    res = AdmmResiduals(11, 24)
    @test res.iters == 0

    # the six traces the plots consume exist and start empty (RESEARCH Pattern 5).
    for tr in (
        res.primal_trace,
        res.dual_trace,
        res.rho_trace,
        res.eps_pri_trace,
        res.eps_dual_trace,
        res.price_gap_trace,
    )
        @test tr isa Vector{Float64}
        @test isempty(tr)
    end

    # the EXTENDED 8-arg record! pushes to every trace; all stay length-consistent.
    record!(res, 1, 0.5, 0.3, 5.0, 1e-4, 2e-4, 0.9)
    record!(res, 2, 0.2, 0.1, 10.0, 1e-4, 2e-4, 0.4)
    @test res.iters == 2
    for tr in (
        res.primal_trace,
        res.dual_trace,
        res.rho_trace,
        res.eps_pri_trace,
        res.eps_dual_trace,
        res.price_gap_trace,
    )
        @test length(tr) == res.iters
    end
    @test res.rho_trace == [5.0, 10.0]

    # the RETAINED Phase-6 4-arg record! NaN-pads the four new traces (no baseline regression).
    record!(res, 3, 0.05, 0.02)
    @test res.iters == 3
    @test isnan(res.rho_trace[3])
    @test isnan(res.eps_pri_trace[3])
    @test isnan(res.eps_dual_trace[3])
    @test isnan(res.price_gap_trace[3])
    @test res.primal_trace[3] == 0.05        # the primal/dual magnitudes are still recorded
end

# --- WITH-CairoMakie path (plan 07-06): the ext method lights up and returns a Figure -------
#
# This item exercises the OTHER half of the isolation contract: WITH CairoMakie loaded, the
# TSODSOMakieExt weakdep extension activates and `plot_convergence` / `plot_price_convergence`
# gain an `AdmmResiduals` method that returns a `Makie.Figure`.
#
# It runs the check in a SEPARATE Julia PROCESS (`import CairoMakie` in a child) — never in the
# headless core test process — because package loading is PROCESS-GLOBAL: importing CairoMakie
# here would activate the ext for the whole worker and break the "core stays plot-free" sibling
# item above (threat T-07-17). If CairoMakie is not installed in the active environment (it is a
# weakdep, not a hard dep — the headless/CI case), the item is SKIPPED-with-message, not failed,
# so the core suite stays green and plot-free. The FIGURE AESTHETICS are the manual-only check
# (07-VALIDATION): run `import CairoMakie; using TSODSO`, then
# `save("conv.pdf", plot_convergence(res))` / `save("price.pdf", plot_price_convergence(res))`.
@testitem "diagnostics plot: ext returns a Makie Figure when CairoMakie is loaded (plot, makie)" begin
    using TSODSO

    if Base.find_package("CairoMakie") === nothing
        @info "CairoMakie not installed (weakdep) — SKIPPING the with-CairoMakie Figure check; " *
              "the headless core suite stays plot-free. Aesthetics are the manual-only 07-VALIDATION check."
        # skipped-with-message: the with-CairoMakie ext-method path is exercised only where
        # CairoMakie is present (a separate, non-headless environment).
        @test_skip Base.find_package("CairoMakie") !== nothing
    else
        proj = dirname(Base.active_project())
        code = raw"""
        import CairoMakie
        using TSODSO
        res = AdmmResiduals(2, 4)
        record!(res, 1, 0.5, 0.3, 5.0, 1e-4, 2e-4, 0.9)
        record!(res, 2, 0.2, 0.1, 10.0, 1e-4, 2e-4, 0.4)
        # WITH CairoMakie loaded the ext activates: the generics now HAVE an AdmmResiduals method.
        @assert hasmethod(TSODSO.plot_convergence, Tuple{AdmmResiduals})
        @assert hasmethod(TSODSO.plot_price_convergence, Tuple{AdmmResiduals})
        f1 = TSODSO.plot_convergence(res)
        f2 = TSODSO.plot_price_convergence(res)
        @assert f1 isa CairoMakie.Makie.Figure "plot_convergence must return a Makie Figure"
        @assert f2 isa CairoMakie.Makie.Figure "plot_price_convergence must return a Makie Figure"
        println("MAKIE_EXT_OK")
        """
        out = read(`$(Base.julia_cmd()) --project=$proj -e $code`, String)
        @test occursin("MAKIE_EXT_OK", out)
    end
end

# docs/make.jl
#
# Minimal Documenter + Literate build proving the reproducibility pipeline
# (Phase 1). Literate turns `docs/literate/toy_dc.jl` into a Documenter markdown
# page whose `@example` blocks Documenter EXECUTES during `makedocs` — so the
# rendered numbers cannot drift from the real `solve_toy_dc` code (threat
# T-01-09). Full per-model math docs are Phase 9 (EXP-03).

using Documenter
using Literate
using TSODSO

const LITERATE_DIR = joinpath(@__DIR__, "literate")
const GENERATED_DIR = joinpath(@__DIR__, "src", "generated")

# Render each Literate source to a Documenter markdown page. `documenter = true`
# emits `@example` blocks, so the toy solve runs during `makedocs` below.
Literate.markdown(
    joinpath(LITERATE_DIR, "toy_dc.jl"),
    GENERATED_DIR;
    documenter = true,
)

makedocs(;
    sitename = "TSODSO",
    modules = [TSODSO],
    authors = "Pedro Bittencourt",
    format = Documenter.HTML(; prettyurls = get(ENV, "CI", nothing) == "true"),
    # No repo source links: the build must succeed in a bare/worktree checkout
    # where Documenter cannot infer a remote. Re-enable when deploying from CI.
    remotes = nothing,
    pages = [
        "Home" => "index.md",
        "Rung 0: Toy DC" => "generated/toy_dc.md",
    ],
    # Phase 1 is a pipeline proof, not the API-docs phase: don't fail the build on
    # missing docstrings or cross-references (those land with EXP-03 in Phase 9).
    checkdocs = :none,
    warnonly = [:missing_docs, :cross_references],
)

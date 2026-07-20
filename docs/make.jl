# docs/make.jl
#
# Documenter + Literate build for the full six-rung abstraction ladder (Phase 1
# proved the pipeline with a single page; Phase 9 / EXP-03 wires all six). Every
# `docs/literate/*.jl` source becomes a Documenter markdown page whose `@example`
# blocks Documenter EXECUTES during `makedocs` — so the rendered numbers cannot
# drift from the real `src/` code (threat T-01-09 / T-09-03).

using Documenter
using Literate
using TSODSO

const LITERATE_DIR = joinpath(@__DIR__, "literate")
const GENERATED_DIR = joinpath(@__DIR__, "src", "generated")

# Render each Literate source to a Documenter markdown page. `flavor =
# Literate.DocumenterFlavor()` emits `@example` blocks, so every solve below runs
# during `makedocs` (the non-deprecated replacement for the old `documenter = true`
# kwarg — RESEARCH Pitfall 1; migrated here for the existing `toy_dc.jl` call too).
for src in (
    "toy_dc.jl", "lindistflow.jl", "convex_branch_flow.jl",
    "prosumer_welfare.jl", "pricing_dlmp.jl", "admm.jl",
)
    Literate.markdown(
        joinpath(LITERATE_DIR, src), GENERATED_DIR;
        flavor = Literate.DocumenterFlavor(),
    )
end

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
        "Models" => [
            "Rung 0: Toy DC" => "generated/toy_dc.md",
            "Rung 1-2: LinDistFlow" => "generated/lindistflow.md",
            "Rung 3: SOCP + Exactness" => "generated/convex_branch_flow.md",
            "Rung 3: Devices + GLB-CVX" => "generated/prosumer_welfare.md",
            "Rung 4: DADP/DLMP Pricing" => "generated/pricing_dlmp.md",
            "Rung 5: ADMM Decomposition" => "generated/admm.md",
        ],
    ],
    # Tightened from :none (Phase 1) to :exports (Phase 9 EXP-03): fail the build
    # on undocumented PUBLIC-API (exported) symbols, cross-version-safe on the 1.10
    # LTS floor (RESEARCH Pitfall 4). `warnonly` still covers residual gaps so the
    # build stays green while surfacing them.
    checkdocs = :exports,
    warnonly = [:missing_docs, :cross_references],
)

# Deploy only from CI (never from a local/worktree checkout — Pitfall 5 / the same
# `remotes = nothing` rationale above). The repo slug below is a PLACEHOLDER — it
# must be confirmed against the real GitHub org/repo before this ever runs in CI
# (see plan 09-05 Task 2, the human-verify checkpoint that confirms/updates it).
if get(ENV, "CI", nothing) == "true"
    deploydocs(; repo = "github.com/PLACEHOLDER-ORG/PLACEHOLDER-REPO.git")
end

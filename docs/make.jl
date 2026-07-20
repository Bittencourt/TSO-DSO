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
    # Tightened from :none (Phase 1) to :exports (Phase 9 EXP-03): check undocumented
    # PUBLIC-API (exported) symbols and broken `@ref`s, cross-version-safe on the 1.10
    # LTS floor (RESEARCH Pitfall 4). NOTE: `:missing_docs` and `:cross_references` are
    # BOTH in `warnonly` below, so this check is currently non-fatal — it SURFACES
    # docstrings-not-in-manual and unresolved `@ref`s as build warnings but does NOT fail
    # the build on them (locked CONTEXT.md decision: "keep `warnonly` for the remainder
    # so the build stays green while surfacing missing docs"). Documenter currently reports
    # ~104 exported-symbol docstrings that EXIST in `src/` but are not yet wired into the
    # rendered manual via `@docs`/`@autodocs` blocks (NOT 104 undocumented symbols — the
    # docstrings are written; they just aren't surfaced on a page). Adding those blocks and
    # then dropping `:missing_docs`/`:cross_references` from `warnonly` (making this a true
    # hard-fail gate) is the tracked follow-up, deferred, not done here.
    checkdocs = :exports,
    warnonly = [:missing_docs, :cross_references],
)

# Deploy only from CI (never from a local/worktree checkout — Pitfall 5 / the same
# `remotes = nothing` rationale above).
#
# TODO(deploydocs repo slug): the slug below is a PLACEHOLDER, kept intentionally
# per researcher decision on plan 09-05's human-verify checkpoint (this checkout has
# no git remote configured, so the real org/repo could not be discovered locally).
# It is gated on `CI == "true"`, so it is inert until this workflow actually runs in
# GitHub Actions. It MUST be replaced with the real `github.com/ORG/REPO` slug (and
# DOCUMENTER_KEY/GITHUB_TOKEN wiring confirmed) before the first real gh-pages deploy.
if get(ENV, "CI", nothing) == "true"
    deploydocs(; repo = "github.com/PLACEHOLDER-ORG/PLACEHOLDER-REPO.git")
end

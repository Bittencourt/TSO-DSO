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
    "toy_dc.jl",
    "lindistflow.jl",
    "convex_branch_flow.jl",
    "ac_oracle.jl",             # NEW: Rung 3 AC-exactness oracle (EXACT-04)
    "restricted_branch_flow.jl", # NEW: Rung 3 overvoltage-capable restriction (OVR-01..04)
    "prosumer_welfare.jl",
    "pricing_dlmp.jl",
    "admm.jl",
    "stackelberg_benders.jl",   # NEW: Rung 6
    "nash_diagonalization.jl",  # NEW: Rung 7
    "ieee123_impedances.jl",    # NEW: real IEEE-123 impedance reduction (IMPED-01/02)
    "thesis_reproduction_ieee123.jl",  # NEW: thesis reproduction — IEEE-123 real-impedance DSO-surplus sign flip (REPRO-01)
    "thesis_reproduction_assumptions.jl",  # NEW: thesis reproduction assumptions/reduction chain (REPRO-02)
    # SOC-relaxation applicability maps. Substrate A (3-bus, ~70 s) is solved LIVE here;
    # substrate B (real IEEE-123, ~16 min) is loaded from results/socp_applicability/ because
    # it exceeds this job's whole CI timeout. See the page's own note.
    "socp_applicability.jl",
    # IEEE-8500 scalability benchmark (phase 25, SCALE-05): a cheap live slice (ieee8500-mv,
    # lowest density, Clarabel only) + the committed cross-fixture density-sweep curve, following
    # socp_applicability.jl's own precomputed-results precedent (D-17 REVISED) — the full grid
    # (including the 4,875-bus headline point) exceeds this job's CI timeout AND, at this scale,
    # the measurement machine's available RAM; see the page's own note.
    "ieee8500_scaling.jl",
    "mpc_rolling_horizon.jl",   # NEW: Rung 8 MPC / rolling-horizon RTP closed loop (MPC-01..04)
    "stochastic_pv_demand.jl", # NEW: Rung 9 Stochastic PV/Demand Uncertainty (STOCH-01..04)
    "meshed_reactive_price.jl", # NEW: Rung 10 Meshed Networks + Live Reactive Price (MESH-01..03,06)
    "integer_investment.jl",   # NEW: Rung 11 Discrete/Integer Investment Expansion (INT-01..04)
    "experiments.jl",           # NEW: the Phase-8 experiment harness (Scenario / run_scenario / run_and_store / run_sweep)
)
    Literate.markdown(
        joinpath(LITERATE_DIR, src),
        GENERATED_DIR;
        flavor = Literate.DocumenterFlavor(),
    )
end

makedocs(;
    sitename = "TSODSO",
    modules = [TSODSO],
    authors = "Pedro Bittencourt",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        # The consolidated `api.md` (full @autodocs of the ~100-symbol public API on one
        # page) exceeds Documenter's default 200 KiB per-page HTML size_threshold. Raise
        # the hard limit (and the warn threshold) so the single API-reference page builds;
        # all other pages are well under this.
        size_threshold = 600 * 1024,
        size_threshold_warn = 400 * 1024,
    ),
    # No repo source links: the build must succeed in a bare/worktree checkout
    # where Documenter cannot infer a remote. Re-enable when deploying from CI.
    remotes = nothing,
    pages = [
        "Home" => "index.md",
        "Models" => [
            "Rung 0: Toy DC" => "generated/toy_dc.md",
            "Rung 1-2: LinDistFlow" => "generated/lindistflow.md",
            "Rung 3: SOCP + Exactness" => "generated/convex_branch_flow.md",
            "Rung 3: AC-Exactness Oracle" => "generated/ac_oracle.md",
            "Rung 3: Overvoltage-Capable Restriction" => "generated/restricted_branch_flow.md",
            "Rung 3: Devices + GLB-CVX" => "generated/prosumer_welfare.md",
            "Rung 4: DADP/DLMP Pricing" => "generated/pricing_dlmp.md",
            "Rung 5: ADMM Decomposition" => "generated/admm.md",
            "IEEE-123 Real Impedances" => "generated/ieee123_impedances.md",
            "Thesis Reproduction — IEEE-123" => "generated/thesis_reproduction_ieee123.md",
            "Thesis Reproduction — Assumptions" => "generated/thesis_reproduction_assumptions.md",
            "SOC Relaxation Applicability" => "generated/socp_applicability.md",
            "Scaling to IEEE-8500" => "generated/ieee8500_scaling.md",
            "Rung 8: MPC / Rolling-Horizon RTP" => "generated/mpc_rolling_horizon.md", # from mpc_rolling_horizon.jl
            "Rung 9: Stochastic PV/Demand Uncertainty" => "generated/stochastic_pv_demand.md",
            "Rung 10: Meshed Networks + Live Reactive Price" => "generated/meshed_reactive_price.md",
        ],
        "Experiments" => ["The Experiment Harness" => "generated/experiments.md"],
        "Planning" => [
            "Rung 6: Stackelberg-Benders" => "generated/stackelberg_benders.md",
            "Rung 7: Nash Diagonalization & Shared Corridor" => "generated/nash_diagonalization.md",
            "Rung 11: Discrete/Integer Investment Expansion" => "generated/integer_investment.md",
        ],
        "API Reference" => "api.md",
    ],
    # `checkdocs = :exports`: verify every DOCUMENTED exported symbol's docstring is
    # surfaced somewhere in the manual. The `api.md` page wires the full module docstring
    # set in via `@autodocs` blocks, so exported docstrings now appear in the rendered docs.
    # `:missing_docs` is NO LONGER in `warnonly` — a documented-but-UNSURFACED exported
    # symbol now FAILS the build (the tracked Phase-9 follow-up, completed here). KNOWN
    # LIMIT (Phase 14 review WR-02): an exported symbol with NO docstring at all passes
    # `checkdocs` silently — docstring EXISTENCE is enforced by review convention, not by
    # this build gate; and every `api.md` `@autodocs` block must keep `:constant` in its
    # `Order`, or the first docstring added to an exported constant in that section turns
    # into a delayed build failure here. `:cross_references` stays in `warnonly` (broken
    # `@ref`s remain non-fatal, cross-version-safe on the 1.10 LTS floor per RESEARCH
    # Pitfall 4) so an unrelated stray link doesn't break the docs deploy.
    checkdocs = :exports,
    warnonly = [:cross_references],
)

# Deploy only from CI (never from a local/worktree checkout — Pitfall 5 / the same
# `remotes = nothing` rationale above).
#
# Gated on `CI == "true"`, so it is inert locally and only runs in GitHub Actions.
# For the first gh-pages deploy to succeed, wire a deploy credential in CI — either a
# `DOCUMENTER_KEY` SSH deploy key (recommended) or `GITHUB_TOKEN` (needs Pages enabled
# + workflow `permissions: contents: write`). `devbranch` matches the repo default branch.
if get(ENV, "CI", nothing) == "true"
    deploydocs(; repo = "github.com/Bittencourt/TSO-DSO.git", devbranch = "main")
end

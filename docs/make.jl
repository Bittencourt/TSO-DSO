# docs/make.jl
#
# Documenter + Literate build for the full abstraction ladder. Every
# `docs/literate/*.jl` source becomes a Documenter markdown page whose `@example`
# blocks Documenter EXECUTES during `makedocs` — so the rendered numbers cannot
# drift from the real `src/` code.

using Documenter
using Literate
using TSODSO

const LITERATE_DIR = joinpath(@__DIR__, "literate")
const GENERATED_DIR = joinpath(@__DIR__, "src", "generated")

# Render each Literate source to a Documenter markdown page. `flavor =
# Literate.DocumenterFlavor()` emits `@example` blocks, so every solve below runs
# during `makedocs` (the non-deprecated replacement for the old `documenter = true`
# kwarg; the `toy_dc.jl` call uses it too).
for src in (
    "toy_dc.jl",
    "lindistflow.jl",
    "convex_branch_flow.jl",
    "ac_oracle.jl",             # Rung 3 AC-exactness oracle
    "restricted_branch_flow.jl", # Rung 3 overvoltage-capable restriction
    "prosumer_welfare.jl",
    "pricing_dlmp.jl",
    "admm.jl",
    "stackelberg_benders.jl",   # Rung 6
    "nash_diagonalization.jl",  # Rung 7
    "ieee123_impedances.jl",    # real IEEE-123 impedance reduction
    "thesis_reproduction_ieee123.jl",  # thesis reproduction — IEEE-123 real-impedance DSO-surplus sign flip
    "thesis_reproduction_assumptions.jl",  # thesis reproduction assumptions/reduction chain
    # SOC-relaxation applicability maps. Substrate A (3-bus, ~70 s) is solved LIVE here;
    # substrate B (real IEEE-123, ~16 min) is loaded from results/socp_applicability/ because
    # it exceeds this job's whole CI timeout. See the page's own note.
    "socp_applicability.jl",
    "socp_highpv_exactness.jl",   # DEV-09 high-PV exactness re-measurement + Volt-VAR comparator
    "aggregator_actor.jl",        # Phase 44 aggregator-as-actor: retail wedge, shared buses, behavioural scenarios
    # IEEE-8500 scalability benchmark: a cheap live slice (ieee8500-mv,
    # lowest density, Clarabel only) + the committed cross-fixture density-sweep curve, following
    # socp_applicability.jl's own precomputed-results precedent — the full grid
    # (including the 4,875-bus headline point) exceeds this job's CI timeout AND, at this scale,
    # the measurement machine's available RAM; see the page's own note.
    "ieee8500_scaling.jl",
    "mpc_rolling_horizon.jl",   # Rung 8 MPC / rolling-horizon RTP closed loop
    "stochastic_pv_demand.jl", # Rung 9 Stochastic PV/Demand Uncertainty
    "meshed_reactive_price.jl", # Rung 10 Meshed Networks + Live Reactive Price
    "integer_investment.jl",   # Rung 11 Discrete/Integer Investment Expansion
    "experiments.jl",           # the experiment harness (Scenario / run_scenario / run_and_store / run_sweep)
    # The thesis-scale Case A population (784 houses → 10 bus-level aggregators):
    # composition measured LIVE (build-only — no solves), calibration provenance, and
    # the agreement/scaling sections read from results/case_a_population/ (the
    # committed-CSV pattern this page set's precomputed pages follow).
    "case_a_population.jl",
    # Settlement, tariffs & equity (Phase 41): a seconds-scale live slice (2-bus ledger,
    # revenue-neutral flat/TOU, price-taker, feasibility status, equity metrics) plus the
    # tariff-comparison sections read from results/settlement_comparison/ — the same
    # committed-CSV pattern as the Case-A population page above.
    "settlement_equity.jl",
    "flex_market.jl",           # flexibility market vs price coordination, read from results/settlement_comparison/
    # Case A welfare-gain magnitude (Phase 42): the honest pre-registered measurement's
    # writeup. The live/precomputed split here is TOTAL — the page SOLVES NOTHING at all:
    # its whole live slice is reading results/thesis_case_a_magnitude/*.csv (a
    # seconds-scale committed-CSV read; the docs 30-min CI budget is safe), and every
    # derived percentage is recomputed LIVE from the committed rows (the Phase-28 CR-01
    # no-stale-derived-figures discipline) — following the settlement_equity.jl
    # committed-CSV page pattern.
    "case_a_magnitude.jl",
)
    Literate.markdown(
        joinpath(LITERATE_DIR, src),
        GENERATED_DIR;
        flavor = Literate.DocumenterFlavor(),
    )
end

makedocs(;
    sitename = "TSODSO",
    modules = [TSODSO, TSODSO.ReactiveMode],
    authors = "Pedro Bittencourt",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", nothing) == "true",
        # The consolidated `api.md` (full @autodocs of the public API on one page) exceeds
        # Documenter's default 200 KiB per-page HTML size_threshold. Raised once already
        # (commit dc0de79) to 600/400 KiB; since then the page has organically
        # grown to 676.24 KiB (more exported symbols and docstrings) and
        # tripped that limit too. Raised again with headroom for further growth rather
        # than re-bumping repeatedly; all other pages are well under this.
        size_threshold = 1024 * 1024,
        size_threshold_warn = 800 * 1024,
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
            "SOCP Exactness in High-PV (optimal Q)" => "generated/socp_highpv_exactness.md",
            "Aggregator as Actor (wedge, behaviour)" => "generated/aggregator_actor.md",
            "Scaling to IEEE-8500" => "generated/ieee8500_scaling.md",
            "Rung 8: MPC / Rolling-Horizon RTP" => "generated/mpc_rolling_horizon.md", # from mpc_rolling_horizon.jl
            "Rung 9: Stochastic PV/Demand Uncertainty" => "generated/stochastic_pv_demand.md",
            "Rung 10: Meshed Networks + Live Reactive Price" => "generated/meshed_reactive_price.md",
        ],
        "Experiments" => [
            "The Experiment Harness" => "generated/experiments.md",
            "Case A Population (784 houses)" => "generated/case_a_population.md",
            "Settlement, Tariffs & Equity" => "generated/settlement_equity.md",
            "Flexibility Market vs Price Coordination" => "generated/flex_market.md",
            "Case A Magnitude" => "generated/case_a_magnitude.md",
        ],
        "Status & Exception Policy" => "status_policy.md",
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
    # symbol now FAILS the build. KNOWN
    # LIMIT: an exported symbol with NO docstring at all passes
    # `checkdocs` silently — docstring EXISTENCE is enforced by review convention, not by
    # this build gate; and every `api.md` `@autodocs` block must keep `:constant` in its
    # `Order`, or the first docstring added to an exported constant in that section turns
    # into a delayed build failure here. `:cross_references` stays in `warnonly` (broken
    # `@ref`s remain non-fatal, cross-version-safe on the 1.10 LTS floor)
    # so an unrelated stray link doesn't break the docs deploy.
    checkdocs = :exports,
    warnonly = [:cross_references],
)

# Deploy only from CI (never from a local/worktree checkout — the same
# `remotes = nothing` rationale above).
#
# Gated on `CI == "true"`, so it is inert locally and only runs in GitHub Actions.
# For the first gh-pages deploy to succeed, wire a deploy credential in CI — either a
# `DOCUMENTER_KEY` SSH deploy key (recommended) or `GITHUB_TOKEN` (needs Pages enabled
# + workflow `permissions: contents: write`). `devbranch` matches the repo default branch.
if get(ENV, "CI", nothing) == "true"
    deploydocs(; repo = "github.com/Bittencourt/TSO-DSO.git", devbranch = "main")
end

# src/solver/factory.jl
#
# SEAM: the single solver factory (INFRA-02).
# OWNER: plan 01-03.
#
# This is the ONLY core file (besides the ext/* package extensions) that names
# concrete solvers. `select_optimizer(::ProblemClass)` returns a JuMP-ready
# optimizer factory (`optimizer_with_attributes(...)`). Model files never name a
# solver — they call `Model(select_optimizer(LP()))`. Commercial solvers
# (Gurobi/MosekTools) are reachable ONLY via the weakdep package extensions in
# ext/, which add `commercial_optimizer` methods.
#
# RESEARCH Pitfall 1 correction to the CLAUDE.md perf note (VERIFIED 2026-07-18):
#   Clarabel is a `copy_to`-only solver (`supports_incremental_interface == false`).
#   `direct_model(Clarabel.Optimizer())` ERRORS. Use a standard `Model(...)`
#   (auto-wrapped in a CachingOptimizer) for anything Clarabel-backed. Reserve
#   `direct_model` for HiGHS-backed hot loops only. Do NOT call
#   `direct_model` with any Clarabel-backed factory returned here.

using JuMP
import HiGHS
import Clarabel
import Ipopt

# `output_flag => false` (LP/MILP below): silence HiGHS's per-solve console log, matching
# the factory's existing convention for Clarabel (`verbose => false`) and Ipopt
# (`print_level => 0`). Previously the one unsilenced backend — its raw "Objective value
# ... HiGHS run time" blocks leaked into test logs and into the Documenter-executed
# planning literate pages (Phase 14 review WR-03). Nothing in src/ or test/ depends on
# HiGHS console output. (Comment deliberately sits ABOVE the docstring: a comment BETWEEN
# a docstring and its definition detaches the docstring — verified on Julia 1.12.)
"""
    select_optimizer(pc::ProblemClass)

Return a JuMP-ready optimizer factory (from `optimizer_with_attributes`) for the
given problem class `pc`. Dispatched by singleton type — there is no `if class ==`
branching — so weakdep extensions can extend the commercial path independently.

Open-source defaults:

  - `LP`   → HiGHS (presolve on)
  - `MILP` → HiGHS
  - `QP`   → Clarabel (native quadratic objective)
  - `SOCP` → Clarabel (tight duality-gap tolerances for accurate duals / prices)
  - `NLP`  → Ipopt

A model file uses this as `Model(select_optimizer(LP()))` and never names a solver.

The `NLP` method additionally accepts backend attribute overrides as keyword arguments —
`select_optimizer(NLP(); mu_strategy = "adaptive")` — layered on top of the factory's own
base attributes. This is the INFRA-02 seam that lets callers (e.g.
[`ac_dual_fallback_price`](@ref)'s D-11 multi-start loop, via
[`nlp_multistart_variants`](@ref)) vary the NLP backend's convergence strategy WITHOUT
naming the concrete solver outside this file (review WR-04).
"""
select_optimizer(::LP) =
    optimizer_with_attributes(HiGHS.Optimizer, "presolve" => "on", "output_flag" => false)

select_optimizer(::MILP) =
    optimizer_with_attributes(HiGHS.Optimizer, "output_flag" => false)

select_optimizer(::QP) = optimizer_with_attributes(Clarabel.Optimizer, "verbose" => false)

# Tight gap tolerances: transactive prices ARE the duals, so accurate conic duals
# matter. Clarabel's `tol_gap_abs`/`tol_gap_rel` default to 1e-8; set explicitly.
#
# Plan 22-02 (STOCH-01) deviation (Rule 1 — auto-fixed bug): keyword overrides, mirroring
# the `NLP` method's own established pattern below — layered ON TOP of the `tol_gap_abs/
# rel = 1e-8` base (a duplicate key passed later wins in `optimizer_with_attributes`, so
# callers can only ADD/OVERRIDE, never lose the base tightness unless they explicitly
# override it). `select_optimizer(SOCP())` with NO kwargs stays BYTE-IDENTICAL to the prior
# behavior. Added because `build_stochastic_welfare`'s probability-weighted extensive-form
# objective genuinely weakens each scenario's own loss-cost gradient (scaled by that
# scenario's `probabilities[s]`), which — empirically verified this plan, on a near-lossless
# branch — can leave Clarabel's default `tol_gap=1e-8` interior-point iterate measurably
# short of the SOC cone's true (unique, gradient-driven) tight point for a LOW-probability
# scenario, tripping the PF-04 exactness gate on a genuinely tiny (not structural) residual.
# Tightening `tol_gap_abs/rel` resolves it (verified: 5.6e-6 → 4.8e-8 at the builder's chosen
# `5e-10`) because the true optimum IS exactly cone-tight (any slack costs objective value,
# however marginally) — a convergence-precision fix, not a tolerance-weakening of the
# exactness GATE itself. `build_stochastic_welfare` picked `5e-10` (not a more aggressive
# `1e-10`) after sweeping BOTH this near-lossless fixture and a separate, more-lossy one and
# finding `1e-10` alone measurably trips `ALMOST_OPTIMAL` on the lossier feeder.
select_optimizer(::SOCP; attrs...) = optimizer_with_attributes(
    Clarabel.Optimizer,
    "verbose" => false,
    "tol_gap_abs" => 1e-8,
    "tol_gap_rel" => 1e-8,
    (String(k) => v for (k, v) in pairs(attrs))...,
)

# Keyword overrides layer ON TOP of the factory base ("print_level" => 0); a duplicate key
# passed later wins in optimizer_with_attributes, so callers can only ADD/OVERRIDE
# attributes, never lose the silencing default unless they explicitly override it.
select_optimizer(::NLP; attrs...) = optimizer_with_attributes(
    Ipopt.Optimizer,
    "print_level" => 0,
    (String(k) => v for (k, v) in pairs(attrs))...,
)

"""
    nlp_multistart_variants() -> Vector{<:NamedTuple}

The 5 distinct, DETERMINISTIC NLP-backend convergence-strategy variants used as "seeded
starts" by [`ac_dual_fallback_price`](@ref)'s D-11 multi-start agreement evidence. Each
entry is an attribute set to splat into [`select_optimizer`](@ref) —
`select_optimizer(NLP(); variant...)` — and is documented as its DELTA from the factory's
NLP base configuration (`print_level = 0` only, i.e. the backend's own defaults otherwise:
`mu_strategy = "monotone"`, `nlp_scaling_method = "gradient-based"`, `bound_push = 0.01`).

Lives HERE (not in models/ac_dual_fallback.jl) because the attribute vocabulary is
inherently backend-specific (Ipopt option names): this factory is the ONLY core file that
names concrete solvers or their option vocabulary (INFRA-02, review WR-04). If the NLP
backend ever changes, this list changes WITH it in the same file — no model silently pins
the old solver.

Review WR-03: the previous variant 3, `(; mu_strategy = "monotone")`, was byte-identical to
variant 1 ("monotone" IS the backend default) — a duplicate "seed" that always agreed with
seed 1 exactly, silently overstating D-11's multi-start agreement evidence. All 5 variants
are genuinely distinct solver configurations.
"""
nlp_multistart_variants() = [
    (;),                                              # 1: NLP() factory default (monotone μ)
    (; mu_strategy = "adaptive"),                     # 2: adaptive μ update
    (; mu_strategy = "adaptive", bound_push = 1e-4),  # 3: adaptive μ + tighter interior start
    (; nlp_scaling_method = "none"),                  # 4: unscaled NLP (monotone μ)
    (; mu_strategy = "adaptive", nlp_scaling_method = "none"),  # 5: adaptive μ, unscaled
]

"""
    commercial_optimizer(choice, pc::ProblemClass)

Return a JuMP-ready optimizer factory for a commercial solver selected by `choice`
(a [`GurobiChoice`](@ref) or [`MosekChoice`](@ref) marker) for problem class `pc`.

This fallback method ERRORS by design: commercial backends are opt-in and are
wired in only by the `TSODSOGurobiExt` / `TSODSOMosekExt` package extensions,
which add methods for the concrete marker types. To enable one, `import Gurobi`
(or `import MosekTools`) in your environment before calling.
"""
function commercial_optimizer(choice, pc::ProblemClass)
    error(
        """
        No commercial optimizer is available for choice $(choice) and problem class $(pc).
        Commercial solvers are opt-in weakdep extensions and are never hard dependencies.
        To enable one, load the solver in your environment, e.g.:
            import Gurobi      # enables commercial_optimizer(GurobiChoice(), pc)
            import MosekTools  # enables commercial_optimizer(MosekChoice(), pc)
        """,
    )
end

export select_optimizer, commercial_optimizer

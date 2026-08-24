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

# Phase 24 (24-RESEARCH.md Priority Finding 4, live-verified against the installed HiGHS
# 1.24.1): the runtime default `mip_rel_gap = 1e-4` is NOT overridden by `output_flag =>
# false` alone — a MILP master could report `objective_value` up to 1e-4 RELATIVE short of
# its own true optimum for the current cut set, silently laundering any later "exact lattice
# termination" claim built on top of it (D-13). Set explicitly to `0.0`. `MILP()` had ZERO
# call sites before this phase (confirmed repo-wide), so this changes no existing behavior.
# Empirically verified (test/test_solver_factory_milp.jl) that `mip_rel_gap => 0.0` does NOT
# stall branch-and-bound on this project's tiny toy instances.
#
# Phase 24 GAP-CLOSURE (plan 24-05.1): `mip_feasibility_tolerance` ALSO needed tightening
# from HiGHS's runtime default (1e-6) — empirically confirmed (this session) to be the ROOT
# CAUSE of a genuine, DETERMINISTIC (bit-for-bit reproducible across runs, never flaky)
# residual between the certified master's own reported incumbent (`result.UB`, from a REAL
# `solve_follower!`/`solve_planning_oracle!` re-solve at the master's own trial `z`) and the
# `test/test_planning_certification_integer.jl` enumeration harness's independently-computed
# reference value: at the DEFAULT `mip_feasibility_tolerance = 1e-6`, HiGHS accepts a
# continuous `z` up to ~1e-6 outside its own box bound `z <= y_inv` as "MIP-feasible" — at a
# corner whose TRUE argmin sits exactly ON that box boundary (confirmed on the D-12 fixture:
# `y_inv=0.5`, follower/oracle net cost strictly decreasing on `[0, y_inv]`, argmin at the
# right endpoint), this ~1e-6 slack in the ACCEPTED `z` translates via the recourse
# function's own local slope into an ~7e-8 residual in the reported cost — small, but larger
# than `KNOWN_OPTIMUM_ATOL` (`benders.jl`, ~4e-8), so the certified exact-match convergence
# test could never pass no matter how many further Benders iterations ran (the master
# reaches this SAME numerically-limited fixed point and stops improving). Tightening to
# `1e-9` (three orders of magnitude below the default, and one order below
# `KNOWN_OPTIMUM_ATOL` itself) empirically closes the residual to ~1.6e-16 — machine
# precision, not a coincidental near-miss — and lets the certified run converge CLEANLY
# (`:clean`, zero no-good cuts) in 9 iterations, well inside the plan's own `max_iter = 50`
# budget. This is `MILP()`-only, tuning HiGHS's OWN attribute vocabulary (24-CONTEXT.md's
# own "Claude's Discretion": "MILP solver attribute tuning (HiGHS gap/threads/presolve) is
# discretionary, provided nothing is hard-coded outside select_optimizer") — it does NOT
# touch `KNOWN_OPTIMUM_ATOL`, `L`, or the LL-cut algebra, none of which this gap-closure wave
# is authorized to weaken.
select_optimizer(::MILP) = optimizer_with_attributes(
    HiGHS.Optimizer,
    "output_flag" => false,
    "mip_rel_gap" => 0.0,
    "mip_feasibility_tolerance" => 1e-9,
)

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

"""
    alternative_optimizer(choice, pc::ProblemClass)

Return a JuMP-ready optimizer factory for an OPEN-SOURCE alternative solver selected
by `choice` (e.g. an [`SCSChoice`](@ref) marker) for problem class `pc`.

This is a NEW, SEPARATE dispatch point from [`commercial_optimizer`](@ref) (D-20):
alternative solvers like SCS are opt-in weakdep extensions, exactly like the
commercial backends, but they are NOT commercial/licensed software, so routing them
through a function named/documented as "commercial" would be a semantic mismatch.

This fallback method ERRORS by design: alternative backends are opt-in and are wired
in only by package extensions (e.g. `TSODSOSCSExt`), which add methods for the
concrete marker types. To enable one, `import SCS` in your environment before calling.
"""
function alternative_optimizer(choice, pc::ProblemClass)
    error(
        """
        No alternative optimizer is available for choice $(choice) and problem class $(pc).
        Alternative solvers are opt-in weakdep extensions and are never hard dependencies.
        To enable one, load the solver in your environment, e.g.:
            import SCS # enables alternative_optimizer(SCSChoice(), pc)
        """,
    )
end

export select_optimizer, commercial_optimizer, alternative_optimizer

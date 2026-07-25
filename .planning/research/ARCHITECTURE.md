# Architecture Research

**Domain:** v2.1 Validation & Reproduction — hardening the operational transactive-energy core
of an existing Julia+JuMP framework with four validation capabilities (AC-OPF oracle, reactive
ADMM consensus, real IEEE-123 impedances, directional thesis reproduction). Built on top of the
shipped v1.0 operational core and v2.0 planning layer.
**Researched:** 2026-07-25
**Confidence:** HIGH (all four capabilities map onto existing, well-documented seams; verified
against the actual source files, not assumed)

## Summary Verdict

All four v2.1 capabilities integrate as **additive extensions of existing seams**, not
restructuring:

| # | Capability | Integration seam | New `ProblemClass`? | Feature-flag needed? |
|---|------------|-------------------|----------------------|------------------------|
| a | AC-OPF oracle | `AbstractPowerFlow` contract + `solve_welfare`'s existing `allow_local`/formulation-agnostic path | No — reuses `NLP()` | No — new formulation, purely additive |
| b | Reactive μ consensus | `DsoOpt`/`AgrOpt`/`solve_admm`/`residuals.jl` build-once seam | N/A | **Yes** — `reactive_consensus::Bool` kwarg, default preserving old behavior |
| c | Real IEEE-123 impedances | `src/data/ieee123.jl` data table, offline PMD script (never a runtime dep) | N/A | Transitional toggle, then goldens re-pinned |
| d | Directional thesis reproduction | `docs/literate/*.jl` rung + `test/fixtures_*.jl` golden pattern (same as Rung 6/7, PVAL-02) | N/A | No |

No change is required to `ModelContext.jl`, `ProblemClass.jl`, `solver/factory.jl` (Ipopt
already wired as the `NLP()` default), or the DC/LinDistFlow/ConvexBranchFlow formulation files.
This is the strongest evidence the v1.0/v2.0 architecture is fit-for-purpose: the seams built
then absorb all four v2.1 capabilities without a rewrite.

## Standard Architecture (current, as verified from source)

### System Overview

```
┌───────────────────────────────────────────────────────────────────────────┐
│  data/  (JuMP-free, PMD-free)                                             │
│  Feeder/Bus/Branch structs ← ieee13.jl / ieee123.jl / topology.jl         │
├───────────────────────────────────────────────────────────────────────────┤
│  powerflow/  (AbstractPowerFlow contract — dispatch, no if-formulation==) │
│  DCPowerFlow │ LinDistFlow │ ConvexBranchFlow(SOCP)  →  contribute!(ctx)  │
├───────────────────────────────────────────────────────────────────────────┤
│  core/ModelContext  — residuals[:Rp]/[:Rq] (affine), meta[:objective]     │
│                       (quadratic), constraints (for later dual() reads)   │
├───────────────────────────────────────────────────────────────────────────┤
│  models/  — welfare_solve.jl (GLB-CVX centralized) │ exactness.jl (PF-04) │
│             oracle.jl (operational_oracle, planning coupling seam)        │
├───────────────────────────────────────────────────────────────────────────┤
│  admm/  — AgrOpt (per-node QP) │ DsoOpt (whole-net SOCP) │ solve_admm     │
│           (build-once, Parameter-free coefficient re-solve, adaptive ρ)   │
├───────────────────────────────────────────────────────────────────────────┤
│  pricing/ — dlmp.jl / fit.jl / checks.jl / welfare.jl                     │
│  planning/ — retry/checkpoint/subproblem/follower/master/benders/coupling │
│              /nash (Stackelberg-Benders + Gauss-Seidel diagonalization)   │
├───────────────────────────────────────────────────────────────────────────┤
│  solver/ — ProblemClass (LP/MILP/QP/SOCP/NLP) → factory.jl select_optimizer│
│            (Clarabel/HiGHS/Ipopt; Gurobi/Mosek weakdep-gated)             │
└───────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Relevant to v2.1 |
|-----------|-----------------|-------------------|
| `AbstractPowerFlow` | Contract: `contribute!` writes per-bus/time branch/voltage terms into `ctx.residuals[:Rp]`/`[:Rq]` | (a) — the new `ACPowerFlow` is a peer subtype, zero contract changes |
| `ModelContext` | Residual/constraint/meta registries; the "no `if formulation==`" seam | Untouched by all four capabilities |
| `exactness.jl` | SOCP relaxation cone-gap gate, `assert_socp_exact!` | (a) stays untouched — a NEW sibling gate is added instead |
| `welfare_solve.jl` | Formulation-agnostic centralized solve (`solve_welfare`), already supports `allow_local`, alternate `optimizer` | (a) reused verbatim — this is why the AC oracle is "free" |
| `AgrOpt`/`DsoOpt`/`solve_admm` | Build-once, coefficient-mutate ADMM decomposition; `qag` placeholder already exists but unread | (b) — the target of the reactive-consensus wiring |
| `residuals.jl` | JuMP-free `AdmmResiduals` ledger; established precedent of NaN-padded backward-compatible `record!` overloads across the Phase-6→7 transition | (b) — reused pattern for the new q-residual traces |
| `data/ieee123.jl` | Topology + per-unit magnitudes; explicitly documents its R/X as "representative, not thesis-verbatim" | (c) — the target of the impedance-source swap |
| `docs/literate/*.jl` + `test/fixtures_*.jl` | Established "literate rung + gate-then-golden regression" pattern (Rung 6/7, PVAL-02) | (d) — reused verbatim for the reproduction rung |

## Recommended Approach Per Capability

### (a) AC-OPF Oracle

**Where it lives:** a new `AbstractPowerFlow` concrete subtype, `src/powerflow/ACPowerFlow.jl` —
**not** a standalone `src/models/` module. Rationale: the contract (`contribute!` writing
`P,Q` into `:Rp`/`:Rq`) is exactly what an AC branch-flow formulation needs, and reusing it means
the oracle is a genuine drop-in swap for `ConvexBranchFlow`, callable through the *existing*
`solve_welfare(feeder, pf, aggregators; ...)` entrypoint with zero changes to that file.

**Why "true AC" and not "same relaxation, different solver":** the codebase already re-solves the
*relaxed* SOCP model through Ipopt via the `RSOCtoNonConvexQuadBridge`/`SOCtoNonConvexQuadBridge`
registered in both `welfare_solve.jl` and `DsoOpt.jl` — this is the "current toy-point +
same-relaxation self-check" the milestone explicitly wants replaced. That bridge only changes
*which solver* enforces the same *inequality* cone (`l·v ≥ P²+Q²`); it does not certify AC
exactness independently. A genuine oracle must enforce the **equality** `l[b,t]*v[from,t] ==
P[b,t]^2 + Q[b,t]^2` (thesis 3.34 in its unrelaxed form) — a nonconvex quadratic *equality*, not
an inequality cone. `ACPowerFlow.contribute!` should mirror `ConvexBranchFlow.contribute!`
variable-for-variable (`v`, `P`, `Q`, `l`) but:
  - drop the exactness-copy `v̂` entirely (no relaxation to force tight — nothing to copy against);
  - replace the rotated-SOC `@constraint(... in RotatedSecondOrderCone())` with a nonconvex
    equality `l[b,t]*v[from,t] == P[b,t]^2 + Q[b,t]^2`;
  - keep the true voltage drop (3.33) and apparent-power limit (3.36) verbatim;
  - stash `ctx.meta[:pf_vars] = (; v, P, Q, l)` (same key names as `ConvexBranchFlow`, minus `v̂`)
    so a comparison function can index both solutions identically.

**Is it a new `ProblemClass`?** No. Add `problem_class(::ACPowerFlow) = NLP()` **inside
`ACPowerFlow.jl` itself** (mirroring `ConvexBranchFlow.jl`'s own `problem_class(::ConvexBranchFlow)
= SOCP()` defined at that file's end) — `solver/problem_class_trait.jl` is untouched. `NLP()`
already resolves to Ipopt via `select_optimizer` (`solver/factory.jl`), so no solver wiring
changes are needed.

**Feeding `exactness.jl`:** do **not** modify `exactness.jl` — its single responsibility is the
SOCP relaxation's own cone-gap gate and should stay that way. Add a **new sibling file**,
`src/models/ac_oracle.jl`, containing:
  - `solve_ac_oracle(feeder, aggregators; T, λ₀, allow_export)` — a thin wrapper that calls
    `solve_welfare(feeder, ACPowerFlow(), aggregators; λ₀, T, allow_export, optimizer =
    select_optimizer(NLP()), allow_local = true)`. Because `solve_welfare` is already
    formulation-agnostic (dispatches `contribute!` and `problem_class` by trait), this "just
    works" with **zero changes to `welfare_solve.jl`**. Note: `solve_welfare`'s existing
    exactness-gate line (`haskey(ctx.meta[:pf_vars], :l)`) will also fire for the AC solve and
    call `assert_socp_exact!` — harmlessly, since the AC model enforces the cone as an equality
    by construction, so the reported gap is ≈0 (a free, incidental self-consistency check, not a
    bug).
  - `assert_ac_exact!(ctx_socp::ModelContext, ctx_ac::ModelContext; rtol=1e-3, atol=1e-6) ->
    (; obj_gap, v_gap, p_gap, q_gap)` — the actual v2.1 certification gate. Same feeder/T on
    both sides guarantees identical indexing; compares `value.(v)`, `value.(P)`, `value.(Q)`,
    `objective_value` pointwise with the **same isapprox-style combined `atol + rtol·magnitude`
    convention** `assert_socp_exact!` already established (scale-free, base-invariant — reuse the
    idiom, do not invent a new tolerance philosophy). THROWS on violation (fail-loud, matching
    project convention), returns the gap NamedTuple on success as a first-class reported output.

**New vs Modified:**
- NEW: `src/powerflow/ACPowerFlow.jl`
- NEW: `src/models/ac_oracle.jl`
- NEW: `test/test_ac_powerflow.jl` (contribute!-level unit tests, mirrors `test_convex_branch_flow.jl`)
- NEW: `test/test_ac_oracle.jl` (welfare-solve + `assert_ac_exact!` certification tests)
- NEW: `docs/literate/ac_oracle.jl` (a Rung — narrates independent AC certification)
- MODIFIED: `src/TSODSO.jl` (2 new `include`s: `powerflow/ACPowerFlow.jl` right after
  `powerflow/ConvexBranchFlow.jl`; `models/ac_oracle.jl` right after `models/exactness.jl`)
- MODIFIED: `docs/make.jl` (add the new literate source + a page entry)
- UNCHANGED: `src/models/exactness.jl`, `src/models/welfare_solve.jl`, `src/core/ModelContext.jl`,
  `src/solver/ProblemClass.jl`, `src/solver/factory.jl`, `src/solver/problem_class_trait.jl`

### (b) Reactive-Power μ Consensus

**Current state (verified from source):** `AgrOpt.qag::Vector{Float64}` is already computed
(`-Pdc[t]*tanφ`, thesis 3.23) but is a plain constant field, explicitly documented as "currently
NOT read by `solve_admm`" — a real placeholder, not a stub function. `DsoOpt` independently
computes the *same* constant (`q_draw`) and injects it directly into `:Rq[j]`; reactive balance
is closed by a **free** `q_import` at the root. Because both sides already compute the identical
deterministic constant, the reactive balance is *physically* consistent today — what's missing is
an actual **priced** reactive coupling variable and its own dual `μ_j[t]`, so a reactive DLMP
component becomes a first-class ADMM output (this is what "restoring voltage/DLMP credibility"
means — today reactive power is unpriced in the decomposed path).

**Design — mirror the active pag/λ split exactly, but keep it feature-flagged:**
  - `build_dso_opt(feeder, aggregators, T; ρ, λ₀, reactive_consensus::Bool=false)` — new keyword.
    When `false` (default), **byte-identical** to today: `q_draw` injected as a constant.
    When `true`: introduce `@variable(model, qag_dso[j=load_nodes, t=1:T])`, inject it into `:Rq[j]`
    instead of the constant, and add the mirror penalty term `+(μ/2)Σ(qag_dso - b_j)²` to the
    objective (μ reuses the SAME adaptive ρ schedule as the active block — do not introduce a
    second tunable penalty surface unless conditioning demands it later). `solve_dso!` gains
    `μ`, `b` args (mirroring `λ`, `a`) that, when `reactive_consensus` is on, set
    `set_objective_coefficient(dso.model, dso.qag_dso[j,t], -μ[j][t] - ρ*b[j][t])` per iteration
    — same mechanism as the active coefficient update, no new machinery invented.
  - `AgrOpt` needs **no structural change** — `agr.qag` is already the AGR-side target (a fixed
    constant per node, since DERs stay active-only per A3/thesis; 4Q-BESS is explicitly deferred).
    `solve_admm` reads `agr.qag` directly as the consensus target `b_j` each iteration (it never
    moves, since there is no reactive decision on the AGR side yet) — this is intentionally
    degenerate (μ converges quickly because the AGR-side target is fixed), but it exercises the
    *same* consensus/price machinery that a future 4Q-BESS extension would need to make `qag` a
    genuine decision variable. Update `AgrOpt.jl`'s docstring to remove the "placeholder, not
    read" language once wired (the only edit that file needs).
  - `solve_admm(... ; reactive_consensus::Bool=false)` — new keyword, threaded to
    `build_dso_opt`. When `true`: add μ state (`Dict{Int,Vector{Float64}}`, warm-started
    analogously to λ), compute the reactive primal residual `r_q = b_j - qag_dso_j` and a
    reactive dual residual `s_q` (Boyd z-block, same 2-norm form as the active block), extend the
    **stop criterion** to require the q-residuals within their own `ε_pri_q`/`ε_dual_q` **in
    addition to** the existing active-block stop (AND, never OR — a false-convergence bug on
    either block is still a false-convergence bug), and dual-ascent `μ_j ← μ_j + ρ·r_q`. Return a
    new `μ`/`dvdp` (day-ahead VAR price) field in the result NamedTuple, purely additive.
  - `residuals.jl` (`AdmmResiduals`): add new traces (`primal_q_trace`, `dual_q_trace`,
    `mu_trace`, `eps_pri_q_trace`, `eps_dual_q_trace`) and a **new, wider `record!` overload**
    that appends to all of them, following the *exact* precedent already in this file (the
    Phase-6→7 transition kept the old 4-arg `record!` and NaN-padded the new Phase-7 traces so
    old call sites kept compiling). Do the same here: keep the current 8-arg `record!` working
    (NaN-pad the 5 new q-traces) and add a new ~13-arg overload for the reactive-consensus path.
    `converged(...)` similarly grows a new overload that additionally checks the q-residuals; the
    existing 2-arg/3-arg forms stay untouched.

**Feature-flag vs unconditional — recommendation: feature-flag, default `false`.** This is the
only one of the four capabilities that structurally changes an already-shipped, cross-validated
build path (`DsoOpt`'s `:Rq` closure). The codebase's own convention (the Phase-6→7 adaptive-ρ
upgrade, the `record!` 4-arg/8-arg coexistence) is to add new behavior *behind* an explicit
opt-in during the transition, then flip the default once goldens are re-validated at every scale
(2-bus, IEEE-13, IEEE-123) — do the same here rather than risk silently perturbing the existing
IEEE-13/123 ADMM cross-validation regressions.

**New vs Modified:**
- MODIFIED: `src/admm/DsoOpt.jl` (new kwarg, new `qag_dso` variable + objective term when
  `reactive_consensus=true`; old path byte-identical when `false`)
- MODIFIED: `src/admm/AgrOpt.jl` (docstring only — `qag` field goes from "placeholder, unread" to
  "read as the reactive consensus target")
- MODIFIED: `src/admm/solve_admm.jl` (new kwarg, μ state, q-residual block, extended stop
  criterion, new return field)
- MODIFIED: `src/admm/residuals.jl` (new trace fields + new backward-compatible `record!`/
  `converged` overloads)
- NEW: `test/test_admm_reactive.jl` (mirrors the one-file-per-ADMM-feature convention already
  visible in `test_admm_adaptive.jl`, `test_admm_dualresid.jl`)
- Validation-only (not a core-code change): a test-level cross-check that the converged μ matches
  `dual(balance_q)` from the centralized `solve_welfare` on the same feeder — analogous to how λ
  is already cross-validated against `dual(balance_p)`. `pricing/dlmp.jl` itself is **not**
  modified — out of scope for this milestone (no new research axis).

### (c) Real IEEE-123 Impedances

**Where the OpenDSS-parse pipeline lives: an offline, one-time data-prep script — never a
runtime dependency.** This directly matches the codebase's already-stated policy (CLAUDE.md:
"PMD as data-parsing and cross-validation oracle only," never built into the operational core)
and the existing precedent of ad-hoc `scripts/*.jl` files at the repo root (`scripts/
benders_toy.jl`, `scripts/thesis_caseA.jl` already present in the working tree). `PowerModels
Distribution` must **not** enter `Project.toml`'s `[deps]` — it would make every downstream user
of `TSODSO` pull in PMD's dependency tree just to load a feeder fixture, and would violate
"feeder structs JuMP-free."

**Recommended data flow (four stages):**

```
[public IEEE-123 OpenDSS files]
        |  (PMD.parse_file, offline, one-time)
        v
[scripts/ieee123_opendss_reduce.jl]   -- own throwaway env (`scripts/Project.toml` w/ PMD),
        |   documented positive-sequence reduction     NOT the package env
        |   (3-phase Z matrix -> single r,x per segment; re-based to IEEE123_BASE)
        v
[src/data/ieee123_impedances.jl]      -- committed, PURE-DATA, JuMP-free, PMD-free
        |   const Dict{Tuple{Int,Int},Float64} keyed by ORIGINAL (pre-relabel) terminal pairs
        v
[src/data/ieee123.jl]                 -- ieee123_modified() looks up real r/x by (p,c) edge
        |
        v
[Feeder{Float64}]                     -- unchanged struct, unchanged topology/relabeling/
                                          load-split logic; only the r/x SOURCE changes
```

  1. `scripts/ieee123_opendss_reduce.jl` — a standalone script (its own small `Project.toml` or a
     `Pkg.activate(temp=true)` block pulling in `PowerModelsDistribution` transiently) that parses
     the public IEEE-123 OpenDSS test-feeder files, performs the documented positive-sequence
     reduction (the standard sequence-component / Kron-style collapse of each line's 3-phase
     impedance matrix to one effective positive-sequence `r,x`), converts to the framework's
     `IEEE123_BASE` (1 MVA / 4.16 kV — **not** PMD's own internal per-unit base; re-basing must be
     explicit: `z_pu_new = z_pu_pmd * (Sbase_pmd/Sbase_framework) * (Vbase_framework/Vbase_pmd)²`
     or equivalent from raw Ω), and prints/writes a Julia `const` table. Run once by the
     researcher; not part of `Pkg.test()`, not part of CI, not re-executed automatically —
     documented in the script's own header (mirroring the DATA PROVENANCE comment convention
     already used at the top of `ieee123.jl`).
  2. `src/data/ieee123_impedances.jl` (NEW) — the **vendored, committed** output: plain
     `const IEEE123_REAL_R::Dict{Tuple{Int,Int},Float64}`, `const IEEE123_REAL_X::Dict{Tuple{Int,Int},
     Float64}` keyed by the **original, pre-relabel** `IEEE123_EDGES` terminal pairs (so it slots
     in before the `ieee123_relabel_map()` step, keeping the relabeling logic untouched). Zero
     runtime dependencies — a pure data file, included in `TSODSO.jl` immediately **before**
     `data/ieee123.jl` (mirrors how `ieee123.jl` is itself positioned after `ieee13.jl`).
  3. `src/data/ieee123.jl` (MODIFIED) — `ieee123_modified()`'s per-edge loop changes from
     `r = is_switch ? IEEE123_SWITCH_R : IEEE123_LINE_R` to a lookup `IEEE123_REAL_R[(p,c)]` /
     `IEEE123_REAL_X[(p,c)]`, erroring loudly (fail-loud, matching `_ieee123_assert_incidence`'s
     convention) on any edge missing from the table — a transcription tripwire exactly like the
     existing incidence self-check. Topology (`IEEE123_EDGES`, `IEEE123_SWITCH_EDGES`,
     `IEEE123_LOAD_TERMINALS`, `ieee123_relabel_map`) is **completely untouched** — this is a
     surgical, single-responsibility swap of the impedance *source*, not a topology change.
  4. Retain the OLD representative constants (`IEEE123_LINE_R/X`, `IEEE123_SWITCH_R/X`) in the
     file, but demote them to a clearly-marked fallback path behind a keyword,
     `ieee123_modified(; real_impedances::Bool=true)`, defaulting to the NEW real data. This lets
     any *existing* pinned golden in `test_ieee123.jl`/`test_ieee123_admm.jl` that was computed
     against the synthetic numbers still be reachable (`real_impedances=false`) for one
     transitional phase while those goldens are deliberately re-derived and re-pinned against
     the real-impedance case — do not carry two parallel impedance sets forever; this milestone's
     explicit purpose is the replacement.

**Known risk to flag for the roadmap (do not silently absorb):** the synthetic R/X in
`ieee123.jl` were **hand-tuned** (per its own DATA PROVENANCE comment) specifically so the
Case-B population keeps the feeder genuinely voltage-constrained (binds `[0.9, 1.1]` pu under
load and PV reverse-flow) and so the SOC cone stays numerically well-conditioned for Clarabel
under the ADMM ρ-penalty. Swapping in real impedances can shift both properties — the case may
become voltage-slack (no longer exercising the exactness copy meaningfully) or push Clarabel
conditioning differently. **Re-tuning the aggregator/PV population (not the impedances) may be
required** to preserve a genuinely-binding, well-conditioned test case; this should be an explicit
task/checkpoint in whichever phase implements (c), not an assumed side-effect.

**New vs Modified:**
- NEW: `scripts/ieee123_opendss_reduce.jl` (offline, own env, not part of package/CI)
- NEW: `src/data/ieee123_impedances.jl` (committed pure-data table)
- MODIFIED: `src/data/ieee123.jl` (impedance lookup swap + transitional fallback keyword)
- MODIFIED: `src/TSODSO.jl` (1 new include, positioned immediately before `data/ieee123.jl`)
- MODIFIED (re-pin, not restructure): `test/test_ieee123.jl`, `test/test_ieee123_admm.jl` (any
  goldens computed against the old synthetic magnitudes)
- POSSIBLY MODIFIED: `test/fixtures_phase7.jl` (IEEE-123 population/PV-profile tuning, if the
  voltage-binding risk above materializes)
- UNCHANGED: `src/data/Feeder.jl`, `src/data/topology.jl`, `src/units/PerUnit.jl` (no dependency
  or constraint on how `r`/`x` are sourced — the JuMP-free, PMD-free contract is preserved by
  construction since only a `Dict` lookup changes)

### (d) Directional Thesis Reproduction

**Where it lives — reuse the exact Rung-6/7 + PVAL-02 pattern already shipped in v2.0**, not a
new mechanism:
  - a literate rung page, `docs/literate/thesis_reproduction.jl`, narrating: build the (now
    real-impedance) IEEE-123 feeder with a Case-B-like PV/demand population, run the centralized
    `solve_welfare` (and/or `solve_admm`) welfare-maximizing solve, compute the welfare gain
    against the flat-tariff FIT baseline (`pricing/fit.jl` — already shipped, unmodified), and
    report the gain's **sign** and **order of magnitude** against the thesis's directional claim
    — explicitly *not* the exact +$1,819/+25% figure (Appendix E is IP-blocked; this is a stated,
    accepted milestone constraint, not a gap to paper over).
  - a dedicated fixtures module, `test/fixtures_thesis_repro.jl` (mirrors `test/
    fixtures_planning.jl`'s `PlanningFixtures` pattern exactly): pinned constants such as
    `const THESIS_GAIN_SIGN = 1` and a **band**, not a point value —
    `const THESIS_GAIN_ORDER_MAG_LO`, `..._HI` — computed once (ideally via `DrWatson`
    `@tagsave`-stamped provenance, consistent with the project's reproducibility convention) and
    committed.
  - `test/test_thesis_reproduction.jl` — one `@testitem` tagged e.g. `[:thesis_repro]`, following
    the **gate-then-golden** ordering convention established by `test_planning_goldens.jl`: first
    assert the run's *own* correctness gates hold (`assert_solved!`, `assert_socp_exact!`/
    `assert_ac_exact!` if the AC oracle is wired by then, ADMM convergence if ADMM is used), THEN
    assert `sign(gain) == THESIS_GAIN_SIGN` and `lo <= gain <= hi` — a wide directional band, the
    intentional relaxation of the tight `atol=1e-3` point-golden style used for the planning-layer
    goldens (those had an authoritative hand-computed/BilevelJuMP-certified point value available;
    this one deliberately does not, per the milestone's own stretch-goal framing).
  - The already-present (untracked) `scripts/thesis_caseA.jl` is almost certainly the researcher's
    exploratory prototype for exactly this — the recommended path is to **promote/refactor** it
    into the literate rung + golden test once (b) and (c) land, rather than write the reproduction
    from scratch.

**Dependency, not independence:** unlike (a), this capability is **not** independently sequenced.
PROJECT.md is explicit that reactive-power consensus is needed to restore "a meaningful AC
comparison," and the thesis Case B result is voltage-driven — a directional reproduction run on
synthetic impedances or without reactive pricing would not credibly track the thesis's claimed
mechanism. (d) should be the **last** of the four to land.

**New vs Modified:**
- NEW: `docs/literate/thesis_reproduction.jl`
- NEW: `test/fixtures_thesis_repro.jl`
- NEW: `test/test_thesis_reproduction.jl`
- MODIFIED: `docs/make.jl` (new literate source + page)
- MODIFIED (promoted, not from scratch): `scripts/thesis_caseA.jl` → folded into the literate rung
- UNCHANGED: `pricing/fit.jl`, `pricing/welfare.jl`, `experiments/*` (the harness already supports
  declarative `Scenario`/`run_scenario` — reuse it to materialize the reproduction case rather
  than hand-rolling a new runner)

## Recommended Project Structure (delta only — additions to the existing tree)

```
src/
├── powerflow/
│   └── ACPowerFlow.jl              # NEW (a) — true nonconvex AC branch-flow, AbstractPowerFlow
├── models/
│   └── ac_oracle.jl                # NEW (a) — solve_ac_oracle + assert_ac_exact!
├── admm/
│   ├── DsoOpt.jl                   # MODIFIED (b) — reactive_consensus kwarg, qag_dso coupling var
│   ├── AgrOpt.jl                   # MODIFIED (b) — docstring only (qag now consumed)
│   ├── solve_admm.jl               # MODIFIED (b) — μ state, q-residuals, extended stop criterion
│   └── residuals.jl                # MODIFIED (b) — new traces + backward-compatible overloads
├── data/
│   ├── ieee123_impedances.jl       # NEW (c) — committed real-impedance lookup table
│   └── ieee123.jl                  # MODIFIED (c) — impedance-source swap, topology untouched
└── TSODSO.jl                       # MODIFIED (a,b,c) — 3 new includes, no restructuring

scripts/
├── ieee123_opendss_reduce.jl       # NEW (c) — offline PMD-parse + positive-sequence reduction
└── thesis_caseA.jl                 # MODIFIED (d) — promoted into the literate rung

docs/
├── literate/
│   ├── ac_oracle.jl                # NEW (a)
│   └── thesis_reproduction.jl      # NEW (d)
└── make.jl                         # MODIFIED (a,d) — 2 new literate sources + pages

test/
├── test_ac_powerflow.jl            # NEW (a)
├── test_ac_oracle.jl               # NEW (a)
├── test_admm_reactive.jl           # NEW (b)
├── test_ieee123.jl                 # MODIFIED (c) — re-pinned goldens
├── test_ieee123_admm.jl            # MODIFIED (c) — re-pinned goldens
├── fixtures_phase7.jl              # POSSIBLY MODIFIED (c) — population re-tuning if needed
├── fixtures_thesis_repro.jl        # NEW (d)
└── test_thesis_reproduction.jl     # NEW (d)
```

### Structure Rationale

- Every new file lands in an **existing directory** (`powerflow/`, `models/`, `admm/`, `data/`,
  `docs/literate/`, `test/`) — there is no new top-level module or directory, matching "fit
  existing seams, not restructure."
- `ACPowerFlow.jl` sits beside `ConvexBranchFlow.jl` because it is a peer formulation under the
  same `AbstractPowerFlow` contract — not a "validation-only" side module — so it can be reused
  anywhere a `pf::AbstractPowerFlow` is accepted (e.g. a future direct AC solve of IEEE-13).
- `ac_oracle.jl` sits beside `exactness.jl`/`oracle.jl` because it is the same *kind* of thing
  (a post-solve certification gate / oracle wrapper), keeping the `models/` directory's existing
  organizing principle (one file per validation concern) intact.
- The OpenDSS pipeline is a `scripts/` one-off, never a `src/` runtime path — this is the
  strongest guarantee that "feeder structs stay JuMP-free / PMD-free" cannot regress: PMD simply
  never appears in `Project.toml`.

## Architectural Patterns

### Pattern 1: Formulation-as-peer-subtype (already established, reused for (a))

**What:** A new physics formulation is added by writing one more `AbstractPowerFlow` subtype +
`contribute!` method + `problem_class` method — never by branching inside `solve_welfare` or
`ModelContext`.
**When to use:** Any new power-flow model (AC-OPF here; a future unbalanced/meshed formulation
later).
**Trade-off:** Requires the new formulation to fit the `(v,v̂,P,Q,l)`-shaped variable convention
and the affine `:Rp`/`:Rq` residual seam; a formulation whose balance is inherently non-affine
(there is none currently, and AC-OPF's balance stays affine — only the cone becomes an equality)
would need a documented exception.

```julia
struct ACPowerFlow <: AbstractPowerFlow end
function contribute!(::ACPowerFlow, ctx::ModelContext, feeder; T::Int = 1)
    # same v, P, Q, l as ConvexBranchFlow, no v̂; true drop unchanged;
    # cone becomes an EQUALITY: l[b,t]*v[from,t] == P[b,t]^2 + Q[b,t]^2
end
problem_class(::ACPowerFlow) = NLP()
```

### Pattern 2: Feature-flagged structural change with a compatibility overload (reused for (b))

**What:** When a change touches an already-shipped, cross-validated build path, add a keyword
defaulting to the OLD behavior, and — if a data structure needs new fields — add a NEW overload
of the mutating function that appends to the new fields, keeping the OLD overload/arity
compiling unmodified (the project's own precedent: Phase-6→7 `record!` 4-arg → 8-arg).
**When to use:** `DsoOpt`/`solve_admm`/`residuals.jl` changes for reactive consensus.
**Trade-off:** Two code paths temporarily coexist (more surface area) in exchange for zero
regression risk on already-cross-validated IEEE-13/123 goldens; retire the flag once goldens are
re-validated at the new default.

### Pattern 3: Offline data-prep script → committed pure-data file (new pattern, for (c))

**What:** A heavyweight, one-time transformation (OpenDSS parse + positive-sequence reduction via
PMD) runs in its own throwaway environment and its **output** — not the tool — is vendored as a
plain, dependency-free `const` table in `src/data/`.
**When to use:** Any future "import real-world data via a heavyweight parser" need (e.g. a later
IEEE-8500 or real DSO feeder) — this is the reusable template, not a one-off hack.
**Trade-off:** The prep script itself is unmaintained/unrun in CI (acceptable — it's provenance,
not a build step); a data update requires manually re-running the script and re-committing the
generated file, which is a deliberate, reviewable step, not automatic drift.

### Pattern 4: Literate rung + gate-then-golden regression (already established, reused for (d))

**What:** A new experiment/reproduction gets a `docs/literate/*.jl` narrated page (executed live
by `Documenter`/`Literate`, so numbers can't drift from `src/`) plus a dedicated
`test/fixtures_*.jl` constants module and a `@testitem` that asserts the run's own correctness
gates BEFORE comparing to the pinned golden.
**When to use:** Any milestone-closing reproduction/validation result (this is exactly the
PVAL-02 pattern from v2.0's Rung 6/7).
**Trade-off:** None significant — this is the established, working convention; deviating from it
(e.g. a bare `@test` without the fixtures-module + gate-then-golden structure) would be the
anti-pattern here.

## Data Flow

### (a) AC-OPF Oracle Flow

```
feeder, aggregators, λ₀
        |
        v
solve_welfare(feeder, ConvexBranchFlow(), aggregators; allow_export=true)  -> ctx_socp (unchanged)
solve_ac_oracle(feeder, aggregators; λ₀, allow_export)
        |  solve_welfare(feeder, ACPowerFlow(), aggregators; optimizer=NLP(), allow_local=true)
        v  -> ctx_ac
assert_ac_exact!(ctx_socp, ctx_ac; rtol, atol) -> (; obj_gap, v_gap, p_gap, q_gap)  [THROWS on fail]
```

### (b) Reactive Consensus Flow (mirrors the existing active-block flow exactly)

```
solve_admm(...; reactive_consensus=true)
  per iteration k:
    solve_agr!(...)              -> a[j] (active), b[j] = agr.qag (reactive target, FIXED)
    solve_dso!(...; μ, b)        -> pag_dso[j,t] (active), qag_dso[j,t] (reactive, NEW)
    r_p = a - pag_dso;  r_q = b - qag_dso
    λ <- λ + ρ·r_p   (existing)   μ <- μ + ρ·r_q   (NEW, same mechanism)
  stop iff (‖r_p‖≤ε_pri ∧ ‖s_p‖≤ε_dual) ∧ (‖r_q‖≤ε_pri_q ∧ ‖s_q‖≤ε_dual_q)   [AND, not OR]
```

### (c) Real-Impedance Data Flow

```
public IEEE-123 OpenDSS files
    |  scripts/ieee123_opendss_reduce.jl (offline, PMD, own env)
    |  positive-sequence reduction + re-base to IEEE123_BASE
    v
src/data/ieee123_impedances.jl (committed const Dict, JuMP-free, PMD-free)
    |
    v
src/data/ieee123.jl: ieee123_modified() looks up (p,c) -> (r,x)
    |
    v
Feeder{Float64}  (topology/relabeling/load-split UNCHANGED)
```

### (d) Directional Reproduction Flow

```
ieee123_modified()  [real impedances, from (c)]
    |
    v
solve_admm(...; reactive_consensus=true)  [from (b)]  OR  solve_welfare(..., allow_export=true)
    |
    v
welfare  vs.  flat-tariff FIT baseline (pricing/fit.jl, unmodified)
    |
    v
gain = welfare - fit_baseline
    |
    v
test_thesis_reproduction.jl: gate (assert_solved!/assert_socp_exact!) THEN
  sign(gain) == THESIS_GAIN_SIGN  ∧  lo ≤ gain ≤ hi   (directional band, not point golden)
```

## Scaling / Validation Considerations

| Concern | 2-bus / IEEE-13 (existing) | IEEE-123 synthetic (existing) | IEEE-123 real (new, (c)) |
|---------|---------------------------|-------------------------------|----------------------------|
| SOC cone conditioning | Validated exact, Clarabel converges in tens of iters | Tuned so the cone stays exact | **Must re-verify** — real R/X may loosen or tighten the cone; re-tune population if needed |
| Voltage-band bindingness | N/A (13-node is congestion-driven) | Hand-tuned to bind `[0.9,1.1]` | **Must re-verify** — real R/X changes lateral voltage drop; may need population re-tuning |
| ADMM convergence (adaptive ρ) | Cross-validated | Cross-validated | Re-run the existing adaptive-ρ schedule; flag if `ρ_min`/`ρ_max`/`τ`/`μ` need retuning |
| AC-vs-SOCP exactness gap | Cheap to certify (small case) | N/A until (c) lands | The primary target case for `assert_ac_exact!` — this is where AC-OPF nonconvexity/local-optima risk (Ipopt) is most likely to bite; consider multiple Ipopt starts as a scale mitigation |

## Anti-Patterns

### Anti-Pattern 1: Re-solving the SOCP relaxation through Ipopt and calling it "AC certification"

**What people do:** Reuse the existing `RSOCtoNonConvexQuadBridge` cross-solver path (already
wired for a different purpose — solver-choice cross-validation of the *same* relaxed model) as
if it were an independent AC-OPF oracle.
**Why it's wrong:** It only changes the solver, not the physics — the cone stays a *relaxed
inequality*, so it cannot detect a case where the SOCP relaxation itself is inexact. This is
explicitly the deficiency PROJECT.md calls out ("current toy-point + same-relaxation self-check").
**Instead:** A genuinely separate `ACPowerFlow` formulation enforcing the cone as an *equality*.

### Anti-Pattern 2: Making PowerModelsDistribution a `Project.toml` dependency

**What people do:** `import PowerModelsDistribution` directly inside `src/data/ieee123.jl` (or
anywhere in `src/`) to "just parse OpenDSS at load time."
**Why it's wrong:** Violates the explicit CLAUDE.md policy (PMD is a data/validation *oracle*,
never a core dependency), pulls PMD's entire dependency tree into every downstream user's
environment, and risks non-reproducible builds if the OpenDSS source files move/change upstream.
**Instead:** Offline script → committed pure-data `const` table (Pattern 3 above).

### Anti-Pattern 3: Unconditionally flipping the reactive-consensus default before re-validating goldens

**What people do:** Land the `reactive_consensus` machinery and immediately make it the only
path (remove the flag), assuming "it's strictly more correct."
**Why it's wrong:** `DsoOpt`'s `:Rq` closure is part of the already-cross-validated IEEE-13/123
ADMM regression baseline (welfare/DADP matching the centralized optimum). Flipping unconditionally
risks a silent, un-reviewed perturbation of numbers the test suite currently pins.
**Instead:** Feature-flag first (default off), re-validate every affected golden explicitly, flip
the default in a clearly-labeled follow-up commit/plan.

### Anti-Pattern 4: Chasing the exact thesis figure

**What people do:** Try to reverse-engineer or approximate the thesis's exact +$1,819/+25%
headline from public data, treating a close numeric match as the success criterion.
**Why it's wrong:** The source Appendix E data is IP-blocked (CONICET repository); any numeric
match against public-data substitutes would be coincidental, not a genuine reproduction, and
risks a false sense of validated correctness.
**Instead:** Pin a **directional** band (sign + rough order of magnitude) per PROJECT.md's own
explicit scope decision; treat exact-figure reproduction as a stretch goal contingent on
obtaining Appendix E, never as a required regression gate.

## Integration Points

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|----------------|-------|
| `ACPowerFlow` ↔ `ModelContext` | `contribute!` writes `:Rp`/`:Rq` via `add_to_residual!`, stashes `pf_vars` in `meta` | Identical contract to `ConvexBranchFlow`; zero `ModelContext.jl` changes |
| `ac_oracle.jl` ↔ `welfare_solve.jl` | Calls `solve_welfare(feeder, ACPowerFlow(), ...)` unchanged | `solve_welfare` is already formulation/solver-agnostic; no modification needed |
| `ac_oracle.jl` ↔ `exactness.jl` | None (deliberately) — `assert_ac_exact!` is a new, separate gate | Keeps `assert_socp_exact!`'s single responsibility (SOCP-only cone gap) intact |
| `DsoOpt`/`AgrOpt` ↔ `solve_admm` | New `μ`/`b` params threaded through `solve_dso!`/read from `agr.qag`, mirroring `λ`/`a` | Purely additive when `reactive_consensus=true`; no seam change, same mechanism reused |
| `residuals.jl` ↔ `solve_admm` | New trace fields + new `record!`/`converged` overloads | Backward-compatible via the project's established NaN-pad-old-overload convention |
| `ieee123_impedances.jl` ↔ `ieee123.jl` | Plain `Dict` lookup keyed by original terminal pairs | No JuMP, no PMD, no runtime I/O — a pure compile-time constant table |
| `scripts/ieee123_opendss_reduce.jl` ↔ package | None at runtime — output is committed, script is never `include`d by `TSODSO.jl` | The only place PMD is even imported, and it's outside the package boundary |
| `thesis_reproduction.jl` ↔ `experiments/*` | Uses `Scenario`/`run_scenario` (existing declarative harness) to materialize the case | Avoids hand-rolling a new runner; reuses `run.jl`/`materialize.jl` verbatim |

## Build Order & Phase Mapping (dependency-aware)

**Dependency graph:**

```
(a) AC-OPF Oracle           - independent (touches powerflow/, models/ only)
(b) Reactive μ Consensus     - independent (touches admm/ only)
(c) Real IEEE-123 Impedances - independent (touches data/, scripts/ only), but its OWN
                                validation (voltage-binding, SOC conditioning) benefits from
                                (a) and (b) being available to certify the real-data case
(d) Directional Reproduction - DEPENDS on (b) + (c); optionally consumes (a) for an extra
                                AC-certification badge on the reproduction run
```

**Recommended 4-phase mapping** (independent code changes first, convergent validation last):

1. **Phase 1 — AC-OPF Oracle.** Fully independent; can be developed and tested against existing
   2-bus/IEEE-13/synthetic-IEEE-123 fixtures immediately. No blocking dependency on 2/3/4.
2. **Phase 2 — Reactive μ-Consensus in ADMM.** Independent of Phase 1's files (admm/ vs
   powerflow+models/); can in principle run in parallel, but sequenced second because it is the
   most invasive change to an already-shipped path (feature-flagged) and its own goldens should
   be re-validated before Phase 3/4 build on top of it.
3. **Phase 3 — Real IEEE-123 Impedances.** Code-independent of 1/2, but its *validation* (is the
   real-data case still voltage-binding? is the SOC cone still exact? is ADMM still
   well-conditioned?) should exercise the Phase 1 AC oracle and Phase 2 reactive consensus on the
   new topology as part of this phase's own acceptance criteria — this is where the "does the
   real feeder actually need population re-tuning" risk gets resolved.
4. **Phase 4 — Directional Thesis Reproduction.** Strictly depends on Phase 2 (reactive pricing
   for DLMP/voltage credibility) and Phase 3 (real, standard data) both landing; optionally
   reports an AC-certification badge from Phase 1. Promote the existing exploratory
   `scripts/thesis_caseA.jl` into the literate rung + golden test here.

This ordering also matches the milestone framing in `.planning/PROJECT.md` — "real impedances +
reactive power likely precede meaningful thesis reproduction; AC oracle is independent" — and
keeps each phase's regression surface isolated (Phase 1 cannot break Phase 2's admm/ tests and
vice versa; only Phase 4 depends on both).

## Sources

- Direct inspection of the current v2.1 codebase (HIGH confidence — these are the actual files,
  not summarized from documentation): `src/powerflow/AbstractPowerFlow.jl`,
  `src/powerflow/ConvexBranchFlow.jl`, `src/models/exactness.jl`, `src/models/welfare_solve.jl`,
  `src/admm/AgrOpt.jl`, `src/admm/DsoOpt.jl`, `src/admm/solve_admm.jl`, `src/admm/residuals.jl`,
  `src/data/ieee123.jl`, `src/data/Feeder.jl`, `src/core/ModelContext.jl`,
  `src/solver/ProblemClass.jl`, `src/solver/factory.jl`, `src/TSODSO.jl`, `docs/make.jl`,
  `test/test_planning_goldens.jl`, `test/test_exactness.jl`, `Project.toml`.
- `.planning/PROJECT.md` (v2.1 milestone scope, deferred-features list, key decisions log) — HIGH
  confidence, primary source for milestone intent and constraints.
- Project `CLAUDE.md` (tech-stack constraints: PMD-as-oracle-only policy, JuMP-vs-Convex.jl
  rationale, hand-rolled-decomposition rationale) — HIGH confidence, explicit project policy.
- MEDIUM confidence, flagged for roadmap attention: the exact reactive-consensus tolerance
  scheme (whether μ needs its own ρ_q or can safely reuse the active-block ρ) and whether the
  IEEE-123 aggregator/PV population will need re-tuning once real impedances land — both are
  judgment calls based on the documented tuning rationale in `ieee123.jl`, not verified against a
  live re-solve (no real impedance data exists yet to test against).

---
*Architecture research for: TSO-DSO v2.1 Validation & Reproduction milestone*
*Researched: 2026-07-25*

# Project Research Summary

**Project:** TSO-DSO Integration Optimization Framework — v2.0 Stackelberg-Nash Planning Layer
**Domain:** Hand-rolled Benders decomposition + Gauss-Seidel diagonalization for a bilevel
(Stackelberg) TSO-DSO investment-equilibrium game, built additively on top of the shipped v1.0
convex operational core (`operational_oracle`, JuMP/Clarabel/HiGHS).
**Researched:** 2026-07-22
**Confidence:** MEDIUM-HIGH overall (HIGH on stack/architecture mechanics, verified directly
against shipped v1 source; MEDIUM-LOW on the underlying theory source itself, which is
self-flagged ambiguous)

## Executive Summary

v2.0 adds a second, genuinely bilevel decomposition layer on top of the already-validated v1.0
operational core: a distributor-as-leader investment master solved by hand-rolled Benders
decomposition, wrapping a small transmission-reinforcement follower subproblem, with multiple
distributors reconciled to a Nash equilibrium via Gauss-Seidel diagonalization. All four
researchers (stack, features, architecture, pitfalls) independently converged on the same
build order, the same architectural shape (`src/planning/` mirroring the proven `src/admm/`
build-once/pure-data-ledger pattern), and the same top risk: the source theory note (PSR
N1-N2 internal note) is itself flagged MEDIUM confidence and internally inconsistent on which
side is leader and which is follower — so this milestone's first deliverable is not the Benders
loop itself but an empirical, BilevelJuMP-certified resolution of that ambiguity, gating
everything downstream.

The recommended approach requires **no new core solver technology** — HiGHS (Benders master),
Clarabel (follower/oracle subproblems), and Ipopt all route through the existing
`select_optimizer(::ProblemClass)` factory unchanged. The only new dependency is BilevelJuMP.jl,
added test-only as a small-instance validation oracle (never the production solver, per
CLAUDE.md's already-locked decision). Architecturally, the plan is strictly additive: zero
modifications to `src/models/oracle.jl` or `src/models/welfare_solve.jl`; a new `src/planning/`
subtree reuses the same `contribute!` builders and `ModelContext`/`assert_solved!` discipline
already proven by the ADMM layer, with one meaningful new idiom — the coupling flow `z` becomes
a genuine JuMP `Parameter` (safe here because it enters the objective affinely, unlike ADMM's
`λ_j` which must stay a `Float64` to avoid a bilinear objective).

The dominant risk cluster is correctness-under-ambiguity: (1) no numerical reference case exists
anywhere for the planning layer, so canonical fixtures must be project-generated goldens, gated
by an independent BilevelJuMP cross-check; (2) a known, unresolved, intermittent Clarabel
`NUMERICAL_ERROR` flake (documented in STATE.md) gets combinatorially amplified once the oracle
is re-solved inside a Benders × scenario × distributor × diagonalization nest — bounded retry
and checkpointing must be built in from day one, not bolted on after a long run fails; (3)
Gauss-Seidel Nash diagonalization has no general uniqueness or convergence guarantee, so the
project must report "a converged equilibrium" with multi-seed/multi-order probing, never claim
"the" equilibrium. Scope is deliberately continuous-only for v2.0 — integer/binary-expansion
investment, MCP/VI recast, and stochastic/multistage extensions are all explicitly deferred, with
an automated no-binaries guard recommended to prevent silent scope creep.

## Key Findings

### Recommended Stack

No new core solver technology is needed: v2.0's planning layer is continuous-only (LP/QP master,
LP/QP/SOCP subproblems) and reuses the existing `select_optimizer(::ProblemClass)` factory
verbatim. The only addition is BilevelJuMP.jl (0.6.3), added as a **test-only** dependency in
`test/Project.toml` (never the root `[deps]`), used exclusively as a small-instance validation
oracle. Its open-source-compatible modes are `BigMMode` (HiGHS, needs only binary-variable
support) and `StrongDualityMode`/`ProductMode` (Ipopt, already wired); `SOS1Mode`/`IndicatorMode`
require a licensed MIP solver (HiGHS.jl does not implement `MOI.SOS1`/`MOI.Indicator`) and are
reserved for an optional Gurobi-licensed run. PATHSolver, Complementarity.jl, DualDecomposition.jl,
Coluna.jl, and StructJuMP all stay explicitly "on the shelf" — none have a genuine consumer in
v2.0's continuous, fixed-point (not MCP, not stochastic-MIP, not Dantzig-Wolfe) scope.

**Core technologies:**
- **HiGHS** (1.24.1, unchanged) — Benders master LP (leader's continuous investment + growing cut rows)
- **Clarabel** (0.11.1, unchanged) — follower subproblem LP/QP and the reused operational SOCP oracle
- **JuMP `Parameter`** — the coupling flow `z`, re-solved via `set_parameter_value` per Benders iteration (no rebuild)
- **BilevelJuMP.jl** (0.6.3, NEW, test-only) — small-instance MPEC validation oracle, never production

### Expected Features

**Must have (table stakes):**
- Wire the SEAM-01 `z`-pin into a new build-once subproblem (coupling constraint + its dual), superseding the current `ArgumentError` stub deliberately
- Leader (distributor) investment master with continuous `y_inv`, `y_inv,flex`, `z_{y,s}`
- New transmission-reinforcement follower LP `α(z)` exposing coupling dual `π_s`, including an infeasibility/Farkas certificate path
- Hand-rolled Benders cut accumulation — **both optimality AND feasibility cuts** (the source only documents optimality; feasibility handling is a project-added gap-fill, not optional)
- Single-distributor Stackelberg equilibrium validated first as a cheap regression rung before Nash
- Gauss-Seidel diagonalization across N distributors with fixed-point convergence detection and honest non-uniqueness reporting
- BilevelJuMP validation oracle on tiny instances, gating the canonical fixtures
- Two-level convergence diagnostics (inner Benders gap + outer diagonalization/Nash residual)
- Literate docs mapping PSR problem numbers (1,2,4,7,8,9) to code, including the interpretive choices made explicit

**Should have (differentiators):**
- Independent MPEC cross-validation on every new canonical fixture, not just once
- The coupling seam (`z↔p_ag`, `λ_j↔π_s`) made genuinely *live* rather than just validated
- Explicit, documented resolution of the leader/follower labeling ambiguity as a recorded Key Decision

**Defer (v2.x+ / later milestone):**
- Binary-expansion of `z` + Lagrangian/integer-L-shaped cuts (materially harder, separate research problem)
- MCP/VI recast via PATHSolver/Complementarity.jl (only if diagonalization proves unreliable)
- Full multistage stochastic (SDDiP) treatment
- Cut-strengthening/acceleration (only if measured slow convergence, not speculative)

### Architecture Approach

The guiding principle is that the planning layer is additive, not a refactor: `src/planning/`
mirrors the proven shape of `src/admm/` — pure-data ledgers (`cuts.jl`, `diagnostics.jl`), a
build-once JuMP wrapper (`subproblem.jl`, reusing the SAME `contribute!` builders `DsoOpt.jl`
already reuses), and thin orchestrators with no JuMP-building logic of their own (`benders.jl`,
`diagonalize.jl`). `operational_oracle`/`solve_welfare` remain completely unmodified; the z-pin is
implemented in a new, purpose-built subproblem file, not retrofitted into files exercised by
~2000 existing tests.

**Major components:**
1. `subproblem.jl` (`OracleProblem`) — build-once wrapper exposing coupling flow `z` as a genuine JuMP `Parameter`; reads the coupling dual off the same `:balance_p` registry the DADP already uses
2. `cuts.jl` / `diagnostics.jl` — pure-data Benders cut store and convergence ledgers, no JuMP, mirroring `residuals.jl`
3. `master.jl` / `benders.jl` — persistent Benders master (LP/QP) + outer loop orchestrator; cuts accumulate as new `@constraint` rows, never a rebuild
4. `coupling.jl` — a **genuinely new** shared N2/transmission-reinforcement model with no v1 analog; without it the diagonalization loop has nothing shared to iterate on and "Nash" is vacuous
5. `diagonalize.jl` — Gauss-Seidel sweep treating each distributor's full Benders solve as an atomic black box
6. `validation.jl` — weakdep-gated BilevelJuMP cross-check, parallel path, tiny fixtures only

The single most load-bearing architectural rule (Pattern 3 in the architecture research): every
solve whose `(cost, π)` becomes a **permanent** Benders cut must use the STRICT
`assert_solved!(...; allow_almost=false)` gate — never ADMM's mid-loop `allow_almost=true`
relaxation, because a bad dual from a near-feasible solve bakes an invalid, self-correcting-free
cut permanently into the master.

### Critical Pitfalls

1. **Benders cuts built from a faked/proxy dual before the pin exists, or from an inexact SOC relaxation** — wire the real `p_import == z` constraint and read *its* dual first; add an automated cut-validity check (`α(z') ≥ w^k + π^k·(z'-z^k)` for later-evaluated `z'`) as a hard failure gate, not a warning.
2. **Leader/follower roles and coupling-dual sign hard-coded from the ambiguous PSR note** — the source is explicitly self-contradictory on this point; resolve empirically via a tiny BilevelJuMP MPEC cross-check and a hand-worked toy enumeration BEFORE writing production Benders code, and encode the resolution as a tested invariant, not a code comment.
3. **`NUMERICAL_ERROR` flake amplification** — a known, documented, intermittent Clarabel numerical error (STATE.md) that was low-priority in v1 becomes near-certain across a Benders × scenario × distributor × diagonalization nest; bounded retry + checkpointing is a day-one co-requirement of the z-pin work, not an afterthought.
4. **Gauss-Seidel Nash non-convergence/non-uniqueness treated as a solved single answer** — diagonalization has no general convergence guarantee; instrument round-over-round gap, nest inner tolerances strictly tighter than outer, and deliberately probe multiple seeds/sweep orders as a gating acceptance criterion, reporting "a converged equilibrium" never "the" one.
5. **Skipping the BilevelJuMP certification because the Benders loop "just runs and converges"** — given zero external reference case and a flagged-ambiguous source, self-consistency is not correctness; make a tiny, tractable BilevelJuMP certification case a gating deliverable, re-run whenever the sign/role convention changes.

## Implications for Roadmap

All four researchers converge on the same four-phase build order below. This is not an
independent roadmap proposal — it is the **unanimous cross-cutting conclusion** of the stack,
features, architecture, and pitfalls research passes, and should be treated as the strong
starting point for phase structure.

### Phase 1: Oracle-Coupling-Wiring + Single-Distributor Stackelberg-Benders (gated)
**Rationale:** Everything downstream depends on a real (not proxy) coupling dual, and on
resolving the source-flagged leader/follower ambiguity empirically before it propagates into
dozens of call sites. Architecture, features, and pitfalls research all independently name this
as the first, gating phase.
**Delivers:**
- The z-pin wired into a new `subproblem.jl` (build-once `OracleProblem`, `z` as a JuMP
  `Parameter`, coupling dual read off `:balance_p`) — `operational_oracle`/`solve_welfare` remain
  unmodified
- Coupling-dual reconciliation function (hourly `λ_j` ↔ per-scenario `π_s`: time-aggregation +
  sign convention), pinned against a hand-computed toy case
- Bounded retry + checkpointing around the oracle solve (co-requirement, not deferred — see
  Pitfall 5)
- Single-distributor Benders loop with **both optimality AND feasibility cuts**, persistent
  master, strict `assert_solved!` on every cut-producing solve
- A tiny BilevelJuMP MPEC certification case (BigMMode/StrongDualityMode) that empirically
  resolves Reading A vs Reading B of the leader/follower semantics — this is a **gating
  deliverable of this phase**, not appended later
**Addresses:** SEAM-01 z-pin wiring, leader/follower resolution, transmission-reinforcement
follower LP, Benders optimality+feasibility cuts, single-distributor base rung, BilevelJuMP
validation oracle (all P1 in FEATURES.md)
**Avoids:** Pitfalls 1 (cut validity vs. convex/SOCP precondition), 2 (role/sign ambiguity), 3
(coupling-dual sign/scale mismatch), 5 (NUMERICAL_ERROR amplification), 6 (skipping BilevelJuMP
certification)

### Phase 2: Cut-Store / Master Robustness Hardening
**Rationale:** Once the single-distributor loop is correct and certified, harden the mechanics
that every later phase (diagonalization) will call repeatedly and at higher volume — architecture
research explicitly separates this from Phase 1 because robustness-at-scale concerns
(feasibility-cut edge cases, cut-store growth, retry-budget tuning, convergence-gap
instrumentation) are best proven solid before nesting a second outer loop on top.
**Delivers:** Hardened `cuts.jl`/`master.jl`/`diagnostics.jl` — feasibility-cut edge cases
exercised, Benders gap (UB-LB) convergence diagnostics finalized as its own purpose-built struct
(explicitly NOT a copy of ADMM's residual-based stopping criterion — Pitfall 7), retry/checkpoint
behavior load-tested at realistic iteration counts.
**Addresses:** Benders inner-loop convergence detection, two-level convergence diagnostics
scaffolding (P1 in FEATURES.md)
**Avoids:** Pitfall 7 (conflating ADMM's dual-ascent convergence semantics with Benders' outer
UB/LB gap)

### Phase 3: Nash Diagonalization + Shared-Transmission Coupling Model (gated)
**Rationale:** Only once a single distributor's Benders loop is certified and hardened does the
genuinely new, cross-cutting piece make sense: `src/planning/coupling.jl` is not a v1 mirror at
all — it's the shared N2/transmission-reinforcement model that gives the Gauss-Seidel sweep
something to actually iterate on. All four researchers flag that without this component the
diagonalization loop has nothing shared and "Nash" is vacuous.
**Delivers:** `coupling.jl` (new shared-transmission model, per-distributor marginal signal);
`diagonalize.jl` (Gauss-Seidel sweep, each distributor's Benders solve treated as an atomic
black box per Pattern 4); fixed-point convergence detection with strictly-nested tolerances;
mandatory multi-seed/multi-order convergence probing as a **gating acceptance criterion of this
phase**, not a later hardening pass.
**Addresses:** Gauss-Seidel diagonalization across N distributors, Nash fixed-point convergence +
honest non-uniqueness reporting (P1 in FEATURES.md)
**Avoids:** Pitfall 4 (non-convergence/cycling/non-uniqueness reported as a single solved answer)

### Phase 4: Validation-Oracle Regression Hardening + Documentation
**Rationale:** With both the single-distributor and multi-distributor mechanics validated, the
final phase converts one-off validation runs into permanent regression infrastructure and
completes the traceability requirement (a hard project constraint per CLAUDE.md) that the
ambiguous source material makes especially important here.
**Delivers:** BilevelJuMP certification case retained as a permanent, fast regression test
(re-run whenever role/sign conventions change); canonical N=1/N=2 fixtures pinned as first-
correct-run goldens (gated by BilevelJuMP agreement + diagonalization convergence); Literate docs
mapping PSR problem numbers to code with interpretive choices made explicit; automated
no-binaries guard on every planning-layer subproblem builder.
**Addresses:** Canonical regression fixtures, literate documentation, declarative scenario
extension (P1/P2 in FEATURES.md)
**Avoids:** Pitfall 6 (certification run once then forgotten), Pitfall 8 (integer structure
sneaking back in via a discretization shortcut)

### Phase Ordering Rationale

- **Correctness-before-scale, unanimous across all four research passes:** the leader/follower
  semantic ambiguity and the missing z-pin dual are *foundational* — every later phase's outputs
  are meaningless if either is wrong, so both must be resolved and certified (via BilevelJuMP)
  before any Nash/diagonalization work begins.
- **Robustness hardening (Phase 2) is deliberately separated from correctness (Phase 1) and from
  scale (Phase 3):** the pitfalls research is explicit that combinatorial amplification of the
  known `NUMERICAL_ERROR` flake and cut-store growth only become load-bearing once the outer
  diagonalization loop multiplies call volume — proving the mechanics solid at N=1 before nesting
  a second loop is cheaper to debug.
- **`coupling.jl` is the phase-3 pivot, not a phase-1 concern:** architecture research is explicit
  this is a genuinely new model (no v1 analog) that only becomes necessary once multiple
  distributors need something shared to iterate on — building it earlier would be premature
  without a certified single-distributor baseline to attach it to.
- **Documentation/regression-hardening last, but not optional:** CLAUDE.md's Literate/Documenter
  requirement is a hard constraint; deferring it to Phase 4 is about sequencing (write once the
  interpretive choices are actually settled), not deprioritizing it.
- **Continuous-only scope enforced throughout:** an automated no-binaries assertion belongs in
  every phase's acceptance criteria, not just Phase 4 — integer/binary-expansion investment,
  MCP/VI recast, and stochastic/multistage are all explicitly OUT of v2.0 and must not creep in
  via a "quick" discretization shortcut (Pitfall 8).

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** HIGH — the leader/follower semantic resolution and coupling-dual sign/scale
  reconciliation are empirical, not literature-answerable; expect `/gsd:plan-phase
  --research-phase 1` to need a focused pass on BilevelJuMP's exact mode API surface
  (`BigMMode`/`StrongDualityMode` construction, bound requirements for Fortuny-Amat) before
  coding the certification case.
- **Phase 3:** MEDIUM — Gauss-Seidel/diagonalization convergence theory for multi-leader-
  multi-follower games is general literature (no project-specific numerical case exists); the
  `coupling.jl` model design itself is a genuinely new research decision, not a lookup.

Phases with standard patterns (skip research-phase):
- **Phase 2:** the build-once/pure-data-ledger/strict-solve-gating patterns are already fully
  proven in `src/admm/` — this phase is disciplined reuse, not new research.
- **Phase 4:** Literate/Documenter documentation patterns and regression-fixture pinning are
  already established v1.0 conventions (`test_ieee13.jl`'s "COMPUTED golden" pattern) — apply
  directly.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All versions re-verified live against the Julia General registry and BilevelJuMP's own docs on research date; no new core solver needed, only an additive test-only dependency. |
| Features | MEDIUM-HIGH | Ecosystem grounding (BilevelJuMP capabilities, Gauss-Seidel/diagonalization literature) is HIGH confidence; the primary theory source it maps features onto (`THEORY-papers.md`, the PSR note) is itself flagged MEDIUM confidence with no numerical case and one internal inconsistency. |
| Architecture | MEDIUM-HIGH | Integration mechanics (module layout, `Parameter` idiom, build-once discipline) are HIGH confidence — read directly from shipped v1 source (`src/models/oracle.jl`, `src/admm/*`). The exact leader/follower semantic mapping is explicitly MEDIUM confidence and deliberately left unresolved by this research pass (flagged for empirical Phase-1 resolution, not invented here). |
| Pitfalls | HIGH on Benders/strong-duality theory and the v1.0 oracle's actual code contract (read directly); MEDIUM on Nash-diagonalization convergence specifics (standard literature, not project-specific); MEDIUM-LOW on the PSR note's leader/follower and integer-cut claims (source self-contradicts). |

**Overall confidence:** MEDIUM-HIGH — the engineering/architecture/stack layer is solidly
grounded in the shipped v1.0 codebase; the residual uncertainty is concentrated entirely in the
underlying theory source's leader/follower semantics, which all four researchers independently
and explicitly refuse to resolve by invention, deferring instead to an empirical BilevelJuMP
gate as Phase 1's first deliverable.

### Gaps to Address

- **Leader/follower semantic ambiguity (no numerical reference case exists anywhere):** do not
  resolve by re-reading `THEORY-papers.md` again — resolve via the tiny BilevelJuMP MPEC
  cross-check plus a hand-worked toy enumeration, as Phase 1's first gating deliverable.
- **Coupling-dual sign/scale reconciliation (`λ_j` hourly ↔ `π_s` per-scenario):** no existing
  code performs this aggregation; write and test it explicitly against a hand-computed 2-node
  toy case rather than inferring the convention from the seam's abstract naming.
- **Empirical `NUMERICAL_ERROR` failure rate at planning-layer call volume:** v1's "rare,
  non-blocking" rate is not a reliable estimate once the oracle is pinned (pinning likely
  stresses the SOC exactness boundary differently) and re-solved inside nested loops — measure
  on the planning layer's own fixtures before assuming v1's rate holds.
- **Nash equilibrium uniqueness:** no general uniqueness guarantee exists for this game class;
  every reported equilibrium must be accompanied by a multi-seed/multi-order probe, and any
  thesis/paper figure must disclose the spread rather than presenting one run as definitive.

## Sources

### Primary (HIGH confidence)
- `src/models/oracle.jl`, `src/admm/*.jl`, `src/core/ModelContext.jl`, `src/core/status.jl`,
  `src/solver/ProblemClass.jl`, `src/solver/factory.jl` — read directly, current repo state
- Julia General registry `Versions.toml`/`Deps.toml` (fetched 2026-07-22) — all stack versions
- `jump-dev/HiGHS.jl` README, `joaquimg/BilevelJuMP.jl` docs/repo (fetched 2026-07-22)
- `CLAUDE.md`, `.planning/PROJECT.md`, `.planning/STATE.md` — locked project decisions and the
  documented, unresolved intermittent Clarabel `NUMERICAL_ERROR`

### Secondary (MEDIUM confidence)
- `.planning/research/THEORY-papers.md` (PSR N1-N2 internal note) — self-flagged MEDIUM
  confidence, no numerical case, internally inconsistent leader/follower labeling
- Gauss-Seidel/diagonalization for multi-leader-multi-follower games: arXiv 2404.02605, SIAM J.
  Optimization (existence/uniqueness restricted to special classes)
- BilevelJuMP.jl capabilities: arXiv 2205.02307, INFORMS Journal on Computing

### Tertiary (LOW confidence)
- General Benders/strong-duality and VI convergence theory — textbook-level, not
  independently re-verified against a live source this session, consistent with v1.0's own
  treatment

---
*Research completed: 2026-07-22*
*Ready for roadmap: yes*

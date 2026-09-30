# Phase 29: Genuine Bilevel TSO-DSO Variant - Research

**Researched:** 2026-09-30
**Domain:** Bilevel programming / MPEC single-level (KKT+complementarity) reformulation in JuMP; BilevelJuMP validation-oracle usage; HiGHS MILP capabilities
**Confidence:** MEDIUM-HIGH (the mathematical reformulation and the HiGHS/SOS1 capability finding are directly verified this session; the exact fixture numbers and the choice between the two documented network-valuation options are Claude's-discretion / [ASSUMED] and need confirmation during planning or execution)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Game formulation — BILEV-01**
- DSO LEADER chooses investment y; the tariff π is EXOGENOUS (a parameter). TSO FOLLOWER chooses its
  supply/interface quantity z to minimize its OWN cost c(z) − π·z — which differs from the leader's
  valuation of z — so bilevel ≠ joint whenever π ≠ the leader's marginal value.
- Follower convex LP/QP; DSO network LinDistFlow (LP); small fixtures (2- and 3-bus, T ≤ 2). SOCP
  lower level is out of scope.
- Production method: in-house KKT single-level reformulation in JuMP (complementarity via SOS1, or
  Fortuny-Amat with a MEASURED big-M), solved as MILP by HiGHS; documented why plain Benders is
  invalid here (the follower's value function is not the leader's recourse).

**Certification — BILEV-02**
- Two independent oracles: BilevelJuMP in a DIFFERENT mode than production (e.g. strong-duality or
  a different complementarity mode) AND brute-force enumeration over a leader decision grid.
- Fixture built so the follower's own cost makes it under-supply vs the joint optimum; assert a
  MEASURED bilevel-vs-joint gap well above tolerance, and production == bilevel ≠ joint.
- HiGHS `mip_rel_gap`/feasibility tolerances set explicitly and comparison epsilons MEASURED
  (memory: highs-exactness-defaults).

**API**
- New entry point `solve_bilevel!` (or `strategy=:bilevel`); existing `solve_stackelberg!` stays
  byte-identical but its docstring is honestly relabelled "integrated problem, Benders-decomposed".
- Unsupported inputs (SOCP lower level, integer follower, …) throw a clear ArgumentError — never a
  silent fallback.

**Process (carried)**
- ≤3 concurrent Julia executors; full suite after each wave with NO `.claude/worktrees/agent-*`
  present; executors never edit STATE/ROADMAP; findings → 29-FINDINGS.md (serialized) or SUMMARY;
  real executable verify scripts; long runs polled in the FOREGROUND (never end a turn waiting).

### Claude's Discretion
- SOS1 vs Fortuny-Amat choice (whichever HiGHS handles robustly — HiGHS has no native SOS1, so
  research must confirm), exact fixture numbers, result struct fields.

### Deferred Ideas (OUT OF SCOPE)
- Price-setting leader (π as a leader decision) — possible follow-up.
- SOCP lower level — out of scope.
- Planning docs refresh / game-theory statement — Phase 31 (BILEV-08).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BILEV-01 | Genuinely bilevel TSO–DSO variant: TSO follower minimizes its own cost, DSO leader pays tariff π·z, follower objective differs from leader's view. Solved by hand-rolled loop OR appropriate reformulation where plain Benders is no longer valid, documented. | §Architecture Patterns (KKT single-level MILP), §Common Pitfalls (why Benders fails here), §Code Examples (SOS1 complementarity via HiGHS bridge), §Pattern Map |
| BILEV-02 | BilevelJuMP certification fixture where bilevel optimum provably differs from joint optimum; production method matches bilevel, not joint. | §Architecture Patterns (fixture design), §Validation Architecture, §Code Examples (brute-force + BilevelJuMP oracle) |
</phase_requirements>

## Summary

The current `solve_stackelberg!` (src/planning/benders.jl) is confirmed — by direct reading of
`follower.jl`, `master.jl`, `subproblem.jl`, `benders.jl`, and the Phase-11 BilevelJuMP certification
fixture (`test/test_planning_certification.jl`) — to be the **integrated single-level problem**
decomposed by Benders, not a genuine bilevel game: the follower's own true cost (`c_inv·x_inv +
Σc_op[t]·x_op[t]`) is fed **unmodified** into the leader's epigraph (`add_optimality_cut!(master, :x,
follower_res.cost, follower_res.π_s, ...)`), and the existing BilevelJuMP toy fixture's Upper-level
objective *literally repeats* the Lower level's own cost terms verbatim
(`0.3*y_inv + 1.0*x_inv + 0.5*x_op - (2*z - 0.5*z^2)`). There is no wedge between what the follower
optimizes and what the leader cares about — which is exactly why BilevelJuMP cannot distinguish this
fixture from a joint optimum (memory: `quality-audit-2026-09-28-defects`). This phase must build a
new formulation with a genuine wedge: an **exogenous tariff π** that the follower is paid, distinct
from the leader's own (LinDistFlow-network-derived) valuation of the same quantity.

The recommended production method is a **single-level KKT/MPCC MILP**, built and solved ONCE (no
outer loop) in a **new** file (`src/planning/bilevel_kkt.jl`), reusing the project's `select_optimizer
(MILP())` factory (already a hard dependency — HiGHS) and existing boundary-guard/build-once idioms,
but a **new struct** distinct from `FollowerLP`/`BendersMaster` because the coupling direction is
inverted: the leader now supplies a **capacity bound** on the follower's investment (`x_inv <= y_inv`),
and the follower **freely chooses** its own operating quantity `z = x_op` — the reverse of today's
`FollowerLP`, where `z` is **pinned** onto the follower via an equality `Parameter`. This is the single
most important architectural fact this research turned up: **do not try to reuse `FollowerLP` for the
genuine-bilevel follower** — its coupling constraint (`x_op[t] == z[t]`, dual-pinned) encodes exactly
the joint-problem structure this phase must move away from.

The complementarity-reformulation question the roadmap flagged as unresolved ("does HiGHS support
SOS1 through MOI?") is now empirically answered: **HiGHS has no native SOS1/Indicator support**
(`MOI.supports_constraint` returns `false` for both), **but** JuMP/MathOptInterface 1.51.2 ships a
generic `SOS1ToMILPBridge` that automatically reformulates a `@constraint(model, [slack, dual] in
MOI.SOS1([1.0, 2.0]))` into a binary+big-M MILP **using the two variables' own declared bounds as the
big-M** — verified working end-to-end against the exact pinned HiGHS 1.24.1 this session. The bridge
**fails loudly** (`BridgeRequiresFiniteDomainError`) if either paired variable lacks a finite bound —
which is exactly the fail-loud behavior this project's conventions require, and removes any need to
hand-roll Fortuny-Amat's binary+big-M inequalities by hand. **Recommendation: use SOS1 via the
automatic bridge**, not hand-rolled Fortuny-Amat — less code, same underlying mechanism, and the
"big-M" is expressed as ordinary variable bounds that this phase must still derive by measurement
(see Pitfall 3). BilevelJuMP's own `SOS1Mode`, by contrast, does **not** work with HiGHS out of the
box (verified — it leaves its internal dual/slack variables unbounded, tripping the same bridge
error), so the phase's certification oracle should use `StrongDualityMode` (Ipopt, already proven to
work in the existing Phase-11 fixture) as the "different mode than production" BilevelJuMP oracle,
plus a brute-force grid-enumeration oracle (both required by CONTEXT.md).

**Primary recommendation:** build a brand-new, small (~150-250 line) `src/planning/bilevel_kkt.jl`
implementing the follower's KKT conditions directly as JuMP constraints with SOS1 complementarity
pairs (bounds derived by solving the tiny follower LP once at each extreme of the leader's feasible
investment range), wire it as `solve_bilevel!` with zero edits to `benders.jl`/`follower.jl`/
`master.jl`, and certify it against BilevelJuMP `StrongDualityMode` + brute-force grid enumeration on
a fixture whose exogenous π is set strictly below the DSO's own linear marginal valuation of z so the
follower provably under-supplies relative to the joint optimum.

## Architectural Responsibility Map

This project's "tiers" are not a web-app stack; the closest analog is the codebase's own layering
(data → power-flow/model builders → planning orchestration → solver factory → test/certification).
Mapped for this phase:

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Follower's own cost minimization (primal LP) | Planning orchestration (`src/planning/`, NEW file) | Solver factory (`select_optimizer(MILP())`) | The follower's primal variables live inside the single-level MILP built in the new file; HiGHS is selected only via the existing factory seam. |
| Follower's KKT stationarity + complementarity | Planning orchestration (`src/planning/`, NEW file) | Solver factory (SOS1 bridge, MOI/JuMP layer) | The KKT block is hand-written JuMP constraints; the SOS1→MILP reformulation happens transparently inside JuMP/MOI, never named explicitly by the model file (mirrors INFRA-02's "never name a solver/bridge" discipline). |
| Leader's investment decision + tariff payment | Planning orchestration (`src/planning/`, NEW file) | — | A single continuous variable + linear objective term; no new tier needed. |
| DSO's own valuation of z (network-derived) | Power-flow/model builders (`src/powerflow/LinDistFlow.jl`, `src/models/oracle.jl`) IF Option B chosen | Planning orchestration (fixed coefficient) IF Option A chosen | CONTEXT.md's "DSO network LinDistFlow (LP)" decision is satisfiable either by embedding the real LinDistFlow builder (Option B) or by deriving a fixed linear coefficient from ONE reference LinDistFlow solve (Option A) — see Open Questions (RESOLVED) #1. |
| Big-M / variable-bound derivation for SOS1 | Planning orchestration (`src/planning/bilevel_kkt.jl`, a helper function) | — | Two tiny LP solves (leader at y=0 and y=y_max) at build time; no new tier. |
| BilevelJuMP + brute-force certification oracles | Test/certification (`test/`) ONLY | — | Never touches `src/` (mirrors the existing `test_planning_certification.jl` convention: BilevelJuMP is a test-only dependency, never imported by `src/`). |

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | 1.30.1 [VERIFIED: test/Manifest.toml] | Algebraic modeling of the single-level KKT MILP | Already the project's sole modeling layer; no new dependency. |
| HiGHS | 1.24.1 [VERIFIED: test/Manifest.toml, and confirmed loadable this session] | Solves the KKT-reformulated MILP via `select_optimizer(MILP())` | Already a hard `[deps]` entry in the main `Project.toml` — **no new dependency for `src/`**. |
| MathOptInterface (MOI) | 1.51.2 [VERIFIED: test/Manifest.toml, and its `SOS1ToMILPBridge` empirically exercised this session] | Provides the automatic SOS1→MILP bridge that HiGHS itself doesn't natively support | Confirmed this session: `MOI.supports_constraint(HiGHS.Optimizer(), MOI.VectorOfVariables, MOI.SOS1{Float64})` returns `false`, but `@constraint(model, [a,b] in MOI.SOS1([1.0,2.0]))` solves correctly through JuMP's default caching+bridging optimizer as long as both `a` and `b` carry finite declared bounds. |

### Supporting (test-only, already pinned, no new dependency)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| BilevelJuMP | 0.6.3 [VERIFIED: test/Manifest.toml `= 0.6.3` pin] | Certification oracle #1 (BILEV-02), a DIFFERENT mode from production | `StrongDualityMode` (Ipopt) — already proven to work on the Phase-11 toy fixture; do not use `SOS1Mode` with HiGHS (see Pitfall 1). |
| Ipopt | 1.15.0 [VERIFIED: test/Manifest.toml] | Backend for BilevelJuMP `StrongDualityMode` | Test-only; already imported in `test_planning_certification.jl`. |
| HiGHS (test project) | 1.24.1 [VERIFIED] | Backend for the brute-force grid-enumeration oracle's per-grid-point follower LP solve | Reuse the SAME `select_optimizer(LP())`-style call, or a plain `Model(HiGHS.Optimizer)` in a test-only harness mirroring `BilevelCertFixture`'s existing INFRA-02 documented exception. |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| SOS1 (via automatic MOI bridge) | Hand-rolled Fortuny-Amat (explicit binary `b`, two `<=` inequalities with a numeric big-M constant per complementarity pair) | Functionally identical once you supply the same bound — SOS1 lets JuMP/MOI derive the binary+big-M wiring from the variables' own bounds, so there is strictly less hand-written algebra and less surface for a sign/direction bug. Fortuny-Amat is the fallback ONLY if a future complementarity pair cannot be given finite bounds (the bridge then fails loudly and the phase must switch that one pair to hand-written Fortuny-Amat with a documented, measured big-M). |
| Hand-rolled single-level KKT MILP (production) | BilevelJuMP + a HiGHS-compatible mode, used as the PRODUCTION solver (not just certification) | CLAUDE.md and the project's own established convention (Phase 11) reserve BilevelJuMP as a validation-oracle-only, test-only dependency — never a production solver. Also, no BilevelJuMP mode is both HiGHS-compatible AND avoids the MIQP trap if any objective term is quadratic (see Pitfall 5). |
| Linear DSO valuation coefficient (Option A) | Fully embedded LinDistFlow network + linear-utility aggregator inside the single-level MILP (Option B) | Option B is more physically faithful to "DSO network LinDistFlow (LP)" but adds real network variables/constraints to the MILP (still solvable, LinDistFlow is LP) and forces every device utility in the fixture to stay strictly LINEAR (not quadratic) to avoid turning the outer problem into an unsolvable MIQP (the same trap the existing Phase-11 fixture's `BigMMode+HiGHS` regression already documents). Option A isolates that constraint to a single scalar/vector precomputed OUTSIDE the MILP. |

**Installation:** No new packages required — `HiGHS`, `JuMP` are already `[deps]` in the main
`Project.toml`; `BilevelJuMP`, `Ipopt` are already pinned in `test/Project.toml`/`test/Manifest.toml`.

**Version verification:** confirmed directly against `test/Manifest.toml` (git-tree-sha pinned) and by
loading each package in `julia --project=test` this session (`HiGHS`, `JuMP`, `BilevelJuMP` all import
cleanly; `MOI.SOS1` constraint construction and solve exercised live against HiGHS 1.24.1).

## Package Legitimacy Audit

**No new external packages are required by this phase.** Every library referenced above (`JuMP`,
`HiGHS`, `MathOptInterface`, `BilevelJuMP`, `Ipopt`) is already a pinned dependency in either the main
`Project.toml` (`JuMP`, `HiGHS`) or `test/Project.toml`/`test/Manifest.toml` (`BilevelJuMP`, `Ipopt`,
`MathOptInterface` transitively). The slopcheck / registry-verification protocol is not applicable —
there is nothing new to install.

| Package | Registry | Age | Source Repo | slopcheck | Disposition |
|---------|----------|-----|--------------|-----------|-------------|
| (none — no new packages) | — | — | — | — | N/A |

**Packages removed due to slopcheck [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none.

## Architecture Patterns

### System Architecture Diagram

```
                    ┌─────────────────────────────────────────────────────┐
                    │        build_bilevel_kkt(...)  (build ONCE)          │
                    │  src/planning/bilevel_kkt.jl  (NEW FILE)             │
                    │                                                     │
  leader inputs     │  1. Pre-pass: solve tiny follower LP twice          │
  (c_y, y_max, π,   │     (y=0, y=y_max) via plain JuMP+HiGHS to MEASURE  │
   c_inv, c_op,     │     finite bound candidates for every dual/slack    │
   corridor_cap,    │     variable that will need an SOS1 pair.           │
   x_inv_max,       │            │                                        │
   [Option A: v]    │            ▼                                        │
   [Option B: feeder│  2. Build ONE JuMP Model(select_optimizer(MILP())): │
   + LinDistFlow +  │     - leader var: y_inv  (continuous, bounded)      │
   linear aggregator│     - follower primal vars: x_inv, z[1:T]           │
   if network-       │       (bounded using the measured bounds)          │
   embedded valuation)│    - follower dual vars: μ_cap[t], ρ_y, ρ_lo_xinv,│
                    │       μ_lo_z[t]  (bounded, >= 0)                     │
                    │     - [Option B only] LinDistFlow network vars      │
                    │       + linear aggregator utility, contribute!()    │
                    │       reused verbatim                               │
                    │            │                                        │
                    │            ▼                                        │
                    │  3. Follower KKT block (linear):                    │
                    │     - stationarity (2 equations, T+1 total)         │
                    │     - primal feasibility (follower's own <= rows)   │
                    │     - dual feasibility (all duals >= 0, already in  │
                    │       variable bounds)                              │
                    │     - complementarity: SOS1([slack_i, dual_i])      │
                    │       for each of the (2T+2) constraint pairs       │
                    │            │                                        │
                    │            ▼                                        │
                    │  4. Leader objective (linear, single level):        │
                    │     min c_y*y_inv + Σ_t π[t]*z[t] − W(z)            │
                    │       [Option A: W(z)=Σ_t v[t]*z[t], fixed coeffs]  │
                    │       [Option B: W(z) = welfare terms from the      │
                    │        embedded LinDistFlow + linear aggregator]    │
                    └──────────────────────┬──────────────────────────────┘
                                           │  optimize!() — ONE solve, no loop
                                           ▼
                    ┌─────────────────────────────────────────────────────┐
                    │  solve_bilevel!(...) returns                        │
                    │  (; y, z, x_inv, duals, total_cost, model)          │
                    └──────────────────────┬──────────────────────────────┘
                                           │
              ┌────────────────────────────┼─────────────────────────────┐
              ▼                            ▼                             ▼
   test-only: BilevelJuMP        test-only: brute-force grid      test-only: joint
   StrongDualityMode (Ipopt)     enumeration over y (uses a       reference solve
   on the IDENTICAL fixture      SEPARATE, build-once follower    (no π at all — leader
   (independent MPEC reduction)  LP with y as a Parameter UPPER   directly optimizes
                                 BOUND on x_inv, re-solved per     y, x_inv, z using the
                                 grid point via HiGHS — mirrors    TRUE valuation v)
                                 the Parameter/re-solve idiom of
                                 FollowerLP but with the INVERTED
                                 coupling direction)
              └────────────────────────────┴─────────────────────────────┘
                                           │
                                           ▼
                         assert: production ≈ BilevelJuMP ≈ brute-force
                                ≠ joint (measured gap >> tolerance)
```

### Recommended Project Structure
```
src/planning/
├── bilevel_kkt.jl        # NEW — build_bilevel_kkt / solve_bilevel! (production, one-shot MILP)
├── follower.jl            # UNCHANGED — byte-identical, still used by solve_stackelberg!
├── master.jl               # UNCHANGED
├── benders.jl              # UNCHANGED — only its module-header docstring gains one relabelling
│                            #   sentence ("integrated problem, Benders-decomposed"), per API decision
└── ...                      # everything else untouched

test/
├── test_planning_bilevel.jl                 # NEW — unit/boundary-guard tests for build_bilevel_kkt!/solve_bilevel!
├── test_planning_certification_bilevel.jl   # NEW — BILEV-02: BilevelJuMP + brute-force + joint-optimum
│                                              #   certification, mirrors test_planning_certification.jl's shape
└── fixtures_planning.jl                      # EXTENDED — add the new fixture's hand-derived/measured constants
                                               #   (mirrors the existing N1_Y_HAND/N1_Z_HAND/N1_OBJ_HAND block)
```

### Pattern 1: Follower KKT-as-JuMP-constraints (the core new pattern, no in-repo analog)

**What:** The follower's own LP
`min_{x_inv, z} c_inv*x_inv + Σ_t (c_op[t] − π[t])*z[t]  s.t.  z[t] <= corridor_cap*x_inv (μ_cap[t]),
x_inv <= y_inv (ρ_y), x_inv >= 0 (ρ_lo), z[t] >= 0 (μ_lo[t])` is embedded directly as its OWN KKT
system inside the single-level MILP, rather than solved as a separate subproblem re-solved in a loop.

**When to use:** Exactly the genuine-bilevel case where the follower's objective differs from what
the leader cares about — a Benders cut built from the follower's own dual would be a cut on the WRONG
function (see Common Pitfalls #1).

**Example (illustrative, T=1 for brevity — generalizes to T<=2 by the same pattern per hour):**
```julia
# Source: derived this session from the follower LP's own KKT conditions (standard
# Karush-Kuhn-Tucker stationarity/complementarity for a linear program in <= form);
# cross-checked against BilevelJuMP's own KKT-mode wiring (~/.julia/packages/BilevelJuMP/*/src/modes/sos1.jl)
# and empirically validated this session that MOI's SOS1ToMILPBridge reformulates it correctly on HiGHS.
model = Model(select_optimizer(MILP()))

# --- Leader ---
@variable(model, 0 <= y_inv <= y_max)

# --- Follower primal (bounds MEASURED by a pre-pass solve, see Pitfall 3) ---
@variable(model, 0 <= x_inv <= x_inv_max)
@variable(model, 0 <= z <= z_ub)             # z_ub = corridor_cap * x_inv_max (a valid, cheap bound)

# --- Follower duals (>= 0, upper bounds MEASURED, see Pitfall 3) ---
@variable(model, 0 <= mu_cap <= MU_CAP_UB)
@variable(model, 0 <= rho_y  <= RHO_Y_UB)
@variable(model, 0 <= rho_lo <= RHO_LO_UB)
@variable(model, 0 <= mu_lo  <= MU_LO_UB)

# --- Stationarity (linear equalities, no complementarity needed here) ---
@constraint(model, c_inv - corridor_cap*mu_cap + rho_y - rho_lo == 0)   # d/d(x_inv)
@constraint(model, (c_op - pi_tariff) + mu_cap - mu_lo == 0)            # d/d(z)

# --- Primal feasibility (already partly in variable bounds; the coupling one is separate) ---
@expression(model, slack_cap, corridor_cap*x_inv - z)
@constraint(model, slack_cap >= 0)
@expression(model, slack_y, y_inv - x_inv)
@constraint(model, slack_y >= 0)
# x_inv >= 0 and z >= 0 are already the variable's own lower bounds; their "slack" IS the
# variable itself.

# --- Complementarity via the automatic SOS1->MILP bridge (Pitfall 3: EVERY paired
# variable must carry a FINITE bound, or MOI throws BridgeRequiresFiniteDomainError) ---
@constraint(model, [slack_cap, mu_cap] in MOI.SOS1([1.0, 2.0]))
@constraint(model, [slack_y,   rho_y ] in MOI.SOS1([1.0, 2.0]))
@constraint(model, [x_inv,     rho_lo] in MOI.SOS1([1.0, 2.0]))
@constraint(model, [z,         mu_lo ] in MOI.SOS1([1.0, 2.0]))

# --- Leader objective (Option A: fixed linear valuation v) ---
@objective(model, Min, c_y*y_inv + pi_tariff*z - v*z)

optimize!(model)
```

### Pattern 2: Measured, not guessed, complementarity bounds (the "big-M" derivation)

**What:** Before building the MILP above, solve the follower's OWN tiny LP (as a genuinely separate,
throwaway `Model(select_optimizer(LP()))`) at the two extremes of the leader's feasible range
(`y_inv = 0` and `y_inv = y_max`), read the resulting primal/dual values, and set each SOS1-paired
variable's upper bound to a documented safety multiple (e.g. 10×, following this project's own
`KNOWN_OPTIMUM_ATOL`/`JOINT_RECOURSE_GAP_TOL` "measure, don't guess" convention) of the largest
observed magnitude for that quantity across both extreme solves.

**When to use:** Every complementarity pair in Pattern 1's KKT block.

**Validity check (mandatory, mirrors this project's own certificate-not-assumption discipline):**
after `optimize!`, assert that **no** complementarity variable's value sits at (or within solver
tolerance of) its derived upper bound — a binding "big-M" bound is invalid evidence that the true
optimum was cut off, not a benign coincidence.

### Pattern 3: Inverted coupling direction vs. the existing `FollowerLP`

**What:** The existing `FollowerLP` (`src/planning/follower.jl`) has the leader PIN `z` onto the
follower via an equality `Parameter` (`coupling[t]: x_op[t] == z[t]`) — the leader dictates the exact
quantity, and the follower's only freedom is its investment `x_inv`. The genuine-bilevel follower must
have the OPPOSITE coupling: the leader bounds the follower's investment (`x_inv <= y_inv`), and the
follower is FREE to choose whatever `z` (= `x_op`) is optimal for its own `c(z) − π·z`. This is why a
NEW struct/file is required, not a parametrized reuse of `FollowerLP`.

### Anti-Patterns to Avoid

- **Reusing `FollowerLP`'s `coupling[t]: x_op[t] == z[t]` for the genuine-bilevel follower:** this
  bakes in the joint-problem coupling direction and would silently reproduce the "bilevel == joint"
  degeneracy this phase exists to fix.
- **Any quadratic term inside the single-level MILP's objective or constraints:** the existing
  `test_planning_certification.jl` already found — and documents as a PERMANENT negative regression —
  that `BilevelJuMP.BigMMode` + HiGHS cannot solve a bilevel reduction whose upper-level objective is
  quadratic (produces a genuine MIQP, `termination_status == MOI.OTHER_ERROR`, not a bound-tuning
  issue). The SAME trap applies to this phase's own hand-rolled MILP: keep every objective/constraint
  term strictly affine (Option A's fixed linear coefficient `v`, or Option B's LinDistFlow network with
  a strictly LINEAR aggregator utility, never the quadratic `ToyElasticDevice`-style utility used
  elsewhere in the codebase).
- **BilevelJuMP `SOS1Mode` + HiGHS as the "different mode" certification oracle:** empirically fails
  this session (`BridgeRequiresFiniteDomainError`) because BilevelJuMP's own SOS1 wiring leaves the
  dual/slack pair unbounded. Use `StrongDualityMode` (Ipopt) instead — already proven in the Phase-11
  fixture.
- **Silently inheriting `select_optimizer(MILP())`'s existing `mip_feasibility_tolerance = 1e-9`
  without re-measuring it against the new model's own constraint scale:** the factory file's own WR-03
  comment explicitly warns the NEXT `MILP()` consumer (this phase is it) to re-measure, not assume,
  that this global tight tolerance is safe for a structurally different MILP (see Pitfall 6).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Complementarity `slack_i · dual_i = 0` reformulation | Manual binary `b_i` + two big-M inequalities (`slack_i <= M*(1-b_i)`, `dual_i <= M*b_i`) written by hand | `@constraint(model, [slack_i, dual_i] in MOI.SOS1([1.0, 2.0]))` | JuMP/MOI's `SOS1ToMILPBridge` (MOI 1.51.2, confirmed shipped and working against HiGHS 1.24.1 this session) does the identical reformulation automatically from the two variables' own declared bounds, with less code and a built-in fail-loud guard (`BridgeRequiresFiniteDomainError`) if a bound is missing — a class of bug a hand-rolled version would NOT catch automatically. |
| Deriving a "safe" big-M constant | Guessing a large round number (e.g. `1e6`) | Solve the tiny follower LP at both extremes of the leader's range first, then set the bound to a documented multiple of the observed magnitude, and assert post-solve that no complementarity variable sits at its bound | This project's own `KNOWN_OPTIMUM_ATOL`/`JOINT_RECOURSE_GAP_TOL` convention (memory: highs-exactness-defaults) already establishes "measure, don't guess" as the house style for exactly this class of tolerance/bound; an oversized guessed M also numerically weakens the MILP's LP relaxation and can slow branch-and-bound for no reason, while an undersized one silently cuts off the true optimum. |
| A second, independent bilevel certification path | Hand-writing your own KKT-vs-BilevelJuMP cross-check from scratch | BilevelJuMP `StrongDualityMode` (already proven, Ipopt-backed, works for LP lower levels since strong duality of an LP is a linear-in-the-duals equality even though it is bilinear in (primal,dual) jointly — Ipopt handles this as a small NLP) | Re-implementing an independent MPEC reformulation by hand defeats the purpose of an INDEPENDENT oracle — BilevelJuMP is exactly this project's chosen validation-oracle tool (CLAUDE.md, carried from Phase 11). |

**Key insight:** every piece of genuinely new mechanics this phase needs (SOS1 complementarity,
big-M/bound derivation, an independent bilevel oracle) already has a proven, in-repo or in-ecosystem
analog — the actual novel work is entirely in the MATHEMATICAL MODEL (the follower's KKT conditions
for the NEW tariff-based objective), not in inventing new optimization machinery.

## Common Pitfalls

### Pitfall 1: Plain Benders is invalid for a genuine bilevel game (the BILEV-01 documentation requirement)
**What goes wrong:** Feeding the follower's own reported cost/dual directly into the leader's Benders
epigraph (exactly what `add_optimality_cut!(master, :x, follower_res.cost, follower_res.π_s, ...)`
does today) silently assumes the follower's value function IS the leader's own cost-to-go.
**Why it happens:** Standard Benders/L-shaped decomposition requires the subproblem's reported
optimal-value function to be a valid (convex, in the master's decision) description of what the MASTER
actually pays. When the follower minimizes `c(z) − π·z` but the leader's true payoff at the SAME `z`
is `π·z − v(z)` — a DIFFERENT function of `z` — a cut built from the follower's own dual describes the
sensitivity of the FOLLOWER's private objective, not the leader's. WebSearch-verified (MEDIUM
confidence, cross-referenced against the bilevel-programming literature on Benders-for-bilevel, e.g.
Bagnoli et al./B&M-style approaches surveyed in "Benders Subproblem Decomposition for Bilevel Problems
with Convex Follower" and "A Survey on Mixed-Integer Programming Techniques in Bilevel Optimization")
that even the specialized Benders-for-bilevel literature only works by first taking the KKT/duality
route — confirming the correct fix is exactly the single-level KKT reformulation CONTEXT.md already
locked in.
**How to avoid:** Document this explicitly in the new file's module header (mirrors this codebase's
own convention of explaining "why not X" prominently — see `benders.jl`'s own header comments) and in
the phase's docs update — never attempt a `corner_recourse`-style cutting-plane loop against the
follower's raw cost for this variant.
**Warning signs:** If a future contributor is tempted to reuse `add_optimality_cut!`/`BendersMaster`
for this variant "for consistency," that is the warning sign — the two problems have genuinely
different mathematical structure, not just different code style.

### Pitfall 2: BilevelJuMP `SOS1Mode`/`IndicatorMode` silently fail on HiGHS
**What goes wrong:** `BilevelModel(HiGHS.Optimizer, mode=BilevelJuMP.SOS1Mode())` throws
`MathOptInterface.Bridges.BridgeRequiresFiniteDomainError` at `optimize!` time (verified this
session on a trivial 2-variable toy bilevel model), NOT a clean unsupported-mode error — the failure
surfaces deep in `final_touch` of the bridge machinery.
**Why it happens:** BilevelJuMP's own `sos1.jl` (`~/.julia/packages/BilevelJuMP/*/src/modes/sos1.jl`)
creates the complementarity `slack`/`dual` pair with NO explicit finite upper bound (the slack is
`MOI.add_constrained_variable(m, s)` where `s` only bounds it below by the constraint's own sense, and
the KKT dual variable is likewise only sign-constrained) — the doc-listed solver set for `SOS1Mode`
(Cbc, Xpress, Gurobi, CPLEX, SCIP) all have NATIVE SOS1 support and never need the MOI bridge at all;
HiGHS is not in that list for exactly this reason.
**How to avoid:** Use `StrongDualityMode` (Ipopt) as the certification oracle, as the existing
Phase-11 fixture already does successfully — do not attempt `SOS1Mode`/`IndicatorMode`/`BigMMode`
with HiGHS as the CERTIFICATION oracle for this phase (BigMMode+HiGHS is additionally already a
documented PERMANENT negative regression for any quadratic upper-level term, per the existing test
file).
**Warning signs:** `MOI.OTHER_ERROR` or a `BridgeRequiresFiniteDomainError` stack trace mentioning
`SOS1ToMILPBridge`/`IndicatorToMILPBridge` inside BilevelJuMP's own generated model.

### Pitfall 3: An unbounded (or too-loosely-bounded) complementarity pair
**What goes wrong:** Either the SOS1 bridge throws (unbounded case) or, if bounds ARE supplied but far
too loose, HiGHS's branch-and-bound spends needlessly long closing an oversized MILP gap, or — worse —
a TOO TIGHT bound silently cuts off the true optimum, producing a wrong answer with no error at all.
**Why it happens:** The follower's dual variables (`μ_cap`, `ρ_y`, `ρ_lo`, `μ_lo`) have no natural
bound from the model's own primal data the way `x_inv`/`z` do (`x_inv_max`, `corridor_cap*x_inv_max`)
— their magnitude depends on the LP's own conditioning (roughly, the ratio of objective-coefficient
scale to constraint-coefficient scale).
**How to avoid:** Pattern 2 above — solve the tiny follower LP at both extremes first and measure.
**Warning signs:** Post-solve, any complementarity variable sitting at (or within `1e-6` of) its
declared upper bound is the tell-tale sign of an invalid, too-tight bound; a validity assertion for
this must be part of `solve_bilevel!`'s own contract (report or throw, per this project's status-
policy convention), not left to a human to notice.

### Pitfall 4: `select_optimizer(::MILP)`'s existing tight tolerances are UNTESTED beyond one consumer
**What goes wrong:** `mip_feasibility_tolerance => 1e-9` (globally set in `src/solver/factory.jl`) was
tuned SOLELY against `build_master_integer`'s own box constraint on one specific fixture (Phase 24) —
its own header comment (WR-03) explicitly warns that a NEW MILP consumer (this phase) inherits it
silently and "may not want 1e-9 feasibility," and that on a larger/harder MILP this tight a tolerance
"can measurably slow or stall branch-and-bound... or cause HiGHS to report spurious infeasibility."
**Why it happens:** `select_optimizer(::MILP)` has no keyword-override seam today (unlike `::NLP`/
`::SOCP`, which both accept `attrs...` layered on top of the base attributes) — every `MILP()` caller
gets the exact same global tolerance.
**How to avoid:** At implementation time, first try the shared default as-is (the new MILP here is
tiny — at most ~10 binaries after SOS1-bridging for a T<=2, 2-3-bus fixture — likely fine). If it
stalls or produces a spurious-infeasible result, extend `select_optimizer(::MILP; attrs...)` with a
keyword passthrough (exactly mirroring the existing `::NLP`/`::SOCP` pattern already in the same
file), and document the NEW model's own measured tolerance choice — never silently loosen the shared
default in place (this would violate `build_master_integer`'s own certified exactness claim).
**Warning signs:** `termination_status` other than `MOI.OPTIMAL` on a tiny, obviously-feasible
fixture, or a measurably slow solve (more than a fraction of a second) on a 2-3-bus/T<=2 instance.

### Pitfall 5: Any quadratic term anywhere in the single-level MILP produces an unsolvable MIQP
**What goes wrong:** Exactly the documented, PERMANENT negative regression already in
`test_planning_certification.jl` (`BilevelJuMP.BigMMode` + HiGHS on a quadratic upper-level objective
returns `MOI.OTHER_ERROR`, "Cannot solve MIQP problems with HiGHS" — not a bound-tuning issue, a
categorical solver-capability gap).
**Why it happens:** HiGHS is an LP/MILP solver; it does not support mixed-integer QUADRATIC programs
at all, regardless of Big-M/SOS1 bound choice.
**How to avoid:** Keep every term in the single-level MILP's objective and constraints strictly
AFFINE. If Option B (embedded LinDistFlow + aggregator) is chosen over Option A (fixed linear
coefficient), the aggregator's utility function in THIS fixture must be linear (e.g., a fixed
per-unit valuation, not the codebase's usual quadratic `ToyElasticDevice`/prosumer utility forms).
**Warning signs:** `termination_status(model) == MOI.OTHER_ERROR` with no other diagnostic, or HiGHS's
own console message "Cannot solve MIQP problems with HiGHS" (silenced by `output_flag => false` in
production — watch for the bare status instead).

### Pitfall 6: Confusing "bilevel ≠ joint" with an ordinary solver-tolerance artifact
**What goes wrong:** A false-positive "genuine gap" that's actually within the MILP's own
`mip_rel_gap`/measured-atol noise floor, or a false-negative "no gap" caused by picking `π` too close
to the true marginal valuation `v` by accident.
**Why it happens:** This project has documented this exact class of mistake repeatedly (memory:
`highs-exactness-defaults`, the v2.1 "knife-edge-fragile" retraction) — a claimed structural finding
that later turns out to be solver noise.
**How to avoid:** Pick `π` deliberately and substantially different from `v` (not just epsilon-off),
verify the resulting `z*` genuinely differs between the bilevel and joint solves (not just the
objective value), and set `mip_rel_gap = 0.0` (already the factory default) so the MILP's own
reported optimum has zero solver-tolerance slack to hide behind.
**Warning signs:** A measured bilevel-vs-joint gap that's within one or two orders of magnitude of
`mip_feasibility_tolerance`/`KNOWN_OPTIMUM_ATOL`-class quantities (currently `1e-9`/`~4e-8` in this
codebase) is a red flag, not a result.

## Code Examples

### Deriving measured SOS1 bounds (Pattern 2, concrete)
```julia
# Source: derived this session; mirrors this project's own "measure, don't guess" convention
# (src/planning/benders.jl's KNOWN_OPTIMUM_ATOL/JOINT_RECOURSE_GAP_TOL header comments).
function _measure_follower_bounds(; corridor_cap, x_inv_max, c_inv, c_op, pi_tariff, y_max, safety = 10.0)
    duals_lo = Float64[]; duals_hi = Float64[]
    for y_probe in (0.0, y_max)
        m = Model(select_optimizer(LP()))
        @variable(m, 0 <= x_inv <= x_inv_max)
        @variable(m, 0 <= z)
        @constraint(m, cap, corridor_cap * x_inv - z >= 0)
        @constraint(m, inv_bound, x_inv <= y_probe)
        @objective(m, Min, c_inv * x_inv + (c_op - pi_tariff) * z)
        optimize!(m)
        is_solved_and_feasible(m; dual = true) || continue   # y_probe=0 forces x_inv=z=0, still solves
        push!(duals_hi, abs(dual(cap)))
        push!(duals_hi, abs(dual(inv_bound)))
    end
    m_ub = safety * max(1e-6, maximum(duals_hi; init = 0.0))
    return m_ub   # use as the SAME upper bound for every dual variable in the KKT block (documented,
                  # not hand-picked — re-derive per fixture, never hardcode across fixtures)
end
```

### Verifying HiGHS solves SOS1-bridged complementarity correctly (empirically confirmed this session)
```julia
# Source: verified live this session against the exact pinned HiGHS 1.24.1 / MOI 1.51.2.
using HiGHS, JuMP
m = Model(HiGHS.Optimizer); set_silent(m)
@variable(m, 0 <= x[1:2] <= 5)              # BOTH bounds finite -- required by the bridge
@constraint(m, x in MOI.SOS1([1.0, 2.0]))   # at most one of x[1], x[2] may be nonzero
@objective(m, Max, x[1] + x[2])
optimize!(m)
# result: termination_status(m) == MOI.OPTIMAL, value.(x) == [0.0, 5.0] -- confirms the complementarity
# is genuinely enforced (both nonzero would give 10.0, a strictly better but infeasible-under-SOS1 point)
```

### The unbounded-pair failure mode (fail LOUD, verified this session)
```julia
# Source: verified live this session.
m = Model(HiGHS.Optimizer); set_silent(m)
@variable(m, x[1:2] >= 0)                   # NO upper bound
@constraint(m, x in MOI.SOS1([1.0, 2.0]))
@objective(m, Max, x[1] + x[2])
optimize!(m)
# throws MathOptInterface.Bridges.BridgeRequiresFiniteDomainError -- confirms the bridge fails loudly,
# never silently, on a missing bound. This IS the desired behavior (matches T-11-03/WR-03 style
# fail-loud guards elsewhere in this codebase) -- do not work around it by catching and ignoring.
```

## State of the Art

| Old Approach (this repo, pre-Phase-29) | Current/recommended Approach (Phase 29) | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `solve_stackelberg!`'s Benders loop feeds the follower's own true cost unmodified into the leader's epigraph | A single-level KKT MILP where the follower's KKT conditions (built from a DIFFERENT objective, `c(z)-π·z`) are embedded directly | Phase 29 (this phase) | `solve_stackelberg!` is honestly relabelled "integrated problem, Benders-decomposed" (API decision); a NEW `solve_bilevel!` exists alongside it for genuinely divergent leader/follower objectives. |
| BilevelJuMP certification (Phase 11) could only ever confirm bilevel==joint (by fixture construction) | BILEV-02's new fixture is DESIGNED so bilevel≠joint by a measured margin | Phase 29 | The certification suite gains a genuine discriminating test, closing the gap the 2026-09-28 quality audit flagged. |

**Deprecated/outdated:** none — `solve_stackelberg!` remains fully valid for the problem it actually
solves (the integrated/Benders-decomposed problem); it is not being replaced, only more honestly named.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Choosing Option A (a fixed linear DSO valuation coefficient `v`, derived from one reference LinDistFlow/oracle solve) rather than Option B (fully embedding the LinDistFlow network inside the single-level MILP) is an acceptable reading of CONTEXT.md's "DSO network LinDistFlow (LP)" decision. | Architectural Responsibility Map, Open Questions #1 | If the user actually wants a literal embedded network (Option B), the planner needs to add tasks for reusing `contribute!(LinDistFlow(), ctx, feeder; T)` and a strictly-linear aggregator device, which is a larger blast radius than Option A. Low risk (both are locked-decision-compliant; this is a discretion item, explicitly called out as such). |
| A2 | A safety multiple of 10× the measured extreme-case dual magnitude is a sufficient (not too tight, not absurdly loose) SOS1 bound for this fixture's scale. | Pattern 2, Pitfall 3 | If the true optimum's dual value at the ACTUAL optimal `y_inv` (not just the two extremes probed) exceeds 10× the extremes' magnitude — possible if the follower's response is highly nonlinear in y (it isn't, for an LP: the value function is piecewise-linear in y, and its slope in y is one of the finitely many dual values achievable across the small number of bases, so the two extremes should bracket it, but this must be VERIFIED post-solve per Pitfall 3, not assumed). |
| A3 | HiGHS's default `mip_feasibility_tolerance = 1e-9` (inherited from `select_optimizer(MILP())`) will not stall or misbehave on this phase's KKT-MILP, given its small size (comparable to or smaller than `build_master_integer`'s own MILP). | Pitfall 4 | If wrong, the planner needs a task to extend `select_optimizer(::MILP; attrs...)` with a keyword-override seam — a small, well-scoped, single-file change, not a redesign. |
| A4 | Setting `π[t]` strictly below the DSO's marginal valuation `v[t]` (rather than above, or time-varying in a more complex way) is sufficient to produce a clean, analytically-explicable "follower under-supplies vs. joint optimum" fixture, satisfying CONTEXT.md's "Fixture built so the follower's own cost makes it under-supply vs the joint optimum" instruction. | Summary, Architecture Patterns | If the chosen numbers produce a degenerate (zero-measure) gap due to a binding capacity/investment bound coinciding at both the bilevel and joint optima, the planner/executor must adjust exact fixture numbers (already flagged Claude's discretion) — no architectural rework needed. |

**If this table is empty:** N/A — table populated above; none of these threaten the phase's
feasibility, only the exact fixture-tuning details already flagged as Claude's discretion.

## Open Questions (RESOLVED)

1. **Does HiGHS support SOS1 complementarity, directly or via a bridge? (roadmap-flagged open
   question from Phase 24/29 sequencing notes)**
   - What we know: HiGHS itself has zero native SOS1/Indicator support (`MOI.supports_constraint`
     returns `false` for both, verified this session).
   - What's unclear (was): whether JuMP's default bridging would paper over this transparently.
   - **RESOLVED (verified this session):** Yes — MOI 1.51.2 ships `SOS1ToMILPBridge`, which JuMP's
     default `CachingOptimizer`+bridge stack applies automatically and TRANSPARENTLY. It requires
     every variable in the SOS1 set to carry a finite declared bound (fails loudly,
     `BridgeRequiresFiniteDomainError`, if not). **Recommendation:** use SOS1 via this automatic
     bridge for production; do NOT hand-roll Fortuny-Amat unless a specific complementarity pair
     genuinely cannot be given a finite bound.

2. **Does BilevelJuMP's own `SOS1Mode`/`FortunyAmatMcCarlMode`/`IndicatorMode` work with HiGHS at
   all, for the certification oracle? (roadmap-flagged, carried from Phase 24's own unresolved flag)**
   - What we know: the official BilevelJuMP docs list `SOS1Mode`/`IndicatorMode` as usable with
     "MIP solvers (Cbc, Xpress, Gurobi, CPLEX, SCIP)" — HiGHS is conspicuously absent from that list.
   - **RESOLVED (verified this session):** `BilevelJuMP.SOS1Mode()` + `HiGHS.Optimizer` throws
     `BridgeRequiresFiniteDomainError` on even a trivial 2-variable toy bilevel model, because
     BilevelJuMP's own SOS1 wiring (`~/.julia/packages/BilevelJuMP/*/src/modes/sos1.jl`) does not
     bound its internal slack/dual pair. **Recommendation:** use `StrongDualityMode` (Ipopt) as the
     "different mode than production" certification oracle — already proven working on the existing
     Phase-11 fixture, no new risk.

3. **Is the leader's investment `y` continuous, integer, or both? (research prompt's own question)**
   - What we know: CONTEXT.md's locked decisions describe `y` only as "investment," with no mention
     of integrality; BILEV-07 (integer Nash diagonalization) is explicitly a LATER phase (31), and
     this phase's own "Claude's Discretion" list does not mention integrality.
   - **RESOLVED (by scope, not by new evidence):** continuous-only for this phase, matching the
     project's own "continuous investment first" convention (v2.0's PVAL-04 no-binaries guard) and
     keeping the KKT-MILP's ONLY binaries the ones introduced by the SOS1 complementarity bridge
     itself (not by the leader's own decision). Supporting an integer leader investment on top of
     this KKT-MILP is straightforward LATER (just declare `y_inv` `Int`) but is explicitly out of
     this phase's locked scope — flag as a natural BILEV-07-adjacent follow-up, not a Phase 29 task.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| HiGHS (main env) | Production `solve_bilevel!` MILP | Yes [VERIFIED: `Project.toml [deps]`, loaded this session] | 1.24.1 | — |
| JuMP (main env) | Production model building | Yes [VERIFIED] | 1.30.1 | — |
| MathOptInterface (transitive) | SOS1→MILP bridge | Yes [VERIFIED, exercised live this session] | 1.51.2 | — |
| BilevelJuMP (test env only) | BILEV-02 certification oracle #1 | Yes [VERIFIED: `test/Manifest.toml` pin `= 0.6.3`] | 0.6.3 | — |
| Ipopt (test env only) | BilevelJuMP `StrongDualityMode` backend | Yes [VERIFIED] | 1.15.0 | — |
| HiGHS (test env, for brute-force oracle) | BILEV-02 grid-enumeration oracle | Yes [VERIFIED] | 1.24.1 | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none — every tool this phase needs is already installed and
pinned; there is nothing to fall back from.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `Test` (stdlib) + `TestItems`/`TestItemRunner` (`@testitem`/`@testmodule`), this project's established idiom |
| Config file | none dedicated — `test/runtests.jl` is the TestItemRunner entrypoint; `test/Project.toml`/`Manifest.toml` pin the test-only env |
| Quick run command | Direct Julia/Test.jl script under `--project=.` reproducing the relevant `@testitem` body (memory: `gsd-plan-verify-testitemrunner-trap` — TestItemRunner does NOT resolve under `--project=.`, it is test-only) |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (~21-36 min per current baseline; memory: `background-suite-orphan-race` — run detached/foreground, never end a turn waiting, and verify no `.claude/worktrees/agent-*` exists first) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BILEV-01 | `solve_bilevel!` solves the genuine-bilevel MILP to a certified optimum on the new fixture, boundary guards throw `ArgumentError` for SOCP-lower-level/integer-follower inputs | unit | direct Julia script reproducing `test/test_planning_bilevel.jl`'s `@testitem` bodies under `--project=.` | ❌ Wave 0 — new file |
| BILEV-01 | Production KKT-MILP answer matches an independent brute-force grid enumeration of the follower's true best response | integration | direct Julia script reproducing `test/test_planning_certification_bilevel.jl`'s brute-force `@testitem` under `--project=.` | ❌ Wave 0 — new file |
| BILEV-02 | Production answer matches BilevelJuMP `StrongDualityMode` on the identical fixture (different mode than production) | integration | direct Julia script reproducing the BilevelJuMP `@testitem` under `--project=test` (BilevelJuMP is test-only, needs the test env) | ❌ Wave 0 — new file |
| BILEV-02 | Bilevel optimum genuinely differs from the joint (single-planner) optimum by a MEASURED margin well above tolerance | regression/golden | same file, a dedicated `@testitem` asserting `abs(bilevel_total - joint_total) > MEASURED_GAP_FLOOR` | ❌ Wave 0 — new file |
| API decision | `solve_stackelberg!` stays byte-identical; only its docstring changes | regression | existing `test_planning_benders.jl`/`test_planning_certification.jl`/`test_planning_goldens.jl` full pass, unmodified | ✅ already exists, must stay green |

### Sampling Rate
- **Per task commit:** direct Julia/Test.jl script reproducing the specific new `@testitem`(s) touched, under `--project=.` (production) or `--project=test` (certification, since BilevelJuMP is test-only) — NOT the full TestItemRunner invocation (memory trap).
- **Per wave merge:** full suite (`julia --project=. -e 'import Pkg; Pkg.test()'`), run detached/foreground per the `background-suite-orphan-race` memory's protocol, with `.claude/worktrees/agent-*` confirmed absent first.
- **Phase gate:** full suite green (current baseline to diff against: 30703 pass / 0 fail / 0 error / 5 broken, per STATE.md's Phase 28 close) before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/test_planning_bilevel.jl` — covers BILEV-01 unit/boundary-guard behavior of `build_bilevel_kkt`/`solve_bilevel!`.
- [ ] `test/test_planning_certification_bilevel.jl` — covers BILEV-02 (both oracles + the joint-vs-bilevel gap assertion).
- [ ] `src/planning/bilevel_kkt.jl` — the production module itself (not a test gap, but the Wave-0-blocking new file every above test depends on).
- [ ] `fixtures_planning.jl` extension — the new fixture's hand-derived/measured constants, mirroring the existing `N1_Y_HAND`/`N1_Z_HAND`/`N1_OBJ_HAND` block, needed before the certification tests can assert against fixed goldens.
- Framework install: none — `Test`/`TestItems`/`TestItemRunner`/`BilevelJuMP`/`Ipopt`/`HiGHS` are all already present.

## Security Domain

This is a single-user, offline PhD-research optimization library with no network exposure,
authentication surface, or externally-supplied untrusted input in the sense ASVS targets (all inputs
are researcher-authored Julia literals/fixtures). Per this project's own established convention (no
prior phase has included a Security Domain section, and none of V2/V3/V4/V6 apply to a local
JuMP/solver pipeline), most ASVS categories are N/A here. The one genuinely applicable control is
input validation on the new public API surface (`solve_bilevel!`), which this research's own Pattern
1/Common Pitfalls already require in the form of fail-loud `ArgumentError` boundary guards.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A — no auth surface, local research library |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A |
| V5 Input Validation | Yes | Boundary-guard `ArgumentError`s on `build_bilevel_kkt!`/`solve_bilevel!` (unsupported SOCP lower level, integer follower, shape mismatches) — mirrors this codebase's own established `T >= 1`/`length(...) == T`-style guards in `follower.jl`/`master.jl`/`subproblem.jl`. |
| V6 Cryptography | No | N/A — never hand-rolled here regardless; not relevant to this phase |

### Known Threat Patterns for this stack
Not applicable — no network/auth/crypto surface is touched by this phase. The only "threat" analog
in a research-correctness sense is a SILENT wrong answer (an unvalidated big-M cutting off the true
optimum, or a solver-tolerance artifact mistaken for a genuine bilevel≠joint finding) — both are
already covered as Common Pitfalls #3 and #6 above, with mandatory report-or-throw validity checks
rather than a STRIDE-style table.

## Pattern Map

Analogs for each new/modified file this phase is expected to touch:

| New/Modified File | Closest In-Repo Analog | What to Reuse | What Must Differ |
|--------------------|------------------------|----------------|-------------------|
| `src/planning/bilevel_kkt.jl` (NEW) | `src/planning/follower.jl` + `src/planning/master.jl` (structural idiom: boundary guards before assembly, `select_optimizer(...)` factory call, single `build_*` + `solve_*!` pair, exported at file end) | Boundary-guard-before-assembly discipline; `Model(select_optimizer(MILP()))` factory seam; `ArgumentError` naming the offending value; docstring style documenting WHY (mirrors `benders.jl`'s own extensive "why" header comments) | Coupling direction is INVERTED vs `FollowerLP` (Pattern 3) — do not copy `follower.jl`'s `coupling[t]: x_op[t]==z[t]` Parameter-pin idiom; this is a ONE-SHOT solve (no `Parameter`/re-solve loop needed in production, unlike every existing `planning/` file). |
| `src/solver/factory.jl` (CONDITIONALLY modified — only if Pitfall 4 bites) | `select_optimizer(::NLP; attrs...)` / `select_optimizer(::SOCP; attrs...)` (existing keyword-passthrough pattern) | The exact `attrs...` splat-on-top-of-base-attributes pattern already used for NLP/SOCP | `select_optimizer(::MILP)` currently has NO such seam — must ADD it without changing `build_master_integer`'s existing byte-identical default call (`select_optimizer(MILP())` with no kwargs must stay identical). |
| `test/test_planning_bilevel.jl` (NEW) | `test/test_planning_benders.jl` (unit-level `@testitem`s for a single-solve planning entrypoint, boundary-guard negative tests) | `@testitem ... tags=[:planning]` convention; boundary-guard `@test_throws ArgumentError` style | Tests a ONE-SHOT MILP solve, not an iterative Benders loop — no `BendersTrace`/checkpoint assertions needed. |
| `test/test_planning_certification_bilevel.jl` (NEW) | `test/test_planning_certification.jl` (the Phase-11 `BilevelCertFixture` `@testmodule` + two-mode-agreement `@testitem` pattern) | The `@testmodule` + `@testitem ... setup=[...]` structure; the INFRA-02-documented exception allowing direct `using HiGHS, Ipopt, BilevelJuMP, JuMP` in a test-only file; the "cross-check BOTH independent oracles, then cross-check against production" three-way assertion shape | Must ALSO build a THIRD reference model (the joint/single-planner optimum, no `π` at all) and assert `bilevel_total` genuinely differs from `joint_total` by a measured margin — the existing file only ever asserts AGREEMENT between oracles, never a DELIBERATE measured DISAGREEMENT against a third joint baseline. |
| `test/fixtures_planning.jl` (EXTENDED) | The existing `N1_Y_HAND`/`N1_Z_HAND`/`N1_OBJ_HAND` `const` block inside `@testmodule PlanningFixtures` | Plain top-level `const`s, no top-level solve call (T-04-08-style contract already documented in the file's own header) | New constants need a documented DERIVATION comment explaining the bilevel-vs-joint gap's provenance (measured, not guessed), mirroring the existing block's own "RE-DERIVED, NOT 11-01-PLAN.md's stated..." derivation-transparency convention. |
| `src/TSODSO.jl` (ONE new include line) | The existing `include("planning/master_integer.jl")` / `include("planning/benders.jl")` lines and their ordering-rationale comments | Add the new include AFTER `benders.jl`'s (diff-stability convention already stated in the surrounding comment block) | Nothing else in this file changes. |
| `src/planning/benders.jl` (module docstring ONLY) | N/A — this is the ONE locked-decision-mandated edit to an existing file | The API decision requires ONLY a docstring/header-comment relabelling ("integrated problem, Benders-decomposed") | `solve_stackelberg!`'s CODE must stay byte-identical — this is a comment-only diff, verify with a content-diff tool (the project already has one: `check_content_loss.py`, per STATE.md's JuliaFormatter hazard note) if any formatting pass touches this file. |

## Sources

### Primary (HIGH confidence)
- Direct code reading this session: `src/planning/follower.jl`, `src/planning/subproblem.jl`,
  `src/planning/master.jl`, `src/planning/benders.jl` (lines 1-120, 640-956), `src/planning/
  master_integer.jl` (lines 1-90), `src/solver/factory.jl`, `src/solver/ProblemClass.jl`,
  `src/TSODSO.jl`, `test/test_planning_certification.jl` (full file).
- Live empirical verification this session (`julia --project=test`): HiGHS's lack of native
  `MOI.SOS1`/`Indicator` support; JuMP/MOI's automatic `SOS1ToMILPBridge` working correctly on
  HiGHS 1.24.1 when both paired variables have finite bounds; the exact `BridgeRequiresFiniteDomainError`
  failure mode when a bound is missing; BilevelJuMP `SOS1Mode` + HiGHS failing with the same error.
- `test/Manifest.toml` / `test/Project.toml` — exact pinned versions (`BilevelJuMP = 0.6.3`,
  `HiGHS = 1.24.1`, `JuMP = 1.30.1`, `MathOptInterface = 1.51.2`, `Ipopt = 1.15.0`).
- `~/.julia/packages/BilevelJuMP/*/src/modes/sos1.jl` — direct source read confirming the unbounded
  slack/dual construction that causes the HiGHS-bridge failure.

### Secondary (MEDIUM confidence)
- WebFetch of `joaquimg.github.io/BilevelJuMP.jl/dev/tutorials/modes/` — the official BilevelJuMP
  modes-overview page, listing solver compatibility per mode (SOS1Mode/IndicatorMode: Cbc/Xpress/
  Gurobi/CPLEX/SCIP; BigMMode: any basic-binary MIP solver with bounds; StrongDualityMode/ProductMode:
  NLP solvers).
- WebSearch on "Benders decomposition bilevel programming follower value function convexity" —
  cross-referenced against the general bilevel-programming literature (Benders-for-bilevel survey
  material) confirming that plain Benders on the follower's own cost is invalid outside the joint-
  problem-degenerate case, and that KKT/MPCC reformulation is the standard correct alternative.
- `.planning/research/THEORY-papers.md`, `.planning/research/THEORY-thesis.md` — confirm the source
  theory's Stackelberg-via-Benders method (Paper 2) is itself built on the JOINT-problem decomposition
  (follower's dual `π_s` = "marginal cost," fed directly into the leader's cut), i.e. the SAME structure
  as `solve_stackelberg!` — corroborating that the existing production code faithfully implements the
  cited theory, and that "genuine bilevel" (this phase) is a DELIBERATE departure from that theory into
  a new, harder game structure, not a bug fix to the existing one.

### Tertiary (LOW confidence)
- None — every claim above was either directly verified this session or corroborated against an
  official doc page / the project's own committed source.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every package is already installed/pinned; no new-dependency risk at all.
- Architecture (KKT/SOS1 reformulation mechanics): HIGH — empirically verified against the exact
  pinned solver/JuMP/MOI versions this session, not just read from docs.
- Architecture (exact fixture numbers, Option A vs B network-valuation choice): MEDIUM — these are
  explicitly Claude's-discretion items per CONTEXT.md; the mechanics are solid but the specific
  numbers/embedding choice need to be fixed during planning or execution, not assumed from this
  research alone.
- Pitfalls: HIGH — every pitfall listed was either empirically reproduced this session (SOS1/HiGHS,
  BilevelJuMP SOS1Mode failure, the unbounded-pair error) or is a direct, cited restatement of an
  existing in-repo documented finding (MIQP incapacity, tight MILP tolerances, measure-don't-guess).

**Research date:** 2026-09-30
**Valid until:** ~30 days (stable ecosystem — JuMP/HiGHS/MOI/BilevelJuMP versions are all exact-pinned
in this repo and change only on a deliberate version bump; re-verify the SOS1-bridge behavior if any
of `JuMP`/`HiGHS`/`MathOptInterface` version pins change before this phase executes).

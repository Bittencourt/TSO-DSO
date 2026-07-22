# Architecture Research

**Domain:** v2.0 planning-layer integration — hand-rolled Benders + Gauss–Seidel diagonalization for a Stackelberg–Nash TSO–DSO investment game, built on top of the shipped v1.0 operational transactive-energy core (JuMP/Clarabel/HiGHS, SEAM-01 coupling stubs).
**Researched:** 2026-07-22
**Confidence:** MEDIUM-HIGH on the integration mechanics (grounded in the actual v1 source: `src/models/oracle.jl`, `src/admm/*`, `src/core/*`); MEDIUM on the exact leader/follower semantic mapping (the PSR source note itself is author-flagged as inconsistent on this point — see "Open Question" below, which this document deliberately does NOT resolve by invention).

---

## Guiding principle: the planning layer is additive, not a refactor

v1 was built oracle-shaped on purpose. `src/models/oracle.jl`'s header states the coupling
seam (`z ↔ p_ag`, `λ_j ↔ π_s`) exists specifically "so the deferred Stackelberg-Nash planning
layer (Phase 8/9) will consume WITHOUT a rewrite." The v1 ADMM layer (`src/admm/`) already
proved the pattern this milestone must repeat: **never call the monolithic one-shot solve
(`solve_welfare`/`operational_oracle`) inside a hot loop.** `DsoOpt.jl`/`AgrOpt.jl` do NOT call
`solve_welfare` per ADMM iteration — they reuse its underlying builders (`contribute!` on the
power-flow formulation and on each aggregator) to build a JuMP model **once**, then mutate a
handful of coefficients and re-solve. The Benders subproblem must follow the identical
discipline: build once, reuse the SAME `contribute!` builders, expose the coupling flow as a
**JuMP `Parameter`** (not a rebuild), and read the coupling dual off the balance constraint the
same way the DADP is already read. This is the single architectural decision that makes v2.0
additive: **zero modifications to `src/models/oracle.jl` or `src/models/welfare_solve.jl`.**

---

## (1) The oracle interface: what v1 exposes, what is missing, what to add

### What `operational_oracle` already gives you (verified in `src/models/oracle.jl`)

```julia
operational_oracle(feeder, pf, aggregators; λ₀, T=24, z=nothing, role=:follower,
                    objective_hook=identity, horizon_state=nothing, allow_export=false)
    -> (; cost, π, dadp, ctx)
```

- `cost` = the GLB-CVX welfare optimum (`objective_value`).
- `π` = `_coupling_dual(ctx, z)` — currently **only implemented for `z === nothing`**: the
  free-frontier DADP at `feeder.root` (`dual.(ctx.constraints[:balance_p][root, :])`).
- For `z !== nothing` it **throws `ArgumentError`** by design (threat T-04-13, "no silent
  partial pinning") — this is the exact SEAM-01 extension point named in the docstring
  ("PLAN-01/02 (Phase 8/9) extension point... NOT wired into `solve_welfare` in Phase 4").
- `role` is validated (`:leader`/`:follower`) but inert; `objective_hook`/`horizon_state` are
  typed-but-inert stubs for the stochastic/MPC axes, irrelevant to v2.0.

**Verdict: the v1 stub's *signature* is the right contract and needs no change. The
*implementation* behind `z` is genuinely missing and must be added — but NOT by editing
`oracle.jl` or `welfare_solve.jl`.** Making `p_import` a real Parameter-pinned coupling
variable inside `solve_welfare` would touch a file exercised by 1946 existing tests for no
reason; the ADMM precedent (`DsoOpt.jl` reusing `contribute!` instead of calling
`solve_welfare`) shows the correct move is a **new, purpose-built build-once subproblem** that
reuses the same underlying builders.

### The extension: `src/planning/subproblem.jl` (new, mirrors `DsoOpt.jl`)

```julia
struct OracleProblem{Z, F}
    model::Model
    ctx::ModelContext
    z::Z                 # z[t] :: VariableRef, each `in Parameter(0.0)` — the coupling flow
    feeder::F
    T::Int
end

function build_oracle_problem(feeder, pf::AbstractPowerFlow, aggregators; λ₀, T::Int = 24)
    model = Model(select_optimizer(problem_class(pf)))       # INFRA-02, never names a solver
    ctx = ModelContext(model)
    ctx.meta[:feeder] = feeder; ctx.meta[:T] = T

    contribute!(pf, ctx, feeder; T)                          # VERBATIM reuse (as DsoOpt.jl does)
    for agg in aggregators
        contribute!(agg, ctx; T)                              # VERBATIM reuse — sums U_ag, :Rp/:Rq
    end

    @variable(model, z[t = 1:T] in Parameter(0.0))            # the coupling flow z (thesis z_y,s)
    add_to_residual!(ctx, :Rp, feeder.root, t, z[t])           # for each t: injects z at the frontier
    close_balance!(ctx)                                        # :Rp==0 ∀(j,t) → register :balance_p

    @objective(model, Max, ctx.meta[:objective] - sum(λ₀[t]*z[t] for t in 1:T))
    return OracleProblem(model, ctx, collect(z), feeder, T)
end

function solve_oracle!(op::OracleProblem, z_trial::AbstractVector{<:Real})
    set_parameter_value.(op.z, z_trial)                        # cheap re-solve (no rebuild)
    assert_solved!(op.model; dual = true)                      # STRICT — see Anti-Pattern below
    cost = objective_value(op.model)
    π = dual.(op.ctx.constraints[:balance_p][op.feeder.root, :])
    return (; cost, π)
end
```

This is a **genuine JuMP `Parameter`** on the coupling flow itself (CLAUDE.md's prescribed
idiom — `@variable(m, x in Parameter(v)); set_parameter_value(x, v)`), not the price-as-`Float64`
workaround ADMM uses for `λ_j` (that workaround exists only because `λ·pag` would be an
indefinite bilinear in a `Max` objective; here `λ₀ᵀ·z` with `z` as a `Parameter` and `λ₀` a
constant vector is affine — no bilinear risk). Because `z` now closes the frontier balance
directly (replacing `solve_welfare`'s free `p_import` variable), `π` falls out of the **same**
`:balance_p` dual read `_coupling_dual` already performs — no new dual-extraction machinery,
same registry (`ctx.constraints`), same `assert_solved!` gate, same fail-loud discipline.

**Do the v1 stubs suffice?** The *signature/contract* — yes. The *executable z-pin* — no,
and it should NOT be retrofitted into `operational_oracle`/`solve_welfare`; it should be a new,
additive, build-once sibling that reuses the same `contribute!` seam. `operational_oracle`
itself is untouched and remains useful as a one-shot reference/cross-check call (e.g., the
free-import welfare baseline, or an occasional whole-model sanity re-solve outside the hot
Benders loop).

---

## (2) Module layout: `src/planning/` mirroring `src/admm/`

`src/admm/` splits cleanly into: a pure-data ledger (`residuals.jl`), two build-once JuMP
wrappers (`AgrOpt.jl`, `DsoOpt.jl`), and one orchestrator with zero JuMP-building logic of its
own (`solve_admm.jl`). `src/planning/` repeats that shape one level up:

```
src/planning/
├── subproblem.jl     # OracleProblem: build-once Parameter-z wrapper (mirrors DsoOpt.jl)
├── cuts.jl            # BendersCutStore: pure data, NO JuMP (mirrors residuals.jl)
├── master.jl          # BendersMaster: plain JuMP LP/QP over (y_inv, z, α); add_cut!
├── benders.jl          # solve_benders: single-distributor outer loop (mirrors solve_admm.jl)
├── diagnostics.jl      # BendersResiduals: UB/LB gap ledger, pure data (mirrors residuals.jl)
├── coupling.jl         # shared N2/transmission-reinforcement stand-in — SEE OPEN QUESTION below
├── diagonalize.jl       # Gauss-Seidel Nash sweep over Vector{DistributorState}
└── validation.jl        # BilevelJuMP small-instance cross-check (weakdep-gated)
```

Wired into `src/TSODSO.jl` **after** `admm/` (needs `ModelContext`, `assert_solved!`,
`select_optimizer`/`problem_class`, and the `contribute!` builders already established) and
**after** `models/oracle.jl` (the documented v1 contract these files fulfill):

```julia
include("planning/cuts.jl")          # pure data — no deps beyond Base
include("planning/diagnostics.jl")   # pure data — mirrors admm/residuals.jl
include("planning/subproblem.jl")    # OracleProblem — needs ModelContext, contribute!, select_optimizer
include("planning/coupling.jl")      # shared reinforcement stand-in (new model, no v1 mirror)
include("planning/master.jl")        # BendersMaster — needs select_optimizer, assert_solved!
include("planning/benders.jl")       # solve_benders — orchestrates subproblem+master+cuts
include("planning/diagonalize.jl")   # Gauss-Seidel sweep over solve_benders calls
include("planning/validation.jl")    # BilevelJuMP oracle — weakdep-gated, see (4)
```

Each file "declares its own `export`s per the include-graph convention" exactly as the
`admm/` block's comment in `TSODSO.jl` documents — no shared-edit-surface files beyond the one
line appended to the top module.

**New vs. modified, explicit:**

| File | New / Modified | Notes |
|------|-----------------|-------|
| `src/planning/*.jl` (all 8) | **NEW** | Entire subtree; zero v1 files touched. |
| `src/models/oracle.jl` | **UNMODIFIED** | Remains the documented one-shot contract; not called from the hot Benders loop. |
| `src/models/welfare_solve.jl` | **UNMODIFIED** | `contribute!` builders reused verbatim, exactly as `DsoOpt.jl` already does. |
| `src/admm/*.jl` | **UNMODIFIED** | No coupling between the ADMM outer loop and the planning outer loop; both are independent `AbstractSolveStrategy`-adjacent orchestrators sitting above the same builder layer. |
| `src/TSODSO.jl` | **MODIFIED (append-only)** | 8 new `include(...)` lines in the established comment-block convention. |

---

## (3) Data flow: single-distributor Benders, then Gauss–Seidel diagonalization

### Single-distributor Benders (thesis Problem 4 / eq. 4a–4f)

```
BendersMaster (JuMP LP/QP; NOT a ModelContext — no power-flow, no residual registry needed)
  vars:  y_inv, y_inv,flex  (continuous flexibility investment, v2.0 scope — no binaries)
         z[t]               (trial import/coupling profile — free variable in the MASTER)
         α                  (epigraph: anticipated operational cost as a function of z)
  obj:   min  c_y,inv·y_inv + c_y,inv,flex·y_inv,flex + α
  cons:  investment bounds (1d); flexibility-feasibility coupling (1i-analog on z vs y_inv,flex)
         α ≥ w^k + π^k · (z − z^k)   for k = 1..K   (Benders cuts, appended by BendersCutStore)

solve_benders loop (mirrors solve_admm.jl's shape):
  1. BUILD ONCE: `sub = build_oracle_problem(feeder, pf, aggregators; λ₀, T)`
                 `master = build_benders_master(...)`
  2. for k in 1:maxiter
       (z_k, y_inv_k, α_k) = solve!(master)                     # LP/QP, assert_solved!(strict)
       (cost_k, π_k) = solve_oracle!(sub, z_k)                   # SOCP/QP, assert_solved!(strict)
       add_cut!(cutstore, w = cost_k, π = π_k, z_at = z_k)       # pure-data append
       add_cut_constraint!(master, cutstore, k)                  # ONE new @constraint on α
       gap = α_k - cost_k                                        # UB−LB-style Benders gap
       record!(residuals, k, gap)                                 # pure-data ledger (mirrors AdmmResiduals)
       converged(residuals, ε) && break
  3. FAIL LOUD if maxiter reached without gap ≤ ε (mirrors solve_admm.jl's maxiter ErrorException)
```

The **cut store is pure data**, no JuMP, exactly like `AdmmResiduals` — it holds
`Vector{(w::Float64, π::Vector{Float64}, z_at::Vector{Float64})}` triples; `master.jl` is the
ONLY file that turns a stored triple into a JuMP `@constraint`. This separation is what let
`residuals.jl` be reused unmodified across Phase 6→7 in the ADMM case, and buys the same thing
here: the cut *bookkeeping* (used for convergence plots, regression fixtures, and the
validation cross-check in (4)) never depends on a live JuMP model.

### Gauss–Seidel diagonalization over multiple distributors

```
DistributorState  (one per distributor i)
  feeder_i, aggregators_i, λ₀_i    — this distributor's own network/data (independent SOCP)
  sub_i::OracleProblem              — built once
  master_i::BendersMaster           — built once, cuts accumulate over the WHOLE run (not reset
                                       per sweep — a later sweep's master keeps prior cuts as a
                                       warm, still-valid outer approximation, since a valid
                                       Benders cut for fixed z_{-i} remains valid — only NEW cuts
                                       reflecting the current z_{-i} need to be added)
  z_i::Vector{Float64}              — this distributor's current equilibrium import trajectory

diagonalize(distributors::Vector{DistributorState}; maxsweeps, tol)
  for sweep in 1:maxsweeps
    for i in 1:N
      shared = coupling_state(distributors, i)      # OTHERS' fixed z_{-i} → shared reinforcement signal
      z_i_new, _ = solve_benders(distributors[i]; shared)   # inner Benders loop to full convergence
      Δ_i = norm(z_i_new - distributors[i].z_i)
      distributors[i].z_i = z_i_new
    end
    record_sweep!(diag_residuals, sweep, maximum(Δ_i for i in 1:N))
    converged(diag_residuals, tol) && return (; z_eq = [d.z_i for d in distributors], sweep)
  end
  error("diagonalize: FAILED to reach a fixed point in maxsweeps=$maxsweeps sweeps ...")  # fail loud
```

This is the direct Julia rendering of the thesis's own description: *"each optimizes taking
others' equilibrium flows as fixed... solved by Gauss–Seidel diagonalization — optimize each
distributor in turn, fixing others' flows, iterate to convergence."* The fixed-point residual
ledger (`diag_residuals`) is a second, small pure-data struct in `diagnostics.jl`, following
the exact same `record!`/`converged` idiom as `AdmmResiduals` (sequential-k fail-loud guard,
non-negative magnitude traces) — reuse the *pattern*, not the *type* (the shapes differ: ADMM
tracks per-iteration primal/dual norms, diagonalization tracks per-sweep max-Δz across
distributors).

### Open question this data flow surfaces (do not resolve by invention — flag for Phase 1)

The thesis note states Nash coupling arises because *"cut coefficients `w_i^k, π_i^k` depend on
others' reinforcements"* — i.e., distributor `i`'s Benders subproblem must somehow see a signal
from distributors `j≠i`. But `OracleProblem` as built above is **electrically local to
distributor `i`'s own feeder** — it has no notion of other distributors or of shared N2
transmission capacity at all. Nothing in v1 (`operational_oracle`, `contribute!`, `ModelContext`)
carries a cross-distributor coupling term. **A genuinely new small model is needed** —
`src/planning/coupling.jl` — representing the shared N2/transmission-reinforcement cost as a
function of the *vector* of distributors' import profiles (thesis eq. 2, `α({z_{y,s}})`,
parameterized by `x_inv`/`x_op` on the transmission side), returning both its own value and a
per-distributor marginal (`∂α/∂z_i`) to fold into `coupling_state(...)` above. **Without this
component the diagonalization loop has literally nothing shared to iterate on** — each
distributor's Benders problem would converge independently and "Nash" would be vacuous.

This is exactly the ambiguity the source material itself flags (`THEORY-papers.md`: *"the note
labels leader/follower inconsistently once,"* PROJECT.md: *"leader/follower-role inconsistency
and integer-cut correctness ... open concerns"*). Two readings are both defensible from the
text and this document does not adjudicate between them:

- **Reading A** — `operational_oracle`'s `(cost, π)` proxies the *transmission follower's*
  value function directly (the "Natural architecture" paragraph in `THEORY-papers.md` literally
  says the operational engine "plays the role of Paper 2's second-level subproblem"), and
  `coupling.jl` only needs to translate *aggregate* import volatility into a shared capacity
  signal — no separate cost model, just a shared capacity/price adjustment layered on `λ₀`.
- **Reading B** — `operational_oracle` represents the *distributor's own* day-ahead recourse
  (a two-stage invest-then-operate decomposition), and the transmission reinforcement cost
  `α({z_y,s})` is a genuinely separate, small LP (`coupling.jl` builds and solves it) whose dual
  is the real `π_s`, with the DADP (`operational_oracle`'s `π`) playing no role in the Nash
  coupling at all.

**Recommendation:** resolve this empirically, not by further reading of an already-flagged
MEDIUM-confidence source — build the tiny single-distributor BilevelJuMP MPEC first (see (4))
and check which reading reproduces its investment/import decision. This is a Phase-1
correctness gate, not a Phase-3 (diagonalization) one, precisely because the ambiguity lives at
the single-Stackelberg level already, before any Nash coupling is introduced.

---

## (4) Where BilevelJuMP plugs in: a parallel path, tiny instances only

`src/planning/validation.jl` is a **weakdep-gated, parallel** path — never called from
`solve_benders`/`diagonalize`, only from tests/experiments on deliberately tiny fixtures (2–3
bus toy feeder, 1–2 scenarios, few hours), mirroring how Gurobi/Mosek are reachable only through
package extensions (`ext/TSODSOGurobiExt`-style) so `using TSODSO` never hard-depends on
BilevelJuMP/PATHSolver.

```julia
function validate_single_distributor(tiny_spec)
    # (a) hand-rolled path: this project's own Benders loop
    benders_result = solve_benders(tiny_spec)

    # (b) independent path: BilevelJuMP's KKT/SOS1/Fortuny-Amat single-level reduction
    #     solving the SAME leader (investment+import) vs follower (reinforcement) MPEC
    #     as ONE compact JuMP model — no decomposition, no diagonalization.
    bilevel_result = solve_bilevel_reference(tiny_spec)   # BilevelJuMP.jl, tiny instance only

    return (; benders_result, bilevel_result,
              match = isapprox(benders_result.obj, bilevel_result.obj; rtol=1e-4))
end
```

Two uses, in priority order:

1. **Phase 1, first thing built** — pin down the Reading-A-vs-Reading-B ambiguity from (3) by
   comparing what the tiny hand-built MPEC actually computes for `y_inv`/`z`/`α` against each
   candidate wiring of `operational_oracle`/`coupling.jl`, BEFORE committing to the production
   Benders subproblem's exact semantics.
2. **Ongoing regression net** — once semantics are pinned, keep `validate_single_distributor`
   as a permanent tiny-fixture test (mirrors `test_admm_vs_central.jl`'s role for the
   operational layer): any future change to `subproblem.jl`/`master.jl` must keep matching the
   independent MPEC solve on the same toy case.

BilevelJuMP is **not** extended to the multi-distributor Nash case in v2.0 — its single-level
MPEC reduction does not scale to a genuine game among several leaders (per CLAUDE.md: *"Single-
level MPEC reductions blow up and diverge from the thesis's Benders/diagonalization method"*) —
so it validates rung 1 only, never the diagonalization loop.

---

## Architectural Patterns

### Pattern 1: Build-once oracle with a genuine JuMP `Parameter` for the coupling flow

**What:** `z[t] in Parameter(0.0)`, reused across every Benders iteration via
`set_parameter_value.(op.z, z_trial)`; the coupling dual `π` is read off the SAME `:balance_p`
registry the DADP already uses.
**When:** Any time a decomposition needs a "re-solve at a new exogenous value of a variable
that WAS a free decision variable in the monolithic model." Contrast with ADMM's `λ_j`
(a price coefficient, kept as a plain `Float64` because it multiplies a variable — a
`Parameter×variable` product is an indefinite bilinear a conic solver rejects). Here `z` closes
an equality residual and appears linearly in the objective (`λ₀ᵀz`, both affine in a
`Parameter`) — no bilinear risk, so the textbook `Parameter` idiom applies directly.
**Trade-offs:** One extra JuMP variable class to learn (`Parameter`), but eliminates a full
SOCP rebuild per Benders iteration — the single biggest performance lever available, and the
one CLAUDE.md explicitly calls out ("Rebuilding JuMP models each ADMM/Benders iteration" is in
the "What NOT to Use" table).

### Pattern 2: Pure-data cut store, JuMP-free

**What:** `BendersCutStore` holds `(w, π, z_at)` triples as plain arrays; `master.jl` is the
sole consumer that turns a triple into a `@constraint`. Mirrors `AdmmResiduals`.
**When:** Any accumulating diagnostic/decision record that must be inspectable, testable, and
plottable without a live JuMP model (regression fixtures, convergence plots via the existing
`TSODSOMakieExt` weakdep extension pattern).
**Trade-offs:** A tiny indirection (append to the store, then separately render the cut) buys
the same benefit `residuals.jl` already proved: the ledger survives independent of solver
backend and is trivially unit-testable.

### Pattern 3: Strict solve-gating on every cut-producing solve — no `allow_almost`

**What:** Every `solve_oracle!` call whose `(cost, π)` will be baked into a **permanent**
Benders cut MUST use `assert_solved!(model; dual = true)` with the STRICT default
(`allow_almost = false`), never the ADMM mid-loop relaxation (`allow_almost = true,
strict = false`).
**When:** Always, for every Benders subproblem solve. The master, too, should read `α`/`z`
only after a strict solve.
**Trade-offs / why this differs from ADMM:** ADMM's mid-loop tolerance is safe because the
residual loop **self-corrects** — an inexact intermediate iterate just costs an extra
iteration. A Benders cut is **added to the master and never removed**; an inexact `π` from an
`ALMOST_OPTIMAL`/`NEARLY_FEASIBLE` solve can silently insert an invalid (not a genuine
subgradient) cut that permanently miscuts the true optimum out of the master's feasible region,
with no self-correction mechanism. This is the single most important divergence from the
`src/admm/` pattern to carry into the planning layer, and it belongs in the phase's own
pitfalls note.

### Pattern 4: Gauss–Seidel diagonalization as sequential full-convergence Benders calls

**What:** `diagonalize` treats each distributor's Benders solve as an atomic, fully-converged
inner call; only after distributor `i`'s Benders loop reaches its own `ε` does the sweep move
to `i+1`. No interleaving of Benders iterations across distributors.
**When:** Matches the thesis's own description ("optimize each distributor in turn, fixing
others' flows, iterate to convergence") and is the simplest, most debuggable composition —
each `solve_benders` call is independently testable (Pattern-1-level unit tests) with no
cross-distributor state leaking into it except through the explicit `shared` argument.
**Trade-offs:** More total inner iterations than a jointly-interleaved scheme, but keeps the
outer Nash loop's state machine trivial (`Vector{DistributorState}` + one scalar per-sweep
`Δz`) and testable in isolation from Benders-loop internals — appropriate for a
correctness-first research bench per CLAUDE.md's stated priorities.

---

## Data Flow

### Coupling-flow direction (build-time → solve-time)

```
Scenario/feeder data (per distributor)
        │
        ▼
build_oracle_problem(feeder, pf, aggregators; λ₀, T)     ── ONCE ──
        │  reuses contribute!(pf, ctx, feeder) + contribute!(agg, ctx) VERBATIM
        │  z[t] in Parameter(0.0) replaces solve_welfare's free p_import
        ▼
OracleProblem{z, ctx}  ─────────────────────────────────────────────┐
        │                                                            │ solve_oracle!(op, z_trial)
        ▼                                                            │  → set_parameter_value.(z, z_trial)
BendersMaster (y_inv, z, α) ── solve! ──► z_k, y_inv_k ──────────────┘  → assert_solved!(strict)
        ▲                                                              → (cost_k, π_k)
        │  add_cut!(w=cost_k, π=π_k, z_at=z_k)
        └── BendersCutStore (pure data) ── render cut ──► @constraint(master, α ≥ w^k + π^k'(z-z^k))
```

### Diagonalization direction (sweep over distributors)

```
Vector{DistributorState}  (each: feeder_i, sub_i, master_i, cutstore_i, z_i)
        │
        ▼
for sweep in 1:maxsweeps
    for i in 1:N
        shared_i = coupling_state(others' z)          ── src/planning/coupling.jl (NEW model, see Open Q)
        z_i ← solve_benders(distributor_i; shared_i)   ── full inner convergence, Pattern 3/4
    Δ = max_i ‖z_i^{sweep} − z_i^{sweep−1}‖
    record_sweep!(diag_residuals, sweep, Δ)
    converged(diag_residuals, tol) ⇒ return z_eq
```

---

## Scaling Considerations

| Scale | Architecture response |
|-------|------------------------|
| Single distributor, tiny toy feeder (2–3 bus), Benders correctness only | `solve_benders` alone; cross-validate every run against `validation.jl`'s BilevelJuMP MPEC (Pattern 3/4 unnecessary at this size — correctness is the only goal). |
| Single distributor, IEEE-13-scale feeder | `OracleProblem` reuses the SAME validated `ConvexBranchFlow`/aggregator builders at full scale (no planning-specific scaling concern here — it inherits whatever `solve_welfare`/ADMM already validated); the Benders-specific cost is purely in cut-count growth (mitigate: cut aggregation / cut selection once cut counts exceed a few dozen — not needed for v2.0's continuous-only scope). |
| 2–3 distributors, Gauss–Seidel Nash | The `coupling.jl` shared-reinforcement model (Open Question in (3)) becomes load-bearing; validate the fixed point is a genuine Nash equilibrium (no distributor can unilaterally improve given others fixed) on a toy 2-distributor case before scaling. |
| Many distributors / integer investment (both explicitly OUT of v2.0 scope) | Binary-expansion + Lagrangian/integer-L-shaped cuts (thesis "integer case") — a LATER milestone; do not let the continuous-only `master.jl` design preclude adding a MILP variant of the same file later (keep `master.jl`'s public API — `add_cut!`, `solve!` — agnostic to whether `y_inv` is continuous or binary-expanded). |

**First likely bottleneck:** none at v2.0's stated scope (single-then-multi distributor,
continuous investment, toy-to-IEEE-13-scale feeders) — this milestone is about correctness of
a NEW decomposition axis, not throughput. Do not pre-optimize (CLAUDE.md's explicit
clarity-over-performance priority applies with even more force here than in v1, since the
model semantics themselves are still MEDIUM confidence).

---

## Anti-Patterns

### Anti-Pattern 1: Rebuilding the operational SOCP every Benders iteration

**What people do:** Call `operational_oracle(feeder, pf, aggregators; z=z_trial, ...)` (or a
freshly-`Model(...)`-built equivalent) inside the Benders `for k in 1:maxiter` loop.
**Why it's wrong:** Rebuilds the full `ConvexBranchFlow` + all-devices SOCP from scratch every
iteration — the exact "dominant, avoidable performance sink" CLAUDE.md calls out for both ADMM
and Benders. It also silently defeats the whole point of the SEAM-01 stub (built to make the
planning layer ADDITIVE, not a rebuild-heavy afterthought).
**Instead:** `build_oracle_problem` once per distributor; `solve_oracle!` mutates the `z`
`Parameter` and re-solves (Pattern 1).

### Anti-Pattern 2: Reusing ADMM's `allow_almost=true` tolerance for cut-producing solves

**What people do:** Copy `solve_agr!`/`solve_dso!`'s `strict=false` convenience into the
Benders subproblem solve, reasoning "it's an iterative loop, so a near-feasible point is fine."
**Why it's wrong:** ADMM's mid-loop tolerance is safe because of self-correction (the next
iteration corrects an inexact one). A Benders cut is a PERMANENT addition to the master's
feasible region for `α` — an inexact `π` from a near-feasible solve can insert an invalid cut
with no later correction, silently corrupting every subsequent master solve (Pattern 3).
**Instead:** Every solve whose `(cost, π)` becomes a cut uses the STRICT `assert_solved!`
default (`dual=true`, `allow_almost=false`).

### Anti-Pattern 3: Inventing a resolution to the leader/follower semantic ambiguity in code comments

**What people do:** Pick one of Reading A / Reading B from (3) and hard-code it into
`coupling.jl`/`subproblem.jl` without an independent check, because "the PSR note basically
says X."
**Why it's wrong:** The source is explicitly author-flagged as inconsistent on exactly this
point (`THEORY-papers.md`, PROJECT.md's own risk list). Silently picking a reading bakes an
unverified assumption into the one place (the coupling semantics) where the whole planning
layer's correctness lives.
**Instead:** Build the tiny BilevelJuMP MPEC FIRST (Pattern in (4)) and let the two independent
solves agree or disagree — resolve empirically, then document the resolution with a comment
citing the specific tiny-case evidence, not the note alone.

### Anti-Pattern 4: Coupling the diagonalization loop to Benders-loop internals

**What people do:** Have `diagonalize.jl` reach into `distributor_i.master.model` directly to
tweak constraints mid-sweep, or interleave partial Benders iterations across distributors for
"efficiency."
**Why it's wrong:** Breaks the clean state-machine boundary (Pattern 4) that makes each
`solve_benders` call independently testable; reproduces the exact "separate constraint code
for centralized vs ADMM" anti-pattern v1's own ARCHITECTURE.md warned against, one level up.
**Instead:** `diagonalize` only ever calls the public `solve_benders(distributor; shared)`
entry point and reads back `z_i`; all Benders-internal state stays inside `benders.jl`/
`master.jl`.

---

## Integration Points

### External libraries

| Library | Role | Notes |
|---------|------|-------|
| **JuMP.jl `Parameter`** | The coupling-flow mechanism | Already the CLAUDE.md-prescribed idiom; used here for `z`, not `λ`/`ρ` (those stay `Float64` per the ADMM bilinear lesson). |
| **HiGHS.jl** | `BendersMaster`'s LP/QP backend | `select_optimizer(LP())`/`select_optimizer(QP())`, same factory v1 already has — no new solver wiring needed for the continuous-investment v2.0 scope. |
| **Clarabel.jl** | `OracleProblem`'s SOCP backend | `select_optimizer(problem_class(pf))`, identical to `operational_oracle`'s own routing — zero new solver code. |
| **BilevelJuMP.jl (+ PATHSolver as its dependency for some reformulations)** | `validation.jl` only | Weakdep-gated (mirrors the existing Gurobi/Mosek extension pattern); never on the production Benders/diagonalization path. |

### Internal boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| `planning/subproblem.jl` ↔ `models/welfare_solve.jl`, `powerflow/*`, `devices/*` | Calls the SAME `contribute!` builder functions those files already export | Zero modification to any of them — identical reuse discipline to `admm/DsoOpt.jl`. |
| `planning/subproblem.jl` ↔ `models/oracle.jl` | **None at the hot-loop level** | `operational_oracle` remains a separate, unmodified one-shot entry point; not called by `solve_benders`. |
| `planning/master.jl` ↔ `planning/cuts.jl` | Reads pure-data triples, renders `@constraint` | Mirrors `admm/solve_admm.jl` ↔ `admm/residuals.jl`. |
| `planning/benders.jl` ↔ `planning/subproblem.jl` + `planning/master.jl` | Orchestration only, no JuMP building of its own | Mirrors `admm/solve_admm.jl`'s role over `AgrOpt`/`DsoOpt`. |
| `planning/diagonalize.jl` ↔ `planning/benders.jl` | Calls `solve_benders(distributor; shared)` as an atomic black box | Anti-Pattern 4 boundary. |
| `planning/diagonalize.jl` ↔ `planning/coupling.jl` | Reads/updates the shared reinforcement signal between sweeps | The genuinely NEW model — no v1 analog. |
| `planning/validation.jl` ↔ everything else | Read-only comparison, tiny fixtures only, weakdep-gated | Never imported by `benders.jl`/`diagonalize.jl`. |
| `core/status.jl` (`assert_solved!`) ↔ every planning solve | Same single choke point v1 established | Pattern 3 requires STRICT mode specifically for cut-producing solves. |

---

## Sources

- `src/models/oracle.jl` (read in full) — the exact v1 SEAM-01 contract, the `z`/`role`
  stub semantics, the documented "fails loudly rather than a silent partial pin" design intent.
  HIGH confidence (primary source, current repo state).
- `src/admm/solve_admm.jl`, `src/admm/AgrOpt.jl`, `src/admm/DsoOpt.jl`, `src/admm/residuals.jl`
  (read in full) — the hand-rolled build-once/re-solve/pure-data-ledger pattern this milestone
  must repeat; the `strict`/`allow_almost` solve-gating distinction that motivates Anti-Pattern 2.
  HIGH confidence (primary source).
- `src/core/ModelContext.jl`, `src/core/status.jl`, `src/solver/ProblemClass.jl`,
  `src/solver/factory.jl` (read in full) — `register_constraint!`/`add_to_residual!` registry
  API, `assert_solved!`/`assert_no_slack` gating, `select_optimizer`/`problem_class` dispatch.
  HIGH confidence (primary source).
- `.planning/research/THEORY-papers.md` — Paper 2 (PSR N1–N2 note) problem formulations
  (1)/(2)/(4)/(7)/(8)/(9), the Benders cut form (4f), the diagonalization description, and the
  explicitly author-flagged leader/follower labeling inconsistency this document deliberately
  does not resolve by invention. MEDIUM confidence (the source itself is MEDIUM confidence,
  per the project's own research).
- `.planning/PROJECT.md` (Current Milestone v2.0 section) — locked v2.0 scope (continuous
  investment first, hand-rolled Benders + diagonalization, BilevelJuMP validation-only), and
  the project's own named risk ("leader/follower-role inconsistency ... open concerns").
  HIGH confidence (primary source, current repo state).
- `CLAUDE.md` (project root) — the `Parameter`/warm-start idiom, the "never rebuild inside the
  loop" anti-pattern, the BilevelJuMP-as-oracle-only decision, the hand-rolled-over-framework
  decomposition stance. HIGH confidence (primary source, current repo state).
- `.planning/research/v1.0/ARCHITECTURE.md` — the v1 architecture this milestone extends;
  confirms `planning/` was reserved and stubbed from Phase 4 onward, and that ADMM/planning are
  meant to be independent orchestrators over the same builder layer. HIGH confidence (primary
  source, prior milestone's research).

---
*Architecture research for: v2.0 Stackelberg–Nash TSO–DSO planning-layer integration*
*Researched: 2026-07-22*

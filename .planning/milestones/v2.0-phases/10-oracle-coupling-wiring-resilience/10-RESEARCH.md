# Phase 10: Oracle Coupling Wiring & Resilience - Research

**Researched:** 2026-07-22
**Domain:** JuMP `Parameter`-based build-once subproblem wiring (Clarabel/SOCP), dual-sign/
time-aggregation reconciliation, Clarabel numerical-error retry + DrWatson-style checkpointing.
**Confidence:** HIGH on API mechanics and code seams (all empirically verified against the
installed environment and read directly from shipped source); MEDIUM on the exact retry-ladder
tuning and empirical failure rate (explicitly deferred to measurement against real fixtures,
per CONTEXT.md Claude's Discretion).

## Summary

Phase 10 turns three inert `oracle.jl` stubs into a live subproblem. The critical technical
question — "does a genuine JuMP `Parameter` actually work on a Clarabel-backed SOCP model, and
what does its raw `dual()` actually return?" — is **not settled by documentation alone**: JuMP's
own manual states `Parameter` "works with solvers that support `MOI.Parameter`, such as Ipopt"
and does not list Clarabel. This research resolved the ambiguity empirically by running small
Julia scripts directly against this project's pinned `Project.toml`/`Manifest.toml`
(JuMP 1.30.1, Clarabel 0.11.1): **`Parameter` works with Clarabel with no ParametricOptInterface
wrapper needed**, including inside a `SecondOrderCone` constraint, and `set_optimizer_attribute`
can be used to escalate Clarabel's numerical-conditioning settings on retry **without** touching
the model's variable/constraint count (build-once preserved). A second, more consequential
finding: the raw `dual()` on an equality-pin constraint does **NOT** always equal
`∂(objective)/∂z` as CONTEXT.md's D-06 docstring-math suggests — under a **`Max`**-sense
objective (which is exactly `solve_welfare`'s objective sense) the empirically measured raw dual
equals **`-∂(objective)/∂z`** (negated), while under a `Min`-sense toy it matches the gradient
directly. This is precisely why D-06 defers the leader/follower interpretation to Phase 11 and
mandates a hand-computed toy case rather than trusting the docstring formula — this research
provides both the mechanism (JuMP's dual convention is defined by constraint direction, not
objective sense — use `shadow_price()` for the textbook-signed version if ever needed) and a
ready-made toy-case template that reproduces the sign numerically.

The retry/checkpoint side of the phase (PLAN-03) has essentially all its plumbing already
established in the codebase and does not need new dependencies: `assert_solved!`'s thrown
`ErrorException` leaves `termination_status(model)`/`raw_status(model)` fully queryable in a
`catch` block (verified), so the retry wrapper can branch cleanly on `NUMERICAL_ERROR` vs. a
genuine `INFEASIBLE`/other failure that should fail immediately. Clarabel's actual installed
`Settings()` field list (introspected directly) gives concrete attribute names for the
escalating-perturbation ladder (`static_regularization_constant`, `dynamic_regularization_eps`,
`iterative_refinement_max_iter`, `equilibrate_max_iter`, etc.), settable post-build via
`set_optimizer_attribute` with zero rebuild. Checkpointing has a direct, already-used precedent
in `src/experiments/store.jl`: DrWatson's `@tagsave`/`safesave` (JLD2, resolved transitively via
DrWatson's own Manifest entry — no new dependency needed) is the established provenance-stamped
persistence idiom in this codebase and should be reused, not reinvented, for per-Benders-
iteration checkpoints.

**Primary recommendation:** Build `src/planning/subproblem.jl` (`build_planning_oracle` /
`solve_planning_oracle!`) exactly mirroring `src/admm/DsoOpt.jl`'s shape: reuse
`contribute!(pf, ctx, feeder; T)` + `contribute!(agg, ctx; T)` verbatim, build `p_import[t]`
free-sign (mirroring `DsoOpt`'s frontier, not `solve_welfare`'s default import-only bound, so a
Benders trial `z` can propose an export without spurious infeasibility), close `:Rp`/`:Rq`
exactly as `welfare_solve.jl` does, add `@variable(model, z[t=1:T] in Parameter(0.0))`, pin
`@constraint(model, pin[t=1:T], p_import[t] == z[t])`, and read `dual.(pin)` — all gated by the
existing `assert_solved!` choke point, now wrapped in a bounded escalating-retry loop that
inspects `termination_status`/`raw_status` after every caught failure.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| `p_import[t] == z[t]` pin + dual read | Optimization / API layer (`src/planning/subproblem.jl`, new) | — | This IS the seam; it is a JuMP model-building concern, not a Benders orchestration concern (Phase 11) or a database/storage concern. |
| `λ_j[t] → π_s` time-aggregation + sign doc | Optimization / API layer (same module or a sibling pure function) | Reporting (Phase 14 plots) | Pure post-solve numeric transform on an already-solved `ctx`; no new solve, no new tier. |
| Retry + checkpoint wrapper | Optimization / API layer (wraps `assert_solved!`, `src/core/status.jl` or a new `src/core/retry.jl`) | Persistence (checkpoint files under `data/`, gitignored — mirrors `src/experiments/store.jl`) | The retry decision itself is a solve-orchestration concern (API layer); the checkpoint FILE write is a thin persistence concern reusing the existing DrWatson/JLD2 idiom, not a new storage subsystem. |
| Solver selection (`select_optimizer`) | Optimization / API layer (`src/solver/factory.jl`, UNMODIFIED) | — | Already established (INFRA-02); Phase 10 must not add a second solver-naming path. |
| `contribute!` (power-flow + aggregator terms) | Optimization / API layer (`src/powerflow/*`, `src/devices/Aggregator.jl`, UNMODIFIED) | — | Reused verbatim; Phase 10 owns zero device/power-flow logic. |

This project has no browser/CDN/frontend-server tiers — it is a single-process Julia research
framework, so every capability in this phase lives in the "API/Backend" analogue (the JuMP
model-building + solve-orchestration layer) with a thin persistence side-channel for checkpoints.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | 1.30.1 (installed, confirmed via `Pkg.status`) | `Parameter` variable, `dual()`, `@constraint` pin | Already the project's sole modeling layer (CLAUDE.md); `Parameter` is a JuMP 1.23+ feature, present and working at 1.30.1. |
| Clarabel | 0.11.1 (installed, confirmed via `Pkg.status`) | SOCP/QP backend for the new build-once oracle | Already the project's primary conic solver; **empirically confirmed** (this session) to accept `MOI.Parameter`-set variables directly, including alongside `SecondOrderCone` constraints, with no `ParametricOptInterface.jl` wrapper. |

No new runtime dependency is required for PLAN-01/02/03. `ParametricOptInterface.jl` is
**not needed** — Clarabel already accepts JuMP's native `Parameter` mechanism directly
`[VERIFIED: local Julia execution against this project's Project.toml/Manifest.toml, JuMP 1.30.1 / Clarabel 0.11.1, 2026-07-22]`.

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| DrWatson | 2.19.1 (already a `[deps]` entry) | `@tagsave`/`safesave` for per-Benders-iteration checkpoints | Reuse the exact idiom `src/experiments/store.jl` already uses for per-run provenance — do not hand-roll a new serialization format. |
| JLD2 | resolved transitively via DrWatson's own `Manifest.toml` entry (not a direct project dep) | The actual file format `@tagsave` writes | Already resolvable in this environment (`deps.JLD2` present in `Manifest.toml` under DrWatson) — confirmed no new `[deps]` entry needed. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JuMP `Parameter` for `z[t]` | Plain `@variable` + `fix(z[t], v)`/`unfix` | `fix`/`unfix` is the pre-`Parameter` idiom; it works on any solver but is documented by CLAUDE.md/prior research as the workaround `Parameter` was specifically added to replace. Since `Parameter` is now confirmed to work on Clarabel, there is no remaining reason to use `fix`/`unfix` here. |
| DrWatson `@tagsave` checkpoint | Hand-rolled `Serialization.serialize`/custom JSON | `@tagsave` is free provenance (git commit, Julia version) matching the project's existing reproducibility discipline (INFRA-04); a hand-rolled format would have to reinvent that stamping. |
| Escalating Clarabel-attribute retry | Retry with a *different* solver (SCS) on `NUMERICAL_ERROR` | D-09/CLAUDE.md explicitly forbid an SCS fallback for the price-producing oracle solve — SCS's lower-accuracy duals would corrupt the very quantity (the coupling dual) this phase exists to produce correctly. |

**Installation:** No new packages. Confirm current pins:
```bash
julia --project=. -e 'using Pkg; Pkg.status(["JuMP","Clarabel"])'
```
Observed output this session: `JuMP v1.30.1`, `Clarabel v0.11.1` (both match `[compat]` exactly;
Pkg flagged both as having newer versions available upstream but did not resolve them — no
action needed, current pins are sufficient and match CLAUDE.md's stack).

## Package Legitimacy Audit

Not applicable — this phase adds **zero new packages** (`[deps]`/`[weakdeps]` in `Project.toml`
are unchanged). `Parameter` support was confirmed to already exist in the installed JuMP/Clarabel
pair; DrWatson/JLD2 are already resolved dependencies. Skipping the slopcheck/registry-audit
protocol is correct here per its own scope ("whenever this phase installs external packages") —
this phase installs none.

## Architecture Patterns

### System Architecture Diagram

```
Benders master (Phase 11, NOT built here)
        │  trial z[1..T] (per-scenario coupling-flow profile)
        ▼
┌───────────────────────────────────────────────────────────────────┐
│  src/planning/subproblem.jl  (THIS PHASE — new, build ONCE)       │
│                                                                     │
│  build_planning_oracle(feeder, pf, aggregators; λ₀, T)             │
│     ├─ contribute!(pf, ctx, feeder; T)        [VERBATIM reuse]    │
│     ├─ contribute!(agg, ctx; T)  per aggregator [VERBATIM reuse]   │
│     ├─ @variable p_import[1:T]  (free-sign, mirrors DsoOpt)        │
│     ├─ @variable q_import[1:T]  (free-sign, if reactive channel)   │
│     ├─ @variable z[1:T] in Parameter(0.0)      [NEW — the seam]   │
│     ├─ @constraint pin[t]: p_import[t] == z[t] [NEW — the seam]   │
│     ├─ close :Rp / :Rq  →  register :balance_p / :balance_q        │
│     └─ @objective Max welfare  (identical shape to solve_welfare)  │
│                                                                     │
│  solve_planning_oracle!(o, z_trial)   ── PER BENDERS ITERATION ────│
│     ├─ set_parameter_value.(o.z, z_trial)   [no rebuild]           │
│     ├─ retry-wrapped assert_solved!(model; dual=true) ─────┐       │
│     │     on NUMERICAL_ERROR: escalate Clarabel settings,  │       │
│     │     re-optimize!, bounded attempts, else RAISE LOUD  │◄──┐   │
│     ├─ π  = dual.(pin)             [length-T cut gradient] │   │   │
│     ├─ π_s = Σ_t Δt·π[t]           [duration-weighted]     │   │   │
│     └─ returns (; cost, π, π_s, dadp, ctx)                 │   │   │
└──────────────────────────────────────────────────────────────┼───┼─┘
                                                                 │   │
        checkpoint-per-Benders-iteration (JLD2 via @tagsave) ───┘   │
        (persists: iteration index, cuts so far, z trial, status) ──┘
        on process restart: scan checkpoint dir, resume from
        last COMPLETE iteration, redo only the CURRENT iteration
```

Reading order for the pin's dual: `p_import` is the SAME variable role `welfare_solve.jl`/
`DsoOpt.jl` already use to close the frontier `:Rp` residual; `z` is a parallel, independent
`Parameter` that never itself enters `:Rp` — the pin constraint `p_import[t] == z[t]` is the
ONLY place the two interact. This is a deliberate structural choice (D-11) and differs from an
earlier, simpler design considered during milestone-level research (fusing `z` directly into the
residual in place of `p_import`) — **do not use the fused design**; the explicit pin is what
lets `z === nothing` (free path, Phase-4-identical) and `z !== nothing` (pinned path) share one
mental model without special-casing the residual assembly.

### Recommended Project Structure

```
src/planning/
├── subproblem.jl     # OracleProblem/PlanningOracle: build-once Parameter-z wrapper (THIS phase)
├── retry.jl           # (or extend src/core/status.jl) bounded escalating-retry wrapper (THIS phase)
└── checkpoint.jl       # per-Benders-iteration checkpoint save/resume via DrWatson @tagsave (THIS phase)
```
(`cuts.jl`, `master.jl`, `benders.jl`, `coupling.jl`, `diagnostics.jl`, `diagonalize.jl`,
`validation.jl` are Phase 11/13 concerns — do not create them in this phase.)

Wired into `src/TSODSO.jl` **after** `admm/` and **after** `models/oracle.jl` — append-only,
mirroring the existing comment-block convention (see `TSODSO.jl`'s own header comment for the
`admm/` block as the direct template: "Dependency order: … ORCHESTRATION over the already-
validated builders … NO Phase-N source file is modified").

### Pattern 1: Build-once `Parameter`-pinned subproblem (mirrors `DsoOpt.jl`)

**What:** One JuMP `Model` built once per (feeder, aggregators, λ₀) combination; each Benders
iteration only calls `set_parameter_value.(z, z_trial)` then re-`optimize!`s — no `@variable`/
`@constraint` calls inside the loop.
**When to use:** Any subproblem re-solved many times with only a numeric RHS/target changing —
exactly PLAN-01's coupling pin.
**Example (all lines individually verified in this session against JuMP 1.30.1 / Clarabel 0.11.1):**
```julia
# Source: verified locally (jump.dev/JuMP.jl/stable/manual/variables/ + empirical test, 2026-07-22)
using JuMP, Clarabel

model = Model(select_optimizer(problem_class(pf)))   # INFRA-02, never name a solver directly
ctx = ModelContext(model)
ctx.meta[:feeder] = feeder; ctx.meta[:T] = T

contribute!(pf, ctx, feeder; T = T)                  # verbatim, as DsoOpt.jl / solve_welfare do
for agg in aggregators
    contribute!(agg, ctx; T = T)                     # verbatim
end

@variable(model, p_import[t = 1:T])                  # FREE-SIGN, mirrors DsoOpt (not solve_welfare's default)
for t in 1:T
    add_to_residual!(ctx, :Rp, feeder.root, t, p_import[t])
end
ctx.meta[:p_import] = p_import

reactive = haskey(ctx.residuals, :Rq)
if reactive
    @variable(model, q_import[t = 1:T])              # FREE-SIGN reactive frontier
    for t in 1:T
        add_to_residual!(ctx, :Rq, feeder.root, t, q_import[t])
    end
    ctx.meta[:q_import] = q_import
end

@constraint(model, balance_p[j = 1:Np, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
register_constraint!(ctx, :balance_p, balance_p)
if reactive
    @constraint(model, balance_q[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
    register_constraint!(ctx, :balance_q, balance_q)
end

@variable(model, z[t = 1:T] in Parameter(0.0))        # the coupling-flow setpoint (D-01)
@constraint(model, pin[t = 1:T], p_import[t] == z[t]) # D-01/D-11: p_import PINNED to z

@objective(model, Max, ctx.meta[:objective] - sum(λ₀[t] * p_import[t] for t in 1:T))

# --- per-iteration re-solve (no rebuild) ---
set_parameter_value.(z, z_trial)                      # cheap; num_variables/constraints unchanged
assert_solved!(model; dual = true)                    # STRICT gate (never allow_almost on this path)
π = dual.(pin)                                        # length-T coupling dual (D-01)
```
`num_variables(model)` and `num_constraints(model, ...)` are confirmed (this session) to stay
identical across repeated `set_parameter_value` + `optimize!` calls — the build-once contract
holds `[VERIFIED: local test, JuMP 1.30.1]`.

### Pattern 2: Escalating-retry wrapper around `assert_solved!` (D-08/D-09)

**What:** Catch `assert_solved!`'s thrown `ErrorException`, branch on `termination_status`, and
only escalate Clarabel's numerical-conditioning attributes (never rebuild, never fall back to
SCS) for `NUMERICAL_ERROR`-class failures; re-raise immediately (no retry) for anything else
(e.g. genuine `INFEASIBLE`).
**When to use:** Every `solve_planning_oracle!` call inside the (future) Benders loop.
**Example (verified this session — the caught model retains a fully queryable status):**
```julia
# Source: verified locally against src/core/status.jl's assert_solved! (2026-07-22)
using JuMP

const RETRYABLE_STATUSES = (MOI.NUMERICAL_ERROR, MOI.SLOW_PROGRESS, MOI.ALMOST_OPTIMAL)

function solve_with_retry!(model; max_attempts::Int = 4, dual::Bool = true)
    ladder = [
        Dict(),                                                     # attempt 1: as-built
        Dict("static_regularization_constant" => 1e-6),             # attempt 2: relax static reg
        Dict("static_regularization_constant" => 1e-6,
             "iterative_refinement_max_iter" => 100,
             "equilibrate_max_iter" => 50),                         # attempt 3: + refine/equilibrate
        Dict("static_regularization_constant" => 1e-5,
             "dynamic_regularization_eps" => 1e-11,
             "iterative_refinement_max_iter" => 200),                # attempt 4: last resort
    ]
    for (attempt, settings) in enumerate(ladder[1:min(max_attempts, length(ladder))])
        for (k, v) in settings
            set_optimizer_attribute(model, k, v)      # post-build attribute change; no rebuild
        end
        try
            return assert_solved!(model; dual = dual)
        catch e
            e isa ErrorException || rethrow()
            ts = termination_status(model)
            if ts in RETRYABLE_STATUSES && attempt < max_attempts
                @warn "solve_with_retry!: attempt $attempt failed ($ts); escalating conditioning" raw = raw_status(model)
                continue
            end
            # non-retryable status, OR budget exhausted: RAISE LOUDLY with full diagnostics (D-10)
            error("""
                  solve_with_retry!: exhausted $attempt attempt(s) — refusing to trust results:
                    termination_status : $(ts)
                    primal_status      : $(primal_status(model))
                    dual_status        : $(dual_status(model))
                    raw_status         : $(raw_status(model))
                  """)
        end
    end
end
```
`termination_status(model)`/`raw_status(model)` remain valid inside the `catch` block after
`assert_solved!` throws — confirmed with a forced-infeasible HiGHS model this session
`[VERIFIED: local test, 2026-07-22]`. Clarabel's actual installed default `Settings()` (this
session, `Clarabel.Settings()` field introspection) confirms the attribute names above exist and
have the defaults: `static_regularization_constant = 1.0e-8`, `dynamic_regularization_eps =
1.0e-13`, `dynamic_regularization_delta = 2.0e-7`, `iterative_refinement_max_iter = 10`,
`equilibrate_max_iter = 10`, `equilibrate_min_scaling = 1.0e-4`, `equilibrate_max_scaling =
1.0e4`, `max_iter = 200`, `tol_gap_abs = tol_gap_rel = 1.0e-8` (the project's `select_optimizer(::SOCP())`
already tightens the last two explicitly). **Do not guess these names** — they were read
directly off the installed `Clarabel.jl` 0.11.1 `Settings` struct, not from training-data recall.

### Pattern 3: Checkpoint per Benders iteration (D-10) — reuse `@tagsave`, not a new format

**What:** After each Benders iteration completes (all scenarios solved, cut generated), persist
enough state to resume without redoing prior iterations.
**When to use:** Wraps the (Phase-11) outer Benders loop; Phase 10 only needs to deliver the
save/resume primitive and prove it round-trips.
**Example (mirrors `src/experiments/store.jl`'s already-established idiom):**
```julia
# Source: pattern read directly from src/experiments/store.jl (2026-07-22)
using DrWatson: @tagsave, datadir

function checkpoint_iteration!(state, iter::Int; dir = datadir("planning_checkpoints"))
    mkpath(dir)
    path = joinpath(dir, "iter_$(lpad(iter, 5, '0')).jld2")
    @tagsave(path, Dict(:iteration => iter, :state => state); safe = false)  # one file per iter — no _1/_2 needed
    return path
end

function resume_from_checkpoint(dir = datadir("planning_checkpoints"))
    files = sort(filter(f -> endswith(f, ".jld2"), readdir(dir; join = true)))
    isempty(files) && return nothing
    last = load(files[end])                          # JLD2.load, resolved via DrWatson
    return (; iteration = last["iteration"], state = last["state"])
end
```
Per D-10: on resume, the CURRENT (highest-numbered, possibly incomplete) iteration is redone in
full; only STRICTLY LOWER-numbered checkpoint files are treated as complete/skippable. Write the
checkpoint file only AFTER an iteration's cut is fully validated — a partially-written file
should never exist (write to a temp path + `mv`, or rely on `@tagsave`'s own atomic-ish write, if
that guarantee matters for the eventual Phase-11/12 hardening; Phase 10 only needs the primitive
proven, not stress-tested — that is explicitly Phase 12's job per ROADMAP.md).

### Anti-Patterns to Avoid

- **Fusing `z` directly into the `:Rp` residual in place of `p_import`** (an earlier,
  milestone-level research sketch, superseded by CONTEXT.md D-11): loses the explicit pin
  constraint whose DUAL is the deliverable, and complicates keeping the `z === nothing` free
  path and `z !== nothing` pinned path structurally analogous.
- **Modeling `z` as a `Float64`-coefficient like ADMM's `λ_j`**: ADMM avoids `Parameter` for
  `λ_j` specifically because `λ_j · pag` would be an indefinite bilinear term in a `Min`
  objective — that risk does NOT apply here: `z` enters only through the LINEAR pin constraint
  `p_import[t] == z[t]`, never multiplied by another decision variable, so `Parameter` is safe
  (confirmed empirically to solve cleanly through Clarabel, including inside an SOCP).
- **Retrying on `INFEASIBLE`, `INFEASIBLE_OR_UNBOUNDED`, or `DUAL_INFEASIBLE`**: these are not
  numerical-conditioning artifacts; retrying wastes the budget and can mask a genuine modeling
  bug (e.g. a Benders trial `z` truly infeasible for the network). Only retry on
  `NUMERICAL_ERROR`/`SLOW_PROGRESS`/`ALMOST_OPTIMAL`-class statuses.
- **Falling back to SCS on `NUMERICAL_ERROR`**: explicitly forbidden by D-09/CLAUDE.md — SCS's
  first-order duals are not trustworthy enough for the coupling-dual product this oracle exists
  to deliver.
- **Reading `dual(pin)` and assuming it already equals the "intuitive" `∂(welfare)/∂z` without a
  toy-case check**: empirically false under a `Max`-sense objective (see Common Pitfalls below).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Re-solving a model with a changed target value | A custom "rebuild the model each time" loop | JuMP `Parameter` + `set_parameter_value` | Confirmed cheap (no `@variable`/`@constraint` re-issued) and confirmed compatible with Clarabel this session; the project's own `DsoOpt.jl` already proves the build-once discipline for the sibling ADMM subproblem. |
| Detecting a "trustworthy" solve | A custom re-implementation of status checking | `assert_solved!` (`src/core/status.jl`, UNMODIFIED) | Already the project's single INFRA-03 choke point; the retry wrapper must WRAP it, not duplicate its logic. |
| Persisting intermediate run state | A hand-rolled JSON/CSV checkpoint format | DrWatson `@tagsave` (JLD2) | Already the established provenance-stamped persistence idiom (`src/experiments/store.jl`); reusing it keeps git-commit/Julia-version stamping "for free" and consistent across the whole project. |
| Solver-conditioning tuning | Guessed/hallucinated Clarabel attribute names | The introspected `Clarabel.Settings()` field list (this document) | Training-data recall of solver option names is exactly the kind of claim that must be verified, not assumed — this session verified them against the installed 0.11.1 struct directly. |

**Key insight:** almost nothing in this phase is genuinely new machinery — it is disciplined
reuse of `DsoOpt.jl`'s build-once shape, `status.jl`'s solve gate, and `store.jl`'s persistence
idiom, wired together around one new, empirically-verified JuMP idiom (`Parameter` on Clarabel).
The temptation to hand-roll comes from uncertainty about whether `Parameter` "really" works on
this solver — that uncertainty is now resolved.

## Common Pitfalls

### Pitfall 1: Assuming raw `dual(pin)` already equals `∂(welfare)/∂z` under `solve_welfare`'s `Max` objective

**What goes wrong:** D-06's docstring math (`π[t] := dual(pin[t]) = ∂(welfare optimum)/∂z[t]`)
reads as a definitional equivalence. Taken literally and coded without a toy-case check, a
downstream Benders cut (Phase 11) could be built with exactly the WRONG sign.
**Why it happens:** JuMP's `dual()` sign convention is documented as **independent of objective
sense** and instead depends on the constraint's direction (`<=`/`>=`/`==`) — this is
counter-intuitive relative to "textbook" shadow-price reasoning, where the sign flips between
Min and Max. `shadow_price()` exists specifically to give the textbook-signed version; `dual()`
does not.
**How to avoid:** This session built and ran a small, hand-computable toy case
(concave quadratic utility `U(x) = -0.5(x-2)^2`, balance `x - p_import = 0`, pin
`p_import == z`, `@objective(model, Max, U(x) - 1·p_import)`) at `z ∈ {0, 1, 2}` and measured:
`dual(pin)` = `{-1.0, ≈0.0, +1.0}` while the hand-derived `∂(objective)/∂z = -z+1` = `{+1.0,
0.0, -1.0}` — **exactly negated** at every point `[VERIFIED: local Julia execution, 2026-07-22]`.
Do not assume this sign generalizes without re-deriving it against `solve_planning_oracle!`'s
ACTUAL objective shape (welfare `Max`, concave utilities, possibly the SOCP cone active) — reuse
this toy-case PATTERN (a tiny feeder + one aggregator + a known-analytic optimum, mirroring
`test/fixtures_phase6.jl`'s existing "dual-sign anchor" 2-bus fixture) as the Success-Criterion-2
regression, not this document's specific numeric toy (which uses no network at all).
**Warning signs:** A Benders cut (Phase 11) that makes the master's investment decision move
the WRONG direction relative to the trial `z`'s marginal cost; a toy-case test that "passes" only
because it checks `isfinite(π)` rather than the actual signed value against a hand-derived
number.

### Pitfall 2: Believing JuMP's `Parameter` manual page that Clarabel is unsupported

**What goes wrong:** Defaulting to `ParametricOptInterface.jl` (a NEW dependency) or to the
`fix`/`unfix` workaround because the manual only names Ipopt as a working example.
**Why it happens:** The JuMP manual's `Parameter` page genuinely does not list Clarabel among
its example solvers, and does state a general caveat about "solvers that support MOI.Parameter."
**How to avoid:** This session verified DIRECTLY (three separate scripts: a QP-only model, an
SOCP model with a `SecondOrderCone` constraint, and a Max-sense welfare-shaped toy) that Clarabel
0.11.1 accepts `Parameter`-set variables with no wrapper and re-solves correctly after
`set_parameter_value` — `num_variables`/`num_constraints` unchanged across re-solves, and
`dual()` on a constraint referencing the parameter returns a finite, consistent value across
value changes. Trust the empirical result over the manual's generic caveat for THIS solver/JuMP
version pair; if `Clarabel.jl` or `JuMP.jl` is ever upgraded, re-run this session's verification
scripts (or an equivalent smoke test) before assuming the behavior still holds.
**Warning signs:** A `MethodError`/`MOI.UnsupportedConstraint` at `optimize!` time — did not occur
in this session's tests, but if it recurs after a version bump, treat it as a genuine
`Manifest.toml` regression to investigate, not an expected/documented limitation.

### Pitfall 3: Retrying `NUMERICAL_ERROR` without inspecting `termination_status` first

**What goes wrong:** A retry wrapper that catches ANY exception from `assert_solved!` and blindly
retries burns the attempt budget on genuinely infeasible trial points (e.g. a Benders master
proposing a `z` the network truly cannot serve), masking a real modeling/master-side bug as
"just another flake."
**Why it happens:** `assert_solved!` throws a plain `error(...)` (a generic `ErrorException`),
not a typed exception carrying the status — the retry wrapper must re-query the model.
**How to avoid:** Confirmed this session that `termination_status(model)` and `raw_status(model)`
remain fully valid and queryable inside a `catch` block after `assert_solved!` throws
`[VERIFIED: local test against a forced-infeasible HiGHS model, 2026-07-22]` — branch the retry
decision on `termination_status(model) in (MOI.NUMERICAL_ERROR, MOI.SLOW_PROGRESS,
MOI.ALMOST_OPTIMAL)`; anything else (`INFEASIBLE`, `DUAL_INFEASIBLE`, `INFEASIBLE_OR_UNBOUNDED`)
should re-raise immediately, no retry.
**Warning signs:** Retry-budget exhaustion messages that, on inspection, show
`termination_status == INFEASIBLE` on every attempt (the perturbation ladder cannot fix a
genuinely infeasible point — only conditioning issues).

### Pitfall 4: Measuring the retry-budget `N` and perturbation magnitudes without empirical data (Claude's Discretion item, CONTEXT.md)

**What goes wrong:** Picking `N` (attempt budget) or the ladder's magnitudes (e.g.
`static_regularization_constant` jump size) by intuition/analogy to unrelated projects, rather
than by actually measuring the failure rate on THIS project's planning-layer fixtures.
**Why it happens:** It is tempting to treat this as "just retry a few times" boilerplate.
**How to avoid:** CONTEXT.md is explicit this is Claude's Discretion but that it must be
empirically measured, "don't assume v1's rate holds." A concrete, cheap measurement protocol:
reuse `Phase4Fixtures.build_ieee13_ground_aggregators`/`ieee13_modified` (already in
`test/fixtures_phase4.jl`), sweep a plausible Benders trial range of `z` (e.g. `±20%` around the
feeder's natural unconstrained frontier import, since D-09/Pitfall-5-in-prior-research
specifically flags that PINNING pushes trial points toward the SOC-exactness/conditioning edge
more than an unconstrained solve does), and count how many of, say, 50–100 pinned solves hit
`NUMERICAL_ERROR` at attempt 1 vs. after each ladder rung. Use that empirical count (not a
guess) to size `N` and to decide whether 3 or 4 escalation rungs suffice.
**Warning signs:** A retry budget picked before any oracle code exists; a ladder whose rungs were
never actually observed to fix a real captured failure.

## Code Examples

### Reading the Clarabel installed settings directly (do this before hard-coding attribute names)

```julia
# Source: verified locally, Clarabel.jl 0.11.1 installed in this project's environment, 2026-07-22
using Clarabel
s = Clarabel.Settings()
for f in fieldnames(typeof(s))
    println(f, " = ", getfield(s, f))
end
```
Relevant fields and their DEFAULTS (subset, verified this session):
`static_regularization_enable = true`, `static_regularization_constant = 1.0e-8`,
`dynamic_regularization_enable = true`, `dynamic_regularization_eps = 1.0e-13`,
`dynamic_regularization_delta = 2.0e-7`, `iterative_refinement_enable = true`,
`iterative_refinement_max_iter = 10`, `iterative_refinement_reltol = 1.0e-13`,
`iterative_refinement_abstol = 1.0e-12`, `equilibrate_enable = true`,
`equilibrate_max_iter = 10`, `equilibrate_min_scaling = 1.0e-4`,
`equilibrate_max_scaling = 1.0e4`, `max_iter = 200`, `tol_gap_abs = tol_gap_rel = 1.0e-8`
(the project's `select_optimizer(::SOCP())` already sets the last two explicitly to `1e-8`).

### Confirming `Parameter` works inside an SOCP (this session's actual test, condensed)

```julia
# Source: verified locally, JuMP 1.30.1 / Clarabel 0.11.1, 2026-07-22
using JuMP, Clarabel
model = Model(Clarabel.Optimizer); set_silent(model)
@variable(model, z in Parameter(1.0))
@variable(model, p_import >= -10)
@variable(model, t0 >= 0); @variable(model, u); @variable(model, v)
@constraint(model, pin, p_import == z)
@constraint(model, cone, [t0, u, v] in SecondOrderCone())
@constraint(model, bal, u - p_import == 0)
@objective(model, Min, t0 + 0.1 * v^2)
for zval in (1.0, 2.0, 0.5)
    set_parameter_value(z, zval)
    optimize!(model)
    @assert termination_status(model) == MOI.OPTIMAL
end
```
Result: `OPTIMAL` at every `z` value, `dual(pin)` finite and consistent
`[VERIFIED: local test, 2026-07-22]`.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `_coupling_dual` throws `ArgumentError` on any non-`nothing` `z` (Phase 4/9 behavior) | `build_planning_oracle`/`solve_planning_oracle!` in a NEW `src/planning/subproblem.jl` handles the pinned path; `oracle.jl`'s throw stays as the FREE-path guard (D-03) | This phase | Planning callers get a genuine pinned coupling dual instead of a loud failure; `operational_oracle`'s existing behavior and ~2000 existing tests are untouched. |
| Milestone-level research sketch: fuse `z` into `:Rp` in place of `p_import` | CONTEXT.md D-11: keep `p_import` as its own variable, add an explicit `pin[t]: p_import[t] == z[t]` | Discuss-phase (CONTEXT.md, this phase) | Cleaner shared structure between the free (`z === nothing`) and pinned (`z !== nothing`) paths; the pin's dual is unambiguously the deliverable, not conflated with the frontier balance dual. |

**Deprecated/outdated:** The `ParametricOptInterface.jl`-required reading of JuMP's `Parameter`
docs, for THIS solver/version pair — empirically superseded by direct verification this session.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The empirically-observed dual-sign-flip pattern (raw `dual(pin)` = `-∂(objective)/∂z` under `Max`) generalizes to the actual welfare-shaped SOCP model with a live power-flow cone, not just the tiny toy tested this session | Common Pitfalls #1, Code Examples | If the generalization is wrong (e.g. the SOCP cone or the reactive coupling introduces an extra sign flip), Phase 10's own toy-case regression (Success Criterion 2) must catch it — it does not, by itself, certify the FULL model's sign; that is explicitly Phase 11's BilevelJuMP job per D-06. |
| A2 | The Clarabel-`Parameter` compatibility holds at the CURRENT pinned versions (JuMP 1.30.1 / Clarabel 0.11.1) and may not survive a future upgrade unverified | Standard Stack, Pitfall 2 | A version bump could silently break `build_planning_oracle` at `optimize!` time; re-run the verification scripts in this document as a smoke test after any `Manifest.toml` update touching JuMP/Clarabel. |
| A3 | A single retry-ladder shape (4 rungs, the specific attribute names/magnitudes shown) is a reasonable STARTING point, not yet validated against the planning layer's own empirical failure rate | Pattern 2, Pitfall 4 | CONTEXT.md explicitly leaves this to measurement; shipping the example ladder unmeasured risks either a budget too small (fails loud too often) or too large (masks a genuine modeling bug behind many wasted retries). |

**None of the JuMP/Clarabel API claims above are `[ASSUMED]`** — every mechanical claim about
`Parameter`, `dual()`, `set_optimizer_attribute`, and `assert_solved!`'s post-catch queryability
was independently reproduced against this project's actual pinned environment this session, not
sourced from training-data recall alone.

## Open Questions

1. **Should `p_import`/`q_import` in the new oracle be free-sign (mirroring `DsoOpt.jl`) or
   import-only (mirroring `solve_welfare`'s DEFAULT, `allow_export = false`)?**
   - What we know: `DsoOpt.jl` (the explicit structural template per D-11) uses free-sign
     `p_import`/`q_import` unconditionally. `solve_welfare` defaults to import-only unless
     `allow_export = true` is passed.
   - What's unclear: whether every Phase-11 Benders trial `z` will always be non-negative
     (import-only) or could plausibly go negative (export) — if the latter, an import-only
     `p_import >= 0` would make the pin `p_import[t] == z[t]` INFEASIBLE for a negative trial
     `z[t]`, not merely suboptimal.
   - Recommendation: default to free-sign (the `DsoOpt.jl`/`allow_export = true` shape) so the
     pin can never be structurally infeasible for a negative trial `z`; this is the safer
     default and matches the explicitly-named structural template.

2. **Exact retry-ladder magnitudes and attempt budget `N` (Claude's Discretion, CONTEXT.md).**
   - What we know: the Clarabel attribute names and their defaults (this document); the
     mechanism for escalating them without a rebuild.
   - What's unclear: the actual empirical failure rate on PINNED planning-layer solves — v1's
     rate is explicitly not a reliable estimate (STATE.md, PITFALLS.md Pitfall 5).
   - Recommendation: run the measurement protocol in Pitfall 4 during implementation (or as an
     explicit plan task) before finalizing `N` and the ladder's magnitudes; treat the example
     ladder in this document as a reasonable starting point only.

3. **Checkpoint file granularity vs. "per Benders iteration" wording (D-10).**
   - What we know: D-10 says checkpoint granularity is "per Benders iteration (all scenarios for
     an iterate)"; Phase 10 has no scenarios or Benders loop yet (that's Phase 11).
   - What's unclear: exactly what Phase 10's own deliverable should checkpoint, given there is no
     real Benders loop to checkpoint yet.
   - Recommendation: Phase 10 should deliver and test the SAVE/RESUME PRIMITIVE
     (`checkpoint_iteration!`/`resume_from_checkpoint` or equivalent) against a synthetic
     "iteration" (e.g. a sequence of `solve_planning_oracle!` calls at different trial `z`
     values), proving round-trip correctness; Phase 11 is where it gets wired into the real
     Benders loop's iteration boundary.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | All of Phase 10 | ✓ | 1.12.5 (confirmed via `julia --version`; project floor is 1.10 LTS per CLAUDE.md/`Project.toml`) | — |
| JuMP | `Parameter`, `dual`, `@constraint` | ✓ | 1.30.1 (matches `[compat]`) | — |
| Clarabel | SOCP/QP backend, `Settings()` attributes | ✓ | 0.11.1 (matches `[compat]`) | — |
| DrWatson | Checkpoint persistence (`@tagsave`) | ✓ | 2.19.1 (already a `[deps]` entry) | — |
| JLD2 (via DrWatson) | Checkpoint file format | ✓ (resolved transitively, confirmed in `Manifest.toml`) | resolved by DrWatson's own compat | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none — every dependency this phase needs is already
installed and pinned; no new `[deps]` entry is required.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `TestItemRunner.jl` (`@testitem`/`@testmodule`, `@run_package_tests` in `test/runtests.jl`) |
| Config file | none dedicated — `test/runtests.jl` is the entrypoint; `Project.toml`/`test/Project.toml` (if present) pin test deps |
| Quick run command | `julia --project=. -e 'using TestItemRunner; TestItemRunner.runtests(filter=ti->occursin("oracle", ti.name) \|\| occursin("planning", ti.name))'` (mirrors the existing `occursin("dso", ti.name)`/`occursin("oracle", ti.name)` tag convention used by `test_dso.jl`/`test_oracle.jl`) |
| Full suite command | `julia --project=. -e 'using Pkg; Pkg.test()'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PLAN-01 | `build_planning_oracle`/`solve_planning_oracle!` wire `p_import[t]==z[t]` and return `dual.(pin)`; `operational_oracle`/`solve_welfare` byte-identical | unit + regression | `julia --project=. -e '...filter=ti->occursin("planning", ti.name)'` PLUS the existing full `test_oracle.jl`/`test_welfare.jl`(-equivalent) suite unchanged | ❌ Wave 0 — new `test/test_planning_oracle.jl` needed |
| PLAN-02 | `λ_j[t] → π_s` time-aggregation (`π_s = Σ_t Δt·π[t]`) matches a hand-computed toy case; sign documented (raw dual, D-06) | unit (fast, permanent regression per CONTEXT.md Specifics) | same filter, a dedicated `@testitem "planning: coupling-dual sign/scale toy case (PLAN-02)"` | ❌ Wave 0 |
| PLAN-03 | Bounded retry survives an injected/observed `NUMERICAL_ERROR`; checkpoint round-trips (save → simulate crash → resume → correct skip of completed iterations) | unit + integration | same filter, `@testitem "planning: retry survives injected NUMERICAL_ERROR"` / `"planning: checkpoint round-trips"` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** the tag-filtered quick run (`occursin("planning", ...)` or similar,
  matching the project's existing `occursin("dso"/"oracle", ...)` convention).
- **Per wave merge:** full `Pkg.test()`.
- **Phase gate:** full suite green before `/gsd:verify-work`, PLUS the pre-existing
  `test_oracle.jl`/`solve_welfare`-consuming suite must remain byte-identical (regression proof
  that D-03/D-11's "unmodified" constraint actually held).

### Wave 0 Gaps

- [ ] `test/test_planning_oracle.jl` — new file, PLAN-01 coverage (pin wiring, dual read,
      free-path `z === nothing` parity with existing `operational_oracle` behavior).
- [ ] A coupling-dual sign/scale toy-case test (PLAN-02) — reuse the "dual-sign anchor" PATTERN
      from `test/fixtures_phase6.jl`'s 2-bus fixture (near-lossless, uncongested, analytically
      known DADP), not a bare unit-free numeric toy.
- [ ] A retry/checkpoint test module — needs a way to FORCE (not just hope for) a
      `NUMERICAL_ERROR` deterministically for the retry test (e.g. an artificially
      ill-conditioned tiny model, or mocking `optimize!`'s status) since the real flake is
      intermittent and version-independent, not reliably reproducible on demand.
- [ ] Framework install: none — `TestItemRunner`/`Test` already wired project-wide.

## Security Domain

Not applicable in the ASVS sense — this is a single-process research framework with no network
input, authentication, or session boundary. The project's own "security" concerns (per
`.planning/research/PITFALLS.md`'s Security Mistakes table) are reproducibility/provenance
integrity, already covered above (checkpoint provenance via `@tagsave`'s git-commit stamping,
never silently substituting a stale `π` on retry — D-10's "raise loudly, never silent-corrupt").

| ASVS Category | Applies | Standard Control |
|---------------|---------|-------------------|
| V2 Authentication | no | n/a — no network-facing surface |
| V3 Session Management | no | n/a |
| V4 Access Control | no | n/a |
| V5 Input Validation | yes (as fail-loud guards, not web input validation) | `ArgumentError` guards mirroring `solve_welfare`/`build_dso_opt`'s existing boundary checks (empty aggregators, `λ₀`/`z` length mismatch, aggregator bus range) |
| V6 Cryptography | no | n/a |

### Known Threat Patterns for this stack

| Pattern | STRIDE-analogue | Standard Mitigation |
|---------|------------------|----------------------|
| Silently substituting a stale/last-good `π` on a caught `NUMERICAL_ERROR` without flagging it | Tampering (with research provenance) | D-10: raise loudly on budget exhaustion; log every retry attempt (status + attempt number) so a downstream cut-validity check can flag it — never a silent fallback value. |
| A partially-written checkpoint file read back as "complete" after a crash mid-write | Tampering / Repudiation of the run's own history | Only mark an iteration checkpoint complete after its cut/result is fully validated; prefer write-then-rename or rely on `@tagsave`'s own write discipline; treat the highest-numbered checkpoint as ALWAYS-redo, never trust-on-resume (D-10). |

## Sources

### Primary (HIGH confidence)
- `src/models/oracle.jl`, `src/models/welfare_solve.jl`, `src/admm/DsoOpt.jl`,
  `src/core/status.jl`, `src/core/ModelContext.jl`, `src/solver/factory.jl`,
  `src/powerflow/AbstractPowerFlow.jl`, `src/experiments/store.jl`, `src/TSODSO.jl`,
  `test/test_oracle.jl`, `test/test_dso.jl`, `test/fixtures_phase4.jl`, `test/fixtures_phase6.jl`
  — all read directly, current repo state, 2026-07-22.
- Local Julia execution against this project's own `Project.toml`/`Manifest.toml` (JuMP 1.30.1,
  Clarabel 0.11.1, Julia 1.12.5) — six independent verification scripts run this session
  covering: `Parameter` + `dual()` under `Min`; `Parameter` + `dual()` under `Max` (sign check);
  `Parameter` inside a `SecondOrderCone`; `set_optimizer_attribute` post-build with
  `num_variables` invariance; `Clarabel.Settings()` field introspection;
  `termination_status`/`raw_status` queryability after a caught `assert_solved!`-style throw.
- `.planning/phases/10-oracle-coupling-wiring-resilience/10-CONTEXT.md` — the locked D-01..D-11
  decisions this research implements, not re-opens.
- `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` §Phase 10, `.planning/STATE.md` — scope,
  success criteria, and the carried `NUMERICAL_ERROR` blocker.

### Secondary (MEDIUM confidence)
- `jump.dev/JuMP.jl/stable/manual/variables/` (fetched 2026-07-22) — `Parameter`
  declaration/API surface; its Clarabel-support claim was found INCOMPLETE and superseded by
  this session's direct verification (see Pitfall 2).
- `jump.dev/JuMP.jl` duality-convention documentation (fetched 2026-07-22) — the
  objective-sense-independence of `dual()`'s sign convention, cross-checked against this
  session's own numeric toy (agreement confirmed).
- `.planning/research/SUMMARY.md`, `.planning/research/ARCHITECTURE.md`,
  `.planning/research/PITFALLS.md` (milestone-level v2.0 research, same session date) — prior
  architectural sketch and pitfall catalogue; ARCHITECTURE.md's specific fused-`z` code sketch is
  explicitly SUPERSEDED by CONTEXT.md's D-11 pin-constraint design (flagged above, not silently
  followed).

### Tertiary (LOW confidence)
- Clarabel.jl's own online docs (`clarabel.org`) were referenced only for cross-checking field
  names already confirmed by direct introspection of the installed `Clarabel.Settings()` struct
  — the introspection result is the higher-confidence source and is what this document reports.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new dependency; both core libraries' relevant behaviors verified
  empirically against the installed environment, not assumed from training data or docs alone.
- Architecture: HIGH on the build-once/pin-constraint shape (directly read from `DsoOpt.jl` and
  CONTEXT.md's locked D-11); MEDIUM on the exact free-sign-vs-import-only choice for the new
  oracle's `p_import` (flagged as Open Question 1, a genuine unresolved design point, not a
  confidence gap in what was researched).
- Pitfalls: HIGH on the dual-sign and Clarabel-Parameter-compatibility findings (both directly
  reproduced this session); MEDIUM on the retry-ladder tuning specifics (explicitly deferred to
  empirical measurement, per CONTEXT.md's own instruction).

**Research date:** 2026-07-22
**Valid until:** ~30 days, OR immediately upon any `JuMP`/`Clarabel`/`DrWatson` version bump in
`Manifest.toml` (re-run this document's verification scripts as a smoke test first).

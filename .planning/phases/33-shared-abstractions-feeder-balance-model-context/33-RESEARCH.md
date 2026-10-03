# Phase 33: Shared Abstractions — Feeder, Balance, Model Context - Research

**Researched:** 2026-10-03
**Domain:** Julia/JuMP internal refactor (type hierarchy, helper extraction, struct typing); no new packages
**Confidence:** HIGH (all findings are codebase-grep verified or measured in a Julia 1.12.5 REPL this session)

## Summary

This is a pure-refactor phase. Three findings change the plan shape versus what CONTEXT.md assumes.
(1) There are ZERO `isa Feeder` / `isa MeshedFeeder` runtime branches in `src/` today, and only ONE
function annotated `::Feeder` (`solve_toy_dc`, `src/models/toy_dc.jl:41`). Every consumer takes an
untyped `feeder`, so ARCH-03 is "add the supertype, then ADD typing + the invalid-pair methods", not
"replace branches". The invalid formulation x feeder pairs do not fail today at all — they silently
build a model (notably `RestrictedBranchFlow` on a `MeshedFeeder` silently uses a BFS spanning tree).
(2) `ACPowerFlow` stashes `:l`, so `haskey(pf_vars, :l)` is TRUE for it and `assert_socp_exact!` already
runs on AC contexts (it only reads `l, P, Q, v`). The has-branch-current trait must be true for
ConvexBranchFlow, RestrictedBranchFlow, MeshedFlow AND ACPowerFlow to stay bit-identical. A single
trait is sufficient (all five `haskey(:l)` sites mean the same thing).
(3) `DCPowerFlow` never writes `ctx.meta[:pf_vars]` at all, and `LinDistFlow` writes `(; v, P, Q)` with no
`:l`; the typed `pf_vars` field therefore needs a `nothing` state, and `has_reactive(pf)` ==
`haskey(ctx.residuals, :Rq)` holds for every formulation when evaluated right after `contribute!`.

The balance blocks are textually identical except for index letter (`t`/`τ`), horizon name, a
`"scenario $s "` error prefix in the stochastic extensive builder, `reactive` provenance, and
named-vs-anonymous container. No code reads `model[:balance_p]`/`model[:balance_q]` (verified), and an
anonymous container with `base_name = "balance_p"` produces the identical container type and identical
MOI constraint names (measured), so solver-visible order and bit-identity are preserved.

**Primary recommendation:** Execute in 5 plans / 4 waves: (W1) `AbstractFeeder` + trait scaffolding +
include-order fix; (W2) `close_balance!` migration of the 5 sites; (W3) typed `ModelContext` fields added
ADDITIVELY then call-site migration in 3 file batches (src core/formulations, src consumers, test+docs+
scripts) with a final grep gate; (W4) certification. Keep the package compiling between plans by making
the typed fields and the old `meta` keys coexist ONLY until the last migration batch removes the old keys.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
(Copied from CONTEXT.md `## Implementation Decisions`.)

**AbstractFeeder Supertype (ARCH-03)**
- `abstract type AbstractFeeder{T<:Real} end`; `Feeder{T} <: AbstractFeeder{T}` and
  `MeshedFeeder{T} <: AbstractFeeder{T}`. Shared contract = the fields `buses`, `branches`, `root`,
  documented on the supertype; no accessor functions. Construction-is-the-gate validation in each
  concrete struct is unchanged.
- Shared entry points (`solve_welfare`, builders, `contribute!`) are typed `feeder::AbstractFeeder`;
  radial-only code paths (ADMM, LinDistFlow, radial exactness) dispatch on `::Feeder`; meshed-only on
  `::MeshedFeeder`. Any `feeder isa MeshedFeeder`/`isa Feeder` runtime branches are replaced by methods.
- Invalid formulation x feeder pairs (e.g. a radial-only formulation on a `MeshedFeeder`) get an
  explicit method throwing `ArgumentError` naming the pair, not a bare `MethodError`.

**close_balance! Helper (ARCH-04)**
- `close_balance!(ctx, N, T; reactive::Bool) -> (balance_p, balance_q_or_nothing)`: performs the
  `:Rp` (and, if `reactive`, `:Rq`) size check with the EXISTING error text, builds the
  `Rp[j,t] == 0` / `Rq[j,t] == 0` constraints, registers `:balance_p` / `:balance_q`. Frontier
  `p_import`/`q_import` creation and DsoOpt's transit-node zero injections stay in callers.
- Uses ANONYMOUS constraint containers (`base_name = "balance_p"` / `"balance_q"`) registered only in
  `ctx.constraints` — no model-level name, so multiple scenario contexts on one shared model (stochastic)
  cannot collide. Planning must confirm no code reads `model[:balance_p]` / `model[:balance_q]`.
  Naming does not change the math -> goldens unaffected.
- `reactive` is decided by a formulation trait `has_reactive(pf)` (false for `DCPowerFlow`) passed by
  callers, replacing `haskey(ctx.residuals, :Rq)`; DsoOpt passes `true`. Bit-identity must be
  checked at every site where the trait and the old residual check could disagree.
- Scope: exactly the five ARCH-04 sites — `welfare_solve`, `mpc_window`, `stochastic_welfare` (both
  the extensive-form builder and the OOS harness), `DsoOpt`, `linear_solve`. Planning-layer copies are
  NOT migrated (recorded as deferred).

**Typed ModelContext (ARCH-07)**
- `ModelContext` gains typed fields for the fixed metadata: `feeder::Union{Nothing,AbstractFeeder}`,
  `T::Int`, `pf::Union{Nothing,AbstractPowerFlow}` (the formulation), `pf_vars` (the formulation's
  NamedTuple), `objective::QuadExpr`, `device_vars` (today's `:agg_device_vars`). `meta` remains for
  experiment/result-specific keys (`p_import`, `q_import`, `socp_maxgap`, `price_provenance`,
  `qag_dso`, `problem_class`, ...).
- Hard migration of all call sites this phase (internal API, no compat shim). Grep gate: zero
  remaining `meta[:pf_vars]`, `meta[:T]`, `meta[:feeder]`, `meta[:objective]`, `meta[:agg_device_vars]`
  in `src/` and `test/`.
- `haskey(pf_vars, :l)` gates are replaced by a formulation-type trait (e.g. `has_branch_current(pf)`)
  whose truth table reproduces TODAY's behaviour exactly per formulation (ACPowerFlow included —
  research confirms each); where a site actually means "SOCP-exactness applies", a separate trait is
  used. No behaviour change.
- `pf_vars` stays a per-formulation NamedTuple (concrete per formulation), held in a parametric or
  `Union` field — no new per-formulation structs.

### Claude's Discretion
- Whether `ModelContext` becomes parametric (`ModelContext{F,V}`) or uses `Union`/abstract fields,
  provided JET/type-stability does not regress and incremental construction (`ModelContext(model)`
  then `contribute!` filling fields) still works.
- Exact trait names.

### Deferred Ideas (OUT OF SCOPE)
- Migrating planning-layer balance-closing copies (subproblem/master/feasibility_oracle/bilevel_kkt/nash)
  to `close_balance!`.
- Typing the result-specific `meta` keys (`p_import`, `socp_maxgap`, ...).
- Accessor-function interface for feeders.

Out of scope (CONTEXT `<domain>`): `solve_admm` decomposition / formulation-generic ADMM / meshed reactive
(ARCH-05/06, Phase 34); status/exception policy (ARCH-08/09, Phase 34).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ARCH-03 | `Feeder` and `MeshedFeeder` share an `AbstractFeeder` supertype; consumers dispatch on it | Section "Feeder inventory": no isa-branches exist; 1 typed function; valid/invalid pair table; include order is already safe (data/ loads first) |
| ARCH-04 | One `close_balance!` helper replaces five copied balance-closing blocks | Section "Balance blocks": diff table, anonymous-container measurement, `has_reactive` truth table, error-text prefix kwarg |
| ARCH-07 | `ModelContext` typed fixed metadata; dispatch on formulation type instead of `haskey(pf_vars,:l)` | Sections "meta inventory", "`:l` truth table", "ModelContext design"; include-order hazard (AbstractPowerFlow must load before ModelContext) |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Stack is Julia + JuMP; models never hard-code a solver (factory only). Goldens must stay reproducible.
- Documentation is a hard requirement: every new type/function needs a docstring, and `docs/src/api.md`
  uses `@autodocs` by `Pages = [...]` file list with `checkdocs = :exports` (a new FILE must be added to
  the Pages list; a new exported symbol without a docstring fails the docs build).
- Clean, idiomatic, well-organized Julia; clarity and traceability over premature performance.
- GSD workflow: all edits go through a GSD command (this phase is executed via `/gsd-execute-phase`).
- Memory notes to honour: targeted tests use
  `JULIA_LOAD_PATH="@:.:test:@stdlib" julia --project=. -e 'using TestItemRunner; TestItemRunner.run_tests(joinpath(pwd(),"test"); filter = ti -> endswith(ti.filename, "test_<name>.jl"))'`;
  never put TestItemRunner commands in a plan `<verify>` (they fail under `--project=.`; use direct Test.jl
  scripts with `JULIA_LOAD_PATH="test:.:@stdlib"`); `try x = ...` / for-loop reassignment of outer vars
  inside `@testitem` is a soft-scope trap (wrap in a function / `let`); the full suite must be launched
  DETACHED by the orchestrator (orphan race); the 2 known-false Aqua failures (CairoMakie stale-deps +
  Makie persistent-tasks) appear only on the drifted main checkout — never commit `Project.toml`/`Manifest`
  drift; do not raise exactness thresholds (`atol_b` hybrid floor).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Feeder type hierarchy | Data model (`src/data/`) | — | Loaded first; `AbstractFeeder` must precede `Feeder`/`MeshedFeeder` and `ModelContext` |
| Formulation capability traits (`has_reactive`, `has_branch_current`) | Power-flow seam (`src/powerflow/`) | Core (`ModelContext` typed `pf` field) | Capabilities belong to the formulation type; consumers query the trait |
| `close_balance!` | Core (`src/core/`, next to `ModelContext`) | Models/admm callers | Operates only on a `ModelContext`; no formulation/feeder knowledge |
| Typed context metadata | Core (`ModelContext`) | all builders (writers), exactness/pricing/experiments (readers) | Single owner of the fixed metadata; `meta` shrinks to result-specific keys |
| Invalid-pair `ArgumentError` | Power-flow seam (`contribute!` methods) | ADMM entry points | Dispatch on `(pf, feeder)` types at the earliest point |

## Standard Stack

No new packages. Everything is `JuMP 1.30.x` (already in Manifest), Julia stdlib, and existing test tooling
(`TestItems`/`TestItemRunner`, `Aqua`, `Documenter`). `[VERIFIED: codebase + Julia 1.12.5 REPL]`

### Package Legitimacy Audit
No external packages are installed in this phase. Slopcheck not applicable. Packages removed: none. Flagged: none.

## Architecture Patterns

### Data/control flow (what changes)

```
Feeder / MeshedFeeder <: AbstractFeeder{T}            (src/data, loads FIRST)
            |
solve_welfare / solve_linear / build_mpc_window / build_stochastic_* / build_dso_opt ...
   feeder::AbstractFeeder (shared)   feeder::Feeder (radial-only: ADMM)
            |
 ctx = ModelContext(model);  ctx.feeder = feeder;  ctx.T = T
            |
 contribute!(pf, ctx, feeder; T)  --> writes ctx.residuals[:Rp,(:Rq)], ctx.pf_vars = (;...), ctx.pf = pf
            |
 reactive = has_reactive(pf)       (trait, replaces haskey(ctx.residuals,:Rq))
            |
 aggregators/devices -> add_to_residual!, add_to_objective!(ctx.objective), ctx.device_vars
            |
 frontier p_import/q_import (callers)  -->  close_balance!(ctx, N, T; reactive) -> (balance_p, balance_q|nothing)
            |
 @objective(model, Max, ctx.objective - ...)  --> solve --> if has_branch_current(ctx.pf): assert_socp_exact!(ctx)
```

### Recommended file layout
```
src/data/AbstractFeeder.jl   NEW (or put the abstract type at top of Feeder.jl; if a new file, add to docs api.md Pages)
src/core/balance.jl          NEW  close_balance!  (add to api.md "Core" Pages)
src/core/ModelContext.jl     typed struct
src/powerflow/AbstractPowerFlow.jl   + has_reactive / has_branch_current docs + defaults (MOVE its include above ModelContext)
```

### Include-order hazard (verified, `src/TSODSO.jl:19-60`)
`core/ModelContext.jl` is included at line 50, BEFORE `powerflow/AbstractPowerFlow.jl`. Typed fields
`pf::Union{Nothing,AbstractPowerFlow}` need the abstract type first. `AbstractPowerFlow.jl` contains only
`abstract type AbstractPowerFlow end` and `function contribute! end` (no dependency on `ModelContext`), so
move its `include` line above `core/ModelContext.jl`. `AbstractFeeder` is safe: `data/Feeder.jl` already
loads before core. `close_balance!` must load after `register_constraint!` (same file or after it).

### Pattern: close_balance! (verified syntax)
```julia
# Verified in Julia 1.12.5 + JuMP (this session): identical container type, identical MOI names,
# no object_dictionary entry for the anonymous form.
function close_balance!(ctx::ModelContext, N::Int, T::Int; reactive::Bool, label::AbstractString = "")
    model = ctx.model
    size(ctx.residuals[:Rp]) == (N, T) || error(
        "$(label)residual :Rp is $(size(ctx.residuals[:Rp])), expected ($N, $T) — an index escaped the feeder")
    bp = @constraint(model, [j = 1:N, t = 1:T], ctx.residuals[:Rp][j, t] == 0, base_name = "balance_p")
    register_constraint!(ctx, :balance_p, bp)
    bq = nothing
    if reactive
        size(ctx.residuals[:Rq]) == (N, T) || error("$(label)residual :Rq is ... — an index escaped the feeder")
        bq = @constraint(model, [j = 1:N, t = 1:T], ctx.residuals[:Rq][j, t] == 0, base_name = "balance_q")
        register_constraint!(ctx, :balance_q, bq)
    end
    return bp, bq
end
```
Order of operations is identical to the current blocks (Rp size check -> Rp constraints -> register ->
Rq size check -> Rq constraints -> register), so JuMP/MOI constraint creation order is unchanged.

### Anti-Patterns to Avoid
- **Parametric `ModelContext{PV}`:** impossible with incremental construction (`ModelContext(model)` then
  `contribute!` fills `pf_vars`); a type parameter cannot change after construction. Use a `Union` field.
- **Setting `ctx.pf` in `contribute!` of a delegating formulation BEFORE the delegate runs:**
  `RestrictedBranchFlow` and `MeshedFlow` call `contribute!(ConvexBranchFlow(), ...)` first, which would
  set `ctx.pf = ConvexBranchFlow()`. Assign `ctx.pf = pf` at the END of each concrete method (after
  delegation), or have the delegates call an internal `_contribute_convex!` that does not set `pf`.
- **Reading `ctx.T`/`ctx.feeder` when unset:** previously a `KeyError`; now `0`/`nothing`. See Pitfall 3.

## 1. Feeder inventory (ARCH-03)

| Fact | Evidence |
|------|----------|
| `isa Feeder`/`isa MeshedFeeder` runtime branches | NONE. `grep "isa (Feeder|MeshedFeeder)" src` = 0 hits |
| `::Feeder` / `::MeshedFeeder` annotations | ONLY `solve_toy_dc(feeder::Feeder)` `src/models/toy_dc.jl:41` |
| `MeshedFeeder` mentions outside `data/` | ONLY `src/TSODSO.jl:28` (include). `MeshedFlow` takes an untyped `feeder` |
| Struct fields typed by feeder | `PlanningOracle{Z,PC,PI,F}.feeder::F` (`planning/subproblem.jl:59,67`), `FeasibilityOracle...F` (`feasibility_oracle.jl:56,65`), `DsoOpt{P,Q,PI,F}` (`admm/DsoOpt.jl:85,93`), `MpcWindow{F}` (`mpc_window.jl:63,68`), `StochasticOosHarness{F}` (`stochastic_welfare.jl:552,556`) — all unconstrained `F`; constrain to `F<:AbstractFeeder` |
| Duck-typed fake feeders in tests/src | NONE (grep for `(; buses` / `buses = ..., branches` = 0). Typing entry points `::AbstractFeeder` cannot break a caller |
| Generic helper with untyped feeder | `assert_magnitudes(feeder)` `units/PerUnit.jl:110`; `_load_buses`, `_path_branches(feeder, j)` `pricing/dlmp.jl:199`, `_fit_ac_settlement_violations`, `_mpc_*` — leave untyped or type `AbstractFeeder` |

**Entry points to type `feeder::AbstractFeeder`** (all currently untyped, signature lines): `solve_welfare`
(`models/welfare_solve.jl:108`), `solve_linear` (`linear_solve.jl:53`), `build_mpc_window` (`mpc_window.jl:130`),
`build_stochastic_welfare` (`stochastic_welfare.jl:163`), `build_stochastic_oos_harness` (`:614`),
`build_planning_oracle` (`planning/subproblem.jl:116`), `build_feasibility_oracle` (`feasibility_oracle.jl:93`),
`make_relaxed_oracle_model`/`alpha_op_lb_derivation`/`derive_alpha_op_lb` (`planning/master.jl`),
`build_bilevel_kkt`, `fit_baseline`, `operational_oracle` (`models/oracle.jl:23`), all `contribute!` methods.
**Radial-only (`::Feeder`):** `solve_admm` (`admm/solve_admm.jl:240`), `build_dso_opt` (`admm/DsoOpt.jl:275`).

### Formulation x feeder validity (what each does on a MeshedFeeder TODAY)

All `contribute!` bodies read only `feeder.buses/branches/root` and are graph-generic, so none fails today.

| Formulation | Radial `Feeder` | `MeshedFeeder` today | Recommended |
|-------------|-----------------|----------------------|-------------|
| `DCPowerFlow` | valid | builds (inflow-outflow per bus; physically fine) | valid `[ASSUMED]` |
| `LinDistFlow` | valid | builds, but derivation is radial | `ArgumentError` `[ASSUMED - confirm]` |
| `ConvexBranchFlow` | valid | builds (no exactness guarantee on loops) | `ArgumentError` for direct use; `MeshedFlow` must call an internal shared body, not the public method |
| `RestrictedBranchFlow` | valid | SILENTLY WRONG: BFS spanning tree (`powerflow/RestrictedBranchFlow.jl:235-258`) | `ArgumentError` (certain) |
| `ACPowerFlow` | valid | builds; `ac_oracle` BFS recovery is tree-based | `[ASSUMED]` valid or error — open question |
| `MeshedFlow` | valid (Feeder is a connected special case) | valid (its purpose) | valid on `AbstractFeeder` |

Because `MeshedFlow.contribute!` currently delegates to the PUBLIC `contribute!(ConvexBranchFlow(), ...)`
(`powerflow/MeshedFlow.jl:79-80`) and `RestrictedBranchFlow` likewise (`:210-211`), refactor the Convex body
into an internal function typed `AbstractFeeder` (e.g. `_contribute_convex!`) so the public
`::Feeder`-only / `::MeshedFeeder`-throws split does not break `MeshedFlow`. `RestrictedBranchFlow` stashes
`:formulation = :RestrictedBranchFlow` (`:317`) and `MeshedFlow` stashes `:MeshedFlow` (`MeshedFlow.jl:81`);
keep those `meta` keys (result provenance, read via `get(ctx.meta, :formulation, :unknown)`).

Stale comment found: `models/exactness.jl:~230` says the gate "never" runs for `MeshedFlow` because it
never stashes `:l`. That is wrong: `MeshedFlow` delegates to `ConvexBranchFlow`, which stashes `:l`, so
`solve_welfare(MeshedFlow)` DOES run `assert_socp_exact!` (confirmed by `test/test_mesh_flow.jl` "assert_socp_exact!
both pass"). Fix the comment while touching that file.

## 2. The five balance-closing blocks (ARCH-04)

| Site | Lines | Loop idx / horizon | Reactive source | Error prefix | Container | Local used afterwards |
|------|-------|--------------------|-----------------|--------------|-----------|-----------------------|
| `solve_welfare` | `welfare_solve.jl:237-252` | `t`,`T` (`Np`) | `reactive = haskey(ctx.residuals,:Rq)` captured right after `contribute!(pf)` (`:179`) | none | NAMED | YES `dual.(balance_p[priced,:])` (`:297`) |
| `build_mpc_window` | `mpc_window.jl:~208-221` | `τ`,`H` (`N`) | same, captured `:189` | none | NAMED | no (reads `ctx.constraints`) |
| `build_stochastic_welfare` | `stochastic_welfare.jl:348-365` | `t`,`T` | `reactive_s` captured `:313` | `"scenario $s "` | ANONYMOUS already | no (`ctxs[s].constraints`, `:466`) |
| `build_stochastic_oos_harness` | `stochastic_welfare.jl:681-696` | `t`,`T` (`N`) | captured `:652` | none | NAMED (single build) | no |
| `build_dso_opt` | `DsoOpt.jl:463-475` | `t`,`T` (`N`) | UNCONDITIONAL (both closed) | none | NAMED | no |
| `solve_linear` | `linear_solve.jl:~120-146` | `t`,`T` (`Np`) | `haskey(ctx.residuals,:Rq)` evaluated AFTER devices (`:129`), has the WR-03 invariant comment | none | NAMED | YES `dual.(balance_p[priced,:])` (`:159`) |

Differences the helper must absorb: (a) the `"scenario $s "` error prefix -> `label` kwarg (preserve the
EXISTING text; the other four use the bare text `"residual :Rp is $(size), expected ($N, $T) — an index
escaped the feeder"`); (b) welfare_solve and linear_solve bind the local `balance_p` -> bind from the returned
tuple `balance_p, balance_q = close_balance!(...)`; (c) DsoOpt passes `reactive = true`; (d) mpc index name `τ`
is cosmetic (Matrix axes are plain `1:H`).

**Name-reader audit (verified):** no code reads `model[:balance_p]`/`model[:balance_q]` (grep
`\[:balance_[pq]\]` excluding `constraints[`/`meta[` = 0 hits); the only `object_dictionary`/`unregister`
users are `planning/nash.jl:1487-1490` (diff of names created by `contribute!`, not by balance closing) and
`stochastic_welfare.jl:307` (explicit list of 12 formulation names, none are balance names); the one
`object_dictionary` test is `test/test_powerflow.jl:100` (`:vdrop`). Other (non-migrated) copies exist and
keep named containers: `planning/{subproblem,feasibility_oracle,master,bilevel_kkt,nash}.jl`,
`pricing/fit.jl:506,570`, `experiments/mpc_loop.jl:1367,1600`, and test fixtures
(`test/fixtures_phase19.jl:343`, `fixtures_planning_ieee13_short.jl:207`, two `test_planning_certification_*`).
These are untouched by anonymous containers (different models).

**Bit-identity (measured):** `@constraint(m, balance_p[j=1:3,t=1:2], ...)` vs
`@constraint(m, [j=1:3,t=1:2], ..., base_name="balance_p")` -> both `Matrix{ConstraintRef{...}}`, both name
`balance_p[2,1]`, anonymous form not in `object_dictionary`, calling twice on one model does not collide. The
MOI index order follows macro iteration order (column-major over `(j,t)`) in both forms. The knife-edge ADMM
canary (`iters=56`, `welfare=-4823.66604824162`) and the S=1 stochastic-vs-`solve_welfare` D-08 byte-identity
test are the existing detectors for any ordering drift.

### `has_reactive` truth table (does `contribute!` populate `:Rq` iff reactive?)

| Formulation | Writes `:Rq` in `contribute!` | `has_reactive` |
|-------------|-------------------------------|----------------|
| `DCPowerFlow` | NO (`powerflow/DCPowerFlow.jl:45-56`) | **false** |
| `LinDistFlow` | yes (`LinDistFlow.jl:94`) | true |
| `ConvexBranchFlow` | yes (`ConvexBranchFlow.jl:350`) | true |
| `RestrictedBranchFlow` | via delegation | true |
| `MeshedFlow` | via delegation | true |
| `ACPowerFlow` | yes (`ACPowerFlow.jl:274`) | true |

Aggregators ALWAYS write `:Rq` (`devices/Aggregator.jl:234`) even on DC, which is exactly why the callers
capture `reactive` BEFORE aggregators run (WR-03). Four of five sites already capture it pre-aggregator, so
`has_reactive(pf)` is identical. `solve_linear` evaluates AFTER devices, but its devices write only `:Rp`
(`linear_solve.jl:~95`), so the post-device `haskey` equals the pre-device value: no disagreement site
exists for `welfare_solve`, `mpc_window`, both stochastic sites, `linear_solve`. **No device writes `:Rq`
for DC in a way that matters** because DC `reactive=false` leaves it unclosed (pre-existing documented behaviour
that must be preserved: `welfare_solve.jl:171-176`). Not migrated and still using `haskey(ctx.residuals,:Rq)`:
planning copies, `pricing/fit.jl:547`, `experiments/mpc_loop.jl:1339,1572` — leave as is (they remain
correct); optionally switch fit/mpc_loop to the trait only if trivially equal.

Recommended trait definition: explicit per concrete formulation (6 one-liners; `MeshedFlow`/`Restricted`
included), documented on `AbstractPowerFlow`. A default of `true` on `AbstractPowerFlow` plus
`DCPowerFlow -> false` is acceptable (CONTEXT: "false for `DCPowerFlow`"); no fallback throwing is needed
since no third-party formulation exists (grep `<: AbstractPowerFlow` = the 6 concrete + none in tests).

## 3. `ctx.meta` inventory (ARCH-07)

Counts of the five keys (regex `meta[:K]` or `meta, :K`): **src 210, test 125, docs/literate 6, scripts 11.**
A textual grep gate over src/test must also catch docstring/comment mentions (many docstrings say
"`ctx.meta[:pf_vars]`") — update docs text, not only code. The gate regex must additionally cover the
non-bracket forms `haskey(x.meta, :K)`, `get(x.meta, :K, ...)`, `get!(x.meta, :K, ...)`: e.g.
`devices/Aggregator.jl:241` (`get!`), `pricing/checks.jl:123` (`get(ctx.meta, :feeder, nothing)`),
`models/{welfare_solve:368,mpc_window:231,stochastic_welfare:702,complementarity_4q:123}` (`haskey(...:agg_device_vars)`).

### src by key and file (writers marked W)
- **`:T`** — W: `welfare_solve:152`, `linear_solve:74`, `mpc_window:167` (`= H`), `stochastic_welfare:289,645`, `DsoOpt:387`,
  `AgrOpt:134` (the ONLY key AgrOpt sets besides objective/device_vars), `pricing/fit.jl:169,467,543`,
  `planning/{subproblem:155,feasibility_oracle:117,master:252,bilevel_kkt:382,nash:1471}`, `experiments/mpc_loop.jl:1336,1569` (`= 1`).
  Readers: `exactness.jl:179,304,368`, `ac_oracle.jl:68,178,309-311`, `restriction_exactness.jl:248`,
  `mesh_angle_certificate.jl:185`, `complementarity_4q.jl:25,120`, `welfare_solve.jl:302,363` (kwarg defaults),
  `pricing/{welfare:22,75, checks:24,74}` (kwarg defaults `T = ctx.meta[:T]`).
- **`:feeder`** — W: same builders as `:T` plus `toy_dc:44`. Readers: `exactness.jl:178,303,367`, `ac_oracle.jl:67,177,315`,
  `restriction_exactness.jl:247`, `mesh_angle_certificate.jl:184`, `oracle.jl:163`, `pricing/{welfare:92, dlmp:377}`,
  `pricing/checks.jl:123` (`get(..., nothing)` — the one tolerant reader; typed field default `nothing` keeps it).
- **`:objective`** — W: ONLY `ModelContext.add_to_objective!` (`:157`). Readers: objective assembly in
  `welfare_solve:254`, `linear_solve:150`, `mpc_window:274`, `stochastic_welfare:420,753`, `AgrOpt:157,239,319`,
  `planning/{subproblem:212,master:293,nash:1564,1599}`, `pricing/welfare:126`. Tests assert absence:
  `!haskey(ctx.meta,:objective)` in `test_pvbattery:203`, `test_fourquadbess:412`, `test_deferrable:97`,
  `test_device:46`, `test_thermostatic:207`; presence in `test_context:74`, `test_welfare_solve:263`.
- **`:pf_vars`** — W: `LinDistFlow:97 (v,P,Q)`, `ConvexBranchFlow:356 (v,v̂,P,Q,l)`, `ACPowerFlow:280 (v,P,Q,l)`;
  Restricted/Meshed via delegation; **`DCPowerFlow` NEVER writes it**. Readers: `exactness.jl:177,302,366`, `ac_oracle.jl:69,179,316-317`,
  `restriction_exactness.jl:246`, `mesh_angle_certificate.jl:186`, `RestrictedBranchFlow:213`, `ac_recheck.jl:139`,
  `pricing/fit.jl:580,581,638`, `experiments/mpc_loop.jl:698,865,1405,1607`.
- **`:agg_device_vars`** — W: only `Aggregator.jl:241` (`get!(ctx.meta, ..., Dict{Int,Vector{Any}}())`, created even for an
  aggregator with zero devices). Readers: `AgrOpt` (stash), `solve_admm:896`, `stochastic_welfare:374,378,702`,
  `mpc_window:231`, `welfare_solve:368,369`, `complementarity_4q:123,126`, `run_stochastic:190`, `mpc_loop:374,461,533,755`.
  Keep the field type `Dict{Int,Vector{Any}}` (same insertion/iteration behaviour -> identical bus iteration order).

### Construction order (incremental fill)
`ModelContext(model)` -> `feeder`,`T` set (builders) -> `contribute!(pf,...)` sets `pf_vars` (+ `pf` in the new design) ->
aggregators/devices fill `objective` + `device_vars` -> frontier/`close_balance!` -> result keys (`p_import`, `q_import`,
`socp_maxgap`, ...). `add_to_residual!` indexed variant deliberately uses NO feeder (docstring `ModelContext.jl:109`;
`test_context.jl:47-49` asserts a fresh ctx has no feeder). Contexts built WITHOUT a feeder: `AgrOpt` (`T`, objective,
device_vars only), bare device tests (`test_aggregator`, `test_fourquadbess`, `test_pvbattery`, `test_device`, ...).

### Key name collision
`linear_solve.jl:106` stores a DIFFERENT value under `ctx.meta[:device_vars]` (a `Vector{Any}` of per-device vars;
read by `test_linear_solve.jl:39`). A typed field also named `device_vars` (a `Dict{Int,Vector{Any}}`) would give one name
two meanings. **Recommendation:** name the typed field `agg_device_vars` (keeps today's name, zero ambiguity) or keep
CONTEXT's `device_vars` and rename linear_solve's key (changes `test_linear_solve.jl`). Planner picks; recommend
`agg_device_vars` and flag to the discuss step since CONTEXT wrote `device_vars`.

### `:objective` representation
`add_to_objective!` does `get(meta,:objective, zero(QuadExpr)) + expr`, i.e. new object, first add = `zero(QuadExpr) + expr`.
A typed `objective::QuadExpr` initialised `zero(QuadExpr)` makes the first add numerically identical. Tests that assert
"never touched" (`!haskey(ctx.meta,:objective)`) become `iszero(ctx.objective)`-style checks
(`isempty(ctx.objective.terms) && iszero(ctx.objective.aff)`) — verify the exact predicate in a REPL before planning it
(JuMP has `iszero(::GenericQuadExpr)` for zero polynomial; confirm). `value(zero(QuadExpr))` is the constant.

## 4. `:l` gate truth table (`haskey(pf_vars, :l)`)

| Formulation | `pf_vars` | has `:l` | Notes |
|-------------|-----------|----------|-------|
| `DCPowerFlow` | not written (absent) | false | `haskey(meta,:pf_vars)` false |
| `LinDistFlow` | `(; v, P, Q)` | false | |
| `ConvexBranchFlow` | `(; v, v̂, P, Q, l)` | **true** | |
| `RestrictedBranchFlow` | same (delegates) | **true** | |
| `MeshedFlow` | same (delegates) | **true** | gate DOES run (see stale-comment note) |
| `ACPowerFlow` | `(; v, P, Q, l)` | **true** | gate DOES run today: `assert_socp_exact!` reads only `l,P,Q,v` (`exactness.jl:~238-246`) |

Sites and meaning (all five mean "branch current exists => run/require the exactness certificate"):
`welfare_solve.jl:275` (run `assert_socp_exact!`, stash `:socp_maxgap`), `stochastic_welfare.jl:449` (same, per scenario),
`planning/subproblem.jl:352` (run gate with `on_inexact` policy), `pricing/dlmp.jl:112` (REFUSE pricing when `:l` present and
no `:socp_maxgap`), `pricing/fit.jl:522` (`has_cone`: choose AC re-solve path; `pf` is in scope there). `test/fixtures_phase19.jl:357`
is a test copy of the same gate. **One trait is enough** (`has_branch_current(pf)` = true for the four above, false for
DC/LinDistFlow); a separate "SOCP-exactness applies" trait would change behaviour for `ACPowerFlow` (today the gate runs on AC),
so do NOT split them. `has_branch_current(::Nothing) = false` so an unset `ctx.pf` behaves like today's absent `pf_vars`.

**Equivalence invariant to test** (cheap, catches any future drift): after `contribute!(pf, ctx, feeder; T=1)` on a 2-bus
feeder, for every formulation
`has_branch_current(pf) == (ctx.pf_vars !== nothing && haskey(ctx.pf_vars, :l))` and
`has_reactive(pf) == haskey(ctx.residuals, :Rq)`.

**Hand-built contexts need `ctx.pf` set:** `test/test_pricing_dlmp.jl:85-103` builds a ctx with
`pf_vars = (; l = x)` (SOCP-shaped, no `:socp_maxgap`) and a second with `(; P = x)`; under the trait design these must set
`ctx.pf = ConvexBranchFlow()` / `LinDistFlow()` (or `DCPowerFlow()`). Audit all 11 `ctx.meta[:pf_vars] = ` test writes
(`test_exactness` x5, `test_ac_oracle` x2, `test_pricing_dlmp` x2, others): only those that flow into a trait-gated consumer
(`extract_dlmp`/`_assert_priceable`) need `pf`; `assert_socp_exact!` itself does not use the trait.

## 5. ModelContext design

**Recommendation: concrete struct with `Union` fields (NOT parametric).** Parametric `ModelContext{PV}` cannot be filled
incrementally, would force every `::ModelContext` method/`Vector{ModelContext}` (e.g. `stochastic_welfare.jl:280`,
`nash.jl:1466`) to widen, and gains nothing because `pf_vars` is already read dynamically (today through
`Dict{Symbol,Any}`, so a `Union{Nothing,NamedTuple}` field is strictly more typed, never worse for JET). No JET test exists in
the repo (only Aqua: `test/test_toy_dc.jl:30`).

```julia
mutable struct ModelContext
    model::Model
    constraints::Dict{Symbol,Any}
    residuals::Dict{Symbol,Any}
    meta::Dict{Symbol,Any}
    feeder::Union{Nothing,AbstractFeeder}
    T::Int                                   # 0 = unset (see Pitfall 3)
    pf::Union{Nothing,AbstractPowerFlow}
    pf_vars::Union{Nothing,NamedTuple}
    objective::QuadExpr                      # zero(QuadExpr) until first add_to_objective!
    agg_device_vars::Dict{Int,Vector{Any}}
end
ModelContext(model::Model) = ModelContext(model, Dict{Symbol,Any}(), Dict{Symbol,Any}(), Dict{Symbol,Any}(),
    nothing, 0, nothing, nothing, zero(QuadExpr), Dict{Int,Vector{Any}}())
```
- Only constructor in the repo is `ModelContext(model)` (`ModelContext.jl:64`); no positional 4-arg call exists elsewhere
  (grep `ModelContext(model,` = 1 hit, the definition) — safe to change the field list.
- No `deepcopy`/`serialize`/`copy(ctx)` of a `ModelContext`, and no `keys(ctx.meta)`/`pairs(ctx.meta)` iteration anywhere in
  `src/`, `test/` (grep verified) — migration cannot break an iteration. `ctx.meta` is only indexed, `get`, `get!`, `haskey`.
- `store.jl:97-99` writes `:feeder => s.feeder`, `:T => s.T` into a result Dict (`Scenario`, Symbols) — unrelated to `ctx.meta`;
  do NOT touch.
- Docstring of `ModelContext` and `add_to_objective!` must be rewritten (they describe `meta[:objective]`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Anonymous named container | manual name mangling | `@constraint(m, [j=..,t=..], expr, base_name="balance_p")` | verified: identical type and MOI names |
| Frozen-fingerprint of constraint order | custom model diff | existing goldens (ADMM canary, S=1 D-08, 356 MPC assertions) + one new fingerprint testitem comparing `all_constraints` names order for a tiny `solve_welfare` model against a literal list | cheap bit-identity tripwire |

## Common Pitfalls

### Pitfall 1: `ctx.pf` overwritten by delegation
`RestrictedBranchFlow`/`MeshedFlow` delegate to `contribute!(ConvexBranchFlow(), ...)`. If `contribute!(Convex)` sets
`ctx.pf = pf` the stored value is the wrong type, `has_*` traits stay correct (both true) but provenance is wrong and any future
dispatch on the real formulation breaks. **Avoid:** set `ctx.pf = pf` last in every concrete method / use an internal body.
**Detect:** testitem asserting `typeof(ctx.pf) == typeof(pf)` for all six formulations.

### Pitfall 2: Typing `ConvexBranchFlow.contribute!` radial-only breaks `MeshedFlow` and `RestrictedBranchFlow`
They call the public method. **Avoid:** internal shared body (see section 1).

### Pitfall 3: Unset-state semantics change KeyError -> silent default
`ctx.T` default `0` and `ctx.feeder === nothing` replace a `KeyError`. Kwarg defaults `T = ctx.meta[:T]`
(`pricing/welfare.jl:75`, `checks.jl:74`, `welfare_solve.jl:302,363`, `complementarity_4q.jl:25,120`) would silently become `T=0`
on a hand-built ctx. **Avoid:** readers that need them go through a small checked accessor or assert `ctx.T > 0` /
`ctx.feeder !== nothing` with an `ArgumentError` naming the field; keep message loud. Tests setting `ctx.meta[:T] = 3` on bare ctxs
(`test_fourquadbess.jl:461-574`) migrate to `ctx.T = 3`.

### Pitfall 4: DC has no `pf_vars`
`ctx.pf_vars` is `nothing` for DC (and for fresh ctxs). Every former `haskey(ctx.meta,:pf_vars)` guard needs the `nothing` branch;
`test_ac_powerflow:62`, `test_convex_branch_flow:58`, `test_dso:42`, `test_planning_oracle:335` assert presence -> `!== nothing`.

### Pitfall 5: Include order
`AbstractPowerFlow.jl` must load before `core/ModelContext.jl` (see Architecture). Symptom: `UndefVarError: AbstractPowerFlow`
at precompile.

### Pitfall 6: docs/literate and scripts also read the keys
`docs/literate/{convex_branch_flow:183, prosumer_welfare:221, restricted_branch_flow:155, socp_applicability:93}.jl` and
`scripts/{socp_applicability_sweep, demo_mpc_plots, thesis_caseA}.jl` read `meta[:pf_vars]`/`[:agg_device_vars]`. The docs build
EXECUTES literate files, so an unmigrated one fails `docs/make.jl`; the CONTEXT grep gate only lists `src/` and `test/`. Extend the
gate to `docs/literate` and `scripts`. (`docs/src/generated/` is git-ignored — do not edit.)

### Pitfall 7: `checkdocs = :exports` and PVAL-04
New exported symbols (`AbstractFeeder`, `close_balance!`, `has_reactive`, `has_branch_current`) need docstrings AND their file in
the `@autodocs` `Pages` of `docs/src/api.md` (Network Data Model list line 45; Core list line 29; Power-Flow list). Adding a new
file without listing it reproduces the Phase 30/32 `checkdocs` failure. PVAL-04 (`test_planning_noninteger.jl:241`) only checks
exported `build_*` names: none are added, so no allowlist change is needed.

### Pitfall 8: Aqua ambiguities
Defining `contribute!(pf, ctx, ::MeshedFeeder)` throwing methods alongside `contribute!(pf, ctx, ::AbstractFeeder)` is
non-ambiguous (strictly more specific). Avoid defining both `(::SpecificPF, ::AbstractFeeder)` and `(::AbstractPowerFlow, ::MeshedFeeder)`
— that pair is ambiguous on `(SpecificPF, MeshedFeeder)`. Use only per-formulation x feeder methods.

## Code Examples

### Trait definitions (place beside `contribute!` in `AbstractPowerFlow.jl`)
```julia
has_reactive(::AbstractPowerFlow) = true            # contribute! writes :Rq
has_reactive(::DCPowerFlow) = false                 # (defined in DCPowerFlow.jl)
has_branch_current(::AbstractPowerFlow) = false     # default: no :l
has_branch_current(::ConvexBranchFlow) = true
has_branch_current(::RestrictedBranchFlow) = true
has_branch_current(::MeshedFlow) = true
has_branch_current(::ACPowerFlow) = true            # gate runs on AC today (pf_vars carries :l)
has_branch_current(::Nothing) = false
```
(Concrete subtype files load after `AbstractPowerFlow.jl`; define each formulation's method in its own file.)

### Call-site rewrite (welfare_solve)
```julia
balance_p, balance_q = close_balance!(ctx, Np, T; reactive = has_reactive(pf))
...
if has_branch_current(ctx.pf)
    ctx.meta[:socp_maxgap] = assert_socp_exact!(ctx; rtol = rtol_exact)
end
```

## Runtime State Inventory

Not a rename/migration of persisted state — in-memory refactor. Stored data: none (ModelContext is never serialized; verified no
`serialize`/`JLD2` of a ctx — JLD2 is used only for planning checkpoints, which store numeric iterates). Live service config: none.
OS-registered state: none. Secrets/env vars: none. Build artifacts: none. Cached results: DrWatson/`store.jl` result Dicts use their own
`:feeder`/`:T` Symbol keys (not `ctx.meta`) — unchanged, no migration.

## State of the Art
Not applicable (internal refactor). JuMP anonymous containers with `base_name` are standard JuMP API `[VERIFIED: Julia 1.12.5 REPL this session]`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `DCPowerFlow` is a VALID pair with `MeshedFeeder` | Feeder inventory | If user wants DC radial-only, add one more throwing method |
| A2 | `LinDistFlow` x `MeshedFeeder` should throw `ArgumentError` | same | If a meshed LinDistFlow experiment is desired, remove the method; no test uses it today |
| A3 | `ACPowerFlow` x `MeshedFeeder` validity left open | same | Either choice is non-breaking today (no test/fixture uses it) |
| A4 | Name the typed field `agg_device_vars` rather than `device_vars` (collision with `linear_solve`'s `meta[:device_vars]`) | meta inventory | Cosmetic; CONTEXT said `device_vars` — needs user/discuss confirmation |
| A5 | `ctx.T` unset sentinel `0` (CONTEXT says `T::Int`) | ModelContext design | Alternative `Union{Nothing,Int}` is safer but widens kwarg defaults |
| A6 | `iszero`/term-emptiness predicate for "objective untouched" on `QuadExpr` | meta inventory | Verify in REPL during planning; trivial to swap |

## Open Questions (RESOLVED)

1. **Which pairs throw?** Certain: `RestrictedBranchFlow` x `MeshedFeeder` (silent BFS spanning tree). Recommended: `ConvexBranchFlow` direct and
   `LinDistFlow` x `MeshedFeeder`. Left to the planner/user: `DCPowerFlow`, `ACPowerFlow`. Recommendation: throw only for the three above. RESOLVED (user, 2026-10-03): throw for RestrictedBranchFlow, ConvexBranchFlow (direct), LinDistFlow on MeshedFeeder; DC/AC/MeshedFlow allowed.
2. **Unlisted balance copies in src**: `pricing/fit.jl:506,570` and `experiments/mpc_loop.jl:1367,1600` are copies of the same block but not among
   the five ARCH-04 sites. Recommendation: leave (CONTEXT scope), record as deferred alongside the planning copies. RESOLVED: left out of scope, deferred.
3. **Field name `device_vars` vs `agg_device_vars`** (A4). RESOLVED: `agg_device_vars`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | yes | 1.12.5 | — |
| JuMP / project env | tests | yes | per Manifest | — |
| Documenter (docs env) | docs gate | yes (`docs/` env, last green at 03b91a5) | — | — |

No missing dependencies.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | TestItems 1.0 + TestItemRunner 1.1 (`@testitem`), Aqua quality gate in `test/test_toy_dc.jl` |
| Config file | `test/runtests.jl`, `test/Project.toml` |
| Quick run command (per file) | `JULIA_LOAD_PATH="@:.:test:@stdlib" julia --project=. -e 'using TestItemRunner; TestItemRunner.run_tests(joinpath(pwd(),"test"); filter = ti -> endswith(ti.filename, "test_<name>.jl"))'` |
| Full suite command | detached full run owned by the ORCHESTRATOR (memory `background-suite-orphan-race`); baseline 31782 / 0 / 0 / 5 at 0e1b30a |
| Docs gate | `julia --project=docs docs/make.jl` (must exit 0; `checkdocs = :exports`) |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ARCH-03 | `Feeder <: AbstractFeeder`, `MeshedFeeder <: AbstractFeeder`; `AbstractFeeder{Float64}` parameterised; `Feeder`/`MeshedFeeder` constructors still gate (radial/connected) | unit | targeted: `test_feeder.jl`, `test_mesh_feeder.jl` (+ new assertions) | partial (extend existing) |
| ARCH-03 | invalid pairs throw `ArgumentError` naming the pair: `RestrictedBranchFlow`/`ConvexBranchFlow`/`LinDistFlow` x `MeshedFeeder`; `MeshedFlow` x `Feeder` and x `MeshedFeeder` still solve | unit | new `test_abstract_feeder.jl` (or extend `test_mesh_flow.jl`) | no, Wave 1 |
| ARCH-04 | `close_balance!` returns `(bp,bq)`; registers `ctx.constraints[:balance_p/_q]`; names `balance_p[j,t]`; no `model[:balance_p]`; two calls on one model with different ctxs do not collide; error text identical for `:Rp`/`:Rq` size mismatch incl. `label` prefix; `reactive=false` returns `nothing` and leaves `:Rq` unclosed | unit | new `test_close_balance.jl` | no, Wave 2 |
| ARCH-04 | trait/residual agreement: for all 6 formulations `has_reactive(pf) == haskey(ctx.residuals,:Rq)` right after `contribute!` | unit | new `test_model_context_traits.jl` | no, Wave 1 |
| ARCH-04 | bit-identity of the five sites | golden | existing: `test_welfare_solve`, `test_linear_solve`, `test_mpc_window`, `test_stochastic_welfare`, `test_stochastic_oos_harness`, `test_dso`, `test_admm_knifeedge_canary` (`iters=56`, `welfare=-4823.66604824162`), `test_admm` | yes |
| ARCH-07 | typed fields default/incremental fill (`ModelContext(model)` has `feeder===nothing`, `T==0`, `pf===nothing`, `pf_vars===nothing`, zero objective, empty device vars); `contribute!` fills `pf`/`pf_vars`; `typeof(ctx.pf)==typeof(pf)` for all 6 (delegation) | unit | extend `test_context.jl` + new traits file | partial |
| ARCH-07 | `has_branch_current(pf) == (pf_vars !== nothing && haskey(pf_vars,:l))` for all 6; AC TRUE | unit | new traits file | no, Wave 1 |
| ARCH-07 | grep gate: zero `meta[:pf_vars|:T|:feeder|:objective|:agg_device_vars]`, `haskey/get/get!(…meta, :K` in `src/ test/ docs/literate scripts` | source-scan testitem | new testitem reading files (precedent: `test_pricing_fit.jl:306` reads `src`) — exclude itself | no, Wave 3 final |
| ARCH-07 | pricing refusal unchanged: `extract_dlmp` refuses a `ConvexBranchFlow`-shaped ctx lacking `:socp_maxgap`, passes DC/LinDistFlow | unit | `test_pricing_dlmp.jl` (migrated hand-built ctx with `ctx.pf`) | yes (migrate) |
| all | docs build + `checkdocs` | gate | `julia --project=docs docs/make.jl` | yes |
| all | Aqua (ambiguities, undefined exports, stale deps) | quality | `test_toy_dc.jl` Aqua item (2 known-false failures on drifted main checkout only) | yes |

### Sampling Rate
- **Per task commit:** targeted test file(s) for the touched module (command above; run each in a direct Test.jl script for `<verify>` blocks).
- **Per wave merge:** the directly affected family (welfare/linear/mpc/stochastic/dso/admm/exactness/pricing/mesh/restricted).
- **Phase gate:** full detached suite >= 31782 passes, 0 fail, 0 error, 5 broken (plus any new tests); docs build exit 0; grep gates zero; `git worktree list` shows no stray agent worktree; `Project.toml`/`Manifest` untouched.

### Wave 0 Gaps
- [ ] `test/test_abstract_feeder.jl` — ARCH-03 subtype + invalid-pair `ArgumentError` + valid-pair solves
- [ ] `test/test_close_balance.jl` — ARCH-04 helper contract
- [ ] `test/test_model_context_traits.jl` — trait/residual/pf_vars/`ctx.pf` equivalence invariants (6 formulations)
- [ ] Constraint-order fingerprint testitem (literal MOI constraint-name order for a tiny `solve_welfare`) captured BEFORE migrating `close_balance!`, kept green after
- [ ] Grep-gate testitem (added in the LAST migration plan so intermediate plans compile)

## Security Domain

Local research code, no network/auth/untrusted input surface; ASVS categories V2/V3/V4/V6 not applicable. V5 (input validation) is
already handled by construction-is-the-gate inner constructors, which this phase preserves. Pre-existing loud-failure guards
(`ArgumentError` for invalid pairs, shape check in `close_balance!`) must not be weakened. Threat pattern relevant here is "silently wrong
model" (e.g. Restricted on a mesh) -> mitigated by the explicit invalid-pair methods.

## Recommended Wave / Plan Split (keeps package compiling between plans)

| Wave | Plan | Content | Compiles because |
|------|------|---------|------------------|
| 1 | 33-01 AbstractFeeder + traits | `AbstractFeeder{T}`; subtype both structs; move `AbstractPowerFlow.jl` include above `ModelContext.jl`; add `has_reactive`/`has_branch_current` (+ docs, api.md pages); constrain struct `F<:AbstractFeeder`; type shared entry points; internal `_contribute_convex!` + invalid-pair `ArgumentError` methods; tests `test_abstract_feeder`, traits invariants (the `ctx.pf` equivalence test is added in W3) | purely additive; no behaviour change for existing callers |
| 2 | 33-02 close_balance! | new `core/balance.jl` + test; migrate 5 sites (take `has_reactive(pf)`); fingerprint testitem green; stochastic extensive keeps `label="scenario $s "` | helper added then callers swapped one file at a time |
| 3 | 33-03 typed ModelContext, additive | add typed fields; `add_to_objective!` writes the field; `Aggregator` writes `agg_device_vars`; every `contribute!` sets `ctx.pf`/`ctx.pf_vars`; builders set `ctx.feeder`/`ctx.T`. Keep old `meta` writes mirrored TEMPORARILY (or provide read-through) so unmigrated readers still work | old and new coexist |
| 3 | 33-04 migrate readers/writers in src (2 batches by directory: models+powerflow+devices+admm; planning+pricing+experiments) | each batch compiles; `haskey(:l)` sites -> `has_branch_current` | uses typed fields only after 33-03 |
| 3 | 33-05 migrate test/, docs/literate, scripts; remove mirrored `meta` writes; add grep-gate testitem; update docstrings | last plan deletes the shims; gate proves zero remains |
| 4 | 33-06 certification | detached full suite, docs build, goldens, Aqua attribution; evolve VALIDATION.md | — |

Parallelism: 33-01 and 33-02 touch disjoint files except `welfare_solve.jl`/`mpc_window.jl` signatures (type annotation vs block body) —
serialise 33-02 after 33-01 to avoid merge conflicts. 33-04 batches are file-disjoint and may run in parallel. 33-05 must follow both.
(If the temporary-mirror shim feels like a "compat shim" against the CONTEXT "no compat shim" decision, the alternative is one atomic plan that
changes the struct and all 210 src sites at once — higher risk, not recommended; note the mirror lives only inside the phase and is removed in 33-05.)

## Sources

### Primary (HIGH confidence — codebase and REPL, this session)
- `src/core/ModelContext.jl`, `src/TSODSO.jl` (include order), `src/data/{Feeder,MeshedFeeder}.jl`, `src/powerflow/*.jl`
  (`contribute!` bodies, `pf_vars` stashes), `src/models/{welfare_solve,linear_solve,mpc_window,stochastic_welfare,exactness}.jl`,
  `src/admm/{DsoOpt,AgrOpt}.jl`, `src/devices/Aggregator.jl`, `src/pricing/{dlmp,fit}.jl`, `src/planning/{subproblem,nash}.jl`
- Test/docs inventories: `grep` over `src test docs/literate scripts`; `docs/src/api.md`; `test/test_planning_noninteger.jl:225-250`
- Julia 1.12.5 REPL: anonymous `@constraint(... base_name=...)` container type/name equivalence and no `object_dictionary` entry
- `.planning/phases/32-.../32-07-SUMMARY.md` (baseline, PVAL-04 and `checkdocs` gotchas); memory notes listed above

### Secondary / Tertiary
None used.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages.
- Architecture / inventories: HIGH — exhaustive grep with file:line; REPL-verified JuMP behaviour.
- Pitfalls: HIGH for include order, delegation, DC `pf_vars` absence, docs/scripts readers; MEDIUM for the invalid-pair policy (needs user confirmation: A1-A3).

**Research date:** 2026-10-03
**Valid until:** 2026-11-02 (stable; invalidate if Phase 34 lands first)

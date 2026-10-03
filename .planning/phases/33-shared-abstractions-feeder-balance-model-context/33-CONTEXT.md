# Phase 33: Shared Abstractions — Feeder, Balance, Model Context - Context

**Gathered:** 2026-10-03
**Status:** Ready for planning

<domain>
## Phase Boundary

Feeder types, balance-closing logic, and `ModelContext` metadata are unified and typed instead of
duplicated five times or carried in an untyped `Dict` (ARCH-03, ARCH-04, ARCH-07):

1. `Feeder` and `MeshedFeeder` share an `AbstractFeeder` supertype, and consumers dispatch on it.
2. One `close_balance!` helper replaces the five copied balance-closing blocks in `welfare_solve`,
   `mpc_window`, `stochastic_welfare`, `DsoOpt`, and `linear_solve`.
3. `ModelContext` carries typed fields for its fixed metadata (power-flow variables, objective,
   feeder, device variables); downstream code dispatches on the formulation type instead of
   `haskey(pf_vars, :l)`.

Pure refactor: every numeric golden must stay bit-identical (full suite baseline after Phase 32:
31782 passed / 0 failed / 0 errored / 5 broken at 0e1b30a).

OUT of scope: `solve_admm` decomposition / formulation-generic ADMM / meshed reactive (ARCH-05/06,
Phase 34); status/exception policy (ARCH-08/09, Phase 34); planning-layer balance-closing copies.

</domain>

<decisions>
## Implementation Decisions

### AbstractFeeder Supertype (ARCH-03)
- `abstract type AbstractFeeder{T<:Real} end`; `Feeder{T} <: AbstractFeeder{T}` and
  `MeshedFeeder{T} <: AbstractFeeder{T}`. Shared contract = the fields `buses`, `branches`, `root`,
  documented on the supertype; no accessor functions. Construction-is-the-gate validation in each
  concrete struct is unchanged.
- Shared entry points (`solve_welfare`, builders, `contribute!`) are typed `feeder::AbstractFeeder`;
  radial-only code paths (ADMM, LinDistFlow, radial exactness) dispatch on `::Feeder`; meshed-only on
  `::MeshedFeeder`. Any `feeder isa MeshedFeeder`/`isa Feeder` runtime branches are replaced by methods.
- Invalid formulation × feeder pairs (e.g. a radial-only formulation on a `MeshedFeeder`) get an
  explicit method throwing `ArgumentError` naming the pair, not a bare `MethodError`.

### close_balance! Helper (ARCH-04)
- `close_balance!(ctx, N, T; reactive::Bool) -> (balance_p, balance_q_or_nothing)`: performs the
  `:Rp` (and, if `reactive`, `:Rq`) size check with the EXISTING error text, builds the
  `Rp[j,t] == 0` / `Rq[j,t] == 0` constraints, registers `:balance_p` / `:balance_q`. Frontier
  `p_import`/`q_import` creation and DsoOpt's transit-node zero injections stay in callers.
- Uses ANONYMOUS constraint containers (`base_name = "balance_p"` / `"balance_q"`) registered only in
  `ctx.constraints` — no model-level name, so multiple scenario contexts on one shared model (stochastic)
  cannot collide. Planning must confirm no code reads `model[:balance_p]` / `model[:balance_q]`.
  Naming does not change the math → goldens unaffected.
- `reactive` is decided by a formulation trait `has_reactive(pf)` (false for `DCPowerFlow`) passed by
  callers, replacing `haskey(ctx.residuals, :Rq)`; DsoOpt passes `true`. Bit-identity must be
  checked at every site where the trait and the old residual check could disagree.
- Scope: exactly the five ARCH-04 sites — `welfare_solve`, `mpc_window`, `stochastic_welfare` (both
  the extensive-form builder and the OOS harness), `DsoOpt`, `linear_solve`. Planning-layer copies are
  NOT migrated (recorded as deferred).

### Typed ModelContext (ARCH-07)
- `ModelContext` gains typed fields for the fixed metadata: `feeder::Union{Nothing,AbstractFeeder}`,
  `T::Int`, `pf::Union{Nothing,AbstractPowerFlow}` (the formulation), `pf_vars` (the formulation's
  NamedTuple), `objective::QuadExpr`, `device_vars` (today's `:agg_device_vars`). `meta` remains for
  experiment/result-specific keys (`p_import`, `q_import`, `socp_maxgap`, `price_provenance`,
  `qag_dso`, `problem_class`, …).
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

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/data/Feeder.jl` (`Bus`, `Branch`, `Feeder{T}`), `src/data/MeshedFeeder.jl` (`MeshedFeeder{T}`,
  reuses `Bus`/`Branch`), `src/data/topology.jl`, `mesh_topology.jl`.
- `src/core/ModelContext.jl` — `mutable struct ModelContext(model, constraints, residuals, meta)`,
  `register_constraint!`, `add_to_residual!` (scalar + indexed), `add_to_objective!` (writes
  `meta[:objective]`).
- Balance blocks: `welfare_solve.jl:237-252`, `mpc_window.jl:~205-221`, `stochastic_welfare.jl:~348-365`
  and `~681-696`, `DsoOpt.jl:463-475`, `linear_solve.jl` (similar).

### Established Patterns
- Construction-is-the-gate validation via inner constructors throwing `ArgumentError`.
- `contribute!(pf, ctx, feeder; T)` writes residuals + stashes `pf_vars`; reactive capability today is
  data-driven (`haskey(ctx.residuals, :Rq)`).
- meta key usage counts: `:pf_vars` 56, `:T` 45, `:objective` 44, `:feeder` 39, `:agg_device_vars` 33,
  `:p_import` 15, `:socp_maxgap` 14, `:q_import` 13, `:qag_dso` 10, `:formulation` 7.
- `haskey(...pf_vars, :l)` gates: planning/subproblem.jl:352, pricing/fit.jl:522, pricing/dlmp.jl:112,
  models/stochastic_welfare.jl:449, models/welfare_solve.jl:275 (+ exactness.jl docs).

### Integration Points
- Every builder in src/models, src/admm, src/planning, src/pricing writes `ctx.meta[:feeder]`/`[:T]`.
- Tests read `ctx.meta[...]` directly in many files — migrate with the grep gate.

</code_context>

<specifics>
## Specific Ideas

- Every numeric golden bit-identical; certify with the detached full suite (≥ 31782 passes, 0/0/5).
- Docs `checkdocs = :exports`: any new exported symbol (`AbstractFeeder`, `close_balance!`, traits)
  must be surfaced in `docs/src/api.md`.
- PVAL-04 tripwire (test_planning_noninteger.jl): any new exported `build_*` must be allowlisted.

</specifics>

<deferred>
## Deferred Ideas

- Migrating planning-layer balance-closing copies (subproblem/master/feasibility_oracle/bilevel_kkt/nash)
  to `close_balance!`.
- Typing the result-specific `meta` keys (`p_import`, `socp_maxgap`, …).
- Accessor-function interface for feeders.

</deferred>

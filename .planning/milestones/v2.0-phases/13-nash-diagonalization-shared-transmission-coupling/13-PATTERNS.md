# Phase 13: Nash Diagonalization & Shared-Transmission Coupling - Pattern Map

**Mapped:** 2026-07-23
**Files analyzed:** 9 (2 new source files with 3 distinct sub-components, 1 extended
core-stub file, 1 extended weakdep-extension file, 1 config/include file, 2 new test
files, plus the `solve_stackelberg!` parameterization question)
**Analogs found:** 8 / 9 (strong in-repo analogs); 1 sub-component (`run_nash_probe`)
has no in-repo analog and reuses RESEARCH.md's own designed pattern instead.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `src/planning/coupling.jl` — `SharedTransmission`/`build_shared_transmission`/`update_coupling!`/`write_back!` | model (JuMP model-builder) | transform (build-once, `Parameter`-mutate, re-solve — never rebuild) | `src/planning/follower.jl` (`FollowerLP`/`build_follower`/`solve_follower!`) | role-match (same build-once/Parameter/INFRA-02-factory idiom generalized from 1 to N distributor rows; the shared capacity row and per-distributor cost-share vector are genuinely new) |
| `src/planning/nash.jl` — `run_nash!`/`solve_nash!` (outer Gauss-Seidel loop) | service (orchestration loop, one level above Benders) | batch (cyclic sweep over independently-converged best-response units) | `src/planning/benders.jl` (`solve_stackelberg!`) | exact (identical "boundary guards → build subproblems ONCE outside the loop → iterate → fail-loud cap" shape, one level up) |
| `src/planning/nash.jl` — `NashTrace` struct + `push!`/`is_converged`/`trace_summary` | model (JuMP-free ledger) | CRUD (append-only insert via `push!`, read via summary/query) | `src/planning/trace.jl` (`BendersTrace`) | exact (RESEARCH.md's own Pattern 3 explicitly instructs mirroring this struct's shape) |
| `src/planning/nash.jl` — `run_nash_probe` (multi-seed × multi-order gate) | service (probe driver / regression gate) | batch | **none in-repo** | no analog — build from RESEARCH.md Pattern 4's designed seed/order matrix + spread metric (this is a genuinely new capability, not a literature lookup) |
| `src/diagnostics/plots.jl` — `plot_nash_convergence` generic stub | utility (method-less generic + export, JuMP/Makie-free) | transform | `plot_price_convergence`/`plot_convergence` stubs, same file (lines 16-37) | exact |
| `ext/TSODSOMakieExt.jl` — `TSODSO.plot_nash_convergence(::NashTrace)` method | provider (CairoMakie weakdep extension method) | transform | `TSODSO.plot_price_convergence(::AdmmResiduals)` (twin-axis idiom, lines 77-113) | exact |
| `src/TSODSO.jl` — planning include block | config (module assembly / include graph) | n/a | existing `planning/*.jl` include block (lines 101-126) — **already contains a forward-reference comment naming `coupling.jl` as Phase 13's join point** | exact |
| `test/test_planning_coupling.jl` | test (unit, build-once model) | CRUD/transform | `test/test_planning_follower.jl` | exact |
| `test/test_planning_nash.jl` | test (loop convergence + gating regression) | batch | `test/test_planning_benders.jl` (convergence/incumbent asserts) + `test/test_planning_hardening.jl` (load-test/empirical-measurement/gating idiom) | exact (two analogs, different sub-scopes) |

## Pattern Assignments

### `src/planning/coupling.jl` (model, transform)

**Analog:** `src/planning/follower.jl` (`FollowerLP`/`build_follower`/`solve_follower!`)

**Header/ownership comment convention** (lines 1-26 of `follower.jl`) — every planning
seam file opens with a `# src/planning/X.jl` / `# SEAM:` / `# OWNER:` block naming the
requirement ID and documenting the ONE deliberate departure from a sibling pattern.
`coupling.jl` should open the same way, naming NASH-01 and stating the departure: N
coupling rows instead of 1, one *shared* capacity row, and the `[ASSUMED]` per-
distributor cost-share convention (CONTEXT.md's locked "each distributor owns its own
`x_inv[i]`" decision — note this project's own CONTEXT.md OVERRODE RESEARCH.md's
tentative equal-split/one-shared-investment sketch; `coupling.jl` must reflect the
CONTEXT.md decision, not the RESEARCH.md sketch verbatim — see "Departure from
RESEARCH.md" note below).

**Struct + build-once pattern** (`follower.jl` lines 59-131):
```julia
struct FollowerLP{Z, C}
    model::Model
    x_inv::VariableRef
    x_op::Vector{VariableRef}
    z::Z
    coupling::C
    T::Int
    corridor_cap::Float64
    x_inv_max::Float64
end

function build_follower(; T::Int, corridor_cap::Real, x_inv_max::Real, c_inv::Real,
    c_op::AbstractVector{<:Real})
    T >= 1 || throw(ArgumentError("build_follower needs T >= 1, got T=$T"))
    corridor_cap > 0 || throw(ArgumentError(...))
    x_inv_max > 0 || throw(ArgumentError(...))
    length(c_op) == T || throw(ArgumentError(...))

    model = Model(select_optimizer(LP()))   # INFRA-02: never Model(HiGHS.Optimizer) directly

    @variable(model, 0 <= x_inv <= x_inv_max)
    @variable(model, x_op[t = 1:T] >= 0)
    @variable(model, z[t = 1:T] in Parameter(0.0))

    @constraint(model, invest_op[t = 1:T], x_op[t] <= corridor_cap * x_inv)
    @constraint(model, coupling[t = 1:T], x_op[t] == z[t])

    @objective(model, Min, c_inv * x_inv + sum(c_op[t] * x_op[t] for t in 1:T))
    return FollowerLP(model, x_inv, x_op, z, coupling, T, Float64(corridor_cap), Float64(x_inv_max))
end
```
**Direct translation to `coupling.jl`:** index every `x_inv`, `x_op`, `z`, `coupling` by
distributor `i = 1:N` (per CONTEXT.md's per-distributor-ownership decision,
`x_inv` becomes a length-N vector `x_inv[i]`, not a scalar), and add ONE new
`@constraint(model, capacity[t = 1:T], sum(x_op[i, t] for i in 1:N) <= corridor_cap *
sum(x_inv[i] for i in 1:N))` row — the single genuinely-new coupling row NASH-01 exists
for. Boundary guards (`T >= 1`, `corridor_cap > 0`, `N >= 2`, per-distributor
`x_inv_max[i] > 0`, `length(c_op[i]) == T` for every `i`) belong BEFORE any
`@variable`/`@objective` call, mirroring `build_follower`'s discipline verbatim.

**Re-solve idiom (`update_coupling!`/`write_back!`)** — mirrors `solve_follower!`'s
`set_parameter_value.(f.z, z_trial)` (line 170 of `follower.jl`) EXACTLY, scoped to
distributor `i`'s row only:
```julia
set_parameter_value.(f.z, z_trial)   # follower.jl line 170 — the idiom to reuse verbatim
optimize!(f.model)
```
`coupling.jl`'s `update_coupling!(shared, i, z_i_trial)` and `write_back!(shared, i,
z_i_converged)` both reduce to this same one-line `set_parameter_value.` call, scoped to
`shared.z[i, :]` — NEVER a rebuild, NEVER touching any other distributor's row `j != i`.

**Error-handling / Farkas-certificate branch** (`follower.jl` lines 166-226) — the
feasible/infeasible/loud-error three-way branch (`is_solved_and_feasible` → genuine
cost+dual; `dual_status == MOI.INFEASIBILITY_CERTIFICATE` → `(v, u)` with the
`isfinite(v) && v > 0 && all(isfinite, u)` production guard; anything else → loud
`error(...)` naming all four status queries) is the EXACT pattern the per-distributor
`solve_shared_follower!`-style entry point on `coupling.jl` must reuse — this is the
single most load-bearing excerpt in the whole phase, since it is what
`solve_stackelberg!` depends on structurally (see "Parameterizing `solve_stackelberg!`"
section below).

**Departure from RESEARCH.md's sketch (flag for the planner):** RESEARCH.md's Pattern 1
sketch (lines 288-347 of 13-RESEARCH.md) shows ONE shared `x_inv` scalar with a
`cost_share::Vector{Float64}` split vector (`[ASSUMED]` equal-split default). CONTEXT.md
(the user's locked decision, dated the SAME session, post-research) explicitly
overrides this: **per-distributor `x_inv[i]`**, each distributor pays its own
investment, with `capacity[t]: Σᵢ x_op[i,t] <= corridor_cap · Σᵢ x_inv[i]` (or the
model's own equivalent aggregate form) — NOT one jointly-owned scalar. The planner MUST
implement CONTEXT.md's decision (per-distributor `x_inv[i]` vector), not
RESEARCH.md's tentative single-`x_inv` sketch; document this override explicitly in
`coupling.jl`'s own docstring for thesis traceability, exactly as CONTEXT.md instructs.

---

### `src/planning/nash.jl` — `run_nash!`/`solve_nash!` (service, batch)

**Analog:** `src/planning/benders.jl` (`solve_stackelberg!`)

**File-header convention** (`benders.jl` lines 1-37) — states the seam, the owner, the
convergence-criterion divergence from a sibling loop (there: UB/LB gap vs ADMM's
residual test; here: outer Nash residual vs Benders' own UB/LB gap), and the
checkpoint/cut-store contract. `nash.jl` should open identically, stating NASH-02/03/04,
and explicitly documenting the fresh-cut-store-per-best-response contract (the cut-
invalidation math argument from 13-CONTEXT.md/13-RESEARCH.md, embedded verbatim per
CONTEXT.md's own instruction).

**Boundary-guards-before-build-call idiom** (`benders.jl` lines 126-147):
```julia
T >= 1 || throw(ArgumentError("solve_stackelberg! needs T >= 1 (got T=$T)"))
max_iter >= 1 || throw(ArgumentError(...))
length(λ₀) == T || throw(ArgumentError(...))
isfinite(tol) && tol > 0 || throw(ArgumentError(...))
max_iter <= 99_999 || throw(ArgumentError(...))   # checkpoint_iteration!'s 5-digit contract
```
`nash.jl`'s `run_nash!` needs the SAME discipline plus the ONE NEW guard CONTEXT.md
locks: `tol_inner < tol_outer` (strict), raising `ArgumentError` — mirror this exact
"guard BEFORE any build call" ordering, do not bury it after `SharedTransmission` is
built.

**Build-once-outside-the-loop pattern** (`benders.jl` lines 149-154):
```julia
oracle = build_planning_oracle(feeder, pf, aggregators; λ₀ = λ₀, T = T)
follower = build_follower(; follower_kwargs..., T = T)
master = build_master(; master_kwargs..., T = T)
```
`nash.jl`'s outer loop builds `shared = build_shared_transmission(...)` ONCE, outside
`for k in 1:max_sweeps`, exactly like this — no `build_*`/`Model(` call appears inside
the sweep loop.

**Per-iteration timing + trace-row-append idiom** (`benders.jl` lines 167-230,
specifically the `t_solve`/`time_ns()` bracketing and the `push!(trace, k; ...)` calls)
— `nash.jl` should time ONLY the `solve_stackelberg!` call itself (never
`checkpoint_iteration!`'s I/O) with `time_ns()`, exactly mirroring the WR-01/phase-12
lesson already encoded here:
```julia
t0_ns = time_ns()
lb_res = solve_master!(master; attempts_out = master_attempts)
t_solve += (time_ns() - t0_ns) / 1.0e9
```

**Fail-loud exhaustion + trace-sourced diagnostic** (`benders.jl` lines 302-315) — on
`max_iter`/`max_sweeps` exhaustion, read the LAST recorded trace row (never a stale
loop-local variable), mirroring:
```julia
last_LB = last(trace.LB_trace)
last_UB = last(trace.UB_trace)
last_gap = last(trace.gap_trace)
error("solve_stackelberg!: exhausted $max_iter iteration(s) without converging " *
      "(last recorded LB=$last_LB, UB=$last_UB, gap=$last_gap ...) — refusing to " *
      "silently return a non-converged result")
```
`run_nash!`'s own exhaustion error should read `last(trace.nash_residual_trace)` etc.
the SAME way — IN-01's own lesson (phase 12 review) generalizes cleanly one level up.

**Gauss-Seidel-vs-Jacobi timing (the ONE genuinely new correctness risk, no in-repo
precedent — RESEARCH.md Pitfall 1):** `write_back!` must fire IMMEDIATELY after each
distributor's `solve_stackelberg!` returns, BEFORE the next distributor in
`sweep_order(k)` reads `z_{-i}` — there is no analog for this timing discipline in
`benders.jl` (a single-distributor loop has no such ordering to get wrong); it is this
phase's own novel correctness obligation and should be called out explicitly in
`nash.jl`'s docstring, with a dedicated regression test (see Test section below).

---

### `src/planning/nash.jl` — `NashTrace` (model, CRUD ledger)

**Analog:** `src/planning/trace.jl` (`BendersTrace`)

**File-header "why structurally different from the sibling ledger" convention**
(`trace.jl` lines 1-41) — `BendersTrace`'s own header explains why it is NOT a copy of
`AdmmResiduals` (single relative-gap scalar vs a primal/dual residual pair). `NashTrace`
must do the same for `BendersTrace`: one row per `(sweep, distributor)` pair (not one
row per sweep), embedding each distributor's own Benders summary — RESEARCH.md's own
Pattern 3 already justifies this shape; restate it in the header, don't just implement it.

**Struct + empty-constructor pattern** (`trace.jl` lines 88-120):
```julia
mutable struct BendersTrace
    iter_trace::Vector{Int}
    LB_trace::Vector{Float64}
    UB_trace::Vector{Float64}
    gap_trace::Vector{Float64}
    cut_type_trace::Vector{Symbol}
    n_cuts_trace::Vector{Int}
    master_status_trace::Vector{Symbol}
    oracle_status_trace::Vector{Symbol}
    retry_count_trace::Vector{Int}
    solve_time_trace::Vector{Float64}
    iters::Int
end
BendersTrace() = BendersTrace(Int[], Float64[], Float64[], Float64[], Symbol[], Int[],
    Symbol[], Symbol[], Int[], Float64[], 0)
```
Direct translation for `NashTrace` (per RESEARCH.md's Pattern 3 field list): replace
`LB_trace`/`UB_trace`/`gap_trace`/`cut_type_trace` with `sweep_trace::Vector{Int}`,
`distributor_trace::Vector{Int}`, `nash_residual_trace::Vector{Float64}`,
`benders_iters_trace::Vector{Int}`, `benders_gap_trace::Vector{Float64}`,
`benders_retries_trace::Vector{Int}`, `cuts_rebuilt_trace::Vector{Int}`,
`order_trace::Vector{Symbol}`, plus `iters::Int` — same empty-constructor idiom.

**Sequential-`k` fail-loud guard** (`trace.jl` lines 122-130):
```julia
@inline function _assert_sequential_trace(trace::BendersTrace, k::Integer)
    expected = trace.iters + 1
    k == expected ||
        throw(ArgumentError("push!: expected sequential iteration $expected, got k=$k"))
    return nothing
end
```
`NashTrace`'s own `push!` should reuse this EXACT guard shape (a distinct, file-local,
non-exported helper — no dispatch collision, per `trace.jl`'s own comment).

**`push!` guard-before-mutate pattern** (`trace.jl` lines 161-200) — every field
guarded (`cut_type in (...)`, `isfinite(LB)`, `n_cuts >= 0`, `retry_count >= 0`) BEFORE
any `push!(trace.X_trace, ...)` mutation, with `UB`/`gap`-style fields DELIBERATELY left
unguarded for finiteness where `Inf`/`NaN` are legitimate sentinels (documented, not a
gap). `NashTrace`'s `push!` should guard `nash_residual_trace` similarly (its own `NaN`
sentinel before a distributor's first row) and `order_trace ∈ (:forward, :reverse)`.

**`is_converged`/`trace_summary` empty-ledger-safe query pattern** (`trace.jl` lines
202-241) — both return legitimate sentinels (`false`/`NaN`/`0`) on an empty trace rather
than throwing; `NashTrace`'s own summary/convergence queries should follow the identical
contract.

---

### `src/planning/nash.jl` — `run_nash_probe` (service, batch) — NO ANALOG

No in-repo file implements a multi-seed/multi-order probe-and-report gate; this is a
genuinely new capability (NASH-04). Build directly from RESEARCH.md's own designed
Pattern 4 (13-RESEARCH.md lines 478-524): a hand-picked ≥3-seed × 2-order matrix (`zero`,
`saturating`, `skewed` initial `z^(0)` profiles × `:forward`/`:reverse` sweep orders),
asserting ALL runs converge (the gating test), and computing the spread as the max
pairwise distance (`C(n,2)` combinations) across `z`, investment `y`, and total cost —
never a mean/variance summary, per the "honesty over convenience" rationale RESEARCH.md
gives. The summary string must literally contain `"a converged equilibrium"` and never
`"the equilibrium"` (STATE.md's carried blocker, encoded in code per CONTEXT.md).

---

### `src/diagnostics/plots.jl` (utility, transform) — extend

**Analog:** the file's own existing `plot_convergence`/`plot_price_convergence` stubs
(lines 16-37, this same file):
```julia
"""
    plot_price_convergence(res::AdmmResiduals; filename=nothing)
...
"""
function plot_price_convergence end

export plot_convergence, plot_price_convergence
```
Add `function plot_nash_convergence end` + `export plot_nash_convergence` in the exact
same JuMP/Makie-free style — the core package must stay plot-free (threat T-07-01, this
file's own header comment, lines 1-14). Take a `NashTrace` argument in the docstring,
require CairoMakie for a dispatchable method (same "deliberate MethodError otherwise"
contract as the existing two stubs).

---

### `ext/TSODSOMakieExt.jl` (provider, weakdep extension) — extend

**Analog:** `TSODSO.plot_price_convergence(res::TSODSO.AdmmResiduals; filename =
nothing)` (lines 77-113, this file) — the twin-axis idiom is the direct structural
template for `plot_nash_convergence`'s "two-level" requirement (outer Nash residual +
inner Benders gap on a twin/overlaid axis):
```julia
function TSODSO.plot_price_convergence(res::TSODSO.AdmmResiduals; filename = nothing)
    xs = _iters_axis(res)
    fig = Figure()
    ax = Axis(fig[1, 1]; xlabel = "...", ylabel = "...", yscale = log10, title = "...")
    axρ = Axis(fig[1, 1]; ylabel = "...", yaxisposition = :right, ylabelcolor = :seagreen,
        yticklabelcolor = :seagreen)
    hidespines!(axρ)
    hidexdecorations!(axρ)
    linkxaxes!(ax, axρ)

    lgap = lines!(ax, xs, _logsafe(res.price_gap_trace); color = :purple)
    lrho = lines!(axρ, xs, res.rho_trace; color = :seagreen, linestyle = :dot)
    axislegend(ax, [lgap, lrho], [...]; position = :rt)
    filename === nothing || save(filename, fig)
    return fig
end
```
`plot_nash_convergence(trace::TSODSO.NashTrace; filename = nothing)` should: (1) group
rows by `sweep_trace`, reduce `nash_residual_trace` by `max` per sweep for the OUTER
curve (left axis, log-scaled, `_logsafe`-guarded exactly like `_logsafe(trace) =
max.(trace, eps())`, lines 33 of this file — the log10(0)=-Inf Makie-rejection guard
applies identically here); (2) overlay `benders_gap_trace` per distributor on the SAME
or a twin axis for the INNER curve. Reuse `_iters_axis`/`_logsafe` helpers (lines 26-33)
verbatim rather than redefining them — they are file-local, non-exported, and already
generic over any ledger exposing an `iters`/trace-vector shape.

---

### `src/TSODSO.jl` (config, include graph) — extend

**Analog:** the file's own existing planning include block (lines 101-126), which
ALREADY contains a forward-reference comment: *"`planning/subproblem.jl` (below) and
Phase 13's `planning/coupling.jl` join this directory."* Append, in this exact
commented style (naming owner plan + requirement ID per line):
```julia
include("planning/coupling.jl")     # SharedTransmission per-distributor views (plan 13-0X, NASH-01)
include("planning/nash.jl")         # run_nash!/NashTrace/run_nash_probe (plan 13-0X, NASH-02/03/04)
```
placed AFTER `planning/benders.jl` (line 126) — `nash.jl` needs `solve_stackelberg!`
loaded first — and BEFORE `diagnostics/plots.jl` (line 133), since `plot_nash_convergence`
(the generic stub) needs `NashTrace` defined first if its docstring/signature refers to
the type. Mirror the existing per-line comment convention (owner plan + requirement ID)
exactly.

---

## Parameterizing `solve_stackelberg!` for per-distributor best-response reuse

**Problem:** `solve_stackelberg!` currently (`benders.jl` lines 114-125) takes
`follower_kwargs::NamedTuple` and BUILDS its own standalone `FollowerLP` internally
(line 153: `follower = build_follower(; follower_kwargs..., T = T)`). Phase 13 needs
each distributor's best-response to solve against a per-distributor VIEW of the ONE
shared, already-built `SharedTransmission` model instead — but CONTEXT.md and
13-RESEARCH.md both lock "keep Phase 11/12 call sites unchanged."

**Recommended parameterization (duck-typed, zero-diff for existing callers):** add ONE
new, defaulted keyword to `solve_stackelberg!`:

```julia
function solve_stackelberg!(
    feeder, pf::AbstractPowerFlow, aggregators::AbstractVector{<:Aggregator};
    λ₀, T::Int, follower_kwargs::NamedTuple, master_kwargs::NamedTuple,
    tol::Real = 1e-6, max_iter::Int = 100,
    checkpoint_dir::AbstractString = datadir("planning_checkpoints"),
    follower = nothing,   # NEW, additive, defaults nothing — Phase 11/12 callers never pass this
)
    ...
    follower = follower === nothing ? build_follower(; follower_kwargs..., T = T) : follower
    ...
```

- Every existing Phase 11/12 call site omits the new keyword → `follower === nothing` →
  `build_follower(; follower_kwargs...)` runs exactly as today, byte-identical behavior
  (mirrors `attempts_out::Union{Nothing,Ref{Int}} = nothing`'s own additive-keyword
  precedent, `master.jl` lines 262-265 / `retry.jl`'s `attempts_out` contract — the SAME
  "new keyword defaults to a pure no-op" idiom already used twice in this codebase for
  exactly this kind of non-breaking extension).
- `nash.jl`'s per-distributor best-response instead passes `follower =
  <distributor i's SharedTransmission view>`, and `follower_kwargs = NamedTuple()` (or
  the boundary guard treats `follower_kwargs` as ignored/optional when `follower !==
  nothing` — assert mutual exclusivity with an `ArgumentError` if BOTH a non-empty
  `follower_kwargs` and a non-`nothing` `follower` are supplied, to avoid silently
  ignoring one).
- The "view" object passed as `follower` needs NO new abstract type (this codebase's own
  convention: `FollowerLP`, `PlanningOracle`, `BendersMaster` are all concrete structs
  with no shared supertype, duck-typed via method dispatch) — it only needs a
  `solve_follower!(view, z_trial)` method returning the SAME NamedTuple shape
  `follower.jl` already documents: `(; feasible=true, cost, π_s)` or `(; feasible=false,
  v, u)`. `coupling.jl`'s per-distributor accessor (e.g. a small `DistributorView`
  struct wrapping `(shared, i)`) should implement exactly this method, reusing
  `follower.jl`'s three-way feasible/infeasible/loud-error branch (lines 166-226)
  verbatim, scoped to `shared.model`/`shared.coupling[i, :]`.
- `solve_stackelberg!`'s DIRECT (never-retry-wrapped) call to `solve_follower!` (line
  201: `follower_res = solve_follower!(follower, lb_res.z)`) is untouched — dispatch
  picks the `FollowerLP` method or the new `DistributorView` method transparently; the
  Farkas-certificate discipline (PLAN-04's "never retry an infeasible follower solve")
  applies identically to both.

This keeps `solve_stackelberg!`'s existing positional/keyword contract 100% source- and
behavior-compatible for every Phase 11/12 test and call site, while giving `nash.jl` the
seam it needs. The exact keyword name (`follower` vs `follower_override` vs
`shared_view`) and whether the mutual-exclusivity guard is an `ArgumentError` or a
softer "last one wins" rule are Claude's Discretion (per CONTEXT.md) — the planner
should pick one and document it in `benders.jl`'s own docstring update.

## Shared Patterns

### Build-once / `Parameter` re-solve (INFRA-02-compatible)
**Source:** `src/planning/follower.jl` lines 110, 114, 170
**Apply to:** `coupling.jl`'s `SharedTransmission` build + `update_coupling!`/`write_back!`
```julia
model = Model(select_optimizer(LP()))         # INFRA-02 — never Model(HiGHS.Optimizer) directly
@variable(model, z[t = 1:T] in Parameter(0.0))
set_parameter_value.(f.z, z_trial)            # re-solve idiom, NEVER a rebuild
```

### Boundary guards BEFORE any build/loop-body call
**Source:** `src/planning/follower.jl` lines 102-108; `src/planning/benders.jl` lines 126-147
**Apply to:** `build_shared_transmission`, `run_nash!` (including the NEW `tol_inner <
tol_outer` `ArgumentError` CONTEXT.md locks), `run_nash_probe`
```julia
T >= 1 || throw(ArgumentError("... needs T >= 1, got T=$T"))
```

### Fail-loud, trace-sourced exhaustion diagnostic
**Source:** `src/planning/benders.jl` lines 302-315
**Apply to:** `run_nash!`'s `max_sweeps` cap and `run_nash_probe`'s "not all runs
converged" gate — never a silent partial result; read the last row off the trace, never
a stale loop-local.

### JuMP-free purpose-built ledger, sequential-push! guarded
**Source:** `src/planning/trace.jl` (whole file; guard at lines 125-130, `push!` at
161-200, empty-safe queries at 202-241)
**Apply to:** `NashTrace` — same struct/constructor/guard/query shape, new field names.

### CairoMakie weakdep twin-axis convergence plot
**Source:** `ext/TSODSOMakieExt.jl` lines 26-33 (`_iters_axis`/`_logsafe` helpers,
reusable verbatim) and lines 86-113 (`plot_price_convergence`, the twin-axis template)
**Apply to:** `plot_nash_convergence` — outer Nash residual (log-scaled, `_logsafe`-
guarded) + inner Benders gap, twin/overlaid axis.

### Checkpoint-per-iteration reuse (no new primitive needed)
**Source:** `src/planning/checkpoint.jl` (whole file — `checkpoint_iteration!` is
already generic over any `state::NamedTuple`) and its call site in `benders.jl` lines
206-210
**Apply to:** `run_nash!` — call `checkpoint_iteration!` once per outer sweep (or once
per best-response, Claude's Discretion per CONTEXT.md) with a Nash-shaped state tuple;
no new checkpoint mechanism is needed, just a new `state` NamedTuple shape and (likely) a
distinct `checkpoint_dir` subpath to avoid filename collision with the inner Benders
loop's own per-iteration checkpoints (each distributor's `solve_stackelberg!` call
already checkpoints its OWN inner iterations — the planner should decide whether the
outer loop's checkpoint directory nests under a per-sweep/per-distributor subpath, e.g.
`joinpath(checkpoint_dir, "sweep_$k", "distributor_$i")`, to avoid the inner and outer
checkpoint streams overwriting each other's `iter_NNNNN.jld2` files).

## No Analog Found

| File/Component | Role | Data Flow | Reason |
|-----------------|------|-----------|--------|
| `run_nash_probe` (in `src/planning/nash.jl`) | service | batch | No in-repo multi-seed/multi-order probe-and-report gate exists; build directly from 13-RESEARCH.md's own Pattern 4 (seed/order matrix + max-pairwise-distance spread metric), not from a codebase analog. |
| Gauss-Seidel write-back timing discipline (inside `nash.jl`) | (cross-cutting correctness rule, not a file) | n/a | No existing loop in this repo has an inter-player ordering dependency to get right/wrong (Benders is single-distributor); this is a genuinely new pitfall (RESEARCH.md Pitfall 1) with no in-repo precedent to copy — only a documented risk to test against explicitly. |

## Metadata

**Analog search scope:** `src/planning/`, `src/diagnostics/`, `ext/`, `src/TSODSO.jl`,
`test/test_planning_*.jl` (9 existing planning-layer files read in full: `follower.jl`,
`benders.jl`, `trace.jl`, `master.jl`, `checkpoint.jl`, `retry.jl`, `plots.jl`,
`TSODSOMakieExt.jl`, `TSODSO.jl`; 3 test files read: `test_planning_benders.jl`,
`test_planning_hardening.jl`, `test_planning_follower.jl` excerpt).
**Files scanned:** 12 read in full or targeted excerpt; 0 re-reads of any already-loaded
range.
**Pattern extraction date:** 2026-07-23

# Phase 31: GNE Nash Fixture, Integer N>1 & Planning Docs Refresh - Pattern Map

**Mapped:** 2026-10-01
**Files analyzed:** 10 (7 modified, 1 likely-new test file, 2 docs refreshed)
**Analogs found:** 10 / 10 (every file has a direct in-repo analog — this phase is pure
extension/generalization of Phases 13/24/29/30 patterns, no new algorithm design)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/planning/nash.jl` (`run_nash_probe` seeds dispatch) | orchestrator | event-driven (multi-run probe) | `run_nash_probe` itself, lines 769-851 (same file, extend in place) | exact |
| `src/planning/nash.jl` (`run_nash!` `integer` kwarg + cycle detection) | orchestrator | event-driven (Gauss-Seidel loop) | `run_nash!` itself, lines 381-662 (same file, extend in place); cycle dict mirrors `master_integer.jl`'s `visited::Dict{Vector{Int},...}` | exact |
| `src/planning/nash.jl` (new `solve_variational_equilibrium`) | model builder + solver | CRUD (single monolithic convex solve) | `test/fixtures_planning_ieee13_short.jl`'s `solve_joint_reference` (lines 154-239) | exact (same "independently-built monolithic joint model" pattern, generalized N=1→N) |
| `src/planning/master_integer.jl` (`build_master_integer` `bounds_ctx`) | model builder | CRUD (build-once MILP) | `src/planning/master.jl`'s `build_master` (lines 470-664) | exact (same opt-in `bounds_ctx` keyword, same three-way `α_x_lb` dispatch) |
| `src/planning/master_integer.jl` (`add_ll_cut!` WR-02 fix) | model mutator (cut append) | CRUD (persistent constraint append) | `add_optimality_cut!`/`add_feasibility_cut!` (`master.jl` lines 695-735) — finiteness-guard-before-`@constraint` idiom | exact |
| `src/planning/benders.jl` (`_oracle_or_infeasible` WR-01 fix) | solver/oracle dispatcher | request-response (classify-or-rethrow) | the function itself (lines 267-289), reusing the outer loop's own `feas_oracle`-confirmed `ALMOST_INFEASIBLE` handling (lines 1310-1330) | exact |
| `src/planning/benders.jl` (convergence certificate WR-03 fix) | solver loop | CRUD (iterate-and-converge) | `converged_at`/`LB_k` block (lines 1605-1609), using `_accepted_lb_slack` (already defined, lines 730-739, currently unused at this call site) | exact |
| `test/test_planning_nash.jl` (new fixtures/tests) | test | unit | existing testitems in same file (interior-cap fixture mirrors the corner-cap control, lines 257-325; probe tests mirror lines 622-767) | exact |
| `test/test_planning_nash_integer.jl` (new, or appended to `test_planning_nash.jl`) | test | unit | `test/test_planning_benders_integer.jl` (single-distributor integer smoke test, lines 84-135) | exact |
| `docs/writeups/stackelberg_vs_psr_n1n2.typ` | documentation | — | itself (stale passages at lines 173-189, 189, 205-221, 237) | exact (refresh in place) |
| `docs/writeups/modelo_stackelberg_dso_unico.typ` | documentation | — | sibling writeup's own taxonomy framing (no existing section — new section modeled on the OTHER file's equivalence tables, e.g. `stackelberg_vs_psr_n1n2.typ` lines 209-217) | role-match (new section, borrowed table style) |

## Pattern Assignments

### `src/planning/nash.jl` — `run_nash_probe`'s seed dispatch extension (BILEV-06a)

**Analog:** the function itself, `src/planning/nash.jl:769-851` (extend additively, do not rewrite).

**Current signature / loop to extend** (lines 769-822):
```julia
function run_nash_probe(
    specs::AbstractVector{<:NamedTuple},
    build_shared::Function;
    seeds::NamedTuple,
    orders::Tuple = (:forward, :reverse),
    tol_outer::Real = 1e-4,
    max_sweeps::Int = 50,
    checkpoint_dir::AbstractString = datadir("nash_probe_checkpoints"),
    inexact_policy::Symbol = :strict,
)
    ...
    runs = Vector{NamedTuple}()
    for (seed_name, seed_z0) in pairs(seeds)
        for order in orders
            shared_run = build_shared()
            result = run_nash!(
                specs,
                shared_run;
                z0 = seed_z0,
                tol_outer = tol_outer,
                max_sweeps = max_sweeps,
                order = order,
                checkpoint_dir = joinpath(checkpoint_dir, "$(seed_name)_$(order)"),
                inexact_policy = inexact_policy,
            )
            push!(runs, (; seed = seed_name, order, result))
        end
    end
```

**Required extension (additive, backward-compatible — orchestrator-resolved Open Question
1):** dispatch on `seed_z0 isa NamedTuple`. A bare matrix (existing behavior, used by every
current caller including the corner-cap control test) stays byte-identical. A `(; z0,
x_inv0)` NamedTuple forwards BOTH to `run_nash!`, whose `x_inv0` keyword already exists
(`run_nash!`'s signature, line 385: `x_inv0::Union{Nothing, AbstractVector{<:Real}} =
nothing`) — no change needed to `run_nash!` itself for this part. Minimal patch shape:

```julia
for (seed_name, seed_z0) in pairs(seeds)
    z0_arg, x_inv0_arg = seed_z0 isa NamedTuple ?
        (seed_z0.z0, get(seed_z0, :x_inv0, nothing)) : (seed_z0, nothing)
    for order in orders
        shared_run = build_shared()
        result = run_nash!(
            specs, shared_run;
            z0 = z0_arg, x_inv0 = x_inv0_arg,
            tol_outer = tol_outer, max_sweeps = max_sweeps, order = order,
            checkpoint_dir = joinpath(checkpoint_dir, "$(seed_name)_$(order)"),
            inexact_policy = inexact_policy,
        )
        push!(runs, (; seed = seed_name, order, result))
    end
end
```

**Docstring pattern to extend** (the function's own docstring, lines 692-767) — follow its
existing "Boundary guards" / "Algorithm" / "Returns" / "Throws" section convention exactly;
add one paragraph under "Algorithm" documenting the new NamedTuple seed shape, citing the
empirically-confirmed reason the z0-only default seed cannot expose this specific
continuum (RESEARCH.md's "CRITICAL FINDING" section, quoted verbatim in RESEARCH.md,
useful for the docstring's own prose).

**Test pattern to copy:** `test/test_planning_nash.jl:622-674` (the existing N=2 probe
test) — same `specs`/`build_shared`/`seeds`/`orders` shape, same assertions
(`result.n_runs`, `all(r -> r.result.converged, result.runs)`, the two `occursin` checks on
`result.summary`). For BILEV-06a, replace `x_inv_max = [0.3, 0.3]` with `[1.0, 1.0]` and
replace the `seeds` NamedTuple's bare matrices with `(; z0 = ..., x_inv0 = ...)` entries
spanning `{0.0, 0.2, 0.5, 0.7}` (RESEARCH.md's own recommendation), then assert
`result.spread.x_inv_spread` exceeds a measured floor and `result.spread.z_spread` stays
near zero (documented as a correct property of this continuum, not a bug — see
RESEARCH.md's explicit note to this effect).

### `src/planning/nash.jl` — new `solve_variational_equilibrium` (BILEV-06b)

**Analog:** `test/fixtures_planning_ieee13_short.jl:154-239`, `solve_joint_reference` —
the EXACT "independently-built monolithic joint model" pattern Phase 30 used for its own
single-player cross-check, generalized here from N=1 to N players sharing ONE
`capacity[t]` row (mirrors `coupling.jl`'s `build_shared_transmission`, lines 174-249, but
with every `x_inv_i`/`x_op_i` FREE simultaneously — never bound-pinned via
`activate_distributor!`/`write_back!`).

**Imports/model-construction pattern** (from `solve_joint_reference`, lines 172-177,
generalize the single-`contribute!` call into an `N`-player loop):
```julia
model = Model(select_optimizer(SOCP()))   # or select_optimizer(problem_class(pf)) per-player if pf varies
ctx_i = ModelContext(model)   # one ModelContext region per distributor i — reuses
                               # subproblem.jl's own contribute!/add_to_residual! helpers
contribute!(ConvexBranchFlow(), ctx_i, feeder_i; T = T)
```

**Shared-row pattern** (mirrors `coupling.jl`'s `build_shared_transmission`, lines 211-228,
but WITHOUT any bound-pinning — every `x_inv[i]`/`x_op[i,:]` stays genuinely free):
```julia
@variable(model, 0 <= x_inv[i = 1:N] <= x_inv_max[i])
@variable(model, x_op[i = 1:N, t = 1:T] >= 0)
@constraint(model, capacity[t = 1:T],
    sum(x_op[i, t] for i in 1:N) <= corridor_cap * sum(x_inv[i] for i in 1:N))
@objective(model, Min,
    sum(c_y[i]*y_inv[i] + ...per-player oracle cost... + c_inv[i]*x_inv[i] +
        sum(c_op[i][t]*x_op[i,t] for t in 1:T) for i in 1:N))
```

**Certification pattern** (mirrors `solve_joint_reference`'s own `solve_with_retry!` +
`assert_socp_exact!` discipline, lines 228-229): solve ONCE with `dual = true`, read
`dual.(capacity)` — the single shared multiplier (certifies VE by construction, since the
row is written once) — then cross-check against each player's own best response pinned at
the joint-optimal `(x_inv_j, z_j)` of every OTHER player (re-run
`solve_follower!(DistributorView(shared_check, i), ...)` or a full `solve_stackelberg!`),
confirming no cheaper unilateral deviation exists.

**Genericity note (orchestrator-resolved Open Question 2):** accept `pf` per distributor
generically (exactly as `solve_stackelberg!` does — `pf::AbstractPowerFlow` is a normal
argument, never hard-coded to `LinDistFlow`/`ConvexBranchFlow`), even though this phase's
own fixture only exercises `LinDistFlow()`.

**Export/docstring placement:** add directly below `run_nash_probe`'s `export
run_nash_probe` (line 853) in the SAME file — `nash.jl` already owns every Nash-family
export (`NashTrace`, `run_nash!`, `run_nash_probe`); per RESEARCH.md's Architectural
Responsibility Map, a sibling file would be a needless split. Docstring style: follow
`run_nash!`'s own docstring convention (lines 270-380) — `# Algorithm` / `# Returns` /
`# Throws` sections, concrete field names in the returned NamedTuple.

**PVAL-04 registry note:** if the internal joint-model construction introduces a
`build_\w+`-named helper function, it MUST be added to `test/test_planning_noninteger.jl`'s
registry (lines 48-125) or the file's own source-scan tripwire (lines 191-205) will fail
loudly — prefer an unprefixed internal name (mirrors `master.jl`'s own
`make_relaxed_oracle_model`/`alpha_op_lb_derivation`, deliberately named WITHOUT `build_`
for exactly this reason, documented at `master.jl:207-211`) unless the function IS meant to
be a registered planning-layer builder.

### `src/planning/master_integer.jl` — `build_master_integer`'s `bounds_ctx` (BILEV-07 bounds fix, WR-03 root cause)

**Analog:** `src/planning/master.jl`'s `build_master`, lines 470-664 — port the SAME
`α_op_lb`/`α_x_lb` `Union{Symbol,Real}` + opt-in `bounds_ctx::Union{Nothing,NamedTuple}`
keyword, the SAME three-way `bounds_ctx.follower_kwargs` dispatch (`NamedTuple` / `FollowerLP`
/ `nothing`), and the SAME `lb_slack` bookkeeping field.

**Current (unvalidated) signature to extend** (`master_integer.jl:162-212`):
```julia
function build_master_integer(;
    T::Int, K::Int = 4, c_y::Real, y_max::Real,
    α_op_lb::Real, α_x_lb::Real,
)
    ...
    @variable(model, α_op >= α_op_lb)
    @variable(model, α_x >= α_x_lb)
    ...
    return BendersMasterInteger(model, y_inv, z, α_op, α_x, b, K, T,
        Float64(c_y), Float64(y_max), Float64(α_op_lb + α_x_lb), Any[],
        Dict{Vector{Int}, Vector{Float64}}())
end
```

**Pattern to port verbatim from `build_master`** (`master.jl:530-664`): the exact resolution
block —
```julia
(α_op_lb === :auto || α_x_lb === :auto) && bounds_ctx === nothing &&
    throw(ArgumentError("build_master_integer: α_op_lb/α_x_lb = :auto requires bounds_ctx"))
...
α_op_lb_resolved = if α_op_lb === :auto
    derive_alpha_op_lb(bounds_ctx.feeder, bounds_ctx.pf, bounds_ctx.aggregators;
        λ₀ = bounds_ctx.λ₀, T = T, y_max = y_max)
elseif bounds_ctx !== nothing
    d = alpha_op_lb_derivation(...)
    slack = alpha_lb_margin(d.optimum, d.gap; floor = rejection_tol)
    α_op_lb > d.optimum + slack && throw(ArgumentError(...))
    slack_op = slack + (isfinite(d.gap) ? abs(d.gap) : 0.0)
    Float64(α_op_lb)
else
    Float64(α_op_lb)
end
# ... identical α_x_lb three-way dispatch on bounds_ctx.follower_kwargs (NamedTuple /
#     FollowerLP / nothing) — DistributorView honestly skips validation (nothing branch),
#     same as the continuous path already does (benders.jl:856-862).
```

Reuse `derive_alpha_op_lb`/`derive_alpha_x_lb`/`alpha_lb_margin`/`ALPHA_LB_REJECTION_TOL`
from `master.jl` directly (already exported/available in the same module — no duplication,
per RESEARCH.md's "Don't Hand-Roll" table).

`BendersMasterInteger` struct (lines 107-121) needs a NEW `lb_slack::NamedTuple{(:op,
:x), Tuple{Float64,Float64}}` field mirroring `BendersMaster`'s own (`master.jl:88`) —
`_accepted_lb_slack(master, label)` (`benders.jl:738-739`) ALREADY has a generic
`master -> 0.0` fallback for any type without this field, so adding the field to
`BendersMasterInteger` and populating it correctly (instead of relying on the generic
`0.0` fallback) is what wires the new integer path into the EXISTING WR-05 runtime-floor
mechanism with zero changes to `benders.jl`'s `_assert_epigraph_floor` call sites.

### `src/planning/master_integer.jl` — `add_ll_cut!`'s `Q_ν ≥ L` precondition (WR-02)

**Analog:** the function itself, `master_integer.jl:448-476`; the finiteness-guard-before-
`@constraint` idiom is the SAME one `add_optimality_cut!`/`add_feasibility_cut!`
(`master.jl:695-735`) already use.

**Current code (guard missing)**:
```julia
function add_ll_cut!(
    master::BendersMasterInteger,
    b_trial::AbstractVector{<:Real},
    Q_nu::Real,
    L::Real,
)
    length(b_trial) == master.K || throw(ArgumentError(...))
    all(isfinite, b_trial) || throw(ArgumentError(...))
    isfinite(Q_nu) || throw(ArgumentError(...))
    isfinite(L) || throw(ArgumentError(...))
    b_nu = round.(Int, b_trial)
    ...
    @constraint(master.model, θ >= (Q_nu - L) * Dexpr + L)
    push!(master.cuts, (; kind = :ll, b_trial = b_nu, Q_nu, L))
    return master
end
```

**Fix (quoted verbatim from `.planning/phases/30-*/30-REVIEW.md`'s own already-vetted
patch, reproduced in RESEARCH.md)** — add immediately after the existing `isfinite(L)`
guard, BEFORE any `@constraint`:
```julia
Q_nu >= L - atol * max(1, abs(L)) || error(
    "add_ll_cut!: Q_nu=$Q_nu < L=$L — the declared epigraph lower bound " *
    "α_op_lb + α_x_lb is not a valid lower bound on the per-corner recourse; " *
    "the LL cut would be INVALID at every corner with Hamming distance >= 2.")
```
with a new `atol::Real = 1e-6` keyword added to the function signature. Also correct the
docstring's wrong reduction-at-Hamming-distance-`k` claim (currently: `"D <= -1, reduces
to θ >= L - 2k(Q_nu - L)"`, lines 436-438) to `θ >= L − (k−1)(Q_ν − L)`.

**Test pattern to copy:** `test_planning_benders_integer.jl`'s existing K=4 16-corner
exhaustive verification style (referenced in `add_ll_cut!`'s own docstring, line 434) —
add a new `@test_throws ErrorException add_ll_cut!(imaster, b_trial, Q_nu_bad, L; atol)`
case where `Q_nu_bad < L`, alongside the existing valid-cut regression.

### `src/planning/benders.jl` — `_oracle_or_infeasible`'s `ALMOST_INFEASIBLE` confirmation (WR-01)

**Analog:** the function itself, `benders.jl:267-289`; the CONFIRMED pattern already used
by the OUTER oracle catch (lines 1310-1330) and the feasibility-cut's own `feas_oracle`
construction (`feas_oracle = build_feasibility_oracle(...)`, line 1148, already in scope at
`ll_cut_recourse`'s call site, line 1516).

**Current code (treats `ALMOST_INFEASIBLE` as a hard infeasibility, no confirmation)**:
```julia
function _oracle_or_infeasible(oracle, z; on_inexact::Symbol)
    return try
        solve_planning_oracle!(oracle, z; on_inexact = on_inexact)
    catch e
        e isa ErrorException || rethrow()
        is_solved_and_feasible(oracle.model; dual = true) && rethrow()
        termination_status(oracle.model) in ORACLE_INFEASIBLE_STATUSES || rethrow()
        nothing
    end
end
```
Note `ORACLE_INFEASIBLE_STATUSES` (line 123-124) ALREADY includes `MOI.ALMOST_INFEASIBLE`
— this is exactly the gap: the corner search treats it as a hard infeasibility with no
confirmation, unlike the outer loop (lines 1310-1330) which confirms via
`solve_feasibility_oracle!`/`_feas_cut_class`.

**Fix (quoted verbatim from `30-REVIEW.md`, reproduced in RESEARCH.md)** — introduce a
NARROWER constant excluding `ALMOST_INFEASIBLE`, and thread a new `feas_oracle = nothing`
keyword through:
```julia
const CORNER_INFEASIBLE_STATUSES =
    (MOI.INFEASIBLE, MOI.INFEASIBLE_OR_UNBOUNDED, MOI.LOCALLY_INFEASIBLE)

function _oracle_or_infeasible(oracle, z; on_inexact::Symbol, feas_oracle = nothing)
    return try
        solve_planning_oracle!(oracle, z; on_inexact = on_inexact)
    catch e
        e isa ErrorException || rethrow()
        is_solved_and_feasible(oracle.model; dual = true) && rethrow()
        ts = termination_status(oracle.model)
        ts in ORACLE_INFEASIBLE_STATUSES || rethrow()
        if ts == MOI.ALMOST_INFEASIBLE
            feas_oracle === nothing && rethrow()   # unconfirmed near-certificate: fail loud
            _feas_cut_class(solve_feasibility_oracle!(feas_oracle, z).v) === :disagree && rethrow()
        end
        nothing
    end
end
```
Then thread `feas_oracle` through the two call chains that reach this function:
  - `corner_recourse(oracle, follower, y_inv, T; iters, on_inexact, feas_oracle = nothing)`
    (line 238) → `_corner_recourse_ternary`/`_corner_recourse_joint` (lines 308, 450) →
    their own `_oracle_or_infeasible(oracle, zvec; on_inexact, feas_oracle)` calls (lines
    324, 475).
  - `ll_cut_recourse(master::BendersMasterInteger, oracle, follower, lb_res, Q_nu_iterate;
    on_inexact, feas_oracle = nothing)` (line 670) → forwards to `corner_recourse`.
  - The ONE production call site, `ll_cut_recourse(...)` inside `solve_stackelberg!` (line
    1516), already has `feas_oracle` in lexical scope (built at line 1148) — pass it
    through: `ll_cut_recourse(master, oracle, follower, lb_res, Q_nu_iterate; on_inexact =
    ..., feas_oracle = feas_oracle)`.

Also correct `_oracle_or_infeasible`'s docstring (line 277-278) which currently claims it
"applies the same classification `solve_stackelberg!`'s own outer oracle catch applies" —
true only AFTER this fix.

### `src/planning/benders.jl` — convergence certificate widened by `lb_slack` (WR-03, applies to BOTH masters)

**Analog:** the convergence block itself, `benders.jl:1605-1609`, and the ALREADY-DEFINED
`_accepted_lb_slack` dispatcher (lines 730-739) which this block currently does NOT call.

**Current code:**
```julia
LB_k = lb_res.LB
converged_at(UBx) =
    known_optimum === nothing ? ((UBx - LB_k) / max(1, abs(UBx)) <= tol) :
    isapprox(UBx, known_optimum; atol = KNOWN_OPTIMUM_ATOL)
converged_now = converged_at(UB)
```

**Fix (Option B from `30-REVIEW.md`, quoted in RESEARCH.md — widen the certificate itself,
reusing the EXISTING `_accepted_lb_slack` dispatcher so `BendersMaster` and
`BendersMasterInteger` are both covered with ONE change, per the orchestrator's resolution
of Open Question 3 — apply to BOTH master types)**:
```julia
LB_k = lb_res.LB
lb_slack_total = _accepted_lb_slack(master, :op) + _accepted_lb_slack(master, :x)
converged_at(UBx) =
    known_optimum === nothing ?
        ((UBx - (LB_k - lb_slack_total)) / max(1, abs(UBx)) <= tol) :
        isapprox(UBx, known_optimum; atol = KNOWN_OPTIMUM_ATOL)
converged_now = converged_at(UB)
```
For `BendersMaster` with `bounds_ctx === nothing` (every pre-existing call site) and for
`BendersMasterInteger` BEFORE this phase's own `lb_slack` field is added,
`_accepted_lb_slack` returns `0.0` for both labels (the generic fallback method, line 739,
or `BendersMaster.lb_slack == (; op = 0.0, x = 0.0)` when unvalidated) — so this is
BYTE-IDENTICAL on every existing golden/regression test; it only widens the certificate
when a `bounds_ctx`-validated bound actually carries nonzero slack.

**Test pattern to copy:** no NEW test file needed — extend `test_planning_hardening.jl`'s
or `test_planning_benders.jl`'s existing α-bound regression style (search for the T=8
finding referenced in `build_master`'s own docstring, line 592/623) with one case where a
`bounds_ctx`-validated bound carries nonzero `lb_slack` and confirm the reported `gap`
after this fix is `<= tol` using the WIDENED formula (would have falsely read `> tol`
under the UN-widened formula on a tight enough fixture) — or add a narrow unit test
directly against `_accepted_lb_slack`/`converged_at`'s formula in isolation, mirroring
`test_planning_benders_integer.jl`'s own standalone `_converged_now` replication pattern
(lines 67-81).

### `test/test_planning_nash.jl` — new interior-cap fixture + probe + VE tests (BILEV-06/06b)

**Analog:** the file's own existing corner-cap control test (lines 257-325) and probe
tests (lines 622-767) — copy the EXACT structure (fixture construction inline per
`@testitem`, `tags = [:planning]`, `setup = [Phase6Fixtures, ToyDeviceFixture]`).

**Fixture-construction pattern to copy** (lines 262-289, change only `x_inv_max`):
```julia
shared = build_shared_transmission(;
    N = 2, T = 1, corridor_cap = 2.0,
    x_inv_max = [1.0, 1.0],   # BILEV-06a: interior cap, was [0.3, 0.3] for the control
    c_inv = [1.0, 1.0], c_op = [[0.5], [0.5]],
)
dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
spec = (; feeder = Phase6Fixtures.two_bus_feeder(), pf = LinDistFlow(),
    aggregators = [agg], λ₀ = [4.0],
    master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0))
specs = [spec, spec]
```

**Derivation-comment pattern to copy** (lines 242-255 — "HAND-DERIVED EQUILIBRIUM" header
comment immediately above the testitem): document the analytic GNE interval `x_inv_1 ∈
[0, 0.7]`, `x_inv_2 = 0.7 − x_inv_1`, `z_1 ≈ z_2 ≈ 0.7` beside the new testitem, exactly as
the existing control fixture documents its own unique equilibrium derivation.

### `test/test_planning_nash_integer.jl` (new) or appended section — N>1 integer Nash + brute force + cycling (BILEV-07)

**Analog:** `test/test_planning_benders_integer.jl` (whole file, 135 lines) — single-
distributor integer smoke-test structure (`build_master_integer` + `solve_stackelberg!`
with `master = imaster, master_kwargs = NamedTuple()`, lines 94-121) generalizes directly
to `run_nash!`'s new `integer` kwarg per distributor.

**Pattern to copy for the N=2 brute-force certification** (per-player univariate sweep,
NOT full joint grid — RESEARCH.md's own cost/correctness argument): hold the OTHER
distributor's `(x_inv_j, z_j)` pinned at the reported equilibrium, enumerate `2^K` lattice
points for distributor `i` via `corner_recourse` (same function the production LL-cut path
already calls, `benders.jl:238`), confirm none achieves a strictly lower cost.

**Cycle-detection pattern to copy:** `master_integer.jl`'s own `visited::Dict{Vector{Int},
Vector{Float64}}` field (lines 79-105, struct field 120) — mirror its exact-equality,
no-tolerance dictionary-lookup idiom for `run_nash!`'s NEW outer-sweep cycle check (a
`Dict{Vector{Int}, Int}` mapping the concatenated per-distributor `b` state to the sweep
index first seen), never a tolerance-based residual comparison (binaries are exact).

## Shared Patterns

### Fail-loud guards-before-build/solve
**Source:** every `build_*`/`run_nash!`/`add_*_cut!` function project-wide (e.g.
`master.jl:540-556`, `nash.jl:393-481`, `master_integer.jl:170-176`)
**Apply to:** every new/modified function in this phase — `ArgumentError` for malformed
caller input (naming the offending value), `error(...)` for a detected invariant
violation (e.g. `add_ll_cut!`'s new `Q_ν ≥ L` check), BEFORE any `@variable`/`@constraint`/
solve call.
```julia
T >= 1 || throw(ArgumentError("build_master_integer needs T >= 1, got T=$T"))
```

### Build-once, re-solve via `Parameter`/bound mutation, never rebuild
**Source:** `coupling.jl`'s `update_coupling!`/`write_back!` (lines 282-333), `master.jl`'s
cut-append idiom (never rebuilds `model`)
**Apply to:** `solve_variational_equilibrium` (build ONE monolithic model, solve ONCE — no
loop); any new cut function in `master_integer.jl` (append `@constraint` rows, never touch
existing ones).

### Opt-in `bounds_ctx` validation (BILEV-05 lineage)
**Source:** `master.jl`'s `build_master`, lines 495-527 (the "Design decision" paragraph
explicitly stating every pre-existing call site stays byte-identical)
**Apply to:** `build_master_integer`'s new `bounds_ctx` keyword — MUST be opt-in; every
existing `test_planning_benders_integer.jl`/`test_planning_certification_integer.jl` call
site that passes explicit `Real` bounds and omits `bounds_ctx` must remain unchanged.

### Never-swallow / never-average honesty gates
**Source:** `run_nash_probe`'s own header comment (lines 666-690) — "NO try/catch AROUND
run_nash!, BY DESIGN"; spread computed as MAXIMUM pairwise distance, never mean/variance
**Apply to:** the new cycle-detection error (report the full cycle, never a generic
"exhausted" message); the brute-force deviation check (assert, don't average over corners).

## No Analog Found

None — every file in this phase's scope has a direct, exact in-repo analog (this phase is
scoped as extension/generalization of Phases 13/24/29/30 patterns, confirmed by
RESEARCH.md's own "Don't Hand-Roll" table: joint-model VE, cut validity, bound derivation,
and cycle bookkeeping machinery all already exist somewhere in `src/planning/`).

## Docs Refresh Reference (BILEV-08) — exact stale passages to replace

### `docs/writeups/stackelberg_vs_psr_n1n2.typ`
- **Lines 173-189** (`== Extensão inteira — problemas (8)-(9)`): every row currently reads
  "Não implementado (`INT-STRETCH`)" and line 189 states "Nenhuma variável binária/inteira
  existe em lugar algum de `src/planning/` hoje" — FALSE since Phase 24. Remap (8a)-(9e)
  onto `master_integer.jl`'s actual `build_master_integer`/`add_ll_cut!`
  Laporte-Louveaux-cut construction; keep "Desvio deliberado" framing for the PSR note's
  own Lagrangian-relaxation method (this project uses LL integer L-shaped cuts, not
  Lagrangian dual decomposition), but change "Não implementado" to "Implementado (Fase
  24/31)".
- **Lines 205-221** (`= Equilíbrio de Nash multi-distribuidor <sec-nash>`): add (a) a note
  that Gauss-Seidel converges to A generalized Nash equilibrium, not necessarily unique
  (cite this phase's own BILEV-06 fixture), (b) a new subsection on
  `solve_variational_equilibrium` and what it certifies, (c) a note that `run_nash!` now
  accepts an `integer` kwarg for N>1 integer investment (BILEV-07).
- **Line 237** (`Resumo de desvios deliberados` bullet): same "genuinamente não
  implementada" fix, cite Phase 24/31.

### `docs/writeups/modelo_stackelberg_dso_unico.typ`
No existing taxonomy section (headings are: Conjuntos e índices, Variáveis de decisão, O
problema bilevel completo, Como Benders resolve, Resultado, Notas de implementação — lines
36-181). Add a NEW section (e.g. `= Taxonomia dos variantes de planejamento`), styled after
`stackelberg_vs_psr_n1n2.typ`'s own equivalence-table convention (lines 209-217,
`#table(columns: ..., align: ..., stroke: 0.4pt + gray, [*Eq.*], [*Significado*], ...)`),
with rows for `solve_stackelberg!` (integrated, Benders-decomposed — cite
`test_planning_benders.jl`/`test_planning_goldens.jl`), `solve_bilevel!`/`build_bilevel_kkt`
(genuine bilevel — cite `test_planning_bilevel.jl`), and `run_nash!`/
`solve_variational_equilibrium` (shared-constraint GNE/VE — cite `test_planning_nash.jl`),
each citing its backing function AND test file per CONTEXT.md's requirement, plus one line
on `BendersMasterInteger` (usable via `master=` in both the first and third rows) and the
Phase-30 `inexact_policy` policy (applies to all three via `solve_stackelberg!`).

### Documenter docstrings
- `solve_stackelberg!` (`benders.jl:805-830`, the existing "Honest relabelling" paragraph)
  — add a short pointer to `run_nash!`/`solve_variational_equilibrium` for the N>1
  shared-constraint case; update the `master=` paragraph (lines 876-884) to mention
  `BendersMasterInteger`'s own new `bounds_ctx` support instead of leaving it unqualified.
- `solve_bilevel!` (`bilevel_kkt.jl:683-728`) — add a short cross-reference to the new
  taxonomy table in `modelo_stackelberg_dso_unico.typ`.
- `run_nash!` (`nash.jl:270-380`) / new `solve_variational_equilibrium` — add the
  GNE-multiplicity caveat and the new `integer` kwarg's full contract, mirroring the
  existing `inexact_policy` kwarg's own documentation style in the SAME docstring (already
  present, lines 391-392 area).
- **Documenter wiring:** `docs/src/api.md`'s `## Planning Layer` `@autodocs` block (lines
  132-147) already lists `"planning/nash.jl"` and `"planning/master_integer.jl"` — placing
  `solve_variational_equilibrium` inside `nash.jl` (as recommended above) and exporting it
  means ZERO `api.md` edits are needed; only if it instead lands in a new file would
  `api.md`'s `Pages` list need a new entry.

## Metadata

**Analog search scope:** `src/planning/*.jl` (nash.jl, coupling.jl, master.jl,
master_integer.jl, benders.jl, bilevel_kkt.jl — all read in full or targeted-section),
`test/test_planning_nash.jl` (full), `test/test_planning_benders_integer.jl` (full),
`test/test_planning_noninteger.jl` (full), `test/fixtures_planning_ieee13_short.jl`
(targeted), `docs/writeups/*.typ` (targeted), `docs/src/api.md` (targeted).
**Files scanned:** 12
**Pattern extraction date:** 2026-10-01

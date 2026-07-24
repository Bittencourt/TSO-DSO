# Phase 12: Cut-Store & Benders Master Robustness Hardening - Pattern Map

**Mapped:** 2026-07-22
**Files analyzed:** 7 (3 modified existing, 1 new struct file, 1 new test file, 2 extended test files)
**Analogs found:** 7 / 7 (all have a strong analog; one — the plotting helper — is a
role-match that CONTEXT.md explicitly makes conditional/deferred)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `src/planning/trace.jl` (new, or inline `BendersTrace` in `benders.jl`) | model (diagnostics ledger) | event-driven / batch (per-iteration append) | `src/admm/residuals.jl` (`AdmmResiduals`) | role-match, DELIBERATELY divergent data flow — see Pitfall block below |
| `src/planning/benders.jl` (modify: wire `BendersTrace`, extend return, IN-01/02/03/06 cleanups) | controller (outer-loop orchestrator) | event-driven / iterative request-response | itself (existing `solve_stackelberg!`, this file) + `src/admm/solve_admm.jl`'s `record!`/`converged`/return-NamedTuple loop idiom | exact (self) / role-match (solve_admm.jl for the "instrument-then-return" wiring) |
| `src/planning/master.jl` (modify: possible cut-store instrumentation hooks) | service (build-once JuMP model + persistent cut store) | CRUD (append-only cut rows) | itself (existing `add_optimality_cut!`/`add_feasibility_cut!`) | exact (self) |
| `src/planning/follower.jl` (modify: IN-06 Farkas `v > 0` guard) | service (build-once JuMP model) | request-response | itself (existing `solve_follower!` finiteness guard, line 201) | exact (self) |
| `src/diagnostics/plots.jl` (NOT modified unless planner opts in) | utility (plotting stub / weakdep seam) | transform | itself — pattern to *copy the shape of*, only if a `BendersTrace` plotting helper is added | role-match, conditional per CONTEXT.md |
| `test/test_planning_hardening.jl` (new) | test | batch / load-test + edge-case request-response | `test/test_planning_master.jl` (edge-case testitem shape) + `test/test_planning_checkpoint.jl` (`with_tempdir`/round-trip idiom) + `test/test_ieee123_admm.jl` (iteration-count/scale assertion idiom) | exact (master/checkpoint) + role-match (load-test) |
| `test/test_planning_benders.jl` / `test/test_planning_master.jl` (extend) | test | request-response | themselves (existing testitems in the same files) | exact (self) |

## Pattern Assignments

### `src/planning/trace.jl` (new struct file) — `BendersTrace`

**Analog:** `src/admm/residuals.jl` (`AdmmResiduals`)

**Why this is the right analog (role):** it is the ONLY existing "pure data / bookkeeping,
no JuMP, no solves" convergence ledger in the codebase — mutable struct, a `record!`-style
append function, a `converged`-style query predicate, and an `export` list at the bottom of
the file. `BendersTrace` should copy this *shape*, not its *content*.

**Imports pattern** — `src/admm/residuals.jl` has NO `using` block at all (JuMP-free by
design, RESEARCH Pattern 5/threat T-07-01). `BendersTrace` should copy this: no `using JuMP`
in `trace.jl` — it stores only primitive `Float64`/`Int`/`Symbol`/`String` fields, never a
`VariableRef` or `Model`.

**Struct + constructor pattern** (`src/admm/residuals.jl` lines 63–99):
```julia
mutable struct AdmmResiduals
    N::Int
    T::Int
    primal_trace::Vector{Float64}
    dual_trace::Vector{Float64}
    rho_trace::Vector{Float64}
    eps_pri_trace::Vector{Float64}
    eps_dual_trace::Vector{Float64}
    price_gap_trace::Vector{Float64}
    iters::Int
end

AdmmResiduals(N::Integer, T::Integer) = AdmmResiduals(
    Int(N), Int(T), Float64[], Float64[], Float64[], Float64[], Float64[], Float64[], 0,
)
AdmmResiduals() = AdmmResiduals(0, 0)
```
Copy the "empty-vectors + `iters`/row-count field" shape, the two-arg-sized + zero-arg
convenience constructors, and the doc-comment convention of naming every trace field's
physical meaning.

**Sequential-append guard pattern** (lines 101–107, 120–139):
```julia
@inline function _assert_sequential(res::AdmmResiduals, k::Integer)
    expected = res.iters + 1
    k == expected ||
        throw(ArgumentError("record!: expected sequential iteration $expected, got k=$k"))
    return nothing
end

function record!(res::AdmmResiduals, k::Integer, primal::Real, dual::Real, ρ::Real,
                  ε_pri::Real, ε_dual::Real, price_gap::Real)
    _assert_sequential(res, k)
    push!(res.primal_trace, abs(float(primal)))
    ...
    res.iters += 1
    return res
end
```
`BendersTrace`'s `push!` (per CONTEXT.md's proposed API name) should copy this
fail-loud-on-skipped/duplicate-iteration guard — Benders' `k` is exactly the same kind of
monotonically-increasing iteration counter.

**Query-predicate pattern** (lines 168–192):
```julia
function converged(res::AdmmResiduals, ε_pri::Real, ε_dual::Real)
    res.iters == 0 && return false
    return last(res.primal_trace) <= ε_pri && last(res.dual_trace) <= ε_dual
end
```
`BendersTrace.is_converged` (or similar) should copy the "empty ledger ⇒ false" guard and
the "read the LAST recorded row" idiom — but see the Pitfall block below: the *predicate
itself* must be `(UB - LB) / max(1, |UB|) <= tol`, structurally incapable of being confused
with a residual-norm test.

**Export pattern** (line 194): `export AdmmResiduals, record!, converged` — one line at file
end. `BendersTrace`'s file should do the same: `export BendersTrace, push!, is_converged, ...`
(module-qualify `push!` per planner's discretion since it overloads `Base.push!` or names a
distinct function — check whether `AdmmResiduals`'s `record!` deliberately avoided
overloading `Base.push!`; if `BendersTrace` instead overloads `push!`, add an explicit
`import Base: push!` at file top, since `AdmmResiduals` has no such precedent to copy).

**PITFALL — WHAT NOT TO COPY (per CONTEXT.md decision + roadmap criterion 2, PATTERNS.md
Pitfall 7 from Phase 11):** `AdmmResiduals`/`converged` is a **dual-ascent residual-based
stopping criterion**: TWO independent norms (`primal_trace`, `dual_trace`) each compared to
their OWN per-unit threshold (`eps_pri_trace`/`eps_dual_trace`), with NO notion of an
upper/lower bound or a "gap". `BendersTrace` records a **relative UB/LB gap** — ONE
scalar quantity per iteration, not two residual norms — because Benders bounds a single
primal problem from above (incumbent UB) and below (relaxed master LB); there is no
"consensus violation" to measure. Do NOT:
  - name a field `primal_trace`/`dual_trace` on `BendersTrace` (these terms are ADMM-specific
    and would mislead a reader that Benders has a primal/dual residual pair);
  - give `BendersTrace` an `ε_pri`/`ε_dual` pair — the correct field is a single `tol`
    (already the `solve_stackelberg!` keyword, `src/planning/benders.jl` line 117);
  - reuse the name `converged` for the predicate if it collides on dispatch ambiguity with
    `AdmmResiduals`'s own `converged(res, tol)` 1-tol-arg method (line 189) — that method
    already exists for a *different* struct type, so Julia's multiple dispatch technically
    disambiguates by argument type, but CONTEXT.md's guardrail is about conceptual (not just
    type-level) confusion; consider `is_converged` (CONTEXT.md's own suggested name) to make
    the distinction unmistakable even to a reader skimming call sites.
  - Per-iteration row suggested shape (Claude's discretion per CONTEXT.md): a `NamedTuple`
    per row — `(; iter, LB, UB, gap, cut_type, subproblem_statuses, retry_count, solve_time)`
    — pushed into a `Vector{NamedTuple}`, OR six/seven parallel `Vector{T}` fields mirroring
    `AdmmResiduals`'s parallel-vector layout. Either is consistent with the "cheap NamedTuple
    rows, always-on" decision; parallel vectors are more consistent with the `AdmmResiduals`
    analog's own layout and make an eventual CairoMakie plot trivial (one field = one Y
    series, exactly how `plot_convergence` consumes `primal_trace`/`dual_trace`).

---

### `src/planning/benders.jl` (modify: wire `BendersTrace`, extend return, IN-01/02/03/06)

**Analog (self):** the existing `solve_stackelberg!`, this file, lines 109–216.
**Analog (wiring idiom):** `src/admm/solve_admm.jl`'s own "build ledger before the loop →
`record!` each iteration → check convergence off the ledger → return the ledger in the
NamedTuple" shape.

**Existing boundary-guard pattern to EXTEND (IN-02/IN-03)** (`benders.jl` lines 121–126):
```julia
T >= 1 || throw(ArgumentError("solve_stackelberg! needs T >= 1 (got T=$T)"))
max_iter >= 1 || throw(
    ArgumentError("solve_stackelberg! needs max_iter >= 1 (got max_iter=$max_iter)"),
)
length(λ₀) == T || throw(ArgumentError("λ₀ has length $(length(λ₀)), expected T=$T"))
```
IN-02's fix (`isfinite(tol) && tol > 0`) and IN-03's fix (`max_iter <= 99_999`, citing
`checkpoint.jl`'s 5-digit filename contract at line 49) both slot into this SAME guard
block, in the SAME "one line, one `ArgumentError` naming the offending value" style —
copy the existing three lines' shape exactly, do not introduce a different guard idiom.

**Ledger-before-the-loop pattern to COPY from `solve_admm.jl` line 181** (`AdmmResiduals(N, T)`
built once, before `for k in 1:maxiter`): `benders.jl`'s loop currently starts (lines
135–143):
```julia
UB = Inf
y_best = NaN
z_best = fill(NaN, T)
gap = NaN
for k in 1:max_iter
```
`trace = BendersTrace(...)` (or equivalent zero-arg constructor) should be built HERE,
alongside `UB`/`y_best`/`z_best`/`gap` — same "accumulator state initialized immediately
before the loop" convention already used in this exact function.

**Per-branch instrumentation points** — the loop already has TWO exit branches that need a
`push!`/`record!` call, mirroring `solve_admm.jl` line 276's single `record!` call site:
  - feasibility branch (`benders.jl` lines 157–165): after
    `checkpoint_iteration!((; k, LB = lb_res.LB, UB, gap = NaN, z_k = lb_res.z, feasible = false), k; dir = checkpoint_dir)`
    and before `continue` — record a `BendersTrace` row with `cut_type = :feasibility`,
    `gap = NaN` (mirrors the existing `checkpoint_iteration!` call's own `gap = NaN` for this
    branch, IN-01's own observation that this is the "stale gap" branch), plus whatever
    `subproblem_statuses`/`retry_count`/`solve_time` fields are captured (see `solve_with_retry!`
    integration note below).
  - optimality branch (`benders.jl` lines 167–207): after `gap = (UB - lb_res.LB) / max(1, abs(UB))`
    (line 184) and before/alongside the existing `checkpoint_iteration!` call (lines
    186–190) — record a `BendersTrace` row with `cut_type = :optimality`, the real `gap`.

**IN-01 fix pattern** (stale gap in the exhaustion message, `benders.jl` lines 210–213):
```julia
error(
    "solve_stackelberg!: exhausted $max_iter iteration(s) without converging " *
    "(last gap=$gap, tol=$tol) — refusing to silently return a non-converged result",
)
```
Once `trace` exists, this message can read the trace's LAST row instead of the loop-local
`gap` variable (which, per IN-01, can be stale/NaN if the final iterations were all
feasibility branches) — e.g. report `UB`/`LB` alongside, or the last non-NaN gap row, per
the REVIEW's own suggested fix. Copy the existing `error(...)` string-interpolation format
(D-10's "name the exhausted count + last observed gap" convention) — do not switch to a
different exception style.

**IN-06 fix pattern (in `follower.jl`, consumed by `benders.jl`'s feasibility branch)** —
`follower.jl` line 201's existing finiteness guard:
```julia
isfinite(v) && all(isfinite, u) || error(
    "solve_follower!: HiGHS returned a non-finite Farkas certificate " *
    "(v=$v, u=$u) — refusing to emit a feasibility cut from it",
)
```
IN-06's fix extends this to `isfinite(v) && v > 0 && all(isfinite, u) || error(...)` — SAME
guard-then-error shape, just widening the boolean condition and the error string's implicit
claim (a `v <= 0` certificate is als
o "refus[ed]", update the message body accordingly).
This is a one-line, in-place change to an EXISTING guard — do not add a second/parallel
guard function.

**Return-NamedTuple extension pattern** (`benders.jl` lines 196–206, and `solve_admm.jl`
lines 435–443 for the "ledger is just another NamedTuple field" convention):
```julia
return (;
    y = y_best, z = z_best, UB, LB = lb_res.LB, gap, iters = k,
    oracle, follower, master,
)
```
Add `trace` as one more field — additive, non-breaking, exactly how `solve_admm` appends
`residuals = residuals` to its own return tuple (`solve_admm.jl` line 440) alongside
`iters = residuals.iters`. Follow that same convention: also expose a convenience
`iters = k` (already present) rather than only nesting inside `trace`.

**INFRA-03/D-08/D-09 solve-with-retry integration for trace's `retry_count`/`subproblem
statuses` fields:** `solve_with_retry!` (`src/planning/retry.jl`) does not itself return an
attempt count — it only `@warn`s per escalation (line 147) and returns `assert_solved!`'s
result on success or raises on exhaustion. If `BendersTrace` wants a `retry_count` per
iteration, `solve_with_retry!`'s signature/return would need extending (out of this file,
but flagged here since `master.jl`'s `solve_master!` is the call site that would need to
plumb it through) — OR the trace can settle for recording only `termination_status(master.model)`
post-solve (always queryable, no signature change needed) as the "subproblem status" field,
which is the CHEAPER, NO-NEW-DEPENDENCY option consistent with "always-on, cheap
NamedTuple rows."

---

### `src/planning/master.jl` (modify: possible cut-store instrumentation hooks)

**Analog (self):** `add_optimality_cut!`/`add_feasibility_cut!`, this file, lines 147–242.

**Existing finiteness-guard-then-append pattern** (lines 161–186, optimality cut):
```julia
isfinite(cost_k) ||
    throw(ArgumentError("add_optimality_cut!: cost_k must be finite, got $cost_k"))
all(isfinite, grad_k) || throw(
    ArgumentError("add_optimality_cut!: grad_k contains a non-finite entry: $grad_k"),
)
all(isfinite, z_k) ||
    throw(ArgumentError("add_optimality_cut!: z_k contains a non-finite entry: $z_k"))

α = epigraph === :op ? master.α_op : master.α_x
@constraint(master.model, α >= cost_k + sum(grad_k[t] * (master.z[t] - z_k[t]) for t in 1:(master.T)))
push!(master.cuts, (; kind = :optimality, epigraph, cost_k, grad_k = Vector{Float64}(grad_k), z_k = Vector{Float64}(z_k)))
return master
```
Any cut-store instrumentation hook (e.g. a `cuts_added` counter, or logging cut-store growth
into `BendersTrace` from the CALLER side in `benders.jl`) should read `length(master.cuts)`
after each `add_*_cut!` call — `master.cuts` is ALREADY the append-only bookkeeping log
(field doc, lines 53–55: "a bookkeeping log of every cut appended ... not consumed by
`solve_master!` itself"). The natural hook point is in `benders.jl`'s loop, immediately
after each `add_optimality_cut!`/`add_feasibility_cut!` call, reading
`length(master.cuts)` into the `BendersTrace` row — NOT a new mutation method on
`BendersMaster` itself (the struct's existing contract is "rows are ADDED rather than
coefficients mutated", file header lines 12–14; do not add a NEW public mutator, reuse the
existing `cuts` field as a read-only instrumentation source).

**Duplicate-Farkas-cut handling (Claude's discretion per CONTEXT.md)** — if a cheap dedup is
chosen, the natural insertion point is inside `add_feasibility_cut!` (lines 209–242), BEFORE
the `@constraint` call, checking `any(c -> c.kind == :feasibility && c.v_k ≈ v_k && c.u_k ≈ u_k for c in master.cuts)` (or a hash-based check) — mirroring the EXISTING finiteness-guard
placement (guard-then-append, never guard-after). If tolerating redundant rows instead
(the simpler option), no code change is needed here at all — only a test + doc note, per
CONTEXT.md's "as long as the store stays valid and the behavior is documented + tested."

---

### `test/test_planning_hardening.jl` (new)

**Analog 1 (edge-case testitem shape):** `test/test_planning_master.jl`, e.g. the
finiteness-guards testitem (lines 109–127):
```julia
@testitem "planning master: finiteness guards — NaN/Inf cut inputs are rejected loudly BEFORE touching the model (WR-03)" tags =
    [:planning] begin
    using TSODSO
    using JuMP: num_constraints

    master = build_master(; T = 1, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)
    nc0 = num_constraints(master.model; count_variable_in_set_constraints = true)

    @test_throws ArgumentError add_optimality_cut!(master, :op, NaN, [2.0], [1.0])
    ...
    @test num_constraints(master.model; count_variable_in_set_constraints = true) == nc0
    @test isempty(master.cuts)
end
```
Copy this "build once → snapshot a size/count → attempt N degenerate inputs → assert the
store is UNCHANGED + still empty/valid" shape for the near-boundary-`z`, zero-volume-corridor,
and repeated-Farkas-cut edge cases (CONTEXT.md's three named edge cases). The "assert LB
stays monotone non-decreasing across the episode" assertion should read `master.cuts` /
re-solve `solve_master!` across iterations and assert `LB[k+1] >= LB[k] - tol_slack`,
mirroring how `test_planning_benders.jl`'s own end-to-end test reads `result.LB`/`result.gap`
(lines 67–83).

**Analog 2 (hermetic tempdir + checkpoint round-trip idiom):**
`test/test_planning_checkpoint.jl` lines 10–23 and 70–118 — the `Phase8Fixtures.with_tempdir`
wrapper, and specifically the CR-02 "resume from highest-numbered checkpoint" pattern:
```julia
@testitem "planning checkpoint: round-trip through JLD2" tags = [:planning] setup =
    [Phase8Fixtures] begin
    using TSODSO
    Phase8Fixtures.with_tempdir() do dir
        path = TSODSO.checkpoint_iteration!((; z = [1.0, 2.0], cost = 3.5), 1; dir = dir)
        @test isfile(path)
        resumed = TSODSO.resume_from_checkpoint(dir)
        @test resumed.iteration == 1
        ...
    end
end
```
For the load-test's "resume from iter >= 50 reproduces the same trajectory" assertion:
run `solve_stackelberg!` to completion (or interrupt logic not needed — since
`solve_stackelberg!` checkpoints every iteration unconditionally, lines 159–163/186–190),
then call `resume_from_checkpoint(dir)` directly and assert
`resumed.iteration >= 50 && resumed.state.z_k == <the z at that iteration from the trace>`
— reusing `mktempdir() do dir ... end` exactly as `test_planning_benders.jl` already does
(lines 53, 109, 154), NOT `Phase8Fixtures.with_tempdir` (that helper is used by the
lower-level `checkpoint.jl`-only tests; the higher-level Benders end-to-end tests in
`test_planning_benders.jl` already use plain `mktempdir() do dir` directly — copy THAT
convention since `test_planning_hardening.jl` is testing the end-to-end loop, not the
checkpoint primitive in isolation).

**Analog 3 (forcing many iterations / scale-target assertion idiom):**
`test/test_ieee123_admm.jl` lines 20–80 — the general shape of "build a harder fixture on
purpose, assert an iteration COUNT bound, assert results are still correct" — e.g.
```julia
res = solve_admm(feeder, ConvexBranchFlow(), aggs; T = Th, λ₀ = λ₀, ρ = ..., maxiter = 300, ...)
@test res.iters < 300   # converged before the fail-loud cap
```
Copy the "assert `iters` is comfortably under the fail-loud cap, not merely that it didn't
throw" idiom for the ~50–100-iteration load test — e.g.
`@test 50 <= result.iters <= 100` (or similar), tightening `tol` on the toy fixture (per
CONTEXT.md's `Claude's Discretion` on fixture parameterization) rather than building an
IEEE-13-scale oracle (CONTEXT.md explicitly forbids the full SOCP oracle here).

**Tag/name-filter convention (existing, copy verbatim):** every `@testitem` in this new file
must carry `tags = [:planning]` and a NAME containing `"planning"` and `"hardening"` — the
occursin-filter convention documented at the top of every existing
`test_planning_*.jl` file (e.g. `test_planning_master.jl` lines 9–10: "Items tagged
`[:planning]`, names contain `"planning"` and `"master"` (occursin filter convention,
mirrors test_planning_follower.jl)"). If the load-test item risks pushing the `:planning`
quick-run over budget (~2 min, per `12-VALIDATION.md`), CONTEXT.md leaves a `[:slow]`-style
extra tag as Claude's discretion — no existing file in the repo currently uses a `:slow` tag
(searched `test/*.jl`; only `:planning`, `:admm`, `:phase7`, `:dso`, `:welfare`, etc. tag
combinations exist today, `[:admm, :phase7]` at `test_ieee123_admm.jl` line 21 being the
closest precedent for a two-tag item) — if introduced, mirror that two-tag-array syntax
(`tags = [:planning, :slow]`) exactly.

---

### `test/test_planning_benders.jl` / `test/test_planning_master.jl` (extend)

**Analog:** themselves — no external analog needed; extend using the SAME testitem/fixture
conventions already present in each file (see full excerpts read above): `setup =
[Phase6Fixtures, ToyDeviceFixture]` for `benders.jl` tests (the toy Stackelberg fixture,
`test_planning_benders.jl` lines 42–51), plain `build_master(...)` calls with no setup module
for `master.jl` tests (`test_planning_master.jl` lines 18–42). New `BendersTrace`-focused
testitems should assert on `result.trace` (added return field) the same way the existing
CR-01 incumbent-regression testitem (`test_planning_benders.jl` lines 74–83) asserts on
`result.master.cuts` and re-solves subproblems to check an identity — i.e., re-derive an
expected trace-row count / monotone-LB property analytically or from `result.iters`, never
hard-code a "should be N" magic number without derivation (this file's own header comment,
lines 23–40, models exactly this "re-derive, don't blindly assert" discipline).

---

## Shared Patterns

### Fail-loud `ArgumentError` boundary guards (applies to `trace.jl`'s constructor/`push!`,
`benders.jl`'s extended guards, and any new `master.jl` hook)
**Source:** `src/planning/master.jl` lines 92–96 / `src/planning/benders.jl` lines 121–126
```julia
T >= 1 || throw(ArgumentError("build_master needs T >= 1, got T=$T"))
y_max > 0 || throw(ArgumentError("build_master needs y_max > 0, got $y_max"))
c_y >= 0 || throw(ArgumentError("build_master needs c_y >= 0, got $c_y"))
```
One guard per line, `||`-short-circuit, `throw(ArgumentError("<fn name>: <what> got <value>"))`
— applies verbatim to `BendersTrace`'s own constructor and `push!`/`record!` guards (e.g. a
non-monotone `iter` argument, mirroring `AdmmResiduals`'s `_assert_sequential`).

### WR-03 finiteness guards BEFORE mutating persistent state
**Source:** `src/planning/master.jl` lines 161–169 / `src/planning/follower.jl` lines
197–204 / `src/planning/checkpoint.jl` lines 46–53
```julia
isfinite(cost_k) || throw(ArgumentError("... must be finite, got $cost_k"))
all(isfinite, grad_k) || throw(ArgumentError("... contains a non-finite entry: $grad_k"))
```
Applies to: any `BendersTrace` row field that could receive `NaN`/`Inf` (e.g. `solve_time`,
`gap`) — guard BEFORE `push!`, mirroring "a NaN/Inf row appended ... is unremovable and
silently poisons every later" reasoning already baked into `master.jl`'s comments (lines
140–142).

### `solve_with_retry!` / direct-`optimize!` split (D-08/D-09, Amendment revision 1)
**Source:** `src/planning/retry.jl` (whole file) / `src/planning/follower.jl` lines 170–176
**Apply to:** `benders.jl`'s trace instrumentation must NOT change which calls are
retry-wrapped: `solve_master!`/`solve_planning_oracle!` remain gated by `solve_with_retry!`;
`solve_follower!` remains a DIRECT `optimize!` call. Any "subproblem status"/"retry count"
field on `BendersTrace` must be read AFTER these existing calls, never by inserting a NEW
wrapper around `solve_follower!`.

### Checkpoint-every-iteration, both branches (D-10)
**Source:** `src/planning/benders.jl` lines 157–165 and 186–190
**Apply to:** the trace `push!` call sites are the SAME two branches — feasibility (before
`continue`) and optimality (before the `gap <= tol` check) — so trace instrumentation and
checkpointing stay co-located, one per iteration, on both branches, exactly as T-11-06
already requires for `checkpoint_iteration!` alone.

### TestItems tag + name-filter convention
**Source:** every `test/test_planning_*.jl` file header comment
**Apply to:** `test_planning_hardening.jl` — `tags = [:planning]` (plus optional `:slow`,
Claude's discretion) and item names containing `"planning"` + `"hardening"`.

## No Analog Found

None — every file in scope has at least a role-match analog. The one CONDITIONAL item:

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `BendersTrace` plotting helper (only if added) | utility | transform | `src/diagnostics/plots.jl` is a real, usable analog (weakdep-extension stub pattern) IF the planner opts into it; CONTEXT.md defers this to Phase 14 unless the planner judges it cheap enough now. If added, copy `plots.jl`'s exact shape: a method-less generic function declared in core (`function plot_benders_trace end`), exported, with NO CairoMakie import in core, and the real method added only in `ext/TSODSOMakieExt.jl` (not read this session — out of scope unless planner opts in; locate via `Glob("ext/**/*.jl")` before writing it). |

## Metadata

**Analog search scope:** `src/admm/`, `src/planning/`, `src/diagnostics/`, `test/test_planning_*.jl`, `test/test_diagnostics_plot.jl`, `test/test_ieee123_admm.jl`, `test/fixtures_phase8.jl`, `.planning/phases/11-single-distributor-stackelberg-benders-certified/11-REVIEW.md`
**Files scanned:** 13 (7 source, 6 test/doc)
**Pattern extraction date:** 2026-07-22

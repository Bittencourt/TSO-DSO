# Phase 16: Reactive-Power (μ) Consensus - Pattern Map

**Mapped:** 2026-07-25
**Files analyzed:** 9 (3 src MODIFY, 6 test/script CREATE-or-MODIFY)
**Analogs found:** 9 / 9 (every file has a working, same-repo peer to mirror — this phase is
explicitly "reuse the peer mechanism exactly," per 16-RESEARCH.md's own "Don't Hand-Roll" table)

## CRITICAL naming constraint (read before touching any file below)

The bare identifier **`μ`/`mu` is ALREADY TAKEN** — it means ONLY the adaptive-ρ
residual-balancing band, threaded through:
- `src/admm/solve_admm.jl:58` — kwarg `μ::Real = 10.0` (Boyd §3.4.1 imbalance band, used at
  lines 320-330: `r̂ > μ * ŝ` / `ŝ > μ * r̂`)
- `src/admm/solve_admm.jl:128` — the kwarg default in the function signature
- `src/experiments/Scenario.jl:106,190,211` — struct field `μ::Float64 = 10.0`, golden-hash
  `savename`-serialized
- `src/experiments/run.jl:140` — `μ = s.μ` threads `Scenario.μ` into `solve_admm`
- `test/fixtures_phase7.jl:49` — `const MU = 10.0` (ASCII spelling of the same value)

**No file in this phase may bind a new value to bare `μ`, `mu`, or `MU`.** Use a DISTINCT
identifier for anything reactive-related:
- The JuMP coupling variable → `qag_dso` (no Greek letter needed — it's a variable, not a dual)
- The `decompose_dlmp` NamedTuple field → `reactive` (already unambiguous, no Greek letter needed)
- Any scalar/vector handle for the extracted price, if code needs one → `μq` or `mu_q`
  (research's suggestion) — **never bare `μ`**

This must be the FIRST thing verified in every diff below; it is REACT-03's Success Criterion #1.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|---------------|
| `src/admm/DsoOpt.jl` (MODIFY) | model-builder (JuMP SOCP subproblem) | CRUD (build-once, coefficient-mutate, re-solve) | itself — active-side `pag_dso`/`:balance_p` block in the SAME file | exact (self-mirror) |
| `src/admm/solve_admm.jl` (MODIFY) | orchestrator (ADMM outer loop) | event-driven (iterate/converge) | itself — `build_dso_opt(...)` call site + final `:balance_p` `assert_no_slack` block, SAME file | exact (self-mirror) |
| `src/models/welfare_solve.jl` (VERIFY, likely no change) | model-builder (centralized JuMP) | CRUD | itself — `:balance_q` registration already genuine (lines 228-234) | exact (already correct) |
| certificate for `:balance_q` (part of `solve_admm.jl`'s final block) | utility / gate | request-response (assert-and-throw) | `src/core/status.jl` `assert_no_slack` (existing function, reused verbatim — do NOT write a new one) | exact |
| `src/pricing/dlmp.jl` (MODIFY, `decompose_dlmp`) | service (pure post-processing/reporting) | transform (dual → priced NamedTuple field) | itself — `energy`/`loss`/`congestion`/`voltage` extraction in the SAME file/function | exact (self-mirror) |
| `test/test_admm_reactive.jl` (CREATE) | test | behavioral/regression | `test/test_admm_adaptive.jl` | exact (same RED-guard → behavioral-assert convention, same ADMM domain) |
| `test/test_dso.jl` (MODIFY) | test | behavioral/regression | itself — existing `@test haskey(dso.ctx.constraints, :balance_q)` assertions (lines 51, 123, 153) | exact (self-mirror) |
| `test/test_pricing_dlmp.jl` (MODIFY) | test | behavioral/regression | itself — existing 2-bus (`extract_dlmp` sign pin, lines 20-57) and IEEE-13 `decompose_dlmp` sum-to-price pin (lines 126-172) | exact (self-mirror) |
| flake-rate measurement script (CREATE, under `scripts/`) | utility / batch script | batch (repeated solve + tally) | `scripts/benders_toy.jl` (direct low-level model construction, no `Scenario`) + `src/experiments/materialize.jl`'s `build_feeder`/`build_population` exports | role-match (script), CRUD data flow differs (batch measurement, not a single solve) |

## Pattern Assignments

### `src/admm/DsoOpt.jl` (MODIFY) — promote `q_draw` constant to `qag_dso` coupling variable

**Analog:** the file's own existing ACTIVE-side block, lines 206-210 and 244-252 (self-mirror —
this is the literal template REACT-01 asks you to copy for reactive).

**Existing ACTIVE pattern to mirror** (`src/admm/DsoOpt.jl:206-210`):
```julia
    # (4a) ACTIVE load-node coupling: one variable per (load node, t), injected into :Rp[j].
    @variable(model, pag_dso[j = load_nodes, t = 1:T])
    for j in load_nodes, t in 1:T
        add_to_residual!(ctx, :Rp, j, t, pag_dso[j, t])
    end
```

**Existing REACTIVE pattern being REPLACED (conditionally)** (`src/admm/DsoOpt.jl:212-216`):
```julia
    # (4b) REACTIVE load-node CONSTANT draw (thesis 3.23), injected into :Rq[j]. A fixed
    # parameter (no μ dual-ascent — reactive is not a consensus quantity).
    for j in load_nodes, t in 1:T
        add_to_residual!(ctx, :Rq, j, t, q_draw[j][t])
    end
```

**Target shape** (matches 16-RESEARCH.md Pattern 1 verbatim, cite it in the PLAN — do not
re-derive): new kwarg `reactive_consensus::Bool = false` on `build_dso_opt`; when `true`,
allocate `@variable(model, qag_dso[j = load_nodes, t = 1:T])` and inject that into `:Rq[j]`
instead of the constant `q_draw[j][t]`; when `false` (default), inject `q_draw[j][t]` exactly
as today — BYTE-IDENTICAL default path (REACT-03). `:balance_q` registration itself
(lines 238-242) is UNCHANGED either way — it already closes at all N buses regardless of
whether the injected term is a constant or a variable.

**Constraint-registration pattern to mirror unchanged** (`src/admm/DsoOpt.jl:230-242`):
```julia
    # (4c) Close BOTH balances at ALL buses (root + every load node). Registered so the DADP
    # duals are recoverable (mirrors the centralized SOCP; ADMM welfare + duals then match).
    size(ctx.residuals[:Rp]) == (N, T) || error(
        "residual :Rp is $(size(ctx.residuals[:Rp])), expected ($N, $T) — an index escaped the feeder",
    )
    @constraint(model, balance_p[j = 1:N, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
    register_constraint!(ctx, :balance_p, balance_p)          # dual = λ_j (DADP)

    size(ctx.residuals[:Rq]) == (N, T) || error(
        "residual :Rq is $(size(ctx.residuals[:Rq])), expected ($N, $T) — an index escaped the feeder",
    )
    @constraint(model, balance_q[j = 1:N, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
    register_constraint!(ctx, :balance_q, balance_q)
```

**Struct field consideration:** `DsoOpt` (lines 69-79) currently has a `pag::P` field only for
the active coupling container. If the plan wants `qag_dso` retrievable post-solve the same way
`pag` is (for a test assertion or the certificate block in `solve_admm.jl`), add a field
(e.g. `qag::Union{Nothing,P}` defaulting `nothing` when `reactive_consensus=false`) — OR, simpler
and more additive, stash it in `ctx.meta[:qag_dso]` the way `p_import`/`q_import` are already
stashed (`ctx.meta[:p_import] = p_import` at line 203) — prefer the `ctx.meta` route since it
needs no struct-field schema change and mirrors an established convention.

**Objective note:** the research's minimal-scope recommendation is a one-shot dual read, NOT a
live μ-ascent — so `qag_dso[j,t]` needs NO new quadratic penalty term of its own in the
objective (unlike `pag_dso`, which carries `0.5·ρ·pag_dso²` at lines 247-252 because it is a
genuinely live-priced consensus variable). Pin `qag_dso[j,t] == q_draw[j][t]` directly if a
fixed-target equality is wanted, or simply inject it unconstrained and let `:balance_q` (an
equality across the WHOLE network) determine it — re-verify against 16-RESEARCH.md Pattern 1's
"pinned toward the still-fixed target `b_j`" wording before choosing; this is a planner-level
decision this PATTERNS.md flags but does not resolve.

---

### `src/models/welfare_solve.jl` (VERIFY only — likely NO diff)

**Analog:** itself. `:balance_q` is ALREADY a genuine equality, data-driven on `reactive =
haskey(ctx.residuals, :Rq)` (line 162), registered unconditionally when true (lines 228-234):
```julia
    if reactive
        size(ctx.residuals[:Rq]) == (Np, T) || error(
            "residual :Rq is $(size(ctx.residuals[:Rq])), expected ($Np, $T) — an index escaped the feeder",
        )
        @constraint(model, balance_q[j = 1:Np, t = 1:T], ctx.residuals[:Rq][j, t] == 0)
        register_constraint!(ctx, :balance_q, balance_q)
    end
```
The centralized path needs no `reactive_consensus` kwarg at all — its aggregator injection
(`Aggregator.contribute!`, called at line 180) is ALREADY a genuine JuMP-expression contribution,
not a hand-summed constant like the ADMM `DsoOpt`'s per-load-node `q_draw`. Confirm this by
reading `Aggregator.contribute!`'s `:Rq` write (not required to change) before writing the plan
task — the task here is a VERIFICATION task, not a code-change task.

---

### No-slack certificate for `:balance_q` (part of `src/admm/solve_admm.jl`'s FINAL block)

**Analog:** the file's own existing `:balance_p` certificate, `src/admm/solve_admm.jl:412-416`:
```julia
    let balance_p = dso.ctx.constraints[:balance_p]
        for j in 1:size(balance_p, 1), t in 1:size(balance_p, 2)
            assert_no_slack(dso.model, balance_p[j, t]; atol = 1e-6)
        end
    end
```
**Mirror exactly** for `:balance_q`, gated on `reactive_consensus == true` (do not run it
unconditionally — on the default `reactive_consensus=false` path the reactive draw is still a
constant and its slack-tolerance semantics are UNCHANGED from today, where the comment at
lines 408-411 explicitly documents it as "intentionally not gated... NOT published/load-bearing"):
```julia
    if reactive_consensus
        let balance_q = dso.ctx.constraints[:balance_q]
            for j in 1:size(balance_q, 1), t in 1:size(balance_q, 2)
                assert_no_slack(dso.model, balance_q[j, t]; atol = 1e-6)
            end
        end
    end
```
`assert_no_slack` itself is REUSED VERBATIM from `src/core/status.jl:79-94` — no new helper:
```julia
function assert_no_slack(model::Model, cref; atol::Real = 1e-6)
    obj = constraint_object(cref)
    lhs = value(obj.func)                 # AffExpr evaluated at the solution
    rhs = MOI.constant(obj.set)           # RHS for EqualTo / scalar sets
    residual = lhs - rhs
    if abs(residual) > atol
        error("""
              Hidden constraint slack detected — refusing to trust results:
                constraint : $(cref)
                lhs(value) : $(lhs)
                rhs        : $(rhs)
                residual   : $(residual)  (atol = $(atol))
              """)
    end
    return residual
end
```
Place the new block in `solve_admm.jl` directly AFTER the existing `:balance_p` block
(lines 412-416), inside the same final consolidation section (after `dres_final =
solve_dso!(dso, λ, a, ρf; check_exact = true, strict = false)` at line 392) — same section
comment block ("WR-01 PUBLISHED-PRIMAL CERTIFICATE") extended, not a new section.

Also thread `reactive_consensus::Bool = false` as a new `solve_admm` kwarg (mirroring the
existing kwarg list at lines 116-132) and pass it through to `build_dso_opt(feeder, aggregators,
T; ρ = ρf, λ₀ = λ₀, reactive_consensus = reactive_consensus)` at line 159.

---

### `src/pricing/dlmp.jl` (MODIFY `decompose_dlmp`) — add `reactive` field

**Analog:** the SAME function's existing energy/loss/congestion/voltage extraction pattern,
`src/pricing/dlmp.jl:165-261`.

**Gate to reuse verbatim** (`src/pricing/dlmp.jl:56-77`, called at the top of BOTH
`extract_dlmp` and `decompose_dlmp` — line 97 and line 172):
```julia
function _assert_priceable(ctx::ModelContext)
    haskey(ctx.constraints, :balance_p) || throw(
        ArgumentError(
            "extract_dlmp: ctx has no registered :balance_p — this is not a solved " *
            "welfare ModelContext (thesis eq. 3.31)",
        ),
    )
    if haskey(ctx.meta, :pf_vars) &&
       haskey(ctx.meta[:pf_vars], :l) &&
       !haskey(ctx.meta, :socp_maxgap)
        throw(
            ArgumentError(
                "extract_dlmp: refusing to price an UNGATED SOCP ctx — the PF-04 exactness " *
                "certificate `ctx.meta[:socp_maxgap]` is ABSENT while a squared-current `:l` " *
                "is present, so the SOC relaxation was never certified exact. ...",
            ),
        )
    end
    return nothing
end
```

**Existing `extract_dlmp` shape to mirror for a new `extract_reactive_dlmp`**
(`src/pricing/dlmp.jl:96-104`):
```julia
function extract_dlmp(ctx::ModelContext; bus = nothing, T = nothing)
    _assert_priceable(ctx)
    bp = ctx.constraints[:balance_p]          # bus × time ConstraintRef array (thesis 3.31)
    N, Tfull = size(bp)
    M = Float64[dual(bp[j, t]) for j in 1:N, t in 1:Tfull]
    bus === nothing && return M
    Tsel = T === nothing ? Tfull : Int(T)
    return M[bus, 1:Tsel]
end
```
Copy this shape for `:balance_q` (per 16-RESEARCH.md Pattern 2 — reproduced here verbatim as
the concrete diff, add a presence guard since a DC/active-only formulation has no `:balance_q`):
```julia
function extract_reactive_dlmp(ctx::ModelContext; bus = nothing, T = nothing)
    _assert_priceable(ctx)
    haskey(ctx.constraints, :balance_q) || throw(
        ArgumentError("extract_reactive_dlmp: ctx has no :balance_q -- this formulation has no " *
                      "reactive channel (e.g. DCPowerFlow); no reactive price exists to extract"),
    )
    bq = ctx.constraints[:balance_q]
    N, Tfull = size(bq)
    M = Float64[dual(bq[j, t]) for j in 1:N, t in 1:Tfull]
    bus === nothing && return M
    Tsel = T === nothing ? Tfull : Int(T)
    return M[bus, 1:Tsel]
end
```

**`decompose_dlmp`'s return NamedTuple to extend** (`src/pricing/dlmp.jl:251` and `:254-260`):
current:
```julia
    bus === nothing && return (; energy, loss, congestion, voltage, total)
    Tsel = T === nothing ? Tfull : Int(T)
    rows = 1:Tsel
    return (;
        energy = energy[bus, rows],
        loss = loss[bus, rows],
        congestion = congestion[bus, rows],
        voltage = voltage[bus, rows],
        total = total[bus, rows],
    )
```
Add `reactive = extract_reactive_dlmp(ctx)` (or `reactive[bus, rows]` in the bus-selected branch)
as a 6th field. **Do NOT sum it into `total`** — per 16-RESEARCH.md's explicit warning, `total`
remains the ACTIVE nodal price; `reactive` is a SEPARATE price signal, so the existing
sum-to-nodal-price HARD assertion at lines 231-249 (`energy[j,t] + loss[j,t] + congestion[j,t]
+ voltage[j,t] ≈ total[j,t]`) must stay a 4-term check — do not fold `reactive` into it.
Guard: if the ctx has no `:balance_q` (a DC formulation), either omit the `reactive` field
entirely or set it to a zero/`missing` placeholder — decide in the plan, but the existing
`decompose_dlmp` already REQUIRES `:cone`/`:vdrop`/`:cpydrop`/`:smax` (lines 173-181) which only
exist on `ConvexBranchFlow`, so a `:balance_q`-guard here is consistent with that existing
precedent (DC formulations already can't call `decompose_dlmp` at all).

**Confirmed safe (A4 in RESEARCH.md):** no test asserts a fixed field count/shape on
`decompose_dlmp`'s return (verified again in `test/test_pricing_dlmp.jl` reads below) — adding
a field is additive and safe.

---

### `test/test_admm_reactive.jl` (CREATE)

**Analog:** `test/test_admm_adaptive.jl` (full file read above) — copy its EXACT shape:
- File-header comment block naming the SEAM, the RED signal gate, and the CONTRACT pinned.
- `@testitem "..." setup = [Phase7Fixtures, Phase6Fixtures] tags = [:admm, :phase7] begin ... end`
  syntax, e.g.:
  ```julia
  @testitem "admm reactive: qag_dso coupling variable + certified :balance_q dual (reactive)" setup =
      [Phase6Fixtures, Phase4Fixtures] tags = [:admm, :reactive] begin
      using TSODSO

      # RED until this phase lands reactive_consensus.
      @test isdefined(TSODSO, :build_dso_opt)

      if isdefined(TSODSO, :build_dso_opt)
          feeder = Phase6Fixtures.two_bus_feeder()
          aggs = Phase6Fixtures.build_two_bus_aggregators(feeder)
          Th = Phase6Fixtures.T
          λ₀ = Phase6Fixtures.two_bus_lambda0()

          dso = build_dso_opt(feeder, aggs, Th; ρ = Phase6Fixtures.RHO_2BUS, λ₀ = λ₀,
                               reactive_consensus = true)
          @test haskey(dso.ctx.constraints, :balance_q)
          # ... assert qag_dso is a genuine JuMP variable container, not a constant Dict ...
      end
  end
  ```
- Item names MUST contain a substring the project's test filters select on — use `"reactive"`
  consistently (per the RESEARCH doc's own recommended filter
  `occursin("reactive", ti.name)`), mirroring how `test_admm_adaptive.jl` uses `"adaptive"`/
  `"rho"`/`"transit"` in its own item names (lines 23, 54, 111 of that file).
- Include a `reactive_consensus=false` (default) REGRESSION item asserting BYTE-IDENTICAL
  behavior to today — mirrors the "same (ε_abs, ε_rel, τ, μ...) config" scale-invariance item
  at `test/test_admm_adaptive.jl:54-109`, but here proving the DEFAULT flag value changes
  nothing (REACT-03's core regression guarantee).
- Include the "certificate" behavioral assert: `assert_no_slack` on `:balance_q` must NOT throw
  after a converged `solve_admm(...; reactive_consensus = true)` — a positive-path certificate
  test, not merely a `haskey` shape check.

---

### `test/test_dso.jl` (MODIFY)

**Analog:** the file's OWN existing assertions — `test/test_dso.jl:50-51` (2-bus build item):
```julia
    @test haskey(dso.ctx.constraints, :balance_p)
    @test haskey(dso.ctx.constraints, :balance_q)
```
and lines 122-123 / 152-153 (transit-relaxation items, same pattern repeated). Add a NEW
`@testitem` (or extend an existing one) that passes `reactive_consensus = true` to
`build_dso_opt` and asserts:
- `haskey(dso.ctx.constraints, :balance_q)` still true (unchanged)
- the reactive coupling container (`qag_dso`, wherever it's stashed — struct field or
  `ctx.meta[:qag_dso]`) exists and has shape `(length(load_nodes), Th)`, mirroring the EXISTING
  active-side shape assertion at line 45: `@test size(dso.pag) == (1, Th)`.
- The default (`reactive_consensus` omitted / `false`) path is BYTE-IDENTICAL — re-run the
  EXISTING 2-bus build item (lines 18-56) unmodified as the regression net; do not edit its
  assertions, only ADD new ones in new `@testitem`s.

---

### `test/test_pricing_dlmp.jl` (MODIFY)

**Analog:** the file's own 2-bus sign-pin item (`test/test_pricing_dlmp.jl:20-57`) and its
IEEE-13 `decompose_dlmp` sum-to-price item (lines 126-172, referenced via grep — same file).

**2-bus pin pattern to mirror** (lines 20-57, reproduced above in full) — add a hand-computed
reactive-price pin using the SAME lossless/uncongested/interior 2-bus fixture but with a
NON-ZERO `tanφ` (i.e., `φ < 1` on the `Aggregator`, per 16-RESEARCH.md's "Code Examples"
section) so the reactive requirement is analytically non-trivial:
```julia
d = decompose_dlmp(ctx)   # after adding the `reactive` field
@test d.reactive[2, t] ≈ <hand-derived KKT value>   # load bus, non-degenerate
@test d.reactive[1, t] ≈ 0.0 atol=1e-6              # root: q_import free-sign, zero-coeff ⇒ dual ≡ 0 (degenerate, per RESEARCH "Free slack, precisely located")
```
**Existing sum-to-price assertion pattern to mirror structurally, NOT extend** (lines 143-156,
generalized from the grep hits) — the existing 4-term check:
```julia
d = decompose_dlmp(ctx)
for f in (d.energy, d.loss, d.congestion, d.voltage)
    @test all(isfinite, f)
end
@test isapprox(
    d.energy[j, t] + d.loss[j, t] + d.congestion[j, t] + d.voltage[j, t],
    d.total[j, t];
    rtol = ...,
)
```
Add a PARALLEL, SEPARATE assertion block for `d.reactive` (finite, correct sign, degenerate at
the root) — do NOT insert `d.reactive` into the existing 4-term sum check (it is a DIFFERENT
price signal per RESEARCH's explicit warning above).

---

### Flake-rate measurement script (CREATE, under `scripts/`)

**Analog:** `scripts/benders_toy.jl` for the DrWatson/direct-construction convention (header +
`@quickactivate` + `projectdir` + inline model construction, NOT `Scenario`), plus
`src/experiments/materialize.jl`'s exported `build_feeder`, `build_price`, `build_population`
helpers for constructing a feeder/aggregator population WITHOUT touching `Scenario.jl`.

**Header/activation convention to copy** (`scripts/benders_toy.jl:1-33`, and identically
`scripts/demo_flexibility_plots.jl:1-37`):
```julia
# scripts/<name>.jl
#
# <one-paragraph purpose>
#
# Run:
#     julia --project=. scripts/<name>.jl
# <output description>

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using Printf

const OUT = projectdir("results", "<name>")
mkpath(OUT)
```

**Construction convention — use `build_feeder`/`build_population` (exported,
`src/experiments/materialize.jl:298`), NOT `Scenario`** (per the phase's explicit "do not touch
`Scenario.jl`" constraint — a script that calls `Scenario(...)` would still work for the
DEFAULT `reactive_consensus=false` path, but this script needs `reactive_consensus=true` on
`solve_admm`, which `Scenario`/`run_scenario` do NOT expose this phase — so call `solve_admm`
directly, mirroring how `scripts/demo_flexibility_plots.jl` builds a feeder/population directly
and calls `solve_admm(...)` itself for its "ADMM convergence diagnostics" section rather than
going through `run_scenario`):
```julia
# Build the SAME IEEE-13 population `run_scenario`/`Scenario` would, but call solve_admm
# directly so `reactive_consensus` (not yet a Scenario field, deliberately — REACT-03) can be
# passed through.
feeder = ieee13_modified()
# ... build aggregators via build_population / generate_profiles, mirroring materialize.jl ...

N_REPEATS = 20   # per 16-RESEARCH.md Pitfall 5 / Open Question 2 (N ≥ 20 recommended)

function count_failures(feeder, aggs; reactive_consensus::Bool)
    n_fail = 0
    for seed in 1:N_REPEATS
        try
            solve_admm(feeder, ConvexBranchFlow(), aggs; T = 24, λ₀ = ..., ρ = ...,
                       reactive_consensus = reactive_consensus, maxiter = 500)
        catch e
            n_fail += 1
            @warn "solve failed" seed reactive_consensus exception=e
        end
    end
    return n_fail
end

n_fail_off = count_failures(feeder, aggs; reactive_consensus = false)
n_fail_on  = count_failures(feeder, aggs; reactive_consensus = true)

@printf "reactive_consensus=false: %d/%d failures\n" n_fail_off N_REPEATS
@printf "reactive_consensus=true:  %d/%d failures\n" n_fail_on  N_REPEATS
```
Run this for BOTH the IEEE-13 (`ieee13_modified()`) and IEEE-123 (`ieee123_modified()`)
fixtures per the RESEARCH doc's explicit gating measurement requirement; write the tallied rates
to a small text/CSV artifact under `results/<name>/` (mirroring `scripts/sweep.jl`'s
`projectdir("results", "sweeps", ...)` convention) so the numbers are committed/citable in the
phase's completion notes — NOT merely printed and discarded.

## Shared Patterns

### The `pag_dso`/`:balance_p` → `qag_dso`/`:balance_q` mirror (the central pattern of this phase)
**Source:** `src/admm/DsoOpt.jl:206-210` (variable + residual injection) and `:230-236`
(constraint registration) — apply to: `src/admm/DsoOpt.jl`'s new reactive block.
```julia
@variable(model, pag_dso[j = load_nodes, t = 1:T])
for j in load_nodes, t in 1:T
    add_to_residual!(ctx, :Rp, j, t, pag_dso[j, t])
end
@constraint(model, balance_p[j = 1:N, t = 1:T], ctx.residuals[:Rp][j, t] == 0)
register_constraint!(ctx, :balance_p, balance_p)
```

### The no-slack certificate gate (INFRA-03 choke point)
**Source:** `src/core/status.jl:79-94` (`assert_no_slack`, reused VERBATIM — do not reimplement)
**Apply to:** the new `:balance_q` certificate in `src/admm/solve_admm.jl`'s final block,
gated on `reactive_consensus == true`, placed immediately after the EXISTING `:balance_p`
certificate at `src/admm/solve_admm.jl:412-416`.

### The `_assert_priceable` PF-04 gate (single certification choke point for ALL dual-based prices)
**Source:** `src/pricing/dlmp.jl:56-77` — apply to: the new `extract_reactive_dlmp` AND the
extended `decompose_dlmp`, called FIRST in both, exactly as `extract_dlmp`/`decompose_dlmp`
already do (lines 97, 172).

### Feature-flag threading without touching `Scenario.jl` (REACT-03's non-regression discipline)
**Source:** the project's own established "additive kwarg, default preserves behavior" idiom,
visible in EVERY existing kwarg on `build_dso_opt`/`solve_admm` (e.g. `allow_export::Bool =
true` at `src/models/welfare_solve.jl` call sites, `τ::Real = 2.0` / `μ::Real = 10.0` in
`solve_admm.jl:58`). **Apply to:** `reactive_consensus::Bool = false` on `build_dso_opt` and
`solve_admm` ONLY — explicitly NOT added to `src/experiments/Scenario.jl`, `run.jl`, `sweep.jl`,
or `store.jl` this phase (per 16-RESEARCH.md's "Anti-Patterns to Avoid" / Pitfall 3 — avoids a
second golden-hash `savename` perturbation).

## No Analog Found

None. Every file in this phase's scope has a strong, same-repo, same-role analog — this phase
is explicitly scoped (per 16-RESEARCH.md's own "Don't Hand-Roll" table) to REUSE existing
mechanisms exactly, not invent new ones.

## Metadata

**Analog search scope:** `src/admm/`, `src/pricing/`, `src/models/`, `src/core/`,
`src/experiments/materialize.jl`, `test/`, `scripts/` — directories named in 16-RESEARCH.md's
own "Sources — Primary" list, re-verified directly this session (not re-summarized).
**Files scanned/read directly this session:** `src/admm/DsoOpt.jl` (full, 373 lines),
`src/admm/solve_admm.jl` (full, 447 lines), `src/admm/AgrOpt.jl` (full, 238 lines),
`src/pricing/dlmp.jl` (full, 264 lines), `src/core/status.jl` (relevant excerpt,
`assert_no_slack`), `src/models/welfare_solve.jl` (lines 140-238), `test/test_admm_adaptive.jl`
(full, 134 lines), `test/test_dso.jl` (lines 1-60, 100-165), `test/test_pricing_dlmp.jl`
(lines 1-60, plus grepped structure of remaining decompose_dlmp items), `scripts/run_scenario.jl`,
`scripts/sweep.jl`, `scripts/benders_toy.jl` (header), `scripts/demo_flexibility_plots.jl`
(header), `src/experiments/materialize.jl` (grep for exports).
**Pattern extraction date:** 2026-07-25

# Phase 27: Integer Planning & Pricing Certificate Correctness - Pattern Map

**Mapped:** 2026-09-29
**Files analyzed:** 12 (6 source, 6 test) — the Wave-0-required set; docs/scripts blast-radius
files (13, per RESEARCH.md FIX-07 table) are OUT of this map's scope (alias mechanism keeps them
working unmodified; planner may choose to migrate a subset per-wave).
**Analogs found:** 12 / 12 — this is a "close a documented gap" phase (RESEARCH.md's own framing):
every touched file's fix pattern already has a strong IN-FILE or SIBLING-FILE precedent, so every
analog below is same-file (self-analog: extend an existing function/idiom already in that file) or
same-directory (a sibling file using the identical project idiom). No cross-project/external
analog was needed anywhere in this phase.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|-----------------|---------------|
| `src/planning/benders.jl` (`corner_recourse`, FIX-06) | service (optimization subroutine) | transform (parametric convex minimization) | itself — existing ternary-search `corner_recourse` (T=1 path kept verbatim) + `add_optimality_cut!`'s dual-read pattern (lines 299-301/530-533) | exact (self-extension) |
| `test/test_planning_certification_integer.jl` (new T=2 grid oracle, FIX-06) | test (validation oracle) | batch (exhaustive enumeration) | itself — existing `enumerate_lattice`/`ternary_min` (lines 115-184) | exact (self-extension, generalize 1-D→2-D grid) |
| `src/pricing/dlmp.jl` (`decompose_dlmp` rename, FIX-07) | service (post-processing / pure function) | transform (dual-read decomposition) | itself — existing NamedTuple-return + header derivation (lines 1-90, 297-365); `Base.getproperty`/`Base.depwarn` idiom is NEW to this file (no in-repo precedent found — standard-library idiom, cited in RESEARCH) | role-match (return-type change) |
| `src/models/exactness.jl` (`assert_socp_exact!` per-branch floor, FIX-08) | middleware (correctness gate) | transform (per-branch tolerance check) | itself — existing flat-`atol` loop (lines 78-107); `socp_relaxation_gap` sibling function immediately below (calibration-only twin) | exact (self-extension) |
| `src/pricing/fit.jl` (`fit_baseline` exactness gate, FIX-09) | service (counterfactual solver) | request-response (3-site solve pipeline) | `src/models/welfare_solve.jl`'s `on_violation::Symbol` kwarg pattern (lines 273-284, 345-348) — direct sibling idiom for `on_inexact` | role-match (kwarg-gated assertion idiom) |
| `src/experiments/mpc_loop.jl` (`run_mpc` truth settlement, FIX-10) | service (closed-loop orchestrator) | event-driven (receding-horizon step loop) | itself — existing `realized_welfare` accumulation (lines 111-128, 380-415) + `src/models/mpc_window.jl`'s `propagate_soc`/`propagate_tin` (lines 328-349) | exact (self-extension) |
| `test/test_planning_benders_integer.jl` (T=1 regression, FIX-06) | test | CRUD (existing suite, unmodified re-run) | n/a — regression only | exact |
| `test/test_exactness.jl` (new slack-cone fixture, FIX-08) | test (fixture + assertion) | batch (synthetic hand-built ctx) | itself — existing "throws on inexact relaxation" item (lines 11-51): hand-built `Model`/`fix.()`/`ctx.meta[:pf_vars]` pattern | exact (self-extension, new `smax`-bearing branch) |
| `test/test_fit.jl` (new inexact-FIT fixture, FIX-09) | test | request-response | itself — existing `fit_baseline(feeder, ConvexBranchFlow(), [agg]; ...)` call shape (lines 9-31) | exact (self-extension) |
| `test/test_mpc_loop.jl` (new forced-PV-shortfall fixture, FIX-10) | test | event-driven | itself — existing `Scenario(...)` + `run_mpc(s)` happy-path item (lines 15-38) | exact (self-extension, `mpc_forecast_error > 0` variant) |
| `test/test_pricing_dlmp.jl` (rename `.loss`/`.voltage`→`.cone`/`.drop`, new zero-iff-multiplier test, FIX-07) | test | CRUD (assertion rewrite) | itself — existing sum-to-price + "≈0 when unbinding" items (lines 255-286) | exact (self-extension) |
| `test/test_dlmp.jl` (rename field usages, FIX-07) | test | CRUD | same as above | exact |

## Pattern Assignments

### `src/planning/benders.jl` — `corner_recourse` (service, transform)

**Analog:** itself (lines 129-187, existing ternary search), plus the outer Benders loop's dual-read
convention (lines 299-301, 530-533).

**Current T=1 pattern to preserve byte-identically** (`src/planning/benders.jl:129-176`):
```julia
function corner_recourse(oracle, follower, y_inv::Real, T::Int; iters::Int = 100)
    function Qfun(z::Real)
        zvec = fill(Float64(z), T)
        fr = solve_follower!(follower, zvec)
        fr.feasible || return Inf
        orr = solve_planning_oracle!(oracle, zvec)
        return fr.cost - orr.cost
    end
    check_finite(Qv::Real, z::Real) =
        isfinite(Qv) || throw(ErrorException("corner_recourse: recourse evaluated to a " *
            "non-finite value at z=$z (y_inv=$y_inv) ..."))
    if y_inv <= 0
        Qv = Qfun(0.0)
        check_finite(Qv, 0.0)
        return Qv
    end
    lo, hi = 0.0, Float64(y_inv)
    for _ in 1:iters
        m1 = lo + (hi - lo) / 3
        m2 = hi - (hi - lo) / 3
        f1, f2 = Qfun(m1), Qfun(m2)
        if isinf(f1) && isinf(f2)
            hi = m2
        elseif f1 < f2
            hi = m2
        else
            lo = m1
        end
    end
    zstar = (lo + hi) / 2
    Qv = Qfun(zstar)
    check_finite(Qv, zstar)
    return Qv
end
```
**Dispatch rule (locked by CONTEXT.md):** `T == 1` calls this function UNCHANGED (byte-identical);
`T > 1` dispatches to a NEW joint cutting-plane function. Do not algebraically special-case inside
one body — RESEARCH.md is explicit that different floating-point trajectories would break
byte-identity even if mathematically equivalent.

**Dual-read-as-gradient pattern to reuse for the new T>1 inner loop** (`src/planning/benders.jl:299-301`
docstring excerpt / `530-533` call sites):
```julia
# Oracle's :op cut — sign_convention derivation, reused verbatim:
add_optimality_cut!(master, :op, -oracle_res.cost, oracle_res.π, lb_res.z)
# Follower's :x cut — used exactly as solve_follower! returns it.
add_optimality_cut!(master, :x, follower_res.cost, follower_res.π_s, lb_res.z)
```
For the new joint algorithm, at any trial `z::Vector`:
```julia
fr = solve_follower!(follower, z)
fr.feasible || return (Inf, nothing)          # Pitfall FIX-06-2: skip cut row on Inf
orr = solve_planning_oracle!(oracle, z)
Qz  = fr.cost - orr.cost
gradQ = fr.π_s .+ orr.π                        # elementwise, length T — same sign convention
```

**Small master LP solver factory to reuse** (`src/planning/follower.jl:41` header comment —
`FollowerLP` "built ONCE via `Model(select_optimizer(LP()))`"): the new inner cutting-plane
master LP should use the SAME `select_optimizer(LP())` factory, never a hardcoded solver
(`src/planning/follower.jl:110`: "never `Model(HiGHS.Optimizer)` directly").

**Error/finite-guard idiom to copy:** `check_finite`'s `throw(ErrorException(...))` closure and the
WR-01 double-infinite tie-break (`isinf(f1) && isinf(f2) → hi = m2`, never fall through to
`lo = m1`) — this exact tie-break logic generalizes to "skip the cut row" in the multivariate
master, per RESEARCH.md's Pitfall FIX-06-2.

**Measured-tolerance idiom to copy** (`src/planning/benders.jl:35-60`, `KNOWN_OPTIMUM_ATOL`):
comment format is "measure the solver's OWN achieved precision, cite the fixture and the raw
numbers, never hand-pick a constant" — apply the same discipline to the new T=2 grid-vs-cutting-
plane comparison tolerance.

---

### `test/test_planning_certification_integer.jl` — new T=2 enumeration oracle (test, batch)

**Analog:** itself — `enumerate_lattice`/`ternary_min` (lines 115-184).

**Pattern to mirror** (`test/test_planning_certification_integer.jl:122-153`):
```julia
Qfun(z) = begin
    fr = solve_follower!(follower, [z])
    fr.feasible || return Inf
    orr = solve_planning_oracle!(oracle, [z])
    fr.cost - orr.cost
end
function ternary_min(f, lo, hi; iters::Int = 100)
    for _ in 1:iters
        m1 = lo + (hi - lo) / 3
        m2 = hi - (hi - lo) / 3
        f1, f2 = f(m1), f(m2)
        if isinf(f1) && isinf(f2)
            hi = m2
        elseif f1 < f2
            hi = m2
        else
            lo = m1
        end
    end
    z = (lo + hi) / 2
    return (z, f(z))
end
```
Generalize to a T=2 grid: `Qfun(z1, z2)` calling `solve_follower!(follower, [z1, z2])` /
`solve_planning_oracle!(oracle, [z1, z2])`, then a dense double loop over
`(z1, z2) ∈ [0,y_inv]×[0,y_inv]` at a handful of `y_inv` lattice corners (reuse the EXACT
`y_inv = (y_max / 2^K) * sum(2.0^(k-1) * b[k] for k in 1:K)` formula, line 164, "IDENTICAL formula
to `build_master_integer`'s own `y_inv` expression"). Reuse the `isfinite`-or-throw guard verbatim
(lines 175-181) — an infeasible grid point is a legitimate `Inf`, never a silent `NaN`/error.

---

### `src/pricing/dlmp.jl` — `decompose_dlmp` rename (service, transform)

**Analog:** itself — current NamedTuple return + per-branch increment loop (lines 297-365).

**Current formula (rename targets only, ZERO numeric change per RESEARCH.md):**
```julia
# src/pricing/dlmp.jl:305-318 (variable names to rename: loss_b→cone_b or keep local names,
# volt_b stays computationally identical; only the RETURNED field names change)
loss_b[b, t] = -dual(cone[b, t])[3]                        # 3.39 P-slot → becomes `.cone`
volt_b[b, t] = -2 * r * (dual(vdrop[b, t]) + dual(cpydrop[b, t]))  # 3.33/3.43 → becomes `.drop`
...
return (; energy, loss, congestion, voltage, reactive, total)   # line 362 — rename loss→cone, voltage→drop
```

**Deprecation-alias struct pattern (NEW to this file — no in-repo `Base.depwarn` precedent found;
this is the standard-library idiom RESEARCH.md cites, safe to introduce)**:
```julia
struct DlmpDecomposition
    energy::Matrix{Float64}
    cone::Matrix{Float64}
    drop::Matrix{Float64}
    congestion::Matrix{Float64}
    reactive::Matrix{Float64}
    total::Matrix{Float64}
end
function Base.getproperty(d::DlmpDecomposition, s::Symbol)
    if s === :loss
        Base.depwarn("DlmpDecomposition.loss is deprecated, use .cone", :decompose_dlmp)
        return getfield(d, :cone)
    elseif s === :voltage
        Base.depwarn("DlmpDecomposition.voltage is deprecated, use .drop", :decompose_dlmp)
        return getfield(d, :drop)
    end
    return getfield(d, s)
end
```
Verify at implementation time this preserves `(; energy, loss, ...) = decompose_dlmp(ctx)`
destructuring (Julia property destructuring calls `getproperty` per field — RESEARCH.md confirms
this is expected to work automatically).

**Hard-assertion idiom to preserve verbatim** (`src/pricing/dlmp.jl:335-357`, the sum-to-price
check) — same `atol + rtol * maximum(abs, total)` scale-free style as `assert_socp_exact!`; only
the field names referenced in the residual computation change (`loss`→`cone`, `voltage`→`drop`).

---

### `src/models/exactness.jl` — `assert_socp_exact!` per-branch floor (middleware, transform)

**Analog:** itself — the existing flat-`atol` loop (lines 78-107) and the `socp_relaxation_gap`
calibration-only sibling immediately below it (same file, additive-twin pattern already
established for exactly this kind of change).

**Current loop to extend** (`src/models/exactness.jl:82-98`):
```julia
function assert_socp_exact!(ctx::ModelContext; rtol::Real = 1e-4, atol::Real = 1e-6)
    pv = ctx.meta[:pf_vars]
    feeder = ctx.meta[:feeder]
    T = ctx.meta[:T]
    maxgap = 0.0
    maxratio = 0.0
    for (b, br) in enumerate(feeder.branches), t in 1:T
        lhs = value(pv.l[b, t]) * value(pv.v[br.from, t])
        rhs = value(pv.P[b, t])^2 + value(pv.Q[b, t])^2
        gap = abs(lhs - rhs)
        tol = atol + rtol * max(abs(lhs), abs(rhs))
        maxgap = max(maxgap, gap)
        maxratio = max(maxratio, gap / tol)
    end
    maxratio <= 1 || error("SOCP relaxation INEXACT: ...")
    return maxgap
end
```
**New per-branch reference splice (RESEARCH.md's own recommended code, `exactness.jl:78-107` +
head-branch convention from `src/data/ieee13.jl:80`):**
```julia
head_b = findfirst(br -> br.from == feeder.root, feeder.branches)
for (b, br) in enumerate(feeder.branches), t in 1:T
    ref_b = br.smax < SMAX_NO_LIMIT ? br.smax^2 :
        value(pv.P[head_b, t])^2 + value(pv.Q[head_b, t])^2
    tol = ε * ref_b + rtol * max(abs(lhs), abs(rhs))
    ...
end
```
`SMAX_NO_LIMIT` constant is at `src/units/PerUnit.jl:73` (`const SMAX_NO_LIMIT = 99.0`), already
exported project-wide — import, do not redefine. `ε` must be a NEW, MEASURED, NAMED constant
(mirror `KNOWN_OPTIMUM_ATOL`'s measured-and-cited comment style, `benders.jl:35-60`) — never a
hand-picked value.

**Error-idiom to preserve verbatim** (line 99-103): `error(...)` (never `@assert`), citing the
worst ratio/branch and thesis equation numbers — same style for any new per-branch message.

---

### `src/pricing/fit.jl` — `fit_baseline` exactness gate (service, request-response)

**Analog:** `src/models/welfare_solve.jl`'s `on_violation::Symbol` kwarg idiom (lines 273-284,
345-348) — the DIRECT project-standard pattern for "gate an assertion behind a caller-selectable
error/report mode," cited explicitly by RESEARCH.md as "a PROJECT-STANDARD idiom, not a new
pattern to invent."

**Pattern to copy** (`src/models/welfare_solve.jl:284, 345-348`):
```julia
function assert_battery_complementarity!(ctx; τ = ..., on_violation::Symbol = :error)
    on_violation in (:error, :warn) ||
        throw(ArgumentError("assert_battery_complementarity!: invalid on_violation=" *
            "$(repr(on_violation)), expected :error or :warn"))
    ...
    if on_violation === :error
        error(...)
    else
        @warn ...
    end
end
```
**Wire the same shape into `fit_baseline`'s SITE 2 (FIT AC-PF)** (`src/pricing/fit.jl:320-378`,
insert immediately after the existing `assert_solved!(model; dual = false)` at line ~378, BEFORE
`imports = value.(p_import)`):
```julia
# NEW: on_inexact::Symbol = :error kwarg on fit_baseline itself, threaded down to here.
if on_inexact === :error
    assert_socp_exact!(ctx)             # throws on inexact — no maxgap captured downstream
elseif on_inexact === :report
    maxgap = try
        assert_socp_exact!(ctx)
    catch e
        # capture the certificate instead of throwing — mirrors `o.ctx.meta[:socp_maxgap]`
        # shape already used elsewhere (subproblem.jl:298)
        NaN   # or a dedicated (; exact, maxgap) certificate struct, per plan discretion
    end
else
    throw(ArgumentError("fit_baseline: invalid on_inexact=$(repr(on_inexact)), expected " *
        ":error or :report"))
end
```
Guard-validation idiom (`ArgumentError` on an invalid kwarg symbol) to copy verbatim from
`welfare_solve.jl:347-348`.

**`on_violation` reference site 2** (`src/models/welfare_solve.jl:273`):
```julia
on_violation = problem_class(pf) isa SOCP ? :error : :warn
assert_battery_complementarity!(ctx; τ = τ, T = T, on_violation = on_violation)
```
This shows the "compute the mode from context, pass it down" call-site convention — not directly
needed here (CONTEXT locks `on_inexact` default to `:error` unconditionally) but useful precedent
if a plan wave wants a data-driven default.

---

### `src/experiments/mpc_loop.jl` — `run_mpc` truth settlement (service, event-driven)

**Analog:** itself — current forecast-consistent accumulation (lines 380-415) and
`src/models/mpc_window.jl`'s existing JuMP-free re-derivation functions (lines 328-349).

**Current forecast-consistent settlement to rename → `forecast_settled_welfare`**
(`src/experiments/mpc_loop.jl:380-415`, unchanged computation, new name only):
```julia
for agg in mpc_aggs
    ...
    for d in agg.devices
        realized_welfare += _mpc_device_hour_utility(d, varlist, τ_apply)
        if d isa PVBattery || d isa FourQuadBESS
            v = only(vv for vv in varlist if haskey(vv, :soc0))
            p_ch1 = value(v.p_ch[τ_apply])
            p_dch1 = value(v.p_dch[τ_apply])
            measured_state[(agg.bus, :soc)] = propagate_soc(
                measured_state[(agg.bus, :soc)], p_ch1, p_dch1, d.η, d.Δt,
            )
        elseif d isa Thermostatic
            v = only(vv for vv in varlist if haskey(vv, :Tin0))
            p1 = value(v.p[τ_apply])
            measured_state[(agg.bus, :Tin)] = propagate_tin(
                measured_state[(agg.bus, :Tin)], p1, d.α, d.β, d.Tout[abs_hour],
            )
        end
    end
end
# WR-01: FORECAST-CONSISTENT settlement...
realized_welfare -= λ₀[abs_hour] * value(o.p_import[τ_apply])
```
**New truth-clip pattern to splice in (per CONTEXT/RESEARCH FIX-10 algorithm), reusing
`d.Ppv[abs_hour]` (Assumption A6, `src/devices/PVBattery.jl:29-30`) as the TRUE availability**:
```julia
if d isa PVBattery
    p_ch_true = min(value(v.p_ch[τ_apply]), d.Ppv[abs_hour])   # clip to TRUE PV (A6)
    p_dch1 = value(v.p_dch[τ_apply])
    next_soc = propagate_soc(measured_state[(agg.bus, :soc)], p_ch_true, p_dch1, d.η, d.Δt)
    (d.Emin <= next_soc <= d.Emax) || throw(ErrorException(
        "run_mpc: true-state SOC propagation out of [Emin,Emax] at bus=$(agg.bus), " *
        "abs_hour=$abs_hour — a genuine out-of-band state (not solver-tolerance noise; " *
        "see _mpc_window_device's SEPARATE clamp, mpc_loop.jl:759-762)."))
    measured_state[(agg.bus, :soc)] = next_soc
    # accumulate utility from p_ch_true, not the unclipped solved value (utility function
    # signature unchanged — same _mpc_device_hour_utility shape, clipped input)
end
```
**Throw-not-clamp idiom to copy** — contrast with the EXISTING, differently-scoped clamp at
`src/experiments/mpc_loop.jl:759-762` (`_mpc_window_device`'s own docstring: "clamped ... purely to
absorb solver-tolerance noise ... a genuinely out-of-band state is prevented upstream ... so the
clamp is never a silent repair of a real violation") — the NEW truth-propagation check is the
opposite case (a genuinely out-of-band state from a real forecast-error/PV-clip event) and per
CONTEXT must `throw`, never reuse that clamp.

**JuMP-free re-derivation functions to call unchanged** (`src/models/mpc_window.jl:328-349`):
```julia
function propagate_soc(soc::Real, p_ch1::Real, p_dch1::Real, η::Real, Δt::Real)
    return soc + (η * p_ch1 - p_dch1 / η) * Δt
end
function propagate_tin(Tin::Real, p1::Real, α::Real, β::Real, Tout_true::Real)
    return Tin + α * (Tout_true - Tin) - β * p1
end
```
These are called with the CLIPPED `p_ch_true` in place of `p_ch1` — no signature change needed.

**Docstring-convention idiom to copy** (lines 111-128): name every approximation explicitly in the
returned NamedTuple's docstring (e.g. "the copper-plate `p_import_true` correction ignores
second-order network-loss changes — see docstring") rather than hiding it, matching this file's own
existing "WR-01 ... documented here rather than silently implied" convention.

---

### Test files (FIX-07/08/09/10 new `@testitem`s)

**Analog:** `test/test_exactness.jl:11-51` (hand-built `Model`/`fix.()`/`ctx.meta` fixture idiom),
`test/test_fit.jl:9-31` (`fit_baseline(feeder, ConvexBranchFlow(), [agg]; ...)` call shape),
`test/test_mpc_loop.jl:15-38` (`Scenario(...)` + `run_mpc(s)` call shape),
`test/test_pricing_dlmp.jl:255-286` (sum-to-price + per-component assertion shape).

**Shared harness convention (every file, verified across all four):**
```julia
@testitem "<seam>: <behavior> (<REQ-ID>)" tags = [:<seam>] begin
    using TSODSO
    @test isdefined(TSODSO, :<new_symbol>)   # RED-until-defined guard, if new export
    if isdefined(TSODSO, :<new_symbol>)
        <hand-built fixture or canonical Scenario/feeder>
        <call under test>
        @test <assertion, atol/rtol scale-free style>
    end
end
```
Per `.planning/STATE.md`/RESEARCH.md's own testing-constraint note, verify each new item as a
plain `julia --project=.` script BEFORE relying on TestItemRunner discovery (TestItemRunner does
not resolve under `--project=.` — memory `gsd-plan-verify-testitemrunner-trap`).

**FIX-08 synthetic slack-cone fixture** — mirror `test_exactness.jl:11-51`'s hand-built
`Model`/`fix.()` pattern exactly, but give the fixed branch a small `smax` (or leave it
`SMAX_NO_LIMIT` for the interior-branch case) and inject a deliberately small-but-nonzero
`gap = |l·v - (P²+Q²)|` relative to `ref_b` (not the previous test's grossly-inexact `gap=1`
point) — this is the NEW discriminating case the flat `atol` missed.

**FIX-09 synthetic inexact-FIT fixture** — mirror `test_fit.jl:9-31`'s `fit_baseline(feeder,
ConvexBranchFlow(), [agg]; ...)` call, but construct a feeder/aggregator combination (or a directly
hand-built `ctx` at SITE 2) known to leave the cone slack — assert
`@test_throws Exception fit_baseline(...; on_inexact = :error)` and
`@test isfinite(fit_baseline(...; on_inexact = :report).socp_maxgap)` (or equivalent certificate
field name, per plan discretion).

**FIX-10 forced-PV-shortfall fixture** — mirror `test_mpc_loop.jl:15-38`'s `Scenario(...)` +
`run_mpc(s)` shape, but set `mpc_forecast_error > 0` with a `pv_factor` draw forced high enough
(or a direct hand-built low-`Ppv` truth override) that the solved `p_ch` exceeds
`d.Ppv[abs_hour]`; assert `r.forecast_settled_welfare != r.realized_welfare` (the two now
genuinely differ) and, on a SEPARATE more-extreme fixture, `@test_throws Exception run_mpc(s2)`
for the SOC-bound-violation-throws case.

**FIX-07 field-rename test edits** — `test/test_pricing_dlmp.jl:264-278` and `test/test_dlmp.jl`:
mechanical `.loss`→`.cone`, `.voltage`→`.drop` field renames in existing assertions (lines
264-278, 433), PLUS a new replacement for the removed "voltage ≈ 0 when unbinding" item (line 275)
asserting `d.drop[j,t] == 0 iff (dual(:vdrop[b,t]) == 0 && dual(:cpydrop[b,t]) == 0)` for every
branch `b` on `j`'s root path, on the IEEE-13-slice fixture CONTEXT locks — mirror the existing
per-node/per-hour loop shape at lines 264-278.

## Shared Patterns

### Measure-then-pin constants (applies to FIX-06 tolerance, FIX-08 ε)
**Source:** `src/planning/benders.jl:35-60` (`KNOWN_OPTIMUM_ATOL`)
**Apply to:** the new T=2 enumeration-vs-cutting-plane comparison tolerance (FIX-06) and the new
per-branch `ε` (FIX-08).
```julia
# EMPIRICALLY MEASURED (<date>) on <fixture>, solving <models> and reading each solver's OWN
# certified primal/dual objective gap directly (no second reference solve needed):
#   gap_X = <measured value>
# Per the measurement formula `max(<floor>, 10 * gap_X)`, the constant is set to <value>.
const SOME_MEASURED_TOL = <value>
```

### `on_<x>::Symbol` kwarg-gated assertion (applies to FIX-09)
**Source:** `src/models/welfare_solve.jl:284, 345-348` (`assert_battery_complementarity!`'s
`on_violation`)
```julia
on_violation in (:error, :warn) ||
    throw(ArgumentError("...: invalid on_violation=$(repr(on_violation)), expected :error or :warn"))
if on_violation === :error
    error(...)
else
    @warn ...
end
```

### Scale-free `atol + rtol * max(...)` tolerance shape (applies to FIX-07's sum-to-price check,
FIX-08's per-branch floor)
**Source:** `src/models/exactness.jl:99` / `src/pricing/dlmp.jl:353`
```julia
tol = atol + rtol * max(abs(lhs), abs(rhs))     # or maximum(abs, total) for a global reference
```

### `error(...)` never `@assert` (applies to every new gate/throw in this phase)
**Source:** `src/models/exactness.jl` docstring: "Uses an explicit `error(...)` (never `@assert`,
which is elided under `-O`), per project convention (`src/core/status.jl`)."

### Thesis-equation-number comments on every constraint/formula
**Source:** ubiquitous project convention (every file read this session) — e.g.
`src/pricing/dlmp.jl:1-90`'s "thesis 3.31/3.33/3.36/3.39/3.43" citations. Apply to every new/changed
line touching a thesis-derived quantity (FIX-06's `Q(z)` convexity comment, FIX-07's renamed
fields, FIX-08's `ref_b`, FIX-10's A6 clip).

### `ArgumentError` guards on bad kwargs/inputs
**Source:** pervasive (`src/models/welfare_solve.jl:347-348`, `src/pricing/fit.jl` throughout) —
apply to `on_inexact`, any new `ε`/tolerance kwarg validation.

## No Analog Found

| File/Pattern | Role | Data Flow | Reason |
|--------------|------|-----------|--------|
| `Base.getproperty`/`Base.depwarn` deprecation-alias struct (FIX-07) | utility (property-access shim) | transform | No prior use of `Base.depwarn` anywhere in `src/`/`test/` (grep confirmed zero hits) — this is a NEW-to-repo but standard-library-standard idiom; RESEARCH.md cites it directly (Julia Base, not project-specific), safe to introduce without an in-repo precedent |
| Multivariate (T-dimensional) cutting-plane/Kelley's-method inner loop (FIX-06) | service (convex optimization) | transform | No existing T>1 joint minimization anywhere in `src/planning/`; RESEARCH.md's own recommendation (reusing `select_optimizer(LP())` + existing dual reads) is itself the closest available analog, already captured above — flagged here because the OVERALL algorithm is new even though every ingredient (LP factory, dual-read convention, finite-guard idiom) is not |

## Metadata

**Analog search scope:** `src/planning/`, `src/pricing/`, `src/models/`, `src/experiments/`,
`src/devices/`, `src/units/`, `src/data/`, `test/` (files named in RESEARCH.md's Phase Requirements
→ Test Map and Architecture Patterns sections).
**Files scanned:** ~15 direct reads (grep-targeted, non-overlapping ranges) across
`src/planning/benders.jl`, `src/planning/follower.jl`, `src/pricing/dlmp.jl`, `src/pricing/fit.jl`,
`src/models/exactness.jl`, `src/models/welfare_solve.jl`, `src/models/mpc_window.jl`,
`src/experiments/mpc_loop.jl`, `src/units/PerUnit.jl`,
`test/test_planning_certification_integer.jl`, `test/test_exactness.jl`, `test/test_fit.jl`,
`test/test_mpc_loop.jl`, `test/test_pricing_dlmp.jl`.
**Pattern extraction date:** 2026-09-29

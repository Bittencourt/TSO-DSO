# Phase 26: Network & Device Model Correctness - Pattern Map

**Mapped:** 2026-09-28
**Files analyzed:** 10 modified + 4-6 new (test/docs)
**Analogs found:** 10 / 10 (all files being MODIFIED are themselves their own best
pattern source — this is a surgical-correctness phase, not a new-feature phase; new test
files have strong existing templates)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `src/powerflow/ConvexBranchFlow.jl` (cpydrop sign flip, FIX-01/02) | model/constraint-builder | transform (JuMP model assembly) | itself (`RestrictedBranchFlow.jl`'s existing `v̂ ≥ v` Gan-Low delegation as the target *property*, not code to copy) | exact (self-modify) |
| `src/powerflow/ConvexBranchFlow.jl` (reverse thermal cone, FIX-03) | model/constraint-builder | transform | same file's existing forward `smax` cone block (lines 189-206) | exact |
| `src/powerflow/RestrictedBranchFlow.jl` (thesis-literal variant home / audit) | model/constraint-builder | transform | `RestrictedBranchFlow`'s own `ε`-kwarg opt-in pattern (struct field + inner-constructor guard) | exact |
| `src/devices/PVBattery.jl` (soc horizon, FIX-04) | device (aggregatable) | CRUD-like state-recursion (temporal coupling) | `src/devices/FourQuadBESS.jl`'s byte-identical SOC recursion block | exact |
| `src/devices/FourQuadBESS.jl` (soc horizon, FIX-04) | device (aggregatable) | temporal coupling | `src/devices/PVBattery.jl`'s byte-identical SOC recursion block | exact |
| `src/models/mpc_window.jl` (soc[H+1] terminal target, guard removal) | model assembly | transform / re-solve seam | itself — the `terminal_soc && H==1` guard block (lines 136-149) and `soc[H]` terminal wiring (lines 236-259) | exact |
| `src/models/stochastic_welfare.jl` (audit soc index refs) | model assembly | batch (per-scenario copies) | `mpc_window.jl`'s per-scenario `contribute!` delegation pattern | role-match |
| `src/devices/Aggregator.jl` (flexible-load tanφ roll-up, FIX-05) | service/roll-up (device aggregation) | event-driven roll-up (sums per-device returns) | itself — existing `q_inject` `hasproperty` accumulator pattern (lines 196-201) | exact |
| `src/devices/Interruptible.jl` (Variant-1 → Variant-2 conversion, FIX-05) | device (converting self-injecting → aggregatable) | request-response → CRUD-return | `src/devices/Thermostatic.jl` / `src/devices/Deferrable.jl` (already Variant-2, structurally near-identical) | exact |
| `src/devices/Thermostatic.jl` (add `is_flexible_load`/optional φ) | device (aggregatable) | CRUD-return | itself + `Deferrable.jl` (sibling Variant-2 device) | exact |
| `src/devices/Deferrable.jl` (add `is_flexible_load`/optional φ) | device (aggregatable) | CRUD-return | itself + `Thermostatic.jl` (sibling Variant-2 device) | exact |
| `src/pricing/dlmp.jl` (`decompose_dlmp` voltage-coefficient re-derivation) | service (pure post-solve duality read) | transform (dual-read, no model building) | itself — the file's own `volt_b` formula + empirical-certification convention stated in its header comment | exact |
| `test/test_exactness_verdict.jl` (NEW, FIX-01 3-bus regression) | test (integration) | request-response (solve + assert) | `test/test_restricted_branch_flow.jl`'s first `@testitem` (lines 20-54) + `test/fixtures_phase4.jl`'s 3-bus construction idiom + `test/test_pricing_fit.jl`'s `FitFixtures` 3-bus feeder builder | strong role-match |
| `test/test_convex_branch_flow.jl` (extend: FIX-02 v̂≥v assert, FIX-03 PV back-feed) | test (unit/integration) | request-response | itself — existing `@testitem` scaffolding (2-bus `Feeder`/`Branch` literal construction, `pf_vars` stash pattern) | exact |
| `test/test_restricted_branch_flow.jl` (flip the line-20 golden assertion) | test (unit) | request-response | itself — the exact `@testitem` to edit (line 20) | exact |
| `test/test_pvbattery.jl`, `test/test_fourquadbess.jl` (FIX-04 zero-discharge-at-T regression) | test (unit) | request-response | each file's own existing SOC/complementarity `@testitem`s | exact |
| `test/test_mpc_window.jl` (FIX-04 `soc[H+1]` / `H==1` guard-removal regression) | test (unit) | request-response | itself — existing terminal-condition `@testitem`s | exact |
| `test/test_aggregator.jl`, `test/test_thermostatic.jl`, `test/test_deferrable.jl` (FIX-05 per-device `:Rq == p·tanφ`) | test (unit) | request-response | `test/test_device.jl`'s existing `Aggregator`-wrapping pattern for `q_inject` (FourQuadBESS precedent) | exact |
| `test/test_device.jl` (update for `Interruptible`'s new Variant-2 return contract) | test (unit) | request-response | itself — existing standalone `Interruptible` call sites | exact |
| docs page for the FIX-01 verdict (new `.md`, location Claude's discretion) | docs | n/a | `RestrictedBranchFlow.jl`'s own extensive derivation-in-docstring convention (escalation-history comment block, lines 1-49) as the prose/citation style to mirror | role-match |

## Pattern Assignments

### `src/powerflow/ConvexBranchFlow.jl` — FIX-01/02 cpydrop sign flip (model/constraint-builder, transform)

**Analog:** itself; target property matches `RestrictedBranchFlow`'s documented Gan-Low
direction, but the MECHANISM (Option A, per RESEARCH.md) is a pure coefficient edit, not a
structural copy of `RestrictedBranchFlow`'s tree machinery.

**Current code to change** (`src/powerflow/ConvexBranchFlow.jl:177-183`):
```julia
@constraint(
    m,
    cpydrop[b = 1:nB, t = 1:T],
    v̂[B[b].to, t] ==
    v̂[B[b].from, t] -
    2 * (B[b].r * (P[b, t] + B[b].r * l[b, t]) + B[b].x * (Q[b, t] + B[b].x * l[b, t]))
)
```

**Fix (Option A, RESEARCH-recommended):** flip the sign of the `r·l`/`x·l` terms inside the
parentheses (`+` → `-`), i.e. substitute `P̂ = P − r·l`, `Q̂ = Q − x·l` instead of `P + r·l`,
`Q + x·l`. This is proven (telescoping-sum argument in RESEARCH.md) to yield `v̂ ≥ v`
unconditionally. Update:
  - the docstring narrative at lines 58-60, 68-71, 88-89, 104, 136-137, 166 (every place the
    formula/sign is documented) — these currently describe the CURRENT wrong-direction
    formula and the wrong "load-bearing bound" claim; must be rewritten to state the
    corrected direction and cite the FIX-01 docs page/RESEARCH.md derivation;
  - the module header comment at lines 6-15 similarly.
- The registered constraint container (`register_constraint!(ctx, :cpydrop, cpydrop)`,
  line 187) keeps its EXACT shape/name — only the numeric coefficient inside changes, so
  every downstream consumer (`MeshedFlow`, `RestrictedBranchFlow`, `DsoOpt.jl`,
  `stochastic_welfare.jl`, `decompose_dlmp`) continues to structurally resolve.
- Retain the OLD (thesis-literal) formula as an explicit opt-in variant per CONTEXT.md
  ("retained as an explicit opt-in variant, clearly labelled a RESTRICTION"). Naming is
  Claude's discretion; the cleanest precedent for "an opt-in variant of an existing
  formulation, gated by a struct field with an inner-constructor guard" is
  `RestrictedBranchFlow`'s own `ε::Float64` field + validating inner constructor
  (`src/powerflow/RestrictedBranchFlow.jl:114-134`) — copy that shape (a boolean/enum field
  on a NEW struct, or a kwarg on `ConvexBranchFlow` itself if the planner prefers a single
  type) rather than inventing a new mechanism.

**Docstring/citation style to copy** (for the FIX-01 verdict prose, wherever it lands —
inline docstring and/or a docs page):
```julia
# src/powerflow/RestrictedBranchFlow.jl:17-49 (escalation-history comment block) —
# copy this STYLE: numbered rationale, explicit citation to the source theorem/paper,
# explicit statement of what was tried and rejected and why, a pointer to the empirical
# record file (e.g. a phase SUMMARY.md).
```

---

### `src/powerflow/ConvexBranchFlow.jl` — FIX-03 reverse thermal limit (model/constraint-builder, transform)

**Analog:** the EXISTING forward `smax` cone block in the SAME file (lines 189-206) — copy
this pattern almost verbatim, substituting the receiving-end power expression.

**Pattern to copy** (`src/powerflow/ConvexBranchFlow.jl:201-206`):
```julia
@constraint(
    m,
    smax[b = 1:nB, t = 1:T; B[b].smax < _SMAX_NO_LIMIT],
    [B[b].smax, P[b, t], Q[b, t]] in SecondOrderCone()
)
register_constraint!(ctx, :smax, smax)   # dual ν = congestion DLMP component (3.36)
```

**New constraint (FIX-03), same filter predicate, receiving-end power `(P−r·l, Q−x·l)`:**
```julia
@constraint(
    m,
    smax_rev[b = 1:nB, t = 1:T; B[b].smax < _SMAX_NO_LIMIT],
    [B[b].smax, P[b, t] - B[b].r * l[b, t], Q[b, t] - B[b].x * l[b, t]] in SecondOrderCone()
)
register_constraint!(ctx, :smax_rev, smax_rev)   # dual = receiving-end congestion (3.37)
```
- Uses the SAME `_SMAX_NO_LIMIT`/`B[b].smax < _SMAX_NO_LIMIT` filter (single source of truth,
  `src/units/PerUnit.jl:73` `const SMAX_NO_LIMIT = 99.0`) — no new sentinel needed.
- `LinDistFlow.jl` is explicitly excluded (l≡0 makes it identical to the forward cone) — do
  NOT add this constraint there.
- `MeshedFlow.jl` and `RestrictedBranchFlow.jl` both delegate their entire `contribute!` to
  `ConvexBranchFlow.contribute!` first (see `RestrictedBranchFlow.jl:174-175`,
  `contribute!(ConvexBranchFlow(), ctx, feeder; T = T)`), so they inherit this new cone
  automatically — confirm via a read of `MeshedFlow.jl`'s one-line delegation but expect NO
  code change needed there.
- Register even though no phase success-criterion strictly requires the dual yet — mirrors
  the `:opfm_shadow_voltage` precedent in `RestrictedBranchFlow.jl:277` ("dual available for
  future diagnostics, though this plan's certificate does not require it").

---

### `src/devices/PVBattery.jl` — FIX-04 SOC horizon linking (device, temporal coupling)

**Analog:** `src/devices/FourQuadBESS.jl` (byte-identical SOC recursion shape — cross-check
both files change identically).

**Current code** (`src/devices/PVBattery.jl:253`, `290-297`):
```julia
soc = @variable(m, [t = 1:T], lower_bound = d.Emin, upper_bound = d.Emax) # (3.9)
...
@constraint(m, soc[1] == soc0)                                            # (3.9 IC)
if T > 1
    @constraint(
        m,
        [t = 1:(T - 1)],
        soc[t + 1] == soc[t] + (d.η * p_ch[t] - p_dch[t] / d.η) * d.Δt
    )
end
```

**Fix pattern (apply to BOTH `PVBattery.jl` and `FourQuadBESS.jl` identically):**
```julia
soc = @variable(m, [t = 1:(T + 1)], lower_bound = d.Emin, upper_bound = d.Emax) # (3.9), now T+1 long
...
@constraint(m, soc[1] == soc0)                                            # (3.9 IC), unchanged
@constraint(
    m,
    [t = 1:T],                                                            # now covers ALL T hours, closing on soc[T+1]
    soc[t + 1] == soc[t] + (d.η * p_ch[t] - p_dch[t] / d.η) * d.Δt
)
```
- Drop the `if T > 1` guard around the recursion (it now always has at least one term, `t=1`,
  since the recursion covers `1:T` unconditionally instead of `1:(T-1)`).
- Add the OPTIONAL `soc_terminal` keyword (`nothing` default | numeric value | `:cyclic`)
  per CONTEXT.md. No existing precedent for a tri-state keyword like this in the codebase;
  the closest shape convention is `RestrictedBranchFlow`'s `ε::Real = 0.0` optional kwarg
  field with an inner-constructor guard (`RestrictedBranchFlow.jl:124-134`) — mirror the
  "validate at construction, default to a no-op" discipline, but note `soc_terminal` is a
  `contribute!`-time (not construction-time) concern since it affects constraint-building,
  closer to `mpc_window.jl`'s own `terminal_soc::Bool` kwarg
  (`build_mpc_window(...; terminal_soc::Bool = true, ...)`) — copy THAT kwarg-threading
  style instead.
- Return-tuple shape is UNCHANGED (`(; vars = (; p_ch, p_dch, soc, pv_used, soc0,
  Ppv_param), p_inject, utility)` for `PVBattery`; analogous for `FourQuadBESS`) — `soc` is
  simply a longer vector now; no key renames.

---

### `src/models/mpc_window.jl` — FIX-04 downstream index shift (model assembly)

**Analog:** itself.

**Current code to change** (`src/models/mpc_window.jl:140-149`, the `H==1` guard):
```julia
if terminal_soc && H == 1
    throw(
        ArgumentError(
            "build_mpc_window: terminal_soc = true requires H ≥ 2 — at H = 1 the " *
            "terminal equality soc[H] == terminal_param double-pins the SAME variable " *
            "the initial condition soc[1] == soc0 already pins, which is infeasible " *
            "whenever the measured state differs from the terminal target (MPC-02, D-06)",
        ),
    )
end
```
**Fix:** REMOVE this guard's throw entirely (CONTEXT.md: "drops the WR-03 H==1 special
case") — once the device's own `soc` vector is `1:(H+1)` long, `soc[H+1]` is a DIFFERENT
index from `soc[1]` even at `H=1`, so the double-pin collision this guard existed to prevent
structurally disappears.

**Current code to change** (`src/models/mpc_window.jl:236-247`, the terminal-condition
target):
```julia
if haskey(v, :soc0)
    if terminal_soc
        term = @variable(
            model,
            base_name = "soc_terminal_bus$(bus)",
            set = Parameter(parameter_value(v.soc0)),
        )
        @constraint(model, v.soc[H] == term)     # <-- change to v.soc[H + 1]
        ...
```
**Fix:** change `v.soc[H] == term` to `v.soc[H + 1] == term` — the ONE line CONTEXT.md and
RESEARCH.md both name explicitly.
- Add a new regression per RESEARCH.md: `build_mpc_window(...; H = 1, terminal_soc = true)`
  should now SOLVE (not throw) — verify via the SAME `@testitem` idiom `test_mpc_window.jl`
  already uses for its other terminal-condition tests.

---

### `src/models/stochastic_welfare.jl` — FIX-04 audit (model assembly, batch)

**Analog:** `mpc_window.jl`'s delegation pattern — `stochastic_welfare.jl` registers the
SAME nine named containers including `:cpydrop` per scenario copy (per RESEARCH.md, around
line 296) via `contribute!` delegation, so BOTH the cpydrop fix and the SOC-horizon fix
propagate automatically with NO separate code change expected. Action here is AUDIT, not
edit:
- Grep `soc[T]`, `soc[end]`, `length(soc)` inside this file and its own out-of-sample
  harness (`StochasticOosHarness`, ~line 475-495) to confirm nothing reads the OLD
  `T`-length `soc` vector as a terminal/output value. The harness's own comment ("pins
  `p_ch`/`p_dch` per-step... because App. C dominance already forces `p_ch·p_dch=0`") should
  still hold since it concerns `p_ch`/`p_dch`, not `soc`'s length — but confirm empirically.
- No code excerpt to copy here — this is a read/confirm task, not a pattern-transplant task.

---

### `src/devices/Aggregator.jl` — FIX-05 flexible-load reactive draw (roll-up, event-driven sum)

**Analog:** itself — the EXISTING optional `q_inject` `hasproperty` accumulator is the exact
shape to extend for the NEW flexible-load `tanφ` contribution.

**Current code** (`src/devices/Aggregator.jl:192-204`):
```julia
for d in agg.devices
    res = contribute!(d, ctx; T = T)
    for t in 1:T
        p_inject[t] += res.p_inject[t]
    end
    if hasproperty(res, :q_inject)
        for t in 1:T
            q_inject[t] += res.q_inject[t]
        end
    end
    utility += res.utility
    push!(device_vars, res.vars)
end
```

**Fix pattern (add a parallel trait dispatch + per-device φ override, per RESEARCH.md's
recommended mechanism):**
```julia
# New trait function (candidate home: AbstractDevice.jl, mirroring the q_inject widened-
# contract docstring convention at AbstractDevice.jl:67-80):
is_flexible_load(::AbstractDevice) = false
is_flexible_load(::Interruptible) = true
is_flexible_load(::Thermostatic)  = true
is_flexible_load(::Deferrable)    = true

# Inside the Aggregator's roll-up loop, alongside the existing q_inject accumulator:
for d in agg.devices
    res = contribute!(d, ctx; T = T)
    for t in 1:T
        p_inject[t] += res.p_inject[t]
    end
    if hasproperty(res, :q_inject)
        for t in 1:T
            q_inject[t] += res.q_inject[t]
        end
    end
    if is_flexible_load(d)
        φ_used = hasproperty(d, :φ) ? d.φ : agg.φ
        tanφ_d = reactive_factor(φ_used)      # reuse the SAME reactive_factor helper (line 28)
        for t in 1:T
            q_inject[t] += res.p_inject[t] * tanφ_d
        end
    end
    utility += res.utility
    push!(device_vars, res.vars)
end
```
- Reuse `reactive_factor(φ)` (already defined + exported at `Aggregator.jl:20-28`) — do NOT
  reimplement `tan(arccos φ)` a second time.
- Sign check (documented in RESEARCH.md): `res.p_inject[t]` is NEGATIVE for a load, so
  `res.p_inject[t] * tanφ_d` is negative — consistent with the EXISTING
  `-Pdc_param[t] * tanφ` convention at line 213 (both negative = reactive power drawn).
- The `:Rp`/`:Rq` write block itself (lines 211-214) does NOT need to change — `q_inject` is
  already summed into the `:Rq` write via `+ q_inject[t]`; the fix is entirely inside the
  accumulation loop above.
- **One test per device type** per CONTEXT.md — pattern to copy for the test harness: build
  a MINIMAL single-member `Aggregator` wrapping ONE device
  (`Aggregator(bus, φ, [device], Pdc)`, mirrors `src/experiments/materialize.jl`'s
  `_house_aggregator` construction shape) and assert `value(res.q_inject[t]) ≈
  value(res.p_inject[t]) * reactive_factor(φ)` — or assert against the actual registered
  `:Rq` residual/dual, per the CONTEXT.md phrasing "`:Rq` contribution == `p·tanφ` at the
  solution."

---

### `src/devices/Interruptible.jl` — FIX-05 Variant-1 → Variant-2 conversion (device contract change)

**Analog:** `src/devices/Thermostatic.jl` and `src/devices/Deferrable.jl` — both are ALREADY
Variant-2 (aggregatable) devices with a near-identical struct/constructor/docstring shape to
`Interruptible`'s current Variant-1 shape. Convert `Interruptible.contribute!` to follow
their contract exactly.

**Current code (Variant-1, self-injecting)** (`src/devices/Interruptible.jl:104-122`):
```julia
function contribute!(d::Interruptible, ctx::ModelContext; T::Int = 1)
    m = ctx.model
    p = @variable(m, [t = 1:T], lower_bound = d.Pmin, upper_bound = d.Pmax)

    for t in 1:T
        add_to_residual!(ctx, :Rp, d.bus, t, -p[t])
    end

    add_to_objective!(ctx, sum(d.a * p[t] - (d.b / 2) * p[t]^2 for t in 1:T))

    return p
end
```

**Target shape (Variant-2, copy `Deferrable.jl:174-219`'s exact return-tuple pattern — the
closest sibling since neither carries temporal coupling beyond simple bounds):**
```julia
function contribute!(d::Interruptible, ctx::ModelContext; T::Int = 1)
    m = ctx.model
    p = @variable(m, [t = 1:T], lower_bound = d.Pmin, upper_bound = d.Pmax)

    utility = sum(d.a * p[t] - (d.b / 2) * p[t]^2 for t in 1:T)

    # Signed ACTIVE injection: a consumed load is a NEGATIVE injection (Interruptible's own
    # existing sign convention, unchanged) — matches Deferrable/Thermostatic's identical
    # convention.
    p_inject = AffExpr[-p[t] for t in 1:T]

    return (; vars = (; p), p_inject, utility)
end
```
- Update the module header comment (lines 1-12) and docstring (lines 86-102) from "the
  first... self-injecting device... Variant-1" language to the Variant-2 aggregator-as-writer
  language `Deferrable.jl`'s header (lines 1-16) and docstring (lines 151-172) already use —
  copy that prose shape directly (swap device-specific details only).
- `AbstractDevice.jl`'s own docstring (lines 24-80) documents BOTH variants and explicitly
  names `Interruptible` as the Variant-1 example (line 34) — this reference must be updated
  or removed once the conversion lands (the docstring's "Used by `[Interruptible]`" claim at
  line 34 becomes stale).
- **Blast radius — 4 call sites to update** (per RESEARCH.md Pitfall 3), located via:
  ```
  grep -rn "contribute!(.*Interruptible\|= contribute!(load\|= contribute!(d," test/
  ```
  Files: `test/test_device.jl`, `test/test_linear_solve.jl`, `test/test_conformance.jl`,
  `test/test_planning_oracle.jl`. Each currently does `p = contribute!(load, ctx; T)`
  expecting `p` indexable as `p[t]`; update to either wrap the load in a minimal `Aggregator`
  (mirroring the FIX-05 Aggregator test pattern above) or destructure `res.vars.p` directly
  where a standalone (non-aggregated) smoke-test is what's actually wanted.

---

### `src/devices/Thermostatic.jl` / `src/devices/Deferrable.jl` — optional `φ` override field (FIX-05)

**Analog:** each other (sibling Variant-2 devices) + `PVBattery.jl`'s optional-field
discipline (`q_inject`, `hasproperty`-checked).

**Pattern:** per CONTEXT.md, "Optional per-device φ override field (default: fall back to
aggregator φ)." Mirror the EXISTING optional-field convention the codebase already
establishes for `q_inject` (`AbstractDevice.jl:67-80`, "A device WITHOUT [it]... simply OMITS
the... key"): add an OPTIONAL `φ::Union{Nothing,T}` field (or a separate zero-arg-defaulted
keyword) to `Thermostatic`/`Deferrable`/`Interruptible` structs, checked via
`hasproperty(d, :φ) ? d.φ : agg.φ` in the Aggregator roll-up above — NOT a required
constructor argument (would break every existing call site). Since none of the three structs
currently has a `φ` field, the simplest byte-identical-default-preserving approach is an
optional KEYWORD argument on the outer convenience constructor defaulting to `nothing`,
mirroring `Deferrable`'s own existing `E_min::Real = 0` optional-keyword pattern
(`Deferrable.jl:73-81`, `138-149`):
```julia
function Deferrable(bus, t_start, t_end, E, Pmax, b; E_min::Real = 0)   # existing pattern
```
Copy that exact "optional keyword on both inner and outer constructor, validated in the
inner one" shape for `φ`.

---

### `src/pricing/dlmp.jl` — `decompose_dlmp` coefficient re-derivation (pure post-solve, transform)

**Analog:** itself — this is a re-derivation task on the EXISTING formula, not a new-pattern
task. No external analog needed; the file's own header comment documents HOW the original
coefficient was derived and that same empirical-certification method must be repeated.

**Current code to re-derive** (`src/pricing/dlmp.jl:267`):
```julia
volt_b[b, t] = -2 * r * (dual(vdrop[b, t]) + dual(cpydrop[b, t]))  # 3.33/3.43 (voltage)
```
**What must happen (execution-time empirical task, NOT a priori algebra per RESEARCH.md
Open Question 2):** after the FIX-01/02 cpydrop sign flip lands, re-run
`decompose_dlmp`'s own HARD sum-to-price assertion (lines 289-307,
`worst_res <= tol || error(...)`) on a solved fixture and determine whether the correct
post-fix formula is `-2*r*(dual(vdrop) - dual(cpydrop))`, some other linear recombination,
or numerically unchanged — treat the file's own header derivation-comment block (lines
34-53) as the TEMPLATE to update once the new coefficient is confirmed (same style: state
the KKT-stationarity path, cite the telescoping-path argument, note it was empirically
certified to machine precision on named fixtures).
- The `_assert_priceable` PF-04 gate (lines 65-86) and `assert_socp_exact!` are UNAFFECTED —
  per RESEARCH.md Pitfall 5, do not touch `src/models/exactness.jl`.
- `src/admm/DsoOpt.jl` reuses `cpydrop` VERBATIM (comment: "VERBATIM ConvexBranchFlow reuse")
  — no separate ADMM-side fix, but its own convergence-behavior tests
  (`test/test_experiments.jl`'s IEEE-13 "knife-edge canary") must be re-run, not assumed
  stable.

---

## Shared Patterns

### Thesis-equation-number annotation convention
**Source:** every file in `src/powerflow/`, `src/devices/`, `src/pricing/` (e.g.
`ConvexBranchFlow.jl:50-65`, `PVBattery.jl:26-32`, `dlmp.jl:34-53`)
**Apply to:** every touched constraint/comment in this phase.
```julia
# Every constraint/expression carries an inline comment citing its thesis equation number,
# e.g.:
@constraint(m, cpydrop[b = 1:nB, t = 1:T], ...)   # thesis eq. 3.43
```
This is a hard house convention (per CLAUDE.md: "Every constraint annotated with its thesis
equation number") — every new/modified constraint in this phase must keep or gain this
annotation, and any DIRECTION/SIGN change must update the accompanying prose, not just the
code.

### Throw-based constructor/argument guards, never `@assert`
**Source:** every device constructor (e.g. `PVBattery.jl:113-154`, `Deferrable.jl:82-123`,
`RestrictedBranchFlow.jl:124-132`)
**Apply to:** any new optional field/kwarg this phase adds (`soc_terminal`, `φ` override).
```julia
if !(condition)
    throw(ArgumentError("<Device> requires <condition> (<thesis-eq-or-rationale>); got <val>"))
end
```
Project convention is explicit: "@assert can be elided under -O" — always `throw`, cite the
thesis equation or research rationale, and echo the offending value(s) in the message.

### Aggregatable-device (Variant-2) contract
**Source:** `src/devices/AbstractDevice.jl:50-80`, exemplified by `Thermostatic.jl`,
`Deferrable.jl`, `PVBattery.jl`, `FourQuadBESS.jl`
**Apply to:** `Interruptible.jl`'s FIX-05 conversion.
```julia
# contribute!(d::SomeDevice, ctx::ModelContext; T::Int) builds vars/constraints on ctx.model,
# writes NOTHING to ctx.residuals, calls NO add_to_objective!, and RETURNS:
return (; vars = (; ...), p_inject, utility)          # + optional q_inject (D-09 widened contract)
```

### Anonymous JuMP `Parameter`/constraint construction to avoid object-dictionary collisions
**Source:** `PVBattery.jl:263-288` (`soc0`, `Ppv_param`), `Aggregator.jl:172-183`
(`Pdc_param`), `FourQuadBESS.jl:322-328` (`soc0`), `Thermostatic.jl:253-263`
**Apply to:** any NEW per-device Parameter/constraint this phase introduces (e.g. a
`soc_terminal` Parameter, if implemented as one).
```julia
# NEVER: @variable(m, some_name[t=1:T] in Parameter.(...))   -- collides across multiple
#        device instances sharing one model ("An object of name X is already attached").
# ALWAYS: @variable(m, [t=1:T], set = Parameter(...))         -- anonymous, composes freely.
```
This is a documented "21-05 deviation / Rule 1" project-wide discipline — any new Parameter
this phase's fixes add MUST follow it or a multi-device/multi-aggregator model will crash on
the second instance.

### `register_constraint!` for every network-level constraint
**Source:** `src/core/ModelContext.jl:74-76`; exemplified throughout `ConvexBranchFlow.jl`
(`:cone`, `:vdrop`, `:cpydrop`, `:smax`)
**Apply to:** the new FIX-03 `:smax_rev` container.
```julia
register_constraint!(ctx, :smax_rev, smax_rev)   # dual = receiving-end congestion (3.37)
```
Device-LEVEL constraints (inside `PVBattery`/`FourQuadBESS`/etc.) are, by contrast,
deliberately NOT registered (only network-level `ConvexBranchFlow` constraints are) — do not
register the SOC recursion or apparent-power cone inside device files.

### Test-file `@testitem` / `@testmodule` fixture conventions
**Source:** `test/fixtures_phase4.jl` (`Phase4Fixtures` `@testmodule`), `test/test_pricing_fit.jl`
(`FitFixtures` `@testmodule`), `test/test_restricted_branch_flow.jl` (inline 2-3-bus literal
construction)
**Apply to:** the new FIX-01 3-bus heavy-load/low-voltage fixture and the FIX-03 PV
back-feed fixture.
```julia
@testmodule SomeFixtures begin
    using TSODSO
    using TSODSO: Bus, Branch, Feeder
    const T = ...
    function feeder()
        buses = [Bus(1, vmin, vmax, true), Bus(2, vmin, vmax, false), ...]
        branches = [Branch(from, to, r, x, smax), ...]
        return Feeder(buses, branches, root)
    end
end

@testitem "<file-tag>: <behavior> (<REQ-ID>)" tags = [:<file_tag>] setup = [SomeFixtures] begin
    using TSODSO, JuMP
    ...
    @test <assertion>
end
```
Every `@testitem` name embeds the seam tag (e.g. `"restricted_branch_flow: ..."`,
`"socp: ..."`) even though (per `test_pricing_fit.jl`'s own note) there is no active
`occursin`-based filter wired into `runtests.jl` today — this is a DOCUMENTATION/
organizational convention, still expected to be followed.

## No Analog Found

None. Every file this phase touches or creates has a strong, concrete in-repo analog —
this is a correctness-fix phase operating entirely within existing seams (`ConvexBranchFlow`
delegation, the aggregatable-device contract, the DLMP dual-read seam), not a new-feature
phase requiring foreign patterns.

## Metadata

**Analog search scope:** `src/powerflow/`, `src/devices/`, `src/models/`, `src/pricing/`,
`src/units/`, `test/` (targeted reads + greps, no exhaustive directory walk needed — the
CONTEXT.md/RESEARCH.md `code_context` and `Integration Points` sections already enumerated
every file with file:line precision).
**Files scanned (full read):** `ConvexBranchFlow.jl`, `RestrictedBranchFlow.jl`,
`PVBattery.jl`, `FourQuadBESS.jl`, `Aggregator.jl`, `Interruptible.jl`, `Thermostatic.jl`,
`Deferrable.jl`, `AbstractDevice.jl`, `mpc_window.jl`, `dlmp.jl`, `Feeder.jl` (partial),
`ModelContext.jl` (partial).
**Files scanned (grep/targeted):** `test_restricted_branch_flow.jl`,
`test_convex_branch_flow.jl`, `fixtures_phase4.jl`, `test_pricing_fit.jl`, `PerUnit.jl`.
**Pattern extraction date:** 2026-09-28

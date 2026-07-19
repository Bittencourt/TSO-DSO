---
phase: 04-convex-branch-flow-correctness-milestone
reviewed: 2026-07-19T01:11:48Z
depth: deep
files_reviewed: 5
files_reviewed_list:
  - src/powerflow/ConvexBranchFlow.jl
  - src/models/exactness.jl
  - src/models/welfare_solve.jl
  - src/models/oracle.jl
  - src/data/ieee13.jl
findings:
  critical: 0
  warning: 3
  info: 2
  total: 5
status: issues_found
---

# Phase 4: Code Review Report

**Reviewed:** 2026-07-19T01:11:48Z
**Depth:** deep (cross-file: ConvexBranchFlow ↔ exactness ↔ welfare_solve ↔ oracle, plus supporting ModelContext/Feeder/PerUnit/Aggregator/factory)
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Phase 4 is the correctness keystone: a third `AbstractPowerFlow` (SOCP DistFlow with the
LinDistFlow exactness copy), the price-refusal exactness gate, priced-export welfare, the
operational oracle, and the modified IEEE-13 fixture. I traced the SOCP model against the
LinDistFlow analog and the shared residual seam, the exactness gate against the cone it
certifies, the welfare/objective signs against the balance-closure math, and the fixture
against `assert_radial`/`assert_magnitudes`/`to_pu_power`.

**The core modeling is sound.** Specifically I confirmed (independent of the pre-verified
list): the rotated-cone indexing (`v[B[b].from]`) matches the exactness-gate indexing
(`pv.v[br.from]`); the loss terms `−r·l`/`−x·l` are charged at the child node consistently
with the DistFlow receiving-end convention; the true drop `+(r²+x²)l` vs copy drop
`−2(r²+x²)l` are internally consistent; the priced-export term `−λ₀ᵀp_import` is sign-correct
for both buy and sell and cannot manufacture phantom welfare (export is capacity-bounded by
active-only DERs, and `p_import = P_head` is pinned by the radial balance, so free-sign import
cannot be exploited into unboundedness even at negative λ₀); the node→index `k→k+1` map is
off-by-one-free and radial; `to_pu_power(6.86, 100) = 0.0686`; the reactive-channel capture
and the `:l`-keyed gate are correctly data-driven with no formulation branching.

**No BLOCKER survives.** The material findings are a coherent theme: two correctness/safety
gates (SOCP exactness τ, SOCP battery-complementarity τ) use **absolute** tolerances whose
protective strength is **scale-dependent on the 100 MVA per-unit base**, where distribution
quantities are ~`1e-3`…`1e-2` pu. On this base the gates can accept a mildly-inexact
relaxation / a small-but-real simultaneous charge-discharge; the *same physical* defect would
be caught on a smaller base. Plus a silent proxy in the oracle's z-pin.

## Warnings

### WR-01: SOCP exactness gate uses an absolute tolerance that weakens with the 100 MVA base; docstring conflates duality-gap with cone-residual

**File:** `src/models/exactness.jl:57-68` (and rationale at `:42-46`; `src/models/welfare_solve.jl:236-238`)

**Issue:** The gate asserts `max|l·v − (P²+Q²)| < τ` with an **absolute** `τ = 1e-5` pu.
On the IEEE-13 fixture the base is `S_base = 100 MVA` and the head limit is `0.0686` pu, so
branch flows are ~`1e-3`…`7e-2` pu and `l·v ≈ P²+Q² ≈ 5e-3`. An absolute gap of `1e-5` is
therefore ~0.2% **relative** cone slack. The protection is base-dependent: the *same physical
feeder* on a `1 MVA` base would have flows ~1 pu, `P²+Q² ≈ 1`, and the identical 0.2% slack
would be `2e-3 > τ` → correctly **rejected**. So whether a given physical inexactness refuses
prices or silently returns them depends on the per-unit base, not on the physics — a
scale-dependence hazard in the project's headline "trust the prices" gate.

The docstring rationale ("`τ = 1e-5` sits ~2 orders above Clarabel's `tol_gap_abs/rel = 1e-8`")
conflates two different quantities: Clarabel's `tol_gap` is the **interior-point duality gap**
in the solver's internal scaling, not the **physical cone-slack residual** `l·v−(P²+Q²)` in
per-unit². The margin argument does not transfer between them.

**Fix:** Make the gate relative (scale-free), e.g. normalize by the RHS magnitude:

```julia
scale = max(rhs, 1e-8)              # rhs = P² + Q²
maxrel = max(maxrel, abs(lhs - rhs) / scale)
# ...
maxrel < τ_rel || error("SOCP relaxation INEXACT: max rel gap=$maxrel ≥ τ_rel=$τ_rel …")
```
with `τ_rel ≈ 1e-4`…`1e-3`. Alternatively keep an absolute τ but derive it from the base
(`τ ∝ (S_ref/S_base)²`) and correct the docstring to reference the cone-slack/feasibility
tolerance rather than the duality gap.

### WR-02: SOCP battery-complementarity tolerance (1e-4) can mask a genuine simultaneous charge/discharge on the 100 MVA base

**File:** `src/models/welfare_solve.jl:101, 243-256`

**Issue:** The complementarity check asserts `value(p_ch[t])·value(p_dch[t]) < τ` with the
default `τ = (problem_class(pf) isa SOCP ? 1e-4 : 1e-6)` — a **100× looser absolute** gate on
the SOCP path. On the 100 MVA base, per-house battery powers are ~`1e-2`…`1e-3` pu. A genuine
*simultaneous* charge and discharge of, e.g., `p_ch = p_dch = 3e-3` pu (0.3 MW each on this
base) yields a product `9e-6 < 1e-4` and **passes** — the exact physical violation the check
exists to catch (App. C, threat T-03-13). Because the product of two small pu quantities
shrinks quadratically with the base, the absolute `1e-4` threshold does not distinguish
"numerical noise on a true zero" from "both legs genuinely nonzero." The stated justification
(conic vars reported to ~`1e-6`…`1e-8`, so noise on the zero leg gives product ~`1e-9`) argues
for a threshold like `1e-8`, not `1e-4`; the two-order jump to `1e-4` also admits real
violations up to ~`1e-2 × 1e-2`.

**Fix:** Scale the complementarity check by the variable magnitudes (relative test) instead of
a fixed absolute product, so it is base-independent and still tolerant of solver noise:

```julia
den = max(abs(value(v.p_ch[t])), abs(value(v.p_dch[t])), 1e-8)
rel = value(v.p_ch[t]) * value(v.p_dch[t]) / den   # ≈ the smaller leg's magnitude
rel < τ_rel || error("Battery complementarity violated …")   # τ_rel ≈ 1e-5
```
This flags "min(p_ch, p_dch) is non-negligible" regardless of the MVA base, and does not
loosen the QP path.

### WR-03: `_coupling_dual` z-pin proxy is effectively silent (@debug off by default), contradicting the stated "no silent partial pinning" intent

**File:** `src/models/oracle.jl:157-174` (see also `:112-117`)

**Issue:** When a caller passes a non-`nothing` `z` (the SEAM-01 coupling setpoint), the pin
is documented but NOT wired; `_coupling_dual` returns the *unpinned* frontier DADP as a proxy
and only emits `@debug`. `@debug` is disabled by default in Julia, so a future planning-layer
caller that passes `z` expecting `p_import == z` to be enforced receives an unpinned proxy dual
with **zero visible signal** that the constraint was ignored. This directly undercuts the
module's own stated guarantee (threat T-04-13: "NO silent partial pinning") and is inconsistent
with the loud `throw` used for an invalid `role` two functions up. A wrong coupling price fed
into the Phase 8/9 Stackelberg loop is a silent-wrong hazard exactly of the kind the phase is
meant to preclude.

**Fix:** Make the not-yet-implemented pin loud rather than silently proxied — either throw, or
emit a visible-by-default `@warn`:

```julia
if z !== nothing
    @warn "operational_oracle: z-pin (p_import == z) is a PLAN-01/02 (Phase 8/9) extension \
           point and is NOT enforced in Phase 4; returning the UNPINNED frontier DADP as a \
           proxy π — do not consume as a pinned coupling price." maxlog=1
end
```
(Or `throw(ArgumentError(...))` if no caller legitimately passes `z` in v1.)

## Info

### IN-01: Duplicated `99.0` no-limit sentinel across two files with no single source of truth

**File:** `src/powerflow/ConvexBranchFlow.jl:31` (`_SMAX_NO_LIMIT = 99.0`) and `src/data/ieee13.jl:39` (`IEEE13_INTERIOR_SMAX = 99.0`)

**Issue:** The "interior branch is unconstrained" semantics depend on two independently
declared `99.0` literals being equal: the fixture tags interior branches with
`IEEE13_INTERIOR_SMAX`, and `contribute!(::ConvexBranchFlow, …)` drops the SOC power cone via
`br.smax < _SMAX_NO_LIMIT`. The coupling is implicit and relies on exact float equality of two
separate constants in different modules. Practical impact is low (a mismatch yields either a
correct skip or a huge non-binding limit ~90 pu that never binds against ~`0.07` pu flows), so
this is not a correctness bug today — but it is a fragile magic-number duplication.

**Fix:** Export a single `SMAX_NO_LIMIT` constant (e.g. from `units/PerUnit.jl` next to
`SMAX_PU_MAX`) and reference it from both the fixture and the formulation, so the sentinel has
one source of truth.

### IN-02: Fixture header says "13-node" but the modified feeder has 11 buses / 10 branches

**File:** `src/data/ieee13.jl:1-14, 47`

**Issue:** The file/comment names it the "IEEE 13-node feeder" while the modified thesis case
is 11 buses (root + 10 aggregator nodes) and 10 branches. The node→index table and body docs
are correct and unambiguous, but the "13-node" label in the header can mislead a reader
skimming for topology size.

**Fix:** Note explicitly in the header that the *modified* thesis case collapses the IEEE-13
to 11 buses (root MEM node 0 + 10 load nodes), so the name is historical, not a count.

---

_Reviewed: 2026-07-19T01:11:48Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_

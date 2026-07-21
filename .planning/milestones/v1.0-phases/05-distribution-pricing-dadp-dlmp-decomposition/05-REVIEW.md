---
phase: 05-distribution-pricing-dadp-dlmp-decomposition
reviewed: 2026-07-19T00:00:00Z
depth: deep
files_reviewed: 5
files_reviewed_list:
  - src/pricing/dlmp.jl
  - src/pricing/fit.jl
  - src/pricing/checks.jl
  - src/pricing/welfare.jl
  - src/powerflow/ConvexBranchFlow.jl
findings:
  critical: 1
  warning: 2
  info: 1
  total: 4
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-07-19
**Depth:** deep (cross-file, with live reproduction on the Clarabel SOCP path)
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Phase 5 produces the project's PRICES and the headline research result, so I ran the
actual solves (not just static reading) to confirm sign conventions. Most of the phase is
sound and provably so:

- `decompose_dlmp` reconstructs the four-way split to machine precision (verified residual
  `1.4e-14` on a 3-bus path); its distinct-dual strategy means a per-branch mislabel would
  break the sum, so the total-price identity genuinely protects the loss/congestion/voltage
  attribution. Component signs are economically sensible (loss negative in reverse flow,
  congestion ~0 off the head, small positive voltage term).
- `economic_direction_checks` is non-vacuous: the test suite proves it by negating `λ₀`
  for the `:pv_glut` regime and negating the DADP for `:congestion`, both of which correctly
  invert the expected relation and throw.
- `fit.jl`'s FIT-OPT flow identities are exact (`net = exp − imp = Ppv − p_h`), the German-FIT
  price triple has coefficient `λ_self − λ_export + λ_import = +2.6 > 0` on `self`, so
  self-consumption is correctly maximized; the FIT vs DADP comparison is apples-to-apples
  (both solved on the same voltage-relaxed feeder).
- The `05-01` `:smax` loop→named-container change is feasible-set-identical (same
  `B[b].smax < _SMAX_NO_LIMIT` predicate, same rotated/SOC cones, only a registered handle
  added).

**However, the prosumer/DSO surplus split in `welfare.jl` is sign-inverted** (CR-01). This is
exactly the "two wrongs summing right" failure the phase brief warned about: the reported
prosumer surplus and DSO surplus are economically nonsensical, but the surplus identity holds
vacuously so every assertion passes and the suite is green. The `+25%`/`ratio` headline itself
is unaffected (it reads `objective_value`), but the surplus *split* — a stated PRICE-03
deliverable (thesis page 98) — is wrong.

## Critical Issues

### CR-01: Prosumer and DSO surplus are sign-inverted (silently wrong headline split)

**File:** `src/pricing/welfare.jl:118-122`

```julia
prosumer = util - transfer                        # AGR-OPT value (3.46)
dso = (_transfer_flip ? -transfer : transfer) - mem_cost
```

**Issue:** The `Σ_j Σ_t λ_j[t]·p_agⱼ[t]` price-transfer term is applied with the wrong sign in
BOTH settlements, where `p_agⱼ = net injection` (`entry.net`, from `solve_welfare` line 183:
`net = p_inject − Pdc`) and `λ_j > 0` = marginal cost of consumption (per `extract_dlmp`'s own
docstring).

Economics: a prosumer that INJECTS (exports) net power should be PAID `λ_j·net`, so its surplus
is `U + λ_j·net`. A consumer (net < 0, draws) pays `λ_j·(−net)`, so its surplus is
`U − λ_j·(−net) = U + λ_j·net`. Either way `prosumer = util + transfer`. The code computes
`util − transfer`. Symmetrically the DSO surplus should be `−transfer − mem_cost`, not
`transfer − mem_cost`.

Live reproduction (2-bus, `allow_export=true`, aggregator is a NET EXPORTER with
`net ≈ +0.575` and `λ ≈ +40`):

```
transfer Σλ·net = 69.20
util = -3.60 ,  mem_cost = -69.59 ,  social(obj) = 65.99
CODE:    prosumer = -72.80   dso = 138.79   (sum = 65.99)   <-- reported
CORRECT: prosumer = +65.60   dso =  +0.39   (sum = 65.99)
```

The reported DSO surplus (`138.79`) is more than **2× the entire social welfare** (`65.99`),
and the exporting prosumer is reported as having a large NEGATIVE surplus — both economically
impossible at a DADP optimum where individual rationality should give non-negative surpluses.
The correct split (exporter earns `+65.6`, DSO keeps only the tiny loss markup `+0.39`) sums to
the same social welfare, which is precisely why the identity assertion cannot detect the error
(see WR-01).

This originates upstream in the research extraction (`05-RESEARCH.md:213-217` literally
specifies `Pro = Σ_j[U − Σ_t λ_j·p_agⱼ]` with `p_agⱼ` = net injection). The latent sign clash
is that thesis eq. 3.22 defines `p_ag` as net *injection*, while the AGR-OPT surplus (3.46) must
subtract the cost of energy *purchased* (net *demand* = −net injection); the code used the 3.22
convention uniformly and inverted the settlement.

**Fix** (confirm the final sign against thesis eqs. 3.46/3.47, page 85-86, but the economic
direction is unambiguous — an exporter must earn):

```julia
prosumer = util + transfer                        # AGR-OPT value (3.46): U + λ·(net injection)
# −DSO-OPT value (3.47): DSO pays prosumers for injections, buys from MEM at λ₀.
dso = (_transfer_flip ? transfer : -transfer) - mem_cost
```

Then add a direct sign assertion so this cannot regress silently (see WR-01), e.g. that at a
DADP optimum both `prosumer` and `dso` are ≥ −tol.

## Warnings

### WR-01: Surplus identity is algebraically vacuous w.r.t. the transfer term; docstring oversells it and no test guards the individual signs

**File:** `src/pricing/welfare.jl:138-150` (assertion) and `:44-47` (docstring claim)

**Issue:** The docstring calls the identity "the load-bearing correctness gate" and claims "a
sign error or dropped term in ONE settlement breaks the cancellation and throws." This is false
in the production path. `transfer` is computed once (line 105-114) and appears as `−transfer`
in `prosumer` and `+transfer` in `dso`, so:

```
prosumer + dso = (util − transfer) + (transfer − mem_cost) = util − mem_cost
```

The transfer cancels for ANY value or sign of `transfer`. The identity therefore reduces to
`util − mem_cost ≈ objective_value` — it validates the objective composition and the KKT
root-price equality, but validates NEITHER the transfer term NOR the DADP `λ_j`. A wrong-signed
`transfer` (CR-01) passes it untouched. The `_transfer_flip` self-test only fires because it
flips ONE of the two occurrences — something that never happens in real use — so it proves the
`error()` path *can* execute, not that the production split is validated. Combined with
`test_pricing_welfare.jl` asserting only `isfinite(prosumer)`/`isfinite(dso)` and the identity
(never the sign/magnitude of the individual surpluses), this is what allowed CR-01 to ship green.

**Fix:** Correct the docstring to state the identity only certifies `objective ≈ util − mem_cost`
and does NOT certify the prosumer/DSO split; add an independent check on the split (e.g.
`prosumer ≥ −tol && dso ≥ −tol` at a DADP optimum, or cross-check `prosumer` against a
directly-resolved AGR-OPT value on a fixture).

### WR-02: `extract_dlmp`/`decompose_dlmp` `T` truncation keeps the LEADING hours, but the docstring says it "truncates the leading hours"

**File:** `src/pricing/dlmp.jl:101-102` (and `:250-251`)

**Issue:** `return M[bus, 1:Tsel]` returns the FIRST `Tsel` hours (drops trailing). The docstring
(line 93) says "a shorter `T` truncates the leading hours," which reads as dropping the leading
hours and keeping the trailing ones — the opposite subset. A caller trusting the docstring to get
an evening window would silently receive the morning hours.

**Fix:** Align docstring and code. Either state "keeps the first `T` hours" or, if a trailing
window was intended, slice `M[bus, (Tfull−Tsel+1):Tfull]`. Same wording fix applies to
`decompose_dlmp`'s `rows = 1:Tsel` (line 251).

## Info

### IN-01: `_path_branches` rebuilds the child→parent-branch map on every node call

**File:** `src/pricing/dlmp.jl:110-127`

**Issue:** `_path_branches(feeder, j)` reconstructs `child_branch` (a full pass over
`feeder.branches`) on each of the `N−1` non-root calls, giving `O(N·B)` map builds. Correctness
is fine (radial tree, unique path). Noted only for maintainability — performance is explicitly
out of v1 review scope. If desired, hoist the `child_branch` dict to `decompose_dlmp` and pass it
in (built once).

---

_Reviewed: 2026-07-19_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: deep_

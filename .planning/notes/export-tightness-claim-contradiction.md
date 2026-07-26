---
title: welfare_solve.jl's priced-export tightness claim is contradicted by EXACT-04
date: 2026-07-26
context: Found during the v3.0 exploration session while answering "can we solve without the relaxation?"
status: OPEN — live inconsistency in shipped code and shipped docs
severity: documentation overclaim, not a correctness bug
---

# `welfare_solve.jl`'s priced-export tightness claim is contradicted by EXACT-04

## The claim, as shipped

`src/models/welfare_solve.jl:50-54`:

> "Priced export is the SOC-EXACTNESS enabler (PF-04): it makes the welfare objective **strictly
> decreasing in the loss current `l`** (every unit of `l` costs export revenue), so the SOC cone
> `l·v ≥ P²+Q²` stays TIGHT in the over-voltage / reverse-flow regime instead of going slack
> (inexact). Import-only leaves losses-vs-curtailment welfare-equivalent, breaking that condition."

This is the classical objective-monotonicity condition, stated correctly, and the mechanism it
describes is real: PV is curtailable (`0 ≤ pv_used[t] ≤ Ppv[t]`, `src/devices/PVBattery.jl:29`), so
under an import-only frontier, dumping surplus PV via curtailment and dumping it via losses are
welfare-equivalent — monotonicity in `l` breaks and the cone goes slack.

## The contradiction

**EXACT-04 ran with `allow_export = true` and the cone went slack anyway.**

- `test/test_ac_oracle.jl:187` — `allow_export = true` on the SOCP solve
- `test/test_ac_oracle.jl:191` — `allow_export = true` on the AC solve
- `docs/literate/ac_oracle.jl:84,89` — same, in the published literate page
- `test/test_ac_oracle.jl:236` — "DOCUMENTED FINDING (EXACT-04): at pv_scale = 1.2 the SOC relaxation
  goes genuinely INEXACT"

So priced export is **not sufficient** to keep the cone tight. The docstring asserts a guarantee the
codebase's own headline finding refutes, and both the docstring and the finding are shipped.

## Why this matters more than a stale comment

1. **It is in the published docs.** The literate pages and the API docs carry the claim.
2. **It is the stated rationale for a design decision** (PF-04 / the `allow_export` default), so the
   decision's justification is weaker than recorded — the flag may still be right, but not for the
   reason given.
3. **It is the answer to [[../research/questions.md — Q2]], half-written already.** The v3.0 brief
   flagged the exactness mechanism as an unverified recollection; in fact the codebase states it, and
   states it in a form that is demonstrably incomplete. Resolving this *is* resolving Q2.

## Hypothesis for the missing term — NOT DERIVED

Priced export makes `l` **costly** (at roughly `λ₀·r` per unit), but with the voltage upper bound
binding, slack `l` may be **beneficial**: the `(r² + x²)·l` term in the branch voltage-drop relation
means inflating `l` buys voltage feasibility. So the cone would go slack when

```
(value of relieving the binding voltage bound)  >  (export revenue lost to r·l)
```

i.e. roughly when `reduced_cost(v[j,t]) · ∂v/∂l  >  λ₀ · r`.

If that is the right shape it explains two observed things the current docstring cannot:

- **Why it is a knife edge** — it is a comparison of two prices, not a structural property.
- **Why the voltage band is decisive** — a looser band means the upper bound does not bind, so there
  is no benefit to buying slack. Directly predicts the IEEE-13 (`0.95/1.05`) vs IEEE-123 (`0.9/1.1`)
  divergence recorded in [[socp-validity-envelope]].

**Both quantities are already computed or trivially available:** `reduced_cost(v[j,t])` (the bound is
a JuMP variable bound, `src/powerflow/ConvexBranchFlow.jl:142`) and the per-branch `r`. Testable
without new machinery.

⚠️ This is a hypothesis about the shape of the missing condition. It has **not** been derived, and the
`∂v/∂l` factor is stated loosely. Do not put it in a paper before deriving it properly against
Farivar & Low (2013) / Gan et al. (2015).

## Additional wrinkle worth checking

The classical exactness conditions assume a plain loss-minimising objective. This model's objective is
concave prosumer utility minus import cost, with batteries and deferrable loads. That structural
difference may itself be why priced export is insufficient — and if so it is the genuinely novel part.
See [[../research/questions.md — Q2]] item 3.

## What to do

Minimum: soften the docstring from a guarantee to a *necessary-but-not-sufficient* condition, citing
EXACT-04 as the counterexample. Do not leave a refuted guarantee in published docs.

Better: derive the actual condition, then state it. That is Q2, and it is the same work that
[[prices-as-duals-lapse]] needs before it can claim anything.

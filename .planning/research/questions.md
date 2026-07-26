# Open Research Questions

Questions that need deeper investigation before or during a milestone. Each records why it matters
and what would answer it — not a guess at the answer.

---

## Q1 — Does the binding-set predicate actually predict SOCP inexactness?

**Raised:** 2026-07-26 (exploration session, v3.0 scoping)
**Blocks:** the v3.0 validity-envelope method — see [[../notes/socp-validity-envelope]]
**Status:** open

### The question

The Farivar & Low (2013) / Gan et al. (2015) sufficient conditions say the radial SOC branch-flow
relaxation is exact when the **upper voltage bounds do not bind** and the objective stays monotone in
branch flow. That suggests a cheap predicate, computable free off every SOCP solve:

```julia
binding  = value(v[j,t]) ≈ vmax^2          # src/powerflow/ConvexBranchFlow.jl:142 (variable bound)
shadow   = reduced_cost(v[j,t])
reverse  = value(P[b,t]) < 0
```

v3.0's whole cost model depends on this predicate standing in for the expensive AC oracle
(`assert_ac_exact!`, `src/models/ac_oracle.jl:148`, one nonconvex Ipopt solve per point) across a
dense 3D grid.

**But a sufficient condition run backwards is not a test.** "Not binding ⇒ exact" does not give
"binding ⇒ inexact". So:

1. **Precision** — of the points the predicate flags, what fraction are measurably inexact?
2. **Recall** — of the measurably inexact points, what fraction does the predicate flag?
3. Is there a *third* signature (reverse flow without binding? binding without reverse flow? a
   near-binding margin band?) that improves either?

### Why recall is the load-bearing half

Poor **precision** is merely conservative: the envelope is drawn too large, some trustworthy prices
get stamped as suspect, nothing false is claimed.

Poor **recall** is a correctness failure. Inexact points the predicate misses mean the dense sweep
**undercounts** the invalid region, the envelope is drawn too small, results get stamped valid when
they are not — and the pre-registered WIDE/NARROW gate in
[[../seeds/overvoltage-capable-relaxation]] reads NARROW for the wrong reason.

### What would answer it

An AC-verified subsample deliberately designed to **hunt false negatives** — drawn from points the
predicate calls *exact*, especially near the predicted boundary and in the high-PV/reverse-flow
neighbourhood. A subsample drawn only from predicate-flagged points measures precision and
**cannot measure recall at all**; that sampling mistake would silently invalidate the envelope.

Report both numbers with the sample size. If recall is poor, say so and treat the NARROW verdict as
unreliable rather than reinterpreting the gate.

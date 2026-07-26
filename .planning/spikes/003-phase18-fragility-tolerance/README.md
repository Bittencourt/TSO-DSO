---
spike: 003
name: phase18-fragility-tolerance
type: standard
validates: "Given Phase 18-01's ±2-5% population sweep re-run at tightened solver tolerance, when the shipped exactness gate stays armed, then we learn whether the recorded 'fragility' is a tolerance artifact or a physical boundary"
verdict: VALIDATED
related: [001, 002]
tags: [socp, exactness, tolerance, phase18, thesis-reproduction, correction, fit-baseline, misattribution]
---

# Spike 003: Is Phase 18-01's population fragility a tolerance artifact?

## Verdict

**VALIDATED — and it overturns a shipped v2.1 finding.**

`results/repro_stability_check/findings.txt` records `sign_flip_survives: false`, attributing all four
perturbed-point failures to `solve_welfare`'s SOCP-exactness gate and concluding the thesis
DSO-surplus sign flip "does NOT survive ±2%/±5% population-scale perturbation in EITHER direction."

Both halves of that are wrong:

1. **Two of the four failures were `fit_baseline`, not `solve_welfare`.** Phase 18-01's single
   try/catch wrapped `solve_welfare` + `welfare_accounting` + `fit_baseline` together, so the findings
   text attributed every failure to `assert_socp_exact!` in `solve_welfare`. Proven by bit-identical
   ratios (table below).
2. **The `solve_welfare` failures are purely numerical.** 0 of 5 points throw at `tol_gap = 1e-10`,
   at unchanged optima.
3. **The sign flip DOES survive `δ = −0.05`** — a point recorded as failing outright.

## How to Run

```bash
julia --project=. .planning/spikes/003-phase18-fragility-tolerance/check.jl   # ~20 solves
```

The shipped gate is left **ARMED** (default `rtol_exact = 1e-4`) throughout — only the *solver*
tolerance changes. The question is whether the gate still fires when the solver converges properly,
not whether it can be bypassed.

**Equivalence control passed bit-for-bit:** `δ=0` at default reproduces the committed
`dso = 3.725705` and `socp_maxgap = 3.060e-07`. The replication is faithful to
`scripts/repro_stability_check.jl`, so every discrepancy below is real.

## Results

```
                   default tol_gap=1e-8              tight tol_gap=1e-10
delta   gate      socp_maxgap  dadp_dso   fit_dso   gate     socp_maxgap  dadp_dso   fit_dso   flip
-0.05   THREW     —            —          —         PASSED   3.505e-08    2.709838   -182.96   YES
-0.02   PASSED*   1.810e-07    3.277536   —         PASSED   1.900e-08    3.277535   —         —
 0.00   PASSED    3.060e-07    3.725705   -196.22   PASSED   1.162e-08    3.725742   -196.22   YES
+0.02   THREW     —            —          —         PASSED   4.610e-08    4.163925   —         —
+0.05   PASSED*   1.215e-06    4.807424   —         PASSED   1.342e-08    4.807417   —         —

* solve_welfare passed; fit_baseline then threw (see misattribution below)
```

`solve_welfare` gate: **2/5 threw at default → 0/5 at tight.**

### Finding 1 — Phase 18-01 misattributed 2 of 4 failures

Committed error ratios vs. what this run shows actually threw:

| δ | findings.txt ratio | actually threw in | this run's ratio | identical? |
|---|---|---|---|---|
| −0.05 | 2.685423204302964 | `solve_welfare` | 2.685423204302964 | ✓ |
| −0.02 | 3.227073440795618 | **`fit_baseline`** | 3.227073440795618 | ✓ |
| +0.02 | 1.1425393613288473 | `solve_welfare` | 1.1425393613288473 | ✓ |
| +0.05 | 1.1002062714021996 | **`fit_baseline`** | 1.1002062714021996 | ✓ |

Bit-identical to 16 digits. **Clarabel is deterministic; nothing here is flaky.** The failures always
reproduced — the findings text simply named the wrong call for two of them, because one try/catch
covered three solves and the error was assumed to come from the SOCP gate.

At `δ=+0.02` **both** fail: `solve_welfare` numerically at default, and `fit_baseline` underneath it.
Tightening reveals the second one.

### Finding 2 — the `solve_welfare` failures are numerical, conclusively

| δ | gap @ 1e-8 | gap @ 1e-10 | shrink | dadp_dso @ 1e-8 | @ 1e-10 |
|---|---|---|---|---|---|
| −0.05 | 3.100e-6 (threw) | 3.505e-08 | 88× | — | 2.709838 |
| −0.02 | 1.810e-07 | 1.900e-08 | 9.5× | 3.277536 | 3.277535 |
| +0.02 | 1.581e-6 (threw) | 4.610e-08 | 34× | — | 4.163925 |
| +0.05 | 1.215e-6 | 1.342e-08 | 91× | 4.807424 | 4.807417 |

Where comparable, `dadp_dso` agrees to **6-7 significant figures** while the residual drops one to two
orders of magnitude. Same optimum, better-converged residual — the definition of a numerical artifact.
Consistent with [spike 002](../002-ieee123-validity-map/README.md): the gate's `atol = 1e-6` sits at
Clarabel's noise floor on this 122-branch feeder.

### Finding 3 — the DADP side has no knife edge whatsoever

```
δ:         −0.05     −0.02      0.00     +0.02     +0.05
dadp_dso:  2.7098    3.2775    3.7257    4.1639    4.8074
```

Strictly positive, smooth, **monotone increasing** in population scale across the entire ±5% band.
There is no boundary, no discontinuity, and no fragility on the DADP side. Phase 17's "genuine
asymmetric exactness knife-edge" (cited by 18-RESEARCH.md Pitfall 4 and carried into the findings
narrative) is not visible in this quantity at all.

### Finding 4 — the sign flip survives −5%

`δ = −0.05`: `dadp_dso = +2.709838`, `fit_dso = −182.9611` → **sign flip YES**, at a point the committed
findings record as `FAILED` in every column.

Where `fit_dso` is measurable it is −183 to −196 — nowhere near marginal, so the *sign* is not in doubt
at those points.

### Finding 5 — `fit_baseline` cannot be tolerance-conditioned (concrete `src/` defect)

`fit_baseline` (`src/pricing/fit.jl:271`) has **no `optimizer` kwarg**, unlike `solve_welfare`
(`src/models/welfare_solve.jl:105`). So it always runs at default tolerance and its exactness failures
at `δ = −0.02, +0.02, +0.05` are untestable — they persist bit-identically in both runs for that reason
alone, not because they are physical.

Whether they are *also* numerical is **unknown**. It is plausible: same feeder, same default tolerance,
same noise-floor mechanism that spike 002 proved for `solve_welfare`, and the failures are non-monotone
in δ (fails at ±0.02 and +0.05, succeeds at −0.05 and 0.0) with ratios 1.10–3.73 sitting in exactly the
band spike 002 identified as noise.

**Adding an `optimizer` kwarg to `fit_baseline`, mirroring `solve_welfare`, is the single change that
would make the population-robustness question answerable.** Small, mechanical, and it unblocks a
published claim.

## The correction that is owed

`sign_flip_survives: false` should read, on this evidence:

> Survives at δ = −0.05 and 0.00 (measured: `dadp_dso > 0`, `fit_dso < 0`).
> **Unmeasurable** at δ = −0.02, +0.02, +0.05 — blocked by `fit_baseline`'s exactness gate, which
> cannot be tolerance-conditioned. `dadp_dso` is strictly positive and monotone across the whole band.

"Does not survive perturbation in either direction" and "survives at −5%, unmeasurable elsewhere" are
materially different claims. The first is in `results/repro_stability_check/findings.txt`, in
18-01-SUMMARY.md, and — per 18-03 — in the published assumptions literate page. **All three need
correcting, not annotating.**

Downstream check needed: Plan 18-02's golden band (`DSO_BAND_HI = 5.58855710237937`) was derived as
`1.5 × max|dso|` over "successfully solved points" — which was 1 point. With 5 points now solving, the
observed max is 4.8074, so `1.5 × 4.8074 = 7.211`. The pinned band is **narrower than its own
derivation rule now implies**, though 4.8074 still falls inside `[0, 5.5886]`, so the existing
`test_thesis_repro.jl` gate does not break. Worth re-deriving deliberately rather than leaving a rule
and a value that disagree.

## My own error, recorded

Mid-run I claimed run-to-run nondeterminism — "half the recorded failures don't reproduce" — and built
a coin-flip-across-the-threshold story on it. **Wrong.** All four reproduce bit-for-bit. I was comparing
my per-stage `solve_welfare` result against findings.txt rows that had *merged* three solves, so two
`fit_baseline` failures looked like `solve_welfare` passes that contradicted the record. The lesson is
the same one spike 002 taught in reverse: when comparing against a prior measurement, first confirm the
two are measuring the same call.

## Honest Limits

1. **5 points, one seed** (`20260719`). Shows the recorded fragility is not what it claims; does **not**
   establish population robustness, which needs a wider sweep once `fit_baseline` is conditionable.
2. **3 of 5 points still have no `fit_dso`.** The sign flip is confirmed at 2 points, not 5.
3. **`fit_baseline`'s failures remain undiagnosed** — plausibly numerical, untested. Do not assert they
   are artifacts without the kwarg fix and a re-run.
4. **`tol_gap = 1e-10` is not free.** Spike 002 saw `ALMOST_OPTIMAL` refusals at this tolerance on other
   points of this feeder; none occurred here, but it is not a safe global default.
5. No AC-oracle cross-check. "Exact at tight tolerance" here means the cone closed, not that the
   solution was verified against nonconvex AC.

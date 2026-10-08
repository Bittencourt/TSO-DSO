# Phase 27: Integer Planning & Pricing Certificate Correctness - Research

**Researched:** 2026-09-29
**Domain:** Julia/JuMP parametric convex optimization (Benders recourse under T>1), convex-duality
DLMP decomposition, SOCP-exactness certification, and MPC ground-truth settlement — all within the
existing `src/planning/`, `src/pricing/`, `src/models/`, `src/experiments/` seams.
**Confidence:** HIGH on code-level facts (all claims below are `[VERIFIED: direct code read]` of
this repo's own `src/`/`test/` files unless tagged otherwise); MEDIUM-HIGH on the recommended
algorithm for FIX-06 (a design synthesis over verified convexity facts, not itself pulled from an
external source); LOW/`[ASSUMED]` only on the FIX-09 ALMOST_OPTIMAL root cause, which prior
sessions explicitly left open (see Open Questions).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**corner_recourse T>1 — FIX-06**
- IMPLEMENT the true T>1 recourse `Q(y) = min_{z∈[0,y]^T} [follower_cost(z) − oracle_welfare(z)]`
  as a genuine joint convex minimization (not per-hour-independent unless proven separable, not
  `fill(z,T)`); Phase 30's multi-bus Benders will need T>1.
- Validation oracle: exhaustive grid enumeration on a small T=2 fixture; the Laporte–Louveaux loop
  must match its optimum (and cuts) within a MEASURED tolerance.
- Remove the scalar `fill(z,T)` path; T=1 must stay byte-identical (the joint minimization reduces
  to the existing ternary search at T=1).

**DLMP component naming — FIX-07**
- Rename components after their multipliers: `cone` (rotated-SOC cone-slot multiplier) and `drop`
  (voltage-drop / copy-drop multipliers); `congestion` and `energy` unchanged.
- Keep `loss`/`voltage` as DEPRECATED aliases (one-time deprecation warning), removal scheduled for
  Phase 36 (Code & Export Cleanup).
- Replace the "voltage component ≈ 0 when unbinding" test with correct properties on a
  realistic-impedance fixture (IEEE-13 slice): exact sum-to-price identity, and each component is
  zero iff its multiplier is zero.

**Per-branch exactness floor — FIX-08**
- Per-branch absolute floor `atol_b = ε·ref_b` with `ref_b = S̄_b²` for thermally limited branches,
  else the head-branch flow magnitude; replaces the global `atol = 1e-6`.
- ε MEASURED on the canonical fixtures: the largest ε that flags the new synthetic slack-cone test
  while all genuinely-exact fixtures pass; measurement recorded.
- Any fixture newly flagged inexact is a FINDING: triage it and ESCALATE to the user before any
  relaxation — never raise ε to hide it.

**FIT certificate + MPC settlement — FIX-09/10**
- FIT baseline: assert exactness by default (throw on inexact); opt-in `on_inexact=:report` returns
  the certificate in the result. Never skip.
- `ALMOST_OPTIMAL` flake at `tol_gap=1e-10`: root-cause first; if solver-intrinsic, explicitly
  bound it (accept ALMOST_OPTIMAL only with a certified gap under a documented tolerance).
- MPC truth plant: realized PV clips charging, settlement uses true import, and true-state
  propagation THROWS on an SOC bound violation; the forecast-settled number survives only as a
  clearly labelled `forecast_settled_welfare` diagnostic.

**Golden policy + process (SC-6, lessons from Phase 26)**
- Same as Phase 26: every moved golden re-pinned in-phase with old→new + cause comment and a
  GOLDEN-AUDIT table; no silent re-pin.
- Run a full post-merge suite AFTER EACH WAVE (not only at phase end) and triage by root cause
  before the next wave — Phase 26 found 55 downstream failures only at the end.
- Executors in parallel worktrees never edit STATE.md/ROADMAP.md; findings go to 27-FINDINGS.md.
- Machine limit: ≤3 concurrent Julia executors (4 cores / 15 GB).

### Claude's Discretion
- Exact joint-minimization algorithm for T>1 (single JuMP model vs. projected descent), exact
  new DLMP field names' spelling, ε measurement protocol details.

### Deferred Ideas (OUT OF SCOPE)
- Removal of deprecated DLMP aliases — Phase 36.
- App. C η<1 complementarity treatment — unscheduled backlog (Phase 26 finding).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FIX-06 | `corner_recourse` returns the true per-hour `Q(bᵛ)` for T>1, validated against exhaustive enumeration on a T>1 fixture | § Standard Stack / Architecture Patterns "FIX-06" — algorithm recommendation (nested cutting-plane reusing existing duals), convexity proof already in-tree, T=1 dispatch preserved |
| FIX-07 | DLMP components named/documented after their true multipliers (`cone`/`drop`), deprecated `loss`/`voltage` aliases, corrected voltage-unbinding test | § Architecture Patterns "FIX-07" — exact derivation already in `dlmp.jl` header, full blast-radius grep (13 files), `Base.depwarn` alias mechanism recommendation |
| FIX-08 | Per-branch relative exactness floor `atol_b = ε·ref_b`, slack-cone-on-small-branch test | § Architecture Patterns "FIX-08" — exact current formula read from `exactness.jl`, concrete `ref_b` definition, ε measurement protocol |
| FIX-09 | FIT-baseline exactness never skipped; `ALMOST_OPTIMAL` flake root-caused/bounded | § Common Pitfalls "FIX-09" — exact code-path gap found (FIT AC-PF step 2 of 3 has NO exactness gate at all), prior-session flake evidence collected, root-cause hypotheses ranked |
| FIX-10 | MPC realized welfare/regret settle against the true plant; forecast-settled kept as diagnostic | § Architecture Patterns "FIX-10" — exact current (forecast-consistent) settlement mechanism quoted from source, concrete truth-settlement algorithm proposed with an explicit open engineering choice flagged |
</phase_requirements>

## Summary

This phase touches five narrow, already-well-documented seams — every one of the five fixes has
its root cause already diagnosed in-tree (in docstrings, `26-POSTMERGE-TRIAGE.md`, or
`.planning/notes/socp-validity-envelope.md`) from prior phases' own investigation. None require a
new package, a new solver, or new modeling theory: FIX-06 is a parametric-convex-optimization
generalization of code already present; FIX-07 is a rename plus a Julia deprecation idiom; FIX-08
is a formula change to an existing function; FIX-09 closes a gate that was simply never wired to
one specific solve; FIX-10 corrects a settlement convention its own docstring already flags as an
approximation.

**Primary recommendation:** implement FIX-06 as a small in-process cutting-plane ("bundle")
loop that reuses the SAME `solve_follower!`/`solve_planning_oracle!` calls and the SAME dual reads
(`follower_res.π_s`, `oracle_res.π`) already used to build the OUTER Benders cuts — this is
literally a miniature nested Benders loop minimizing over the box `[0,y_inv]^T` instead of over
`(y,z)` jointly, requires no new solver dependency, and collapses to the current ternary search
at `T=1` via an explicit `T==1` dispatch (preserving byte-identical output there).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| T>1 recourse minimization (FIX-06) | Planning/Benders (`src/planning/benders.jl`) | Follower LP + Oracle SOCP (already-built subproblems) | `corner_recourse` is pure planning-layer orchestration; it must not duplicate follower/oracle model-building |
| DLMP component naming (FIX-07) | Pricing (`src/pricing/dlmp.jl`) | Docs/scripts consumers (13 files) | Pure post-processing over solved duals; no network/model-layer change |
| Exactness floor (FIX-08) | Correctness gate (`src/models/exactness.jl`) | Feeder/Branch data (`smax`, `SMAX_NO_LIMIT`) | The gate reads per-branch `smax` already on `Feeder.branches`; no new data needed |
| FIT certificate (FIX-09) | Pricing counterfactual (`src/pricing/fit.jl`) | Correctness gate (`assert_socp_exact!`) | The FIT AC-PF step must call the SAME gate `solve_welfare` already calls — this is a wiring fix, not new theory |
| MPC truth settlement (FIX-10) | Experiment orchestration (`src/experiments/mpc_loop.jl`) | Device dynamics (`propagate_soc`/`propagate_tin`, `src/models/mpc_window.jl`) | Settlement/accounting change only; the window MODEL itself (build-once JuMP) is untouched |

## Standard Stack

No new packages for this phase. Every fix is implemented with the already-pinned stack
(JuMP 1.30.x, Clarabel 0.11.1, HiGHS 1.24.1) `[VERIFIED: Project.toml / CLAUDE.md, unchanged]`.
FIX-06's recommended cutting-plane inner loop needs only a tiny LP (`Min θ` subject to a handful of
affine cuts over `z ∈ R^T`) — solvable with the SAME `select_optimizer(LP())` factory
`src/planning/follower.jl` already uses; no new solver class.

## Package Legitimacy Audit

Not applicable — this phase adds zero new external packages. Skipped per the gate's own scope note
("required whenever this phase installs external packages").

## Architecture Patterns

### FIX-06 — `corner_recourse` for T>1

**Current state `[VERIFIED: src/planning/benders.jl:129-187]`.** `corner_recourse(oracle,
follower, y_inv, T)` runs a scalar ternary search over `z ∈ [0, y_inv] ⊂ R`, then evaluates
`Qfun(z) = fr.cost - orr.cost` by calling `solve_follower!(follower, fill(z, T))` and
`solve_planning_oracle!(oracle, fill(z, T))` — i.e. it pins the SAME scalar trial value at every
one of the `T` hours. The docstring is explicit that this is "the natural minimal generalization,"
not a claim of joint-multivariate optimality.

**Why the box is genuinely a hypercube, not per-hour-independent boxes
`[VERIFIED: src/planning/master_integer.jl:107-156]`.** The master's own constraint is
`box_hi[t]: z[t] <= y_inv` for every `t`, where `y_inv` is a SINGLE scalar (`y_inv = (y_max/2^K) *
Σ_k 2^(k-1) b_k`, one binary-expansion value, not a per-hour vector). So the true recourse is

```
Q(y_inv) = min_{z ∈ R^T, 0 <= z[t] <= y_inv ∀t} [follower_cost(z) − oracle_welfare(z)]
```

— a genuine T-dimensional convex minimization over one shared hypercube, not T independent
1-D problems glued together.

**Convexity is already proved in-tree, not something this phase needs to re-derive
`[VERIFIED: src/planning/master_integer.jl:270-285]`.** The existing `add_ll_cut!`/
`add_optimality_cut!` docstring states: "`Q(y_inv) = min_{0<=z<=y_inv}[α_op(z)+α_x(z)]` is a
partial minimization of a jointly-convex function over a jointly-convex, monotonically expanding
feasible set, hence `Q` is convex... in the continuous relaxation of `y_inv`." The SAME argument
(parametric value function of a convex program is convex in the RHS perturbation `z`, by the
usual sensitivity/envelope theorem) makes `Q(z)` jointly convex over `z ∈ R^T` for FIXED `y_inv` —
this is not a new theorem, it is the SAME sensitivity argument the codebase already leans on for
the outer loop, one level down.

**Is `Q(z)` separable per hour?** NO, not in general. `follower_cost(z)` (the `FollowerLP`,
`src/planning/follower.jl:94-131`) has NO inter-temporal coupling — its only cross-hour term is
`x_inv >= max_t(x_op[t]/corridor_cap)`, so `follower_cost(z)` has a simple closed form:
`c_inv * max_t(z[t]/corridor_cap) + Σ_t c_op[t]*z[t]` (a convex, piecewise-linear function coupled
across hours ONLY through the `max`). `oracle_welfare(z)` (the `PlanningOracle`,
`src/planning/subproblem.jl`) is the value function of the FULL welfare SOCP/QP with `p_import[t]
== z[t]` pinned at every hour — whenever a `PVBattery`/`FourQuadBESS` is present, its `soc[t+1]`
recursion couples hour `t`'s dispatch to hour `t+1`'s, so the oracle's value function is NOT
separable across `t` in general. **Recommendation: do not assume separability; do not implement
per-hour independent ternary searches — this would silently produce a WRONG answer whenever a
battery is in the oracle's aggregator set** (which is the common case on every canonical fixture).

**Recommended concrete algorithm — a nested cutting-plane (Kelley/bundle) loop reusing existing
duals.** Both value functions are already exposed with FIRST-ORDER information at zero extra
solves:

  - `follower_res.π_s` (`= dual.(f.coupling)`, length T) is the exact gradient of
    `follower_cost(z)` w.r.t. `z` — this is the SAME quantity `add_optimality_cut!(master, :x,
    follower_res.cost, follower_res.π_s, ...)` already uses for the outer `:x` cut
    `[VERIFIED: benders.jl:299-301, 533]`.
  - `oracle_res.π` (`= dual.(o.pin)`, length T) is the exact gradient of `-oracle_welfare(z)`
    w.r.t. `z` under the SAME sign convention already pinned and reused verbatim for the outer
    `:op` cut (`add_optimality_cut!(master, :op, -oracle_res.cost, oracle_res.π, ...)`)
    `[VERIFIED: benders.jl:530-531]`.
  - Hence at ANY trial `z`, one call each to `solve_follower!`/`solve_planning_oracle!` yields
    BOTH `Q(z) = follower_res.cost − oracle_res.cost` AND its exact gradient
    `∇Q(z) = follower_res.π_s + oracle_res.π` (elementwise) — no extra solves, no finite
    differencing, no numerical differentiation.

  Algorithm (mirrors the project's own idiom — "hand-roll ADMM and Benders," CLAUDE.md — one
  level down):

  ```
  cuts = []                      # each: (z_i, Q_i, g_i)
  z = fill(y_inv/2, T)           # or any interior start; z=0 is always feasible
  loop up to `iters` times:
      (Q_i, g_i) = evaluate(z)   # one follower solve + one oracle solve, as Qfun already does
      push!(cuts, (z, Q_i, g_i))
      UB = min(UB, Q_i)
      # small master LP: min θ  s.t.  θ >= Q_j + g_j'(z - z_j) ∀ cuts,  0 <= z <= y_inv (elementwise)
      (θ*, z_next) = solve_small_master(cuts, y_inv, T)
      LB = θ*
      converged = (UB - LB) <= measured_tol   # mirror KNOWN_OPTIMUM_ATOL's measure-don't-guess protocol
      z = z_next
  ```

  This is a standard Kelley's cutting-plane method for convex minimization with a first-order
  oracle; it provably converges to the global minimum of a convex function over a convex compact
  set (the box `[0,y_inv]^T`) `[ASSUMED: standard convex-optimization theory, not re-derived from
  a specific textbook this session]`. The small master LP is a T-dimensional LP with `iters` rows
  — trivially cheap on `HiGHS`/`select_optimizer(LP())`, the SAME factory `follower.jl` uses.

**T=1 byte-identical requirement.** Do NOT make the general algorithm collapse to ternary search
algebraically (different floating-point trajectories would break byte-identity even if
mathematically equivalent). Instead, dispatch explicitly: `T == 1` keeps calling the EXISTING
ternary-search code path unchanged; `T > 1` calls the new joint algorithm. This is the
straightforward reading of the locked decision ("T=1 must stay byte-identical... reduces to the
existing ternary search") and needs no new proof.

**Validation fixture.** CONTEXT.md locks "exhaustive grid enumeration on a small T=2 fixture."
`test/test_planning_certification_integer.jl` already has an `enumerate_lattice` reference
implementation and its own `Qfun`/`ternary_min` helpers, but scoped to the existing `K`-bit,
single-scalar-`z` lattice — it does not currently enumerate a T=2 GRID `(z[1], z[2])`
`[VERIFIED: grep of enumerate_lattice, single Qfun(z::Real) signature]`. A NEW small T=2
enumeration oracle (dense grid over `(z[1],z[2]) ∈ [0,y_inv]^2` for a handful of `y_inv` lattice
corners) is needed — build it in the test file mirroring the existing `enumerate_lattice`
pattern, not in `src/`. Reuse the SAME `Qfun` computation (one follower + one oracle solve per
grid point) so the comparison is apples-to-apples with `corner_recourse`'s own internal calls.

**WR-01/CR-01 ternary-search fixes must have joint-algorithm analogues.** The existing docstring's
WR-01 (double-infinite tie-break shrinks toward the known-feasible `z=0` anchor) and CR-01
(`y_inv <= 0` genuinely computes `Qfun(0)`, never assumed `0.0`) protect against a follower
infeasibility (`z` beyond deliverable capacity) making the search diverge. The joint algorithm
needs the SAME `Inf`-extended-value treatment: `Qfun` already returns `Inf` when
`fr.feasible == false` (unmodified), and the small master LP must handle a cut row with
`Q_i = Inf` by EXCLUDING it from the cutting-plane model (an `Inf` affine minorant is
meaningless) rather than feeding `Inf` into a JuMP constraint — this is a genuinely NEW edge case
the ternary search's simpler branch logic didn't have to handle multivariately (in 1-D, `Inf` at
one of two ternary probe points has a clean tie-break; in T-D, an infeasible trial simply
contributes no cut and the search continues from a still-finite incumbent).

### FIX-07 — DLMP component renaming

**Exact current derivation `[VERIFIED: src/pricing/dlmp.jl:1-90, 300-330]`.** The file header
already gives the closed-form KKT derivation:

```
λ_j − λ_i = −( cone_dual_b[3] + 2·r_b·(β_b + γ_b) + smax_dual_b[2] )
```

where `cone_dual_b` is `dual(:cone[b,t])` (the rotated-SOC multiplier, thesis 3.39 — currently
named `loss` in the returned NamedTuple), and `β_b = dual(:vdrop[b])`, `γ_b = dual(:cpydrop[b])`
(the voltage-drop and copy-drop multipliers, thesis 3.33/3.43 — currently named `voltage`).
**These ARE, respectively, the "cone-slot" and "drop-constraint" multipliers CONTEXT.md's locked
decision names** — the rename is a pure LABEL change; the underlying formula
(`loss_b[b,t] = -dual(cone[b,t])[3]`, `volt_b[b,t] = -2*r*(dual(vdrop[b,t])+dual(cpydrop[b,t]))`,
`src/pricing/dlmp.jl:310-318`) needs ZERO numeric change — rename the local variables and the
returned NamedTuple keys only.

**Deprecation mechanism recommendation.** `decompose_dlmp` currently returns a PLAIN `NamedTuple`
(`(; energy, loss, congestion, voltage, reactive, total)`). A plain `NamedTuple` has no hook for a
"one-time deprecation warning on field access" — `nt.loss` is a direct field read, not a function
call. **Recommend switching the return type to a small immutable struct** (e.g.
`DlmpDecomposition`) with fields `energy, cone, drop, congestion, reactive, total` and a custom
`Base.getproperty` override:

```julia
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

`Base.depwarn` is Julia's own built-in deprecation-warning primitive (respects the `--depwarn`
startup flag, integrates with `Test.detect_ambiguities`-style CI checks, prints once per call site
by default) — no new dependency, and it is the IDIOMATIC choice for exactly this "old field name
still works, but warns" contract `[CITED: Julia Base, Base.depwarn — a standard-library function,
not project-specific]`. Confirm at implementation time that struct-with-`getproperty` does not
break existing destructuring call sites (`(; energy, loss, ...) = decompose_dlmp(ctx)` — Julia's
property destructuring calls `getproperty` per field, so this pattern is preserved automatically).

**Blast radius (13 files touch `.loss`/`.voltage` or call `decompose_dlmp`)
`[VERIFIED: grep -rln '\.loss\b\|\.voltage\b\|decompose_dlmp' src test docs scripts]`:**

| File | Usage |
|------|-------|
| `src/pricing/dlmp.jl` | Definition site (rename here) |
| `src/powerflow/ConvexBranchFlow.jl` | Comment only ("dual feeds the loss/voltage DLMP component") — update comment |
| `test/test_dlmp.jl:77` | Sum-to-price assertion using `.loss`/`.voltage` |
| `test/test_pricing_dlmp.jl` (6 call sites: lines 155,163,174,212,223,267,275,286,433) | Sum-to-price assertions AND the "voltage ≈ 0 when unbinding" test targeted by this fix |
| `test/test_admm_reactive.jl` | Grep hit — confirm at implementation time whether it reads DLMP fields or is a false-positive match |
| `test/test_thesis_repro.jl` | Grep hit — confirm at implementation time |
| `docs/literate/pricing_dlmp.jl:118,120,182` | Literate doc source (regenerates `docs/src/generated/pricing_dlmp.md`) |
| `docs/literate/thesis_reproduction_ieee123.jl` | Grep hit — confirm at implementation time |
| `scripts/pv_boom_report.jl:83,85`, `scripts/pv_boom_report_v2.jl:83,85` | Report scripts reading `decomp.loss`/`decomp.voltage` |
| `scripts/demo_flexibility_plots.jl:426,428` | Same |
| `scripts/thesis_caseA.jl:345,347` | Same |

Since the alias mechanism keeps `.loss`/`.voltage` WORKING (with a warning), none of the
consumer files strictly MUST change in this phase — but CONTEXT's "documented after what they
mathematically are" intent argues for updating at least the two literate-doc files (they are the
published, citable documentation) to the new names, leaving the scripts/tests on the alias unless
a plan wave chooses to update them too.

**Corrected test property (replacing "voltage ≈ 0 when unbinding")
`[VERIFIED: test/test_pricing_dlmp.jl:275]`.** The current test
(`@test isapprox(d.voltage[2, t], 0.0; atol=1e-4)  # in-bound ⇒ ≈ 0`) asserts the component is
near-zero whenever voltage is not binding — CONTEXT's locked decision says this must be replaced
"on a realistic-impedance fixture (IEEE-13 slice)" with: (1) the exact sum-to-price identity
(already exists elsewhere in the file, e.g. line 267/433 — keep it, now spelled with `cone`/`drop`)
and (2) "each component is zero IFF its multiplier is zero" — i.e. `d.drop[j,t] == 0` if and only
if `dual(:vdrop[b,t]) == 0 AND dual(:cpydrop[b,t]) == 0` for every branch `b` on `j`'s root path
(and symmetrically for `d.cone`/`dual(:cone[b,t])[3]`), rather than a magnitude-based "≈0 when
physically unbinding" claim that the old test conflated with the `thesis_literal` sign-flip
finding from Phase 26 (26-GOLDEN-AUDIT.md's PM-01: neither exactness-copy direction is a genuine
relaxation, so "voltage bound not binding" and "drop-multiplier is zero" are not the same physical
statement post-Phase-26).

### FIX-08 — Per-branch exactness floor

**Exact current formula `[VERIFIED: src/models/exactness.jl:78-107]`.**

```julia
tol = atol + rtol * max(abs(lhs), abs(rhs))     # SAME atol=1e-6 for EVERY branch
```

The `rtol` term already scales with the CONE'S OWN magnitude at the operating point (`lhs`/`rhs`),
so it is already somewhat branch-relative — but on a lightly loaded branch BOTH `lhs` and `rhs`
sit near zero, collapsing the effective bound to the flat `atol` term for every branch regardless
of that branch's physical scale (its `smax`). A branch whose thermal capacity `S̄_b` is small (e.g.
a fine-grained lateral) can therefore have a slack cone that is LARGE relative to `S̄_b^2` but still
pass, because `1e-6` was calibrated against head-branch-scale fixtures.

**Recommended concrete formula (CONTEXT already locks the two cases; this pins the data source):**

```julia
ref_b = branches[b].smax < SMAX_NO_LIMIT ? branches[b].smax^2 : head_flow_mag2[t]
atol_b = ε * ref_b
tol = atol_b + rtol * max(abs(lhs), abs(rhs))
```

where `head_flow_mag2[t] = value(P[head_b, t])^2 + value(Q[head_b, t])^2` — the SAME `(P²+Q²)`
quantity already computed for every branch, read at the HEAD branch (the branch incident to
`feeder.root`, i.e. `br.from == feeder.root` — confirmed the canonical convention on every fixture:
IEEE-13 "head branch (thesis 0→1, struct index 1→2)," IEEE-123 "head branch (frontier terminal
150→149)," IEEE-8500 "head branch... either endpoint equal to IEEE8500_ROOT_BUS"
`[VERIFIED: src/data/ieee13.jl:80, ieee123.jl:404, ieee8500.jl:212]`) — used as the network-scale
reference for INTERIOR (unlimited, `SMAX_NO_LIMIT` sentinel) branches, since they carry no `smax`
of their own to normalize against. `SMAX_NO_LIMIT` is already an exported/available constant
`[VERIFIED: src/units/PerUnit.jl, referenced project-wide]`.

**ε measurement protocol (Claude's discretion per CONTEXT, but a concrete recipe is
recommended, mirroring `KNOWN_OPTIMUM_ATOL`'s own "measure, don't guess" precedent,
`src/planning/benders.jl:42-62`):**

 1. Build the CONTEXT-mandated new synthetic test fixture: a small branch (low `smax` or an
    interior unlimited branch) with a DELIBERATELY slack cone (e.g. force `l` above `P²+Q²` by a
    known, injected amount via a synthetic/hand-built `ctx`, mirroring how `test_exactness.jl`'s
    existing fixtures already inject `@test_throws` cases).
 2. Sweep `ε` from loose to tight and, at each value, run the FULL existing canonical-fixture
    suite that currently passes `assert_socp_exact!` (IEEE-13, IEEE-123, the 2-bus fixtures) to
    find the largest `ε` that (a) makes the new slack-cone test FAIL (correctly flagged inexact)
    while (b) every genuinely-exact canonical fixture still PASSES.
 3. Record the sweep result and the chosen `ε` value with a comment citing the measurement
    (mirrors `KNOWN_OPTIMUM_ATOL`'s and `_EXACT04_MEASURED_ε`'s existing precedent of a named,
    commented, measured constant rather than a hand-picked one).
 4. Per the LOCKED escalation policy: if any EXISTING canonical fixture flips from exact to
    inexact at the chosen `ε`, this is a FINDING (not a bug to quietly fix by loosening `ε`) —
    write it to `27-FINDINGS.md` and escalate to the user before proceeding, exactly as Phase 26's
    cluster-E/G/H/I findings were handled.

**Interaction with Phase 26's per-fixture `tol_gap` calibrations
`[VERIFIED: 26-GOLDEN-AUDIT.md items "D-26-01"/"D-26-02"/cluster E]`.** Phase 26 already tightened
several fixtures' Clarabel `tol_gap_abs`/`tol_gap_rel` (e.g. `1e-9`, `5e-10`, `3e-9`) specifically
to keep `assert_socp_exact!`'s FLAT `atol=1e-6` from tripping on precision-floor artifacts on
near-lossless/large fixtures. Changing `atol` to a per-branch `atol_b` may shrink the effective
floor further on some of THOSE SAME fixtures (a near-lossless 2-bus's `smax=10` branch would get
`ref_b = 100`, so a LOOSER `atol_b` there if `ε` is calibrated conservatively — or TIGHTER if `ε`
turns out small) — re-run the cluster-E fixtures (`test_pricing_dlmp.jl:22/221`,
`test_pricing_welfare.jl:66`, `test_admm.jl:27/127`, `test_planning_oracle.jl:269`, the IEEE-123
cluster) FIRST after implementing FIX-08, before touching anything else, since these are the
fixtures most likely to flip status again.

### FIX-09 — FIT-baseline certificate + ALMOST_OPTIMAL flake

**The exactness gate is currently NEVER CALLED on `fit_baseline`'s own FIT AC-PF step
`[VERIFIED: src/pricing/fit.jl:320-378]`.** `fit_baseline` performs THREE solves:

 1. `_fit_opt_solve` (a per-prosumer QP, no network, no `:l`) — correctly gated by
    `assert_solved!` only (no SOCP cone exists here).
 2. **The FIT AC-PF** (`Model(optimizer)` at line 324, `contribute!(pf, ctx, relaxed; T)`) — THIS
    is the step the file's own header comment calls "a plain AC power flow" and "the same
    export-as-loss-penalty mechanism as the DADP solve," relying on the SOC cone being driven
    tight by the loss-penalty objective — but it is gated ONLY by `assert_solved!(model;
    dual=false)` (line 378). **`assert_socp_exact!` is never called on this ctx.** If `pf` is
    `ConvexBranchFlow` (the only formulation this file is exercised with in practice), this step
    IS solving an SOC relaxation and its exactness is silently ASSUMED, never verified.
 3. `solve_welfare(...)` (line 407, the nested DADP reference solve, "SITE 3 of 3") — this ALREADY
    carries its own internal `assert_socp_exact!` call (inherited from `solve_welfare`'s own
    gate), so it is this step that is documented as flaking with `ALMOST_OPTIMAL` at tight
    `tol_gap` (see below) — but note this gate protects `social_dadp`, a cross-check value, not
    `social_fit` itself.

**FIX-09's "certify exactness, never skip" therefore needs a NEW `assert_socp_exact!` call
wired into step 2** (the FIT AC-PF), with the CONTEXT-mandated `on_inexact::Symbol = :error`
default (throw) / `:report` opt-in (return the certificate in the result rather than throwing) —
mirroring the EXISTING `on_violation` kwarg pattern already used elsewhere in this codebase
(`assert_battery_complementarity!(...; on_violation::Symbol=:error)`,
`src/models/welfare_solve.jl:284`, and `assert_restriction_exact!(...; report::Bool=true)`,
referenced from `mpc_loop.jl:621`) — this is a PROJECT-STANDARD idiom, not a new pattern to
invent. `fit_baseline`'s return NamedTuple gains a `socp_maxgap`/`exactness_certificate` field
when `on_inexact=:report`, following the SAME shape `o.ctx.meta[:socp_maxgap]` already uses
elsewhere (`subproblem.jl:298`).

**The `ALMOST_OPTIMAL` flake — prior-session evidence, NOT yet root-caused (HIGH-confidence
evidence, LOW-confidence root cause).** Extensive prior investigation
(`.planning/notes/socp-validity-envelope.md`, quick tasks `260823-gea`/`260822-hld`/`260822-oi7`)
already measured, but explicitly left OPEN:

  - At `tol_gap=1e-10`, `solve_welfare`'s OWN SOCP-exactness gate resolves 5/5 on the swept
    fixture — the inexactness-vs-tolerance question for `solve_welfare` is CLOSED.
  - `fit_baseline`'s NESTED `solve_welfare` call (SITE 3) returns `ALMOST_OPTIMAL`/
    `NEARLY_FEASIBLE_POINT` at 3 of 5 points at that SAME `tol_gap=1e-10`, reproduced across 3
    runs (flake rate 13/20 = 0.650 in the `repro_stability_check.jl` script)
    `[VERIFIED: 260823-gea-SUMMARY.md, socp-validity-envelope.md]`.
  - Quick task `260822-hld` found a DIFFERENT but structurally similar case (IEEE-8500) where
    `ALMOST_OPTIMAL` is a genuine solver conditioning wall, NOT fixable by any tolerance choice
    tried (both looser AND tighter `tol_gap` failed) — "do NOT attempt to fix the centralized
    ALMOST_OPTIMAL status... a separate, genuine conditioning question."
  - `highs-exactness-defaults` memory (this session's `[MEMORY.md]`) documents an ANALOGOUS class
    of bug (HiGHS `mip_rel_gap`/`mip_feasibility_tolerance` defaults silently undercutting an
    "exact" claim) — worth checking whether Clarabel has an equivalent silently-defaulted
    attribute interacting with `tol_gap=1e-10` specifically (e.g. `max_iter`, `equilibrate_enable`,
    or a static-regularization floor that becomes the binding constraint before the duality gap
    target is reached at very tight tolerances) — **this is a concrete, previously-untried
    hypothesis for THIS phase to test**, distinct from every retry/tolerance-ladder approach
    already exhausted in prior sessions.

**Recommended root-cause protocol for this phase (not yet executed by any prior session):**

 1. Reproduce the 3/5-point flake with `repro_stability_check.jl` (already exists, already
    threads an `optimizer` kwarg per quick task `260726-mo7`).
 2. At a flaking point, inspect Clarabel's OWN reported `status`/`iterations`/residuals in detail
    (not just the terminal `ALMOST_OPTIMAL` symbol) — is it converging SLOWLY (would resolve with
    more iterations / raised `max_iter`) or STALLING (residual plateau, a genuine conditioning
    wall like the IEEE-8500 case)?
 3. If slow-converging: raising `max_iter` (a Clarabel attribute, NOT yet tried per the
    evidence above — every prior attempt varied `tol_gap`/`tol_feas`, none varied `max_iter`) is
    the untried, cheap first move.
 4. If genuinely stalling (matches the IEEE-8500 conditioning-wall precedent): this is
    solver-intrinsic — CONTEXT's fallback applies: "explicitly bound it (accept ALMOST_OPTIMAL
    only with a certified gap under a documented tolerance)" — i.e. widen `solve_with_retry!`'s
    (or a NEW, FIT-baseline-scoped) allow-list to accept `ALMOST_OPTIMAL` PROVIDED
    `dual_objective_value`/`objective_value`'s own gap is measured and asserted under a NAMED,
    measured threshold (mirroring `KNOWN_OPTIMUM_ATOL`'s "measure the solver's own achieved
    precision" protocol, `benders.jl:42-62`) — never a bare "trust ALMOST_OPTIMAL" relaxation.

### FIX-10 — MPC realized-welfare truth-plant settlement

**Current (forecast-consistent) behavior is explicitly self-documented as an approximation
`[VERIFIED: src/experiments/mpc_loop.jl:113-128, 410-415]`.** The `realized_welfare` docstring
states verbatim: **"settlement is FORECAST-CONSISTENT by construction, not re-settled against the
ground truth"** — the frontier term charges the window's OWN solved `p_import[τ]` (balanced
against the FORECAST-perturbed PV/demand the optimizer saw), and "when `fe.pv_factor > 1` the
applied `p_ch` can exceed the TRUE PV availability `d.Ppv[abs_hour]` (Assumption A6 violated on
the ground truth)." Only the STATE propagation (`propagate_tin`) is already truth-anchored (uses
`d.Tout[abs_hour]`, the ground-truth ambient) — `propagate_soc` is NOT (it uses the solved
`p_ch1`/`p_dch1` UNCLIPPED against true PV).

**Device-level constraint this must respect (Assumption A6)
`[VERIFIED: src/devices/PVBattery.jl:29-30]`.** `PVBattery`'s charge is STRUCTURALLY PV-limited,
not grid-chargeable: `0 <= pv_used[t] <= Ppv[t]` and `0 <= p_ch[t] <= pv_used[t]` — the battery can
ONLY charge from its OWN co-located, curtailable PV. This is why "realized PV clips charging" is
the correct physical fix (CONTEXT's locked wording): under the forecast, the optimizer chose
`p_ch[τ]` believing `Ppv[abs_hour]*fe.pv_factor` was available; under TRUTH, only
`d.Ppv[abs_hour]` (unperturbed) is physically available, so the REALIZED charge must be
`min(p_ch_solved[τ], d.Ppv[abs_hour])`, not the solved value verbatim.

**Recommended concrete settlement algorithm:**

 1. **Clip charging.** `p_ch_true = min(value(v.p_ch[τ_apply]), d.Ppv[abs_hour])` (device's own
    TRUE, unperturbed PV availability at the absolute hour) before both (a) the utility
    accumulation and (b) `propagate_soc`'s input — never propagate the unclipped solved value.
 2. **True-state feasibility throws.** After `propagate_soc`/`propagate_tin` compute the next
    measured state, ASSERT it is within `[Emin,Emax]`/`[Tmin,Tmax]` and `throw` (not clamp,
    contrary to `_mpc_window_device`'s existing SEPARATE, explicitly-scoped "solver-tolerance
    noise absorption" clamp at `src/experiments/mpc_loop.jl:759-762`, which is for a DIFFERENT,
    already-in-band case) — CONTEXT's locked wording is explicit: "true-state propagation THROWS
    on an SOC bound violation," a genuinely out-of-band state after a real forecast-error/PV-clip
    event is a modeling finding to surface loudly, not silently absorb.
 3. **True import.** The window's solved `p_import[τ_apply]` balanced the FORECAST-perturbed
    network. Under truth, the net injection at every prosumer bus differs by
    `Δ_bus = (true_demand − forecast_demand) − (true_PV_used − forecast_PV_used)`
    (accounting for the clip in step 1 changing the battery's own net injection too). The
    SIMPLEST physically-defensible true-up (a copper-plate net-injection correction, ignoring the
    SECOND-ORDER change in network losses this would induce) is:
    `p_import_true[τ_apply] = value(o.p_import[τ_apply]) + Σ_bus Δ_bus[τ_apply]`
    — i.e. the substation absorbs the exact real-power mismatch the forecast error and the PV
    clip introduce. **This is the ONE genuinely open engineering choice in this phase** (see
    Open Questions): a FULLY rigorous fix would re-solve a fixed-dispatch power flow (only
    `p_import` free, every device setpoint pinned to its true-clipped value) each applied hour to
    also true-up network losses — more correct but adds a solve per applied hour inside the
    innermost loop. Recommend starting with the copper-plate correction (cheap, no new solve,
    directly implementable) and flagging the loss-truing refinement as an explicit, named
    approximation in the returned NamedTuple's docstring (mirroring this file's OWN existing
    convention of naming its approximations rather than hiding them).
 4. **Keep the old number as a diagnostic.** CONTEXT: "the forecast-settled number survives only
    as a clearly labelled `forecast_settled_welfare` diagnostic" — rename today's
    `realized_welfare` computation (unchanged) to `forecast_settled_welfare` in the returned
    NamedTuple, and add a NEW `realized_welfare` (or a clearly-different name if `regret`'s
    existing consumers need `realized_welfare` to keep meaning "truth-settled" — confirm against
    every test that reads `run_mpc(...).realized_welfare` before renaming; `test_mpc_loop.jl`,
    `test_mpc_terminal.jl` are the direct consumers per the file listing in `CLAUDE.md`'s
    reusable-assets note) compute the truth-settled number from steps 1-3, and re-derive `regret`
    against it.

**Blast radius.** `test_mpc_loop.jl`, `test_mpc_terminal.jl` (both listed as `run_mpc`/
`build_mpc_window` consumers in the Phase 27 CONTEXT's own "Reusable Assets" note) are the two
files most likely to need golden re-derivation — `regret`/`realized_welfare` numeric goldens will
move whenever `s.mpc_forecast_error > 0` in a canonical fixture (a zero-forecast-error fixture is
BYTE-IDENTICAL under this fix, since `p_ch_true == p_ch_solved` and `Δ_bus == 0` when
`fe.pv_factor == fe.demand_factor == 1.0` exactly — confirm this invariant holds in the
implementation, it is a useful regression check).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Convex value-function minimization with a first-order oracle (FIX-06) | A custom gradient-descent line-search with hand-tuned step sizes | A small cutting-plane/bundle LP (reuses `select_optimizer(LP())`) accumulating affine minorants from EXISTING duals | Step-size-free, provably convergent for convex functions, and reuses the SAME dual-read pattern already validated for the outer Benders loop — no new numerical-tuning surface |
| Deprecation warnings on renamed fields (FIX-07) | A hand-rolled `Dict`-based property forwarder with manual "warned once" bookkeeping | `Base.getproperty` override + `Base.depwarn` | Standard library primitive, respects `--depwarn`, already the idiomatic Julia pattern for exactly this |
| Per-branch tolerance calibration (FIX-08) | A single global constant picked by intuition | The measure-then-pin protocol already established by `KNOWN_OPTIMUM_ATOL`/`_EXACT04_MEASURED_ε` | This project's own standing bar ("measure, don't assume," STATE.md cross-cutting note) — reinventing an ad hoc constant here would violate a documented project convention |
| Solver-tolerance flake investigation (FIX-09) | A blind retry-until-it-passes loop, or silently widening `tol_gap` further | The existing `solve_with_retry!`/`RETRYABLE_STATUSES` ladder, extended with a NAMED, measured gap-tolerance if the root cause is confirmed solver-intrinsic | Matches `highs-exactness-defaults`' documented anti-pattern warning and this project's explicit "never widen a tolerance to hide a gate" rule |
| True-plant re-settlement (FIX-10) | A full closed-loop re-simulation framework | The existing `propagate_soc`/`propagate_tin` JuMP-free re-derivation functions, extended with clipping + a copper-plate import correction | These functions already exist for exactly this purpose (D-05's "apply each step's controls to the ground-truth dynamics" contract) — this phase completes their existing, documented, not-yet-finished job |

**Key insight:** every one of these five fixes is closing a gap between what a docstring/comment
ALREADY documents as the intended behavior and what the code ACTUALLY does — this is a
"finish the documented contract" phase, not a "design something new" phase.

## Common Pitfalls

### Pitfall FIX-06-1: Assuming per-hour separability
**What goes wrong:** Implementing T independent 1-D ternary searches (one per hour) instead of a
joint T-dimensional minimization.
**Why it happens:** The T=1 ternary search is simple and tempting to "just repeat T times."
**How to avoid:** Any aggregator with a `PVBattery`/`FourQuadBESS` couples hours via `soc[t+1]`;
the oracle's value function is not separable whenever one is present. Always use the joint
algorithm; never special-case "no batteries ⇒ separable" without an explicit, tested guard.
**Warning signs:** The T=2 grid-enumeration validation test would catch this directly (a
per-hour-independent implementation gives a DIFFERENT — generally worse/wrong — answer than the
true joint minimum whenever the oracle is non-separable).

### Pitfall FIX-06-2: Feeding `Inf` cuts into the master LP
**What goes wrong:** An infeasible follower trial (`fr.feasible == false`) returns `Qfun(z) =
Inf`; naively adding `θ >= Inf + g'(z-z_i)` as a JuMP constraint either errors or silently breaks
the LP.
**Why it happens:** The 1-D ternary search's `isinf` tie-break logic (WR-01) does not generalize
mechanically to a multivariate cutting-plane master.
**How to avoid:** Skip adding a cut row entirely when `Qfun(z_i) = Inf` — an infeasible trial
contributes no valid affine minorant; the incumbent UB and existing finite cuts still bound the
search. `z=0` is always follower-feasible (per the existing docstring's own invariant), so the
box's feasible sub-region is always nonempty.
**Warning signs:** JuMP `ArgumentError`/`Inf` propagating into the small master's objective, or
the master reporting `INFEASIBLE`/`UNBOUNDED` when the true answer should be a finite corner.

### Pitfall FIX-07-1: NamedTuple destructuring silently bypassing the deprecation warning
**What goes wrong:** If `decompose_dlmp` keeps returning a plain `NamedTuple` instead of a
custom-`getproperty` struct, there is NO way to warn on `.loss`/`.voltage` access — Julia
NamedTuples have no property-access hook.
**Why it happens:** A NamedTuple is the path of least resistance and the function already returns
one.
**How to avoid:** Switch to a small immutable struct with `Base.getproperty` override (see
Architecture Patterns above) — confirmed compatible with `(; energy, loss, ...) = decompose_dlmp(ctx)`-style destructuring since Julia's property destructuring calls `getproperty`.

### Pitfall FIX-08-1: Recalibrating ε against a fixture Phase 26 already retuned for a DIFFERENT reason
**What goes wrong:** Several fixtures already have a tightened Clarabel `tol_gap` specifically to
keep the FLAT `atol=1e-6` from tripping on precision-floor noise (Phase 26 cluster E). Changing
`atol` to `atol_b` changes the effective floor on exactly those same fixtures, and it is easy to
conflate "this fixture is inexact under the new floor" with "the tol_gap tuning stopped working."
**How to avoid:** Re-run the cluster-E fixtures FIRST (see Architecture Patterns FIX-08) and
attribute any status change explicitly to the `atol_b` formula change, not the `tol_gap` value —
keep the two tunables' provenance separate in any comment/finding.

### Pitfall FIX-09-1: Treating every ALMOST_OPTIMAL as the SAME root cause
**What goes wrong:** Prior sessions found the IEEE-8500 `ALMOST_OPTIMAL` wall is a genuine,
untunable conditioning limit (neither looser nor tighter `tol_gap` fixed it). It would be easy to
assume `fit_baseline`'s flake is "the same thing" and give up on root-causing it without testing
the untried `max_iter` hypothesis.
**How to avoid:** Follow the FIX-09 root-cause protocol above; distinguish "slow convergence,
fixable by more iterations" from "genuine conditioning wall" BEFORE concluding it is unfixable and
falling back to the "explicitly bound it" contingency.

### Pitfall FIX-10-1: Silently changing what `run_mpc(...).realized_welfare` means downstream
**What goes wrong:** Any caller (tests, scripts, docs) that reads `.realized_welfare` today gets
the FORECAST-consistent number; if this phase renames the truth-settled number to
`realized_welfare` and demotes the old one to `forecast_settled_welfare`, every existing consumer
silently starts reading a DIFFERENT number under the SAME field name.
**How to avoid:** Grep every consumer of `run_mpc(...).realized_welfare`/`.regret` BEFORE
renaming (this research found `test_mpc_loop.jl`/`test_mpc_terminal.jl` as the direct consumers,
per CONTEXT's own "Reusable Assets" note — re-verify exhaustively at implementation time, since a
grep here was not re-run against the full test suite this session) and re-derive/re-pin every
affected golden explicitly, per the phase's own SC-6 golden policy.

## Code Examples

### FIX-06 — reusing existing dual reads as a first-order oracle
```julia
# Source: src/planning/benders.jl:299-301 (existing outer-loop cut, reused verbatim as the
# gradient-read pattern for the new inner cutting-plane loop)
add_optimality_cut!(master, :op, -oracle_res.cost, oracle_res.π, lb_res.z)
add_optimality_cut!(master, :x, follower_res.cost, follower_res.π_s, lb_res.z)
# => the SAME two dual reads, at a trial z inside corner_recourse, give:
#    Q(z)  = follower_res.cost - oracle_res.cost
#    ∇Q(z) = follower_res.π_s .+ oracle_res.π            # elementwise, length T
```

### FIX-07 — deprecation-warning property override
```julia
# Pattern: Julia Base.depwarn (standard library, CITED not project-specific)
struct DlmpDecomposition
    energy::Matrix{Float64}
    cone::Matrix{Float64}
    drop::Matrix{Float64}
    congestion::Matrix{Float64}
    reactive::Matrix{Float64}
    total::Matrix{Float64}
end
function Base.getproperty(d::DlmpDecomposition, s::Symbol)
    s === :loss && (Base.depwarn("... use .cone", :decompose_dlmp); return getfield(d, :cone))
    s === :voltage && (Base.depwarn("... use .drop", :decompose_dlmp); return getfield(d, :drop))
    return getfield(d, s)
end
```

### FIX-08 — per-branch reference scale
```julia
# Source: src/models/exactness.jl:78-107 (existing loop) + src/data/ieee13.jl:80 (head-branch
# convention) — new ref_b computation to splice into the existing per-branch loop
head_b = findfirst(br -> br.from == feeder.root, feeder.branches)
for (b, br) in enumerate(feeder.branches), t in 1:T
    ref_b = br.smax < SMAX_NO_LIMIT ? br.smax^2 :
        value(pv.P[head_b, t])^2 + value(pv.Q[head_b, t])^2
    tol = ε * ref_b + rtol * max(abs(lhs), abs(rhs))
    ...
end
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| `corner_recourse` pins `fill(z,T)` for T>1 | Joint T-dimensional cutting-plane minimization | This phase | T>1 LL cuts become mathematically valid; unblocks Phase 30/31's multi-bus, T>1 Benders |
| `decompose_dlmp` fields named `loss`/`voltage` | Named `cone`/`drop` (their true multiplier identity), old names deprecated | This phase | Docs/consumers must migrate before Phase 36 removes the aliases |
| Flat `atol=1e-6` exactness floor | Per-branch `atol_b = ε·ref_b` | This phase | Some previously-"exact" small/interior branches may newly flag inexact — each such flip is a FINDING, not silently absorbed |
| FIT AC-PF step ungated | FIT AC-PF step exactness-certified (`on_inexact` kwarg) | This phase | `fit_baseline` can now genuinely throw (or report) on an inexact FIT counterfactual — previously silent |
| MPC `realized_welfare` forecast-consistent | Truth-settled `realized_welfare` + `forecast_settled_welfare` diagnostic | This phase | Existing MPC goldens under nonzero forecast error will move; zero-forecast-error fixtures are an implicit regression check (must stay byte-identical) |

**Deprecated/outdated:** the `fill(z,T)` scalar-recourse path (FIX-06) is REMOVED, not merely
deprecated — CONTEXT: "Remove the scalar `fill(z,T)` path."

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A Kelley's-cutting-plane / bundle method converges to the global minimum of a convex function over a convex compact box given an exact first-order (value+gradient) oracle at every trial | Architecture Patterns FIX-06 | If wrong, the recommended T>1 algorithm would need a different convergence argument (e.g. a trust-region/bundle stabilization) — the convexity of `Q(z)` itself is independently `[VERIFIED]` from in-tree docstrings, only the SPECIFIC solution-method's convergence is `[ASSUMED]` standard theory |
| A2 | `head_flow_mag2 = P_head²+Q_head²` (rather than `l_head·v_head` or another head-branch quantity) is the intended "head-branch flow magnitude" CONTEXT.md's locked decision refers to | Architecture Patterns FIX-08 | If the intended reference is a different head-branch quantity, `ref_b`'s formula for interior branches needs adjustment — the TWO-CASE structure (limited vs. unlimited branches) itself is locked, only the exact unlimited-branch formula is `[ASSUMED]` |
| A3 | A copper-plate (network-loss-blind) net-injection correction is an ACCEPTABLE first cut for FIX-10's "true import," with full loss-truing flagged as a documented approximation rather than mandatory in this phase | Architecture Patterns FIX-10 | If the user/planner requires loss-exact truth-settlement, this adds one power-flow-style solve per applied MPC hour inside the innermost loop — a nontrivial cost/complexity increase the CONTEXT decision does not explicitly rule in or out |
| A4 | `fit_baseline`'s `ALMOST_OPTIMAL` flake is EITHER a slow-convergence issue (fixable by raising `max_iter`) OR a genuine conditioning wall (matching the IEEE-8500 precedent) — no OTHER root cause (e.g. a data/formulation bug specific to the FIT counterfactual's voltage-relaxed feeder) was considered by any prior session | Common Pitfalls FIX-09-1 / Open Questions | If the true root cause is FIT-specific (not a generic Clarabel conditioning issue), the recommended protocol's two branches would both fail to resolve it, and a THIRD investigation path (comparing the FIT AC-PF's voltage-relaxed feeder's conditioning against the DADP solve's normal-band feeder) would be needed |

## Open Questions (RESOLVED)

1. **Does the Benders cut validity question flagged in STATE.md's Phase-24 research note (whether
   standard optimality cuts remain valid at the binary-expansion granularity) still block this
   phase?**
   - **RESOLVED — already answered in-tree, no further action needed.**
     `src/planning/master_integer.jl:270-285`'s own docstring gives the full Geoffrion (1972)
     Generalized Benders Decomposition argument: because `y_inv` is a LINEAR function of the
     binary vector `b`, and `Q` is convex over the CONTINUOUS relaxation of `y_inv`, any
     subgradient cut derived at a trial `z_k` is a globally valid supporting hyperplane over the
     entire continuous relaxation — hence valid at EVERY one of the `2^K` binary corners. This
     was resolved by Phase 24's own implementation, cited here for completeness; FIX-06 does not
     need to re-derive or re-verify it, only to correctly COMPUTE `Q(y_inv)` at each corner
     (the actual FIX-06 gap).

2. **Is `oracle_welfare(z)`/`follower_cost(z)` separable per hour when NO battery is present
   (e.g. a Thermostatic/Deferrable-only aggregator set)?**
   - **RESOLVED — do not rely on this even if true in special cases.** `Deferrable`'s
     energy-budget window `[t_start,t_end]` (referenced in `mpc_loop.jl`'s own header deviation
     note) ALSO couples hours, so even a battery-free aggregator set is not guaranteed separable
     in general. The joint algorithm handles both cases uniformly with no correctness risk from
     mis-detecting separability; this question does not need a case-split answer.

3. **Does `fit_baseline`'s FIT AC-PF step (SITE 2) actually solve an SOC relaxation today, or is
   it somehow already AC-exact by construction (as its "plain AC power flow" naming suggests)?**
   - **RESOLVED — it IS an SOC relaxation, not a genuine AC power flow.** `contribute!(pf, ctx,
     relaxed; T)` is called with whatever `pf::AbstractPowerFlow` the caller passed
     (`fit_baseline(feeder, pf, aggregators; ...)`) — when `pf isa ConvexBranchFlow` (the only
     formulation this file's own header comment says is reused: "we reuse the exact
     `ConvexBranchFlow` DistFlow model"), this step solves the SAME SOC relaxation as everywhere
     else in the project, just on a voltage-relaxed feeder. The file's "plain AC power flow"
     language describes the INTENDED physical role (the thesis's own "AC-PF, observe 3.35 not
     enforced" step), not the actual convex relaxation being solved — hence FIX-09's exactness
     gate is genuinely needed here, not redundant.

4. **Which files must change for FIX-07's rename, versus which can stay on the deprecated alias?**
   - **RESOLVED as a recommendation, not a hard requirement.** See the Architecture Patterns
     FIX-07 blast-radius table (13 files). Since the alias mechanism keeps every existing call
     site WORKING, no file strictly must change this phase — the planner should decide, per wave,
     how much of the 13-file blast radius to migrate to the new names now versus deferring to
     Phase 36 (when the aliases are removed and EVERY remaining `.loss`/`.voltage` site becomes a
     hard break).

5. **Root cause of the `fit_baseline` `ALMOST_OPTIMAL` flake at `tol_gap=1e-10`.**
   - **NOT RESOLVED — genuinely open, carried into this phase's own execution.** Every prior
     session's tolerance-ladder approach (looser AND tighter `tol_gap`) was exhausted without
     resolving it; the `max_iter`-raise hypothesis (§ Architecture Patterns FIX-09) is untried and
     recommended as the phase's first concrete experiment. If it fails, CONTEXT's fallback
     applies directly: bound `ALMOST_OPTIMAL` acceptance behind a measured, named gap tolerance,
     exactly as `KNOWN_OPTIMUM_ATOL` was derived from a measured (not guessed) solver gap.

## Environment Availability

Skipped — this phase is pure Julia source-code work against the already-installed, already-pinned
project environment (`Project.toml`/`Manifest.toml`, `test/Project.toml`). No new external tool,
service, or runtime dependency is introduced by any of FIX-06..10.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `Test.jl` stdlib + `TestItems`/`TestItemRunner` 1.0/1.1 (`[VERIFIED: CLAUDE.md stack table]`) |
| Config file | `test/Project.toml` (test-only dependency env, separate from `Project.toml`) |
| Quick run command | Direct `julia --project=. -e '...'` script reproducing the relevant `@testitem` body (TestItemRunner does NOT resolve under `--project=.` — `[MEMORY: gsd-plan-verify-testitemrunner-trap]`) |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` — the ONLY safe full-suite invocation (`[MEMORY: background-suite-orphan-race]`); ~16-23 min, MUST run in the foreground or via a detached `nohup setsid` + polled `.done` marker, NEVER a bare backgrounded `&` that dies when the agent turn ends |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FIX-06 | `corner_recourse` matches exhaustive T=2 grid enumeration within a measured tolerance | unit | direct script reproducing `test_planning_benders_integer.jl`'s / a NEW T=2 `@testitem` body | ❌ Wave 0 — new T=2 enumeration oracle needed, `test/test_planning_certification_integer.jl`'s existing `enumerate_lattice` is single-`z`-scalar scoped |
| FIX-06 | T=1 byte-identical to pre-phase output | unit | existing `test_planning_benders_integer.jl`/`test_planning_master_integer.jl` items, re-run unmodified | ✅ existing |
| FIX-07 | Sum-to-price identity holds under new field names | unit | `test_pricing_dlmp.jl` items (6 call sites) | ✅ existing, needs field-name edits |
| FIX-07 | Corrected "component zero iff multiplier zero" property on IEEE-13 slice | unit | NEW `@testitem` in `test_pricing_dlmp.jl` | ❌ Wave 0 |
| FIX-07 | Deprecated alias still works + warns once | unit | NEW `@testitem` asserting `Base.depwarn` fires / `.loss`==`.cone` | ❌ Wave 0 |
| FIX-08 | Slack cone on a lightly loaded branch is flagged | unit | NEW synthetic fixture `@testitem` in `test_exactness.jl` | ❌ Wave 0 |
| FIX-08 | Every canonical fixture still passes at the measured ε | integration | existing `test_exactness.jl`, `test_exactness_verdict.jl`, plus cluster-E re-runs (`test_pricing_dlmp.jl:22/221`, `test_pricing_welfare.jl:66`, `test_admm.jl:27/127`, `test_planning_oracle.jl:269`) | ✅ existing |
| FIX-09 | FIT-baseline inexactness throws by default, reports under `on_inexact=:report` | unit | NEW `@testitem` in `test_fit.jl` (synthetic inexact fixture) | ❌ Wave 0 |
| FIX-09 | `ALMOST_OPTIMAL` root cause bounded or fixed | integration/manual | `scripts/repro_stability_check.jl` re-run at `tol_gap=1e-10`, ≥3 repeats | ✅ existing script, extend per root-cause protocol |
| FIX-10 | Truth-settled `realized_welfare` matches hand-derived expectation on a forced-PV-shortfall fixture | unit | NEW `@testitem` in `test_mpc_loop.jl` | ❌ Wave 0 |
| FIX-10 | Zero-forecast-error fixture unchanged (regression) | unit | existing `test_mpc_loop.jl`/`test_mpc_terminal.jl` items, re-run unmodified | ✅ existing |
| FIX-10 | SOC-bound violation throws (not clamps) under a forced-shortfall fixture | unit | NEW `@testitem` in `test_mpc_loop.jl` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** direct `julia --project=.` script reproducing the touched `@testitem`(s).
- **Per wave merge:** full suite (`Pkg.test()`), per CONTEXT's own locked process note — run
  AFTER EACH WAVE, not only at phase end, to avoid Phase 26's end-of-phase 55-failure surprise.
- **Phase gate:** full suite green (or every non-green item named/attributed, exactly as Phase
  26's 5 Broken items were) before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] A NEW T=2 grid-enumeration oracle (test-only, mirrors `enumerate_lattice`'s existing
      pattern but over a `(z[1],z[2])` grid) — covers FIX-06.
- [ ] A NEW synthetic slack-cone-on-small-branch fixture — covers FIX-08.
- [ ] A NEW synthetic inexact-FIT fixture — covers FIX-09.
- [ ] A NEW forced-PV-shortfall MPC fixture (small `pv_factor` forecast-error draw guaranteed to
      make the solved `p_ch` exceed true PV) — covers FIX-10's clip/throw behavior.
- [ ] Framework install: none — `Test`/`TestItems`/`TestItemRunner` are already present in
      `test/Project.toml`.

## Security Domain

`security_enforcement` is absent from `.planning/config.json` (treated as enabled per protocol),
but this phase has essentially no attack surface: it is a research-computation library with no
network service, no authentication boundary, no user-supplied untrusted input parser, and no
secrets handling. The ASVS categories below are assessed for completeness, not because a genuine
risk was found.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A — no auth surface in a Julia research library |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A |
| V5 Input Validation | Partial | Already handled by this project's own pervasive `ArgumentError`-on-bad-input convention (ubiquitous in every file read this session); FIX-06..10 should follow the SAME convention for any new kwarg (`on_inexact`, `ε`, etc.) |
| V6 Cryptography | No | N/A — no secrets/crypto in this domain |

### Known Threat Patterns for this stack
None applicable — a local research-computation codebase with no external inputs beyond
researcher-supplied `Scenario`/fixture parameters, already validated by existing boundary guards.

## Sources

### Primary (HIGH confidence — direct code read this session)
- `src/planning/benders.jl`, `src/planning/follower.jl`, `src/planning/subproblem.jl`,
  `src/planning/master_integer.jl` — FIX-06 current state, convexity argument, dual-sign
  conventions.
- `src/pricing/dlmp.jl`, `src/powerflow/ConvexBranchFlow.jl` (grep) — FIX-07 derivation and
  blast radius.
- `src/models/exactness.jl`, `src/data/ieee13.jl`/`ieee123.jl`/`ieee8500.jl` (head-branch
  convention) — FIX-08 current formula and reference-scale data source.
- `src/pricing/fit.jl` — FIX-09 gap (missing gate on FIT AC-PF step).
- `src/experiments/mpc_loop.jl`, `src/models/mpc_window.jl`, `src/devices/PVBattery.jl` — FIX-10
  current settlement convention and Assumption A6.
- `.planning/phases/26-network-device-model-correctness/26-GOLDEN-AUDIT.md`,
  `26-FINDINGS.md`, `26-POSTMERGE-TRIAGE.md` — Phase 26 blast-radius precedent, cluster-E
  tol_gap calibrations interacting with FIX-08.
- `.planning/notes/socp-validity-envelope.md`, `.planning/quick/260823-gea-*`,
  `.planning/quick/260822-hld-*` — FIX-09 ALMOST_OPTIMAL flake evidence and prior root-cause
  attempts.
- `.planning/STATE.md`, `.planning/REQUIREMENTS.md`, `27-CONTEXT.md` — phase scope, locked
  decisions, requirement traceability.

### Secondary (MEDIUM confidence)
- `Base.depwarn` as the recommended FIX-07 deprecation mechanism — a standard-library primitive,
  not independently re-verified against current Julia docs this session (training-knowledge level
  confidence on its exact call signature; verify signature at implementation time).

### Tertiary (LOW confidence — flagged for validation)
- The specific claim that Kelley's cutting-plane method converges for this exact problem class
  (piecewise-linear-convex `follower_cost` + concave-value-function-negated `oracle_welfare`) —
  the GENERAL convexity is `[VERIFIED]` in-tree; the SPECIFIC convergence guarantee for this
  method choice is `[ASSUMED]` standard theory, not re-derived or externally verified this
  session.

## Metadata

**Confidence breakdown:**
- FIX-06 (T>1 recourse): MEDIUM-HIGH — convexity fact HIGH (in-tree proof), algorithm choice
  MEDIUM (design synthesis, not pulled from an external citation).
- FIX-07 (DLMP naming): HIGH — derivation and blast radius directly read from source; only the
  `Base.depwarn` signature is unverified against live docs.
- FIX-08 (exactness floor): HIGH on current-state read; MEDIUM on the exact `ref_b` formula for
  unlimited branches (head-branch quantity choice is `[ASSUMED]`, though CONTEXT's two-case
  structure itself is locked).
- FIX-09 (FIT certificate): HIGH on the missing-gate diagnosis; LOW on the ALMOST_OPTIMAL root
  cause (genuinely unresolved by every prior session).
- FIX-10 (MPC truth settlement): HIGH on the current-behavior diagnosis and the clip/throw
  mechanism; MEDIUM on the "true import" copper-plate correction (an explicit, flagged
  simplification, not a full loss-exact re-solve).

**Research date:** 2026-09-29
**Valid until:** 30 days (stable, in-repo-only domain; no external ecosystem drift risk) — but
re-check `Base.depwarn`'s exact signature against the pinned Julia version at implementation time.

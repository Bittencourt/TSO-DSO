# Phase 24: Discrete/Integer Investment Expansion - Research

**Researched:** 2026-08-23
**Domain:** Mixed-integer Benders decomposition (Laporte–Louveaux integer L-shaped cuts) for a
single-distributor Stackelberg planning loop; JuMP/HiGHS MILP master; BilevelJuMP oracle
availability for a binary-leader/continuous-follower MPEC.
**Confidence:** HIGH on the four priority questions (verified by direct code read + a live spike
against the installed BilevelJuMP 0.6.3 + HiGHS 1.24.1/Ipopt 1.15.0); MEDIUM on general LL-method
background (textbook-standard, cross-checked but not re-derived from the original 1993 paper text).

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Investment Lattice Design (INT-01)**
- **D-01:** Pure binary expansion of `y_max`, NOT engineering block sizes and NOT an explicit level
  menu. `y_inv = (y_max / 2^K) · Σ_k 2^k b_k`. Integrality is deliberately framed as a
  solver-behaviour axis, not a physical claim.
- **D-02:** Endpoint convention: divide by `2^K` (round step sizes), NOT `2^K − 1`. Consequence,
  accepted with eyes open: all-ones gives `y_max·(1 − 2^-K)`, so `y_max` itself is never
  attainable, and the continuous diff carries a known `2^-K` boundary bias — MUST be stated
  explicitly in the fixture docstring and the literate page. Verified harmless on the canonical
  instance (continuous golden `N1_Y_HAND = 0.7` is deep in the interior of `[0, 8.0]`).
- **D-03:** Default `K = 4` → 16 levels, step `y_max/16 = 0.5` for `y_max = 8.0`, reachable set
  `{0, 0.5, 1.0, …, 7.5}`. K is configurable (a parameter change, not a code change), but a
  committed fixture default is pinned so there is something to golden-test against.
- **D-04 (derived, load-bearing):** the canonical instance has a genuine, non-degenerate
  integrality gap — `0.7` is NOT on the K=4 lattice, and its neighbours are `0.5` and `1.0`. The
  integer optimum therefore must differ from the continuous one. Do NOT "fix" a nonzero gap here;
  a zero gap would be the suspicious outcome.

**Integer Master Seam (INT-01, INT-04)**
- **D-05:** A NEW separate builder (`build_master_integer` or similar) alongside a completely
  untouched `build_master`. NOT an `integer=false` flag on the existing builder. The continuous
  v2.0 path stays byte-identical by construction, so the PVAL-02..04 goldens are trivially safe to
  diff against.
- **D-06:** The PVAL-04 exemption is a per-builder carve-out, not a conditional one. The new
  builder's name IS added to `test/test_planning_noninteger.jl`'s registry (it must be — see D-07)
  but appears on an explicit EXEMPT list; the unmodified no-binaries assertion still runs over all
  four existing builders. Exemption must be greppable by name.
- **D-07 (constraint discovered in code, not negotiable):** `test/test_planning_noninteger.jl` is
  not just a registry — it carries a source-scan tripwire asserting the discovered `build_*` set
  *equals* the registry keys (walkdir over `src/planning/`, docstring-aware regex, plus an
  exported-symbol channel). A new builder therefore cannot be omitted from the registry to dodge
  the guard; omission fails the tripwire loudly. The exemption must be an explicit allowlist inside
  the item.
- **D-08:** `solve_stackelberg!` reaches the integer master via a `master = nothing` injection
  kwarg, mirroring the existing `follower = nothing` seam in the same signature. When `nothing`,
  the loop builds `build_master(; master_kwargs..., T = T)` exactly as today
  (`src/planning/benders.jl:185`); when supplied, it uses the caller's prebuilt master. Note:
  `benders.jl:62` documents an invariant that no `build_*`/`Model(` call appears outside the single
  construction point — injection moves construction to the caller for the integer path — that
  docstring must be UPDATED to describe the seam, not silently falsified.
- **D-09:** `MILP <: ProblemClass` already exists (`src/solver/ProblemClass.jl:31`) and the factory
  already maps it. INT-01's "new/extended `ProblemClass` as needed" most likely needs nothing new —
  verify before adding anything. [Verified this session: confirmed, nothing new needed.]

**Certification Oracle & Tiny Instance (INT-03)**
- **D-10:** Exhaustive enumeration is the PRIMARY certificate; a BilevelJuMP reduction is a
  SECONDARY independent confirmation where mode-compatible, and its unavailability is a documented
  non-blocker, NOT a coverage gap. Enumerate all 16 lattice points, solve the follower at each,
  take the best — exhaustive by construction, no sampling possible.
- **D-11 (corrects an inherited research flag):** STATE.md's Phase 24 flag worried whether
  BilevelJuMP's KKT/SOS1/Fortuny-Amat modes support any mixed-integer follower. That concern likely
  does not apply to this phase: integrality lives in the leader (`y_inv`) while the follower stays
  continuous, and integer leader variables sit in the outer MILP where those reductions handle them
  normally. Verify at implementation time, but do not treat the flag as a blocker on the original
  grounds. Precedent: `test/test_planning_goldens.jl:52` already describes the N=1 golden as
  "hand-enumerated/BilevelJuMP-certified". [This session's research verifies and REFINES this — see
  Priority Finding 3: the diagnosis about follower continuity is correct, but a different,
  previously undocumented solver-capability gap independently blocks the secondary certificate on
  the D-12 fixture. Reported as new information, not a re-litigation of D-11.]
- **D-12:** Certify on the existing canonical N=1 toy — `Phase6Fixtures.two_bus_feeder()` +
  `ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)` + single aggregator, `c_y = 0.3`,
  `y_max = 8.0`, `λ₀ = [4.0]`, `T = 1`, at `K = 4`. NOT a new smaller fixture.

**Cut Policy, Termination & This Phase's Own Certificate (INT-02)**
- **D-13:** Termination is a lattice-gap EXACT criterion, explicitly NOT the continuous loop's
  inherited `tol = 1e-6` gap tolerance. Terminate when `UB − LB` falls below the smallest objective
  separation two distinct lattice points can produce — on a finite lattice this is an optimality
  proof, not a tolerance.
- **D-14 (open risk, with a decided fallback):** `δ_min` is NOT simply `c_y · step` (= 0.15 here).
  That bounds only the leader-cost separation; the follower's continuous response to two adjacent
  lattice points can partially offset it, so the true objective separation may be smaller —
  potentially arbitrarily small. Decided fallback: the enumeration-backed criterion — terminate
  when the incumbent MATCHES the enumerated optimum. Accepted cost: this works only where
  enumeration is tractable; a production criterion for large lattices is an explicitly deferred
  open item. [This session's research: confirms this is NOT derivable in general for this problem
  structure — see Priority Finding 3, a clean negative result, not an override of this decision.]
- **D-15:** Phase 24's own new certificates (beyond INT-03's enumeration agreement): (1) per-cut
  validity assertion — every LL cut generated during the certified run is checked against the
  enumerated optimum; a valid cut must NEVER cut off the true optimal lattice point. (2)
  continuous-baseline diff — assert the continuous relaxation objective is a valid bound on the
  integer objective, and the integer solution is one of the lattice neighbours bracketing it.
  Explicitly NOT selected: a no-good-count-zero assertion, and a finite-termination iteration
  bound.
- **D-16:** No-good cuts are allowed, counted, and surfaced as INT-02's anti-stall fallback. Every
  firing is counted and recorded in the run trace/report. Convergence is only ever attributed to
  the LL cuts: a run that needed no-goods is reported as `:nogood_assisted` rather than presented
  as clean LL convergence. `m > 0` does not fail the run — but it must never be invisible.

### Claude's Discretion
- The concrete algebraic form of the LL cut, cut-management/dedup strategy, and where the cut
  bookkeeping lives (`benders.jl` vs a new module) are implementation choices for research/planning.
- MILP solver attribute tuning (HiGHS gap/threads/presolve) is discretionary, provided nothing is
  hard-coded outside `select_optimizer`.
- Trace/report field naming for the no-good bookkeeping (D-16) is discretionary as long as the
  count and the `converged_via` attribution are both present.

### Deferred Ideas (OUT OF SCOPE)
- A production termination criterion for large lattices — D-14's enumeration-backed fallback is
  tractable only where exhaustive enumeration is. If the rigorous `δ_min` derivation does not hold
  up (confirmed this session: it does not, in general), deriving a criterion that scales beyond
  enumerable lattices is explicitly deferred, and must be recorded as an open item rather than
  substituted with a tolerance.
- Integrality in the N>1 Nash / diagonalization path — this phase is single-distributor Stackelberg
  only (INT-01). Integer investment across multiple distributors, and what integrality does to
  Gauss-Seidel diagonalization's already-absent uniqueness guarantee, is a separate phase.
- Engineering block sizes / explicit level menus (the D-01 alternatives) — if a later phase wants
  physically-meaningful lumpy investment, that is a modelling extension on top of this machinery.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INT-01 | Planning master supports binary-expansion integer investment as a HiGHS MILP behind `select_optimizer` (new/extended `ProblemClass` as needed) | D-09 confirmed: `MILP <: ProblemClass` already exists, nothing new needed. Priority Finding 4 identifies the required `mip_rel_gap => 0.0` factory fix for the solve to be exact. Pattern 1 gives the binary-expansion-as-`@expression` idiom; Pattern 2 flags the struct-reuse dispatch issue that must be resolved. |
| INT-02 | Convergence driven by genuine Laporte–Louveaux integer optimality cuts (LP Benders cuts retained where valid; no-good cuts only as documented anti-stall fallback), iteration behavior re-measured | Priority Finding 1 gives the exact LL cut algebraic form, its `L`/complete-recourse data requirements, and a citation. Priority Finding 2 proves (via Geoffrion GBD + a project-specific convexity derivation) that the existing continuous `:op`/`:x` cuts remain valid and must be kept firing unchanged. Priority Finding 3 gives the honest negative result on `δ_min`, supporting D-13/D-14's exact-termination design. |
| INT-03 | Integer loop certified on a tiny instance against an independent oracle (exhaustive enumeration and/or BilevelJuMP reduction where mode-compatible) | D-10's enumeration path is unaffected by this research (continuous follower/oracle re-solved as-is at each of the 16 lattice points). Priority Finding 3 (BilevelJuMP) gives a verified, concrete account of why the secondary certificate is unavailable on the D-12 fixture specifically — to be documented as a non-blocking negative result, matching the existing `BigMMode+HiGHS` MIQP precedent already in `test_planning_certification.jl`. |
| INT-04 | PVAL-04 no-binaries guard scoped (registry exemption for the lifted builder only), full guard green for all non-lifted builders, literate page documenting the guard lift and cut mechanism | D-06/D-07 mechanics read directly from `test/test_planning_noninteger.jl` (registry + source-scan tripwire + exported-symbol channel) — no additional research needed beyond confirming the existing tripwire's shape, done this session. |
</phase_requirements>

## Summary

This phase adds genuine binary-expansion integer investment to the single-distributor Benders
master (`src/planning/master.jl`/`benders.jl`), replacing the continuous `y_inv` with a HiGHS MILP
over K binary variables. Four research questions were resolved:

1. **The Laporte–Louveaux (LL) cut is the classical "no-good cut with a value" (Birge & Louveaux;
   Laporte & Louveaux 1993)** — algebraically simple, requires only a valid global lower bound `L`
   on the recourse, and is retained by design *alongside*, not instead of, standard continuous
   optimality cuts. This project already has `L`: the master's existing `α_op_lb + α_x_lb`
   (Pitfall M1) is a valid `L` with **zero new derivation needed**, PROVIDED those bounds were
   derived to hold over the *entire* continuous `z ∈ [0, y_max]` domain (verify at implementation
   time by re-reading the Pitfall M1 derivation in `11-RESEARCH.md`/`master.jl`'s own comments —
   this research did not find that derivation file, so it is flagged as an open item, not assumed).

2. **Standard continuous optimality cuts on `z` REMAIN VALID under an integer `y_inv`** — this is
   answered with a citable, derived argument, not a guess: `Q(y_inv) = min_{0≤z≤y_inv}[α_op(z)+α_x(z)]`
   is a **partial minimization of a jointly-convex function over a jointly-convex, monotonically
   expanding feasible set**, hence `Q` is convex (and monotone non-increasing) in the *continuous
   relaxation* of `y_inv`. Because `y_inv` is a *linear* function of the binary vector `b`
   (`y_inv = (y_max/2^K)·Σ 2^k b_k`), `Q(b)` is convex over `[0,1]^K` too, and any subgradient cut
   on `z` derived at a trial `z_k` is a **globally valid supporting hyperplane over the entire
   continuous relaxation — hence valid at every one of the `2^K` binary corners**. This is exactly
   the classical justification for **Geoffrion's Generalized Benders Decomposition (GBD, 1972)**:
   integer/complicating master variables coupled *linearly* to a convex continuous recourse always
   admit valid cuts from the recourse's continuous relaxation. Laporte & Louveaux's own 1993 method
   explicitly *retains* ordinary L-shaped (Benders) cuts alongside the new integer cut for exactly
   this reason — the integer cut exists only to guarantee **finite** termination for a possibly
   *smooth* (non-polyhedral) recourse, not because the ordinary cuts become invalid.

3. **D-11's correction is directionally right but incomplete — verified empirically.** BilevelJuMP
   0.6.3's reduction machinery (`moi.jl:build_bilevel`) copies the *entire* upper-level MOI model
   verbatim (`MOIU.default_copy_to`) and dualizes *only* the lower level (`Dualization.dualize`), so
   an upper-level `Bin`/`Integer` variable is **structurally preserved** through the reduction — the
   original STATE.md worry ("mixed-integer follower") does not apply, confirming D-11's diagnosis.
   **But a live spike on the project's actual toy fixture (with its genuinely quadratic upper-level
   welfare term) shows the secondary certificate is NOT reachable on the D-12-mandated instance
   anyway, for a different, previously undocumented reason:** `StrongDualityMode`/`ProductMode`
   (backed by Ipopt) throw `MOI.UnsupportedConstraint{VariableIndex, ZeroOne}` immediately —
   Ipopt cannot represent discrete variables *at all*, regardless of objective linearity. `BigMMode`
   (backed by HiGHS) *can* represent the binary leader (confirmed: solves correctly on a
   **linearized** toy variant), but on the actual quadratic-welfare fixture it degrades to the exact
   same MIQP failure **already documented as a negative regression in
   `test/test_planning_certification.jl`** ("Cannot solve MIQP problems with HiGHS") — a failure
   that exists independent of leader integrality (it already fires today, with a *continuous*
   leader, purely from BigMMode's own complementarity binaries). **Net finding: the BilevelJuMP
   secondary certificate remains unavailable on the D-12 fixture — this is not a coverage gap
   (D-10 already treats it as a documented non-blocker) but the reason has shifted from "unclear
   mode support" to a concretely verified, dual-cause solver-capability gap.**

4. **HiGHS MILP defaults are NOT exact by default and this is a real, actionable risk.** Live query
   of the installed HiGHS 1.24.1 confirms `mip_rel_gap = 1e-4`, `mip_abs_gap = 1e-6` — neither is
   overridden by `select_optimizer(::MILP())` (`src/solver/factory.jl:59-60` sets only
   `output_flag => false`). Left as-is, the master's own `objective_value(master.model)` (the outer
   loop's `LB`) can be up to `1e-4` relatively short of the master's *own* MILP optimum for the
   current cut set — directly undermining D-13's "optimality proof, not a tolerance" claim, since
   the outer criterion's exactness is only as good as the inner MILP solve's exactness. **Must be
   set explicitly to `0.0`** (or empirically verified not to stall B&B at exactly `0.0` on this tiny
   instance) in `factory.jl`'s `MILP` branch.

**Primary recommendation:** implement the LL "no-good cut with a value" exactly as derived below,
keep the existing continuous `add_optimality_cut!`/`add_feasibility_cut!` cut families completely
unchanged and firing on every iteration (they remain valid, per finding 2), add the LL cut as a
strict superset behavior, set `mip_rel_gap => 0.0` explicitly in the MILP factory branch, and treat
the BilevelJuMP secondary certificate as unavailable-by-design (document the two independent,
verified reasons in the literate page) rather than spending further effort chasing it.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Binary-expansion integer master (leader) | Planning/optimization core (`src/planning/`) | Solver factory (`src/solver/`) | The master's own JuMP model owns the binary variables and objective; the factory only supplies the MILP backend. |
| LL / no-good cut generation & bookkeeping | Planning/optimization core (`benders.jl`) | — | Cuts are appended to the master's persistent constraint set, mirroring the existing `:op`/`:x` cut families — no new tier. |
| MILP solve (HiGHS) | Solver factory (`src/solver/factory.jl`) | — | `select_optimizer(MILP())` is the sole solver-naming seam (INFRA-02); the master calls it, never names HiGHS directly. |
| Certification oracle (enumeration + BilevelJuMP) | Test layer (`test/`) | — | Test-only dependency (BilevelJuMP is never imported by `src/`, per CLAUDE.md's "validation oracle only" rule, already enforced in `test_planning_certification.jl`). |
| PVAL-04 guard scoping | Test layer (`test/test_planning_noninteger.jl`) | — | Registry + source-scan tripwire lives entirely in the test suite; no `src/` capability owns it. |

## Package Legitimacy Audit

**Not applicable.** This phase introduces **no new external packages**. `HiGHS` (already a hard
dependency, pinned `1.24.1`) supplies the MILP backend via the existing factory; `BilevelJuMP`
(already a **test-only** dependency, pinned `= 0.6.3` in `test/Project.toml`, never imported by
`src/`) is reused as-is for the optional secondary certificate. `MILP <: ProblemClass` already
exists (`src/solver/ProblemClass.jl:31`, confirms D-09 — nothing new needed there). No
`slopcheck`/registry verification is required.

## Priority Findings (the research payload)

### 1. The Laporte–Louveaux cut — exact algebraic form, data requirements, and citation

**Source:** G. Laporte and F. V. Louveaux, "The integer L-shaped method for stochastic integer
programs with complete recourse," *Operations Research Letters* 13 (1993), pp. 133–142. Also
reproduced as the standard reference textbook treatment in J. R. Birge and F. Louveaux,
*Introduction to Stochastic Programming*, 2nd ed., §5.2 ("Binary First-Stage Variables"), Springer,
2011 — cross-checked via WebSearch against multiple secondary academic sources (Georgia Tech course
notes, ScienceDirect follow-on papers citing the identical cut form); MEDIUM-HIGH confidence (the
core formula is stable across every secondary source found; the primary 1993 paper's PDF was not
directly fetched this session).

**Setting:** first-stage decision vector `x ∈ {0,1}^n` (pure binary — this is the method's
*defining* restriction, not a generalization to bounded integers directly; see the "binary
expansion" note below for how this project's `y_inv` maps onto it). A scalar epigraph variable `θ`
in the master approximates the recourse value `Q(x)` from below (`θ ≥ L` declared at build time —
this project's analog is `α_op ≥ α_op_lb`, `α_x ≥ α_x_lb`, Pitfall M1).

**The cut, given an incumbent trial `x^ν` and its exact recourse value `Q(x^ν)` (obtained by
actually re-solving the recourse subproblem(s) at `x^ν` — never estimated):**

Let `S^ν = { i : x_i^ν = 1 }` (the incumbent's "on" set). Define

```
D(x) = Σ_{i ∈ S^ν} x_i − Σ_{i ∉ S^ν} x_i − |S^ν| + 1
```

The cut is

```
θ ≥ (Q(x^ν) − L) · D(x) + L
```

**Why it works (verify-by-construction, not folklore):**
- At `x = x^ν`: `D(x^ν) = |S^ν| − 0 − |S^ν| + 1 = 1`, so the cut reduces to `θ ≥ Q(x^ν)` — tight and
  exact at the incumbent.
- At any OTHER binary `x ≠ x^ν` (differing in `k ≥ 1` bits from `x^ν`): `D(x) = 1 − 2k ≤ −1`. Since
  `Q(x^ν) − L ≥ 0` (L is a valid lower bound), the cut reduces to `θ ≥ L − 2k(Q(x^ν) − L) ≤ L`,
  which is **implied by the master's own existing `θ ≥ L` epigraph bound** — i.e. the cut adds
  **zero new information at any other integer point**. Its entire function is to forbid the master
  from re-selecting `x^ν` at a value below the already-known-true `Q(x^ν)` — a "no-good cut with a
  pinned objective value," not a supporting hyperplane in the usual convex sense. This is precisely
  why it requires **no convexity assumption on Q(x) at all** (unlike GBD-style cuts) and why it is
  the mechanism Laporte & Louveaux use to prove **finite** convergence even when the recourse value
  function is not polyhedral.
- **Only requires `x^ν` binary and `Q(x^ν)` exact.** The cut is written directly in terms of the
  *raw binary variables*, never a linear aggregate — for this project that means it must be written
  in terms of the actual `b_k` decision variables (`k = 1..K`), **not** the derived expression
  `y_inv = (y_max/2^K)·Σ 2^k b_k`. This is a concrete implementation requirement for the planner:
  the new master builder must expose the raw `b` vector (not just `y_inv`) to whatever function adds
  this cut.

**Complete recourse — verified to hold here, not assumed.** LL's method is titled "with complete
recourse," meaning the recourse subproblem must be feasible for *every* first-stage choice. Reading
`src/planning/follower.jl`: the follower's feasible set for `z` at a given `y_inv` is
`z ∈ [0, min(y_inv, corridor_cap·x_inv_max)]`, and `z = 0` (`x_inv = 0`, `x_op = 0`) is **always**
feasible regardless of `y_inv ≥ 0`. So for every feasible `b` (hence every feasible `y_inv`), the
recourse is feasible at `z = 0` — complete recourse holds with respect to the *master's* choice of
`y_inv`. The existing feasibility-cut branch (`benders.jl`'s `!follower_res.feasible` path, T-11-06)
is not about `y_inv`-infeasibility; it exists because the master's LP *relaxation* can still propose
an intermediate `z_k` (within `[0,y_inv]`) that the follower cannot deliver at that specific trial —
this is orthogonal to LL-cut applicability and requires **no change**: keep it exactly as-is.

**What `L` should be — reuse, do not re-derive.** LL's `L` must lower-bound `Q(x)` for *every*
feasible `x` (here: for every `y_inv` on the lattice, including the trivial `y_inv = 0`). This
project's `Q(y_inv) = α_op(y_inv) + α_x(y_inv)`, and `build_master`'s existing
`α_op ≥ α_op_lb`, `α_x ≥ α_x_lb` (Pitfall M1) are *already* declared to hold as a valid lower bound
at build time, before any cut exists — i.e., before *any* `z` trial has been observed. If that
derivation in the existing continuous builder was made to hold over the **entire** `z ∈ [0, y_max]`
domain (the natural reading of "declared at build time, never added later"), then `L = α_op_lb +
α_x_lb` is directly reusable with **zero new derivation** for the integer builder — this is a
strong candidate answer, but the actual derivation text for `α_op_lb`/`α_x_lb` lives in
`11-RESEARCH.md` (not read this session — it was not in this phase's required file list and was not
located under `.planning/phases/11-*` in this pass). **Flagged as an open item for the planner to
confirm at implementation time** (a five-minute check, not a re-derivation): read that file's
Pitfall M1 section and verify the stated bound derivation does not implicitly assume `y_inv` is
continuous or unbounded above `y_max`.

**No-good cut (D-16's fallback), for completeness — the classical *un-weighted* combinatorial
form** (same S^ν convention, no `L`/objective value carried):

```
Σ_{i ∈ S^ν} (1 − b_i) + Σ_{i ∉ S^ν} b_i ≥ 1
```

Simply forbids exact re-visitation of `b^ν`; strictly weaker than the LL cut (which additionally
pins the *known* objective value), which is exactly why D-16 requires no-good-assisted runs to be
reported as `:nogood_assisted` rather than attributed to genuine LL convergence.

### 2. Do standard continuous Benders cuts remain valid alongside LL cuts? — YES, derived and cited

This was flagged in STATE.md as unresolved and is answered here with a citable derivation, not a
guess (see Summary point 2 for the full argument). Two citable anchors:

- **Geoffrion, A. M. (1972), "Generalized Benders Decomposition," *Journal of Optimization Theory
  and Applications* 10(4), pp. 237–260.** GBD is the general theorem that Benders-style cuts
  (derived from the *continuous* relaxation of a convex recourse) remain valid whenever
  "complicating" master variables (here: the binary `b`) are coupled to a convex subproblem — the
  master variables' integrality is irrelevant to cut *validity*, only to cut *sufficiency for finite
  termination*. [CITED via WebSearch, cross-referenced against Cornell/Northwestern optimization
  wiki summaries — MEDIUM confidence on exact page numbers, HIGH confidence on the substantive
  claim, which is standard textbook material.]
- **Laporte & Louveaux (1993) itself explicitly retains ordinary L-shaped optimality cuts
  alongside the new integer cut** in the same master — the integer cut is an *addition* for finite
  termination guarantees on non-polyhedral recourse, not a replacement.

**Project-specific derivation (this session, not from either citation directly):** `Q(y_inv) =
min_{0≤z≤y_inv} [α_op(z) + α_x(z)]` is a partial minimization of a jointly-convex function
(`α_op`, `α_x` are each convex — SOCP welfare and LP cost respectively) over the feasible set
`{(z,t) : 0 ≤ z ≤ t}`, which is itself jointly convex in `(z,t)`. By the standard convex-analysis
"partial minimization preserves convexity" result, `Q(t)` is convex in the scalar `t` — and,
because larger `t` weakly enlarges the feasible set, `Q` is also monotone non-increasing in `t`.
Substituting the linear map `t = y_inv(b) = (y_max/2^K)·Σ 2^k b_k`, `Q(b)` is convex over the
continuous relaxation `b ∈ [0,1]^K` (composition of a convex function with a linear map). Therefore
**any subgradient cut on `z` derived at a trial `z_k`(the existing `add_optimality_cut!` form) is a
valid global underestimator of `Q` over the *entire* continuous relaxation of `b` — hence valid at
every one of the `2^K` binary lattice points, with no modification required.** Practical
consequence: **keep `add_optimality_cut!`/`add_feasibility_cut!` completely unmodified** and firing
on every iteration exactly as today; the LL/no-good cuts are a pure *addition*, not a replacement.

### 3. `δ_min` — is a rigorous bound derivable? Answer: NO, and here is why (a clean negative result)

D-14 already decided the enumeration-backed fallback; this research's job was to determine whether
the *primary* (non-fallback) path — a rigorous `δ_min` — is reachable, without proposing to
override that decision. **It is not reachable in general, for a structural reason specific to this
model, not merely "hard to compute":**

By the same convexity argument as finding 2, `Q(y_inv)`'s local slope at any point equals (by the
envelope theorem) the shadow price / dual value of the box constraint `z ≤ y_inv` — a continuous LP
(follower side) or SOCP (oracle side) dual variable. For the **follower** (an LP), the value
function is piecewise-linear with finitely many breakpoints (classical parametric-RHS sensitivity
analysis), so a slope bound *could* in principle be obtained by enumerating that LP's own
breakpoints. But the **oracle** (`α_op`, a SOCP welfare problem) has a genuinely *smooth*, not
piecewise-linear, value function in general — its dual price (the DADP) varies continuously with
`z`, and nothing in this project's theory or code establishes an a-priori Lipschitz bound on that
variation independent of the actual data (feeder topology, device curves, price profile). Because
the total objective is `F(y_inv) = c_y·y_inv + Q(y_inv)` (linear plus convex-decreasing), the
separation between two adjacent lattice points is

```
ΔF = c_y·step + [Q(y_inv+step) − Q(y_inv)],   with the bracket term ≤ 0
```

`c_y·step` bounds only the first term. If, on some segment, the oracle's/follower's marginal price
(the local slope of `Q`) happens to equal `c_y` exactly, `F` is flat there and **two adjacent lattice
points can produce an arbitrarily small — or exactly zero — true objective separation**, with no
generic (data-independent) formula ruling this out. Establishing an *instance-specific* `δ_min`
would require either (a) a Lipschitz bound on the SOCP oracle's dual price as a function of `z` —
not established anywhere in this project's theory documents, and not something derivable without
first solving the problem (circular), or (b) direct enumeration of `Q` at every lattice point, which
is exactly D-10/D-14's already-adopted fallback. **Conclusion: no rigorous, general-purpose `δ_min`
is reachable with this project's current theoretical machinery; the enumeration-backed criterion is
not merely a fallback of convenience but the only currently-available exact criterion, and a
production-scale (non-enumerable) exact criterion is correctly left as an explicitly deferred open
item (per the Deferred section of CONTEXT.md) rather than one this research can close.**

### 4. HiGHS MILP specifics through `select_optimizer(MILP())` — a required, concrete fix

Live-queried against the installed `HiGHS 1.24.1` (`Highs_getDoubleOptionValue`, this session):

| Option | Default value | Currently overridden by `select_optimizer(::MILP())`? |
|--------|---------------|--------------------------------------------------------|
| `mip_rel_gap` | `1e-4` | No — only `output_flag => false` is set (`src/solver/factory.jl:59-60`) |
| `mip_abs_gap` | `1e-6` | No |
| `mip_feasibility_tolerance` | `1e-6` | No |
| `presolve` | `"choose"` (auto) | No — the `LP` method explicitly sets `"on"`; `MILP` sets nothing |

**This is a genuine, actionable risk, not a hypothetical:** with `mip_rel_gap = 1e-4` left at
default, HiGHS is licensed to terminate the master's MILP re-solve once it has proven the incumbent
is within `1e-4` *relative* of the best bound — meaning `objective_value(master.model)` (consumed
as the outer loop's `LB`) can be inexact by construction, independent of how many cuts have
accumulated. Since D-13 explicitly rejects reusing any inherited tolerance and requires the outer
criterion to be "an optimality proof, not a tolerance," an inexact *inner* MILP solve silently
reintroduces exactly the kind of imprecision D-13 is designed to exclude — this is a load-bearing
gap for the planner to close, not a nice-to-have.

**Required action:** extend `select_optimizer(::MILP())` (mirroring the already-established
`select_optimizer(::SOCP; attrs...)` / `select_optimizer(::NLP; attrs...)` keyword-override pattern
in the same file) to set `"mip_rel_gap" => 0.0` (and consider `"mip_abs_gap" => 0.0` for full
rigor, though `1e-6` absolute is likely below floating noise on this toy instance — verify
empirically rather than assume). This is squarely within CONTEXT.md's "Claude's Discretion" grant
("MILP solver attribute tuning ... is discretionary, provided nothing is hard-coded outside
`select_optimizer`") — no new user decision is required, but it MUST be done inside
`src/solver/factory.jl`, never inline in `master.jl` (INFRA-02).

**Caveat to verify empirically at implementation time (not assumed here):** setting
`mip_rel_gap = 0.0` can occasionally cause branch-and-bound to stall on floating-point noise for
larger instances; on this phase's tiny fixture (`K=4`, 16 combinations) this is very unlikely to be
an issue, but the planner should include a quick empirical check (does the MILP master solve
converge promptly at `mip_rel_gap=0.0` on the `K=4` fixture?) rather than assume it based on this
research alone.

## Standard Stack

No new libraries. Reused, already-pinned:

| Library | Version | Purpose | Why Standard (for this use) |
|---------|---------|---------|------------------------------|
| HiGHS | 1.24.1 (pinned in `test/Project.toml`; hard dep in main `Project.toml`) | MILP backend for the new integer master | Already the project's sole open-source MILP solver (INFRA-02); `MILP <: ProblemClass` already routes here. |
| BilevelJuMP | 0.6.3 (test-only, pinned `= 0.6.3`) | Secondary certification oracle attempt (D-10/D-11) | Already the project's established validation-oracle-only dependency; verified this session to structurally support upper-level binary variables via `MOIU.default_copy_to`, though practically blocked on the D-12 fixture (finding 3 above). |
| JuMP | 1.30.1 | Modeling layer for the new builder | Unchanged — same modeling idiom (`@variable`, `@expression`, `@constraint`) as every existing planning-layer builder. |

**Version verification:** confirmed live this session via
`julia --project=test -e 'import Pkg; println(Pkg.dependencies()[...].version)'` → BilevelJuMP
`0.6.3`; via `HiGHS.Highs_create()` + `Highs_getDoubleOptionValue` → HiGHS runtime `1.15.1` embedded
binary reported at solve time (matches the `HiGHS_jll` shipped by the pinned `HiGHS.jl = 1.24.1`
wrapper — the two version numbers refer to different things: the Julia package version and the
embedded C++ solver version; both are already pinned by `test/Project.toml`/`Manifest.toml`, no
action needed).

## Architecture Patterns

### System Architecture Diagram

```
solve_stackelberg!(... ; master = nothing)
        │
        ▼
  master === nothing ?
        │yes                                  │no (D-08 injection)
        ▼                                      ▼
 build_master_integer(; K, y_max, c_y, ...)   caller-supplied prebuilt master
        │  (NEW builder, src/planning/master.jl or sibling)
        │    - @variable(model, b[1:K], Bin)
        │    - y_inv = @expression(... binary-expansion sum ...)
        │    - z[1:T], α_op ≥ α_op_lb, α_x ≥ α_x_lb   (UNCHANGED shape)
        │    - Model(select_optimizer(MILP()))         (mip_rel_gap=>0.0 fix, factory.jl)
        ▼
   ┌─────────────────────────── Benders loop (benders.jl, UNCHANGED shape) ───────────────────────┐
   │  for k in 1:max_iter                                                                          │
   │    lb_res = solve_master!(master)          # now an exact MILP solve                          │
   │    follower_res = solve_follower!(follower, lb_res.z)     # UNCHANGED — still continuous LP    │
   │      infeasible → add_feasibility_cut!(...)               # UNCHANGED, still valid (finding 2) │
   │      feasible   → oracle_res = solve_planning_oracle!(...)                                    │
   │                    add_optimality_cut!(master, :op, ...)   # UNCHANGED, still valid (finding 2)│
   │                    add_optimality_cut!(master, :x, ...)    # UNCHANGED, still valid (finding 2)│
   │                    add_ll_cut!(master, b_k_trial, Q(b^ν), L)   # NEW — finding 1               │
   │                    [stall-fallback] add_nogood_cut!(master, b_k_trial)   # NEW — D-16          │
   │    termination: exact lattice-gap OR enumeration-match (D-13/D-14) — NOT tol=1e-6              │
   └────────────────────────────────────────────────────────────────────────────────────────────────┘
        │
        ▼
  certification (test-only): exhaustive enumeration (PRIMARY, D-10) over 16 lattice points,
  each solved via the UNCHANGED continuous follower/oracle; BilevelJuMP (SECONDARY, verified
  unavailable on this fixture — findings 3 above) documented as a non-blocking negative result.
```

### Recommended Project Structure

```
src/planning/
├── master.jl            # UNCHANGED build_master (D-05); ADD build_master_integer alongside
├── benders.jl            # UNCHANGED loop shape; ADD LL-cut/no-good-cut call sites + master=nothing
│                          # resolution branch (mirrors follower=nothing, D-08); UPDATE the
│                          # "no build_*/Model( outside the single construction point" docstring
│                          # invariant at benders.jl:62 (D-08 explicitly requires this update)
├── follower.jl            # UNCHANGED — continuous LP, no touch
├── subproblem.jl          # UNCHANGED — continuous SOCP oracle, no touch
└── trace.jl               # EXTEND (additive) — no-good count + converged_via attribution (D-16)
src/solver/
└── factory.jl            # EXTEND select_optimizer(::MILP()) — mip_rel_gap => 0.0 (finding 4)
test/
└── test_planning_noninteger.jl   # registry gains build_master_integer on the EXPLICIT EXEMPT list
                                    # (D-06/D-07) — the source-scan tripwire still runs unmodified
```

### Pattern 1: Binary-expansion investment variable as a JuMP `@expression`, not a `@variable`

**What:** declare the K raw binaries as the actual `@variable`s; derive `y_inv` as an `@expression`
(an `AffExpr`) over them. `BendersMaster{Y,Z,AOP,AX}` is already generically parametrized on the
`y_inv` field type `Y` — nothing in `add_optimality_cut!`/`add_feasibility_cut!`/`solve_master!`
inspects `Y`'s concrete type, so `y_inv::GenericAffExpr` would type-check against the *existing*
generic struct signature if reused directly.

**When to use:** exactly this case — a derived quantity used only in linear constraints/objectives,
where the underlying decision variables (`b`) must also be individually addressable (for the LL
cut, which needs the raw `b_k`, not `y_inv`).

**Example (illustrative, not literal committed code):**
```julia
# Source: derived this session from JuMP 1.30's @expression + @variable idioms
# (JuMP docs: "Expressions" section — general to any JuMP-1.x version, not version-pinned)
K = 4
@variable(model, b[1:K], Bin)
y_inv = @expression(model, (y_max / 2^K) * sum(2^(k-1) * b[k] for k in 1:K))
@constraint(model, [t = 1:T], z[t] <= y_inv)   # AffExpr RHS — supported unchanged
```

### Pattern 2: A NEW struct is very likely required — reusing `BendersMaster` verbatim has a
concrete dispatch problem

**What was found by reading the actual code (not assumed):** `add_optimality_cut!` and
`add_feasibility_cut!` are dispatched as `function add_optimality_cut!(master::BendersMaster, ...)`
— a *concrete* type annotation, not an abstract supertype. `BendersMaster` is parametric
(`BendersMaster{Y,Z,AOP,AX}`), so a `BendersMaster{AffExpr,...}` instance *would* dispatch correctly
— BUT `BendersMaster`'s field list (`model, y_inv, z, α_op, α_x, T, c_y, cuts`) has **no slot for the
raw binary vector `b`**, which the LL cut needs. Adding a field to `BendersMaster` would require
editing `build_master`'s positional constructor call — directly violating D-05's "completely
untouched `build_master`" (the struct and its builder are constructed together; you cannot touch one
without the other in this file's current form).

**Recommendation (implementation choice, per CONTEXT.md's discretion grant):** define a genuinely
separate struct (e.g. `BendersMasterInteger`) with its own field for `b`, and either (a) give it its
own `add_optimality_cut!`/`add_feasibility_cut!`/`solve_master!` method overloads (thin — likely
near-identical bodies, differing only in the struct type annotation), mirroring the exact pattern
`follower = nothing`'s duck-typed injection already establishes for a *different* concrete type
(Phase 13's `DistributorView`), or (b) introduce a one-line `abstract type AbstractBendersMaster
end` / `struct BendersMaster{...} <: AbstractBendersMaster` change and retype the three functions'
signatures to the abstract type — a minimal, behavior-preserving touch to `master.jl` that keeps
`build_master`'s *behavior* byte-identical while only widening its struct's supertype. **This
research does not decide between (a) and (b)** — CONTEXT.md explicitly reserves "where the cut
bookkeeping lives" as a Claude's-Discretion item — but flags that *some* such decision is
unavoidable; "just reuse `BendersMaster`" as stated in D-05/D-08's framing is not literally possible
without one of these two changes.

### Anti-Patterns to Avoid

- **Do not derive a new `δ_min` formula and quietly present it as rigorous** — finding 3 shows this
  is not generically derivable; only the enumeration-backed criterion is currently exact.
- **Do not reuse the continuous loop's `tol = 1e-6`** as the integer loop's termination gate — D-13
  already forbids this; this research found no theoretical basis on which it would be sound anyway
  (finding 3 shows the true minimum lattice separation is not `c_y·step`).
- **Do not assume `select_optimizer(::MILP())` already produces an exact solve** — verified false
  (finding 4); the default `mip_rel_gap = 1e-4` must be overridden.
- **Do not spend further implementation time chasing BigMMode+HiGHS as the secondary certificate on
  the D-12 fixture** — verified (this session, live spike) to fail categorically via the pre-existing
  MIQP incapacity, independent of leader integrality.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| MILP solve | A custom branch-and-bound loop | HiGHS via `select_optimizer(MILP())` | Already the project's standard open-source MILP solver; D-09 confirms the `ProblemClass` plumbing already exists. |
| Integer-cut validity proof | A hand-derived ad-hoc cut | The classical LL "no-good cut with a value" (finding 1) | Textbook-standard, finitely convergent by a published proof (Laporte & Louveaux 1993) — reinventing this risks a subtly invalid cut. |
| Secondary MPEC certificate | A hand-rolled KKT/complementarity reformulation | BilevelJuMP (attempted, found unavailable on this fixture — document the negative result, do not build a replacement reformulation by hand; that would reintroduce exactly the bespoke-MPEC risk CLAUDE.md's "validation oracle only" rule exists to avoid) | — |

**Key insight:** every piece of machinery this phase needs (MILP solver, integer-cut theory,
independent oracle) already exists in the project's stack or in 30-year-old, well-cited OR theory —
the actual work is wiring, not invention.

## Common Pitfalls

### Pitfall 1: Writing the LL cut in terms of `y_inv` instead of the raw `b_k`
**What goes wrong:** the cut's `S^ν`/`D(x)` construction is only valid for genuine 0-1 variables;
substituting the derived continuous expression `y_inv` breaks the combinatorial argument entirely.
**Why it happens:** `y_inv` is the "natural" quantity everywhere else in the codebase (cuts,
objective, docstrings all refer to it).
**How to avoid:** thread the raw `b` vector through wherever the LL cut is added; never reconstruct
`S^ν` from `y_inv`'s numeric value.
**Warning signs:** a cut that is not tight at the incumbent, or that excludes the true optimal
lattice point (this is exactly D-15's own "per-cut validity assertion" certificate — it exists
precisely to catch this class of bug).

### Pitfall 2: Assuming `mip_rel_gap`'s default is already tight enough because the instance is tiny
**What goes wrong:** on a 16-point lattice, HiGHS can (and empirically may) return a "solved"
status that is only within `1e-4` relative of true optimality, silently laundering the outer loop's
exactness claim.
**Why it happens:** `mip_rel_gap` defaults are tuned for large, hard MILPs where `1e-4` is
negligible relative to overall solve difficulty — this project's toy MILP is exactly where the
default's looseness is most visible relative to the tiny objective values involved (`N1_OBJ_HAND =
-0.245`; `1e-4` relative on numbers this small is not obviously negligible).
**How to avoid:** set `mip_rel_gap => 0.0` explicitly (finding 4); do not rely on "it's a small
instance, defaults are probably fine."

### Pitfall 3: Reusing `add_optimality_cut!`/`add_feasibility_cut!`'s type-annotated signatures
without a plan for the new struct
**What goes wrong:** `MethodError` at the first `add_optimality_cut!(new_master, ...)` call if the
new integer master's struct type is not `BendersMaster` itself and no matching method is added.
**Why it happens:** D-05 emphasizes "reuse the seam" language that could be misread as "the same
functions just work" — they do not, without one of Pattern 2's two fixes.
**How to avoid:** decide (a) vs (b) from Pattern 2 explicitly during planning, before writing the
cut-adding code.

## Code Examples

### The LL cut, as a JuMP `@constraint` (illustrative — exact variable names are the planner's choice)
```julia
# Source: derived this session from Laporte & Louveaux (1993)'s published cut form,
# cross-checked against Birge & Louveaux's textbook restatement (see Priority Finding 1).
function add_ll_cut!(master, b_trial::AbstractVector{<:Real}, Q_nu::Real, L::Real)
    S = findall(==(1.0), round.(b_trial))          # S^ν: indices where b_trial[i] == 1
    K = length(b_trial)
    Dexpr = sum(master.b[i] for i in S; init = 0) -
            sum(master.b[i] for i in setdiff(1:K, S); init = 0) - length(S) + 1
    θ = master.α_op + master.α_x                     # this project's combined epigraph
    @constraint(master.model, θ >= (Q_nu - L) * Dexpr + L)
    return master
end
```

### The no-good cut (D-16 fallback), same convention
```julia
# Source: standard combinatorial no-good cut, e.g. as summarized in Birge & Louveaux §5.2.
function add_nogood_cut!(master, b_trial::AbstractVector{<:Real})
    S = findall(==(1.0), round.(b_trial))
    K = length(b_trial)
    @constraint(
        master.model,
        sum(1 - master.b[i] for i in S) + sum(master.b[i] for i in setdiff(1:K, S)) >= 1
    )
    return master
end
```

### HiGHS MILP exact-gap factory fix
```julia
# Source: this session's live query against the installed HiGHS 1.24.1
# (Highs_getDoubleOptionValue confirmed default mip_rel_gap = 1e-4, mip_abs_gap = 1e-6)
select_optimizer(::MILP()) = optimizer_with_attributes(
    HiGHS.Optimizer,
    "output_flag" => false,
    "mip_rel_gap" => 0.0,     # NEW — exactness required by D-13's lattice-gap criterion
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Continuous `y_inv` LP master | Binary-expansion MILP master | This phase | New `ProblemClass` usage (`MILP`, already existed unused for planning); genuinely new integrality gap vs. continuous baseline (D-04, by design). |
| HiGHS default `mip_rel_gap=1e-4` | Explicit `mip_rel_gap=0.0` (recommended) | This phase | Required for D-13's exactness claim to be sound end-to-end. |

**Deprecated/outdated:** nothing in the existing continuous v2.0 path is deprecated — it is
explicitly kept byte-identical (D-05) and reused wholesale by the new integer path's own optimality
cuts (finding 2).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `α_op_lb + α_x_lb` (as declared in the existing continuous `build_master`) is a valid global lower bound `L` over the *entire* `z ∈ [0, y_max]` domain, not just a locally-sufficient bound for the zero-cut LP case. | Priority Finding 1 | If false, the LL cut's `L` is invalid and the cut can cut off the true optimum. Must be confirmed by reading `11-RESEARCH.md`'s Pitfall M1 derivation (not located this session) before implementation. |
| A2 | HiGHS `mip_rel_gap = 0.0` will not stall branch-and-bound on the `K=4` toy fixture. | Priority Finding 4 / Common Pitfalls | If it stalls, a small positive value (e.g. `1e-9`) would need to be substituted with an explicit note that the outer exactness claim then inherits that (negligible but nonzero) slack. Low risk given the instance's tiny size, but unverified by an actual solve this session. |
| A3 | The GBD-style convexity argument (Priority Finding 2) applies without qualification to the ACTUAL oracle (`α_op`, a LinDistFlow/branch-flow SOCP welfare problem), not just to a generic "convex subproblem." | Priority Finding 2 | If the oracle's SOCP relaxation is not exactly convex in `z` for the fixture in use (e.g. a non-exact relaxation regime — cf. the project's own documented SOCP-inexactness findings on other feeders, MEMORY.md), the continuous-cut-validity argument could weaken. On the D-12 canonical N=1 fixture this is not believed to be an issue (it is a long-validated, tiny, radial, SOCP-exact instance per the existing PVAL-01/PVAL-02 goldens), but the general claim should not be exported to a larger feeder without re-checking exactness there too. |

## Open Questions

1. **What exactly is the `α_op_lb`/`α_x_lb` derivation, and does it hold over the full `[0,y_max]`
   domain?**
   - What we know: the values are declared at build time and are load-bearing for the continuous
     master's first (zero-cut) solve (Pitfall M1, `master.jl`'s own docstring).
   - What's unclear: the exact derivation (this session did not locate/read `11-RESEARCH.md`).
   - Recommendation: a five-minute read before writing the LL cut's `L` — see Assumption A1.

2. **(a) vs (b) from Pattern 2 — new struct with duplicated methods, or a one-line abstract
   supertype retrofit?**
   - What we know: both are behaviorally sound and satisfy D-05's "completely untouched
     `build_master` function" requirement.
   - What's unclear: which better serves this project's existing "byte-identical by construction"
     philosophy and its test-suite's expectations (the PVAL-04 registry keys off `build_*` function
     *names*, not struct types, so either choice is compatible with D-06/D-07 as written).
   - Recommendation: planner's choice; lean toward (b) (abstract supertype) if it minimizes new
     code, since the two cut-adding functions' bodies would otherwise be near-identical duplicates.

## Environment Availability

Skipped — no new external tool/service dependency; HiGHS, Ipopt, and BilevelJuMP are already
installed and pinned in this repository's environment (confirmed live this session via
`Pkg.dependencies()` and direct `HiGHS.Highs_create()` calls).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `Test` (stdlib) + `TestItems`/`TestItemRunner` (`@testitem`/`@run_package_tests`) |
| Config file | `test/runtests.jl` (entrypoint: `@run_package_tests`) |
| Quick run command | `julia --project=. -e 'import Pkg; Pkg.test(test_args=["--tags=planning"])'` (verify exact tag-filter syntax at implementation time — TestItemRunner's CLI filtering has changed across minor versions; do NOT invoke via `julia --project=test -e '... @run_package_tests ...'` — MEMORY.md documents this as a sibling-worktree contamination hazard) |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|---------------------|--------------|
| INT-01 | Binary-expansion MILP master builds and solves via `select_optimizer(MILP())` | unit | new `@testitem` in a new or existing `test_planning_master*.jl` | ❌ Wave 0 |
| INT-02 | LL cuts + no-good fallback converge, iteration behavior re-measured, no-good count surfaced | unit + integration | new `@testitem`(s) in `test_planning_benders*.jl` | ❌ Wave 0 |
| INT-03 | Enumeration certificate (+ documented BilevelJuMP non-blocker) on the N=1 toy | integration | new `@testitem` reusing `Phase6Fixtures`/`ToyDeviceFixture`, enumerating all 16 lattice points | ❌ Wave 0 |
| INT-04 | PVAL-04 guard exemption + literate page | unit + docs | extend `test/test_planning_noninteger.jl`'s registry/EXEMPT list; new literate page under `docs/` (existing pattern) | Registry file exists (`test/test_planning_noninteger.jl`); new exemption entries do not yet exist — ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `julia --project=. -e 'import Pkg; Pkg.test()'` filtered to `[:planning]`-tagged items (fast — the existing planning suite already runs in seconds on toy fixtures).
- **Per wave merge:** full `Pkg.test()`.
- **Phase gate:** full suite green before `/gsd:verify-work`, matching the project's existing convention (2358 pass / 1 known-false Aqua fail per MEMORY.md's steady-state baseline).

### Wave 0 Gaps
- [ ] `test/test_planning_master.jl` (or a new file) — covers INT-01 (new builder's own boundary
      guards, PVAL-04-compliant non-binaries-elsewhere behavior verified via the EXEMPT registry).
- [ ] `test/test_planning_benders.jl` (extended) — covers INT-02 (LL cut per-cut validity assertion,
      D-15's continuous-baseline diff, no-good count/`:nogood_assisted` attribution, D-16).
- [ ] A new certification `@testitem` — covers INT-03 (16-point enumeration oracle; BilevelJuMP
      attempt documented as a negative regression exactly like `test_planning_certification.jl`'s
      existing BigMMode+HiGHS precedent).
- [ ] `test/test_planning_noninteger.jl` registry/EXEMPT-list extension — covers INT-04.
- Framework install: none — `Test`/`TestItems`/`TestItemRunner` already present and configured.

## Security Domain

Not applicable — `security_enforcement` is not set in `.planning/config.json` and this phase has no
authentication, session, access-control, external input-validation, or cryptography surface (it is
a pure numerical-optimization change to an internal research bench). No ASVS categories apply.

## Sources

### Primary (HIGH confidence — verified directly this session)
- `src/planning/master.jl`, `benders.jl`, `follower.jl`, `subproblem.jl` (direct code read).
- `src/solver/factory.jl`, `ProblemClass.jl` (direct code read).
- `test/test_planning_noninteger.jl`, `test_planning_goldens.jl`, `test_planning_certification.jl`,
  `fixtures_planning.jl` (direct code read).
- Live Julia spike (`julia --project=test`) against installed `BilevelJuMP 0.6.3` + `HiGHS
  1.24.1`/`Ipopt 1.15.0`: confirms `MOI.UnsupportedConstraint{VariableIndex,ZeroOne}` for
  `StrongDualityMode`/`ProductMode` (Ipopt-backed) with a binary upper-level variable; confirms
  `BigMMode`+HiGHS solves correctly for a **linearized** upper objective with a binary leader
  (`y_inv=1.0, z=1.0`, `OPTIMAL`); confirms `BigMMode`+HiGHS reproduces the exact documented MIQP
  failure on a **quadratic** upper objective (`"Cannot solve MIQP problems with HiGHS"`, matching
  `test_planning_certification.jl`'s existing negative regression verbatim).
- Live query of installed HiGHS runtime option defaults via `HiGHS.Highs_getDoubleOptionValue`:
  `mip_rel_gap = 1e-4`, `mip_abs_gap = 1e-6`, `mip_feasibility_tolerance = 1e-6`.
- `BilevelJuMP` package source read directly
  (`~/.julia/packages/BilevelJuMP/KbDlX/src/{moi,jump,jump_variables}.jl`): confirms
  `MOIU.default_copy_to` copies the entire upper-level MOI model verbatim (including any
  `ZeroOne`/`Integer` variable-attached sets) and that dualization (`Dualization.dualize`) is scoped
  to the lower level only — the structural basis for D-11's "follower continuity is what matters"
  diagnosis being correct as far as it goes.

### Secondary (MEDIUM confidence)
- G. Laporte and F. V. Louveaux (1993), "The integer L-shaped method for stochastic integer
  programs with complete recourse," *Operations Research Letters* 13, 133–142 — cut form and
  finite-convergence claim cross-checked via WebSearch against multiple secondary academic sources
  (the primary PDF was not fetched directly this session).
- A. M. Geoffrion (1972), "Generalized Benders Decomposition," *Journal of Optimization Theory and
  Applications* 10(4), 237–260 — cited for the "integer master + convex continuous recourse ⇒
  continuous cuts remain valid" theorem, cross-checked via WebSearch (Cornell/Northwestern
  optimization-wiki summaries), not fetched from the primary source this session.

### Tertiary (LOW confidence)
- None used as load-bearing claims in this document; all WebSearch findings above were
  cross-referenced against at least one additional secondary source or verified directly by code
  read/live spike before being stated as fact.

## Metadata

**Confidence breakdown:**
- LL cut algebraic form + citation: MEDIUM-HIGH — stable across multiple independent secondary
  sources, standard textbook material, not independently re-derived from the primary 1993 paper.
- Continuous-cut validity under integer master: HIGH — derived from first principles this session
  (partial-minimization convexity argument) and independently corroborated by the Geoffrion
  GBD citation.
- BilevelJuMP leader-integrality availability: HIGH — verified by a live, reproducible spike against
  the exact installed package versions, not inferred from documentation alone.
- HiGHS MILP gap defaults: HIGH — verified by a live query against the installed solver binary.
- `δ_min` non-derivability: HIGH as a negative result (the argument for *why* no generic bound exists
  is solid); inherently cannot be "verified" as a positive existence claim, which is the point.

**Research date:** 2026-08-23
**Valid until:** 30 days (stable, internal-codebase-grounded findings; the only external-package
dependency, BilevelJuMP 0.6.3, is pinned and unlikely to change within that window).

# Pitfalls Research — v2.0 Stackelberg-Nash TSO–DSO Planning Layer

**Domain:** Hand-rolled Benders decomposition + Gauss-Seidel Nash diagonalization, built on top of
the shipped v1.0 convex operational oracle (`operational_oracle(feeder, pf, aggregators; λ₀, T, z,
role, ...) -> (; cost, π, dadp, ctx)`, `src/models/oracle.jl`).
**Researched:** 2026-07-22
**Confidence:** HIGH on Benders/strong-duality theory and the v1.0 oracle's actual code contract
(read directly); MEDIUM on Nash-diagonalization convergence specifics (standard VI/game-theory
literature, not project-specific); MEDIUM-LOW on the PSR note's leader/follower and integer-cut
claims (the source itself is flagged MEDIUM-confidence and self-contradicts once — see
`THEORY-papers.md` "Cautionary flags").

> v2.0's core architectural fact, verified directly in `src/models/oracle.jl`: the coupling seam is
> **not yet load-bearing**. `operational_oracle` accepts `z` (coupling-flow setpoint) and `role`
> (`:leader`/`:follower`) as typed parameters, but `z !== nothing` currently **throws
> `ArgumentError`** (the frontier-import pin `p_import == z` is not wired into `solve_welfare`), and
> `role` is validated but never changes the solve. **Every pitfall below assumes the first v2.0 task
> is wiring this pin — not writing the Benders loop against an oracle that can't yet be pinned.**

---

## Critical Pitfalls

### Pitfall 1: Benders cuts assumed valid without confirming the pinned subproblem is still convex-strong-duality-clean

**What goes wrong:**
Standard (classical / L-shaped) Benders optimality cuts `α ≥ w^k + π^k·(z − z^k)` are valid
**only if** the subproblem is convex and strong duality holds at the trial point `z^k` — i.e. the
subproblem's optimal value is a genuine (weak, but here tight) upper-bounding **supporting
hyperplane** of the true value function `α(z)`. The v2.0 lower level *is* `operational_oracle`'s
`GLB-CVX` — LP + QP + **SOCP** — which is convex, so this holds **in principle**. But three
project-specific ways to accidentally violate the precondition:
1. **The pin constraint doesn't exist yet.** Until `p_import == z` is actually wired into
   `solve_welfare` (see the module header above), there is no constraint whose dual is `π^k`; any
   code that fakes it (e.g. reusing the *unpinned* frontier DADP as if it were the pinned coupling
   dual) generates a cut from the wrong sensitivity and it is **not** a supporting hyperplane of the
   true `α(z)` — silently invalid.
2. **SOCP relaxation inexactness (v1 Pitfall 1) reappears here with higher stakes.** If the pinned
   subproblem's SOC relaxation is inexact at the trial `z^k` (plausible exactly at the pin boundary,
   or under reverse flow / over-voltage — the same regime v1 flagged as exactness-fragile), `π^k`
   is the dual of a *relaxed*, not the *true*, feasible region. The cut is built from a fictitious
   sensitivity and can cut off the true optimum. Benders then converges confidently to a wrong
   investment equilibrium with no visible symptom (the master just "converges").
3. **Loose conic accuracy silently degrades cut tightness.** Even with an exact-in-principle
   relaxation, an `ALMOST_OPTIMAL` or loosely-toleranced Clarabel solve returns an approximate dual;
   accumulating dozens of such cuts across Benders iterations compounds error into a master problem
   that "converges" to a value systematically off from the true `α`.

**Why it happens:**
- Benders is usually taught/coded against **LP** subproblems where "solve, read the dual, add a
  cut" is foolproof; nobody re-derives the convexity/strong-duality precondition when the
  subproblem becomes an SOCP with its own exactness caveat layered on top.
- The oracle boundary (`_coupling_dual`) is a single function call — it *looks* like a black box
  that "just gives you the dual," hiding that its validity depends on upstream conditions (pin
  wired, relaxation exact, solver tight) that a Benders loop author may not re-verify per call.

**How to avoid:**
- **First implementation task, gating everything else:** wire `p_import == z` into `solve_welfare`
  as a real constraint and change `_coupling_dual` to read *that* constraint's dual when `z !==
  nothing`, removing the `ArgumentError` stub. Do not build the Benders loop against a faked pin.
- After every oracle call inside the Benders loop, assert (a) `termination_status == OPTIMAL` (not
  `ALMOST_OPTIMAL`), and (b) the SOC exactness gap `max|l·v − (P²+Q²)| < τ` at the pinned point —
  reuse the v1 exactness invariant, but re-run it **at every Benders trial point**, not just once at
  model-build time.
- Add an automated **cut-validity check**: for every generated cut `(w^k, π^k, z^k)`, assert it does
  not exceed a later-evaluated true value, `α(z') ≥ w^k + π^k·(z' − z^k)` for any subsequently
  evaluated `z'`. A violation is a hard failure, not a warning.
- Cross-validate the whole Benders loop against a **monolithic single-level convex reformulation**
  on a tiny instance (single scenario, single hour or a handful of hours) where the entire
  leader+follower problem can be solved as one convex program — Benders' optimum must match it to
  tolerance before trusting it on any larger case.

**Warning signs:**
- Benders lower bound (master) exceeds a later-computed true upper bound at some `z` (a hard cut-
  validity violation — must never happen with correct convex cuts).
- Cut coefficients `π^k` that jump erratically between consecutive, nearby trial points `z^k`
  (suggests exactness gap or loose conic tolerance, not smooth sensitivity).
- Master converges but disagrees with the monolithic small-case reformulation.

**Phase to address:** Oracle-coupling-wiring phase (implement the real pin + dual, first), then the
single-distributor Benders phase (cut-validity + exactness-at-trial-point invariants as gating
tests before Nash/diagonalization is attempted).

---

### Pitfall 2: Leader/follower roles hard-coded from the ambiguous PSR note without pinning sign conventions first

**What goes wrong:**
`THEORY-papers.md` explicitly flags: *"the note labels leader/follower inconsistently once; the
consistent reading is distributor = leader... confirm with author before hard-coding."* The
oracle's `role` kwarg already encodes this as `:leader`/`:follower` but is currently **inert** — it
doesn't change anything about the solve. When the Benders loop is actually built, three
role-dependent decisions must be made **consistently**, and getting any one backwards silently
inverts the whole equilibrium concept (it will still "solve" and "converge" — Stackelberg games
with swapped roles are still well-posed games, just the wrong one):
1. **Who optimizes first / anticipates whom.** Distributor-as-leader (PSR's stated intent) means
   the distributor's master problem embeds the transmission-reinforcement value function `α(z)` as
   an epigraph variable with Benders cuts; the transmission system (follower) is *only* ever solved
   as the inner subproblem that returns `(w^k, π^k)`. If this is flipped — transmission solved as
   an outer master with distributor cuts — the Benders decomposition target is a different (wrong)
   bilevel program, not a relabeling of the same one.
2. **Sign convention on the coupling dual `π_s`.** PSR: `π_s` = dual of `z_x,s = z_y,s` (export =
   import), described as "marginal cost of a unit increment of interconnection flow." Whether an
   *increase* in the distributor's import (`z_y`) makes the cut coefficient a cost the leader's
   objective **adds** (if `π_s ≥ 0` penalizes more import) depends on which side of the equality
   constraint is written and the model's min/max sense — exactly the class of sign bug v1 Pitfall 7
   already caught for `λ_j`, now transplanted to `π_s` at a different constraint.
3. **Which side's investment appears in whose objective.** The PSR formulation has the
   distributor's master objective include `α({z_y,s})` (transmission's response cost) as the whole
   point of the Stackelberg game (flexibility investment trades off against reinforcement cost via
   this term). If the follower subproblem's objective and the leader's epigraph term use
   inconsistent signs/units for the same physical cost, the leader will systematically
   over/under-invest in flexibility relative to the true trade-off.

**Why it happens:**
- The source document (MEDIUM confidence, single internal PSR note, no numerical case to check
  against) itself is internally inconsistent on this exact point — there is no "obviously correct"
  reading to fall back on without an independent check.
- `role` being a currently-inert, "just validate and pass through" parameter in the v1 oracle
  invites treating it as cosmetic when the real implementation lands, rather than as the load-bearing
  switch it needs to become.

**How to avoid:**
- Before writing any Benders code, write down (in the phase's design doc / docstring, not just in a
  variable name) the three decisions above as an explicit, testable contract: which problem is the
  master, which is the subproblem, and the exact sign of `π^k` in the cut `α ≥ w^k + π^k·(z − z^k)`.
- Validate the sign/role convention on a **hand-worked toy instance** (1 distributor, 1 scenario, 2–3
  discretized investment levels) where the true leader-optimal decision is computable by
  enumeration or by direct KKT inspection — assert the Benders answer matches it, not just that it
  "runs."
- Use **BilevelJuMP.jl**, on the same toy instance, as an independent oracle: build the tiny
  leader-follower MPEC directly (KKT or Fortuny-Amat single-level reduction) with the leader/follower
  roles as BilevelJuMP's own `Upper`/`Lower` levels, matching the same physical interpretation, and
  require agreement with the Benders answer. Disagreement here is far more informative than staring
  at the PSR note again — it pins the ambiguity down empirically.
- Treat `role` as a documented, tested invariant from the first Benders phase onward — not
  something to revisit "later" once more of the loop exists (by then the sign convention is baked
  into dozens of call sites).

**Warning signs:**
- Toy-instance Benders answer disagrees with brute-force enumeration or the BilevelJuMP oracle.
- Flexibility investment moving in the economically wrong direction (e.g., more reinforcement cost
  *reduces* the leader's incentive to invest in flexibility — backwards from the PSR note's stated
  value-of-flexibility story).
- `π^k`'s sign flips between iterations without the underlying physical situation changing.

**Phase to address:** Single-distributor Stackelberg-Benders phase, gated on an author-confirmed (or
BilevelJuMP-confirmed) role/sign convention **before** any multi-distributor Nash work begins —
getting this wrong once and propagating it into N distributors multiplies the fix cost.

---

### Pitfall 3: Coupling-dual sign/scale mismatch between `λ_j` (DADP) and `π_s` (interconnection dual) across the seam

**What goes wrong:**
The project's own framing is explicit that `λ_j[t] ↔ π_s` is a **conceptual** bridge, not a literal
identity: `λ_j` is the dual of the *nodal* active-balance constraint (thesis 3.31, per-hour, at every
node) inside the operational SOCP; `π_s` is the dual of the *coupling* constraint `z_x,s = z_y,s`
(PSR eq. 2e, per-scenario, at the single frontier node) inside the planning-layer follower
subproblem. Even after Pitfall 1's pin is correctly wired, three distinct sources of sign/scale
mismatch can appear when code on the planning side treats `π` (what `_coupling_dual` returns) as if
it were directly comparable to `λ_j`, or feeds it into the leader's objective without reconciling
units:
1. **Time resolution mismatch.** `λ_j[t]` is hourly (24 values/day); the PSR planning-layer
   coupling dual `π_s` is per-**scenario** (annualized/representative-period investment economics),
   not per-hour. `_coupling_dual` currently returns a length-`T` vector (hourly). Feeding a raw
   24-vector into a planning objective built for scenario-level costs without an explicit
   time-aggregation step (e.g., duration-weighted sum, or one scenario = one representative day)
   silently mixes hourly ¢/kWh-scale numbers into an annualized-investment-scale objective.
2. **Objective-sense mismatch.** The operational oracle **maximizes** welfare (3.38); the PSR
   follower subproblem (problem 2) **minimizes** reinforcement cost. JuMP dual signs depend on
   objective sense (v1 Pitfall 7 already flags this for `λ_j` alone) — carrying a dual from a
   max-sense model directly into a min-sense Benders cut without an explicit sign flip is the same
   class of bug, now crossing a model-family boundary, which is more likely to be missed because
   the two models "belong" to different code modules and are rarely inspected side by side.
3. **Which side of the pin owns the sign.** `p_import == z` can be written as `p_import - z = 0` or
   `z - p_import = 0`; JuMP's dual of an equality constraint flips sign with the constraint's
   direction. Because `_coupling_dual` is the single seam both Benders (reading `π^k`) and the
   Nash diagonalization loop (reading other distributors' equilibrium flows) depend on, a sign
   error here propagates identically into **every** consumer, making it easy to "test" the sign in
   one place, see internally-consistent (self-cancelling) results, and never notice the absolute
   sign is backwards.

**Why it happens:**
- The v1↔v2 seam is deliberately abstract (`z↔p_ag`, `λ_j↔π_s` — see the oracle module's own
  docstring) so it can be built without rewriting v1; abstraction is good, but it means the two
  numbers were never designed to be numerically comparable without an explicit reconciliation step
  someone has to write and test.
- Hourly-vs-scenario time granularity is a structural mismatch invisible in a single call — it only
  shows up when the aggregation logic is written (or, worse, silently omitted and `T[1]` is used).

**How to avoid:**
- Write an explicit, tested **reconciliation function** at the seam: given the oracle's hourly `π`
  (or `dadp`) and the scenario/period definition, produce the single per-scenario coupling value the
  Benders cut needs (duration-weighted average, or an explicit representative-hour selection),
  documented with its own equation reference (not implicit in Julia broadcasting).
- Pin the sign of `_coupling_dual`/`π^k` with a **hand-computed 2-node, 1-hour, 1-scenario toy case**
  where the correct marginal cost of interconnection capacity is known analytically (same technique
  v1 Pitfall 7 used for `λ_j`) — assert it in a permanent regression test, not a one-off REPL check.
- Add an assertion at the seam itself: `π` values fall within a documented plausible band relative to
  `λ₀` (wholesale) and to the DLMP range seen in the operational solve — a coupling dual off by a
  clean factor of 10/100/1000 (unit mismatch) or of opposite sign (convention mismatch) should fail
  loudly, not be silently accepted as a valid cut coefficient.
- Never let both the sign convention (Pitfall 2) and the scale reconciliation (this pitfall) be
  tuned simultaneously against the same toy case "until the answer looks right" — verify each
  independently (unit test for time-aggregation logic with known inputs; separate unit test for sign
  with a case where sign is analytically obvious).

**Warning signs:**
- Coupling dual magnitude wildly different from the operational DADP range on the same case.
- Benders cuts that are self-consistent (loop converges) but the resulting flexibility-investment
  level is insensitive to a deliberately large synthetic change in `c_x,inv` (reinforcement cost) —
  suggests the coupling term isn't actually entering the leader's decision with correct scale.
- Two independently-written call sites (Benders master, Nash diagonalization) disagreeing on the
  sign of "more import ⇒ more/less reinforcement cost."

**Phase to address:** Oracle-coupling-wiring phase (own the reconciliation function alongside the pin
constraint), verified again at the single-distributor Benders phase before multi-distributor Nash
work begins.

---

### Pitfall 4: Gauss-Seidel Nash diagonalization — non-convergence, cycling, and non-unique equilibria treated as a solved single answer

**What goes wrong:**
Nash-via-diagonalization (fix every distributor's flows except one, optimize that one, rotate) has
**no general convergence guarantee** outside potential games / contraction conditions. Three
distinct failure modes, each of which "looks like it worked" if not explicitly instrumented:
1. **Non-convergence / cycling** — the outer sweep's flow changes don't shrink; the loop either runs
   to a hard iteration cap (reporting a non-equilibrium iterate as if it were the answer) or
   oscillates between 2+ states indefinitely.
2. **Non-uniqueness** — even where a fixed point exists and is reached, which one depends on
   initialization and sweep order (which distributor moves first, second, ...). Reporting "the"
   equilibrium without disclosing this is a reproducibility and scientific-validity hazard —
   different runs (different seeds/orderings) can legitimately report different, both-valid Nash
   equilibria, and a paper/thesis figure built from just one run without checking this is fragile.
3. **False stability from coarse per-distributor step sizes.** If each distributor's inner Benders
   loop itself hasn't converged tightly before its flows are frozen and the sweep rotates to the next
   distributor, the outer diagonalization is iterating on noisy inputs — it may appear to converge
   (flow changes below a loose tolerance) while actually drifting slowly, undetected because the
   inner-loop residual was never checked against the outer-loop tolerance.

**Why it happens:**
- Diagonalization is simple to code (just a `for i in distributors; fix_others(); resolve(i); end`
  loop) and its convergence caveats are a game-theory subtlety, not visible in the code itself.
- The PSR note supplies **no numerical case at all** for the multi-distributor game (it is a
  methodology note) — there is no reference equilibrium to validate against, unlike the operational
  layer's IEEE-13/123 cases.
- Nash equilibria are, in general, genuinely non-unique in investment games with coupled costs;
  assuming uniqueness because the single-distributor Stackelberg case (Pitfall 1/2) was well-behaved
  is an unwarranted generalization.

**How to avoid:**
- Instrument the outer sweep with an explicit, logged convergence metric: max relative change in
  each distributor's `z_{y,i,s}` across a **full round** (all distributors touched once), not just
  between consecutive individual moves. Cap rounds and **fail loudly** (raise, don't silently return
  the last iterate) if the metric doesn't monotonically shrink within a tolerance window.
- Nest tolerances correctly: each distributor's inner Benders loop must converge to a tolerance
  strictly tighter than the outer diagonalization tolerance, or outer "convergence" is meaningless.
- **Deliberately probe non-uniqueness** as a first-class experiment, not an afterthought: run
  diagonalization from multiple initializations and multiple sweep orders (e.g., all `N!` orderings
  for small `N`, or a random sample for larger `N`) on every reported case; log whether they agree.
  If they don't, report the equilibrium as **one of several**, with the spread, not as *the* answer.
- Add damping (e.g., partial step: `z^{k+1} = (1-γ)z^k + γ·z_i^{new}`, `γ<1`) as an available lever
  to try when cycling is detected, and document/measure its effect rather than silently tuning `γ`
  until a single run happens to converge.
- Where the case is small enough, cross-check the diagonalization-found equilibrium against the
  **monolithic multi-distributor MILP/convex reformulation** solved once as a single (large) convex
  program, or against **BilevelJuMP** on a tiny multi-leader instance if that reduction is tractable
  for more than one leader (see Pitfall 6 for scaling limits).

**Warning signs:**
- Round-over-round flow changes not shrinking, or shrinking non-monotonically.
- Different initial seeds/orderings → materially different reported equilibria on the same case.
- Outer loop reports convergence while an inner distributor's own Benders gap is still loose.

**Phase to address:** Nash-diagonalization phase (after the single-distributor Stackelberg-Benders
phase is validated standalone) — convergence instrumentation and multi-seed/multi-order probing are
gating acceptance criteria for this phase, not a later hardening pass.

---

### Pitfall 5: Reusing `operational_oracle` as a repeated Benders/Nash subproblem amplifies the known intermittent Clarabel `NUMERICAL_ERROR` flake

**What goes wrong:**
`.planning/STATE.md` documents a **known, version-independent, intermittent** Clarabel
`NUMERICAL_ERROR` on the IEEE-13 ADMM cross-validation solve, correctly caught by `assert_solved!`
(the gate refuses to trust the result) but currently **unresolved** — root-caused to per-unit-base-
dependent cone-slack sensitivity, occurring on "a fraction of pushes," not a hard break. A single
operational solve in v1.0 already hits this occasionally. In v2.0, `operational_oracle` (or the
`DSO-OPT`/`AGR-OPT` SOCP subproblems it wraps) will be **re-solved far more often**:
- once per Benders iteration (potentially dozens, per the v1 ADMM's own ~28-iteration analogue),
- **times** the number of scenarios `s` in the expectation `(1/S)Σ_s`,
- **times** the number of trial points needed for the leader's own search,
- **times** the number of distributors `N` in a Gauss-Seidel round,
- **times** the number of diagonalization rounds until Nash convergence (Pitfall 4).

Even at a conservatively low per-solve failure probability, the **combinatorial multiplication**
across these loops turns an "intermittent, fraction-of-pushes" flake into a near-certainty that at
least one oracle call in a full Benders+Nash run hits `NUMERICAL_ERROR`. Two additional
planning-layer-specific ways this manifests worse than in v1:
1. **The pin (Pitfall 1) sits exactly at a boundary** — `p_import == z` fixes the frontier flow to a
   trial value chosen by the Benders master, which will deliberately probe points *away* from the
   "natural" unconstrained optimum (that's the whole point of sensitivity/cut generation). Pinning
   the import can push the subproblem toward the same reverse-flow/over-voltage/near-cone-boundary
   regime v1 already flagged as the fragile one — Benders trial points are *more*, not less, likely
   to stress the SOC exactness/numerical-conditioning edge case than a typical unconstrained
   operational run.
2. **A silent partial-solve inside a long-running loop is worse than a CI red X.** In v1, a
   `NUMERICAL_ERROR` fails a test loudly and visibly. Inside a multi-hour Benders/Nash run, an
   unhandled solver failure either crashes the whole run (losing all prior progress if there's no
   checkpointing) or — if error-handling is sloppy — gets silently caught and a stale/garbage
   `π^k` is fed into a cut, corrupting the master with an invalid cut that then produces a
   confidently-wrong "converged" equilibrium (compounds directly with Pitfall 1).

**Why it happens:**
- The flake was accepted as low-priority deferred tech debt in v1.0 precisely because it was rare
  and non-blocking for a milestone with far fewer oracle calls; that risk calculus changes
  completely once the oracle sits inside nested Benders×scenario×distributor×diagonalization loops.
- Retry/robustness code is easy to skip when writing the "happy path" Benders loop first and adding
  robustness "later."

**How to avoid:**
- Treat this as a **prerequisite hardening item for the planning layer**, not an independent
  deferred-forever item: before wiring the pin (Pitfall 1), add a bounded, logged **solve-retry**
  around `operational_oracle`'s inner solve — on `NUMERICAL_ERROR` (or `ALMOST_*`/`SLOW_PROGRESS`),
  retry with tightened Clarabel tolerances / adjusted `equilibrate` settings / a warm start from the
  previous accepted iterate, and only after a small retry budget is exhausted, fail loudly with full
  context (which Benders iteration, scenario, distributor, and pinned `z`) rather than silently
  substituting a stale value.
- **Never** catch the solver-status exception and continue with a default/last-good `π` without
  flagging it in the returned result — any such fallback must be visibly recorded alongside the
  cut it produced, so a downstream cut-validity check (Pitfall 1) can flag and discard it.
- Checkpoint Benders/Nash progress (cuts accumulated, current iterate per distributor) so a hard
  failure loses minutes, not hours, of compute — this is a DrWatson-friendly persistence problem,
  not a new dependency.
- Measure the empirical failure rate **per pinned-oracle-call** on the planning-layer's own test
  fixtures (not just reuse v1's unpinned-solve failure rate) — pinning likely changes the
  distribution of trial points relative to the exactness/conditioning edge case, so v1's rate is not
  a reliable estimate.
- Revisit the actual root-cause levers flagged in STATE.md as "candidate levers, not yet applied":
  Clarabel tolerance/`equilibrate`/`max_iter` settings and per-unit base — this planning-layer work
  is the forcing function to finally spend the "deliberate numerical-robustness pass" v1 deferred.

**Warning signs:**
- Benders/Nash runs that fail deep into a long loop with no checkpoint to resume from.
- Cut coefficients that look like a stale/repeated value across consecutive, physically-distinct
  trial points (a sign a retry silently reused a previous solve).
- Empirical solve-failure rate materially higher on **pinned** oracle calls than on the unpinned v1
  baseline (confirms the boundary-stress hypothesis above).

**Phase to address:** Oracle-coupling-wiring phase, as a co-requirement alongside the pin
constraint itself — do not build the Benders loop's happy path first and add retry/robustness
later; the combinatorial amplification argument above means this is load-bearing from day one of
the planning layer, not a hardening afterthought.

---

### Pitfall 6: Trusting the hand-rolled Benders+diagonalization loop without a BilevelJuMP certification pass — and misusing BilevelJuMP when you do

**What goes wrong:**
CLAUDE.md and the project's own stack research are explicit: BilevelJuMP.jl is a **validation
oracle only**, never the production solver (its single-level KKT/SOS1/Fortuny-Amat MPEC reductions
don't scale and don't match the thesis's decomposition intent). Two opposite failure modes:
1. **Skipping BilevelJuMP entirely** because the Benders loop "runs and converges." Given the
   PSR source's own flagged ambiguities (Pitfalls 2, 9) and the complete absence of a numerical
   reference case for the planning layer, a hand-rolled Benders/diagonalization loop that only
   checks its *own* internal consistency (residuals shrinking, cuts not obviously violated) has
   **no independent ground truth** — it can converge smoothly to a self-consistent but wrong
   equilibrium (wrong sign, wrong role, inexact-relaxation-based cut) and nothing in the loop itself
   would ever flag it.
2. **Misusing BilevelJuMP once it's added** — building a BilevelJuMP MPEC on a case large enough
   that its single-level reformulation blows up (dozens of scenarios/investment options), and either
   (a) concluding "BilevelJuMP failed, so skip validation," discarding the one independent check
   available, or (b) comparing BilevelJuMP's *reformulated* variables/duals directly against
   Benders' `π^k`/`w^k` as if they were the same objects — they are outputs of genuinely different
   mathematical reductions (KKT stationarity multipliers vs. Benders cut coefficients) and only the
   **decisions and objective value** are guaranteed comparable, not every intermediate dual.

**Why it happens:**
- Adding a second modeling framework (BilevelJuMP) for a handful of tiny validation cases feels like
  low-value overhead compared to "just getting the Benders loop working," especially under time
  pressure — exactly when independent validation is most needed given the source ambiguities.
- BilevelJuMP's reformulations (big-M / Fortuny-Amat especially) are known to be numerically
  fragile and slow to scale — a naive attempt on a "slightly bigger than trivial" case can fail for
  reasons unrelated to the Benders loop's correctness, inviting the wrong conclusion ("validation is
  too hard, skip it") instead of the right one ("shrink the validation case further").

**How to avoid:**
- Make a **tiny, tractable BilevelJuMP certification case** (1 distributor, 1–2 scenarios, a handful
  of discretized investment levels, deliberately small enough for KKT/Fortuny-Amat to solve fast and
  reliably) a **gating deliverable** of the single-distributor Benders phase, not an optional
  nice-to-have appended later.
- Compare only the objects that are mathematically guaranteed comparable across the two reductions:
  final investment decisions, final coupling flow `z`, and total objective value — not intermediate
  duals/multipliers, which live in different reformulated spaces.
- If BilevelJuMP fails to solve even the tiny case reliably (numerical fragility of its own
  reformulation), shrink further (fewer scenarios, coarser investment grid) rather than abandoning
  the cross-check — the value of an independent oracle here is categorically higher than the
  convenience of skipping it, given the source-document ambiguities this milestone inherits.
- Re-run the BilevelJuMP certification whenever the sign/role convention (Pitfall 2) or the
  coupling-dual reconciliation (Pitfall 3) changes — it is the regression test for exactly those two
  pitfalls, not a one-time bootstrap check to discard once "it passed once."

**Warning signs:**
- Benders/diagonalization code with zero references to a BilevelJuMP cross-check anywhere in the
  phase's tests.
- A BilevelJuMP case abandoned as "too slow/fragile" without first trying a smaller instance.
- Comparing BilevelJuMP's KKT multipliers directly to Benders' `π^k` and treating a mismatch (or an
  accidental match) as diagnostic — when only decisions/objective are guaranteed comparable.

**Phase to address:** Single-distributor Stackelberg-Benders phase (tiny BilevelJuMP certification
case as a gating test) — re-invoked as a regression check at the Nash-diagonalization phase if a
small enough multi-leader BilevelJuMP reduction is tractable, otherwise explicitly documented as
"validated only at the single-distributor level; multi-distributor Nash validated by cross-
seed/cross-order agreement (Pitfall 4) instead."

---

### Pitfall 7: Conflating v1's "conceptual" leader/follower narrative (convex dual decomposition) with v2's genuine bilevel/Benders structure

**What goes wrong:**
`THEORY-thesis.md`'s own framing correction is explicit: the *operational* layer's leader/follower
story (DSO designs the price, prosumers respond) is **conceptual only** — the actual solution
machinery is a single-level convex social-welfare maximization decomposed by ADMM, with **no**
KKT-of-a-lower-level, **no** MPEC, **no** genuine bilevel structure. The *planning* layer (this
milestone) is where a **real** Stackelberg game with a genuine bilevel/Benders structure first
appears in the codebase. The risk: carrying over patterns, intuitions, or even code idioms from the
operational ADMM loop (dual-ascent price updates, `λ_j ← λ_j + ρ·R_{p,j}`) into the planning loop as
if Benders cut generation were "the same kind of thing" as an ADMM dual update. They are not:
- ADMM's `λ_j` update is a **fixed-point/gradient-ascent** step on a single convex problem's dual;
  it does not build an outer epigraph/cut model, has no "master problem," and converges to the
  *same* problem's optimum every time (given exact subproblems).
- Benders' `π^k` is used to build a **growing outer approximation** (the master's cuts) of a
  genuinely different (upper-level) problem's value function; the master and subproblem are
  different optimization problems in a real bilevel hierarchy, and "convergence" means the outer
  approximation has tightened enough — a structurally different guarantee than ADMM's residual
  shrinking.
Treating the planning loop as "ADMM with an extra layer" risks reusing the wrong convergence
criteria (primal/dual residual language, thesis-tuned `ρ`/`ε`) where Benders' actual gap criterion
(upper bound − lower bound) is what's needed, and risks reusing v1's dual-decomposition mental
model to (mis)validate the planning layer against the wrong kind of ground truth.

**Why it happens:**
- Both layers involve "solve a subproblem, read a dual, update something, iterate" — superficially
  identical control flow, textually adjacent in the codebase (`operational_oracle` sits right next
  to where the Benders loop will live), inviting pattern reuse without re-deriving what convergence
  actually means in the new setting.
- The project's own naming (`λ_j ↔ π_s`) deliberately draws the analogy for the *coupling variable*
  bridge — useful for architecture, but easy to over-extend into "the algorithms are analogous too."

**How to avoid:**
- Document, in the planning-layer's own module header (mirroring `oracle.jl`'s style), the explicit
  distinction: "this loop is Benders (outer approximation of a genuine bilevel value function), NOT
  ADMM (dual-ascent on a single convex problem) — do not reuse ADMM's residual-based stopping
  criterion; use the Benders gap (UB − LB) instead."
- Use a different, purpose-built convergence-tracking struct for the Benders/Nash loop rather than
  adapting the ADMM `AdmmResiduals`-style struct, so the two are never silently interchanged.
- When validating (Pitfall 1, 6), always validate against a genuine single-level **bilevel**
  reformulation (monolithic MILP/convex reformulation of the *full* leader+follower problem, or
  BilevelJuMP) — never against "the same kind of check v1 used for ADMM" (which only ever validated
  against the single-level `GLB-CVX`, a fundamentally different target).

**Warning signs:**
- Planning-layer code stopping on a residual-shrinking criterion copied from `admm/residuals.jl`
  rather than an explicit upper/lower bound gap.
- Documentation or commit messages describing the Benders loop as "like ADMM but for planning."
- Validation code comparing the Benders result to the *operational* `GLB-CVX` optimum (the wrong
  ground truth — that only validates the lower-level oracle, not the bilevel equilibrium itself).

**Phase to address:** Architecture/design step at the start of the planning-layer work (before any
Benders code is written) — an explicit written contrast between the two algorithms, referenced by
both modules' docstrings.

---

### Pitfall 8: Deferred integer-cut correctness accidentally reintroduced through a "quick" discrete-investment shortcut

**What goes wrong:**
v2.0's locked scope is explicit: **continuous** flexibility investment variables only; discrete/
integer expansion (binary-expansion + Lagrangian/integer-L-shaped cuts) is deferred, precisely
because the PSR note's cut representation is "exact only for binary/continuous LP subproblems" and
the author flagged integer-cut correctness as an open concern (carried over from v1 Pitfall 9,
still unresolved). The risk in *this* milestone is not building the integer machinery on purpose,
but **accidentally reintroducing an integer-like structure** through a seemingly innocuous modeling
shortcut and then generating classical (LP-dual) Benders cuts against it without realizing the
precondition broke:
- Discretizing a "continuous" investment into a small number of candidate levels "just to make the
  master a simpler LP" (a coarse grid is, structurally, an integer/combinatorial choice even if
  coded as a continuous variable with a rounding step afterward).
- Adding an on/off "invest or don't" indicator anywhere in the flexibility-investment or
  reinforcement model for convenience (e.g., a fixed cost that only applies "if invested at all")
  — this reintroduces exactly the MIP structure the continuous-first scope was designed to avoid,
  and classical LP-dual Benders cuts against it are invalid per the PSR note's own caveat.

**How to avoid:**
- Keep the investment variables **genuinely continuous** (convex cost, no fixed/step costs, no
  indicator variables) end-to-end through this milestone; if a fixed/step cost or discrete choice
  seems necessary for realism, treat that as **out of scope** for v2.0 and flag it for the deferred
  integer-cut milestone rather than working around it with a partial discretization inside the
  "continuous" scope.
- Add an explicit guard/assertion (or a code-review checklist item) that the leader's and follower's
  subproblems contain **no binary or discretized decision variables** anywhere before generating a
  classical Benders cut — this is the direct, cheap version of the cut-validity check in Pitfall 1,
  specialized to catch this specific regression.

**Warning signs:**
- Any `@variable(..., Bin)` or manually-rounded/discretized "continuous" investment variable
  appearing in the planning-layer models.
- A "quick fix" commit adding a fixed cost or on/off toggle to the investment cost function.

**Phase to address:** Scoping/architecture guard at the start of the planning-layer work, enforced
by an automated no-binaries assertion in every planning-layer subproblem builder — explicitly listed
as out-of-scope-for-this-milestone in the phase's own acceptance criteria.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Reuse the frontier DADP as a stand-in for the pinned coupling dual `π^k` (skip wiring the real pin) | Unblocks Benders coding immediately | Cuts built from the wrong sensitivity — invalid, silently wrong equilibrium (Pitfall 1) | Never — must wire the real pin first |
| Hard-code distributor = leader without an author/BilevelJuMP confirmation | Saves a validation step | Whole equilibrium concept inverted if wrong; expensive to detect later (Pitfall 2) | Never |
| Skip the tiny BilevelJuMP certification case "since Benders converges" | Faster to a demo | No independent ground truth against a MEDIUM-confidence, self-contradicting source (Pitfall 6) | Never for the first single-distributor case; may be skipped only for later, clearly-analogous scenario variants once the core case is certified |
| Reuse ADMM's residual-based stopping criterion for the Benders/Nash loop | Less new code | Wrong convergence semantics; may stop before the true Benders gap has closed (Pitfall 7) | Never |
| Add retry-on-`NUMERICAL_ERROR` "later, once the loop works" | Faster initial Benders loop | Combinatorial amplification (Pitfall 5) means the loop will fail deep into a long run with no salvage | Only acceptable for a throwaway single-shot prototype never run at multi-scenario/multi-distributor scale |
| Discretize "continuous" investment into a coarse grid inside this milestone | Simpler master LP | Silently reintroduces the deferred integer-cut correctness problem (Pitfall 8) | Never in v2.0 scope |
| Skip cross-seed/cross-order probing of Nash equilibria to save compute | Faster reported result | Non-uniqueness hidden; reproducibility hazard for thesis/paper figures (Pitfall 4) | Only for internal debugging runs, never for a reported/published result |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|--------------|-----------------|-------------------|
| `operational_oracle` (v1 seam) | Passing `z !== nothing` before the pin is wired and treating the resulting `ArgumentError` as a bug to silence rather than the intended fail-loud guard | Wire the real `p_import == z` constraint into `solve_welfare` first; only then pass non-`nothing` `z` |
| `operational_oracle`'s `role` kwarg | Assuming `role` already changes solver behavior because it's a typed, validated parameter | Confirm (via code read, as done here) that `role` is currently inert; the planning phase must make it load-bearing, not assume it already is |
| BilevelJuMP.jl | Using it as the production planning solver, or scaling it up until it becomes the de facto solver for medium cases | Tiny gating certification cases only (Pitfall 6); production path is always hand-rolled Benders |
| Clarabel (inside the oracle, called repeatedly) | Assuming v1's "rare, non-blocking" failure rate still holds once call volume multiplies across Benders×scenario×distributor×diagonalization loops | Re-measure failure rate on pinned, planning-layer-scale call patterns; add bounded retry + checkpointing before scaling up loops (Pitfall 5) |
| HiGHS (Benders master) | Rebuilding the master model from scratch each time a cut is added (v1 Pitfall 5's lesson, transplanted) | Persist the master model; add cuts via `@constraint` on the existing model; never rebuild |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Rebuilding the Benders master each iteration to add one cut | Time dominated by model construction, not solving | Persist the master `Model`; append cuts in place (v1 Pitfall 5 lesson) | Any case with more than a handful of Benders iterations |
| Solving all scenarios/distributors serially inside one Benders/diagonalization round | Wall-clock scales linearly with `S × N` | Parallelize independent oracle calls (per scenario, per distributor-fixed-others) | Multi-scenario, multi-distributor cases |
| No warm-start between successive pinned oracle calls at nearby `z^k` | Every Benders iteration's subproblem solves cold | Warm-start from the previous iteration's primal/dual point (nearby pins ⇒ nearby solutions) | Many Benders iterations per distributor |
| Retrying a `NUMERICAL_ERROR` oracle call with no bound | A single stuck subproblem can hang the whole loop | Bounded retry budget with escalating tolerance adjustments, then fail loud (Pitfall 5) | Any pinned trial point near the SOC exactness/conditioning edge |

## Security Mistakes

Maps to research integrity/reproducibility, as in v1.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Reporting a single Nash-diagonalization run's equilibrium without disclosing seed/order sensitivity | A thesis/paper figure built on one of several valid equilibria, presented as *the* answer | Always report the multi-seed/multi-order probe (Pitfall 4) alongside any published equilibrium |
| Silently substituting a stale `π` on a `NUMERICAL_ERROR` retry without flagging it in provenance | A cut in the published master is derived from garbage, undetectable after the fact | Log every retry/fallback in the run's provenance record (DrWatson `tagsave`-style), tied to the specific cut it produced |
| Unpinned BilevelJuMP/PATHSolver version drift between the certification run and the "real" Benders run | Certification silently stops matching the production solver path | Pin BilevelJuMP + solver versions in `Manifest.toml`; re-run certification whenever either changes |

## UX Pitfalls

"Users" = the PhD researcher and collaborators extending/reading this planning layer.

| Pitfall | User Impact | Better Approach |
|---------|-------------|------------------|
| Benders/Nash loop reports only a final equilibrium, no gap/residual history | Can't distinguish "converged" from "ran out of iterations" | Surface UB/LB gap history, per-round flow-change history, and the seed/order used as first-class outputs (mirrors v1's convergence-diagnostics precedent) |
| `role`/sign convention documented only in a code comment, not enforced | Silent regression if someone "cleans up" the oracle call later | Encode the confirmed leader/follower + sign convention as an assertion/test, not just prose |
| BilevelJuMP certification run once, then deleted/forgotten | No regression protection against future sign/role changes | Keep the tiny certification case as a permanent, fast-running regression test, not a throwaway validation script |

## "Looks Done But Isn't" Checklist

- [ ] **Oracle pin wired:** `z !== nothing` no longer throws — but is the dual actually read off the *pin* constraint, not a proxy (Pitfall 1)?
- [ ] **Benders cuts generated:** loop converges — but has cut-validity been asserted (`α(z') ≥ w^k + π^k(z'-z^k)`) at points beyond the generating trial (Pitfall 1)?
- [ ] **Leader/follower roles assigned:** `role=:leader`/`:follower` passed through — but confirmed against a toy-case enumeration or BilevelJuMP, not just the PSR note as written (Pitfall 2)?
- [ ] **Coupling dual read from the seam:** `π` returned — but reconciled for time-resolution (hourly vs. scenario) and sign convention against a hand-computed toy case (Pitfall 3)?
- [ ] **Benders/Nash run completes:** an equilibrium is reported — but was it checked from multiple seeds/sweep orders for non-uniqueness (Pitfall 4)?
- [ ] **Oracle re-solves inside the loop:** runs succeed on the dev machine — but is there a bounded retry + checkpoint for `NUMERICAL_ERROR`, measured at planning-layer call volume, not assumed from v1's rate (Pitfall 5)?
- [ ] **Validation claimed:** "matches expectations" — but was there an actual BilevelJuMP certification run on a tiny case, kept as a regression test (Pitfall 6)?
- [ ] **Convergence criterion:** loop stops — but on a genuine Benders gap (UB-LB), not a residual-shrinking criterion copied from ADMM (Pitfall 7)?
- [ ] **Investment variables:** modeled as continuous — but audited for any snuck-in binary/discretized/on-off structure (Pitfall 8)?

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|-----------------|
| Cuts generated against an un-pinned/proxy dual | MEDIUM | Wire the real pin, discard and regenerate all prior cuts (they were built from the wrong sensitivity), re-run Benders from scratch |
| Wrong leader/follower role baked in | MEDIUM-HIGH | Swap master/subproblem roles, re-derive sign convention, re-validate on the toy case + BilevelJuMP before re-running any larger case |
| Coupling-dual sign/scale error discovered late | MEDIUM | Fix the reconciliation function's sign/aggregation, re-run affected cuts; contained if the reconciliation is a single seam function (by design) |
| Nash equilibrium reported without uniqueness check | LOW | Re-run the existing result set from multiple seeds/orders retroactively; disclose spread in the writeup — does not require re-deriving the model |
| Oracle `NUMERICAL_ERROR` crashes a long run with no checkpoint | HIGH (lost compute) | Add checkpointing + retry before re-running; without checkpointing, must restart the whole Benders/Nash run from scratch |
| BilevelJuMP certification skipped, later found to disagree | HIGH | Every Benders cut/decision generated since the skipped certification is suspect; must re-certify and re-validate the full accumulated cut set, not just the newest ones |
| Integer structure snuck into a "continuous" investment variable | MEDIUM-HIGH | Remove the discrete/indicator structure, re-verify no-binaries assertion, regenerate cuts under the genuinely continuous model |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|----------------|
| 1. Benders cut validity vs. convex SOCP lower level | Oracle-coupling-wiring phase → single-distributor Benders phase | Pin wired + dual read from real constraint; automated cut-validity check (`α(z') ≥` cut) at every Benders iteration; exactness gap re-checked at every trial `z^k` |
| 2. Leader/follower role & sign ambiguity | Single-distributor Stackelberg-Benders phase (gated before Nash) | Toy-case enumeration match + BilevelJuMP agreement on the tiny certification case |
| 3. Coupling-dual sign/scale (`λ_j` ↔ `π_s`) | Oracle-coupling-wiring phase (own the reconciliation function) | Hand-computed toy-case sign/scale regression test; magnitude-band assertion at the seam |
| 4. Nash-diagonalization non-convergence/non-uniqueness | Nash-diagonalization phase | Multi-seed/multi-order convergence probe as a gating test; explicit UB-LB-style round metric, capped with fail-loud |
| 5. Oracle-in-loop numerical robustness (`NUMERICAL_ERROR` amplification) | Oracle-coupling-wiring phase (co-requirement with the pin) | Bounded retry + checkpoint implemented before any multi-iteration Benders loop is exercised; empirical failure-rate re-measured at planning-layer call volume |
| 6. BilevelJuMP certification (trust boundary for the hand-rolled loop) | Single-distributor Stackelberg-Benders phase (gating deliverable) | Tiny BilevelJuMP KKT/Fortuny-Amat case kept as a permanent regression test; re-run whenever Pitfall 2/3 conventions change |
| 7. ADMM-vs-Benders conceptual conflation | Architecture/design step, start of planning-layer work | Written contrast in module docstrings; distinct convergence-tracking struct (gap-based, not residual-based) for Benders/Nash |
| 8. Integer-cut correctness reintroduced via discretization shortcut | Scoping guard, start of planning-layer work | Automated no-binaries/no-discretized-investment assertion in every planning-layer subproblem builder |

## Sources

- `src/models/oracle.jl` (read directly, 2026-07-22) — HIGH confidence: `operational_oracle`'s
  actual signature, the `z`/`role` SEAM-01 stub semantics, and the confirmed-as-inert `role`
  parameter and confirmed-throwing `z`-pin are read from the shipped v1.0 code, not inferred.
- `.planning/research/THEORY-papers.md` (PSR N1–N2 note extraction) — MEDIUM confidence per the
  extraction's own flag: single internal note, no numerical case, self-contradictory leader/follower
  labeling once, integer-cut caveat stated by the source itself.
- `.planning/research/THEORY-thesis.md` — HIGH confidence on the "operational layer is NOT itself a
  Stackelberg/MPEC" framing correction (Pitfall 7's basis).
- `.planning/research/v1.0/PITFALLS.md` — HIGH confidence carry-over basis for Pitfalls 1, 2, 3, 5's
  root causes (SOCP exactness, dual-sign conventions, solver-status discipline) and the seed
  content for what became Pitfalls 4 and 8 here (deepened with v2.0-specific detail).
- `.planning/STATE.md` — HIGH confidence on the documented, accepted, unresolved intermittent
  Clarabel `NUMERICAL_ERROR` flake (Pitfall 5's factual basis: version-independent, per-run
  fractional occurrence, root-caused to per-unit-base cone-slack sensitivity, candidate levers not
  yet applied).
- `CLAUDE.md` (project instructions) — HIGH confidence on the BilevelJuMP-as-validation-oracle-only
  policy and the hand-rolled-Benders-is-the-production-path decision (Pitfall 6's basis).
- Standard Benders/strong-duality and diagonalization/VI convergence theory (textbook-level:
  Benders decomposition requires convexity + strong duality of the subproblem for cut validity;
  Gauss-Seidel-style diagonalization/best-response dynamics lack general convergence guarantees
  outside potential-game/contraction conditions) — MEDIUM confidence, general literature not
  independently re-verified against a live source this session, consistent with v1.0 PITFALLS.md's
  own treatment of the same theory.

---
*Pitfalls research for: v2.0 Stackelberg-Nash TSO–DSO planning layer (Benders + Gauss-Seidel
diagonalization over the v1.0 convex operational oracle)*
*Researched: 2026-07-22*

# Feature Research

**Domain:** Power-systems optimization research bench — five new research axes on a validated
convex branch-flow TSO–DSO transactive-pricing framework (JuMP/Julia)
**Researched:** 2026-07-26
**Confidence:** MEDIUM-HIGH (canonical papers verified via search; several axes cross-checked
against multiple independent sources; some Julia-ecosystem specifics remain MEDIUM)

> **Framing note.** This is a *subsequent-milestone* feature landscape for v3.0 "Research
> Extension Rungs" — it supersedes the v2.1 FEATURES.md previously at this path (AC-exactness
> certification / reactive consensus / IEEE-123 impedances / directional reproduction, now
> shipped). It covers ONLY the five v3.0 research axes layered on top of the already-shipped
> v1.0 operational core, v2.0 planning layer, and v2.1 validation hardening.

## Context: what "feature" means here

This is not a consumer product — "features" are **research capabilities** (a formulation, a
solve strategy, a validation certificate). Table stakes = what the power-systems-optimization
literature treats as the minimum correct/citable version of each capability. Differentiators =
what would make this bench notable vs. a bare textbook implementation. Anti-features = scope
traps that look like "the real thing" but are wrong-sized for a "minimal validated rung."

---

## Axis 1 — Overvoltage-Capable Relaxation (high-PV reverse-flow SOCP inexactness)

### Background (what the literature says the failure mode is)

Farivar & Low's branch-flow model (Farivar & Low, *"Branch Flow Model: Relaxations and
Convexification,"* IEEE Trans. Power Systems, 2013, arXiv:1204.4865) proves the SOC relaxation
of `l_ij = (P_ij²+Q_ij²)/v_i` is **exact for radial networks provided there is no upper bound on
voltage** (or, more precisely, no upper voltage bound binding) — the LinDistFlow-copy trick this
project already uses (thesis eq. 3.43–3.45) is exactly this "no-upper-voltage-bound-on-the-relaxed-copy"
device. Gan, Li, Topcu & Low (*"Exact Convex Relaxation of Optimal Power Flow in Radial
Networks,"* arXiv:1311.7170 / IEEE TAC 2015) sharpen this: exactness for radial networks holds
under an a-priori-checkable condition tied to **no reverse real power flow** and a
resistance/reactance-ratio monotonicity condition moving away from the substation. High-PV
reverse flow is *precisely* the condition this project's own v2.1 AC-oracle found violated
(EXACT-04: gap≈10.4, voltage pinned at `V²max`) — this is not a novel failure, it is the textbook
edge case the literature already names. **HIGH confidence**, multiple independent sources agree.

### Standard responses in the literature (ranked by fit for a "minimal validated rung")

| Approach | What it does | Fit for this project |
|----------|--------------|----------------------|
| **QC / strengthened SOCP with valid inequalities (cutting planes)** | Add valid cuts (e.g. tightened `S_max` cone bounds, McCormick-style envelope tightening) to shrink the relaxation gap without abandoning conic solvers | Table stakes candidate — cheap, keeps Clarabel, keeps duals-as-prices intact. Multiple ScienceDirect/arXiv sources ("cutting planes based relaxed OPF," "properties of convex OPF based on power-loss relaxation") treat this as the standard first response for active distribution systems with DG |
| **Convex-hull relaxation of the branch-flow quadratic constraint** | Replace the SOC relaxation with the actual convex hull of the (nonconvex) `l=(P²+Q²)/v` equation over the box `[v_min,v_max]` (arXiv:1701.07146, "Convex Hull of the Quadratic Branch AC Power Flow Equations…") | Differentiator — theoretically tighter, still conic-representable, but adds real modeling complexity for a "minimal rung"; good v3.1+ follow-on |
| **Sequential convex approximation / convex-concave procedure (penalized SOCP)** | Iteratively re-linearize the nonconvex gap term and penalize it in the objective, re-solving a sequence of SOCPs (SCA/CCP is the standard nonconvex-QCQP recipe) | MEDIUM fit — recovers near-AC-feasible points but loses the clean "price = dual of one convex QP" story; convergence to only a local optimum, and duals from the last SCA iterate are heuristic, not certified LP/SOCP duals |
| **Direct nonconvex AC-OPF pricing with local-solution caveats** | Solve the true nonconvex AC-OPF (already available in this repo as `ACPowerFlow`/Ipopt) and read `dual()` off its equality constraints as a *local* DADP | Table-stakes fallback — the project already has the AC oracle; the "new" work is *documenting the caveat* (local-optimum, no global-optimality certificate, KKT multiplier ≠ market-clearing price in general) rather than building new machinery |
| **Restriction (shrink the feasible set to force exactness)** | Tighten the *relaxed* problem's own bounds (e.g. Gan/Low's "shrinking the feasible set slightly") so the SOCP's optimum is provably AC-feasible, at the cost of a (small, bounded) loss of true optimality | Table stakes — directly matches the "shrink feasible set" device Gan & Low prove for radial networks; cheapest to implement given the existing LinDistFlow-copy scaffolding, and preserves the pricing-as-duals story exactly |

**Recommended minimal rung:** combine **restriction** (tighten `V²max`/reverse-flow-aware bound
on the relaxed copy, in the spirit of Gan & Low's a-priori-checkable condition) as the primary
mechanism, with the **existing AC-oracle as the certifying peer** (already built in v2.1) rather
than the CCP/SCA route — this keeps the pricing semantics convex-dual and citable, and reuses
`assert_ac_exact!` as the acceptance gate for the new regime instead of building a second oracle.
Document the **direct nonconvex fallback** (Ipopt AC-OPF dual, with explicit local-optimum
caveat) as the honest last resort when even the restricted SOCP cannot certify exactness — this
mirrors the project's existing "report, don't throw" philosophy (EXACT-01..04).

### Complexity: MEDIUM. Reuses `AbstractPowerFlow`/`ACPowerFlow`/`assert_ac_exact!` (no new
solver dependency); the new work is bound-tightening logic + a new certificate, not a new solver
integration.

### Dependency
Directly extends `models/exactness.jl` and the AC-oracle machinery from v2.1 (EXACT-01..04).
No SEAM-01 stub currently targets this axis by name — it is a refinement of the existing
`pf::AbstractPowerFlow` dispatch point, not the meshed slot (that is axis 4, see below), and
should NOT be conflated with it even though both touch "the relaxation machinery" (flagged as
an explicit interdependency in PROJECT.md).

---

## Axis 2 — MPC / Rolling-Horizon / Real-Time Pricing

### Standard ingredients (cross-checked across MPC-for-microgrid/EV-charging literature)

| Ingredient | Standard treatment | Notes |
|------------|--------------------|-------|
| **Terminal state constraint / terminal value** | Either (a) a hard terminal-SOC target (e.g. "battery ends the horizon at ≥ SOC₀" or at a scenario-specific target) or (b) a terminal *value function* (economic MPC with a terminal cost approximating "value of stored energy beyond the horizon") | Literature on EV/BESS MPC (MDPI 2024 "EV Charging Control... MPC," arXiv:2012.14624 "Deferrable Load Scheduling under Demand Charge: Block MPC") consistently flags that omitting a terminal condition causes end-of-horizon myopic battery dump/hoarding — a known artifact, not a subtle one |
| **Forecast-error model** | Perfect-foresight-over-shrinking-horizon is the simplest (deterministic re-solve each step with updated forecast); stochastic/robust variants replace point forecasts with scenario trees or error bounds | For a "minimal validated rung," deterministic re-solve with a synthetic forecast-error injection (perturb the known ground truth by a bounded noise process at each rolling step) is standard and cheap — matches this project's existing seeded-Markov data generation pattern (thesis §2.8) |
| **Closed-loop vs. open-loop benchmarking** | Standard practice: report the *closed-loop* trajectory (what actually happens under receding-horizon re-solves with realized, not forecast, disturbances) against the *open-loop*/perfect-foresight day-ahead optimum as the ceiling | This project already states this explicit benchmark target in PROJECT.md ("benchmarked against the perfect-foresight day-ahead solve") — matches literature norm exactly |
| **Rolling price-consistency metrics** | Track (i) price volatility/jump magnitude between consecutive re-solves, (ii) cumulative deviation of realized rolling DADP path from the day-ahead DADP path, (iii) welfare/cost gap vs. perfect foresight | No single canonical metric name in the literature; report as a small metrics struct (residual style, matching this project's existing ADMM-residual/BendersTrace conventions) |

### Table stakes vs differentiators

- **Table stakes:** deterministic receding-horizon re-solve loop; terminal SOC handling (even a
  simple terminal-target constraint, not a full value function); closed-loop-vs-open-loop
  comparison table/plot.
- **Differentiator:** rolling re-computed DADP as an actual re-priced signal at each step (not
  just re-dispatch) — this is the "real-time pricing" framing the milestone specifically wants,
  and is a genuine extension beyond a bare MPC re-dispatch loop.
- **Anti-feature:** a full economic-MPC terminal *value function* (dynamic-programming-derived
  terminal cost) or a robust/tube-MPC formulation — both are standard in the control literature
  but are overkill for "minimal validated rung"; a hard terminal-SOC target is the right-sized
  substitute. Defer value-function terminal costs to a later milestone if closed-loop
  performance is found lacking.

### Complexity: MEDIUM. The mechanism (JuMP `Parameter` re-solve without rebuild) is **already
verified in this codebase's own research notes** — `horizon_state = nothing` in
`operational_oracle` is explicitly documented as reserved for exactly `@variable(m, s0 in
Parameter(v)); set_parameter_value(s0, x)` (oracle.jl, "RESEARCH Pattern 6, verified"). The new
work is the *outer rolling loop* + terminal-condition constraint + benchmarking harness, not the
re-solve mechanism itself.

### Dependency
Directly consumes the **SEAM-01 `horizon_state` stub** in `operational_oracle`
(`src/models/oracle.jl`) — this is the named, already-scaffolded hook (`MPC-01/02` in the code
comments). No new seam needs to be invented; the milestone's job is to make this stub load-bearing.

---

## Axis 3 — Stochastic PV/Demand Uncertainty (scenario-based extensive form)

### Standard formulation

Two-stage (or multi-stage) stochastic programming extensive form: build one large welfare
problem over all scenarios `s∈S` with probabilities `π_s`, first-stage (here-and-now) decisions
shared across scenarios, second-stage (wait-and-see) recourse decisions indexed by scenario,
objective = `Σ_s π_s · welfare_s(...)`. This is the textbook approach and is exactly what the
milestone specifies ("scenario-based extensive form first"). Confirmed as the standard DLMP
pattern in recent literature (ScienceDirect "e-Carsharing siting... DLMP-based under demand
uncertainty" — explicit two-stage stochastic DLMP model with scenario-based demand uncertainty).

### Scenario generation & reduction

- **Generation:** the thesis's own data layer already uses first-order Markov chains for
  occupancy/PV/demand (thesis §2.8) — the natural, in-repo-consistent generator for scenario
  *trees*, not just i.i.d. draws. A recent paper (ScienceDirect 2023, "Stochastic optimization
  and Markov chain-based scenario generation for exploiting flexibilities of an active
  distribution network") confirms Markov-chain scenario generation is standard practice for
  exactly this PV/demand setting — directly reusable, not a new technique to import.
- **Reduction:** literature standard is fast-forward/backward reduction or k-means clustering to
  collapse a large sampled set down to a tractable few representative scenarios with adjusted
  probabilities (examples found: 1000→7 scenarios via fast-forward reduction; 3000→20 via
  k-means). For a "minimal validated rung," a **small, fixed, seeded scenario count** (e.g. 3–5
  scenarios, no formal reduction algorithm) is the right-sized table stake; a full scenario-
  reduction algorithm (fast-forward/k-means) is a differentiator to defer.

### Stochastic DLMP/price semantics — the key modeling decision

Two legitimate semantics exist in the literature, and they answer different questions:
1. **Expected/scenario-weighted dual** — the dual of the extensive-form nodal balance constraint
   *as written* (if the balance constraint is scenario-indexed, its dual is a genuine per-scenario
   price; if scenarios share a single first-stage balance row, the dual is a probability-weighted
   expected price). Confirmed practice: "DLMPs... obtained by the dual variables of constraints"
   and "the LMP is equal to the weighted dual variable of the nodal power balance constraint" in
   stochastic security-constrained unit commitment — i.e., **weighted/expected duals are the
   standard semantics when the balance constraint itself is aggregated across scenarios.**
2. **Per-scenario dual** — if the model keeps a *separate* balance constraint per scenario (as an
   extensive form naturally does for second-stage recourse variables), each scenario gets its own
   genuine dual/DADP; these can differ substantially across scenarios (e.g. a low-PV scenario
   prices congestion, a high-PV scenario prices overvoltage/curtailment).
This project should document **per-scenario DADPs as the primary output** (since each scenario's
balance constraint is genuinely distinct in an extensive form with scenario-indexed recourse), and
report the probability-weighted expectation as a derived summary statistic, not the other way
around — this preserves the existing "price = dual of the nodal balance" framing exactly, just
applied per-scenario, rather than inventing a new "expected-price" primitive that has no single
well-defined constraint behind it.

### Out-of-sample validation

Standard practice (confirmed pattern across the stochastic-OPF literature): evaluate the
extensive-form solution's *first-stage* decisions against a held-out set of scenarios **not**
used in the optimization (an out-of-sample test), reporting the realized cost/welfare gap vs. the
in-sample expected value — this is the stochastic-programming analogue of this project's existing
train/test discipline (e.g. the AC-oracle-as-independent-peer pattern) and should be reused as the
validation gate for this axis.

### Complexity: MEDIUM. Building the extensive form itself is mechanical (replicate the existing
single-scenario JuMP model S times, share first-stage variables) — the genuine complexity is
(a) deciding and documenting the per-scenario-vs-expected DADP semantics honestly, and (b) an
out-of-sample validation harness.

### Dependency
Directly consumes the **SEAM-01 `objective_hook` stub** (`src/models/oracle.jl`,
`STOCH-01/02` in code comments) — reserved exactly for "compose the per-scenario welfare into
the extensive-form objective." This is the named hook to make load-bearing for this axis.

### Anti-feature
Full Sample Average Approximation (SAA) convergence studies, distributionally-robust
formulations, or chance-constrained reformulations — all standard *deeper* stochastic-programming
techniques, but explicitly out of scope for a "minimal validated rung" (these are natural v3.1+
follow-ons once the extensive form and its semantics are validated).

---

## Axis 4 — Meshed Networks + 4Q-BESS

### Meshed branch-flow exactness — the angle-recovery obstruction

Farivar & Low (2013) and Gan/Li/Topcu/Low prove a specific, important asymmetry: for **radial**
networks, both the angle-elimination step and the SOC relaxation are exact together. For
**meshed** networks, **the SOC/conic relaxation itself remains exact, but the angle-recovery step
is not guaranteed** — a relaxed solution can be power-flow-feasible in `(v,l,P,Q)` space yet have
no consistent voltage-angle assignment across a cycle (the classic "angle relaxation" gap). Their
fix: check a simple a-posteriori condition on whether the relaxed solution is angle-recoverable;
if not, either (a) accept the SOCP as a valid *lower bound* without a physically-realizable angle
solution, or (b) **add phase-shifters** at a spanning-tree-complement set of lines to convexify
the meshed network exactly (their proposed convexification route). This is the single most
citable, HIGH-confidence fact for this axis — confirmed independently across three separate
Farivar/Low/Gan sources.

**Practical alternatives for a "minimal validated rung"** (beyond full phase-shifter
convexification, which is a heavier structural change):
- **QC (quadratic convex) relaxation** — tighter than plain SOCP, still conic-representable,
  commonly used as a meshed-network alternative in the OPF-relaxation literature when angle
  recovery matters.
- **SDP relaxation** — provably at least as tight as SOCP for meshed networks (SOCP is a
  projection/relaxation of the SDP relaxation), standard in the meshed-OPF-relaxation literature,
  but heavier (larger PSD cone, slower solves) — a differentiator/defer candidate, not a table
  stake, unless the SOCP+angle-check is shown to actually fail on the project's own meshed test
  fixture.
- **Post-hoc feasible-solution recovery** — several papers (e.g. "Recover Feasible Solutions for
  SOCP Relaxation of OPF Problems in Mesh Networks") describe local-search/perturbation recovery
  of a true AC-feasible point from a relaxed meshed solution when the direct relaxation is
  inexact — a reasonable fallback matching this project's existing "AC oracle as certifying peer"
  pattern (reuse `ACPowerFlow` again, exactly as in axis 1) rather than importing a new recovery
  algorithm.

**Recommended minimal rung:** implement plain SOCP for the meshed case (the conic relaxation
itself needs no new mathematics beyond dropping the radial-only exactness copy), add the
angle-recoverability a-posteriori check from Gan/Low as the *validity certificate* for this rung
(this is the natural meshed-specific counterpart to the existing `assert_ac_exact!`), and treat
QC/SDP tightening and phase-shifter convexification explicitly as deferred differentiators.

### Four-quadrant BESS

Confirmed standard treatment across multiple sources (ScienceDirect "Optimal provision of
concurrent primary frequency and local voltage control from a BESS considering variable
capability curves"; ScienceDirect "Optimal active and reactive power scheduling for
inverter-integrated PV and BESS"): a 4Q-BESS is modeled with an **inverter apparent-power
capability constraint** `p² + q² ≤ S_max²` (a second-order cone, directly composable with the
project's existing SOCP machinery — no new cone type needed) plus **independent sign-free `p`
and `q` decision variables** (vs. this project's current thesis-faithful active-only battery,
thesis A3). This is a *strict superset* of the current battery model: table stakes = add `q_bess`
as a genuine decision variable inside the existing per-inverter `S_max` cone; the differentiator
is wiring `q_bess` into the **already-existing-but-inert reactive dual-ascent** path
(`reactive_consensus`/`qag_dso`/`extract_reactive_dlmp` from v2.1) so that it becomes *live*
(the reactive price actually moves in response to a live decision variable) rather than the v2.1
one-shot certified-but-fixed dual.

### Volt-VAR

IEEE 1547-style Volt-VAR droop control (reactive power set as a function of local voltage) is the
standard *industry* control law, but it is a **decentralized heuristic control rule**, not an
optimization-native primitive — confirmed by multiple sources ("IEEE 1547 standard mandates
Volt-VAR mode..."; "Optimal Design of Volt/VAR Control Rules of Inverters using Deep Learning").
For this project's optimization-first framing, the correct analogue is **not** to hand-code a
droop curve, but to let the SOCP/QP jointly optimize `q_bess` subject to the capability cone and
voltage limits — the optimization *subsumes* Volt-VAR as a special (myopic, non-optimal) case.
**Anti-feature: do not implement a literal IEEE 1547 Volt-VAR droop-curve controller** — it would
be an out-of-place decentralized-heuristic detour inside an optimization-first framework; if a
"Volt-VAR-like" behavior is wanted for comparison, derive it as a *post-hoc characterization* of
the optimal `q_bess(v)` relationship the SOCP already produces, not a separately-coded control law.

### Complexity: MEDIUM-HIGH. Meshed formulation itself is a moderate lift (new topology, new
exactness certificate, breaks the `assert_radial` invariant deliberately); 4Q-BESS is a smaller,
well-understood addition (one more SOC constraint, one more decision variable) that unlocks
already-built v2.1 reactive machinery.

### Dependency
Meshed formulation consumes the **SEAM-01 meshed-formulation slot** — explicitly named in
`src/models/oracle.jl` as "the `pf::AbstractPowerFlow` argument IS the seam: a future
`MeshedFlow <: AbstractPowerFlow` plugs in here and would bypass the `assert_radial` invariant."
4Q-BESS's live reactive dual-ascent consumes the **v2.1 `reactive_consensus`/`qag_dso` machinery**
(REACT-01..03) — this is not a SEAM-01 stub but an existing, shippable feature being switched
from "fixed constant" to "live decision variable." **Flagged interdependency (per PROJECT.md):**
both axis 1 (overvoltage relaxation) and this axis touch "the relaxation/exactness machinery" —
sequence axis 1 before or alongside axis 4 so the meshed exactness certificate can reuse whatever
generalized restriction/AC-oracle-certification pattern axis 1 establishes, rather than inventing
two independent certification mechanisms.

---

## Axis 5 — Discrete/Integer Investment Expansion

### Standard method: Laporte–Louveaux integer L-shaped

Laporte & Louveaux (*"The integer L-shaped method for stochastic integer programs with complete
recourse,"* Operations Research Letters, 1993) is the canonical generalization of Benders/L-shaped
decomposition to problems with **integer first-stage (here: investment) variables**: the master
problem is a MILP over the integer investment variables with (i) standard LP-relaxation Benders
optimality/feasibility cuts when needed, and (ii) a genuine **integer optimality cut** (a
no-good-style cut using the fact the first-stage variables are bounded integers, so a finite
big-M-free cut can certify "no better solution exists with this integer assignment") whenever the
LP relaxation's cuts are insufficient to close the gap at an integer-feasible master solution.
Confirmed across multiple sources; modern refinements exist (Angulo et al. 2016 "alternating
between linear and mixed-integer subproblems," and a 2025 arXiv paper on "non-supporting no-good
optimality cuts") but the 1993 Laporte–Louveaux method is the correct **table-stakes** citation
and starting point for a minimal rung — the refinements are legitimate differentiators/defer
candidates, not required for validity.

### Binary expansion

The PROJECT.md/thesis source (PSR N1–N2 note) already specifies **binary-expansion** as the
mechanism for integer investment sizes (i.e., represent a bounded integer investment level as a
sum of binary "block" variables, `x = Σ_k 2^k b_k` or a unary/SOS1 block expansion depending on
whether the discrete levels are naturally ordered blocks) — this is a standard MILP modeling
device, not novel; the genuine new work is wiring the **integer** L-shaped cuts (not just LP
Benders cuts) around this now-discrete master.

### No-good cuts vs. optimality cuts — what's actually needed here

A "no-good cut" (`Σ_{k: x̂_k=1} x_k + Σ_{k: x̂_k=0}(1-x_k) ≤ n-1`) merely excludes a *specific*
previously-tried integer assignment — it proves nothing about optimality, only that that exact
point won't be revisited (useful as a cheap anti-cycling safety net, weak as a convergence
driver). The Laporte–Louveaux **integer optimality cut** is strictly stronger — it uses the
subproblem's optimal value at the incumbent integer point to cut off *all* points that cannot beat
that value, not merely the one point itself. **Recommendation: implement the genuine
Laporte–Louveaux integer optimality cut as the primary convergence mechanism; keep a plain
no-good cut only as a cheap defensive fallback/anti-stall guard**, not as the convergence
argument — conflating the two would leave the algorithm technically running but without a
real finite-convergence proof behind it.

### What convergence guarantees are lost / kept vs. the current continuous Benders

| Property | Continuous Benders (current, v2.0) | Integer L-shaped (new, v3.0 axis 5) |
|----------|-------------------------------------|----------------------------------------|
| Finite convergence | Yes — standard LP Benders converges in finitely many cuts to the *global* LP optimum | Yes, but weaker: Laporte–Louveaux integer L-shaped is finitely convergent to the **global MILP optimum** only under "complete recourse" and boundedness of the integer first stage — genuinely finite, but typically far more iterations/branch nodes than the continuous case, and each integer-optimality-cut iteration requires solving an integer (not LP) subproblem, which is itself NP-hard in general |
| Cut tightness | LP duality gives exact supporting hyperplanes everywhere | Integer optimality cuts are valid but generally **not** tight/supporting everywhere off the incumbent — more cuts are needed for the same gap closure |
| Master problem class | LP/QP (HiGHS/Clarabel, polynomial) | MILP (HiGHS MIP, worst-case exponential) — the master itself becomes the bottleneck, not just cut generation |
| Existing no-binaries guard (PVAL-04) | Enforced (no integers anywhere in planning) | **Consciously scoped down, not deleted** (per PROJECT.md) — becomes "no undeclared/unexpected integers outside the axis-5 investment block," a narrower guard, not a blanket ban |
| Nash/diagonalization compatibility | Gauss-Seidel diagonalization assumes each distributor solves a well-behaved (continuous) best-response | With integer investments, best-response becomes a MILP per distributor per sweep — diagonalization still mechanically works (solve, fix, move to next), but the "a converged equilibrium" honesty-gate language (already adopted in v2.0) becomes *even more* essential, since integer best-response equilibria have weaker existence/uniqueness theory than continuous Nash — do not claim existence, only report empirically |

### Complexity: HIGH. This is the heaviest of the five axes: new master problem class (MILP),
new cut type (integer optimality cuts, not a drop-in extension of the existing LP Benders cut
code), and a probable interaction with the Nash diagonalization loop's convergence story.

### Dependency
Directly extends the existing hand-rolled `BendersMaster`/cut-store machinery from v2.0
(PLAN-04..07) — this is not a SEAM-01 stub but a planned **scoping-down** of the existing
**PVAL-04 no-binaries guard**, explicitly called out in PROJECT.md ("PVAL-04 no-binaries guard
consciously scoped down, not deleted"). Recommend sequencing this axis **last** among the five
(or at minimum, after axis 4/Nash-adjacent work settles) since it is the only axis touching the
planning layer rather than the operational layer, and its correctness depends on the continuous
Benders baseline (PVAL-02..04 pinned goldens) remaining a stable regression to diff against.

### Anti-feature
Full branch-and-Benders-cut (lazy-constraint callback integration with HiGHS/Gurobi) or a
general Dantzig-Wolfe/Coluna-style framework — both are legitimate *scaling* upgrades once the
integer L-shaped method is validated, but are explicitly declined project-wide per CLAUDE.md
("No decomposition mega-framework... they impose structure that fights a research bench") and
are out of scope for a minimal rung.

---

## Feature Dependencies

```
[Axis 1: Overvoltage-capable relaxation]
    └──extends──> src/models/exactness.jl + ACPowerFlow (v2.1 EXACT-01..04)
    └──shares-machinery-with──> [Axis 4: Meshed relaxation/exactness]  (flagged interdependency,
                                  PROJECT.md — sequence together, don't invent two certificates)

[Axis 2: MPC / rolling-horizon / RTP]
    └──requires──> SEAM-01 `horizon_state` stub (operational_oracle, MPC-01/02)
    └──requires──> JuMP Parameter re-solve pattern (already verified in oracle.jl comments)

[Axis 3: Stochastic PV/demand uncertainty]
    └──requires──> SEAM-01 `objective_hook` stub (operational_oracle, STOCH-01/02)
    └──requires──> existing Markov-chain data-generation layer (thesis §2.8, reused not replaced)

[Axis 4: Meshed networks + 4Q-BESS]
    └──requires──> SEAM-01 meshed-formulation slot (`pf::AbstractPowerFlow` dispatch point)
    └──requires──> v2.1 reactive-consensus machinery (REACT-01..03: qag_dso, extract_reactive_dlmp)
                       to go from "fixed dual" to "live decision variable"
    └──breaks──> `assert_radial` invariant (Feeder construction) — intentional, scoped to MeshedFlow only

[Axis 5: Discrete/integer investment expansion]
    └──requires──> v2.0 continuous Benders baseline (BendersMaster, PLAN-04..07) as the regression
                       to diff against
    └──scopes-down──> PVAL-04 no-binaries guard (guard narrowed, not deleted)
    └──interacts-with──> Nash diagonalization (NASH-01..04) — best-response becomes MILP; honesty-gate
                       language ("a converged equilibrium") becomes load-bearing, not just prose
```

### Dependency Notes

- **Axis 2 and Axis 3 are the cheapest/lowest-risk** — both consume SEAM-01 stubs that are
  already typed, documented, and load-bearing-ready (`horizon_state`, `objective_hook`); neither
  touches the relaxation/exactness machinery or the planning layer.
- **Axis 1 and Axis 4 share risk** — both touch the SOCP relaxation/exactness certification
  machinery. The roadmap should decide whether to do axis 1 first (establishing a general
  restriction/AC-oracle-certification pattern) and have axis 4 reuse it, or genuinely parallelize
  them with an explicit reconciliation step.
- **Axis 5 is the highest-risk/highest-complexity and structurally independent of axes 1–4** — it
  touches only the planning layer (Benders/Nash), not the operational SOCP/branch-flow machinery.
  It can be sequenced last without blocking the other four, and should be, given its HIGH
  complexity rating and interaction with the Nash equilibrium-existence honesty framing.

## MVP Definition (per-axis "minimal validated rung")

### Launch With (v3.0) — one minimal rung per axis, all five required per PROJECT.md

- [ ] **Axis 1:** restricted/tightened SOCP (Gan-Low-style feasible-set shrink) + reuse of
      `assert_ac_exact!` as the certifying gate on the known EXACT-04 high-PV scenario — must
      actually price that scenario, not merely refuse it
- [ ] **Axis 2:** deterministic receding-horizon re-solve loop over `horizon_state`, hard
      terminal-SOC constraint, closed-loop-vs-perfect-foresight benchmark table
- [ ] **Axis 3:** small fixed seeded scenario set (3–5 scenarios) via existing Markov generator,
      extensive-form solve via `objective_hook`, per-scenario DADP as primary output +
      probability-weighted expectation as derived summary, one out-of-sample check
- [ ] **Axis 4:** plain SOCP meshed relaxation (drop LinDistFlow-copy, no phase-shifter
      convexification) + Gan/Low angle-recoverability a-posteriori check as the validity gate;
      4Q-BESS apparent-power cone + `q_bess` wired into the existing v2.1 reactive-dual path
- [ ] **Axis 5:** binary-expansion investment (per PSR note) + Laporte–Louveaux integer
      optimality cuts on top of the existing `BendersMaster`; PVAL-04 guard narrowed and
      re-tested as a scoped-not-deleted regression

### Add After Validation (v3.1+)

- [ ] QC/SDP tightening for meshed exactness — if plain-SOCP+angle-check proves insufficient
- [ ] Phase-shifter convexification for meshed networks — if the angle-recovery gap is material
- [ ] Formal scenario-reduction algorithm (fast-forward/k-means) — if fixed small scenario counts
      prove insufficient for credible uncertainty coverage
- [ ] Economic-MPC terminal value function (vs. hard terminal-SOC target) — if closed-loop
      performance is found materially worse than open-loop under the simple terminal constraint
- [ ] Angulo et al. (2016) / non-supporting no-good-cut refinements to integer L-shaped — if plain
      Laporte–Louveaux proves too slow on the project's planning fixtures

### Future Consideration (v4+)

- [ ] Distributionally-robust / chance-constrained stochastic reformulations (axis 3)
- [ ] Full branch-and-Benders-cut / lazy-constraint MILP integration (axis 5) — explicitly
      declined per CLAUDE.md's anti-mega-framework stance unless scaling genuinely demands it
- [ ] Literal IEEE 1547 Volt-VAR droop-curve controller (axis 4) — anti-feature; only revisit if a
      reviewer/collaborator specifically needs a decentralized-control comparison baseline

## Feature Prioritization Matrix

| Feature | User Value (research/thesis value) | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Axis 1 restricted-SOCP + AC-oracle certification | HIGH (prices the thesis's own motivating scenario) | MEDIUM | P1 |
| Axis 2 receding-horizon + terminal SOC + benchmark | MEDIUM-HIGH | MEDIUM | P1 |
| Axis 3 extensive-form + per-scenario DADP | MEDIUM-HIGH | MEDIUM | P1 |
| Axis 4 meshed SOCP + angle check | HIGH (new topology class) | MEDIUM-HIGH | P1 |
| Axis 4 4Q-BESS + live reactive dual-ascent | HIGH (unlocks deferred v2.1 item) | LOW-MEDIUM | P1 |
| Axis 5 binary-expansion + integer L-shaped | HIGH (completes thesis's planning-layer scope) | HIGH | P1 |
| QC/SDP meshed tightening | MEDIUM | HIGH | P3 |
| Formal scenario reduction algorithm | LOW-MEDIUM | MEDIUM | P3 |
| Economic-MPC terminal value function | LOW-MEDIUM | HIGH | P3 |
| Phase-shifter meshed convexification | MEDIUM | HIGH | P3 |

**Priority key:** P1 = required for v3.0 (all five axes are must-haves per PROJECT.md); P3 =
explicit v3.1+/v4+ deferrals.

## Sources

- Farivar & Low, *"Branch Flow Model: Relaxations and Convexification"* (Parts I & II), IEEE
  Trans. Power Systems, 2013 — https://arxiv.org/pdf/1204.4865 (HIGH confidence, canonical)
- Gan, Li, Topcu & Low, *"Exact Convex Relaxation of Optimal Power Flow in Radial Networks,"*
  arXiv:1311.7170 (IEEE TAC 2015) — HIGH confidence, canonical
- Gan & Low, *"Exact Convex Relaxation of OPF in Tree Networks,"* arXiv:1208.4076 — HIGH confidence
- "Convex Hull of the Quadratic Branch AC Power Flow Equations..." arXiv:1701.07146 — MEDIUM
  confidence (single source)
- "Recover Feasible Solutions for SOCP Relaxation of OPF Problems in Mesh Networks" (ResearchGate)
  — MEDIUM confidence
- "Cutting planes based relaxed optimal power flow in active distribution systems" (ResearchGate)
  — MEDIUM confidence
- Laporte & Louveaux, *"The integer L-shaped method for stochastic integer programs with complete
  recourse,"* Operations Research Letters 13(3), 1993 — https://www.sciencedirect.com/science/article/abs/pii/016763779390002X
  (HIGH confidence, canonical; verified via Semantic Scholar + ScienceDirect abstract cross-check)
- Angulo, Ahmed & Dey (2016) integer L-shaped enhancement (referenced via secondary sources) —
  MEDIUM confidence (not directly fetched, cited by name only)
- arXiv:2511.06340, "Integer L-Shaped Method with Non-Supporting No-Good Optimality Cuts" (2025) —
  MEDIUM confidence, single source, confirms no-good-cut vs. optimality-cut distinction is an
  active research area
- ScienceDirect, "Optimal provision of concurrent primary frequency and local voltage control from
  a BESS considering variable capability curves" (arXiv:1910.04052 companion) — MEDIUM-HIGH
  confidence, cross-checked across two related papers
- ScienceDirect, "Optimal active and reactive power scheduling for inverter-integrated PV and BESS
  under inverter current constraints" — MEDIUM confidence
- IEEE 1547 Volt-VAR mode references (multiple secondary sources: arXiv:2210.12805, arXiv:2211.09557,
  industry blog) — MEDIUM confidence on standard's scope; HIGH confidence Volt-VAR is a
  decentralized droop control, not an optimization primitive (consistent across all sources)
- ScienceDirect, "e-Carsharing siting and sizing DLMP-based under demand uncertainty" — MEDIUM
  confidence, single source for two-stage stochastic DLMP framing
- ScienceDirect (2023), "Stochastic optimization and Markov chain-based scenario generation for
  exploiting flexibilities of an active distribution network" — MEDIUM-HIGH confidence, directly
  confirms Markov-chain scenario generation (already this project's own data-gen approach) is
  standard practice
- General MPC-for-microgrid/EV-charging sources (MDPI 2024 EV-MPC, arXiv:2012.14624 Block-MPC,
  arXiv:1606.06682 Plug-and-Play MPC) — MEDIUM confidence, consistent terminal-condition/
  closed-loop-benchmarking pattern across all three
- Project-internal: `.planning/PROJECT.md`, `.planning/research/THEORY-thesis.md`,
  `src/models/oracle.jl` (SEAM-01 stub definitions, HIGH confidence — primary source, own codebase)

---
*Feature research for: TSO-DSO v3.0 Research Extension Rungs (five research axes)*
*Researched: 2026-07-26*

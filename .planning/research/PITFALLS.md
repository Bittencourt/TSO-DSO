# Pitfalls Research

**Domain:** v3.0 "Research Extension Rungs" — adding overvoltage-capable relaxation, MPC/rolling-horizon/RTP,
stochastic PV/demand uncertainty, meshed networks + 4Q-BESS, and integer investment expansion to an
existing, validated Julia/JuMP TSO-DSO transactive-energy optimization framework.
**Researched:** 2026-07-26
**Confidence:** MEDIUM-HIGH — grounded directly in this repo's code (`src/models/exactness.jl`,
`src/models/oracle.jl`, `src/admm/solve_admm.jl`, `src/admm/DsoOpt.jl`, `src/devices/PVBattery.jl`,
`src/planning/benders.jl`, `test/test_planning_noninteger.jl`, `src/experiments/Scenario.jl`,
`src/experiments/store.jl`) and the project's own documented v1.0–v2.1 lessons
(`.planning/RETROSPECTIVE.md`, `.planning/PROJECT.md`). Domain-optimization pitfalls (Benders with
integer recourse, meshed SOC-relaxation structural gap, ADMM two-block dual ascent) are standard
results in the convex-optimization/decomposition literature (MEDIUM confidence on the general
theory — not independently re-verified against a specific paper this session; HIGH confidence on
how they interact with THIS codebase's specific mechanisms, which were read directly).

This file organizes pitfalls by the five v3.0 research axes. Each axis covers a DOMAIN pitfall
(a mistake in the optimization theory/economics itself) and an INTEGRATION pitfall (a mistake in
how the new capability plugs into this system's existing certificates, guards, and goldens).

## Critical Pitfalls

### Axis 1: Overvoltage-capable relaxation

#### Pitfall 1: A new formulation quietly reuses `assert_socp_exact!`'s tuned tolerance as its own certificate

**What goes wrong:**
The overvoltage rung ships a new formulation (tightened relaxation, exact reformulation, or a
recovery/rounding step) for the regime where `assert_socp_exact!` currently — correctly — throws
(EXACT-04: gap≈10.4 on IEEE-13 `pv_scale=1.2`, real IEEE-123 upper band). The new formulation is
declared "exact" either by (a) reusing the existing `rtol=1e-4`/`atol=1e-6` gate unmodified, or (b)
loosening those constants until the SAME gate stops throwing on the SAME EXACT-04 fixture — neither
is a certificate that the new mechanism actually closes the gap; it's tuning the detector, not
fixing the defect.

**Why it happens:**
`assert_socp_exact!`'s tolerance was derived and empirically validated for the RADIAL LinDistFlow
exactness copy (thesis 3.43–3.45) — a specific mechanism that makes the cone tight. A genuinely
different overvoltage-capable mechanism needs its own derivation of why the cone should be tight
under it, and its own tolerance re-derivation; reusing the existing constant is the path of least
resistance under time pressure.

**How to avoid:**
- Require a NEW, separate certificate function (e.g. `assert_overvoltage_exact!`) with its own
  documented derivation of why the new mechanism drives the cone tight — do not silently repurpose
  `assert_socp_exact!`'s constants.
- Cross-validate the new formulation against the INDEPENDENT nonconvex AC oracle (`ACPowerFlow`,
  `assert_ac_exact!`) on the EXACT EXACT-04 fixture (IEEE-13 `pv_scale=1.2`, real IEEE-123 upper
  band) — the oracle exists specifically so a new relaxation is not validated only against itself.
- Never treat "the old gate stopped throwing" as evidence; treat "the AC oracle agrees" as evidence.

**Warning signs:**
- A PR/plan that touches `exactness.jl`'s `rtol`/`atol` defaults in the same commit that claims
  overvoltage capability.
- A new formulation validated only by re-running `assert_socp_exact!`, with no `assert_ac_exact!`
  cross-check on the EXACT-04 fixtures.

**Phase to address:** Overvoltage-capable relaxation phase (gate design must precede or ship
alongside the formulation, per the project's gate-then-golden convention).

---

#### Pitfall 2: Pricing off a single local AC-OPF solution with no multi-start evidence

**What goes wrong:**
If the overvoltage rung falls back to (or cross-validates against) the Ipopt AC oracle for pricing
in the regime the SOCP legitimately cannot certify, a SINGLE local Ipopt solve is used as "the"
ground truth. AC-OPF is nonconvex; Ipopt returns a local stationary point, which may not be global
in the overvoltage/reverse-flow regime specifically (voltage pinned at bounds — exactly where
multiple local optima are most likely).

**Why it happens:**
The existing `ACPowerFlow`/`assert_ac_exact!` machinery already runs a single Ipopt solve
per-hour as an oracle; extending it to also be a PRICING source (not just a certification source)
without adding multi-start is the natural, minimal-effort path.

**How to avoid:**
- Multi-start Ipopt from several distinct initial voltage guesses on any AC-derived price used for
  publication; report spread, not a point estimate.
- Apply the project's own honesty-gate pattern (`run_nash_probe`'s "a converged equilibrium, never
  the" language) here: "an AC-consistent price (spread: …)", never "the AC price."

**Warning signs:**
- A price reported from a single Ipopt call with no seed/initial-point variation, especially near a
  voltage bound.

**Phase to address:** Overvoltage-capable relaxation phase.

---

#### Pitfall 3: A stabilizing penalty term contaminates the dual that becomes the price

**What goes wrong:**
A tempting way to make the overvoltage regime "well-behaved" is adding a penalty/regularization
term (e.g., a soft voltage-violation penalty, or a proximal term near the knife-edge) to the
objective or to the balance constraint. Since DADP is defined as `dual(:balance_p)`, ANY penalty
term that touches the balance constraint or is folded into the objective in a way that shifts its
shadow price silently changes what "price" means — the researcher ships a number that is part
physical marginal cost, part tuning artifact, with no visible flag.

**Why it happens:**
Penalty terms are the standard numerical trick to tame a hard nonconvex/knife-edge region; it is
easy to add one without tracing its effect through to the specific dual that downstream code reads
as a price.

**How to avoid:**
- Any new penalty term must be checked against which constraint's dual is later read as DADP/DLMP.
- If the penalty structurally cannot avoid touching that dual, it must be decomposed and disclosed
  as its own named component — mirroring `extract_reactive_dlmp`'s explicit rule: "a certified,
  citable... component, never summed into the active total."
- Prefer penalties on AUXILIARY constraints/variables that do not intersect `:balance_p`.

**Warning signs:**
- A new objective term or constraint added in the same formulation that also defines `:balance_p`,
  with no explicit accounting of its effect on `dual(:balance_p)`.

**Phase to address:** Overvoltage-capable relaxation phase.

---

#### Pitfall 4: Byte-identical default path breaks, or gate-then-golden ordering is inverted

**What goes wrong:**
Two integration failure modes: (a) threading the new formulation through `solve_welfare`/
`operational_oracle` changes ANY numeric output on the EXISTING default (no-overvoltage-flag) path,
silently invalidating pinned v1.0/v2.0/v2.1 regression goldens; (b) the new overvoltage certificate
is implemented as report-don't-throw (like `assert_ac_exact!`) when its actual job is a HARD gate
(like `assert_socp_exact!`/PF-04) — since its whole purpose is letting the framework price a case it
previously refused, getting the throw/report polarity backwards either re-refuses legitimately
priceable cases or publishes prices with no certificate at all.

**Why it happens:**
The codebase has TWO existing certificate patterns (hard-throw PF-04 vs. report-don't-throw
`assert_ac_exact!`) and it is easy to copy the wrong one for a capability whose entire point is
being a NEW hard pricing gate, not a diagnostic report.

**How to avoid:**
- Add a default-path regression test asserting the new kwarg/dispatch path is OFF by default and
  every existing golden is untouched, before adding the new formulation's own tests.
- Explicitly decide and document: is the new overvoltage certificate throw-refusing (like PF-04) or
  report-only (like `assert_ac_exact!`)? Given its job is to REPLACE a refusal with a price, it
  should be throw-refusing — get this decision on record before implementation.

**Warning signs:**
- Any existing pinned test's numeric golden changes when the new axis's default (off) path is
  exercised.

**Phase to address:** Overvoltage-capable relaxation phase.

---

### Axis 2: MPC / rolling-horizon / RTP

#### Pitfall 5: Terminal-SOC myopia silently invalidates the PVBattery no-binaries argument

**What goes wrong:**
A rolling window with no terminal cost/constraint drains batteries (and distorts thermostatic
setpoints) at every window edge, because the optimizer has zero visibility beyond the horizon.
Separately and more dangerously: `PVBattery.jl`'s entire justification for omitting a
`p_ch·p_dch == 0` constraint is a FULL-horizon strict-cost-ordering argument
(`λ_min < λ_med < λ_max` makes simultaneous charge/discharge strictly dominated) that was proven
for the ORIGINAL T=24 basis. Chopping the horizon into short rolling windows can reweight the
marginal utility trade-off near a window's tail and reintroduce simultaneous charge/discharge that
the no-binaries proof never covered at short T.

**Why it happens:**
MPC rolling-horizon is a well-known myopia trap in general; what's specific to THIS system is that
the no-binaries guarantee is a PROOF tied to a specific horizon length, not a universal property of
the device model — extending to arbitrary `T_window` silently steps outside the proof's domain.

**How to avoid:**
- Add an explicit terminal-SOC target or cost term (or shrink the horizon at the simulation's true
  end) so the window's optimum reflects value beyond its edge.
- Re-run the existing `p_ch[t]·p_dch[t] < τ` post-solve check (already implemented in
  `Aggregator.jl`) as a HARD gate specifically at the rolling `T_window` used, not only at T=24 —
  do not assume the docstring's proof transfers untested to a shorter window.

**Warning signs:**
- Batteries showing SOC at `Emin`/`Emax` at every window boundary in a simulated run.
- The post-solve `p_ch·p_dch` check silently not re-run per rolling window (only run once at the
  end of the whole simulation).

**Phase to address:** MPC / rolling-horizon / RTP phase.

---

#### Pitfall 6: Comparing closed-loop MPC cost to open-loop day-ahead as if they share an information set

**What goes wrong:**
The natural benchmark is the existing perfect-foresight centralized solve (`solve_welfare`/
`operational_oracle` over the full 24h). But that solve sees the ENTIRE horizon's forecast with
zero error; MPC only sees each window's forecast. Reporting "MPC costs X% more than day-ahead" as
a comparable finding, without framing it as a value-of-information gap, risks manufacturing an
inflated, uncited percentage — the same class of error the project already had to correct once
(the thesis's own +25% welfare figure, which REPRO-01/02 showed does not reproduce; see
`.planning/research/` and `memory/v2.1-socp-inexactness-and-thesis-repro.md`).

**Why it happens:**
It is the obvious, cheapest benchmark to compute; the information-set mismatch is easy to overlook
when both numbers come from the "same" scenario data.

**How to avoid:**
- Explicitly frame any MPC-vs-day-ahead cost gap as "value of perfect information," not
  "MPC underperformance" — match the project's REPRO-01/02 honesty-framing precedent.
- If a fair apples-to-apples comparison is wanted, feed the day-ahead solve the SAME rolling
  forecast information (i.e., also handicap it), or report both numbers with the information-set
  difference stated up front in the same sentence as the percentage.

**Warning signs:**
- A headline percentage gap between MPC and day-ahead cost with no accompanying statement of what
  forecast information each solve had access to.

**Phase to address:** MPC / rolling-horizon / RTP phase.

---

#### Pitfall 7: Window-boundary price discontinuities misread as a real-time-pricing volatility finding

**What goes wrong:**
DADPs recomputed fresh each rolling window will show jumps at window boundaries purely from (a)
new forecast information arriving, (b) Clarabel returning a slightly different optimum across
near-identical adjacent-window re-solves (numerical noise), or (c) ADMM convergence tolerance
slack if the operational solve is decomposed. Reporting these jumps as evidence of "real-time price
volatility" without first isolating forecast-driven changes from solver/decomposition noise
misattributes a numerical artifact as an economic finding.

**Why it happens:**
The rolling re-solve pipeline naturally produces a jagged price series; distinguishing "real"
volatility from noise requires an extra analysis step that's easy to skip once a plot "looks
interesting."

**How to avoid:**
- Before reporting any price-discontinuity finding, re-solve the SAME window twice (identical
  inputs) and quantify solver-repeat noise as a baseline; only jumps exceeding that baseline are
  candidate real volatility.
- If ADMM is used for the rolling solves, also separate ADMM-convergence-tolerance-driven jitter
  from genuine forecast-driven price movement.

**Warning signs:**
- A volatility claim with no repeat-solve noise floor established first.

**Phase to address:** MPC / rolling-horizon / RTP phase.

---

#### Pitfall 8: `horizon_state` gets wired in a way that violates build-once/`Parameter`-re-solve

**What goes wrong:**
`operational_oracle`'s `horizon_state` kwarg is currently an INERT stub (`oracle.jl` lines
112–121: accepted, `@debug`-logged, never applied). Wiring it live for real rolling-horizon state
(battery `soc0`, thermostatic initial temperature) the naive way — rebuilding the JuMP model each
rolling step with a new initial condition baked into the constraint RHS — reintroduces exactly the
"rebuilding JuMP models each iteration" anti-pattern the project's own stack doc explicitly forbids
(and which `solve_admm`'s build-once/`Parameter` design was built to avoid for the ADMM outer loop).

**Why it happens:**
Passing a new initial condition through a fresh `solve_welfare` call per window is the simplest
code to write; the build-once discipline requires deliberately keeping ONE built model and mutating
`soc0`/initial-temperature via a JuMP `Parameter` + `set_parameter_value`, which takes more upfront
design.

**How to avoid:**
- Thread `horizon_state` as a JuMP `Parameter` on the initial-condition constraints
  (`soc[1] == soc0`, thermostatic initial temp), matching the project's own cited recipe
  (`@variable(m, s0 in Parameter(v)); set_parameter_value(s0, x)` — already named in the
  `oracle.jl` docstring as "RESEARCH Pattern 6, verified").
- Build the operational model ONCE across the whole rolling simulation; each window is a
  `set_parameter_value` + re-solve, not a `solve_welfare(...)` rebuild.

**Warning signs:**
- A rolling-horizon implementation that calls `solve_welfare`/`build_dso_opt`/`build_agr_opt`
  inside the per-window loop.

**Phase to address:** MPC / rolling-horizon / RTP phase.

---

#### Pitfall 9: A rolling window drifts into overvoltage-inexact territory with no defined fallback

**What goes wrong:**
If a rolling window's pinned initial SOC pushes the network state near the high-PV reverse-flow
knife-edge, the per-window solve can legitimately hit `assert_socp_exact!`'s throw (PF-04) mid
-simulation. Sequencing MPC before the overvoltage-capable relaxation axis ships means a rolling
simulation has no defined behavior when this happens (abort the whole run? skip the window? use a
stale price?) — a silent catch-and-continue would ship an incorrect price with no certificate,
exactly the failure mode PF-04 exists to prevent.

**Why it happens:**
PROJECT.md itself flags this dependency ("Known interdependency: overvoltage-capable relaxation
and meshed+4Q-BESS both touch the relaxation/exactness machinery — sequencing decided in the
roadmap") but does not extend the same interdependency note to MPC, which also touches the same
exactness gate every time it re-solves.

**How to avoid:**
- Decide window-level failure handling explicitly (hard-abort the simulation with a named error is
  the safe default, matching PF-04's existing throw-refuse polarity) — do not silently skip or
  interpolate a window's price.
- Prefer sequencing the overvoltage-capable relaxation phase BEFORE (or concurrently gated with)
  the MPC phase if rolling scenarios are expected to visit the reverse-flow regime.

**Warning signs:**
- A rolling-horizon test suite that never exercises a high-PV scenario (so the interaction is
  never tested), or one that catches the exactness error silently inside the per-window loop.

**Phase to address:** MPC / rolling-horizon / RTP phase — sequencing decision, cross-referenced
with Overvoltage-capable relaxation phase.

---

### Axis 3: Stochastic PV/demand uncertainty

#### Pitfall 10: Misreading a scenario-weighted constraint's dual as a plain per-scenario DADP

**What goes wrong:**
In an extensive-form stochastic formulation, a balance constraint of the form
`Σ_s prob_s · balance_s = 0` (or per-scenario balance constraints coupled by a shared first-stage
decision) yields duals that are inherently PROBABILITY-SCALED — `dual(balance_s)` in that setting
is generally `prob_s × (marginal value)`, not directly the same object as the current
single-scenario `dadp = dual(balance_p)`. Treating a per-scenario dual as directly comparable to,
or summable with, the existing 4-way DLMP decomposition (energy/loss/congestion/voltage) without
re-deriving what a "stochastic DADP" means economically would misreport the price.

**Why it happens:**
The codebase's whole pricing story rests on "duals = prices" via a SINGLE-scenario formulation;
extensive-form scenario weighting is a structurally different constraint shape, and it is easy to
keep reading `dual(...)` the same way out of habit.

**How to avoid:**
- Explicitly derive, in the phase's own documentation, what the stochastic DADP IS (e.g.,
  `dual(balance_s) / prob_s` as the per-scenario marginal value, or a probability-weighted
  first-stage price as "the" DADP with per-scenario duals reported as a separate decomposition
  component) before shipping any number.
- Apply the same never-silently-summed discipline REACT-01/02 established for the reactive DLMP
  component: a stochastic/per-scenario price component must be its own named, citable quantity,
  never folded unlabeled into the existing decomposition.

**Warning signs:**
- Code that reads `dual(balance_s)` directly into a `dlmp`-shaped output with no probability
  rescaling or explicit documentation of the scaling convention chosen.

**Phase to address:** Stochastic PV/demand uncertainty phase.

---

#### Pitfall 11: Scenario-count explosion collides with Clarabel's IPM memory ceiling, and SCS gets reached for silently

**What goes wrong:**
A naive scenario-tree extensive form multiplies the per-hour SOCP cone set by the scenario count
inside a SINGLE monolithic build. Clarabel (the default, and the ONLY solver trusted for final
DADP/exactness per this project's own stack doc) is an interior-point method whose whole
"first-order fallback" (SCS) exists precisely for when a monolithic SOCP outgrows IPM memory. A
natural but explicitly-forbidden move under time pressure is switching the stochastic rung to SCS
"to make it fit," without registering that SCS's lower-accuracy duals are called out by name in
this project's own stack research as unacceptable for "final DADP/exactness certification."

**Why it happens:**
SCS is already in the `Project.toml`/stack as a fallback; reaching for it when Clarabel chokes on
scenario count is the path of least resistance, and the accuracy caveat is easy to forget once the
model "solves."

**How to avoid:**
- Establish an explicit scenario-count ceiling (measured empirically on IEEE-13/123) below which
  Clarabel stays authoritative for the shipped finding.
- If SCS is used at all above that ceiling, confine it explicitly to scale/feasibility scouting —
  never to the published stochastic-DADP finding, matching the stack doc's own rule verbatim.
- Prefer scenario-tree reduction (fewer, well-chosen scenarios) or a Benders/L-shaped decomposition
  of the stochastic recourse over brute-force monolithic scaling, if the ceiling is hit early.

**Warning signs:**
- A stochastic experiment that silently swaps `select_optimizer` to SCS once scenario count grows,
  with no accompanying accuracy caveat in the reported result.

**Phase to address:** Stochastic PV/demand uncertainty phase.

---

#### Pitfall 12: Pinning a stochastic golden on a single lucky scenario draw

**What goes wrong:**
The project's hard invariant is seeded, bit-for-bit reproducible generation. A seeded Markov
scenario-tree generator IS reproducible in principle — but if the golden regression is pinned on
whichever specific (seed, scenario-count) combination happened to converge cleanly during
development, that is exactly the "measurement-before-golden" trap Phase 18 was built to close (the
±2–5% population sweep that exposed the SOCP knife-edge BEFORE pinning REPRO's golden).

**Why it happens:**
The first seed/scenario-count that "just works" is tempting to pin immediately; a sweep across
seeds/scenario-counts to check the finding is stable takes extra effort that's easy to skip once a
single run looks clean.

**How to avoid:**
- Sweep the stochastic golden candidate across multiple seeds and scenario counts BEFORE pinning,
  exactly matching the Phase 18 measurement-before-golden pattern.
- Pin the golden on a SIGN-SAFE or otherwise robust quantity (mirroring the "never ratios of
  possibly-negative aggregates" rule already established for REPRO-01/02), not a fragile point
  value that could flip sign or diverge across nearby seeds.

**Warning signs:**
- A stochastic regression test with a single hard-coded seed and no accompanying sweep test/
  discussion of stability across seeds.

**Phase to address:** Stochastic PV/demand uncertainty phase.

---

#### Pitfall 13: `Scenario`/`savename` collisions from new stochastic fields, and `objective_hook` wired into only one of three consumers

**What goes wrong:**
Two integration failures: (a) adding scenario-tree fields (scenario count, branching, seed) to the
`Scenario` struct changes its default `savename`; per the CR-01 fix already documented in
`Scenario.jl` ("differing only in a Float64 field produce distinct default savenames... do NOT
rely on the bare savename(s,...) string as a uniqueness guarantee"), a new float-valued stochastic
field must go through the SAME `digits`-aware convention (`scenario_filename`'s `digits = 10`) or
it reintroduces the exact collision class that fix closed. (b) `operational_oracle`'s
`objective_hook` is currently consumed ONLY by the centralized `solve_welfare` path; wiring a real
multi-scenario hook into JUST the centralized solve while leaving `solve_admm`'s AGR-OPT/DSO-OPT
split and the planning oracle's Benders wrapper silently still single-scenario is the "no silent
partial behavior" failure (T-04-13) the SEAM-01 docstring explicitly warns against.

**Why it happens:**
The `Scenario` struct and `objective_hook` are both single, shared seams touched by multiple
consumers; it is easy to update the one consumer being actively worked on and assume the others
"just inherit" the change.

**How to avoid:**
- Route any new stochastic `Scenario` field through `scenario_filename`'s existing `digits=10`
  convention; add a regression test asserting two scenarios differing only in the new field
  produce distinct savenames.
- Explicitly enumerate all THREE consumers of the welfare/objective machinery (centralized
  `solve_welfare`, ADMM `AGR-OPT`/`DSO-OPT`, planning `operational_oracle`/Benders) and either wire
  the hook into all three or fail loudly (ArgumentError, matching the existing `role`/`z`-pin
  guard style) on any caller that assumes it's live in an unwired consumer.

**Warning signs:**
- A new `Scenario` field with no `savename`-collision regression test.
- `objective_hook` wired into `solve_welfare` but `solve_admm`/planning tests never exercising a
  non-identity hook.

**Phase to address:** Stochastic PV/demand uncertainty phase.

---

### Axis 4: Meshed networks + 4Q-BESS

#### Pitfall 14: Reusing Baran-Wu variables in a mesh without an angle-consistency (loop) constraint

**What goes wrong:**
The `pf::AbstractPowerFlow` slot IS the documented seam for a future `MeshedFlow` (per
`oracle.jl`'s own docstring: "a future `MeshedFlow <: AbstractPowerFlow` plugs in here... no
meshed formulation exists"). A meshed feeder has LOOPS, and the Baran-Wu/branch-flow variables
`(v, l, P, Q)` alone are insufficient around a loop — an angle-consistency constraint (or an
equivalent loop-flow constraint) is required, or the relaxation is under-constrained: it can return
`OPTIMAL` and pass `assert_socp_exact!` PER BRANCH while corresponding to NO physically realizable
AC solution, because the branch-flow cone check has no way to see a global loop-consistency
violation. This is a more dangerous silent failure mode than the overvoltage gap, because the
EXISTING gate would not catch it at all.

**Why it happens:**
The branch-flow variable set is radial-topology-complete by construction (a tree has no loops to be
inconsistent around); reusing the same variables/constraints for a mesh without adding the missing
loop constraint is the natural (and wrong) first attempt.

**How to avoid:**
- Add an explicit angle-consistency (or loop-flow) constraint for every fundamental cycle in the
  meshed topology before claiming the formulation is complete.
- Cross-validate any meshed solve against the independent AC oracle (`ACPowerFlow`) specifically
  checking that recovered angles are loop-consistent, not just that each branch's cone is tight.
- Do NOT reuse `assert_radial`'s construction-time guard as evidence of correctness for a mesh —
  it is the OPPOSITE invariant (it asserts the feeder has no loops).

**Warning signs:**
- A `MeshedFlow` implementation that reuses the exact same `(v, l, P, Q)` variable/constraint set
  as `ConvexBranchFlow` with no additional loop constraint.
- `assert_socp_exact!` passing on a meshed case with no independent angle-consistency check.

**Phase to address:** Meshed networks + 4Q-BESS phase.

---

#### Pitfall 15: Treating the meshed SOC-relaxation gap as a tunable knife-edge instead of a structural gap

**What goes wrong:**
The LinDistFlow exactness-copy trick that makes the RADIAL SOCP relaxation exact (thesis 3.43–3.45)
is a tree-topology-specific mechanism (EXACT-04 already showed even the radial case can go inexact
under reverse flow, but when it IS exact, radial topology is why). On a mesh, there is no
equivalent proof; the gap is expected to be structural, not a tunable artifact. The tempting-but-
wrong move: treat a meshed exactness gap exactly like EXACT-04 was treated — sweep parameters,
characterize a "knife-edge," and look for a fix — when the honest framing is "SOC relaxation is not
expected to be exact here at all," and the deliverable should be a genuinely different validity
story (SDP tightening, an accepted/reported gap, or restricting meshed test cases to configurations
where the gap is provably small).

**Why it happens:**
The project's own successful pattern from v2.1 (characterize a knife-edge via a sweep, ship the
honest finding) is a strong, recently-reinforced habit; applying it reflexively to a DIFFERENT
mathematical situation (structural non-exactness vs. a knife-edge) risks spending the whole rung
chasing a fix that cannot exist.

**How to avoid:**
- Before any sweep/tuning effort, establish (from the literature or a first-principles argument)
  whether the meshed case is EXPECTED to have a structural gap; if so, the "minimal validated rung"
  deliverable is an honest structural-gap finding (with a clear validity boundary), not a
  fixed/exact relaxation.
- If a tighter (e.g., SDP) relaxation is attempted instead, it needs its OWN exactness
  argument/certificate — see Pitfall 1's pattern, applied to the meshed case.

**Warning signs:**
- A meshed-rung plan whose acceptance criterion is "the relaxation is exact" with no prior
  literature check on whether meshed SOC relaxations are exact in general (they are not, in
  general).

**Phase to address:** Meshed networks + 4Q-BESS phase.

---

#### Pitfall 16: 4Q-BESS's P-Q coupling invalidates the existing no-binaries complementarity trick

**What goes wrong:**
`PVBattery.jl`'s entire justification for omitting a `p_ch·p_dch == 0` constraint is a ONE
-DIMENSIONAL, active-power-only strict-cost-ordering argument: `λ_min < λ_med < λ_max` makes
simultaneous charge/discharge strictly dominated in the ACTIVE-power objective alone (the docstring
is explicit: "Only the STRICT ordering makes simultaneous charge/discharge STRICTLY dominated").
Adding a genuine reactive decision variable (an apparent-power cap `P² + Q² ≤ S_max²`, or separate
`Q_ch`/`Q_dch`) breaks the scalar-tradeoff premise: with a coupled P-Q feasible region, there can
exist reactive-power-driven co-optima where simultaneous P-charge/discharge is NOT strictly
dominated even though the ACTIVE-only inequality still holds. Inheriting the 2D device's proof
unchanged for the 4Q device is a silent correctness gap — a co-optimum the post-solve check was
built to catch could reappear with a different economic mechanism than the one the proof rules out.

**Why it happens:**
The 4Q-BESS device is naturally implemented as an EXTENSION of `PVBattery` (same SOC dynamics, same
utility shape, plus a reactive dimension); it is easy to inherit the "no complementarity constraint
needed" conclusion along with the code, without re-checking that the PREMISE (one-dimensional
marginal tradeoff) still holds.

**How to avoid:**
- Re-derive the no-binaries argument explicitly for the P-Q coupled feasible region before
  shipping the 4Q device without a complementarity constraint.
- At minimum, reinstate the existing post-solve `p_ch·p_dch < τ` check (already implemented in
  `Aggregator.jl`) as a HARD, always-run gate for the 4Q device specifically — do not assume the
  2D device's construction-time strict-ordering REJECT check (which validates `λ_min<λ_med<λ_max`)
  suffices for the new device without its own analogous construction-time check.
- If the re-derivation shows the strict-dominance argument does NOT hold with reactive power,
  either add an explicit complementarity constraint (accepting the "no binaries" guard does not
  cover this specific device) or find and prove a different sufficient condition.

**Warning signs:**
- A 4Q-BESS device that subclasses/copies `PVBattery`'s docstring claim verbatim with no new
  derivation for the P-Q coupled case.
- The post-solve battery-complementarity check (`Aggregator.jl`) never invoked for the new device
  type in tests.

**Phase to address:** Meshed networks + 4Q-BESS phase.

---

#### Pitfall 17: Live reactive dual-ascent convergence is not covered by the existing (single-block) Boyd residual theory

**What goes wrong:**
Today, `reactive_consensus=true` PINS `qag_dso` to a fixed constant target and reads ONE certified
dual off `:balance_q` — explicitly documented as "a ONE-SHOT certified dual read, NOT a live μ
dual-ascent loop" (`solve_admm.jl`, `DsoOpt.jl`). `solve_admm`'s stopping rule (Boyd primal + dual
2-norm residuals, adaptive ρ via `τ`/`μ`-ratio bounds) is derived and implemented for a SINGLE
coupling variable `λ_j` (active power). Making the reactive coupling genuinely LIVE (a second
dual-ascent variable `μ_j`) means two coupled price updates per iteration; naively copying the
existing residual/ρ logic for a second block risks either non-convergence or a FALSE-CONVERGENCE
read — one residual pair (active) satisfies its threshold while the other (reactive) is still
moving, and an independent per-block stopping check would report "converged" anyway.

**Why it happens:**
The existing ADMM loop's single-block structure is well-tested and easy to extend mechanically
(add a second `λ`-shaped variable with the same ρ/τ/μ constants) without re-deriving the JOINT
stopping criterion that a genuinely two-block ADMM requires.

**How to avoid:**
- Re-derive the stopping rule as a JOINT residual norm across BOTH `λ` (active) and the new `μ`
  (reactive) — e.g., a stacked primal/dual residual vector — not two independently-checked scalar
  pairs that can trip "converged" while one channel still moves.
- Re-validate the adaptive-ρ residual-balancing logic (`τ`, `μ`-ratio) explicitly for the
  two-block case; the single-block tuning that works on IEEE-13/123 is not guaranteed to transfer.
- Add a liveness regression (per the project's own v2.0 CR-01 lesson: "tests passing ≠ mechanism
  live") proving two runs differing ONLY in the reactive coupling target converge to genuinely
  different λ/μ trajectories — not just that the loop terminates.

**Warning signs:**
- A live reactive dual-ascent implementation whose convergence check is two independent
  `≤ε`-comparisons on `λ`-residuals and `μ`-residuals with no joint/stacked norm.
- No liveness regression analogous to NASH-04's multi-seed probe for the new reactive dimension.

**Phase to address:** Meshed networks + 4Q-BESS phase.

---

#### Pitfall 18: `assert_radial` loosened globally instead of a parallel meshed feeder type; reactive-consensus default path broken; device-check registry gap

**What goes wrong:**
Three integration failures bundled: (a) `assert_radial` is a construction-time invariant that
protects EVERY existing radial rung; a meshed feeder needs a NEW, explicitly-meshed feeder
type/flag — loosening or removing `assert_radial` globally so a meshed feeder can be constructed
would silently stop protecting the radial rungs too. (b) Live reactive dual-ascent must be layered
as ITS OWN opt-in (on top of, not replacing, `reactive_consensus=true`'s existing pinned behavior)
so every pre-v3.0 regression golden (which never touches `qag_dso`) stays byte-identical. (c) A new
4Q-BESS device type must be registered wherever the post-solve `p_ch·p_dch<τ` check enumerates
device types to inspect — otherwise the check silently only ever loops over old 2D `PVBattery`
instances and never runs on the new device (a silent coverage gap, not a caught failure) — the same
class of risk the PVAL-04 registry+tripwire was purpose-built to catch for planning builders, but
with no analogous registry yet on the device side.

**Why it happens:**
Each of these three seams (radial guard, reactive-consensus default, device-check enumeration) is a
single shared invariant with multiple implicit consumers; extending it for the meshed/4Q rung is
easy to do in a way that "works for the new case" while quietly breaking or bypassing protection
for the old ones.

**How to avoid:**
- Add a NEW meshed feeder constructor/type that `assert_radial` explicitly does NOT apply to,
  leaving `assert_radial` fully intact and still enforced on the default/radial feeder path.
- Gate live reactive dual-ascent behind its own kwarg (e.g., `reactive_dual_ascent::Bool=false`)
  layered on top of `reactive_consensus=true`, never replacing the existing pinned mechanism.
- Build an explicit device-type registry (mirroring PVAL-04's registry+tripwire pattern) that the
  post-solve battery-complementarity check must cover, with a test asserting a new device type
  cannot silently ship uncovered.

**Warning signs:**
- `assert_radial`'s call sites reduced or a bypass flag added to the EXISTING `Feeder` constructor
  (rather than a new type).
- Any pre-v3.0 regression golden's numeric value changes when `reactive_consensus=true` (already
  shipped) is exercised after the live-dual-ascent change lands.
- No test that deliberately builds an aggregator with the new 4Q device and asserts the
  complementarity check actually runs against it.

**Phase to address:** Meshed networks + 4Q-BESS phase.

---

### Axis 5: Integer investment expansion

#### Pitfall 19: Standard Benders cuts (as implemented) are invalid once the recourse subproblem's response to `z` is non-convex/discontinuous

**What goes wrong:**
`benders.jl`'s `add_optimality_cut!`/`add_feasibility_cut!` construct a linear supporting
hyperplane from a continuous dual gradient (`cost_k`, `grad_k` — `oracle_res.π`/
`follower_res.π_s`), which is valid ONLY because the follower/oracle subproblem is currently
convex (LP/QP/SOCP) in the coupling variable `z`. Binary-expansion investment can make the
follower's or oracle's OWN response to `z` discontinuous at an investment threshold (a step change
in feasible operating range) — at that point the existing gradient-based cut construction can
silently produce an INVALID (non-supporting) cut that cuts off the true optimum, with no visible
error (the master still solves to `OPTIMAL`, just to the WRONG bound).

**Why it happens:**
The existing Benders machinery (Phase 10–13, empirically certified against BilevelJuMP on the
CONTINUOUS case) is directly reusable code — same `add_optimality_cut!` signature, same sign
convention — making it tempting to just start feeding it binary-expansion-derived duals without
checking that the underlying convexity assumption the cut construction relies on still holds.

**How to avoid:**
- Before reusing `add_optimality_cut!`/`add_feasibility_cut!` verbatim, verify the subproblem
  remains convex/differentiable in `z` at the specific binary-expansion granularity chosen — if
  not, switch to integer L-shaped cuts (a weaker but VALID cut form specifically designed for
  MILP-recourse subproblems), not the existing LP-dual-gradient cut.
- Add a small-instance validation (BilevelJuMP or hand/brute-force enumeration, see Pitfall 21)
  checking the integer Benders loop's converged answer against an independent ground truth BEFORE
  trusting the production loop on larger instances — mirroring the Phase 11 certify-before-build
  sequencing that worked well for the continuous case.

**Warning signs:**
- An integer-investment Benders run that "converges" (UB/LB gap closes) but disagrees with a
  brute-force enumeration on a tiny instance.
- Cut construction code reused unchanged from `benders.jl` with no new check on subproblem
  convexity/continuity in `z`.

**Phase to address:** Integer investment expansion phase.

---

#### Pitfall 20: Integer L-shaped cuts are structurally weaker — reusing the continuous loop's `max_iter`/retry defaults understates the real cost

**What goes wrong:**
Integer L-shaped cuts are a well-known WEAKER cut form than continuous Benders optimality cuts
(they can require many more iterations, sometimes a number growing with problem size, to close the
gap) — this is a structural property, not a tuning shortfall. The existing continuous Benders loop
was load-tested at 66 iterations (Phase 12) with `max_iter=100` and a specific checkpoint/retry
cadence; silently reusing those defaults for the integer variant risks either premature "iteration
cap exhausted" failures (the loop's own fail-loud design, correctly triggering, but on an
under-provisioned cap) or an ACTUAL problem with unbounded cut-store growth (already an accepted,
"instrumented, unbounded accumulation retained" debt at continuous-Benders iteration counts) that
becomes materially worse at 10–100x more iterations.

**Why it happens:**
`max_iter=100`, the checkpoint cadence, and the retry ladder are all already-tuned, working
constants; reusing them for a "similar-looking" loop is the natural default, and the weaker-cut
property is a theoretical fact easy to under-weight against a working continuous baseline.

**How to avoid:**
- Re-characterize expected iteration count for integer L-shaped cuts on the project's own toy/
  IEEE-13-scale planning instances BEFORE picking a `max_iter` default — do not inherit 100
  unchanged.
- Re-examine whether the existing cut-store growth debt (accepted for continuous Benders) is still
  acceptable at the higher iteration counts integer L-shaped cuts are expected to need; if not,
  address cut-store pruning as part of this phase rather than carrying the debt forward unexamined.

**Warning signs:**
- The integer Benders phase ships with the SAME `max_iter=100`/checkpoint cadence as the
  continuous case with no measurement of how many iterations the integer loop actually needs.

**Phase to address:** Integer investment expansion phase.

---

#### Pitfall 21: HiGHS lazy-constraint/callback cuts mixed with the existing external outer-loop design

**What goes wrong:**
The planning master is already HiGHS-solved and the existing pattern (`add_optimality_cut!`/
`add_feasibility_cut!` appending `@constraint` rows to a persistent JuMP model, then re-solving to
optimality each Benders iteration) is a straightforward, PROVEN external-loop design that also
works for integer L-shaped cuts (they're linear rows too). A tempting alternative — HiGHS's native
lazy-constraint/callback mechanism, injecting cuts DURING a single branch-and-bound tree to avoid
re-solving the whole MILP from scratch each iteration — is a genuinely different JuMP/MOI
integration path. Mixing the two designs (partial callback-based injection, partial external-loop
cut accumulation) without committing to one is a likely integration trap, and HiGHS's/JuMP's lazy-
constraint callback support and semantics should be verified explicitly rather than assumed
available, before committing engineering effort to that path.

**Why it happens:**
CLAUDE.md itself flags this as a possible LATER upgrade ("optionally lazy-constraint callbacks via
HiGHS/Gurobi for branch-and-Benders-cut later"), which can be misread as "available now" under
schedule pressure, especially once integer variables make the external-loop's per-iteration
full-MILP re-solve look expensive.

**How to avoid:**
- For the v3.0 "minimal validated rung," keep the EXISTING external Benders/L-shaped outer loop
  (matches the proven, hand-rolled precedent and the project's stated no-heavyweight-framework
  policy) — explicitly defer callback-based lazy cuts to a later milestone, per CLAUDE.md's own
  "later" framing.
- If callback-based cuts are attempted anyway, verify HiGHS's JuMP lazy-constraint API surface via
  Context7/official docs FIRST (do not assume feature parity with Gurobi's callback API), and do
  not mix it with the external-loop cut-accumulation pattern in the same subproblem.

**Warning signs:**
- A plan that references HiGHS lazy constraints without a prior doc-verification step, or a
  codebase with BOTH an external cut-accumulation loop and a partial callback registration for the
  same master problem.

**Phase to address:** Integer investment expansion phase.

---

#### Pitfall 22: The PVAL-04 guard lift accidentally loosens the OPERATIONAL-layer no-binaries protection too

**What goes wrong:**
PVAL-04's actual mechanism (`test/test_planning_noninteger.jl`) is a REGISTRY of the four planning
builders (`build_planning_oracle`, `build_follower`, `build_master`, `build_shared_transmission`)
plus a source-scan tripwire that unions in "every EXPORTED `build_*` symbol not on the documented
`operational_builders` allowlist." A "scoped, not deleted" lift (per PROJECT.md's own stated
intent) means removing/modifying the CHECK for the SPECIFIC planning builder(s) that now legitimately
carry integer variables — but a plausible mistake is instead loosening the shared tripwire mechanism
itself (e.g., widening `operational_builders`, or replacing the per-builder `isempty(offenders)`
assertion with a single global on/off flag), which would silently stop checking OTHER builders —
including operational-layer builders (`build_agr_opt`, `build_dso_opt`, `build_ieee123`, etc.) —
for accidental binaries too.

**Why it happens:**
The registry+tripwire is a single shared test file covering ALL builders; the path of least
resistance when "the guard needs to allow binaries now" is to touch the shared mechanism rather
than carve out a scoped exception for exactly the one or two builders that need it.

**How to avoid:**
- The lift must ADD a new, still-active assertion for the newly-integer planning builder(s) — an
  INVERTED/positive check (e.g., "the expansion builder DOES introduce the expected integer
  variables, and ONLY the expected ones") — while the zero-binaries assertion for every OTHER
  builder (the remaining continuous planning builders AND every operational-layer builder in the
  allowlist) must keep passing completely unmodified in the same test run.
- Do not touch `operational_builders` or the shared `isempty(offenders)` loop structure as part of
  this lift; add a SEPARATE, explicitly-named registry entry/test for the now-integer builder(s).
- Re-run the FULL existing `test_planning_noninteger.jl` unmodified against the post-lift codebase
  and confirm every non-lifted builder still reports zero binaries — this is the acceptance test
  for "scoped, not deleted."

**Warning signs:**
- A diff to `test_planning_noninteger.jl` that removes/loosens the shared `for (name, build) in
  registry` loop or the `operational_builders` allowlist, rather than adding a new, separate
  registry/assertion for the lifted builder(s).
- Any operational-layer builder (`build_agr_opt`, `build_dso_opt`) newly able to introduce a binary
  variable without a NEW test failing.

**Phase to address:** Integer investment expansion phase.

---

#### Pitfall 23: BilevelJuMP's continuous-case validation-oracle role does not automatically extend to integer investments

**What goes wrong:**
The Phase 11 4-way agreement (StrongDualityMode, ProductMode, hand enumeration, production Benders)
that empirically certified the continuous leader/follower sign convention relies on
BilevelJuMP's KKT/SOS1/Fortuny-Amat single-level reductions, which in turn rely on the follower's
LP being convex/continuous with clean strong duality. An integer leader/follower reformulation may
have NO valid KKT reduction at all (KKT requires differentiability/convexity assumptions integer
variables break) — reusing the "certify via BilevelJuMP" pattern unchanged for the integer case is
not guaranteed to be meaningful, and the codebase has ALREADY documented a related capacity limit
("BigMMode+HiGHS MIQP incapacity pinned as an asserted negative regression").

**Why it happens:**
The Phase 11 validation pattern worked well and is a strong, recent precedent; assuming it
generalizes to "any" Stackelberg variant, including an integer one, is a natural but unverified
extrapolation.

**How to avoid:**
- Explicitly check which BilevelJuMP reduction modes (if any) are valid for a MIQP/mixed-integer
  follower BEFORE relying on it as the integer rung's validation oracle; the existing pinned
  BigMMode+HiGHS MIQP-incapacity regression is a strong hint this path is already partially closed.
- If BilevelJuMP cannot serve as the validation oracle for the integer case, use the ALREADY-
  precedented fallback from Phase 11 itself: hand/brute-force enumeration over the (small) discrete
  investment grid on a tiny instance, cross-checked against the production integer Benders loop.

**Warning signs:**
- An integer-expansion phase plan that assumes BilevelJuMP validation "just works" without first
  checking mode compatibility with integer variables, given the project's own pinned MIQP-
  incapacity regression.

**Phase to address:** Integer investment expansion phase.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|-----------------|------------------|
| Reusing `assert_socp_exact!`'s `rtol`/`atol` unmodified for the overvoltage-capable formulation | Zero new gate code | Silently certifies a formulation the tolerance was never derived for | Never — always re-derive or add a new gate |
| Copying `PVBattery`'s no-binaries docstring claim onto the 4Q-BESS device without re-derivation | Fast device-model reuse | A silent P-Q co-optimum the complementarity check can no longer catch | Never for the shipped rung; acceptable only as a throwaway spike explicitly labeled unverified |
| Rebuilding the operational JuMP model each rolling-horizon window instead of `Parameter`-threading `horizon_state` | Simpler per-window code | Reintroduces the rebuild-in-loop anti-pattern; breaks the project's stated build-once discipline | Acceptable only for a first correctness spike on a toy 2-bus fixture, never for the shipped MPC rung |
| Reusing the continuous Benders `max_iter=100`/checkpoint cadence for integer L-shaped cuts | No new tuning work | Premature iteration-cap failures or unbounded cut-store growth at higher iteration counts | Never for the shipped rung; acceptable only for an initial toy-instance smoke test |
| Widening the PVAL-04 `operational_builders` allowlist or touching the shared tripwire loop to "make room" for the lifted planning builder | Fast unblock | Silently stops checking operational-layer builders for binaries too | Never |
| Pinning a stochastic golden on the first seed/scenario-count that converges cleanly | Fast test-green | Fragile golden, may not represent a stable finding (Phase-18 style knife-edge risk) | Never — always sweep first |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|--------------|------------------|--------------------|
| `assert_socp_exact!` (PF-04 gate) | Loosening its tolerance to accommodate a new formulation instead of adding a new, separately-derived certificate | New certificate function per new formulation; cross-validate against `ACPowerFlow`, never against the same relaxed cone |
| `operational_oracle`'s SEAM-01 stubs (`objective_hook`, `horizon_state`, `role`/`z`) | Wiring a stub live in only ONE of its three consumers (centralized/ADMM/planning) | Enumerate all consumers explicitly; fail loudly (ArgumentError) on any unwired consumer, matching the existing `role`/`z`-pin guard style |
| `solve_admm`'s build-once/`Parameter` discipline | Rebuilding AGR-OPT/DSO-OPT (or a new MPC/stochastic model) inside a per-iteration or per-window loop | Build once outside the loop; mutate via `Parameter`/`set_objective_coefficient`/`set_rho!`; re-solve only |
| PVAL-04 registry + source-scan tripwire (`test_planning_noninteger.jl`) | Loosening the shared mechanism (allowlist, loop) to accommodate the integer builder | Add a new, separate positive-check registry entry for the lifted builder; leave the shared zero-binaries loop untouched for everyone else |
| `Scenario`/`savename` (`Scenario.jl`, `store.jl`) | Adding new stochastic/rolling-horizon fields without the `digits=10`-aware convention | Route new float-valued fields through `scenario_filename`'s existing convention; add a collision regression test |
| `assert_radial` (Feeder construction-time guard) | Loosening/removing it globally to allow a meshed feeder | Add a NEW meshed feeder type/constructor that `assert_radial` does not apply to; leave the radial guard fully intact |
| `reactive_consensus` pinned default (REACT-01/02) | Replacing the pinned one-shot mechanism with live dual-ascent under the SAME flag | Add a new, separate opt-in kwarg for live reactive dual-ascent, layered on top of the existing pinned mechanism |
| Aggregator post-solve `p_ch·p_dch<τ` check | New 4Q-BESS device type not registered in whatever enumerates device types for the check | Build an explicit device-type registry (PVAL-04-style) the check must cover; test that a new device type cannot silently ship uncovered |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|-------------|-----------------|
| Monolithic scenario-tree SOCP on Clarabel | Solve times/memory growing steeply with scenario count; eventual Clarabel OOM or excessive wall-clock | Establish an empirical scenario-count ceiling on IEEE-13/123 before scaling; consider Benders/L-shaped decomposition of the recourse instead of a bigger monolithic build | Somewhere past a few dozen scenarios on IEEE-123-scale cones, depending on machine memory — measure, don't assume |
| Rebuilding the operational model per rolling-horizon window | Wall-clock scaling linearly (or worse) with simulation length; JuMP model construction dominating profile | `Parameter`-thread `horizon_state`; build once, re-solve per window | Any simulation longer than a handful of windows makes the rebuild cost visible |
| Integer L-shaped cut-store growth at 10-100x the continuous iteration count | Master solve time growing per-iteration as the row count balloons | Re-examine the existing "unbounded accumulation retained" debt; add pruning/aggregation if iteration counts are materially higher than the continuous case | Once iteration counts exceed the continuous case's already-tested ~66-iteration scale by an order of magnitude |
| Live two-block ADMM (active + reactive dual ascent) with unretuned ρ/τ/μ | Slower or non-convergence relative to the single-block case at the same feeder scale | Re-tune/re-derive the joint stopping rule and ρ-adaptation explicitly for two blocks before scaling to IEEE-123 | Any feeder scale beyond the toy 2-bus fixture where the joint dynamics were first checked |

## "Looks Done But Isn't" Checklist

- [ ] **Overvoltage-capable relaxation:** Often missing a NEW, independently-derived exactness
      certificate — verify it is not just the existing `assert_socp_exact!` tolerance loosened, and
      that it cross-validates against `ACPowerFlow` on the EXACT-04 fixtures (IEEE-13 `pv_scale=1.2`,
      real IEEE-123 upper band).
- [ ] **MPC / rolling-horizon:** Often missing a terminal-SOC/temperature term and a re-run of the
      `p_ch·p_dch<τ` complementarity check AT THE ACTUAL ROLLING WINDOW LENGTH — verify a battery
      is not silently drained at every window edge and the no-binaries proof still holds at
      `T_window`.
- [ ] **Stochastic uncertainty:** Often missing an explicit derivation of what the "stochastic
      DADP" actually is (probability-scaled dual vs. re-scaled marginal value) — verify it is
      documented as its own citable component, never silently summed into the existing DLMP
      decomposition.
- [ ] **Meshed networks:** Often missing an angle-consistency/loop constraint — verify
      `assert_socp_exact!` (or its meshed analogue) is checked ALONGSIDE an explicit loop-
      consistency check, not per-branch alone.
- [ ] **4Q-BESS:** Often missing a re-derived (or reinstated) complementarity check for the P-Q
      coupled feasible region — verify the post-solve `p_ch·p_dch<τ` check actually runs against
      the new device type, not just the old 2D `PVBattery`.
- [ ] **Integer investment expansion:** Often missing a small-instance independent validation
      (BilevelJuMP-mode-compatible or brute-force enumeration) BEFORE trusting the production
      integer Benders loop at scale — verify the guard lift is scoped (PVAL-04 registry entry
      added, not the shared mechanism loosened) and every non-lifted builder still asserts zero
      binaries in the same test run.

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|----------------|------------------|
| Overvoltage rung ships with a loosened `assert_socp_exact!` tolerance masquerading as a new certificate | MEDIUM | Revert the tolerance change; add a genuinely new, separately-named certificate function; re-run `assert_ac_exact!` cross-validation on EXACT-04 fixtures before re-shipping |
| A regression golden silently changes on the default (flag-off) path after a new axis lands | LOW-MEDIUM | Bisect the change to the specific commit; add an explicit default-path regression test; restore byte-identical behavior before continuing the feature |
| Meshed formulation passes `assert_socp_exact!` per-branch but has no loop-consistency check | HIGH | Requires adding the missing angle/loop constraint to the formulation itself (not just a test) and re-validating against the AC oracle from scratch — treat any previously-reported meshed "exact" result as unverified until this lands |
| 4Q-BESS ships without a re-derived complementarity check and a later co-optimum is found | MEDIUM | Reinstate the post-solve `p_ch·p_dch<τ` hard check for the device; audit any published prices/results that used the device before the check existed |
| PVAL-04 guard lift accidentally loosens operational-builder protection | LOW | Revert to a scoped, per-builder registry entry for only the lifted planning builder; re-run the full unmodified `test_planning_noninteger.jl` to confirm every other builder still reports zero binaries |
| Stochastic golden pinned on a fragile single-seed draw later shown unstable | MEDIUM | Re-run the Phase-18-style sweep across seeds/scenario counts; re-pin on a sign-safe, sweep-validated quantity; document the walked-back finding honestly (matching the project's honest-finding-as-deliverable ethic) |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|--------------------|----------------|
| 1–4 (overvoltage certificate, multi-start AC pricing, penalty contamination, default-path/gate-ordering) | Overvoltage-capable relaxation phase | New certificate cross-validated against `ACPowerFlow` on EXACT-04 fixtures; default-path regression test green; throw-vs-report polarity explicitly decided and documented |
| 5–9 (terminal-SOC myopia, unfair benchmark, price-discontinuity misread, `horizon_state` build-once, overvoltage interaction) | MPC / rolling-horizon / RTP phase | Terminal-SOC test at `T_window`; explicit value-of-information framing in any cost-gap finding; repeat-solve noise floor established before any volatility claim; `Parameter`-threading verified (no rebuild-in-loop); explicit sequencing decision recorded vs. Overvoltage phase |
| 10–13 (per-scenario dual scaling, Clarabel/SCS ceiling, golden stability, `Scenario`/`objective_hook` wiring) | Stochastic PV/demand uncertainty phase | Stochastic-DADP derivation documented and cited; scenario-count ceiling measured and enforced; golden pinned only after a seed/scenario-count sweep; `savename` collision test added; all three `objective_hook` consumers enumerated |
| 14–18 (loop/angle constraint, structural-gap framing, 4Q complementarity, two-block dual ascent, guard-scoping) | Meshed networks + 4Q-BESS phase | Explicit loop-consistency check alongside cone check; meshed-gap framing checked against literature before any tuning attempt; complementarity check re-derived/reinstated for 4Q device with a registry test; joint (not independent) two-block stopping-rule liveness regression; `assert_radial`/`reactive_consensus` defaults verified untouched by regression |
| 19–23 (invalid standard cuts, weaker integer L-shaped convergence, HiGHS callback mixing, PVAL-04 scoped lift, BilevelJuMP mode compatibility) | Integer investment expansion phase | Small-instance independent validation (BilevelJuMP-mode-compatible or brute-force) before trusting production loop; `max_iter`/checkpoint cadence re-measured, not inherited; explicit lazy-constraint-vs-external-loop decision recorded; full unmodified `test_planning_noninteger.jl` green with a new, separate registry entry for the lifted builder(s) |

## Sources

- `/home/pedro/programming/TSO-DSO/src/models/exactness.jl` — `assert_socp_exact!` (PF-04 gate) implementation and documented tolerance derivation.
- `/home/pedro/programming/TSO-DSO/src/models/oracle.jl` — `operational_oracle` + SEAM-01 extension stubs (`objective_hook`, `horizon_state`, `role`/`z`-pin, meshed slot), read directly for the exact inert-stub behavior and documented extension points.
- `/home/pedro/programming/TSO-DSO/src/admm/solve_admm.jl`, `src/admm/DsoOpt.jl` — build-once/`Parameter`-re-solve ADMM design, Boyd two-residual stopping rule, and the pinned (not live) `reactive_consensus`/`qag_dso` mechanism.
- `/home/pedro/programming/TSO-DSO/src/devices/PVBattery.jl` — the documented active-power-only strict-cost-ordering argument for omitting a `p_ch·p_dch==0` complementarity constraint.
- `/home/pedro/programming/TSO-DSO/src/planning/benders.jl` — Benders cut construction (`add_optimality_cut!`/`add_feasibility_cut!`), sign-convention provenance, and the fail-loud follower/oracle solve-gating pattern.
- `/home/pedro/programming/TSO-DSO/test/test_planning_noninteger.jl` — PVAL-04 no-binaries registry + source-scan tripwire mechanism, read directly for the exact scoping to reason about a correct guard lift.
- `/home/pedro/programming/TSO-DSO/src/experiments/Scenario.jl`, `src/experiments/store.jl` — `savename`/`scenario_filename` collision-avoidance convention (`digits=10`, CR-01 fix).
- `/home/pedro/programming/TSO-DSO/.planning/PROJECT.md` — v3.0 milestone scope, the five target axes, and the explicitly-flagged overvoltage/meshed relaxation-machinery interdependency.
- `/home/pedro/programming/TSO-DSO/.planning/RETROSPECTIVE.md` — cross-milestone lessons this file directly builds on: gate-then-golden ordering, honest-finding-as-deliverable, "tests passing ≠ mechanism live" (CR-01), sign-safe economic goldens, measurement-before-golden (Phase 18).
- General decomposition/optimization theory (Benders with integer recourse requiring integer L-shaped cuts; meshed AC/SOC relaxations lacking the radial exactness proof; ADMM two-block joint stopping criteria) — MEDIUM confidence, standard results not re-verified against a specific paper this session; flagged for a targeted literature check at phase-start if the roadmap wants HIGH confidence before implementation.

---
*Pitfalls research for: v3.0 Research Extension Rungs (TSO-DSO Integration Optimization Framework)*
*Researched: 2026-07-26*

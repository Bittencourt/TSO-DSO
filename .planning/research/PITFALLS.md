# Pitfalls Research — v2.1 Validation & Reproduction

**Domain:** Hardening an existing convex-optimization research bench with four validation
capabilities layered onto the shipped v1.0 operational core (SOCP Convex Branch Flow + LinDistFlow
exactness, active-only ADMM, synthetic IEEE-13/123 fixtures) and the shipped v2.0 planning layer:
(a) an independent Ipopt AC-OPF exactness oracle, (b) reactive-power `μ` consensus in ADMM, (c) real
IEEE-123 impedances via OpenDSS parse + positive-sequence reduction, (d) directional thesis
reproduction on real data.
**Researched:** 2026-07-25
**Confidence:** HIGH on the project's own code contracts (read directly: `src/models/exactness.jl`,
`src/admm/solve_admm.jl`, `src/admm/AgrOpt.jl`, `src/admm/DsoOpt.jl`, `src/data/ieee123.jl`,
`src/solver/factory.jl`, `src/experiments/Scenario.jl`) and on the documented, accepted Clarabel
`NUMERICAL_ERROR` flake (`.planning/STATE.md`). MEDIUM-HIGH on SOCP exactness / reverse-flow theory
(established literature, consistent with v1.0's own PITFALLS.md). MEDIUM on the IEEE-123
length/units ambiguity and positive-sequence reduction fidelity (public OpenDSS community knowledge
+ the project's own `ieee123-real-impedances-source` memory note, not independently re-verified
against the live dataset this session).

> This milestone's defining hazard is different from v1.0/v2.0's: it is not "build a new convex
> model" but "build an INDEPENDENT SECOND WAY to check the first one, and don't let the checker
> itself become the thing that's wrong." Every pitfall below is oriented at that risk. The single
> most important interpretive stance for this milestone: **a validation check that FAILS is not
> automatically a bug** — for the AC-OPF oracle and the real-impedance fixture especially, a
> "failing" exactness/reproduction check may be the CORRECT, physically-honest answer (the SOCP
> relaxation genuinely going inexact under high-PV reverse flow is the textbook failure regime this
> project's own v1.0 PITFALLS.md already flagged as the interesting one). Treat every "it doesn't
> match" result as requiring a diagnosis, not a tolerance bump.

---

## Critical Pitfalls

### Pitfall 1: AC-OPF "inexactness" verdict is actually a comparison artifact, not a relaxation failure

**What goes wrong:**
`assert_socp_exact!` (PF-04) already certifies the SOC relaxation is tight in the *scale-free*
sense (`gap ≤ atol + rtol·max(|lhs|,|rhs|)`, per-branch, per-hour). The new AC-OPF oracle adds a
**second, independent** notion of exactness — "does the SOCP optimum match a genuine nonconvex
AC-OPF optimum" — solved on a structurally different JuMP model (Ipopt `NLP()`, polar or
rectangular voltage variables, no `l`/relaxed-cone variables at all). Four ways this comparison can
report "INEXACT" when the SOCP is actually fine:
1. **Ipopt converges to a different local optimum.** AC-OPF is nonconvex; Ipopt's interior-point
   method finds a KKT point, not necessarily the global optimum the SOCP's convex relaxation
   bounds. A locally-optimal-but-globally-suboptimal AC point can differ from the SOCP solution
   even when the SOCP is exact — the comparison is then measuring Ipopt's initialization
   sensitivity, not the relaxation.
2. **Mismatched problem data between the two models.** If the AC-OPF oracle is built from a
   separately-assembled feeder/aggregator/load snapshot (rather than literally reusing the SAME
   `feeder`, `aggregators`, and per-hour dispatch the SOCP solved), any drift in load, PV profile,
   `λ₀`, or `allow_export` setting makes the two models solve **different problems** that happen to
   look similar — a mismatch is then guaranteed and uninformative.
3. **Unit/per-unit base mismatch (v1.0 Pitfall 3, transplanted across a model-family boundary).**
   The SOCP model works in the project's per-unit convention (`v = V²`, `IEEE123_BASE = (1 MVA,
   4.16 kV)`, thesis 3.3x numbering). An independently-built Ipopt AC-OPF model is a natural place
   to accidentally reintroduce SI units, a different `S_base`, or `v = V` instead of `v = V²` — a
   clean factor-of-`V_base²` or `S_base` error that makes the comparison look like a gross
   exactness failure when it is a units bug in the ORACLE, not the model under test.
4. **Angle recovery / no-angle comparison on radial nets.** The SOCP branch-flow model (thesis
   3.31–3.45) never introduces a voltage angle `θ` — it is a magnitude-only convex relaxation. The
   AC-OPF oracle, to be a genuine independent check, needs real `(P,Q)`-consistent voltage phasors;
   on a radial network the angle is recoverable from the branch power flows and impedances
   (a well-defined but non-trivial reconstruction), and a sign error or omitted reactance term in
   that recovery silently corrupts the comparison even though both underlying solves are correct.

**Why it happens:**
- The AC-OPF oracle is new code with no existing invariant to lean on (unlike PF-04, which the SOCP
  path already has); it is tempting to build it quickly from "whatever data is at hand" rather than
  literally threading the SOCP's own solved `feeder`/`aggregators`/hour-`t` snapshot through.
- Ipopt local-optimum risk is easy to forget precisely because the SOCP side of the project is
  *always* globally optimal (convex) — there is no local-optimum instinct built up from the rest of
  the codebase.
- The angle-free SOCP formulation is a deliberate simplification (thesis choice); an AC-OPF oracle
  is the FIRST place in this codebase angles become load-bearing, so there is no existing
  convention or test to reuse.

**How to avoid:**
- Build the AC-OPF oracle to consume the **exact same** `Feeder`, `Aggregator` population, `λ₀`,
  and per-hour dispatch snapshot the SOCP solved — never a re-derived or re-sampled instance. Make
  this a type-level contract (the oracle function signature takes the already-solved SOCP `ctx`
  or its primal values as fixed data, not a fresh scenario).
- Multi-start Ipopt from several initializations (including a warm start AT the SOCP solution
  itself) and report the best; if different starts converge to different objectives, that is
  itself a finding to surface (nonconvexity bites), not silently averaged away.
- Adopt one shared per-unit convention module for both models; assert magnitude bands
  (`v ∈ [0.81, 1.21]` etc., mirroring v1.0 Pitfall 3) on the AC-OPF oracle's own solved values
  before ever comparing them to the SOCP's.
- Write down the angle-recovery formula explicitly (as a `docs/literate` page, thesis-equation-style)
  and validate it FIRST on a 2-bus, no-PV, no-congestion fixture where the AC and SOCP solutions are
  known analytically to agree — before trusting it on IEEE-13/123.
- Choose the comparison tolerance deliberately and document why: it is NOT the same quantity as
  PF-04's scale-free cone-slack `rtol` — decide whether "match" means objective value, voltage
  magnitude, or branch flow agreement, at what tolerance, and write it down once rather than tuning
  it per fixture until "it passes."

**Warning signs:**
- AC-OPF objective value that changes materially between Ipopt runs from different starting points
  on the SAME data — a local-optimum red flag, not an exactness verdict.
- A reported mismatch that disappears when you re-derive the AC-OPF model's per-unit conversions
  by hand — a units bug, not a relaxation failure.
- Angle-recovery values that don't satisfy the basic radial power-flow identity
  (`θ_child ≈ θ_parent − (approximately) X·P/V² + R·Q/V²` for small angle differences) even on an
  easy, uncongested fixture.

**Phase to address:** AC-exactness oracle phase — data-sharing contract (same feeder/aggregators/
dispatch snapshot) and angle-recovery validation on a trivial 2-bus fixture are GATING acceptance
criteria before the oracle is ever run against IEEE-13/123.

---

### Pitfall 2: A genuinely inexact SOCP relaxation under high-PV / reverse-flow is mistaken for an oracle bug (and "fixed" by loosening tolerance)

**What goes wrong:**
v1.0's own PITFALLS.md (Pitfall 1) already names the failure regime precisely: SOCP branch-flow
exactness is a THEOREM under specific conditions (no reverse flow, upper voltage bound non-binding)
that Gan–Low/Farivar–Low establish, and it can genuinely FAIL under high DER penetration,
**reverse power flow**, and **binding upper voltage limits** — exactly the over-voltage / high-PV
regime this project's own IEEE-123 Case B targets. Once the AC-OPF oracle exists, there are now TWO
plausible readings of a disagreement between AC and SOCP on a high-PV hour:
1. **The SOCP relaxation is genuinely inexact at that hour** (the correct, scientifically
   interesting finding — this is the exact regime the exactness theory predicts trouble in).
2. **The comparison itself is broken** (Pitfall 1).

Treating every disagreement as case (2) and iterating on the oracle/tolerances until the check
"passes" would silently discard the single most scientifically important finding this milestone
could produce: **a documented case where the SOCP is provably inexact**, which is valuable
information (it bounds when the project's operational-layer prices can be trusted), not a defect to
engineer away.

**Why it happens:**
- The natural framing of "AC-OPF certifies SOCP exactness" implicitly assumes the certification
  will pass; a milestone scoped around "certifying exactness" creates pressure to make the checks
  green rather than to honestly report where they are red.
- PF-04 (`assert_socp_exact!`) already passes on all of v1.0's shipped fixtures at their CURRENT
  (comparatively modest) PV penetration — there is no existing case in the test suite where the
  relaxation is known to fail, so a first AC-OPF disagreement has no local precedent to distinguish
  "genuinely inexact" from "comparison bug."
- Loosening a tolerance is a one-line fix that makes a CI/test go green; diagnosing whether an
  inexactness is real requires actually inspecting the reverse-flow/voltage-binding state at that
  hour, which is more work.

**How to avoid:**
- Before touching any tolerance, check the PHYSICAL diagnostic v1.0's own Pitfall 1 already names:
  is there reverse (net-injection) power flow at any bus at the disagreeing hour, and is the upper
  voltage bound (`v ≤ 1.1²` etc.) binding or near-binding? If yes to either, treat the disagreement
  as a candidate GENUINE inexactness, not an oracle bug, and investigate the AC/SOCP gap's
  magnitude and direction (does AC show a *tighter* — lower-loss/lower-voltage — feasible region
  than the relaxed SOC cone predicts, as theory predicts?).
- Build (or extend) the existing "known-hard fixture" the v1.0 PITFALLS.md called for (high-PV,
  over-voltage) as a DELIBERATE stress case in this milestone, and expect — document, don't
  suppress — a nonzero exactness gap there if physics predicts one.
- Report the AC-vs-SOCP comparison as a per-hour, per-branch table (mirroring PF-04's own
  `maxgap`/`maxratio` reporting), not a single pass/fail boolean — a milestone deliverable that
  says "exact on N of T hours, inexact at hours {h1,h2} under reverse flow, magnitude X" is
  strictly more valuable and more honest than a single green checkmark.
- If a genuine inexactness is found, this is a MILESTONE FINDING to write up (which downstream
  DLMPs are and are not trustworthy), not a bug ticket against the SOCP model or the oracle.

**Warning signs:**
- A "fix" that only changes a tolerance number, with no accompanying investigation of reverse-flow/
  voltage-binding state at the disagreeing hour.
- Every disagreement getting resolved by adjusting the AC-OPF oracle, never by concluding "the SOCP
  is inexact here."
- A milestone report that claims "100% certified exact" with no high-PV stress case ever exercised.

**Phase to address:** AC-exactness oracle phase — the high-PV/reverse-flow stress fixture and the
per-hour reporting format are gating deliverables; the phase's acceptance criteria must explicitly
allow (and require investigating, not suppressing) a genuine inexactness finding.

---

### Pitfall 3: The new reactive-consensus dual `μ_j[t]` collides — in name and in mental model — with the EXISTING adaptive-ρ band parameter `μ`

**What goes wrong:**
`solve_admm`'s keyword signature already has a live, load-bearing parameter named `μ::Real = 10.0`
(the Boyd §3.4.1 residual-BALANCING band: `ρ ← τ·ρ` if `r̂ > μ·ŝ`, `ρ ← ρ/τ` if `ŝ > μ·r̂`), and it
is threaded all the way through `Scenario`'s flat, golden-hashed schema (`μ::Float64 = 10.0`,
serialized into `savename`/provenance strings and pinned into experiment result filenames). The
project's OWN docstring (`AgrOpt.jl`) names the future reactive-consensus dual **the same Greek
letter** — "PLACEHOLDER for a FUTURE reactive-consensus (`μ` dual-ascent) extension." These are two
COMPLETELY DIFFERENT mathematical objects (a scalar per-run tuning knob vs. a per-node-per-hour
Lagrange multiplier vector), and implementing the second under the same name/field as the first is
a landmine:
- If `μ_j[t]` (the reactive dual, a `Dict{Int,Vector{Float64}}` analogous to `λ`) is introduced as a
  same-named field or kwarg alongside the existing scalar `μ` (the ρ-band), any code, doc, or
  `Scenario` reader that assumes "the `μ` field" means the ρ-band silently reads/writes the wrong
  quantity.
- `Scenario`'s `μ::Float64` is already part of the reproducibility-hash surface (`savename`) — if
  the reactive dual needs its own scenario-level knob (e.g. an initial value or a separate penalty),
  reusing the `μ` name or field risks EITHER silently overloading the existing golden-hash key
  (breaking bit-for-bit reproducibility of every EXISTING pinned experiment that references `μ`) OR
  requiring a rename that itself breaks every existing golden filename/hash.

**Why it happens:**
- Both concepts are conventionally "the second dual-ish symbol" in ADMM literature (Boyd's ρ-tuning
  band is often called `μ` in one textbook section; the reactive consensus multiplier is `μ_j` by
  direct analogy to `λ_j` in the project's own thesis-notation convention) — the SAME name is a
  reasonable, independently-arrived-at choice from two different contexts, which is exactly how
  naming collisions happen without anyone intending one.
- The `AgrOpt.jl` docstring already primed the "reactive dual = μ" association months before this
  milestone, making it the path of least resistance to reuse literally, without checking whether the
  name is already taken elsewhere in the same call stack.

**How to avoid:**
- Before writing any reactive-consensus code, `grep` the full existing usage of the bare identifier
  `μ` (kwargs, struct fields, `Scenario` schema, `savename`/`sweep.jl`/`store.jl` provenance keys) —
  already enumerated above — and pick a DISTINCT name for the reactive dual (e.g. `μ_j` as a
  variable name is fine in math/docstrings, but the CODE identifier should be unambiguous, e.g.
  `μq`/`mu_q`/`reactive_dual`, never a bare `μ` that could be confused with the existing kwarg).
- If the reactive-consensus milestone needs its OWN scenario-level tuning knob (a separate penalty
  weight, initial value, or convergence band for the Q-consensus), add it as a NEW, distinctly-named
  `Scenario` field — never overload the existing `μ::Float64` — and treat any resulting golden-hash
  filename change as an explicit, reviewed, DOCUMENTED reproducibility-breaking change (v1.0/v2.0
  goldens referencing the old schema must be preserved or explicitly re-pinned, not silently
  invalidated).
- Add a one-line assertion/test that the existing ρ-band `μ` kwarg and any new reactive quantity
  are never the same Julia binding/field — a cheap regression against exactly this collision.

**Warning signs:**
- A PR/diff that adds a `μ` field to `AgrOpt`/`DsoOpt`/`solve_admm` without first checking whether
  `μ` already means something in that same call stack.
- `Scenario` golden hashes/filenames changing for EXISTING (non-reactive) experiments as a
  side-effect of the reactive-consensus work — a sign the shared `μ` schema field was touched.
- Code review comments asking "wait, which `μ` is this?" — the collision made visible late.

**Phase to address:** Reactive-power consensus phase, as the FIRST design decision (before any
`AgrOpt`/`DsoOpt` code changes) — pick and document the distinct identifier, and audit/guard the
`Scenario` schema boundary, before the loop or the golden-hash keys are touched.

---

### Pitfall 4: Adding a second (Q) consensus dual degrades ADMM convergence and silently breaks the existing active-only regression baseline

**What goes wrong:**
`solve_admm` currently closes the network's reactive balance with a FIXED constant per load node
(`qag_j = −Pdc·tan(acos φ)`, no decision variable, no dual) and a free-sign `q_import` at the root —
by design, "reactive is not a consensus quantity" (verbatim comment in both `AgrOpt.jl` and
`DsoOpt.jl`). Making `Q` a genuine per-node decision with its own consensus dual `μ_j[t]` changes the
STRUCTURE of both subproblems (AGR-OPT gains a Q decision variable and its own coupling constraint;
DSO-OPT's `:Rq[j]` closure changes from "constant draw" to "free coupling variable `qag_dso_j[t]`"),
which is a strictly bigger and more coupled ADMM problem than the one every existing convergence
tuning (`ε_abs=1e-4, ε_rel=1e-3, τ=2.0, μ=10.0, ρ_min=1e-2, ρ_max=1e4`) was ever validated against.
Concretely:
1. **A single shared `ρ` now penalizes two physically different consensus residuals** (`R_{p,j}`
   in MW-ish units, `R_{q,j}` in MVAr-ish units) — if their natural scales differ (plausible, since
   real/reactive flows are rarely numerically identical even in per-unit), one consensus block can
   dominate the OTHER in the residual-balancing adaptive-ρ logic (the exact "apples vs oranges"
   trap `solve_admm`'s own header comment already diagnosed and fixed for the p-vs-λ scale mismatch
   — the same fix (ε-normalized balancing) needs to be RE-DERIVED for a joint (p,q) residual, not
   assumed to transfer automatically).
2. **The existing active-only IEEE-13/123 cross-validation (ADMM-04)** — the load-bearing "ADMM
   matches centralized" regression — is validated against the CURRENT constant-Q model. Wiring in a
   Q decision variable changes the centralized model too (if the "same" welfare problem is to stay
   comparable), so this regression must be re-derived and re-validated, not silently left pointing
   at stale expectations while the underlying model changed.
3. **Reactive DLMP is a genuinely new, previously-nonexistent price component.** Unlike the active
   DADP (already cross-validated against a hand-solved 2-bus case, per v1.0 Pitfall 7's own
   prevention), there is NO existing sign/magnitude convention for a reactive price in this
   codebase — it must be pinned from scratch with the same rigor (hand-computed toy case, economic
   direction checks) before being trusted as a "reactive DLMP," not assumed correct because it
   compiles and the loop converges.

**Why it happens:**
- The existing 2-block ADMM split (AGR-OPT/DSO-OPT) is well-tuned and well-understood for the
  ACTIVE-only consensus; "just add a parallel `μ` block" reads as a small, symmetric extension of
  code that already exists, inviting a copy-paste that doesn't re-derive the scale/balancing
  implications of doubling the coupling dimension.
- The constant-Q closure was a DELIBERATE simplification (device model A3: "DERs active-only");
  removing it is not a parameter tweak, it is lifting a standing modeling assumption that several
  other invariants (the exactness gate's `:balance_q` NEARLY_FEASIBLE tolerance noted in
  `solve_admm`'s own final-block comment, the App. C battery complementarity check) were written
  around.

**How to avoid:**
- Treat the joint (active+reactive) residual-balancing as a NEW derivation, not a transplant:
  either scale the two consensus blocks into comparable units before combining them into one `ρ`
  decision, or — more robustly — give reactive consensus its OWN penalty `ρ_q` (distinctly named,
  per Pitfall 3) with its own adaptive-balancing derivation, and explicitly test whether a single
  shared `ρ` is even adequate before assuming it is.
- **Gate this phase on the existing active-only regression continuing to pass UNCHANGED** when
  reactive consensus is DISABLED (a feature flag / dispatch path, not a hard rewrite) — the safest
  sequencing is additive: keep the constant-Q path as the default/tested baseline, and add the
  Q-consensus path as an opt-in variant validated on its own fixtures, so the shipped active-only
  golden never silently changes behavior underneath it.
- Pin the reactive DLMP's sign/magnitude on a hand-computed 2-bus toy case with a NON-ZERO,
  analytically-known reactive requirement (mirroring exactly how v1.0 Pitfall 7 pinned the active
  DADP) BEFORE trusting it on IEEE-13/123 — this is a new, from-scratch invariant, not an inherited
  one.
- Re-validate ADMM-04 (ADMM optimum == centralized optimum) against a centralized model that ALSO
  now has the Q decision variable — comparing a Q-consensus ADMM run against the OLD constant-Q
  centralized model is comparing two different underlying problems and will show a spurious
  "mismatch."

**Warning signs:**
- Iteration counts far above the existing ~10-100 baseline once Q consensus is enabled, or
  oscillation that wasn't present in the active-only path.
- The active-only (Q-consensus disabled) regression suite showing ANY numeric change after this
  phase's changes land — a sign the "additive" boundary was not actually respected.
- A reactive DLMP whose sign flips between runs, or that is never checked against a hand-solved
  case at all.

**Phase to address:** Reactive-power consensus phase — additive/flagged rollout, joint-residual
re-derivation, and a from-scratch 2-bus reactive-price pin are gating acceptance criteria; the
existing active-only regression must be proven byte-identical with Q-consensus disabled before any
Q-consensus fixture is exercised.

---

### Pitfall 5: Reactive consensus amplifies the KNOWN Clarabel `NUMERICAL_ERROR` flake — and this milestone is exactly the wrong place to assume v1.0's failure rate still holds

**What goes wrong:**
`.planning/STATE.md` documents an ACCEPTED, unresolved, intermittent, version-independent Clarabel
`NUMERICAL_ERROR` on the IEEE-13 ADMM solve, root-caused to per-unit-base-dependent cone-slack
sensitivity — correctly caught by `assert_solved!` (never silently trusted) but never fixed. Adding
Q as a genuine decision variable to DSO-OPT's SOCP changes the cone geometry that flake lives in:
1. **More decision variables sharing the same SOC cone** (`P,Q` both now potentially free/decided at
   every load node, not just `P`) plausibly moves the solved point CLOSER to the cone boundary more
   often — the same mechanism v2.0's own Pitfall 5 flagged for Benders trial points pushing the
   pinned SOCP toward reverse-flow/over-voltage/near-boundary regimes, here triggered by a genuinely
   richer feasible region rather than an external pin.
2. **A second consensus dual `μ_j[t]` (see Pitfall 3/4) multiplies the same combinatorial exposure
   v2.0's Pitfall 5 already named for the planning layer** — but for the OPERATIONAL ADMM loop
   instead: more iterations may be needed for a two-consensus-block loop to converge, and EACH
   iteration's DSO-OPT re-solve is now a genuinely harder-conditioned SOCP (Q free instead of
   constant) — so the flake's per-solve probability may rise AND the number of solves per
   experiment may rise, compounding in the same way v2.0 Pitfall 5 already analyzed for Benders×
   scenario×distributor loops.
3. **This is measurable, not assumable.** v2.0's own Phase-12 finding (`.planning/STATE.md`) showed
   0% escalation on a toy fixture that deliberately did NOT exercise the full SOCP oracle — i.e.
   even THAT milestone's own measurement explicitly does not cover this flake's real trigger
   (per-unit-base-dependent cone-slack sensitivity on the genuine IEEE-13/123 SOCP). Assuming the
   flake rate is unchanged (or even "probably fine because it was rare in v1.0") under a materially
   different, more-coupled SOCP subproblem repeats the exact mistake v2.0's Pitfall 5 called out.

**Why it happens:**
- The flake was accepted as low-priority in v1.0 because it was rare and non-blocking for a
  milestone that solved the SOCP subproblem far less densely; that risk calculus does not
  automatically transfer to a milestone that (a) changes the SOCP's own decision-variable
  structure and (b) may need more ADMM iterations for two-consensus convergence.
- Retry/robustness code (`solve_with_retry!`-style bounded ladders, already proven useful in the
  PLANNING layer per v2.0) has no equivalent yet wired into the OPERATIONAL `solve_admm` loop —
  it currently fails loud via `ErrorException` on `maxiter`, but does not retry an individual
  `NUMERICAL_ERROR` `solve_dso!`/`solve_agr!` call the way the planning oracle does.

**How to avoid:**
- Before enabling reactive consensus broadly, EMPIRICALLY re-measure the Clarabel
  `NUMERICAL_ERROR` rate on the IEEE-13/123 fixtures WITH Q-consensus enabled — do not reuse the
  v1.0 rate or the v2.0 Phase-12 toy-fixture measurement (both explicitly do not cover this trigger).
- Reuse the planning layer's already-proven pattern (`src/planning/retry.jl`, `solve_with_retry!`)
  as a template for a bounded, logged retry ladder around `solve_dso!`/`solve_agr!` inside
  `solve_admm` if the re-measured rate justifies it — this is the SAME lesson v2.0 Pitfall 5 already
  learned for the planning layer, now due for the operational layer too.
- Revisit the "candidate levers, not yet applied" STATE.md already names (Clarabel
  tolerance/`equilibrate`/`max_iter` settings, per-unit base) as part of THIS phase's own scope — the
  reactive-consensus phase is a natural forcing function to finally spend that deferred numerical-
  robustness pass, since it is the first work to genuinely change the cone's conditioning since the
  flake was first observed.
- Never silently catch a `NUMERICAL_ERROR`/`ALMOST_*` status and substitute a stale iterate without
  flagging it in the returned residual trace — the same discipline v2.0 Pitfall 5 already
  established for the planning oracle applies here.

**Warning signs:**
- IEEE-13/123 ADMM runs with Q-consensus enabled failing (via the existing fail-loud `maxiter`
  path) more often than the active-only baseline on the same fixtures.
- A retry/robustness mechanism added to the planning layer but never ported back to
  `solve_admm`, despite the operational loop now sharing the same conditioning risk.
- Empirical failure-rate measurement skipped entirely because "v1.0 said it was rare."

**Phase to address:** Reactive-power consensus phase — empirical re-measurement of the
`NUMERICAL_ERROR` rate under Q-consensus, and a decision on whether/how to port retry robustness
into `solve_admm`, are gating deliverables, not a follow-on hardening pass.

---

### Pitfall 6: The IEEE-123 OpenDSS length/units ambiguity silently rescales every real impedance

**What goes wrong:**
The IEEE-123 OpenDSS master file (`IEEE123Master.dss`) is FAMOUS in the power-systems community for
a length/units ambiguity the file's own comments warn about: line lengths are given in a unit
(historically feet, sometimes miles depending on the released variant/vintage) that must be matched
against the linecode's own `R1/X1` (or full 3×3 `Rmatrix`/`Xmatrix`) units-per-length convention
(Ω/mile vs Ω/1000ft vs Ω/km) in `IEEELineCodes.DSS`. Getting this ONE conversion wrong scales
**every branch impedance in the entire feeder by the same constant factor** (feet-vs-miles ⇒ ~5280×,
feet-vs-1000ft ⇒ 1000×) — a globally-consistent, internally-plausible-looking but wrong dataset:
voltage drops, losses, and the SOC exactness margin all shift together, so nothing looks obviously
broken (unlike a single-branch transcription error, which a topology tripwire like
`_ieee123_assert_incidence` would never catch, because incidence is unaffected by impedance scale).

**Why it happens:**
- This is a documented, well-known trap in the OpenDSS/PowerModelsDistribution community — not a
  project-specific mistake, but new to THIS project since v1.0/v2.0 never parsed real OpenDSS length
  data (the synthetic `ieee123.jl` fixture hand-assigned representative in-band pu values with no
  length/linecode ingestion at all).
- A uniform rescaling is qualitatively "safe-looking": voltages stay in a plausible band, the SOC
  cone may still even certify exact (rescaling every branch by the same factor does not obviously
  break the physics-level relative relationships a quick eyeball check would catch).

**How to avoid:**
- Follow the project's own memory note (`ieee123-real-impedances-source.md`) recommendation
  literally: use PowerModelsDistribution to PARSE the `.dss` files (the "PMD as data oracle"
  pattern CLAUDE.md already prescribes) rather than hand-parsing lengths/units — PMD has already
  solved this exact ambiguity for the canonical IEEE-123 release.
- After parsing, sanity-check the RESULT against a known, independently-published reference
  quantity for the IEEE-123 feeder (e.g. a published total feeder loss, head-branch current, or
  voltage-profile figure at nominal load) — a 1000× or 5280× units error will show up immediately
  as a grossly wrong loss/voltage-drop magnitude against any published reference, even though the
  internally-consistent rescaled dataset alone would not self-reveal the bug.
- Keep the existing per-unit magnitude tripwire (`assert_magnitudes`, INFRA-05) as a FIRST filter,
  but do not treat "passes the tripwire" as "units are correct" — the tripwire is a strictly-in-band
  sanity check, not a units-correctness certificate, and a uniform 1000× rescale of a
  strictly-in-band fixture can still land in-band on the wrong side of correct.
- Document the resolved length/units convention explicitly in the new fixture's provenance
  comment (mirroring `ieee123.jl`'s existing DATA PROVENANCE NOTE style) so the choice is traceable
  and re-checkable, not buried in a one-off parsing script.

**Warning signs:**
- Solved voltage drops / losses on the real-impedance fixture that are implausibly small or large
  relative to any independently-published IEEE-123 reference figure.
- The SOC exactness margin or ADMM iteration count on the real-impedance fixture changing by an
  exact, suspicious factor of ~1000 or ~5280 relative to the synthetic fixture's behavior.
- No independent published-reference cross-check ever performed — only internal self-consistency
  checks (magnitude tripwire, topology incidence) run against the new dataset.

**Phase to address:** Real IEEE-123 impedances phase — PMD-parse (not hand-parse) + an independent
published-reference magnitude cross-check are gating deliverables before the new impedances replace
the synthetic ones anywhere in the test suite.

---

### Pitfall 7: The positive-sequence reduction (mean-diag minus mean-offdiag) is applied uncritically to segments where the transposition assumption doesn't hold

**What goes wrong:**
The project's own bridging recipe (`ieee123-real-impedances-source.md`) — `R1 = mean(diag R) −
mean(offdiag R)`, `X1 = mean(diag X) − mean(offdiag X)` per linecode — is the STANDARD positive-
sequence reduction for a **transposed** (or symmetric/balanced) three-phase line, where the
diagonal self-impedances are equal and the off-diagonal mutual-couplings are equal across all three
phase pairs. Real IEEE-123 linecodes are NOT uniformly transposed: some segments are genuinely
untransposed or asymmetric (unequal phase spacing on the pole, single- and two-phase laterals with
smaller, non-square impedance matrices), and applying the mean-diag/mean-offdiag formula there
produces a positive-sequence value that is a plausible-looking NUMBER with no error thrown, but a
poor approximation of the segment's true positive-sequence behavior — an averaging error that is
invisible unless deliberately checked, because the resulting `R1/X1` still passes every existing
in-band magnitude tripwire.

**Why it happens:**
- The reduction formula is correct FOR THE CASE it was verified on (the project's own memory note
  reports it verified on "linecode.1"); generalizing it to all ~12 linecodes without re-checking the
  transposition/symmetry assumption per linecode is the natural but unjustified extrapolation.
- Single- and two-phase lateral segments (very common on IEEE-123, which is deliberately a
  partially-unbalanced feeder in its native form) don't even have a full 3×3 matrix to average in
  the same way — a naive application of the same formula to a smaller matrix silently changes what
  "mean(offdiag)" means without flagging it.
- The balanced-positive-sequence modeling choice (project-wide, per `CLAUDE.md`) is exactly what
  makes this reduction TEMPTING to apply blindly everywhere — the destination format (single
  `R1,X1` per branch) is uniform even when the source data's fidelity to that assumption is not.

**How to avoid:**
- Per-linecode (not once, globally), check the actual matrix symmetry/near-diagonal-equality before
  trusting the mean-diag/mean-offdiag reduction — report, for each linecode, how far the 3×3 R/X
  matrix is from a symmetric/transposed form (e.g. the spread across the three diagonal entries and
  across the three off-diagonal entries) as an explicit reduction-quality metric, not just the
  reduced `R1,X1` number.
- For single-/two-phase laterals, use the linecode's OWN native (smaller) matrix reduction rather
  than force-fitting the 3-phase formula — document the distinct handling explicitly (this is
  exactly the kind of "documented reduction/assumption" the project's own core value statement
  requires).
- Cross-check the reduced positive-sequence feeder's overall behavior (voltage profile shape,
  loss magnitude) against the SAME independently-published reference used for Pitfall 6's units
  check — a poor reduction, like a units error, tends to show up as a magnitude/shape discrepancy
  against ground truth even when it passes internal self-consistency checks.
- Treat the reduction quality metric as a FIRST-CLASS documented output of the ingestion pipeline
  (a per-linecode "reduction fidelity" table in the new fixture's provenance comment), not a
  one-off REPL sanity check discarded after use.

**Warning signs:**
- A per-linecode reduction that was verified on only one representative linecode ("linecode.1") and
  never checked on the others before shipping.
- Single-/two-phase laterals reduced via the SAME 3-phase averaging formula without adjustment.
- No documented reduction-quality/fidelity metric anywhere near the shipped fixture — only the
  final `R1,X1` numbers, with no record of how well the transposition assumption actually held.

**Phase to address:** Real IEEE-123 impedances phase — per-linecode reduction-fidelity reporting
(not just the reduced numbers) is a gating deliverable, verified against the SAME published
reference cross-check as Pitfall 6.

---

### Pitfall 8: Regulators, capacitors, and switches in the real dataset don't map onto the existing radial positive-sequence `Feeder`/branch model — and their omission can silently un-tighten the deliberately-tuned voltage-binding scenario

**What goes wrong:**
The EXISTING synthetic `ieee123.jl` fixture already documents (in its own header) that it was
CALIBRATED — its representative `IEEE123_LINE_R/X` and `IEEE123_SWITCH_R/X` values were deliberately
sized so the Case-B feeder is "genuinely voltage-constrained... under-voltage on the long load
laterals, over-voltage under midday PV reverse flow" (plan-07-05 finding), a load-bearing property
the whole voltage-constrained test case exists to exercise. The REAL IEEE-123 OpenDSS dataset
contains components this project's radial `Feeder`/`Branch` model has no representation for at all:
**voltage regulators** (which actively adjust voltage magnitude along their segment — not a passive
series impedance), **shunt capacitor banks** (reactive power injection at specific buses, not a
branch quantity), and **switches** (already handled as near-ideal impedance branches in the
synthetic fixture, but the real dataset's actual switch states/positions must be read correctly).
Two distinct silent failure modes:
1. **Naively treating a regulator as a passive impedance branch** (the same simplification already
   used for switches) discards its actual voltage-boosting behavior — this can materially change
   whether the long laterals still hit the under-voltage bound, potentially making the "genuinely
   voltage-constrained" property the synthetic fixture was deliberately tuned for SILENTLY STOP
   HOLDING on the real-data fixture, with no error — the model still solves, the SOC cone may still
   even certify exact, but the case has quietly become an unconstrained (uninteresting) one.
2. **Ignoring shunt capacitor banks entirely** (no injection modeled) shifts the reactive balance at
   those buses, changing voltage profiles in a way that, again, can move the case away from the
   voltage-binding regime the fixture is supposed to exercise — without any test failing, because
   nothing in the existing test suite asserts "the voltage bound is actually binding," only that the
   model solves and the SOC relaxation is exact.

**Why it happens:**
- The project's balanced-positive-sequence, radial-branch-flow modeling choice is explicit,
  deliberate, and correct for the framework's scope (per CLAUDE.md) — but it was designed against a
  HAND-CALIBRATED synthetic dataset with no regulators/capacitors in the first place; the real
  OpenDSS dataset is the first time these components need an explicit "how do we represent this, or
  do we omit it and document why" decision.
- Silently dropping unsupported components is the path of least resistance (the parser can simply
  skip element types it doesn't recognize) and produces a feeder that still radially validates
  (`assert_radial`) and still passes magnitude tripwires — nothing in the existing validation
  machinery is positioned to catch "a physically-meaningful component was dropped."

**How to avoid:**
- Before ingestion, enumerate every non-line element in the real IEEE-123 `.dss` files (regulators,
  capacitors, switches, any transformers) and make an EXPLICIT, documented decision per element
  type: model it (even approximately, e.g. a capacitor as a fixed reactive injection at its bus,
  matching the project's existing constant-reactive-draw convention), or omit it with a written
  rationale — never a silent drop.
- Add an explicit acceptance test that the real-data fixture's voltage bound is ACTUALLY BINDING
  under the intended stress scenario (e.g. assert some bus hits within a documented margin of
  `vmin`/`vmax` under the designed load/PV profile) — this directly catches the "case became
  accidentally slack" failure mode that no existing test currently checks for.
- If regulators are omitted (a defensible v2.1 scope choice given the project's explicit v1
  balanced-positive-sequence, no-regulator-model scope), state this explicitly in the new fixture's
  provenance note (mirroring the existing DATA PROVENANCE NOTE convention in `ieee123.jl`) and flag
  it as a documented limitation on how faithfully the real-data fixture represents the true IEEE-123
  feeder's voltage behavior — not a silent simplification discovered only by a careful reader of the
  parsing code.
- Cross-check the omission's practical impact by comparing the real-data fixture's voltage profile
  (with regulators/capacitors omitted) against a PMD-parsed AC power-flow solve on the FULL dataset
  (regulators/capacitors included) — if the two disagree materially, the omission is not innocuous
  and must be reconsidered or the fixture's stress scenario re-tuned.

**Warning signs:**
- The real-impedance fixture solves cleanly with NO binding voltage constraint anywhere, despite
  the synthetic fixture's documented voltage-binding design intent.
- No enumeration/documentation anywhere of which OpenDSS element types were modeled vs. silently
  skipped during ingestion.
- No cross-check against a full (regulator/capacitor-inclusive) reference solve.

**Phase to address:** Real IEEE-123 impedances phase — explicit per-component-type modeling
decisions (documented, not silent) and a binding-voltage-constraint acceptance test are gating
deliverables.

---

### Pitfall 9: Swapping synthetic → real IEEE-123 impedances silently changes every pinned IEEE-123-based golden, and re-baselining without re-verifying invariants masks a real regression as "just numbers changed"

**What goes wrong:**
The synthetic `ieee123.jl` fixture is not an isolated artifact — it feeds the shipped v1.0
ADMM-vs-centralized cross-validation, DLMP decomposition checks, and (per v2.0) any planning-layer
regression that happens to use IEEE-123-scale data, plus whatever bit-for-bit goldens this project's
"reproducibility is a hard requirement" stance has already pinned against it. Replacing
`IEEE123_LINE_R/X`/`IEEE123_SWITCH_R/X` (or the whole edge/impedance ingestion path) with real
values changes EVERY downstream number derived from that fixture — welfare, DADPs, exactness
margins, ADMM iteration counts. The dangerous failure mode is not that numbers change (they are
SUPPOSED to, real data differs from synthetic placeholders) but that the natural response —
"re-run and re-pin the goldens to the new numbers" — can paper over a genuine regression introduced
elsewhere in this same milestone (a units bug from Pitfall 6, a reduction error from Pitfall 7, an
omitted regulator from Pitfall 8) by simply accepting whatever new numbers come out as the new
truth, with no independent check that the NEW numbers are actually more correct than the OLD ones,
merely that they are DIFFERENT.

**Why it happens:**
- "Re-pin the golden to the new run's output" is the standard, usually-correct move for an
  intentional behavior change (this project's own DrWatson-based golden workflow is built around
  exactly this pattern) — but it is agnostic to WHY the numbers changed, and cannot by itself
  distinguish "real data is legitimately different" from "a units/reduction/omission bug in this
  milestone's own new ingestion code."
- The invariants that WOULD catch such a bug (SOC exactness gap, ADMM convergence, voltage-binding)
  are checked at goldenING time, not necessarily RE-verified as "still meaningfully exercising the
  same physical regime" — a case that used to be voltage-constrained can become slack (Pitfall 8)
  and still "pass" every existing gate (solves, SOC exact, ADMM converges) while testing something
  materially less interesting than before.

**How to avoid:**
- Before re-pinning any IEEE-123-based golden, explicitly re-verify the qualitative invariants the
  ORIGINAL golden was designed to exercise (voltage-binding for Case B, SOC-exactness margin in a
  comparable range, ADMM converging in a comparable iteration-count order of magnitude) — a
  re-pinned golden whose UNDERLYING PHYSICAL REGIME silently changed (e.g. from voltage-binding to
  slack) should be flagged and investigated, not casually accepted as "the new correct answer."
- Keep the OLD synthetic-fixture goldens in the test suite ALONGSIDE the new real-data ones (do not
  delete/replace) for at least this milestone — the synthetic fixture remains a valid, fast,
  hand-calibrated regression target for the ADMM/exactness MACHINERY itself, independent of whether
  its impedances are "real"; only the real-data fixture's OWN new goldens should be freshly pinned.
- Require, as part of code review for this phase, an explicit before/after comparison table (SOC
  exactness margin, ADMM iteration count, whether voltage bounds bind) alongside any golden re-pin —
  not just "tests pass with new numbers."
- Apply the same "looks done but isn't" discipline v2.0's own PITFALLS.md already established for
  cut-validity/BilevelJuMP certification: a re-pinned golden with no accompanying investigation of
  WHY the numbers moved is a red flag, not a completed task.

**Warning signs:**
- A commit that changes pinned IEEE-123 golden values with a message like "update goldens for real
  impedances" and no accompanying note on whether the qualitative regime (voltage-binding, exactness
  margin, iteration count) is still comparable.
- The synthetic-fixture goldens deleted/replaced rather than kept as an independent regression.
- No before/after invariant comparison in the PR/review for this phase.

**Phase to address:** Real IEEE-123 impedances phase — the before/after invariant comparison is a
gating review checklist item for any golden re-pin; keeping the synthetic-fixture goldens as a
parallel, undisturbed regression is a phase-scoping decision made explicit up front.

---

### Pitfall 10: Directional thesis reproduction overclaims exactness, or under-documents exactly which assumptions make the reported number what it is

**What goes wrong:**
v2.1's own scope is explicit and honest: exact reproduction of the thesis's `+$1,819/+25%` headline
is NOT a hard requirement (the source Appendix E is IP-blocked; public IEEE-123 data + a documented
reduction is used instead), and only DIRECTIONAL agreement (welfare-gain SIGN and rough magnitude)
is targeted. Two ways this honest scope can erode in execution:
1. **Overclaiming in the writeup.** A directional match (right sign, plausible order of magnitude)
   gets informally described — in a docstring, a thesis chapter draft, a commit message, or a
   figure caption — as "reproducing" or "validating" the thesis result, without the qualifier that
   the underlying feeder data, reduction, aggregator population, and PV penetration are NOT the
   thesis's own App. E values. A reader (including a future co-author or thesis committee member)
   encountering the unqualified claim has no way to know the exact-figure caveat exists unless they
   dig into this milestone's own scope notes.
2. **Under-documenting the assumption stack that produces the reported number.** The reported
   welfare gain is a function of (at minimum): the real-impedance reduction choice (Pitfall 7), the
   length/units resolution (Pitfall 6), which OpenDSS components were modeled vs. omitted
   (Pitfall 8), the aggregator population and device-parameter assignment overlaid on the real
   topology (a NEW ingestion step this milestone introduces, distinct from the thesis's own
   assumed population), and the PV penetration scenario chosen to produce a "gain." If these choices
   live only in code (not in a citable, versioned documentation page), the number is not
   REPRODUCIBLE in the scientific sense even though it is bit-for-bit pinned as a golden — a
   collaborator cannot tell what would need to change to get a materially different number.

**Why it happens:**
- "Directional reproduction" is a nuanced scope statement that is easy to compress, informally, back
  down to "reproduction" in day-to-day discussion, docstrings, and quick summaries — the qualifier
  is the first casualty of brevity.
- The assumption stack is genuinely large (spanning three OTHER pitfalls in this same document —
  6, 7, 8) and each individual choice was made in a different phase/file; nothing forces them to be
  assembled into one place that documents "here is the full chain of assumptions behind this number."

**How to avoid:**
- Every artifact (docstring, golden test name/comment, docs page, thesis-chapter draft prose) that
  reports the welfare-gain figure MUST carry the qualifier explicitly: "directional reproduction on
  public IEEE-123 data with a documented positive-sequence reduction; NOT the thesis App. E exact
  figures" — make this a fixed, copy-pasted phrase (or a single cross-referenced doc anchor) rather
  than something re-worded (and potentially softened) each time it's mentioned.
- Write ONE consolidated "reproduction assumptions" doc page (Documenter, matching the project's own
  literate-docs convention) that enumerates the full assumption chain behind the reported number:
  data source + length/units resolution, reduction method + fidelity metric, component-omission
  decisions, aggregator population source, PV penetration scenario — cross-referenced from wherever
  the number itself is reported, so a reader is always one click from the full provenance.
- Treat "is the sign/direction right, and is the assumption chain fully documented" as the actual
  MILESTONE-LEVEL acceptance criterion — not "does the number look close to +$1,819" (a criterion
  that, taken alone, invites exactly the overclaiming this pitfall describes).
- If/when the CONICET Appendix E becomes available later (a stretch goal explicitly out of THIS
  milestone's scope), treat exact-figure reproduction as its own SEPARATE, later deliverable with
  its own separate documentation — never quietly merge "directional" and "exact" claims into one
  reported number as more data becomes available piecemeal.

**Warning signs:**
- Any docstring, commit message, or docs page using the unqualified word "reproduces"/"validates"
  the thesis figure without the directional/public-data qualifier attached in the same sentence.
- The welfare-gain number reported with no cross-reference to a single page documenting its full
  assumption chain.
- A thesis-chapter draft or paper submission citing this milestone's number without the same
  qualifier the milestone's own README/PROJECT.md scope statement already uses.

**Phase to address:** Directional thesis reproduction phase — the consolidated assumptions doc page
and the fixed qualifier phrase are gating deliverables, checked at the SAME acceptance gate as the
welfare-gain sign/magnitude check itself, not as an afterthought once the number "looks right."

---

### Pitfall 11: Bit-for-bit goldens pin transient numerical noise from the very Clarabel flake this project already knows about

**What goes wrong:**
This project's reproducibility discipline (seeded, pinned `Manifest.toml`, bit-for-bit goldens) is a
hard requirement — but it assumes the underlying computation is DETERMINISTIC given the same seed
and environment. The known, accepted, intermittent Clarabel `NUMERICAL_ERROR` flake
(`.planning/STATE.md`) is EXACTLY the kind of non-determinism (a "fraction of pushes" failure mode,
root-caused to per-unit-base-dependent cone-slack sensitivity) that can also manifest as
SUB-THRESHOLD numerical jitter even when it doesn't cross the hard-failure line — i.e., a solve that
"succeeds" but lands at a slightly different point run-to-run near a conditioning edge case. Both new
data sources in this milestone (the real IEEE-123 impedances, which per Pitfalls 6-8 may shift the
feeder's conditioning in an unmeasured direction, and the reactive-consensus ADMM path, which per
Pitfall 5 is a documented candidate for INCREASED flake exposure) are plausible new places for this
jitter to surface. Pinning a bit-for-bit golden from a SINGLE run, before the new pipeline's
run-to-run stability has been explicitly checked, risks freezing an artifact of that one run
(a particular near-boundary numerical outcome) as "the" reproducible answer — a later re-run
(same seed, same Manifest, different machine/BLAS/solver-internal nondeterminism) could then FAIL
the golden not because anything is wrong, but because the golden itself was never actually stable.

**Why it happens:**
- "Reproducible" and "deterministic" are easy to conflate; the project's OWN reproducibility
  machinery (seeds, pinned Manifest) handles the INPUT side of determinism but cannot, by itself,
  guarantee a numerically-fragile SOLVE is deterministic across machines/BLAS versions/solver
  internal thread counts — exactly the axis STATE.md's own flake report already flags as
  "version-independent" (i.e., NOT fully explained by the pinned Manifest alone).
- Pinning a golden immediately after a pipeline first produces a plausible-looking number is the
  natural, fast path to a "done" checkbox; explicitly re-running the SAME pinned scenario multiple
  times before committing the golden is easy to skip under time pressure.

**How to avoid:**
- Before pinning any NEW golden introduced by this milestone (AC-OPF comparison numbers, reactive
  DLMP values, real-impedance-fixture welfare/exactness numbers, the directional reproduction
  headline figure), re-run the SAME scenario multiple times (same seed, same Manifest) and confirm
  bit-for-bit (or, where genuine solver nondeterminism is expected, tolerance-bound) stability BEFORE
  committing the golden — not after a single successful run.
- Where a new fixture's conditioning is plausibly closer to the known flake's trigger (per Pitfalls
  5 and 6-8), treat "does this fixture solve deterministically and away from the numerical edge" as
  its own explicit acceptance check, separate from "does the fixture produce the RIGHT answer."
- If a genuinely fragile near-boundary case is discovered while pinning a new golden, prefer FIXING
  the underlying conditioning (the STATE.md-documented "candidate levers, not yet applied") over
  simply re-running until a lucky, stable-looking result appears to pin — a golden pinned by luck on
  a fragile case is a ticking regression-suite time bomb.
- Document, alongside any new golden, whether it was verified stable across N repeated runs (and N),
  mirroring the rigor the project already applies to the planning layer's `BendersTrace`/retry
  instrumentation.

**Warning signs:**
- A new golden pinned from a single run, with no repeated-run stability check recorded anywhere.
- A previously-passing golden starting to fail intermittently on CI (not deterministically) after
  this milestone's changes land — the textbook symptom of having pinned an unstable numerical point.
- New fixtures (real IEEE-123, reactive-consensus) never explicitly checked against the STATE.md
  flake's known trigger conditions before their goldens are committed.

**Phase to address:** All four v2.1 workstreams, at golden-pinning time specifically — a repeated-
run stability check is a gating step before any NEW golden from this milestone is committed, called
out explicitly in each phase's acceptance criteria (not assumed as "the reproducibility
infrastructure already handles this").

---

### Pitfall 12: This milestone's own retrospective lessons (green tests ≠ live mechanism, docs-build silently red, undocumented constant-term offsets) get re-learned the hard way instead of applied proactively

**What goes wrong:**
This project has ALREADY paid for three specific lessons in its own history, each directly
transplantable to v2.1's four workstreams, and each easy to re-forget because the NEW code is new:
1. **"Green tests ≠ live mechanism."** v2.0's own `operational_oracle` `role` kwarg was
   "validated but currently inert" for an entire milestone boundary before becoming load-bearing —
   passing type/validation checks gave false confidence that it was doing something. The DIRECT
   v2.1 analogue: the reactive `qag` field in `AgrOpt` is ALREADY documented, verbatim, as a
   "PLACEHOLDER... currently NOT read by `solve_admm`" — exactly the same "exists, validates,
   does nothing yet" shape. A test suite that merely checks "the reactive consensus code runs and
   converges" without confirming the μ dual ACTUALLY changes the solved Q allocation relative to
   the constant-draw baseline (e.g., under a scenario where the optimal Q clearly differs from the
   constant heuristic) would be green while the mechanism is still inert — the same trap, recurring.
2. **"Docs build silently red."** v2.0's own Documenter build went red and stayed unnoticed across
   at least one phase boundary before Phase 14 fixed it. Four NEW literate/doc pages are plausible
   outputs of this milestone (AC-OPF exactness certification writeup, reactive-consensus math,
   real-IEEE-123 provenance, directional-reproduction assumptions per Pitfall 10) — each is a new
   opportunity for a `@example`-executed docs page to silently stop building (e.g., an AC-OPF
   NLP solve inside a doc example that becomes flaky per Pitfall 11, or a new module that isn't
   wired into `@autodocs`) without anyone noticing until a later phase's audit.
3. **"Algebraic doc claims need constant-term reconciliation."** v2.0's Phase 14 review caught a
   docs page whose algebraic welfare claim was off by a constant offset (the "Deferrable +18
   objective-offset reconciliation" fix, per PROJECT.md's own phase log) — a documentation page that
   states an equation/relationship without re-deriving or checking its constant/offset terms against
   the actual code. This milestone introduces at least two new places for exactly this class of bug:
   any doc page comparing the AC-OPF objective to the SOCP welfare objective (Pitfall 1's comparison,
   now narrated in prose) and any doc page describing the reactive-consensus augmented Lagrangian
   (mirroring the EXISTING, already-corrected sign-derivation care in `solve_admm.jl`'s own header,
   which must be re-derived, not copy-pasted, for the Q-block).

**Why it happens:**
- Each lesson was learned once, in a DIFFERENT phase/module than where it will recur (`operational_oracle`'s inertness in v2.0 vs. `AgrOpt`'s `qag` inertness in v2.1; the Documenter build in v2.0's planning docs vs. this milestone's four new doc pages; the Deferrable objective-offset in v2.0's planning welfare accounting vs. this milestone's AC-OPF/reactive objective narration) — nothing mechanically forces a "have we seen this shape before" check across milestone boundaries.
- Retrospective lessons live in prose (PROJECT.md's phase log, milestone audits) rather than as an
  automated gate; applying them requires someone to actually remember and re-read them at the start
  of a new phase, which is exactly the kind of discipline that erodes under normal project momentum.

**How to avoid:**
- At the start of EACH of the four v2.1 phases, explicitly check: is there an existing "documented
  placeholder, not yet load-bearing" field in the code this phase is about to make load-bearing
  (the `qag`/`role`-shaped pattern)? Write a test that positively demonstrates the NEW mechanism
  changes behavior relative to the OLD placeholder default, not merely that the code runs.
- Add the Documenter build (full `docs/make.jl`, not just `Pkg.test()`) as an EXPLICIT, checked step
  in this milestone's own phase-completion criteria, for every phase that adds or touches a literate
  doc page — do not rely on a later, separate "docs hardening" phase to catch a red build, per the
  v2.0 lesson.
- For every new doc page that narrates an algebraic/objective relationship (AC-OPF vs. SOCP
  objective; the reactive augmented Lagrangian derivation), require an explicit constant/offset-term
  reconciliation step in code review — the SAME discipline `solve_admm.jl`'s own header comment
  already demonstrates for the ACTIVE block's sign derivation ("NOT the thesis-3.47 printed sign...
  derived from the single MAX augmented Lagrangian") should be re-derived, in the same rigor, for
  the reactive block's own doc narration, not assumed to mirror it by symmetry.

**Warning signs:**
- A reactive-consensus test suite that never asserts the solved Q differs from the constant-draw
  heuristic under a scenario designed to make them differ.
- A CI or local `docs/make.jl` run skipped ("tests pass, that's the gate") anywhere in this
  milestone's phase completion checklist.
- A new doc page's algebraic claim reviewed only for "does this look like the existing derivation
  style," not "does this specific constant/offset term actually check out against the code."

**Phase to address:** All four v2.1 phases, as a standing cross-cutting checklist item (not owned by
a single phase) — each phase's own completion/verification step should explicitly re-apply these
three named lessons, referencing this pitfall by name in the phase's acceptance checklist.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Build the AC-OPF oracle from a freshly-sampled/re-derived scenario instead of the SOCP's own solved snapshot | Faster to stand up independently | Guaranteed, uninformative "mismatch" (Pitfall 1) | Never for the certification path; fine for an unrelated exploratory Ipopt script |
| Loosen the AC-vs-SOCP comparison tolerance when a high-PV hour disagrees | Makes the check green fast | Discards the milestone's most scientifically interesting finding (Pitfall 2) | Never without first checking reverse-flow/voltage-binding state |
| Reuse the bare identifier `μ` for the reactive-consensus dual | Matches existing docstring language | Collides with the live adaptive-ρ `μ` kwarg and the `Scenario` golden-hash schema (Pitfall 3) | Never in code identifiers; fine in prose/math notation only, with an unambiguous code name |
| Share one `ρ` across active and reactive consensus blocks without re-deriving the balancing | Less new code | Scale-mismatched residual balancing, degraded convergence (Pitfall 4) | Only after empirically confirming the two blocks' natural residual scales are comparable |
| Skip re-measuring the Clarabel `NUMERICAL_ERROR` rate under Q-consensus | Faster to ship the happy path | Combinatorial exposure repeats v2.0's own already-learned lesson (Pitfall 5) | Never — this is a gating measurement, not an optional one |
| Hand-parse OpenDSS lengths/units instead of using PMD | Feels lower-dependency | Silent global impedance rescale (Pitfall 6) | Never — PMD is already the project's own prescribed data oracle for exactly this |
| Apply the mean-diag/mean-offdiag reduction to every linecode without a per-linecode fidelity check | Simpler pipeline | Silent averaging error on untransposed/asymmetric segments (Pitfall 7) | Never for shipped fixtures; fine for a first rough-draft exploration |
| Silently drop regulators/capacitors during ingestion | Simpler parser, faster to a working feeder | Case may silently stop being voltage-binding (Pitfall 8) | Only with an explicit, documented decision AND a binding-constraint acceptance test |
| Re-pin IEEE-123 goldens to whatever the new real-data run produces, with no invariant comparison | Fast "done" checkbox | Masks a units/reduction/omission bug as "the new correct answer" (Pitfall 9) | Never without an explicit before/after invariant table |
| Describe the directional reproduction number as "reproducing the thesis" in prose/docstrings | Sounds like a stronger result | Overclaiming; undermines the project's own documented-assumptions core value (Pitfall 10) | Never — always attach the directional/public-data qualifier |
| Pin a new golden from the first successful run | Fast | Freezes transient numerical jitter from the known Clarabel flake as "the" answer (Pitfall 11) | Never without a repeated-run stability check first |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|--------------|-----------------|-------------------|
| Ipopt (`NLP()`, AC-OPF oracle) | Treating it as a drop-in "ground truth" the way Clarabel is treated for the convex core | Multi-start, check for local-optimum sensitivity, and validate the angle-recovery/units bridge on a trivial fixture first (Pitfall 1) |
| `AgrOpt`/`DsoOpt` reactive fields (`qag`) | Assuming the documented "PLACEHOLDER... currently NOT read" field just needs to be "turned on" | Confirm (as done here, by direct code read) that it is currently inert; making it load-bearing is new modeling work, not a flag flip |
| `solve_admm`'s `μ` kwarg / `Scenario`'s `μ` field | Reusing the name for the new reactive-consensus dual | Distinct identifier for the reactive dual; audit the `Scenario` golden-hash schema boundary first (Pitfall 3) |
| PowerModelsDistribution (OpenDSS parse) | Hand-rolling the length/units/reduction logic instead of using PMD as the prescribed data oracle | Parse via PMD (CLAUDE.md's own "PMD as data oracle" pattern), then apply/verify the positive-sequence reduction on PMD's output |
| Existing IEEE-123-based goldens | Re-pinning them to new real-data numbers with no investigation of why the numbers moved | Explicit before/after invariant comparison (voltage-binding, exactness margin, iteration count) as a gating review step (Pitfall 9) |
| Documenter (`docs/make.jl`) | Assuming `Pkg.test()` passing implies the docs build is still green | Run the full docs build explicitly as a phase-completion gate for every phase touching a literate page (Pitfall 12) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Multi-start Ipopt from many initializations per AC-OPF comparison hour | Wall-clock dominated by redundant NLP solves across 24h × many fixtures | Warm-start one run from the SOCP solution itself as the primary attempt; reserve multi-start for hours that already disagree | Full 24h × IEEE-123 comparison sweep |
| Two-consensus-block ADMM (λ, μ) needing more iterations to jointly converge | Iteration count rising well past the existing ~10-100 baseline | Re-derive joint residual balancing (Pitfall 4) rather than inheriting the active-only tuning | Any Q-consensus fixture at IEEE-13/123 scale |
| Re-running Clarabel-flake-prone SOCP solves many times for golden-stability checks (Pitfall 11) | Golden-pinning step itself becomes slow | Bound the repeated-run count to what's needed for confidence (e.g. 5-10 reruns), not an unbounded loop | Any new fixture near the known conditioning edge case |
| PMD-based OpenDSS parsing of the full unbalanced IEEE-123 dataset on every test run | Slow test suite if re-parsed from raw `.dss` each time | Parse once, vendor the reduced positive-sequence fixture as a clean Julia data file (mirroring the existing `ieee123.jl` pattern), re-parse only when re-deriving | Every CI run, if parsing isn't cached/vendored |

## Security Mistakes

Maps to research integrity/reproducibility, as in v1.0/v2.0.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Reporting an AC-OPF "exactness certified" result without disclosing which hours (if any) showed genuine disagreement | A thesis/paper claim of "certified exact" that quietly omits a known-inexact regime | Report the full per-hour/per-branch comparison table (Pitfall 2), not a single pass/fail headline |
| Reporting the directional welfare-gain figure without the public-data/reduction qualifier | Overclaims thesis reproduction to a reader who can't see the assumption chain | Fixed qualifier phrase + consolidated assumptions doc page, cross-referenced everywhere the number appears (Pitfall 10) |
| Pinning a golden from an unstable, single run near the known Clarabel conditioning edge | A "reproducible" result that isn't actually stable across reruns/machines | Repeated-run stability check before pinning any new golden (Pitfall 11) |
| Silently dropping regulators/capacitors during real-data ingestion with no documentation | A feeder that quietly no longer represents the physical scenario it claims to (voltage-binding case becomes slack) | Explicit, documented per-component-type modeling decision (Pitfall 8) |

## UX Pitfalls

"Users" = the PhD researcher and collaborators extending/reading this validation layer.

| Pitfall | User Impact | Better Approach |
|---------|-------------|------------------|
| AC-OPF comparison reports only "exact"/"inexact", no per-hour/per-branch detail | Can't tell a comparison bug from a genuine high-PV inexactness | Surface the full gap table as a first-class output (mirrors PF-04's own `maxgap` precedent) |
| Reactive DLMP reported with no sign/economic-direction sanity check documented anywhere | Researcher can't tell if the reactive price is trustworthy | Hand-computed 2-bus toy-case pin, treated with the same rigor as the existing active DADP pin |
| Real-IEEE-123 fixture's provenance (units resolution, reduction fidelity, component omissions) buried in a parsing script, not in the fixture's own docstring | Future reader can't tell what's real vs. approximated without reading a throwaway script | Mirror the existing `ieee123.jl` DATA PROVENANCE NOTE convention for every ingestion decision |
| Directional-reproduction number reported without a single, discoverable page explaining its full assumption chain | Collaborator/committee member can't audit what would need to change for a different number | One consolidated, cross-referenced "reproduction assumptions" doc page (Pitfall 10) |

## "Looks Done But Isn't" Checklist

- [ ] **AC-OPF oracle wired:** Ipopt solves and returns a comparison — but does it consume the SOCP's OWN solved feeder/aggregator/dispatch snapshot, not a freshly-sampled one (Pitfall 1)?
- [ ] **Exactness "certified":** the milestone reports a pass — but was a genuine high-PV/reverse-flow stress fixture actually exercised, and was any disagreement there investigated (not tolerance-adjusted) before concluding "certified" (Pitfall 2)?
- [ ] **Reactive consensus added:** `μ` dual-ascent code exists and converges — but is it under a NAME distinct from the existing adaptive-ρ `μ` kwarg and `Scenario` field (Pitfall 3)?
- [ ] **Reactive consensus "works":** loop converges on IEEE-13/123 — but does the EXISTING active-only regression still pass byte-identically with Q-consensus disabled (Pitfall 4)?
- [ ] **Reactive DLMP reported:** a number comes out — but was it pinned against a hand-computed 2-bus toy case, the same rigor as the active DADP (Pitfall 4)?
- [ ] **Clarabel robustness:** the reactive-consensus fixtures run — but was the `NUMERICAL_ERROR` rate actually re-measured under Q-consensus, not assumed from v1.0/v2.0 (Pitfall 5)?
- [ ] **Real IEEE-123 impedances ingested:** the parser runs and produces plausible numbers — but was the length/units convention resolved via PMD and cross-checked against a published reference, not just internally self-consistent (Pitfall 6)?
- [ ] **Positive-sequence reduction applied:** `R1/X1` values exist per linecode — but was a reduction-fidelity metric checked per linecode, not just verified once on "linecode.1" (Pitfall 7)?
- [ ] **Regulators/capacitors/switches handled:** the real-data feeder builds and validates — but is there an explicit, documented decision per component type, and does the intended voltage-binding scenario ACTUALLY bind (Pitfall 8)?
- [ ] **IEEE-123 goldens updated:** tests pass with new numbers — but was a before/after invariant comparison (voltage-binding, exactness margin, iteration count) done, and are the OLD synthetic-fixture goldens kept as an independent regression (Pitfall 9)?
- [ ] **Directional reproduction claimed:** a welfare-gain sign/magnitude is reported — but is the public-data/reduction qualifier attached everywhere the number appears, with a consolidated assumptions doc page (Pitfall 10)?
- [ ] **New goldens pinned:** a bit-for-bit value is committed — but was run-to-run stability actually checked (not pinned from a single run), especially for fixtures near the known Clarabel conditioning edge (Pitfall 11)?
- [ ] **Docs build:** literate pages added/edited for this milestone — but was the FULL `docs/make.jl` build actually run and checked green, not just `Pkg.test()` (Pitfall 12)?

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|-----------------|
| AC-OPF comparison built against mismatched/re-sampled data | MEDIUM | Rewire the oracle to consume the SOCP's own solved snapshot; discard and re-run all prior comparison results (they compared different problems) |
| A genuine SOCP inexactness was tolerance-adjusted away instead of investigated | MEDIUM-HIGH | Revert the tolerance change; re-run the stress fixture; write up the genuine inexactness finding as a documented limitation, not a bug fix |
| `μ` naming collision discovered late (Scenario golden hashes already affected) | MEDIUM-HIGH | Rename the reactive quantity; regenerate any Scenario-hash-affected goldens; audit every call site that read the ambiguous `μ` |
| Q-consensus broke the existing active-only regression | MEDIUM | Gate Q-consensus behind an explicit flag/dispatch path if not already; re-verify the active-only path is untouched; re-derive joint residual balancing before re-enabling |
| Clarabel flake rate under Q-consensus never measured, discovered via CI flakiness later | MEDIUM | Add the retry ladder (mirroring `src/planning/retry.jl`) retroactively; re-measure; consider revisiting per-unit base / tolerance levers |
| IEEE-123 length/units error discovered after goldens pinned | MEDIUM-HIGH | Re-parse via PMD with the correct convention; discard and re-derive every downstream golden that depended on the mis-scaled impedances |
| Positive-sequence reduction found invalid on some linecodes after shipping | MEDIUM | Re-derive per-linecode fidelity metrics; re-reduce the affected linecodes with the native (possibly non-3-phase) matrix; re-verify against the published reference |
| Regulators/capacitors omitted, case found to be silently slack | MEDIUM-HIGH | Add the omitted component's approximate model (or explicitly re-tune the stress scenario); re-verify the binding-constraint acceptance test; re-pin affected goldens |
| Directional reproduction number found to be overclaimed in existing docs/prose | LOW | Add the qualifier retroactively everywhere the number is cited; write the consolidated assumptions page if missing |
| An unstable golden (pinned from one run) starts failing intermittently on CI | LOW-MEDIUM | Re-run repeatedly to characterize the instability; either fix the underlying conditioning or re-pin with an explicit tolerance band, never re-pin blindly to make CI green again |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|-------------------|----------------|
| 1. AC-OPF comparison mismatch (local optima, data drift, units, angle recovery) | AC-exactness oracle phase | Oracle consumes the SOCP's own solved snapshot; angle-recovery validated on a trivial 2-bus fixture first; multi-start Ipopt sensitivity checked |
| 2. Genuine SOCP inexactness mistaken for oracle bug | AC-exactness oracle phase | High-PV/reverse-flow stress fixture exercised; per-hour/per-branch gap table reported; any disagreement investigated for reverse-flow/voltage-binding state before any tolerance change |
| 3. `μ` naming collision (reactive dual vs. adaptive-ρ band) | Reactive-power consensus phase (first design decision) | Distinct code identifier chosen and grepped-clean; `Scenario` schema boundary audited before any field is added |
| 4. Q-consensus convergence degradation + active-only regression break | Reactive-power consensus phase | Active-only regression proven byte-identical with Q-consensus disabled; joint residual balancing re-derived; reactive DLMP pinned on a from-scratch 2-bus toy case |
| 5. Clarabel `NUMERICAL_ERROR` amplification under Q-consensus | Reactive-power consensus phase | Empirical failure-rate re-measurement under Q-consensus fixtures; retry-ladder ported from the planning layer if the rate justifies it |
| 6. IEEE-123 length/units ambiguity | Real IEEE-123 impedances phase | PMD-based parse (not hand-parse); cross-check against an independently-published reference magnitude |
| 7. Positive-sequence reduction validity per linecode | Real IEEE-123 impedances phase | Per-linecode reduction-fidelity metric reported, not just verified on one representative linecode |
| 8. Regulators/capacitors/switches unmapped, case silently un-tightened | Real IEEE-123 impedances phase | Explicit documented decision per component type; binding-voltage-constraint acceptance test added |
| 9. Silent golden re-pin masking a real regression | Real IEEE-123 impedances phase | Before/after invariant comparison table required for any golden re-pin; synthetic-fixture goldens kept as an independent regression |
| 10. Directional reproduction overclaiming / undocumented assumptions | Directional thesis reproduction phase | Fixed qualifier phrase used everywhere; consolidated assumptions doc page cross-referenced from the reported number |
| 11. Goldens pinning transient Clarabel-flake noise | All four phases, at golden-pinning time | Repeated-run stability check required before any new golden from this milestone is committed |
| 12. Retrospective lessons (inert mechanism, docs-build-red, constant-offset) re-learned instead of applied | All four phases, cross-cutting | Positive-mechanism test (not just "it runs"); full `docs/make.jl` build checked per phase; constant/offset reconciliation required for any new algebraic doc narration |

## Sources

- `src/models/exactness.jl` (read directly, 2026-07-25) — HIGH confidence: `assert_socp_exact!`'s
  actual scale-free `rtol`/`atol` combined-tolerance contract, and its explicit statement that a
  strict cone at the optimum is a physically-meaningful PF-04 refusal, not a solver error.
- `src/admm/solve_admm.jl`, `src/admm/AgrOpt.jl`, `src/admm/DsoOpt.jl` (read directly, 2026-07-25) —
  HIGH confidence: the EXISTING `μ::Real = 10.0` adaptive-ρ band kwarg (threaded through
  `solve_admm`'s signature and derived from Boyd §3.4.1 residual balancing), and the CONFIRMED
  currently-inert `qag` reactive placeholder field with its own docstring naming a future `μ`
  dual-ascent extension — the direct evidentiary basis for Pitfall 3.
- `src/experiments/Scenario.jl` (grepped directly, 2026-07-25) — HIGH confidence: `μ::Float64 = 10.0`
  is part of the flat, `savename`-serialized, golden-hash-relevant `Scenario` schema (also threaded
  through `sweep.jl`/`store.jl`), confirming Pitfall 3's reproducibility-breakage risk is concrete,
  not hypothetical.
- `src/data/ieee123.jl` (read directly, 2026-07-25) — HIGH confidence: the synthetic fixture's own
  DATA PROVENANCE NOTE, the plan-07-05 calibration finding ("genuinely voltage-constrained... under-
  voltage on the long load laterals, over-voltage under midday PV reverse flow"), and the
  representative (not App.-E-verbatim) impedance values this milestone will replace — the direct
  basis for Pitfalls 8 and 9.
- `src/solver/factory.jl`, `src/solver/ProblemClass.jl` (read directly, 2026-07-25) — HIGH
  confidence: `NLP()` already dispatches to Ipopt via `select_optimizer`, confirming the AC-OPF
  oracle has a ready-made, un-hacked solver-abstraction seam to build on.
- `~/.claude/projects/.../memory/ieee123-real-impedances-source.md` (read directly, 2026-07-25) —
  MEDIUM-HIGH confidence: the project's own prior research on the public OpenDSS IEEE-123 source,
  the PMD-as-data-oracle execution path, the mean-diag/mean-offdiag reduction recipe (verified only
  on "linecode.1"), and the explicit caveat that exact thesis-figure reproduction requires the
  IP-blocked Appendix E — direct basis for Pitfalls 6, 7, 10.
- `.planning/STATE.md` (read directly, 2026-07-25) — HIGH confidence: the accepted, unresolved,
  version-independent, intermittent Clarabel `NUMERICAL_ERROR` flake (root-caused to per-unit-base-
  dependent cone-slack sensitivity) and the v2.0 Phase-12 measurement explicitly NOT covering the
  full-SOCP-oracle trigger this milestone's reactive-consensus and real-impedance work newly
  exercises — direct basis for Pitfalls 5 and 11.
- `.planning/PROJECT.md` (read directly, 2026-07-25) — HIGH confidence: the v2.1 milestone scope
  statement (directional reproduction, not exact-figure requirement; the four target features)
  and the v2.0 Phase 14 retrospective note ("Deferrable +18 objective-offset reconciliation in
  docs") — direct basis for Pitfalls 10 and 12.
- `.planning/research/v1.0/PITFALLS.md` — HIGH confidence carry-over basis for Pitfall 1 (SOCP
  exactness theory, reverse-flow/over-voltage failure regime), Pitfall 3 (unit/per-unit scaling),
  Pitfall 4 (solver status discipline), and Pitfall 7 (dual sign conventions) — this milestone's
  Pitfalls 1-2 and 6 directly extend that document's own named failure modes across a new
  model-family boundary (AC-OPF) and a new data-ingestion boundary (real OpenDSS parse).
- `.planning/research/PITFALLS.md` (the prior, v2.0 planning-layer pitfalls research, now
  superseded as the live file by this document but preserved in git history) — HIGH confidence
  carry-over basis for the "cut-validity"/"looks-done-but-isn't" discipline pattern this document's
  Pitfall 9 and the cross-cutting Pitfall 12 checklist explicitly reapply, and for the precedent of
  measuring (not assuming) the Clarabel `NUMERICAL_ERROR` rate under new call patterns (Pitfall 5).
- Standard SOCP branch-flow exactness literature (Farivar-Low, Gan-Low-Topcu — exactness fails under
  reverse flow / binding upper voltage) and IEEE-123 / OpenDSS community knowledge (the length/units
  ambiguity is a well-documented community trap, not project-specific) — MEDIUM confidence, general
  domain knowledge not independently re-verified against the live OpenDSS dataset this session;
  flagged for direct verification once the real `.dss` files are actually parsed in the
  implementation phase.

---
*Pitfalls research for: v2.1 Validation & Reproduction milestone (AC-OPF exactness oracle,
reactive-power ADMM consensus, real IEEE-123 impedances, directional thesis reproduction) — a
Julia/JuMP TSO-DSO convex-optimization research bench where duals ARE the product.*
*Researched: 2026-07-25*

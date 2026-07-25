# Feature Research

**Domain:** Power-systems optimization validation — SOCP/AC-OPF exactness certification, ADMM
reactive-power consensus, three-phase→positive-sequence network reduction, and directional
reproduction of a published transactive-energy result. (Milestone v2.1 "Validation & Reproduction")
**Researched:** 2026-07-25
**Confidence:** MEDIUM-HIGH (exactness-condition literature and DLMP decomposition are HIGH
confidence, well-cited results; the positive-sequence reduction recipe is HIGH confidence and
already verified numerically in this repo's memory notes; the "directional reproduction" norms are
MEDIUM confidence — a methodological convention rather than a single citable theorem)

> **Framing note.** This is a *subsequent-milestone* feature landscape — it supersedes the v2.0
> FEATURES.md previously at this path (planning-layer Stackelberg-Nash research, now shipped). It
> covers ONLY the four v2.1 validation/hardening capabilities layered on top of the already-shipped
> v1.0 operational core and v2.0 planning layer. "Table stakes" here means *what a credible
> validation claim in the power-systems SOCP/ADMM/DLMP literature requires* — not general
> feature-completeness of a product.

## Feature Landscape

Each of the four v2.1 target capabilities is treated as its own "feature" with its own
table-stakes / differentiators / anti-features split, because they are four largely independent
validation seams (see Feature Dependencies below for what little coupling exists).

---

### Capability A — AC-OPF-vs-SOCP Exactness Certification

**What "good" looks like, standard procedure:**

The distribution SOCP relaxation ships with two theoretical bodies of sufficient-exactness
results for *radial* (tree) networks:

- **Farivar & Low, "Branch Flow Model: Relaxations and Convexification — Part I/II," IEEE Trans.
  Power Systems 28(3), 2013.** Establishes the branch-flow model itself and proves that for a
  **radial** network the SOC relaxation (thesis eq. 3.39, `l ≥ (P²+Q²)/v`) is exact **provided
  there is no binding upper bound on nodal power injections/withdrawals** (i.e., loads/DER are not
  artificially capped in a way that would want to "round-trip" through the slack `l` variable) —
  physically, the relaxation is tight whenever the true optimum wants to draw the minimum current
  needed to serve the injection, which is the generic case in a welfare-maximizing dispatch. HIGH
  confidence (canonical, ~2000+ citations).
- **Gan, Li, Topcu & Low, "Exact Convex Relaxation of Optimal Power Flow in Radial Networks," IEEE
  Trans. Automatic Control 60(1):72–87, 2015 (arXiv:1311.7170).** Sharpens the above: gives an
  a-priori-checkable sufficient condition (after a small, provably-inconsequential enlargement of
  the feasible set) and **empirically verifies it holds on the IEEE 13-, 34-, 37- and 123-bus test
  feeders** — i.e., the exact same fixture family this project already uses. MEDIUM-HIGH
  confidence on the precise theorem statement (verify wording against the paper before citing a
  numbered theorem in a thesis chapter; HIGH confidence on the headline claim "holds on
  IEEE-13/34/37/123").

**Practical takeaway for this project:** the LinDistFlow exactness-copy trick (thesis 3.43–3.45,
already implemented in `src/models/exactness.jl`) is the project's own construction for *forcing*
tightness rather than relying on the Farivar-Low/Gan-et-al. natural-exactness argument — which is
the right engineering choice (defensive, not fragile), but the validation milestone should still
show the natural-exactness literature applies to the fixture family (radial, standard IEEE feeders)
so a reader trusts the result is not a numerical accident.

**Standard certification quantities and comparison procedure (what the literature and standard
practice actually compare):**

1. **Internal cone-tightness (already implemented, keep):** `gap = |l·v − (P²+Q²)|` per branch/hour
   against a scale-free `atol + rtol·max(|·|)` bound. This shows the relaxation is *self-consistent*
   but does **not** by itself certify the recovered point solves the true nonconvex AC-OPF — it can
   be tight and still be wrong if, e.g., the exactness-copy voltage bound (3.45) itself biased the
   solution away from the true optimum.
2. **External oracle comparison (the missing piece, table stakes for v2.1):** solve the *same*
   scenario as a genuine nonconvex AC-OPF — the un-relaxed power-flow equations (3.29–3.34 with
   3.34 as an **equality**, not the SOC relaxation) in polar or rectangular form — via **Ipopt**
   (already available per milestone context), and compare:
   - **Objective value gap** (SOCP welfare vs. AC-OPF welfare at its own optimum): report as a
     signed relative gap; a genuinely exact relaxation gives `gap ≈ 0` to numerical tolerance
     (SOCP is a valid relaxation, so `AC-OPF welfare ≤ SOCP welfare`; exactness means equality).
   - **Voltage vector deviation**: `max_{j,t} |v_SOCP[j,t] − v_AC[j,t]|` in pu — this is the check
     that actually matters physically (a tight cone with a voltage mismatch would mean the
     exactness-copy is producing a *different*, merely-feasible AC point, not *the* AC optimum).
   - **Branch flow deviation** `max |P_SOCP − P_AC|`, `max |Q_SOCP − Q_AC|`.
   - Optionally, **loss deviation** (`Σ r·l` vs. true AC losses) — a natural single scalar summary.
3. **Two complementary check modes seen in the literature and worth distinguishing explicitly in
   the report** (this distinction is what makes the report *rigorous* rather than hand-wavy):
   - **Feasibility check** ("does the SOCP point lie in the true AC feasible set?"): fix the SOCP's
     optimal `(p_ag, q_ag)` injections and run a plain AC power-flow solve (not an OPF — no
     re-optimization) to get the true `V, P, Q`; compare against the SOCP variables. This isolates
     *whether the recovered dispatch is physically realizable*, independent of optimality.
   - **Optimality check** ("does the SOCP objective match the true AC-OPF optimum?"): solve the
     full nonconvex AC-OPF independently (Ipopt, multiple warm starts) and compare objectives and
     primal points. This is the stronger, headline claim and is what Gan-Li-Topcu-Low's own
     numerical sections do on the IEEE test feeders.
4. **Ipopt-specific pitfall, must be mitigated:** nonconvex AC-OPF is **not** guaranteed a global
   optimum from Ipopt — a local-optimum artifact could masquerade as a "relaxation gap." Standard
   mitigation: **multi-start** (several initializations, including a flat-start and the SOCP
   solution itself as a warm start — the SOCP point is a natural starting guess precisely *because*
   it should already be near-global if exactness holds) and report the **best** (lowest-cost/
   highest-welfare) AC-OPF solve found, not an arbitrary one.
5. **Defensible tolerance:** match the order already established in this codebase's own cone gate
   (`rtol = 1e-4`, scale-free) — a relative objective gap and max-voltage-deviation both at
   `O(1e-4)` is standard practice for "negligible optimality gap, relaxation certified exact on
   this instance"; anything above `O(1e-2)` should be reported as a **genuine relaxation gap**, not
   waved away as numerical noise.
6. **Reporting rigor ("exact" vs. "gap", how to state it defensibly):** report BOTH numbers side by
   side — the internal cone residual (existing PF-04 gate) and the external AC-OPF gap (objective
   %, max |ΔV|, max |ΔP|, max |ΔQ|) — and explicitly state which theoretical result (radial +
   Farivar-Low / Gan-Li-Topcu-Low) the instance falls under, vs. an instance-level empirical
   check only. Never claim "exact" from the cone residual alone; the AC-OPF cross-check is what
   licenses the word "certified."

**Table stakes:**

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Independent nonconvex AC-OPF model (Ipopt, same feeder/scenario, `l=(P²+Q²)/v` as equality) | Without it, "exact" is only ever self-referential (relaxation vs. itself) | MEDIUM | Reuses existing constraint definitions (3.29–3.34) from `ConvexBranchFlow.jl`; swap the SOC inequality for the nonconvex equality and solve with Ipopt via `select_optimizer` |
| Objective-value + voltage + flow comparison report (SOCP vs. AC-OPF) at a defensible tolerance | Standard practice in the exactness literature (Gan-Li-Topcu-Low's own validation) | LOW-MEDIUM | Mostly numeric post-processing once both solves exist |
| Multi-start Ipopt (≥2–3 initializations incl. SOCP warm start) | Guards against reporting a false gap that's actually an Ipopt local optimum | LOW | Cheap insurance; a documented, known NLP pitfall |
| Written methodology note citing Farivar-Low / Gan-Li-Topcu-Low and stating which case applies | "Citable" is the milestone's own bar (thesis/paper-grade); avoids an unsupported "exact" claim | LOW | Docs-only; pairs naturally with the existing Literate rung-page style |

**Differentiators:**

| Feature | Value Proposition | Complexity | Notes |
|---------|--------------------|------------|-------|
| A-priori exactness-condition checker (Gan-Li-Topcu-Low style, e.g. verifying the voltage upper bound is not binding at the AC optimum) that auto-classifies "provably exact" vs. "empirically exact" | Moves from case-by-case empirical checks to a structural argument citable independent of the solved instance | MEDIUM-HIGH | Requires precisely nailing down the paper's checkable condition; verify against the source PDF before implementing |
| Stress sweep to find (and report) a genuine relaxation gap (e.g., high-PV reverse flow on IEEE-123, deliberately tightened voltage band) | Demonstrates understanding of the boundary of exactness, not just the easy case — strong thesis-defense material | MEDIUM | Reuses the existing IEEE-123 voltage-constrained fixture; needs a scenario knob for PV penetration |
| Gap-vs-stress plot (CairoMakie) — relaxation/AC gap as a function of PV penetration or voltage-band tightness | Publication-quality, single figure that tells the whole exactness story | LOW-MEDIUM | Straight-forward given the sweep above; matches existing `DrWatson`/sweep infrastructure |

**Anti-features:**

| Feature | Why Requested | Why Problematic | Alternative |
|---------|----------------|------------------|-------------|
| Building a from-scratch nonconvex AC power-flow *solver* (Newton-Raphson, forward-backward sweep) | Feels more "from first principles" | Ipopt is already an available, validated NLP solver in the stack; writing a bespoke solver is scope creep against the project's explicit "clarity over premature optimization" constraint | JuMP nonconvex model + Ipopt, reusing the `ConvexBranchFlow.jl` constraint blocks with the SOC relaxed to equality |
| General-purpose formal verification of Gan-Li-Topcu-Low's conditions across arbitrary radial topologies | Sounds rigorous | Over-engineering for a validation milestone whose fixtures are two fixed, known feeders (IEEE 13/123) — this is a paper-worthy contribution in its own right, not a v2.1 checkbox | Instance-level empirical certification (per-fixture, per-scenario) documented against the cited theorems |
| Chasing exactness on meshed topologies | "More general is better" | Explicitly out of scope (thesis + fixtures are radial-only; meshed is a deferred research axis per PROJECT.md) | Stay radial; flag meshed exactness as a future-axis note only |

---

### Capability B — Reactive-Power (Q) Consensus in ADMM

**How the reactive dual is standardly written, and what changes:** in a Lagrangian/ADMM
decomposition of a branch-flow OPF, the standard symmetric treatment mirrors the active-power split
exactly: a dual `μ_j[t]` on the nodal reactive-balance residual `R_{q,j}[t]` (thesis eq. 3.32),
with an augmented-Lagrangian quadratic penalty `(ρ/2)‖R_{q,j}‖²` alongside the active-power term —
this is precisely thesis eq. 3.47 as written (`DSO-OPT` carries **both** `λ_j·R_p` and `μ_j·R_q`
penalty terms). Consensus/dual-decomposition literature (general ADMM-for-OPF surveys) treats `P`
and `Q` balance identically: both are "copies" of a shared coupling quantity reconciled by a price
(dual) that converges to the marginal value of relaxing that balance.

The subtlety specific to this project (per the existing `AgrOpt.jl` docstrings): the thesis's own
DER model is **active-power only** (assumption A3, thesis eq. 3.23 — `q_ag_j` is a *known constant*
`−Pdc·tan(arccos φ)`, not an aggregator decision variable). This means:

- There is genuinely **no** degree of freedom on the aggregator side for `μ_j` to move — AGR-OPT's
  objective (thesis 3.46) correctly has **no** `μ`/`R_q` term at all; only DSO-OPT (3.47) carries
  `μ_j·R_q`. This is not a bug to "fix" by inventing an AGR-side reactive decision (that would
  reopen the explicitly-deferred 4Q-BESS/volt-var research axis).
- Given `q_ag_j` is DSO-OPT's own *known parameter* once AGR-OPT reports it, the reactive nodal
  balance `R_{q,j}=0` is really an **internal** equality constraint of DSO-OPT alone (every term in
  it — `Q_{i,j}`, `x·l_{i,j}`, `q_ag_j`, downstream `Q_{j,m}`) is either a DSO-OPT variable or a
  constant fed in from AGR-OPT's last solve. Standard SOCP/QP duality gives `μ_j = dual(R_{q,j})`
  "for free" the moment this is written as a genuine equality constraint inside DSO-OPT — **no
  separate ADMM outer-loop dual-ascent is required for Q** under the active-only DER assumption;
  what is required is that the constraint be a **real, per-node equality** (not the current
  free-`q_import` slack workaround that only balances reactive power in aggregate at the
  substation, decoupling it from the true per-node physics of eq. 3.32).
- What adding a genuine per-node `R_{q,j}=0` changes for **DLMP**: the standard DLMP-decomposition
  literature (e.g., Bhattacharya et al., "Distribution Locational Marginal Pricing for Congestion
  Management and Voltage Support," IEEE Trans. Smart Grid 2018) splits the nodal price into
  active-power, **reactive-power**, congestion, voltage-support, and loss components — with the
  reactive-power component being exactly this `μ_j` (the shadow price of the nodal VAR balance).
  Restoring a genuine per-node `μ_j` therefore (a) makes the existing 4-way DLMP decomposition
  (`src/pricing/dlmp.jl`) more physically grounded — today its "voltage" term must indirectly
  absorb reactive-balance effects that should properly load onto a distinct reactive-price term —
  and (b) gives the project a citable, standard 5th price component (`Q-DLMP`) to report, matching
  the DLMP literature's own convention rather than an ad hoc quantity.

**Table stakes:**

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Genuine per-node reactive balance `R_{q,j}[t]=0` as a real DSO-OPT equality (thesis 3.32), replacing the free-`q_import` aggregate slack | Matches the thesis equation as written; today's slack only enforces reactive balance in aggregate, not per-node | LOW-MEDIUM | Localized to `DsoOpt.jl`; `q_ag_j` is already computed by `AgrOpt.jl` (the constant `qag` field already exists, documented as an unread placeholder) |
| Report `μ_j[t] = dual(R_{q,j})` as a first-class quantity, mirroring how `λ_j` is already surfaced | The reactive shadow price is the standard "Q-DLMP" component in the DLMP literature | LOW | Direct `dual()` read once the constraint is real; no new solve loop needed |
| Convergence/consistency check: `R_{q,j}[t] ≈ 0` at the converged ADMM point (mirrors the existing `R_p` check) | Symmetric correctness gate to the existing active-balance residual check | LOW | Same pattern as the existing ADMM residual diagnostics (`src/admm/residuals.jl`) |
| Regression: adding the real Q balance must NOT change the active-power welfare optimum (since `q_ag` is still a fixed parameter — only pricing/bookkeeping changes) | Cheap, high-value correctness check; a change here would signal an accidental coupling bug | LOW | Compare pre/post welfare on the pinned goldens |
| DLMP decomposition extended with the reactive-price (`μ_j`) as a distinct, citable component | Matches standard DLMP literature convention (5-component split) rather than an ad hoc "voltage" catch-all | MEDIUM | Touches `src/pricing/dlmp.jl`'s existing derivation; must re-verify the additive decomposition still telescopes exactly (same discipline as the existing 4-way check) |

**Differentiators:**

| Feature | Value Proposition | Complexity | Notes |
|---------|--------------------|------------|-------|
| A genuine cross-subproblem ADMM dual-ascent loop on `μ_j` (only meaningful once AGR-OPT has an actual reactive decision variable, e.g., power-factor control within `[0.85,0.95]`) | Would make the reactive price a live consensus quantity rather than a free dual read | HIGH | This *is* the deferred 4Q-BESS/volt-var research axis — flag as a stretch/future item, not v2.1 MVP |
| Reactive-price sensitivity plot (μ_j vs. voltage-band tightness) showing μ rising as voltage constraints bind | Physically intuitive validation that μ tracks the right thing | LOW-MEDIUM | Cheap once μ is real; reuses IEEE-123 voltage-constrained fixture |

**Anti-features:**

| Feature | Why Requested | Why Problematic | Alternative |
|---------|----------------|------------------|-------------|
| Full 4-quadrant inverter / volt-var control as part of this validation milestone | "While we're touching Q, let's make it live" | Explicitly deferred (meshed+4Q-BESS research axis, PROJECT.md Out of Scope); scope creep against a *validation* milestone | Keep DERs active-only (thesis A3); ship the real per-node balance + μ dual read only |
| Inventing a nonstandard ad hoc "voltage price" formula not grounded in a real dual | Might seem to "solve" the DLMP-decomposition ambiguity faster | Not citable, undermines the "trustworthy, documented" bar the milestone exists for | Use the standard nodal-reactive-balance-dual (`μ_j`) as in Bhattacharya et al. and the general DLMP literature |

---

### Capability C — Positive-Sequence Reduction (IEEE-123 real impedances)

**Standard method (textbook, HIGH confidence — Kersting, *Distribution System Modeling and
Analysis*; Fortescue symmetrical-component theory):** given a line segment's 3×3 phase-impedance
matrix `Z_abc` (self on the diagonal, mutual off-diagonal, from Carson's equations / OpenDSS
linecode data), the exact symmetrical-component transform is `Z_012 = A⁻¹ Z_abc A` with
`A = [[1,1,1],[1,a²,a],[1,a,a²]]`, `a = e^{j120°}`. For a **perfectly transposed/balanced** line
(`Zaa=Zbb=Zcc`, all mutuals equal), this collapses cleanly to scalars: `Z+ = Zs − Zm`,
`Z0 = Zs + 2·Zm`. Real distribution linecodes (including IEEE-123's) are **not** transposed, so the
exact transform produces a full 3×3 sequence matrix with nonzero sequence-coupling off-diagonals —
"the positive-sequence impedance" is then not rigorously a single scalar. The standard engineering
**approximation** (used by OpenDSS-style "balanced-equivalent" line-code reduction and confirmed by
this project's own prior research note) treats the line *as if* transposed by **averaging** the
diagonal and off-diagonal terms before applying the same formula:

```
R1 = mean(diag(R_abc)) − mean(offdiag(R_abc))
X1 = mean(diag(X_abc)) − mean(offdiag(X_abc))
```

This is exactly the recipe already validated in this repo's memory note
(`ieee123-real-impedances-source.md`: verified on linecode.1 → `R1≈0.05797, X1≈0.11876 Ω/unit`,
sensible order of magnitude) against the public GitHub-hosted OpenDSS IEEE-123 dataset
(`tshort/OpenDSS` `123Bus/IEEELineCodes.DSS` + `IEEE123Master.dss`). The recommended execution path
— parse via **PowerModelsDistribution** (oracle-only, per CLAUDE.md's own stack decision), extract
per-branch 3×3 series impedance, apply the reduction, vendor a clean fixture — sidesteps the
IEEE-123 file's own documented length/unit ambiguities.

**Caveats that make this approximate (must be documented, not silently absorbed):**

1. **Untransposed asymmetry is discarded.** The averaging step assumes away the real geometric
   asymmetry of the conductor spacing; error scales with how far `Z_abc` is from its balanced form.
2. **Single/two-phase laterals have no rigorous positive-sequence equivalent at all.** A large
   fraction of IEEE-123's laterals are single-phase spurs — collapsing them into a balanced
   positive-sequence branch is an additional modeling assumption (project's own stated "balanced
   positive-sequence" scope), not a mathematical identity; must be flagged, not hidden.
3. **Sequence-coupling terms (positive↔negative↔zero interaction on an asymmetric line) are
   dropped** — valid to first order for short distribution feeders but not exact.
4. **Per-phase voltage unbalance cannot be recovered** from a positive-sequence single-phase power
   flow — this is fundamentally a balanced-feeder surrogate, and should be presented as such.
5. Charging capacitance / neutral-return effects differ between the true 3-phase network and the
   positive-sequence equivalent; secondary for a feeder this short, worth a one-line caveat only.

**Table stakes:**

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Documented Fortescue-averaging reduction (`R1/X1` formula above) applied per real OpenDSS IEEE-123 linecode, replacing the current synthetic representative r/x | This is the milestone's explicit deliverable; the formula is already verified in this repo's own memory note | LOW-MEDIUM | Recipe and public data source already identified; mostly a data-engineering + vendoring task |
| PMD-parse of the public OpenDSS `.dss` files as an oracle-only data source (never the production power-flow model) | Matches the project's own CLAUDE.md stack decision ("PMD as data-parsing and cross-validation oracle") | MEDIUM | New (weak) dependency on PowerModelsDistribution for parsing; verify it resolves cleanly under the current `Manifest.toml` |
| Written caveat (mirroring the existing DATA PROVENANCE note style already in `ieee123.jl`) enumerating the approximation's error sources | Consistent with the codebase's existing rigor/documentation convention; prevents silently overclaiming fidelity | LOW | Docs-only |
| Quantitative cross-check: same topology/real impedances run through PMD's own unbalanced power-flow oracle vs. the positive-sequence-reduced SOCP solve; report max voltage-magnitude / loss deviation | Turns "we did a reduction" into "we measured how wrong the reduction is" — a defensible, citable fidelity number | MEDIUM | Needs a real (not synthetic) 3-phase load allocation to run the PMD oracle meaningfully |

**Differentiators:**

| Feature | Value Proposition | Complexity | Notes |
|---------|--------------------|------------|-------|
| Explicit list/flag of which real segments are single/two-phase laterals (where the approximation is weakest) | Tells future researchers exactly where to look if results look suspicious | LOW | Cheap given the per-segment reduction already computes per-linecode phase counts |
| Per-segment asymmetry metric (`‖Z_abc − balanced(Z_abc)‖ / ‖Z_abc‖`) reported alongside the reduction | Quantifies, rather than just asserts, which lines are most approximated | LOW-MEDIUM | Nice-to-have scalar; easy given the matrices are already parsed |

**Anti-features:**

| Feature | Why Requested | Why Problematic | Alternative |
|---------|----------------|------------------|-------------|
| Full unbalanced three-phase OPF as the production model | "Since we're parsing 3-phase data anyway..." | Explicitly out of scope (PROJECT.md: "Unbalanced three-phase / phase-detailed modeling... balanced positive-sequence" is the v1+ scope); would silently expand the whole framework's modeling axis mid-validation-milestone | Keep PMD strictly as a data/cross-validation **oracle**; production model stays balanced positive-sequence SOCP |
| Deriving negative/zero-sequence impedances or fault-level analysis | "The transform gives us these for free" | Irrelevant to OPF/pricing validation; scope creep with no consumer in this project | Skip; only `Z+` (and by extension R1/X1) is needed |
| Attempting to individually model single-phase laterals with their true phase | Feels "more correct" | Contradicts the project's own stated balanced-equivalent scope; half-modeling 3-phase creates an inconsistent hybrid model | Treat every branch as balanced-equivalent per the stated scope; document it as a limitation instead |

---

### Capability D — Directional Reproduction of the Published Welfare/DLMP Result

**What a credible "we reproduce the direction/structure" claim looks like** when the exact source
data is unavailable (this project's specific blocker: thesis Appendix E lives behind an
IP-blocked CONICET repository). This maps closely to a recognized distinction in computational
research reproducibility — the ACM Artifact Review and Badging terminology separates
**"Reproduced"** (independently obtained data/means, same qualitative conclusions) from
**"Replicated"** (same result from the original artifact/data) — MEDIUM confidence attribution
(well-known convention in CS/systems venues; power-systems methods papers follow an analogous,
less formally badged, norm when a predecessor's exact dataset is unavailable). A credible
"Reproduced, not Replicated" claim in this domain typically has these ingredients:

1. **Explicit, prominent framing up front:** state plainly that this reproduces the *qualitative
   direction and mechanism* of the published result, not the exact figures, and *why*
   (data-source constraint), before presenting any numbers — never let a reader infer exact-figure
   reproduction occurred.
2. **Sign checks, not magnitude matches, as the primary evidence:** e.g., DADP-based social welfare
   exceeds FIT-based welfare (the thesis's headline `+25%` is a *sign*, not a digit, claim at its
   core); DSO surplus moves loss→gain; prosumer surplus decreases under DADP relative to FIT (the
   thesis's own regressive-to-prosumer / net-positive-to-total story) — each of these is a
   **sign** on a delta, independently checkable on different input data.
3. **Magnitude BAND rather than a point estimate:** state a plausible range grounded in the same
   underlying mechanism (congestion/voltage relief monetized by dynamic pricing) — e.g., "welfare
   improves by a double-digit percentage, bracketing the thesis's own +25%" — rather than asserting
   a specific percentage as if it were expected to match.
4. **Qualitative curve-SHAPE reproduction as the most convincing single artifact:** the
   characteristic DADP-vs-hour signature (below wholesale during midday PV surplus, above wholesale
   during evening peak) is reproducible on *any* reasonably parameterized dataset if the mechanism
   is correctly implemented — this is standard practice in transactive-energy/dynamic-pricing
   papers as the qualitative "sanity" figure, independent of the exact source numbers, and is
   already partially supported by this project's existing `pricing/checks.jl` "economic-direction
   checks."
5. **Sensitivity-DIRECTION reproduction:** the thesis runs its own sensitivity cases (battery×1.5,
   PV×1.5, willingness-to-pay×1.5, alt. MEM profile); reproducing the **direction** of each (e.g.,
   more battery capacity ⇒ more welfare gain) on independently generated data is a strong,
   defensible claim precisely because it does not depend on matching the thesis's absolute numbers.
6. **A pinned regression on sign + band, not exact equality** — extending this codebase's existing
   "computed goldens" and "a converged equilibrium" honesty-gate conventions (already used for the
   planning layer, PVAL-02..04 / NASH-04) to the operational-layer welfare comparison: assert the
   sign of the DADP-vs-FIT welfare delta and a magnitude band, fail loud if a future change flips
   the sign or exits the band — never assert exact equality to a digitized or otherwise
   uncertain reference number.
7. **Explicit data-provenance statement**: point to the actual data differences driving the
   inability to match exactly (public IEEE-123 impedances vs. thesis App. E; a regenerated
   demand/PV Markov-chain population vs. the thesis's UK Time-Use Survey + Loughborough irradiance
   data) — this project already states this correctly in PROJECT.md and
   `memory/ieee123-real-impedances-source.md`; the validation milestone should carry that framing
   into the actual reported artifact, not just internal docs.

**Table stakes:**

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| "Reproduced, not Replicated" framing stated explicitly in the docs/report before any numbers | Prevents an unsupported exact-match claim; matches recognized reproducibility conventions | LOW | Docs-only, but must precede the numeric artifact, not follow it |
| Sign check: DADP welfare > FIT welfare on the same (real or synthetic) feeder/data | The thesis's own core claim, checkable independent of magnitude | LOW | Reuses existing `pricing/welfare.jl` + `pricing/fit.jl` machinery |
| Pinned golden regression asserting sign + a magnitude BAND (not exact value) for the welfare delta | Extends the codebase's own existing honesty-gate pattern; the correct rigor level given data constraints | LOW-MEDIUM | Direct analogue of the existing PVAL-02..04 / NASH-04 pattern, applied to the operational layer |
| Qualitative DADP-vs-hour plot reproducing the midday-dip / evening-peak shape (vs. wholesale price) | The most convincing single "we got the mechanism right" artifact | LOW | CairoMakie plot; data already available post-solve |

**Differentiators:**

| Feature | Value Proposition | Complexity | Notes |
|---------|--------------------|------------|-------|
| Directional reproduction of the thesis's own sensitivity sweep (battery×1.5, PV×1.5, willingness×1.5, alt. MEM profile) | A materially stronger reproduction claim — five independent directional checks instead of one | MEDIUM | Reuses existing `experiments/sweep.jl`; needs the sensitivity scenarios defined |
| Side-by-side overlay figure (thesis-digitized curve, if the Appendix E gate is ever cleared, vs. this project's curve, normalized) | Nice bridge artifact if/when the CONICET data becomes available | LOW (contingent) | Explicitly a **stretch goal** per PROJECT.md — gated on obtaining Appendix E, not a v2.1 commitment |

**Anti-features:**

| Feature | Why Requested | Why Problematic | Alternative |
|---------|----------------|------------------|-------------|
| Chasing the exact `+$1,819 / +25%` headline via parameter back-fitting to the thesis's number | Feels like the "real" reproduction | With genuinely different input data (public vs. App. E impedances, regenerated vs. original demand data) this is curve-fitting to a single number, not validation — it would actively undermine the "trustworthy, documented" bar the milestone exists to establish | Report sign + band; state the data-provenance limitation explicitly (already the project's own documented position) |
| Treating a digitized thesis figure (from a low-resolution PDF) as a numeric golden for a tight quantitative regression | Seems like "real" ground truth | Digitization error is itself a noise source; committing a tight regression to it manufactures false precision | Use a digitized figure only as a qualitative visual reference (a plot overlay), never as a numeric assertion target |

---

## Feature Dependencies

```
Capability A (AC-OPF exactness oracle)
    — independent of B, C, D; only needs the existing Ipopt wiring + ConvexBranchFlow.jl constraints

Capability B (Reactive-power Q consensus)
    — independent of A, C, D; localized to admm/DsoOpt.jl + pricing/dlmp.jl
    ──synergizes with──> A (once Q balance is real, A's AC-OPF cross-check can also validate Q,
                            not just P — do B before/alongside A if sequencing matters)

Capability C (Positive-sequence reduction, real IEEE-123 impedances)
    └──requires──> PMD-parse of public OpenDSS IEEE-123 data (external data acquisition step)
    ──feeds into──> Capability D (Case B / IEEE-123 reproduction wants real, not synthetic, impedances)

Capability D (Directional reproduction)
    └──requires (for the IEEE-123 / voltage-constrained case)──> Capability C
    └──benefits from (not strictly required)──> Capability B (a real reactive price strengthens
                                                    the voltage-driven reproduction story)
    (Capability D's IEEE-13 / congestion-driven case does NOT require C or B)
```

### Dependency Notes

- **A is the most self-contained** — it only touches the existing `ConvexBranchFlow.jl` constraint
  set plus the already-available Ipopt solver; no dependency on the other three. Good candidate to
  sequence first or in parallel.
- **B is likewise self-contained** — localized to `admm/DsoOpt.jl` (real per-node Q balance) and
  `pricing/dlmp.jl` (the new μ-based price component); no data-acquisition dependency. Doing B
  before/alongside A means A's AC-OPF cross-check can also confirm the reactive flows/voltages,
  strengthening both.
- **C requires external data acquisition** (the public GitHub OpenDSS IEEE-123 files) and a new
  (weak, oracle-only) dependency on PowerModelsDistribution for parsing — the highest
  external-dependency risk of the four, but the reduction recipe itself is already verified
  numerically in this repo's own memory note.
- **D depends on C** for the IEEE-123/voltage-constrained reproduction (the milestone explicitly
  wants "real, standard data"), but the IEEE-13/congestion-driven reproduction can proceed
  independently. Sequence C before D's IEEE-123 leg; D's IEEE-13 leg can run any time.

## MVP Definition

### Launch With (v2.1, all four table-stakes rows above)

- [ ] AC-OPF oracle (Ipopt, multi-start) + objective/voltage/flow gap report alongside the existing
      cone-tightness gate — why essential: without it, "exact" is a self-referential claim
- [ ] Genuine per-node reactive balance (`R_{q,j}=0`) + reported `μ_j` reactive price — why
      essential: restores physical grounding of the voltage/DLMP story; today's free-`q_import`
      slack decouples reactive balance from the per-node physics
- [ ] Real IEEE-123 impedances via the verified Fortescue-averaging reduction on public OpenDSS
      data, plus a PMD-oracle fidelity cross-check — why essential: the milestone's explicit
      deliverable; synthetic impedances cannot be cited
- [ ] Directional welfare/DLMP reproduction (sign + band pinned regression + DADP-shape plot) with
      explicit "Reproduced, not Replicated" framing — why essential: gives the thesis a citable,
      honest reproduction claim without requiring data that is not obtainable

### Add After Validation (v2.1.x / stretch within v2.1)

- [ ] Stress sweep finding a genuine relaxation gap (Capability A differentiator) — trigger: once
      the baseline AC-OPF oracle is solid and time remains to explore the boundary
- [ ] Sensitivity-direction reproduction (battery/PV/willingness sweeps, Capability D
      differentiator) — trigger: once the single-scenario directional reproduction is pinned

### Future Consideration (later milestone)

- [ ] Live μ ADMM consensus loop requiring an actual AGR-side reactive decision — defer until the
      4Q-BESS/volt-var research axis opens (explicitly out of scope for v2.1)
- [ ] A-priori exactness-condition auto-checker (Gan-Li-Topcu-Low style) — defer; a paper-worthy
      contribution in its own right, not a v2.1 checkbox
- [ ] Thesis-figure digitized overlay — explicitly gated on obtaining Appendix E (stretch goal per
      PROJECT.md, not a commitment)

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|----------------------|----------|
| AC-OPF oracle + gap report (A) | HIGH | MEDIUM | P1 |
| Multi-start Ipopt guard (A) | HIGH | LOW | P1 |
| Real per-node Q balance + μ price (B) | HIGH | LOW-MEDIUM | P1 |
| DLMP 5-way decomposition incl. Q-price (B) | MEDIUM-HIGH | MEDIUM | P1 |
| Fortescue-averaged real IEEE-123 impedances (C) | HIGH | MEDIUM | P1 |
| PMD-oracle fidelity cross-check (C) | MEDIUM-HIGH | MEDIUM | P1 |
| Directional sign+band pinned regression (D) | HIGH | LOW-MEDIUM | P1 |
| DADP-shape qualitative plot (D) | MEDIUM | LOW | P1 |
| Stress sweep / gap-vs-PV-penetration plot (A) | MEDIUM | MEDIUM | P2 |
| Sensitivity-direction reproduction (D) | MEDIUM | MEDIUM | P2 |
| Per-segment asymmetry metric (C) | LOW-MEDIUM | LOW | P3 |
| A-priori exactness-condition checker (A) | MEDIUM | HIGH | P3 |
| Live μ consensus / AGR-side Q decision (B) | LOW (for v2.1) | HIGH | Out of scope this milestone |

**Priority key:**
- P1: Must have — this is the concrete, citable "done" standard for v2.1
- P2: Should have, add when time remains within v2.1
- P3: Nice to have, defer to a future milestone

## Sources

- Farivar, M. & Low, S.H., "Branch Flow Model: Relaxations and Convexification — Part I / Part II,"
  IEEE Transactions on Power Systems, 28(3), 2013. HIGH confidence (canonical, widely cited).
  https://arxiv.org/pdf/1204.4865 ; https://smart.caltech.edu/papers/relaxconvex2parts.pdf
- Gan, L., Li, N., Topcu, U. & Low, S.H., "Exact Convex Relaxation of Optimal Power Flow in Radial
  Networks," IEEE Transactions on Automatic Control, 60(1):72–87, 2015. MEDIUM-HIGH confidence on
  precise theorem wording (verify against the paper before citing a numbered theorem); HIGH
  confidence on the headline applicability to IEEE 13/34/37/123-bus feeders.
  https://arxiv.org/abs/1311.7170 ; https://arxiv.org/pdf/1311.7170
- Bhattacharya, S. et al., "Distribution Locational Marginal Pricing (DLMP) for Congestion
  Management and Voltage Support," IEEE Transactions on Smart Grid, 2018 (OSTI/IEEE Xplore) — 5-way
  DLMP decomposition including a distinct reactive-power price component. MEDIUM-HIGH confidence
  (WebSearch-verified summary; recommend reading the full paper before citing a specific formula).
  https://www.osti.gov/biblio/1488555 ; https://ieeexplore.ieee.org/document/8089425/
- ADMM/dual-decomposition-for-OPF general pattern (consensus variables, Lagrangian multiplier as
  price) — MEDIUM confidence, general survey-level WebSearch corroboration, consistent with the
  thesis's own eq. 3.46–3.47 structure already extracted in `THEORY-thesis.md`.
- Kersting, W.H., *Distribution System Modeling and Analysis* — symmetrical-component /
  positive-sequence reduction of an unbalanced line-impedance matrix. HIGH confidence (standard
  textbook method); the specific averaging recipe used here is already independently verified
  numerically in this repository's own prior research
  (`memory/ieee123-real-impedances-source.md`, linecode.1 → R1≈0.05797, X1≈0.11876 Ω/unit).
- ACM Artifact Review and Badging terminology ("Reproduced" vs. "Replicated") — MEDIUM confidence
  attribution as the closest formal analogue to the "directional reproduction" convention used
  here; power-systems methods papers follow an informal version of the same norm.
- Project-internal sources consulted: `.planning/PROJECT.md`, `.planning/research/THEORY-thesis.md`
  (thesis equations 3.2–3.47, case data), `src/models/exactness.jl` (existing PF-04 cone-tightness
  gate), `src/admm/AgrOpt.jl` (documented μ/Q placeholder), `src/pricing/dlmp.jl` (existing 4-way
  DLMP decomposition derivation), `src/data/ieee123.jl` (existing synthetic-impedance provenance
  note), `memory/ieee123-real-impedances-source.md` (verified public-data reduction recipe).

---
*Feature research for: TSO-DSO Integration Optimization Framework — v2.1 Validation & Reproduction*
*Researched: 2026-07-25*

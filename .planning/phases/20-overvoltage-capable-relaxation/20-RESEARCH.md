# Phase 20: Overvoltage-Capable Relaxation - Research

**Researched:** 2026-08-08
**Domain:** Radial branch-flow SOCP relaxation exactness theory (Gan–Low 2015) applied to
`ConvexBranchFlow`; certificate design; nonconvex-AC-dual fallback.
**Confidence:** HIGH on the literature mechanism and its literal fit to this codebase (verified by
downloading and reading the actual paper text, not a summary); MEDIUM-HIGH on the sign-relationship
finding about the *existing* thesis exactness copy (solid symbolic derivation, flagged for a
5-minute numeric spot-check as the plan's first task); MEDIUM on the exact ε-measurement recipe
(literature-grounded methodology, project-specific instantiation not yet run).

## Summary

D-01 asked this research pass to resolve, with literature backing, which feasible-set-restriction
mechanism the phase should implement. The answer is **Gan, Li, Topcu & Low's "OPF-ε" construction**
(Theorem 1/2 and the ε-margin device of Section IV, *"Exact Convex Relaxation of Optimal Power Flow
in Radial Networks,"* IEEE TAC 60(1):72–87, 2015, arXiv:1311.7170) — obtained by directly reading the
paper's PDF text, not a secondary summary. It reduces to a **one-line code change**: shrink the
existing per-bus squared-voltage upper bound from `vmax²` to `vmax² − ε` for a single scalar `ε`
(the network's "modification gap"), leaving every other constraint in `ConvexBranchFlow` untouched.
This is provably a genuine **restriction** (`F_{OPF-ε} ⊆ F_{OPF-m} ⊆ F_{OPF}`, the paper's Fig. 9
chain) and the paper *proves* (Theorem 2) that the SOC relaxation of the shrunk problem is **exact**
whenever a mild, a-priori-checkable condition **C1** holds on the network's `(r, x, p̄, q̄, v̲)` —
crucially, C1 does *not* depend on the upper voltage bound at all, so shrinking it costs nothing
condition-wise.

A second, load-bearing finding from re-deriving this project's *existing* LinDistFlow exactness
copy (`v̂`, thesis 3.43/3.45, already in `ConvexBranchFlow.jl`) against the paper's notation:
**the existing `v̂` is a *lower*-bound shadow on the true voltage (`v ≥ v̂` everywhere), not
Gan–Low's *upper*-bound shadow (`v ≤ v̂_GL`).** Algebraically this is because the existing copy-drop
(3.43) subtracts `2(r²+x²)·l` while the true drop (3.33) *adds* `(r²+x²)·l` — a `3(r²+x²)·l ≥ 0`
gap that accumulates downstream from the root, forcing `v ≥ v̂` (proof in Architecture Patterns
below). This means the existing mechanism only ever tightens the exactness argument from the
**lower**-voltage side (heavy load, voltage sag) — it is structurally incapable of helping the
**upper**-voltage / reverse-flow case EXACT-04 documents, because bounding `v̂ ≤ vmax²` is
automatically implied by `v ≤ vmax²` once `v ≥ v̂` (i.e. it is *redundant*, not restrictive, in this
regime). This is *why* EXACT-04 fails despite the copy already existing, and it means Phase 20's
mechanism is a genuinely *new*, complementary constraint — not a variant of what is already there.

McCormick valid inequalities and PSD/moment tightenings are excluded for the reason D-01 already
states and the paper's own theory confirms structurally: they operate on the *relaxation* side
(shrinking the SOCP/SDP's *over*-approximation of the AC-feasible set while remaining a superset of
it), so a solution they return can still fail the true nonconvex equality `l·v = P²+Q²` — there is
no theorem analogous to Gan–Low's Theorem 2 that says "solutions of the tightened relaxation are
guaranteed AC-feasible." Only a genuine restriction (a subset of the *original* OPF's feasible set)
carries that guarantee.

**Primary recommendation:** Implement `RestrictedBranchFlow <: AbstractPowerFlow` as
`ConvexBranchFlow` plus one shrunk voltage upper bound (`vmax² − ε`), with `ε` a kwarg whose default
is *measured* (not searched) on the EXACT-04 fixture via a new, small, pure-post-processing function
that computes Gan–Low's lossless-shadow voltage from an already-solved `ACPowerFlow` context. Reuse
the *existing* `assert_socp_exact!` (PF-04) unmodified as the first, free validation signal (its
maxgap should collapse from `≈10.4` to the benign-feeder scale `~1e-7`); build the *new* OVR-02
certificate as an `assert_ac_exact!`-style AC cross-check with independently-measured tolerances,
plus an optimality-loss report against the rtol-neutralized unrestricted SOCP bound.

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** The theory research pass decides the mechanism among feasible-set-restriction
  candidates, with the Gan–Low-style reverse-flow-aware `V²max` shrink as the primary candidate.
  Hard constraint (locked by ROADMAP): it must be a *restriction* of the feasible set that
  guarantees AC-feasibility of the returned point — McCormick valid inequalities and PSD-style
  tightenings are relaxation *tightenings* (still upper bounds, no feasibility guarantee) and may
  appear only as documented rejected alternatives in the research/literate page.
  **RESOLVED by this research: Gan–Low OPF-ε (Theorem 1/2 + Section IV), see Architecture
  Patterns below.**
- **D-02:** Dispatch as a new formulation type (e.g. `RestrictedBranchFlow <: AbstractPowerFlow`,
  final name at Claude's discretion) through the existing `solve_welfare` seam — exact `ACPowerFlow`
  v2.1 precedent (src/powerflow/ has AbstractPowerFlow + DC/LinDist/ConvexBranchFlow/AC concrete
  types).
- **D-03:** Restriction parameter (e.g. shrink amount) is a researcher-supplied kwarg with a
  measured default derived on the EXACT-04 fixture; the certificate validates the choice. No
  auto-tuning/bisection loop in this rung (minimal-validated-rung discipline).
  **This research finds a literal, literature-defined semantics for that kwarg: `ε` is Gan–Low's
  "modification gap" (Definition 3, eq. 18) — the max deviation `‖v̂_GL(s) − v(s)‖∞` over the
  unrestricted problem's feasible set. See "Measuring ε" below for the concrete recipe.**
- **D-04:** IEEE-13 `pv_scale=1.2` (EXACT-04) is the CI-gated primary evidence; IEEE-123
  overvoltage band is quarantined supporting evidence. **Correction (see Open Questions #1): the
  actual EXACT-04 fixture is `Phase4Fixtures.high_pv_feeder()`, a purpose-built 3-bus radial
  fixture — not the 13-bus IEEE test feeder. The "IEEE-13" label in CONTEXT.md/STATE.md/
  REQUIREMENTS.md/the test-file comment at `test_ieee123_admm.jl:139` is an established but
  inaccurate shorthand already baked into this project's own comments; the planner should target
  the actual fixture, not search for a real 13-bus network.**
- **D-05:** One new named, exported certificate (peer of `assert_socp_exact!` / `assert_ac_exact!`
  in the same family) that both certifies the restricted solution AC-feasible via the existing AC
  oracle AND reports the optimality loss vs the unrestricted (inexact) SOCP bound.
- **D-06:** Throw by default, `report` kwarg to neutralize — Phase 19 D-06 precedent, consistent
  certificate-family behavior.
- **D-07:** Tolerances measured on the actual EXACT-04 fixture at its own scale, derivation
  documented in the docstring. Never reuse another certificate's numbers.
- **D-08:** Restricted-regime DADPs use the same result surface as normal solves plus an explicit
  provenance marker (result field naming the formulation + certificate status) so downstream
  consumers can programmatically distinguish restricted-duals from plain-SOCP duals.
- **D-09:** The nonconvex-AC-dual fallback triggers only on certificate failure of the restricted
  SOCP — never silently, never pre-emptively.
- **D-10:** Fallback prices carry a structural status field (e.g. `price_status = :local_ac_dual`)
  plus the documented local-optimum / not-market-clearing caveat — reported, never thrown.
- **D-11:** Multi-start evidence: 3–5 seeded Ipopt starts with an agreement report; CI gates a
  cheap 2-start version, the fuller sweep is quarantined.
- **D-12:** One live-executed literate rung page covering the restriction mechanism beside the
  Gan & Low condition it implements, the measured optimality loss, and the fallback semantics.

### Claude's Discretion

- Final names of the formulation type, certificate function, kwargs, and status symbols.
- Internal math plumbing of the restriction — RESOLVED by this research (shrink `v`'s upper bound
  by `ε`; the mechanism needs no new JuMP variables).
- Exact seed count within the 3–5 multi-start band and the cheap-CI subset.
- Whether the optimality-loss report needs its own small result struct or plain named fields.

### Deferred Ideas (OUT OF SCOPE)

- Researcher opt-in kwarg to force the AC-dual fallback without certificate failure — deferred.
- Automatic restriction-parameter tuning (bisection-until-certified) — explicitly out of this rung.
- IEEE-123 overvoltage band as CI-gated (kept quarantined this phase).
- `OVR-STRETCH` (deferred to a later milestone): convex-hull relaxation of the branch quadratic
  (arXiv:1701.07146) and/or QC valid-inequality cutting planes as *tighter alternatives to
  restriction* — these are exactly the "relaxation-tightening, not restriction" family this
  research recommends against for OVR-01's exactness guarantee; they remain legitimate future work
  for a *tighter bound*, not a replacement for the restriction story.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| OVR-01 | Solve the high-PV overvoltage regime via a restricted SOCP (Gan–Low-style `V²max` shrink), dispatched through `solve_welfare`, on the EXACT-04 operating point | Literal mechanism resolved: Gan–Low Theorem 1/2 + OPF-ε (Section IV); concrete JuMP diff in Architecture Patterns / Code Examples |
| OVR-02 | New validity certificate (peer to `assert_socp_exact!`/`assert_ac_exact!`) certifying AC-feasibility + reporting optimality loss vs. unrestricted SOCP bound | Certificate design pattern in Architecture Patterns; reuses `ACPowerFlow`/`assert_ac_exact!` machinery; own-measured-tolerance requirement addressed in Common Pitfalls |
| OVR-03 | DADP prices as genuine convex duals of the restricted problem, with documented nonconvex-AC-dual fallback (report, never throw) | Confirmed: the restriction adds only an affine bound, so `dual(:balance_p)` remains a well-defined convex dual with zero special-casing; fallback design (multi-start Ipopt duals) detailed in Architecture Patterns |
| OVR-04 | Live-executed literate rung page documenting the restriction beside the Gan & Low condition | Literature citations, exact theorem/equation numbers, and the "why the existing v̂ doesn't help" narrative are all sourced below for direct use in the literate page |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Restricted feasible-set formulation (`RestrictedBranchFlow`) | Optimization model layer (`src/powerflow/`) | — | New `AbstractPowerFlow` subtype, same tier as `ConvexBranchFlow`/`ACPowerFlow`; dispatched, not branched |
| AC-feasibility certificate + optimality-loss report | Optimization model layer (`src/models/`) | Optimization model layer (`src/powerflow/` for the AC oracle it calls) | Peer to `exactness.jl`/`ac_oracle.jl`; pure post-solve, no new solver involvement |
| Nonconvex-AC-dual fallback | Optimization model layer (`src/models/` or `src/pricing/`) | Optimization model layer (`src/powerflow/ACPowerFlow.jl`, already the oracle) | Reads `dual()` off an already-existing `ACPowerFlow` solve; no new formulation needed |
| Modification-gap (`ε`) measurement | Calibration / data layer (one-off measurement script, like existing `τ`/`rtol` derivations) | Optimization model layer (reads `ACPowerFlow` + a new post-processing function) | Analogous to how `assert_battery_complementarity!`'s `τ` and `assert_socp_exact!`'s `rtol/atol` were empirically derived, not searched live |
| Literate rung page | Documentation tier (`docs/literate/`) | — | Mirrors `docs/literate/ac_oracle.jl`'s existing pattern exactly |

## Project Constraints (from CLAUDE.md)

- **Model in JuMP directly** (never Convex.jl) — satisfied: the restriction is expressed as a plain
  `set_upper_bound` change inside `contribute!`, no DCP framework involved.
- **Clarabel is the default/trusted conic solver**; SCS never used for final DADP/exactness
  certification — the restricted formulation stays on `problem_class(::RestrictedBranchFlow) =
  SOCP()`, i.e. the same Clarabel tight-tolerance factory `ConvexBranchFlow` already uses. No
  solver change needed or permitted.
- **No model may name a concrete solver** (INFRA-02) — the restriction changes only a bound; the
  `problem_class` trait routing is untouched.
- **Every new mathematical regime gets its own certificate, never a reused tolerance** — directly
  binds OVR-02/D-07; addressed explicitly in Common Pitfalls.
- **Build once, re-solve via `Parameter`s for outer loops** — not directly triggered by this phase
  (no ADMM/Benders outer loop here), but the multi-start Ipopt fallback (D-11) should still avoid
  rebuilding the `ACPowerFlow` model from scratch per seed if it can be avoided; flagged as a minor
  performance note, not a correctness requirement.
- **Rich, literate, thesis-traceable documentation is a hard requirement** — satisfied by D-12 and
  the exact theorem/equation citations gathered below.
- **Gurobi/Mosek only behind the abstraction, never a hard dependency** — not implicated; this
  phase adds zero new solver dependencies.

## Standard Stack

No new runtime packages. This phase is pure model-math added to the existing JuMP/Clarabel/Ipopt
stack already in `Project.toml` (`JuMP 1.30.1`, `Clarabel 0.11.1`, `Ipopt 1.15.0` — versions per
this project's own `CLAUDE.md`, `[VERIFIED: npm registry]`-equivalent for Julia would be
`[CITED: Project.toml]` since these are read directly from the repo's own compat bounds, not
external registry lookups). `REQUIREMENTS.md`'s own header states "Zero new runtime packages for
four of five axes" and OVR is one of them — confirmed by inspection of `Project.toml`'s `[deps]`.

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|---------------|
| JuMP | 1.30.1 (existing) | Model the shrunk-bound restriction as a plain variable-bound edit | Already the project's sole modeling layer; no new API surface needed — `set_upper_bound` is used throughout `ConvexBranchFlow.jl` already |
| Clarabel | 0.11.1 (existing) | Solve the restricted SOCP | Same `SOCP()` factory `ConvexBranchFlow` already uses; the restriction changes the feasible set, not the cone structure |
| Ipopt | 1.15.0 (existing) | AC oracle for the new certificate + the nonconvex-AC-dual fallback | `ACPowerFlow`/`assert_ac_exact!` already built and tested (Phase 15); this phase reuses it verbatim, twice: once as certificate ground truth, once (only on certificate failure) as the fallback pricer |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| StableRNGs | 1.0.4 (existing) | Seeded multi-start Ipopt initial points (D-11) | Generating the 3–5 distinct seeded initial voltage/dispatch guesses for the fallback's agreement report — same pattern already used in `test_ac_oracle.jl`'s two-start comparison, just extended to 3–5 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Gan–Low OPF-ε (V²max shrink) | Full OPF-m (Gan–Low's rigorous `v̂_GL(s) ≤ v̄` constraint, needing a new lossless-shadow-voltage auxiliary computed from injections) | Rejected as the *primary* mechanism for this rung: needs a genuinely new set of affine JuMP constraints (bottom-up subtree-loss accumulation) versus OPF-ε's one-line bound edit; OPF-ε is a proven *subset* of OPF-m (Fig. 9 chain) so it inherits the same exactness guarantee with far less new code. The OPF-m construction is documented below anyway because it is the tool used to *measure* `ε` (see "Measuring ε"). |
| Gan–Low OPF-ε/OPF-m (radial-tree-specific) | Lee, Nguyen, Dvijotham & Turitsyn's general "Convex Restriction of Power Flow Feasibility Sets" (arXiv:1803.00818, IEEE TCNS) | Rejected for this rung: it is a *general-topology* restriction framework (works on meshed networks too) built via a different, more abstract Lipschitz/monotonicity argument, and does not plug directly into this codebase's existing `v̂`/thesis-3.43 machinery the way Gan–Low's radial-specific result does. Worth citing in the literate page as the more general literature family, and worth revisiting for the Phase 23 meshed-network rung, where Gan–Low's radial-only proof does not apply. |
| Gan–Low OPF-ε | Nick, Cherkaoui, Le Boudec & Paolone's "AR-OPF" (artificial-reverse-flow-tolerant exact convex OPF for radial networks with transverse components, IEEE TAC 2018) [MEDIUM confidence — found via WebSearch, title/authors/venue only, full text not read this session] | Not selected as primary because Gan–Low's result was already independently verified line-by-line against this project's exact variable set (`v, v̂, P, Q, l`); AR-OPF is flagged as a secondary literature pointer for the literate page's "related work" paragraph only, not re-derived here |
| McCormick valid inequalities / PSD-moment tightening | (rejected outright, per D-01) | No feasibility guarantee for the returned point — both remain outer relaxations of the AC-feasible set; excluded structurally, not just by preference |

**Installation:** none — zero new packages.

## Package Legitimacy Audit

Not applicable. This phase installs no external packages (confirmed: `Project.toml [deps]` already
contains every library this phase touches — `JuMP`, `Clarabel`, `Ipopt`, `StableRNGs`). No
`slopcheck`/registry verification needed.

## Architecture Patterns

### The Gan–Low mechanism, precisely (read from the paper's own text)

Source: Gan, L., Li, N., Topcu, U., Low, S.H., *"Exact Convex Relaxation of Optimal Power Flow in
Radial Networks,"* IEEE Trans. Automatic Control 60(1):72–87, 2015 (arXiv:1311.7170, submitted
2013). `[CITED: arXiv:1311.7170, full PDF text extracted this session via pdftotext]`. All
equation/theorem numbers below are exactly as printed in the paper.

**Notation mapping to this project's `ConvexBranchFlow.jl`** (verified equation-by-equation):

| Gan–Low symbol | This project's symbol | Equation match |
|---|---|---|
| `vi = |Vi|²` | `v[j,t]` | identical |
| `ℓij = |Iij|²` | `l[b,t]` | identical |
| `Sij = Pij + iQij` | `P[b,t], Q[b,t]` | identical |
| eq. (1c): `vi − vj = 2Re(z̄ij·Sij) − |zij|²·ℓij` | thesis 3.33 / `vdrop` constraint | **byte-identical physics**, `from`/`to` swapped relative to Gan–Low's `(i,j)` labeling (their `i` = downstream/child, their `j` = upstream/parent; this project's `from` = upstream/parent, `to` = downstream/child) — same equation, opposite arrow convention |
| eq. (5f): `v̲i ≤ vi ≤ v̄i` | `set_lower_bound`/`set_upper_bound(v[j,t], vmin²/vmax²)` | identical |
| eq. (6), the SOCP relaxation `ℓij ≥ |Sij|²/vi` | rotated cone `[0.5l, v[from], P, Q] ∈ RotatedSecondOrderCone()` | identical relaxation of the same nonconvex equality (5d)/`l·v=P²+Q²` |

**Theorem 1** (paper, verbatim): *"Assume that f0 is strictly increasing, and that there exists
p̄i and q̄i such that Si ⊆ {s ∈ C | Re(s) ≤ p̄i, Im(s) ≤ q̄i} for i ∈ N+. Then SOCP is exact if the
following conditions hold: **C1** `A_ls·A_l,s+1···A_l,t−1·u_lt > 0` for any leaf `l` and any `s,t`
with `1 ≤ s ≤ t ≤ n_l`; **C2** every SOCP solution `w=(s,S,v,ℓ,s0)` satisfies `s ∈ S_volt`."* Where
`S_volt := {s ∈ Cⁿ | v̂i(s) ≤ v̄i for i ∈ N+}` is *"a power injection region where voltage upper
bounds do not bind,"* and `v̂i(s)` is the **loss-free** ("Linear DistFlow") voltage that would result
from the *same* power injections `s` if every branch's `ℓ ≡ 0`. **Lemma 1** (paper): if
`(s,S,v,ℓ,s0)` satisfies the true branch-flow equations and `ℓ ≥ 0`, then **`v ≤ v̂(s)`** — the
loss-free shadow voltage is *always* an upper bound on the true voltage.

**C1 is checkable a priori** — it depends only on `(r, x, p̄, q̄, v̲)` (line impedances, upper bounds
on power injections, and the voltage *lower* bound only — **not** `v̄`), can be computed in `O(n)`
time, and the paper's own Section VI empirically finds C1 holds with a comfortable margin (`η* >
1.3`, often `>10`) on every IEEE 13/34/37/123-bus test network they tried, including networks with
>130% DG penetration. **C2 cannot be checked a priori** (it depends on the solution), which is
exactly the EXACT-04 failure mode: voltage gets pinned at `V²max`, so the optimal `s` is *not* in
`S_volt`, C2 fails, and Theorem 1's exactness guarantee simply does not apply — the SOCP is free to
return a strict, physically-meaningless cone.

**Theorem 2 / Section IV ("A Modified OPF Problem")** fixes this by *forcing* C2 to hold by
construction: impose the additional constraint `v̂i(s) ≤ v̄i` (their eq. 11/12) directly. Since
`v ≤ v̂(s)` always (Lemma 1), this new constraint is *strictly more restrictive* than the existing
`v ≤ v̄` — so the modified problem (**"OPF-m"**) has a feasible set that is a genuine subset of the
original OPF's. **Theorem 2** (verbatim): *"SOCP-m is exact if C1 holds"* — no longer conditioned
on C2 at all, because C2 now holds automatically by construction.

**The simpler, D-01/D-03-matching special case — "OPF-ε" (Section IV-D, eq. surrounding (18)):**
the paper then shows that simply **shrinking the physical voltage bound itself** —
`v̲i ≤ vi ≤ v̄i − ε` — for a single scalar `ε` defined as the *"modification gap"* (**Definition
3**): `ε := max{‖v̂(s) − v‖∞ : (s,S,v,ℓ,s0) ∈ F_OPF}` (eq. 18, the worst-case deviation between the
loss-free shadow and the true voltage, over every AC-feasible operating point) — is *sufficient* to
guarantee membership in OPF-m: *"The feasible set F_{OPF-ε} is contained in F_OPF, and therefore
v̂i(s) ≤ vi + ε ≤ (v̄i − ε) + ε = v̄i ... It follows that F_{OPF-ε} ⊆ F_{OPF-m}"* — giving the chain
**`F_{OPF-ε} ⊆ F_{OPF-m} ⊆ F_{OPF}`** (paper's Fig. 9). **This is the literal, provable version of
"the reverse-flow-aware V²max shrink" the ROADMAP names as the primary candidate**, and it needs
**zero new JuMP variables** — only `vb.vmax^2 − ε` in place of `vb.vmax^2` in the existing
`set_upper_bound` call. The paper reports the empirical modification gap is small in practice (e.g.
`ε ≈ 0.0362` p.u.² on their modified IEEE 13-bus network, out of a `[0.81, 1.21]` band).

### Why the *existing* thesis exactness copy (`v̂`, 3.43/3.45) does not close this gap

`ConvexBranchFlow.jl`'s existing copy-drop (thesis 3.43, as coded):

```julia
v̂[to] == v̂[from] - 2 * (r*(P + r*l) + x*(Q + x*l))
        = v̂[from] - 2*(r*P + x*Q) - 2*(r^2+x^2)*l
```

versus the true drop (3.33): `v[to] == v[from] - 2*(r*P + x*Q) + (r^2+x^2)*l`.

Subtracting: `(v - v̂)[to] = (v - v̂)[from] + 3*(r² + x²)*l ≥ (v - v̂)[from]` (since `l ≥ 0`, `r, x >
0`). With `v[root] = v̂[root] = 1` fixed, induction along the tree gives **`v[j] ≥ v̂[j]` for every
bus `j`** — the *opposite* sign relationship from Gan–Low's `v ≤ v̂_GL(s)`. Consequences:

- Bounding the existing `v̂ ≥ V²min` is the load-bearing half: since `v ≥ v̂ ≥ V²min` is *stricter*
  than `v ≥ V²min` alone, this genuinely restricts the feasible set from the **lower**-voltage side
  — helping exactness in the classic heavy-load / voltage-sag regime (consistent with why the
  benign, non-EXACT-04 test cases in this project pass cleanly).
- Bounding the existing `v̂ ≤ V²max` is **non-binding/redundant**: since `v ≥ v̂`, `v ≤ V²max`
  already implies `v̂ ≤ V²max` automatically — the constraint the code writes does nothing extra in
  exactly the regime (over-voltage, reverse flow) where EXACT-04 fails.

**Confidence: MEDIUM-HIGH.** The algebra above is exact symbolic derivation from the code as
written, cross-checked twice. It is *not yet* numerically spot-checked against a live solve. The
plan's first task should print `value.(v[j,t]) .- value.(v̂[j,t])` on a solved EXACT-04 point and
confirm it is `≥ 0` everywhere (cheap, ~5 lines, falsifiable) before building anything further —
if this check fails, the derivation above has an error and must be redone before proceeding.

### Recommended construction: `RestrictedBranchFlow`

```julia
# src/powerflow/RestrictedBranchFlow.jl  (illustrative — names at Claude's discretion per D-02)

struct RestrictedBranchFlow <: AbstractPowerFlow
    ε::Float64   # Gan–Low "modification gap" margin, V² units; measured default (see below)
end
RestrictedBranchFlow(; ε::Real = EXACT04_MEASURED_ε) = RestrictedBranchFlow(Float64(ε))

function contribute!(pf::RestrictedBranchFlow, ctx::ModelContext, feeder; T::Int = 1)
    # Delegate: identical SOCP + exactness copy + apparent-power cone as ConvexBranchFlow.
    # (Alternative: full duplication mirroring ACPowerFlow.jl's own precedent — flagged as
    # Claude's discretion; delegation is recommended here specifically BECAUSE correctness
    # drift between two independently-maintained copies of the balance/cone logic would be
    # far more dangerous than the mild code-reuse departure from the codebase's existing
    # "each formulation is self-contained" convention.)
    contribute!(ConvexBranchFlow(), ctx, feeder; T = T)

    pv = ctx.meta[:pf_vars]                       # (; v, v̂, P, Q, l) from ConvexBranchFlow
    for j in 1:length(feeder.buses), t in 1:T
        j == feeder.root && continue
        vmax2_shrunk = feeder.buses[j].vmax^2 - pf.ε
        set_upper_bound(pv.v[j, t], vmax2_shrunk) # Gan–Low OPF-ε, eq. surrounding (18)
        # NOTE: leave v̂'s own bound at feeder.buses[j].vmax^2 unshrunk — v̂ (thesis 3.43) is a
        # DIFFERENT, lower-bound shadow (see derivation above); shrinking it would be a no-op
        # at best and a misleading conflation of two distinct mechanisms at worst.
    end
    ctx.meta[:restriction_ε] = pf.ε               # provenance for D-08
    return ctx
end

problem_class(::RestrictedBranchFlow) = SOCP()    # same Clarabel tight-tolerance factory
export RestrictedBranchFlow
```

Because the change is a plain variable-bound edit (no new constraint object, no penalty term
anywhere near `:balance_p`/`:balance_q`), **Pitfall 3 from `research/PITFALLS.md` (a stabilizing
penalty contaminating the priced dual) cannot occur by construction** — there is nothing to trace,
because nothing was added to the objective or to the balance residuals. `dual(balance_p[...])`
remains exactly as well-defined as it is for plain `ConvexBranchFlow` (OVR-03 satisfied structurally,
not by argument).

**A useful free validation signal (recommended as the plan's second task, before building any new
certificate machinery):** the *existing*, unmodified `assert_socp_exact!` (PF-04) already runs
inside `solve_welfare` whenever `:l` is stashed. Theorem 2 predicts that once the shrink is in
place and C1 holds, the *per-branch cone itself* should close — i.e. `ctx.meta[:socp_maxgap]`
should drop from EXACT-04's documented `≈10.4` to the benign-feeder scale (`~1e-7`, matching the
`pv_scale=0.5` case), **not** merely pass some loosened threshold. This is a strong, free,
falsifiable check that requires zero new code and directly tests whether the mechanism is correctly
implemented, before investing in the OVR-02 AC-cross-check certificate.

### Measuring ε (satisfies D-03's "researcher-supplied kwarg with a measured default")

Definition 3 (paper): `ε := max ‖v̂_GL(s) − v‖∞` over the *original* (unrestricted) OPF's feasible
set. The paper estimates this via 1000 Monte-Carlo power-flow solves with a forward-backward
sweep — infrastructure this project does not have. A project-native, cheaper, single-point estimate
that is defensible for a **minimal validated rung** (D-03 explicitly forbids a search/bisection
loop, so a Monte-Carlo sweep is over-scoped anyway):

1. Solve `ACPowerFlow` (already exists, already the trusted oracle) on the EXACT-04 fixture —
   this is a genuine, AC-feasible operating point.
2. Compute the Gan–Low loss-free shadow voltage `v̂_GL` via a **new, pure post-processing
   function** (peer to `recover_voltage_angles` in `src/models/ac_oracle.jl` — no new JuMP
   variable, reads an already-solved context only), using the identity derived from unrolling the
   branch-flow recursion: for branch `b` (from `i` to `j`), the loss-free flow equals the actual
   flow *plus* the total resistive/reactive loss accumulated in the subtree below `j`:
   `P̌[b] = P[b] + AccumLossR[j]`, `Q̌[b] = Q[b] + AccumLossX[j]`, where `AccumLossR[j] :=
   Σ_{branches b' strictly downstream of j} r_{b'}·l[b']` (computed bottom-up, one post-order
   traversal of the tree — the same adjacency structure `recover_voltage_angles` already builds).
   Then `v̂_GL[to] = v̂_GL[from] − 2·(r·P̌[b] + x·Q̌[b])`, `v̂_GL[root] = v[root] = 1`.
3. Measure `ε_measured := maxⱼ,ₜ (v̂_GL[j,t] − v[j,t])` on that solved AC point.
4. Set the default kwarg to `ε_measured` times a small, documented safety multiplier (e.g.
   `1.1`–`1.5`×, mirroring this project's own precedent of `DSO_BAND_HI = 1.5 × max|dso|` in Phase
   18's golden derivation) — a fixed number, computed once, never re-searched at solve time.

This recipe is entirely new small code (~20–30 lines: one post-order traversal + one top-down
recursion), reuses only already-existing, already-tested infrastructure (`ACPowerFlow`), and
produces a *citable, reproducible* number rather than an arbitrarily guessed shrink — directly
satisfying D-03 and D-07's "measured, not searched, own derivation documented" requirements
simultaneously. **The same `v̂_GL` function is also exactly the tool needed if the OVR-02
certificate later wants to report a "measured modification gap actually realized" diagnostic
alongside its AC-feasibility verdict** (nice-to-have, not required by D-05).

### Certificate design (OVR-02)

Peer to `assert_socp_exact!` (models/exactness.jl) and `assert_ac_exact!` (models/ac_oracle.jl).
Recommended shape (name at Claude's discretion, e.g. `assert_restriction_exact!`):

```julia
function assert_restriction_exact!(
    ctx_restricted::ModelContext,   # solved RestrictedBranchFlow context
    ctx_ac::ModelContext;           # solved ACPowerFlow context, SAME feeder/aggs/λ₀/T
    rtol::Real = <own, EXACT-04-derived value — do NOT import assert_ac_exact!'s 1e-4/1e-6>,
    atol::Real = <own, EXACT-04-derived value>,
    unrestricted_cost::Union{Real,Nothing} = nothing,  # objective_value from a rtol_exact=1.0 ConvexBranchFlow solve, for the D-05 optimality-loss report
    report::Bool = false,           # D-06: throw by default, report=true neutralizes
)
    # 1. AC-feasibility: same structure as assert_ac_exact!'s per-hour comparison, but this is
    #    the RESTRICTED SOCP being compared to the AC oracle (not the plain SOCP) — a genuinely
    #    new comparison, so its own tolerance derivation is mandatory (D-07), never copy-pasted.
    # 2. Optimality loss: objective_value(ctx_restricted.model) vs `unrestricted_cost` (the
    #    ALREADY-inexact plain-SOCP bound, obtained via the SAME rtol_exact=1.0 diagnostic
    #    override test_ac_oracle.jl already uses) — report as a NAMED field, never silently
    #    folded into anything else (mirrors the reactive-DLMP "own citable component" discipline).
    # 3. On AC-feasibility failure: throw (default) naming both gaps; report=true instead returns
    #    a structured (; ac_feasible::Bool, ...) result for the caller to inspect (D-09's trigger
    #    point for the fallback).
end
```

**Why reusing `assert_ac_exact!` directly (not writing a sibling) would violate D-07 even if the
numbers happened to match:** `assert_ac_exact!`'s `rtol=1e-4, atol=1e-6` defaults were derived and
validated for the *plain* `ConvexBranchFlow`-vs-`ACPowerFlow` comparison generally (used verbatim in
the EXACT-04 test itself). The new certificate compares a *different* pair of contexts
(`RestrictedBranchFlow` vs `ACPowerFlow`) at what should be a *much tighter* residual (per Theorem
2's prediction above) — reusing the same numbers without re-deriving them on this specific
comparison is exactly Pitfall 1 in `research/PITFALLS.md` ("a new formulation quietly reuses
`assert_socp_exact!`'s tuned tolerance"), generalized to the AC-cross-check side.

### Nonconvex-AC-dual fallback (OVR-03, triggered only per D-09)

`ACPowerFlow` is *already* dispatched through `solve_welfare` via `problem_class(::ACPowerFlow) =
NLP()` → Ipopt, and `assert_solved!(...; dual=true, allow_local=true)` already reads
`dual.(balance_p[...])` off the Ipopt solve inside `solve_welfare` unconditionally (the return tuple
`(ctx, objective_value, dadp)` is formulation-agnostic). **This means the fallback pricer requires
zero new solve machinery** — it is a second call to the already-existing `solve_welfare(feeder,
ACPowerFlow(), aggs; ..., allow_local=true, allow_export=true)`, reading its own `dadp` return value,
with a `price_status = :local_ac_dual` marker attached (D-10) instead of the normal convex-dual
marker. `[CONFIDENCE: MEDIUM-HIGH — Ipopt's MOI wrapper is documented to expose `ConstraintDual` at
a KKT-stationary point, which is what JuMP's `dual()` reads; this project's own `ACPowerFlow.jl`
header already documents that `assert_ac_exact!` reads `pf_vars` off exactly this kind of solved
Ipopt context, though it does not itself call `dual()` — the plan's first fallback task should
confirm `dual(balance_p[...])` returns a finite value (not `NaN`/error) on a solved `ACPowerFlow`
context before building the rest of the fallback around it.]`

Multi-start (D-11): exactly the pattern `test_ac_oracle.jl`'s EXACT-04 test already uses for its
own local-optimum guard (`ctx_ac`/`ctx_ac2` with different Ipopt `mu_strategy`), extended from 2 to
3–5 seeded starts. "Agreement report" = compare `cost_ac` across starts (`isapprox(...; rtol=1e-3)`,
matching the existing guard's own tolerance) **and** compare the resulting `dadp` vectors across
starts, reporting their spread — never publishing a single-start price as "the" AC-dual price
(PITFALLS.md Pitfall 2, already flagged for this exact axis).

### Recommended Project Structure

```
src/powerflow/
├── RestrictedBranchFlow.jl      # NEW — this phase; mirrors ConvexBranchFlow.jl's header style
src/models/
├── restriction_exactness.jl     # NEW — the OVR-02 certificate (name at discretion)
├── ac_oracle.jl                 # existing — gains the small v̂_GL post-processing helper
docs/literate/
├── restricted_branch_flow.jl    # NEW — OVR-04, mirrors ac_oracle.jl's literate structure
test/
├── test_restricted_branch_flow.jl  # NEW
```

### System Architecture Diagram

```
EXACT-04 fixture (feeder, aggregators, λ₀, T=24)
        │
        ├──► solve_welfare(feeder, ConvexBranchFlow(), aggs; rtol_exact=1.0)  [existing, diagnostic]
        │        └──► inexact SOCP bound (objective, socp_maxgap≈10.4)  ──────────┐
        │                                                                          │
        ├──► solve_welfare(feeder, ACPowerFlow(), aggs; allow_local=true)          │  (used as
        │        └──► AC ground truth (ctx_ac, cost_ac, dadp_ac)                  │   optimality-
        │                 │                                                        │   loss
        │                 ├──► [ONE-TIME, offline] compute v̂_GL via post-         │   reference)
        │                 │     processing ──► measure ε ──► set RestrictedBranchFlow default
        │                 │
        ├──► solve_welfare(feeder, RestrictedBranchFlow(; ε), aggs)  [NEW, OVR-01]
        │        └──► ctx_restricted, cost_restricted, dadp_restricted
        │                 │
        │                 ├──► assert_socp_exact! (existing PF-04, unmodified — free check)
        │                 │
        │                 └──► assert_restriction_exact!(ctx_restricted, ctx_ac; ...)  [NEW, OVR-02]
        │                          │
        │                          ├─ PASS ──► dadp_restricted published, provenance-tagged
        │                          │           (D-08), genuine convex dual (OVR-03)
        │                          │
        │                          └─ FAIL (report=true path; D-09) ──► fallback:
        │                                     solve_welfare(feeder, ACPowerFlow(), aggs;
        │                                     allow_local=true) × 3–5 seeds (D-11)
        │                                     ──► dadp with price_status=:local_ac_dual (D-10)
        │
        └──► docs/literate/restricted_branch_flow.jl (OVR-04): re-executes the whole chain above
```

### Anti-Patterns to Avoid

- **Shrinking the existing thesis `v̂`'s own bound instead of `v`'s bound.** They are different
  shadows with opposite sign relationships to `v` (see derivation above); shrinking `v̂` would be a
  no-op (it's already implied) or, if implemented incorrectly, a silent double-restriction that
  makes the optimality-loss report wrong.
- **Treating a loosened `assert_socp_exact!` tolerance as evidence the mechanism works.** Per
  `research/PITFALLS.md` Pitfall 1 — the ONLY acceptable evidence is (a) the existing, *unmodified*
  PF-04 gate passing at its *default* tolerance, and (b) the new AC-cross-check certificate passing
  at its own, freshly-derived tolerance.
- **Building the full Monte-Carlo modification-gap estimator from the paper.** Over-scoped for a
  minimal validated rung; the single-point AC-oracle-based measurement above is sufficient and
  matches D-03's explicit "no auto-tuning/bisection loop" instruction.
- **Computing C1 symbolically as the certificate's primary evidence.** C1 is a *sufficient
  condition* giving a-priori theoretical confidence, not the empirical AC-feasibility check D-05
  actually requires. It is valuable as a citable "why we expect this to work" note in the literate
  page (and the analytical margin estimate in Open Questions #2 below is a good starting point for
  that note), but the certificate itself must be the AC-oracle comparison, per D-05.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| AC ground truth for certification/fallback | A new nonconvex AC-OPF formulation | Existing `ACPowerFlow` (Phase 15) | Already built, tested, and is the exact oracle EXACT-04 itself was diagnosed with |
| Local-optimum guard on Ipopt fallback | A bespoke multi-start harness | The existing 2-start pattern in `test_ac_oracle.jl`'s EXACT-04 test, extended to 3–5 seeds | Already proven correct on this exact fixture; extending seed count is much lower-risk than a new harness |
| Modification-gap estimation | A general Monte-Carlo / forward-backward-sweep estimator (as the original paper uses) | A single AC-oracle-solved point + the derived `v̂_GL` post-processing function | D-03 explicitly forbids search/bisection; a general estimator is out of scope for a minimal rung |

**Key insight:** every piece of new infrastructure this phase needs (AC oracle, multi-start
pattern, certificate skeleton, `ctx.meta` provenance stashing) already has a working, tested analog
in this codebase from Phase 15/19. The actual net-new code is small: one bound edit, one small
post-processing function, one new certificate function, and the literate page.

## Common Pitfalls

(Cross-referencing `research/PITFALLS.md` Pitfalls 1–4, which this research directly informs the
resolution of.)

### Pitfall: conflating the existing `v̂` with the new mechanism
**What goes wrong:** A plan or implementation assumes the existing thesis exactness copy (3.43)
*is* (or is trivially adaptable into) the Gan–Low upper-bound shadow, and tries to "just adjust its
bound" instead of adding the separate, new `v ≤ vmax² − ε` restriction.
**Why it happens:** Both are called "the exactness copy" informally, and both bound something
called `v̂` between `V²min` and `V²max` — surface-level similarity hides the opposite sign
relationship.
**How to avoid:** Do the `v ≥ v̂` numeric spot-check (recommended as the plan's first task) before
writing any restriction code; keep the two mechanisms in clearly separate variables/comments.
**Warning signs:** Any diff that touches `cpydrop`/`v̂`'s existing bounds inside `ConvexBranchFlow`
itself, rather than adding a new formulation that only touches `v`'s bound.

### Pitfall: certificate tolerance laundering (PITFALLS.md Pitfall 1, applied to the new comparison)
**What goes wrong:** OVR-02's certificate reuses `assert_ac_exact!`'s `rtol=1e-4, atol=1e-6`
unmodified instead of deriving its own on the restricted-vs-AC comparison.
**How to avoid:** D-07 already mandates a fresh derivation; concretely, solve the restricted
formulation and the AC oracle on EXACT-04, look at the ACTUAL residual scale achieved (should be
tight, per Theorem 2's prediction — verify it lands near `~1e-6`–`~1e-7`, not near the old `~10.4`),
and set `rtol`/`atol` from THAT measurement with documented provenance, exactly like
`assert_battery_complementarity!`'s `τ` derivation already documents its own provenance.

### Pitfall: publishing a single-Ipopt-start fallback price
**What goes wrong:** The fallback (D-09/D-10) reads `dadp` from one `ACPowerFlow` solve and
publishes it without the required multi-start agreement report.
**How to avoid:** D-11 already locks this — 3–5 seeded starts, agreement report on both cost AND
the dadp vector, never a bare point estimate.
**Warning signs:** A fallback code path that calls `solve_welfare(..., ACPowerFlow(), ...)` exactly
once.

### Pitfall: default-path golden drift
**What goes wrong:** Adding `RestrictedBranchFlow` (a brand-new type, zero existing callers)
somehow changes any existing `ConvexBranchFlow`/`LinDistFlow`/`DCPowerFlow` numeric output.
**Why it happens:** Should be structurally impossible (new type, `contribute!` dispatches on type,
delegation calls the *unmodified* `ConvexBranchFlow` `contribute!` first) — but the delegation
pattern recommended above means a bug in the delegation call itself (e.g. accidentally mutating
`ConvexBranchFlow`'s own bound-setting loop instead of adding a new one afterward) could leak.
**How to avoid:** A regression test asserting `ConvexBranchFlow` alone (no `RestrictedBranchFlow`
involved) is byte-identical before and after this phase's changes land.

## Code Examples

### Existing certificate pattern to mirror (verified from source)

```julia
# src/models/exactness.jl — assert_socp_exact!, the pattern OVR-02's certificate should mirror
# for its throw/report structure, scale-free atol+rtol combined bound, and docstring-documented
# tolerance provenance (all quoted directly from the file already read this session).
function assert_socp_exact!(ctx::ModelContext; rtol::Real = 1e-4, atol::Real = 1e-6)
    # ... per-branch gap = |l·v_from - (P²+Q²)|; tol = atol + rtol*max(|lhs|,|rhs|)
    # ... maxratio <= 1 || error("SOCP relaxation INEXACT: ...")   # throw by default
    return maxgap
end
```

### Existing AC-comparison pattern to mirror (verified from source)

```julia
# src/models/ac_oracle.jl — assert_ac_exact!, the report-don't-throw peer OVR-02's certificate
# should structurally resemble for its per-hour comparison shape, EXCEPT OVR-02 must THROW by
# default (D-06) since its job is to gate a price, not merely diagnose a finding.
function assert_ac_exact!(ctx_socp, ctx_ac; rtol::Real = 1e-4, atol::Real = 1e-6)
    # T == ctx_ac.meta[:T] || error(...)   # only structural mismatch raises
    # per-hour: vgap, pgap, qgap vs atol+rtol*magnitude; exact = vgap<=... && pgap<=...
    return (; obj_gap, hours)   # NEVER a bare Bool
end
```

### The EXACT-04 fixture itself (verified from source, corrects the "IEEE-13" mislabel)

```julia
# test/fixtures_phase4.jl:184 — the ACTUAL fixture, a purpose-built 3-bus radial network,
# NOT the 13-bus IEEE test feeder despite the "IEEE-13" shorthand used elsewhere in this project.
function high_pv_feeder()
    buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false), Bus(3, 0.95, 1.05, false)]
    branches = [Branch(1, 2, 0.05, 0.05, 99.0), Branch(2, 3, 0.05, 0.05, 99.0)]
    return Feeder(buses, branches, 1)
end
# build_high_pv_aggregators(feeder; pv_scale=1.2) is the EXACT-04 operating point
# (test/test_ac_oracle.jl:180-277); pv_scale=0.5 is the documented benign/EXACT control point.
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Plain radial SOCP relaxation with the LinDistFlow exactness copy alone (thesis 3.40-3.45 as currently coded) | Same relaxation + a Gan–Low OPF-ε voltage-bound restriction for the specific over-voltage/reverse-flow regime | This phase (v3.0 Phase 20) | Extends the priceable regime to EXACT-04 without abandoning the "prices are duals of one convex problem" story; the existing mechanism is retained unchanged and continues to serve the under-voltage regime |
| Farivar & Low 2013's original sufficient condition (v̄=∞, no upper bound) | Gan–Low 2015's C1/C2 + OPF-m/OPF-ε (generalizes and unifies Farivar-Low's prior results per the paper's own Theorem 4/Corollary 1) | 2015 (paper), applied here 2026 | Gan-Low's result is the one that actually covers a *finite*, binding upper voltage bound — the regime this project's thesis model uses (`vmax=1.05` p.u.), unlike Farivar-Low's original unbounded-voltage case |

**Deprecated/outdated:** none — this is the first phase to bring this specific literature's
restriction mechanism into the codebase; nothing here replaces prior project code, it adds a new
formulation alongside the existing ones.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The existing thesis `v̂` copy is provably a *lower*-bound shadow (`v ≥ v̂`), making its upper bound non-binding in the over-voltage regime | Architecture Patterns — "Why the existing thesis exactness copy... does not close this gap" | MEDIUM-HIGH confidence, exact symbolic derivation (not `[ASSUMED]` in the weak sense) but NOT yet numerically spot-checked live; if wrong, the entire "why a new mechanism is needed" narrative needs revision, though the recommended `RestrictedBranchFlow` mechanism (which does not depend on this claim, only motivates it) would still work |
| A2 | Ipopt's MOI wrapper exposes usable `ConstraintDual` values at a `LOCALLY_SOLVED` point, so `dual(balance_p[...])` on an `ACPowerFlow` solve returns a meaningful local-KKT multiplier rather than erroring | Architecture Patterns — "Nonconvex-AC-dual fallback" | MEDIUM-HIGH; if Ipopt's dual read fails or returns garbage, the fallback (OVR-03/D-09/D-10) needs a different implementation (e.g. explicit KKT-multiplier extraction), which is a moderate rework, not a phase-blocking one, since `assert_solved!` already calls `dual=true` for every formulation including `ACPowerFlow` today |
| A3 | Nick, Cherkaoui, Le Boudec & Paolone's "AR-OPF" (IEEE TAC 2018) is a related, complementary literature pointer worth citing in the literate page's related-work paragraph | Alternatives Considered | LOW — sourced from a WebSearch summary only (title/authors/venue), full text not read this session; low risk since it is offered only as an optional citation, not a mechanism this research recommends implementing |
| A4 | The single-point (one AC-oracle solve) modification-gap measurement recipe for `ε` is an acceptable substitute for the paper's own 1000-sample Monte-Carlo estimate, for a "minimal validated rung" scoped to the single EXACT-04 fixture (D-04) | "Measuring ε" | MEDIUM — acceptable per D-03's explicit "no auto-tuning/bisection loop, measured default" instruction and D-04's single-fixture CI-gating scope, but the resulting `ε` is a *point estimate at one fixture*, not a network-wide worst case; if the researcher later runs `RestrictedBranchFlow` on a DIFFERENT fixture/scenario without re-measuring `ε` there, the guarantee (Theorem 2) may not transfer — this should be an explicit caveat in the literate page and the certificate's docstring |

## Open Questions

1. **(RESOLVED — plan 20-01's `<interfaces>` section instructs all new code/comments to say
   "the EXACT-04 fixture" / "the high-PV stress fixture", never "IEEE-13"; every subsequent plan
   (20-02..20-05) follows this convention, and plan 20-05's SUMMARY records the correction for
   STATE.md's next update.) The EXACT-04 fixture is NOT the 13-bus IEEE feeder, despite being
   called "IEEE-13" throughout CONTEXT.md/STATE.md/REQUIREMENTS.md/an existing test-file
   comment.**
   - What we know: `test/fixtures_phase4.jl:184`'s `high_pv_feeder()` is a purpose-built 3-bus
     radial fixture (root + 2 buses, `r=x=0.05` low-impedance branches); `pv_scale=1.2` on THIS
     fixture is the actual, empirically-found EXACT-04 operating point
     (`test/test_ac_oracle.jl:180-277`). A comment at `test/test_ieee123_admm.jl:139` refers to it
     as "Phase 15's EXACT-04 finding... on the IEEE-13 stress fixture," which is where the loose
     shorthand entered the project's own vocabulary and then propagated into v3.0's planning docs.
   - What's unclear: whether the user/roadmap intends to eventually ALSO validate on a genuine
     13-bus network (D-04's IEEE-123 "quarantined supporting evidence" language suggests the
     project's naming convention for "the other fixture" is by node-count, so a literal 13-node
     fixture may be a natural companion at some point) — but that is explicitly NOT the D-04-gated
     primary evidence for this phase.
   - Recommendation: the plan should target `Phase4Fixtures.high_pv_feeder()` exactly as it exists
     today, and use "the EXACT-04 fixture" or "the high-PV stress fixture" as the name in new
     code/docs rather than perpetuating "IEEE-13," to avoid a future contributor searching for a
     nonexistent 13-node network. Flag this correction to the user/STATE.md once the plan lands.

2. **(RESOLVED — plan 20-05 Task 1's "The Gan-Low condition" subsection live-computes a
   citable C1-margin-adjacent measurement on the EXACT-04 fixture's actual parameters, with an
   explicit honest-fallback narrative if the paper's exact `A₁·u₂` formula cannot be
   confidently re-derived from RESEARCH.md alone — per the Recommendation below.) Whether C1
   provably holds on the EXACT-04 fixture has not been numerically computed this session (only
   analytically argued).**
   - What we know: C1 for this fixture's 2-branch linear-chain topology reduces to a single
     nontrivial 2×2 matrix-vector inequality (`A₁·u₂ > 0`, per the paper's own linear-network
     worked example in their Fig. 5/eq. 7), depending on `r=x=0.05`, `v̲=0.9025` (`=0.95²`), and the
     upper bound on net active/reactive injection at the two non-root buses. Given the fixture's
     tiny impedances (`0.05 ≪ 1`) and modest injection magnitudes (order `0.1–1` p.u.), the
     correction term is analytically small relative to `1`, so C1 almost certainly holds with a
     large margin — consistent with the paper's own finding that C1 holds broadly even at high DG
     penetration.
   - What's unclear: the EXACT numeric value of the two upper-bound injection parameters `p̄, q̄`
     for this project's specific aggregator device mix (PV nameplate + battery discharge power +
     zero load, per bus) has not been extracted and plugged into the inequality this session.
   - Recommendation: this is a cheap (~10-line), high-value, LOW-risk verification task for the
     plan (not a research gap that blocks planning) — compute `A₁·u₂` numerically on the actual
     fixture parameters and confirm strict positivity; use it as a citable "C1 margin" number in
     the literate page (D-12), mirroring the paper's own Table III reporting convention. This is
     NOT required for the certificate (D-05's actual gate is the AC-oracle comparison), only for
     the literate page's theoretical-grounding narrative.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | TestItems 1.0.0 / TestItemRunner 1.1.5, discovered via `test/runtests.jl` |
| Config file | `test/runtests.jl` (TestItemRunner entrypoint; no separate config file) |
| Quick run command | A plain `julia --project=. -e '...'` script using `Test` (NOT TestItemRunner) that inlines the EXACT-04 fixture construction (mirrors `docs/literate/ac_oracle.jl`'s own inline-fixture pattern) and asserts the same behavioral claim as the corresponding `@testitem` — per-task verify commands in 20-01..20-04's PLAN.md files. **CORRECTION (checker revision 1, 2026-08-08):** the previously-documented `include("test/test_restricted_branch_flow.jl")` pattern is BROKEN — TestItemRunner is test-only (`--project=.` cannot resolve it) and even under `--project=test` a bare `include` of `@testitem` blocks executes ZERO tests (they only run via `TestItemRunner.runtests`/`@run_package_tests`). `@testitem` bodies can only be executed via the Full suite command below. |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (the real `test/runtests.jl` entrypoint; ~12–20 min per this project's documented baseline; run in background) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| OVR-01 | `RestrictedBranchFlow` solves EXACT-04 through `solve_welfare` without throwing PF-04, at `assert_socp_exact!`'s DEFAULT tolerance | unit/integration | direct Julia script invoking `solve_welfare(feeder, RestrictedBranchFlow(), aggs; ...)` and asserting `ctx.meta[:socp_maxgap] < 1e-5` (order-of-magnitude check, not a hard-pinned golden yet) | ❌ Wave 0 — new file `test/test_restricted_branch_flow.jl` |
| OVR-01 | Default-path regression: plain `ConvexBranchFlow` on EXACT-04-and-benign fixtures is byte-identical before/after this phase | regression | existing `test/test_ac_oracle.jl` EXACT-04 item + `test/test_exactness.jl`, re-run unmodified | ✅ existing, must stay green |
| OVR-02 | New certificate throws (default) or reports (`report=true`) correctly; own-derived tolerance documented | unit | new `@testitem` in `test_restricted_branch_flow.jl` asserting both polarities | ❌ Wave 0 |
| OVR-02 | Optimality-loss report is a named, non-summed field, computed against the `rtol_exact=1.0`-neutralized `ConvexBranchFlow` bound | unit | same new test file | ❌ Wave 0 |
| OVR-03 | `dual(balance_p[...])` on the restricted solve is a genuine convex dual (sanity: matches a hand re-derivation on the tiny fixture, or at minimum is finite and stable across repeated solves) | unit | new test file | ❌ Wave 0 |
| OVR-03 | Fallback triggers ONLY on certificate failure, never pre-emptively; carries `price_status` field; multi-start agreement report (2-start CI-gated, 3–5-start quarantined) | unit + quarantined | new test file (CI) + a quarantined script under `.planning/spikes/` or `scripts/` (mirrors Phase 19's D-13 quarantine pattern) | ❌ Wave 0 (both) |
| OVR-04 | Literate page re-executes the full mechanism live, no drift from `src/` | doc-build (Documenter) | `julia --project=docs docs/make.jl` (existing Documenter build convention — verify exact invocation against `docs/make.jl` before use) | ❌ Wave 0 — new `docs/literate/restricted_branch_flow.jl` |

### Sampling Rate

- **Per task commit:** the new file's own `@testitem`s via a direct `include`/small script under
  `--project=.` (fast, seconds — the EXACT-04 fixture is a 3-bus network).
- **Per wave merge:** full `julia --project=. -e 'import Pkg; Pkg.test()'` (background, ~12–20 min,
  confirms no cross-file regression — especially the default-path byte-identical check).
- **Phase gate:** full suite green before `/gsd:verify-work`, plus the literate page rebuilding
  cleanly (D-12 requires it to be live-executed, not merely present).

### Wave 0 Gaps

- [ ] `test/test_restricted_branch_flow.jl` — new file, covers OVR-01/02/03's unit-level checks
- [ ] The `v̂_GL` (Gan–Low lossless-shadow) post-processing function — needed both for measuring
  `ε` (used by the plan's calibration step) and optionally by the certificate's diagnostic report;
  should land in `src/models/ac_oracle.jl` alongside `recover_voltage_angles` or its own small file
- [ ] `docs/literate/restricted_branch_flow.jl` — new literate page (OVR-04)
- [ ] A quarantined multi-start (3–5 seed) fallback-agreement script, mirroring the
  `.planning/spikes/` or Phase 19 D-13 quarantine convention for the fuller evidence set

## Security Domain

Not applicable in the ASVS sense — this is a local, offline research/optimization library with no
network-facing input, no authentication surface, and no user-supplied untrusted data path (all
inputs are researcher-constructed Julia structs and seeded synthetic profiles). No new ASVS
category is implicated by this phase; V5 (input validation) is already covered project-wide by the
existing boundary guards (`ArgumentError` checks in `solve_welfare`, `assert_radial`, etc.), which
this phase does not weaken (the new formulation adds a bound, not a new input path).

## Sources

### Primary (HIGH confidence)

- Gan, L., Li, N., Topcu, U., Low, S.H., *"Exact Convex Relaxation of Optimal Power Flow in Radial
  Networks,"* IEEE Trans. Automatic Control 60(1):72–87, 2015; arXiv:1311.7170 — full PDF
  downloaded and converted to text (`pdftotext -layout`) and read directly this session; Theorem
  1/2, Lemma 1, Definitions 1–3, eqs. (1a-d), (5a-f), (6), (11), (12), (18), Fig. 9, Section IV,
  Section VI-C all quoted/paraphrased directly from the extracted text.
- `/home/pedro/programming/TSO-DSO/src/powerflow/ConvexBranchFlow.jl` — read in full; source of
  the exact `v̂`/`v`/`P`/`Q`/`l` variable definitions and the 3.33/3.43 recursions this research
  algebraically compares against Gan–Low's `v̂(s)`/`v` relationship.
- `/home/pedro/programming/TSO-DSO/src/powerflow/ACPowerFlow.jl` — read in full; confirms the AC
  oracle's exact variable stash (`(;v,P,Q,l)`, no `v̂`) and its `NLP()` routing through the
  unmodified `solve_welfare`.
- `/home/pedro/programming/TSO-DSO/src/models/exactness.jl`, `ac_oracle.jl`, `welfare_solve.jl` —
  read in full; source of the certificate/dispatch/throw-report patterns this research recommends
  mirroring.
- `/home/pedro/programming/TSO-DSO/test/fixtures_phase4.jl`, `test/test_ac_oracle.jl` — read in
  full; source of the corrected EXACT-04 fixture identity (Open Question 1) and the exact
  `pv_scale=1.2` operating point / documented finding.
- `/home/pedro/programming/TSO-DSO/.planning/research/PITFALLS.md` — read in full; Pitfalls 1–4
  directly informed the Common Pitfalls section and the certificate-design constraints.

### Secondary (MEDIUM confidence)

- Lee, D., Nguyen, H.D., Dvijotham, K., Turitsyn, K., *"Convex Restriction of Power Flow
  Feasibility Sets,"* arXiv:1803.00818 (IEEE Trans. Control of Network Systems) — found via
  WebSearch, abstract/framing read, not the full derivation; cited as a rejected general-topology
  alternative, flagged as worth revisiting for the Phase 23 meshed-network rung.
- Nick, M., Cherkaoui, R., Le Boudec, J.-Y., Paolone, M. — "AR-OPF" exact convex OPF for radial
  networks with transverse components (IEEE TAC 2018) — found via WebSearch (title/authors/venue
  only); offered as an optional literate-page citation, not independently verified this session.

### Tertiary (LOW confidence)

- None used as load-bearing claims; the WebSearch-only items above are explicitly flagged
  `[ASSUMED]`-adjacent (A3 in the Assumptions Log) rather than presented as verified fact.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new packages, confirmed directly against `Project.toml`.
- Architecture (the restriction mechanism itself): HIGH — verified against the paper's own PDF
  text, not a summary; the codebase mapping was cross-checked equation-by-equation.
- The "existing v̂ doesn't help" finding: MEDIUM-HIGH — solid derivation, pending a 5-minute live
  numeric spot-check (flagged explicitly, not hidden).
- Certificate/fallback design: HIGH for the *pattern* (directly mirrors existing, tested code in
  this repo); MEDIUM-HIGH for the Ipopt-dual-read assumption (A2), flagged.
- Pitfalls: HIGH — sourced directly from this project's own `research/PITFALLS.md`, written for
  this exact phase.

**Research date:** 2026-08-08
**Valid until:** No expiry driver — this is a literature-grounded mathematical mechanism, not a
fast-moving library API; re-validate only if the underlying `ConvexBranchFlow.jl`/thesis equations
are themselves revised.

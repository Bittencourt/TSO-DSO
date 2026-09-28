# Phase 26: Network & Device Model Correctness - Research

**Researched:** 2026-09-28
**Domain:** SOCP branch-flow convex-relaxation exactness theory (Gan–Low 2015), JuMP/Clarabel
modeling, battery temporal-coupling correctness, aggregator power-factor reactive draw.
**Confidence:** HIGH on the FIX-01/02 verdict and code loci (direct thesis-PDF + code read,
cross-checked); MEDIUM on the exact refactor shape (two viable mechanisms, tradeoffs below);
HIGH on FIX-03/04/05 mechanics; MEDIUM on downstream DLMP blast radius (structural risk
identified, exact fix left to the phase's own regression).

## Summary

This phase fixes four confirmed defects in the DEFAULT `ConvexBranchFlow` SOCP formulation and
two aggregatable device files. The thesis PDF itself (not just the code) was read at eqs.
3.29–3.45, and it resolves FIX-01's central question with unusual clarity: **the thesis's own
narrative text says the eq. 3.43/3.45 mechanism it adopts from Gan, Li, Topcu & Low (2015) makes
the original `v_i ≤ V²max` bound (eq. 3.35) "redundant"** — a claim that is only true if the
exactness-copy voltage `v̂ ≥ v`. But the *literal transcribed formula* for eq. 3.43 (which the
code faithfully reproduces) algebraically produces `v̂ ≤ v` — the reverse. This is a **defect in
the thesis's own eq. 3.43 algebra relative to its own stated Gan–Low-sourced claim**, not a
deliberate restriction, and not a code bug relative to the thesis text. The verdict is
unambiguous and well-sourced.

The fix itself has two viable shapes with different blast radius, discussed in detail below;
this research recommends the lower-risk one (a local per-branch sign flip inside the existing
`cpydrop` constraint, provably sufficient) while flagging the more literal one (reusing
`RestrictedBranchFlow`'s existing tree-based Gan–Low shadow-voltage machinery) as the
CONTEXT.md-literal alternative with materially higher cost. **Either choice changes the sign of
the `dual(:cpydrop)` term that `decompose_dlmp`'s `voltage` component and its empirically-derived
KKT coefficient depend on** — this is the single largest blast-radius risk in the phase and must
be re-derived and re-verified as part of FIX-01/02, not deferred to Phase 27 (which only touches
DLMP component *labels*, not the underlying sum-to-price identity).

FIX-03 (reverse thermal limit) is mechanically simple: the thesis's own eq. 3.37 uses the
`P_{j,i}, Q_{j,i}` reverse-flow variables, which are algebraically the "shadow" flow after
subtracting the branch's own loss — `(P − r·l, Q − x·l)` in the existing `P,Q,l` variables
already in scope. No new variables are needed; only a second cone per limited branch.

FIX-04 (battery SOC horizon) and FIX-05 (flexible-load reactive draw) are both real,
confirmed-by-code-read defects: `PVBattery`/`FourQuadBESS` only recurse `soc[1:T-1]→soc[t+1]`
(no `soc[T+1]`, so hour-`T` charge/discharge is free energy), and `Interruptible`/`Thermostatic`/
`Deferrable` return `p_inject` with **no** reactive component at all — the Aggregator currently
applies `tanφ` only to the inelastic `Pdc` term, never to flexible-load consumption. FIX-05 also
surfaces an architecture mismatch the CONTEXT.md decision doesn't fully resolve on its own:
`Interruptible` is currently a **self-injecting** (Variant-1) device that writes directly to
`ctx.residuals`, bypassing the Aggregator entirely and never appearing inside any production
`Aggregator.devices` list — see the dedicated section below.

**Primary recommendation:** implement FIX-01/02 as a local sign flip inside `ConvexBranchFlow`'s
existing `cpydrop` constraint (proven correct by telescoping-sum algebra below), preserve the
`:cpydrop` constraint container's shape for `decompose_dlmp` compatibility, extract a genuinely
shared helper only for the parts that are byte-for-byte identical between `ConvexBranchFlow` and
`RestrictedBranchFlow`, and treat `decompose_dlmp`'s `voltage`-component coefficient as a
value that MUST be numerically re-derived and re-certified in this phase (not assumed
unchanged).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FIX-01 | Documented verdict on thesis eq. 3.43 (relaxation vs. restriction), backed by a 3-bus heavy-load/low-voltage AC-feasible-but-SOCP-tests regression | Thesis PDF quote + citation to Gan–Low 2015 (ref [136]) resolved below; existing 3-bus fixture patterns identified (`fixtures_phase4.jl`, `test_pricing_fit.jl`) as templates, though none is the exact heavy-load/low-voltage regime needed |
| FIX-02 | Default `ConvexBranchFlow` copy satisfies v̂ ≥ v or is relabelled a restriction; bounds never redundant/tightening; docstring's load-bearing claim tested | Telescoping-sum proof of the local sign-flip fix; existing (wrong-direction) `test_restricted_branch_flow.jl` spot-check identified as a golden that MUST move |
| FIX-03 | Receiving-end apparent-power limit (3.37) on every limited branch, PV back-feed fixture shows it binding | Thesis PDF confirms 3.37 uses `P_{j,i},Q_{j,i}`; algebraically equal to `‖(P−r·l, Q−x·l)‖≤S̄` in existing variables — no new variables needed; `_SMAX_NO_LIMIT` filter pattern to reuse |
| FIX-04 | `PVBattery`/`FourQuadBESS` link SOC across the whole horizon (`soc[T+1]`), optional terminal condition | Confirmed by code read: `soc[t+1]` recursion only for `t=1:T-1`; `mpc_window.jl`'s `soc[H]` terminal target and its `H==1` guard identified as needing to move to `soc[H+1]` |
| FIX-05 | Flexible loads (interruptible/thermostatic/deferrable) draw `q=p·tanφ` into `:Rq` | Confirmed by code read: none of the three devices carries any reactive term; `Interruptible`'s Variant-1 (self-injecting) status vs. the "Aggregator sole writer" requirement is a real architectural gap, detailed below |

</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| SOCP exactness-copy direction (FIX-01/02) | Model / power-flow formulation (`src/powerflow/`) | Pricing (`src/pricing/dlmp.jl` consumes the dual) | The copy is a modeling-layer correctness property; its dual is consumed one layer up by pricing, which is why the blast radius crosses tiers |
| Reverse thermal limit (FIX-03) | Model / power-flow formulation | — | Pure additive constraint on existing variables, no other tier touched |
| Battery SOC horizon linking (FIX-04) | Device layer (`src/devices/`) | Model assembly (`mpc_window.jl`, `stochastic_welfare.jl` reference `soc[H]`/`soc[1]`) | Device owns its own temporal recursion; the MPC/stochastic wrappers reference specific indices that shift when the horizon grows by one |
| Flexible-load reactive draw (FIX-05) | Aggregator roll-up (`src/devices/Aggregator.jl`) | Device layer (each device must expose enough for the Aggregator to classify it) | CONTEXT.md's "Aggregator remains sole writer" decision places this capability at the roll-up tier, not the device tier — this has architectural consequences for `Interruptible` (see below) |
| DLMP decomposition consistency after FIX-01/02 | Pricing (`src/pricing/dlmp.jl`) | Model / power-flow formulation | Downstream consumer of a dual whose sign this phase changes; not itself a FIX-01..05 target but its assertion will break without care |

This is a single-process Julia research library (no browser/API/CDN tiers apply).

## Standard Stack

No new external packages are introduced by this phase — it is a pure correctness fix within the
existing `src/powerflow/`, `src/devices/`, `src/models/` modules using JuMP + Clarabel + HiGHS +
Ipopt, all already pinned in `Project.toml` per the project's CLAUDE.md stack table. No
`## Package Legitimacy Audit` section is included — no packages are installed in this phase.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Gan–Low loss-free "shadow voltage" recursion | A third independent tree-walk/BFS implementation of the subtree-loss accumulation | `src/models/ac_oracle.jl`'s `recover_lossfree_shadow_voltage` (post-solve) and `src/powerflow/RestrictedBranchFlow.jl`'s inline `v̂_GL` construction (model-time) — **already two near-duplicate implementations of the identical math** | A third copy (inside `ConvexBranchFlow`, if Option B below is chosen) would be the third hand-rolled copy of the same BFS/reverse-accumulation logic; extract ONE shared helper instead |
| AC feasibility oracle for the FIX-01 regression | A hand-solved AC power-flow check | `src/powerflow/ACPowerFlow.jl` (Ipopt-backed `AbstractPowerFlow` already wired into `solve_welfare`) | Already exists, already the project's designated AC-feasibility ground truth |
| Reverse apparent-power cone (FIX-03) | A new `P_{j,i}`/`Q_{j,i}` pair of variables per branch | The existing `P[b,t]`, `Q[b,t]`, `l[b,t]` — the receiving-end power is algebraically `P[b,t] - r*l[b,t]`, `Q[b,t] - x*l[b,t]` | Thesis 3.37's `P_{j,i}` is definitionally the negative of the receiving-end power; introducing new variables would duplicate state that is already fully determined |

**Key insight:** every mechanism this phase needs (loss-free shadow voltage, AC oracle, reverse
power) already exists in the codebase in at least one place. The main engineering risk is
duplicating it a second or third time instead of extracting a shared helper.

## FIX-01/02 — The eq. 3.43 verdict (HIGH confidence)

### What the thesis PDF actually says

Direct `pdftotext` extraction of `docs/references/86. Tesis Doctoral Juan Pablo Palacios (2).pdf`
around eqs. 3.40–3.45 (page ~84, Capítulo 3):

```
0 = P̂_{i,j}[t] − p_{ag_j}[t] − Σ_{m:j→m} P̂_{j,m}[t]                          (3.40)
0 = Q̂_{i,j}[t] − q_{ag_j}[t] − Σ_{m:j→m} Q̂_{j,m}[t]                          (3.41)
v̂_j[t] = v̂_i[t] − 2(r_{i,j} P̂_{i,j}[t] + x_{i,j} Q̂_{i,j}[t])                  (3.42)

"Se puede demostrar que P̂_{i,j}[t] ≈ P_{i,j}[t] + r_{i,j} l_{i,j}[t], y
Q̂_{i,j}[t] ≈ Q_{i,j}[t] + x_{i,j} l_{i,j}[t], entonces las ecuaciones (3.40)-(3.42)
pueden presentarse como una única ecuación (3.43)."

v̂_j[t] = v̂_i[t] − 2{ r_{i,j}(P_{i,j}[t] + r_{i,j} l_{i,j}[t])
                     + x_{i,j}(Q_{i,j}[t] + x_{i,j} l_{i,j}[t]) }             (3.43)
```

This is [VERIFIED: thesis PDF] EXACTLY what `ConvexBranchFlow.jl`'s `cpydrop` constraint
implements today (`v̂[to] == v̂[from] - 2*(r*(P + r*l) + x*(Q + x*l))`) — [CONFIRMED: code read,
`src/powerflow/ConvexBranchFlow.jl` cpydrop block]. **The code is thesis-literal.** The `+r·l`,
`+x·l` inside the parentheses is the thesis's own transcribed formula.

Immediately after presenting (3.43)–(3.45), the thesis text says [VERIFIED: thesis PDF, same
page]:

> "La relajación convexa de GLB-OPT se denomina GLB-CVX... Cabe indicar que después de imponer
> (3.45), las restricciones del tipo `v_i[t] ≤ V²max` en (3.35) se vuelven **redundantes** [136]."

Translation: *"After imposing (3.45) [the bound `V²min ≤ v_i, v̂_i ≤ V²max` on BOTH `v` and
`v̂`], the constraints of the form `v_i ≤ V²max` in (3.35) become **redundant**."* Reference
[136] is confirmed [VERIFIED: thesis PDF bibliography, line 7954] to be:

> L. Gan, N. Li, U. Topcu, and S. H. Low, "Exact Convex Relaxation of Optimal Power Flow in
> Radial Networks," *IEEE Trans. Automat. Contr.*, vol. 60, no. 1, 2015.

— i.e. **Gan–Low 2015**, the exact paper CONTEXT.md and this phase's research asks name. The
thesis explicitly states (page ~83, just before 3.43) that it "adopts an approach proposed in
[136]" to guarantee exactness.

### The verdict

The claim "`v ≤ V²max` becomes redundant after imposing `v̂ ≤ V²max`" is **only true if
`v̂ ≥ v`** (if `v̂` upper-bounds `v`, then `v ≤ v̂ ≤ V²max` makes the separate `v ≤ V²max`
constraint implied). This is the thesis's **own stated intent**, sourced to Gan–Low, on the same
page as eq. 3.43. But the literal formula 3.43 as transcribed produces the **opposite**
direction. Proof (general, for any branch on the path from the root):

Let the drop recursions be:

```
v_j  = v_i − 2(r·P + x·Q) + (r²+x²)·l                     (3.33, true drop)
v̂_j  = v̂_i − 2(r·(P + a·r·l) + x·(Q + a·x·l))              (parametrized copy, a = sign of the loss term)
```

Since `v_root = v̂_root` (both fixed at the reference `1.0`), subtracting and telescoping along
the unique root→j path on a radial feeder:

```
v_j − v̂_j = (1 + 2a) · Σ_{b ∈ path(root,j)} (r_b² + x_b²) · l_b
```

With `l_b ≥ 0` (a JuMP variable bound already present) and `r_b, x_b > 0`:

- `a = +1` (current code, thesis-literal): coefficient `= 3 > 0` ⇒ `v_j ≥ v̂_j` ⇒ **`v̂ ≤ v`** —
  the REVERSE of Gan–Low. This matches the quality-audit memory's empirical finding exactly
  (`v̂ ≤ v` measured on a 3-bus heavy-load probe, and the probe was AC-feasible but the SOCP was
  infeasible — i.e. `v̂ ≥ V²min` acts as a **restriction** under this sign, not a relaxation).
- `a = −1` (proposed fix — see Option A below): coefficient `= −1 < 0` ⇒ `v_j ≤ v̂_j` ⇒
  **`v̂ ≥ v`** — the Gan–Low direction, matching the thesis's own stated redundancy claim.

**Conclusion for the docs page (FIX-01 deliverable):** this is a **defect in the thesis's own
eq. 3.43 algebra**, inconsistent with the thesis's own adjacent claim (citing Gan–Low) that
`v ≤ V²max` becomes redundant. The current code is a faithful, byte-for-byte implementation of
the (defective) literal formula — so it is "thesis-literal" in the narrow sense CONTEXT.md
already established, and should be retained as an explicit, clearly-labelled opt-in **restriction**
variant per the locked decision. [VERIFIED: thesis PDF text + citation cross-check] — this claim
does not need further validation; the algebra above is a direct proof from the thesis's own
fixed-point (`v_root = v̂_root`) and variable bound (`l ≥ 0`), not an inference from training data.

### Redundant vs. load-bearing bound, both directions (for the docstring test, FIX-02)

- **Current (reversed) code, `v̂ ≤ v`:** `v̂ ≤ V²max` is redundant (implied by `v ≤ V²max` since
  `v̂ ≤ v ≤ V²max`); `v̂ ≥ V²min` is the genuine, load-bearing (restrictive) bound — this is
  exactly what the quality-audit memory's 3-bus infeasibility finding demonstrates.
- **Corrected (Gan–Low) direction, `v̂ ≥ v`:** `v̂ ≥ V²min` is redundant (implied by
  `v ≥ V²min` since `v̂ ≥ v ≥ V²min`); `v̂ ≤ V²max` is the genuine, load-bearing (exactness-driving)
  bound — this matches `ConvexBranchFlow`'s EXISTING docstring language ("bounding `v̂ ≤ V²max`
  ... is what drives the cone tight — this is the load-bearing half of the exactness copy, not
  decoration"), which was already written assuming the correct direction even though the code
  implemented the wrong one. FIX-02's "docstring's claimed load-bearing bound" test should assert
  exactly this asymmetry (which bound binds, in which direction) at the solution of a fixture
  with active voltage headroom.

### Two viable fix mechanisms — pick one, document the tradeoff for the planner

**Option A — local per-branch sign flip (RECOMMENDED, lower blast radius).** Change the
`cpydrop` constraint's `P̂`/`Q̂` substitution from `P + r·l`, `Q + x·l` to `P − r·l`, `Q − x·l`
(i.e. `a = -1` in the proof above). This is a **one-line-per-term** change inside the EXISTING
`@constraint(m, cpydrop[b,t], v̂[to,t] == v̂[from,t] - 2*(r*(P[b,t] - r*l[b,t]) + x*(Q[b,t] -
x*l[b,t])))`. It:
  - Is proven (above) to achieve `v̂ ≥ v` at every bus, unconditionally (no fixture-specific
    tuning, no free parameter — matches the project's "no auto-tuning/bisection loop" convention
    already established for `RestrictedBranchFlow`).
  - Preserves the `v̂[j,t]` variable and the `:cpydrop[b,t]` registered constraint container's
    EXACT shape (same indices, same per-branch semantics) — so `ctx.meta[:pf_vars]`,
    `MeshedFlow`'s delegation, `RestrictedBranchFlow`'s delegation, `DsoOpt.jl`'s ADMM reuse, and
    `decompose_dlmp`'s `ctx.constraints[:cpydrop]` lookup all continue to structurally resolve —
    only the NUMERIC VALUE of `dual(:cpydrop[b,t])` changes.
  - Is NOT the literal Gan–Low Definition-3 "loss-free shadow voltage" (which requires
    subtree-wide loss accumulation, per Option B) but achieves the property that actually matters
    for the exactness-copy TRICK (`v̂` is an affine over-estimate of `v` whose own upper bound,
    once imposed, forces the SOC relaxation tight) — the same purpose the thesis's own text
    describes.

**Option B — reuse `RestrictedBranchFlow`'s tree-based `v̂_GL` mechanism as the new default
(the literal CONTEXT.md phrase "matching the form already in `RestrictedBranchFlow`").** This is
the LITERAL Gan–Low Definition-3 quantity: a rooted BFS tree, reverse-BFS subtree-loss
accumulation (`LossInclR`/`LossInclX`), then a forward recursion `v̂_GL[i] = v̂_GL[parent] −
2(r·P̌ + x·Q̌)` with `P̌ = P − LossInclR[i]` (the WHOLE downstream subtree's accumulated loss, not
just the branch's own `r·l`) — see `src/powerflow/RestrictedBranchFlow.jl` lines 226–276 and its
near-identical twin `recover_lossfree_shadow_voltage` in `src/models/ac_oracle.jl` (post-solve
version of the same math). This is a strictly TIGHTER bound than Option A's local flip (it is
the literal counterfactual "zero loss everywhere downstream" voltage), and would make
`ConvexBranchFlow`'s default v̂ identical in kind to what `RestrictedBranchFlow` already builds
for its OWN restriction purpose. Costs:
  - Requires introducing a rooted-tree traversal into `ConvexBranchFlow.contribute!`, which today
    has NO tree-order dependency anywhere (its whole design point, per the MeshedFlow research
    note, is being graph-generic / tree-order-free) — this is architecturally in tension with
    keeping `ConvexBranchFlow` usable on `MeshedFeeder` topologies (which have no unique
    root→j tree in general and are exactly why `MeshedFlow.jl`'s header explains loop-closure is
    deferred to a post-solve certificate rather than a model-time constraint).
  - `v̂` would need to become "a variable EQUAL to a per-timestep tree expression" (an added
    equality constraint per bus/time on top of the existing bound constraints), materially
    changing the constraint shape `decompose_dlmp` and the DLMP dual derivation depend on — a much
    larger, structurally different consumer-side change than Option A's coefficient-only flip.
  - This would be the **third** near-duplicate implementation of the identical BFS/loss-accumulation
    logic in the codebase (after `ac_oracle.jl` and `RestrictedBranchFlow.jl`) unless a shared
    helper is extracted FIRST — which the "Share ONE cpydrop helper" CONTEXT.md decision text
    seems to anticipate, but that helper would need to be MeshedFeeder-safe (or `ConvexBranchFlow`
    would need to special-case radial vs. meshed feeders, which none of its code does today).

**Recommendation for the planner:** default to Option A. It provably satisfies FIX-02's stated
property (`v̂ ≥ v`, never redundant/tightening in the wrong direction), keeps the phase's blast
radius to a coefficient-sign change plus a DLMP coefficient re-derivation, and does not
reintroduce a tree-order dependency into a formulation whose graph-genericity `MeshedFlow`
explicitly relies on. If the planner or a later reviewer decides Option B is required to
literally match "the form already in `RestrictedBranchFlow`," budget for: (1) extracting a
shared, `MeshedFeeder`-compatible tree-helper (or explicitly scoping the new default to radial
feeders only, which would need its own decision/flag), and (2) a full rewrite of
`decompose_dlmp`'s `voltage` component derivation, not just a coefficient tweak. Either way, the
"share ONE cpydrop helper between `ConvexBranchFlow` and `RestrictedBranchFlow`" decision is
satisfiable literally only under Option B, or satisfiable in SPIRIT under Option A by extracting
the `P̂ = P − r·l, Q̂ = Q − x·l` substitution into one named function both files call (since
`RestrictedBranchFlow` currently DOES NOT reuse `ConvexBranchFlow`'s `cpydrop` math for its own
`v̂_GL` construction — it independently reimplements a related-but-different tree-based
formula). Flag this naming/sharing tension explicitly for the plan-checker.

### Regression fixture guidance

An existing 3-bus low-impedance/high-PV fixture family already exists (`fixtures_phase4.jl`'s
"EXACT-04" fixture, referenced by `test_ac_oracle.jl`, `test_restricted_branch_flow.jl`,
`test_ieee123_admm.jl`) but it stresses the **upper** voltage bound (overvoltage from PV
back-feed) — the OPPOSITE regime from what FIX-01 needs (a **heavy-load, low-voltage** feeder
that is AC-feasible but SOCP-infeasible under the reversed/thesis-literal copy). A NEW 3-bus
fixture is needed with heavy load (not PV) driving voltage toward `V²min`; `test_pricing_fit.jl`
and `fixtures_phase4.jl` are the closest existing templates for the 3-bus construction pattern
(`Feeder`/`Branch` literal construction, per-unit bounds) to copy from, not the EXACT-04 fixture
itself. [ASSUMED: exact impedances/loads are Claude's discretion per CONTEXT.md] — the planner
must choose specific numbers that make the AC solve feasible with `v` near `V²min` while the
literal thesis-form SOCP (with `v̂ ≥ V²min` binding as a restriction) goes infeasible; this needs
empirical tuning at execution time, not a priori derivation.

### Golden that WILL move — identified concretely

`test/test_restricted_branch_flow.jl` line 20 has an existing `@testitem` titled *"v ≥ v̂
sign-relationship spot-check on the EXACT-04 fixture (RESEARCH Assumption A1)"* — this test
currently encodes and asserts the CURRENT (wrong, thesis-literal) `v ≥ v̂` relationship as
ground truth. Once the default flips, this specific assertion is EXPECTED to reverse. This is a
concrete, locatable golden the phase must re-derive and explain in its SUMMARY (not just an
abstract risk) — [VERIFIED: code read, exact file:line, test title].

## FIX-01/02 → DLMP blast radius (MEDIUM-HIGH risk, must be handled in-phase)

`src/pricing/dlmp.jl`'s `decompose_dlmp` reads `dual(cpydrop[b,t])` directly, using an
EMPIRICALLY-DERIVED (not analytically proven, per the file's own header comment: "derivation...
empirically certified to machine precision on the 2-bus / IEEE-13 / high-PV solves") KKT
coefficient:

```julia
volt_b[b, t] = -2 * r * (dual(vdrop[b, t]) + dual(cpydrop[b, t]))   # 3.33/3.43 (voltage)
```

and a hard hard-tolerance assertion that `energy + loss + congestion + voltage ≈
dual(:balance_p)` (in `decompose_dlmp`, `worst_res <= tol` or it `error()`s). This formula's
`+dual(cpydrop)` sign was derived against the CURRENT (thesis-literal, `a=+1`) `cpydrop`
constraint. Changing `cpydrop`'s coefficient (Option A: `a: +1 → -1`) changes the KKT
relationship between the branch-flow stationarity condition and `dual(:cpydrop)` — the
coefficient in `volt_b`'s formula (currently `+1`) may need to become `-1`, or some other
re-derived value; **this cannot be assumed unchanged**. Under Option B the entire mechanism
disappears (`v̂` would no longer be a simple per-branch recursive variable with one dual per
branch) and `decompose_dlmp`'s `voltage` component would need a structural rewrite, not a
coefficient change.

**Concretely, this phase must:**
1. After implementing FIX-01/02, run `test/test_dlmp.jl`, `test/test_pricing_dlmp.jl` and
   re-derive/re-verify (empirically, the same way the current formula was derived — machine-
   precision residual check on a solved fixture) the correct sign/coefficient for `dual(cpydrop)`
   in `volt_b`.
2. Treat `decompose_dlmp`'s hard sum-to-price assertion as a certificate that will EITHER (a)
   continue to pass with a re-derived coefficient (if Option A), or (b) require restructuring
   (if Option B) — either outcome is in-scope for THIS phase's golden-policy obligation ("every
   golden this phase's fixes move is re-derived in-phase"), not Phase 27's (which is scoped to
   the "loss"/"voltage" NAMING, not the underlying sum-to-price correctness).
3. `src/admm/DsoOpt.jl` reuses `cpydrop` verbatim (comment: "VERBATIM ConvexBranchFlow reuse: P,
   Q, v, v̂, l, cone, vdrop, cpydrop, smax") — the ADMM per-hour SOCP subproblem inherits whichever
   fix is chosen automatically (good: no separate ADMM-side fix needed), but ADMM convergence
   behavior (iteration count, the existing IEEE-13 "knife-edge canary" pinned in
   `test/test_experiments.jl` per the `background-suite-orphan-race` memory) may shift and should
   be re-measured, not assumed stable.
4. `src/models/stochastic_welfare.jl` registers the SAME nine named containers including
   `:cpydrop` per scenario copy (line 296) — the fix propagates there too via `contribute!`
   delegation, no separate code change expected, but its own DLMP-adjacent tests
   (`test_stochastic_welfare.jl`, `test_pricing_dlmp.jl`) are in the blast radius.

## FIX-03 — Reverse thermal limit (HIGH confidence, low risk)

Thesis PDF confirms [VERIFIED: thesis PDF, page ~82]:

```
S²max,ij ≥ P_{i,j}[t]² + Q_{i,j}[t]²         (3.36, forward/sending-end)
S²max,ij ≥ P_{j,i}[t]² + Q_{j,i}[t]²         (3.37, reverse/receiving-end)
```

`P_{j,i}` (flow measured from `j` back to `i`) is definitionally the negation of the
receiving-end power at `j`, which in the branch-flow model is `P_{i,j} − r_{ij}·l_{ij}` (the
sending-end power minus the branch's own loss). Since the SOC/apparent-power cone only depends
on the SQUARED magnitude, `‖(P_{j,i}, Q_{j,i})‖ = ‖(P − r·l, Q − x·l)‖` exactly, confirming
CONTEXT.md's stated formula is a correct restatement of the literal thesis equation in the
existing `P[b,t]`, `Q[b,t]`, `l[b,t]` variables — no new decision variables needed, only a
second `SecondOrderCone()` constraint per limited branch, gated by the SAME `B[b].smax <
_SMAX_NO_LIMIT` filter predicate `ConvexBranchFlow`'s existing forward `smax` cone already uses
(`src/units/PerUnit.jl`'s `SMAX_NO_LIMIT = 99.0` sentinel, single source of truth, also aliased
in `src/data/ieee13.jl` as `IEEE13_INTERIOR_SMAX`).

Per CONTEXT.md this must be added to every formulation with a sending-end limit: `ConvexBranchFlow`
(direct), `MeshedFlow` (inherits automatically via its full delegation to `ConvexBranchFlow`
— no separate code needed, confirmed by reading `MeshedFlow.jl`'s `contribute!`, which is a pure
one-line delegation), and `RestrictedBranchFlow` (also inherits automatically via its own
delegation to `ConvexBranchFlow.contribute!` at line 175 — again no separate code expected).
`LinDistFlow` (`l ≡ 0`) is explicitly excluded by CONTEXT.md since the reverse cone is then
identical to the forward one.

Register the new cone (e.g. `:smax_rev`) via `register_constraint!` following the exact pattern
of the existing `:smax` container, for potential future dual consumption (not required by this
phase's success criteria, but consistent with the codebase's "every network constraint gets
registered" convention — see the `:opfm_shadow_voltage` precedent in `RestrictedBranchFlow.jl`,
which registers even though "this plan's certificate does not require it").

### PV back-feed fixture

CONTEXT.md requires: "PV back-feed through a limited branch; assert receiving-end limit active
(nonzero dual) while sending-end is slack." A limited branch under PV back-feed has REVERSED
active-power flow direction (power flows child→parent), so `P[b,t] < 0` while `l[b,t] ≥ 0` still
(current magnitude squared), making the receiving-end quantity `P − r·l` have LARGER magnitude
than the sending-end `P` alone (since both terms are negative-reinforcing under reverse flow with
positive `r`, whereas under forward flow they partially cancel) — this is the qualitative reason
receiving-end limits bind preferentially under back-feed and is worth stating explicitly in the
fixture's design rationale/test comment.

## FIX-04 — Battery SOC horizon linking (HIGH confidence)

Confirmed by direct code read of both `src/devices/PVBattery.jl` (lines 288–297) and
`src/devices/FourQuadBESS.jl` (lines 328–338): both declare `soc = @variable(m, [t=1:T],
lower_bound=Emin, upper_bound=Emax)` and the recursion `@constraint(m, [t=1:(T-1)], soc[t+1] ==
soc[t] + (η·p_ch[t] - p_dch[t]/η)·Δt)` — **only for `t = 1:(T-1)`**, so `p_ch[T]`/`p_dch[T]`
never appear in ANY SOC constraint. This is [CONFIRMED: code read] the free-energy defect the
quality-audit memory describes.

**Fix:** declare `soc = @variable(m, [t=1:(T+1)], lower_bound=Emin, upper_bound=Emax)`, IC
`soc[1] == soc0` (unchanged), recursion `@constraint(m, [t=1:T], soc[t+1] == soc[t] +
(η·p_ch[t] - p_dch[t]/η)·Δt)` now covering `t=1:T` (i.e. INCLUDING hour `T`, closing on
`soc[T+1]`). No default terminal condition (bounds only, per CONTEXT.md); optional
`soc_terminal` keyword (`nothing` default | a value | `:cyclic` meaning `soc[T+1] ≥ soc0`).

### Downstream index-shift consequences (must be updated together)

1. **`src/models/mpc_window.jl` line 243:** `@constraint(model, v.soc[H] == term)` — the
   terminal-condition target must become `v.soc[H+1]` once the device's own `soc` vector is
   `1:(H+1)` long. This is [CONFIRMED: code read] exactly the line CONTEXT.md names.
2. **The `terminal_soc && H == 1` guard (lines 140-149, "WR-03"):** the guard exists TODAY
   because at `H=1`, `soc[H] == soc[1]` collides with the IC `soc[1] == soc0` on the SAME index —
   a genuine double-pin. Once the terminal target moves to `soc[H+1]` (a DIFFERENT index from
   `soc[1]` even at `H=1`), this collision disappears structurally — CONTEXT.md's "drops the
   WR-03 `H==1` special case" is architecturally sound and should be implemented as REMOVING the
   guard's throw, not just leaving it in place unnecessarily. Verify with a new `H=1,
   terminal_soc=true` regression that it now solves rather than throws.
3. **`src/models/stochastic_welfare.jl`:** per-scenario copies each carry "their own `soc[1] ==
   soc0` initial condition plus the recursion" (comment at line 374-375) — since this file drives
   `contribute!(d, ctx; T)` verbatim per device per scenario (no separate SOC-indexing code of
   its own found by direct grep), the fix should propagate automatically; however, its STOCH-03
   out-of-sample harness (`StochasticOosHarness`, same file, ~line 475-495) explicitly says it
   pins `p_ch`/`p_dch` per-step rather than `soc` directly "because... App. C dominance already
   forces `p_ch·p_dch=0`" — audit this comment's continued validity once `soc[T+1]` exists (it
   should still hold, since the argument is about `p_ch`/`p_dch`, not the SOC vector length, but
   confirm no code reads `soc[T]` as a terminal/output value anywhere in this file).
4. **Any test reading `value.(soc)` and asserting its length equals `T`** (grep `test/` for
   `length(soc)`, `soc[end]`, `size(soc)` before assuming byte-identical shapes) will need
   updating — a per-test audit at execution time is required since this research did not
   exhaustively enumerate every such assertion (do this as an execution-time grep, not from this
   document).

### Regression fixture (FIX-04 success criterion 4)

"`soc0 = Emin` with incentive to discharge at hour `T` → zero discharge (or infeasible)." Since
`soc[T+1] ≥ Emin` will now be enforced and the recursion at `t=T` makes `p_dch[T]` reduce
`soc[T+1]` below `soc[T]`, starting at `soc0=Emin` with `soc` monotonically bounded below makes
ANY `p_dch[T] > 0` immediately infeasible UNLESS `p_ch` earlier in the horizon has built up
headroom — the test should confirm the OPTIMAL solution (not just a feasibility probe) drives
`p_dch[T] → 0` when there is no such headroom and a genuine App.-C-style discharge incentive
(e.g. a high λ at hour T) exists, distinguishing "the constraint prevents it" from "the model
never wanted to anyway."

## FIX-05 — Flexible-load reactive draw (HIGH confidence on the defect; architectural gap on the mechanism)

### Confirmed defect

Direct code read of `Interruptible.jl`, `Thermostatic.jl`, `Deferrable.jl`: none returns or
writes anything reactive. `Thermostatic`/`Deferrable` (Variant-2, aggregatable) return `(;
vars, p_inject, utility)` with NO `q_inject` key at all (unlike `FourQuadBESS`, which does).
`Aggregator.contribute!`'s reactive write is currently:

```julia
add_to_residual!(ctx, :Rq, agg.bus, t, -Pdc_param[t] * tanφ + q_inject[t])   # (3.23) + D-10
```

— `tanφ` is applied ONLY to the inelastic `Pdc` term; `q_inject[t]` sums ONLY devices that
explicitly opt in via the `hasproperty(res, :q_inject)` check (today, only `FourQuadBESS`). No
mechanism today applies `tanφ` to a flexible LOAD's own `p_inject` (which is negative,
representing consumption) — this is [CONFIRMED: code read] the FIX-05 defect exactly as the
quality-audit memory and REQUIREMENTS.md describe.

### Recommended mechanism

CONTEXT.md's decision ("Aggregator applies its existing `tanφ` to flexible-load... `p_inject`
into `:Rq`... Optional per-device φ override field") implies the Aggregator, not each device,
computes the reactive contribution. This requires the Aggregator to be able to **classify** a
member device as "a flexible load whose consumption should draw reactive power via `tanφ`" vs.
"a DER whose active injection should NOT" (PV/battery are active-only per Assumption A3 — this
is why the fix must NOT blanket-apply `tanφ` to every device's `p_inject`, only to load-type
devices). The cleanest mechanism consistent with the codebase's existing `hasproperty`-based
optional-field pattern (used for `q_inject`) is a parallel trait function, e.g.:

```julia
# Default: a device does not draw power-factor reactive power.
is_flexible_load(::AbstractDevice) = false
is_flexible_load(::Interruptible) = true
is_flexible_load(::Thermostatic)  = true
is_flexible_load(::Deferrable)    = true
```

with an OPTIONAL per-device `φ` override resolved via `hasproperty(d, :φ) ? d.φ : agg.φ`
(mirroring the existing optional-field discipline `q_inject` already establishes — "a device
lacking the field contributes zero" becomes "a device lacking `φ` falls back to the aggregator's
`φ`"). The Aggregator's roll-up loop then becomes, for each member device `d` returning `res`:

```julia
if is_flexible_load(d)
    φ_used = hasproperty(d, :φ) ? d.φ : agg.φ
    for t in 1:T
        q_inject[t] += res.p_inject[t] * reactive_factor(φ_used)
    end
end
```

Sign check: `res.p_inject[t]` is NEGATIVE for a load (consumption), and `reactive_factor(φ) =
tan(arccos φ) > 0`, so the product is negative — consistent with the EXISTING `-Pdc_param[t] *
tanφ` sign convention for inelastic demand (both are negative, i.e. both represent reactive
power drawn/consumed, matching thesis 3.23's own sign).

**A per-device test per CONTEXT.md** ("One test per device type asserting its `:Rq` contribution
== `p·tanφ` at the solution") is straightforward for `Thermostatic`/`Deferrable` since they are
already aggregatable and already appear inside production `Aggregator` fixtures
(`materialize.jl`'s `_house_aggregator`/`_ieee8500_house`, both build `Aggregator(bus, φ, [therm,
defer, batt], Pdc)`).

### Architectural gap: `Interruptible` is NOT currently aggregatable

`Interruptible.jl`'s `contribute!` is [CONFIRMED: code read] a **Variant-1 self-injecting**
device (per `AbstractDevice.jl`'s own documented "TWO variants" contract): it calls
`add_to_residual!(ctx, :Rp, d.bus, t, -p[t])` and `add_to_objective!(ctx, ...)` DIRECTLY, and
returns a bare `p::Vector{VariableRef}` — NOT a `(; vars, p_inject, utility)` NamedTuple.
Consequently:

- `Aggregator.contribute!` **cannot** currently accept an `Interruptible` in its `devices` list —
  `res.p_inject` would immediately error (`Vector` has no such property), and even if it did not
  error, the device would ALREADY have written to `:Rp` itself, causing a double-write.
- A grep of the entire `src/` tree confirms `Interruptible` is used standalone
  (`src/models/linear_solve.jl`, comment: "no Phase-2 device injects reactive power
  (Interruptible carries no...)") and NEVER inside a production `Aggregator` — the only
  `Aggregator(...)` construction sites in `src/experiments/materialize.jl` use `[therm, defer,
  batt]`, never `Interruptible`.
- `Interruptible` is exercised in exactly four test files
  (`test/test_device.jl`, `test/test_linear_solve.jl`, `test/test_conformance.jl`,
  `test/test_planning_oracle.jl`) plus one doc-literate file, all treating it as standalone/
  self-injecting.

**This means CONTEXT.md's phrase "Aggregator remains the SOLE `:Rp`/`:Rq` writer" is a
statement about the DESIRED end state that `Interruptible` does not currently satisfy at all** —
it is not "Aggregator is sole writer, and now also handles Interruptible's reactive term"; it is
"Aggregator is not even in the loop for Interruptible today." The planner has two honest options,
both consistent with the letter of FIX-05 (which is scoped by its own acceptance criterion to "a
per-device test showing... `:Rq`," which only requires the property be DEMONSTRATED, not that
`Interruptible`'s production self-injecting usage be migrated):

**Option 1 (lower blast radius):** leave `Interruptible` as a self-injecting Variant-1 device for
its EXISTING standalone call sites, and satisfy FIX-05's `Interruptible` obligation by
constructing a MINIMAL test-only `Aggregator` wrapping a NEWLY-converted-to-Variant-2
`Interruptible` (i.e., convert `Interruptible.contribute!` to return `(; vars, p_inject,
utility)` like `Thermostatic`/`Deferrable` INSTEAD of self-injecting) — this is the conversion
CONTEXT.md's "Aggregator remains sole writer" language actually requires literally, and the
lower-risk sub-option is to do the conversion but audit/update the (small: 4 files) set of
existing standalone call sites rather than trying to preserve both variants simultaneously
(which would require a flag/dual-mode device, adding complexity `AbstractDevice.jl`'s own
docstring explicitly frames as an either/or "TWO variants" choice per device type, not a hybrid).

**Option 2 (larger, likely out of scope):** keep `Interruptible` self-injecting and give it its
OWN direct `:Rq` write (bypassing the Aggregator for this one device), which technically
satisfies "loads draw `q=p·tanφ` into `:Rq`" but directly CONTRADICTS the CONTEXT.md decision
text "Aggregator remains the SOLE `:Rp`/`:Rq` writer."

**Recommendation:** Option 1 (convert `Interruptible` to Variant-2/aggregatable). It is the only
option that satisfies both the letter and the spirit of the locked CONTEXT.md decision, and the
blast radius is small and enumerable: 4 test files + `src/models/linear_solve.jl`'s comment
(only a comment reference, not a call site — verify at execution time whether `linear_solve.jl`
itself constructs an `Interruptible`; this research did not find a live call site there, only a
docstring/comment mention). Flag this conversion explicitly as a distinct task in the plan (not
a footnote under "add tanφ"), since it changes a device's fundamental contract, not just adds a
term.

## Common Pitfalls

### Pitfall 1: Assuming the cpydrop sign fix is "just a sign flip" with no downstream cost
**What goes wrong:** Treating FIX-01/02 as isolated to `ConvexBranchFlow.jl`.
**Why it happens:** The change IS textually tiny (two `+` become `-`), so it's easy to
underestimate.
**How to avoid:** Budget explicit time for re-deriving/re-verifying `decompose_dlmp`'s `voltage`
coefficient and re-running the full ADMM/DLMP/stochastic test suites (34 files touch
`ConvexBranchFlow`, 11 touch DLMP — see Validation Architecture below).
**Warning signs:** `decompose_dlmp`'s hard sum-to-price assertion throwing after the sign flip,
or passing "by coincidence" with a residual near (not below) tolerance.

### Pitfall 2: Reintroducing a tree-order dependency that breaks `MeshedFlow`
**What goes wrong:** Choosing Option B (tree-based v̂_GL as the new default) makes
`ConvexBranchFlow.contribute!` depend on a rooted spanning tree, which does not exist uniquely on
a `MeshedFeeder` (nB > N-1).
**Why it happens:** `RestrictedBranchFlow`'s existing tree-based mechanism looks like the
"obviously correct, thesis-cited" answer, but it was built for RADIAL feeders only (`Feeder`, not
`MeshedFeeder`) and MESH-02's own research explicitly relies on `ConvexBranchFlow` staying
graph-generic.
**How to avoid:** If Option B is chosen, explicitly re-verify `MeshedFlow.jl`'s delegation still
works on a genuine mesh, or scope Option B to radial feeders only with a documented fallback.
**Warning signs:** `test_mesh_angle_certificate.jl` or any `MeshedFeeder`-based test failing with
an ambiguous-parent or non-tree error after the fix.

### Pitfall 3: Converting `Interruptible` without updating all four call sites
**What goes wrong:** Changing `contribute!(::Interruptible, ...)`'s return type from a bare
`Vector` to a NamedTuple silently breaks every existing standalone caller that does
`p = contribute!(load, ctx; T)` and expects `p` to be indexable as `p[t]`.
**Why it happens:** The four call sites (`test_device.jl`, `test_linear_solve.jl`,
`test_conformance.jl`, `test_planning_oracle.jl`) are spread across different test concerns, easy
to miss one.
**How to avoid:** `grep -rn "contribute!(.*Interruptible\|= contribute!(load\|= contribute!(d,"
test/` before and after the change; update every standalone call site to either wrap the load in
an `Aggregator` or destructure `res.vars.p` explic3ly.
**Warning signs:** A previously-passing test file suddenly erroring with "no method
`getproperty(::Vector{VariableRef}, :p_inject)`" or similar.

### Pitfall 4: HiGHS/Clarabel tolerance masking the FIX-01 regression's intended infeasibility
**What goes wrong:** The FIX-01 regression needs the THESIS-LITERAL variant to be genuinely
INFEASIBLE (not just numerically strained) on the chosen 3-bus fixture; a loose solver tolerance
can report `ALMOST_OPTIMAL`/a feasible-looking point instead of `INFEASIBLE`.
**Why it happens:** Per the project's own `highs-exactness-defaults` memory, default solver
tolerances routinely mask "exact" claims; Clarabel's SOCP tolerances are similarly not
automatically tight enough for a knife-edge feasibility/infeasibility demonstration.
**How to avoid:** Use the SAME tight-tolerance Clarabel factory (`select_optimizer(SOCP())`)
`ConvexBranchFlow`/`RestrictedBranchFlow` already route to; if the fixture sits too close to the
feasibility boundary, widen the heavy-load/low-voltage margin rather than loosening tolerances.
**Warning signs:** The regression test passing only at a specific optimizer tolerance setting, or
being flaky across runs.

### Pitfall 5: Believing `assert_socp_exact!` is affected by the cpydrop sign
**What goes wrong:** Assuming the SOCP exactness GATE (`assert_socp_exact!`) itself needs
modification for FIX-01/02.
**Why it happens:** Both concern "exactness," so it's tempting to conflate them.
**How to avoid:** `assert_socp_exact!` (per `src/models/exactness.jl`) checks ONLY `l·v ≈
P²+Q²` using `ctx.meta[:pf_vars]`'s `l`, `v`, `P`, `Q` — it never reads `v̂` directly. It is
insulated from the cpydrop sign change structurally; what changes is whether the CONDITIONS that
make the gate actually PASS (vs. throw on a genuine inexactness) are met on previously-passing
fixtures, which is exactly why the full suite must be re-run, not because the gate's own code
needs to change.
**Warning signs:** Spending planning time on `exactness.jl` changes that this research found no
evidence are needed.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `Test` (stdlib) + `TestItemRunner.jl`/`TestItems.jl` — items tagged, discovered by `test/runtests.jl` |
| Config file | `test/runtests.jl` (real entrypoint; do NOT invoke `TestItemRunner`/`@run_package_tests` via `julia -e` — see Known Pitfalls below) |
| Quick run command | A direct Julia/Test.jl script reproducing the relevant `@testitem` body under `julia --project=.` (TestItemRunner itself does not resolve deps under `--project=.` — see memory below) |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` |

**CRITICAL test-invocation hazards (from project memory, re-confirm relevance at execution
time — these are point-in-time observations):**

1. **Never** run via `julia --project=test -e '... @run_package_tests ...'` or via
   `julia -e` at all for the real suite — cwd-based root resolution picks up sibling worktrees
   and `Pkg.develop(path=".")` mutates the pinned `test/Manifest.toml`. Always
   `julia --project=. -e 'import Pkg; Pkg.test()'`.
2. **`<verify>` blocks should NOT invoke `TestItemRunner` directly** — it is a test-only
   dependency that does not resolve under `--project=.`. Per-plan/per-task verification should be
   a direct Julia script under `--project=.` reproducing the relevant `@testitem` body, plus a
   clean `Pkg.precompile()`. Full-suite verification only via the `Pkg.test()` invocation above.
3. **Full suite runtime is ~16-23 minutes** — longer than a single agent turn and close to the
   10-minute Bash tool timeout ceiling. Launch detached (`nohup setsid bash -c "... > LOG 2>&1;
   echo $? > DONE" </dev/null &`) and poll a marker file; never end a turn waiting on a
   backgrounded child (it dies with the turn). Always check the log's start timestamp against the
   commits it's meant to cover before trusting a delta.
4. **Known-false failures to discount on a clean checkout:** 2 Aqua failures
   (CairoMakie-as-weakdep stale-deps + persistent-tasks) if the LOCAL uncommitted `Project.toml`
   drift is present — confirm via `git log -- Project.toml Manifest*.toml` showing no phase
   commit touched them before attributing failures here.
5. **Inside any `@testitem`, never** `try x = f() catch e; caught = e end` — the assignment does
   not escape the `try` body's scope under TestItemRunner's module-wrapping (passes as a plain
   script, fails only under the real runner). Use `x = try f() catch e; caught = e; nothing end`.
6. **Baseline suite size (2026-08-24):** ~30,138 passed / a handful of known flakes (intermittent
   Clarabel `NUMERICAL_ERROR` on IEEE-13 ADMM) — re-measure the CURRENT baseline before this
   phase's changes to have a clean before/after delta; do not assume this exact count still holds
   50+ days later.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command (direct script pattern) | File Exists? |
|--------|----------|-----------|---------------------------------------------|-------------|
| FIX-01 | 3-bus heavy-load/low-voltage: AC-feasible (Ipopt) AND default-SOCP-feasible; thesis-literal variant infeasible | integration | New test file, e.g. `test/test_exactness_verdict.jl`, reproduced as a direct `julia --project=. script.jl` per the TestItemRunner-trap workaround | ❌ new file needed |
| FIX-02 | `v̂ ≥ v` at solution; docstring load-bearing-bound claim matches actual binding constraint | unit | Extend `test/test_convex_branch_flow.jl`; UPDATE the existing (now-reversed) spot-check in `test/test_restricted_branch_flow.jl:20` | ⚠️ existing file, assertion must flip |
| FIX-03 | PV back-feed fixture: receiving-end limit binds (nonzero dual), sending-end slack | integration | New `@testitem` in `test/test_convex_branch_flow.jl` or a new file | ❌ new fixture needed |
| FIX-04 | `soc0=Emin`, discharge incentive at hour T → zero discharge/infeasible | unit | Extend `test/test_pvbattery.jl`, `test/test_fourquadbess.jl`; update `test/test_mpc_window.jl` for the `soc[H+1]` terminal shift and the `H==1` guard removal | ⚠️ existing files, index shift |
| FIX-05 | Per-device `:Rq` == `p·tanφ` for interruptible/thermostatic/deferrable | unit | Extend `test/test_aggregator.jl`, `test/test_thermostatic.jl`, `test/test_deferrable.jl`; NEW test for converted `Interruptible` (Variant-2) + update `test/test_device.jl` for its new return contract | ⚠️ mix of new + existing |
| SC-6 (golden policy) | Every moved golden re-derived with test-comment + SUMMARY table; full suite green | process | Full `Pkg.test()` run before/after, diffed; no automated single command captures this — a manual audit step | n/a (process, not a single test) |

### Sampling Rate

- **Per task commit:** the relevant direct-script reproduction of the touched `@testitem`(s)
  under `julia --project=.` (seconds, not minutes).
- **Per wave merge:** full suite (`Pkg.test()`, ~16-23 min, launched detached per the pitfall
  above).
- **Phase gate:** full suite green (or every non-green item is an explicitly `@test_broken`-
  quarantined, previously-known flake — NOT a new regression) before `/gsd:verify-work`.

### Wave 0 Gaps

- [ ] `test/test_exactness_verdict.jl` (or similarly-named new file) — the FIX-01 3-bus
  heavy-load/low-voltage regression comparing AC (Ipopt), default SOCP, and thesis-literal
  variant feasibility.
- [ ] A PV back-feed fixture for FIX-03 (new `@testitem`, likely in `test_convex_branch_flow.jl`).
- [ ] A minimal single-member `Aggregator` wrapping the converted (Variant-2) `Interruptible`,
  for FIX-05's per-device reactive test — this fixture does not exist today since `Interruptible`
  has never been placed inside an `Aggregator`.
- [ ] Explicit `git grep -n "soc\[H\]\|soc\[T\]\|length(soc)\|soc\[end\]"` sweep across `test/`
  before implementation, to enumerate every test assertion the `soc[1:T+1]` index shift touches
  (this research identified `mpc_window.jl` and the general area but did not exhaustively
  enumerate every test-level assertion — that sweep is Wave-0 work, not research).

*(No framework install gap — `Test`/`TestItemRunner` are already wired.)*

## Security Domain

This is a single-process, offline research/optimization library with no network-facing
endpoints, no authentication, no persisted user data, and no external inputs beyond
researcher-supplied `.jl` fixture files and PDF/CSV data files already in the repo. ASVS
categories V2 (Authentication), V3 (Session Management), and V4 (Access Control) do not apply —
there is no session or user boundary. V5 (Input Validation) is already handled by the project's
own `ArgumentError`-on-construction convention (confirmed throughout `PVBattery`, `FourQuadBESS`,
`Aggregator`, `Interruptible` constructors) — no change needed for this phase. V6 (Cryptography)
does not apply — no secrets, no crypto. No new threat surface is introduced by this phase (pure
internal modeling-correctness fixes); the `## Known Threat Patterns` table is intentionally
omitted as not applicable to this codebase's threat model.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Option A (local sign flip) is the recommended fix mechanism, rather than Option B (tree-based reuse) | FIX-01/02 | If the planner/reviewer instead requires literal Option B, budget and blast radius are materially larger (MeshedFlow tree-order risk, DLMP restructure, not just a coefficient re-derivation) — flagged prominently, not hidden |
| A2 | Converting `Interruptible` from Variant-1 (self-injecting) to Variant-2 (aggregatable) is the correct way to satisfy FIX-05's "Aggregator sole writer" requirement for that device | FIX-05 | If a lighter-touch interpretation is acceptable (e.g., FIX-05's `Interruptible` obligation is satisfiable without touching its production contract, via a test-only shim), the conversion is unnecessary extra work — but no such shim mechanism exists in the current codebase's device contract, so this risk is judged low |
| A3 | Exact 3-bus fixture impedances/loads for the FIX-01 regression need empirical tuning at execution time; no specific numbers are prescribed here | FIX-01 | If the planner expects concrete numbers from research, they must instead be derived empirically during execution (Claude's Discretion per CONTEXT.md, but flagging that no template fixture already matches "heavy-load, low-voltage") |
| A4 | `decompose_dlmp`'s `voltage` coefficient will need RE-DERIVATION (not just re-verification) after the cpydrop sign changes | DLMP blast radius | If the coefficient happens to remain valid unchanged (e.g. if both `vdrop` and `cpydrop` duals flip sign together in a way that cancels), the phase could over-invest in re-deriving something that needs no change — still safer to verify than assume |

## Open Questions

1. **Exact numeric fixture for FIX-01's 3-bus heavy-load/low-voltage regression**
   - What we know: needs to be AC-feasible (Ipopt), default-SOCP-feasible after the fix, and
     thesis-literal-variant-infeasible; existing 3-bus fixture patterns exist as structural
     templates but none stresses this specific (low-voltage, not over-voltage) regime.
   - What's unclear: the specific `r`, `x`, load magnitudes needed to land exactly at this
     three-way boundary.
   - Recommendation: empirical tuning at execution time, mirroring how `RestrictedBranchFlow`'s
     own `_EXACT04_MEASURED_ε` constant was originally measured rather than guessed.

2. **Whether Option A's `decompose_dlmp` coefficient re-derivation changes the SIGN or just a
   scalar multiplier**
   - What we know: the current formula is `-2r(dual(vdrop) + dual(cpydrop))`; the `cpydrop`
     constraint's coefficient on the `l` terms changes from `+1` to `-1` (relative to `r`,`x`).
   - What's unclear: whether the correct post-fix formula is `-2r(dual(vdrop) - dual(cpydrop))`,
     some other linear recombination, or numerically identical (if the dual itself absorbs the
     sign change in a way that cancels) — this is a KKT-stationarity question that should be
     re-derived empirically (matching machine-precision residuals on a solved fixture) exactly as
     the ORIGINAL formula's header comment says it was derived, not assumed from the algebra
     alone.
   - Recommendation: treat this as its own explicit task with its own pass/fail test
     (`decompose_dlmp`'s existing hard assertion), not a side effect of the FIX-01/02 task.

3. **Whether `RestrictedBranchFlow`'s OWN `v̂_GL` OPF-m mechanism needs ANY change**
   - What we know: `RestrictedBranchFlow` delegates its base SOC/exactness-copy machinery to
     `ConvexBranchFlow.contribute!` (so it inherits whichever cpydrop fix is chosen), but its
     OPF-m restriction is a SEPARATE, independently-coded tree-based `v̂_GL` computation that does
     NOT read `ConvexBranchFlow`'s `v̂` variable at all (it builds its own expression from `P`,
     `Q`, `l` directly).
   - What's unclear: whether `RestrictedBranchFlow`'s OPF-m restriction remains sound/necessary
     once the DEFAULT `ConvexBranchFlow` copy is fixed (it was designed to compensate for a
     DIFFERENT problem — v2.1's EXACT-04 over-voltage finding — not FIX-01's low-voltage
     finding), or whether it becomes partially redundant.
   - Recommendation: out of scope for this phase's success criteria (FIX-01/02 are about the
     DEFAULT formulation); flag for a plan-checker sanity note but do not require
     `RestrictedBranchFlow` behavior changes beyond what its existing delegation already inherits.

## Sources

### Primary (HIGH confidence)
- `docs/references/86. Tesis Doctoral Juan Pablo Palacios (2).pdf` — direct `pdftotext`
  extraction, eqs. 3.29-3.45 (pp. ~82-84) and bibliography entry [136], read in this session.
- Direct code reads (this session) of: `src/powerflow/ConvexBranchFlow.jl`,
  `src/powerflow/RestrictedBranchFlow.jl`, `src/powerflow/MeshedFlow.jl`,
  `src/devices/PVBattery.jl`, `src/devices/FourQuadBESS.jl`, `src/devices/Aggregator.jl`,
  `src/devices/AbstractDevice.jl`, `src/devices/Interruptible.jl`, `src/models/mpc_window.jl`,
  `src/models/stochastic_welfare.jl` (partial), `src/models/ac_oracle.jl` (partial),
  `src/pricing/dlmp.jl`, `src/units/PerUnit.jl` (partial), `src/experiments/materialize.jl`
  (grep-level), `test/runtests.jl` (header), `test/test_convex_branch_flow.jl`,
  `test/test_restricted_branch_flow.jl` (grep-level + one `@testitem` title read).
- `.planning/research/THEORY-thesis.md` — prior-session theory digest, cross-checked against the
  raw PDF this session (found consistent).
- `.claude/projects/-home-pedro-programming-TSO-DSO/memory/*.md` — project memories on test
  invocation hazards, HiGHS tolerance defaults, TestItemRunner scoping trap, and the original
  quality-audit findings (all explicitly dated/point-in-time per their own headers).

### Secondary (MEDIUM confidence)
- Gan, Li, Topcu & Low, "Exact Convex Relaxation of Optimal Power Flow in Radial Networks," IEEE
  Trans. Automat. Contr. 60(1), 2015 — identity and general result (exact convex relaxation via a
  lossless shadow network) confirmed via the thesis's own citation and cross-referenced against
  this session's independent algebraic derivation (telescoping-sum proof above); the paper's
  FULL text was not independently fetched this session (no network access to IEEE Xplore was
  attempted) — the citation and its role are [VERIFIED: thesis PDF], but the paper's OWN exact
  Definition-3 formula is [CITED via thesis + training knowledge, cross-checked algebraically],
  not independently re-read from the primary source this session.

### Tertiary (LOW confidence)
- None — no unverified WebSearch-only claims were used in this research; all technical claims
  trace to either the thesis PDF, direct code reads, or self-contained algebraic proof.

## Metadata

**Confidence breakdown:**
- FIX-01/02 verdict: HIGH — thesis PDF text is unambiguous, citation independently confirmed,
  algebraic proof is self-contained and checked twice (telescoping sum + redundancy-direction
  cross-check against the thesis's own adjacent claim).
- FIX-01/02 fix mechanism (Option A vs B): MEDIUM — Option A is proven sufficient; whether it
  satisfies CONTEXT.md's literal "matching the form in RestrictedBranchFlow" phrasing to the
  planner's satisfaction is a judgment call this research flags but cannot resolve unilaterally.
- FIX-03: HIGH — direct algebraic equivalence to the thesis's literal eq. 3.37, existing code
  pattern to mirror is unambiguous.
- FIX-04: HIGH — defect and fix are both directly confirmed by code read; downstream index-shift
  consequences enumerated concretely (`mpc_window.jl:243`, the `H==1` guard).
- FIX-05: HIGH on the defect; MEDIUM-HIGH on the mechanism, given the `Interruptible`
  Variant-1/Variant-2 architectural gap this research surfaced that CONTEXT.md's decision text
  does not explicitly resolve.
- DLMP blast radius: MEDIUM — the RISK is HIGH-confidence (a dual sign this phase changes feeds a
  hard-asserting downstream consumer), but the EXACT fix needed is deliberately left as an
  execution-time empirical re-derivation, consistent with how the original coefficient was itself
  derived (not from first-principles KKT algebra alone).

**Research date:** 2026-09-28
**Valid until:** ~14 days (this is an active-development correctness milestone; code this
research reads may shift under later phases of the SAME milestone before Phase 26 executes —
re-verify file:line citations at execution time if execution is delayed).

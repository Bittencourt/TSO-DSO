# Phase 23: Meshed Networks - Research

**Researched:** 2026-08-10
**Domain:** Non-radial branch-flow SOCP relaxation, angle-recoverability theory (Farivar-Low BFM,
Gan-Low), and this codebase's `AbstractPowerFlow`/`solve_welfare` integration surface.
**Confidence:** HIGH (codebase audit + empirical Julia/Clarabel verification, this session) /
MEDIUM-HIGH (literature synthesis — canonical papers located and read via ar5iv, some passages
degraded in extraction quality; the specific mechanism explaining WHY the loop-uniform-impedance
fixture is recoverable is this session's own derivation, not lifted verbatim from a paper)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** `MeshedFeeder` is a **separate struct alongside** the radial `Feeder` — `assert_radial`
  and every radial code path byte-untouched (MESH-01 locked). Shared helpers by composition only
  where free.
- **D-02:** Committed fixture: **smallest honest loop fixture** (3–4 bus, single loop) as the CI
  substrate; a meshed-IEEE-13-with-tie-switch variant only as literate/quarantined evidence.
- **D-03:** **The theory research pass decides the formulation** (cycle-basis signed incidence vs
  bus-injection/line-flow with loop constraints), with literature (Gan–Low meshed/OPF-m results,
  Bose et al. exactness conditions, Farivar–Low). Hard constraint locked by ROADMAP: explicit
  cycle/loop consistency — never the radial Baran–Wu variables alone.
- **D-04:** **No meshed ADMM this rung.** Centralized meshed SOCP + certificate satisfy the
  criteria; the literate page shows the 4Q-BESS reactive price on the meshed fixture via
  centralized `:balance_q` duals and references Phase 19's live μ-ascent (radial). Meshed
  decomposition is a later rung.
- **D-05:** New named exported certificate, **report-by-default** with an opt-in strict/throw
  kwarg — a deliberate, documented divergence from the family's throw-by-default because
  "unrecoverable" is a first-class scientific finding per MESH-03's own wording.
- **D-06:** The check is **angle recoverability per the Gan–Low condition**: cycle-consistency of
  the angle differences implied by the SOCP solution around every independent loop (exact math per
  the research pass). Never the per-branch cone residual alone (structurally blind to loop
  inconsistency — banned by MESH-03).
- **D-07:** Unrecoverable output: SOCP objective reported as a **valid lower bound**, with a
  structural status field (Phase-20 `price_provenance` precedent) and the inexactness stated as a
  finding. Recoverable output: recovered angles returned + certified.
- **D-08:** Tolerances **measured on the committed meshed fixture at its own scale**, docstring
  provenance table — never reused from sibling certificates (Phase-19 CR-01 lesson).
- **D-09:** CI regression asserting radial behavior unchanged (radial goldens byte-identical;
  `assert_radial` untouched).
- **D-10:** **Honest-gap outcome allowed as the deliverable** (user-approved): a structural gap on
  the meshed fixture ships as the certificate's honest "unrecoverable / lower bound" finding —
  Pitfall 15 respected, no knife-edge fixture tuning to force exactness.
- **D-11:** **Anti-feature honored:** no IEEE-1547 Volt-VAR droop controller anywhere; optimal
  q(v) behavior characterized post-hoc ONLY if it falls out of solved results for free.
- **D-12:** Evidence split: small loop fixture CI-gated; meshed-IEEE variant and anything heavy
  quarantined/literate (Phase 19-22 precedent).

### Claude's Discretion

- All names (MeshedFeeder fields, MeshedFlow, certificate function, status symbols).
- Exact loop-fixture topology/parameters (subject to D-02's smallest-honest-loop bar).
- Angle-recovery algorithm details (BFS spanning tree + cycle closure check, or research's
  recommendation), provided D-06's condition is what is checked.
- Whether the 4Q-BESS lands on the loop fixture or the quarantined meshed-IEEE variant for the
  literate page's reactive-price demonstration.

### Deferred Ideas (OUT OF SCOPE)

- Meshed ADMM / decomposed meshed pricing — later rung (D-04).
- IEEE-1547 Volt-VAR droop controller — permanent anti-feature per MESH-06.
- Multi-loop / N-1 switching topologies — beyond the single-loop rung.
- Meshed planning-layer (Benders) integration — later milestone.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MESH-01 | `MeshedFeeder` data type alongside radial `Feeder`, `assert_radial` untouched | "Formulation Resolution" + "Don't Hand-Roll" sections: `assert_connected` design lifted line-by-line from `topology.jl`'s existing BFS, dropping only the tree-specific edge-count shortcut |
| MESH-02 | `MeshedFlow <: AbstractPowerFlow` SOCP through the `pf` dispatch seam, cycle/loop consistency handled explicitly | "Formulation Resolution" section: `ConvexBranchFlow.contribute!`'s existing per-branch KCL/v-drop/cone loops are ALREADY topology-generic (cited line-by-line); "explicit handling" is realized as the a-posteriori certificate, matching Farivar-Low's own mechanism (angle relaxation is inherently a post-solve question, not a convex model constraint) |
| MESH-03 | Angle-recoverability a-posteriori certificate (Gan-Low condition), report-don't-throw | "The Angle-Recoverability Certificate" section: exact algorithm, empirically verified in this session on a live 3-bus Clarabel spike; "Honest-Gap Fixture Design" section resolves the recoverable/unrecoverable fixture split |
| MESH-06 | Live-executed literate rung page: meshed formulation + certificate + live reactive price | "Architecture Patterns" + "Code Examples" sections: reuses the `docs/literate/stochastic_pv_demand.jl` pattern; 4Q-BESS device already exists (Phase 19, MESH-04/05 complete) — no new device work needed |
</phase_requirements>

## Summary

**The STATE.md blocker is resolved.** The non-radial formulation question decomposes into two
independent sub-questions that the literature (and this session's own empirical Clarabel spike)
answer cleanly:

1. **What variables/constraints does the meshed SOCP need?** Answer: **the exact same ones
   `ConvexBranchFlow` already has** (`v`, `P`, `Q`, `l` per bus/branch; rotated-cone 3.39; v-drop
   3.33; KCL 3.31/3.32). This is option (a) from the objective's framing — "cycle-basis signed
   incidence branch-flow" — and it is **not a new formulation to invent**: direct code reading
   shows `ConvexBranchFlow.contribute!`'s per-branch loops (`src/powerflow/ConvexBranchFlow.jl:150-227`)
   iterate generically over `1:nB` and accumulate KCL via `br.to==j`/`br.from==j` predicates with
   **no tree-order or parent/child assumption anywhere** — they are already graph-generic. Farivar
   & Low's own Branch Flow Model is, by construction, this same magnitude-only (angle-eliminated)
   representation for *any* graph, radial or meshed — the "angle relaxation" step is what makes it
   topology-agnostic at the model layer, not a mesh-specific extension. Bus-injection/line-flow
   (BIM) with an explicit loop constraint (option b) is rejected: a genuine loop constraint written
   in bus-injection angle variables is a **nonconvex** trigonometric identity — it cannot be a hard
   SOCP constraint, which is exactly why Farivar-Low's own treatment defers loop consistency to a
   **post-solve angle-recovery check**, never a model-time constraint (confirmed via ar5iv reads of
   arXiv:1204.4865 and arXiv:1405.0766/1405.0814, "Sources" below).
2. **How is "cycle/loop consistency handled explicitly" (MESH-02) if not as a convex constraint?**
   Answer: it is handled by the **a-posteriori angle-recoverability certificate** MESH-03 already
   separately requires — this is not a second, independent deliverable layered on top of a novel
   formulation; it **is** the formulation's loop-consistency mechanism, exactly matching Pitfall
   14's own prescription ("cross-validate any meshed solve against the independent AC oracle... a
   recovered-angle loop-consistency check") and Farivar-Low's "angle recovery condition."

**Empirical finding (this session, live Clarabel run — see "The Angle-Recoverability Certificate"):**
building a minimal 3-bus triangle loop with the exact `ConvexBranchFlow` constraint shapes and
solving a loss-minimizing SOCP shows the angle-recovery residual is **numerical-noise-level
(~1e-5) whenever all three loop branches share the same R/X ratio**, regardless of how asymmetric
the loads are — and **genuinely structural (~1.5e-3 to 5.8e-3, three orders of magnitude larger)
whenever the branches have heterogeneous R/X ratios**. This gives a concrete, verified recipe for
D-02/D-10's single committed fixture to exercise **both** certificate branches by toggling one
impedance profile, without any knife-edge parameter search (Pitfall 15 respected — the gap is a
structural fact about R/X heterogeneity, not a tuned artifact).

**Primary recommendation:** Implement `MeshedFlow.contribute!` as a thin delegation to
`contribute!(ConvexBranchFlow(), ctx, feeder; T)` (the `RestrictedBranchFlow` delegation precedent,
`src/powerflow/RestrictedBranchFlow.jl:174-175`) plus a `MeshedFeeder` that swaps `assert_radial`
for a new `assert_connected` (drops only the `B == N-1` tree-count shortcut, keeps everything
else). Ship the angle-recoverability certificate as a genuinely new post-processing function
generalizing `recover_voltage_angles`'s BFS with an explicit chord-closure residual check — **do
not reuse `recover_voltage_angles` unmodified**, because it is silently loop-blind (see "Critical
Codebase Finding" below, a sharper, code-level restatement of Pitfall 14).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Meshed topology validation (connectivity, not tree-ness) | Data layer (`src/data/`) | — | `MeshedFeeder`'s inner constructor is the single gate, mirroring `Feeder` |
| Meshed SOCP branch-flow assembly | Power-flow formulation (`src/powerflow/`) | Solver (Clarabel via `problem_class` trait) | `contribute!` writes into the shared `ctx.residuals`; solver choice is a trait, never named here |
| Nodal balance / DADP duals | Model assembly (`src/models/welfare_solve.jl`) | — | Untouched — feeder is duck-typed, no `Feeder`-specific type annotation exists in `solve_welfare` |
| Angle-recoverability certificate | Model post-processing (`src/models/`, sibling to `ac_oracle.jl`/`exactness.jl`) | — | Pure post-solve computation over `ctx.meta[:pf_vars]`; no new JuMP variable, no solver involvement |
| Device injections (4Q-BESS, aggregator) | Device layer (`src/devices/`) | — | Couples only through bus-indexed `:Rp`/`:Rq` — confirmed topology-agnostic (see audit below) |
| Literate demonstration | Docs (`docs/literate/`) | — | Combines the above; no new mechanism, reuses Phase-19's live reactive price |

## Formulation Resolution (D-03 — the STATE.md blocker)

### The literature's actual mechanism (not a menu of two formulations)

Farivar & Low's Branch Flow Model (*"Branch Flow Model: Relaxations and Convexification,"* Parts
I/II, IEEE TPS 2013, arXiv:1204.4865) already treats *both* radial and mesh networks with the
**same** angle-eliminated variable set (bus voltage magnitudes squared, branch active/reactive
flow, branch squared current). Their own two-step relaxation is:

1. **Angle relaxation** — eliminate voltage/current *angles* entirely, keeping only magnitude-level
   quantities (`v = |V|²`, `P`, `Q`, `l = |I|²`) related by the *exact* (non-relaxed) recursion
   `v_j = v_i − 2(rP+xQ) + (r²+x²)l` — this is thesis eq. 3.33, and it is an **algebraic identity**
   (derived by taking `|·|²` of the exact complex equation `V_j = V_i − zI`), true for *any*
   network topology, not a radial-specific simplification. This step, "OPF → OPF-ar," is what
   removes angles from the model, and it is topology-agnostic by construction.
2. **Conic relaxation** — relax the exact equality `l·v = P²+Q²` to the inequality/SOC cone
   `l·v ≥ P²+Q²` ("OPF-ar → OPF-socp"), giving the tractable SOCP `ConvexBranchFlow` already
   implements.

**The mesh-specific subtlety is entirely in step 1's *invertibility*, not in step 2's cone.**
For a radial (tree) network, given any `(v,P,Q,l)` satisfying the exact magnitude equations, there
is a *unique* way to walk the tree from the root and reconstruct a globally consistent voltage
*phasor* field (Theorem 1-style result, and exactly what `recover_voltage_angles` already
implements, `src/models/ac_oracle.jl:66-112`). For a mesh, the *same* magnitude-only equations,
written on every branch of a cycle (not just a spanning tree), are satisfiable by a strictly
larger set of `(v,P,Q,l)` values than the ones that correspond to a *real*, angle-consistent AC
operating point — because the magnitude-only equations cannot "see" the trigonometric identity
that must hold going around a loop (`Σ θ-differences ≡ 0 mod 2π` around every fundamental cycle
— Farivar-Low's "angle recovery condition," confirmed via ar5iv extraction of arXiv:1204.4865:
*"the implied angle differences sum to zero (mod 2π) around each cycle."*). **This is precisely
why the check must be a-posteriori (on a solved point), not a hard convex constraint at model-build
time**: the true loop-closure condition is a nonlinear (trigonometric) identity in angles that do
not exist as decision variables in the angle-eliminated model — writing it as a JuMP constraint
would require reintroducing angles and a nonconvex sine/cosine relation, defeating the entire
point of the branch-flow relaxation. `[CITED: arXiv:1204.4865]`

**Resolution of the (a) vs (b) framing:** option (a) — "cycle-basis signed incidence branch-flow
with explicit loop-closure constraints" — is correct in spirit but the "explicit loop-closure
constraint" it refers to is realized as the **post-solve angle-recoverability certificate**, not a
JuMP-time constraint. Option (b) — bus-injection/line-flow with an explicit loop constraint written
directly in bus-injection angle variables — is a strictly harder, nonconvex reformulation that the
literature does not use for exactly this reason, and it would also require reintroducing angle
variables the project's entire architecture (and CLAUDE.md's "build the branch-flow model from
scratch," Clarabel-native SOCP mandate) is built to avoid. **Recommendation: (a), realized as (i)
generalized cycle-basis KCL/v-drop/cone constraints — already free, since `ConvexBranchFlow` is
already graph-generic — plus (ii) the a-posteriori angle-recoverability certificate as the
loop-consistency mechanism MESH-02 requires "explicitly handled."** `[ASSUMED: this synthesis of
(a)/(b) into a single mechanism is this session's own reading of the papers combined with the
codebase audit below — not a verbatim statement from any single source; flagged in Assumptions
Log A1]`

### Critical codebase finding: `ConvexBranchFlow.contribute!` is ALREADY graph-generic

Direct read of `src/powerflow/ConvexBranchFlow.jl:116-234` (`[VERIFIED: direct code read]`):

- The KCL accumulation loop (lines 213-227) computes `pin`/`pout` via
  `if br.to == j` / `if br.from == j` predicates over `enumerate(B)` for **every** branch — this
  is a full signed-incidence Kirchhoff sum, correct for *any* graph (tree or not). No BFS, no
  parent/child recursion.
- The rotated-cone constraint (line 150-154), the true voltage-drop constraint (`vdrop`, line
  162-168), the exactness-copy drop (`cpydrop`, line 177-183), and the apparent-power cone
  (`smax`, line 201-205) are **all** built via `@constraint(m, name[b=1:nB, t=1:T], ...)` —
  per-branch, indexed by the branch's own `(from, to)`, with **zero reference to tree order or
  a spanning structure**.
- The only place topology enters at all is the **root-fixing** logic (`fix.(v[feeder.root,:],
  1.0)`, line 132) and the bus voltage bounds loop (line 138-145) — both indexed by bus, not by
  tree position.

**Conclusion:** `ConvexBranchFlow.contribute!` would build a mathematically well-posed (if
possibly angle-inconsistent) SOCP relaxation on a graph with `nB > N-1` branches **without any
code change** — the *only* thing standing in the way is `Feeder`'s inner constructor calling
`assert_radial` (`src/data/Feeder.jl:66`), which enforces `B == N-1` and rejects cycles by
construction. `MeshedFlow.contribute!` can therefore **delegate** to
`contribute!(ConvexBranchFlow(), ctx, feeder; T)` exactly as `RestrictedBranchFlow` already does
(`src/powerflow/RestrictedBranchFlow.jl:174-175`, "correctness-drift avoidance… delegate rather
than duplicate").

### Critical codebase finding: `solve_welfare` needs NO sibling entry point (resolves the
"MeshedFlow through solve_welfare's pf dispatch, or sibling?" question)

`src/models/welfare_solve.jl:99-110` — the `solve_welfare` function signature:

```julia
function solve_welfare(
    feeder,
    pf::AbstractPowerFlow,
    aggregators::AbstractVector{<:Aggregator};
    T::Int = 24,
    λ₀,
    optimizer = select_optimizer(problem_class(pf)),
    ...
)
```

**`feeder` carries NO type annotation** (`[VERIFIED: direct code read]`) — it is fully duck-typed.
The function body only ever accesses `feeder.buses`, `feeder.branches`, `feeder.root`, and
`length(feeder.buses)`. As long as `MeshedFeeder` exposes fields named `buses::Vector{Bus{T}}`,
`branches::Vector{Branch{T}}`, `root::Int` (the identical shape `Feeder` uses — trivial to satisfy
by composition, per D-01's "shared helpers by composition only where free"), `solve_welfare`
dispatches on `pf::MeshedFlow` via ordinary Julia multiple dispatch and runs **completely
unmodified**. **No sibling `solve_welfare_meshed` entry point is needed.** This directly answers
the objective's audit question #2: the radial assumption in `welfare_solve.jl` is **zero** — it
lives entirely in `Feeder`'s own constructor (`assert_radial`) and in the two power-flow
formulation files (`ConvexBranchFlow.jl`, which turns out to already be graph-generic; `LinDistFlow.jl`,
`DCPowerFlow.jl`, `RestrictedBranchFlow.jl`, which are not this phase's concern and stay radial —
D-01 requires nothing there).

### Critical codebase finding: `recover_voltage_angles` is SILENTLY loop-blind — do not reuse
unmodified

`src/models/ac_oracle.jl:66-112` builds a signed bidirectional adjacency (`children[i]` includes
**every** branch touching `i`, both directions — genuinely graph-generic construction) but then
runs a single BFS with a `visited[j] && continue` guard. On a graph with a cycle, **the first
branch that reaches a node wins**; the branch that would have closed the loop (the chord) is
silently skipped — its `(j, bsigned)` pair is discarded because `visited[j]` is already `true`.
Handed a `MeshedFeeder` context unmodified, `recover_voltage_angles` would run to completion with
**no error**, silently drop the chord's information, and return a phasor field that looks
identical in shape to the radial case — a textbook instance of Pitfall 14's warning made concrete
at the specific line level. **The new certificate must be a genuinely new function, not a call to
`recover_voltage_angles` followed by a separate check** — it needs to (1) run the same BFS but
explicitly record which branches became chords (never traversed), then (2) for each chord,
independently evaluate the SAME branch-flow phasor equation using the chord's own `(P,Q)` and the
BFS-recovered voltage at its `from`-endpoint, and (3) compare the result to the BFS-recovered
voltage at the chord's `to`-endpoint — the residual **is** the cycle-consistency / angle-recovery
measure. `[VERIFIED: direct code read + this session's own empirical spike, below]`

## The Angle-Recoverability Certificate (MESH-03, D-06)

### Exact algorithm (empirically verified this session)

Generalizing `recover_voltage_angles`'s BFS (`src/models/ac_oracle.jl:66-112`):

1. Build the signed bidirectional adjacency exactly as `recover_voltage_angles` already does
   (`children[i]` = list of `(neighbor, ±branch_index)`).
2. BFS from `feeder.root`, but additionally track, for every branch, whether it was used as a
   *tree* edge (the first time its target was reached) or never used (a **chord**) — an
   `nB`-length boolean vector, `tree_edges[b]`.
3. Recover phasors along tree edges using the EXACT SAME recursion `recover_voltage_angles`
   already implements: `V_j = V_i − z·conj(S)/conj(V_i)`, root anchored at angle 0.
4. For **every** chord `b = (f,t)` (there is exactly one for the committed single-loop fixture;
   the algorithm generalizes to `nB − (N−1)` chords for future multi-loop fixtures — MESH-STRETCH):
   compute `V_t,predicted = V_f,tree − z_b·conj(S_b)/conj(V_f,tree)` using the chord's own solved
   `(P_b, Q_b)`, and compare to `V_t,tree` (the value the tree-path recursion already assigned to
   bus `t`). The residual `|V_t,predicted − V_t,tree|` is the **cycle-closure / angle-recovery
   residual** — this operationalizes Farivar-Low's "sum of angle differences ≡ 0 mod 2π around
   each cycle" condition directly in the phasor domain (equivalent by construction: if the
   residual is zero, the accumulated rotation around the loop is exactly the identity).
5. `recoverable = residual ≤ atol + rtol·scale` (the same WR-01 scale-free combined-bound
   philosophy every existing certificate in this codebase uses — `assert_socp_exact!`,
   `assert_ac_exact!`, `assert_restriction_exact!` — reused for *style* consistency; tolerance
   *values* MUST be independently measured on the actual committed fixture, D-08, never copied).

### Empirical verification (this session, live Julia/Clarabel 0.11 spike, not part of the repo)

A standalone 3-bus triangle (`bus 1`=root, branches `(1,2)`, `(2,3)`, `(3,1)`) built with the
*exact* `ConvexBranchFlow` constraint shapes (rotated cone, v-drop, generic KCL) and solved as a
loss-minimizing SOCP (`Model(Clarabel.Optimizer)`, `tol_gap_abs/rel = 1e-9`) gives:

| Case | Branch impedances | Loads | Cone gap (max) | Angle-recovery residual | Verdict |
|------|-------------------|-------|----------------|------------------------|---------|
| A | uniform `r=0.01,x=0.02` all 3 branches | asymmetric (`P2=0.30,P3=0.05`) | ~2e-9 | **1.0e-5** | recoverable |
| A2 | uniform `r=0.01,x=0.02` | EXTREME asymmetric (`P2=0.45,P3=0.01`) | ~8e-10 | **1.4e-5** | recoverable |
| B | uniform `r=0.01,x=0.02` | symmetric (`P2=P3=0.20`) | ~4e-9 | **2.3e-5** | recoverable (degenerate: chord flow ≈0) |
| C | heterogeneous R/X (`r/x` = 4.0, 0.167, 1.0 per branch) | asymmetric | ~7e-9 | **5.8e-3** | **unrecoverable** |
| C2 | mildly heterogeneous R/X (0.67, 0.36, 0.5) | mildly asymmetric | — | **1.5e-3** | **unrecoverable** |

`[VERIFIED: direct Julia/Clarabel execution, this session — script and full output available in
the session's scratchpad, not committed]`. Every case's per-branch SOC **cone** is tight
(`~1e-9`, i.e. `ConvexBranchFlow`'s existing `assert_socp_exact!` would pass on ALL five cases) —
this is exactly Pitfall 14's warning made numerically concrete: **the existing cone-tightness gate
cannot distinguish case A from case C**, both pass it identically, yet only A is a genuine AC
operating point.

**Mechanism (this session's own derivation — `[ASSUMED]`, physically well-motivated but not
independently re-verified against a citable source):** when every branch in the loop shares the
same R/X ratio, the loss-minimizing SOCP dispatch coincides with the true AC KVL current split by
an analogue of Thomson's minimum-dissipation principle for linear resistive networks (a network
where all impedances are scalar multiples of one reference impedance is equivalent, up to a
rotation, to a purely resistive network, for which the physical current distribution IS the
loss-minimizing one subject to KCL alone) — so the optimizer's cost-minimizing choice of the
"extra" loop-flow degree of freedom happens to reproduce the physically correct one, regardless of
load asymmetry. Heterogeneous R/X ratios break this coincidence, and the optimizer's cost-driven
loop-flow split diverges from the true AC split by a genuinely structural (not noise-level) amount.

### Honest-Gap Fixture Design (D-02, D-10 — resolves "will the fixture show a gap or not")

**Design the single committed fixture with a togglable impedance profile, not two fixtures:**

- **3-4 bus single loop** (D-02), e.g. a 4-bus "diamond" (root=1, buses 2 and 3 as two parallel
  paths, bus 4 closing the loop) or the literal 3-bus triangle spiked above.
- **Profile "uniform"** (all loop branches share one R/X ratio): exercises the **recoverable**
  certificate branch — a genuine, non-trivial test (asymmetric loads keep chord flow strictly
  nonzero, unlike the degenerate symmetric case B above) — angles recovered and certified,
  `status = :angle_certified` (or similar).
- **Profile "heterogeneous"** (loop branches with differing R/X ratios — realistic: overhead vs.
  underground segments, different conductor gauges): exercises the **unrecoverable** certificate
  branch — SOCP value reported as a valid lower bound, `status = :angle_unrecoverable` (D-07),
  the inexactness stated as a first-class finding, never a thrown error under `report = true`
  (D-05).
- **This is not a knife-edge search** (Pitfall 15 respected): R/X heterogeneity is a *qualitative*,
  structural property fixed at fixture-design time, not a swept continuous parameter chased until
  a residual crosses some threshold. The 3-orders-of-magnitude separation observed in the spike
  (1e-5 vs 1e-3–1e-2) means any reasonable tolerance choice cleanly separates the two regimes —
  robust to the parameter values.

## Standard Stack

### Core
No new packages. `Clarabel.jl` (existing `SOCP()` factory, `src/solver/factory.jl:71-84`) solves
the meshed SOCP identically to the radial one — the constraint set is the same shape, just with
`nB ≥ N` instead of `nB = N-1`. `JuMP.RotatedSecondOrderCone()` (existing).

### Supporting
None new. Reuses `ModelContext`, `add_to_residual!`, `register_constraint!` (`src/core/ModelContext.jl`),
`assert_solved!` (`src/core/status.jl`), the existing WR-01 scale-free tolerance idiom.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Delegating `MeshedFlow.contribute!` to `ConvexBranchFlow.contribute!` | Duplicate the constraint-writing code in a standalone `MeshedFlow` | Duplication risks correctness drift (exactly the reasoning `RestrictedBranchFlow.jl`'s own header comment gives for delegating) — no upside since the math is byte-identical |
| Post-solve angle-recoverability certificate | A hard loop-closure JuMP constraint at model-build time | Not possible without reintroducing nonconvex angle variables — rejected by the literature itself, not just an implementation convenience |
| SDP tightening (Clarabel native PSD cone) if the loop residual is unacceptably large in a future case | — | Explicitly deferred, `MESH-STRETCH` — not needed for the minimal validated rung; D-10 makes "honest gap" an acceptable deliverable |

**Installation:** none — zero `Project.toml` changes.

## Package Legitimacy Audit

Not applicable — this phase installs no new packages (all machinery is existing `Project.toml`
dependencies: JuMP, Clarabel). No package legitimacy gate required.

## Architecture Patterns

### System Architecture Diagram

```
                     MeshedFeeder(buses, branches, root)
                              │  (assert_connected — NEW, replaces
                              │   assert_radial's B==N-1 tree check
                              │   with genuine BFS reachability;
                              │   assert_magnitudes reused as-is)
                              ▼
      solve_welfare(feeder::MeshedFeeder, MeshedFlow(), aggregators; λ₀, T)
      (UNCHANGED — feeder param is duck-typed, dispatches on pf's type)
                              │
                              ▼
      MeshedFlow.contribute!(ctx, feeder; T)
        └─ DELEGATES to contribute!(ConvexBranchFlow(), ctx, feeder; T)
             (KCL / v-drop / rotated-cone / exactness-copy / smax —
              ALL already graph-generic, zero new constraint code)
                              │
                              ▼
                    assert_solved!(model; dual=true)
                              │
                              ▼
      assert_socp_exact!(ctx)   ← existing per-branch cone gate (STILL RUNS,
                              │     necessary but NOT sufficient on a mesh — Pitfall 14)
                              ▼
      *** NEW: certify_angle_recoverable!(ctx; report=true) ***
        1. BFS spanning tree (mirrors recover_voltage_angles, but tracks chords)
        2. Per-chord closure residual (this session's verified algorithm)
        3. recoverable  → angles returned + :angle_certified status (D-07)
           unrecoverable → SOCP objective reported as valid lower bound,
                            :angle_unrecoverable status, @warn (report=true) (D-05/D-07)
                              │
                              ▼
              dadp = dual.(balance_p[...])  (unchanged — DADP is a genuine
              convex dual of the SOLVED SOCP either way; its PHYSICAL
              interpretation as a real-AC nodal price is what the
              certificate's verdict qualifies, not its mathematical validity)
```

### Recommended Project Structure
```
src/
├── data/
│   ├── Feeder.jl              # UNCHANGED
│   ├── topology.jl            # UNCHANGED (assert_radial untouched, D-01/D-09)
│   ├── MeshedFeeder.jl        # NEW — mirrors Feeder.jl's shape/field names exactly
│   └── mesh_topology.jl       # NEW — assert_connected (BFS reachability, drops B==N-1)
├── powerflow/
│   ├── ConvexBranchFlow.jl    # UNCHANGED
│   └── MeshedFlow.jl          # NEW — thin delegation, mirrors RestrictedBranchFlow.jl's pattern
├── models/
│   ├── exactness.jl           # UNCHANGED (assert_socp_exact! still runs, still necessary)
│   ├── ac_oracle.jl           # UNCHANGED (recover_voltage_angles left as-is — NOT reused
│   │                          #   unmodified for mesh, per the "silently loop-blind" finding)
│   └── mesh_angle_certificate.jl  # NEW — the MESH-03 certificate (Claude's discretion: name)
└── ...
docs/literate/
└── meshed_reactive_price.jl   # NEW — MESH-06, combines MeshedFlow + certificate + 4Q-BESS
                                #   (device already exists, Phase 19 — no new device code)
```

### Pattern 1: Delegation over duplication for a peer `AbstractPowerFlow`
**What:** A new formulation that is "the base formulation plus X" calls
`contribute!(BaseFormulation(), ctx, feeder; T)` first, then adds only its own delta.
**When to use:** Any time the new formulation's constraint set is a strict superset/variant of an
existing one — established precedent, not a MESH-specific invention.
**Example:**
```julia
# Source: src/powerflow/RestrictedBranchFlow.jl:174-175 (existing precedent)
function contribute!(pf::RestrictedBranchFlow, ctx::ModelContext, feeder; T::Int = 1)
    contribute!(ConvexBranchFlow(), ctx, feeder; T = T)
    # ... pf's own additional constraints ...
end
```
For `MeshedFlow`, the delta is **empty** at the constraint-writing level — see "Critical codebase
finding" above — so `MeshedFlow.contribute!` is *purely* the delegation call plus a provenance
stash (`ctx.meta[:formulation] = :MeshedFlow`, D-08-style precedent).

### Pattern 2: A-posteriori certificate over hard convex constraint, when the true condition is
nonconvex
**What:** When the "real" validity condition (angle/loop closure) cannot be expressed as a convex
constraint on the model's own decision variables, do not approximate it into the model — solve the
relaxation, then check the condition on the solved point, report-don't-throw if the condition is a
first-class scientific finding (D-05).
**When to use:** Any relaxation whose exactness/validity depends on information eliminated by the
relaxation itself (angles here; the SOCP cone-tightness question in the radial case is a related
but distinct instance already handled by `assert_socp_exact!`).

### Anti-Patterns to Avoid
- **Reusing `recover_voltage_angles` unmodified on a `MeshedFeeder` context:** silently drops chord
  information (see "Critical codebase finding" above) — produces a plausible-looking but
  unvalidated phasor field with no error. Always route mesh angle recovery through the NEW
  chord-aware certificate.
- **Treating a mesh SOC-relaxation gap as a knife-edge to tune away** (Pitfall 15) — R/X
  heterogeneity is a *qualitative* topology/impedance property; do not sweep continuous parameters
  hunting for exactness.
- **Writing a bus-injection/angle-based loop constraint directly into the JuMP model** — nonconvex,
  defeats the SOCP relaxation's entire purpose; not what the literature does.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Meshed SOCP constraint assembly | A new bespoke variable/constraint set for `MeshedFlow` | Delegate to `ConvexBranchFlow.contribute!` | Already graph-generic (verified above); duplicating risks correctness drift for zero benefit |
| Spanning-tree BFS + signed adjacency | A new adjacency-building routine | Mirror `recover_voltage_angles`'s existing `children[i]` construction (`src/models/ac_oracle.jl:76-80`) verbatim, only adding chord tracking | Same signed-branch-index idiom already battle-tested (Phase-20 CR-01 branch-orientation-safety lesson) |
| Connectivity check | A new graph library dependency (e.g. `Graphs.jl`) | Copy `assert_radial`'s existing hand-rolled BFS (`src/data/topology.jl:81-107`), drop the `B==N-1` shortcut, keep the BFS reachability check | Consistent with the project's own "no `Graphs.jl` dependency" convention stated in `topology.jl`'s header comment; the BFS is ~15 lines, unchanged in spirit |
| Scale-free tolerance philosophy for the new certificate | A bespoke ad-hoc tolerance scheme | The existing `atol + rtol·scale` combined-bound idiom (WR-01), independently measured (D-08) | Every certificate in this codebase (`assert_socp_exact!`, `assert_ac_exact!`, `assert_restriction_exact!`) already uses this shape — consistency of STYLE, not of VALUE (never copy the actual numbers) |

**Key insight:** This phase's "new model-math" is almost entirely in the **certificate**, not the
**formulation** — the formulation is a near-zero-code delegation once the data-layer gate
(`assert_radial` → `assert_connected`) is lifted. Plans should budget effort accordingly: most of
the phase's genuine risk and novelty is in getting the angle-recovery algorithm and its fixture
right, not in inventing a new SOCP.

## Runtime State Inventory

Not applicable — this is a greenfield phase (new types/files), not a rename/refactor/migration.

## Common Pitfalls

### Pitfall 1 (repo Pitfall 14): Reusing Baran-Wu variables in a mesh without an explicit
loop-consistency mechanism
**What goes wrong:** A `MeshedFlow` that reuses `ConvexBranchFlow`'s constraints verbatim (correct,
per this research) but ships with NO angle-recoverability certificate can pass `assert_socp_exact!`
per-branch while being globally loop-inconsistent — this is a SILENT failure with no solver error.
**Why it happens:** The branch-flow variable set is graph-generic and "looks complete" (see the
Critical Codebase Finding) — it is easy to mistake "the model builds and solves OPTIMAL" for
"the model is correct on a mesh."
**How to avoid:** MESH-03's certificate is not optional polish — it is the ONLY thing that catches
this. Never ship `MeshedFlow` without it wired into the plan's acceptance criteria.
**Warning signs:** A test suite exercising `MeshedFlow` that only calls `assert_socp_exact!` and
never the new angle-recoverability certificate.

### Pitfall 2 (repo Pitfall 15): Treating the meshed gap as a tunable knife-edge
**What goes wrong:** Chasing exactness by sweeping fixture parameters instead of accepting the
structural finding.
**Why it happens:** The project's own successful v2.1 EXACT-04 pattern (sweep, characterize,
fix) is a strong recently-reinforced habit; it does not apply here (see "Honest-Gap Fixture
Design" — the mechanism is qualitative, not a sweepable scalar).
**How to avoid:** Design the fixture's two impedance profiles (uniform / heterogeneous) as a
DELIBERATE, DOCUMENTED CHOICE before any numeric tuning, per this research's empirical measurement.
**Warning signs:** A plan task that says "tune the loop impedance until the certificate passes."

### Pitfall 3 (new, this session): `recover_voltage_angles` silently drops chord information
**What goes wrong:** Calling the EXISTING `recover_voltage_angles` on a meshed context returns a
plausible-looking phasor field with NO error, silently ignoring the chord — a false-negative risk
distinct from (but related to) Pitfall 14.
**Why it happens:** `recover_voltage_angles`'s BFS-with-`visited` guard is a standard, correct
pattern for a TREE (where it happens to visit every node exactly once via every edge, since there
IS only one path) but silently discards extra edges on a graph with cycles — this is invisible
without reading the function's `visited[j] && continue` line.
**How to avoid:** Never call `recover_voltage_angles` directly on a `MeshedFeeder` context expecting
it to validate anything; always route through the new certificate, which explicitly enumerates and
checks chords.
**Warning signs:** Code that calls `recover_voltage_angles(ctx)` where `ctx.meta[:feeder]` is a
`MeshedFeeder`.

### Pitfall 4 (repo Pitfall 16, cross-reference only — already resolved in Phase 19): 4Q-BESS
P-Q complementarity
Already re-derived and shipped (MESH-04/05, Phase 19, complete). No new work this phase — MESH-06's
literate page reuses the existing `FourQuadBESS`/`assert_4q_complementarity!` machinery as-is.

## Code Examples

### Delegation pattern for `MeshedFlow.contribute!`
```julia
# Source: this research, pattern lifted from src/powerflow/RestrictedBranchFlow.jl:174-175
function contribute!(pf::MeshedFlow, ctx::ModelContext, feeder; T::Int = 1)
    contribute!(ConvexBranchFlow(), ctx, feeder; T = T)   # byte-identical constraint set
    ctx.meta[:formulation] = :MeshedFlow                  # D-08-style provenance for the certificate
    return ctx
end
problem_class(::MeshedFlow) = SOCP()   # same tight-gap Clarabel factory, src/solver/problem_class_trait.jl pattern
```

### Angle-recoverability certificate skeleton (verified mechanism, this session's spike)
```julia
# Mirrors src/models/ac_oracle.jl:66-112's BFS, adding chord tracking + closure residual.
function certify_angle_recoverable!(ctx::ModelContext; atol = <measured>, rtol = <measured>,
                                      report::Bool = false)
    feeder = ctx.meta[:feeder]; pv = ctx.meta[:pf_vars]; T = ctx.meta[:T]
    N = length(feeder.buses)
    children = [Tuple{Int,Int}[] for _ in 1:N]
    for (b, br) in enumerate(feeder.branches)
        push!(children[br.from], (br.to, b)); push!(children[br.to], (br.from, -b))
    end
    tree_edges = falses(length(feeder.branches))
    # ... BFS identical to recover_voltage_angles, but set tree_edges[b] = true per traversal ...
    chords = findall(!, tree_edges)
    worst = 0.0
    for b in chords, t in 1:T
        # predict V_to from V_from via branch b's own (P,Q); compare to the BFS-recovered V_to
        # residual = |V_to_predicted - V_to_tree|; worst = max(worst, residual)
    end
    recoverable = worst <= atol + rtol * <scale>
    status = recoverable ? :angle_certified : :angle_unrecoverable
    ctx.meta[:price_provenance] = (; formulation = get(ctx.meta, :formulation, :unknown),
        certificate = :certify_angle_recoverable!, status)
    if !recoverable
        msg = "Meshed SOCP angle-recovery FAILED (residual=$worst): SOCP objective is a " *
              "valid LOWER BOUND only, not a certified AC operating point (Gan-Low condition; MESH-03)"
        report ? (@warn msg) : error(msg)
    end
    return (; recoverable, worst_residual = worst, status)
end
```
(Sketch only — exact field names, tolerance provenance table, and per-hour reporting shape are
Claude's discretion at plan time, per CONTEXT.md.)

## State of the Art

| Old Approach (radial-only assumption) | Current Approach (this research) | When Changed | Impact |
|--------------|------------------|--------------|--------|
| "Meshed needs a new SOCP formulation" (PROJECT.md/SUMMARY.md's pre-research framing) | Meshed needs the SAME formulation + a new a-posteriori certificate | This research pass, 2026-08-10 | Substantially reduces MESH-02's implementation scope; concentrates risk in MESH-03 |
| `recover_voltage_angles` treated as "the" angle-recovery mechanism, reusable as-is | Must be replaced/wrapped by a chord-aware variant for mesh contexts | This research pass | New function required, not a config flag on the existing one |

**Deprecated/outdated:** None — no prior meshed code exists in this codebase to deprecate (SEAM-01
slot was empty per PROJECT.md).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The (a)/(b) formulation choice resolves to "reuse ConvexBranchFlow's constraints + realize loop-consistency purely as a post-solve certificate" — this session's synthesis of Farivar-Low's papers with the codebase audit, not a verbatim single-source claim | Formulation Resolution | If wrong, MeshedFlow would need genuinely new model-time constraints beyond delegation — larger implementation scope than estimated, though the certificate work is unaffected either way |
| A2 | The "uniform R/X ratio ⇒ recoverable, heterogeneous ⇒ structural gap" mechanism, explained via a Thomson's-principle analogy | The Angle-Recoverability Certificate ("Mechanism") | The EMPIRICAL residuals (1e-5 vs 1e-3–1e-2) are directly verified by this session's own Clarabel run and are trustworthy regardless of the explanation; if the explanatory mechanism is wrong, the FIXTURE DESIGN recommendation (toggle R/X ratio) still holds because it is grounded in the measured numbers, not the theory of why |
| A3 | Farivar-Low's exact "angle recovery condition" wording ("implied angle differences sum to zero mod 2π around each cycle") — extracted via ar5iv HTML rendering of arXiv:1204.4865, which is a lossy re-derivation of the PDF, not a direct PDF text extraction (the raw PDF's binary/FlateDecode streams could not be decoded directly by the fetch tool) | Formulation Resolution | If the exact wording is imprecise, the OPERATIONALIZED algorithm (phasor closure residual, empirically verified independently in this session) is the load-bearing deliverable and does not depend on the precise wording being exact |
| A4 | `MeshedFeeder`'s field shape (buses/branches/root with the exact same names as `Feeder`) is sufficient for `solve_welfare`'s duck-typing to work with zero changes — verified by reading `solve_welfare`'s body for every `feeder.` access, but not by actually constructing a `MeshedFeeder` and running it end-to-end (no such type exists yet) | Critical codebase finding: solve_welfare | Low risk — the audit is a complete enumeration of every `feeder.` access in the function body; a missed access would surface immediately as a `MethodError`/`KeyError` at first execution, not a silent-wrong hazard |

## Open Questions

1. **How many chords should the certificate handle for the quarantined meshed-IEEE-13-tie-switch
   variant?**
   - What we know: the algorithm generalizes to `nB − (N−1)` chords (loop over all of them).
   - What's unclear: whether a single tie-switch closes exactly one loop (most likely, if it's a
     single tie between two radial branches) or more, depending on the exact IEEE-13 topology
     modification chosen.
   - Recommendation: verify the exact chord count when the quarantined variant is built (D-12);
     the CI-gated single-loop fixture (D-02) only ever needs the single-chord case. (RESOLVED for
     the CI fixture — MEDIUM confidence on the quarantined variant, deferred to implementation.)
2. **Exact tolerance values (`atol`/`rtol`) for the shipped certificate.**
   - What we know: this session's spike shows a ~1e-5 (recoverable) vs ~1e-3–5.8e-3 (unrecoverable)
     separation on a TOY triangle with made-up per-unit values, not the project's actual
     `PerUnitBase`/fixture conventions.
   - What's unclear: the exact numbers on the ACTUAL committed fixture (D-08 requires
     re-measurement there, never a copy of this spike's numbers).
   - Recommendation: plan a measurement task exactly mirroring `RestrictedBranchFlow`'s own D-07
     "Tolerance provenance" documentation pattern (`src/models/restriction_exactness.jl:150-198`).
     (RESOLVED — mechanism and separation margin confirmed; only the specific numbers are deferred,
     as D-08 already requires.)
3. **Naming** (Claude's discretion per CONTEXT.md) — `MeshedFlow` vs some other name,
   `certify_angle_recoverable!` vs `assert_angle_recoverable!`, exact status symbols
   (`:angle_certified`/`:angle_unrecoverable` used above are illustrative only). (Not a
   research gap — explicitly deferred to planning per CONTEXT.md's Claude's Discretion list.)

## Environment Availability

Skipped — no external dependencies beyond the existing `Project.toml` (Julia 1.11/JuMP/Clarabel,
already verified present and working in this session via the live spike run:
`julia --project=. -e 'println(VERSION)'` → `1.12.5`, and the spike's own successful Clarabel
solves).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `Test` stdlib + `TestItems`/`TestItemRunner` (existing project convention) |
| Config file | `test/runtests.jl` (existing) |
| Quick run command | `julia --project=. -e 'include("test/test_mesh_XXX.jl")'` (direct script, per the phase's testing-constraint precedent — never TestItemRunner in a plan's `<verify>` block) |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (reserved for the final acceptance plan only, ~12-20 min, background) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MESH-01 | `MeshedFeeder` accepts a cyclic topology; `assert_radial`/`Feeder` byte-unchanged | unit | direct Julia script asserting `MeshedFeeder(...)` succeeds on the loop fixture AND `Feeder(...)` on the SAME cyclic edge list still throws | ❌ Wave 0 |
| MESH-02 | `MeshedFlow()` dispatches through `solve_welfare` unmodified, solves OPTIMAL on the loop fixture | unit/integration | direct script: `solve_welfare(mesh_feeder, MeshedFlow(), aggs; λ₀, T)` returns `(ctx, obj, dadp)` with `termination_status == OPTIMAL` | ❌ Wave 0 |
| MESH-03 | Angle-recoverability certificate: recoverable branch (uniform R/X) certifies + returns angles; unrecoverable branch (heterogeneous R/X) reports lower bound, never throws under `report=true` | unit | direct script exercising BOTH fixture profiles, asserting `status` symbol and residual ordering (unrecoverable residual ≫ recoverable residual, mirroring this session's ~1e-5 vs ~1e-3 separation) | ❌ Wave 0 |
| MESH-06 | Literate page executes end-to-end, documents both certificate outcomes + 4Q-BESS reactive price | manual (Documenter-executed literate) | `julia --project=docs docs/make.jl` (existing convention) or direct `include` of the literate script | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** direct Julia script for the specific behavior just implemented.
- **Per wave merge:** re-run all `test/test_mesh_*.jl` scripts directly.
- **Phase gate:** Full suite green (`Pkg.test()`) before `/gsd:verify-work`, including the D-09
  radial-regression check (existing radial goldens byte-identical).

### Wave 0 Gaps
- [ ] `test/test_mesh_feeder.jl` — MeshedFeeder construction + assert_connected behavior (MESH-01)
- [ ] `test/test_mesh_flow.jl` — MeshedFlow SOCP solve via solve_welfare, cone-tightness sanity (MESH-02)
- [ ] `test/test_mesh_angle_certificate.jl` — both certificate branches on the two fixture profiles (MESH-03)
- [ ] Fixture module (mirrors `Phase4Fixtures`/`IEEE13_BASE` convention) exposing the committed
      loop fixture with BOTH impedance profiles as named constructors
- [ ] No new framework install needed — `Test`/`TestItems` already present.

## Security Domain

Not applicable — this is a research computation library with no network-facing surface, no
authentication/session/access-control concerns, no user input parsing beyond fixture literals.
`security_enforcement` is not set in `.planning/config.json` at the time of this research; treated
as N/A given the domain (research math library, no ASVS category applies materially — confirmed
by the absence of any security-relevant surface in the audited files).

## Sources

### Primary (HIGH confidence)
- Direct code reads, this session, with file:line citations throughout: `src/data/topology.jl`,
  `src/data/Feeder.jl`, `src/powerflow/ConvexBranchFlow.jl`, `src/powerflow/AbstractPowerFlow.jl`,
  `src/powerflow/RestrictedBranchFlow.jl`, `src/models/welfare_solve.jl`, `src/models/ac_oracle.jl`,
  `src/models/exactness.jl`, `src/models/restriction_exactness.jl`, `src/solver/factory.jl`,
  `src/solver/problem_class_trait.jl`, `src/devices/Aggregator.jl`, `src/TSODSO.jl`.
- Live empirical verification, this session: a standalone JuMP 1.x + Clarabel 0.11 (Julia 1.12.5,
  `--project=.` using the repo's own pinned `Project.toml`/`Manifest.toml`) 3-bus triangle spike,
  5 solved cases, cone-gap and angle-recovery-residual measurements reported verbatim above.

### Secondary (MEDIUM confidence)
- Farivar & Low, *"Branch Flow Model: Relaxations and Convexification"* Parts I/II, IEEE TPS 2013
  (arXiv:1204.4865) — angle recovery condition ("implied angle differences sum to zero mod 2π
  around each cycle"), phase shifters placed on chords/outside a spanning tree — extracted via
  ar5iv HTML rendering (`ar5iv.labs.arxiv.org/html/1204.4865`), not a direct PDF text read (the raw
  PDF resisted decompression by the fetch tool — flagged in Assumptions Log A3).
- Low, *"Convex Relaxation of Optimal Power Flow, Part I: Formulations and Equivalence"*
  (arXiv:1405.0766) and *Part II: Exactness* (arXiv:1405.0814), IEEE TCNS 2014 — confirms "for mesh
  networks, the conic relaxation is always exact but the angle relaxation may not be exact," and
  that sufficient conditions for radial exactness "are insufficient for general mesh networks
  because they cannot guarantee that an optimal solution of a relaxation satisfies the cycle
  condition" — extracted via ar5iv HTML rendering.
- Bose, Gayme, Chandy & Low, *"Quadratically Constrained Quadratic Programs on Acyclic Graphs with
  Application to Power Flow"* (arXiv:1203.5599, IEEE TCNS 2014) — located via WebSearch/abstract
  read only (not fetched in full); its headline result ("exact SDP relaxation when the underlying
  graph is acyclic, given a technical condition") is cited by analogy — the meshed/cyclic case is
  the structural complement this phase's certificate must handle, consistent with (not
  independently re-derived from) this paper's acyclic result.

### Tertiary (LOW confidence)
- Gan, Li, Topcu & Low's meshed-specific treatment was searched for but not separately located
  beyond the radial "Exact Convex Relaxation of OPF in Tree/Radial Networks" papers already cited
  in the project's own prior research (SUMMARY.md); the meshed exactness question is instead
  answered by Low's tutorial Part I/II (arXiv:1405.0766/1405.0814) directly, which explicitly
  covers mesh networks. No separate Gan-Low meshed-specific paper was found distinct from the
  tutorial's own mesh section — flag for a targeted re-check if a plan later needs a citation more
  specific than the tutorial.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new packages, existing Clarabel/JuMP factory reused verbatim.
- Architecture (formulation delegation, `solve_welfare` duck-typing): HIGH — grounded in direct
  code reads with file:line citations, cross-checked by literature agreement (BFM's own
  topology-agnostic construction).
- Angle-recoverability mechanism and algorithm: HIGH on the algorithm and its empirical behavior
  (independently run and measured this session); MEDIUM on the precise theoretical explanation
  (Thomson's-principle analogy is this session's own synthesis, not sourced verbatim).
- Fixture design (uniform vs. heterogeneous R/X): HIGH — directly measured, large (3-order-of-
  magnitude) separation margin, robust to the exact numeric choices.
- Pitfalls: HIGH — two are the project's own pre-existing research (Pitfall 14/15, already
  code-grounded); the third (`recover_voltage_angles` silently loop-blind) is a new, directly
  code-verified finding this session.

**Research date:** 2026-08-10
**Valid until:** 30 days (stable domain — no external API/library churn risk; re-check only if the
committed fixture's actual measured tolerances diverge substantially from this session's toy-spike
scale during implementation, per D-08).

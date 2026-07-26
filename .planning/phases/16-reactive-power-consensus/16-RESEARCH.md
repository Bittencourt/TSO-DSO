# Phase 16: Reactive-Power (μ) Consensus - Research

**Researched:** 2026-07-25
**Domain:** Julia/JuMP ADMM decomposition extension — adding a genuine reactive-power balance +
citable reactive nodal price to an already-shipped, cross-validated operational ADMM core
(`src/admm/`) and the DLMP pricing pipeline (`src/pricing/dlmp.jl`)
**Confidence:** HIGH on code facts (every claim below was grepped/read directly against the live
`src/`/`test/` tree, not summarized from the prior same-day SUMMARY/ARCHITECTURE/PITFALLS research
pass); MEDIUM on the two open judgment calls (`ρ_q` vs shared `ρ`; the Clarabel flake rate under
Q-consensus) that this phase must resolve empirically, per STATE.md's own flags.

> **Correction to the prior same-day research pass:** ARCHITECTURE.md/SUMMARY.md (written earlier
> the same day, before this phase's own line-level code read) describe today's reactive closure as
> a "free reactive-import slack" that REACT-01 must "replace." Direct inspection of
> `src/admm/DsoOpt.jl` and `src/models/welfare_solve.jl` shows this is **not quite accurate**:
> `:balance_q` is **already** registered as a genuine equality constraint at *every* bus (root +
> every load node) in **both** the centralized `solve_welfare` and the ADMM `DsoOpt`, today,
> unconditionally. The *only* genuinely free/unpriced quantity is the root's `q_import` (free-sign,
> zero objective coefficient — see "Free slack, precisely located" below). This changes REACT-01's
> minimal scope non-trivially; see "Key Findings" and "Architecture Patterns" below for the corrected
> design.

## Summary

Phase 16 closes the `AgrOpt.jl`/`DsoOpt.jl` reactive-power placeholder by (a) resolving a genuine
naming collision between the *new* reactive dual and the *existing* adaptive-ρ residual-balancing
scalar `μ::Real=10.0` — already threaded through `solve_admm`'s kwargs and `Scenario`'s
golden-hash-serialized schema — and (b) extracting a citable reactive nodal price as a 5th DLMP
component. Both the centralized welfare solve and the ADMM `DsoOpt` subproblem **already** register
`:balance_q[j,t] == 0` as a genuine equality constraint at every bus, so `dual(:balance_q[j,t])` is,
in principle, *already* a well-defined economic shadow price today — nobody in the entire codebase
(`grep -rn "balance_q" src/ test/`) ever calls `dual()` on it. The actual missing pieces are: (1) a
distinctly-named code identifier for this dual (never the bare `μ`), (2) a first-class extraction
function alongside `extract_dlmp`/`decompose_dlmp`, and (3) — the one place a real model change is
warranted — turning the ADMM `DsoOpt`'s per-load-node **constant** reactive draw into a genuine
JuMP coupling variable so the reactive price is obtained the *same trustworthy way* the active DADP
already is (a maintained, gated multiplier sequence, not a raw `dual()` call against a solve that
tolerates `ALMOST_OPTIMAL`/`NEARLY_FEASIBLE`).

Per thesis A3 (DERs are active-only) and the roadmap's own explicit deferral, this is a **one-shot
price read off a genuine equality, not a live cross-subproblem μ dual-ascent loop** — `AgrOpt.qag`
is a fixed constant (no reactive DER decision exists to iterate on), so a full Boyd-style μ-ascent
block is unnecessary machinery for what the thesis scope actually needs. The recommended path is
additive and feature-flagged (`reactive_consensus::Bool=false` default), touches only `src/admm/`
+ `src/pricing/dlmp.jl`, and does **not** touch `src/experiments/Scenario.jl` — keeping the
already-brittle DrWatson `savename`/golden-hash schema completely untouched this phase, which is
the simplest possible way to satisfy REACT-03's byte-identical non-regression requirement.

**Primary recommendation:** Resolve the `μ` naming collision first (grep-and-pick a distinct
identifier, e.g. `μq`/`mu_q`, for the reactive dual — never reuse bare `μ`); then, behind
`reactive_consensus::Bool=false` in `build_dso_opt`/`solve_admm`, turn the per-load-node reactive
injection in `DsoOpt` into a genuine coupling variable `qag_dso[j,t]` pinned to the (still fixed,
per A3) target `agr.qag[j][t]`, extend the FINAL-solve certificate block (mirroring `assert_no_slack`
on `:balance_p`) to also certify `:balance_q`, and expose `dual(:balance_q[j,t])` as a new,
documented 5th field in `decompose_dlmp`'s returned NamedTuple — never touching `Scenario.jl`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Reactive balance closure (genuine per-node equality) | `admm/` (DsoOpt build/solve) | `models/` (centralized `welfare_solve.jl`, already correct) | The physical constraint lives in the JuMP model layer; ADMM's `DsoOpt` is the one that needs a structural change (constant → variable), the centralized model needs none. |
| Reactive dual extraction / naming | `admm/` (internal state) + `pricing/` (`dlmp.jl` reporting) | — | The internal ADMM state (whatever it's named) is orchestration-layer; the *reported*, citable price is a pricing-layer concern (`extract_dlmp`/`decompose_dlmp` peers) — keep the two names decoupled so a pricing-layer rename never touches ADMM internals. |
| Non-regression / feature flag | `admm/` (kwarg default) | — | The flag is a function-signature concern local to `build_dso_opt`/`build_agr_opt`/`solve_admm`; it explicitly must NOT propagate into `experiments/Scenario.jl` this phase (see "Key Findings" — avoids a second, unrelated golden-hash perturbation). |
| Empirical flake re-measurement | `admm/` (solve loop) + test harness | — | Instrumentation-only; no architectural placement decision, just an experiment to run against the existing IEEE-13/123 ADMM fixtures with `reactive_consensus=true`. |
| Reactive-price certification (no-hidden-slack gate) | `admm/` (`solve_admm`'s final consolidation block) | `core/status.jl` (`assert_no_slack`, reused verbatim) | Mirrors the EXISTING active-balance certificate exactly — same tier, same mechanism, new target constraint. |

**Explicitly NOT touched this phase (confirmed by direct inspection, not assumed):**
`src/experiments/Scenario.jl`, `src/experiments/run.jl`, `src/experiments/sweep.jl`,
`src/experiments/store.jl` (the DrWatson-backed golden-hash surface), `src/models/exactness.jl`,
`src/solver/*`, `src/data/*`. ROADMAP.md's own phase framing ("touches only `src/admm/`") is
confirmed accurate for the ADMM change; this research additionally confirms `src/pricing/dlmp.jl`
is the correct (and only) home for the reported price, per REACT-02's explicit file reference.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REACT-01 | DSO-OPT per-node reactive-power balance is a genuine equality constraint (replacing today's free reactive-import slack), enforced in both centralized and ADMM solves | "Free slack, precisely located" + "Pattern 1" below: `:balance_q` is *already* a genuine equality in BOTH models today; the actual code change needed is turning the ADMM load-node injection from a `Float64` constant into a JuMP coupling variable `qag_dso[j,t]` (mirroring `pag_dso`), so the reactive price is obtained via the SAME trustworthy mechanism as the active DADP, not a raw `dual()` call on a lenient (`strict=false`) solve. |
| REACT-02 | A reactive nodal price `μ_j` (dual of the reactive balance) is extracted and contributes a documented reactive/voltage component to the DLMP decomposition in `pricing/dlmp.jl` | "Pattern 2" below: add a new function (or extend `decompose_dlmp`'s NamedTuple with a `reactive` field) reading `dual(ctx.constraints[:balance_q][j,t])`, gated by the SAME `_assert_priceable` PF-04 certificate `extract_dlmp`/`decompose_dlmp` already require. No existing test asserts a fixed NamedTuple shape (verified — safe to add a field). |
| REACT-03 | Reactive consensus rolls out without regressing the existing active-only ADMM path (feature-flagged/additive), with the `μ` naming collision resolved as the first design decision | "The `μ` Naming Collision" section below: full grep of every `μ`/`mu` binding in `src/`, confirming the SOLE existing meaning is the adaptive-ρ residual-balancing band (`solve_admm` kwarg → `Scenario.μ` → `Phase7Fixtures.MU`); recommend a distinct identifier and — critically — recommend NOT touching `Scenario.jl` at all this phase (see "Don't Hand-Roll" / Pitfall discussion) so the existing golden-hash surface is untouched by construction, the strongest possible non-regression guarantee. |
</phase_requirements>

## Standard Stack

No new external dependencies for this phase — confirmed by direct inspection: the entire reactive
consensus mechanism is an orchestration/formulation extension of code already resident in the
project (JuMP model construction + `dual()` reads), using solvers already pinned in `Project.toml`.

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | 1.30.1 `[VERIFIED: local Manifest, julia --project Pkg.status]` | The coupling variable `qag_dso[j,t]`, its objective-coefficient mutation, and `dual(:balance_q)` all use JuMP APIs already exercised identically for the active block (`pag_dso`/`:balance_p`) — zero new API surface. | Per CLAUDE.md — named-constraint dual access is the entire reason this project is JuMP-, not Convex.jl-, based; this phase is the textbook case. |
| Clarabel | 0.11.1 `[VERIFIED: local Manifest]` | Solves the (now slightly larger) DSO-OPT SOCP; already the SOCP factory default via `select_optimizer(SOCP())` — no solver-selection code changes. | Native conic IPM with accurate duals — the reactive price IS a dual, so solver-dual accuracy matters exactly as it does for the active DADP (CLAUDE.md: never use SCS for a "final" dual). |

### Supporting
No new supporting libraries. `select_optimizer`, `assert_solved!`, `assert_no_slack`,
`register_constraint!`, `add_to_residual!` are all reused verbatim from the existing `core/`/
`solver/` seams — this phase adds zero new infrastructure files.

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Reading `dual(:balance_q)` directly ("for free," per thesis A3) | A full live cross-subproblem μ dual-ascent loop (mirroring λ's outer-loop ascent) | Explicitly deferred by ROADMAP.md/STATE.md ("Deferred Items" table: "Live cross-subproblem reactive dual-ascent loop... deferred alongside meshed+4Q-BESS") — only needed once a real AGR-side reactive DECISION variable (4Q-BESS/volt-var) exists. Building it now is speculative machinery for a decision that doesn't yet exist. |
| A distinct reactive penalty `ρ_q` | Reusing the shared active-block `ρ` | Genuine open judgment call (STATE.md, MEDIUM confidence) — resolve empirically this phase (see "Open Questions"), do not assume either answer. |

**Installation:** none — no `Pkg.add` needed for this phase.

## Package Legitimacy Audit

Not applicable — this phase installs no external packages. `Package Legitimacy Gate` skipped per
its own trigger condition ("Every phase that installs external packages").

## Architecture Patterns

### System Architecture Diagram

```
                     solve_admm(feeder, ConvexBranchFlow(), aggregators;
                                reactive_consensus::Bool = false, ...)
                                        |
                     BUILD ONCE (outside the loop, ADMM-03)
                                        |
        +-------------------------------+-------------------------------+
        |                                                               |
  build_agr_opt(agg, T; ρ)                                    build_dso_opt(feeder, aggs, T; ρ, λ₀,
   -> AgrOpt                                                            reactive_consensus)
   .qag[t] = -Pdc[t]*tanφ  (CONSTANT,                                   -> DsoOpt
    per A3 -- no reactive DER decision)                        if reactive_consensus == false (DEFAULT):
        |                                                        q_draw[j][t] injected into :Rq[j]  (BYTE-
        |  agr.qag read as the FIXED consensus                   IDENTICAL to pre-milestone -- REACT-03)
        |  target b_j (never moves -- no live                  if reactive_consensus == true:
        |  ascent needed per A3)                                 qag_dso[j,t] (NEW JuMP variable) injected
        |                                                        into :Rq[j], pinned toward b_j = agr.qag[j][t]
        |                                                       :Rq[root] <- q_import[t] (free-sign, UNPRICED
        |                                                        -- the genuinely "free" quantity)
        |                                                       :Rq closed to 0 at ALL buses -> :balance_q
        |                                                        (ALREADY true even at reactive_consensus=false --
        |                                                        see "Free slack, precisely located")
        +-------------------------------+-------------------------------+
                                        |
                             ITERATE k = 1:maxiter (unchanged active loop;
                             reactive path adds no NEW outer-loop dual-ascent
                             -- per A3, b_j never moves, so the "consensus"
                             is trivially satisfied by construction)
                                        |
                          CONVERGED: final DSO-OPT re-solve
                          (check_exact=true, strict=false -- EXISTING)
                                        |
                    NEW: assert_no_slack on :balance_q (mirrors :balance_p
                    certificate) -- makes dual(:balance_q) trustworthy
                    DESPITE the lenient strict=false solve label
                                        |
                                        v
                    dual(dso_ctx.constraints[:balance_q][j,t])
                                        |
                                        v
         pricing/dlmp.jl: decompose_dlmp(ctx) gains a 5th field
              (; energy, loss, congestion, voltage, reactive, total)
                     <-- REACT-02's citable reactive DLMP
```

### Recommended Project Structure (delta only)

```
src/admm/
├── DsoOpt.jl        # MODIFIED -- reactive_consensus kwarg; qag_dso variable + objective
│                       term when true; byte-identical q_draw path when false (default)
├── AgrOpt.jl        # MODIFIED (docstring only) -- qag goes from "placeholder, unread" to
│                       "read as the fixed reactive consensus target, per A3"
├── solve_admm.jl    # MODIFIED -- reactive_consensus kwarg threaded to build_dso_opt; final
│                       block gains assert_no_slack on :balance_q when reactive_consensus=true
└── residuals.jl     # LIKELY UNCHANGED -- no live μ dual-ascent loop needed (see Pattern 3),
                        so no new q-residual trace fields are required THIS phase (contrast
                        with ARCHITECTURE.md's fuller mirror design, which assumed a live loop)

src/pricing/
└── dlmp.jl          # MODIFIED -- new `reactive` field in decompose_dlmp's NamedTuple (or a
                        new peer function `extract_reactive_dlmp`), gated by the SAME
                        `_assert_priceable` PF-04 certificate

test/
├── test_dso.jl              # MODIFIED -- reactive_consensus=true builder tests
├── test_admm.jl             # UNCHANGED -- default-path byte-identical regression (must stay green)
├── test_admm_adaptive.jl    # UNCHANGED -- same
├── test_ieee123_admm.jl     # UNCHANGED (default path) + NEW reactive_consensus=true variant
├── test_pricing_dlmp.jl     # MODIFIED -- new `reactive` field assertions, hand-computed 2-bus pin
└── test_admm_reactive.jl    # NEW -- one-file-per-ADMM-feature convention (mirrors
                                test_admm_adaptive.jl / test_admm_dualresid.jl)

NOT MODIFIED: src/experiments/Scenario.jl, src/experiments/run.jl, src/experiments/sweep.jl,
src/experiments/store.jl (deliberately out of scope -- see "Don't Hand-Roll")
```

### Free slack, precisely located (grounded in `src/admm/DsoOpt.jl` and `src/models/welfare_solve.jl`)

Direct inspection of both models shows the reactive closure is **already**:

```julia
# DsoOpt.jl (ADMM), build_dso_opt, TODAY (reactive_consensus doesn't exist yet):
@variable(model, q_import[t = 1:T])                    # FREE-SIGN, root ONLY, NO price term
add_to_residual!(ctx, :Rq, root, t, q_import[t])
for j in load_nodes, t in 1:T
    add_to_residual!(ctx, :Rq, j, t, q_draw[j][t])      # CONSTANT (Float64), not a JuMP variable
end
@constraint(model, balance_q[j = 1:N, t = 1:T], ctx.residuals[:Rq][j, t] == 0)   # ALREADY genuine equality, ALL buses
register_constraint!(ctx, :balance_q, balance_q)
```

The identical shape exists in `welfare_solve.jl` (centralized) — `q_import` free at root,
aggregator-contributed constant draw at every other bus, `:Rq` pinned to zero everywhere,
registered as `:balance_q`. **The "free slack" is precisely and only the root's `q_import`** — it
has zero coefficient in the objective (`welfare = ctx.meta[:objective] - Σ λ₀·p_import`, no `λ₀_Q`
term at all) and no bounds, so its own KKT stationarity condition forces
`dual(:balance_q[root,t]) ≡ 0` at any optimum (an expected, economically-correct degeneracy: no
reactive energy market exists at the substation in this model — consistent with the DLMP-Q
literature, where the "energy" component of a reactive price is typically null). For every
non-root load bus `j`, `dual(:balance_q[j,t])` is **already** a well-defined, non-degenerate shadow
price today — `grep -rn "balance_q" src/ test/` confirms `dual()` is never called on it anywhere in
the codebase. **This is the exact mechanism the FEATURES/SUMMARY research called "for free."**

### Pattern 1: Constant → coupling-variable promotion (the actual REACT-01 code change)

**What:** Even though `:balance_q` is already a genuine equality, its dual is only as trustworthy as
the solve it comes from. The ADMM `DsoOpt`'s FINAL consolidation solve currently runs with
`strict = false` (`assert_solved!(dso.model; dual = false, allow_almost = true)`,
`solve_admm.jl:392`) — it explicitly tolerates `ALMOST_OPTIMAL`/`NEARLY_FEASIBLE_POINT`, and its
docstring is explicit that `:balance_q`'s "NEARLY_FEASIBLE reactive slack... is intentionally not
gated... it is NOT published/load-bearing." Publishing `dual(:balance_q)` as a citable DLMP-Q
component (REACT-02) makes it exactly as load-bearing as `:balance_p`, which IS certified via
`assert_no_slack` after the final solve. Promoting the load-node constant `q_draw[j][t]` to a real
coupling variable `qag_dso[j,t]` (pinned toward the still-fixed target `b_j = agr.qag[j][t]`, since
there is no reactive DER decision per A3) is what makes `:balance_q` a first-class, certified
constraint on par with `:balance_p` — NOT a change to whether it's "an equality" (it already is),
but a change to whether its dual is *trustworthy and published-grade*.

**When to use:** Any time a previously-diagnostic-only constraint (`:balance_q`, unread) is promoted
to a published output (a citable DLMP-Q) — the certification bar must rise with it.

**Example (the minimal, additive diff on `build_dso_opt`):**
```julia
# NEW kwarg, default preserves today's exact behavior byte-for-byte:
function build_dso_opt(feeder, aggregators, T::Int; ρ::Real, λ₀, reactive_consensus::Bool = false)
    ...
    if reactive_consensus
        @variable(model, qag_dso[j = load_nodes, t = 1:T])
        for j in load_nodes, t in 1:T
            add_to_residual!(ctx, :Rq, j, t, qag_dso[j, t])
        end
    else
        for j in load_nodes, t in 1:T
            add_to_residual!(ctx, :Rq, j, t, q_draw[j][t])      # UNCHANGED default path
        end
    end
    # :balance_q registration, root q_import, transit-node zero-injection: UNCHANGED either way
end
```
Since `b_j` (the target) never moves (per A3, no live μ-ascent — see Pattern 3), `qag_dso[j,t]`
converges to `q_draw[j][t]` essentially immediately; the "consensus" is a formality that buys a
trustworthy, certified dual, not a behavior change to the physical solution.

### Pattern 2: Peer extraction function, mirroring `extract_dlmp` (REACT-02)

**What:** `pricing/dlmp.jl` already has a clean precedent — `_assert_priceable(ctx)` gates BOTH
`extract_dlmp` and `decompose_dlmp` on the PF-04 exactness certificate. Add the reactive price
through the SAME gate, reusing the SAME idiom, never inventing a second certification philosophy.

```julia
# Source: mirrors extract_dlmp's own shape (dlmp.jl:96-104), adding a presence guard for
# formulations without a reactive channel (haskey(ctx.constraints, :balance_q) == false, e.g. DC).
function extract_reactive_dlmp(ctx::ModelContext; bus = nothing, T = nothing)
    _assert_priceable(ctx)
    haskey(ctx.constraints, :balance_q) || throw(
        ArgumentError("extract_reactive_dlmp: ctx has no :balance_q -- this formulation has no " *
                      "reactive channel (e.g. DCPowerFlow); no reactive price exists to extract"),
    )
    bq = ctx.constraints[:balance_q]
    N, Tfull = size(bq)
    M = Float64[dual(bq[j, t]) for j in 1:N, t in 1:Tfull]
    bus === nothing && return M
    Tsel = T === nothing ? Tfull : Int(T)
    return M[bus, 1:Tsel]
end
```
Then extend `decompose_dlmp`'s return to `(; energy, loss, congestion, voltage, reactive, total)`
— `reactive = extract_reactive_dlmp(ctx)`, documented explicitly as a SEPARATE price signal from
the active 4-way split (it is NOT summed into `total`, which remains the ACTIVE nodal price;
conflating an active total with a reactive addend would be dimensionally and economically wrong).

**When to use:** Any new dual-based price this project ever adds — this is now the established,
reusable template (gate on `_assert_priceable`, mirror `extract_dlmp`'s shape, extend
`decompose_dlmp`'s NamedTuple additively).

### Pattern 3: No live μ dual-ascent loop needed (deliberate scope reduction vs. ARCHITECTURE.md)

**What:** ARCHITECTURE.md's same-day design proposed a full mirror of the active λ/ρ machinery: a
`μ` state dict, a reactive primal/dual residual pair, an extended `converged`/`record!` overload,
and a joint (p,q) stop criterion. Given `AgrOpt.qag` is a FIXED constant (no reactive DER decision
exists per A3 — explicitly, "Live cross-subproblem reactive dual-ascent loop... deferred," per
ROADMAP.md's own Deferred/Future-Milestone Notes), a live outer-loop ascent has nothing genuine to
iterate on: `b_j` never changes between iterations, so `qag_dso[j,t]` converges to it in O(1)
iterations regardless of any ascent mechanism. The FEATURES/SUMMARY research already names this
explicitly ("a full live mu dual-ascent loop may be unnecessary at all... yielding `mu_j =
dual(R_{q,j})` 'for free'"). This research's own code inspection reinforces that conclusion and
recommends the LIGHTER path: no new `residuals.jl` trace fields, no new stop-criterion AND clause —
just the coupling-variable promotion (Pattern 1) + the certificate (Pattern 1's `assert_no_slack`
addition) + the peer extraction function (Pattern 2).

**When to use:** Whenever a "consensus" target is provably fixed/degenerate — avoid building
dual-ascent machinery for a quantity that never needs ascending. Revisit ONLY when a genuine
AGR-side reactive decision variable exists (4Q-BESS/volt-var — explicitly a later milestone).

**Trade-off:** If a future milestone DOES introduce a live reactive decision, this lighter design
would need to be revisited (the coupling variable `qag_dso` and `:balance_q`'s registration are
forward-compatible with that extension; the ABSENCE of a dual-ascent loop is the only piece that
would need adding later — a strictly additive follow-up, not a rewrite).

### Anti-Patterns to Avoid

- **Reading `dual(:balance_q)` from today's `strict=false` final solve without adding a
  certificate.** This is the most likely near-miss failure mode: the constraint is already an
  equality, so it is tempting to just call `dual()` on it immediately. Without `assert_no_slack`
  parity with `:balance_p`, a genuinely near-infeasible final primal could silently publish a
  meaningless reactive price — exactly the WR-01 discipline `solve_admm.jl`'s own final block
  already documents for the active balance, now needed for `:balance_q` too since it becomes published.
- **Building the full ARCHITECTURE.md mirror design (μ state dict, joint residual balancing,
  extended `record!`/`converged` overloads) before confirming a live ascent is actually needed.**
  Per Pattern 3, it likely is not — implement the lighter path first, and only escalate to the
  fuller design if the empirical rho/mu-adequacy experiment (see Open Questions) shows the
  degenerate-target assumption doesn't hold at scale (e.g. numerical drift of `qag_dso` away from
  `b_j` under the shared `ρ` that the joint-residual Pitfall 4 in PITFALLS.md warns about).
- **Touching `src/experiments/Scenario.jl`/`run.jl`/`sweep.jl` this phase.** Nothing in
  REACT-01/02/03 requires it — the feature flag is a plain function kwarg on
  `build_dso_opt`/`solve_admm`, not a declarative `Scenario` selector. Adding it anyway (even a
  `reactive_consensus::Bool = false` field defaulting to today's behavior) changes DrWatson's
  `savename` string for **every existing pinned experiment**, since `Scenario`'s docstring is
  explicit that ALL fields participate in the default-allowed `savename` — a second, unrelated
  golden-hash perturbation this phase does not need to risk. Defer `Scenario` wiring to whichever
  future phase actually needs `run_scenario(:admm)` to exercise reactive consensus declaratively.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Reactive price certification | A new, bespoke slack-checking helper for `:balance_q` | `assert_no_slack(dso.model, balance_q[j,t]; atol=1e-6)` — the EXISTING `core/status.jl` function, already used for `:balance_p` | Single, tested, documented choke point (INFRA-03); a second bespoke checker would duplicate logic and could drift out of sync with the `:balance_p` certificate's semantics. |
| Q-price gating | A new "is this ctx priceable" check duplicating PF-04 logic | `_assert_priceable(ctx)` — already private to `dlmp.jl`, reused verbatim for the new `extract_reactive_dlmp` | One gate, one place a future formulation change (e.g. a new SOCP variant) needs updating. |
| Live reactive dual-ascent (if ever needed later) | A bespoke ascent loop distinct from the active block's | The EXISTING `λ` dual-ascent shape in `solve_admm.jl` (warm-start, per-unit-normalized stop, adaptive-ρ) — mirror it structurally, do not invent a new update rule | Boyd's ADMM theory is the same for any consensus block; a divergent update rule for Q would be an unjustified, untested departure from the one already cross-validated for P. |

**Key insight:** every piece REACT-01/02/03 needs already has a working, tested peer in this
codebase (`pag_dso`/`:balance_p`/`assert_no_slack`/`extract_dlmp` for the active block). The
discipline this phase requires is *reuse the peer mechanism exactly*, not design a parallel one —
consistent with the project's own "Feature-flagged structural change with a compatibility overload"
pattern (the Phase-6→7 `record!` 4-arg/8-arg precedent already in `residuals.jl`).

## The `μ` Naming Collision — Full Grep Audit (REACT-03's first design decision)

**Every existing binding of the bare identifier `μ` in the codebase**, confirmed via
`grep -rln "\bμ\b" src/ test/`:

| File | Binding | Meaning |
|------|---------|---------|
| `src/admm/solve_admm.jl:58,128` | `μ::Real = 10.0` kwarg | Boyd §3.4.1 residual-balancing imbalance BAND (`ρ ← τ·ρ` if `‖r‖ > μ·‖s‖`) — a scalar tuning knob, NOT a dual/price. |
| `src/admm/AgrOpt.jl` (docstring only) | "PLACEHOLDER for a FUTURE reactive-consensus (`μ` dual-ascent) extension" | The project's own prior docstring already primed the "reactive dual = μ" association — the root cause of the collision risk. |
| `src/admm/DsoOpt.jl` (docstring/comments) | "no μ dual-ascent — reactive is not a consensus quantity" | Same prior association, comment-only. |
| `src/experiments/Scenario.jl:106,190,211` | `μ::Float64 = 10.0` struct field | The SAME ρ-band scalar, threaded into the golden-hash-serialized `savename` schema (docstring: "sub-percent ADMM float knob... `ρ`/`ε_abs`/`ε_rel`/`τ_ratio`/`μ`"). |
| `src/experiments/run.jl:140` | `μ = s.μ` | Thread from `Scenario.μ` directly into `solve_admm`'s `μ` kwarg — confirms the ONE end-to-end semantic thread. |
| `test/fixtures_phase7.jl:49` | `const MU = 10.0` | Same ρ-band value (ASCII spelling in this fixture module). |
| `test/test_admm_adaptive.jl`, `test/test_ieee123_admm.jl`, `test/test_acceptance.jl` | usage sites | Consumers of the above, no independent meaning. |

**Conclusion:** today, EVERY `μ`/`mu` binding in the entire codebase means exactly one thing — the
adaptive-ρ residual-balancing band. There is currently zero collision (only one meaning exists);
the collision is prospective — it will exist the moment a reactive dual is introduced under the
same bare name. This confirms PITFALLS.md/ARCHITECTURE.md's claim precisely and gives the complete
grep-audit inventory the phase's Success Criterion #1 requires be produced "before any
`AgrOpt`/`DsoOpt` code changes land."

**Recommendation:** name the reactive dual/coupling-related identifiers distinctly and
unambiguously — e.g. `qag_dso` (the JuMP variable, Pattern 1; no Greek letter needed at all since
it's a coupling variable, not a dual), and, if a scalar/vector handle for the extracted price is
needed in code (as opposed to the `reactive` field name in `decompose_dlmp`'s NamedTuple, which
needs no Greek letter either), use `μq` or `mu_q` — never bare `μ`. This is the single item this
research recommends resolving with the discuss-phase/planner as an explicit, tiny decision (the
exact spelling is not load-bearing; the DISTINCTNESS from bare `μ` is).

## Common Pitfalls

### Pitfall 1: Publishing `dual(:balance_q)` without a slack certificate (new finding this session)
**What goes wrong:** The ADMM `DsoOpt` final consolidation solve uses `strict = false` (tolerates
`ALMOST_OPTIMAL`/`NEARLY_FEASIBLE_POINT`); today `:balance_q`'s slack is explicitly, deliberately
NOT checked because it isn't published. The moment REACT-02 makes `dual(:balance_q)` a citable
DLMP-Q component, that same leniency becomes a live risk: a near-infeasible reactive balance could
publish a numerically meaningless price with no error raised.
**Why it happens:** The existing code correctly reasoned "not published ⇒ don't need the
certificate"; REACT-02 changes that premise, but nothing forces a revisit of the accompanying gate.
**How to avoid:** Add `assert_no_slack(dso.model, balance_q[j,t]; atol=1e-6)` to the SAME final
block that already certifies `:balance_p`, activated whenever the reactive price will be reported
(i.e., whenever `reactive_consensus = true`).
**Warning signs:** A reactive DLMP value that jumps discontinuously between adjacent hours/runs with
no physical explanation — the signature of reading a dual off a near-infeasible point.
**Phase to address:** This phase (Phase 16), as part of REACT-02's certification, not a follow-up.

### Pitfall 2: Building the full μ dual-ascent mirror when a one-shot dual read suffices
See Pattern 3 above. Building `residuals.jl` q-traces, a joint stop criterion, and an ascent loop
for a target (`agr.qag`) that is fixed and never moves is unnecessary engineering effort and
introduces new convergence/scale-mismatch surface (PITFALLS.md's own Pitfall 4: two consensus
blocks under one shared `ρ`) for no behavioral benefit. Confirm empirically (Open Questions) before
building the heavier machinery.

### Pitfall 3: Touching `Scenario.jl`'s golden-hash surface unnecessarily
See "Anti-Patterns to Avoid" above — a second, avoidable savename perturbation. Keep the feature
flag at the `build_dso_opt`/`solve_admm` kwarg level only, this phase.

### Pitfall 4 (inherited from PITFALLS.md, re-confirmed against code): the `μ` naming collision
See the full grep-audit section above — this research CONFIRMS the collision claim with a complete
enumeration, satisfying REACT-03 Success Criterion #1's explicit "every existing mu usage grepped."

### Pitfall 5 (inherited, STATE.md flag): Clarabel `NUMERICAL_ERROR` flake re-measurement
**What goes wrong:** `.planning/STATE.md` documents an accepted, unresolved, intermittent, version-
independent Clarabel `NUMERICAL_ERROR` on the IEEE-13 ADMM solve (per-unit-base-dependent cone-slack
sensitivity). Adding `qag_dso` as a genuine decision variable in the SOCP subtly changes the cone's
conditioning (more free variables sharing the same SOC cone at each load node). STATE.md explicitly
requires this phase to re-measure the flake rate under Q-consensus, not assume v1.0's (or v2.0
Phase-12's toy-fixture) rate transfers — both explicitly do not cover this trigger.
**How to avoid / what to measure:** Run the existing `test_ieee123_admm.jl`/`test_admm.jl` fixtures
with `reactive_consensus=true` repeated N times (N ≥ 20 recommended, matching PITFALLS.md Pitfall
11's "repeated-run stability" discipline) on IEEE-13 AND IEEE-123, count `NUMERICAL_ERROR`
occurrences (via the existing fail-loud `ErrorException`/`assert_solved!` diagnostics), and compare
against a same-N baseline run of the UNCHANGED (`reactive_consensus=false`) path on the identical
fixtures/seeds. Report both rates explicitly in the phase's own findings — do not silently accept
or silently "fix" a change in rate without reporting it.
**Phase to address:** This phase, as an explicit, gating measurement task — not deferred.

### Pitfall 6 (inherited, PITFALLS.md Pitfall 11 applied here): repeated-run stability before pinning any new golden
Any NEW golden this phase pins (a hand-computed 2-bus reactive-price toy case, an IEEE-13/123
reactive-consensus regression) must be re-run multiple times with the same seed/Manifest and
confirmed stable BEFORE being committed — the same discipline already applied project-wide,
specifically flagged as elevated risk here because Q-consensus is a plausible new place for
solver-conditioning jitter to surface (Pitfall 5 above).

## Code Examples

### Reading the existing (already-registered) reactive balance dual — the "for free" mechanism
```julia
# Source: mirrors extract_dlmp (src/pricing/dlmp.jl:96-104); requires reactive_consensus=true
# on the ADMM path so the FINAL solve's :balance_q dual is certified (Pitfall 1), or works
# unconditionally on the ALREADY-strict centralized solve_welfare path (dual=true always there).
mu_q = extract_reactive_dlmp(ctx; bus = load_bus, T = T)
```

### Hand-computed 2-bus reactive-price sanity pin (recommended before trusting IEEE-13/123)
Mirror exactly how v1.0's own Pitfall 7 pinned the active DADP on a hand-solved 2-bus case: choose
a non-zero, analytically-known reactive requirement (`φ < 1`, i.e. `tanφ > 0`) on the trivial 2-bus
radial fixture already used by `test_ac_oracle.jl` (r=0.01, x=0.02), solve both centralized and
ADMM paths, and confirm `dual(:balance_q[2,t])` matches a hand-derived KKT value before trusting
the mechanism on IEEE-13/123 — the SAME validation discipline Phase 15 already applied to its own
new angle-recovery math.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Reactive draw as a fixed `Float64` constant injected into `:Rq[j]`, dual never read | A genuine JuMP coupling variable `qag_dso[j,t]`, `:balance_q` certified via `assert_no_slack`, dual published as a 5th DLMP component | This phase (Phase 16) | Reactive power becomes a priced, citable quantity — closing the `AgrOpt.jl` "placeholder, currently NOT read" gap named in its own docstring since Phase 6. |

**Deprecated/outdated:** none — this is a net-new capability, not a replacement of a previously
"correct" approach.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | A one-shot dual read off a promoted coupling variable is sufficient — no live μ dual-ascent loop is needed, because `AgrOpt.qag` never moves (per thesis A3) | Pattern 3 | If a future extension needs `qag` to be genuinely decided (not just promoted-but-fixed) sooner than expected, the lighter design would need the fuller ARCHITECTURE.md mirror (μ state, joint residual balancing) as a follow-up — additive, not a rewrite, but extra scope if the timeline compresses. |
| A2 | Sharing the active block's `ρ` for the (now real, if degenerate) reactive coupling constraint is adequate — no `ρ_q` needed, since `b_j` is fixed and `qag_dso` has nothing genuine to "fight" over | "Alternatives Considered" / Open Questions | If empirically the SOCP conditioning worsens under a shared `ρ` (Pitfall 4 in PITFALLS.md — apples-to-oranges P/Q residual scales), a distinct `ρ_q` may be required; this is exactly why STATE.md flags it MEDIUM confidence and demands an empirical resolution this phase, not an assumption. |
| A3 | The Clarabel `NUMERICAL_ERROR` flake rate will be measurably affected (likely increased) by adding `qag_dso` to the SOCP, but the magnitude is unknown until measured | Pitfall 5 | If the rate increases materially, this phase may need to also port a bounded retry ladder (mirroring `src/planning/retry.jl`'s `solve_with_retry!`) into `solve_admm` — a larger scope addition than currently planned; STATE.md explicitly names this as a live possibility. |
| A4 | `decompose_dlmp`'s NamedTuple can safely gain a new `reactive` field without breaking any existing caller | Pattern 2 | Verified — no test in `test/` asserts a fixed field count/shape on `decompose_dlmp`'s return (`grep` for `keys(`/`propertynames`/`fieldnames` against it returned zero matches). Low risk, but any external (non-test) caller outside this repo would be unaffected either way (additive field). |

## Open Questions

1. **Does a shared `ρ` (vs. a distinct `ρ_q`) keep the DSO-OPT SOCP well-conditioned once `qag_dso`
   is a genuine variable?**
   - What we know: `AgrOpt.qag`'s target never moves (A3), so the coupling constraint
     `qag_dso[j,t] ≈ b_j` should converge in very few iterations regardless of ρ scale — unlike the
     active block, which genuinely fights for a non-trivial consensus point.
   - What's unclear: whether adding this (even near-trivial) extra coupling dimension to the SAME
     SOC cone changes the cone's numerical conditioning enough to matter for the Clarabel flake
     (Pitfall 5) or for the adaptive-ρ residual-balancing logic (which currently normalizes by
     ε_pri/ε_dual computed ONLY from the active block's scale).
   - Recommendation: instrument BOTH a shared-`ρ` run and a separate-`ρ_q` run (start `ρ_q = ρ₀`,
     independent adaptive schedule) on the SAME IEEE-13/123 fixtures, side-by-side. Metric: iteration
     count to convergence, `qag_dso` residual to `b_j` at convergence, and the re-measured
     `NUMERICAL_ERROR` rate (Pitfall 5) under each. Pick whichever is simpler (shared `ρ`) UNLESS
     the separate-`ρ_q` run shows a measurably better conditioning/convergence outcome.

2. **What is the actual Clarabel `NUMERICAL_ERROR` rate under `reactive_consensus=true` on
   IEEE-13/123, relative to the existing (accepted) baseline rate?**
   - What we know: the baseline is described in STATE.md as rare, version-independent, root-caused
     to per-unit-base-dependent cone-slack sensitivity, and never fixed. The v2.0 Phase-12 toy
     fixture measured 0% escalation, but explicitly did NOT exercise the full SOCP oracle this
     concern is about.
   - What's unclear: the actual rate with a genuinely larger/more-coupled SOCP subproblem.
   - Recommendation: run N ≥ 20 repeats (same seeds, varying nothing else) of the IEEE-13 and
     IEEE-123 ADMM fixtures with `reactive_consensus=true`, count failures, and report the rate
     explicitly alongside the SAME measurement for `reactive_consensus=false` on the identical
     fixtures as a same-session baseline (isolates whether the Q-consensus change itself moved the
     rate, vs. ambient CI/machine variance).

## Environment Availability

Skip — no external dependencies beyond what's already pinned and verified in `Project.toml`/
`Manifest.toml` (JuMP 1.30.1, Clarabel 0.11.1, HiGHS 1.24.1, all confirmed present via
`Pkg.status` this session). This phase is a pure `src/` code change.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `TestItemRunner.jl` + `TestItems.jl` (`@testitem`/`@testmodule`, existing project convention — same as Phase 15) |
| Config file | `test/runtests.jl` (`@run_package_tests`, no separate config) |
| Quick run command | `julia --project -e 'using TestItemRunner, TSODSO; @run_package_tests filter=ti->occursin("admm", ti.name) \|\| occursin("dlmp", ti.name)'` (broad substring — narrow to `occursin("reactive", ti.name)` once the new `test_admm_reactive.jl` file exists and its items are named with that substring, mirroring the project's own documented per-feature filter convention) |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` (matches `julia-actions/julia-runtest@v1` in `.github/workflows/CI.yml`) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REACT-01 | With `reactive_consensus=false` (default), `build_dso_opt`/`solve_admm` produce a BYTE-IDENTICAL model/result to today (existing `test_admm.jl`, `test_admm_adaptive.jl`, `test_ieee123_admm.jl`, `test_dso.jl` pass UNCHANGED); with `reactive_consensus=true`, `:balance_q` closes via a genuine `qag_dso[j,t]` variable in both centralized (already true, no change needed) and ADMM solves | unit + integration (regression) | `julia --project -e 'using TestItemRunner, TSODSO; @run_package_tests filter=ti->occursin("admm", ti.name) \|\| occursin("dso", ti.name)'` | Partial — existing regression files ✅ exist and must stay green; new `reactive_consensus=true` assertions ❌ Wave 0 (need adding to `test_dso.jl`/new `test_admm_reactive.jl`) |
| REACT-02 | `decompose_dlmp(ctx)` returns a NEW `reactive` field = `dual(:balance_q)`, gated by the SAME PF-04 certificate as `energy`/`loss`/`congestion`/`voltage`; hand-computed 2-bus sanity pin matches | unit | `julia --project -e 'using TestItemRunner, TSODSO; @run_package_tests filter=ti->occursin("dlmp", ti.name)'` | ❌ Wave 0 — `test_pricing_dlmp.jl` needs new assertions; `test_dlmp.jl` may need a RED-then-green item mirroring its own Phase-5 precedent |
| REACT-03 | Default-path byte-identical regression (see REACT-01's first clause) + the `μ` naming-collision grep-audit is documented BEFORE any `AgrOpt`/`DsoOpt` diff lands + a distinct identifier is chosen and used consistently | regression + manual review gate | Same commands as REACT-01, PLUS a manual/plan-checker review step confirming the grep-audit (this document's own "μ Naming Collision" section) was read and a distinct name chosen before the first code-changing task | Regression tests ✅ exist; the naming-collision review is a PLANNING/task-ordering gate, not a runnable test — the plan MUST sequence "pick + document the identifier" as its own first task, blocking all subsequent `AgrOpt`/`DsoOpt` diffs |

### Sampling Rate
- **Per task commit:** the relevant filtered `@run_package_tests` command above (seconds, small
  fixtures — 2-bus, IEEE-13).
- **Per wave merge:** full `Pkg.test()` (catches any accidental perturbation of the UNCHANGED
  default-path regression suite via a stray shared-code edit).
- **Phase gate:** full `Pkg.test()` green, PLUS the empirical flake-rate re-measurement (Open
  Question 2 / Pitfall 5) explicitly run and its result recorded in the phase's own findings —
  this is a REQUIRED gating measurement, not merely a test that must pass, since there is no
  "correct" pass/fail threshold pre-defined; the number itself is the deliverable (mirroring how
  Phase 15 treats a genuine SOCP inexactness as a citable finding, not a bug).

### Wave 0 Gaps
- [ ] `test/test_admm_reactive.jl` — NEW, covers REACT-01/03 (mirrors `test_admm_adaptive.jl`'s
      structure: RED-guarded `isdefined` checks on the new kwarg/behavior, then behavioral asserts)
- [ ] `test/test_dso.jl` — MODIFIED, new `reactive_consensus=true` builder-shape assertions
      (mirrors the existing `@test haskey(dso.ctx.constraints, :balance_q)` pattern already there)
- [ ] `test/test_pricing_dlmp.jl` — MODIFIED, new `reactive` field assertions + a hand-computed
      2-bus reactive-price pin (mirrors the file's own existing 2-bus/IEEE-13 structure)
- [ ] A repeated-run (N≥20) flake-rate measurement harness/script — not a `@testitem` per se
      (long-running, not meant for every CI push) but should be a documented, re-runnable script
      (mirroring `scripts/*.jl`'s existing convention) whose OUTPUT (the measured rate) is recorded
      in the phase's own completion notes
- [ ] Framework install: none — `TestItemRunner`/`TestItems` already project dev-deps

## Security Domain

`security_enforcement` is absent from `.planning/config.json` — treated as enabled per the
instruction, but (mirroring Phase 15's own, still-accurate assessment) this phase is a pure
numerical-optimization/pricing-extraction change with no network, auth, session, or
untrusted-input surface.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | N/A — no user-facing auth surface anywhere in this codebase |
| V3 Session Management | No | N/A |
| V4 Access Control | No | N/A |
| V5 Input Validation | Marginal | The new `reactive_consensus::Bool` kwarg is a simple boolean toggle with no untrusted-input path; `Feeder`/`Aggregator` construction already enforces the relevant invariants (radial topology, per-unit magnitudes) upstream of this change. |
| V6 Cryptography | No | N/A |

### Known Threat Patterns for this stack
Not applicable — local, offline, single-researcher numerical codebase, no network-facing
component. The project's own "threat" numbering (`T-06-xx`, `WR-01`, etc.) is the operative
correctness-discipline vocabulary here, not STRIDE-style web threat modeling; the relevant
"threats" for this phase are the numerical-trust pitfalls documented above (publishing an uncertified
dual, silently perturbing an unrelated golden-hash schema), not security vulnerabilities.

## Sources

### Primary (HIGH confidence)
- Direct source inspection this session (grepped/read line-by-line, not summarized):
  `src/admm/AgrOpt.jl`, `src/admm/DsoOpt.jl`, `src/admm/solve_admm.jl`, `src/admm/residuals.jl`,
  `src/pricing/dlmp.jl`, `src/models/welfare_solve.jl`, `src/experiments/Scenario.jl`,
  `src/experiments/run.jl`, `src/core/status.jl`, `src/powerflow/AbstractPowerFlow.jl`,
  `src/devices/Aggregator.jl` (partial, `reactive_factor`), `test/test_admm.jl`,
  `test/test_admm_adaptive.jl`, `test/test_ieee123_admm.jl`, `test/test_dso.jl`,
  `test/test_pricing_dlmp.jl`, `test/fixtures_phase7.jl`.
- `julia --project=. -e 'using Pkg; Pkg.status(["JuMP","Clarabel","HiGHS"])'` — VERIFIED version
  pins (JuMP 1.30.1, Clarabel 0.11.1, HiGHS 1.24.1) against the LIVE resolved `Manifest.toml`, this
  session (not merely re-cited from the registry).
- `grep -rln "\bμ\b" src/ test/` and `grep -rn "balance_q" src/ test/` — the full-codebase audits
  underpinning the "μ Naming Collision" and "Free slack, precisely located" sections.
- `.planning/STATE.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` — phase scope,
  Deferred Items table (live μ dual-ascent loop explicitly deferred), STATE.md's two Phase-16 flags
  (rho/rho_q; Clarabel flake re-measurement).
- `.github/workflows/CI.yml` — confirms `julia-actions/julia-runtest@v1` is the full-suite CI
  command mirrored in the Validation Architecture section.

### Secondary (MEDIUM confidence)
- `.planning/research/SUMMARY.md`, `ARCHITECTURE.md`, `PITFALLS.md` (same-day prior research pass)
  — used as a starting hypothesis, then CORRECTED where direct code inspection diverged (the "free
  reactive-import slack" framing; the scope of the μ dual-ascent machinery — see the correction
  notice at the top of this document). Their pitfall catalogue (naming collision, Clarabel flake,
  golden re-pinning discipline) is otherwise confirmed accurate and reused verbatim.
- `.planning/phases/15-ac-exactness-oracle/15-RESEARCH.md` — mirrored for the Validation
  Architecture / test-filter-command conventions (same project, adjacent phase, consistent style).

### Tertiary (LOW confidence)
- None — every claim in this document was either directly verified against source/test files this
  session or explicitly flagged as an open empirical question for the phase itself to resolve.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new dependencies, versions verified against the live Manifest.
- Architecture: HIGH — every design claim traces to a specific file/line read this session; the one
  correction to the prior same-day research (the "free slack" framing) is itself grounded in a
  direct code read, not a re-guess.
- Pitfalls: HIGH on project-specific contracts (read directly); MEDIUM on the two genuinely open
  empirical questions (shared vs. distinct `ρ_q`; the re-measured Clarabel flake rate) — both are
  correctly scoped as THIS PHASE's own measurement tasks, not something research can resolve by
  reading code.

**Research date:** 2026-07-25
**Valid until:** 14 days (this phase is scheduled to execute imminently per STATE.md's "Operator
Next Steps"; the codebase is under active same-week development, so a longer validity window is
not warranted — re-verify the `μ`/`balance_q` grep audits if execution slips past two weeks).

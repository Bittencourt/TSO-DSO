# Phase 19: 4Q-BESS + Live Reactive Dual-Ascent - Research

**Researched:** 2026-08-07
**Domain:** Brownfield extension of a validated Julia/JuMP ADMM operational layer — a new
apparent-power-cone battery device + promoting a one-shot dual read to a genuine two-block
dual-ascent loop.
**Confidence:** HIGH (architecture/integration mechanics, code seams — all read directly from
this repo) / MEDIUM (two-block ADMM convergence theory — standard decomposition results,
not independently re-verified against a specific paper this session) / MEDIUM (4Q
complementarity derivation shape — the skeleton is derivable from the existing App. C argument
by direct algebraic extension, but the negative-price boundary characterization is genuinely
new model-math for this project)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** `FourQuadBESS` is a **standalone battery + 4Q inverter** — no PV field. PV-owning
  prosumers keep using `PVBattery` alongside it.
- **D-02:** **Grid charging, capped**: net active power is sign-free (the battery may import),
  but with an explicit charge-rate cap separate from discharge — asymmetric bounds
  (`Pch_max` ≠ `Pdch_max` permitted). Assumption A6 (charge-from-PV-only) is documented as
  `PVBattery`-specific, deliberately not inherited.
- **D-03:** **q is free inside the cone** — no cost/utility term on reactive power in the device
  objective. Its "price" is purely the reactive nodal dual μ. When μ ≈ 0, q can be
  non-unique/degenerate — cross-validation compares **welfare and prices, not q trajectories**.
- **D-04:** Internal structure keeps the **`p_ch`/`p_dch` ≥ 0 split with net injection
  `p = p_dch − p_ch`** entering the cone — the only convex way to model round-trip efficiency
  η < 1 in the SOC recursion (mirrors `PVBattery`'s eq. 3.6 pattern).
- **D-05:** **Both routes**: re-derive the conditions under which `p_ch·p_dch = 0` holds at the
  optimum for the 4Q grid-charging case (the App. C argument does NOT transfer), document the
  derivation beside the code, AND run the hard post-solve numeric check on every solve
  regardless.
- **D-06:** **Throw by default, kwarg to report**: the check throws on violation, with a
  documented kwarg (mirroring `assert_socp_exact!`'s `rtol_exact` diagnostic-neutralization
  pattern) letting research runs observe violations without modifying `src/`.
- **D-07:** The check is a **new named, exported certificate function** — a peer of
  `assert_socp_exact!`/`assert_ac_exact!` — with its **own tolerance** in the WR-01 scale-free
  idiom (`atol + rtol·magnitude`). Never a reused tolerance. Reusable by Phase 23.
- **D-08:** If the derivation shows violations are genuinely possible in-scope: **honest
  finding + documented boundary** — characterize the violating regime as a first-class finding,
  let the certificate throw there. No constructor parameter restrictions beyond what the
  derivation justifies.
- **D-09:** Devices hand reactive power to the Aggregator via an **optional `q_inject` field** in
  the aggregatable-device return contract: `(; vars, p_inject, q_inject, utility)`, where a
  device that omits `q_inject` contributes zero reactive. **Existing devices stay untouched**
  (absent = zero).
- **D-10:** `:Rq` composition is **purely additive on top of untouched code**:
  `:Rq = −Pdc·tanφ + Σ device q_inject`. The existing inelastic power-factor term is not
  refactored.
- **D-11:** **μ and device q are first-class result outputs, peers of λ**: reactive
  price-per-bus-per-hour and 4Q device q trajectories land in the same results/DataFrame surface
  the active DADPs use today.
- **D-12:** **Promote `reactive_consensus` to a 3-state mode** (e.g. `:off | :certified | :live`)
  with `Bool` still accepted for back-compat (`false → :off`, `true → :certified`). Default
  remains off / byte-identical; existing v2.1 tests must pass unmodified via back-compat mapping.
- **D-13:** **Small radial fixture is the primary CI-gated evidence** for μ-ascent convergence +
  cross-validation (with a `FourQuadBESS` present); IEEE-13 runs as supporting evidence under the
  existing bounded-retry quarantine (quick task 260726-vn2 pattern). Do not gate CI on IEEE-13.
- **D-14:** **Acceptance gate = welfare + λ + μ agreement** vs the centralized solve, each with
  its own newly-measured tolerance (measurement-before-golden). μ matching IS the deliverable.
  If the fixture shows genuine μ degeneracy, document the honest boundary rather than force a
  match.
- **D-15:** **Docs this phase: rich docstrings + the 4Q complementarity derivation note beside
  the code** (house style). No standalone literate page now (that is Phase 23's MESH-06).

### Claude's Discretion

- Exact two-block convergence/stopping treatment math (which residuals, update rule for μ,
  whether the reactive block gets its own ρ) — research question; roadmap only forbids the
  single-block Boyd rule as-is.
- μ initialization / warm-start (e.g. from the `:certified` one-shot read) — implementation
  choice.
- Utility parametrization of the 4Q battery's charge/discharge preference (whether App. C's
  λ-triple shape is reused with new derivation, or a different concave form) — must serve the
  D-05 derivation.
- Naming of the new device struct, certificate function, and mode symbols.
- Whether AGR-OPT's per-node subproblem becoming conic (SOCP) when a 4Q device is present needs
  any solver-path adjustment (Clarabel handles both).

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope. Meshed formulation, angle-recoverability
certificate, and the combined literate page are already scoped to Phase 23; overvoltage
restriction to Phase 20.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MESH-04 | 4Q-BESS device exposes sign-free P/Q inside an inverter apparent-power cone `p²+q²≤S²max`, flowing device→aggregator→`:Rq`; no-binaries complementarity re-derived or hard-checked, never silently inherited | § Architecture Patterns (device struct + cone constraint), § Don't Hand-Roll, § Common Pitfalls #1/#2, § Code Examples (SOC-cone idiom from `ConvexBranchFlow.jl`/`dlmp.jl`), § Complementarity Derivation Skeleton |
| MESH-05 | Live reactive μ-dual-ascent on `:balance_q` using `qag_dso`/`reactive_consensus`, converging inside `solve_admm` on a fixture with `FourQuadBESS`, cross-validated against centralized, own two-block stopping treatment | § Architecture Patterns (two-block ADMM), § Common Pitfalls #3/#4, § Validation Architecture, § Code Examples (residual/record! extension) |
</phase_requirements>

## Summary

This phase is a well-precedented extension of machinery that already exists in this codebase,
not a new architecture. Two independent deliverables share one integration seam
(`Aggregator.contribute!`'s device roll-up) and one shared outer loop (`solve_admm`'s ADMM
iteration), and both must land byte-identical-by-default on top of already-shipped v1.0–v2.1
regression goldens.

**4Q-BESS (MESH-04).** The apparent-power cone `p²+q²≤S²max` is *exactly* the same JuMP idiom
already shipped twice in this codebase: `ConvexBranchFlow.jl`'s per-branch `smax` limit
(`[B[b].smax, P[b,t], Q[b,t]] in SecondOrderCone()`, `ConvexBranchFlow.jl:189` area) and its dual
extraction in `dlmp.jl:182` (`dual(smax[b,t])[2]`). No new solver, no new JuMP feature — Clarabel
already natively solves this cone and returns accurate duals. The genuinely new work is NOT the
cone; it is (a) widening the aggregatable-device contract to carry reactive power for the first
time (currently `PVBattery`/`Thermostatic`/`Deferrable` return only `p_inject`), and (b)
re-deriving `PVBattery`'s App. C no-binaries argument, which is explicitly a **one-dimensional**,
active-power-only strict-cost-ordering proof (`λ_min < λ_med < λ_max` — see `PVBattery.jl:42-57`)
that provably does **not** transfer once a genuine P-Q coupling and asymmetric grid-charging caps
are introduced (this is PITFALLS.md's Pitfall 16, called out by name for this exact phase).

**Live reactive dual-ascent (MESH-05).** `solve_admm.jl` already has a fully worked, heavily
commented single-block Boyd two-residual (primal + dual) stopping rule with adaptive ρ
(`solve_admm.jl:260-359`). `DsoOpt.jl`'s `reactive_consensus::Bool` kwarg already promotes the
constant reactive draw to a genuine JuMP coupling variable `qag_dso[j,t]`, but pins it with a
hard equality (`:qag_pin`, `qag_dso[j,t] == q_draw[j][t]`) rather than dual-ascending it — this is
explicitly documented in-file as "a ONE-SHOT certified dual read, NOT a live μ dual-ascent loop."
Making it live means removing the pin, introducing a second coupling variable + dual-ascent block
for reactive power, and — critically — **not** reusing the existing single-block residual/ρ
machinery unmodified. The existing stopping rule is derived for ONE coupling block; a genuinely
independent per-block ε-check on two simultaneously-ascending blocks is a textbook false-
convergence risk (Boyd §3.3's own multi-block caveat), which is why PITFALLS.md's Pitfall 17
forbids reusing it "as-is."

**Primary recommendation:** Ship both deliverables as strictly additive code on unmodified
existing builders — new device file, new `q_inject` optional field (absent ⇒ zero, so
`PVBattery`/`Thermostatic`/`Deferrable` need zero changes), a new certificate function (never
`assert_battery_complementarity!`'s tolerance), and a `reactive_consensus` mode promotion
(`Bool` still accepted) that only activates new code paths — never mutates the existing
`:certified`/pinned path. Ground the two-block stopping rule in a STACKED joint residual over both
(λ, μ) blocks (Boyd §3.3-style), not two independent scalar checks, and validate liveness with a
regression that two runs differing only in the reactive coupling target converge to different
μ/q trajectories (mirroring the project's own CR-01 "tests passing ≠ mechanism live" lesson).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| 4Q-BESS device model (SOC recursion, apparent-power cone, utility) | Device layer (`src/devices/`) | — | Network-agnostic, aggregatable-device contract (AbstractDevice variant 2); never touches network/residuals directly |
| `q_inject` roll-up into `:Rq` | Aggregator layer (`src/devices/Aggregator.jl`) | — | LOCKED since v1.0: Aggregator is the SOLE `:Rp`/`:Rq` writer; devices never write residuals |
| 4Q complementarity certificate | Models/certification layer (`src/models/exactness.jl` peer, or a new sibling file) | Device layer (constructor guard, if the derivation finds a sufficient parameter condition) | Mirrors `assert_socp_exact!`/`assert_battery_complementarity!`'s existing home; post-solve numeric checks live beside the other price-refusal gates |
| Apparent-power SOC cone (device-level, per-device `Smax`) | Device layer (inside `FourQuadBESS.contribute!`) | AGR-OPT build (`src/admm/AgrOpt.jl`, becomes conic when device present) | The cone constraint is added where the device's own variables live; AGR-OPT's problem-class dispatch (QP vs SOCP) is a downstream consequence, not a separate design decision |
| Live μ dual-ascent update + two-block stopping rule | ADMM orchestration layer (`src/admm/solve_admm.jl`) | DSO-OPT (`src/admm/DsoOpt.jl`, unpins `qag_dso`) | `solve_admm` already owns ALL dual-ascent/residual/ρ logic for the active block; the reactive block is a peer addition in the same outer loop, not a new orchestrator |
| μ / q first-class result surface (D-11) | Pricing/results layer (`src/pricing/dlmp.jl` peer function, or `solve_admm`'s return tuple) | ADMM orchestration (must plumb μ, q out of the loop state) | `extract_reactive_dlmp` already exists for the centralized path; the ADMM path currently has no μ output at all — a genuine gap this phase must close |
| Reactive-consensus mode promotion (`:off\|:certified\|:live`) | ADMM orchestration (`solve_admm` kwarg surface) + DSO-OPT (`build_dso_opt` kwarg surface) | — | Both files already share the `reactive_consensus::Bool` kwarg; the 3-state promotion touches both call sites symmetrically |

## Standard Stack

**No new packages.** This phase is pure additive code on the existing, already-`Project.toml`-pinned
stack (Clarabel, JuMP, HiGHS unused here). This matches the v3.0 research SUMMARY.md's finding
that four of five v3.0 axes (including this one) need zero new dependencies.

### Core (unchanged, already in `Project.toml`)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Clarabel.jl | 0.11.1 [CITED: `.planning/research/SUMMARY.md`, fetched from the Julia General registry 2026-07-26 — not independently re-verified this session] | Solves both the existing per-branch `smax` SOC cone and the new device-level apparent-power cone `p²+q²≤S²max`; native quadratic-objective + SOC support; accurate duals (the reactive price IS a dual) | Already the project's SOCP/QP backend (`select_optimizer(SOCP())`/`select_optimizer(QP())` both dispatch to Clarabel); no new solver capability is needed — `SecondOrderCone()` inside a device's `contribute!` is the identical JuMP idiom already used in `ConvexBranchFlow.jl` |
| JuMP | 1.30.1 [CITED: CLAUDE.md stack table] | `@constraint(m, [Smax, p, q] in SecondOrderCone())` for the 4Q cone; `dual(...)` for μ; `set_objective_coefficient` for the live ascent | Unchanged modeling layer |

No Package Legitimacy Audit is required — **zero new external packages are recommended by this
research.** If the planner or a downstream implementer considers ANY new dependency for this
phase (e.g., a specialized SOCP-warm-start helper), it must go through the full Package
Legitimacy Gate protocol before being added — none was needed for the research pass itself.

## Architecture Patterns

### System Architecture Diagram

```
                         DEVICE LAYER (network-agnostic)
        ┌─────────────────────────────────────────────────────────┐
        │  FourQuadBESS.contribute!(d, ctx; T)                    │
        │    creates: p_ch[t]≥0, p_dch[t]≥0 (asymmetric caps),    │
        │             soc[t], q[t] (free, sign-free)              │
        │    adds:    SOC recursion (η<1), apparent-power cone    │
        │             [Smax, p_dch[t]-p_ch[t], q[t]] in SOC()      │
        │    returns: (; vars, p_inject, q_inject, utility)  ◄────┼─ NEW optional field (D-09)
        └───────────────────────┬───────────────────────────────--┘
                                 │  q_inject (NEW), p_inject (existing)
                                 ▼
                       AGGREGATOR LAYER (sole :Rp/:Rq writer)
        ┌─────────────────────────────────────────────────────────┐
        │  Aggregator.contribute!(agg, ctx; T)                    │
        │    Σ_d p_inject_d − Pdc  → :Rp   (unchanged, 3.22)      │
        │    Σ_d q_inject_d − Pdc·tanφ → :Rq  (D-10: additive)    │
        │    stash device vars → post-solve complementarity check│
        └───────────────────────┬───────────────────────────────--┘
                                 │  :Rp, :Rq residuals at agg.bus
                                 ▼
       ┌─────────────────────────────────────────────────────────────────┐
       │        ADMM OUTER LOOP  (solve_admm.jl — build once, re-solve)  │
       │                                                                 │
       │  AGR-OPT[j] (per node, now conic if 4Q present)                 │
       │    max U_ag − (ρ/2)‖pag+c‖² [− (ρ_q/2)‖qag+c_q‖² if live] ◄──── │  NEW reactive penalty
       │    battery complementarity gate (check_battery=true, final)    │
       │                          │  a_j = pag, [b_j = qag if live]     │
       │                          ▼                                     │
       │  DSO-OPT (whole network SOCP)                                  │
       │    :Rp[j]+pag_dso[j,t]=0 (existing coupling)                   │
       │    :Rq[j]+qag_dso[j,t]=0 (existing, currently PINNED)      ◄── │  UNPIN when :live
       │                          │  pag_dso, qag_dso                   │
       │                          ▼                                     │
       │  JOINT residual (STACKED λ+μ, RESEARCH q's — see below)        │
       │    r=[r_p; r_q], s=[s_p; s_q]  →  ONE ε_pri/ε_dual check   ◄──  │  NEW: not 2 indep checks
       │                          │                                     │
       │           λ ← λ + ρ·r_p   (existing)                           │
       │           μ ← μ + ρ_q·r_q (NEW — same or separate ρ, RESEARCH) │
       └──────────────────────────┬──────────────────────────────────--┘
                                   │  converged (λ, μ, welfare)
                                   ▼
                    RESULTS SURFACE (D-11: μ, q peers of λ)
       ┌─────────────────────────────────────────────────────────────────┐
       │  solve_admm(...) return tuple gains μ (reactive DADP matrix)    │
       │  and per-device q trajectories — same shape convention as λ    │
       └─────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
       ┌─────────────────────────────────────────────────────────────────┐
       │  CROSS-VALIDATION vs centralized solve_welfare (D-14)           │
       │    welfare ≈ welfare_centralized                                │
       │    λ       ≈ extract_dlmp(centralized)                         │
       │    μ       ≈ extract_reactive_dlmp(centralized)                │
       │    (q trajectories NOT compared — D-03 degeneracy)              │
       └─────────────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

```
src/
├── devices/
│   ├── FourQuadBESS.jl          # NEW — struct + contribute! (mirrors PVBattery.jl layout)
│   ├── Aggregator.jl            # MODIFIED — widen contract to read optional q_inject (D-09/D-10)
│   └── AbstractDevice.jl        # MODIFIED — docstring update documenting the widened contract
├── models/
│   └── exactness.jl             # peer file: add assert_4q_complementarity! (or a new sibling
│                                 #   file next to it) — NEVER touches assert_socp_exact!/
│                                 #   assert_battery_complementarity!
├── admm/
│   ├── AgrOpt.jl                # MODIFIED — device-driven SOCP dispatch when 4Q present;
│                                 #   optional reactive penalty block when mode == :live
│   ├── DsoOpt.jl                # MODIFIED — reactive_consensus Bool→3-state; unpin qag_dso
│                                 #   under :live (remove :qag_pin equality, add μ-ascent target)
│   ├── solve_admm.jl            # MODIFIED — joint (λ,μ) residual/stopping/adaptive-ρ under
│                                 #   :live; μ/q added to the return tuple (D-11)
│   └── residuals.jl             # POSSIBLY MODIFIED — a stacked-block record!/converged
│                                 #   variant, OR reuse the existing 8-arg record! by pre-
│                                 #   stacking the (λ,μ) norms before calling it (RESEARCH q)
└── pricing/
    └── dlmp.jl                  # POSSIBLY MODIFIED — an ADMM-side μ/q extraction peer to
                                 #   extract_reactive_dlmp (which is centralized-ctx-only today)
```

### Pattern 1: Apparent-power SOC cone (device-level) — direct reuse of an existing idiom

**What:** `p² + q² ≤ S²max` as a JuMP `SecondOrderCone()` constraint, exactly the pattern already
shipped for the branch apparent-power limit.
**When to use:** Any device (or branch) needing a capability curve rather than independent P/Q
bounds.
**Example (existing code, the template to copy):**
```julia
# Source: src/powerflow/ConvexBranchFlow.jl (forward apparent-power limit, thesis 3.36)
@constraint(
    m,
    smax[b = 1:nB, t = 1:T; feeder.branches[b].smax < Inf],
    [B[b].smax, P[b, t], Q[b, t]] in SecondOrderCone()
)
register_constraint!(ctx, :smax, smax)   # dual feeds the congestion DLMP component
```
For `FourQuadBESS`, the analogous device-level constraint (net active `p = p_dch - p_ch` as an
`AffExpr`, reactive `q` a free variable):
```julia
# NEW pattern for FourQuadBESS.contribute! — same idiom, device-scoped
p = @expression(m, [t = 1:T], p_dch[t] - p_ch[t])
q = @variable(m, [t = 1:T])   # sign-free (D-03: no cost term on q)
@constraint(m, cone[t = 1:T], [d.Smax, p[t], q[t]] in SecondOrderCone())
```
**Dual extraction** (if the device-level cone dual is ever needed — D-03 says compare
welfare/prices, not q, so this is likely NOT needed for the deliverable, but the idiom exists):
```julia
# Source: src/pricing/dlmp.jl:182 — SecondOrderCone dual slot convention
dual(cone[t])[2]   # slot 1 = Smax-side, slot 2 = p, slot 3 = q
```

### Pattern 2: Widened aggregatable-device contract (optional field, absent = zero)

**What:** `(; vars, p_inject, q_inject, utility)` with `q_inject` optional.
**When to use:** Any device that has a genuine reactive decision (currently only `FourQuadBESS`).
**Example:**
```julia
# NEW — FourQuadBESS.contribute! return
return (; vars = (; p_ch, p_dch, soc, q), p_inject, q_inject = q, utility)

# MODIFIED — Aggregator.contribute! roll-up (D-09/D-10), additive only
for d in agg.devices
    res = contribute!(d, ctx; T = T)
    for t in 1:T
        p_inject[t] += res.p_inject[t]
        # NEW: absent q_inject contributes zero — existing devices (PVBattery, Thermostatic,
        # Deferrable) return a NamedTuple with no q_inject key, so hasproperty guards this.
        if hasproperty(res, :q_inject)
            q_inject[t] += res.q_inject[t]
        end
    end
    ...
end
...
add_to_residual!(ctx, :Rq, agg.bus, t, -agg.Pdc[t] * tanφ + q_inject[t])   # D-10, additive
```
This is the load-bearing byte-identical-default mechanism (D-09/D-10 combined): every existing
device's contract is untouched, `hasproperty` fails safe to the old behavior, and the additive
`:Rq` composition means the default (no 4Q device) path reproduces the current expression
byte-for-byte.

### Pattern 3: 3-state reactive-consensus mode with Bool back-compat (D-12)

**What:** Promote `reactive_consensus::Bool` to a 3-state mode while keeping every existing call
site working unchanged.
**Example:**
```julia
# NEW — a small mode type or Symbol-based enum, normalized at the top of both build_dso_opt
# and solve_admm
@enum ReactiveMode OFF CERTIFIED LIVE
normalize_reactive_mode(m::Bool) = m ? CERTIFIED : OFF   # back-compat (D-12)
normalize_reactive_mode(m::ReactiveMode) = m
normalize_reactive_mode(m::Symbol) =
    m === :off ? OFF : m === :certified ? CERTIFIED : m === :live ? LIVE :
    throw(ArgumentError("reactive_consensus mode must be :off|:certified|:live (or Bool); got $m"))
```
Both `build_dso_opt(...; reactive_consensus = false)` (existing call sites) and
`build_dso_opt(...; reactive_consensus = :live)` (new) then dispatch off the SAME normalized
3-state value — `OFF` reproduces today's constant-injection path, `CERTIFIED` reproduces today's
pinned-`qag_dso` path (`:qag_pin` equality kept), `LIVE` is the new unpinned path.

### Two-block ADMM stopping rule — the genuinely open research question

`solve_admm.jl`'s existing rule (lines 260-359) computes, for the SINGLE active-power coupling
block:

```
r_norm = ‖a − pag_dso‖₂            (primal, Boyd eq. 3.11 form)
s_norm = ρ·‖pag_dso − pag_dso_prev‖₂  (dual, z-block)
ε_pri  = √p·ε_abs + ε_rel·max(‖a‖, ‖pag_dso‖)
ε_dual = √p·ε_abs + ε_rel·‖λ‖
converged ⟺ r_norm ≤ ε_pri  AND  s_norm ≤ ε_dual
```

Boyd, Parikh, Chu, Peleato & Eckstein's *Distributed Optimization and Statistical Learning via
the ADMM* (2011) §3.3 (the "multi-block ADMM" discussion the roadmap references) is explicit that
the classical two-residual convergence theory is derived for the **2-block, alternating-direction**
case (exactly what this codebase already implements for ONE coupling variable — x-block AGR,
z-block DSO). Extending to a *second, simultaneously-ascending* coupling variable (reactive μ) is
not automatically covered by the same theorem — it changes the problem from "2-block ADMM on one
coupling axis" to "block-coordinate descent on two separately-penalized coupling axes coupled
through the SAME two subproblems." [MEDIUM confidence — general decomposition-theory statement,
not independently re-derived against a specific paper this session; PITFALLS.md's Pitfall 17
makes the identical claim at MEDIUM-HIGH confidence, grounded in a direct read of this file.]

Two structurally different ways to model the reactive ascent, both defensible, with different
convergence stories:

1. **Genuine second ADMM block (own ρ_q, own quadratic penalty, own z-update)** — treat `qag_dso`
   exactly like `pag_dso`: a second augmented-Lagrangian penalty term `(ρ_q/2)Σ(qag_dso−b_j)²` in
   BOTH AGR-OPT (needs `q_inject`'s consensus target) and DSO-OPT, with its own dual-ascent
   `μ_j ← μ_j + ρ_q·(b_j − qag_dso_j)`. This is the closer analogy to the existing pattern and
   reuses the existing `AdmmResiduals`/`record!`/`converged` machinery IF the residual/threshold
   computation is changed to a **stacked 2-block norm**: `r = [r_p; r_q]` (concatenate both
   coupling-entry vectors before the 2-norm), `s = [s_p; s_q]` likewise, and ONE joint
   `ε_pri`/`ε_dual` pair sized for `p = n_load_nodes·T·2` (both blocks' entry count). This is the
   textbook fix for Pitfall 17's false-convergence risk: a STACKED norm cannot report "converged"
   while one channel still moves, because the stacked residual only shrinks when BOTH shrink.
2. **Unscaled subgradient/dual-ascent step with no reactive penalty term** — since D-03 already
   establishes "q is free inside the cone, no cost/utility term," a defensible simpler design is:
   keep AGR-OPT/DSO-OPT's OWN objectives untouched w.r.t. reactive power (no `(ρ_q/2)‖·‖²` penalty
   at all), and drive μ purely by a subgradient ascent on the reactive balance violation
   `μ_j ← μ_j + α_q·(qag_j − qag_dso_j)` with a diminishing or fixed step `α_q` (classical dual
   decomposition, not ADMM). This avoids inventing a second SOCP-conditioning penalty but trades
   ADMM's typically-faster empirical convergence for weaker, diminishing-step-size subgradient
   convergence guarantees — a different, and generally SLOWER, theoretical regime than option 1.

**Recommendation for the planner:** Option 1 (genuine second block, own ρ_q, stacked joint
residual) is the better fit for THIS codebase specifically, because (a) it reuses
`AdmmResiduals`/`record!`/`set_rho!`'s existing shape almost unchanged (extend the stacking, don't
redesign the ledger), (b) it keeps both coupling variables inside the SAME `set_objective_coefficient`
build-once/re-solve idiom (no new solve pattern), and (c) ADMM (not subgradient) is the reason the
active-power loop converges in ~10 iterations on the 2-bus fixture — abandoning that structure for
the reactive block risks a much slower μ-ascent that dominates total iteration count. Whether ρ_q
should track ρ (single shared penalty) or adapt independently is Claude's Discretion per
CONTEXT.md; independent ρ_q is more defensible given the reactive channel's typically much smaller
magnitude (`−Pdc·tanφ` vs. active `p_inject`), which would make a SHARED ρ badly scaled for one of
the two blocks (a mismatch this codebase's own adaptive-ρ scale-invariance work, cited in
`solve_admm.jl`'s "per-unit scale-invariance, ADMM-02" comments, was built specifically to avoid
for the single-block case — the same logic argues for letting the reactive block find its own
scale).

**Stopping criterion recommendation:** stack, don't independently-check:

```julia
sq_r = sq_r_p + sq_r_q          # concatenated primal residual² across BOTH blocks
sq_s = sq_s_p + sq_s_q          # concatenated dual residual² across BOTH blocks
r_norm = sqrt(sq_r); s_norm = sqrt(sq_s)
p_total = length(load_nodes) * T * 2       # BOTH coupling axes' entry count
ε_pri  = sqrt(p_total)*ε_abs + ε_rel*max(...)   # over BOTH blocks' magnitudes
ε_dual = sqrt(p_total)*ε_abs + ε_rel*sqrt(sq_λ + sq_μ)
converged ⟺ r_norm ≤ ε_pri AND s_norm ≤ ε_dual   # ONE joint check, not two
```

This is a direct, minimal extension of the EXISTING `sq_r`/`sq_ds`/`sq_a`/`sq_pd`/`sq_λ`
accumulator pattern already in `solve_admm.jl:267-291` — add `sq_r_q`/`sq_ds_q`/`sq_b`/`sq_qd`/
`sq_μ` accumulators inside the SAME per-`(j,t)` loop and sum before taking the sqrt, rather than
computing two independent `r_norm`/`ε_pri` pairs and `&&`-ing two `converged` calls.

### Anti-Patterns to Avoid

- **Two independent `converged(...)` checks (one per block), `&&`-combined.** This is Pitfall
  17's exact failure mode: each scalar pair can individually satisfy its own threshold while the
  OTHER block is still moving on a per-block ε; a stacked joint norm does not have this problem
  because a genuinely-unconverged block keeps the SUM above threshold. (Note: `&&`-combining two
  ALREADY-correct booleans is mathematically different from stacking norms BEFORE the ≤ check —
  the former is the anti-pattern, the latter is the fix; do not conflate them.)
- **Reusing `assert_battery_complementarity!`'s tolerance for the 4Q device.** It is scaled by
  `Pmax²` under a ONE-DIMENSIONAL dominance argument that does not hold for the P-Q coupled case;
  a new certificate with its own WR-01-idiom tolerance is required (D-07).
  **This applies even to the 4Q analogue of the check** — even though it superficially checks the
  "same" `p_ch·p_dch = 0` product, the *reason* it should hold is different (see Complementarity
  Derivation Skeleton below), so the tolerance must be independently re-derived, not copy-pasted.
- **Loosening `assert_socp_exact!`'s `rtol`/`atol` to "make room" for the new device cone.** The
  device-level apparent-power cone is a SEPARATE cone from the branch-flow SOC relaxation cone —
  they are certified by different mechanisms and must never share a tolerance constant.
- **Rebuilding AGR-OPT when a run adds/removes a 4Q device.** Build-once still applies: the
  presence of a 4Q device changes the STATIC structure of `build_agr_opt`'s model (adds a cone
  constraint once, at build time) — it does not mean the model is rebuilt per ADMM iteration.
  Nothing in this phase's live μ-ascent should touch model *structure* inside the loop, only
  objective coefficients (same as today).
- **Widening `Aggregator`'s contract by mutating `PVBattery`/`Thermostatic`/`Deferrable` to
  explicitly return `q_inject = zeros(T)`.** D-09 is explicit: *absent* means zero, via an
  optional field / `hasproperty` check — not a forced edit to every existing device file (that
  would be a needless diff against three files that this phase does not need to touch at all).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Apparent-power capability curve | A custom quadratic-penalty approximation of `p²+q²≤S²max` | JuMP `SecondOrderCone()` (exact, native Clarabel support) | The exact cone is already proven, tested, and dual-extractable in this codebase (`ConvexBranchFlow.jl`'s `smax`) — a penalty approximation would be both less accurate AND a second, un-precedented pattern to validate |
| Two-block dual-ascent convergence check | A from-scratch convergence proof/derivation | Boyd et al. §3.3's stacked-norm generalization, applied to the EXISTING `AdmmResiduals` accumulator pattern | The stacking fix is a direct, well-known generalization, not new decomposition theory — inventing a bespoke stopping rule risks reproducing a known failure mode (Pitfall 17) that the literature already has a standard answer for |
| Device-type coverage for the post-solve battery check | A parallel, separately-maintained device enumeration for 4Q vs 2D batteries | Extend the SAME `ctx.meta[:agg_device_vars]` stash + a shared iteration pattern (mirrors `assert_battery_complementarity!`'s `haskey(v, :p_ch) && haskey(v, :p_dch)` duck-typed dispatch) | The existing check already duck-types on field presence; a 4Q device sharing the `p_ch`/`p_dch` field names would be silently picked up by the OLD check too unless a NEW, separately-named check with its OWN tolerance explicitly supersedes it for 4Q devices (D-07) — building a parallel registry from scratch would duplicate machinery that already generalizes cleanly |

**Key insight:** every "don't hand-roll" item above is really the same discipline stated three
ways: this codebase already has the primitives (cones, dual-ascent loops, device-var stashes);
the risk in this phase is not missing a library, it is skipping the *re-derivation* step before
reusing a primitive whose original derivation assumed a narrower structure than the 4Q case now
has.

## Complementarity Derivation Skeleton (MESH-04 clause 2)

**What the App. C argument actually proves (`PVBattery.jl:42-57`, thesis pp. 166-168):** with the
STRICT ordering `λ_min < λ_med < λ_max` and the 1-D utility split
`a_ch·p_ch − (b_ch/2)p_ch² − a_dch·p_dch − (b_dch/2)p_dch²`, the marginal charge benefit
`∂U_ch/∂p_ch = λ_med − b_ch·p_ch` never exceeds `λ_med`, and the marginal discharge cost
`∂C_dch/∂p_dch = λ_med + b_dch·p_dch` never falls below `λ_med` — so ANY simultaneous
`p_ch, p_dch > 0` is a strictly-dominated round trip through the battery (loses `η² < 1` worth of
energy for zero net utility gain, since the objective is monotone in the "wrong" direction on
both legs at once). This is a PURE ACTIVE-POWER argument: reactive power never enters the utility
or the feasible region, so the dominance is 1-D by construction.

**Why D-04's cone breaks the 1-D premise.** With `p = p_dch − p_ch` entering
`p² + q² ≤ S²max`, the device's FEASIBLE REGION for `(p_ch, p_dch)` now depends on `q`: at a fixed
`q ≠ 0`, the achievable range of `p` shrinks to `|p| ≤ √(S²max − q²)`. Because `q` is free (D-03,
no cost term) and the reactive nodal price μ is the ONLY thing pinning it, there exist
`(q, p)` pairs at the SAME `p` where `p_ch, p_dch` are NOT uniquely determined by `p` alone
UNLESS an additional constraint forces `min(p_ch, p_dch) = 0`. The App. C argument's conclusion
("no complementarity constraint needed") relied on the ACTIVE-POWER objective alone penalizing
simultaneous charge/discharge; nothing in the reactive dimension does that penalizing, so the
1-D strict-dominance conclusion needs to be re-checked, not re-derived from scratch — the
question is whether the ACTIVE-power objective term (still present, still `a_ch/b_ch/a_dch/b_dch`
if the researcher keeps App. C's utility shape per Claude's Discretion) still strictly dominates
simultaneous charge/discharge REGARDLESS of what `q` the cone permits.

**Skeleton of the re-derivation (grid-charging, capped, D-02/D-04):**

1. Because `q` does not appear in the objective (D-03) and the cone only RESTRICTS `p`'s range as
   a function of `|q|` (never rewards a particular `p_ch`/`p_dch` split for a fixed `p`), the
   dominance argument's core step — "for a FIXED net `p`, does the objective prefer
   `min(p_ch,p_dch)=0`?" — is UNCHANGED in form from App. C: the objective is still separable in
   `(p_ch, p_dch)` given `p = p_dch - p_ch`, so the SAME 1-D marginal-cost/marginal-benefit
   comparison at a fixed net `p` still applies *if* the utility shape is kept analogous to App. C
   (concave charge benefit, convex discharge cost, evaluated on `p_ch`, `p_dch` independently).
2. The genuinely NEW failure mode is NOT reactive-power-driven co-optimality directly — it is
   grid-charging (D-02) removing App. C's `p_ch[t] ≤ pv_used[t]` bound (Assumption A6, deliberately
   NOT inherited). Without that bound, `p_ch` can be driven by the GRID PRICE rather than only by
   available PV, which reopens the question of whether `λ_med` (this device's OWN indifference
   price) can be strictly ordered against the EFFECTIVE nodal price faced by the device (λ_j[t] in
   ADMM, or `dual(:balance_p[j,t])` centrally) — i.e., whether the App. C argument's premise
   (`λ_min < λ_med < λ_max` as an INTERNAL device parameter triple) is even the right lever once
   the device also reacts to an EXTERNAL, possibly negative, nodal price.
3. **The negative-price regime is where the argument is expected to fail** (flagged explicitly in
   CONTEXT.md's Specific Ideas and PITFALLS.md's framing): if the nodal price `λ_j[t] < 0`
   (the DSO effectively PAYS to inject, e.g. a high-PV reverse-flow scenario — exactly the regime
   `v2.1`'s `EXACT-04` already found interesting for a DIFFERENT reason), then round-trip energy
   burning through `η² < 1` (charge then immediately discharge, net p ≈ 0 but gross throughput > 0)
   can be a way to ABSORB negative-price energy that a pure net-injection variable cannot represent
   — i.e., simultaneous `p_ch, p_dch > 0` literally becomes a way to accept MORE negatively-priced
   energy than the device's own net-power bound would otherwise allow, which is NOT dominated once
   the external price (not just the internal `λ_min/λ_med/λ_max` triple) enters the picture.
4. **What the certificate must therefore be** (per D-08, honest finding + documented boundary):
   NOT a constructor-time guard alone (unlike `PVBattery`'s strict-ordering guard, which is a
   SUFFICIENT condition check the constructor CAN verify without knowing the future nodal price) —
   because the failure mode here depends on the SOLVED price, which is not known at construction
   time. The certificate must be the POST-SOLVE numeric check (D-05's "both routes"), and its
   documentation must characterize the *regime* (negative effective price + grid charging enabled)
   under which a violation is expected, so a thrown violation there is read as "the honest boundary
   was hit" rather than "a bug."

**What the planner needs from this skeleton:** (a) a task to formalize the above into a doc-string
proof beside `FourQuadBESS.jl` (mirroring `PVBattery.jl`'s App. C doc-block structure); (b) a task
for the post-solve certificate itself, gated D-06-style (throw by default, report kwarg); (c) an
explicit acceptance criterion that a NEGATIVE-price fixture point is EITHER shown not to violate
(if the full derivation turns out stronger than this skeleton suggests) OR is documented as the
honest boundary where the certificate legitimately throws — either outcome is a valid, complete
deliverable per D-08, but the plan must decide which fixture exercises this before calling the task
done. [MEDIUM confidence: this skeleton is derived from direct reading of `PVBattery.jl`'s exact
argument plus the D-02/D-03/D-04 constraints; it is NOT a completed proof — the planner should
scope an actual task to write the doc-string derivation, not assume this skeleton is sufficient
documentation on its own.]

## Common Pitfalls

*(Drawn directly from `.planning/research/PITFALLS.md` Pitfalls 16, 17, 18 — the three
axis-4b-specific entries — with codebase line citations re-verified this session.)*

### Pitfall 1: 4Q-BESS silently inherits `PVBattery`'s no-binaries conclusion without re-derivation

**What goes wrong:** The 4Q device is naturally implemented as an extension of `PVBattery` (same
SOC recursion shape, same utility idea); it is easy to copy the docstring's "no binary needed"
CONCLUSION without re-checking that the PREMISE (1-D marginal tradeoff, PV-only charging) still
holds once grid-charging + a genuine P-Q cone are introduced.
**Why it happens:** The code is genuinely very reusable (SOC recursion, `p_ch`/`p_dch` split); the
argument text is not code, so nothing forces re-verification when copying the pattern.
**How to avoid:** Write the derivation skeleton above into `FourQuadBESS.jl`'s docstring BEFORE
writing `contribute!`; treat "no complementarity constraint" as something that must be re-earned,
not inherited.
**Warning signs:** A `FourQuadBESS` docstring that references App. C without a NEW derivation
paragraph specific to grid-charging + reactive coupling.

### Pitfall 2: The post-solve check never actually runs against the new device type

**What goes wrong:** `assert_battery_complementarity!` (`welfare_solve.jl:301-321`) duck-types on
`haskey(v, :p_ch) && haskey(v, :p_dch)` — if `FourQuadBESS`'s `vars` NamedTuple happens to use the
SAME field names, the OLD check would silently run against it using the WRONG (Pmax²-scaled,
1-D-derived) tolerance, while the NEW D-07 certificate might never be wired into `solve_welfare`'s
or `solve_admm`'s call sites at all — a silent coverage gap in either direction.
**Why it happens:** Both checks living in the same `ctx.meta[:agg_device_vars]` stash, iterated
the same way, makes it easy to assume "the check already runs" without verifying WHICH check.
**How to avoid:** Either (a) give `FourQuadBESS`'s vars distinctly-named fields (e.g. a type tag
or a different field name) so the OLD `assert_battery_complementarity!` duck-type guard does NOT
match it, and wire the NEW certificate explicitly into both `solve_welfare` (if 4Q devices are
ever used centrally) and `solve_admm`'s final consolidation block; or (b) make the OLD check
explicitly SKIP 4Q devices (e.g. dispatch on a type check, not just field presence) and add a
NEW, clearly separate call. Add a regression test asserting the NEW certificate actually executes
(not just "the test suite is green") — mirroring the project's CR-01 "tests passing ≠ mechanism
live" lesson.
**Warning signs:** No test that deliberately builds an aggregator with a `FourQuadBESS` and
asserts the NEW certificate function name appears in a stack trace / is called (e.g. via a
mock/spy, or by constructing a KNOWN-violating fixture and checking the error message names the
NEW function).

### Pitfall 3: Independent per-block convergence checks silently false-converge

**What goes wrong:** as covered in Architecture Patterns above — `converged(λ_residuals, ...) &&
converged(μ_residuals, ...)` with each side's own `ε_pri`/`ε_dual` computed independently reports
"converged" once BOTH happen to be simultaneously satisfied at SOME iteration, but nothing
prevents one block "catching up" to its own threshold while genuinely still moving relative to
the OTHER block's dynamics (the two blocks are coupled through the SAME AGR-OPT/DSO-OPT solves
each iteration, so their residuals are not independent processes).
**Why it happens:** It is the mechanically easiest extension — copy the existing 4 accumulator
variables, rename them with a `_q` suffix, and `&&` the two `converged` calls.
**How to avoid:** Stack the (λ, μ) residual/threshold computation into ONE joint norm before the
single `converged` check, per the recommendation above.
**Warning signs:** Two separate `sq_r`/`sq_ds`/etc. blocks and two separate `record!`/`converged`
call pairs in the loop body, rather than one extended accumulator set feeding one call.

### Pitfall 4: Live reactive ascent breaks the existing pinned `:certified` regression path

**What goes wrong:** `test_admm_reactive.jl` already pins two behaviors: (a) `reactive_consensus`
absent/false is byte-identical to pre-Phase-16 behavior; (b) `reactive_consensus=true` certifies
`:balance_q` via the ONE-SHOT pinned read. If the 3-state promotion (D-12) is implemented by
editing the SAME code path that today handles `true` (rather than adding a THIRD, parallel branch
for `:live`), there is a real risk of the pinned-`:certified` numeric behavior shifting when `:live`
lands, because the unpin (removing `:qag_pin`) is exactly the kind of change that, if applied
unconditionally, breaks case (b).
**Why it happens:** `reactive_consensus`'s existing `if reactive_consensus ... else ...` branch in
`build_dso_opt` (`DsoOpt.jl:244-256`) is a natural single edit point; it is tempting to add a THIRD
`elseif` that shares code with the `true`/`:certified` branch in a way that accidentally couples
their behavior.
**How to avoid:** Normalize to the 3-state enum FIRST (Pattern 3 above), then write `OFF`,
`CERTIFIED`, and `LIVE` as three genuinely separate branches (even if `CERTIFIED` and `LIVE` share
some setup code like the `qag_dso` variable declaration) — `CERTIFIED`'s branch must still emit
the EXACT `:qag_pin` equality it does today, unconditionally, byte-identical to before the
refactor. Re-run `test_admm_reactive.jl` UNMODIFIED after the 3-state promotion lands and confirm
every existing assertion still passes with `reactive_consensus = true` (not `:live`).
**Warning signs:** A diff to `DsoOpt.jl`'s `if reactive_consensus` block that removes or
conditionally-skips the `:qag_pin` constraint registration in a way reachable from
`reactive_consensus = true`/`:certified`.

## Code Examples

### Extending the AdmmResiduals accumulator for the stacked joint residual

```julia
# Source: existing pattern, src/admm/solve_admm.jl:267-291 — extend, don't replace
sq_r, sq_ds, sq_a, sq_pd, sq_λ = 0.0, 0.0, 0.0, 0.0, 0.0
sq_r_q, sq_ds_q, sq_b, sq_qd, sq_μ = 0.0, 0.0, 0.0, 0.0, 0.0   # NEW reactive accumulators
for j in load_nodes, t in 1:T
    rp = a[j][t] - pag_dso[j, t]
    dz = pag_dso[j, t] - pag_dso_prev[j][t]
    sq_r += rp^2; sq_ds += dz^2; sq_a += a[j][t]^2; sq_pd += pag_dso[j, t]^2; sq_λ += λ[j][t]^2
    if reactive_mode == LIVE
        rq = b[j][t] - qag_dso[j, t]                       # reactive consensus violation
        dzq = qag_dso[j, t] - qag_dso_prev[j][t]
        sq_r_q += rq^2; sq_ds_q += dzq^2; sq_b += b[j][t]^2
        sq_qd += qag_dso[j, t]^2; sq_μ += μ[j][t]^2
    end
end
r_norm = sqrt(sq_r + sq_r_q)              # JOINT primal norm (both blocks stacked)
s_norm = ρf * sqrt(sq_ds) + ρ_qf * sqrt(sq_ds_q)   # JOINT dual norm (each block's own ρ)
p_total = length(load_nodes) * T * (reactive_mode == LIVE ? 2 : 1)
ε_pri = sqrt(p_total) * ε_abs + ε_rel * max(sqrt(sq_a + sq_b), sqrt(sq_pd + sq_qd))
ε_dual = sqrt(p_total) * ε_abs + ε_rel * sqrt(sq_λ + sq_μ)
```

### Extending the reactive-mode normalization at both call sites

```julia
# Source: NEW pattern for build_dso_opt / solve_admm — mirrors the file's existing
# fail-loud ArgumentError convention (src/admm/DsoOpt.jl:154-173 style)
function normalize_reactive_mode(m)::ReactiveMode
    m isa Bool && return m ? CERTIFIED : OFF
    m isa ReactiveMode && return m
    if m isa Symbol
        m === :off && return OFF
        m === :certified && return CERTIFIED
        m === :live && return LIVE
    end
    throw(ArgumentError(
        "reactive_consensus must be a Bool, :off, :certified, or :live; got $m",
    ))
end
```

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The two-block ADMM joint-stopping-rule generalization (stacked norm over both coupling axes) is the theoretically-correct fix for Pitfall 17, per Boyd et al. §3.3's multi-block caveat | Architecture Patterns § Two-block ADMM stopping rule | If the general theory has a subtlety this session's reasoning missed (e.g., the two blocks need DIFFERENT convergence rates reconciled some other way), the planner may need a deeper literature pass before finalizing the exact stopping formula — but the STACKED-not-independent structural requirement itself is very unlikely to be wrong, since it follows directly from why independent checks false-converge |
| A2 | Option 1 (genuine second ADMM block with its own ρ_q) is preferable to Option 2 (unscaled subgradient ascent) for THIS codebase | Architecture Patterns § Two-block ADMM stopping rule | If ρ_q proves hard to tune/adapt jointly with ρ (e.g., persistent oscillation even after independent adaptive-ρ tuning), the planner may need to fall back to Option 2's simpler subgradient ascent — this is a legitimate mid-implementation pivot, not a research gap, since CONTEXT.md already leaves the exact mechanism to Claude's Discretion |
| A3 | The 4Q complementarity derivation skeleton's negative-price failure-mode characterization (energy-burning through η²<1 becomes non-dominated when the effective nodal price is negative) is the correct/complete characterization of where App. C's argument fails for the 4Q case | Complementarity Derivation Skeleton | If the actual failure boundary is different (e.g., it also depends on the SIGN of μ, not just λ, given the coupled cone), the certificate's documented "expected violation regime" could be incomplete — but D-08's "let it throw and document" design means an incomplete characterization is self-correcting at implementation/testing time, not a silent wrong result |
| A4 | Clarabel handles the AGR-OPT per-node subproblem becoming a genuine SOCP (when a 4Q device is present) without any solver-path code change beyond possibly switching `select_optimizer(QP())` → `select_optimizer(SOCP())` for tighter gap tolerances | Architectural Responsibility Map; Standard Stack | If Clarabel's QP-tolerance profile (`tol_gap_abs/rel` defaulted, not the SOCP profile's explicit `1e-8`) produces a materially looser cone residual on the 4Q device's `SecondOrderCone()` constraint than the SOCP profile would, the planner may need to force the SOCP optimizer factory for any AGR-OPT containing a 4Q device — this is a tuning/tolerance question, not an architecture question, and is flagged explicitly as Claude's Discretion in CONTEXT.md |

## Open Questions

1. **(RESOLVED — plan 19-04 adopts `hasproperty` duck typing exactly as recommended below.)
   Should `Aggregator`'s roll-up read `q_inject` via `hasproperty` (duck typing) or should
   `AbstractDevice`'s contract formally declare an optional-field convention (e.g. a trait
   function `has_reactive(::Type{<:AbstractDevice}) = false`, overridden by `FourQuadBESS`)?**
   - What we know: `hasproperty` on a `NamedTuple` is a zero-cost, idiomatic Julia check and
     requires zero changes to existing device files (matches D-09's "existing devices stay
     untouched" literally).
   - What's unclear: whether the project's existing style favors trait dispatch (used elsewhere,
     e.g. `problem_class`) over ad-hoc `hasproperty` checks for this kind of "is this feature
     present" question.
   - Recommendation: `hasproperty` is sufficient and simpler for a single optional NamedTuple
     field; reserve trait dispatch for cases with more than 2 device behaviors to distinguish.
     The planner should pick one and apply it consistently at the ONE call site
     (`Aggregator.contribute!`) — this is a small implementation decision, not a research gap.

2. **(RESOLVED — plan 19-08 creates the dedicated `Phase19Fixtures` module exactly as
   recommended below, reusing `small_radial_feeder()` verbatim for topology.)
   Does the small radial fixture (`test/fixtures_phase3.jl`'s 3-bus `small_radial_feeder`) need
   a NEW fixture variant with a `FourQuadBESS` aggregator member, or does the existing fixture's
   aggregator wiring already support swapping in a new device type without change?**
   - What we know: `small_radial_feeder()` builds the network only; `Aggregator`/device wiring is
     assembled separately in each test file's own setup, so adding a `FourQuadBESS` member is a
     test-file-level change, not a fixture-file change.
   - What's unclear: whether D-13's "small radial fixture is the primary CI-gated evidence" means
     reusing `small_radial_feeder()` verbatim (network only) with a NEW aggregator/device set, or
     whether a dedicated Phase-19 fixture module (mirroring `Phase3Fixtures`) should be added.
   - Recommendation: reuse `small_radial_feeder()` verbatim for the network topology (it is
     already the project's smallest valid radial fixture) and add a Phase-19-specific
     `@testmodule` (e.g. `Phase19Fixtures`) for the `FourQuadBESS`-bearing aggregator/parameter
     set, mirroring the existing `Phase3Fixtures`/`Phase4Fixtures` convention.

3. **(RESOLVED: deferred to empirical verification in plan 19-07 Task 1 — the μ-sign/identity
   question cannot be resolved on paper before the code runs; the plan assigns the empirical
   check as its first action, mirroring how the λ sign convention was originally pinned.)
   Where exactly should the μ/q-first-class results surface (D-11) live in the ADMM return
   tuple — added fields on `solve_admm`'s existing NamedTuple return, or a new peer extraction
   function (an ADMM-side `extract_reactive_dlmp` analogue) operating on the returned `dso_ctx`?**
   - What we know: the centralized path already has `extract_reactive_dlmp(ctx)` operating on a
     `solve_welfare` `ModelContext`; `solve_admm` returns `dso_ctx` (the converged DSO-OPT
     `ModelContext`) today, so `extract_reactive_dlmp(admm_result.dso_ctx)` may ALREADY work
     UNCHANGED once `:balance_q`'s dual is trustworthy under `:live` mode (since `:balance_q` is
     already registered in `build_dso_opt` regardless of mode).
   - What's unclear: whether `dual(:balance_q[j,t])` on the CONVERGED `dso_ctx` under `:live` mode
     equals the converged outer-loop `μ_j[t]` the ADMM loop computed (analogous to how the
     internal `λ` multiplier and `dual(:balance_p)` are related by a sign convention, verified
     empirically in `solve_admm.jl`'s header comment) — this sign/identity relationship for μ has
     NOT been established in this codebase and is a genuinely open, empirically-checkable question
     the plan should verify early (mirrors exactly how the λ sign convention was originally pinned
     empirically on the 2-bus fixture, per `solve_admm.jl`'s own header commentary).
   - Recommendation: plan a task to empirically verify `μ_j[t] ≈ ±dual(dso_ctx.constraints[:balance_q][j,t])`
     on the 2-bus/3-bus fixture BEFORE deciding the final results-surface shape — if they agree
     (up to the same sign flip λ already has), `extract_reactive_dlmp` may need zero changes and
     D-11 reduces to "expose `μ = -λ`-style negation in the return tuple, documented the same way";
     if they disagree, a genuinely new extraction path is needed.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | TestItems 1.0.0 / TestItemRunner 1.1.5 (`@testitem`, `@testmodule`) |
| Config file | `test/runtests.jl` (`@run_package_tests`, TestItemRunner discovery) |
| Quick run command | `julia --project=. -e 'using TestItemRunner; TestItemRunner.runtests(TSODSO; filter=ti->occursin("4Q", ti.name) \|\| occursin("reactive", ti.name))'` — or filter to the new test files directly with `ARGS`-based filtering per the project's documented pattern |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` — **never** `julia --project=test -e '... @run_package_tests ...'` (documented sibling-worktree contamination hazard, `.planning/STATE.md`) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MESH-04 | `FourQuadBESS` constructs, contributes cone-bounded P/Q, rolls up through widened `q_inject` | unit | new `test/test_fourquadbess.jl` (mirrors `test_pvbattery.jl` structure) | ❌ Wave 0 |
| MESH-04 | Constructor guards reject invalid params (asymmetric caps ≤0, η∉(0,1], Smax≤0) | unit | same file, mirrors `test_pvbattery.jl`'s guard-rejection items | ❌ Wave 0 |
| MESH-04 | Existing devices (`PVBattery`/`Thermostatic`/`Deferrable`) unaffected by widened contract | regression | `test/test_aggregator.jl` — add an assertion that a NON-4Q aggregator's `:Rq` is byte-identical pre/post this phase | ⚠ extend existing file |
| MESH-04 | Post-solve 4Q complementarity certificate throws on a constructed violating fixture, passes on a benign one | unit | new `test/test_fourquadbess.jl` item, or a peer of `test_welfare_solve.jl`'s battery-check tests | ❌ Wave 0 |
| MESH-04 | Certificate's `report`-mode kwarg neutralizes the throw without modifying `src/` (D-06) | unit | same file, mirrors `test/test_ac_oracle.jl:181-187`'s diagnostic-neutralization pattern | ❌ Wave 0 |
| MESH-05 | `reactive_consensus` 3-state mode: `false`/`:off` byte-identical to today | regression | `test/test_admm_reactive.jl` — existing item, MUST still pass unmodified | ✅ exists |
| MESH-05 | `reactive_consensus=true`/`:certified` byte-identical to today (pinned `:qag_pin`, one-shot dual) | regression | `test/test_admm_reactive.jl` — existing item, MUST still pass unmodified | ✅ exists |
| MESH-05 | `:live` mode converges on the small radial fixture with a `FourQuadBESS` present | integration | new `test/test_admm_reactive.jl` item (or a new file), small-radial-primary per D-13 | ❌ Wave 0 |
| MESH-05 | `:live` mode's converged welfare/λ/μ agree with `solve_welfare` centralized cross-validation, within newly-measured tolerances | integration/cross-validation | same new item, following `test_admm.jl`'s existing crossval item structure | ❌ Wave 0 |
| MESH-05 | Liveness regression: two `:live` runs differing ONLY in the reactive coupling target converge to DIFFERENT μ/q trajectories | regression | new item, mirrors project's CR-01 "tests passing ≠ mechanism live" precedent (cf. NASH-04 multi-seed probe pattern) | ❌ Wave 0 |
| MESH-05 | IEEE-13 supporting evidence under bounded-retry quarantine, NOT CI-gating | integration (quarantined) | `test/test_ieee123_admm.jl` sibling or `test_admm.jl`, wrapped in `AdmmRetryFixtures.retry_flaky_admm_solve` (existing helper, `test/fixtures_retry.jl`) | ⚠ extend existing pattern |

### Sampling Rate

- **Per task commit:** filtered TestItemRunner run on the new/modified test files only (fast
  iteration on the small radial fixture — no IEEE-13/123 solve in the inner loop).
- **Per wave merge:** `julia --project=. -e 'import Pkg; Pkg.test()'` (full suite, including the
  quarantined IEEE-13 items under bounded retry).
- **Phase gate:** Full suite green (2358+ pass, the known Aqua CairoMakie-stale-deps failure is
  the ONLY pre-existing accepted non-green item per `.planning/STATE.md`) before `/gsd:verify-work`.

### Wave 0 Gaps

- [ ] `test/test_fourquadbess.jl` — new file, mirrors `test/test_pvbattery.jl`'s structure
      (construction, guard-rejection, `contribute!` shape, standalone-solve complementarity check)
- [ ] A Phase-19 fixture module (e.g. `test/fixtures_phase19.jl`'s `Phase19Fixtures`) providing a
      `FourQuadBESS`-bearing aggregator/parameter set on TOP of the existing
      `Phase3Fixtures.small_radial_feeder()` network — covers MESH-04's unit tests and MESH-05's
      integration/cross-validation tests
- [ ] Extend `test/test_admm_reactive.jl` with the `:live` mode items (convergence, cross-
      validation, liveness regression) — do NOT create a separate file for these, since the
      existing 3-state back-compat regressions (`:off`/`:certified`) MUST live alongside the new
      `:live` items so a single test run demonstrates all three modes coexist correctly
- [ ] A known-violating 4Q fixture (asymmetric grid-charging caps + a forced negative effective
      price) to exercise the D-08 honest-boundary certificate throw — this is itself a research
      deliverable per the Complementarity Derivation Skeleton, not just a test-authoring task

*(Framework install: none needed — TestItems/TestItemRunner already wired.)*

## Security Domain

`security_enforcement` is absent from `.planning/config.json` (treated as enabled per protocol),
but this project is a research optimization library with no network endpoints, no
authentication/session surface, no user-facing input beyond function arguments consumed by a
single researcher/PhD-thesis audience running local Julia code. Most ASVS categories are
structurally inapplicable.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | No | No auth surface — local library code |
| V3 Session Management | No | No sessions |
| V4 Access Control | No | No multi-tenant/access boundary |
| V5 Input Validation | Yes | Already the project's OWN convention: throw-never-`@assert` `ArgumentError` constructor guards (e.g. `PVBattery`'s strict-ordering / bound checks). `FourQuadBESS`'s constructor must follow the SAME pattern for its asymmetric-cap / `Smax`/η guards — this is a pre-existing house standard, not a new control to introduce |
| V6 Cryptography | No | No secrets, no cryptographic operations anywhere in this codebase |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malformed/adversarial constructor arguments causing silent wrong physics (e.g. `Smax ≤ 0`, `Pch_max`/`Pdch_max` ≤ 0, η ∉ (0,1]) | Tampering (data integrity, not a security boundary in the traditional sense) | Throw-loud `ArgumentError` inner-constructor guards, mirroring `PVBattery.jl`'s existing pattern — already the house convention, apply identically to `FourQuadBESS` |
| A silently-unwired certificate (Pitfall 2 above) letting a physically-invalid solve pass as "validated" | Repudiation (a published research result cannot be traced back to a certificate that actually ran) | The explicit "prove the certificate executes" regression test recommended in Pitfall 2 — this is the project's actual security-relevant property (research integrity / reproducibility), not a traditional infosec concern |

This is the honest scope: for a local, single-audience research optimization library, "security"
functionally means "the certificates that gate published numbers cannot be silently bypassed" —
which is exactly what D-06/D-07's throw-by-default-with-explicit-report-kwarg design already
addresses, and what Pitfall 2 above flags as the integration risk to test for.

## Sources

### Primary (HIGH confidence)
- Direct code reads (this session, file:line-cited above): `src/devices/PVBattery.jl`,
  `src/devices/Aggregator.jl`, `src/devices/AbstractDevice.jl`, `src/admm/solve_admm.jl`,
  `src/admm/DsoOpt.jl`, `src/admm/AgrOpt.jl`, `src/admm/residuals.jl`,
  `src/models/exactness.jl`, `src/models/welfare_solve.jl` (lines 230-323),
  `src/powerflow/ConvexBranchFlow.jl` (lines 120-200), `src/pricing/dlmp.jl` (lines 100-200),
  `src/solver/factory.jl`, `src/solver/ProblemClass.jl`, `test/fixtures_phase3.jl`,
  `test/test_admm_reactive.jl`, `.planning/quick/260726-vn2-.../260726-vn2-SUMMARY.md`.
- `.planning/phases/19-4q-bess-live-reactive-dual-ascent/19-CONTEXT.md` — all D-01..D-15 locked
  decisions, quoted verbatim above.
- `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, `.planning/config.json` — requirement text,
  standing bars (certificate-laundering prohibition, byte-identical defaults, gate-then-golden,
  measurement-before-golden, IEEE-13 ADMM flakiness), workflow flags.
- `.planning/research/SUMMARY.md`, `.planning/research/PITFALLS.md` — v3.0 milestone-level
  research already covering this exact phase (Pitfalls 16/17/18 are this phase's pitfalls almost
  verbatim); re-verified against the actual code this session rather than merely copied.
- `.planning/spikes/MANIFEST.md` — solver-noise-floor / scale-free-tolerance measurement-hygiene
  rules binding on the new certificate's tolerance design (D-07).
- `CLAUDE.md` — stack constraints (JuMP not Convex.jl, Clarabel primary conic solver, hand-rolled
  ADMM, build-once-resolve-many, throw-never-`@assert`).

### Secondary (MEDIUM confidence)
- Boyd, Parikh, Chu, Peleato & Eckstein, *Distributed Optimization and Statistical Learning via
  the Alternating Direction Method of Multipliers* (2011), §3.3 (multi-block ADMM convergence
  caveats) — canonical reference for the two-block stopping-rule generalization; cited by
  training knowledge and cross-referenced against this project's own PITFALLS.md characterization
  of the same result, not independently re-fetched from the paper this session.

### Tertiary (LOW-MEDIUM confidence)
- The specific negative-effective-price failure-mode characterization in the Complementarity
  Derivation Skeleton is this session's own algebraic reasoning from the constructor decisions
  (D-02/D-03/D-04) and the App. C argument's stated premises — it is a SKELETON for the planner
  to task out a formal derivation against, not a completed, independently-verified proof.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new packages, both cone idioms and both solver dispatch paths
  already exist and were read directly from source.
- Architecture: HIGH — every integration seam (device contract, Aggregator roll-up, ADMM loop,
  DSO-OPT pinning, residual ledger) was read directly with file:line citations; the only
  genuinely-new architectural surface (μ/q results plumbing, Open Question 3) is flagged as an
  open empirical question, not asserted as settled.
- Pitfalls: MEDIUM-HIGH — codebase-specific pitfalls (2, 4 above) are HIGH confidence (read
  directly); the general two-block ADMM convergence-theory pitfall (1, 3 above) is MEDIUM,
  matching PITFALLS.md's own confidence characterization for the same claim.

**Research date:** 2026-08-07
**Valid until:** 30 days (stable, brownfield codebase; no external API/library drift risk since
zero new dependencies are introduced)

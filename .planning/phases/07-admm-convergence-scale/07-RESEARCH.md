# Phase 7: ADMM Convergence & Scale - Research

**Researched:** 2026-07-19
**Domain:** ADMM convergence theory (Boyd §3.3–3.4) on a mixed QP + SOCP 2-block split; JuMP objective-coefficient mutation; IEEE-123 radial feeder fixture; CairoMakie diagnostics via a package extension
**Confidence:** HIGH on the JuMP API + Boyd theory + thesis data location; MEDIUM-HIGH on IEEE-123 transcription effort and transit-node integration gap

## Summary

Phase 7 hardens the Phase-6 hand-rolled ADMM loop into a scale-robust, theoretically-correct
solver: **both** primal and dual residual stopping, **per-unit-normalized adaptive ρ**, and
first-class plottable diagnostics — then proves it on the IEEE 123-node voltage-constrained case.
Every piece maps to a standard Boyd, Parikh, Chu, Peleato & Eckstein (2011) construction and to the
Palacios thesis, which uses the exact same unscaled ADMM (thesis App. B eqs. B.30–B.32) and ships
the 123-node R/X data in per-unit (thesis App. E, p.170).

**The ROADMAP-flagged finickiness is fully resolvable and NOT a blocker.** The concern — that
adaptive ρ changes the *quadratic* penalty weight `(ρ/2)‖·‖²`, which Phase 6 built once and never
mutates — is resolved by a single verified JuMP call: `set_objective_coefficient(model, x, x,
coeff)` mutates the diagonal quadratic coefficient of `x²` in place, no rebuild. This is **VERIFIED
in the installed JuMP 1.30.1 source** (`src/objective.jl:629`); its own docstring example confirms
`set_objective_coefficient(m, x, x, 2)` yields `2·x²` (JuMP absorbs the MOI factor-of-2
canonicalization for you). Each iteration where ρ changes, update BOTH the quadratic coefficient
(`±0.5·ρ`) and the already-updated linear coefficient (`−λ − ρ·target`). Build-once (ADMM-04) is
preserved; convexity is preserved because adaptive ρ stays strictly positive.

The two genuinely new work-items are (1) the **IEEE-123 fixture** — a mechanical but error-prone
transcription of thesis App. E with node relabeling to the framework's contiguous `bus.id ==
position` convention, radial verification, and a **transit-node integration gap** (IEEE-123 has ~37
non-load junction buses, but the Phase-6 `build_dso_opt` throws unless *every* non-root bus carries
an aggregator); and (2) the **CairoMakie diagnostics**, which should ship as a `TSODSOMakieExt`
package extension (weakdep) mirroring the existing Gurobi/Mosek extension pattern, keeping the core
solve and headless CI plot-free and fast.

**Primary recommendation:** Extend the existing loop in place — do NOT rewrite. Add (a) the correct
Boyd dual residual `s = ρ·Δ(pag_dso)` and 2-norm per-unit tolerances `ε_pri`/`ε_dual`, (b)
residual-balancing adaptive ρ (τ=2, μ=10) with a `set_objective_coefficient(m,x,x,·)` quadratic
update guarded to fire only when ρ actually changes, clamped to `[ρ_min, ρ_max]`, and frozen after
the residuals settle; (c) a JuMP-free extension to `AdmmResiduals` (ρ trace + threshold traces +
price snapshots) feeding a `TSODSOMakieExt`; and (d) an `ieee123_modified()` fixture plus a
transit-node relaxation in `build_dso_opt`. Keep the centralized cross-validation (ADMM-03) as the
load-bearing correctness gate — Clarabel solves the monolithic IEEE-123 SOCP, so it stays available.

<user_constraints>
## User Constraints (from CONTEXT.md)

CONTEXT.md records **no user-preference grey areas** — this is an algorithm-hardening phase whose
decisions are determined by ADMM theory (Boyd) + the thesis + the Phase 4–6 seams. The following are
copied verbatim.

### Locked Decisions
(from `## Implementation Decisions` — "Claude's Discretion, anchored to ADMM theory + Phases 4–6 seams")

- **Primal + dual stopping (ADMM-02):** stop on BOTH the primal residual (block mismatch) AND the
  dual residual (change in the consensus variable between iterations, scaled by ρ) falling below
  per-unit-normalized tolerances (`ε_abs + ε_rel·norm`), per Boyd §3.3. Hitting the iteration cap
  FAILS LOUDLY (throws) — never returns the last iterate silently (Phase-6 already fail-loud; keep it).
- **Per-unit-normalized adaptive ρ (ADMM-02):** residual-balancing adaptive ρ (Boyd §3.4.1): `ρ ← τ·ρ`
  when the primal residual >> dual residual, `ρ ← ρ/τ` when dual >> primal, within a band; NO
  hard-coded scale-specific penalty (the Phase-6 fixed ρ=5/100 must become adaptive). Because prices
  ARE duals and the subproblems are per-unit, normalize the residuals so ρ is scale-invariant across
  2-bus / IEEE-13 / IEEE-123. RESEARCH FLAG: the ρ-penalty coefficient update must stay consistent
  with the build-once `set_objective_coefficient` discipline (changing ρ changes the quadratic
  penalty weight, not just the linear term) — handle without rebuilding, or document the minimal
  re-setup. **Resolved below (Pattern 1).**
- **Convergence diagnostics (ADMM-05):** report residual traces (primal + dual per iteration),
  iteration count, and price convergence (`λ_j` trajectory → DADP); make them PLOTTABLE. Introduces
  **CairoMakie** as a dependency; keep plotting OPTIONAL (a package extension or thin seam) so the
  core solve doesn't hard-depend on a heavy plotting stack, and headless CI stays fast.
- **IEEE-123 scale case:** build the IEEE 123-node voltage-constrained feeder fixture (immutable
  JuMP-free `Feeder`, radial-validated, per-unit), run ADMM, assert convergence in ~tens of
  iterations with `λ_j → DADP` (cross-validated against the centralized SOCP where still solvable
  monolithically) and the PF-04 exactness invariant holding at the converged point. SparseArrays for
  the larger topology.
- **Solver/status discipline (CLAUDE.md):** subproblems via `select_optimizer`; `assert_solved!`;
  PF-04 exactness on the converged DSO-OPT; no model names a solver; build-once/re-solve preserved.

### Claude's Discretion
The adaptive-ρ scheme, the dual residual, and the stopping criteria come from standard ADMM theory
(Boyd et al.) + the thesis. No user preferences to honor beyond those.

### Deferred Ideas (OUT OF SCOPE)
- Experiment harness / scenario sweeps → Phase 8.
- Documentation / literate convergence-study pages → Phase 9 (this phase produces the plottable
  diagnostics; the literate write-up is Phase 9).
- Stochastic / rolling-horizon ADMM → later milestone.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ADMM-02 | ADMM stops on **both** primal and dual residuals with per-unit-normalized adaptive ρ (no hard-coded scale-specific penalty) | Pattern 1 (quadratic-coeff adaptive-ρ update, VERIFIED JuMP API), Pattern 2 (Boyd dual residual `s=ρ·Δz`), Pattern 3 (per-unit 2-norm tolerances), Pattern 4 (residual-balancing schedule) |
| ADMM-05 | Convergence diagnostics (residual traces, iteration count, price convergence) reported and plottable | Pattern 5 (extend `AdmmResiduals` ledger, JuMP-free), Pattern 6 (`TSODSOMakieExt` package extension), Code Examples |
| (scale target) | IEEE 123-node voltage-constrained case converges in ~tens of iterations, λ_j → DADP, exactness holds | `ieee123_modified()` fixture from thesis App. E; transit-node gap resolution; centralized cross-validation still available |

ADMM-02 and ADMM-05 are the only requirements formally mapped to Phase 7 (REQUIREMENTS.md
traceability). The IEEE-123 scale target is a success criterion of the phase, not a separate
requirement ID, but it exercises DATA-03 (123-node fixture, nominally Phase 4) and re-validates
ADMM-03/04 at scale.
</phase_requirements>

## Architectural Responsibility Map

The tiers here are the framework's internal layers, not web tiers.

| Capability | Primary Layer | Secondary Layer | Rationale |
|------------|--------------|-----------------|-----------|
| Adaptive-ρ policy decision (when/how to change ρ) | ADMM orchestration (`solve_admm.jl`) | — | The loop owns convergence control; it sees both residuals and the price. |
| Quadratic + linear penalty-coefficient mutation | Subproblem builders (`AgrOpt.jl`, `DsoOpt.jl`) | JuMP/MOI | The models own their objective; expose a `set_rho!`-style updater so the loop never touches JuMP internals directly. |
| Primal/dual residual computation + norms | ADMM orchestration | Residual ledger (`residuals.jl`) | Residuals are functions of the two blocks' iterates — only the loop has both. |
| Residual/ρ/price trace storage | Residual ledger (`residuals.jl`, JuMP-free) | — | Pure bookkeeping; must stay JuMP-free so Phase 8/9 and the plot ext reuse it. |
| Plotting the traces | `TSODSOMakieExt` (weakdep extension) | CairoMakie | Keep the heavy viz stack out of the core solve + headless CI. |
| IEEE-123 topology + per-unit data | Data/fixture layer (`data/ieee123.jl`) | `SparseArrays`, `topology.jl` | Immutable, JuMP-free, radial-validated by construction (DATA-01/02/03). |
| Transit-node (zero-injection) handling | DSO-OPT builder (`DsoOpt.jl`) | ADMM orchestration | The network subproblem must close `:Rp/:Rq` at junction buses with no aggregator. |
| Centralized cross-validation at scale | `models/welfare_solve.jl` + `pricing/dlmp.jl` | Clarabel SOCP | Ground-truth oracle; unchanged, called by the IEEE-123 test. |

## Standard Stack

No new *solver* dependencies. The only new library is the plotting backend, added as a weakdep.

### Core (already in Project.toml — unchanged)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | 1.30.1 | Objective-coefficient mutation (linear + **quadratic**), build-once re-solve | Only algebraic-modeling layer exposing per-constraint duals + in-place quadratic-coefficient modify (VERIFIED below). |
| Clarabel | 0.11.1 | SOCP DSO-OPT + QP AGR-OPT subproblem solves | Native quadratic objective, high-accuracy conic duals; tight gap already set (1e-8) in `factory.jl`. |
| HiGHS | 1.24.1 | (available) LP/MILP; not on the SOCP path | — |
| SparseArrays | stdlib | IEEE-123 incidence/adjacency (already used by `topology.jl`) | Radial validation already sparse; 123-node topology stays sparse. |

### Supporting (new — plotting only, weakdep)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| CairoMakie | 0.15.13 | Vector (PDF/SVG) convergence + price figures | Loaded ONLY when a researcher/docs build wants plots; core solve never imports it. |
| Makie | 0.24.13 | Plotting API (`Figure`, `Axis`, `lines!`, `scatterlines!`, `save`) — pulled in by CairoMakie | Same. Keep CairoMakie/Makie versions in lockstep (Pkg handles it). |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| CairoMakie via package extension | CairoMakie as a hard `[deps]` dependency | Rejected: bloats every `using TSODSO` + headless CI precompile with a heavy viz stack for a solve that never plots. |
| CairoMakie via package extension | CairoMakie as a `test`/`docs`-only dep, plotting fns living in test/ | Rejected: the plotting functions are part of the researcher-facing API (thesis figures); they belong in the package, lit up on demand — exactly what an extension gives. |
| CairoMakie | Plots.jl | STACK.md: CairoMakie is the thesis vector-figure choice; Plots is exploratory only. |
| `set_objective_coefficient(m,x,x,·)` quadratic update | Epigraph reformulation `(ρ/2)·s`, `s ≥ ‖·‖²` with a mutable linear ρ on `s` | Unnecessary given the verified in-place quadratic modify; the epigraph adds a variable + a cone per coupling entry and obscures the thesis 3.46/3.47 objective. Keep as a documented fallback only if a future backend rejects `ScalarQuadraticCoefficientChange`. |
| Adaptive residual balancing (Boyd §3.4.1) | Spectral/adaptive ρ (Xu et al. 2017), fixed ρ retuned per feeder | Residual balancing is the textbook scheme the thesis+PITFALLS.md prescribe; spectral is an over-engineering for v1. Fixed-ρ-per-feeder violates the "no hard-coded scale-specific penalty" requirement. |

**Installation (plotting extension, when the milestone opens):**
```julia
# In the package Project.toml (NOT a hard dep):
#   [weakdeps]  CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
#   [extensions] TSODSOMakieExt = "CairoMakie"
# The researcher/docs environment then:
import Pkg; Pkg.add("CairoMakie")   # version 0.15.x per [compat]
```

**Version verification:** JuMP 1.30.1 verified from the installed source tree
(`~/.julia/packages/JuMP/EHXNP/Project.toml`). CairoMakie 0.15.13 / Makie 0.24.13 cited from
STACK.md's Julia General registry `Versions.toml` fetch (2026-07-18); re-confirm at install with
`Pkg.add` + the committed Manifest, and pin `[compat] CairoMakie = "0.15"` to keep Makie in lockstep.

## Package Legitimacy Audit

> slopcheck targets npm/PyPI and does not cover the Julia General registry. Julia packages are
> verified against the registry directly (as CLAUDE.md/STACK.md already did on 2026-07-18) and by
> the committed `Manifest.toml` (INFRA-01), which pins exact versions + tree hashes.

| Package | Registry | Age | Downloads | Source Repo | Verdict | Disposition |
|---------|----------|-----|-----------|-------------|---------|-------------|
| CairoMakie | Julia General | ~6 yrs | very high (flagship viz) | github.com/MakieOrg/Makie.jl | N/A (not npm/PyPI) — registry-verified | Approved (weakdep) |
| Makie | Julia General | ~6 yrs | very high | github.com/MakieOrg/Makie.jl | N/A — registry-verified, Context7 `/makieorg/makie.jl` HIGH reputation | Approved (transitive via CairoMakie) |

**Packages removed due to slopcheck [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none. CairoMakie/Makie are the canonical Julia plotting
ecosystem (Context7 resolved `/makieorg/makie.jl`, 1519 snippets, HIGH source reputation). No new
solver or numeric dependency is introduced by this phase.

## Architecture Patterns

### System Architecture Diagram

```
                            solve_admm  (ORCHESTRATION — extend in place)
                            ┌─────────────────────────────────────────────────────┐
 feeder, pf, aggregators →  │  BUILD ONCE:  AgrOpt[j]  (QP)      DsoOpt (SOCP)      │
 T, λ₀, ρ₀, maxiter, tol,   │               │                    │                 │
 ε_abs, ε_rel, τ, μ,        │               ▼                    ▼                 │
 ρ_min, ρ_max, α=1          │  ┌──── iterate k = 1..maxiter ───────────────────┐   │
                            │  │ (1) solve_agr!(λ_j, c_j, ρ)  → a_j  (block x)  │   │
                            │  │ (2) solve_dso!(λ,  a,   ρ)  → pag_dso (block z)│   │
                            │  │ (3) primal  r = a − pag_dso                    │   │
                            │  │     DUAL    s = ρ·(pag_dso^k − pag_dso^{k−1})  │◄──┼─ Pattern 2
                            │  │     ε_pri = √p·ε_abs + ε_rel·max(‖a‖,‖pag_dso‖)│   │
                            │  │     ε_dual= √n·ε_abs + ε_rel·‖λ‖               │◄──┼─ Pattern 3
                            │  │     record!(res, k, ‖r‖, ‖s‖, ρ, price_snap)   │───┼─► AdmmResiduals
                            │  │ (4) STOP if ‖r‖≤ε_pri AND ‖s‖≤ε_dual           │   │   (JuMP-free ledger)
                            │  │ (5) λ ← λ + ρ·r ;  c ← −pag_dso                │   │        │
                            │  │ (6) ADAPT ρ (Boyd §3.4.1, clamp, freeze):      │◄──┼─ Pat.4  │
                            │  │     if ρ changed → set_rho!(AgrOpt/DsoOpt, ρ)  │───┼─► set_objective_
                            │  └────────────────────────────────────────────────┘   │   coefficient(m,x,x,·)
                            │  FINAL: solve_dso!(…; check_exact=true) → PF-04 gate  │◄──── Pattern 1
                            │  welfare from primals; dadp = −λ                     │        │
                            └───────────────────────────────────────────────────────┘        │
                                        │  returns (; welfare, dadp, λ, iters, residuals,…)    │
                                        ▼                                                       │
              centralized cross-validation (solve_welfare / extract_dlmp)  ── ADMM-03 gate      │
                                        │                                                       │
                                        ▼                                                       │
              TSODSOMakieExt.plot_convergence(residuals) / plot_price_convergence(…) ◄──────────┘
                       (weakdep — only when CairoMakie is loaded; PDF/SVG out)
```

A reader can trace the primary use case: fixtures + config enter `solve_admm`; the loop alternates
the two blocks, computes primal + dual residuals with per-unit tolerances, records them, adapts ρ
(mutating both the linear AND quadratic objective coefficients when ρ changes), stops on both
residuals or fails loud at the cap, runs the exactness gate, and returns a ledger that the plotting
extension turns into thesis figures.

### Recommended Project Structure (deltas only — extend, don't restructure)
```
src/
├── admm/
│   ├── solve_admm.jl     # EXTEND: dual-residual stop, per-unit ε, adaptive-ρ policy, freeze/clamp
│   ├── residuals.jl      # EXTEND: correct dual residual, add rho_trace/eps traces/price snapshots
│   ├── AgrOpt.jl         # EXTEND: set_rho!(agr, ρ) — quadratic coeff −0.5ρ (Max) + linear
│   └── DsoOpt.jl         # EXTEND: set_rho!(dso, ρ) — quadratic coeff +0.5ρ (Min) + linear;
│                         #         RELAX transit-node guard (zero-injection non-load buses)
├── data/
│   └── ieee123.jl        # NEW: ieee123_modified() — thesis App. E, per-unit, radial, relabeled
└── (no new src plotting file — plotting lives in the extension)
ext/
└── TSODSOMakieExt.jl     # NEW: plot_convergence / plot_price_convergence methods (weakdep CairoMakie)
```
Core-package plotting *stubs* (empty generic functions + exports) live in a tiny new core file (e.g.
`src/diagnostics/plots.jl`, wired into `TSODSO.jl`) so the ext has methods to extend and the symbols
are always exported; the ext supplies the CairoMakie-backed methods.

### Pattern 1: Adaptive-ρ WITHOUT rebuild — the in-place quadratic-coefficient update (THE flagged problem, RESOLVED)

**What:** When ρ changes, mutate the diagonal quadratic penalty coefficient in place with the
verified JuMP 3-arg `set_objective_coefficient`, alongside the already-mutated linear coefficient.
Build-once (ADMM-04) is fully preserved.

**Why it's correct (VERIFIED, not assumed):** JuMP 1.30.1 source
`~/.julia/packages/JuMP/EHXNP/src/objective.jl:629` defines
`set_objective_coefficient(model, variable_1, variable_2, coeff)`. Its docstring example is
authoritative: `set_objective_coefficient(m, x[1], x[1], 2)` produces `2·x[1]²`. Internally
(`objective.jl:661`) it emits `MOI.ScalarQuadraticCoefficientChange` and, for the diagonal case
`variable_1 == variable_2`, multiplies the stored coefficient by 2 — i.e. **JuMP absorbs the MOI
`0.5·xᵀQx` canonicalization so you pass the coefficient of `x²` directly.** A batch vector form
`set_objective_coefficient(model, vars1, vars2, coeffs)` (`objective.jl:712`) sets many quadratic
coefficients in one call.

**Clarabel compatibility:** Clarabel is `copy_to`-only, so the model is a `CachingOptimizer`. The
`MOI.modify(…, ScalarQuadraticCoefficientChange)` is stored in the cache and re-applied on the next
`optimize!` — exactly the same mechanism as the linear `ScalarCoefficientChange` the loop already
uses. No `direct_model`, no rebuild, no warm-start assumption (warm starts are already a no-op under
Clarabel per Phase-6 header). VERIFIED-adjacent: the mechanism is identical to the working linear
path; re-confirm empirically in a Wave-0 test (below).

**The concrete update (mapping to the current objectives):**
- AGR-OPT is `Max U_ag − (ρ/2)Σ pag²`. Coefficient of `pag[t]²` is `−0.5·ρ`; linear coefficient of
  `pag[t]` is `−λ_j[t] − ρ·c_j[t]`.
- DSO-OPT is `Min λ₀ᵀp_import + (ρ/2)Σ pag_dso²`. Coefficient of `pag_dso[j,t]²` is `+0.5·ρ`; linear
  coefficient is `−λ[j][t] − ρ·a[j][t]`.

```julia
# src/admm/AgrOpt.jl — add a ρ-aware updater (build-once preserved)
function set_rho!(agr::AgrOpt, ρ::Real)
    # diagonal quadratic coeff of pag[t]² is −0.5ρ  (Max objective, penalty subtracted)
    set_objective_coefficient(agr.model, agr.pag, agr.pag, fill(-0.5 * ρ, agr.T))  # batch form
    return agr
end
# Then in solve_agr!, the linear coeff already becomes −λ_j[t] − ρ·c_j[t] each iteration.

# src/admm/DsoOpt.jl — mirror with +0.5ρ (Min objective)
function set_rho!(dso::DsoOpt, ρ::Real)
    v = vec(dso.pag)                                   # DenseAxisArray → flat Vector{VariableRef}
    set_objective_coefficient(dso.model, v, v, fill(0.5 * ρ, length(v)))
    return dso
end
```

**When to use:** Call `set_rho!` ONLY on iterations where the balancing rule actually changed ρ
(guard `ρ_new != ρ_old`). On the (majority of) iterations where ρ is unchanged, only the linear
coefficient update runs — identical cost to Phase 6. This keeps the per-iteration overhead
negligible while making ρ fully adaptive.

**Convexity guard:** adaptive ρ multiplies/divides by τ within `[ρ_min, ρ_max]`, so ρ > 0 always;
AGR stays concave-Max, DSO stays convex-Min. Never let ρ reach 0 (would drop the proximal term).

### Pattern 2: The correct 2-block dual residual (ADMM-02) — `s = ρ·Δ(consensus block)`

**What:** Boyd §3.3 (and thesis App. B.30–B.32, the unscaled form the thesis uses): for
`min f(x)+g(z) s.t. Ax+Bz=c`, updated x-then-z-then-y, the dual residual is
`s^{k+1} = ρ·AᵀB·(z^{k+1} − z^k)`. Here the coupling is the identity consensus `pag_j − pag_dso_j =
0` (A=I on the AGR block `a`, B=−I on the DSO block `pag_dso`, c=0), and the loop updates AGR (`a`,
the x-block) FIRST, then DSO (`pag_dso`, the z-block). Therefore:

```
primal residual  r^{k} = a^k − pag_dso^k                         (already computed, Phase 6)
dual   residual  s^{k} = ρ · (pag_dso^{k} − pag_dso^{k−1})       (change in the z-block)
```

**Correction to Phase 6:** the Phase-6 loop tracks `ρ·(a − a_prev)` as a *diagnostic* dual residual
(the change in the *x*-block `a`). The theoretically-correct Boyd dual residual for the stopping test
is the change in the **z-block** `pag_dso` (the second-updated / consensus block), NOT `a`. Phase 7
must switch the tracked quantity to `ρ·Δ(pag_dso)`. Store `pag_dso_prev` (a plain
`Dict{Int,Matrix}`/array, JuMP-free) exactly as `a_prev` is stored today.

**Why it happens / why it matters:** primal feasibility (`r → 0`) means the two blocks agree; dual
feasibility (`s → 0`) means the price has stopped moving, i.e. optimality. Stopping on `r` alone is
the textbook false-convergence bug (PITFALLS.md Pitfall 2, item 3) — you can hit consensus at a
non-optimal, still-drifting price and report a wrong DADP. This is the single most important
correctness fix in the phase.

### Pattern 3: Per-unit-normalized stopping tolerances (Boyd §3.3.1, eq. 3.12)

**What:** feasibility tolerances that scale with the problem, using an absolute floor + a relative
term on the current iterate norms:

```
ε_pri  = √p · ε_abs + ε_rel · max(‖a‖₂, ‖pag_dso‖₂)          # c = 0, so ‖c‖ drops out
ε_dual = √n · ε_abs + ε_rel · ‖λ‖₂                           # ‖Aᵀy‖ = ‖λ‖ (A = I)
stop  ⟺  ‖r‖₂ ≤ ε_pri  AND  ‖s‖₂ ≤ ε_dual
```

where `p = n = n_load_nodes · T` (the number of coupling entries), and Boyd-typical
`ε_abs ≈ 1e-4`, `ε_rel ≈ 1e-3` (tune tighter if the exactness/cross-validation needs it).

**Why this delivers per-unit scale-invariance (the "no hard-coded penalty" requirement):** all
coupling quantities (`a`, `pag_dso`, `λ`) are in per-unit (INFRA-05; feeder r/x and prices are pu).
The relative term makes the *threshold* a fixed fraction of the *iterate magnitude*, and the √-scaled
absolute floor is dimensionless-in-pu. Consequently the SAME `(ε_abs, ε_rel)` AND the SAME
adaptive-ρ policy `(τ, μ, ρ_min, ρ_max)` transfer unchanged across the 2-bus, IEEE-13 and IEEE-123
fixtures — which is precisely what "scale-invariant ρ" means. This is why Phase 6's single scalar
`tol` on an ∞-norm max-abs residual must be upgraded: it has no relative term and no dual side.

**Norm choice:** adopt the Boyd **2-norm** on the flattened coupling arrays. Keep the Phase-6
∞-norm (worst `|R_p|`) as an *additional* reported diagnostic if desired, but the stopping test uses
the 2-norm form above (matching the √p·ε_abs scaling).

### Pattern 4: Residual-balancing adaptive-ρ schedule (Boyd §3.4.1, eq. 3.13)

```
ρ^{k+1} = τ_incr · ρ^k        if ‖r^k‖₂ > μ · ‖s^k‖₂        # primal lagging → penalize harder
        = ρ^k / τ_decr        if ‖s^k‖₂ > μ · ‖r^k‖₂        # dual lagging → relax penalty
        = ρ^k                 otherwise
ρ^{k+1} ← clamp(ρ^{k+1}, ρ_min, ρ_max)
```
Boyd-typical `μ = 10`, `τ_incr = τ_decr = 2`. **Unscaled-dual note (critical):** because the loop
tracks the *physical* price `λ` and updates it `λ ← λ + ρ·r` (unscaled form, matching thesis
B.30–B.32), `λ` is **NOT** rescaled when ρ changes — only the *scaled* dual `u = λ/ρ` would need
rescaling, and we don't use it. This is why the existing unscaled ascent is exactly right for
adaptive ρ; do not add a λ-rescale step (a common mistake copied from scaled-form pseudocode).

**Freeze for convergence theory:** Boyd's convergence guarantees assume ρ eventually fixed. Freeze
adaptation once the residuals are both within a loose multiple of tolerance (e.g. after both
`‖r‖ ≤ 10·ε_pri` and `‖s‖ ≤ 10·ε_dual`, or after a `ρ_freeze_iter` cap). This prevents late-stage
ρ oscillation from stalling the tail. Include `ρ_freeze` state in the loop.

**Clamp for SOCP stability:** `ρ_max` (e.g. `1e4` pu) stops the penalty Hessian from dominating and
ill-conditioning the SOCP; `ρ_min` (e.g. `1e-2` pu) keeps the proximal term meaningful. These bounds
are pu, so they transfer across feeders.

### Pattern 5: Extend `AdmmResiduals` as the JuMP-free plotting ledger (ADMM-05)

**What:** the ledger stays a pure data type (no JuMP), and gains the traces the diagnostics need:
```julia
mutable struct AdmmResiduals
    N::Int; T::Int
    primal_trace::Vector{Float64}      # ‖r‖₂ per iter  (was worst |R_p|; keep or add 2-norm)
    dual_trace::Vector{Float64}        # ‖s‖₂ = ρ·‖Δ pag_dso‖₂ per iter   (CORRECTED, Pattern 2)
    rho_trace::Vector{Float64}         # NEW: ρ per iter (shows the adaptive schedule)
    eps_pri_trace::Vector{Float64}     # NEW: ε_pri per iter (threshold line for plots)
    eps_dual_trace::Vector{Float64}    # NEW: ε_dual per iter
    price_gap_trace::Vector{Float64}   # NEW: ‖λ^k − λ^{k−1}‖₂ (or vs centralized DADP when known)
    iters::Int
end
```
`record!` gains the new fields; `converged(res, ε_pri, ε_dual)` becomes the two-residual predicate.
Keeping it JuMP-free is a hard contract (the type's own header states Phase 7 reuses it "on the SAME
traces") so Phase 8 (harness) and the plotting ext consume it without pulling JuMP or a solver.

### Pattern 6: Plotting via a `TSODSOMakieExt` package extension (weakdep)

**What:** mirror the existing `ext/TSODSOGurobiExt.jl` / `ext/TSODSOMosekExt.jl` weakdep pattern.
The core package declares empty generic functions and exports them; the extension provides the
CairoMakie-backed methods. Loaded by Julia ONLY when CairoMakie is present — the core `using TSODSO`
and the headless CI test suite never import Makie.

```julia
# src/diagnostics/plots.jl  (core — stubs only, always exported; NO CairoMakie import)
"""Plot ADMM primal+dual residual traces vs iteration (needs CairoMakie loaded)."""
function plot_convergence end
"""Plot the DADP/price convergence trajectory (needs CairoMakie loaded)."""
function plot_price_convergence end
export plot_convergence, plot_price_convergence
```
```julia
# ext/TSODSOMakieExt.jl  (extension — methods)
module TSODSOMakieExt
using TSODSO, CairoMakie
function TSODSO.plot_convergence(res::TSODSO.AdmmResiduals; filename=nothing)
    f = Figure()
    ax = Axis(f[1, 1]; xlabel="iteration", ylabel="residual (pu)", yscale=log10,
              title="ADMM convergence")
    its = 1:res.iters
    lines!(ax, its, res.primal_trace; label="‖r‖ primal")
    lines!(ax, its, res.dual_trace;   label="‖s‖ dual")
    lines!(ax, its, res.eps_pri_trace;  linestyle=:dash, label="ε_pri")
    lines!(ax, its, res.eps_dual_trace; linestyle=:dash, label="ε_dual")
    axislegend(ax)
    filename === nothing || save(filename, f)   # save("conv.pdf", f) → vector PDF
    return f
end
# plot_price_convergence(res; …) similar — ρ_trace on a twin axis, price_gap_trace, or per-node λ.
end
```
**Project.toml wiring** (add alongside the existing Gurobi/Mosek entries):
```toml
[weakdeps]
CairoMakie = "13f3f980-e62b-5c42-98c6-ff1f3baf88f0"
Gurobi = "..."      # existing
MosekTools = "..."  # existing
[extensions]
TSODSOMakieExt = "CairoMakie"
[compat]
CairoMakie = "0.15"
```
Verify the CairoMakie UUID against the local registry at implementation time (`Pkg`), don't trust the
literal above — treat it `[ASSUMED]` until confirmed.

### Anti-Patterns to Avoid
- **Rebuilding the subproblem when ρ changes.** The whole point of Pattern 1 is that you don't have
  to. Rebuilding inside the loop is the dominant, avoidable performance sink (PITFALLS.md; CLAUDE.md).
- **Modeling λ or ρ as a JuMP `Parameter`.** A `λ·pag` Parameter×variable term is an indefinite
  bilinear the conic backend rejects (Phase-6 Pitfall 1). Keep λ, ρ plain `Float64` coefficients.
- **Rescaling λ when ρ changes.** Only valid in the *scaled* form; we use the unscaled physical price
  (thesis B.30–B.32). Rescaling here corrupts the price trajectory.
- **Stopping on the primal residual alone.** The textbook false-convergence bug (PITFALLS.md P2).
- **A hard CairoMakie dependency in `[deps]`.** Bloats CI + every load; use the extension.
- **Running the PF-04 exactness gate mid-loop.** Early iterates are legitimately inexact (Phase-6
  Pitfall 3); keep `check_exact=true` on the final solve only.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Mutating a quadratic objective coefficient | Manual objective re-assembly / `set_objective_function` each iter | `set_objective_coefficient(m, x, x, c)` (VERIFIED JuMP 1.30.1) | In-place MOI modify; no rebuild; batch vector form available. |
| Dual/primal residual + tolerance math | Bespoke convergence heuristics | Boyd §3.3 eqs. 3.12 (verbatim) | The reference standard; PITFALLS.md + thesis both cite it. |
| Adaptive ρ | Trial-and-error per-feeder ρ tuning | Boyd §3.4.1 residual balancing (τ, μ) | Scale-invariant given per-unit normalization; exactly the "no hard-coded penalty" requirement. |
| Radial validation of IEEE-123 | New topology checker | Existing `assert_radial` (`data/topology.jl`) | Already sparse, BFS-based, edge-count theorem; the `Feeder` constructor calls it. |
| IEEE-123 R/X sourcing | Re-deriving from OpenDSS/IEEE PES + pu conversion | Thesis App. E, p.170 (already per-unit) | The thesis ships the *modified* radial per-unit data directly — no SI→pu step, no OpenDSS parse. |
| Plotting | Custom plotting harness | CairoMakie via extension | STACK.md thesis-figure choice; extension keeps it optional. |

**Key insight:** Every hard part of this phase already has a canonical solution — JuMP for the
coefficient mutation, Boyd for the convergence math, the existing `Feeder`/`assert_radial`/`PerUnit`
machinery for the fixture, and the existing weakdep-extension pattern for plotting. The *only*
genuinely bespoke work is transcribing App. E and closing the transit-node gap.

## Runtime State Inventory

> This is a code + fixture + dependency phase (Julia package), not a rename/migration. No external
> datastore, live service, OS registration, or secret is renamed. The section below is included
> because the phase adds a dependency and a data fixture; each category is answered explicitly.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — ADMM state (λ, c, a, residuals) is in-memory per solve; no persisted DB/collection keyed on any renamed string. | none |
| Live service config | None — no external service; solvers are in-process (Clarabel/HiGHS). | none |
| OS-registered state | None. | none |
| Secrets/env vars | None. | none |
| Build artifacts / pinned env | Adding CairoMakie as a `[weakdeps]` entry changes `Project.toml` and (on `Pkg.resolve`) the committed `Manifest.toml` (INFRA-01). The `docs/Project.toml` may also gain CairoMakie for figure builds (Phase 9). | Update + commit `Manifest.toml`; keep CairoMakie/Makie in lockstep via `[compat]`. |

**Nothing found in categories 1–4:** verified — the framework is an in-process research library with
no runtime-registered state (confirmed by inspecting `src/` — only JuMP models, plain structs, and
seeded RNG data generation).

## Common Pitfalls

### Pitfall 1: Forgetting to update the quadratic coefficient when ρ changes
**What goes wrong:** the loop updates only the linear coefficient (`−λ − ρ·target`) on a ρ-change but
leaves the `±0.5·ρ` on the squared term stale, so the augmented-Lagrangian penalty and the dual step
use *different* ρ values — the proximal geometry no longer matches the ascent step, and ADMM
diverges or converges to a slightly wrong point that still passes the primal test.
**Why it happens:** Phase 6 built the quadratic term once with a fixed ρ and never revisited it; the
natural (wrong) extension is to touch only the linear coefficient that Phase 6 already mutates.
**How to avoid:** the `set_rho!` updater (Pattern 1) mutates the quadratic coefficient; call it in
lockstep with the linear update whenever `ρ` changes, in BOTH AgrOpt and DsoOpt.
**Warning signs:** ADMM welfare/DADP drift from the centralized cross-validation on IEEE-13 after
adaptive ρ is enabled (the Phase-6 fixed-ρ cross-validation still passes → isolates the regression).

### Pitfall 2: Wrong block in the dual residual → false convergence
**What goes wrong:** using `ρ·Δa` (the x-block) instead of `ρ·Δ(pag_dso)` (the z-block) as the dual
residual makes the dual stopping test measure the wrong quantity; the loop can stop early or late.
**Why it happens:** Phase 6 tracked `ρ·Δa` as a placeholder diagnostic; the label "dual residual" is
already on it.
**How to avoid:** track `pag_dso_prev`; compute `s = ρ·(pag_dso − pag_dso_prev)` (Pattern 2).
**Warning signs:** dual residual that never decreases while the price is visibly still moving, or a
stop that disagrees with the centralized DADP beyond tolerance.

### Pitfall 3: Per-unit tolerance getting the dual-residual scale wrong
**What goes wrong:** applying `ε_dual` on `‖λ‖` but computing `s` without the ρ factor (or vice
versa) makes the dual test off by orders of magnitude, so it's either always satisfied (false stop)
or never satisfied (spurious maxiter fail-loud).
**Why it happens:** the dual residual carries a ρ; `ε_dual` is scaled by the *price* norm; mixing
scaled/unscaled conventions flips the balance.
**How to avoid:** use the unscaled convention throughout (Pattern 3/4): `s = ρ·Δz`, `ε_dual =
√n·ε_abs + ε_rel·‖λ‖`. Add a Wave-0 unit test on a hand-computed 2-bus iterate.
**Warning signs:** IEEE-13 that used to converge now hits the fail-loud cap, or converges in 1–2
iterations.

### Pitfall 4: IEEE-123 not radial / non-contiguous node labels
**What goes wrong:** the standard IEEE-123 feeder has 4 normally-open tie switches (weakly meshed)
and non-contiguous node labels (150, 149, 1…114, plus regulator/switch nodes). `assert_radial`
requires `branches == buses − 1` AND `bus.id == 1-based position`; either violation throws at
`Feeder` construction.
**Why it happens:** transcribing App. E verbatim keeps the thesis's original terminal labels, which
are not `1..N` contiguous, and may include tie branches.
**How to avoid:** (a) build a relabeling map `thesis_terminal → 1..N` (analogous to ieee13's `k→k+1`
shift but a full dictionary), document it as a table in the fixture (like ieee13.jl); (b) include
only the *radial* branch set (tie switches open) so `edges == N−1`; (c) pick the substation/frontier
node (thesis "150"/"149") as the `root`. Verify with a Wave-0 test that `ieee123_modified()`
constructs without throwing and that `length(branches) == length(buses) − 1`.
**Warning signs:** `ArgumentError` from `assert_radial` ("N buses require N−1 branches" or "Bus ids
must equal their 1-based position") at fixture construction.

### Pitfall 5: Transit (zero-injection) buses break `build_dso_opt` (integration gap)
**What goes wrong:** `build_dso_opt` currently throws if ANY non-root bus lacks an aggregator
(`DsoOpt.jl:145–154`, the transit-node guard) and `solve_admm` assumes a 1:1 node↔aggregator map
(`solve_admm.jl:130`). IEEE-123 has ~85 load nodes but ~122 non-root buses → ~37 junction/transit
buses with no load. The Phase-6 guards will reject the feeder outright.
**Why it happens:** Phase 6 was validated only on the 2-bus and IEEE-13 fixtures where every non-root
bus carries an aggregator; the guard was an explicit Phase-6 simplification (its own comment calls it
"a Phase-7 generalization").
**How to avoid:** relax the DSO-OPT guard to allow a genuine transit bus: inject 0 into `:Rp[j]` /
`:Rq[j]` at non-load, non-root buses and pin the balance (a physically-correct zero-injection node).
Decouple `load_nodes` (aggregator buses, the ADMM coupling axis) from `all non-root buses` (the
balance-closure axis). Keep the fail-loud guard for a bus that is neither root, nor load, nor a valid
transit node. This is a required, well-scoped code change — plan it as its own task with a unit test.
**Warning signs:** `ArgumentError` "non-root bus j carries no aggregator" the first time IEEE-123 is
fed to `solve_admm`.

### Pitfall 6: Adaptive-ρ oscillation / SOCP ill-conditioning at scale
**What goes wrong:** ρ ratchets up unboundedly (primal always lagging on the voltage-binding
IEEE-123 hours), the penalty Hessian dominates, and Clarabel returns `ALMOST_OPTIMAL`/
`NEARLY_FEASIBLE` or the residuals limit-cycle (PITFALLS.md P2 items 1–2).
**Why it happens:** no clamp; no freeze; over-aggressive τ; or the primal 2-norm and dual 2-norm are
on different effective scales so the μ-band never balances.
**How to avoid:** clamp ρ ∈ `[ρ_min, ρ_max]`; freeze adaptation once both residuals are within
`~10×` tolerance; keep τ=2, μ=10 (do not enlarge); rely on the tight Clarabel gap (1e-8, already set)
and `strict=false` mid-loop (already present) to tolerate benign `ALMOST_OPTIMAL` iterates. Start
with over-relaxation OFF (α=1); consider Boyd §3.4.3 over-relaxation (α∈[1.5,1.8]) ONLY as a later
accelerator if convergence is slow, and treat it as out-of-MVP-scope unless needed.
**Warning signs:** iteration count ≫ tens (thesis reports ~28 on IEEE-13); ρ_trace pinned at ρ_max;
residual plot plateaus above tolerance or saw-tooths.

### Pitfall 7: Exactness invariant failing at scale (high reverse flow / over-voltage)
**What goes wrong:** the IEEE-123 case is explicitly *voltage-constrained* with `V∈[0.9,1.1]` and
high PV — exactly the reverse-flow / binding-upper-voltage regime where the SOC relaxation is most
likely to go inexact (PITFALLS.md P1). The converged PF-04 gate then throws and refuses prices.
**Why it happens:** standard Gan-Low/Farivar-Low exactness conditions weaken under reverse power flow
and binding upper-voltage limits; the LinDistFlow exactness copy (thesis 3.43/3.45, already in
`ConvexBranchFlow`) is what keeps it tight, but its numerical margin shrinks at scale.
**How to avoid:** the exactness copy is already built into `ConvexBranchFlow` and reused verbatim by
DSO-OPT — no new modeling needed. Keep the priced free-sign frontier export (the exactness enabler,
already present). If the gate fails at the converged point, that is a genuine physical finding to
report, not a bug to suppress — surface it via the existing `assert_socp_exact!` throw and the
`exact_maxgap` output. The `rtol=1e-4` base-free tolerance already scales correctly across bases.
**Warning signs:** `assert_socp_exact!` throws "SOCP relaxation INEXACT" only on IEEE-123 (not on
IEEE-13); `l·v` noticeably exceeds `P²+Q²` on branches feeding over-voltage buses.

## Code Examples

### Verified quadratic-coefficient mutation (the load-bearing API)
```julia
# Source: JuMP 1.30.1 installed source ~/.julia/packages/JuMP/EHXNP/src/objective.jl:598-627 (docstring)
julia> model = Model();
julia> @variable(model, x[1:2]);
julia> @objective(model, Min, x[1]^2 + x[1] * x[2])
x[1]² + x[1]*x[2]
julia> set_objective_coefficient(model, x[1], x[1], 2)   # sets coeff of x[1]² to 2
julia> set_objective_coefficient(model, x[1], x[2], 3)   # sets coeff of x[1]*x[2] to 3
julia> objective_function(model)
2 x[1]² + 3 x[1]*x[2]
# Batch form (objective.jl:683-710): one call for many quadratic coeffs
julia> set_objective_coefficient(model, [x[1], x[1]], [x[1], x[2]], [2, 3])
```

### The extended stopping + adaptive-ρ core (sketch, maps to solve_admm.jl step 3–6)
```julia
# Source: Boyd et al. (2011) §3.3 eq.3.12 (tolerances) + §3.4.1 eq.3.13 (balancing); thesis App. B.30-B.32
p = length(load_nodes) * T                      # coupling dimension (n == p here)
# (3) residuals — 2-norm on the flattened coupling arrays
r = norm2(a .- pag_dso)                          # primal  ‖r‖₂
s = ρ * norm2(pag_dso .- pag_dso_prev)           # dual    ‖s‖₂ = ρ·‖Δ z‖₂   (Pattern 2)
ε_pri  = sqrt(p) * ε_abs + ε_rel * max(norm2(a), norm2(pag_dso))
ε_dual = sqrt(p) * ε_abs + ε_rel * norm2(stack_prices(λ))
record!(residuals, k, r, s, ρ, ε_pri, ε_dual, price_snapshot(λ))
# (4) stop on BOTH
if r ≤ ε_pri && s ≤ ε_dual
    converged_flag = true; break
end
# (5) unscaled dual ascent (thesis B.32) — λ is the physical price, NOT rescaled on ρ-change
for j in load_nodes, t in 1:T
    λ[j][t] += ρ * (a[j][t] - pag_dso[j, t]);  c[j][t] = -pag_dso[j, t]
end
pag_dso_prev = deepcopy(pag_dso)
# (6) residual balancing (Boyd §3.4.1) with clamp + freeze
if !ρ_frozen
    ρ_new = r > μ * s ? τ * ρ : (s > μ * r ? ρ / τ : ρ)
    ρ_new = clamp(ρ_new, ρ_min, ρ_max)
    if ρ_new != ρ
        ρ = ρ_new
        set_rho!(dso, ρ); for j in load_nodes; set_rho!(agr_by_bus[j], ρ); end   # Pattern 1
    end
    (r ≤ 10ε_pri && s ≤ 10ε_dual) && (ρ_frozen = true)     # freeze for convergence theory
end
```

### IEEE-123 fixture skeleton (mirrors ieee13.jl; data from thesis App. E p.170)
```julia
# Source: thesis App. E "Datos del alimentador de 123 nodos" (per-unit r/x, terminal i→j)
"""
    ieee123_modified() -> Feeder{Float64}
Modified IEEE 123-node feeder (thesis Case B, App. E). VOLTAGE-CONSTRAINED: V∈[0.9,1.1].
Data is ALREADY per-unit in App. E (no SI→pu step). Node labels are RELABELED thesis
terminal → contiguous 1..N (framework `bus.id == position` convention); the map is the
table below. Only the RADIAL branch set (tie switches open) is included so edges == N−1.
"""
function ieee123_modified()
    vmin, vmax = 0.9, 1.1                          # thesis Case B (looser than ieee13)
    # relabel: Dict(thesis_terminal => 1..N), root = substation/frontier terminal
    # raw = [(term_i, term_j, r_pu, x_pu), …]  transcribed verbatim from App. E p.170
    # branches = [Branch(remap[i], remap[j], r, x, smax) …]; head branch smax from 3.8 MVA / S_base
    # buses = [Bus(k, vmin, vmax, k == root_idx) for k in 1:N]
    return Feeder(buses, branches, root_idx)       # assert_radial + assert_magnitudes run here
end
```

## State of the Art

| Old Approach (Phase 6) | Current Approach (Phase 7) | When Changed | Impact |
|--------------------------|-----------------------------|--------------|--------|
| Fixed ρ (5 / 100), primal-only ∞-norm stop | Adaptive ρ (Boyd §3.4.1) + primal AND dual 2-norm stop with per-unit tolerances | This phase | Scale-invariant across feeders; no false convergence. |
| Quadratic penalty coeff fixed at build | `set_objective_coefficient(m,x,x,·)` in-place mutation on ρ-change | This phase (JuMP 1.30.1) | Adaptive ρ without rebuild; build-once preserved. |
| Dual residual = `ρ·Δa` (x-block diagnostic) | `s = ρ·Δ(pag_dso)` (z-block, Boyd-correct) | This phase | Correct optimality test. |
| Every non-root bus must carry an aggregator | Transit (zero-injection) buses allowed | This phase | IEEE-123 (37 junction buses) becomes solvable. |
| No plotting | `TSODSOMakieExt` weakdep extension | This phase | Thesis-grade vector diagnostics, core stays plot-free. |

**Deprecated/outdated:**
- The thesis's `ρ=1000` (thesis §2.6): tuned to the original MATLAB/CVX per-unit scaling; NOT a
  target here. The per-unit-normalized adaptive scheme replaces it (PITFALLS.md P2).
- The 2-arg `set_objective_coefficient(m, x, c)` is linear-only; the 3-arg (quadratic) form is the
  one this phase needs — both coexist in JuMP 1.30.1.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | CairoMakie UUID `13f3f980-…` and version 0.15.13 / Makie 0.24.13 | Stack / Pattern 6 | Low — confirmed against local registry at `Pkg.add`; wrong UUID fails loudly at resolve. |
| A2 | IEEE-123 App. E branch set is radial once tie switches are open (edges == N−1) | Pitfall 4 / fixture | Medium — if the thesis's modified topology isn't a clean tree, need a documented radialization choice; `assert_radial` catches it at construction (fail-loud, not silent). |
| A3 | Head-branch limit 3.8 MVA and the App. E pu r/x share the thesis's S_base (documented as 100 MVA elsewhere; App. E doesn't restate it) | fixture | Medium — a wrong S_base mis-scales only the head `smax` (a magnitude-band check guards gross errors); r/x are given directly in pu so are unaffected. |
| A4 | Clarabel accepts `ScalarQuadraticCoefficientChange` via the CachingOptimizer (same path as the working linear modify) | Pattern 1 | Low — mechanism identical to the in-use linear modify; a Wave-0 test confirms empirically before the loop depends on it. |
| A5 | The monolithic IEEE-123 SOCP (`solve_welfare`) still solves in Clarabel for cross-validation | convergence expectation | Low-Medium — ~123 buses × 24h + devices is well within IPM range; if it ever OOMs, the fallback gate is residuals→0 + PF-04 exactness + PRICE-04 economic-direction sanity. |
| A6 | ~85 load nodes ⇒ ~37 transit buses (thesis Case B says "85 load nodes") | Pitfall 5 | Low — the exact transit count falls out of the fixture; the guard relaxation handles any number. |

## Open Questions (RESOLVED)

> RESOLVED and adopted by the plans: (1) IEEE-123 root/MEM terminal → the no-parent terminal (150), fixed in 07-02; (2) seeded per-node aggregators for the load nodes (exact thesis device params deferred to Phase-9 regression) → 07-01/07-05; (3) 2-norm stopping with ∞-norm kept as a diagnostic → 07-04.

1. **Which thesis terminal is the MEM frontier / root on IEEE-123?**
   - What we know: App. E lists (150,149) and (149,1) as the first branches; the standard IEEE-123
     substation is node 150 (with a regulator to 149). Thesis node 0 = MEM frontier convention.
   - What's unclear: whether the thesis collapses the 150-149 regulator into a single root or keeps
     both as buses.
   - Recommendation: root = the terminal with no parent (150). Document the choice in the fixture
     header table (as ieee13.jl documents its node→index map); a Wave-0 test asserts `feeder.root`
     is the intended bus.

2. **Do all 85 load nodes need full device detail for the convergence/scale test, or lightweight aggregators?**
   - What we know: the phase goal is convergence + scale, not reproducing the thesis's exact $1976
     welfare (that's Phase 9 regression).
   - What's unclear: whether Phase 7 populates all 85 nodes with thesis-parametrized houses or uses
     seeded/scaled aggregators (like the Phase-6 fixtures do).
   - Recommendation: use seeded per-node aggregators (reuse the Phase-4/6 fixture builders) sized to
     keep the case feasible and voltage-binding; defer exact thesis-parameter reproduction to the
     Phase-9 regression fixture. Keep the fixture data (topology) separate from the aggregator
     population (test/experiment layer) as Phase 6 already does.

3. **2-norm vs ∞-norm for the reported residual traces?**
   - Recommendation: stop on 2-norm (Pattern 3, matches √p·ε_abs). Optionally also record the ∞-norm
     worst `|R_p|` for continuity with Phase 6 diagnostics; it's cheap and aids debugging.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | ✓ | 1.12.5 (compat floor 1.10) | — |
| JuMP | quadratic-coeff mutation, subproblems | ✓ | 1.30.1 (installed) | — |
| Clarabel | SOCP/QP solves | ✓ (in Manifest) | 0.11.1 | — |
| HiGHS / Ipopt | available, not on SOCP path | ✓ | 1.24.1 / 1.15.0 | — |
| SparseArrays | topology | ✓ | stdlib | — |
| CairoMakie | ADMM-05 plotting (weakdep) | ✗ NOT installed | target 0.15.13 | Plotting is optional by design — core solve + tests run without it; researcher installs on demand. |
| Makie | pulled in by CairoMakie | ✗ | target 0.24.13 | Same. |
| thesis App. E data | IEEE-123 fixture | ✓ (PDF present) | `docs/references/86. Tesis…pdf` p.170 | — |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** CairoMakie/Makie — absent now, added as a weakdep this phase;
the core solve and the non-plotting test suite never require them (that is the whole point of the
extension), so CI stays green and fast without them.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Test (stdlib) + TestItemRunner / `@testitem` (TestItems 1.0) |
| Config file | `test/runtests.jl` (+ `test/Project.toml`, `test/Manifest.toml`) |
| Quick run command | `julia --project -e 'using TestItemRunner; @run_package_tests filter=ti->occursin("admm", ti.name)'` |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` |

Item-name filter substrings are the project convention (Phase-6 used "admm"/"crossval"/"resolve").
Add "adaptive", "dualresid", "ieee123", "diagnostics" for the new items.

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ADMM-02 | Stops on BOTH primal + dual residual (2-norm, per-unit ε) | unit + integration | `… filter=ti->occursin("dualresid", ti.name)` | ❌ Wave 0 |
| ADMM-02 | Adaptive ρ changes both linear AND quadratic coeff, no rebuild (num_variables constant) | unit | `… filter=ti->occursin("adaptive", ti.name)` | ❌ Wave 0 |
| ADMM-02 | Same `(ε_abs,ε_rel,τ,μ)` converges 2-bus AND IEEE-13 (scale-invariance) | integration | `… filter=ti->occursin("adaptive", ti.name)` | ❌ Wave 0 |
| ADMM-02 | Cross-validation ADMM welfare + DADP == centralized on 2-bus + IEEE-13 (regression: adaptive ρ didn't break Phase-6) | integration | reuse `test_admm.jl` crossval items | ✅ (extend) |
| ADMM-05 | `AdmmResiduals` records primal/dual/ρ/ε/price traces (JuMP-free) | unit | `… filter=ti->occursin("residual", ti.name)` | ✅ `test/…` (extend) |
| ADMM-05 | `plot_convergence` errors helpfully without CairoMakie; returns a `Figure` with it | unit (ext) | separate ext test (loads CairoMakie) | ❌ Wave 0 |
| (scale) | `ieee123_modified()` constructs (radial, magnitudes, contiguous ids, root correct) | unit | `… filter=ti->occursin("ieee123", ti.name)` | ❌ Wave 0 |
| (scale) | IEEE-123 ADMM converges in ~tens of iters; λ_j → DADP; PF-04 exact at convergence | integration | `… filter=ti->occursin("ieee123", ti.name)` | ❌ Wave 0 |
| (scale) | Transit (zero-injection) bus handled by `build_dso_opt` | unit | `… filter=ti->occursin("ieee123", ti.name)` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the `admm`/`adaptive`/`dualresid` filtered items (fast — 2-bus + small).
- **Per wave merge:** full `admm` + `ieee123` items (IEEE-123 is the slow one; keep it in the merge
  gate, not the per-commit loop).
- **Phase gate:** full suite green (including the centralized cross-validation) before
  `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/test_admm_adaptive.jl` (or extend `test_admm.jl`) — adaptive-ρ + build-once-under-ρ-change (ADMM-02)
- [ ] `test/test_admm_dualresid.jl` — dual-residual computation + two-residual stop + per-unit tolerances (ADMM-02)
- [ ] Extend `test/test_admm.jl` residual/ledger item — new `AdmmResiduals` traces (ADMM-05)
- [ ] `test/test_ieee123.jl` — fixture construction + radial/magnitude/relabel asserts + transit-node
- [ ] `test/test_ieee123_admm.jl` — IEEE-123 convergence + λ→DADP + PF-04 exactness (integration)
- [ ] Extension test (loads CairoMakie in a separate env) — `plot_convergence`/`plot_price_convergence`
- [ ] Fixture: `test/fixtures_phase7.jl` `@testmodule` — IEEE-123 seeded aggregator population (85 nodes)
- [ ] CairoMakie install: add to `[weakdeps]` + `[extensions]` + `[compat]`; `Pkg.resolve`; commit Manifest

## Security Domain

> `security_enforcement` is not set in `.planning/config.json`; treated as enabled. This is an
> offline numerical-optimization research library — no auth, session, network endpoint, or untrusted
> external input — so most ASVS categories are Not Applicable. The relevant control is input
> validation on fixture data, which already exists.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No users/credentials. |
| V3 Session Management | no | No sessions. |
| V4 Access Control | no | Single-user local research tool. |
| V5 Input Validation | yes | `assert_radial` (DATA-02), `assert_magnitudes` (INFRA-05), and `assert_solved!`/`assert_socp_exact!` (INFRA-03/PF-04) already fail loud on malformed feeder data, out-of-band magnitudes, non-optimal solves, and inexact relaxations. The IEEE-123 fixture inherits these at construction. No new input surface. |
| V6 Cryptography | no | None used; RNG is `StableRNGs` for reproducibility, not security. |

### Known Threat Patterns for this stack
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Silently-wrong prices from an inexact SOC relaxation at scale | Tampering (of the physical result) | PF-04 `assert_socp_exact!` throws + refuses prices (already built; re-exercised on IEEE-123). |
| False convergence reported as an optimum | Repudiation (of a claimed result) | Two-residual stop + fail-loud maxiter + centralized cross-validation (ADMM-02/03). |
| Malformed/non-radial fixture data | Tampering | `Feeder` constructor invariants (DATA-02/INFRA-05). |
| Supply-chain (new plotting dep) | Tampering | Weakdep only; registry-verified; pinned in committed Manifest (INFRA-01). |

## Sources

### Primary (HIGH confidence)
- **JuMP 1.30.1 installed source** `~/.julia/packages/JuMP/EHXNP/src/objective.jl:598-681,683-720` —
  the 3-arg and vector `set_objective_coefficient` quadratic API + docstring example (the load-bearing
  verification for the ROADMAP-flagged problem). `Project.toml` confirms version 1.30.1.
- **Palacios PhD thesis** `docs/references/86. Tesis Doctoral Juan Pablo Palacios (2).pdf`:
  App. B pp.156-165 (ADMM unscaled form B.30-B.32, PCPM variant B.38-B.49), App. C pp.166-168
  (battery no-binary proof), App. E p.170 (**123-node per-unit R/X data**), §2.6 / Case B pp.176-178
  (thesis ρ, ε, ~28 iters; IEEE-123: 4.16 kV, 85 load nodes, V∈[0.9,1.1], S_max,01=3.8 MVA).
- **Existing Phase 1-6 source** (read in full): `src/admm/{solve_admm,residuals,AgrOpt,DsoOpt}.jl`,
  `src/models/exactness.jl`, `src/data/{ieee13,Feeder,topology}.jl`, `src/solver/factory.jl`,
  `Project.toml`/`ext/*` (weakdep pattern), `test/{test_admm,fixtures_phase6}.jl`.
- **`.planning/research/THEORY-thesis.md`** — model equations 3.31-3.47, ADMM decomposition, Case
  A/B data. **`.planning/research/PITFALLS.md`** — Pitfall 1 (exactness), Pitfall 2 (ADMM
  convergence: dual residual, adaptive ρ, per-unit normalization, cross-validation) — explicitly
  cites Boyd §3.3-3.4 as HIGH confidence.
- **Context7 `/makieorg/makie.jl`** (HIGH reputation, 1519 snippets) — `Figure`/`Axis`/`lines!`/
  `scatterlines!`/`save` API for the diagnostics extension.

### Secondary (MEDIUM confidence)
- **Boyd, Parikh, Chu, Peleato, Eckstein (2011), "Distributed Optimization and Statistical Learning
  via ADMM," §3.3 (stopping, eq. 3.12) and §3.4.1 (varying penalty, eq. 3.13)** — the canonical
  source for the dual residual, per-unit tolerances, and residual-balancing schedule (cited by both
  PITFALLS.md and the thesis; standard ADMM reference).
- **STACK.md / Julia General registry `Versions.toml` (fetched 2026-07-18)** — CairoMakie 0.15.13,
  Makie 0.24.13, and all pinned versions.
- **JuMP official docs** (jump.dev/JuMP.jl/stable/manual/objective) — corroborates the quadratic
  `set_objective_coefficient` signature and semantics.

### Tertiary (LOW confidence — flagged for validation)
- CairoMakie UUID literal in Pattern 6 — confirm at `Pkg.add` (A1).
- IEEE-123 radialization + root choice + S_base for the head limit — confirm against App. E table +
  `assert_radial`/`assert_magnitudes` at fixture construction (A2, A3, Open Q1).

## Metadata

**Confidence breakdown:**
- Adaptive-ρ quadratic-coefficient mechanism (the flagged problem): **HIGH** — verified in the
  installed JuMP 1.30.1 source + docstring example; Clarabel path identical to the working linear modify.
- Dual residual + per-unit tolerances + balancing schedule: **HIGH** — standard Boyd, corroborated by
  PITFALLS.md and thesis App. B.
- IEEE-123 fixture: **MEDIUM-HIGH** — data location verified (App. E, per-unit), but transcription +
  relabeling + radialization + transit-node integration are real, error-prone work items (mitigated by
  fail-loud `assert_radial`/`assert_magnitudes` and a regression check).
- Diagnostics / CairoMakie extension: **HIGH** on the pattern (mirrors existing ext/), MEDIUM on the
  exact version/UUID (confirm at install).

**Research date:** 2026-07-19
**Valid until:** ~2026-08-19 (30 days — stable Julia/JuMP ecosystem; re-check CairoMakie version at
install and re-confirm the JuMP quadratic API if JuMP majors past 1.30.x).

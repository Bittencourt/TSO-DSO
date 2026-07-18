# Phase 3: Prosumer Device Library & Social-Welfare Solve - Research

**Researched:** 2026-07-18
**Domain:** Convex QP prosumer-device modeling + centralized social-welfare assembly in JuMP (temporal-coupling devices, aggregator roll-up, GLB-CVX, seeded Markov profiles) over the Phase-2 LinDistFlow linear branch-flow model.
**Confidence:** HIGH (device math and no-binary battery proof traced directly to thesis eqs. 3.2–3.23 and App. C; existing seams read from source; RNG reproducibility verified against official Julia docs)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
Every model follows the source thesis — no user-preference grey areas. Anchored to source theory + Phase 1–2 seams:

- **Device contract (Phase 2):** every device is an `AbstractDevice` whose `contribute!` adds decision variables, temporal-coupling constraints, a concave quadratic utility (via `add_to_objective!`), and a signed injection into `ctx.residuals` — and NEVER references the network/topology.
- **Thermostatic load:** temperature state dynamics (RC/ETP-style recursion) + comfort-band utility.
- **Deferrable load:** energy-budget / time-window coupling with a concave utility.
- **PV + battery (BESS):** SOC dynamics, PV-limited charge, charge-utility/discharge-cost preferences — **NO binary variables**; rely on the App. C parametrization so `p_ch·p_dch ≈ 0` holds at the optimum. Hard correctness requirement — verify complementarity numerically at the solution.
- **Aggregator (DEV-05):** rolls its member devices into nodal net active/reactive power and total utility; the aggregator (not the device) is what the network sees. Device modules stay network-agnostic (enforced by grep + design).
- **GLB-CVX (OPT-01):** social-welfare objective = Σ aggregator utility − wholesale/MEM purchase cost, assembled from device utility terms + the linear power-flow model, solved centrally to a **global** optimum via `select_optimizer(QP())` (convex QP — Clarabel for accurate duals), gated on OPTIMAL.
- **Seeded profiles (DATA-04):** first-order Markov-chain demand and PV profile generation that is **reproducible** (same seed → identical profiles). Use a seeded RNG passed explicitly; no global RNG state. Feeds the solve.
- **Solver/status discipline (CLAUDE.md):** no model names a concrete solver; `assert_solved!` gates.

### Claude's Discretion
Anchored to source theory + Phase 1–2 seams (see above). The horizon length, the exact device-vs-aggregator residual-writing split, and the profile-generator package choice are within discretion, resolved with recommendations below.

### Deferred Ideas (OUT OF SCOPE)
- SOCP / exact convex branch flow → Phase 4.
- DADP/DLMP price decomposition → Phase 5.
- ADMM decomposition of the welfare solve → Phase 6.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DEV-01 | Thermostatic-load model (temperature linear in power, comfort bounds) + quadratic utility | §Device Models → Thermostatic; thesis eqs. 3.2–3.3, utility 3.11, coeffs 3.13–3.14 |
| DEV-02 | Deferrable-load model (energy-within-window) + quadratic utility | §Device Models → Deferrable; thesis eqs. 3.4–3.5, utility 3.12 |
| DEV-04 | PV + battery (BESS): SOC dynamics, PV-limited charge, charge-utility/discharge-cost, **no binaries** | §Device Models → PV+Battery; thesis eqs. 3.6–3.9, 3.15–3.20, App. C proof |
| DEV-05 | Aggregator rolls devices into nodal net active/reactive power + total utility; devices network-agnostic | §Aggregator Roll-up; thesis eqs. 3.21–3.23 |
| OPT-01 | GLB-CVX social welfare = Σ aggregator utility − wholesale/MEM purchase cost | §GLB-CVX Assembly; thesis eq. 3.38, convex QP |
| DATA-04 | Seeded inelastic-demand + PV profiles via first-order Markov synthesis (data-gen only) | §Seeded Markov Profiles; thesis §2.8; StableRNGs.jl |
</phase_requirements>

## Summary

This phase completes the operational vertical slice at **linear fidelity**: three temporally-coupled prosumer device models (thermostatic, deferrable, PV+battery), an aggregator that rolls member devices into nodal net active/reactive power and utility, the `GLB-CVX` social-welfare objective, and a seeded Markov-chain profile generator — all solved as a single centralized **convex QP** over the existing Phase-2 `LinDistFlow` formulation. The SOCP cone, DADP price decomposition, and ADMM are explicitly out of scope (Phases 4–6). Because every device utility is concave-quadratic (curvature `b > 0`) and the LinDistFlow constraints are affine, the assembled welfare-maximization is a **convex QP** whose local optimum is the global optimum — routed to Clarabel via `select_optimizer(QP())` exactly as the existing `solve_linear` already does.

The two headline correctness risks are: (1) the **no-binary battery** — App. C of the thesis proves that with `λ_min ≤ λ_med ≤ λ_max` the concave charge utility and convex discharge cost make simultaneous charge/discharge strictly dominated, so `p_ch·p_dch = 0` holds at the optimum **without** any complementarity constraint or binary; this must be verified numerically after every solve. (2) **Reproducibility of the Markov profiles** — Julia's stdlib `Random` explicitly does *not* guarantee a stable stream across Julia versions [CITED: docs.julialang.org/en/v1/stdlib/Random], so DATA-04 + INFRA-04 ("regenerate bit-for-bit") require `StableRNGs.jl` [VERIFIED: JuliaRegistries/General, v1.0.4], threaded as an explicit `AbstractRNG` argument.

Two design tensions the planner must resolve are laid out concretely below: (a) whether the **aggregator** becomes the sole residual-writer (devices return expressions) or devices keep self-injecting active power as Interruptible does today — recommendation: aggregator-as-writer, because DEV-05 says "the aggregator, not the device, is what the network sees" and thesis 3.21–3.23 are aggregator-level quantities; and (b) the existing `linear_solve.jl` **WR-03 invariant** — it currently pins `:Rq` at every bus with *no* reactive frontier source, forcing `Q ≡ 0`; Phase 3 introduces reactive load (eq. 3.23), so the assembly MUST add a free-sign `q_import[t]` at the root before closing `:Rq`, exactly as that file's inline note demands.

**Primary recommendation:** Add three device modules + an `Aggregator` type following the `Interruptible` pattern (immutable concretely-typed struct, throw-based concavity/consistency guards, `contribute!` dispatch); make the `Aggregator` the network-facing residual-writer (active into `:Rp`, reactive into `:Rq`, utility into the objective); generalize `solve_linear` into `solve_welfare` over multiple aggregators at horizon **T=24** with a free-sign `q_import` at the root; generate inelastic-demand and PV profiles with a hand-rolled first-order Markov chain driven by an explicit `StableRNGs.LehmerRNG` seed; and add an automated post-solve assertion `p_ch[t]·p_dch[t] < τ` per battery per hour.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Device decision vars + temporal-coupling constraints (3.2–3.9) | Device model (`src/devices/*`) | — | Device owns its own physics; network-agnostic (holds bus/horizon only) |
| Concave quadratic utility (3.10–3.20) | Device model → objective accumulator | Aggregator (sums) | Utility is a per-device preference; curvature must stay in the QuadExpr objective |
| Nodal net active/reactive injection + utility roll-up (3.21–3.23) | Aggregator (`src/devices/Aggregator.jl`) | Device (supplies terms) | DEV-05: the aggregator, not the device, is what the network sees |
| Nodal power balance residual `:Rp`/`:Rq` (3.31–3.32) | Power-flow formulation (`LinDistFlow`) + Aggregator | Assembly closes it | Formulation subtracts branch terms; aggregator adds injections; assembly pins to 0 |
| GLB-CVX welfare objective (3.38) | Assembly (`solve_welfare`) | Aggregators (utility), market (λ₀) | Only assembly knows both the utility side and the priced frontier import |
| Frontier import pricing (`p_import`, `q_import`) | Assembly | Market data (λ₀) | Root/MEM boundary is an assembly concern, not a device |
| Seeded inelastic-demand + PV profiles (3.8 §2.8) | Data layer (`src/data/profiles.jl`) | — | **Data generation, NOT optimization** — pure, JuMP-free, enters as parameters |
| Solver selection | `select_optimizer(QP())` | — | Convex QP; Clarabel for accurate duals (INFRA-02) |
| Solve-status gate | `assert_solved!` | — | INFRA-03; read no value/dual before OPTIMAL+feasible |

## Standard Stack

### Core (already present — reuse, do not re-add)
| Library | Version (pinned) | Purpose | Why Standard |
|---------|------------------|---------|--------------|
| JuMP | 1.30.1 | Algebraic modeling; `@variable`, `@constraint`, `QuadExpr` utility, `dual()` | Project standard; all seams already built on it |
| Clarabel | 0.11.1 | `QP()` backend — native quadratic objective, accurate duals | Already wired in `factory.jl` for `QP()`/`SOCP()` |
| HiGHS | 1.24.1 | `LP()`/`MILP()` backend | Present; not needed this phase (welfare is a QP) |
| Ipopt | 1.15.0 | `NLP()` cross-check backend | Present; optional cross-solver sanity check |
| SparseArrays | stdlib | Sparse structural data | Present |

### Supporting (NEW — must be added to Project.toml)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `StableRNGs` | **1.0.4** | Cross-Julia-version-stable seeded RNG for the Markov profile generator (DATA-04, INFRA-04) | Data generation only; construct `StableRNGs.LehmerRNG(seed)` and thread it explicitly — never a global RNG |
| `Random` (stdlib) | — | `AbstractRNG` interface, `rand(rng)` | Use the *interface* (accept `::AbstractRNG`), but seed with a `StableRNGs` instance, not `Random.seed!` |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `StableRNGs.jl` | stdlib `Random` (`Xoshiro`/`MersenneTwister`) with `Random.seed!` | Julia docs explicitly warn the stream **may change across Julia minor versions** [CITED: docs.julialang.org/en/v1/stdlib/Random]; reproducing a thesis figure on Julia 1.10 LTS vs 1.11 would silently diverge. Rejected for the reproducibility-critical path. |
| Hand-rolled categorical draw | `Distributions.jl` `Categorical` | `Distributions` is a large, heavy dependency; a first-order Markov step is a single cumulative-sum categorical draw over a transition-matrix row — trivially hand-rolled with `rand(rng)`. Keeping the dependency surface minimal matches the project's pinnable-deps preference. Do **not** add `Distributions.jl`. |
| Aggregator-as-writer | Devices self-inject (current Interruptible pattern) | See §Open Questions Q1 — recommendation is aggregator-as-writer for DEV-05 fidelity; the alternative is lower-migration-cost but weaker on the "aggregator is what the network sees" criterion. |

**Installation:**
```julia
# In the project environment (Pkg.activate then):
import Pkg; Pkg.add("StableRNGs")   # adds StableRNGs 1.0.4 to Project.toml + Manifest.toml
```
Then add to `[compat]` in `Project.toml`: `StableRNGs = "1.0.4"` (floor at the pinned version for reproducibility; the package is pure-Julia with `julia ≥ 1.0` compat, safe on both 1.10 LTS and 1.11).

**Version verification:** `StableRNGs` latest is **1.0.4** — verified directly against the authoritative `JuliaRegistries/General` `Versions.toml` (raw.githubusercontent.com), 2026-07-18. It is maintained by the JuliaRandom organization (the same org as the stdlib RNGs).

## Package Legitimacy Audit

> Julia-ecosystem phase. slopcheck targets npm/PyPI/crates and does not cover the Julia General registry; legitimacy is established by (a) authoritative registry lookup and (b) provenance (maintaining organization).

| Package | Registry | Age / Latest | Source Repo | Verdict | Disposition |
|---------|----------|--------------|-------------|---------|-------------|
| `StableRNGs` | JuliaRegistries/General | latest 1.0.4; series since 0.1.x | github.com/JuliaRandom/StableRNGs.jl | Authoritative registry hit + JuliaRandom org (canonical RNG maintainers) | Approved |
| `Clarabel`, `HiGHS`, `Ipopt`, `JuMP`, `SparseArrays` | — | already in Project.toml (Phase 1) | — | Pre-approved (Phase 1) | Reuse unchanged |

**Packages removed due to slop verdict:** none.
**Packages flagged as suspicious:** none. `StableRNGs` is a widely-used (JuliaRandom-org) reproducibility utility; recommendation stands. slopcheck was not run (ecosystem mismatch); the sole new package is verified against the authoritative Julia registry and its canonical maintaining org, so this is not tagged `[ASSUMED]`.

## Architecture Patterns

### System Architecture Diagram (build-time data flow for one centralized welfare solve)

```
  seed (Int) ──► StableRNGs.LehmerRNG(seed) ──► first-order Markov chains
                                                   │  (data layer, NO JuMP)
                                                   ▼
                              inelastic-demand P_dc[h,t]  +  PV P_pv[h,t]   (parameters)
                                                   │
   Feeder (Phase 1) ─┐                             │
   MarketData λ₀[t] ─┤                             ▼
                     │        ┌───────────── Aggregator (per node j) ──────────────┐
                     │        │  owns devices at bus j + power factor φ_j           │
                     │        │  contribute!(agg, ctx; T):                          │
                     │        │    for each device d:  (p_d, q_d, U_d) ◄────────────┼── Thermostatic (3.2–3.3, U 3.11)
                     │        │    p_ag = Σ_d p_d      (3.22)                        │── Deferrable   (3.4–3.5, U 3.12)
                     │        │    q_ag = Σ_d q_d      (3.23, from φ)                │── PV+Battery   (3.6–3.9, U 3.15–3.20)
                     │        │    add_to_residual!(:Rp, j, t, +p_ag_inject)        │   (devices are network-agnostic)
                     │        │    add_to_residual!(:Rq, j, t, +q_ag_inject)        │
                     │        │    add_to_objective!(Σ_d U_d)                       │
                     │        └─────────────────────────────────────────────────────┘
                     ▼                              │
   LinDistFlow.contribute!(pf, ctx, feeder; T) ────┤  subtracts branch P,Q into :Rp/:Rq (3.31–3.33)
   (branch flows P,Q, squared voltage v)           ▼
                              ┌──────────── solve_welfare (assembly) ───────────────┐
                              │  p_import[t] ≥ 0  at root (+, priced at λ₀)          │
                              │  q_import[t] free-sign at root (reactive frontier)   │ ◄── WR-03 fix
                              │  close :Rp: balance_p[j,t] == 0   (dual = future DADP)│
                              │  close :Rq: balance_q[j,t] == 0                       │
                              │  @objective(Max, Σ U_ag − Σ_t λ₀[t]·p_import[t])     │  (3.38)
                              │  assert_solved!(model; dual=true, allow_local=false) │  (INFRA-03)
                              └──────────────────────────────────────────────────────┘
                                                   │
                                                   ▼
                     post-solve: assert p_ch[t]·p_dch[t] < τ  ∀battery,t   (App. C numerical check)
```

### Recommended Project Structure (additions only)
```
src/
├── data/
│   └── profiles.jl          # NEW: first-order Markov gen (StableRNGs) — inelastic demand + PV. NO JuMP.
├── devices/
│   ├── Thermostatic.jl      # NEW: eqs. 3.2–3.3, utility 3.11, coeffs 3.13–3.14
│   ├── Deferrable.jl        # NEW: eqs. 3.4–3.5, utility 3.12
│   ├── PVBattery.jl         # NEW: eqs. 3.6–3.9, utility 3.15–3.20 (NO binaries)
│   └── Aggregator.jl        # NEW: eqs. 3.21–3.23 roll-up; the network-facing residual-writer (DEV-05)
├── models/
│   └── welfare_solve.jl     # NEW: generalizes linear_solve.jl to multi-aggregator GLB-CVX (OPT-01)
└── results/
    └── battery_check.jl     # NEW (or fold into welfare_solve): assert p_ch·p_dch ≈ 0 (App. C)
test/
├── test_thermostatic.jl     # name must contain the @testitem filter substring
├── test_deferrable.jl
├── test_pvbattery.jl        # includes the no-binary complementarity assertion
├── test_aggregator.jl
├── test_profiles.jl         # same seed → identical profiles (bit-for-bit)
└── test_welfare_solve.jl    # end-to-end multi-device GLB-CVX; global-optimum + cross-solver sanity
```
Wire each new `src/` file into `src/TSODSO.jl`'s include graph in dependency order (`profiles.jl` after `data/`, devices after `Interruptible.jl`, `Aggregator.jl` after the concrete devices, `welfare_solve.jl` after `linear_solve.jl`). `TSODSO.jl` itself exports nothing — each seam file declares its own `export`s (existing convention).

### Pattern 1: Device-as-type contributing (replicate Interruptible exactly)
**What:** Each device is an immutable, concretely-typed parametrized struct with a throw-based inner-constructor guard, plus a `contribute!(d, ctx; T)` method that creates variables + temporal constraints, contributes a signed injection, adds a concave `QuadExpr` utility, and returns its variable container.
**When to use:** All three new devices.
**Example (thermostatic, traced to thesis 3.2–3.3, 3.11):**
```julia
# Source: pattern from src/devices/Interruptible.jl; math from THEORY-thesis.md eqs. 3.2–3.3, 3.11
struct Thermostatic{T<:Real} <: AbstractDevice
    bus::Int
    α::T            # thermal coupling to ambient (3.2)
    β::T            # power-to-temperature gain (3.2)
    Tmin::T; Tmax::T   # comfort band (3.3)
    Tin0::T         # initial indoor temperature (state IC for the recursion)
    Pmin::T; Pmax::T   # A/C power bounds
    b::T            # utility curvature > 0 (concavity, 3.11/3.14)
    Tout::Vector{T} # ambient profile parameter, length T-horizon (3.2)
    function Thermostatic(bus, α::T, β, Tmin, Tmax, Tin0, Pmin, Pmax, b, Tout) where {T<:Real}
        b > zero(T) || throw(ArgumentError("Thermostatic utility curvature b must be > 0 (thesis 3.11); got b=$b"))
        Tmax >= Tmin || throw(ArgumentError("comfort band requires Tmax ≥ Tmin"))
        Pmax >= Pmin || throw(ArgumentError("power bounds require Pmax ≥ Pmin"))
        # ... promote/convert, length(Tout) check deferred to contribute! (needs T)
        new{T}(bus, α, β, Tmin, Tmax, Tin0, Pmin, Pmax, b, Tout)
    end
end

function contribute!(d::Thermostatic, ctx::ModelContext; T::Int)
    m = ctx.model
    p    = @variable(m, [t = 1:T], lower_bound = d.Pmin, upper_bound = d.Pmax)
    Tin  = @variable(m, [t = 1:T], lower_bound = d.Tmin, upper_bound = d.Tmax)   # comfort band (3.3)
    @constraint(m, Tin[1] == d.Tin0)                                             # state IC
    @constraint(m, [t = 1:T-1],                                                  # recursion (3.2)
        Tin[t+1] == Tin[t] + d.α*(d.Tout[t] - Tin[t]) - d.β*p[t])
    # Active injection: A/C is a load ⇒ NEGATIVE injection −p (Interruptible sign convention).
    # RECOMMENDED (see Q1): return terms to the Aggregator instead of self-injecting.
    add_to_objective!(ctx, sum(-(d.b/2)*(Tin[t] - d.Tmin)^2 for t in 1:T))       # concave utility (3.11)
    return (; p, Tin)
end
```

### Pattern 2: Aggregator as the network-facing roll-up (DEV-05, thesis 3.21–3.23)
**What:** An `Aggregator` holds a bus id, a power factor `φ`, and a `Vector{AbstractDevice}` at that bus (plus the inelastic-demand and PV *parameter* profiles for its houses). `contribute!(agg, ctx; T)` drives each device, sums their active contributions into `p_ag` (3.22) and derives reactive `q_ag = tan(acos φ) · (active load draws)` (3.23), injects `p_ag`/`q_ag` into `:Rp`/`:Rq` at its bus, and adds the summed utility to the objective.
**Why:** DEV-05 requires "the aggregator, not the device, is what the network sees." Reactive power is defined at the aggregator level (3.23) as a power-factor function of the flexible/inelastic *active* draws — batteries and PV are active-only.
**Reactive relation (3.23):** `q = P · √(1−φ²)/φ = P · tan(arccos φ)`, where `φ` is the load power factor (∈ [0.85, 0.95]). Batteries/PV contribute **no** reactive term.
```julia
# Source: THEORY-thesis.md eqs. 3.21 (utility), 3.22 (p_ag), 3.23 (q_ag)
function contribute!(agg::Aggregator, ctx::ModelContext; T::Int)
    tanφ = sqrt(1 - agg.φ^2) / agg.φ                     # tan(arccos φ)  (3.23)
    for t in 1:T
        p_active = AffExpr(0.0)                           # signed net active injection at bus (3.22)
        q_active = AffExpr(0.0)                           # signed net reactive injection at bus (3.23)
        for d in agg.devices
            (pj, qj) = device_terms(d, ctx, t)           # per-device active/reactive contribution
            add_to_expr!(p_active, pj)
            add_to_expr!(q_active, qj)                    # only flexible/inelastic loads contribute q
        end
        # inelastic demand P_dc (parameter, negative injection) + PV P_pv (parameter, positive):
        add_to_residual!(ctx, :Rp, agg.bus, t, p_active - agg.Pdc[t] + agg.Ppv_inject[t])
        add_to_residual!(ctx, :Rq, agg.bus, t, q_active - agg.Pdc[t]*tanφ)
    end
    add_to_objective!(ctx, sum(device_utility(d, ctx) for d in agg.devices))   # Σ U (3.21)
end
```
*(The exact device→aggregator handshake — `device_terms`/`device_utility` vs devices self-injecting — is Q1; the planner picks one. Whichever is chosen, keep utility a `QuadExpr` and keep `:Rp`/`:Rq` strictly affine.)*

### Pattern 3: PV+battery with NO binaries (App. C — the headline correctness risk)
**What:** Continuous `p_ch[t] ≥ 0`, `p_dch[t] ≥ 0`, `soc[t]`; SOC dynamics (3.6); charge limited by PV (3.7); discharge bound (3.8); SOC band (3.9). A concave charge utility (3.15) and a convex discharge cost (3.16) — **no complementarity constraint, no binary**.
**Why `p_ch·p_dch ≈ 0` at the optimum (convexity/cost-structure argument):**
- Charge utility marginal value starts at `a_ch = λ_med` and **decreases** (`b_ch > 0`): `∂U_ch/∂p_ch = a_ch − b_ch·p_ch ≤ λ_med`.
- Discharge cost marginal value starts at `a_dch = λ_med` and **increases** (`b_dch > 0`): `∂C_dch/∂p_dch = a_dch + b_dch·p_dch ≥ λ_med`.
- Therefore for any positive round-trip (charge δ, discharge δ), the marginal *benefit* of charging (≤ λ_med) never exceeds the marginal *cost* of discharging (≥ λ_med). Simultaneous charge+discharge yields net non-positive preference gain while, with round-trip efficiency `η² < 1` (3.6 uses `η·p_ch` in, `p_dch/η` out), it also *wastes* stored energy. So any feasible point with `p_ch[t] > 0 ∧ p_dch[t] > 0` is strictly dominated by one that nets them out → the unique optimum has `p_ch[t]·p_dch[t] = 0`. Thesis App. C (pp. 166–168) gives the KKT proof; `λ_min ≤ λ_med ≤ λ_max` is the sufficient condition.
**How to verify numerically (mandatory post-solve):** after `assert_solved!`, for each battery and each `t` compute `value(p_ch[t]) * value(p_dch[t])` and assert `< τ` (e.g. `τ = 1e-6` in per-unit²), failing loudly otherwise. This is the "looks-done-but-isn't" checklist item for batteries.
```julia
# Source: THEORY-thesis.md eqs. 3.6–3.9, 3.15–3.20; App. C pp. 166–168
function contribute!(d::PVBattery, ctx::ModelContext; T::Int)
    m = ctx.model
    p_ch  = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pmax)     # (3.8 lower/limit)
    p_dch = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pmax)     # (3.8)
    soc   = @variable(m, [t = 1:T], lower_bound = d.Emin, upper_bound = d.Emax)  # (3.9)
    @constraint(m, soc[1] == d.soc0)
    @constraint(m, [t = 1:T-1],                                                  # SOC dynamics (3.6)
        soc[t+1] == soc[t] + (d.η*p_ch[t] - p_dch[t]/d.η)*d.Δt)
    @constraint(m, [t = 1:T], p_ch[t] <= d.Ppv[t])                               # charge limited by PV (3.7)
    # NO binary, NO p_ch*p_dch=0 constraint — App. C guarantees it.
    a_ch  = d.λ_med;  b_ch  = (d.λ_med - d.λ_min)/d.Pmax                          # (3.17–3.18)
    a_dch = d.λ_med;  b_dch = (d.λ_max - d.λ_med)/d.Pmax                          # (3.19–3.20)
    # + concave charge utility, − convex discharge cost → concave contribution:
    add_to_objective!(ctx, sum(a_ch*p_ch[t] - (b_ch/2)*p_ch[t]^2
                             - a_dch*p_dch[t] - (b_dch/2)*p_dch[t]^2 for t in 1:T))
    return (; p_ch, p_dch, soc)   # active injection: −p_ch (load) + p_dch (gen) + P_pv (gen), via aggregator
end
```

### Pattern 4: Seeded first-order Markov profile generator (DATA-04, data layer, NO JuMP)
**What:** A pure function that, given a transition matrix, an initial state, a state→value map, a horizon, and an **explicit `AbstractRNG`**, produces a reproducible profile. Same seed → identical profile (INFRA-04 bit-for-bit).
```julia
# Source: THEORY-thesis.md §2.8 (first-order Markov, data-gen only); RNG per docs.julialang.org/en/v1/stdlib/Random
using StableRNGs   # cross-version-stable stream (stdlib Random is NOT stable across Julia versions)

"""first-order Markov walk; `P[s, :]` are row-stochastic transition probs; returns state path."""
function markov_path(P::AbstractMatrix, s0::Int, steps::Int, rng::Random.AbstractRNG)
    length(size(P)) == 2 && size(P,1) == size(P,2) || throw(ArgumentError("P must be square"))
    path = Vector{Int}(undef, steps); s = s0
    @inbounds for k in 1:steps
        path[k] = s
        u = rand(rng); c = 0.0; nxt = s                  # categorical draw over row P[s, :]
        for j in axes(P, 2); c += P[s, j]; if u <= c; nxt = j; break; end; end
        s = nxt
    end
    return path
end

# Caller seeds ONCE, threads the rng explicitly (no global RNG state — Anti-Pattern 6):
rng = StableRNGs.LehmerRNG(seed)                         # e.g. seed from Scenario
demand_states = markov_path(P_demand, s0, 24, rng)       # then map states → hourly kW
```
Aggregate 1-min or sub-hourly walks to the hourly optimization resolution (thesis §2.8) before they enter the solve as parameters.

### Anti-Patterns to Avoid
- **Adding a binary or `p_ch*p_dch == 0` to the battery.** Breaks convexity, breaks the QP, breaks future ADMM pricing. App. C makes it unnecessary. Explicitly out of scope (REQUIREMENTS "Out of Scope"). Rely on the parametrization + numerical check.
- **Routing utility through `add_to_residual!`.** `:Rp`/`:Rq` are pinned to `AffExpr`; a `QuadExpr` fails loudly via `convert(AffExpr, ·)` — utility MUST go to `add_to_objective!` (curvature retained). The existing context already enforces this.
- **Closing `:Rq` without a reactive frontier source.** The WR-03 note in `linear_solve.jl` warns: with reactive load present (Phase 3), pinning `:Rq` at every bus is infeasible or silently zeroes reactive draw *unless* a free-sign `q_import[t]` is injected at `feeder.root` first.
- **Global RNG / `Random.seed!` for profiles.** Non-reproducible across Julia versions; violates INFRA-04. Thread an explicit `StableRNGs` instance.
- **Devices holding the network object.** Devices hold only `bus::Int` + parameter vectors; never a `Feeder`. Enforced by grep + the "no feeder" device test.
- **Hard-coding a solver.** Use `select_optimizer(QP())`; never name Clarabel/HiGHS in a model file (INFRA-02).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cross-version-reproducible RNG stream | A custom LCG/PRNG | `StableRNGs.LehmerRNG` | Battle-tested, stream-stable by contract; a hand LCG risks bias and is unverifiable against the thesis |
| Solve-status / feasibility gating | Manual `termination_status == OPTIMAL` checks | `assert_solved!` (existing) | Already delegates to `is_solved_and_feasible` (checks primal+dual); single choke point |
| Quadratic-objective solve | Manual epigraph/SOC reformulation of the QP | Clarabel via `QP()` | Clarabel handles quadratic objectives natively with accurate duals |
| Per-bus/time residual accumulation | A fresh matrix per device | `add_to_residual!(ctx,:Rp,i,t,·)` (existing) | Lazily grows, guards scalar/matrix mismatch, pins to `AffExpr` |
| Radial-topology / magnitude validation | Re-checking in the model | `Feeder` constructor (existing) | Validation is a construction invariant already |

**Key insight:** Almost everything this phase needs already exists as a Phase-1/2 seam. The only genuinely new *infrastructure* is the Markov generator (which is data-layer, not optimization) and it should lean on `StableRNGs` rather than any bespoke randomness.

## Runtime State Inventory

> This phase is greenfield device additions plus a **refactor** of two existing files (`linear_solve.jl` → `welfare_solve.jl`; possibly `Interruptible.jl` for the aggregator handshake). There is no external stored state, live service, or OS registration involved — it is an in-repo Julia library. The categories below are answered for the refactor surface.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — no database/datastore in this project. | None |
| Live service config | None — no external services. | None |
| OS-registered state | None. | None |
| Secrets/env vars | None. | None |
| Build artifacts / installed packages | `Project.toml`/`Manifest.toml` gain `StableRNGs`; no stale egg-info/compiled artifacts (Julia recompiles). Existing `TSODSO` module include graph must gain the new files. | Add dep via `Pkg.add`; wire new includes into `src/TSODSO.jl`; commit updated `Manifest.toml` |
| Code refactor targets (in-repo) | `src/models/linear_solve.jl` (generalize to multi-aggregator, add `q_import`, T=24); `src/core/ModelContext.jl` WR-03 note (reactive frontier); possibly `src/devices/Interruptible.jl` (align to aggregator handshake) | Prefer adding `welfare_solve.jl` alongside `linear_solve.jl` (keep the rung-1 solve as a passing regression) rather than editing in place |

**Nothing found in stored-data / live-service / OS / secrets categories — verified: this is a self-contained Julia research package with no runtime state outside the git repo.**

## Common Pitfalls

### Pitfall 1: Battery simultaneous charge/discharge slips through unchecked
**What goes wrong:** The no-binary parametrization is correct *at the optimum*, but a bug (wrong sign on `b_dch`, `λ_med` outside `[λ_min, λ_max]`, or a loose solver tolerance) can let `p_ch[t]` and `p_dch[t]` both be positive, silently producing a physically-impossible schedule and wrong welfare.
**Why it happens:** No constraint forbids it; correctness relies entirely on the cost structure holding.
**How to avoid:** (1) Guard `λ_min ≤ λ_med ≤ λ_max` and `b_ch, b_dch > 0` in the `PVBattery` inner constructor (throw). (2) Mandatory post-solve assertion `value(p_ch[t])*value(p_dch[t]) < τ` per battery per hour. (3) Keep Clarabel's tight `QP()` tolerances.
**Warning signs:** Non-trivial `p_ch·p_dch` product; welfare higher than a battery-free baseline by an implausible margin; SOC path that "teleports" energy.

### Pitfall 2: Reactive balance forces Q≡0 (the WR-03 trap)
**What goes wrong:** `LinDistFlow` writes `:Rq`; the current assembly pins `:Rq[j,t]==0` at every bus with no reactive frontier source, so introducing any reactive load (eq. 3.23) makes the model **infeasible** — or, if a modeler "relaxes" it, silently zeroes the reactive draw.
**Why it happens:** Phase 2 deliberately had no reactive load, so `Q ≡ 0` was correct and cheap; the note in `linear_solve.jl` flags exactly this.
**How to avoid:** Before closing `:Rq`, inject a **free-sign** `q_import[t]` (no `>= 0`) at `feeder.root` and stash under `ctx.meta[:q_import]`, mirroring `p_import`. The MEM/substation supplies reactive power at the frontier.
**Warning signs:** `INFEASIBLE` when a nonzero-`φ` aggregator is added; reactive draws all reading zero.

### Pitfall 3: Unit / per-unit inconsistency across device (kW) → aggregator (MW) → price (¢/kWh vs $/MWh)
**What goes wrong:** Thesis mixes ¢$/kWh (`λ_max/min/med`), kW (`P_max_b = 5`), and MW/MVA (feeder aggregates); a mismatch makes the quadratic coefficients `a`, `b` (3.13–3.20) wrong after aggregation, so one objective term dwarfs the rest and the optimizer ignores it.
**Why it happens:** Coefficients `b = (λ_max−λ_min)/(P_max−P_min)` carry price/power units; if `P` is kW at device level but MW at aggregator level, `b` is off by 1000×.
**How to avoid:** Convert all inputs to the single per-unit system at ingestion (Phase-1 `PerUnit` seam); derive utility coefficients in those consistent units; add magnitude assertions (prices within 0.1×–10× wholesale; voltages `v ∈ [0.81, 1.21]`). Document the units of every device coefficient in its docstring (as `Interruptible` does).
**Warning signs:** Welfare off by a clean 10/100/1000×; utilities ignored relative to `λ₀ᵀp_import`.

### Pitfall 4: Temporal-coupling infeasibility read as a solution
**What goes wrong:** A thermostatic recursion that can't stay in the comfort band, a deferrable window `E_min` that exceeds `Σ P_max`, or an infeasible initial SOC makes the true model infeasible; without status gating the code reads stale `value(...)`.
**How to avoid:** `assert_solved!` after every solve (already the standard). Per-device feasibility unit tests on tight-band / tight-window / extreme-SOC edge cases. Never add a hidden slack.
**Warning signs:** Results that don't move when an input changes; objective suspiciously round.

### Pitfall 5: Non-reproducible profiles
**What goes wrong:** A profile generated on Julia 1.10 differs from the same seed on 1.11 (stdlib `Random` stream drift), so a thesis figure can't be regenerated.
**How to avoid:** `StableRNGs` + explicit rng argument threaded through; a test asserting two calls with the same seed produce `==` profiles; commit `Manifest.toml`; log the seed with results.
**Warning signs:** CI on 1.10 vs 1.11 producing different profile values.

## Code Examples

See Patterns 1–4 above for the four verified, thesis-traced code templates (thermostatic device, aggregator roll-up, no-binary PV+battery, seeded Markov generator). The `Interruptible` device (`src/devices/Interruptible.jl`) is the canonical concrete-device reference to replicate for constructor guards, sign convention, and the utility→`QuadExpr` routing.

## State of the Art

| Old Approach | Current Approach | Impact |
|--------------|------------------|--------|
| Original thesis: MATLAB + CVX (DCP auto-transform) | JuMP + Clarabel, explicit constraints | Direct per-constraint control, native quadratic objective, accurate duals |
| BESS with charge/discharge binaries (common in MILP dispatch) | No-binary parametrization (App. C) | Keeps the model a convex QP; preserves duals for Phase-5 pricing |
| stdlib `Random` with `seed!` for "reproducible" experiments | `StableRNGs` explicit rng | Cross-version bit-for-bit reproducibility (INFRA-04) |

**Deprecated/outdated for this phase:**
- SOCP cone / LinDistFlow exactness copy: **not yet** — this rung runs on the linear `LinDistFlow` only; the cone and exactness check are Phase 4 (PF-03/PF-04). Do not pull them in early.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Recommended horizon is **T=24** (hourly, Δt=1h), matching the thesis day-ahead horizon; profile length = 24 | Summary / §Assembly | Low — thesis-specified; any T>1 exercises temporal coupling. If a smaller smoke horizon is wanted, T≥2 suffices for coupling. |
| A2 | Aggregator-as-writer is preferred over device self-injection | §Open Questions Q1 | Medium — a real design fork; the alternative also satisfies the requirements with different ergonomics. Planner decides. |
| A3 | Reactive power is `P·tan(arccos φ)` for flexible/inelastic loads only; batteries/PV are active-only | Pattern 2 | Medium — traced to 3.23; if a future 4-quadrant BESS is wanted that changes (v2 MESH-02, out of scope here). |
| A4 | Inelastic demand `P_dc` and PV `P_pv` enter as **parameters** (not decisions), from the Markov generator | §Aggregator, §Profiles | Low — thesis §2.3/§2.8 explicit ("inelastic loads are parameters"; Markov is data-gen). |
| A5 | The utility constant `c` (3.11/3.12) may be dropped from the argmax (affects only absolute welfare, not the optimizer) | Pattern 1 | Low — include `c` only if matching absolute thesis welfare numbers; document the choice. |
| A6 | `PVBattery` charging draws only from PV (`p_ch ≤ P_pv`), not from grid | Pattern 3 | Low — traced to 3.7. If grid-charging is later wanted it is a model variant. |

## Open Questions

1. **Aggregator vs device residual-writing (the one real design fork).**
   - What we know: DEV-05 says "the aggregator, not the device, is what the network sees"; thesis 3.21–3.23 are aggregator-level. The existing `Interruptible` self-injects `−p` into `:Rp` and holds `bus::Int`.
   - What's unclear: whether Phase 3 refactors devices to *return* `(active, reactive, utility)` terms consumed by the `Aggregator` (aggregator is sole `:Rp`/`:Rq` writer), or keeps devices self-injecting active while the aggregator only adds reactive + groups utility.
   - Recommendation: **Aggregator-as-writer.** It is the faithful reading of DEV-05 and 3.21–3.23, makes devices fully network-agnostic (they need not even hold a bus — the aggregator supplies it), and the migration cost is one device (`Interruptible`) this early. Keep `linear_solve.jl` as-is (regression) and build `welfare_solve.jl` + the new contract alongside. If the planner prefers minimal churn, the self-injection alternative is acceptable but weaker on the DEV-05 criterion — flag it in CONTEXT for confirmation.

2. **Does closing `:Rp`/`:Rq` at *every* bus (as `linear_solve.jl` does) scale to the multi-aggregator case, or should only load buses carry injections?**
   - What we know: LinDistFlow writes branch terms at all buses; aggregators sit at load nodes; the root carries the frontier import.
   - What's unclear: whether non-aggregator interior buses need any injection (they don't — their residual is pure branch inflow−outflow = 0, which is correct).
   - Recommendation: keep the pin-every-bus closure (it correctly forces branch continuity at passive buses); only aggregator buses + root add injections. This matches the existing data-driven closure loop.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | ✓ (project targets 1.10 LTS + 1.11) | 1.10/1.11 | — |
| JuMP | all model code | ✓ (Project.toml) | 1.30.1 | — |
| Clarabel | `QP()` welfare solve | ✓ (Project.toml) | 0.11.1 | Ipopt via `NLP()` as cross-check only |
| HiGHS, Ipopt | present, not core to this phase | ✓ | 1.24.1 / 1.15.0 | — |
| `StableRNGs` | DATA-04 profile reproducibility | ✗ (NOT yet in Project.toml) | 1.0.4 (target) | stdlib `Random` — **rejected** (not cross-version stable); no acceptable fallback for the reproducibility requirement |

**Missing dependencies with no fallback:** `StableRNGs` must be added (`Pkg.add("StableRNGs")`) — the reproducibility requirement (INFRA-04) has no stdlib-only path.
**Missing dependencies with fallback:** none.

## Validation Architecture

> nyquist_validation is enabled (config.json `workflow.nyquist_validation: true`).

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `Test` (stdlib) + `TestItems` / `TestItemRunner` — `@testitem` blocks; runner filters by substring in the item name |
| Config file | `test/runtests.jl` (existing) |
| Quick run command | `julia --project -e 'using TestItemRunner; @run_package_tests filter=ti->occursin("device", ti.name)'` |
| Full suite command | `julia --project -e 'using Pkg; Pkg.test()'` |

*Verify the exact filter idiom against the existing `test/runtests.jl`; the established convention is that each `@testitem` name contains the seam substring (e.g. `"device:"`, and new ones like `"battery:"`, `"aggregator:"`, `"welfare:"`, `"profiles:"`).*

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DEV-01 | Thermostatic: recursion 3.2 holds; comfort band binds; utility concave; NO feeder needed | unit | `Pkg.test()` (filter `"thermostatic"`) | ❌ Wave 0 |
| DEV-02 | Deferrable: energy-window budget 3.4; utility concave | unit | filter `"deferrable"` | ❌ Wave 0 |
| DEV-04 | PV+battery: SOC dynamics 3.6; PV-limited charge 3.7; **`p_ch·p_dch < τ` at optimum** | unit + solve | filter `"battery"` | ❌ Wave 0 |
| DEV-05 | Aggregator sums to `p_ag`/`q_ag`/`U_ag` (3.21–3.23); devices never touch feeder | unit | filter `"aggregator"` | ❌ Wave 0 |
| OPT-01 | End-to-end multi-device GLB-CVX solves to a global optimum; welfare = Σ U_ag − λ₀ᵀp_import | integration | filter `"welfare"` | ❌ Wave 0 |
| DATA-04 | Same seed → identical profiles (bit-for-bit); first-order Markov row-stochastic guard | unit | filter `"profiles"` | ❌ Wave 0 |
| — | Cross-solver sanity: Clarabel vs Ipopt objective agree on a small fixture (Pitfall 4) | integration | filter `"welfare"` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the relevant device/aggregator/profile `@testitem` filter.
- **Per wave merge:** full `Pkg.test()`.
- **Phase gate:** full suite green (including the battery complementarity assertion and the same-seed reproducibility test) before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/test_thermostatic.jl` — covers DEV-01
- [ ] `test/test_deferrable.jl` — covers DEV-02
- [ ] `test/test_pvbattery.jl` — covers DEV-04 (incl. `p_ch·p_dch < τ`)
- [ ] `test/test_aggregator.jl` — covers DEV-05
- [ ] `test/test_profiles.jl` — covers DATA-04 (same-seed determinism)
- [ ] `test/test_welfare_solve.jl` — covers OPT-01 + cross-solver sanity
- [ ] Dependency: `Pkg.add("StableRNGs")` + `[compat]` entry (needed before `profiles.jl`)

## Security Domain

> `security_enforcement` is not set in config (treated as enabled). This is a research optimization library — the standard web-app ASVS categories map to research-integrity / reproducibility, per the project's own PITFALLS.md framing.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No users/auth — a solver library |
| V3 Session Management | no | N/A |
| V4 Access Control | no | N/A |
| V5 Input Validation | yes | Throw-based constructor guards (concavity `b>0`, `λ_min≤λ_med≤λ_max`, band/window consistency); `Feeder`/`PerUnit` magnitude tripwires; `λ₀` length check in assembly |
| V6 Cryptography | no | N/A (RNG here is for reproducible *simulation*, not security — `StableRNGs` chosen for stability, not entropy) |

### Known Threat Patterns for this stack (research-integrity framing)

| Pattern | STRIDE-analog | Standard Mitigation |
|---------|---------------|---------------------|
| Silent wrong result (inexact/infeasible read as OPTIMAL) | Information disclosure (bad data) | `assert_solved!` gate; no hidden slacks |
| Battery physical impossibility (`p_ch·p_dch>0`) | Tampering (invalid state) | Post-solve numerical assertion + constructor guard |
| Non-reproducible experiment | Repudiation (can't reproduce a figure) | `StableRNGs` + committed `Manifest.toml` + logged seed |
| Unit/scale corruption | Tampering | Single per-unit system + magnitude assertions |

## Sources

### Primary (HIGH confidence)
- `.planning/research/THEORY-thesis.md` — device eqs. 3.2–3.9, utilities 3.10–3.20, aggregation 3.21–3.23, GLB-CVX 3.38, App. C no-binary battery proof (pp. 166–168), Markov §2.8. Primary source extraction.
- `.planning/research/THEORY-papers.md` — IET 2019 corroboration; KKT no-binary proof reference.
- `.planning/research/ARCHITECTURE.md` — residual-registry seam, device/aggregator/objective responsibilities, build order (rung 2).
- `.planning/research/PITFALLS.md` — units, infeasibility masking, no-binary verification, reproducibility, solver discipline.
- Existing source (read this session): `src/devices/AbstractDevice.jl`, `src/devices/Interruptible.jl`, `src/core/ModelContext.jl`, `src/models/linear_solve.jl` (incl. the WR-03 reactive-frontier note), `src/powerflow/LinDistFlow.jl`, `src/solver/factory.jl`, `src/solver/ProblemClass.jl`, `src/data/Feeder.jl`, `src/units/PerUnit.jl`, `src/core/status.jl`, `src/TSODSO.jl`, `test/test_device.jl`.
- `Project.toml` — current pinned deps and compat.

### Secondary (MEDIUM–HIGH confidence)
- [docs.julialang.org/en/v1/stdlib/Random] — official warning that the RNG stream is an implementation detail and **may change across Julia minor versions**; advises `StableRNGs` / saving data for exact cross-version reproducibility. Verified 2026-07-18.
- `JuliaRegistries/General` `Versions.toml` for `StableRNGs` (raw.githubusercontent.com) — latest **1.0.4**. Verified 2026-07-18.

## Metadata

**Confidence breakdown:**
- Device math + no-binary battery: HIGH — traced equation-by-equation to the thesis and App. C.
- Existing seam signatures: HIGH — read directly from source this session.
- Aggregator residual-writing design: MEDIUM — a genuine design fork (Q1); recommendation given, planner confirms.
- RNG / reproducibility: HIGH — official Julia docs + authoritative registry.
- Horizon / units specifics: MEDIUM-HIGH — thesis-specified, restated as recommendations.

**Research date:** 2026-07-18
**Valid until:** ~2026-08-18 (stable domain; theory fixed, deps pinned. Re-verify `StableRNGs` version only if the Manifest is regenerated.)

Sources:
- [Julia Random stdlib — reproducibility](https://docs.julialang.org/en/v1/stdlib/Random/)
- [JuliaRegistries/General — StableRNGs Versions.toml](https://raw.githubusercontent.com/JuliaRegistries/General/master/S/StableRNGs/Versions.toml)
</content>
</invoke>

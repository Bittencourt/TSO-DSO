# Phase 31: GNE Nash Fixture, Integer N>1 & Planning Docs Refresh - Research

**Researched:** 2026-10-01
**Domain:** Generalized Nash Equilibrium (GNE) theory for a shared-constraint game, integer
(binary-expansion) Benders master extended to N players, Typst/Documenter doc refresh
**Confidence:** HIGH (GNE/VE structure, integer wiring, WR-01/02/03 fixes — all verified by direct
code reading and live Julia probes this session) / MEDIUM (exact numeric tolerances the planner
will still need to measure on the final fixture; doc-refresh content is HIGH, scope is clear)

## Summary

This phase has three independent deliverables sharing one codebase: (1) BILEV-06 — build an
interior-cap variant of the existing 2-distributor Nash toy fixture that exposes a genuine
**continuum** of generalized Nash equilibria (GNE), and a standalone `solve_variational_equilibrium`
that selects the VE (common shared multiplier) inside that continuum; (2) BILEV-07 — thread
`build_master_integer` through `run_nash!`'s per-best-response `solve_stackelberg!` call so integer
investment runs at N>1, and fix the three open Laporte-Louveaux (LL) integer-recourse warnings
Phase 30's code review left open (WR-01/WR-02/WR-03, see `30-REVIEW.md`); (3) BILEV-08 — refresh two
Portuguese Typst writeups and three docstrings to state the game-theoretic taxonomy of every planning
variant, including the integer master, which the current docs do not mention at all.

The most important, non-obvious finding of this research (empirically verified by direct Julia
probes, not assumed): **`run_nash_probe`'s existing multi-seed mechanism varies `z0` only, and
cannot expose GNE multiplicity in this game, no matter how many seeds or orders are tried.** The
shared-transmission game's investment-cost structure makes every distributor's default-seeded,
Gauss-Seidel-driven best-response converge to the *unique* "invest exactly your own marginal need"
split, regardless of the initial `z0` or sweep order — this was directly measured across 8 seed/
order combinations, all landing on the bit-identical point `x_inv=[0.3499,0.3499]`. The continuum
is real and *is* reachable, but only by seeding the OPTIONAL `x_inv0` keyword `run_nash!` already
has (not `run_nash_probe`'s `seeds` NamedTuple, which only feeds `z0`) at different points spanning
the analytically-derived interval. The planner must treat "reuse `run_nash_probe`" as requiring a
small, concrete extension (vary `x_inv0` per seed, not only `z0`), not a literal no-code reuse.

**Primary recommendation:** build the BILEV-06a fixture on the existing toy (`corridor_cap=2.0`,
symmetric `c_inv=c_op`), with `x_inv_max=[1.0,1.0]` (safely non-binding above the analytically
derived total investment need `S=0.7`); derive the GNE interval as `x_inv_1 ∈ [0, 0.7]`,
`x_inv_2 = 0.7 - x_inv_1`, `z_1=z_2≈0.7` (constant) at every point; probe by extending the seed
dimension to vary `x_inv0`, not `z0`; implement `solve_variational_equilibrium` as a single
monolithic joint JuMP model (mirroring Phase 30's own `solve_joint_reference` pattern, generalized
to N players sharing one `capacity[t]` row) since the game is separable in each player's own
`(x_inv_i, z_i)` except through that one shared row — this is a textbook Rosen/VE setting, not a
case requiring the multiplier-equalization fallback. For BILEV-07, extend `run_nash!` with a new
per-distributor `integer` kwarg that builds a fresh `build_master_integer` per best response
(reusing `derive_alpha_op_lb` for `α_op_lb`, and an explicit, honestly-unvalidated `α_x_lb` for the
`DistributorView` follower, mirroring the continuous path's own accepted skip) and add cycle
detection over the *exact* binary state `b` (not a residual tolerance). Fix WR-01/02/03 using the
code reviewer's own already-vetted patches (quoted verbatim below).

## Architectural Responsibility Map

This project is a single-process Julia research library (no client/server split), so the usual
browser/API/DB tiers do not apply. The relevant "tiers" are within `src/planning/`:

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Shared pooled-capacity LP (`capacity[t]`, per-distributor rows) | `coupling.jl` (model layer) | — | The one genuinely shared JuMP model; owns the single multiplier the VE selects |
| Per-distributor best response (Stackelberg-Benders) | `benders.jl` (solve layer) | `master.jl`/`subproblem.jl`/`follower.jl` | Each player's own full decomposition; reused unmodified as the GNE "player problem" |
| Outer Gauss-Seidel diagonalization | `nash.jl` (orchestration layer) | — | Builds no JuMP model itself; pure orchestration over `solve_stackelberg!` + `coupling.jl` |
| Variational-equilibrium selection | NEW: `nash.jl` or a new `variational.jl` (orchestration + model layer) | `coupling.jl` (reuses its parameter shapes) | A monolithic joint model is a distinct JuMP build, not a loop — belongs beside `coupling.jl`'s own builder, or as a sibling file `nash.jl` already owns the Nash-family exports |
| Integer master per best response | `master_integer.jl` (model layer) | `nash.jl` (wiring) | `build_master_integer` is the model; `run_nash!` is the only caller that needs a NEW per-spec wiring path |
| Docs (Typst writeups, Documenter docstrings) | `docs/writeups/*.typ`, module docstrings | — | Pure documentation tier, no runtime code |

## User Constraints (from CONTEXT.md)

<user_constraints>
### Locked Decisions

#### GNE fixture with interior caps (BILEV-06a)
- Fixture: a variant of the existing 2-distributor toy (`test/test_planning_nash.jl`, T=1,
  corridor_cap=2.0, c_inv, c_op) with caps chosen so the POOLED corridor capacity constraint binds
  while no individual `x_inv_max[i]` binds — opening a 1-D continuum in how the shared capacity is
  split.
- Ground truth: the equilibrium set is derived ANALYTICALLY (an interval), documented beside the
  fixture; the test asserts the probe's observed spread lies within that interval and exceeds a
  MEASURED floor (not a picked one).
- Probing: reuse `run_nash_probe` with enough seeds/orders that distinct starting points land on
  distinct equilibria.
- The existing corner-cap fixture (`x_inv_max=[0.3,0.3]`) is KEPT as the unique-equilibrium control;
  its spread must remain 0.

#### Variational-equilibrium selection (BILEV-06b)
- New standalone `solve_variational_equilibrium(shared; ...)`; `run_nash!` unchanged.
- Method: if research confirms players' costs are separable except through the shared constraint,
  solve ONE joint model containing the shared row once (VE ⇔ equal shared-row multipliers); verify the
  multiplier equality explicitly.
- Certification: assert every player's shared-row multiplier is identical (measured tolerance) AND
  the VE lies inside the analytic GNE interval from the fixture above.
- Fallback if the game is NOT separable: multiplier-equalization inside the diagonalization loop,
  documented — not PATHSolver (no new dependency).

#### Integer investment at N>1 (BILEV-07)
- API: `run_nash!(...; integer = (; K, ...))` builds a FRESH `build_master_integer` per best response
  via `solve_stackelberg!`'s existing `master=` keyword.
- Certification: on N=2 with small K, brute-force enumerate the integer grid and assert no profitable
  unilateral deviation at the reported equilibrium.
- Phase-30 open integer-path review warnings are FIXED here (they become load-bearing):
  (WR-01) `ALMOST_INFEASIBLE` in the integer corner search must be classified/confirmed, not mapped
  to +Inf blindly; (WR-02) validate the integer master's `L = α_op_lb + α_x_lb` and enforce the
  Laporte–Louveaux cut validity condition `Q_ν ≥ L` (and correct `add_ll_cut!`'s docstring math);
  see `.planning/phases/30-*/30-REVIEW.md` and `30-FINDINGS.md`.
- Cycling: an integer diagonalization that cycles is detected and reported loudly (with the cycle),
  never claimed converged.

#### Planning docs refresh (BILEV-08)
- Scope: full refresh of `docs/writeups/stackelberg_vs_psr_n1n2.typ`, the variant taxonomy in
  `docs/writeups/modelo_stackelberg_dso_unico.typ`, and the Documenter API docstrings of the three
  entry points (`solve_stackelberg!`, `solve_bilevel!`, `run_nash!` / `solve_variational_equilibrium`).
- Content: a taxonomy table — integrated-decomposed-by-Benders (`solve_stackelberg!`), genuine bilevel
  (`solve_bilevel!`), shared-constraint GNE/VE (`run_nash!` / `solve_variational_equilibrium`) — every
  claim citing the backing function and test, including the integer master and the Phase-30
  SOCP/inexactness policy.
- Language: keep each writeup in its current language (Portuguese).
- Build: compile PDFs with `typst compile` and commit them alongside the sources (as today).

### Claude's Discretion
- Exact fixture numbers (must produce the stated binding pattern; derivation documented), tolerance
  values (measured), naming of new result fields.

### Deferred Ideas (OUT OF SCOPE)
None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BILEV-06 | Nash fixture with interior caps exposes GNE continuum; VE selection available/documented | See "GNE Structure" and "Code Examples" below — fixture numbers derived and empirically confirmed; VE design is a monolithic joint model mirroring Phase 30's `solve_joint_reference` |
| BILEV-07 | Integer investment runs in N>1 Nash diagonalization, each best response using the integer master | See "Integer N>1 Wiring" — exact `run_nash!` extension point identified, bounds-derivation gap identified, cycle-detection design given |
| BILEV-08 | Docs state game-theoretic nature of each planning variant, incl. integer master, refreshed to current code | See "Docs Refresh Scope" — exact stale passages identified line-by-line in both `.typ` files |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Solvers:** open-source first (HiGHS LP/MILP, Ipopt NLP, Clarabel/SCS conic). No new solver
  dependency is needed for this phase — `solve_variational_equilibrium`'s joint model reuses the
  SAME `select_optimizer(LP())`/`select_optimizer(SOCP())` factory every other builder in
  `src/planning/` already uses.
- **No PATHSolver/Complementarity.jl** unless a future variant is recast as a genuine MCP — CONTEXT.md
  explicitly reiterates this: the VE fallback (if ever needed) is "multiplier-equalization inside the
  diagonalization loop," never a new dependency.
- **Hand-roll Benders/Nash decomposition** — `solve_variational_equilibrium` must NOT be built on a
  decomposition framework; it is a single, directly-solved monolithic model (actually *simpler* than
  the Benders loop it replaces for VE purposes).
- **Documentation is a hard requirement** — Typst writeups + Documenter docstrings, not optional
  (BILEV-08 is exactly this).
- **Correctness over performance** — the ~4s/best-response integer MILP cost (measured this session,
  see "Integer N>1 Wiring") is acceptable; do not attempt to speed it up as part of this phase.
- **GSD workflow enforcement** (user's global CLAUDE.md): all file-changing work must go through a
  GSD command; this research phase itself only reads code and runs scratch probes, consistent with
  that constraint.

## Standard Stack

### Core

No new packages. Every tool this phase needs is already a direct dependency:

| Library | Version (installed, confirmed this session) | Purpose | Why Standard |
|---------|---------|---------|--------------|
| JuMP | (project-pinned, see root `Project.toml`) | `solve_variational_equilibrium`'s joint model | Same modeling layer as every other planning builder |
| HiGHS | 1.24.x (confirmed loadable) | LP (shared-transmission corridor) and MILP (integer master) | Unchanged from Phase 24/30 |
| Clarabel | 0.11.x (confirmed loadable) | SOCP operational oracle, reused unmodified per player | Unchanged |
| Ipopt | 1.15.x (confirmed loadable) | AC re-check path, untouched by this phase | Unchanged |
| Typst | 0.15.1 (confirmed at `~/.local/bin/typst`) | Compile the two refreshed `.typ` writeups to PDF | Project's existing doc toolchain |
| Documenter.jl / Literate.jl | project-pinned | Docstring refresh, no new literate page required (existing `docs/literate/nash_diagonalization.jl` and `integer_investment.jl` may need small updates but no new file is mandated) | Unchanged |

**Installation:** none required — `julia --project=. -e 'using TSODSO'` and
`~/.local/bin/typst --version` were both confirmed working this session.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Monolithic joint model for VE | Multiplier-equalization inside `run_nash!`'s own diagonalization loop | CONTEXT.md's explicit fallback, only needed if the game turns out non-separable — research below shows it IS separable, so the fallback should not be built unless the planner finds a different fixture where it's needed |
| Thread `feas_oracle` into the integer corner search (WR-01 fix) | Build a second, integer-specific feasibility oracle | Reuse is strictly simpler and mirrors the outer loop's own established pattern — no reason to diverge |

## Package Legitimacy Audit

Not applicable — this phase installs zero new external packages. All tooling (JuMP, HiGHS,
Clarabel, Ipopt, Typst, Documenter, Literate) is already a pinned, in-use dependency, confirmed
loadable this session. `slopcheck` was not run because there is nothing new to check.

## GNE Structure of the Shared-Transmission Game (BILEV-06)

### The players' problems, precisely

Each distributor `i`'s best response (invoked by `run_nash!` as a full `solve_stackelberg!` call
with `follower = DistributorView(shared, i)`, `src/planning/nash.jl:508-522`) solves:

```
minimize_{y_inv_i, x_inv_i, z_i, x_op_i}
    c_y * y_inv_i + α_op_i(z_i) + c_inv[i]*x_inv_i + Σ_t c_op[i][t]*x_op_i[t]
subject to
    0 <= z_i[t] <= y_inv_i[t]                       (master box, master.jl)
    x_op_i[t] == z_i[t]                              (coupling[i,t], coupling.jl)
    Σ_j x_op_j[t] <= corridor_cap * Σ_j x_inv_j      (capacity[t], shared ONCE — coupling.jl)
    0 <= x_inv_i <= x_inv_max[i]
    [x_inv_j, x_op_j fixed/bound-pinned for all j != i, via write_back!]
```

where `α_op_i(z_i)` is the full operational-welfare SOCP oracle for distributor `i`'s OWN feeder/
aggregators (`subproblem.jl`, independent across `i` — different feeders, no cross term). **The only
place any player's variables appear in any OTHER player's constraint is the shared `capacity[t]`
row.** Objectives are strictly additively separable (`Σ_i [own terms]`, no cross-player terms
anywhere) — confirmed by direct code reading of `coupling.jl`'s `build_shared_transmission` (the
objective is `Σᵢ c_inv[i]*x_inv[i] + Σᵢ Σₜ c_op[i][t]*x_op[i,t]`, verbatim) and
`subproblem.jl`/`master.jl` (each distributor's own oracle/master touch only that distributor's own
variables).

**This is the textbook Rosen (1965) shared-constraint game: individually convex player problems,
jointly convex shared constraint, separable objectives.** `[VERIFIED: direct code read,
src/planning/coupling.jl + src/planning/nash.jl]` For this class, the **variational equilibrium**
(the GNE selected by requiring every player's own multiplier on the shared row to be equal) is
*exactly* the solution of the single joint optimization problem that writes the shared constraint
ONCE instead of `N` times — this is Rosen's own normalized-equilibrium construction at uniform
player weights. CONTEXT.md's own locked decision ("if research confirms players' costs are
separable... solve ONE joint model") is therefore directly actionable: **the game IS separable, use
the joint-model method, do not build the multiplier-equalization fallback.**

### Why a continuum exists here specifically (derived + empirically confirmed)

Because `c_inv[i] > 0` strictly, each player strictly prefers to minimize its OWN `x_inv_i`. Given
the other player's `(x_inv_j, z_j)` fixed, player `i`'s cost is minimized by setting
`x_inv_i = max(0, (z_i + z_j)/corridor_cap − x_inv_j)` — the SMALLEST investment that still
satisfies the shared capacity row — and this reduces player `i`'s problem to choosing `z_i` alone, at
the SAME marginal cost `m_f = c_inv[i]/corridor_cap + c_op[i]` regardless of whether `x_inv_i` ends
up zero (fully free-riding on `j`'s slack) or positive. Consequently:

1. **The optimal `z_i*` is INDEPENDENT of how investment is split** — every player's own flow sits at
   its unconstrained marginal optimum `z_i*` as long as SOME combination of `(x_inv_1, x_inv_2)`
   supports the total `Σz_i*`.
2. **Any split `(x_inv_1, x_inv_2)` with `x_inv_1 + x_inv_2 = S_min := Σz_i*/corridor_cap` and both
   entries inside `[0, x_inv_max_i]` is a fixed point**: given `x_inv_j` fixed at its share, player
   `i`'s own best response reproduces EXACTLY `x_inv_i = S_min − x_inv_j`, i.e. the assigned share —
   by construction, every split on this line is self-consistent.
3. This produces a **genuine 1-D continuum of GNEs** in `(x_inv_1, x_inv_2)` space — all mapping to
   the SAME `(z_1*, z_2*)` — exactly the structure CONTEXT.md's decision anticipates.

### Concrete fixture numbers (derived, then empirically confirmed via live probe)

Reusing the existing toy (`Phase6Fixtures.two_bus_feeder()` + `ToyElasticDevice(2, 6.0, 1.0, 10.0)`,
`corridor_cap=2.0`, `c_inv=[1.0,1.0]`, `c_op=[[0.5],[0.5]]`, `master_kwargs=(;c_y=0.3,y_max=8.0,
α_op_lb=-5.0,α_x_lb=0.0)`): the UNCONSTRAINED per-distributor Stackelberg optimum is `z_i*=0.7`
(hand-derived in `test/test_planning_nash.jl`'s own header comment, lines 242-255, and reconfirmed
live this session). Required total investment: `S_min = (0.7+0.7)/2.0 = 0.7`.

**Recommendation: `x_inv_max = [1.0, 1.0]`** (safely above `0.7` with margin `0.3`, so neither
individual cap binds anywhere on the interval). This was run LIVE (`JULIA_LOAD_PATH` not even
needed — `julia --project=.` loads `TSODSO` directly):

```
`VERIFIED: direct julia --project=. execution, 2026-10-01, scratchpad probe_nash_interior.jl`

x_inv0_seed=[0.0,0.7]  -> converged x_inv=[0.0,      0.699895]  z=[0.7,     0.69979 ]
x_inv0_seed=[0.1,0.6]  -> converged x_inv=[0.100012, 0.599704]  z=[0.700025,0.699409]
x_inv0_seed=[0.35,0.35]-> converged x_inv=[0.349854, 0.349854]  z=[0.699708,0.699708]
x_inv0_seed=[0.5,0.2]  -> converged x_inv=[0.500153, 0.200186]  z=[0.700305,0.700372]
x_inv0_seed=[0.7,0.0]  -> converged x_inv=[0.699895, 0.0     ]  z=[0.69979, 0.7     ]
```

Every point above is a STABLE fixed point (`run_nash!` converges in 2 sweeps, `outer_residual` at or
near machine epsilon) — confirming the analytic interval `x_inv_1 ∈ [0, 0.7]` (equivalently
`x_inv_2 = 0.7 − x_inv_1`) is a genuine continuum of GNEs, with `z_1 ≈ z_2 ≈ 0.7` essentially
constant across it (small ~1e-3 deviations are the inner Benders `tol=1e-6`-scale solver noise, not
a real drift). **The analytic GNE SET to document beside the fixture:**
`{(x_inv_1, 0.7 − x_inv_1) : x_inv_1 ∈ [0, 0.7]}`, each paired with `(z_1, z_2) ≈ (0.7, 0.7)`.

The existing corner-cap control fixture (`x_inv_max=[0.3,0.3]`) was re-run and reconfirmed unique:
`z=[0.6,0.6]`, `x_inv=[0.3,0.3]` (`VERIFIED`, matches the pre-existing pinned test).

### CRITICAL FINDING: `run_nash_probe`'s `seeds` (z0-only) cannot expose this continuum

Empirically confirmed (`VERIFIED: live probe, 2026-10-01`): varying `z0` alone across 4 very
different seeds (`[0,1]`, `[0.2,0.8]`, `[0.5,0.5]`, `[0.9,0.1]`), crossed with both sweep orders (8
combinations total), **always converges to the bit-identical point** `x_inv=[0.349854,0.349854]`,
`z=[0.699708,0.699708]`. The reason: `run_nash!`'s own documented default
`x_inv0[j] = maximum(z0[j,:])/corridor_cap` ALWAYS seeds the "minimal exactly-supporting"
investment for whatever `z0` is chosen — by construction, this default seed has ZERO slack, so the
first mover in Gauss-Seidel is always effectively "alone" (the other's seeded state exactly cancels
in the capacity constraint), and always invests exactly its own marginal need, leaving nothing for
the other to free-ride on. **This means `run_nash_probe`'s current signature (`seeds::NamedTuple`
mapping to `z0` matrices only, no `x_inv0` dimension) is STRUCTURALLY INCAPABLE of exposing GNE
multiplicity in ANY symmetric shared-capacity game with this cost structure — not a fixture-tuning
problem, a probe-API gap.**

**Recommendation for the planner:** extend `run_nash_probe`'s seed mechanism to vary `x_inv0` as
well as (or instead of) `z0`. The minimal, additive change: let a `seeds` entry be EITHER a bare
`z0` matrix (current behavior, unchanged — backward compatible) OR a `(; z0, x_inv0)` NamedTuple,
dispatched by `seed_z0 isa NamedTuple` inside the existing `for (seed_name, seed_z0) in pairs(seeds)`
loop, forwarding `x_inv0 = get(seed_z0, :x_inv0, nothing)` to the inner `run_nash!` call. This is a
small, surgical change to `src/planning/nash.jl`'s `run_nash_probe` — not a rewrite — and it is the
ONLY way the BILEV-06a fixture's probe can report a nonzero `x_inv_spread` while `z_spread` stays
near zero (since `z` is constant across the continuum — see above). **Document this explicitly:
`z_spread` on this fixture should be reported as near-zero (or at least far smaller than
`x_inv_spread`) — this is a correct, expected property of this specific continuum, not a probe bug.**
Pick seed `x_inv0` values spanning (not just touching) the interval, e.g. `{0.0, 0.2, 0.5, 0.7}` —
at least 4 seeds (CONTEXT's own `≥3` floor, comfortably exceeded) crossed with both orders.

### Variational equilibrium (BILEV-06b): monolithic joint-model design

Since the game is separable (confirmed above), `solve_variational_equilibrium(shared; specs...)`
should build ONE JuMP model containing:

- `N` independent `(x_inv_i, x_op_i, oracle_i state)` blocks — essentially `N` copies of
  `coupling.jl`'s own per-distributor structure PLUS each distributor's own full operational SOCP
  oracle, assembled directly (NOT via Benders — a single monolithic solve is strictly simpler and is
  the entire point of VE: no decomposition is needed to CHARACTERIZE the VE, only to iterate toward
  a GNE when the direct joint solve is intractable at scale).
- ONE shared `capacity[t]: Σᵢ x_op[i,t] <= corridor_cap * Σᵢ x_inv[i]` row (mirrors
  `coupling.jl`'s `build_shared_transmission`, but with every `x_inv_i`/`x_op_i` FREE simultaneously,
  never bound-pinned).
- `Min Σᵢ [c_y*y_inv_i + α_op_i(z_i) + c_inv[i]*x_inv_i + Σₜ c_op[i][t]*x_op_i[t]]` where
  `α_op_i(z_i)` is inlined per distributor (reusing `subproblem.jl`'s own constraint-building
  helpers directly, the SAME pattern Phase 30's `solve_joint_reference` already used for the
  single-player BILEV-03 cross-check — see
  `test/fixtures_planning_ieee13_short.jl`'s `solve_joint_reference` for the precedent to adapt).

**Certification:** after solving ONCE, read `dual(capacity[t])` — the single VE multiplier, shared
by construction since the row is written once. To certify this is genuinely a GNE (not merely a
jointly-optimal point that happens to violate individual rationality — though the separability
argument above guarantees it is NOT), re-run each player's OWN best response
(`solve_follower!(DistributorView(shared_check, i), ...)` or a full `solve_stackelberg!`) with the
OTHER player's joint-optimal `(x_inv_j, z_j)` pinned, and confirm NO cheaper deviation exists —
this doubles as the "no profitable deviation" check and the "lies inside the analytic interval"
check CONTEXT.md requires. On the toy fixture, because `c_inv`/`c_op` are IDENTICAL across
distributors, the joint model is itself LP-degenerate in the SPLIT (any split with the right sum is
equally joint-optimal) — expect the underlying LP solver (HiGHS) to return ONE arbitrary vertex of
that degenerate face; this vertex is still a valid VE (equal multiplier by construction, since there
is only one row), it just may not be the SYMMETRIC point unless HiGHS happens to pick it. **If the
planner wants the symmetric split specifically presented as "the" VE, consider a tiny symmetry-
breaking regularization (e.g. `+ε*Σx_inv_i²`) purely for DISPLAY/determinism — but note this changes
which point in the continuum is reported, not the equilibrium theory itself; document this choice
explicitly rather than silently relying on solver tie-breaking.**

## Integer Investment at N>1 (BILEV-07)

### Exact wiring point

`run_nash!` (`src/planning/nash.jl:508-522`) currently calls `solve_stackelberg!` with
`master_kwargs = spec.master_kwargs` and NEVER passes `master=`. `solve_stackelberg!` already has
the keyword it needs (`master = nothing` default, `src/planning/benders.jl:810`, documented at
lines 876-884): supplying a pre-built `BendersMasterInteger` there works TODAY for a single
distributor (confirmed by the existing smoke test,
`test/test_planning_benders_integer.jl:84-131`). **The missing piece is purely in `nash.jl`**: add
a new `integer::Union{Nothing,NamedTuple} = nothing` kwarg to `run_nash!` (or a per-spec
`spec.integer` field — CONTEXT.md's own sketch `run_nash!(...; integer = (; K, ...))` suggests a
single shared kwarg, which is simpler if every distributor uses the same `K`/`y_max` lattice; a
per-spec field is needed only if distributors need DIFFERENT lattices). Inside the `for i in
sweep_order` loop, when `integer !== nothing`, build a FRESH
`build_master_integer(; T=shared.T, K=integer.K, c_y=spec.master_kwargs.c_y,
y_max=spec.master_kwargs.y_max, α_op_lb=..., α_x_lb=...)` and call `solve_stackelberg!(...;
master=fresh_imaster, master_kwargs=NamedTuple(), ...)` instead of forwarding `spec.master_kwargs`
directly.

### Bounds derivation gap (directly feeds the WR-03 fix)

`build_master_integer` (`src/planning/master_integer.jl:162-212`) has **no `bounds_ctx` parameter at
all** — unlike the continuous `build_master` (BILEV-05, Phase 30), which validates `α_op_lb`/
`α_x_lb` against a genuine relaxed-solve minimum whenever `bounds_ctx` is supplied. This means ANY
caller of `build_master_integer` today (including a future `run_nash!` integer path) must supply
`α_op_lb`/`α_x_lb` as **raw, unvalidated `Real`s** — exactly the WR-03 gap CONTEXT.md requires fixed.

**Recommended fix (extends BILEV-05's own pattern to the integer master, consistent with "WR-01/02/
03 become load-bearing"):** give `build_master_integer` the SAME optional `bounds_ctx` keyword
`build_master` already has, reusing the EXISTING `derive_alpha_op_lb`/`derive_alpha_x_lb` helpers
(`src/planning/master.jl:330`/`447`) unchanged — `derive_alpha_op_lb` only needs
`(feeder, pf, aggregators, λ₀)`, independent of the follower type, so it works for `run_nash!`'s
`DistributorView` follower exactly as it already does for the continuous path. `derive_alpha_x_lb`,
however, needs a `FollowerLP`-shaped follower (a `follower_kwargs` NamedTuple or pre-built
`FollowerLP`) — `DistributorView`'s pooled-capacity coupling has NO sound per-object relaxed minimum
(this is ALREADY the accepted, documented behavior on the CONTINUOUS path today —
`src/planning/benders.jl:856-862`: `bounds_ctx.follower_kwargs = nothing`, "honestly SKIPPED, never
silently passed"). **Port this exact same skip to the integer path**: validate `α_op_lb` via
`derive_alpha_op_lb`, honestly skip `α_x_lb` validation for `DistributorView`-following integer
masters (an explicit, caller-supplied `α_x_lb` — e.g. `0.0`, a trivially true lower bound since
follower cost `c_inv*x_inv + c_op*x_op >= 0` on this fixture's nonnegative variables — remains
required and unvalidated, same as today).

This bounds fix is a PRECONDITION for WR-02's cut-validity fix (below): `L = α_op_lb + α_x_lb` must
be a genuine lower bound for `add_ll_cut!`'s `Q_ν ≥ L` precondition to hold in the first place.

### Runtime measured (per best response, K=4 toy fixture)

`VERIFIED: live probe, 2026-10-01, scratchpad probe_integer_timing.jl` — single-distributor
`solve_stackelberg!` with a fresh `build_master_integer(K=4, y_max=8.0, ...)` on the EXISTING toy
fixture: **~4.0s per best response** (5 warmed trials: 3.3s, 4.3s, 4.3s, 3.8s, 4.2s), converging in
7 iterations, `nogood_count=0`, `converged_via=:clean`. For N=2 distributors over ~2-5 outer sweeps,
expect roughly `2×N×4s ≈ 16s` to `5×N×4s ≈ 40s` total integer-Nash wall time on this toy scale — well
within the project's per-test-item execution budget, but **plan for this being noticeably slower
than the continuous Nash fixture (`sweeps=2`, sub-second)**; do not set an aggressive `max_sweeps` if
cycling detection needs several sweeps to confirm a genuine cycle.

### Brute-force certification scope (N=2, small K)

CONTEXT.md says "brute-force enumerate the integer grid and assert no profitable unilateral
deviation at the reported equilibrium" — this is a **per-player univariate sweep**, not a full
joint `N`-player grid: for EACH distributor `i`, holding the OTHER distributor's `(x_inv_j, z_j)`
pinned at the reported equilibrium, enumerate distributor `i`'s own `2^K` lattice points (16 for
`K=4`) and confirm none achieves a strictly lower cost than the reported equilibrium's own cost for
`i`. This is both the mathematically correct definition of "no profitable unilateral deviation" for
a GNE AND the cheaper check (`2 × 16 = 32` extra solves vs. `16^2=256` for a full joint grid, though
even the joint grid would be cheap in wall time at this K/N scale — ~256×~0.1s-scale LP/SOCP solves,
not ~4s MILP solves, since each GRID POINT is a single pinned-`y_inv` evaluation via
`corner_recourse`, not a full master MILP re-solve).

### Cycling detection design

`run_nash!`'s existing convergence test (`is_converged(trace, tol_outer, N)`,
`src/planning/nash.jl:196-202`) compares a CONTINUOUS residual against a tolerance — not suited to
detecting a cycle among a FINITE set of lattice points. Recommended design, mirroring
`master_integer.jl`'s OWN `visited::Dict{Vector{Int}, Vector{Float64}}` pattern (already used for
single-master anti-stall detection): maintain a `Dict{Vector{Int}, Int}` mapping each VISITED joint
state (the concatenation of every distributor's own exact `b::Vector{Int}` binary vector at the end
of a sweep) to the sweep index it was first seen at. If the SAME joint state recurs (exact equality
— binaries are exact, no tolerance needed) WITHOUT having converged in between, raise a loud,
named error reporting the full cycle (every sweep index between the first occurrence and the
repeat, and each distributor's own `b` at each of those sweeps) — never silently continue to
`max_sweeps` and report a generic "exhausted" error that hides the cycle's shape.

### WR-01/WR-02/WR-03 fixes (Phase 30 code review's own already-vetted patches)

These are QUOTED VERBATIM from `.planning/phases/30-*/30-REVIEW.md` (the code reviewer's own
proposed fixes, already verified sound in that review — re-verify once more at implementation time,
but do not re-derive from scratch):

**WR-01 — corner search's `ALMOST_INFEASIBLE` handling** (`src/planning/benders.jl:280-289`,
caller at `:1516`, needs `feas_oracle` threaded through `ll_cut_recourse` → `corner_recourse` →
`_oracle_or_infeasible`; `feas_oracle` IS already in scope at the `ll_cut_recourse` call site,
`src/planning/benders.jl:1148` builds it once per `solve_stackelberg!` call):

```julia
const CORNER_INFEASIBLE_STATUSES =
    (MOI.INFEASIBLE, MOI.INFEASIBLE_OR_UNBOUNDED, MOI.LOCALLY_INFEASIBLE)

function _oracle_or_infeasible(oracle, z; on_inexact::Symbol, feas_oracle = nothing)
    return try
        solve_planning_oracle!(oracle, z; on_inexact = on_inexact)
    catch e
        e isa ErrorException || rethrow()
        is_solved_and_feasible(oracle.model; dual = true) && rethrow()
        ts = termination_status(oracle.model)
        ts in ORACLE_INFEASIBLE_STATUSES || rethrow()
        if ts == MOI.ALMOST_INFEASIBLE
            feas_oracle === nothing && rethrow()   # unconfirmed near-certificate: fail loud
            _feas_cut_class(solve_feasibility_oracle!(feas_oracle, z).v) === :disagree && rethrow()
        end
        nothing
    end
end
```
Then correct `_oracle_or_infeasible`'s docstring claim that it applies "the same classification
`solve_stackelberg!`'s own outer oracle catch applies" (currently false — the outer loop confirms,
this function did not).

**WR-02 — `add_ll_cut!`'s unenforced `Q_ν ≥ L` precondition and wrong docstring math**
(`src/planning/master_integer.jl:448-476`):

```julia
function add_ll_cut!(master::BendersMasterInteger, b_trial, Q_nu::Real, L::Real; atol = 1e-6)
    ...
    Q_nu >= L - atol * max(1, abs(L)) || error(
        "add_ll_cut!: Q_nu=$Q_nu < L=$L — the declared epigraph lower bound " *
        "α_op_lb + α_x_lb is not a valid lower bound on the per-corner recourse; " *
        "the LL cut would be INVALID at every corner with Hamming distance >= 2.")
    ...
end
```
Also correct the docstring's reduction at Hamming distance `k`: it currently claims
`"D <= -1, reduces to θ >= L - 2k(Q_nu - L)"` — BOTH parts are wrong (`D = 0` at `k = 1`, not
`<= -1`; the correct reduction is `θ >= L − (k−1)(Q_ν − L)`).

**WR-03 — unsound build-time bound acceptance silently inflates the reported LB/gap**
(`src/planning/master.jl:584-624`): the ROOT fix recommended above (give `build_master_integer` its
own `bounds_ctx`) does not, by itself, close this gap for the CONTINUOUS master's own pre-existing
acceptance rule — WR-03 is about `build_master`'s rule accepting a bound up to `optimum + S` (sound
PER-BOUND, but the convergence certificate `(UB−LB)/max(1,|UB|) ≤ tol` is never widened to account
for that accepted slack). Two options the reviewer proposed, either is acceptable:

```julia
# Option A: clamp an accepted explicit bound DOWN to the certified derivation minimum.
α_eff = min(Float64(α_op_lb), d.optimum - alpha_lb_margin(d.optimum, d.gap))
α_eff < α_op_lb && @warn "build_master: α_op_lb=$α_op_lb lies within the acceptance slack " *
    "above the derived minimum; using the certified bound $α_eff" maxlog = 1
slack_op = 0.0   # the clamped bound is sound, so the runtime floor needs no slack

# Option B: keep the bound as given, widen the convergence certificate itself.
converged_at(UBx) = (UBx - (LB_k - lb_slack.op - lb_slack.x)) / max(1, abs(UBx)) <= tol
```
**This applies to the CONTINUOUS master too** (it was found there), not only to the new integer
bounds_ctx wiring — it should land as a general fix, with the integer master inheriting it by
construction once `build_master_integer` gains its own `bounds_ctx`/`lb_slack` tracking mirroring
`BendersMaster`'s own fields.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| VE / GNE equilibrium computation at scale | A custom fixed-point iteration solver for the joint model | A single direct JuMP solve of the monolithic joint model (this IS the standard VE-via-Rosen-normalized-equilibrium technique) | The whole point of recognizing separability is that NO iterative algorithm is needed to characterize the VE — one convex solve suffices |
| Cycle detection over a finite lattice | A heuristic "same z within tolerance N times" check | Exact dictionary lookup on the binary state `b` (mirrors `master_integer.jl`'s own `visited` pattern already in the codebase) | Binary states are EXACT; tolerance-based comparison can both miss real cycles (two near-but-not-identical corners) and falsely flag non-cycles |
| α bound derivation for the integer master | A new, separate derivation helper | Reuse `derive_alpha_op_lb`/`derive_alpha_x_lb` from `master.jl` verbatim | They already take exactly the inputs available (`feeder, pf, aggregators, λ₀` / `follower_kwargs`); duplicating them risks the two paths drifting apart |

**Key insight:** every piece this phase needs (joint-model solving, cut validity, bound derivation,
cycle bookkeeping) already has an established, tested PATTERN somewhere in `src/planning/` from
Phases 24/27/29/30 — the task is extension and generalization (N=1→N, continuous→integer), not new
algorithm design.

## Common Pitfalls

### Pitfall 1: Assuming `run_nash_probe`'s existing seed/order dimensions expose GNE multiplicity
**What goes wrong:** building the BILEV-06a fixture and running `run_nash_probe` unmodified, getting
a zero spread, and concluding the fixture numbers are wrong.
**Why it happens:** the DEFAULT `x_inv0` derivation (`maximum(z0[j,:])/corridor_cap`) has zero slack
by construction for ANY `z0`, so the Gauss-Seidel dynamic always converges to the same "invest your
own exact need" split regardless of `z0`/order — this is a property of the ALGORITHM's default
seeding, not the fixture's economics.
**How to avoid:** extend `run_nash_probe` (or build a small bespoke probe loop around `run_nash!`
directly) to vary `x_inv0` across seeds, per the recommendation above.
**Warning signs:** every probe run converging to the bit-identical point regardless of seed/order
(exactly what this session's live probe found before diagnosing the cause).

### Pitfall 2: Treating the joint model's degenerate LP optimum as "the" VE without checking which vertex HiGHS returns
**What goes wrong:** the symmetric fixture's joint model has a DEGENERATE optimal face (any split
summing to `S_min` is equally joint-optimal) — HiGHS may return ANY vertex, not necessarily the
symmetric one, and this can look like a bug ("VE should be symmetric, why is it [0.7,0]?").
**Why it happens:** LP degeneracy + solver-specific tie-breaking, not a modeling error.
**How to avoid:** either accept and document whichever vertex is returned as A valid VE (mathematically
correct — equal multiplier by construction), or add a tiny deterministic tie-breaking regularization
and document that choice explicitly.
**Warning signs:** the VE result changing between HiGHS versions/settings without any constraint
change.

### Pitfall 3: Building the integer bounds fix only for the Nash path, not the general `build_master_integer`
**What goes wrong:** patching bounds validation into `run_nash!`'s NEW integer-spec wiring only,
leaving `test_planning_benders_integer.jl`'s existing single-distributor integer path (and any
future caller) still exposed to the WR-02/WR-03 gaps.
**Why it happens:** the phase's own scope language ("Integer investment at N>1") can read as
Nash-only.
**How to avoid:** fix `build_master_integer`/`add_ll_cut!` themselves (general, in
`master_integer.jl`), then wire `run_nash!` to use the fixed builder — not the reverse.
**Warning signs:** the single-distributor integer test suite (`test_planning_benders_integer.jl`,
`test_planning_certification_integer.jl`) staying silent about a precondition violation that the new
Nash fixture happens to trigger.

### Pitfall 4: Confusing "no individual cap binds" with "no cap exists"
**What goes wrong:** setting `x_inv_max` to something very large (e.g. `Inf` or `100.0`) "to be
safe," which can create numerical conditioning issues in the LP/MILP (unbounded-feeling box
constraints) without actually changing the exposed continuum.
**How to avoid:** pick `x_inv_max` with a modest, clearly-documented margin above the analytically
derived `S_min` (this session used `1.0` vs. `S_min=0.7`, margin `0.3`) — enough to be safely
non-binding, not so much as to be a de facto `Inf`.

### Pitfall 5: TestItemRunner under `--project=.` (standing project trap, still applies)
**What goes wrong:** writing `<verify>` blocks for the new BILEV-06/07 tests that invoke
TestItemRunner directly under `--project=.` — it is a test-only dependency and does not resolve
there (see the standing memory note `gsd-plan-verify-testitemrunner-trap`).
**How to avoid:** verify via direct Julia/Test.jl scripts reproducing the `@testitem` bodies
(exactly as this research session's own probes did — `julia --project=. script.jl` loads `TSODSO`
directly without any TestItemRunner machinery; a script needing BOTH main-env `TSODSO` and
test-only fixtures/macros should use the documented stacked load path
`JULIA_LOAD_PATH="test:.:@stdlib" julia script.jl`). Full suite only via
`julia --project=. -e 'import Pkg; Pkg.test()'` (~24 min, orchestrator-only, run detached per the
`background-suite-orphan-race` memory note).

## Code Examples

### Reproducing the toy fixture standalone (no TestItemRunner), as used for every probe this session

```julia
# Source: this session's own scratchpad probe, verified against test/test_planning_nash.jl and
# test/test_planning_oracle.jl's ToyDeviceFixture
using TSODSO
using JuMP

function two_bus_feeder()
    buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)]
    branches = [Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT)]
    return Feeder(buses, branches, 1)
end

struct ToyElasticDevice <: AbstractDevice
    bus::Int; a::Float64; b::Float64; Pmax::Float64
end
function TSODSO.contribute!(d::ToyElasticDevice, ctx::ModelContext; T::Int)
    p = @variable(ctx.model, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pmax)
    p_inject = AffExpr[-p[t] for t in 1:T]
    utility = sum(d.a * p[t] - (d.b / 2) * p[t]^2 for t in 1:T)
    return (; vars = (; p), p_inject, utility)
end
```

### Explicit `x_inv0` seeding to land on a specific point of the GNE continuum

```julia
# Source: this session's own scratchpad probe (VERIFIED live, see "Concrete fixture numbers" above)
shared = build_shared_transmission(;
    N = 2, T = 1, corridor_cap = 2.0,
    x_inv_max = [1.0, 1.0], c_inv = [1.0, 1.0], c_op = [[0.5], [0.5]],
)
r = run_nash!(specs, shared;
    z0 = reshape([0.7, 0.7], 2, 1),     # seed z AT the unconstrained optimum
    x_inv0 = [0.5, 0.2],                # seed an ASYMMETRIC split (sums to S_min=0.7)
    tol_outer = 1e-4, max_sweeps = 50, order = :forward,
    checkpoint_dir = mktempdir())
# r.x_inv ≈ [0.500153, 0.200186], r.z ≈ [0.700305, 0.700372] — a DIFFERENT, equally valid GNE.
```

### `build_master_integer` through `solve_stackelberg!` — existing single-distributor pattern to extend to N in `run_nash!`

```julia
# Source: test/test_planning_benders_integer.jl:84-131 (existing, byte-identical production pattern)
imaster = build_master_integer(; T = 1, K = 4, c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)
result = solve_stackelberg!(
    feeder, LinDistFlow(), [agg];
    λ₀ = λ₀, T = 1,
    follower_kwargs = follower_kwargs,
    master_kwargs = NamedTuple(),   # MUST be empty when master= is supplied
    master = imaster,
    max_iter = 50, checkpoint_dir = dir,
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|---------------|--------|
| Single-distributor Stackelberg-Benders only | N-distributor Gauss-Seidel Nash diagonalization (`run_nash!`) | Phase 13 (v2.0) | `nash.jl`/`coupling.jl` introduced; this phase extends it to interior caps + integer |
| Continuous-only investment (`BendersMaster`) | Binary-expansion integer master (`BendersMasterInteger`) | Phase 24 (v3.0) | `master_integer.jl` introduced; `docs/writeups/stackelberg_vs_psr_n1n2.typ` has NOT been updated since — still says "no binary/integer variable exists anywhere" (line 189), now FALSE |
| Hand-picked α_op_lb/α_x_lb (risk of invalid bound) | `:auto`-derived, build-time-validated bounds (`bounds_ctx`) | Phase 30 (v4.0) | Only reaches `BendersMaster`, NOT `BendersMasterInteger` — this phase's WR-03 fix closes that gap |
| Single-distributor-only genuine-bilevel variant | `solve_bilevel!`/`build_bilevel_kkt` (genuinely bilevel, distinct from Benders-decomposed integrated problem) | Phase 29 (v4.0) | Docs (`modelo_stackelberg_dso_unico.typ`) never mention this variant at all — BILEV-08 must add it to the taxonomy too |

**Deprecated/outdated (docs only, not code):** `stackelberg_vs_psr_n1n2.typ`'s integer-extension
section (lines 173-189) and its "Resumo de desvios deliberados" bullet (line 237) both assert the
integer extension is "genuinely not implemented" — this is now FALSE (Phase 24 implemented it, and
Phase 31 extends it to N>1). `modelo_stackelberg_dso_unico.typ` has NO section at all on the Nash/
GNE variant, the genuine-bilevel variant, or the integer master — it only narrates the single-
distributor continuous Stackelberg-Benders loop.

## Docs Refresh Scope (BILEV-08)

### `docs/writeups/stackelberg_vs_psr_n1n2.typ` (253 lines, Portuguese) — stale passages identified

- **Lines 173-189** ("Extensão inteira — problemas (8)-(9)"): every row is labelled "Não
  implementado (`INT-STRETCH`)" and line 189 states flatly "Nenhuma variável binária/inteira existe
  em lugar algum de `src/planning/` hoje" — **FALSE since Phase 24**. Must be rewritten to map the
  PSR note's integer-extension equations (8a)-(9e) onto `master_integer.jl`'s actual binary-expansion
  construction (`build_master_integer`, `add_ll_cut!`'s Laporte-Louveaux cut, `apply_integer_cuts!`'s
  dispatch) — likely still "Desvio deliberado" for the PSR note's own Lagrangian-relaxation method
  (this project uses Laporte-Louveaux integer L-shaped cuts, not Lagrangian dual decomposition), but
  no longer "Não implementado."
- **Line 237** ("Extensão inteira... genuinamente não implementada... Fase 24 (v3.0)"): same fix,
  restate as implemented, citing Phase 24/31.
- **§"Equilíbrio de Nash multi-distribuidor" (lines 205-221):** currently describes ONLY the
  Gauss-Seidel GNE-seeking mechanism with no mention of multiplicity, the VE, or integer N>1. Needs:
  (a) a note that the diagonalization converges to A generalized Nash equilibrium, not necessarily
  the unique one (cite BILEV-06's fixture + `run_nash_probe`'s honesty-gate design, already
  described at line 221 but without the GNE-multiplicity framing); (b) a new subsection on
  `solve_variational_equilibrium` and what it certifies; (c) a note that `run_nash!` now accepts an
  `integer` kwarg for N>1 integer investment (BILEV-07).

### `docs/writeups/modelo_stackelberg_dso_unico.typ` (195 lines, Portuguese) — missing taxonomy

This file currently narrates ONLY the single-distributor continuous Stackelberg-Benders loop
(sections: Conjuntos e índices, Variáveis, O problema bilevel completo, Como Benders resolve,
Resultado, Notas de implementação). It has **zero mention** of the genuine-bilevel variant
(`solve_bilevel!`, Phase 29), the Nash/GNE variant (`run_nash!`, Phase 13), or the integer master
(Phase 24). CONTEXT.md's locked decision requires adding "the variant taxonomy" here — recommend a
NEW section (e.g. `= Taxonomia dos variantes de planejamento`) with a table:

| Variante | Função Julia | Natureza teórico-dos-jogos | Teste de certificação |
|----------|-------------|------------------------------|------------------------|
| Integrado, decomposto por Benders | `solve_stackelberg!` | Problema único (não é um jogo de dois níveis genuíno — líder e seguidor compartilham o mesmo objetivo) | `test_planning_benders.jl`, `test_planning_goldens.jl` (PVAL-02) |
| Bilevel genuíno | `solve_bilevel!`/`build_bilevel_kkt` | Stackelberg genuíno (seguidor minimiza seu PRÓPRIO custo, diferente da valorização do líder) | `test_planning_bilevel.jl`, `test_planning_certification_bilevel*.jl` (BILEV-01/02) |
| GNE de restrição compartilhada / VE | `run_nash!` / `solve_variational_equilibrium` | Jogo de Nash generalizado (N jogadores, restrição de capacidade compartilhada); VE = equilíbrio com multiplicador comum | `test_planning_nash.jl` (BILEV-06) |

Each row must cite the backing function AND test file (per CONTEXT.md's "every claim citing the
backing function and test" requirement), plus a one-line mention of the integer master
(`BendersMasterInteger`, usable inside BOTH the first and third rows via `master=`) and the Phase-30
SOCP/inexactness policy (`inexact_policy`, applies to all three via `solve_stackelberg!`).

### Documenter docstring refresh (three entry points)

- `solve_stackelberg!` (`benders.jl:805-1058`): already has an "Honest relabelling" paragraph
  pointing to `solve_bilevel!` — ADD a short pointer to `run_nash!`/`solve_variational_equilibrium`
  for the N>1 shared-constraint case, and update the `master=` paragraph to mention
  `BendersMasterInteger`'s own bounds_ctx support (once implemented) rather than leaving it
  unqualified.
- `solve_bilevel!` (`src/planning/bilevel_kkt.jl`, not read in depth this session — locate via
  `grep -n "function solve_bilevel!" src/planning/bilevel_kkt.jl`): add a short cross-reference to
  the taxonomy table above.
- `run_nash!` / `solve_variational_equilibrium` (`nash.jl`): `run_nash!`'s docstring already
  documents the Gauss-Seidel mechanism in detail (lines 270-380) — ADD the GNE-multiplicity caveat
  and a pointer to `solve_variational_equilibrium` for VE selection, plus the new `integer` kwarg's
  full contract (mirroring the existing `inexact_policy` kwarg's documentation style exactly — this
  file already has a strong docstring convention to follow).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `x_inv_max=[1.0,1.0]` is the recommended interior-cap value (vs. some other safely-non-binding number) | GNE Structure, "Concrete fixture numbers" | LOW — this was empirically tested and confirmed to produce the expected continuum; a different value (e.g. 0.8) would also work, this is Claude's-discretion territory per CONTEXT.md, not a verified-unique requirement |
| A2 | A single shared `integer` kwarg (not per-spec) is the right `run_nash!` API shape | Integer N>1 Wiring | LOW — CONTEXT.md's own sketch suggests this shape; if distributors need different K/y_max lattices a per-spec field is a trivial variant, not a redesign |
| A3 | Symmetry-breaking regularization for VE display is optional/discretionary, not required by CONTEXT.md | GNE Structure, VE design | LOW — CONTEXT.md only requires "verify the multiplier equality explicitly" and "lies inside the analytic GNE interval," both satisfied by ANY vertex HiGHS returns |

**If this table is empty:** N/A — three low-risk discretionary items above, nothing load-bearing is
unverified.

## Open Questions (RESOLVED)

> RESOLVED by orchestrator 2026-10-01: (1) extend `run_nash_probe` by dispatch-in-place, additive/backward-compatible; (2) VE joint model generic over `pf`; (3) WR-03 fix covers BOTH `BendersMaster` and `BendersMasterInteger`.

1. **Should `run_nash_probe`'s signature change be backward-compatible (dispatch on
   `seed_z0 isa NamedTuple`) or should a NEW function (`run_nash_probe_integer`-style) be added
   instead?**
   - What we know: the existing `seeds::NamedTuple` maps names to `z0` matrices; every existing
     caller (just the BILEV-06 corner-cap control test) passes bare matrices.
   - What's unclear: whether the planner prefers a clean additive dispatch inside the SAME function
     (my recommendation) or a visibly separate code path for clarity.
   - **Proposed resolution:** use the dispatch approach (`seed_z0 isa NamedTuple` branch) — it keeps
     ONE honesty-gate function per NASH-04's own design intent ("never present one run as
     canonical"), and the existing corner-cap control test needs zero changes.

2. **Does the VE joint model need to inline the FULL `ConvexBranchFlow` SOCP oracle, or is the toy
   `LinDistFlow` fixture (this phase's actual scope) sufficient?**
   - What we know: CONTEXT.md scopes BILEV-06 to "a variant of the existing 2-distributor toy" —
     the toy uses `LinDistFlow()`, not `ConvexBranchFlow()`.
   - What's unclear: whether a future phase will need a `ConvexBranchFlow`-scale joint VE model.
   - **Proposed resolution:** build `solve_variational_equilibrium` generically (accept any `pf`
     per distributor, exactly as `solve_stackelberg!` does) even though THIS phase's fixture only
     exercises it on `LinDistFlow()` — this costs nothing extra (the function just forwards `pf` to
     each inlined oracle block) and avoids a near-term rewrite.

3. **Should the WR-03 convergence-certificate fix (Option A clamp vs. Option B widen) be applied to
   the EXISTING continuous `BendersMaster` path in this phase, or deferred?**
   - What we know: CONTEXT.md explicitly lists WR-01/02/03 as "Phase-30 open integer-path review
     warnings... FIXED here (they become load-bearing)" — WR-03 is PHRASED as a general warning (not
     integer-specific) in `30-REVIEW.md`, but CONTEXT.md's own bullet only names WR-01/WR-02
     explicitly for the integer path and references WR-03 implicitly via the 30-REVIEW.md citation.
   - What's unclear: whether CONTEXT.md intends WR-03 as in-scope for THIS phase's continuous master
     too, or only for the new integer wiring.
   - **Proposed resolution:** fix WR-03 in `build_master` (continuous) too, since (a) it was found
     there originally and the integer master would otherwise inherit the SAME flaw via its own
     `bounds_ctx` extension, and (b) CONTEXT.md's phrasing "become load-bearing" suggests the full
     warning list, not a subset — but FLAG this choice explicitly to the user/planner since it
     slightly widens scope beyond the integer master alone.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | TestItems.jl 1.0 / TestItemRunner.jl 1.1 (test-only deps), executed via `Pkg.test()` for the full suite |
| Config file | `test/runtests.jl` (`@run_package_tests`); `test/Project.toml` pins the test-only deps |
| Quick run command | Direct Julia script reproducing the relevant `@testitem` body: `julia --project=. script.jl` (main env) or `JULIA_LOAD_PATH="test:.:@stdlib" julia script.jl` (if test-only fixtures/macros are needed) — NEVER `TestItemRunner` under `--project=.` |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (~24 min this session's measured Phase-30 baseline; run detached, never foreground-blocking) |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| BILEV-06 | Interior-cap fixture exposes nonzero GNE spread; corner-cap control stays at zero spread | unit (direct script reproducing a `@testitem`) | `julia --project=. probe.jl` (pattern above) | ❌ Wave 0 — new fixture + probe extension needed in `test/test_planning_nash.jl` |
| BILEV-06b | `solve_variational_equilibrium` certifies equal multiplier + interval membership | unit | same pattern | ❌ Wave 0 — new function + new test file/section |
| BILEV-07 | Integer Nash N=2 converges; brute-force confirms no profitable deviation; cycling is detected and reported | unit | same pattern | ❌ Wave 0 — `run_nash!`'s `integer` kwarg, `build_master_integer`'s `bounds_ctx`, cycle detection all new |
| BILEV-08 | Docs build cleanly (`typst compile`), taxonomy table present, docstrings updated | manual + `typst compile` exit-code check | `~/.local/bin/typst compile docs/writeups/stackelberg_vs_psr_n1n2.typ /tmp/out.pdf` | N/A — doc files exist, content is what's missing |

### Sampling Rate
- **Per task commit:** direct-script reproduction of the new `@testitem`(s) touched by that task.
- **Per wave merge:** re-run every new/touched planning test file directly (not the full suite).
- **Phase gate:** full suite green (`Pkg.test()`, detached, orchestrator-run) before `/gsd:verify-work`.

### Wave 0 Gaps
- [ ] `test/test_planning_nash.jl` — new interior-cap fixture + `solve_variational_equilibrium`
  certification items (BILEV-06/06b)
- [ ] `test/test_planning_nash.jl` or a new `test/test_planning_nash_integer.jl` — N=2 integer Nash
  + brute-force + cycling-detection items (BILEV-07)
- [ ] `run_nash_probe`'s `seeds` dispatch extension (code, not a test gap per se, but blocks the
  BILEV-06 probe test from being written at all until it lands)
- [ ] `build_master_integer`'s `bounds_ctx` extension (code; blocks a sound BILEV-07 bounds story)

*(No framework install needed — TestItems/TestItemRunner are already pinned test-only deps.)*

## Security Domain

`security_enforcement` is absent from `.planning/config.json`, so per policy this section is
included, but this is a pure numerical-research library with no network-facing surface, no
authentication, no user-supplied untrusted input parsing, and no secrets handling — none of the
ASVS categories meaningfully apply to this phase's changes (new Julia functions operating on
in-memory JuMP models and local file I/O for checkpoints/docs).

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | N/A — no auth surface anywhere in this library |
| V3 Session Management | no | N/A |
| V4 Access Control | no | N/A |
| V5 Input Validation | yes (narrow) | `run_nash!`/`build_master_integer`'s own existing `ArgumentError` guards-before-build discipline (already established project convention) — extend identically to the new `integer`/`bounds_ctx` kwargs; no new validation PATTERN needed |
| V6 Cryptography | no | N/A |

### Known Threat Patterns for this stack

Not applicable — no injection, auth, or cryptographic surface exists in this phase's scope. The one
relevant "safety" pattern already established project-wide is **fail-loud-never-silent** on any
malformed input (boundary `ArgumentError`s before any solve call) and **never silently accept an
unsound numerical bound** (the entire WR-01/02/03 fix set is exactly this pattern applied to the
integer Benders path) — continue it, do not introduce a new validation idiom.

## Sources

### Primary (HIGH confidence — direct code reads and live executions this session)

- `src/planning/nash.jl` (853 lines, read in full) — `run_nash!`, `run_nash_probe`, `NashTrace`
- `src/planning/coupling.jl` (439 lines, read in full) — `SharedTransmission`, `DistributorView`
- `src/planning/master_integer.jl` (639 lines, read in full) — `BendersMasterInteger`,
  `add_ll_cut!`, `apply_integer_cuts!`
- `src/planning/benders.jl` (selected sections, ~700 lines read) — `solve_stackelberg!`,
  `corner_recourse`, `_oracle_or_infeasible`, `ll_cut_recourse`, `_assert_epigraph_floor`
- `src/planning/master.jl` (selected sections) — `BendersMaster`, `ALPHA_LB_MARGIN`/
  `ALPHA_LB_RTOL`/`ALPHA_LB_REJECTION_TOL`, `derive_alpha_op_lb`/`derive_alpha_x_lb` (location
  confirmed, body not re-read — already fully specified by Phase 30's own docs)
- `test/test_planning_nash.jl` (lines 1-340 read) — existing corner-cap fixture, `ToyElasticDevice`
- `test/test_planning_benders_integer.jl` (lines 1-130 read) — existing single-distributor integer
  pattern
- `test/test_planning_oracle.jl` (lines 120-305 read) — `ToyDeviceFixture`/`ToyElasticDevice`
  canonical definition
- `docs/writeups/stackelberg_vs_psr_n1n2.typ` (253 lines, read in full)
- `docs/writeups/modelo_stackelberg_dso_unico.typ` (headings only, 195 lines total)
- `.planning/phases/30-*/30-FINDINGS.md` and `30-REVIEW.md` (read in full) — WR-01/02/03 exact fix
  snippets, quoted verbatim above
- Three live Julia probes run this session (`julia --project=.`, confirmed working, zero errors):
  `probe_nash_interior.jl` (GNE continuum + z0-only-seed-fails finding), `probe_integer_timing.jl`
  (per-best-response wall time)
- `~/.local/bin/typst --version` (0.15.1), `julia --version` (1.12.5), `using HiGHS, Clarabel,
  Ipopt` — all confirmed loadable this session

### Secondary (MEDIUM confidence)
- None — every finding in this document was either read directly from source or confirmed by a live
  probe this session.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- GNE/VE theory and fixture design: HIGH — derived analytically AND empirically confirmed via live
  probe in this session, not assumed from training knowledge.
- Integer N>1 wiring and WR-01/02/03 fixes: HIGH — the fixes are the code reviewer's OWN already-
  vetted patches from `30-REVIEW.md`, quoted verbatim; the wiring gap was confirmed by direct
  reading of `nash.jl`'s current (unextended) call to `solve_stackelberg!`.
- Docs refresh scope: HIGH — both `.typ` files were read directly; stale passages identified by line
  number.
- Exact tolerance constants the planner will pin (measured floors for spread, `atol` for the
  `Q_ν ≥ L` check, etc.): MEDIUM — this research measured REPRESENTATIVE values on the toy fixture
  live, but the planner/executor should re-measure on the FINAL fixture numbers chosen, per this
  project's own "measured, not picked" standing convention.

**Research date:** 2026-10-01
**Valid until:** 30 days (stable internal codebase, no external API dependency; re-verify if
Phases 32-34's architecture refactors land first and touch `src/planning/` signatures)

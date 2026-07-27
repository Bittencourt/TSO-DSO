# Architecture Research — v3.0 Research Extension Rungs

**Domain:** Brownfield integration study — five new research axes onto a validated Julia/JuMP
TSO-DSO optimization framework (single-ownership include graph, `src/TSODSO.jl`).
**Researched:** 2026-07-26
**Confidence:** HIGH (all claims below are grounded in the actual code, cited file:line; a few
forward-looking design choices for axes 1/4/5 are marked MEDIUM/flagged as needing a dedicated
model-math research pass before implementation — this document answers the ARCHITECTURE
integration question only)

## System Overview (existing, as-built)

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ experiments/  Scenario (flat kwdef, primitive selectors) → materialize →      │
│               run_scenario (:centralized|:admm) → store (@tagsave/savename)   │
├──────────────────────────────────────────────────────────────────────────────┤
│ admm/         AgrOpt (per-node QP) ⇄ DsoOpt (whole-net SOCP) ⇄ solve_admm     │
│               (build-once, Parameter re-solve, dual ascent on λ [+ μ v2.1])   │
├──────────────────────────────────────────────────────────────────────────────┤
│ planning/     retry/checkpoint → subproblem(PlanningOracle) → follower(LP) →  │
│               master(BendersMaster) → benders(solve_stackelberg!) →           │
│               coupling(SharedTransmission) → nash(run_nash!, Gauss-Seidel)    │
├──────────────────────────────────────────────────────────────────────────────┤
│ models/       welfare_solve (GLB-CVX centralized) → exactness (assert_socp_   │
│               exact!) → oracle (operational_oracle + SEAM-01 inert stubs) →   │
│               ac_oracle (independent AC-OPF peer, exactness certification)   │
├──────────────────────────────────────────────────────────────────────────────┤
│ pricing/      dlmp → fit → checks → welfare  (dual extraction/decomposition) │
├──────────────────────────────────────────────────────────────────────────────┤
│ devices/      AbstractDevice (2 contract variants) → Thermostatic/Deferrable/│
│               PVBattery/Interruptible → Aggregator (SOLE :Rp/:Rq writer)     │
├──────────────────────────────────────────────────────────────────────────────┤
│ powerflow/    AbstractPowerFlow → DCPowerFlow/LinDistFlow/ConvexBranchFlow/  │
│               ACPowerFlow, each `contribute!` into ctx.residuals (no if/else)│
├──────────────────────────────────────────────────────────────────────────────┤
│ core/         ModelContext (model + constraints/residuals/meta registries)  │
├──────────────────────────────────────────────────────────────────────────────┤
│ data/         Feeder (immutable, assert_radial-gated construction) + topology│
└──────────────────────────────────────────────────────────────────────────────┘
```

The load-bearing conventions this milestone must respect (all found directly in code):

- **Additive-orchestration precedent.** Every prior layered feature (ADMM Phase 6, planning
  Phase 10-14) is built as a **new sibling module that reuses `contribute!`/`solve_welfare`
  verbatim**, not by editing the validated builder it reuses (`src/planning/subproblem.jl:1-26`:
  *"`welfare_solve.jl`/`oracle.jl` are byte-for-byte UNMODIFIED by this file (D-03/D-11)"*). v3.0
  should default to the same pattern per axis unless a targeted, reviewed, byte-identical-default
  modification is clearly cheaper (as v2.1's `reactive_consensus` kwarg was).
- **Build-once + `Parameter`-pin + re-solve** is already the house style for every outer loop
  (`AgrOpt`/`DsoOpt` in `solve_admm.jl`, `PlanningOracle` in `subproblem.jl:30-69`, `FollowerLP` in
  `follower.jl:59-68`, `SharedTransmission` in `coupling.jl:112-124`). This is the natural chassis
  for MPC windows, stochastic-scenario subproblems, and Benders subproblems alike (see §g below).
- **Fail-loud, never silent-partial.** `operational_oracle`'s SEAM-01 stubs throw `ArgumentError`
  rather than return a wrong value when a not-yet-wired feature is invoked (`oracle.jl:162-188`).
  New axes should preserve this: an unfilled extension point must error, not silently no-op.

---

## Per-Axis Integration Analysis

### Axis 1 — Overvoltage-capable relaxation

**Consumes (unmodified):** `AbstractPowerFlow` contract (`powerflow/AbstractPowerFlow.jl`),
`ModelContext` residual seam (`core/ModelContext.jl`), `solve_welfare`'s formulation-generic
solver routing (`problem_class(pf)` trait, `welfare_solve.jl:34-40`), `allow_export` frontier
machinery already built for the reverse-flow regime (`welfare_solve.jl:46-60`), the AC-OPF peer
`ACPowerFlow` as an independent oracle (`powerflow/ACPowerFlow.jl:1-85`).

**Consumes (as a design template):** `ConvexBranchFlow`'s LinDistFlow exactness-copy pattern
(`powerflow/ConvexBranchFlow.jl:116-234`) is the reference implementation for "add one more
convex tightening device tied to the SOC cone" — but that specific copy (`v̂`, thesis 3.43/3.45)
is proven **only** for radial, non-reverse-flow operating points (v2.1's own EXACT-04 finding:
`assert_socp_exact!`, `models/exactness.jl:78-107`, throws on the high-PV/overvoltage case — this
is the milestone's own motivating failure).

**New:** a new `AbstractPowerFlow` sibling (e.g. `OvervoltageBranchFlow` or a generalized
`ConvexBranchFlow{Copy}` parametrized by copy-strategy) that writes an **additional or
alternative** convexification valid in the reverse-flow/overvoltage regime, plus a companion
exactness certificate mirroring `assert_socp_exact!`'s shape (same `ctx.meta[:pf_vars]` stash
convention, `ConvexBranchFlow.jl:229-232`) but with a validity condition appropriate to that
regime (its own `rtol`/`atol` combined-bound style, not a copy-paste of `assert_socp_exact!`,
since the failure mode differs qualitatively, not just numerically). **Do not modify**
`ConvexBranchFlow.jl` or `models/exactness.jl` — both are the correctness keystone of the shipped
v1–v2.1 line and their radial-exactness certificate must stay the untouched baseline the new
formulation is benchmarked against (exactly the `ConvexBranchFlow`/`ACPowerFlow` peer-oracle
pattern already used for EXACT-01..04).

**Depth flag:** the actual convexification (tightened SOC, McCormick-style valid inequalities, a
piecewise-linear voltage-envelope, or a bilinear-relaxation strengthening) is unresolved
model-math, not an architecture question — this needs its own THEORY/model research pass before
a plan is written. What IS settled architecturally: it plugs in exactly where `ConvexBranchFlow`
does (new `pf` singleton type + `contribute!` method + `problem_class` trait method), touches no
existing formulation file, and needs a new, axis-specific exactness certificate file beside
(not inside) `models/exactness.jl`.

### Axis 2 — MPC / rolling-horizon / RTP

**Consumes:** the SEAM-01 `horizon_state` stub in `operational_oracle` (`oracle.jl:76-80,
99,119-121`) — **but read carefully**: this stub is still, today, completely inert (only
`@debug`-logged, never threaded into a device). The exact precedent for how such a stub actually
gets filled is instructive and cautionary: the SEAM-01 **`z`/coupling-dual stub was never filled
either** — v2.0's planning layer did not touch `_coupling_dual`'s throw (`oracle.jl:162-188`
remains byte-for-byte from Phase 4); instead it built a **parallel** `PlanningOracle` struct in
`planning/subproblem.jl` that mirrors `solve_welfare`'s shape from scratch with a genuine
`Parameter`-typed `z` (`subproblem.jl:30-69`). Expect the same outcome for `horizon_state`: MPC
will very likely ship as a **new sibling orchestrator** (e.g. `src/mpc/window.jl` building a
`RollingWindowOracle` that mirrors `solve_welfare`'s assembly with `Parameter`-typed initial
states), not as a literal fill of `operational_oracle`'s stub.

**Critical device-contract gap (point c/d of the question):** `PVBattery.contribute!` fixes the
SOC initial condition as a **plain `Float64` struct field substituted directly into an equality
constraint** — `@constraint(m, soc[1] == d.soc0)` (`devices/PVBattery.jl:253`), where `d.soc0`
was baked in at `PVBattery` **construction** time (`PVBattery.jl:87-98,146-156`). `Thermostatic`
has the identical pattern for its initial temperature (`Tin[1] == Tin0`, confirmed by grep,
`devices/Thermostatic.jl:~134`). **There is no re-settable channel today.** A rolling-horizon
loop that wants to re-solve tomorrow's window with today's converged end-state as the new
initial condition cannot do so without either:

1. **Rebuilding the device (and hence the whole model) every window** — works, but throws away
   every "build-once, re-solve via `Parameter`" convention this codebase has established
   everywhere else (ADMM, planning) and is the exact anti-pattern the project's own docs warn
   against (`admm/solve_admm.jl:31-36` "Rebuilding JuMP models each ADMM/Benders iteration" is
   listed as the dominant avoidable performance sink in CLAUDE.md's "What NOT to Use" table); or
2. **A targeted, minimal, byte-identical-default modification** to `PVBattery.jl:253` (and
   `Thermostatic`'s analogous line) that turns the initial-condition RHS into a JuMP `Parameter`
   pinned to the same default value (`@variable(m, soc0_p in Parameter(d.soc0)); @constraint(m,
   soc[1] == soc0_p)`) — numerically identical for a single solve, but now exposes a
   `set_parameter_value!` hook for MPC's re-solve loop. This mirrors the v2.1 `reactive_consensus`
   precedent (a default-off/default-unchanged kwarg added to an already-validated file,
   `admm/solve_admm.jl:99-109`) — modification, not new-file orchestration, because the state
   *must* live inside the same variable the device already declares.

Recommend (2), scoped to exactly the IC line in `PVBattery.jl`/`Thermostatic.jl`, documented as a
new AbstractDevice contract variant ("Variant 3 — stateful/re-solvable device") added to
`devices/AbstractDevice.jl`'s docstring (additive doc, no contract-breaking change to Variant 1/2
callers). `Deferrable`/`Interruptible` have no persistent state and need no such change.

**New:** `src/mpc/` (or `src/rolling/`) directory: a `RollingWindowOracle` builder (mirrors
`PlanningOracle`'s build-once/`Parameter` shape) + an outer `run_mpc!` loop (mirrors
`solve_admm`'s iterate-and-record shape, `admm/solve_admm.jl` docstring algorithm section) that
re-solves the SAME window model each step, pinning battery/thermostat `soc0`/`Tin0` `Parameter`s
to the previous step's converged value and pinning `λ₀`/forecast `Parameter`s to the next
window's data. Diagnostics: a new `NashTrace`/`BendersTrace`-style ledger
(`planning/trace.jl` is the direct template) comparing rolling DADPs to the perfect-foresight
day-ahead solve (the milestone's own stated benchmark).

**Modifies:** `PVBattery.jl`, `Thermostatic.jl` (the two-line `Parameter`-ization above),
`devices/AbstractDevice.jl` (doc-only, new contract variant), and — see the shared §f finding
below — **`experiments/Scenario.jl`**.

### Axis 3 — Stochastic PV/demand uncertainty

**Consumes:** the SEAM-01 `objective_hook::Function = identity` stub (`oracle.jl:72-75,
116-118`). **This stub is architecturally insufficient for a genuine extensive form**, and this
is worth stating plainly: `objective_hook` is documented as composing a **single already-solved**
scenario's welfare into an outer sum — but a proper scenario-tree extensive form needs **N
parallel copies of the device/network variables inside ONE JuMP model**, sharing first-stage
("here-and-now") decisions and a single **non-anticipativity** structure, with the objective a
probability-weighted sum built at construction time, not post-hoc composed from N independent
solves. A `Function` hook applied per-scenario cannot retrofit shared first-stage variables
across scenarios after the fact. Expect (again, matching the `z`-stub precedent) a **new
sibling builder**, not a literal fill of this stub.

**New:** `src/stochastic/extensive_form.jl` (or `src/stochastic/scenario_tree.jl`): a builder
that calls `contribute!(pf, ctx, feeder; T)` and `contribute!(agg, ctx; T)` **once per scenario
`s ∈ 1:S`** into **one shared `ModelContext`/`Model`** (S parallel copies of the network +
device variables, keyed by scenario index — directly reusing the existing `contribute!` verbatim,
per the "ORCHESTRATION over already-validated builders" pattern already used for ADMM and
planning), plus a probability-weighted objective `Σ_s p_s · welfare_s` and non-anticipativity
constraints on any first-stage variable. A seeded Markov scenario-tree generator lives beside
`data/profiles.jl` (the existing seeded PV/demand profile generator, `data/profiles.jl`, is the
direct template for "seeded, deterministic, `StableRNGs`-backed" scenario draws — reuse its
`generate_profiles(seed=...)` idiom, do not hand-roll a second RNG discipline).

**Modifies:** nothing in `models/`, `powerflow/`, or `devices/` — this axis is pure orchestration
over existing `contribute!` builders, matching the ADMM/planning precedent exactly. Does modify
**`experiments/Scenario.jl`** (see §f).

### Axis 4 — Meshed networks + 4Q-BESS + live reactive dual-ascent

This axis has **two structurally separate sub-problems** that the milestone context correctly
flags as sharing relaxation-machinery risk with axis 1, but are otherwise independent and can be
sequenced separately.

**(a) Meshed topology — investigate point (a) directly.**
`Feeder`'s inner constructor (`data/Feeder.jl:62-72`) unconditionally calls `assert_radial`
(`data/topology.jl:36-125`), which **requires** `length(branches) == length(buses) - 1` (the
tree edge-count theorem, `topology.jl:40-44`) and a single `is_root` bus (`topology.jl:109-122`).
A meshed network has cycles (`branches > buses - 1`) by definition — it **cannot** be represented
by `Feeder` at all; there is no relaxed-invariant escape hatch inside the existing struct (its
inner constructor is the ONLY constructor, deliberately, per the file's own header: *"defining an
inner constructor suppresses Julia's auto-generated (non-validating) constructors"*,
`Feeder.jl:53-55`). **This requires a new, parallel `MeshedFeeder{T}` struct** (new file, e.g.
`data/MeshedFeeder.jl`) reusing the existing `Bus`/`Branch` element structs (they carry no
radiality assumption themselves — `r`,`x`,`smax`/`vmin`,`vmax` are topology-agnostic,
`Feeder.jl:18-43`) but validated by a **new** `assert_connected` (drop the edge-count check,
keep the BFS reachability check, `topology.jl:81-107`'s BFS is directly reusable structurally)
— additive, `topology.jl` and `Feeder.jl` untouched.

The **model layer** is where the real new work is, and it is exactly where SEAM-01 already
anticipated the seam: `oracle.jl:81-84` states *"a future `MeshedFlow <: AbstractPowerFlow` plugs
in here and would bypass the `assert_radial` invariant"* — correct as far as it goes, but note
this SEAM-01 comment only anticipated the **`pf` (model) swap**, not the **`Feeder` (data)
swap** above; the milestone needs both, and the existing seam commentary is silent on the data
layer. `ConvexBranchFlow.contribute!`'s per-bus balance accumulation
(`ConvexBranchFlow.jl:213-227`) assumes a **directed parent→child** tree walk (`br.to == j` /
`br.from == j`, single path to root) — a cyclic network needs a genuinely different branch-flow
formulation (signed incidence over a cycle basis, or a bus-injection/line-flow model with loop
constraints), which is new model-math flagged for its own research pass, same caveat as axis 1.
Given the shared-machinery risk the milestone context names, **sequence axis 1's relaxation work
before axis 4's meshed relaxation** — axis 1 will already have produced a non-radial-exactness
certificate pattern (an exactness gate that is NOT the LinDistFlow-copy trick) that axis 4's
meshed formulation can reuse or adapt, rather than inventing two divergent non-radial
certification strategies independently.

**(b) 4Q-BESS reactive device → aggregator → `:Rq` — investigate point (d) directly.**
Confirmed: devices in the aggregatable contract return only `(; vars, p_inject, utility)` — **no
reactive term at all** (`devices/AbstractDevice.jl:58-64`; `PVBattery.jl:227-291` returns exactly
that 3-tuple). `Aggregator.contribute!` derives the entire `:Rq` injection **solely** from the
inelastic load's power factor, `-Pdc[t]*tanφ` (`devices/Aggregator.jl:147,167`) — it never reads
a device-level reactive quantity because none exists (thesis Assumption A3, DERs active-only,
cited explicitly at `Aggregator.jl:42-43`). Closing this gap requires, in order:

1. A **new** `AbstractDevice` (aggregatable variant) — e.g. `devices/FourQuadBESS.jl` — that
   extends `PVBattery`'s SOC/charge-discharge model with a genuine reactive decision `q[t]` and
   an apparent-power capability circle `p[t]²+q[t]² ≤ S²` (the SAME rotated/plain SOC idiom
   `ConvexBranchFlow` already uses for branch limits, `ConvexBranchFlow.jl:150-154,201-205` — a
   device-level cone, not a network one). Returns `(; vars, p_inject, q_inject, utility)` — a
   widened NamedTuple.
2. A **minimal, additive** change to `Aggregator.contribute!` (`Aggregator.jl:136-178`): add a
   `q_inject` accumulator alongside the existing `p_inject` one (mirrors lines 150-159
   structurally), reading `get(res, :q_inject, zero(AffExpr))` per device so **existing** devices
   (which return no `q_inject` key) are unaffected — byte-identical default behavior, additive
   field, not a breaking contract change.
3. **Live reactive dual-ascent** is a smaller lift than it first appears: the v2.1
   `reactive_consensus` scaffolding already promotes `qag_dso[j,t]` to a pinned `Parameter`
   coupling variable inside `DsoOpt` (`admm/solve_admm.jl:99-109` docstring; `qag_dso` stored
   under `ctx.meta[:qag_dso]`) — today it is deliberately **one-shot** (pinned once, certified
   once via `assert_no_slack`, never re-iterated, per the documented v2.1 decision "no live μ
   dual-ascent loop... a one-shot certified dual suffices", PROJECT.md Key Decisions). Making it
   "live" means **modifying `solve_admm.jl`'s outer loop** to add a μ-ascent step mirroring the
   existing λ-ascent line (`λ_j ← λ_j + ρ·R_{p,j}`, `solve_admm.jl:16` docstring / the analogous
   real update in the loop body) — a **targeted, reviewed modification** to the one file that
   already owns the ADMM loop, not a new orchestrator, since the μ update must interleave with
   the existing λ update inside the SAME iteration.

**Build-order note:** (b) (4Q-BESS + live μ) has NO dependency on (a) (meshed topology) — it
works today on radial `ConvexBranchFlow`/`DsoOpt`. Ship (b) independently of, and likely before,
(a); (a) is the harder, higher-risk half of this axis and shares machinery with axis 1.

### Axis 5 — Discrete/integer investment expansion

**Consumes:** `planning/master.jl`'s `BendersMaster` (continuous `y_inv`, `z`, epigraph
`α_op`/`α_x`, `build_master`, `add_optimality_cut!`/`add_feasibility_cut!`, `master.jl:1-116` and
onward) as the direct extension point — binary-expansion investment (thesis-referenced
`y_inv = Σ_k 2^k·b_k`) lands here.

**The PVAL-04 guard — investigate point (e) directly.** The guard is **exactly** built to make a
"conscious, scoped lift" reviewable, not to be redesigned:
`test/test_planning_noninteger.jl:25-131` runs a **registry** of 4 builder closures
(`build_planning_oracle`, `build_follower`, `build_master`, `build_shared_transmission`,
lines 36-65), asserting `isempty(offenders)` for `is_binary`/`is_integer` variables on each
(line 69-77), UNIONED with a **source-scan tripwire** over `src/planning/` (recursive,
docstring-aware regex scan, lines 99-113) and a **semantic channel** (every exported `build_*`
symbol not on a documented `operational_builders` allowlist, lines 120-129) that must together
equal the registry's key set (line 130). A conscious lift for axis 5 looks like:

1. **`planning/master.jl` gains binary/integer variables** (the actual investment-discretization
   work) — a direct modification, expected and scoped.
2. **`test_planning_noninteger.jl`'s registry is split**, not deleted: keep the guard live,
   unmodified, for `build_planning_oracle`/`build_follower`/`build_shared_transmission` (these
   three have no reason to ever carry integers — they are the operational oracle, the
   single-corridor follower, and the N-distributor shared corridor, none of which the PSR note's
   integer-expansion touches), and either (i) add a documented exemption for `build_master`
   specifically (a second registry, e.g. `integer_allowed = Dict("build_master" => ...)`, with a
   comment citing the axis-5 REQ-ID) or (ii) if the binary-expansion master becomes a
   **new**, separately-named builder (e.g. `build_master_integer`), add it as a **new** key to
   the semantic-channel allowlist rather than the continuous registry. Either way the
   **tripwire's own design already anticipated this exact moment** — it exists so a scoped
   change is a small, visible, reviewed diff to one test file, never a silent weakening.
3. `PVBattery`'s device-level no-binary guarantee (`PVBattery.jl:42-57`, thesis App. C) is a
   **completely separate invariant** (device QP convexity, not planning-layer investment
   integrality) and is untouched by this axis — do not conflate the two "no binaries" stories
   when writing the roadmap phase description.
4. **Integer/Lagrangian cuts** in the Benders loop (`planning/benders.jl`'s `solve_stackelberg!`
   and `add_optimality_cut!`/`add_feasibility_cut!` in `master.jl`) are new cut *kinds*
   (integer L-shaped / Lagrangian) layered beside the existing optimality/feasibility cuts
   (`master.jl:118-146` is the direct template for a new `add_integer_cut!` sibling function) —
   this is the axis's own genuinely new algorithmic surface and, per CLAUDE.md's own flagged
   risk ("the author flagged... integer-cut correctness as open concerns"), the axis most likely
   to need a dedicated model-correctness research pass before implementation, independent of this
   architecture mapping.

**HiGHS already supports MILP** (`select_optimizer(LP())`/`select_optimizer(MILP())` — the
solver factory, `src/solver/ProblemClass.jl`/`factory.jl`, was built problem-class-generic from
v1; adding a `MILP` problem class (if not already present) or reusing `LP()`'s HiGHS routing for
mixed-integer is a solver-factory-level, not master-level, concern — confirm the `ProblemClass`
enumeration includes (or trivially extends to) MILP before writing the master's binary variables.

---

## Cross-Cutting Findings

### (f) Scenario.jl golden-hash blast radius — the real shared risk of axes 2 & 3

`Scenario` (`experiments/Scenario.jl:92-214`) is a flat `Base.@kwdef` struct with an explicit,
**all-14-fields-positional** inner constructor (lines 108-123) — by design (documented at the
file header, lines 1-22) so `savename(s)` needs **zero** `DrWatson.default_allowed`
overloading, because every field is already a primitive DrWatson accepts. `store.jl`'s
`result_to_dict` calls `struct2dict(s)` — **literally every field of the struct** — into both
the persisted provenance dict and (via `scenario_filename`, `store.jl:37`) the on-disk filename
(`savename(s, "jld2"; digits=10)`). Two consequences:

1. **Any new field added to `Scenario` changes `savename(s)` for every scenario, including
   existing ones with all-default values on the new field** — because DrWatson's `savename`
   serializes the whole struct, not a diff against defaults. This does not corrupt anything
   (per-run JLD2s are gitignored, `store.jl:23`), but it means any test that constructs an
   expected filename independently, or a documentation example pinning a literal `savename(s)`
   string, will need re-verification. Grep confirms no test currently hardcodes a literal
   `savename` string (`test_experiments.jl:226` re-derives it from the same `Scenario`
   instance), so this specific risk is currently LOW in practice — but it is the reason v2.1
   explicitly avoided adding a `reactive_consensus::Bool` field to `Scenario` at all (confirmed:
   `grep reactive_consensus src/experiments/run.jl` returns **no hits** — the v2.1 feature was
   deliberately kept OUT of the `Scenario`/`run_scenario`/`sweep` pipeline entirely, exercised
   only via `solve_admm`'s own direct kwarg in tests, never through a declarative `Scenario`).
2. **Axes 2 and 3 cannot take the same shortcut.** MPC and stochastic scenarios are *exactly*
   what the declarative `Scenario` → `run_scenario` → `run_sweep` pipeline exists to express
   reproducibly (rolling-window length/step, scenario-tree branching factor/seed count are
   genuinely new experiment dimensions a researcher needs to sweep over, per the framework's own
   core value statement). Both axes **will** add fields to `Scenario` — e.g.
   `horizon_mode::Symbol = :day_ahead` (`:day_ahead`|`:rolling`) + `mpc_window::Int = 24` +
   `mpc_step::Int = 1` for axis 2, and `n_scenarios::Int = 1` + `scenario_seed_offset::Int = 0`
   (or similar) for axis 3 — each requiring: (i) a new field + kwdef default (backward-compatible
   for every existing call site), (ii) a new entry in the **positional** inner constructor
   signature AND its validation block AND its `return new(...)` call (three touch points inside
   one already-heavily-tested file), (iii) a corresponding branch in `materialize.jl`/`run.jl`
   dispatch (`strategy::Symbol` gains new valid values, mirroring the existing
   `SCENARIO_VALID_STRATEGIES` pattern, `Scenario.jl:30-33`), and (iv) awareness that
   `result_to_dict`'s `struct2dict(s)` sweep (`store.jl:53`) will pick the new fields up
   automatically (no change needed there) — but every OTHER existing scenario's stored
   filename/provenance dict shape changes shape too (new keys with default values appear).
   **Recommend doing axis 2's and axis 3's `Scenario` field additions together, in the same
   phase/plan, reviewed as one diff** — since both touch the identical three-point-touch
   pattern in the same file, splitting them across two separate phases doubles the review
   surface on the single most schema-fragile file in the codebase for no benefit.

### (g) Shared "window solve" abstraction across MPC / stochastic / Benders subproblems

Direct evidence that the codebase already treats "one subproblem, `Parameter`-pinned inputs,
re-solved without rebuild" as ONE reusable idiom, not three independent ones:

- `PlanningOracle` (`planning/subproblem.jl:30-69`): build once, `z[t]` a `Parameter`, re-solve
  via `set_parameter_value.(o.z, z_trial)` (Benders subproblem).
- `FollowerLP` (`planning/follower.jl:59-68`): build once, `z[t]` a `Parameter`, identical idiom
  (Benders subproblem, distinct model).
- `SharedTransmission` (`planning/coupling.jl:112-124,144`): build once, `z[i,t]` a `Parameter`
  over two indices, identical idiom (Nash best-response subproblem).
- `AgrOpt`/`DsoOpt` (`admm/solve_admm.jl`): build once, objective **coefficients** (not RHS)
  re-set via `set_objective_coefficient`/`set_rho!`, re-solved every ADMM iteration (a
  slightly different re-solve axis — coefficients, not a pinned RHS — but the same "build-once,
  mutate, never rebuild" discipline).

**A rolling-horizon MPC window IS structurally a Benders-style subproblem**: fixed topology/
devices, a `Parameter`-typed initial state (§ axis 2 above) and a `Parameter`-typed forecast
window, re-solved every step. **A stochastic-scenario subproblem is structurally the same
shape** if the extensive form is decomposed (rather than monolithic) — e.g. a per-scenario
recourse subproblem with `Parameter`-pinned first-stage decisions, exactly `PlanningOracle`'s
shape with `z` reinterpreted as the first-stage variable rather than the TSO-DSO coupling flow.

**Recommendation:** do not invent three bespoke re-solve idioms. Extract (or at minimum
document as) one shared internal pattern — a `BuildOnceParameterOracle`-style convention (not
necessarily a shared abstract type; Julia dispatch + documentation-level convention, matching how
`AgrOpt`/`DsoOpt`/`PlanningOracle`/`FollowerLP`/`SharedTransmission` already independently follow
the same shape without a common supertype) — and have MPC's `RollingWindowOracle` (axis 2) and
any decomposed stochastic subproblem (axis 3) follow it explicitly. This is a documentation/
convention deliverable, not new production code, and costs nothing to defer to whichever axis
ships first; whichever axis ships FIRST should write the convention down (a short "Build-once
Parameter-Oracle pattern" note, analogous to the existing per-file "RESEARCH Pattern N" comments)
so the second axis's implementer reuses it rather than re-deriving it.

---

## Suggested Build Order (dependency-driven)

1. **Axis 4b — 4Q-BESS + live reactive dual-ascent (radial).** No dependency on anything else in
   this milestone; reuses the v2.1 `reactive_consensus`/`qag_dso` scaffolding already in
   `solve_admm.jl` almost entirely as-is (promote one-shot → live ascent) plus one new additive
   device file. Lowest risk, fastest to ship, and exercises the "new device + widened Aggregator
   contract" pattern the other axes' device work (axis 2's `Parameter`-ized SOC) can reference.

2. **Axis 1 — Overvoltage-capable relaxation.** Independent of the Scenario-schema work; its
   main cost is model-math research (a new convex tightening + a new non-radial exactness
   certificate), which the roadmap should flag as needing its own deep-dive phase. Do this before
   axis 4a because axis 4a (meshed) explicitly shares relaxation-machinery risk with it — solving
   axis 1 first produces a reusable "non-radial exactness certificate" pattern.

3. **Axis 2 + Axis 3 (Scenario-schema work), together, one phase.** Both require the identical
   three-touch-point `Scenario.jl` extension (fields + positional constructor + validation) —
   doing them in the same phase means one reviewed diff to the schema-fragile file instead of
   two, and lets axis 3 (if decomposed) reuse axis 2's `Parameter`-pinned window-oracle
   convention (§g) directly. Axis 2 additionally requires the `PVBattery`/`Thermostatic`
   `Parameter`-ization (a small, isolated, reviewable device change) — do that as the first plan
   within this phase since axis 3 does not need it.

4. **Axis 4a — Meshed topology.** Sequenced after axis 1 (shares its relaxation-certificate
   pattern) and after axis 4b ships (so the 4Q-BESS device already exists for a meshed+4Q-BESS
   combined validation rung, per the milestone's own framing "Meshed formulation slot filled with
   its own relaxation/exactness treatment... four-quadrant BESS"). Highest architecture-plus-math
   risk in the milestone (new `MeshedFeeder` struct, new non-radial branch-flow formulation) —
   schedule last among the "network-facing" axes so its research/validation overrun, if any,
   does not block the others.

5. **Axis 5 — Integer investment expansion.** Fully independent of axes 1-4 (touches only
   `planning/`); can run in parallel with any of the above from a code-conflict standpoint. Order
   it last only because the milestone context flags integer-cut correctness as the single
   highest algorithmic-risk item (echoing the PSR source's own flagged "integer-cut correctness"
   concern) — shipping it last means the earlier axes' validated ladder rungs are not blocked
   waiting on the riskiest piece, and gives the most time to resolve cut-correctness before this
   axis's plan is written. It has no shared machinery with axes 1-4, so nothing is lost by
   deferring it.

**Explicit non-dependencies worth stating for the roadmapper:** axis 5 (planning/integer) shares
essentially zero files with axes 1-4 (operational/network) — it can be parallelized against any
of them without merge risk. Axis 4b (4Q-BESS/reactive) has no dependency on axis 4a (meshed) and
should not be gated behind it despite sharing a milestone-level name.

---

## Sources

- `.planning/PROJECT.md` (v3.0 milestone scope, requirements, prior Key Decisions table) — HIGH,
  primary source document.
- Direct code reads (all citations above are file:line from the actual v2.1 checkout):
  `src/TSODSO.jl`, `src/models/oracle.jl`, `src/data/Feeder.jl`, `src/data/topology.jl`,
  `src/powerflow/ConvexBranchFlow.jl`, `src/powerflow/ACPowerFlow.jl`, `src/devices/
  AbstractDevice.jl`, `src/devices/PVBattery.jl`, `src/devices/Aggregator.jl`,
  `src/experiments/Scenario.jl`, `src/experiments/materialize.jl`, `src/experiments/store.jl`,
  `src/core/ModelContext.jl`, `src/models/exactness.jl`, `src/models/welfare_solve.jl`,
  `src/admm/solve_admm.jl`, `src/planning/master.jl`, `src/planning/coupling.jl`,
  `src/planning/follower.jl`, `src/planning/subproblem.jl`,
  `test/test_planning_noninteger.jl`, `test/test_experiments.jl`.
- No external ecosystem research was needed for this milestone — it is a pure internal
  architecture-integration study of an existing, already-researched (CLAUDE.md) codebase.

---
*Architecture research for: TSO-DSO v3.0 Research Extension Rungs*
*Researched: 2026-07-26*

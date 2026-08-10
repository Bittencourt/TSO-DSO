# Phase 23: Meshed Networks - Pattern Map

**Mapped:** 2026-08-10
**Files analyzed:** 11 new + 4 modified
**Analogs found:** 11 / 11

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|----------------|
| `src/data/MeshedFeeder.jl` | model (data) | CRUD (construction/validation) | `src/data/Feeder.jl` | exact |
| `src/data/mesh_topology.jl` | utility (validation) | transform | `src/data/topology.jl` | exact |
| `src/powerflow/MeshedFlow.jl` | service (formulation) | transform (delegated model-build) | `src/powerflow/RestrictedBranchFlow.jl` | exact |
| `src/models/mesh_angle_certificate.jl` | model (certificate/post-processing) | transform | `src/models/restriction_exactness.jl` (structure) + `src/models/ac_oracle.jl` (BFS algorithm) | exact (composite) |
| `docs/literate/meshed_reactive_price.jl` | docs (literate rung page) | batch/report | `docs/literate/stochastic_pv_demand.jl` | exact |
| `test/fixtures_mesh.jl` (name: Claude's discretion) | test fixture (`@testmodule`) | CRUD (fixture construction) | `test/fixtures_phase22.jl` | exact |
| `test/test_mesh_feeder.jl` | test | CRUD | `test/test_topology.jl` | role-match |
| `test/test_mesh_flow.jl` | test | request-response (solve) | `test/test_welfare_solve.jl` / `test/test_factory.jl` | role-match |
| `test/test_mesh_angle_certificate.jl` | test | transform | `test/test_ac_oracle.jl` / `test/test_exactness.jl` | exact |
| `src/TSODSO.jl` (MODIFIED) | config (include graph) | — | itself, prior include-order additions (e.g. `RestrictedBranchFlow.jl`, `restriction_exactness.jl` entries) | exact |
| `docs/make.jl` + `docs/src/api.md` (MODIFIED) | config (docs wiring) | — | `restricted_branch_flow.jl` / `stochastic_pv_demand.jl` entries in both files | exact |

## Pattern Assignments

### `src/data/MeshedFeeder.jl` (model/data, CRUD)

**Analog:** `src/data/Feeder.jl` (full file read, 93 lines)

**Struct + validation-at-construction pattern** (lines 57-72 of `Feeder.jl`):
```julia
struct Feeder{T <: Real}
    buses::Vector{Bus{T}}
    branches::Vector{Branch{T}}
    root::Int

    function Feeder{T}(
        buses::Vector{Bus{T}},
        branches::Vector{Branch{T}},
        root::Int,
    ) where {T <: Real}
        feeder = new{T}(buses, branches, root)
        assert_radial(feeder.buses, feeder.branches, feeder.root)  # DATA-02 topology invariant
        assert_magnitudes(feeder)                                  # INFRA-05 magnitude invariant
        return feeder
    end
end
```

**Convenience outer constructor** (lines 87-91):
```julia
Feeder(
    buses::Vector{Bus{T}},
    branches::Vector{Branch{T}},
    root::Integer,
) where {T <: Real} = Feeder{T}(buses, branches, Int(root))

export Bus, Branch, Feeder
```

**Copy for `MeshedFeeder`:** identical shape (D-01/A4 — `solve_welfare` duck-types on
`buses`/`branches`/`root` field names, so `MeshedFeeder` MUST expose the same field names).
Swap `assert_radial` for the new `assert_connected` inside the inner constructor; reuse
`assert_magnitudes` verbatim (INFRA-05, unchanged — it has no topology dependence). `Bus`/
`Branch` structs are reused as-is from `Feeder.jl` — no new element types are needed.

**Do NOT touch `Feeder.jl` itself** (D-01/MESH-01 lock) — `MeshedFeeder` is a wholly separate
struct/file, never a subtype or field of `Feeder`.

---

### `src/data/mesh_topology.jl` (utility/validation, transform)

**Analog:** `src/data/topology.jl` (full file read, 128 lines)

**BFS connectivity check to copy verbatim, minus the tree-count shortcut** (lines 81-107):
```julia
# (4) Connectivity: BFS from root over an undirected adjacency list.
#     connected ∧ (B == N-1) ⟺ tree, so no cycle detection is needed.
adj = [Int[] for _ in 1:N]
for br in branches
    push!(adj[br.from], br.to)
    push!(adj[br.to], br.from)
end
seen = falses(N)
seen[root] = true
reached = 1
queue = [root]
while !isempty(queue)
    u = pop!(queue)
    for v in adj[u]
        if !seen[v]
            seen[v] = true
            reached += 1
            push!(queue, v)
        end
    end
end
reached == N || throw(
    ArgumentError(
        "Non-radial feeder: graph is disconnected from root $root " *
        "($reached/$N buses reachable).",
    ),
)
```

**What to DROP for `assert_connected`:** the check at lines 40-44
(`B == N - 1 || throw(ArgumentError("Non-radial feeder: ..."))`) — this is the tree-specific
edge-count theorem and must NOT appear in `assert_connected` (a mesh has `nB ≥ N`, not
`nB == N-1`). Everything else — root-range check (lines 46-47), positional-id convention
check (lines 49-55), branch-endpoint range check (lines 57-65), sparse incidence build
(lines 67-79), single-root-flag checks (lines 109-123) — carries over unchanged, since none
of it is tree-specific (per RESEARCH's "Don't Hand-Roll" table).

**Function signature/return contract to mirror:**
```julia
function assert_connected(buses, branches, root)
    # ... same checks minus the B == N-1 theorem ...
    return A   # N × B sparse incidence, same convention (+1 from, -1 to)
end

export assert_connected
```

**No `Graphs.jl` dependency** — the file's own header comment (`topology.jl:9-10`) states
the project's explicit "no Graphs.jl" convention; `mesh_topology.jl` must follow the same
constraint (RESEARCH "Don't Hand-Roll" table).

---

### `src/powerflow/MeshedFlow.jl` (service/formulation, transform — delegated model-build)

**Analog:** `src/powerflow/RestrictedBranchFlow.jl` (full file read, 293 lines) — specifically
its delegation call, NOT its OPF-m constraint-adding body (MeshedFlow's delegation has an
EMPTY delta at the constraint-writing level per RESEARCH's "Critical codebase finding").

**Delegation pattern to copy** (lines 174-175, the ONLY part of `RestrictedBranchFlow`'s
`contribute!` that is directly reusable — the rest of that function, lines 176-286, is
`RestrictedBranchFlow`-specific OPF-m machinery that `MeshedFlow` does NOT need):
```julia
function contribute!(pf::RestrictedBranchFlow, ctx::ModelContext, feeder; T::Int = 1)
    contribute!(ConvexBranchFlow(), ctx, feeder; T = T)
    # ... pf's own additional constraints (NOT applicable to MeshedFlow) ...
```

**Provenance stash pattern to copy** (lines 283-285):
```julia
    ctx.meta[:restriction_ε] = pf.ε             # D-08 provenance
    ctx.meta[:formulation] = :RestrictedBranchFlow   # D-08 provenance
    return ctx
end
```
For `MeshedFlow`: stash `ctx.meta[:formulation] = :MeshedFlow` only (no `ε`-equivalent field
exists for this formulation).

**problem_class trait registration** (line 291, `RestrictedBranchFlow.jl`):
```julia
problem_class(::RestrictedBranchFlow) = SOCP()
```
Copy identically for `MeshedFlow`: `problem_class(::MeshedFlow) = SOCP()` — same tight-gap
Clarabel factory `ConvexBranchFlow`/`RestrictedBranchFlow` already use (`src/solver/problem_class_trait.jl:36`
generic `QP()` fallback is overridden by this more-specific method, per that file's own Holy-trait
dispatch documented at lines 20-36).

**Export line pattern** (line 293): `export MeshedFlow` (plus `contribute!` is already
exported from `AbstractPowerFlow.jl`, no re-export needed).

**RESULT — `MeshedFlow.contribute!`'s expected full shape** (per RESEARCH's own "Code
Examples" section, cross-checked against the `RestrictedBranchFlow` delegation precedent
above):
```julia
function contribute!(pf::MeshedFlow, ctx::ModelContext, feeder; T::Int = 1)
    contribute!(ConvexBranchFlow(), ctx, feeder; T = T)   # byte-identical constraint set
    ctx.meta[:formulation] = :MeshedFlow                  # provenance for the certificate
    return ctx
end
problem_class(::MeshedFlow) = SOCP()
export MeshedFlow
```

**Struct definition analog** — `RestrictedBranchFlow`'s inner-constructor validation pattern
(lines 114-134) is NOT needed here (`MeshedFlow` has no field/parameter to validate, per
CONTEXT.md's discretion list) — a plain `struct MeshedFlow <: AbstractPowerFlow end` singleton
suffices, mirroring `ConvexBranchFlow`'s own zero-field struct (confirmed via
`src/powerflow/ConvexBranchFlow.jl:116`, `function contribute!(::ConvexBranchFlow, ...)` —
positional, unnamed argument, i.e. no field access anywhere in that file's `contribute!`).

**AbstractPowerFlow contract to honor** (`src/powerflow/AbstractPowerFlow.jl:23-34`):
```julia
"""
    contribute!(pf::AbstractPowerFlow, ctx, feeder; T::Int=1)
...a formulation `pf` adds its per-bus, per-time branch/voltage terms into
`ctx.residuals[:Rp]` — and ... `ctx.residuals[:Rq]` — via the INDEXED
`add_to_residual!(ctx, :Rp, bus, t, expr)` seam...
"""
function contribute! end
```

---

### `src/models/mesh_angle_certificate.jl` (model/certificate, transform)

**Analogs (composite — algorithm from one file, contract/reporting shape from another):**

1. **BFS/signed-adjacency algorithm — `src/models/ac_oracle.jl`** (`recover_voltage_angles`,
   lines 66-112, read in full). This is the base BFS to GENERALIZE, not call unmodified
   (RESEARCH's own explicit warning: `recover_voltage_angles` is "silently loop-blind").

   **Signed adjacency construction to copy verbatim** (lines 76-80):
   ```julia
   children = [Tuple{Int, Int}[] for _ in 1:N]
   for (b, br) in enumerate(feeder.branches)
       push!(children[br.from], (br.to, b))
       push!(children[br.to], (br.from, -b))
   end
   ```

   **BFS-with-visited-guard to copy, ADDING chord tracking** (lines 89-109 — the part to
   MODIFY, per RESEARCH's exact prescription: track which branches are `tree_edges[b]`
   instead of silently discarding the ones that hit an already-visited node):
   ```julia
   visited = falses(N)
   visited[feeder.root] = true
   queue = [feeder.root]
   while !isempty(queue)
       i = pop!(queue)
       for (j, bsigned) in children[i]
           visited[j] && continue     # <-- this line is WHERE the chord is silently dropped
           b = abs(bsigned)
           br = feeder.branches[b]
           z = Complex(br.r, br.x)
           S = bsigned > 0 ? Complex(value(pv.P[b, t]), value(pv.Q[b, t])) :
                              -Complex(value(pv.P[b, t]), value(pv.Q[b, t]))
           Vphasor[j, t] = Vphasor[i, t] - z * conj(S) / conj(Vphasor[i, t])
           visited[j] = true
           push!(queue, j)
       end
   end
   ```
   New certificate must ALSO record, for every branch, whether it was ever used as a tree
   edge (`tree_edges[b] = true` at the point `visited[j] = true` fires for that branch) —
   any branch never marked is a chord. This is a NEW, small addition to the loop above, not
   a rewrite of the phasor recursion itself.

   **Chord-closure residual — the genuinely new piece** (no existing analog; algorithm
   spec lifted directly from RESEARCH's "Exact algorithm" section and "Code Examples" skeleton):
   for each chord `b=(f,t)`, predict `V_t,predicted = V_f,tree - z_b·conj(S_b)/conj(V_f,tree)`
   using the SAME phasor formula as the tree-edge recursion above but evaluated on the
   chord's own `(P_b,Q_b)`, then compare to `V_t,tree` (the BFS-recovered value already
   assigned to bus `t`). `residual = |V_t,predicted - V_t,tree|`.

2. **Certificate contract shape (status field, report/throw kwarg, provenance stash,
   docstring tolerance-provenance table) — `src/models/restriction_exactness.jl`**
   (`assert_restriction_exact!`, full file read, 325 lines). MESH-03/D-05 is the deliberate
   EXCEPTION to this family's throw-by-default convention (report-by-default instead) —
   copy the STRUCTURE, invert the DEFAULT.

   **Report/throw branching pattern to copy** (lines 300-313, note the `report` kwarg
   controls `@warn` vs `error`, exactly the mechanism to reuse — only the DEFAULT value of
   `report` flips from `false` (this family) to `true` (MESH-03, D-05)):
   ```julia
   if !ac_feasible
       msg = "RestrictedBranchFlow solution NOT certified PHYSICALLY AC-feasible: ..."
       if report
           @warn msg
       else
           error(msg)
       end
   end
   ```

   **Provenance stash pattern to copy** (lines 294-298, D-07/D-08 precedent explicitly
   cited in CONTEXT.md):
   ```julia
   ctx_restricted.meta[:price_provenance] = (;
       formulation = get(ctx_restricted.meta, :formulation, :unknown),
       certificate = :assert_restriction_exact!,
       status = ac_feasible ? :certified_convex_dual : :cert_failed,
   )
   ```
   For the mesh certificate: `status = recoverable ? :angle_certified : :angle_unrecoverable`
   (illustrative symbols per RESEARCH — Claude's discretion on exact names), `certificate =
   :certify_angle_recoverable!` (or whatever name is chosen), `formulation` READ from
   `ctx.meta[:formulation]` the SAME way (never hardcoded — same "no fabricated provenance"
   review rule as `restriction_exactness.jl:124-131` documents).

   **Scale-free combined-bound tolerance idiom to copy** (WR-01 philosophy, lines 76-77 —
   the exact shape, never the exact numbers, per D-08's explicit "never reused from sibling
   certificates" instruction):
   ```julia
   gap ≤ cone_atol + cone_rtol · max(|l·v|, |P²+Q²|)
   ```
   For the mesh certificate: `residual ≤ atol + rtol · scale` where `scale` is a
   fixture-appropriate magnitude (e.g. max chord voltage magnitude) — MEASURE atol/rtol
   fresh on the committed loop fixture (D-08), do not copy `restriction_exactness.jl`'s
   `5e-4`/`2e-7` or `ac_oracle.jl`'s `1e-4`/`1e-6`.

   **Tolerance-provenance docstring section to mirror the SHAPE of** (lines 150-198,
   `# Tolerance provenance` — measured floor, safety multiplier, resulting default, citation
   of which fixture/case the measurement came from). RESEARCH's own empirical spike table
   (uniform R/X ≈1e-5 recoverable vs heterogeneous R/X ≈1.5e-3–5.8e-3 unrecoverable) is the
   MODEL for this table's shape but NOT its numbers — D-08 requires re-measurement on the
   actual committed fixture.

**Export line pattern** (line 324 of `restriction_exactness.jl`):
`export assert_restriction_exact!` → mirror as
`export certify_angle_recoverable!` (name per Claude's discretion).

---

### `docs/literate/meshed_reactive_price.jl` (docs, batch/report)

**Analog:** `docs/literate/stochastic_pv_demand.jl` (full file read, 148 lines) — freshest
literate rung page (Rung 9), explicitly cited in CONTEXT.md/RESEARCH.md as the pattern to
reuse.

**Structural pattern to copy:**
- Opening comment block (`# # Rung N — Title`, lines 1-14) — frames what is NEW relative to
  every prior rung page, states the primary output up front.
- `using TSODSO` (line 16) then a `# ##` subsection building the `Scenario`/fixture with an
  explanatory comment block citing WHY each parameter value was chosen (lines 18-56) — the
  meshed page should follow the same "explain every literal, cite the honest-gap fixture
  design (D-02/D-10)" discipline rather than a bare numbers dump.
- Each subsequent `# ##` numbered section runs ONE live computation and immediately prints
  a bare expression (Documenter's `@example`-block convention — every solve/computation is
  followed by a bare value/expression on its own line, e.g. lines 69-73, 82-83, 93, 102,
  113, 121, 125):
  ```julia
  r = run_stochastic(s)
  length(r.in_sample.dadp)
  # `length(r.in_sample.dadp) == s.stoch_S == 5`, confirmed live above.
  ```
- Closing `# ## Finding` section (lines 127-147) — an HONEST, numbers-cited narrative
  (explicitly notes both a numerical-sensitivity finding AND the sign/scale of the headline
  result) — the meshed page's Finding section is where D-10's honest-gap outcome (if the
  fixture profile shown is the heterogeneous/unrecoverable one) must be stated exactly this
  plainly, never smoothed over.

**Combining pattern (MESH-06's specific content, no single existing page does this exact
combination, but each piece has a precedent elsewhere):**
- Build `MeshedFeeder` + `MeshedFlow()`, call `solve_welfare` (unchanged entry point, per
  RESEARCH's "Critical codebase finding: solve_welfare needs NO sibling entry point").
- Call the new `certify_angle_recoverable!` and print its `status`/`recoverable` fields
  (mirrors how `docs/literate/restricted_branch_flow.jl` — same directory, same family —
  would print `assert_restriction_exact!`'s returned NamedTuple fields; not read in full
  here since `stochastic_pv_demand.jl` already demonstrates the identical "call, then print
  fields" idiom).
- Reuse `FourQuadBESS`/live `:balance_q` duals for the reactive-price demonstration exactly
  as already shipped in Phase 19 (no new device code — RESEARCH explicitly confirms this).

---

### `test/fixtures_mesh.jl` (test fixture `@testmodule`, CRUD)

**Analog:** `test/fixtures_phase22.jl` (full file read, 185 lines) — freshest fixture-module
precedent, explicitly named in the task prompt.

**`@testmodule` structural pattern to copy** (lines 1-42, 170-184 — header comment
explaining self-containment contract, constants block, `export` list at the bottom):
```julia
@testmodule Phase22Fixtures begin
    using TSODSO
    const T = 6
    const SEED_STOCH = 20260809
    # ... named constants for every fixture parameter (never bare literals downstream) ...
    export T, S_INSAMPLE, ..., stoch_feeder, stoch_scenario_aggregators
end
```

**Feeder-builder-as-function pattern to copy** (lines 102-119, `stoch_feeder`):
```julia
function stoch_feeder()
    buses = [
        Bus(1, 0.95, 1.05, true),
        Bus(2, 0.95, 1.05, false),
    ]
    branches = [
        Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT),
    ]
    return Feeder(buses, branches, 1)
end
```
For the mesh fixture: build TWO named constructors (or one constructor with a
`profile::Symbol` kwarg) returning a `MeshedFeeder` — one for the "uniform" R/X profile
(recoverable branch) and one for "heterogeneous" R/X (unrecoverable branch), per D-02/D-10's
"single committed fixture with a togglable impedance profile" design. Mirrors this
`stoch_feeder()` shape but swaps `Feeder(...)` for `MeshedFeeder(...)` and adds one extra
branch closing the loop (3-4 bus single loop, per D-02).

**Self-containment discipline to copy** (header comment, lines 11-14): the mesh fixture
module must make NO top-level call to any not-yet-defined symbol — every builder takes
arguments (or none) and is called by the consuming `@testitem`, never evaluated at
module-load time.

**Naming convention to mirror:** `Phase22Fixtures` → name the mesh module e.g.
`MeshFixtures` or `Phase23Fixtures` (Claude's discretion, consistent with the
`Phase{N}Fixtures` convention this file and its siblings (`fixtures_phase19.jl`,
`fixtures_phase21.jl`) establish).

---

### `test/test_mesh_feeder.jl`, `test/test_mesh_flow.jl`, `test/test_mesh_angle_certificate.jl` (tests)

**Analogs:** `test/test_topology.jl` (structural/connectivity assertions on `Feeder`),
`test/test_welfare_solve.jl` (solve-and-check-termination-status pattern), `test/test_ac_oracle.jl`
(post-processing-certificate assertion pattern). Not read in full (RESEARCH's own "Phase
Requirements → Test Map" table already specifies the exact behavior each file must assert —
see RESEARCH.md's "Validation Architecture" section, reproduced in CONTEXT for the planner);
these three existing test files are the STRUCTURAL analogs for "how a `@testitem` in this
codebase is shaped" (setup=[FixtureModule], `using Test`, `@testitem "..." begin ... end`),
consistent with the project's TestItems convention documented in `test/runtests.jl`
(`TestItemRunner` auto-discovers every `@testitem` under `test/` — no manual `include` list
to maintain in `runtests.jl`).

---

### `src/TSODSO.jl` (MODIFIED — include-graph wiring)

**Pattern:** every new seam file is wired with a comment citing its owning plan and any load-order
constraint, exactly like the existing entries for `RestrictedBranchFlow.jl` and
`restriction_exactness.jl`:
```julia
# --- Gan-Low OPF-m restricted formulation, with optional OPF-ε margin (owned by plan
# 20-02, OVR-01) --- included right after ACPowerFlow.jl: it delegates to
# ConvexBranchFlow.contribute! and must load after it.
include("powerflow/RestrictedBranchFlow.jl")
...
# --- Restricted-SOCP AC-feasibility + optimality-loss certificate (owned by plan 20-03, OVR-02) ---
# Must load AFTER models/ac_oracle.jl: assert_restriction_exact! calls assert_ac_exact! internally.
include("models/restriction_exactness.jl")
```
**Apply to Phase 23:**
- `include("data/MeshedFeeder.jl")` and `include("data/mesh_topology.jl")` — place beside
  `data/Feeder.jl`/`data/topology.jl` (lines 17-19 currently); `mesh_topology.jl`'s
  `assert_connected` must be defined before `MeshedFeeder.jl`'s inner constructor calls it
  (same ordering convention `Feeder.jl`/`topology.jl` already use: `assert_radial` is
  included AFTER `Feeder.jl` per that file's own header comment, lines 11-14 — resolved by
  Julia's call-time/world-age binding, not include order; the SAME reasoning applies here).
- `include("powerflow/MeshedFlow.jl")` — place AFTER `ConvexBranchFlow.jl` (line 47) since it
  delegates to it, mirroring `RestrictedBranchFlow.jl`'s own positioning comment (lines 54-57).
- `include("models/mesh_angle_certificate.jl")` — place AFTER `models/ac_oracle.jl` (line 96),
  mirroring `restriction_exactness.jl`'s own "Must load AFTER models/ac_oracle.jl" comment
  (lines 98-100), since it generalizes that file's BFS.

---

### `docs/make.jl` + `docs/src/api.md` (MODIFIED — docs wiring)

**Pattern (`docs/make.jl`):** append the new literate source filename to the `for src in (...)`
tuple (lines 20-40) with a `# NEW: ...` comment, and add a matching `"... " => "generated/....md"`
entry to the `pages` list's `"Models"` array (lines 66-81) — exact precedent, lines 38-39:
```julia
"mpc_rolling_horizon.jl",   # NEW: Rung 8 MPC / rolling-horizon RTP closed loop (MPC-01..04)
"stochastic_pv_demand.jl", # NEW: Rung 9 Stochastic PV/Demand Uncertainty (STOCH-01..04)
```
and lines 79-80:
```julia
"Rung 8: MPC / Rolling-Horizon RTP" => "generated/mpc_rolling_horizon.md", # from mpc_rolling_horizon.jl
"Rung 9: Stochastic PV/Demand Uncertainty" => "generated/stochastic_pv_demand.md",
```

**Pattern (`docs/src/api.md`):** append the new `src/` files to the appropriate existing
`@autodocs` `Pages = [...]` block, or add a new subsection if the new files don't fit an
existing grouping. `MeshedFeeder.jl`/`mesh_topology.jl` extend the "Network Data Model" block
(line 45); `MeshedFlow.jl` extends the "Power-Flow Formulations" block (line 69);
`mesh_angle_certificate.jl` extends the "Models & Centralized Solve" block (line 77). All
THREE blocks already exist — no new `## ` subsection is needed (unlike Stochastic/MPC, which
got their own subsections because they introduced a wholly new subsystem directory). Recall
`checkdocs = :exports` (docs/make.jl line 100) will FAIL the build if any newly-exported
symbol's docstring is not surfaced by one of these blocks — this wiring is not optional
polish.

---

## Shared Patterns

### Delegation over duplication (peer `AbstractPowerFlow` formulation)
**Source:** `src/powerflow/RestrictedBranchFlow.jl:174-175`
**Apply to:** `src/powerflow/MeshedFlow.jl` — `contribute!` calls
`contribute!(ConvexBranchFlow(), ctx, feeder; T = T)` FIRST, adds nothing else at the
constraint-writing level (RESEARCH's "Critical codebase finding": `ConvexBranchFlow` is
already graph-generic).

### `problem_class` trait routing (never a solver name in a model)
**Source:** `src/solver/problem_class_trait.jl:36` (generic `QP()` fallback) +
`src/powerflow/ConvexBranchFlow.jl` / `RestrictedBranchFlow.jl:291` (`SOCP()` override)
**Apply to:** `src/powerflow/MeshedFlow.jl` — `problem_class(::MeshedFlow) = SOCP()`.

### Certificate provenance stash (`ctx.meta[:price_provenance]` / `ctx.meta[:formulation]`)
**Source:** `src/models/restriction_exactness.jl:294-298` (status field, read-not-hardcode
formulation) and `src/powerflow/RestrictedBranchFlow.jl:283-284` (the `contribute!`-side
`ctx.meta[:formulation]` write every certificate later reads)
**Apply to:** `MeshedFlow.contribute!` (write `:formulation`) and
`mesh_angle_certificate.jl`'s certificate function (read `:formulation`, write
`:price_provenance` with a `status` field keyed on `recoverable`).

### Report-vs-throw kwarg branching
**Source:** `src/models/restriction_exactness.jl:300-313`
**Apply to:** `mesh_angle_certificate.jl`'s certificate — SAME `if report; @warn; else;
error; end` shape, but DEFAULT flipped to `report::Bool = true` (D-05's deliberate,
documented divergence from this family's throw-by-default).

### Signed bidirectional branch adjacency (orientation-safe traversal)
**Source:** `src/models/ac_oracle.jl:76-80` (`recover_voltage_angles`) — identical
construction also appears at `recover_lossfree_shadow_voltage` (lines 189-193) and
`RestrictedBranchFlow.contribute!` (lines 198-202)
**Apply to:** `mesh_angle_certificate.jl` — reuse this exact `children[i]` construction,
never re-derive it; the CR-01 lesson (never assume a stored `Branch(from,to)` points
parent→child) applies identically to the new chord-tracking BFS.

### Scale-free combined-bound tolerance (`atol + rtol·scale`), independently measured
**Source:** every existing certificate — `src/models/exactness.jl` (`assert_socp_exact!`,
not read in full this session but cited throughout `ac_oracle.jl`/`restriction_exactness.jl`),
`src/models/ac_oracle.jl:328-332` (`assert_ac_exact!`), `src/models/restriction_exactness.jl:262-263`
**Apply to:** the mesh angle-recoverability certificate's `recoverable` decision — SAME
shape, tolerance VALUES measured fresh on the committed fixture (D-08), never copied.

### TestModule fixture self-containment + named constants
**Source:** `test/fixtures_phase22.jl:11-14` (self-containment contract), `:42-55` (named
constants block)
**Apply to:** the new mesh fixture module — no bare numeric literals in downstream
`@testitem`s; every fixture parameter gets a named constant.

### Literate rung page: build → run → print-bare-expression → Finding section
**Source:** `docs/literate/stochastic_pv_demand.jl` (full-file structural pattern, see above)
**Apply to:** `docs/literate/meshed_reactive_price.jl`.

## No Analog Found

None — every file in RESEARCH.md's "Recommended Project Structure" has at least a
role-match (and in most cases an exact-match) analog already in the codebase. This phase's
"new model-math" (RESEARCH's own summary) is concentrated in the angle-recoverability
certificate's chord-closure residual computation, which has no direct prior analog as a
WHOLE function, but its two constituent halves (signed BFS traversal; certificate
report/throw + provenance contract) are both directly modeled on existing code, as detailed
above.

## Metadata

**Analog search scope:** `src/data/`, `src/powerflow/`, `src/models/`, `src/solver/`,
`test/`, `docs/literate/`, `docs/make.jl`, `docs/src/api.md`, `src/TSODSO.jl`.
**Files scanned (read in full or targeted range):** `src/powerflow/RestrictedBranchFlow.jl`,
`src/powerflow/AbstractPowerFlow.jl`, `src/powerflow/ConvexBranchFlow.jl` (lines 1-60,
100-234), `src/data/Feeder.jl`, `src/data/topology.jl`, `src/models/ac_oracle.jl`,
`src/models/restriction_exactness.jl`, `src/solver/problem_class_trait.jl`,
`test/fixtures_phase22.jl`, `docs/literate/stochastic_pv_demand.jl`, `docs/make.jl`,
`docs/src/api.md`, `src/TSODSO.jl`.
**Pattern extraction date:** 2026-08-10

# Phase 14: Validation-Oracle Regression Hardening & Docs - Pattern Map

**Mapped:** 2026-07-24
**Files analyzed:** 7 new + 2 modified
**Analogs found:** 7 / 7

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|--------------------|------|-----------|-----------------|---------------|
| `test/fixtures_planning.jl` | test-fixture (`@testmodule`, constants) | CRUD (golden-value storage/lookup) | `test/fixtures_phase4.jl` | exact (same "computed golden, commented" convention) |
| `test/test_planning_goldens.jl` | test (regression) | request-response (build → solve → assert) | `test/test_acceptance.jl` (golden-gating structure) + `test/test_planning_certification.jl` (gate-then-value pattern) + `test/test_planning_nash.jl` (N=2 fixture/golden) | exact |
| `test/test_planning_noninteger.jl` (no-binaries guard) | test (semantic invariant/guard) | transform (build model → introspect variables) | `test/test_planning_coupling.jl` lines 237-252 (`SharedTransmission`-only guard) + `test/test_planning_nash.jl` lines 257-321 (companion check) | role-match (extends existing partial pattern to 4 builders) |
| `docs/literate/stackelberg_benders.jl` | docs (Literate page) | request-response (build → solve → display) | `docs/literate/admm.jl` | exact (rung-ladder Literate convention) |
| `docs/literate/nash_diagonalization.jl` | docs (Literate page) | request-response (build → solve → display) | `docs/literate/admm.jl` (iteration/decomposition narrative) + `docs/literate/pricing_dlmp.jl` (decomposition/table narrative) | exact |
| `docs/make.jl` (edit) | config (build pipeline wiring) | batch (loop over Literate sources + pages tree) | itself (existing `for src in (...)` loop + `pages` array) | exact (in-place edit, not a new-file analog) |
| `docs/src/api.md` (edit) | config (Documenter `@autodocs` page) | batch (docstring aggregation) | existing sections, e.g. "ADMM Decomposition" (lines 88-94) — BUT note the `Order` diff required | role-match (structure identical; `Order` list must differ) |

## Pattern Assignments

### `test/fixtures_planning.jl` (test-fixture, CRUD/golden-storage)

**Analog:** `test/fixtures_phase4.jl`

**Module shape** (lines 1-29, `test/fixtures_phase4.jl`):
```julia
# test/fixtures_phase4.jl
#
# Shared Phase-4 test fixture module (Wave 1). A TestItems `@testmodule` that the
# Phase-4 `@testitem`s consume via `setup=[Phase4Fixtures]`. ...
#
# CONTRACT (threat T-04-08): this module DEFINES functions and consts ONLY — it makes NO
# top-level call to any symbol filled by a later Phase-4 wave ...
# REPRODUCIBILITY (threat T-04-06): every profile / aggregator flows from a seeded
# `generate_profiles` (StableRNGs), so the high-PV stress fixture regenerates bit-for-bit.

@testmodule Phase4Fixtures begin
    using TSODSO

    const T = 24
    const BATT_λ_MIN = 3.8
    ...
    export T, mem_price_profile, temperature_profile, ...
end
```

**Golden-value convention** — plain top-level `const` with a rationale comment per value
(mirrors `fixtures_phase4.jl`'s `GROUND_LOAD_SCALE`/`GROUND_PV_SCALE` documented-calibration
comments, lines 235-258, and matches the exact literal values already verified in
`test/test_planning_certification.jl` lines 69-74 and `test/test_planning_nash.jl` lines
257-293):
```julia
# N=1 certified Stackelberg equilibrium (Phase 11 BilevelJuMP certification, see
# test/test_planning_certification.jl BilevelCertFixture) — RE-DERIVED hand enumeration,
# NOT 11-01-PLAN.md's original (incorrect) y*=1.0/z*=1.0/-0.2.
const N1_Y_HAND = 0.7
const N1_Z_HAND = 0.7
const N1_OBJ_HAND = -0.245

# N=2 hand-checked congested Nash equilibrium (Phase 13, symmetric toy fixture:
# build_shared_transmission N=2 T=1 corridor_cap=2.0 x_inv_max=[0.3,0.3] c_inv=[1.0,1.0]
# c_op=[[0.5],[0.5]]) — see test/test_planning_nash.jl lines 257-321 for the derivation.
const N2_Z_HAND = [0.6, 0.6]
const N2_XINV_HAND = [0.3, 0.3]
```

**Decision needed at plan time (per CONTEXT.md Claude's Discretion):** whether to make this a
`@testmodule` (like `fixtures_phase4.jl`) or a plain include-file of bare `const`s — CONTEXT.md
says "matches the existing `fixtures_phaseN.jl` computed-golden convention", and
`fixtures_phase4.jl` IS a `@testmodule`; follow that shape for consistency with `setup =
[...]` consumption by `test_planning_goldens.jl`.

---

### `test/test_planning_goldens.jl` (test, request-response gate-then-value)

**Analog 1 (golden-gating structure):** `test/test_acceptance.jl`

**Header/consolidation-without-duplication pattern** (lines 1-22):
```julia
# test/test_acceptance.jl
#
# Seam: the SC3 v1 acceptance gate (EXP-04) — the single consolidated end-to-end proof ...
# This file does NOT introduce any new solve path, fixture, or tolerance: it calls the SAME
# real entrypoints ... and REUSES their already-pinned goldens and tolerances verbatim
# (CONTEXT.md lock: never invent new/looser acceptance-specific thresholds).
```

**Gate-first-then-golden pattern** (lines 33-54, structurally what PVAL-02 requires: exactness
check BEFORE the pinned golden assertion):
```julia
GOLDEN_WELFARE = -4823.1598620624 # GLB-CVX welfare optimum (computed; test_ieee13.jl)
...
res = operational_oracle(feeder, ConvexBranchFlow(), aggs; λ₀ = λ₀, T = 24, allow_export = true)
ctx = res.ctx

@test ctx.meta[:socp_maxgap] < 1e-5                          # PF-04 exact relaxation (GATE)
@test isapprox(res.cost, GOLDEN_WELFARE; rtol = 1e-4)        # existing golden (VALUE, second)
```

**Analog 2 (N=1 gate + value, BilevelJuMP-specific):** `test/test_planning_certification.jl`
lines 170-227 — copy this file's exact `feeder`/`dev`/`agg`/`follower_kwargs`/`master_kwargs`
toy-instance construction and `solve_stackelberg!` invocation verbatim (same fixture as
`fixtures_planning.jl`'s N=1 goldens); the gate is `@test result.gap <= 1e-6` (lines 198),
the value assertions follow at lines 207-219 using `atol = 1e-3`.

**Analog 3 (N=2 gate + value):** `test/test_planning_nash.jl` lines 257-321 — copy the
`build_shared_transmission`/`run_nash!` call shape verbatim; gate is `result.converged`
(line 291) plus the binding-constraint check (lines 313-315, NOT a literal dual check — see
the file's own degeneracy note lines 295-312), values are lines 292-293
(`isapprox(result.z, [0.6, 0.6]; atol=1e-3)`, `isapprox(result.x_inv, [0.3,0.3]; atol=1e-3)`).

**Tolerance policy excerpt to reuse (rel 1e-6 objective/z, looser on duals):**
```julia
@test result.gap <= 1e-6                                     # PVAL-01 gate, tight
@test isapprox(result.y, value(r_sd.y_inv); atol = 1e-3)     # value regression, looser (dual-adjacent)
```

**Cross-reference comment convention to copy** (mirrors `test_acceptance.jl` lines 17-21 exactly):
document in the new file's header that PVAL-01's own permanent regression
(`test_planning_certification.jl`) is NOT duplicated, only cross-referenced, and that this
file adds the DEDICATED goldens module + N=2 pin that did not exist before.

**Probe-spread golden (if pinned as a bound, per CONTEXT.md discretion):** `run_nash_probe`
call shape and assertions to copy from `test/test_planning_nash.jl` lines 618-668:
```julia
result = run_nash_probe(specs, build_shared; seeds = seeds, orders = orders, tol_outer = 1e-4,
    max_sweeps = 50, checkpoint_dir = mktempdir())
@test result.n_runs == 6
@test all(r -> r.result.converged, result.runs)
@test occursin("a converged equilibrium", result.summary)
@test !occursin("the equilibrium", result.summary)
@test result.spread.z_spread >= 0.0 && isfinite(result.spread.z_spread)
```

---

### `test/test_planning_noninteger.jl` (no-binaries guard, semantic invariant)

**Analog:** `test/test_planning_coupling.jl` lines 237-252 (existing partial, SharedTransmission-only)

**Exact idiom to reuse (JuMP introspection, do not hand-roll an AST scan):**
```julia
@testitem "planning coupling: PVAL-04 continuous-only regression — no binary/integer variable anywhere in the shared model" tags =
    [:planning] begin
    using TSODSO
    using JuMP: all_variables, is_binary, is_integer

    shared = build_shared_transmission(;
        N = 2, T = 1, corridor_cap = 2.0,
        x_inv_max = [0.3, 0.5], c_inv = [1.0, 3.0], c_op = [[0.5], [0.5]],
    )

    @test all(v -> !is_binary(v) && !is_integer(v), all_variables(shared.model))
end
```

**Companion duplicate (to consolidate/remove per RESEARCH's Wave-0-gap note):**
`test/test_planning_nash.jl` lines 317-320 — the SAME check, run after a `run_nash!` mutation
cycle; a candidate to fold into the new consolidated file rather than leave duplicated.

**Toy-fixture construction to reuse for the other 3 builders** (from
`test/test_planning_certification.jl` lines 176-181, the SAME instance already used
elsewhere in the planning test suite — reuse rather than invent a new one):
```julia
feeder = Phase6Fixtures.two_bus_feeder()
dev = ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)
agg = TSODSO.Aggregator(2, 0.9, [dev], [0.0])
λ₀ = [4.0]
follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0)
```
(`setup = [Phase6Fixtures, ToyDeviceFixture]` — `Phase6Fixtures` lives in `test/fixtures_phase6.jl`;
`ToyDeviceFixture` is the `@testmodule` defined inside `test/test_planning_oracle.jl` line 144 —
NOT its own file, so `setup=[...]` resolves it by name via TestItemRunner's project-wide
`@testmodule` registry, no explicit include needed.)

**Builder signatures verified for the registry** (from `src/planning/*.jl`):
```julia
# src/planning/subproblem.jl:110
function build_planning_oracle(feeder, pf, aggregators; λ₀, T, kwargs...)  # returns .model
# src/planning/follower.jl:94
function build_follower(; T, corridor_cap, x_inv_max, c_inv, c_op)         # returns .model
# src/planning/master.jl:92
function build_master(; T, c_y, y_max, α_op_lb, α_x_lb)                   # returns .model
# src/planning/coupling.jl:174
function build_shared_transmission(; N, T, corridor_cap, x_inv_max, c_inv, c_op)  # returns .model
```

**Tripwire pattern (source-scan, no new dependency):**
```julia
planning_dir = joinpath(pkgdir(TSODSO), "src", "planning")
found = Set{String}()
for f in readdir(planning_dir; join = true)
    endswith(f, ".jl") || continue
    for line in eachline(f)
        m = match(r"^function (build_\w+)\(", line)
        m !== nothing && push!(found, m.captures[1])
    end
end
@test found == Set(keys(registry))
```
(Verified via direct grep this session: `build_planning_oracle` in `subproblem.jl:110`,
`build_follower` in `follower.jl:94`, `build_master` in `master.jl:92`,
`build_shared_transmission` in `coupling.jl:174` — all match `^function build_\w+\(` at
column 0, confirming the regex is safe to use unmodified.)

---

### `docs/literate/stackelberg_benders.jl` (docs, Literate rung page)

**Analog:** `docs/literate/admm.jl`

**Header/math-narrative shape to copy** (lines 1-46 of `admm.jl`): title comment (`# # Rung N —
...`), a "why this page" paragraph citing the requirement IDs (mirror `PLAN-*`/`NASH-*` style
with this phase's own PSR problem numbers), a `math` block per thesis/PSR equation, and a
closing "Build once, re-solve many" or equivalent discipline note.

**Import convention (do NOT import BilevelJuMP/HiGHS/Ipopt directly — see Anti-Pattern
below):**
```julia
using TSODSO
using TSODSO: Bus, Branch, Feeder
```
(verbatim from `admm.jl` lines 48-49 and `pricing_dlmp.jl` lines 70-71).

**Live `@example` execution pattern** (`admm.jl` lines 79-116): build a tiny feeder/instance
inline, call the real solve entrypoint, then display genuinely-computed values (never a
hardcoded number) — e.g. for Rung 6:
```julia
result = solve_stackelberg!(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = 1,
    follower_kwargs = follower_kwargs, master_kwargs = master_kwargs, tol = 1e-6,
    max_iter = 100, checkpoint_dir = mktempdir())
result.gap
result.y
result.z
result.UB
```

**Anti-pattern to avoid (do not copy):** `admm.jl`'s CairoMakie-guarded final block (lines
118-131) is a fine pattern IF a convergence figure is wanted, but do NOT extend this file's
`using TSODSO` convention to add `using BilevelJuMP, HiGHS, Ipopt` — the certification story
must be narrated as prose/table citing `test/test_planning_certification.jl` by name, never
executed live (see RESEARCH "Anti-Pattern to Avoid" section — this is a locked recommendation,
not open).

---

### `docs/literate/nash_diagonalization.jl` (docs, Literate rung page)

**Analog:** `docs/literate/admm.jl` (iteration-loop narrative) + `docs/literate/pricing_dlmp.jl`
(decomposition-table narrative, for the coupling-seam table `z↔p_ag`, `λ_j↔π_s`)

**Table/decomposition-display pattern to copy** (`pricing_dlmp.jl` lines 104-121 — reaching the
displayed NamedTuple without a thrown error IS the validation):
```julia
decomp = decompose_dlmp(ctx)
(
    energy = sum(decomp.energy),
    loss = sum(decomp.loss),
    congestion = sum(decomp.congestion),
    voltage = sum(decomp.voltage),
)
```
Adapt this shape for the coupling-seam table: build `shared = build_shared_transmission(...)`,
run `run_nash!(specs, shared; ...)`, then display `result.z`, `result.x_inv`, `result.converged`,
and (if pinned) `result.spread` fields as the "genuinely computed, not hardcoded" proof.

**"Never THE equilibrium" language (verbatim requirement from CONTEXT.md) — copy the exact
phrasing already validated in code**, from `test/test_planning_nash.jl` lines 664-665:
```julia
@test occursin("a converged equilibrium", result.summary)
@test !occursin("the equilibrium", result.summary)
```
Rung 7's prose must use "a converged equilibrium (spread: …)" verbatim, matching this
structural rule.

---

### `docs/make.jl` (config edit, batch wiring)

**Analog:** itself — in-place edit of the existing `for src in (...)` loop (lines 20-27) and
`pages` array (lines 51-62).

**Exact diff shape:**
```julia
# Literate loop — append two new sources to the existing tuple:
for src in (
    "toy_dc.jl", "lindistflow.jl", "convex_branch_flow.jl",
    "prosumer_welfare.jl", "pricing_dlmp.jl", "admm.jl",
    "stackelberg_benders.jl",   # NEW: Rung 6
    "nash_diagonalization.jl",  # NEW: Rung 7
)
    Literate.markdown(joinpath(LITERATE_DIR, src), GENERATED_DIR; flavor = Literate.DocumenterFlavor())
end
```
```julia
# pages tree — new "Planning" subsection, sibling to the existing "Models" subsection (lines 53-60):
"Planning" => [
    "Rung 6: Stackelberg-Benders" => "generated/stackelberg_benders.md",
    "Rung 7: Nash Diagonalization & Shared Corridor" => "generated/nash_diagonalization.md",
],
```
Insert directly after the existing `"Models" => [...]` entry (before `"API Reference" =>
"api.md"`, line 61) so ordering matches the rung-ladder narrative.

**Do not touch:** `checkdocs = :exports` (line 70) and `warnonly = [:cross_references]`
(line 71) — these enforcement settings are already correct and load-bearing; the fix is
content (api.md), not config here.

---

### `docs/src/api.md` (config edit, `@autodocs` section)

**Analog:** any existing section, e.g. "ADMM Decomposition" (lines 88-94) — structurally
identical, BUT the `Order` list must differ (see Pitfall below).

**Exact shape to add (new section, append near the end, before or after "Diagnostics"):**
```markdown
## Planning Layer

\`\`\`@autodocs
Modules = [TSODSO]
Pages = [
    "planning/retry.jl",
    "planning/checkpoint.jl",
    "planning/trace.jl",
    "planning/subproblem.jl",
    "planning/follower.jl",
    "planning/master.jl",
    "planning/benders.jl",
    "planning/coupling.jl",
    "planning/nash.jl",
]
Order = [:type, :constant, :function]
\`\`\`
```

**Critical deviation from every existing section's `Order` line** (lines 22, 30, 38, 46, 61,
69, 77, 85, 93, 101, 109 all use `Order = [:type, :function]`): the Planning section MUST use
`Order = [:type, :constant, :function]` because `src/planning/retry.jl` line 33 defines
`const RETRYABLE_STATUSES = (MOI.NUMERICAL_ERROR, MOI.SLOW_PROGRESS, MOI.ALMOST_OPTIMAL)`, a
top-level `const` — the first exported constant in the whole project's `src/` tree. Copying
`Order = [:type, :function]` verbatim will leave `RETRYABLE_STATUSES` orphaned and
`checkdocs = :exports` will still fail the build with exactly one remaining missing-docs error.

**Verification command (must exit 0 before considering PVAL-03 done — not part of `Pkg.test`):**
```bash
julia --project=docs docs/make.jl
```

## Shared Patterns

### `@testitem`/`@testmodule` tagging and setup convention
**Source:** every `test/test_planning_*.jl` file (e.g. `test_planning_coupling.jl` line 63,
`test_planning_nash.jl` line 258, `test_planning_certification.jl` line 133)
**Apply to:** `test_planning_goldens.jl`, `test_planning_noninteger.jl`
```julia
@testitem "<descriptive name including WHY, per this project's convention>" tags = [:planning] setup = [Phase6Fixtures, ToyDeviceFixture] begin
    using TSODSO
    ...
end
```

### Fail-loud / no-silent-defaults convention
**Source:** `src/planning/*.jl` builders (all guard shape/positivity via `ArgumentError` before
any `@variable`/`@objective` assembly — see `test/test_planning_coupling.jl` lines 63-134 for
the exhaustive guard-testing pattern against `build_shared_transmission`)
**Apply to:** the no-binaries guard's failure messages (name the offending builder AND
variables, per CONTEXT.md's explicit "fail-loud" requirement) — do not just `@test isempty(x)`
with no context; prefer:
```julia
offenders = [v for v in all_variables(model) if is_binary(v) || is_integer(v)]
@test isempty(offenders)  # on failure, Test.jl prints `offenders` and the testitem name
                          # (which must embed the builder name) — no extra @info needed
                          # since TestItemRunner already reports the failing @test's context
```

### Documented-exception / DEVIATION comment convention
**Source:** `test/test_planning_certification.jl` lines 1-64 (the file's entire header is a
DEVIATION-from-plan narrative with RE-DERIVED values, negative-regression documentation)
**Apply to:** `fixtures_planning.jl` (document the N=1 RE-DERIVED values, not the original
incorrect plan numbers) and the probe-spread bound-vs-value decision in `test_planning_goldens.jl`
(document the rationale inline per CONTEXT.md's explicit ask).

### Literate `@example` "genuinely computed, never hardcoded" convention
**Source:** `docs/literate/admm.jl` lines 104-116, `docs/literate/pricing_dlmp.jl` lines 104-128
**Apply to:** both new Literate pages — every displayed number must come from a live
`solve_stackelberg!`/`run_nash!` call in the page itself, never a copy-pasted literal from the
goldens file.

## No Analog Found

None — every file in this phase has a strong (exact or role-match) analog already in the
codebase; this phase is pure convention-extension, not new-pattern introduction (matches
RESEARCH's own framing: "no new modeling math... the work is wiring, not procurement").

## Metadata

**Analog search scope:** `test/` (all `test_planning_*.jl`, `fixtures_phase*.jl`,
`test_acceptance.jl`), `docs/` (`make.jl`, `src/api.md`, `literate/*.jl`), `src/planning/*.jl`
(builder signatures + include order in `src/TSODSO.jl`).
**Files scanned:** 9 `src/planning/*.jl`, 10 `test/test_planning_*.jl`, 5 `test/fixtures_phase*.jl`,
6 `docs/literate/*.jl`, `docs/make.jl`, `docs/src/api.md`.
**Pattern extraction date:** 2026-07-24

# Phase 17: Real IEEE-123 Impedances - Pattern Map

**Mapped:** 2026-07-25
**Files analyzed:** 7 (2 vendored data files treated as one unit)
**Analogs found:** 6 / 7 (partial-to-strong); 1 genuinely novel (no analog: vendored upstream data)

## PMD Constraint (explicit, load-bearing)

**PowerModelsDistribution.jl MUST NOT be added to `Project.toml [deps]` for this phase.**
RESEARCH.md's primary recommendation (and the one this pattern map assumes throughout) is a
**dependency-free regex/text parser** — zero new packages, not even a weakdep. `Project.toml`
is UNCHANGED by every file below. If a future planner/executor decides to add PMD anyway (e.g.
as an optional oracle cross-check), it may ONLY go behind `[weakdeps]` + a package extension, or
in a throwaway `scripts/`-local `Project.toml` — never runtime `[deps]`. There is no analog for
"PMD as a runtime dependency" in this codebase because it has never been added, and this phase
must not be the one that adds it.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `scripts/data/IEEE123Master.dss` + `scripts/data/IEEELineCodes.DSS` | config/fixture (vendored upstream data) | file-I/O (static, read-only) | none in-repo (see "No Analog Found") | no-analog |
| `scripts/reduce_ieee123_impedances.jl` | utility (offline batch transform / code generator) | batch / transform | `scripts/benders_toy.jl` (skeleton/header/`--project` convention); `scripts/sweep.jl` (no-`TSODSO`-dependency style is closer for THIS script) | role-match |
| `src/data/ieee123_impedances.jl` | model/config (generated `const` data table) | CRUD (static read, no writes) | `src/data/ieee123.jl` itself — specifically its OWN `IEEE123_EDGES`/`IEEE123_LINE_R`/`IEEE123_LINE_X` const-table shape | exact (same file family, new sibling) |
| `src/data/ieee123.jl` (MODIFY) | model (feeder-fixture builder) | CRUD (in-memory struct construction) | itself, prior revision — this IS the analog for its own edit | exact |
| `test/test_ieee123.jl` (MODIFY) | test | request-response (build + assert) | itself, prior revision (existing `@testitem`s in this exact file) | exact |
| new voltage-binding `@testitem` (in `test_ieee123_admm.jl` or `test_acceptance.jl`) | test | request-response (solve + assert) | `test/test_ieee123_admm.jl` lines 20-95 (fixture setup + solve invocation); `test/test_acceptance.jl` lines 98-147 (IEEE-123 acceptance item, same solve shape) | strong role-match |
| `docs/literate/ieee123_impedances.jl` (optional) | doc/config | transform (literate render) | `docs/literate/lindistflow.jl` (header/structure convention) | role-match |

## Pattern Assignments

### `scripts/reduce_ieee123_impedances.jl` (utility, batch/transform)

**Analog:** `scripts/benders_toy.jl` (header/skeleton convention) + `scripts/sweep.jl` (dependency posture)

**Header/run-instructions pattern** (`scripts/benders_toy.jl:1-19`):
```julia
# scripts/benders_toy.jl
#
# A visual, step-by-step toy of Benders decomposition — the SAME algorithm the planning
# layer uses (`src/planning/benders.jl` `solve_stackelberg!`), but reduced to ONE scalar
# decision so the geometry can be drawn.
# ...
# Run:
#     julia --project=. scripts/benders_toy.jl
```

**Dependency posture — DO NOT copy `benders_toy.jl`'s `using DrWatson; @quickactivate "TSODSO"; using TSODSO`
line-for-line here.** RESEARCH.md is explicit that this script must add **zero new dependencies,
not even a weakdep**, and must be independently runnable/reproducible offline. It does not need
`TSODSO` (it never calls `to_pu_impedance` — that conversion happens later, inside `ieee123.jl`
at ingestion, per Pattern 3 below) and does not need `DrWatson` (no scenario/sweep machinery, no
`datadir()`/gitignored `/data/` output — this script's OUTPUT is a *committed* `src/` file, the
opposite of DrWatson's gitignored `/data/` convention). Use plain `@__DIR__`-relative paths
instead:
```julia
# scripts/reduce_ieee123_impedances.jl — dependency-free (Base + stdlib regex only)
#
# Run:
#     julia scripts/reduce_ieee123_impedances.jl            # regenerate the table
#     julia scripts/reduce_ieee123_impedances.jl --verify   # self-check only, no file write

const SCRIPT_DIR = @__DIR__
const MASTER_DSS = joinpath(SCRIPT_DIR, "data", "IEEE123Master.dss")
const LINECODES_DSS = joinpath(SCRIPT_DIR, "data", "IEEELineCodes.DSS")
const OUT_FILE = joinpath(SCRIPT_DIR, "..", "src", "data", "ieee123_impedances.jl")
```

**Self-check / tripwire pattern (mirrors `PerUnit.jl`'s `throw(ArgumentError(...))` convention,
NEVER `@assert`)** — `src/units/PerUnit.jl:85-93` (`assert_magnitudes_voltage`):
```julia
function assert_magnitudes_voltage(v)
    VOLTAGE_PU_MIN ≤ v ≤ VOLTAGE_PU_MAX || throw(
        ArgumentError(
            "voltage $v pu out of per-unit sanity band [$(VOLTAGE_PU_MIN), $(VOLTAGE_PU_MAX)] " *
            "— check SI/pu conversion at ingestion",
        ),
    )
    return nothing
end
```
Apply the SAME `throw(ArgumentError(...))` style (not `@assert`, not `@error`) for the script's
own `--verify` self-check: `length(linecodes) == 12` and the pinned `linecode.1` sanity value
(`R1 ≈ 0.057967`, `X1 ≈ 0.118756`, per RESEARCH Pattern 2). This keeps the tripwire convention
consistent across the codebase (`topology.jl`'s WR-02 rule, referenced explicitly in
`PerUnit.jl:83,105`) even though this script lives outside `src/`.

**Regex parsing patterns (verified against live upstream content, from RESEARCH.md Code Examples
— no in-repo analog exists for `.dss` parsing, this is genuinely new territory)**:
```julia
# "New Line.*" statement, e.g. "New Line.L115  Bus1=149  Bus2=1  LineCode=1  Length=0.4"
line_re = r"New\s+Line\.(\S+)\s+.*?Bus1=(\S+?)(?:\.\S+)?\s+Bus2=(\S+?)(?:\.\S+)?\s+LineCode=(\d+)\s+Length=([\d.]+)"i
```
Fortescue reduction (`R1 = mean(diag) - mean(offdiag)`, same for `X1`; `n=1` linecodes skip
reduction, `R1 = rmatrix[1,1]` directly) — see RESEARCH.md "Architecture Patterns > Pattern 2"
for the fully worked linecode.1 numeric trace; copy that verification block verbatim as the
`--verify` path's pinned expected values.

**Output-emission pattern — write a committed Julia source file, matching the shape of
Pattern 1 below.** Emit `IEEE123_BRANCH_RX_OHMS::Dict{Tuple{Int,Int},Tuple{Float64,Float64}}`
keyed by the EXISTING `IEEE123_EDGES` tuples (`src/data/ieee123.jl:88-208`, see below) — do not
invent a new key convention; look up each `(from_terminal, to_terminal)` pair from
`IEEE123_EDGES` in the raw `.dss` (in either bus order) rather than re-deriving topology
(RESEARCH Pitfall 3). A lookup miss must `throw(ArgumentError(...))` loudly, never silently
default.

---

### `src/data/ieee123_impedances.jl` (model/config, generated const table)

**Analog:** `src/data/ieee123.jl`'s own existing const-table conventions (this file's sibling)

**Existing const-table shape to mirror** — `src/data/ieee123.jl:60-63` (the two scalars being
replaced) and `:88-208` (`IEEE123_EDGES`, the exact key-tuple shape/order the new Dict must key
against):
```julia
const IEEE123_LINE_R = 0.005
const IEEE123_LINE_X = 0.0025
const IEEE123_SWITCH_R = 0.0003
const IEEE123_SWITCH_X = 0.00015

const IEEE123_EDGES = [
    (150, 149),
    (149, 1),
    (1, 2),
    (1, 3),
    ...
]
```

**Provenance-comment convention to mirror** — `src/data/ieee123.jl:1-32` (the file's own
"DATA PROVENANCE / TRANSCRIPTION NOTE" block documents source, threat ID, and what is
"representative" vs "verbatim"). The new file needs an equivalent header, e.g.:
```julia
# src/data/ieee123_impedances.jl
#
# GENERATED by scripts/reduce_ieee123_impedances.jl — DO NOT hand-edit; re-run the script and
# re-commit if the upstream .dss files change.
#
# Source: raw.githubusercontent.com/tshort/OpenDSS/master/Distrib/IEEETestCases/123Bus/
#         IEEE123Master.dss + IEEELineCodes.DSS, fetched 2026-07-25 (vendored copies committed
#         at scripts/data/, exact case IEEELineCodes.DSS required — see script header).
#
# Values are per-segment SERIES IMPEDANCE IN OHMS (positive-sequence, Fortescue-averaged from
# each linecode's rmatrix/xmatrix), NOT per-unit. Converted once at ingestion in
# ieee123_modified() via to_pu_impedance (src/units/PerUnit.jl:53) — see Pattern 3.
#
# Keyed by ORIGINAL IEEE-123 terminal pairs (pre-relabel), matching IEEE123_EDGES exactly
# (src/data/ieee123.jl). NO length-unit conversion applied (OpenDSS Units= unspecified ⇒ no-op,
# RESEARCH Pitfall 1) — do NOT introduce a feet/miles/kft scale factor here.
const IEEE123_BRANCH_RX_OHMS = Dict{Tuple{Int,Int}, Tuple{Float64,Float64}}(
    (149, 1)  => (0.057967 * 0.4, 0.118756 * 0.4),   # LineCode=1, Length=0.4
    (1, 2)    => (0.251742 * 0.175, 0.255208 * 0.175), # LineCode=10, Length=0.175
    # ... 117 entries total (122 IEEE123_EDGES minus the 5 IEEE123_SWITCH_EDGES) ...
)
```

**Include-wiring note (no existing analog — new convention for this repo):** this file is
`include`d FROM `ieee123.jl` itself (`include("ieee123_impedances.jl")` near the top of
`src/data/ieee123.jl`, NOT registered as a separate top-level `include(...)` in
`src/TSODSO.jl`). Verify against `src/TSODSO.jl:27-29`, which currently does
`include("data/ieee123.jl")` with no sibling include — the new file must load transitively
through that single line, keeping `TSODSO.jl`'s "assembly point only" contract
(`src/TSODSO.jl:6-10`) untouched.

---

### `src/data/ieee123.jl` (MODIFY — model, CRUD)

**Analog:** itself, prior revision (this is a targeted edit, not a new-pattern search)

**Exact lines to change** — the two-scalar assignment inside the branch-build loop,
`src/data/ieee123.jl:400-410` (`ieee123_modified()` body):
```julia
branches = Branch{Float64}[]
for (p, c) in IEEE123_EDGES
    is_switch = (p, c) in IEEE123_SWITCH_EDGES
    r = is_switch ? IEEE123_SWITCH_R : IEEE123_LINE_R
    x = is_switch ? IEEE123_SWITCH_X : IEEE123_LINE_X
    smax = p == IEEE123_ROOT_TERMINAL ? s_head : s_int   # only the frontier branch binds
    push!(branches, Branch(remap[p], remap[c], r, x, smax))
end
```
Replace `r = is_switch ? IEEE123_SWITCH_R : IEEE123_LINE_R` / `x = ...` with the per-segment
lookup + `to_pu_impedance` conversion (RESEARCH Pattern 3, verbatim):
```julia
for (p, c) in IEEE123_EDGES
    is_switch = (p, c) in IEEE123_SWITCH_EDGES
    if is_switch
        r, x = IEEE123_SWITCH_R, IEEE123_SWITCH_X   # near-ideal regulator/switch segments unchanged
    else
        r_Ω, x_Ω = IEEE123_BRANCH_RX_OHMS[(p, c)]
        r, x = to_pu_impedance(r_Ω, IEEE123_BASE), to_pu_impedance(x_Ω, IEEE123_BASE)
    end
    smax = p == IEEE123_ROOT_TERMINAL ? s_head : s_int
    push!(branches, Branch(remap[p], remap[c], r, x, smax))
end
```

**Existing Ω→pu ingestion seam being reused (do not reinvent)** —
`src/units/PerUnit.jl:53` (already read this session):
```julia
to_pu_impedance(z_Ω, b::PerUnitBase) = z_Ω / Z_base(b)   # existing, unmodified
# Z_base(IEEE123_BASE) = 4.16^2 / 1.0 = 17.3056 Ω
```
Same pattern already used one line up in the SAME function for the head-branch limit
(`src/data/ieee123.jl:391`):
```julia
s_head = to_pu_power(IEEE123_HEAD_SMAX_MVA, IEEE123_BASE)   # == 3.8 pu
```

**Constants to remove / retire** — `src/data/ieee123.jl:60-63`
(`IEEE123_LINE_R`/`IEEE123_LINE_X` become dead code once the per-segment table lands; keep
`IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` — RESEARCH Assumption A2 says switch/regulator segments
intentionally keep their existing near-ideal synthetic value, not a "real" one). Per RESEARCH's
own "State of the Art" table: remove the two dead scalars rather than leaving two parallel,
inconsistent impedance sources in the same file.

**Provenance comment to update** — the file's own header block
(`src/data/ieee123.jl:13-32`, "DATA PROVENANCE / TRANSCRIPTION NOTE") currently documents the
per-unit R/X as "REPRESENTATIVE, not the thesis App. E verbatim numbers." This note is
SUPERSEDED for the impedance constants specifically once real data lands — update this
paragraph to point at `ieee123_impedances.jl`'s new provenance header instead of re-describing
representativeness; leave the topology/relabeling/switch documentation in the same block
UNCHANGED (per IMPED-02: "topology untouched").

---

### `test/test_ieee123.jl` (MODIFY — test)

**Analog:** itself, prior revision — existing `@testitem` structure at
`test/test_ieee123.jl:41-64` ("voltage band + per-unit magnitude sanity") is the one to extend,
NOT rewrite:
```julia
@testitem "ieee123: voltage band + per-unit magnitude sanity (ieee123)" tags = [:phase7] begin
    using TSODSO
    @test isdefined(TSODSO, :ieee123_modified)
    if isdefined(TSODSO, :ieee123_modified)
        feeder = ieee123_modified()
        for b in feeder.buses
            b.is_root && continue
            @test b.vmin <= 0.9 + 1e-9
            @test b.vmax >= 1.1 - 1e-9
        end
        for br in feeder.branches
            @test br.r > 0
            @test br.x > 0
            @test 0 < br.smax < 100
        end
    end
end
```
**Keep the existing `0 < r,x < 5` (this file currently checks `br.r > 0`/`br.x > 0`
strictly-positive, and `assert_magnitudes` in `PerUnit.jl:120-131` already enforces
`0 ≤ r,x < IMPEDANCE_PU_MAX(=5)` at construction time) tripwire UNMODIFIED** — RESEARCH.md's
Phase Requirements → Test Map explicitly calls this out as "existing assertion, unmodified."
Add NEW real-data-specific assertions alongside it, e.g. a spot-check that a known segment's
pu r/x matches the pinned linecode.1 reduction within tolerance, mirroring the existing
`@testitem "ieee123: relabel map + substation root spot-check"` style
(`test/test_ieee123.jl:66-90`) which does exactly this kind of "assert a specific pinned known
value" spot-check pattern already:
```julia
# documented spot-checks: smallest non-root terminal -> 2; a known high terminal -> N.
@test remap[1] == 2
@test remap[450] == N
```

---

### New voltage-binding `@testitem` (test — request-response, integration)

**Analog:** `test/test_ieee123_admm.jl:20-95` (fixture setup + solve invocation shape) and
`test/test_acceptance.jl:98-147` (the IEEE-123 acceptance item, structurally near-identical
solve call). Neither file has a `min(V)`-vs-band numeric assertion today — this is the genuinely
new part; everything BEFORE the new assertion should be copied verbatim from one of these two.

**Setup + solve pattern to copy** — `test/test_ieee123_admm.jl:20-78`:
```julia
@testitem "ieee123 admm: end-to-end converge + DADP cross-validation (ieee123, crossval)" setup =
    [Phase7Fixtures] tags = [:admm, :phase7] begin
    using TSODSO

    feeder = ieee123_modified()
    aggs = Phase7Fixtures.build_ieee123_aggregators(feeder)
    Th = Phase7Fixtures.T
    λ₀ = Phase7Fixtures.ieee123_lambda0()

    ctx_c, obj_c, _ = solve_welfare(
        feeder, ConvexBranchFlow(), aggs;
        T = Th, λ₀ = λ₀, allow_export = true,
    )
    res = solve_admm(
        feeder, ConvexBranchFlow(), aggs;
        T = Th, λ₀ = λ₀, ρ = Phase7Fixtures.RHO0,
        ε_abs = Phase7Fixtures.EPS_ABS, ε_rel = Phase7Fixtures.EPS_REL,
        τ = Phase7Fixtures.TAU, μ = Phase7Fixtures.MU,
        ρ_min = Phase7Fixtures.RHO_MIN, ρ_max = Phase7Fixtures.RHO_MAX,
        maxiter = 300, allow_export = true,
    )
```

**New assertion to add (genuinely novel — no analog)**: pull the solved squared-voltage
variable off `ctx_c.meta[:pf_vars].v` the SAME way `test_acceptance.jl:88` already does for a
single (bus, hour) spot-check —
```julia
v9_16 = sqrt(value(ctx.meta[:pf_vars].v[10, 16]))   # test_acceptance.jl:88, single-point pattern
```
— but generalize to a min/max sweep over ALL (bus, hour), e.g.:
```julia
using JuMP: value
Vall = sqrt.(value.(ctx_c.meta[:pf_vars].v))   # (N, T) matrix of |V| per bus/hour
vmin_solved, vmax_solved = minimum(Vall), maximum(Vall)
@info "ieee123 voltage-binding margin" vmin_solved vmax_solved band = (0.9, 1.1)
@test vmin_solved <= 0.92   # documented margin: within 0.02 pu of the lower band (RESEARCH Pitfall 4)
@test vmax_solved >= 1.08   # documented margin: within 0.02 pu of the upper band
```
Place the exact margin values per whatever the real solve actually produces (RESEARCH.md
flags this as genuinely unverified, Assumption A4 — do not hardcode without running the solve
first). Follow `test_ieee123_admm.jl`'s own `@info`-before-`@test` documentation convention
(`test_ieee123_admm.jl` uses plain `@test`, but `test_acceptance.jl:93-95` shows the project's
`@info` + tolerant-`@test` idiom for a "close but not exact" cross-check — reuse THAT idiom
here since this is exactly that kind of margin check, not a hard golden).

---

### `docs/literate/ieee123_impedances.jl` (optional — doc, transform)

**Analog:** `docs/literate/lindistflow.jl:1-30` (header + `using TSODSO` + narrative-then-code
structure) and `docs/make.jl:17-31` (registration loop) + `docs/make.jl:60-64`
(`pages =` list) + `docs/src/api.md:43-47` (`@autodocs` `Pages=` list already includes
`"data/ieee123.jl"`).

**Header/structure to copy** — `docs/literate/lindistflow.jl:1-30`:
```julia
# # Rung 1-2 — LinDistFlow (Linear Branch Flow)
#
# This page is the reproducibility proof that ...
#
# ## The LinDistFlow math
# ...
using TSODSO
```

**Registration additions (both required if this file is created):**
1. `docs/make.jl:17-31` — add `"ieee123_impedances.jl"` to the `for src in (...)` tuple so
   `Literate.markdown` renders it.
2. `docs/make.jl` `pages = [...]` block — add
   `"IEEE-123 Real Impedances" => "generated/ieee123_impedances.md"` under `"Models"` or a new
   section.
3. If the new `const IEEE123_BRANCH_RX_OHMS` gets its own docstring and is exported, add
   `"data/ieee123_impedances.jl"` to the existing `Pages = [...]` list at
   `docs/src/api.md:45` (already lists `"data/ieee123.jl"` — append as a sibling, do not
   replace).

## Shared Patterns

### SI→pu conversion at ingestion (single source of truth)
**Source:** `src/units/PerUnit.jl:48-53` (`to_pu_power`, `to_pu_impedance`)
**Apply to:** `src/data/ieee123.jl` only (never inside the reduction script, never inside a
model builder) — this is the project's one documented "SI→pu ONCE at ingestion" rule
(`src/units/PerUnit.jl:17-19`, `src/data/ieee123.jl` docstring on `ieee123_modified`,
"SI→pu ONCE at ingestion").
```julia
to_pu_impedance(z_Ω, b::PerUnitBase) = z_Ω / Z_base(b)
```

### Loud tripwires, never `@assert`
**Source:** `src/units/PerUnit.jl:76-140` (`assert_magnitudes_voltage`, `assert_magnitudes`)
**Apply to:** the reduction script's `--verify` self-check, and any new lookup-failure guard in
that script (a missing `IEEE123_EDGES` tuple in the raw `.dss` must `throw(ArgumentError(...))`,
never silently default) — matches `topology.jl`'s WR-02 convention referenced in
`PerUnit.jl:83,105`.
```julia
... || throw(ArgumentError("descriptive message naming the offending value"))
```

### Existing magnitude gate already re-validates real data automatically
**Source:** `src/units/PerUnit.jl:110-140` (`assert_magnitudes`, called inside `Feeder(...)`
construction, i.e. at the end of `ieee123_modified()` per `src/data/ieee123.jl`'s final line
`return Feeder(buses, branches, 1)`)
**Apply to:** no new code needed here — this is a FREE regression gate. Once real per-segment
r/x replace the synthetic scalars, `assert_magnitudes` automatically re-checks
`0 ≤ r,x < 5` pu and `0 < smax < 100` pu on every real value at construction time, so a gross
unit-conversion bug (RESEARCH Pitfall 1, e.g. an accidental feet/miles factor) throws
immediately rather than silently propagating into a solve.

### TestItems `@testmodule` fixture-population seam
**Source:** `test/fixtures_phase7.jl:54-67` (`LOAD_SCALE_IEEE123`/`PV_SCALE_IEEE123`/
`DEV_SCALE_IEEE123`)
**Apply to:** IF the real-impedance swap breaks voltage-binding (IMPED-03), re-tune ONLY these
three constants — never touch impedances again to "fix" a population-scale problem (RESEARCH
Pitfall 4's explicit instruction). This is the single documented seam for that adjustment.

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `scripts/data/IEEE123Master.dss` + `scripts/data/IEEELineCodes.DSS` | config/fixture (vendored upstream data) | file-I/O | No committed third-party vendored data file exists anywhere in this repo today — `.gitignore` explicitly excludes `/data/` (DrWatson experiment outputs) and `/docs/references/` (copyrighted PDFs stay local, never committed), so there is no existing "here is how we vendor and commit a third-party file with a provenance comment" precedent to copy structurally. Use the provenance-COMMENT convention from `src/data/ieee123.jl:1-32` (its own "DATA PROVENANCE" block) as the closest STYLE analog for the required header comment (URL + fetch date `2026-07-25` + exact-case warning), even though the file TYPE (raw `.dss` text, not Julia source) has no precedent. |

## Metadata

**Analog search scope:** `src/data/`, `src/units/`, `scripts/`, `test/` (all `*ieee123*` and
`*phase7*` files), `docs/literate/`, `docs/make.jl`, `docs/src/api.md`, `src/TSODSO.jl`,
`.gitignore`
**Files scanned:** 12 (`src/data/ieee123.jl`, `src/units/PerUnit.jl`, `test/test_ieee123.jl`,
`test/test_ieee123_admm.jl`, `test/fixtures_phase7.jl`, `test/test_acceptance.jl`,
`scripts/benders_toy.jl`, `scripts/sweep.jl`, `scripts/run_scenario.jl`,
`docs/literate/lindistflow.jl`, `docs/make.jl`, `docs/src/api.md`, `src/TSODSO.jl`, `.gitignore`)
**Pattern extraction date:** 2026-07-25

# Phase 25: IEEE-8500 Scale Benchmark - Pattern Map

**Mapped:** 2026-08-20
**Files analyzed:** 9 (new) + 4 (modified)
**Analogs found:** 12 / 13 (1 partial — the density-sweep-parametrized harness has no single
exact-shape precedent; synthesized from two harness analogs)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `scripts/reduce_ieee8500_impedances.jl` | utility (CLI reduction script) | file I/O (text-in → Julia-source-out) | `scripts/reduce_ieee123_impedances.jl` | exact |
| `src/data/ieee8500.jl` | model/fixture builder | CRUD (construct-once, immutable) | `src/data/ieee123.jl` | exact |
| `src/data/ieee8500_impedances.jl` | config/generated data | file I/O (const table) | `src/data/ieee123_impedances.jl` | exact |
| `ext/TSODSOSCSExt.jl` | provider (solver extension) | request-response (factory call) | `ext/TSODSOGurobiExt.jl` / `ext/TSODSOMosekExt.jl` | role-match (naming diverges, see D-20) |
| `scripts/benchmark_ieee8500.jl` | utility (CLI benchmark harness) | batch (sweep + measure + emit CSV/results) | `scripts/socp_applicability_sweep.jl` + `scripts/repro_stability_check.jl` | role-match (synthesized from two) |
| `test/test_ieee8500.jl` | test | request-response (construction invariants) | `test/test_ieee123.jl` | exact |
| q-only `FixedCapacitor` device (`src/devices/`) | model (device) | transform (constant injection, no vars) | `src/devices/FourQuadBESS.jl` (q_inject shape) + `src/devices/AbstractDevice.jl` (contract) | exact |
| new literate page `docs/literate/ieee8500_scaling.jl` | component (docs page) | transform (read committed CSV → render) | `docs/literate/socp_applicability.jl` | exact |
| `src/TSODSO.jl` (MODIFIED) | config (include graph) | — | itself (existing `include(...)` block, ieee123 wiring) | exact |
| `src/experiments/materialize.jl` (MODIFIED) | service (registry + population builder) | CRUD | itself (`build_feeder`, `_load_buses`, `build_population`) | exact |
| `Project.toml` (MODIFIED) | config | — | existing `[weakdeps]`/`[extensions]` block (Gurobi/Mosek entries) | exact |
| `src/solver/factory.jl` + `src/solver/ProblemClass.jl` (MODIFIED) | service (solver factory) | request-response | itself (`commercial_optimizer`/`GurobiChoice` pattern) | role-match (new parallel dispatch, not a copy) |
| `src/admm/solve_admm.jl` (POSSIBLY MODIFIED) | service (iterative solver loop) | event-driven (outer loop with convergence exit) | `src/planning/benders.jl` (`time_ns` idiom) | partial (timing idiom transfers; no existing wall-clock-bounded ADMM loop) |

## Pattern Assignments

### `scripts/reduce_ieee8500_impedances.jl` (utility, file I/O)

**Analog:** `scripts/reduce_ieee123_impedances.jl` (full file read, 462 lines)

**Header/provenance pattern** (lines 1-28):
```julia
# scripts/reduce_ieee123_impedances.jl — dependency-free (Base + stdlib regex only)
#
# Parses the two vendored, offline OpenDSS IEEE-123 source files
# (`scripts/data/IEEE123Master.dss` + `scripts/data/IEEELineCodes.DSS`, fetched 2026-07-25),
# reduces each 3-phase/2-phase/1-phase line-code impedance matrix to a positive-sequence
# R1/X1 pair via Fortescue-averaging, and (in default mode) emits a committed Julia source
# file at `src/data/ieee123_impedances.jl` ...
#
# Zero package dependencies (no `using` statements anywhere in this file): the parser is
# Base + stdlib PCRE regex only, so `Project.toml [deps]` is untouched by this script.
#
# Run:
#     julia scripts/reduce_ieee123_impedances.jl            # regenerate the table
#     julia scripts/reduce_ieee123_impedances.jl --verify   # self-check only, no file write

const SCRIPT_DIR = @__DIR__
const MASTER_DSS = joinpath(SCRIPT_DIR, "data", "IEEE123Master.dss")
const LINECODES_DSS = joinpath(SCRIPT_DIR, "data", "IEEELineCodes.DSS")
const OUT_FILE = joinpath(SCRIPT_DIR, "..", "src", "data", "ieee123_impedances.jl")

# Pinned sanity value, independently re-derived.
const LINECODE1_R1_EXPECTED = 0.057967
const LINECODE1_X1_EXPECTED = 0.118756
const SANITY_ATOL = 1.0e-5
```
For the 8500 script: swap the two constants for the CT5 sanity pair from CONTEXT.md
(`R_total=3.0%`, `X_total=2.72%` — pre-pu, in percent, or convert once to Ω/pu as the
`--verify` mode chooses) per RESEARCH.md's "give the reduction script's `--verify` mode a
pinned sanity check analogous to `LINECODE1_R1_EXPECTED`" recommendation.

**Matrix reduction primitive — reuse verbatim, no change needed** (lines 111-161):
```julia
function parse_lower_triangular(s::AbstractString)
    rows = split(s, '|')
    n = length(rows)
    mat = zeros(Float64, n, n)
    for (i, row) in enumerate(rows)
        vals = parse.(Float64, split(strip(row)))
        length(vals) == i || throw(ArgumentError(...))
        for (j, v) in enumerate(vals)
            mat[i, j] = v
            mat[j, i] = v
        end
    end
    return mat
end

function fortescue_reduce(mat::AbstractMatrix{<:Real})
    n = size(mat, 1)
    n == 1 && return Float64(mat[1, 1])
    diagvals = Float64[mat[i, i] for i in 1:n]
    offdiag = Float64[]
    for i in 1:n, j in 1:n
        i == j && continue
        push!(offdiag, mat[i, j])
    end
    return sum(diagvals) / n - sum(offdiag) / length(offdiag)
end
```
RESEARCH.md confirms this transfers directly to the 8500 linecodes (same Ω-matrix form).

**NEW step this fixture needs that IEEE-123 never did — dedupe parallel edges** (pattern from
RESEARCH.md "Code Examples", not lifted from the 123 script since it has no precedent there):
```julia
by_pair = Dict{Tuple{String,String}, Vector{LineRecord}}()
for r in records
    key = r.bus1_base < r.bus2_base ? (r.bus1_base, r.bus2_base) : (r.bus2_base, r.bus1_base)
    push!(get!(by_pair, key, LineRecord[]), r)
end
for (key, recs) in by_pair
    length(recs) == 1 && continue
    r_ref, x_ref = recs[1].r_ohm, recs[1].x_ohm
    all(rec -> isapprox(rec.r_ohm, r_ref; rtol=1e-6) && isapprox(rec.x_ohm, x_ref; rtol=1e-6), recs) ||
        throw(ArgumentError("edge $key collapses $(length(recs)) non-identical phase-tagged " *
                             "records — cannot safely dedupe, inspect source data"))
    # keep exactly one (recs[1])
end
```
Apply this BEFORE the `--verify`/emit steps; wire it into `main()` between "Step 1: parse"
and "Step 3: edge lookup" in the IEEE-123 script's structure.

**New parsing path needed** (RESEARCH Pattern 3 table): a SECOND regex path for lines that
specify `r1=`/`x1=` inline (no `Linecode=` lookup) — `HVMV_Sub_connector` and the `CAP_*`
jumpers. `parse_terminal` must strip a trailing `\.\d+$` phase suffix (not parse a leading
integer, since bus names here are alphanumeric, unlike IEEE-123's integer terminals) — see
`parse_terminal` (lines 48-67) for the shape to adapt, but the regex body itself changes.

**`--verify` / `main()` CLI dispatch pattern — reuse verbatim shape** (lines 376-462):
```julia
function verify()
    master_text = read(MASTER_DSS, String)
    ...
    isapprox(R1, LINECODE1_R1_EXPECTED; atol = SANITY_ATOL) || throw(ArgumentError(...))
    println("PASS: ...")
    return nothing
end

function main()
    if ARGS == ["--verify"]
        verify()
        return nothing
    end
    ...
    outfile = emit_output(rx, meta, OUT_FILE)
    println("Wrote ...")
    return nothing
end

main()
```

**Emit-committed-table pattern** (lines 302-370, `emit_output`): copy the provenance-header
convention verbatim (source URL, fetch date, "GENERATED — DO NOT hand-edit", units statement,
keying convention) — see the `src/data/ieee8500_impedances.jl` section below for the expected
header shape.

---

### `src/data/ieee8500.jl` (fixture builder, CRUD)

**Analog:** `src/data/ieee123.jl` (full file read, 452 lines)

**Header/provenance-note convention** (lines 1-36):
```julia
# src/data/ieee123.jl
#
# SEAM: modified IEEE 123-node feeder built-in fixture (DATA-03, scale target).
# OWNER: plan 07-01 wired this into the include graph; plan 07-02 FILLS it.
#
# NAMING (IN-02): "IEEE 123-node" is the HISTORICAL name of the source test feeder, NOT a
# guaranteed bus count ...
#
# ── DATA PROVENANCE / TRANSCRIPTION NOTE (threat T-07-05, ACCEPTED in the plan): ──
#   * TOPOLOGY is transcribed from the canonical IEEE-123 node test feeder ...
#   * PER-UNIT R/X MAGNITUDES are REAL ... sourced from the public IEEE-123 OpenDSS
#     test-case data ..., reduced by `scripts/reduce_ieee123_impedances.jl` into the
#     generated, committed `src/data/ieee123_impedances.jl` ... The Ω→pu conversion
#     happens ONCE at ingestion here, via `to_pu_impedance` — never inside the reduction
#     script.
```
For the 8500 fixture, this header must additionally state the IN-02 "8500-node" caveat
(per-phase node count vs. real bus count, ~4,873) and the D-05 non-comparability note
(S_base=0.5 MVA, NOT directly comparable to the 1 MVA IEEE-13/123 pu figures) — CONTEXT.md
D-05 explicitly requires this docstring statement.

**PerUnitBase + calibration-rationale docstring pattern** (lines 42-59):
```julia
"""
    IEEE123_BASE

The single documented per-unit base for the modified IEEE-123 fixture (thesis Case B):
`S_base = 1 MVA`, `V_base = 4.16 kV`. A FEEDER-SCALE apparent-power base ... is chosen
deliberately so the distribution quantities land at `O(0.1–1)` pu instead of `O(1e-3)` pu ...
"""
const IEEE123_BASE = PerUnitBase(1.0, 4.16)
```
For 8500: TWO bases are needed (MV `PerUnitBase(0.5, 12.47)`, LV `PerUnitBase(0.5, 0.208)`) —
per RESEARCH.md Pattern 2, the `V_base` ratio must match the real ~60:1 transformer turns
ratio (12.47/0.208 ≈ 59.95), NOT an inconsistent pairing like 12.47/0.12.

**Radial branch-list + switch-set + load/transit-split pattern** (lines 82-306):
```julia
const IEEE123_EDGES = [ (150, 149), (149, 1), ... ]
const IEEE123_SWITCH_EDGES = Set([(150, 149), (13, 152), ...])
const IEEE123_LOAD_TERMINALS = [1, 2, 4, 5, ...]
```
The 8500 fixture's analogous constants are GENERATED (from the reduction script), not
hand-transcribed literals — but the shape (edges list, switch-edge set, load-terminal list)
is the same three-way split, now sourced from `ieee8500_impedances.jl` plus the 4 promoted
cap-bus load terminals (D-12) added explicitly.

**Relabel-map pattern (non-contiguous → 1-based contiguous ids)** (lines 308-334):
```julia
function ieee123_relabel_map()
    terminals = sort!(unique!(reduce(vcat, [[p, c] for (p, c) in IEEE123_EDGES])))
    non_root = filter(!=(IEEE123_ROOT_TERMINAL), terminals)
    remap = Dict{Int, Int}(IEEE123_ROOT_TERMINAL => 1)
    for (rank, term) in enumerate(non_root)
        remap[term] = rank + 1
    end
    return remap
end
```
Directly reusable shape — the 8500 feeder's alphanumeric bus names (`R20185`, `X....`, `SX...`)
relabel through the identical dictionary-based approach, just keyed by `String` not `Int`.

**Incidence transcription tripwire** (lines 351-376):
```julia
function _ieee123_assert_incidence(branches, N)
    B = length(branches)
    Irow = Int[]; Jcol = Int[]; Vval = Int[]
    for (b, br) in enumerate(branches)
        push!(Irow, br.from); push!(Jcol, b); push!(Vval, +1)
        push!(Irow, br.to);   push!(Jcol, b); push!(Vval, -1)
    end
    A = sparse(Irow, Jcol, Vval, N, B)
    (nnz(A) == 2B && all(iszero, sum(A; dims = 1))) || throw(ArgumentError(...))
    return A
end
```
Load-bearing at ~4,873 buses (CLAUDE.md's SparseArrays perf note) — reuse verbatim, just
retarget `N`/`branches`.

**Fixture-builder function shape** (lines 379-445, `ieee123_modified`):
```julia
function ieee123_modified()
    vmin, vmax = 0.9, 1.1
    remap = ieee123_relabel_map()
    N = length(remap)
    buses = [Bus(i, vmin, vmax, i == 1) for i in 1:N]
    s_head = to_pu_power(IEEE123_HEAD_SMAX_MVA, IEEE123_BASE)
    s_int = SMAX_NO_LIMIT
    branches = Branch{Float64}[]
    for (p, c) in IEEE123_EDGES
        is_switch = (p, c) in IEEE123_SWITCH_EDGES
        if is_switch
            r, x = IEEE123_SWITCH_R, IEEE123_SWITCH_X
        else
            r_Ω, x_Ω = IEEE123_BRANCH_RX_OHMS[(p, c)]
            r, x = to_pu_impedance(r_Ω, IEEE123_BASE), to_pu_impedance(x_Ω, IEEE123_BASE)
        end
        smax = p == IEEE123_ROOT_TERMINAL ? s_head : s_int
        push!(branches, Branch(remap[p], remap[c], r, x, smax))
    end
    _ieee123_assert_incidence(branches, N)
    return Feeder(buses, branches, 1)   # assert_radial + assert_magnitudes run here
end
build_ieee123() = ieee123_modified()
export ieee123_modified, build_ieee123, ieee123_load_nodes, ieee123_relabel_map
```
D-07's per-voltage-level `vmin`/`vmax` band (MV 0.9-1.1 vs. LV 0.88 floor) means `Bus`
construction can no longer use ONE scalar pair for every bus — this is the one structural
departure from the IEEE-123 shape: branch the `vmin`/`vmax` choice per bus by which voltage
level it belongs to (MV terminal vs. LV `X*`/`SX*`).

**Two-fixture (headline + MV-only control) structure (D-02):** no direct precedent exists for
a "reduced density" control fixture in `ieee123.jl` or `ieee13.jl` — this is new. The
Claude's-discretion note in CONTEXT.md flags this as open (separate builder vs. documented
reduction mode); either can follow `ieee123_modified()`'s single-function shape, just filtering
the LV rungs out before the `Feeder` constructor call.

---

### `src/data/ieee8500_impedances.jl` (generated, committed)

**Analog:** `src/data/ieee123_impedances.jl` (partial read: header + first ~40 entries of 135
lines total)

**Full committed-table format to replicate:**
```julia
# src/data/ieee123_impedances.jl
#
# GENERATED by scripts/reduce_ieee123_impedances.jl — DO NOT hand-edit; re-run the
# script and re-commit if the upstream .dss files change.
#
# Source: raw.githubusercontent.com/tshort/OpenDSS/master/Distrib/IEEETestCases/123Bus/
#         IEEE123Master.dss + IEEELineCodes.DSS, fetched 2026-07-25 (vendored copies
#         committed at scripts/data/, exact case IEEELineCodes.DSS required).
#
# Values are per-segment SERIES IMPEDANCE IN OHMS (positive-sequence, Fortescue-averaged
# from each linecode's rmatrix/xmatrix), NOT per-unit. Converted once at ingestion in
# ieee123_modified() via to_pu_impedance (src/units/PerUnit.jl:53).
#
# Keyed by ORIGINAL IEEE-123 terminal pairs (pre-relabel), matching IEEE123_EDGES exactly
# (src/data/ieee123.jl). NO length-unit conversion applied ...
const IEEE123_BRANCH_RX_OHMS = Dict{Tuple{Int, Int}, Tuple{Float64,Float64}}(
    (1, 2) => (0.0440549242, 0.044661458274999996),   # LineCode=10, Length=0.175
    ...
)
```
For 8500: key type is `Tuple{String,String}` (alphanumeric bus names, not `Tuple{Int,Int}`);
must pin the vendored-source **commit SHA** (not `master`, per CONTEXT.md's explicit note that
`25-DATA-PROVENANCE.md` only pins the git ref today); must document the transformer-reduction
formula and the CT5 sanity value inline as this file's own provenance note, since that formula
is this session's own derivation (RESEARCH.md Assumption A1), not a citable published one.

---

### `ext/TSODSOSCSExt.jl` (provider, request-response)

**Analog:** `ext/TSODSOGurobiExt.jl` (full file, 24 lines) and `ext/TSODSOMosekExt.jl` (20 lines)

**Full extension-module shape to copy:**
```julia
# ext/TSODSOGurobiExt.jl
#
# Package extension for the commercial Gurobi solver (INFRA-02, opt-in).
# OWNER: plan 01-03.
#
# Loaded by Julia ONLY when both TSODSO and Gurobi are present in the active
# environment (weakdep + [extensions] gating — the modern replacement for
# Requires.jl). Gurobi is NEVER a hard dependency and stays removable: it appears
# only under [weakdeps] in Project.toml.
module TSODSOGurobiExt

using TSODSO, Gurobi, JuMP

TSODSO.commercial_optimizer(::TSODSO.GurobiChoice, pc::TSODSO.ProblemClass) =
    optimizer_with_attributes(Gurobi.Optimizer)

end # module TSODSOGurobiExt
```

**DEVIATION required (D-20, RESEARCH.md Pattern 5):** do NOT route through
`commercial_optimizer`/a `*Choice` marker reused from Gurobi/Mosek — SCS is open-source, a
semantic mismatch with that dispatch's own docstring/error message. Introduce a PARALLEL
dispatch function + marker type instead:
```julia
# ext/TSODSOSCSExt.jl (new shape, mirrors the Gurobi/Mosek module exactly otherwise)
module TSODSOSCSExt

using TSODSO, SCS, JuMP

TSODSO.alternative_optimizer(::TSODSO.SCSChoice, pc::TSODSO.ProblemClass) =
    optimizer_with_attributes(SCS.Optimizer, "verbose" => 0)

end # module TSODSOSCSExt
```
The `SCSChoice` marker type declaration belongs in `src/solver/ProblemClass.jl` (mirror
`GurobiChoice`/`MosekChoice`, lines 48-66) and `alternative_optimizer`'s fallback-errors in
`src/solver/factory.jl` (mirror `commercial_optimizer`'s fallback, lines 130-153) — a
byte-for-byte-structural copy with different names and an updated error message that does not
claim "commercial."

**Project.toml wiring pattern:**
```toml
[weakdeps]
Gurobi = "2e9cd046-0924-5485-92f1-d5272153d98b"
MosekTools = "1ec41992-ff65-5c91-ac43-2df89e9693a4"

[extensions]
TSODSOGurobiExt = "Gurobi"
TSODSOMakieExt = "CairoMakie"
TSODSOMosekExt = "MosekTools"
```
Add `SCS = "c946c3f1-2d62-5474-9fac-a2c854d76d31"` (verify UUID at execute time, per
RESEARCH.md's checkpoint:human-verify gate) under `[weakdeps]` and `TSODSOSCSExt = "SCS"`
under `[extensions]`.

---

### `scripts/benchmark_ieee8500.jl` (utility, batch harness)

**Analogs:** `scripts/socp_applicability_sweep.jl` (CLI/sweep shape) + `scripts/repro_stability_check.jl` (DrWatson output scaffold)

**DrWatson output scaffold** (`repro_stability_check.jl` lines 1-40):
```julia
using DrWatson
@quickactivate "TSODSO"
using TSODSO
using Printf
using Dates

const OUT = projectdir("results", "repro_stability_check")
mkpath(OUT)
```

**CLI dispatch + per-substrate branch shape** (`socp_applicability_sweep.jl` lines 445-493):
```julia
function main(args)
    which = isempty(args) || startswith(first(args), "--") ? "both" : first(args)
    ladder = "--tol-ladder" in args

    if which in ("both", "highpv")
        println("\n", "="^96, "\nSubstrate A ...\n", "="^96)
        df = sweep(:highpv)
        CSV.write(joinpath(OUT, "highpv_3bus_sweep.csv"), df)
        report(df, "...", joinpath(OUT, "highpv_3bus_findings.txt"))
        ...
    end
    if which in ("both", "ieee123")
        println(...)
        df = sweep(:ieee123)
        CSV.write(joinpath(OUT, "ieee123_sweep.csv"), df)
        ...
    end
    return nothing
end

main(ARGS)
```
For `benchmark_ieee8500.jl`: replace the two-substrate branch with a `--fixture` flag
(`ieee13`/`ieee123`/`ieee8500-mv`/`ieee8500`, per D-14) and add the `--quick` mode
VALIDATION.md's Wave 0 requires (`julia scripts/benchmark_ieee8500.jl --fixture ieee8500-mv
--quick` must be CI-affordable — a single small density point, not the full sweep). Mirror
the `ladder = "--tol-ladder" in args`-style boolean-flag parsing for `--quick`.

**Try/catch-per-point + printed-control pattern** (`socp_applicability_sweep.jl` lines
445-460): every sweep point is wrapped so one bad point does not kill the run — reuse this
shape for the density-sweep points, especially since D-18 requires a "budget exceeded" row on
timeout rather than a crash.

**Per-point wall-clock timeout (D-18)** — RESEARCH.md "Code Examples" (Clarabel native
`time_limit`), no existing repo precedent (new pattern, HIGH confidence per research):
```julia
model = Model(select_optimizer(SOCP(); time_limit = per_point_budget_s))
optimize!(model)
if termination_status(model) == MOI.TIME_LIMIT
    status = :budget_exceeded
    partial = has_values(model) ? value.(...) : nothing
else
    status = termination_status(model)
end
```

**Monotonic timing idiom to reuse for the assembly-vs-solve split (D-19)** — see
`src/planning/benders.jl` excerpt under Shared Patterns below.

---

### `test/test_ieee8500.jl` (test, request-response)

**Analog:** `test/test_ieee123.jl` (full file, 141 lines)

**`@testitem` construction-invariant shape to copy verbatim (adapting fixture calls):**
```julia
@testitem "ieee123: fixture is radial, contiguous, single-root (ieee123)" tags = [:phase7] begin
    using TSODSO
    @test isdefined(TSODSO, :ieee123_modified)
    if isdefined(TSODSO, :ieee123_modified)
        feeder = ieee123_modified()
        N = length(feeder.buses)
        @test length(feeder.branches) == N - 1
        @test all(i -> feeder.buses[i].id == i, 1:N)
        @test count(b -> b.is_root, feeder.buses) == 1
        @test feeder.buses[feeder.root].is_root
    end
end
```
```julia
@testitem "ieee123: voltage band + per-unit magnitude sanity (ieee123)" tags = [:phase7] begin
    ...
    for br in feeder.branches
        @test br.r > 0
        @test br.x > 0
        @test 0 < br.smax < 100
    end
end
```
```julia
@testitem "ieee123: pinned real-impedance spot-check on branch (149,1) (ieee123)" tags = [:phase7] begin
    ...
    expected_r = TSODSO.to_pu_impedance(0.057967 * 0.4, TSODSO.IEEE123_BASE)
    @test isapprox(br.r, expected_r; atol = 1e-6)
end
```
VALIDATION.md requires an EXPLICIT test asserting the corrected transformer pu values at
`S_base=0.5 MVA` (CT5 → r=3.00/x=2.72 pu) using this SAME pinned-spot-check shape — mirror the
last `@testitem` above exactly, substituting the CT5 branch and the corrected formula.

**CRITICAL EXECUTION CONSTRAINT (not from the analog file, but load-bearing):** despite
`test_ieee123.jl` using `@testitem`, VALIDATION.md's own `<verify>` command
(`julia --project=. test/test_ieee8500.jl`) must run as **plain `Test.jl`**, never
`TestItemRunner`, under `--project=.` (recorded project trap). See `test/test_planning_hardening.jl`
for the same `@testitem` authoring convention used elsewhere in the suite — the file itself is
authored with `@testitem` (for the full-suite `TestItemRunner` run), but the *direct-invocation*
`<verify>` command for THIS phase's tasks must reproduce the relevant `@testitem` bodies as a
standalone `using Test; ...; @testset` script (or otherwise avoid `@run_package_tests`) — do not
write a `<verify>` block that calls TestItemRunner under `--project=.`.

---

### q-only `FixedCapacitor` device (`src/devices/`, transform)

**Analogs:** `src/devices/AbstractDevice.jl` (contract, full file 92 lines) + `src/devices/FourQuadBESS.jl` (q_inject shape, `contribute!` at lines ~344-374 of the read excerpt)

**Contract this device must satisfy** (`AbstractDevice.jl`, "Variant 2 — AGGREGATABLE device"
+ "Widened contract: optional `q_inject` field"):
```
1. it builds ONLY its variables/constraints on `ctx.model` (for FixedCapacitor: NONE);
2. it writes NOTHING to `ctx.residuals` and calls NO `add_to_objective!`;
3. it RETURNS a `(; vars, p_inject, utility)` NamedTuple, OPTIONALLY widened with
   `q_inject::Vector{AffExpr}` (MESH-04, D-09) for a device with a genuine reactive term.
```

**`FourQuadBESS.contribute!`'s q_inject return shape (the pattern to mimic, minus everything
variable-related):**
```julia
function contribute!(d::FourQuadBESS, ctx::ModelContext; T::Int)
    m = ctx.model
    ...
    return (; vars = (; p_ch, p_dch, soc, q, soc0), p_inject, q_inject = q, utility)
end
```

**Concrete minimal device already sketched in RESEARCH.md (Pattern 4) — adapt directly:**
```julia
struct FixedCapacitor <: AbstractDevice
    bus::Int
    q_nom_pu::Float64     # nameplate reactive injection, per-unit, always-on (D-11)
end

function contribute!(d::FixedCapacitor, ctx::ModelContext; T::Int)
    q_const = fill(AffExpr(d.q_nom_pu), T)     # constant AffExpr, no variables
    p_inject = fill(AffExpr(0.0), T)           # no active injection
    utility = zero(QuadExpr)                   # not a decision, nothing to optimize
    return (; vars = NamedTuple(), p_inject, q_inject = q_const, utility)
end
```

**Aggregator roll-up this plugs into (DEV-05 sole-writer invariant, D-12) — the `hasproperty`
guard that makes `q_inject` optional and additive:**
```julia
# src/devices/Aggregator.jl, contribute!(agg::Aggregator, ctx; T)
q_inject = AffExpr[zero(AffExpr) for _ in 1:T]
...
for d in agg.devices
    res = contribute!(d, ctx; T = T)
    for t in 1:T
        p_inject[t] += res.p_inject[t]
    end
    if hasproperty(res, :q_inject)
        for t in 1:T
            q_inject[t] += res.q_inject[t]
        end
    end
    utility += res.utility
    push!(device_vars, res.vars)
end
...
add_to_residual!(ctx, :Rq, agg.bus, t, -Pdc_param[t] * tanφ + q_inject[t])  # (3.23) + D-10
```
D-12's "promote the 4 no-load cap buses to zero-`Pdc` load buses, each hosting a q-only
Aggregator" means: construct an `Aggregator(bus, φ, [FixedCapacitor(bus, q_nom_pu)], Pdc=zeros(T))`
at each of the 4 promoted buses — no `Aggregator` code change needed, since `Pdc=0` and one
device with `q_inject` already composes correctly through the existing roll-up.

**Include-graph placement:** add `include("devices/FixedCapacitor.jl")` (or chosen name) in
`src/TSODSO.jl` immediately after `include("devices/FourQuadBESS.jl")` and before
`include("devices/Aggregator.jl")` — mirrors the existing device-then-aggregator ordering.

---

### New literate page `docs/literate/ieee8500_scaling.jl` (component, transform)

**Analog:** `docs/literate/socp_applicability.jl` — CRITICAL precedent per D-17's revision (this
page already solves the exact docs-CI budget problem D-17 now follows)

**Admonition-block pattern stating which figures are precomputed and why** (lines 410-420):
```julia
# ## Substrate B — real IEEE-123 impedances (precomputed)
#
# !!! note "This map is precomputed, and deliberately so"
#     The IEEE-123 sweep costs **~68 s per solve** (123 buses, 122 branches, 85 load nodes, T=24), so
#     54 points take ~16 minutes — more than the documentation CI job's entire 30-minute budget. It is
#     therefore **loaded from committed data**, not solved here. Regenerate with:
#     ```
#     julia --project=. scripts/socp_applicability_sweep.jl ieee123 --tol-ladder
#     ```
#     which writes `results/socp_applicability/ieee123_sweep.csv` — the exact file read below.
#     Everything in Substrate A above, by contrast, was solved live at build time.
```
Reuse this exact admonition shape, substituting the ~40x-larger fixture's own measured
per-point cost and pointing the regeneration command at `scripts/benchmark_ieee8500.jl`.

**`Base`-only CSV parsing helper — copy verbatim (the docs env must NOT gain
CSV/DataFrames):**
```julia
# Parsed with `Base` only: the docs environment pins a minimal dependency set ...
function read_sweep_csv(path)
    lines = readlines(path)
    header = split(first(lines), ',')
    idx = Dict(strip(h) => i for (i, h) in enumerate(header))
    num(s) = (v = tryparse(Float64, s); v === nothing ? NaN : v)
    return map(lines[2:end]) do ln
        f = split(ln, ',')
        (; vmax = num(f[idx["vmax"]]), load = num(f[idx["load"]]), ...)
    end
end

rows_123 = read_sweep_csv(
    joinpath(pkgdir(TSODSO), "results", "socp_applicability", "ieee123_sweep.csv"),
)
```
Adapt the field list to the D-19 metrics schema (wall time split, iteration count, peak
memory, termination status, cone-gap floor, exactness verdict) instead of the applicability
page's `(vmax, load, pv, ratio, atvmax, vpeak, minP, class)` tuple.

**`using TSODSO.JuMP` (not `using JuMP`) — the docs-dependency-minimization idiom** (lines
28-33):
```julia
using TSODSO
## `TSODSO.JuMP` rather than `using JuMP`: the docs environment pins a deliberately minimal
## dependency set, and JuMP is already loaded as a dependency of TSODSO ...
using TSODSO.JuMP
using Printf
```

**`docs/make.jl` wiring pattern** (lines 13-43, the `for src in (...)` literate-page list):
```julia
for src in (
    ...
    "socp_applicability.jl",
    ...
)
    Literate.markdown(joinpath(LITERATE_DIR, src), GENERATED_DIR; ...)
end
```
Append `"ieee8500_scaling.jl"` to this tuple, plus a matching `"Scaling to IEEE-8500" =>
"generated/ieee8500_scaling.md"` entry in the page-title map (mirrors line 80's
`"SOC Relaxation Applicability" => "generated/socp_applicability.md"`).

---

### `src/TSODSO.jl` (MODIFIED, include graph)

**Existing wiring to extend (verbatim shape, lines 34-41 and 80-91):**
```julia
include("data/ieee13.jl")
# STUB seam wired here by plan 07-01 (after ieee13.jl in the data block); filled by 07-02.
include("data/ieee123.jl")
...
include("devices/FourQuadBESS.jl")   # plan 19-02, MESH-04
include("devices/Aggregator.jl")
```
Add `include("data/ieee8500_impedances.jl")` is NOT separately included at this level —
`ieee123_impedances.jl` is `include`d FROM WITHIN `ieee123.jl` (see that file's line 40,
`include("ieee123_impedances.jl")`), so `ieee8500.jl` should do the same
(`include("ieee8500_impedances.jl")` at its own top) — only `include("data/ieee8500.jl")`
needs adding to `TSODSO.jl` itself, immediately after the `ieee123.jl` include.

---

### `src/experiments/materialize.jl` (MODIFIED, service/CRUD)

**`build_feeder` registry pattern to extend** (lines 27-45):
```julia
function build_feeder(sym::Symbol)
    if sym === :ieee13
        return ieee13_modified()
    elseif sym === :ieee123
        return ieee123_modified()
    else
        throw(ArgumentError("build_feeder: unknown feeder selector $(repr(sym)); expected :ieee13 or :ieee123"))
    end
end
```
Add `elseif sym === :ieee8500-mv` / `:ieee8500` branches BEFORE the `else` (note: `:ieee8500-mv`
is not a valid bare Julia `Symbol` literal without quoting — use `Symbol("ieee8500-mv")` or
choose an underscore variant like `:ieee8500_mv`; flag this naming detail for the planner).

**`_load_buses` dispatch-on-selector pattern to extend** (lines 181-190):
```julia
function _load_buses(feeder, feeder_sym::Symbol)
    if feeder_sym === :ieee123
        return ieee123_load_nodes()
    end
    return [b.id for b in feeder.buses if !b.is_root]
end
```
Add an `elseif feeder_sym in (:ieee8500, :ieee8500_mv)` branch returning the 8500 fixture's own
load/transit split function (mirrors `ieee123_load_nodes()`).

**Existing scalar `load_scale` population pattern — the one D-03 explicitly departs from**
(lines 121-129, 200-247, 263-296):
```julia
const _IEEE123_LOAD_SCALE = 0.03
...
Pdc = Float64[load_scale * d for d in prof.demand]
...
load_scale, pv_scale, dev_scale = if feeder_sym === :ieee123
    (_IEEE123_LOAD_SCALE, _IEEE123_PV_SCALE, _IEEE123_DEV_SCALE)
else
    (_IEEE13_LOAD_SCALE, _IEEE13_PV_SCALE, _IEEE13_DEV_SCALE)
end
return [_default_house(bus, profiles, seed, T; φ=0.90, load_scale=load_scale, ...) for bus in buses]
```
**NEW code path required (RESEARCH Pitfall 4):** cannot reuse this scalar-`load_scale` shape
for D-03's per-bus real kW. Add either (a) a new `build_population` branch keyed on
`feeder_sym === :ieee8500` threading a `Dict{Int,Float64}` (bus → real kW pu) into a NEW
`_default_house`-like function that takes a per-bus magnitude directly in place of the scalar
`load_scale * d` multiply, or (b) a parallel function. Either is a genuinely new code path per
RESEARCH.md — do not "average" the real kW into one scalar.

---

### `src/solver/factory.jl` + `src/solver/ProblemClass.jl` (MODIFIED)

**Marker-type pattern to extend** (`ProblemClass.jl` lines 48-67):
```julia
struct GurobiChoice end
struct MosekChoice end
export ProblemClass, LP, MILP, QP, SOCP, NLP, GurobiChoice, MosekChoice
```
Add `struct SCSChoice end` alongside these, exported too.

**Fallback-errors dispatch pattern to extend** (`factory.jl` lines 130-153):
```julia
function commercial_optimizer(choice, pc::ProblemClass)
    error("""
        No commercial optimizer is available for choice $(choice) and problem class $(pc).
        Commercial solvers are opt-in weakdep extensions and are never hard dependencies.
        To enable one, load the solver in your environment, e.g.:
            import Gurobi      # enables commercial_optimizer(GurobiChoice(), pc)
            import MosekTools  # enables commercial_optimizer(MosekChoice(), pc)
        """)
end
export select_optimizer, commercial_optimizer
```
Add a PARALLEL `alternative_optimizer(choice, pc::ProblemClass)` fallback with the same shape
but wording that does NOT say "commercial" (SCS is open-source) — e.g. "No alternative
optimizer is available ... Alternative solvers are opt-in weakdep extensions ...". Export
`alternative_optimizer` alongside `select_optimizer`/`commercial_optimizer`.

---

### `src/admm/solve_admm.jl` (POSSIBLY MODIFIED, event-driven)

**No direct existing analog for a wall-clock-bounded ADMM loop.** The closest pattern is the
monotonic `time_ns` bracketing idiom from `src/planning/benders.jl` (Benders' outer loop, a
different but structurally similar iterative decomposition):
```julia
t_solve = 0.0
t0_ns = time_ns()
lb_res = solve_master!(master; attempts_out = master_attempts)
t_solve += (time_ns() - t0_ns) / 1.0e9
```
If the planner picks RESEARCH.md's option (a) — a minimal, additive `time_limit_s::Union{Nothing,Real}=nothing`
kwarg on `solve_admm` that checks `time_ns()` at the top of each iteration and breaks with a
`:budget_exceeded` status field — this is the idiom to extend: wrap the existing `for k in
1:maxiter` loop body with a `t0_ns = time_ns()` check at loop top, `(time_ns() - t0_ns)/1e9 >
time_limit_s && (status = :budget_exceeded; break)`, mirroring how `benders.jl` already
threads a monotonic elapsed accumulator through its own loop (see also
`src/admm/solve_admm.jl:581-588`'s existing "FAIL LOUD on the maxiter cap" throw — the new
`:budget_exceeded` exit must NOT silently return a non-consensus iterate either; it should
still be an explicit, loud, documented status, mirroring the maxiter-throw's own honesty
convention rather than introducing a silent partial-result return).

---

## Shared Patterns

### Monotonic timing (assembly-vs-solve split, D-19)
**Source:** `src/planning/benders.jl:204-269`, `src/planning/trace.jl:77`
**Apply to:** `scripts/benchmark_ieee8500.jl` (every metric row), possibly `solve_admm.jl`
```julia
# with the MONOTONIC clock (time_ns), immune to the NTP steps that could make
# a time()-based span negative
t_solve = 0.0
t0_ns = time_ns()
lb_res = solve_master!(master; attempts_out = master_attempts)
t_solve += (time_ns() - t0_ns) / 1.0e9
```
BenchmarkTools is NOT a project dependency (CLAUDE.md) — do not add it; this idiom plus
`Base.gc_live_bytes()`/`Sys.maxrss()` sampled at the same checkpoints covers D-19's peak-memory
metric too (per RESEARCH.md "Don't Hand-Roll").

### Solver factory dispatch (never name a solver outside `src/solver/`)
**Source:** `src/solver/factory.jl:32-55`, `ProblemClass.jl`
**Apply to:** `scripts/benchmark_ieee8500.jl`, `ext/TSODSOSCSExt.jl`
```julia
select_optimizer(::SOCP; attrs...) = optimizer_with_attributes(
    Clarabel.Optimizer, "verbose" => false, "tol_gap_abs" => 1e-8, "tol_gap_rel" => 1e-8,
    (String(k) => v for (k, v) in pairs(attrs))...,
)
```
Every model in this phase (centralized SOCP solve, ADMM subproblems, SCS comparison run) must
route through `Model(select_optimizer(SOCP(); ...))` or the new `alternative_optimizer` path —
never `Model(Clarabel.Optimizer)`/`Model(SCS.Optimizer)` directly.

### Construction-as-invariant (Feeder radial + magnitude asserts)
**Source:** `src/data/ieee123.jl:443-444`, `src/data/Feeder.jl`, `src/units/PerUnit.jl:56-73`
**Apply to:** `src/data/ieee8500.jl` (both fixtures)
```julia
_ieee123_assert_incidence(branches, N)     # transcription tripwire on the relabel step
return Feeder(buses, branches, 1)          # assert_radial + assert_magnitudes run here
```
An invalid feeder (non-radial, magnitude out of sanity band) can never be constructed — this
is why D-09 needs no core-struct change, and why the incidence self-check must run BEFORE the
`Feeder(...)` call at ~4,873-bus scale (a genuinely error-prone hand-assembled/generated
branch list).

### Per-fixture-only tolerance derivation (anti-certificate-laundering)
**Source:** `src/models/exactness.jl:23-60`
**Apply to:** noise-floor calibration task (SCALE-05), `test/test_ieee8500.jl`
```julia
"""
    assert_socp_exact!(ctx::ModelContext; rtol::Real = 1e-4, atol::Real = 1e-6) -> maxgap::Float64
...
gap ≤ atol + rtol · max(|lhs|, |rhs|)
"""
```
The gate itself (WR-01 combined `atol+rtol·magnitude` classification) is reused UNCHANGED —
only the `atol`/`rtol` NUMBERS are re-derived at ~4,900-branch scale via the spike-002 ladder
method (RESEARCH.md "Code Examples > Noise-floor calibration ladder"). Never reuse IEEE-13/123's
numbers directly (Phase 20/23 standing rule, restated in CONTEXT.md canonical refs).

### Optional device widening via `hasproperty` (additive, zero-cost when absent)
**Source:** `src/devices/Aggregator.jl:186-199`
**Apply to:** the new `FixedCapacitor` device
```julia
if hasproperty(res, :q_inject)
    for t in 1:T
        q_inject[t] += res.q_inject[t]
    end
end
```
No `Aggregator` code changes for this phase — the seam already exists (Phase 19, MESH-04).

## No Analog Found

| File/Aspect | Role | Data Flow | Reason |
|---|---|---|---|
| Density-sweep grid harness exact shape (fixture × density × solver × {centralized, ADMM}) | utility | batch | No existing script sweeps FOUR independent axes at once; `socp_applicability_sweep.jl` sweeps (pv, load, vmax) on ONE solver/fixture. Synthesized from that script's CLI/CSV/report shape + `repro_stability_check.jl`'s DrWatson output scaffold — treat as a role-match, not exact. |
| Per-bus real-kW population path (D-03) | service | CRUD | `build_population`/`_default_house` has no existing per-bus-heterogeneous-magnitude branch; RESEARCH.md explicitly flags this as "a genuinely new code path, not a parameter tweak" — use RESEARCH.md's Pitfall 4 guidance (Dict{Int,Float64} threaded into a new `_default_house`-like function) rather than an existing pattern. |
| Wall-clock-bounded ADMM outer loop | service | event-driven | `solve_admm` has no existing time-based exit (RESEARCH Pitfall 6, Open Question 1) — this is a genuine plan-time design decision, not a copy-paste. The monotonic `time_ns` idiom from `benders.jl` transfers for the MEASUREMENT half; the BREAK/exit-status half has no precedent in this codebase. |
| Two-fixture (headline + control) single-source builder | model | CRUD | No existing fixture ships a "reduced" sibling variant; `ieee13.jl`/`ieee123.jl` each ship exactly one fixture function. D-02's MV-only control fixture is new fixture-authoring territory (Claude's discretion on separate-builder-vs-mode). |

## Metadata

**Analog search scope:** `scripts/`, `src/data/`, `src/devices/`, `src/solver/`, `src/admm/`,
`src/planning/`, `src/models/`, `src/experiments/`, `ext/`, `test/`, `docs/literate/`,
`docs/make.jl`, `Project.toml`.
**Files scanned:** ~20 read directly (full or targeted excerpt): `scripts/reduce_ieee123_impedances.jl`,
`src/data/ieee123.jl`, `src/data/ieee123_impedances.jl` (partial), `ext/TSODSOGurobiExt.jl`,
`ext/TSODSOMosekExt.jl`, `src/solver/factory.jl`, `src/solver/ProblemClass.jl`,
`src/devices/AbstractDevice.jl`, `src/devices/FourQuadBESS.jl` (partial), `src/devices/Aggregator.jl`
(partial), `src/experiments/materialize.jl` (partial), `docs/literate/socp_applicability.jl`
(partial), `scripts/socp_applicability_sweep.jl` (partial), `scripts/repro_stability_check.jl`
(partial), `src/planning/benders.jl` (partial), `src/units/PerUnit.jl` (partial),
`src/models/exactness.jl` (partial), `test/test_ieee123.jl` (full), `test/test_planning_hardening.jl`
(partial), `src/TSODSO.jl` (grep), `docs/make.jl` (partial), `Project.toml` (grep).
**Pattern extraction date:** 2026-08-20

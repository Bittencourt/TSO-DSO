# Phase 18: Directional Thesis Reproduction - Pattern Map

**Mapped:** 2026-07-26
**Files analyzed:** 6 (all CREATE; `docs/make.jl` MODIFY)
**Analogs found:** 6 / 6 (this is a pure COMPOSITION phase — every seam already exists in `src/`)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `scripts/repro_stability_check.jl` | script (measurement harness) | batch (N-repeat + parameter sweep) | `scripts/reactive_flake_rate.jl` | exact (same author, same shape, same committed-findings convention) |
| `scripts/thesis_case123_repro.jl` | script (reproduction/report) | batch (solve → account → plot) | `scripts/thesis_caseA.jl` | exact (same script, different fixture + metric) |
| `docs/literate/thesis_reproduction_ieee123.jl` | doc (literate page) | transform (script → live-executed markdown) | `docs/literate/ieee123_impedances.jl` | exact (same Literate.jl convention) |
| `docs/literate/thesis_reproduction_assumptions.jl` | doc (literate page, narrative) | transform (narrative + light live code) | `docs/literate/ieee123_impedances.jl` | role-match (no pure-narrative page exists yet; borrow the same convention, lighter code ratio) |
| `docs/make.jl` (MODIFY) | config (Documenter/Literate registration) | batch (render loop + nav tree) | itself — `ieee123_impedances` entry (lines 30, 65) | exact (literal 2-line-per-page pattern to replicate twice) |
| `test/test_thesis_repro.jl` | test (`@testitem`, gate-then-golden) | request-response (solve → assert) | `test/test_acceptance.jl` | exact (same 3-stage gate-then-golden convention, same `Phase7Fixtures` setup) |

## Pattern Assignments

### `scripts/repro_stability_check.jl` (script, batch measurement)

**Analog:** `scripts/reactive_flake_rate.jl` (full file, 457 lines) + its committed output `results/reactive_flake_rate/flake_rate_findings.txt`

**Header/provenance comment pattern** (lines 1-31):
```julia
# scripts/reactive_flake_rate.jl
#
# Phase 16 (reactive-power consensus) — the phase's two REQUIRED empirical measurements
# (16-RESEARCH.md Pitfall 5 / Open Questions 1-2), run as a re-runnable DrWatson-convention
# script, NOT a `@testitem` (long-running, N>=20 repeats x 2 fixtures x 2 modes = 80+ solves).
# ...
# FIXTURE CONSTRUCTION NOTE: `Phase4Fixtures`/`Phase7Fixtures` are `TestItems.@testmodule`
# blocks. The standalone `TestItems.jl` package ... expands `@testmodule` to a no-op
# (`return nothing`) — so `include("test/fixtures_phase7.jl")` from a plain script does NOT
# actually define `Phase7Fixtures` outside the test-runner's special AST-introspection path.
# Per this plan's own instruction, the population construction is therefore RE-IMPLEMENTED
# INLINE below, copied verbatim from `test/fixtures_phase4.jl`/`test/fixtures_phase7.jl`...
```
**CRITICAL for the new script:** it must re-implement the IEEE-123 population inline (copy
`_house_aggregator`, `build_ieee123_aggregators`, `ieee123_lambda0`, `temperature_profile`, and
the constants `SEED_IEEE123=20260719`, `LOAD_SCALE_IEEE123=0.05`, `PV_SCALE_IEEE123=0.12`,
`DEV_SCALE_IEEE123=0.05*(0.05/0.03)`) verbatim from `test/fixtures_phase7.jl:92-95, 141-284` —
`@testmodule` is a no-op outside `TestItemRunner`, exactly the trap this analog already
documents and avoids.

**DrWatson output-dir + save pattern** (lines 33-40):
```julia
using DrWatson
@quickactivate "TSODSO"
using TSODSO
using Printf
using Dates

const OUT = projectdir("results", "reactive_flake_rate")
mkpath(OUT)
```

**N-repeat measurement pattern** (lines 273-310, `count_failures`):
```julia
function count_failures(
    feeder, aggs, λ₀;
    reactive_consensus::Bool, n_repeats::Int = 20, seed_offset::Int = 0,
)
    failures = 0
    for i in 1:n_repeats
        jitter = 1e-9 * (i + seed_offset)
        λ₀_i = λ₀ .+ jitter
        try
            solve_admm(feeder, ConvexBranchFlow(), aggs; T = T, λ₀ = λ₀_i, ρ = RHO0, ...)
        catch e
            failures += 1
            @warn "solve_admm failed during reactive-flake-rate measurement" repeat = i ...
        end
    end
    return failures
end
```
For Phase 18, mirror this shape but call `solve_welfare`/`welfare_accounting`/`fit_baseline`
(not `solve_admm`) inside the `try`, and — per RESEARCH Pitfall 5 — this session's live 8-repeat
probe found **zero value jitter** (`std = 7.276e-12`) on identical inputs, so budget effort on
(a) the discrete flake-RATE (same `try/catch`-counter shape) and (b) the NEW population-scale
sweep (±2-5% on `LOAD_SCALE_IEEE123`/`PV_SCALE_IEEE123`), which this analog does NOT already do
— write a second loop varying the scale constants and re-checking `sign(acct.dso)`/`sign(fit_dso)`
at each perturbed point, not just re-solving the identical problem.

**Committed-findings-artifact pattern** (lines 374-457, `report_path` + `open(..., "w") do io ... end`):
```julia
report_path = joinpath(OUT, "flake_rate_findings.txt")
open(report_path, "w") do io
    println(io, "Phase 16 Reactive-Power Consensus — Clarabel Flake-Rate Measurement")
    println(io, "Measured: ", Dates.format(now(), "yyyy-mm-dd HH:MM:SS"), " UTC-local")
    println(io, "Repeats per cell: N = $N_REPEATS (80 solves total)")
    ...
    println(io, "=== Finding 1: ... ===")
    println(io, "... This is a citable phase finding, not a pass/fail gate ...",
        "the number itself is the deliverable, reported here neither silently ",
        "accepted nor silently \"fixed.\"")
end
println("\nWrote findings to: ", report_path)
```
**Output artifact target:** `results/repro_stability_check/findings.txt` (mirror the exact
filename/path shape, at `results/<script-name>/findings.txt`).

**Reference numbers already measured this session** (from `18-RESEARCH.md`, to seed the sweep
design, NOT to hard-code as an assumed-passing result): DSO surplus sign flip at the exact
Phase-17-retuned point is FIT dso=-196.22 → DADP dso=+3.73 (IEEE-123), and FIT dso=-5.32 →
DADP dso=+2.56 (IEEE-13 `ground`). 8 identical back-to-back re-solves were bit-for-bit
identical (`std=7.276e-12`) — confirms no re-solve jitter, only flake (exception) risk and
population-scale sensitivity are open.

---

### `scripts/thesis_case123_repro.jl` (script, reproduction/report)

**Analog:** `scripts/thesis_caseA.jl` (full file, 399 lines) — same author, same shape; this new
script targets IEEE-123 real-impedance instead of IEEE-13, and swaps the PRIMARY metric.

**Imports + output-dir pattern** (lines 33-47):
```julia
using DrWatson
@quickactivate "TSODSO"
using TSODSO
using CairoMakie
using Printf
using Statistics
using JuMP: value, Model, @variable, @constraint, @objective, optimize!

const OUT = projectdir("results", "thesis_caseA")
mkpath(OUT)

saveboth(name, fig) = (save(joinpath(OUT, "$name.pdf"), fig); save(joinpath(OUT, "$name.png"), fig))
```
For the new script, use `OUT = projectdir("results", "thesis_case123_repro")` and reuse the
population-building inline pattern from `test/fixtures_phase7.jl`'s `Phase7Fixtures` module
(re-implement inline, same reasoning as the stability script above, OR — since this is a script
not a `@testitem` — it may be simpler to directly call `ieee123_modified()` + `Phase7Fixtures`
constants copy-pasted, matching `scripts/reactive_flake_rate.jl`'s established inline-copy
convention).

**DADP + FIT + surplus-split solve composition** (lines 70-134, the seam this whole phase
composes — verbatim from `18-RESEARCH.md`'s own "Code Examples" section, cross-checked against
`src/pricing/welfare.jl`/`src/pricing/fit.jl`):
```julia
ctx_dadp, welfare_dadp, _ = solve_welfare(
    FEEDER, PF, aggs; T = T, λ₀ = λ₀, allow_export = true, τ = 1e-2,
)
dadp   = extract_dlmp(ctx_dadp)[load_buses, :]
decomp = decompose_dlmp(ctx_dadp)
acct   = welfare_accounting(ctx_dadp; T = T)         # (; social, dso, prosumer)
pimp   = Float64[value.(ctx_dadp.meta[:p_import])...]
maxgap = ctx_dadp.meta[:socp_maxgap]
```
FIT baseline — **use the plain `fit_baseline(feeder, pf, aggs; T, λ₀)` seam directly** (do NOT
copy `thesis_caseA.jl`'s manual `S_max`-relaxed hand-rolled FIT solve, lines 97-131 — that
machinery exists ONLY because IEEE-13 Case A is congestion-driven and `fit_baseline`'s
voltage-only relaxation is infeasible there; IEEE-123 is voltage-driven and `fit_baseline`
was CONFIRMED FEASIBLE live this session):
```julia
fb = fit_baseline(feeder, pf, aggs; T = T, λ₀ = λ₀)  # (; social_fit, prosumer_surplus, ...)
fit_dso = fb.social_fit - fb.prosumer_surplus         # NOT a returned field — compute manually
```

**Sign-safe directional metric — REPLACES `thesis_caseA.jl`'s `ratio` (lines 130-134,
`132: ratio = welfare_dadp / welfare_fit`)**, which is the ANTI-PATTERN to avoid here (Pitfall 1,
sign-inversion trap on negative-valued welfare). The new script's headline print block should
follow this shape instead:
```julia
@assert acct.dso > 0.0 && fit_dso < 0.0            # the genuine sign flip (headline)
@assert acct.prosumer < fb.prosumer_surplus         # prosumer decreases under DADP
println("  DSO surplus:  FIT=$(fit_dso)  ->  DADP=$(acct.dso)  (sign flip $(cite_repro()))")
println("  Prosumer surplus: FIT=$(fb.prosumer_surplus) -> DADP=$(acct.prosumer) (decreases $(cite_repro()))")
println("  Aggregate welfare delta (secondary, thin): $(welfare_dadp - fb.social_fit) $(cite_repro())")
```
Report the aggregate `welfare_dadp - fb.social_fit` as a SECONDARY line only, never the
primary headline (see "directional, public-data" qualifier wrapper below).

**Figure/plotting conventions to reuse verbatim** (CairoMakie, `saveboth` helper, `Fig D` shape
at lines 313-344 is the closest template for a new "DSO surplus sign flip" bar chart — reuse
the axS "surplus split" bar-pair-per-scheme layout, but change the annotation text from a
`ratio-1` percentage to a plain sign-flip label):
```julia
let
    fig = Figure(; size = (950, 520))
    ...
    axS = Axis(fig[1, 2]; xlabel = "pricing scheme", ylabel = "surplus (per-unit)",
        xticks = (1:2, ["FIT", "DADP"]), title = "(b) prosumer vs DSO surplus")
    barplot!(axS, [1], [fit_prosumer]; color = :dodgerblue, label = "prosumer")
    barplot!(axS, [1], [fit_dso]; offset = [fit_prosumer], color = :orange, label = "DSO")
    barplot!(axS, [2], [acct.prosumer]; color = :dodgerblue)
    barplot!(axS, [2], [acct.dso]; offset = [acct.prosumer], color = :orange)
    axislegend(axS; position = :lt)
    saveboth("figD_dadp_vs_fit_surplus", fig)
end
```

**Reactive DLMP citation** (Pattern 3, `src/pricing/dlmp.jl:138-152`, `extract_reactive_dlmp`):
```julia
d = decompose_dlmp(ctx_dadp)   # d.reactive is populated on a PLAIN solve_welfare ctx
```
No `reactive_consensus` kwarg needed — `solve_welfare` never accepts it (Pitfall 3); it is
`solve_admm`/`build_dso_opt`-only.

**Final-summary print block to model** (lines 383-399, replace the `ratio < 1.02` branch logic
with the sign-flip framing, and thread the qualifier — see Shared Patterns below):
```julia
println("\n" * "=" ^ 72)
@printf("RESULT: DADP/FIT social-welfare ratio = %.4f  (thesis Case A target ≈ 1.25)\n", ratio)
if ratio < 1.02
    println("""
NOTE: on the repo's :default 1-house-per-bus proxy population the ratio is ≈ 1.0, ...
""")
else
    println("DADP beats FIT by +$(round(100 * (ratio - 1); digits = 1))% social welfare ...")
end
```

---

### `docs/literate/thesis_reproduction_ieee123.jl` (doc, literate page)

**Analog:** `docs/literate/ieee123_impedances.jl` (full file, 121 lines)

**Header/title/citation convention** (lines 1-9):
```julia
# # IEEE-123 Real Impedances — Public-Data Reduction
#
# This page documents WHERE the modified IEEE-123 fixture's branch impedances actually come
# from ([`ieee123_modified`](@ref), `src/data/ieee123.jl`): ... It calls the real
# [`ieee123_modified`](@ref) end-to-end — never a re-implemented reduction — so the numbers
# below cannot silently drift from the committed data ...
```
For the new page: `# # Thesis Case A Reproduction — Real-Impedance IEEE-123` header, and the
SAME "calls the real production function, never a re-derivation" guarantee, citing
`solve_welfare`/`fit_baseline`/`welfare_accounting`/`decompose_dlmp` as the real entrypoints.

**Citation bracket convention** (lines 71, 96): `` `[CITED: opendss.epri.com/LineCode1.html]` ``
— Phase 18 must use the SAME bracket convention for thesis citations, e.g.
`` `[CITED: thesis p.98, Case A]` ``, AND for the qualifier phrase (see Shared Patterns).

**Live-executed-call-ends-the-page convention** (lines 95-121, `## 5. Live execution` section
+ final unassigned expression as the last statement so Documenter renders its value):
```julia
using TSODSO

feeder = ieee123_modified()

length(feeder.branches) == length(feeder.buses) - 1 ||
    throw(ArgumentError("radial invariant violated: |branches| must equal |buses|-1"))

(length(feeder.buses), length(feeder.branches))

first(b for b in feeder.branches if b.r > 0 && b.x > 0)
```
The new page must end similarly: call `solve_welfare`, `fit_baseline`, `welfare_accounting`,
`decompose_dlmp` for real (source them from `scripts/thesis_case123_repro.jl`, promoted, not
hand-copied) and let the final DSO-surplus-sign-flip tuple be the page's terminal expression.

**Markdown H1/H2 comment-prefix convention:** `# # Title` / `# ## Section` throughout — mirror
exactly (Literate.jl's `DocumenterFlavor()` markdown-comment syntax).

---

### `docs/literate/thesis_reproduction_assumptions.jl` (doc, narrative literate page)

**Analog:** same file (`docs/literate/ieee123_impedances.jl`), used as the closest available
convention since no purely-narrative literate page exists yet in this repo (`18-RESEARCH.md`
Open Question 2). Reuse:
- The same `# # Title` / `# ## Section` heading convention.
- The same numbered-subsection narrative style (`## 1. ...`, `## 2. ...`, — see lines 10, 29,
  64, 80 for the "numbered subsection, prose + inline code block" shape).
- The "Reduction caveats" bullet-list convention at lines 80-93 as the direct template for this
  page's assumptions/omissions enumeration (units resolution, Fortescue reduction fidelity,
  omitted regulators/caps/switches, population re-tune LOAD=0.05/PV=0.12/DEV≈0.0833, the
  welfare-ratio-vs-surplus-sign metric caveat, the asymmetric voltage-binding caveat from
  Phase 17).
- Per Open Question 2's recommendation: keep a SMALL amount of live code (e.g. re-stating
  `length(ieee123_load_nodes())` and the retuned scale constants) so the page "cannot silently
  drift from `src/`" — do not make it 100% prose; mirror the closing live-execution pattern
  above but with a lighter code:prose ratio than the reproduction page.

---

### `docs/make.jl` (MODIFY — config, render+nav registration)

**Analog:** the file's own EXISTING `ieee123_impedances` entry (this is a "add 2 more of the
same" modification, not a new pattern).

**Render-loop entry to replicate (2x)** (line 30, inside the `for src in (...)` tuple at
lines 20-31):
```julia
for src in (
    "toy_dc.jl",
    ...
    "ieee123_impedances.jl",    # NEW: real IEEE-123 impedance reduction (IMPED-01/02)
)
    Literate.markdown(
        joinpath(LITERATE_DIR, src),
        GENERATED_DIR;
        flavor = Literate.DocumenterFlavor(),
    )
end
```
Add `"thesis_reproduction_ieee123.jl",` and `"thesis_reproduction_assumptions.jl",` as two new
tuple entries, each commented `# NEW: ... (REPRO-01)` / `# NEW: ... (REPRO-02)`.

**Nav-tree (`pages=`) entry to replicate (2x)** (line 65, inside the `"Models" => [...]` list
at lines 55-71):
```julia
pages = [
    "Home" => "index.md",
    "Models" => [
        ...
        "IEEE-123 Real Impedances" => "generated/ieee123_impedances.md",
    ],
    "Planning" => [ ... ],
    "API Reference" => "api.md",
],
```
Add `"Thesis Reproduction — IEEE-123" => "generated/thesis_reproduction_ieee123.md",` and
`"Thesis Reproduction — Assumptions" => "generated/thesis_reproduction_assumptions.md",` (a
new top-level nav section, e.g. `"Reproduction" => [...]`, is also reasonable, but MINIMALLY
add both entries under "Models" alongside "IEEE-123 Real Impedances" to keep the diff
mechanical and small — planner's/executor's discretion on section placement, not on whether
both entries exist).

**Do NOT touch:** `checkdocs = :exports`, `warnonly = [:cross_references]`, `remotes = nothing`,
or the `deploydocs` CI gate (lines 39-98) — none of that changes for this phase.

---

### `test/test_thesis_repro.jl` (test, gate-then-golden `@testitem`)

**Analog:** `test/test_acceptance.jl` (full file, 147 lines) — the IEEE-123 item
(lines 98-147) is the closer structural template (same fixture module, same feeder); the
IEEE-13 item (lines 23-96) demonstrates the FULL 3-stage gate-then-golden shape including the
non-failing `broken=` cross-check.

**`@testitem` header + setup convention** (lines 98-106):
```julia
@testitem "acceptance: IEEE-123 voltage — exact relaxation + DADP + ADMM≈centralized (SC3)" tags =
    [:acceptance] setup = [Phase7Fixtures] begin
    using TSODSO

    feeder = ieee123_modified()
    aggs = Phase7Fixtures.build_ieee123_aggregators(feeder)
    load_buses = [a.bus for a in aggs]
    Th = Phase7Fixtures.T
    λ₀ = Phase7Fixtures.ieee123_lambda0()
```
Mirror exactly: `@testitem "thesis_repro: IEEE-123 real-impedance DADP-vs-FIT — DSO-surplus
sign flip (REPRO-01)" tags = [:thesis_repro] setup = [Phase7Fixtures] begin ... end` (the
`filter=ti->occursin("thesis_repro", ti.name)` command in RESEARCH's Validation Architecture
depends on this exact substring appearing in the item name).

**3-stage gate-then-golden shape** (lines 273-295 of `18-RESEARCH.md`'s own Pattern 1
extraction, cross-checked against `test_acceptance.jl:53-95`'s literal structure):
```julia
@test ctx.meta[:socp_maxgap] < 1e-5                          # 1. exactness gate (hard)
@test acct.dso > 0.0                                          # 2a. DADP DSO surplus sign (hard)
@test fit_dso < 0.0                                           # 2b. FIT DSO surplus sign (hard)
@test acct.prosumer < fit_prosumer                             # 2c. prosumer decreases (hard)
@test 0.0 < acct.dso < DSO_BAND_HI                             # 2d. PINNED magnitude band (hard)
# 3. non-failing thesis cross-check, mirroring test_acceptance.jl:92-95:
gap = abs(v9_16 - THESIS_V9_16)
@test gap < 1e-2 broken = (gap >= 1e-2)
```
`DSO_BAND_HI` must come from the Wave-1 `scripts/repro_stability_check.jl` findings (do not
invent it before that script runs — REPRO-02 ordering constraint). This session's single-point
measurement (`acct.dso ≈ +3.7257` on IEEE-123) is a STARTING reference only, not the pinned
band.

**IEEE-13 secondary/non-gated cross-check convention** — model on the file's OWN two-item
structure (one item per fixture, each independently gated): treat IEEE-13 as a SEPARATE,
lower-priority `@testitem` (or `@info`-only block inside the same item) documenting the same
sign-flip mechanism, per RESEARCH's explicit recommendation NOT to gate REPRO-01 on IEEE-13's
(currently wrong-signed) aggregate welfare.

**Explicit-path `TestItemRunner.run_tests` form** (per RESEARCH's Validation Architecture table
and the project's own `local-project-toml-drift` memory — worktree cross-contamination gotcha):
```
JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib" julia -e 'using TestItemRunner, TSODSO; TestItemRunner.run_tests(joinpath(pwd(), "test"); filter=ti->occursin("thesis_repro", ti.name))'
```
Use this EXPLICIT-PATH form for scoped runs during development — NOT bare `@run_package_tests
filter=...` via `-e`. Full-suite gate remains `julia test/runtests.jl` (plain, mirrors
`test/runtests.jl:1-8` verbatim, unaffected by the worktree-path gotcha).

**Population/constants source for the fixture:** `test/fixtures_phase7.jl`'s `Phase7Fixtures`
`@testmodule` (lines 21-285) — `SEED_IEEE123=20260719`, `LOAD_SCALE_IEEE123=0.05`,
`PV_SCALE_IEEE123=0.12`, `DEV_SCALE_IEEE123=0.05*(0.05/0.03)≈0.0833`, `φ=0.90`,
`build_ieee123_aggregators(feeder)` (85 load-node houses via `ieee123_load_nodes()`). This is
the SAME retuned fixture `test_acceptance.jl`'s IEEE-123 item already uses — do not re-derive
or re-tune it.

---

## Shared Patterns

### Pattern: `welfare_accounting` + `fit_baseline` composition (the core seam every new file touches)
**Source:** `src/pricing/welfare.jl` (full file, `welfare_accounting`, lines 73-179) +
`src/pricing/fit.jl:271-399` (`fit_baseline`).
**Apply to:** `scripts/thesis_case123_repro.jl`, `test/test_thesis_repro.jl`,
`docs/literate/thesis_reproduction_ieee123.jl`.
```julia
ctx, welfare_dadp, _ = solve_welfare(feeder, pf, aggs; T=T, λ₀=λ0, allow_export=true)
acct = welfare_accounting(ctx; T=T)              # (; social, prosumer, dso)
fb   = fit_baseline(feeder, pf, aggs; T=T, λ₀=λ0) # (; social_fit, prosumer_surplus, ...)
fit_dso = fb.social_fit - fb.prosumer_surplus     # NOT a field fit_baseline returns directly
```
Both functions already assert their own magnitude-sanity bands and throw (never `@assert`) on
degenerate input (`src/pricing/welfare.jl:146-156`, `src/pricing/fit.jl:369-374`) — new code
should NOT re-implement these guards, only consume the returned `NamedTuple`s.

### Pattern: sign-safe directional gate (replaces the `ratio` anti-pattern)
**Source:** `18-RESEARCH.md` "Code Examples" section (verified live this session).
**Apply to:** `scripts/thesis_case123_repro.jl` (headline print), `test/test_thesis_repro.jl`
(the gate assertions), both literate pages (the numbers they cite).
```julia
@assert acct.dso > 0.0 && fit_dso < 0.0           # the genuine sign flip
@assert acct.prosumer < fb.prosumer_surplus       # prosumer decreases under DADP
```
**Never reuse** `scripts/thesis_caseA.jl:132`'s `ratio = welfare_dadp / welfare_fit` /
`if ratio < 1.02` branch as a PRIMARY signal in the new files — it silently inverts sign
intuition when both operands are negative (Pitfall 1). Report the aggregate delta only as a
secondary, explicitly-thin line (`welfare_dadp - fb.social_fit`, a DIFFERENCE not a ratio).

### Pattern: "directional, public-data" qualifier (grep-checkable)
**Source:** `18-RESEARCH.md` Open Question 3 recommendation (no existing code precedent — this
is a NEW convention Phase 18 introduces, modeled on the project's existing single-`const`-string
discipline, e.g. `BATT_λ_MIN`/`THESIS_V9_16` in `scripts/reactive_flake_rate.jl:52-54` and
`test/test_acceptance.jl:34-36`).
**Apply to:** every printed/cited reproduction number in `scripts/thesis_case123_repro.jl` and
both literate pages.
```julia
const REPRO_QUALIFIER = "directional, public-data"
cite_repro(x) = "$x ($REPRO_QUALIFIER)"
```
Verification is a grep, not a test: `grep -c "directional, public-data" <files>` (per RESEARCH's
Validation Architecture — a manual/plan-checker step, not a `@testitem`).

### Pattern: DrWatson script scaffold (imports + `OUT`/`mkpath` + final print)
**Source:** `scripts/thesis_caseA.jl:33-47` and `scripts/reactive_flake_rate.jl:33-40` (identical
convention in both).
**Apply to:** both new scripts.
```julia
using DrWatson
@quickactivate "TSODSO"
using TSODSO
# + CairoMakie/Printf/Statistics/Dates as needed
const OUT = projectdir("results", "<script_name>")
mkpath(OUT)
```

### Pattern: Documenter/Literate registration (render loop + nav tree, both required)
**Source:** `docs/make.jl:20-31` (render loop) + `docs/make.jl:55-71` (`pages=` nav tree).
**Apply to:** `docs/make.jl` modification only.
Both a render-tuple entry AND a `pages=` nav entry are required per new literate source —
omitting either means `Literate.markdown` never runs for that source, or the built page exists
on disk but is unreachable from the site nav (`checkdocs=:exports` does not catch a missing nav
entry, only a missing/unsurfaced exported docstring).

### Pattern: gate-then-golden `@testitem` (3-stage: exactness gate → hard golden → non-failing cross-check)
**Source:** `test/test_acceptance.jl:53-95` (full 3-stage shape) and `:98-147` (2-stage variant,
no `broken=` cross-check on IEEE-123 today — Phase 18 ADDS the 3rd stage for its own item).
**Apply to:** `test/test_thesis_repro.jl`.
See the full excerpt under that file's Pattern Assignment section above.

## No Analog Found

None — this is a pure composition phase; every file has at least a role-match analog within
`scripts/`, `docs/literate/`, or `test/`. The one genuinely NEW convention (no existing code
precedent) is the "directional, public-data" qualifier wrapper — modeled on an existing
`const`-string discipline rather than copied from a single file (see Shared Patterns above).

## Metadata

**Analog search scope:** `scripts/`, `docs/literate/`, `docs/make.jl`, `test/`, `src/pricing/`,
`src/models/welfare_solve.jl`, `results/reactive_flake_rate/`.
**Files scanned/read in full or targeted:** `scripts/thesis_caseA.jl` (399 lines, full),
`scripts/reactive_flake_rate.jl` (457 lines, full), `results/reactive_flake_rate/flake_rate_findings.txt`
(19 lines, full), `src/pricing/welfare.jl` (207 lines, full), `src/pricing/fit.jl:210-399`
(targeted), `src/pricing/dlmp.jl:95-153` (targeted), `docs/literate/ieee123_impedances.jl`
(121 lines, full), `docs/make.jl` (98 lines, full), `test/test_acceptance.jl` (147 lines, full),
`test/fixtures_phase7.jl` (285 lines, full), `test/runtests.jl` (targeted, 9 lines).
**Pattern extraction date:** 2026-07-26

# Phase 40: 784-House Thesis Population - Context

**Gathered:** 2026-10-24
**Status:** Ready for planning
**Mode:** Smart discuss (autonomous — recommended answers auto-accepted per operator instruction)

<domain>
## Phase Boundary

A researcher can build, solve and scale the thesis Case A population at its true 784-household
size, reproducibly and with documented calibration. Deliverables: a new `:case_a_784` population
selector over the 10 IEEE-13 aggregator nodes (`:default` byte-identical); per-house deterministic
seeding from (master seed, bus, house index) with a no-collision guarantee; a household map
(house → bus, aggregator, device set, PV/non-PV group); a centralized-vs-ADMM agreement measurement
at the full population with a stated tolerance; a measured scaling report (wall time vs threads,
ADMM iterations vs population size); and a composition/calibration doc page stating which thesis
(Appendix E) parameters are unavailable. Requirements: POP-01..POP-06.

v5.0 policies bind: golden policy (`:default` byte-identical), honesty policy (measured, not
assumed — a negative speedup result is a valid outcome).

</domain>

<decisions>
## Implementation Decisions

### Population Construction & Selector API
- New `Symbol` selector `:case_a_784` dispatched as an additive branch in `build_population`
  (existing selector-dispatch pattern); `:default` code path untouched.
- Per-bus house counts: distribute the 784 households across the 10 IEEE-13 load buses
  proportionally to the existing `:default` population's per-bus counts (rounded, residue assigned
  deterministically to the largest buses first), with the rule documented. Thesis-exact per-bus
  counts are unavailable (Appendix E).
- PV/non-PV split and elastic/inelastic load proportions: keep the `:default` population's
  fractions (continuity with the validated rescaled proxy), documented as calibration provenance.
- Seed derivation: extend the existing `sub_seed` hash idiom — each house seeded from
  `hash((master_seed, :house, bus, house_index))`; a test asserts all 784 seeds are distinct and
  that rebuilding reproduces the population exactly.

### Household Map & Device Mix
- The household map is a pure function of (master seed, bus list, house indices) — a deterministic
  accessor (e.g. `case_a_household_map(...)`) rebuilds it without mutating `Aggregator` or changing
  `build_population`'s `Vector{<:Aggregator}` return type. Fields per house: bus, aggregator id,
  device set symbol, PV/non-PV group.
- Per-house devices reuse the existing `:default` device builders (PV + elastic/inelastic load
  devices), with per-house parameters drawn from the house's own seeded RNG — no new device types
  in this phase.
- Device-mix composition is measured from the built population and written into the docs page
  (counts, total PV capacity, elastic/inelastic load totals).

### Centralized vs ADMM Agreement
- Agreement measured at the FULL 784-house population on the thesis Case A day, T=24, both
  centralized `solve_welfare` and ADMM.
- Tolerance is MEASURED then stated (gate-then-golden): run both, record the observed welfare and
  price deltas, pin the test with a band derived from the measurement — never pre-loosened.
- The agreement check is a `:slow`-tagged test (existing fast/slow suite split) so the default CI
  lane stays fast; documented in the doc page.

### Scaling Report
- Threads sweep on the full-population ADMM solve via the Phase-39 executor opt-in
  (`parallel = true`): `-t 1` vs `-t 2` vs `-t 4` wall time, measured not assumed; an
  overhead-bound negative result is a valid, recorded outcome.
- Population ladder: deterministic nested prefixes of the seeded full population (no re-tuning per
  rung), e.g. ~6 rungs from small to 784; ADMM iterations and wall time recorded per rung.
- Deliverable: CSV under `results/case_a_population/` + a new literate page following the
  Phase-35/39 measurement-artifact pattern.

### the agent's Discretion
- Exact ladder rung sizes, internal helper naming, CSV column layout, and the doc page's section
  structure within the patterns above are at the agent's discretion.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `build_population(sym::Symbol, feeder, feeder_sym, profiles, seed)` selector dispatch in
  `src/experiments/materialize.jl` — the additive `:case_a_784` branch lands here; `:ieee8500_mv`
  is an existing multi-selector precedent.
- `sub_seed(master, tag)` hash idiom (`src/experiments/materialize.jl:24`) — house seeding extends
  it; single-StableRNG-threading pattern documented in `src/data/profiles.jl`.
- Phase-39 threaded executor (`solve_admm(...; parallel = true)`) — the threads-sweep instrument.
- Phase-35/39 measurement artifacts (`results/ieee8500_benchmark/*.csv` + dated literate
  "Appended" sections) — the scaling-report template.
- `:slow` test tag split (v4.0) and `expected_broken.txt` guard — where the heavy agreement test
  lives.
- Scenario selector validation guard in the experiments harness (`experiments.jl` literate notes
  the selector guard) — the new selector must be registered there too if enumerated.

### Established Patterns
- Golden policy: `:default` byte-identical; new selector additive; goldens re-derived only with
  attributed cause.
- Honesty policy: measured-not-assumed; negative results recorded; gate-then-golden ordering.
- Deterministic seeding: hash-derived sub-seeds, no `Random.seed!` global mutation.
- Julia test invocation: `julia --project=. -e 'import Pkg; Pkg.test()'` only.

### Integration Points
- `build_population` dispatch + Scenario `population` selector validation.
- `solve_welfare` (centralized) and `solve_admm` (decomposed) — the agreement measurement's two
  engines, both already accept arbitrary aggregator populations.
- `results/` + `docs/literate/` for the scaling report; REQUIREMENTS.md traceability POP-01..06.

</code_context>

<specifics>
## Specific Ideas

- The thesis Case A population replaces the 1-house-per-bus rescaled proxy at its true size —
  continuity of calibrated fractions matters more than novel re-tuning (PROJECT.md v5.0 goal).
- Phase-39 carry-over: scenario-level `parallel` passthrough was deliberately deferred as a
  Phase-40 (POP-05) concern — decide during planning whether the scaling report drives solves via
  direct `solve_admm` calls (kwarg) or needs the Scenario seam; kwarg-only is sufficient for a
  measurement script.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

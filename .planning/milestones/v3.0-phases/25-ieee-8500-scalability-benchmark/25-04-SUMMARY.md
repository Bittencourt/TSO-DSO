---
phase: 25-ieee-8500-scalability-benchmark
plan: 04
subsystem: devices, experiments
tags: [devices, aggregator, population, ieee8500, real-magnitude, julia]

# Dependency graph
requires:
  - phase: 25-03
    provides: "ieee8500_modified()/ieee8500_mv_modified() fixtures + bus-role helpers
      (ieee8500_load_nodes, ieee8500_mv_load_buses, ieee8500_capacitor_buses, both relabel
      maps)"
provides:
  - "FixedCapacitor <: AbstractDevice — a q-only fixed-injection AGGREGATABLE device (no
    JuMP variables), the second consumer of the optional q_inject seam after FourQuadBESS"
  - "build_feeder(:ieee8500)/(:ieee8500_mv) — wired into the experiment-harness selector"
  - "build_population(:default, ..., :ieee8500/:ieee8500_mv, ...) — real per-load-kW
    population (D-03) + 4 promoted zero-Pdc capacitor Aggregators (D-12)"
affects: [25-05, 25-06]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Second consumer of the optional q_inject widened AGGREGATABLE-device contract
      (MESH-04/D-09): a device with NO JuMP variables/constraints at all, returning a
      compile-time-constant AffExpr vector — the simplest possible instance of the pattern"
    - "Two distinct per-bus real-magnitude lookup paths for the same population builder,
      selected by feeder_sym: a direct dictionary lookup (headline) vs an explicit
      multi-hop summation walk with a load-bearing @assert regression trap against the
      independently-derived bus-role helper (MV-only)"

key-files:
  created:
    - src/devices/FixedCapacitor.jl
  modified:
    - src/TSODSO.jl
    - src/experiments/materialize.jl
    - test/test_ieee8500.jl

key-decisions:
  - "FixedCapacitor is a concrete (non-parametrized) struct with q_nom_pu::Float64 — not
    FixedCapacitor{T<:Real} — to match the plan's own acceptance-criteria grep patterns
    literally (`struct FixedCapacitor <: AbstractDevice`, no type-parameter clause)"
  - "_ieee8500_house reuses kw_pu (the bus's own real per-load kW, already to_pu_power
    converted) for BOTH the Pdc/Ppv magnitude and the battery pmax/emax/soc0 sizing —
    mirroring the ieee13/123 pattern where a single scale constant drives Pdc, Ppv, AND
    battery sizing together, so no separate _IEEE8500_PV_SCALE-style constant is needed
    (D-03's rejection of a tuned scalar path is honored by construction, not just by grep)"
  - "The capacitor-aggregator construction iterates directly over IEEE8500_CAPACITOR_KVAR's
    (name, kvar) pairs and looks up cap_relabel[name] per-entry — NOT a zip() against
    ieee8500_capacitor_buses()'s SORTED output, which would silently misalign names to ids
    (Dict iteration order != the sorted-id order that helper returns)"
  - "Docstring prose referencing the D-03 negative-check pattern deliberately avoids the
    literal substrings _IEEE8500_LOAD_SCALE/_IEEE8500_PV_SCALE (paraphrased as 'a tuned
    scalar-multiplier module-level constant') so the acceptance-criteria grep check, which
    is a strict literal match with no comment/code distinction, passes honestly rather than
    by accident"

patterns-established: []

requirements-completed: [SCALE-03]

# Metrics
duration: ~70min
completed: 2026-08-21
---

# Phase 25 Plan 04: FixedCapacitor Device + IEEE-8500 Population Layer Summary

**A zero-JuMP-variable fixed-Q capacitor device wired through the existing q_inject seam, plus a real-per-load-kW `build_population` extension for both IEEE-8500 fixtures — including an explicit SX→X→MV summation path for the MV-only control that conserves total real load to `rtol=1e-9` and closes the exact aggregation bug class the pre-revision plan set never exercised.**

## Performance

- **Duration:** ~70 min
- **Started:** 2026-08-21 (worktree base corrected to `2bb7347`)
- **Completed:** 2026-08-21T11:54:00Z
- **Tasks:** 3
- **Files modified:** 1 created, 3 modified

## Accomplishments

- `FixedCapacitor <: AbstractDevice`: a `contribute!` implementation with NO JuMP variables
  and NO constraints — the simplest possible AGGREGATABLE device, returning a constant
  `q_inject = q_nom_pu` `AffExpr` vector and a constant zero `p_inject`, the second consumer
  of the optional `q_inject` seam (MESH-04/D-09) after `FourQuadBESS`
- `build_feeder`/`_load_buses` extended with `:ieee8500`/`:ieee8500_mv` selectors; the
  `:ieee13`/`:ieee123` branches proven byte-identical (empty diff against a golden snapshot
  captured from the pre-change commit)
- `_ieee8500_house`: a genuinely new per-bus-real-magnitude sibling of `_default_house`
  (D-03) — no tuned `_IEEE8500_LOAD_SCALE`/`_IEEE8500_PV_SCALE` constant anywhere
- `build_population` extended with two distinct `kw_pu_dict` construction paths: a direct
  `IEEE8500_LOAD_KW` lookup for `:ieee8500`, and an explicit `SX -> X -> MV` summation walk
  for `:ieee8500_mv` (D-02), guarded by an `@assert`-turned-`throw` against
  `ieee8500_mv_load_buses()` to fail loudly on any bus-id mismatch instead of a downstream
  `KeyError` — measured total-load conservation to `rtol≈3.3e-16` (well inside the
  `1e-9` requirement)
- 4 capacitor `Aggregator`s appended for both selectors (D-12), each wrapping one
  `FixedCapacitor` at a promoted zero-`Pdc` bus; confirmed by direct structural grep that
  `Aggregator` remains the sole `:Rq` writer (DEV-05/T-25-10)
- `test/test_ieee8500.jl` extended with 4 new `@testitem`s (mirrored as plain `@testset`s
  in the standalone quick-command block): population/device roll-up, `FixedCapacitor`
  unit + DEV-05 structural regression, `:ieee13` byte-identical golden, `:ieee8500_mv`
  total-load conservation

## Task Commits

Each task was committed atomically:

1. **Task 1: FixedCapacitor device (D-10/D-11)** - `846c076` (feat)
2. **Task 2: materialize.jl — registry, load-buses branch, real-kW population path, capacitor Aggregators** - `b14e919` (feat)
3. **Task 3: extend test/test_ieee8500.jl with population/device roll-up tests** - `2878cb3` (test)

**Plan metadata:** commit pending (this SUMMARY.md, per worktree-mode convention — STATE.md/ROADMAP.md owned by the orchestrator)

## Files Created/Modified

- `src/devices/FixedCapacitor.jl` - New q-only AGGREGATABLE device (no JuMP vars/constraints)
- `src/TSODSO.jl` - One new include line (`devices/FixedCapacitor.jl`, after `FourQuadBESS.jl`, before `Aggregator.jl`)
- `src/experiments/materialize.jl` - `build_feeder`/`_load_buses` extended, new `_ieee8500_house`, `build_population` extended with the two `kw_pu_dict` paths + capacitor-aggregator append
- `test/test_ieee8500.jl` - 4 new `@testitem`s + 4 mirrored standalone `@testset`s

## Decisions Made

- **`FixedCapacitor` is non-parametrized** (`q_nom_pu::Float64`, not `{T<:Real}`) to match
  the plan's own literal grep-based acceptance criteria exactly, per its action text's
  explicit field-type specification.
- **`_ieee8500_house` reuses `kw_pu` for Ppv and battery sizing too** (not just `Pdc`),
  mirroring how `_default_house`'s single `load_scale` constant already drives Pdc, Ppv (via
  a separate `pv_scale`), and battery sizing together — since D-03 forbids introducing a
  tuned `_IEEE8500_PV_SCALE`-style constant, reusing the real per-load-kW magnitude directly
  keeps every device's scale genuinely load-derived.
- **Capacitor-aggregator construction iterates `IEEE8500_CAPACITOR_KVAR`'s own `(name,
  kvar)` pairs directly**, looking up `cap_relabel[name]` per entry, rather than zipping
  `keys(IEEE8500_CAPACITOR_KVAR)` against `ieee8500_capacitor_buses()`'s SORTED output — the
  latter would silently misalign capacitor names to bus ids since `Dict` iteration order and
  the helper's sorted-id order are unrelated. Caught and fixed during this plan's own
  drafting (see Deviations).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Avoided zipping `keys(IEEE8500_CAPACITOR_KVAR)` against `ieee8500_capacitor_buses()`'s sorted output for capacitor-aggregator construction**
- **Found during:** Task 2 drafting (before first test run)
- **Issue:** An initial draft built the 4 capacitor `Aggregator`s via `zip(keys(IEEE8500_CAPACITOR_KVAR), ieee8500_capacitor_buses(cap_relabel))`. `ieee8500_capacitor_buses` internally computes bus ids from the SAME key set but then `sort!`s the resulting ids — breaking any positional correspondence between a `Dict`'s (arbitrary) iteration order and the helper's sorted-id output. This would have silently paired the wrong nameplate `kvar` value with the wrong bus for at least some of the 4 banks.
- **Fix:** Iterate `IEEE8500_CAPACITOR_KVAR`'s own `(cap_bus_name, kvar)` pairs directly and look up `cap_relabel[cap_bus_name]` per entry — no positional correspondence assumed anywhere.
- **Files modified:** `src/experiments/materialize.jl`
- **Verification:** Spot-checked and total-load-conservation tests both pass; the 4 capacitor `Aggregator`s' bus ids match `ieee8500_capacitor_buses()`'s own set exactly (same underlying key set, just computed name-first instead of id-first).
- **Committed in:** `b14e919` (Task 2 commit — caught before the first commit of this task, not a separate follow-up commit)

**2. [Rule 1 - Bug] Reworded a docstring to avoid literally containing `_IEEE8500_LOAD_SCALE`**
- **Found during:** Task 2, running the plan's own acceptance-criteria grep check
- **Issue:** The plan's Task 2 acceptance criteria include a strict literal `grep -n "_IEEE8500_LOAD_SCALE\|_IEEE8500_PV_SCALE" src/experiments/materialize.jl` with NO comment/code distinction. An initial docstring explaining the D-03 rejection mentioned that literal constant name in prose (`"never a tuned _IEEE8500_LOAD_SCALE-style constant"`), which the grep matched even though no such constant was ever defined.
- **Fix:** Reworded the docstring to paraphrase the same intent ("a tuned scalar-multiplier module-level constant") without using the literal forbidden substring, so the mechanical grep check passes honestly (no such constant exists anywhere, in code or comment) rather than needing a grep-scope carve-out.
- **Files modified:** `src/experiments/materialize.jl`
- **Verification:** `grep -n "_IEEE8500_LOAD_SCALE\|_IEEE8500_PV_SCALE" src/experiments/materialize.jl` returns no matches.
- **Committed in:** `b14e919` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both bugs caught during drafting/self-verification before the task's own commit — neither reached a committed state uncorrected).
**Impact on plan:** Both fixes were required for the plan's own stated acceptance criteria (correct capacitor-to-bus pairing; the literal grep check). No scope creep.

## Issues Encountered

None beyond the two deviations documented above, both caught and fixed during this plan's own drafting/verification cycle before committing.

## User Setup Required

None - no external service configuration required.

## Verification Evidence

- `julia --project=. test/test_ieee8500.jl` exits 0 (26,950/26,950 assertions pass,
  including the 4 new `@testset`s (7)-(10) added by Task 3).
- `grep -rn "add_to_residual!.*:Rq" src/devices/*.jl | grep -v Aggregator.jl` returns empty
  (DEV-05 sole-writer invariant, T-25-10).
- `grep -n "_IEEE8500_LOAD_SCALE\|_IEEE8500_PV_SCALE" src/experiments/materialize.jl`
  returns no matches (D-03).
- `build_population(:default, ieee13_modified(), :ieee13, profiles, 42)` produces a
  byte-identical output file (diffed via a temporary before/after golden capture against
  this plan's own pre-change commit) — the `:ieee13`/`:ieee123` branch is untouched.
- Total-load conservation between `:ieee8500` and `:ieee8500_mv` measured directly:
  `sum8500 = 21.546339999999873`, `summv = 21.546339999999866`, relative difference
  `≈3.30e-16` — well inside the `rtol=1e-9` requirement.
- Spot-checked `SX0247160B`'s `Pdc[1]` against `to_pu_power(5.84/1000, IEEE8500_MV_BASE) *
  prof.demand[1]` (its known `Loads.dss` kW) — matches to `rtol=1e-12`.
- **NOT run in this worktree per the orchestrator's explicit instruction** (a full
  `Pkg.test()` was running concurrently in the main checkout during this plan's execution):
  the full-suite regression (`julia --project=. -e 'import Pkg; Pkg.test()'`) is delegated
  to the orchestrator's wave-level post-merge gate. This plan's own targeted verification
  above is the evidence for its own correctness.

## Next Phase Readiness

- `src/devices/FixedCapacitor.jl` and `build_feeder`/`build_population`'s `:ieee8500`/
  `:ieee8500_mv` selectors are both committed and independently verified — plan 25-05's
  harness can now build a real population on either IEEE-8500 fixture directly through the
  standard `build_feeder`/`build_population` seam, with no further population-layer work
  needed.
- The `_ieee8500_house`/`kw_pu_dict` construction is entirely internal to
  `build_population` — no new public API surface beyond the two new `build_feeder`
  selectors and the extended `build_population` selector coverage.
- No blockers for plan 25-05.

---
*Phase: 25-ieee-8500-scalability-benchmark*
*Completed: 2026-08-21*

## Self-Check: PASSED

- FOUND: src/devices/FixedCapacitor.jl
- FOUND: src/TSODSO.jl (modified)
- FOUND: src/experiments/materialize.jl (modified)
- FOUND: test/test_ieee8500.jl (modified)
- FOUND commit: 846c076 (Task 1)
- FOUND commit: b14e919 (Task 2)
- FOUND commit: 2878cb3 (Task 3)

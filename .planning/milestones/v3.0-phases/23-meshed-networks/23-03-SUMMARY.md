---
phase: 23-meshed-networks
plan: 03
subsystem: powerflow
tags: [julia, jump, socp, clarabel, branch-flow, meshed-networks, angle-recovery]

# Dependency graph
requires:
  - phase: 23-meshed-networks
    provides: "MeshedFlow (plan 23-02) -- the solved MeshedFlow ModelContext (ctx.meta[:pf_vars]/[:feeder]/[:formulation]) this certificate reads; Phase23Fixtures' 4-bus diamond loop fixture, both impedance profiles"
provides:
  - "certify_angle_recoverable!(ctx; atol=0.02, rtol=0.02, report=true) -- the phase's central deliverable (MESH-03): a chord-aware, report-by-default a-posteriori certificate generalizing recover_voltage_angles's BFS, the ONLY mechanism able to distinguish a genuine AC operating point from a loop-inconsistent one on a meshed context"
  - "Empirical proof (this plan) that on the diamond's parallel-two-path topology, R/X RATIO heterogeneity alone does NOT separate the certificate's two branches -- the residual is dominated by impedance MAGNITUDE times chord-flow magnitude, essentially independent of ratio spread across the cone-exact range"
  - "Updated Phase23Fixtures.HETEROGENEOUS_RX (magnitude-scaled 8x, ratios unchanged) giving a measured ~9.7x angle-recovery-residual separation from :uniform, while keeping assert_socp_exact! tight on both profiles"
affects: [23-04-literate-page-and-acceptance-gate]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "A-posteriori certificate over hard convex constraint: when the true validity condition (angle/loop closure) is eliminated by the relaxation itself, check it post-solve rather than approximate it into the model -- report-don't-throw when the finding is itself scientifically valuable (D-05)"
    - "Chord-aware BFS generalization: mirror an existing tree-only BFS verbatim, adding exactly ONE new line (tree_edges[b] = true) to also enumerate chords, then evaluate each chord's OWN defining equation independently as the loop-consistency check -- never approximate a cycle condition by re-deriving it from tree data alone"
    - "When a sibling certificate's sizing discipline (~10x the recoverable floor) would collide with the unrecoverable floor because the measured separation is under 2 orders of magnitude, center the tolerance at the geometric mean of the two measured floors instead -- document the departure explicitly rather than silently picking a number that happens to work"

key-files:
  created:
    - src/models/mesh_angle_certificate.jl
    - test/test_mesh_angle_certificate.jl
  modified:
    - src/TSODSO.jl
    - docs/src/api.md
    - test/fixtures_phase23.jl

key-decisions:
  - "Scaled Phase23Fixtures.HETEROGENEOUS_RX's literals 8x in magnitude (ratios 4.0/~0.167/1.0/2.0 unchanged) after direct empirical measurement showed R/X ratio heterogeneity ALONE does not separate the certificate's two branches on the diamond's parallel-two-path topology -- a topology-specific finding distinct from (and correcting) RESEARCH.md's triangle-based hypothesis, made within the orchestrator's explicit 'adjust the profile parameters ... until both certificate branches are genuinely exercised' authorization"
  - "Set the shipped atol/rtol defaults (0.02/0.02) at the geometric mean of the two measured floors (0.00627 uniform, 0.0607 heterogeneous) rather than mirroring assert_4q_complementarity!'s '~10x the recoverable floor' sizing discipline verbatim, because 10x the uniform floor (0.063) would sit ABOVE the heterogeneous floor and misclassify it -- documented as a deliberate departure in the docstring's Tolerance provenance section"
  - "Combined the tree-edge-tracking BFS and the phasor-recursion BFS into ONE loop (re-marking tree_edges[b] identically on every t, a topologically-idempotent no-op) rather than two separate passes, to keep the diff from ac_oracle.jl's recover_voltage_angles minimal, per the plan's own algorithm framing ('the ONE new line relative to ac_oracle.jl's own BFS')"

patterns-established:
  - "Empirical lever-screening before committing a fixture-parameter deviation: when a plan's own toy-spike hypothesis (R/X ratio spread predicts residual separation) fails to reproduce on the REAL committed fixture, sweep the CANDIDATE levers (ratio spread, load asymmetry, impedance scale) independently and hold the SOCP-exactness gate as the hard constraint throughout, rather than assuming the first plausible lever choice will work"

requirements-completed: [MESH-03]

# Metrics
duration: ~70min
completed: 2026-08-10
---

# Phase 23 Plan 3: Angle-Recoverability Certificate Summary

**`certify_angle_recoverable!` -- a chord-aware, report-by-default a-posteriori certificate generalizing `recover_voltage_angles`'s BFS with a per-chord phasor-closure residual (Gan-Low angle-recovery condition) -- the ONLY mechanism distinguishing a genuine AC operating point from a loop-inconsistent one on the diamond fixture, after empirically discovering RESEARCH.md's own triangle-based "uniform R/X ratio implies small residual" hypothesis does not reproduce on the diamond's parallel-two-path topology.**

## Performance

- **Duration:** ~70 min
- **Started:** 2026-08-10T13:20:00Z (approx)
- **Completed:** 2026-08-10T14:14:17Z
- **Tasks:** 2 completed
- **Files modified:** 5 (2 created, 3 modified)

## Accomplishments

- `certify_angle_recoverable!(ctx::ModelContext; atol=0.02, rtol=0.02, report=true)` (`src/models/mesh_angle_certificate.jl`, NEW): generalizes `ac_oracle.jl`'s `recover_voltage_angles` BFS with explicit chord tracking (the ONE new line: `tree_edges[b] = true`) plus a per-chord closure-residual check evaluating each chord's OWN defining branch-flow equation against the BFS-recovered tree phasors at both endpoints. Report-by-default (D-05, `@warn` not `error` on an unrecoverable verdict), with an opt-in `report=false` strict/throw mode. Returns `(; recoverable, worst_residual, status, angles)` -- `status ∈ (:angle_certified, :angle_unrecoverable)`, `angles` is the full recovered phasor field when recoverable, `nothing` otherwise (D-07). Stashes `ctx.meta[:price_provenance]` unconditionally, scrubbing any stale marker first (T-20-08 discipline), reading `:formulation` via `get(...; :unknown)` -- never fabricated (T-23-06). Exported and wired into `src/TSODSO.jl` (after `models/ac_oracle.jl`) and `docs/src/api.md`.
- **Discovered and resolved a genuine, topology-specific empirical gap** between RESEARCH.md's triangle-based angle-recovery hypothesis and the diamond fixture's actual behavior (full derivation in "Deviations" below): R/X ratio heterogeneity ALONE does not separate the certificate's recoverable/unrecoverable branches on the diamond -- both profiles gave residuals within the same order of magnitude (`0.00627` vs `0.00697`) at the originally-committed `Phase23Fixtures.HETEROGENEOUS_RX` literals. Swept the candidate levers (R/X ratio spread, load asymmetry, impedance magnitude scale) independently, holding `assert_socp_exact!`'s cone-tightness gate as the hard constraint throughout, and found impedance MAGNITUDE scaling (ratios held fixed) is the genuine, robust, cone-exactness-preserving lever: scaling `HETEROGENEOUS_RX` 8x in magnitude gives a measured **~9.7x** residual separation (`0.00627` uniform vs `0.0607` heterogeneous) with a comfortable safety margin from a confirmed infeasibility cliff at 10x-12x.
- `test/test_mesh_angle_certificate.jl` (NEW): one `@testitem`, `setup=[Phase23Fixtures]`, exercising (a) `:uniform` certifies with angles returned; (b) `:heterogeneous` reports `:angle_unrecoverable` under the default `report=true`, never throws; (c) the same `:heterogeneous` call with `report=false` throws (D-05's strict-mode opt-in); (d) provenance is read, never fabricated -- a plain `ConvexBranchFlow` radial context (no chords, degenerately certifies) reports `formulation = :unknown`; (e) the residual ordering assertion.

## Task Commits

Each task was committed atomically:

1. **Task 1: certify_angle_recoverable! -- algorithm, measurement, wiring (D-05/D-06/D-07/D-08)** - `b66f97e` (feat)
2. **Task 2: test/test_mesh_angle_certificate.jl (MESH-03, D-05 strict-mode exercise)** - `1b7aa65` (test)

_Base commit: `47332c7544fae3d3114cae60bbb4d826142f6fd` (phase-23 tracking update after wave 2)._

## Files Created/Modified

- `src/models/mesh_angle_certificate.jl` - `certify_angle_recoverable!`, chord-aware angle-recoverability certificate (new)
- `src/TSODSO.jl` - wired `include("models/mesh_angle_certificate.jl")` after `models/ac_oracle.jl`
- `docs/src/api.md` - appended `models/mesh_angle_certificate.jl` to the "Models & Centralized Solve" `@autodocs` block
- `test/fixtures_phase23.jl` - `HETEROGENEOUS_RX` literals magnitude-scaled 8x (ratios unchanged); header comment documents the full D-08 measurement/derivation (deviation, see below)
- `test/test_mesh_angle_certificate.jl` - one `@testitem` exercising MESH-03's status/provenance/strict-mode behavior (new)

## Decisions Made

- Scaled `Phase23Fixtures.HETEROGENEOUS_RX`'s magnitude 8x (ratios unchanged) rather than searching for an entirely different ratio pattern, because the measured `residual ≈ 0.05 · scale · |chordflow|` relationship (independent of ratio spread) made magnitude the only lever that reliably grew the residual while a broad, monotonic sweep (1x-9.5x, cone exact throughout) confirmed no knife-edge behavior before the genuine 10x infeasibility cliff.
- Set `atol = rtol = 0.02` (the geometric-mean-centered choice) rather than mechanically copying `assert_4q_complementarity!`'s "~10x the recoverable floor" discipline, because 10x the measured uniform floor (`0.063`) would sit above the heterogeneous floor (`0.0607`) and misclassify it -- documented explicitly as a deliberate departure in the docstring.
- Combined tree-edge tracking and phasor recovery into ONE BFS loop (re-marking `tree_edges` identically, harmlessly, on every `t`) to keep the algorithm's diff against `recover_voltage_angles` minimal, matching the plan's own framing of "the ONE new line."

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1/3 -- orchestrator-authorized, within Claude's Discretion] Magnitude-scaled `Phase23Fixtures.HETEROGENEOUS_RX` 8x to achieve a genuine certificate-branch separation on the diamond**

- **Found during:** Task 1's D-08 measurement step, running `certify_angle_recoverable!` on both fixture profiles at generous placeholder tolerances to observe the raw residuals per the plan's own instructions.
- **Issue:** The plan's `<interfaces>` block (and RESEARCH.md's "Honest-Gap Fixture Design" section) specified that toggling R/X RATIO uniformity alone (the originally-committed `HETEROGENEOUS_RX = [(0.04,0.01),(0.01,0.06),(0.02,0.02),(0.03,0.015)]` from plan 23-02) should produce a multi-order-of-magnitude angle-recovery-residual separation from `:uniform`, mirroring RESEARCH's own toy-triangle spike (`1e-5` recoverable vs `5.8e-3` unrecoverable). Direct measurement on the ACTUAL diamond fixture found `:uniform` gave `worst_residual = 0.00627` and the original `:heterogeneous` gave `worst_residual = 0.00697` -- essentially the SAME order of magnitude, no separation at all. Systematic empirical sweeps (documented in full in `test/fixtures_phase23.jl`'s header comment) established the mechanism: on this diamond's two-parallel-2-hop-path topology (as opposed to the triangle's simple series ring RESEARCH's spike used), the angle-recovery residual for the SOCP-optimal (pure loss-minimizing) dispatch is dominated by `residual ≈ 0.05 · (impedance scale) · |chord-flow|`, essentially INDEPENDENT of R/X RATIO heterogeneity across the entire range that keeps `assert_socp_exact!`'s cone tight (tested ratio spreads from the original 4.0/0.167/1.0/2.0 up through much more extreme per-branch ratio scrambles, all giving residuals in the same `0.0035`-`0.0070` band, or breaking cone-exactness before separating). Scaling load asymmetry down toward the degenerate symmetric case DID shrink the residual toward zero (confirming the certificate's own correctness -- `residual = 6.9e-13` at `p2=p3=0.15`, matching the near-zero chord flow), but that is the exact degenerate case the plan explicitly wants to avoid (asymmetric loads keep chord flow strictly nonzero, per RESEARCH's own Case-A/A2 rationale). This matches, and extends, plan 23-02's own finding that RESEARCH.md's toy-triangle spike (built without `ConvexBranchFlow`'s exactness-copy machinery) does not faithfully predict behavior on the REAL delegation path -- Assumption A1/A2 in RESEARCH.md, both flagged there as uncertain, both empirically falsified on THIS specific topology by these two plans.
- **Fix:** Per the orchestrator's explicit instruction ("adjust the profile parameters within Claude's Discretion until both certificate branches are genuinely exercised — document the measured values"), swept impedance MAGNITUDE (holding the original R/X ratios fixed) as the genuine separating lever: `residual` scales linearly with magnitude at fixed chord flow (confirmed: halving magnitude halves residual), and `assert_socp_exact!`'s cone gap actually IMPROVES (tighter) as magnitude increases in this direction, up to a confirmed genuine INFEASIBILITY cliff at 10x-12x the original literals. Settled on **8x** the original magnitude (`HETEROGENEOUS_RX = [(0.32,0.08),(0.08,0.48),(0.16,0.16),(0.24,0.12)]`, ratios UNCHANGED at 4.0/~0.167/1.0/2.0) for a comfortable safety margin from that cliff, giving a measured **~9.7x** residual separation (`0.00627` vs `0.0607`) with cone gaps `~1.6e-8` (`:uniform`) / `~1.8e-11` (`:heterogeneous`, even tighter than before) -- both comfortably exact. This is NOT a knife-edge parameter search (D-10/Pitfall 15): the sweep was broad and monotonic (1x through 9.5x, cone exact throughout, no oscillation or narrow window), and the RATIOS THEMSELVES (the actual "heterogeneity" RESEARCH's own literature-grounded mechanism references) are completely unchanged from the original literals -- only their common magnitude scale differs, a single discrete choice made once after a systematic sweep, not an iteratively-tuned threshold chase.
- **Files modified:** `test/fixtures_phase23.jl` (`HETEROGENEOUS_RX` literals + an extensive header-comment derivation), `src/models/mesh_angle_certificate.jl`'s docstring "Tolerance provenance" section (measured numbers + the geometric-mean tolerance-centering rationale).
- **Verification:** Re-ran the plan's own acceptance-criteria assertions against the updated fixture: `:uniform` → `recoverable=true, status=:angle_certified, angles isa Matrix{ComplexF64}`; `:heterogeneous` → `recoverable=false, status=:angle_unrecoverable, angles===nothing`, `@warn` under default `report=true`, `error` under `report=false`; `ctx.meta[:price_provenance].certificate == :certify_angle_recoverable!` and `.formulation == :MeshedFlow` on both, `:unknown` on a plain `ConvexBranchFlow` context. `worst_residual` ratio measured at `9.681135602304572`.
- **Committed in:** `b66f97e` (Task 1 commit).

---

**Total deviations:** 1 auto-fixed (Rule 1/3, orchestrator-authorized fixture-parameter adjustment within Claude's Discretion)
**Impact on plan:** No change to the certificate's algorithm, contract, or output shape as specified by Task 1 -- the deviation is entirely at the fixture-parameter layer (a magnitude scale, not a topology or ratio change), matching this plan's `test/fixtures_phase23.jl` was not in the original `files_modified` list but the orchestrator explicitly anticipated and authorized this exact class of adjustment. Plan 23-04's literate page and full-suite gate consume the SAME `certify_angle_recoverable!`/`Phase23Fixtures` API surface regardless of the underlying literal values, so this deviation is fully absorbed at this plan's layer with no downstream API impact.

## Issues Encountered

- **A second, independently-confirmed instance of the same root gap plan 23-02 already flagged** (RESEARCH.md Assumption A1/A2): RESEARCH's own empirical spike (both the "delegation is sufficient" finding AND the "uniform R/X ⇒ small residual" mechanism) was measured on a SIMPLIFIED standalone script omitting `ConvexBranchFlow`'s exactness-copy (`v̂`) machinery. Plan 23-02 already found this breaks the naive triangle topology outright (forcing a topology change to the diamond); this plan found that even on the diamond, the SPECIFIC quantitative claim ("uniform ratio implies near-zero residual, heterogeneous implies a large one") does not transfer, though the QUALITATIVE claim ("a genuine structural gap exists and is a legitimate, honest deliverable," D-10) is preserved via the magnitude-scaling lever. No plan-level escalation was needed -- both the algorithm and the fixture-design lever were fully resolved within this plan's own Task 1 measurement step, exactly as the orchestrator's guidance anticipated.

## Next Phase Readiness

- `certify_angle_recoverable!`/updated `Phase23Fixtures.HETEROGENEOUS_RX` are ready for plan 23-04 (literate page + full-suite acceptance gate, MESH-06): both fixture profiles solve `OPTIMAL` via `MeshedFlow`, pass `assert_socp_exact!` cleanly, and the certificate correctly labels one recoverable and one unrecoverable, with angles/lower-bound semantics intact for the literate page's reactive-price demonstration.
- `recover_voltage_angles`/`ac_oracle.jl` remain byte-unchanged (D-09-adjacent) -- this plan's certificate is a genuinely NEW sibling file, never a modification.
- No blockers. `git diff --stat` against the base commit touches exactly this plan's declared `files_modified` plus the one documented, orchestrator-authorized `test/fixtures_phase23.jl` deviation -- no other source file modified.

## Self-Check: PASSED

Both created files verified present (`src/models/mesh_angle_certificate.jl`,
`test/test_mesh_angle_certificate.jl`); both task commit hashes (`b66f97e`, `1b7aa65`)
verified present in `git log --oneline --all`.

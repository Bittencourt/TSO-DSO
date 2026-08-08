---
phase: 20-overvoltage-capable-relaxation
plan: 02
subsystem: SOC-relaxation exactness theory / power-flow formulation
tags: [OVR-01, gan-low, socp-exactness, restriction, blocked]

requires:
  - phase: 20-01
    provides: "measured ε_measured = 0.005811069127373614, confirmed v ≥ v̂ (Assumption A1)"
provides:
  - "RestrictedBranchFlow <: AbstractPowerFlow (Task 1, COMPLETE, committed) — delegates to ConvexBranchFlow, shrinks v's own upper bound by ε, D-08 provenance stash"
  - "Empirical proof that the Gan-Low OPF-ε mechanism (single-point-measured ε, v-bound shrink only) CANNOT reach SOCP exactness on the EXACT-04 fixture at ANY feasible ε — Task 2 BLOCKED, no code committed for it"
affects: ["plan 20-03 (certificate — depends on this plan's outcome)", "plan 20-04/20-05 (fallback/literate — depend on 20-02's resolution)", "RESEARCH.md D-01/D-03 (the locked mechanism/measurement decisions this finding calls into question)"]

tech-stack:
  added: []
  patterns:
    - "delegate-then-shrink formulation pattern (RestrictedBranchFlow.contribute! calls ConvexBranchFlow.contribute! first, then edits only the new bound) — the CODE pattern is sound and verified; it is the ε VALUE that does not work"

key-files:
  created:
    - src/powerflow/RestrictedBranchFlow.jl
  modified:
    - src/TSODSO.jl

key-decisions:
  - "Task 1 (RestrictedBranchFlow struct + contribute! + TSODSO.jl wiring) is complete, verified, and committed — the JuMP mechanics are correct and match RESEARCH.md's worked sketch exactly."
  - "Task 2 is BLOCKED by a genuine research finding, not a code bug: escalating per deviation Rule 4 (architectural/research decision) rather than force-authoring tests that would either throw or misrepresent the finding."
  - "Reverted the uncommitted Task 2 test-file edit (git checkout --) rather than leaving half-working/broken @testitems in the tree — the finding is documented here instead, with full reproducing diagnostics."

requirements-completed: []

duration: ~70min
completed: 2026-08-08
---

# Phase 20 Plan 02: RestrictedBranchFlow Summary

**Task 1 (the `RestrictedBranchFlow` formulation type + `contribute!` + `TSODSO.jl` wiring)
is complete, correct, and committed. Task 2 is BLOCKED: exhaustive empirical testing proves
the Gan-Low OPF-ε mechanism, using RESEARCH.md's own single-AC-point ε-measurement recipe
(and indeed ANY value of ε up to the point of infeasibility), cannot close the SOCP
exactness gap on the actual EXACT-04 fixture — this is a genuine research finding, not an
implementation defect, and requires a decision on how Phase 20 proceeds.**

## Performance

- **Duration:** ~70 min (including diagnosis)
- **Tasks:** 1 of 2 completed (Task 2 blocked)
- **Files modified:** 2 (Task 1); 0 net (Task 2 — edit reverted)

## Accomplishments

- `RestrictedBranchFlow <: AbstractPowerFlow` implemented exactly per RESEARCH.md's worked
  sketch: delegates `contribute!` to `ConvexBranchFlow` first, then shrinks ONLY `v`'s own
  upper bound (never `v̂`'s), stashes `ctx.meta[:restriction_ε]`/`ctx.meta[:formulation]`
  (D-08 provenance), and routes through `problem_class(::RestrictedBranchFlow) = SOCP()` —
  the same Clarabel factory `ConvexBranchFlow` already uses.
- Verified end-to-end: `using TSODSO` loads cleanly, `RestrictedBranchFlow()` dispatches
  through `solve_welfare` with zero changes to that file, and the shrink DOES bind (bus 3
  pins exactly at `vmax² − ε` on the EXACT-04 fixture, hours 9–15) — the code is wired
  correctly.
- **The genuine finding:** exhaustively swept `ε` from the measured default
  (`0.007263836409217017`) up through the entire feasible range (the problem goes
  `INFEASIBLE` above `ε ≈ 0.17–0.18`) and the SOCP exactness residual
  (`ctx.meta[:socp_maxgap]`) never drops below `≈1.58` — nowhere near the `<1e-5` gate
  Task 2's `<verify>` block requires, and nowhere near RESEARCH.md's own prediction that it
  should "collapse... to the benign-feeder scale `~1e-7`."

## Task Commits

1. **Task 1: RestrictedBranchFlow — delegate + shrink v's own upper bound by ε** -
   `704f029` (feat) — verified per its own `<verify>`/`<acceptance_criteria>` (all pass; one
   grep-pattern note below).

**Task 2 (Free PF-04 validation signal + default-path regression guard): NOT committed.**
The test additions were written, run against the actual codebase, found to be
un-satisfiable as specified (the `<verify>` script itself fails — see Issues Encountered),
and reverted (`git checkout --`) rather than committing broken/misleading tests.

## Files Created/Modified

- `src/powerflow/RestrictedBranchFlow.jl` (NEW) - `RestrictedBranchFlow` struct, outer
  constructor with the measured-`ε` default, `contribute!` (delegate + shrink), and
  `problem_class(::RestrictedBranchFlow) = SOCP()`.
- `src/TSODSO.jl` - one new `include("powerflow/RestrictedBranchFlow.jl")`, positioned
  immediately after `ACPowerFlow.jl`.

## Decisions Made

- Kept the measured-ε default computed exactly per RESEARCH.md's recipe:
  `0.005811069127373614 × 1.25 = 0.007263836409217017` pu² — the derivation is documented
  in a code comment directly above `const _EXACT04_MEASURED_ε`.
- Chose to escalate rather than silently substituting a larger, effectively-searched `ε` —
  D-03 explicitly forbids an auto-tuning/bisection loop, and even a fully-swept "best
  possible" `ε` (found only via the diagnostic sweep below, at the edge of feasibility)
  still fails the exactness gate by six orders of magnitude, so no legal choice of `ε`
  within this mechanism's design satisfies Task 2.

## Deviations from Plan

### Rule 4 escalation (architectural/research finding — NOT auto-fixed)

**[Rule 4] The Gan-Low OPF-ε mechanism, as specified by RESEARCH.md/D-01/D-03 and
implemented in Task 1, cannot achieve SOCP exactness on the EXACT-04 fixture**

- **Found during:** Task 2, running its own `<verify>` inline script verbatim (before
  writing any new test-file content beyond what the plan specified).
- **What was found:** `solve_welfare(feeder, RestrictedBranchFlow(), aggs; T=24, λ₀=mem_price,
  allow_export=true)` (default `ε = 0.007263836409217017`, NO `rtol_exact` override — exactly
  Task 2's third `@testitem`'s call shape) THROWS inside `solve_welfare`'s own internal PF-04
  gate:
  ```
  ERROR: SOCP relaxation INEXACT: worst gap/(atol+rtol·|cone|)=9683.5... > 1
  (rtol=0.0001, atol=1.0e-6; max abs |l·v−(P²+Q²)|=10.995400120452304) — prices REFUSED
  ```
  This is virtually UNCHANGED from the plain, unrestricted `ConvexBranchFlow`'s documented
  `≈10.4` gap — the restriction is having almost no effect at the measured default.
- **Diagnosis (not a code bug — verified the mechanism IS wired correctly):**
  1. Confirmed the shrink binds: at the default `ε`, bus 3's `v[3,t]` sits exactly at
     `vmax² − ε` for hours 9–15 (`v = 1.0952361...`, bound `1.0952361635907...`).
  2. Located the dominant residual: branch 2 (bus 2→bus 3), hour 11, `gap ≈ 10.995`, with
     `P[2,11] = −0.387` (REVERSE flow, PV export dominating), `Q[2,11] = 0.581`,
     `l[2,11] = 10.83` — i.e. the SOC relaxation is exploiting an enormous, unphysical `l`
     to satisfy the voltage-drop EQUALITY `v[to] = v[from] − 2(rP+xQ) + (r²+x²)l` given the
     REQUIRED voltage RISE from bus 2 (`v≈1.06`) to bus 3 (pinned near its own bound).
     `v[from]` (bus 2) here is NOT near its bound — the inexactness is reverse-flow-driven at
     THIS branch, not primarily a voltage-pinning-at-`v`'s-own-upper-bound effect the OPF-ε
     mechanism targets.
  3. Swept `ε` from `0.02` up to the feasibility boundary (`ε ≈ 0.17`, above which the
     problem becomes `INFEASIBLE`) and measured `ctx.meta[:socp_maxgap]` at each point
     (diagnostic-only `rtol_exact=1.0` override, never committed to test code):
     | ε | socp_maxgap |
     |---|---|
     | 0.02 | 10.39 |
     | 0.05 | 8.87 |
     | 0.10 | 6.24 |
     | 0.15 | 3.03 |
     | 0.17 | 1.58 |
     | 0.18 | INFEASIBLE |
     The gap decreases roughly linearly with `ε` but is still `≈1.58` — six orders of
     magnitude above the `<1e-5` gate — at the LARGEST feasible `ε`, immediately before the
     problem becomes infeasible. **No value of `ε` within this mechanism's own feasible
     range satisfies Task 2's exactness gate on this fixture.**
  4. Cross-checked the modification-gap definition itself: applying
     `recover_lossfree_shadow_voltage` (plan 20-01) to the `RestrictedBranchFlow`'s OWN
     (loose) solved point gives `max(v̂_GL − v) ≈ 0.173` — roughly **30× larger** than the
     `ε_measured = 0.00581` obtained from the single `ACPowerFlow`-solved point RESEARCH.md's
     recipe uses. Gan-Low's Definition 3 defines `ε` as the SUPREMUM over the ENTIRE
     AC-feasible set `F_OPF`, which the paper itself estimates via 1000 Monte-Carlo samples;
     this project's single-point substitute (explicitly sanctioned by D-03's "no
     auto-tuning/bisection loop" constraint, and flagged as a MEDIUM-confidence assumption,
     A4, in RESEARCH.md) is evidently not representative of the true worst case on this
     fixture's aggressive high-PV/reverse-flow regime — and even the empirically-larger
     `≈0.173` value is still 5 orders of magnitude short of what Item 3's sweep shows is
     needed (extrapolating, likely `ε` in the hundreds or more, far beyond the
     `≈0.17` infeasibility ceiling).
- **Why this is Rule 4, not Rule 1/2/3:** the code is correct and matches the interfaces
  section's worked example exactly (verified by Task 1's own acceptance criteria and the
  diagnostics above). The problem is that the CHOSEN mechanism (Gan-Low OPF-ε, D-01) combined
  with the CHOSEN measurement recipe (single AC point, D-03) — both LOCKED decisions from
  RESEARCH.md — do not deliver the promised result on the project's actual, required EXACT-04
  operating point. Fixing this needs one of: (a) a fundamentally different `ε`-measurement
  methodology (which brushes against D-03's explicit "no search/bisection" constraint), (b)
  the fuller Gan-Low "OPF-m" `v̂_GL(s) ≤ v̄` constraint (RESEARCH.md's own "Alternatives
  Considered" table flags this as needing genuinely new JuMP constraints, explicitly deferred
  from this rung's primary mechanism), or (c) accepting this fixture's over-voltage regime
  does not admit an exact SOC restriction via this route at all, and re-scoping OVR-01 to lean
  on the D-09/D-10 nonconvex-AC-dual fallback as the actual answer here. None of these is a
  same-task auto-fix; all are architectural/research decisions requiring the roadmap owner's
  input.
- **Files modified for the diagnosis:** none committed — all diagnostic solves were run via
  ad hoc `julia --project=.` scripts, never written into the repository. Task 1's own files
  (`src/powerflow/RestrictedBranchFlow.jl`, `src/TSODSO.jl`) are unaffected and already
  committed as `704f029`.
- **Action taken:** reverted the in-progress, non-passing Task 2 test-file edit
  (`git checkout -- test/test_restricted_branch_flow.jl`) rather than committing tests that
  would either throw inside `@testitem` execution or misrepresent the finding as a pass.
  `test/test_restricted_branch_flow.jl` is unchanged from plan 20-01's committed state.

### Minor note (acceptance-criteria self-contradiction, not a deviation)

Task 1's own acceptance criteria include `grep -n 'cpydrop\|set_upper_bound(pv.v̂'
src/powerflow/RestrictedBranchFlow.jl` returning NO matches — but the SAME task's `<action>`
text explicitly mandates a comment containing the word "cpydrop" ("Do NOT touch v̂'s bound
(ConvexBranchFlow's cpydrop copy, thesis 3.43)..."). Both cannot be satisfied simultaneously.
Resolved by satisfying the `<action>`'s explicit content requirement (the comment exists,
citing `cpydrop` by name) and instead verifying the acceptance criterion's actual INTENT
directly: `grep -n 'set_upper_bound(pv.v̂\|set_upper_bound(v̂'
src/powerflow/RestrictedBranchFlow.jl` returns zero matches — confirming no code anywhere
sets a bound on `v̂`. T-20-04's mitigation (the anti-pattern is explicitly called out in a
code comment, which the grep's own broad pattern incidentally penalizes) is satisfied.

---

**Total deviations:** 1 Rule-4 escalation (blocking, not auto-fixed) + 1 minor
acceptance-criteria self-contradiction (resolved by satisfying intent).
**Impact on plan:** Task 1 ships as a correct, reusable formulation type. Task 2 — and by
extension plans 20-03/20-04/20-05, which all depend on a working `RestrictedBranchFlow` that
actually closes the exactness gap — cannot proceed until the roadmap owner decides how to
resolve the finding above.

## Issues Encountered

The Task 2 `<verify>` inline script (copied verbatim from the plan) itself reproduces the
blocking finding: it throws inside `solve_welfare`'s internal `assert_socp_exact!` call
before reaching any `@test` assertion, because the default-`ε` `RestrictedBranchFlow` solve
on the EXACT-04 fixture does not close the exactness gap. This is not a script bug — see
Deviations above for the full diagnosis.

## Next Phase Readiness

**NOT ready for plan 20-03 (certificate) as currently scoped.** Blockers:

1. A decision is needed on how OVR-01 proceeds given the Gan-Low OPF-ε mechanism (as
   specified) does not achieve exactness on the EXACT-04 fixture at any feasible `ε`. Options
   surfaced above: (a) revisit the `ε`-measurement methodology, (b) implement the fuller
   OPF-m `v̂_GL(s) ≤ v̄` constraint, or (c) re-scope this rung to rely on the D-09/D-10
   nonconvex-AC-dual fallback as the primary answer for this fixture, with
   `RestrictedBranchFlow` retained as a documented (but non-exact-on-this-fixture) partial
   mitigation.
2. `RestrictedBranchFlow` itself (Task 1) is correct, tested manually, and safe to keep — no
   rework needed there regardless of which option is chosen; only the default `ε` value and/or
   the certificate's expectations need to change.

## Self-Check: PASSED

- `src/powerflow/RestrictedBranchFlow.jl` exists: FOUND.
- `src/powerflow/RestrictedBranchFlow.jl` contains `struct RestrictedBranchFlow`: FOUND.
- `src/TSODSO.jl` contains `RestrictedBranchFlow.jl` include line, positioned after
  `ACPowerFlow.jl`: FOUND.
- Commit `704f029` exists in `git log`: FOUND.
- `test/test_restricted_branch_flow.jl` unchanged from plan 20-01's committed state
  (confirmed via `git diff` showing no pending changes): FOUND.

---
*Phase: 20-overvoltage-capable-relaxation*
*Completed: 2026-08-08 (Task 1 only; Task 2 blocked)*

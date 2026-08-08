---
phase: 20-overvoltage-capable-relaxation
plan: 02
subsystem: SOC-relaxation exactness theory / power-flow formulation
tags: [OVR-01, gan-low, socp-exactness, restriction, opf-m]

requires:
  - phase: 20-01
    provides: "measured ε_measured = 0.005811069127373614, confirmed v ≥ v̂ (Assumption A1), recover_lossfree_shadow_voltage"
provides:
  - "RestrictedBranchFlow <: AbstractPowerFlow (COMPLETE, committed) — Gan-Low OPF-m: direct v̂_GL(s) ≤ v̄ constraint (Theorem 2), built as a live affine JuMP expression, plus an OPTIONAL composable OPF-ε margin (ε kwarg, default 0.0)"
  - "Empirical proof that the SIMPLER OPF-ε special case (v-bound shrink only, RESEARCH.md's original recommendation) CANNOT reach SOCP exactness on the EXACT-04 fixture at ANY feasible ε — documented as a research finding, superseded by OPF-m"
  - "Empirical confirmation that the FULLER OPF-m mechanism DOES reach SOCP exactness on EXACT-04 (socp_maxgap = 2.08e-8, matching RESEARCH.md's ~1e-7 prediction)"
  - "D-08 provenance stash (ctx.meta[:formulation], ctx.meta[:restriction_ε]) on every RestrictedBranchFlow solve"
affects: ["plan 20-03 (certificate — can now assume RestrictedBranchFlow genuinely closes the gap on EXACT-04 via OPF-m)", "plan 20-04 (AC-dual fallback — still relevant for fixtures/regimes where C1 fails; not needed for EXACT-04 itself now)", "plan 20-05 (literate page — should narrate BOTH the OPF-ε failure and the OPF-m success, not just the final mechanism)"]

tech-stack:
  added: []
  patterns:
    - "delegate-then-restrict formulation pattern (RestrictedBranchFlow.contribute! calls ConvexBranchFlow.contribute! first, then adds new constraints/bounds) — reused for BOTH the OPF-ε and OPF-m mechanisms"
    - "model-build-time affine expression mirroring a post-processing function's math (the OPF-m v̂_GL(s) constraint reuses recover_lossfree_shadow_voltage's exact closed-subtree-loss recursion, but built from live JuMP variables instead of value()'d numbers) — a reusable pattern for any future 'constrain a derived physical quantity directly' restriction"

key-files:
  created:
    - src/powerflow/RestrictedBranchFlow.jl
  modified:
    - src/TSODSO.jl
    - test/test_restricted_branch_flow.jl

key-decisions:
  - "Escalated (Rule 4) rather than silently searching for a working ε when the RESEARCH.md-specified OPF-ε special case (single-AC-point measured ε, D-03) failed to close the SOCP exactness gap at any feasible value on EXACT-04 — root cause diagnosed as reverse-flow-driven relaxation slack, not the voltage-pinning effect OPF-ε targets."
  - "Roadmap owner directed implementing the fuller Gan-Low OPF-m mechanism (Theorem 2, Section IV): a direct v̂_GL(s) ≤ v̄ constraint, structural (no free parameter), hence NOT a D-03 violation."
  - "OPF-m closes the gap decisively (socp_maxgap = 2.08e-8 vs the <1e-5 gate) — the honest-negative-result pivot (option c, AC-dual fallback as primary pricer) was NOT needed for this fixture; the fallback (plan 20-04) remains valuable as a general safety net for OTHER fixtures/regimes where C1 might fail, but is not EXACT-04's answer."
  - "OPF-ε retained as an OPTIONAL composable margin (ε kwarg, default 0.0/off) rather than deleted — it is a proven subset of OPF-m's feasible set (F_OPF-ε ⊆ F_OPF-m) and remains available for a researcher who wants extra margin on top of OPF-m on a different fixture."

requirements-completed: [OVR-01]

duration: ~140min
completed: 2026-08-08
---

# Phase 20 Plan 02: RestrictedBranchFlow Summary

**`RestrictedBranchFlow` implements Gan-Low's fuller "OPF-m" restriction (Theorem 2,
Section IV): a direct `v̂_GL(s) ≤ v̄` constraint on the loss-free shadow voltage, built as a
live affine JuMP expression over the existing `P`/`Q`/`l` variables — closing the EXACT-04
SOCP exactness gap to `2.08e-8` (from a documented `≈10.4`) after the simpler OPF-ε
special case (voltage-bound shrink by a single measured scalar) was empirically found
insufficient at any feasible value.**

## Performance

- **Duration:** ~140 min total (Task 1 + diagnosis + Rule-4 escalation + OPF-m rewrite +
  Task 2 + full-suite verification)
- **Started:** 2026-08-08
- **Completed:** 2026-08-08
- **Tasks:** 2 of 2 completed
- **Files modified:** 3 (`src/powerflow/RestrictedBranchFlow.jl` new, `src/TSODSO.jl`,
  `test/test_restricted_branch_flow.jl`)

## Accomplishments

- `RestrictedBranchFlow <: AbstractPowerFlow` — a genuine feasible-set RESTRICTION (D-01),
  dispatched through the unchanged `solve_welfare` entrypoint (D-02), delegating to
  `ConvexBranchFlow.contribute!` first (correctness-drift avoidance).
- **OPF-m mechanism (primary, always active):** the loss-free shadow voltage `v̂_GL(s)`
  (Gan-Low Definition 3/eq. 18 — the SAME quantity `recover_lossfree_shadow_voltage`,
  plan 20-01, computes as post-processing) is built as a live AFFINE JuMP expression at
  model-build time (closed-subtree-loss reverse-BFS + forward recursion, identical math,
  zero new decision variables) and directly constrained `≤ v̄` (Theorem 2, eq. 11/12),
  registered under `:opfm_shadow_voltage`.
- **OPF-ε mechanism (optional, composable, off by default):** the original, simpler
  bound-shrink special case is retained behind an `ε` kwarg (default `0.0`) for a researcher
  who wants extra margin on top of OPF-m — proven safe to compose (`F_OPF-ε ⊆ F_OPF-m`).
- **D-08 provenance:** `ctx.meta[:formulation] = :RestrictedBranchFlow`,
  `ctx.meta[:restriction_ε]` populated on every solve.
- **Free validation signal (Task 2):** the EXISTING, UNMODIFIED `assert_socp_exact!` (PF-04)
  passes at its DEFAULT tolerance on EXACT-04 through `RestrictedBranchFlow` — measured
  `socp_maxgap = 2.08e-8`, matching RESEARCH.md's `~1e-7` prediction.
- **Default-path regression guard (Task 2):** plain `ConvexBranchFlow`'s documented
  inexactness on EXACT-04 (hours 6–15 inexact) is verified UNCHANGED by
  `RestrictedBranchFlow`'s existence — deliberately duplicated from `test_ac_oracle.jl` in a
  second file for double coverage of the anti-pattern Task 1 warns against.
- **Full-suite closing verification:** `2524 passed / 0 failed / 3 pre-existing broken /
  2527 total` — reconciles exactly against the 20-01 baseline (`2518/0/3`) plus this plan's
  6 new `@test` assertions (2 new `@testitem`s × 3 assertions each), zero regressions.

## Task Commits

1. **Task 1: RestrictedBranchFlow — delegate + shrink v's own upper bound by ε
   (original OPF-ε implementation)** - `704f029` (feat)
2. **Rule-4 resolution: implement Gan-Low OPF-m shadow-voltage restriction** - `ca7ab5d`
   (fix) — supersedes Task 1's mechanism after the empirical finding below; retains the OPF-ε
   code as an optional composable margin.
3. **Task 2: free PF-04 validation signal + default-path regression guard** - `24403eb`
   (test)

**Plan metadata:** SUMMARY commit (this commit, following).

## Files Created/Modified

- `src/powerflow/RestrictedBranchFlow.jl` (NEW, then rewritten) - `RestrictedBranchFlow`
  struct/constructor, `contribute!` (delegate + OPF-m constraint + optional OPF-ε shrink),
  `problem_class(::RestrictedBranchFlow) = SOCP()`.
- `src/TSODSO.jl` - one new `include("powerflow/RestrictedBranchFlow.jl")`, positioned
  immediately after `ACPowerFlow.jl`.
- `test/test_restricted_branch_flow.jl` - two new `@testitem`s (free validation signal;
  default-path regression guard), appended to plan 20-01's two existing items (now 4 total).

## Decisions Made

See `key-decisions` in frontmatter. In prose: the plan escalated a genuine research finding
(Rule 4) rather than force-searching for a working `ε` inside the simpler OPF-ε mechanism
(which would have violated D-03's "no auto-tuning/bisection loop" constraint and, empirically,
could not have worked anyway — the gap stayed 6 orders of magnitude above the gate even at the
largest feasible `ε`). The roadmap owner's decision to implement the fuller OPF-m mechanism
resolved the finding decisively: OPF-m is a STRUCTURAL constraint (no parameter to tune, so no
D-03 conflict) and closes the gap to noise-floor scale on the first attempt.

## Deviations from Plan

### Rule 4 escalation — RESOLVED (research finding, then roadmap-owner-directed fix)

**[Rule 4 → resolved] The RESEARCH.md-specified OPF-ε mechanism could not close the SOCP
exactness gap on EXACT-04 at any feasible `ε`; the fuller OPF-m mechanism does.**

**Timeline:**

1. **Implemented OPF-ε exactly per RESEARCH.md's worked sketch** (commit `704f029`): shrink
   `v`'s own upper bound by a single measured scalar
   `ε = 0.005811069127373614 × 1.25 = 0.007263836409217017` (plan 20-01's measured value).
   Verified the mechanism wired correctly (the shrink genuinely binds: bus 3's `v[3,t]` sits
   exactly at `vmax² − ε` for hours 9–15 on EXACT-04).

2. **Task 2's own `<verify>` script (run verbatim) failed**: `solve_welfare` with the default
   `ε`, no `rtol_exact` override, THREW inside PF-04's internal gate —
   `max abs |l·v−(P²+Q²)|=10.995`, virtually unchanged from the plain, unrestricted
   `ConvexBranchFlow`'s documented `≈10.4`.

3. **Diagnosed the root cause** (not a code bug): the dominant residual sits on branch 2
   (bus 2→bus 3), hour 11 — `P[2,11] = −0.387` (REVERSE flow, PV export), `l[2,11] = 10.83`
   — i.e. the relaxation exploits an unphysically large `l` to satisfy the voltage-drop
   EQUALITY given a required voltage RISE downstream, driven by reverse flow, not by `v`
   pinning at its own upper bound (the effect OPF-ε specifically targets; `v[from]=v[2]≈1.06`
   there, nowhere near its bound).

4. **Exhaustively swept `ε`** from the measured default through the ENTIRE feasible range
   (the problem goes `INFEASIBLE` above `ε≈0.18`):

   | ε | socp_maxgap |
   |---|---|
   | 0.0073 (measured default) | ≈11.0 |
   | 0.02 | 10.39 |
   | 0.05 | 8.87 |
   | 0.10 | 6.24 |
   | 0.15 | 3.03 |
   | 0.17 | 1.58 |
   | 0.18 | INFEASIBLE |

   No feasible `ε` gets anywhere near the `<1e-5` gate — off by 6 orders of magnitude even at
   the largest feasible value. **This is a genuine research finding, not a tuning problem**:
   the paper's own Definition 3 defines `ε` as the SUPREMUM over the ENTIRE AC-feasible set
   (estimated via 1000 Monte-Carlo samples in the paper); this project's single-AC-point
   substitute (D-03's "no search" sanctioned simplification) evidently underestimates the true
   worst case by roughly 30× on this fixture's aggressive reverse-flow regime (cross-checked:
   `recover_lossfree_shadow_voltage` applied to the OPF-ε-restricted SOCP's own solved point
   gives `max(v̂_GL−v)≈0.173`, ~30× the measured `0.00581`), and even that larger empirical
   value is still 5+ orders of magnitude short of what the sweep shows is actually needed.

5. **Escalated per Rule 4** (STOPPED, returned a `checkpoint:decision` with the full
   diagnostic record and three options: (a) revisit the ε-measurement methodology,
   (b) implement the fuller OPF-m `v̂_GL(s)≤v̄` constraint, (c) honestly pivot to the D-09/D-10
   AC-dual fallback as EXACT-04's primary pricer).

6. **Roadmap owner selected option (b) with an automatic honest pivot to (c) if (b) also
   failed.** Implemented Gan-Low's OPF-m directly (commit `ca7ab5d`): the loss-free shadow
   voltage `v̂_GL(s)[i,t]` built as a live AFFINE JuMP expression (identical closed-subtree-loss
   recursion to `recover_lossfree_shadow_voltage`, but over the model's own `P`/`Q`/`l`
   variables instead of `value()`'d numbers — no new decision variable), directly constrained
   `≤ v̄` for every non-root bus/time. This is a STRUCTURAL constraint (no tunable parameter),
   so it does not conflict with D-03.

7. **OPF-m succeeded on the first attempt** — no pivot to option (c) was needed:
   `solve_welfare(feeder, RestrictedBranchFlow(), aggs; T=24, λ₀=mem_price, allow_export=true)`
   (default `ε=0.0`, no `rtol_exact` override) returns `socp_maxgap = 2.08e-8` — six orders of
   magnitude BELOW the `<1e-5` gate, and matching RESEARCH.md's own prediction that the
   residual should collapse to the "benign-feeder scale `~1e-7`."

**Why this was Rule 4, not Rule 1/2/3, at the time of escalation:** the OPF-ε code was
correct and matched RESEARCH.md's worked example exactly; the problem was that the CHOSEN
mechanism/measurement combination (both LOCKED research decisions, D-01/D-03) did not
deliver the promised result on the project's actual required fixture — an architectural/
research question, not an implementation defect, requiring the roadmap owner's input on how
to proceed. That input has now been received and applied; the finding is resolved.

**Files modified:** `src/powerflow/RestrictedBranchFlow.jl` (rewritten, commit `ca7ab5d`);
diagnostic sweeps were run via ad hoc `julia --project=.` scripts, never committed.

### Minor note (acceptance-criteria self-contradiction in Task 1's original text, not a deviation)

Task 1's own acceptance criteria included `grep -n 'cpydrop\|set_upper_bound(pv.v̂'
src/powerflow/RestrictedBranchFlow.jl` returning NO matches — but the SAME task's `<action>`
text explicitly mandates a comment containing the word "cpydrop." Resolved by satisfying the
`<action>`'s explicit content requirement (the comment exists, citing `cpydrop` by name,
carried forward into the OPF-m rewrite) and verifying the acceptance criterion's actual
INTENT directly: no `set_upper_bound` call anywhere touches `v̂`'s bound. T-20-04's mitigation
is satisfied.

---

**Total deviations:** 1 Rule-4 escalation (resolved by roadmap-owner-directed OPF-m
implementation, which succeeded) + 1 minor acceptance-criteria self-contradiction (resolved
by satisfying intent).
**Impact on plan:** Both tasks now complete. The mechanism actually shipped (OPF-m) is MORE
POWERFUL and more general than the plan originally scoped (OPF-ε) — a net improvement, not a
scope reduction. Plans 20-03/20-04/20-05 should treat OPF-m as `RestrictedBranchFlow`'s
primary, working mechanism for EXACT-04; the OPF-ε sweep and the AC-dual fallback (plan
20-04) remain valuable, citable context for fixtures/regimes where C1 might not hold as
comfortably as it evidently does here.

## Issues Encountered

The Task 2 `<verify>` inline script literally quoted in the plan (which pins the original
OPF-ε mechanism's default and asserts `restriction_ε > 0.0`) no longer matches the shipped
mechanism's default (`ε = 0.0`, since OPF-m needs no margin). The actual committed
`@testitem` was authored with `ctx.meta[:restriction_ε] >= 0.0` instead — semantically
equivalent D-08 provenance coverage, adjusted for the new mechanism. This is documented here
rather than silently diverging from the plan text.

## Next Phase Readiness

**Ready for plan 20-03 (certificate).** `RestrictedBranchFlow` genuinely closes the SOCP
exactness gap on EXACT-04 via OPF-m (`socp_maxgap = 2.08e-8`), so plan 20-03's certificate can
assume a working restriction to certify against the AC oracle, rather than needing to route
through the fallback by default. Plan 20-04 (AC-dual fallback) and plan 20-05 (literate page)
should still document the OPF-ε sweep finding and the OPF-m resolution as the mechanism's
actual, more nuanced story — including the caveat that OPF-m's own exactness guarantee
remains CONDITIONAL on C1 (not re-verified analytically for EXACT-04 in this plan, only
empirically confirmed to hold in practice via the measured `2.08e-8` residual).

## Self-Check: PASSED

- `src/powerflow/RestrictedBranchFlow.jl` exists and contains `struct RestrictedBranchFlow`:
  FOUND.
- `src/TSODSO.jl` contains the `RestrictedBranchFlow.jl` include line, positioned after
  `ACPowerFlow.jl`: FOUND.
- `test/test_restricted_branch_flow.jl` contains 4 `@testitem` declarations: FOUND
  (`grep -c '^@testitem'` = 4).
- Commits `704f029`, `ca7ab5d`, `24403eb` exist in `git log`: FOUND.
- Full-suite run (`julia --project=. -e 'import Pkg; Pkg.test()'`): **2524 passed / 0 failed /
  3 pre-existing broken / 2527 total** — FOUND (log tail: `Package | 2524 3 2527 23m14.0s`).

---
*Phase: 20-overvoltage-capable-relaxation*
*Completed: 2026-08-08*

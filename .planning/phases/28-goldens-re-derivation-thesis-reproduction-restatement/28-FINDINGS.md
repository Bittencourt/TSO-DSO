# Phase 28 Findings

Findings discovered during Phase 28 (Goldens Re-Derivation & Thesis Reproduction Restatement,
FIX-11) execution, documented as facts (not silently fixed or hidden) per this phase's own
"measure first, never silently drop or soften a caveat" discipline.

## Plan 28-01 — SC-1 Cross-Phase Golden-Move Audit

**Status: RESOLVED.** Built `scripts/audit_goldens.py` (stdlib-only Python), a mechanical,
self-testing detector that parses `git diff 5939799..HEAD -- test/` for numeric-literal
"golden moves" lacking an adjacent old->new + cause attribution comment — deliberately NOT a
re-transcription of the hand-written `26-/27-GOLDEN-AUDIT.md` tables.

- **Script's own run** (base `5939799`, head `9ff2127`): 13 flagged numeric-literal moves, 12
  attributed, 1 flagged unattributed (`test/test_admm.jl:113->145`, `maxiter=200->NONE`).
- **Investigated, not silently accepted:** that one row is a detector false negative of the
  script's own fixed +/-5-line attribution-window heuristic — the real attribution comment
  (D-26-02, Plan 26-16) sits ~30 lines above the assignment. Confirmed already fully
  attributed in `26-GOLDEN-AUDIT.md` Section 1 and in-file. No test/ file needed editing.
- **A second detector blind spot found during cross-reference** (not merely absorbed): bare
  `==` equality-assertion literals (e.g. `test_admm_knifeedge_canary.jl`'s `r.iters 58->56`)
  are structurally invisible to all three extraction regexes. Independently corroborated via
  direct diff/grep inspection — already attributed in-file and in `26-GOLDEN-AUDIT.md`.
- **Every row** of both `26-GOLDEN-AUDIT.md`'s and `27-GOLDEN-AUDIT.md`'s "Golden-value moves"
  tables was checked against the script's own output, or (where structurally outside the
  script's reach — pure additions, `src/`-only changes, renames, formula/behavioral changes)
  against direct `grep`/diff inspection, never against the tables' prose alone.
- **Prose-citation audit** of `.planning/PROJECT.md` and `docs/literate/*.jl`/`docs/writeups/*.typ`
  for the 6 headline moved values: `.planning/PROJECT.md` clean (zero hits);
  `docs/literate/convex_branch_flow.jl` and `thesis_reproduction_assumptions.jl` cite only
  CURRENT, correct values.
- **Verdict:** SC-1 satisfied at Plan 28-01's own HEAD. No open findings were routed to Plan
  28-05 from this plan. See `28-CROSS-PHASE-AUDIT.md` for the full 3-section audit.

**Re-confirmed at Plan 28-05's closing gate:** re-running the same script at the FINAL Phase
28 HEAD reproduces the SAME single flagged row (unchanged since no plan touched
`test/test_admm.jl`). Added an explicit, documented `ALLOWLIST` entry (keyed by file+lineno,
citing this audit's own Section 1) so the closing gate's exit-code check is mechanically
gate-able without editing any `test/` file or widening the detection window (which could
change behavior on future diffs). The script now reports allowlisted rows in their own
visible section — never silently absorbed. Final closing-gate run: 12 attributed + 1
allowlisted (cited) + 0 unattributed, exit code 0.

## Plan 28-02 — REPRO-01 Re-run + Restatement

**Status: RESOLVED.** Measured (never assumed) the REPRO-01 population-point SOCP-exactness
drift F-27-05-2 flagged as a **PRECISION-ARTIFACT** at all three bare call sites
(`solve_welfare`, `fit_baseline` SITE-3, `scripts/thesis_case123_repro.jl`'s own call site) —
confirmed by an independent throwaway script whose measured gap/ratio numbers match the
already-documented Phase 26/27 residuals almost exactly. Resolved by threading the SAME
committed `tol_gap_abs=3e-9`/`tol_gap_rel=1e-9` overrides `test/test_thesis_repro.jl` already
carries into the live docs page and figure-regen scripts — never a new, invented tolerance,
never a raised `τ_solver`/`ε`.

**Headline restatement (full table in `28-RESTATEMENT-SUMMARY.md`):** the reproduction's
pinned claim (DSO-surplus sign flip + prosumer-surplus decrease) reproduces UNCHANGED under
the corrected Phase 26/27 model; `fit_dso`'s magnitude moved from ≈-196.22 to ≈-286.11
(FIX-09/FIX-10's physics-only AC settlement changing the network-settlement term — `fit_prosumer`
itself barely moves). The v2.1 "knife-edge-fragile" population-scale-sensitivity
characterization does **NOT** still hold — genuinely retired by measurement: flake rate
dropped from 13/20=0.650 to 1/20=0.050, and `sign_flip_survives` flipped from `false` (2/5
sweep points) to `true` (5/5 points). This is reported as a positive finding, not silently
dropped (CONTEXT.md's "never silently drop or soften the caveat" instruction — the caveat is
retired by evidence, not by omission).

Regenerated `results/thesis_case123_repro/`, all 6 `results/thesis_caseA/*` figure pairs, and
recompiled `docs/writeups/thesis_caseA.pdf` against the corrected model — fixing a genuine
pre-existing `DimensionMismatch` crash in `scripts/thesis_caseA.jl` (Phase 26 FIX-04's
`soc[T+1]` extension never propagated to this plotting script) along the way.

## Plan 28-03 — SOCP-Inexactness Dual-Mode Re-Verification (EXACT-04)

**Status: RESOLVED.** Re-measured `test_ac_oracle.jl`'s EXACT-04 `@testitem` under BOTH
`ConvexBranchFlow()` (default) and `ConvexBranchFlow(; thesis_literal=true)`, for BOTH
exactness gates:

- **Gate 1 (`assert_socp_exact!`, cone-residual):** both formulations cone-EXACT at the
  EXACT-04 control point (`pv_scale=1.2`) — consistent with, and citing rather than
  re-deriving, PM-01/26-18's own prior measurement.
- **Gate 2 (`assert_ac_exact!`, AC-dispatch comparison):** the pre-Phase-28 test comment
  CONFLATED gate 1 with gate 2. Measured mechanism: the DEFAULT is gate-2 **INEXACT**
  (restriction-induced dispatch-suboptimality, `inexact_hours=6:15`) at this fixture, while
  `thesis_literal=true` is gate-2 **EXACT** there — the OPPOSITE of the stale comment's
  framing. Corrected the comment; assertions unchanged, suite stays green for the now
  correctly-explained reason.
- **Dual-mode `socp_applicability_sweep.jl` extension** (new `formulation` column, full
  150-point highpv grid + IEEE-123 grid re-run under both formulations) uncovered a
  **self-caught overclaim before commit**: an early draft asserted the default is "cone-exact
  by theorem, always" (Gan-Low's Theorem 2). The regenerated data contradicts this as a
  blanket claim — **3/150 highpv grid points are genuinely gate-1 cone-inexact under the
  default** (ratio 8196-9746), rarer than `thesis_literal=true`'s 5/150 (ratio 9727-9872) but
  real. Every instance of the overclaim was corrected before committing.
- **IEEE-123 substrate:** no measurable formulation-dependent difference between the two
  formulations — the fix's directional choice only matters on the high-impedance-ratio 3-bus
  substrate, not on real (low-impedance) IEEE-123.
- **Docs-build-breaking risk caught and fixed** (Pitfall 1): `docs/literate/socp_applicability.jl`'s
  live Substrate-A code had a hard `@assert c_inexact.class == "inexact"` at the now-EXACT
  EXACT-04 control point, which would have thrown at the next Documenter build. Rewritten
  dual-mode with measured expectations.

## Plan 28-04 — MPC Truth-Settlement Restatement + DLMP Closure Verification

**Status: RESOLVED.** `docs/literate/pricing_dlmp.jl`'s FIX-07 `.cone`/`.drop` rename +
deprecated-alias restatement verified ALREADY complete by direct read — not re-edited (no
stale content found). `docs/literate/stochastic_pv_demand.jl`'s own `realized_welfare`
confirmed an UNRELATED, STOCH-axis-specific concept (out-of-sample average over held-out
draws) — no shared drift with `run_mpc`'s FIX-10 semantics, no edit needed.

Restated `docs/literate/mpc_rolling_horizon.jl`'s Section 3 (Regret) and
`scripts/demo_mpc_plots.jl`'s header/console diagnostics to describe FIX-10's truth-settled
`realized_welfare`/`forecast_settled_welfare`/`settlement_violations` semantics with LIVE
measured numbers (never hardcoded prose): on this page's own 24-hour `:ieee13` fixture, **3 of
19 published hours** (abs_hour 10, 13, 14) report a genuine head-branch thermal overload
(`max_overload_ratio` ≈ 1.02/1.004/1.001), zero voltage violations — measured directly before
writing the prose, not assumed to be zero.

**Genuine pre-existing bug found and fixed** (Rule 1, within this plan's own file scope):
`scripts/demo_mpc_plots.jl`'s `mpc_receding_plan` SOC panel threw `DimensionMismatch` — the
SAME latent class of defect as Plan 28-02's `thesis_caseA.jl` fix (Phase 26 FIX-04's
`soc[1:(H+1)]` extension never propagated to this plot's x-range). Fixed the plot's x-range
only; the underlying model's terminal-target VALUE assignment was untouched (out of scope;
`test/test_mpc_terminal.jl` is its existing correctness gate).

## Plan 28-05 — Phase-Closing Gate (full suite + docs build + audit re-run + restatement)

**Status: RESOLVED.**

**Full suite certification:** `Pkg.test()` at final HEAD (all of 28-01..28-04 landed):
**30703 pass / 0 fail / 0 error / 5 broken** — an EXACT match to the Phase 27 close baseline
(30703/0/0/5 at `40ccff2`). Zero deltas to attribute. `git worktree list` showed no
`.claude/worktrees/agent-*` contamination (only unrelated sibling worktrees under
`TSO-DSO.worktrees/*`, a different, non-contaminating location per this plan's own
instruction); the suite log itself contains zero `.claude/worktrees/` lines.

**Docs build certification:** the full `julia --project=docs docs/make.jl` build initially
FAILED with two genuine, pre-existing bugs, neither touching test/ goldens or model behavior
(both Rule 1/Rule 3 auto-fixes, documented in `28-05-SUMMARY.md`'s Deviations section):

1. `docs/literate/prosumer_welfare.jl`'s battery-SOC plot threw `DimensionMismatch`
   (`hours=1:T` vs `bvars.soc` now `T+1`-long since Phase 26 FIX-04) — the SAME latent class
   of bug Plans 28-02/28-04 already found and fixed in `thesis_caseA.jl`/`demo_mpc_plots.jl`,
   never previously caught here because this page had not been exercised end-to-end since
   FIX-04 landed. Fixed by truncating to `bvars.soc[1:T]`, matching the established
   project-wide convention.
2. `docs/make.jl`'s `api.md` (full `@autodocs` page) grew to 676.24 KiB, exceeding the 600 KiB
   `size_threshold` set once post-v1 (`dc0de79`) and never revisited across Phases 9-27's
   organic growth. Raised to 1024/800 KiB with headroom for future growth.

After both fixes, the docs build completed with exit code 0, zero thrown exceptions; all 6
phase-touched literate pages (`thesis_reproduction_ieee123.jl`, `thesis_reproduction_assumptions.jl`,
`ac_oracle.jl`, `restricted_branch_flow.jl`, `socp_applicability.jl`, `mpc_rolling_horizon.jl`)
confirmed non-throwing.

**Audit re-run:** `scripts/audit_goldens.py` re-run at the final HEAD reproduces the same
single known false-negative row from Plan 28-01 (unchanged — no plan touched
`test/test_admm.jl`); resolved by adding an explicit, cited `ALLOWLIST` entry (see Plan 28-01
section above). Final exit code 0.

## Phase 28 completion note

**Status: Phase 28 is COMPLETE.** FIX-11's three sub-clauses (SC-1 cross-phase audit, SC-2
thesis-reproduction re-run, SC-3 SOCP-inexactness + deferred restatements) are all resolved.
Every finding raised during execution has a recorded final disposition:

| Finding | Final disposition |
|---|---|
| SC-1 audit (Plan 28-01) | RESOLVED — mechanical script + cross-reference + prose-citation check all clean; 2 detector limitations disclosed, not hidden |
| SC-1 closing-gate re-run allowlist (Plan 28-05) | RESOLVED — documented, cited allowlist entry; script exits 0 |
| REPRO-01 exactness drift (Plan 28-02) | RESOLVED — PRECISION-ARTIFACT, resolved by pre-existing tol_gap overrides |
| REPRO-01 sign-flip/magnitude restatement (Plan 28-02) | RESOLVED — sign flip holds unchanged; magnitude moved (named cause); knife-edge characterization retired by measurement |
| EXACT-04 dual-mode gate-1/gate-2 (Plan 28-03) | RESOLVED — stale gate-conflation comment corrected; default not unconditionally gate-1 exact (3/150), corrected before commit |
| MPC truth-settlement + DLMP closure (Plan 28-04) | RESOLVED — restated with live-measured numbers; DLMP closure confirmed already complete |
| `prosumer_welfare.jl` SOC DimensionMismatch (Plan 28-05) | RESOLVED — Rule 1 fix, same class as 28-02/28-04's fixes |
| `docs/make.jl` api.md size_threshold (Plan 28-05) | RESOLVED — Rule 3 fix, raised with headroom |
| Full suite + docs build certification (Plan 28-05) | RESOLVED — 30703/0/0/5 (exact Phase 27 match), docs build exit 0 |

**Carried forward for future-phase awareness (not blocking Phase 28 close):**
- F-27-01-2 (`solve_follower!` HiGHS certificate-loss fragility) remains open, out of scope for
  Phase 28 (untouched by any Phase 28 plan).
- The `api.md` `size_threshold` will likely need another bump as the API surface keeps
  growing — no action needed now, flagged for whenever the next size warning appears.

See `28-CROSS-PHASE-AUDIT.md` for the full SC-1 audit detail and `28-RESTATEMENT-SUMMARY.md`
for the consolidated old->new headline-number table.

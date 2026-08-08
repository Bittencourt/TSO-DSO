---
phase: 19-4q-bess-live-reactive-dual-ascent
plan: 07
subsystem: admm
tags: [julia, jump, admm, reactive-power, dual-ascent, mesh-05]

# Dependency graph
requires:
  - phase: 19-01
    provides: "ReactiveMode 3-state enum + normalize_reactive_mode (OFF/CERTIFIED/LIVE)"
  - phase: 19-03
    provides: "build_dso_opt's LIVE reactive coupling block (qag_dso, rho_q, set_rho_q!)"
  - phase: 19-06
    provides: "build_agr_opt's qag_live coupling variable + solve_agr!'s mu_j/d_j/rho_q and check_4q kwargs"
provides:
  - "solve_admm(...; reactive_consensus = :live, rho_q) driving a genuine, jointly-converging
    (lambda, mu) two-block dual ascent, with mu/q_devices as first-class peers of lambda/dadp
    in the return NamedTuple"
  - "The empirical mu-sign-convention finding (mu internal = -dual(:balance_q), mirroring
    lambda's own relationship to dual(:balance_p))"
  - "check_4q wired into the final consolidation block, gated on actual FourQuadBESS device
    presence (not on qag_live !== nothing, which is true for every aggregator under LIVE)"
affects: ["19-08"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "ONE joint stacked (lambda,mu) residual/threshold/record!/converged block feeding a
      SINGLE converged(...) call site (grep-enforced) -- never two independent per-block checks"
    - "Independent adaptive-rho/adaptive-rho_q blocks, each balancing its OWN normalized
      residuals, so a LIVE reactive block can never perturb the active block's own freeze/adapt
      decision (and vice versa)"
    - "solve_dso! (frozen, plan 19-03's shipped signature) does not accept a mu/b/rho_q kwarg --
      the outer loop (this file) pokes DsoOpt.qag's linear coefficient directly via
      set_objective_coefficient, mirroring solve_dso!'s own internal pag_dso update"
    - "check_4q's discriminator is the aggregator's ACTUAL device list (any FourQuadBESS
      member), independent of reactive_consensus mode -- never qag_live !== nothing"

key-files:
  modified:
    - src/admm/solve_admm.jl
  created:
    - .planning/phases/19-4q-bess-live-reactive-dual-ascent/deferred-items.md

key-decisions:
  - "Empirically resolved RESEARCH.md's Open Question 3 (mu-sign convention) on a 2-bus +
    FourQuadBESS fixture with REAL (non-near-lossless) impedance: the internal mu_q converges
    to the NEGATED dual(:balance_q[j]) -- the SAME relationship lambda has to
    dual(:balance_p[j]) -- consistent with the P<->Q structural symmetry of the single
    augmented Lagrangian. Confirmed at two different load/rho_q scales; the negated-hypothesis
    residual was consistently 5-15x smaller than the identical-hypothesis residual, converging
    toward the solver noise floor as tuning improved."
  - "check_4q's condition is `any(d -> d isa FourQuadBESS, agg.devices)` per load node, NOT
    `agr_by_bus[j].qag_live !== nothing` -- the latter is true for EVERY aggregator under LIVE
    regardless of device composition (19-06 ties qag_live to mode==LIVE alone), so it would
    spuriously enable/attempt the certificate on aggregators with no 4Q device at all."
  - "mu/q_devices are STABLE keys in the return NamedTuple, ALWAYS present (nothing under
    OFF/CERTIFIED) rather than conditionally-absent keys -- mirrors this file's own existing
    exact_maxgap convention (always a key, nothing until populated)."
  - "The reactive coupling multiplier's internal variable is named `mu_q` (never bare
    `mu`/`MU`/Greek mu) -- that identifier is PERMANENTLY the pre-existing adaptive-rho
    residual-balancing imbalance band (the `mu::Real = 10.0` kwarg), per
    test_admm_reactive.jl's own grep-audit convention pinned in Phase 16."
  - "DEVIATION (Rule 1 bugfix, found during this plan's own Task 2 verification): the DSO-side
    qag_dso coefficient update used the reactive netflow target `d` where it should have used
    `b` (AGR's own solved qag_live value), mirroring pag_dso's `-lambda-rho*a` (which uses `a`,
    never `c`). The swap produced an unstable, rho_q-independent second-order recursion whenever
    an aggregator's reactive channel was fully rigid (no FourQuadBESS) -- diverging instead of
    converging. Fixed in both the mid-loop and final-block occurrences; re-verified all Task 1
    findings and added a mixed 4Q/non-4Q two-aggregator regression that converges cleanly
    post-fix (it diverged pre-fix)."
  - "Logged, but did NOT fix (out of files_modified scope), a pre-existing `:cone` name
    collision between ConvexBranchFlow.jl (network-level cone) and FourQuadBESS.jl (device-level
    cone) when both share one JuMP model -- blocks a future solve_welfare cross-validation of a
    FourQuadBESS-bearing aggregator, but does not affect solve_admm (AGR-OPT/DSO-OPT are always
    separate models). See deferred-items.md."

requirements-completed: [MESH-05]

# Metrics
duration: ~75min
completed: 2026-08-08
---

# Phase 19 Plan 07: Live Reactive Dual-Ascent Outer Loop Summary

**`solve_admm` now drives a genuinely jointly-converging two-block (λ,μ) dual ascent under
`reactive_consensus = :live` — one stacked residual/stopping check, independently-adapted ρ/ρ_q,
and μ/q_devices published as first-class peers of λ/dadp — while OFF/CERTIFIED stay
byte-identical to pre-Phase-19.**

## Performance

- **Duration:** ~75 min
- **Tasks:** 2/2 completed
- **Files modified:** 1 (`src/admm/solve_admm.jl`)

## Accomplishments

- `solve_admm` normalizes `reactive_consensus` via `normalize_reactive_mode` once, before the
  loop, threading the resulting mode + a new `ρ_q::Real = ρ` kwarg symmetrically into
  `build_dso_opt` and every `build_agr_opt` call.
- The single-block residual/threshold/`record!`/`converged` block is now a JOINT stacked
  (λ,μ) form: under `LIVE` the SAME per-`(j,t)` loop also accumulates the reactive-block
  quantities, feeding ONE `r_norm`/`s_norm`/`ε_pri`/`ε_dual` quadruple to the SAME single
  `record!`/`converged` call site (grep-verified: exactly one `converged(residuals` occurrence
  in the file) — never two independent per-block checks (Pitfall 17 / T-19-15).
  Under OFF/CERTIFIED every reactive accumulator stays `0.0`, so the values are algebraically
  identical to pre-Phase-19.
- The dual-ascent and adaptive-ρ blocks gained mirrored, INDEPENDENT `μ`/`ρ_q` extensions: `μq`
  ascends alongside `λ` under `LIVE` only, and `ρ_q` adapts using the reactive block's OWN
  normalized residuals (own freeze/adapt decision, own `set_rho_q!` calls on both `DsoOpt` and
  every `AgrOpt`) — the active block's own adaptive-ρ decision now explicitly operates on
  active-only quantities (renamed `r_norm_p`/`s_norm_p`/`ε_pri_p`/`ε_dual_p`), so a LIVE
  reactive block can never perturb it.
- `solve_dso!` (plan 19-03's frozen signature) does not accept a μ/b/ρ_q kwarg; `solve_admm`
  drives `DsoOpt.qag`'s linear coefficient directly via `set_objective_coefficient`
  (`-μq[j][t] - ρ_q*b[j][t]`, mirroring `pag_dso`'s own `-λ-ρ*a`), confirmed against 19-03's
  actual shipped code rather than assumed.
- Empirically resolved the μ-sign convention (RESEARCH Open Question 3): the internal `μq`
  converges to the NEGATED `dual(:balance_q[j])`, the same relationship `λ` has to
  `dual(:balance_p[j])`.
- The final consolidation block threads `μ_j`/`d_j`/`ρ_q` into the converged `solve_agr!` calls
  under `LIVE`, and passes `check_4q = true` only for aggregators whose device list genuinely
  includes a `FourQuadBESS` (`has_4q_by_bus`, derived from the actual devices — not
  `qag_live !== nothing`).
- `solve_admm`'s return `NamedTuple` gains stable `μ`/`q_devices` keys: `nothing` under
  OFF/CERTIFIED, and under `LIVE` a `(n_load_nodes, T)` reactive-price matrix (sign-corrected)
  plus a `Dict{Int,Vector{Float64}}` of each `FourQuadBESS`'s converged `q` trajectory.
- Docstring extended with a new "Live reactive dual-ascent (Phase 19, MESH-05)" subsection,
  keeping the existing OFF/CERTIFIED prose verbatim.

## Task Commits

Each task was committed atomically:

1. **Task 1: Empirical μ-sign verification + joint (λ,μ) accumulator/stopping/ascent** —
   `4bfd1f3` (feat)
2. **Task 2: Results surface (μ/q_devices), final-block certificate wiring, docstring** —
   `836b728` (feat)

Supplementary (out-of-scope discovery, logged not fixed): `c586eee` (docs)

## Files Created/Modified

- `src/admm/solve_admm.jl` — `reactive_consensus` promoted to the 3-state mode + new `ρ_q`
  kwarg threaded into both subproblem builders; joint stacked (λ,μ) residual/stopping block
  (single `converged` call site); mirrored dual-ascent + independent adaptive-ρ_q block;
  `set_objective_coefficient` used directly to drive `DsoOpt.qag` (no `solve_dso!` kwarg exists
  for it); final-block `check_4q` wiring gated on actual device presence; `μ`/`q_devices`
  added to the return `NamedTuple`; docstring extended.
- `.planning/phases/19-4q-bess-live-reactive-dual-ascent/deferred-items.md` — logs a
  pre-existing, out-of-scope `:cone` name collision between `ConvexBranchFlow.jl` and
  `FourQuadBESS.jl` discovered during verification (does not affect this plan's own file).

## Verification Evidence

The plan's literal `<verify>` command (`TestItemRunner.runtests(...)`) does not resolve under
`--project=.` (`TestItemRunner` is a `test/Project.toml`-only dependency), consistent with
every prior Phase-19 plan's identical finding. Verified via direct Julia/Test.jl scripts
(not committed; outside this plan's `src/admm/solve_admm.jl`-only scope) at every checkpoint:

1. **Byte-identical default path:** `solve_admm` with no `reactive_consensus` kwarg reproduces
   the 2-bus crossval welfare/DADP to the SAME tolerances as the existing `test_admm.jl` item
   (`isapprox(welfare, obj_c; rtol=1e-4)`, `isapprox(vec(λ), vec(dlmp_c); atol=1e-2, rtol=1e-3)`),
   `iters` unchanged at 2.
2. **`reactive_consensus = true` (CERTIFIED):** reproduces `test_admm_reactive.jl` item 3's
   `:balance_q` no-slack certificate (`max_slack ≈ 2.6e-16 ≤ 1e-6`), and numerically matches
   `reactive_consensus = :certified` (Symbol) to `1e-10` — confirming `normalize_reactive_mode`'s
   Bool/Symbol back-compat.
3. **`grep -c "converged(residuals" src/admm/solve_admm.jl` returns exactly `1`.**
4. **`reactive_consensus = :live` on the 2-bus + `FourQuadBESS` fixture** converges in 6
   iterations (well under `maxiter`), returns `μ` shaped `(1, 24)` and `q_devices[2]` a
   length-24 vector.
5. **`reactive_consensus = :live` with a non-4Q aggregator** converges (2 iterations, the
   reactive channel is trivially degenerate — a fixed constant), and `q_devices` is correctly
   empty (no `FourQuadBESS` present, `check_4q = false` at that node, no crash).
6. **A mixed two-aggregator fixture** (bus 2: `FourQuadBESS`, bus 3: plain aggregator) on a
   3-bus feeder with real branch impedance converges in 19 iterations under `:live`, with
   `q_devices` containing ONLY bus 2's entry.
7. **`test_admm_adaptive.jl`'s 2-bus adaptive-ρ item** reproduces its exact `iters < 500` +
   joint `converged(...)` re-check with `mode == OFF` (default), confirming the renamed
   `r_norm_p`/`ε_pri_p` active-block-only adaptive-ρ quantities are numerically unaffected.
8. `import Pkg; Pkg.precompile()` ran clean (0 warnings/errors) after every edit.

Per the orchestrator's explicit guidance, the full `Pkg.test()` baseline (2439 pass / 0 fail / 3
broken after wave 3/4) was NOT re-run; IEEE-13/IEEE-123 items were NOT exercised in this plan's
verification (per the orchestrator's note and the plan's own `<verify>` filter excluding them).
`git diff --diff-filter=D` was checked after every commit — no unexpected deletions.

## Decisions Made

See `key-decisions` in the frontmatter above. Summarized: (1) empirically pinned the μ-sign
convention (negated, mirroring λ) on a real-impedance 2-bus + `FourQuadBESS` fixture, confirmed
at two scales; (2) `check_4q`'s discriminator is the aggregator's actual device composition, not
`qag_live !== nothing`; (3) `μ`/`q_devices` are stable, always-present return-tuple keys; (4)
found and fixed a genuine implementation bug (d/b swap) during this plan's own verification —
see Deviations below; (5) logged an out-of-scope `:cone` collision rather than fixing it (outside
`files_modified` scope).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `if reactive_consensus` would throw `MethodError` once the kwarg is no
longer `Bool`-typed**
- **Found during:** Task 1, while extending `reactive_consensus`'s type from `Bool` to accept
  `Symbol`/`ReactiveMode` too.
- **Issue:** The pre-existing Phase-16 `:balance_q` certification gate used a bare
  `if reactive_consensus`, which requires a genuine `Bool` condition in Julia — passing `:live`,
  `:certified`, `LIVE`, or `CERTIFIED` would throw `MethodError` at that line.
- **Fix:** Switched the condition to the normalized `mode != OFF`, which also correctly extends
  the certificate to `LIVE` (a genuine, non-pinned coupling variable deserving the same
  no-slack gate `CERTIFIED`'s pinned one gets).
- **Files modified:** `src/admm/solve_admm.jl`
- **Verification:** Re-ran the `CERTIFIED`-mode `:balance_q` certificate check (Bool `true` and
  Symbol `:certified`) — both pass, numerically identical.
- **Committed in:** `4bfd1f3` (Task 1 commit)

**2. [Rule 1 - Bug] DSO-side `qag_dso` coefficient update swapped `b`/`d`, producing an unstable
recursion**
- **Found during:** Task 2's own verification, while testing `check_4q` on a non-4Q aggregator
  under `:live` (a fully rigid reactive channel) — the run diverged instead of converging.
- **Issue:** The DSO-side coefficient update
  `set_objective_coefficient(dso.model, dso.qag[j,t], -μq[j][t] - ρ_q*d[j][t])` used the
  reactive netflow target `d` (mirrors `c`, which feeds AGR's coefficient) where it should have
  used `b` (AGR's own solved `qag_live` value, mirroring how `pag_dso`'s coefficient
  `-λ-ρ*a` uses `a`, never `c`). Analytically, the swap produces a `ρ_q`-INDEPENDENT unstable
  second-order recursion (`x_{k+1}+x_k-x_{k-1}=b0`, characteristic root ≈ −1.618) whenever the
  AGR side is fully rigid (no genuine device flexibility) — diverging regardless of tuning.
- **Fix:** Changed both occurrences (mid-loop and final-block) to use `b[j][t]` instead of
  `d[j][t]`.
- **Files modified:** `src/admm/solve_admm.jl`
- **Verification:** Re-ran all Task 1 checks (unaffected — the bug only manifested for
  fully-rigid reactive channels, which none of Task 1's own fixtures exercised); re-ran the
  μ-sign empirical probe (finding unchanged: negated, now converging cleanly instead of
  oscillating); added and passed a mixed 4Q/non-4Q two-aggregator fixture that previously
  diverged and now converges in 19 iterations.
- **Committed in:** `836b728` (Task 2 commit)

---

**Total deviations:** 2 auto-fixed (both Rule 1 bugs — one a required type-compatibility fix,
one a genuine sign/variable-role swap found by the plan's own mandated empirical verification).
**Impact on plan:** Both fixes were necessary for LIVE mode to function correctly for any
aggregator without full reactive flexibility (a realistic, expected configuration) and for the
3-state mode promotion to work with non-Bool inputs at all. No scope creep — both fixes are
confined to `src/admm/solve_admm.jl`, matching the plan's `files_modified`.

## Issues Encountered

- The near-lossless 2-bus fixture (Phase 6's own dual-sign anchor) produces a genuinely
  degenerate reactive nodal price (μ ≈ 0, D-03) — expected and documented, but it meant the
  μ-sign empirical verification needed a fixture with REAL branch impedance (not the near-
  lossless anchor) to get a decisive, non-noise-floor signal. Resolved by using a standalone
  2-bus fixture with `Branch(1,2,0.01,0.03,10.0)` for that specific empirical check only.
- A pre-existing `:cone` name collision (`ConvexBranchFlow.jl` vs `FourQuadBESS.jl`, both
  registering `:cone` on a shared model) blocks a direct `solve_welfare` cross-validation for
  any `FourQuadBESS`-bearing aggregator — discovered while attempting exactly that check. Out
  of this plan's scope to fix (`src/devices/FourQuadBESS.jl` is not in `files_modified`);
  logged in `deferred-items.md`. Does not affect `solve_admm` itself (AGR-OPT/DSO-OPT are
  always separate JuMP models, so the collision never triggers on the ADMM path).

## User Setup Required

None — no external service configuration required.

## Known Stubs

None. `solve_admm`'s LIVE path is fully wired end-to-end: threading, joint stopping, dual
ascent, adaptive ρ_q, final certificate, and results surface all function on the fixtures
exercised in this plan's verification.

## Next Phase Readiness

- `solve_admm(...; reactive_consensus = :live, ρ_q = ...)` is ready for plan 19-08's dedicated
  `Phase19Fixtures` module and its full validation-architecture test items (the small-radial
  `:live` convergence item, the centralized cross-validation item, and the two-run liveness
  regression) — MESH-05's requirement is functionally complete.
- **19-08 should be aware of two things before writing its fixtures/tests:**
  1. The centralized `solve_welfare` cross-validation cannot yet run with a `FourQuadBESS`
     device present (the `:cone` collision in `deferred-items.md`) — that will need fixing
     first (in `src/devices/FourQuadBESS.jl` or `src/powerflow/ConvexBranchFlow.jl`, both
     outside this plan's scope) if 19-08's fixture combines them in one centralized call.
  2. A reactive channel with NO genuinely flexible device (no `FourQuadBESS` at that bus)
     converges trivially (μ degenerate/near-zero) — this is expected D-03 behavior, not a bug;
     19-08's liveness regression should use a `FourQuadBESS`-bearing bus to observe a
     genuinely-moving μ/q trajectory.
- `μ`/`q_devices` are exported via `solve_admm`'s return tuple and documented; OFF/CERTIFIED
  remain byte-identical to pre-Phase-19, so no existing caller is affected.

---
*Phase: 19-4q-bess-live-reactive-dual-ascent*
*Completed: 2026-08-08*

## Self-Check: PASSED

- FOUND: src/admm/solve_admm.jl
- FOUND: .planning/phases/19-4q-bess-live-reactive-dual-ascent/deferred-items.md
- FOUND: commit 4bfd1f3 (Task 1)
- FOUND: commit 836b728 (Task 2)
- FOUND: commit c586eee (deferred-items docs commit)

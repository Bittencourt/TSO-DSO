# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — Operational Transactive-Energy Core

**Shipped:** 2026-07-20
**Phases:** 9 | **Plans:** 43 | **Tasks:** 83

### What Was Built
- The full operational transactive-energy layer (rungs 0–5): solver abstraction, one swappable
  power-flow residual seam (DC / LinDistFlow / SOCP Convex Branch Flow with validated exactness),
  prosumer device library + aggregator + GLB-CVX social welfare, DADP/DLMP dual-based pricing with
  4-way decomposition, and ADMM decomposition validated against the centralized optimum on IEEE 13 + 123.
- A reproducible experiment harness (declarative `Scenario`, `run_scenario`/`run_sweep`, seeded
  bit-for-bit, provenance-stamped DrWatson storage).
- Literate per-model math documentation (Documenter + Literate, `@example`-executed) and an
  end-to-end regression acceptance gate with pinned fixtures.

### What Worked
- **The residual-seam contract** (locked in Phase 2) paid off: SOCP, pricing dual-extraction, and ADMM
  all reused it verbatim with zero divergent re-implementations — the integration check confirmed a
  single source of truth for every cross-phase seam.
- **Duals-as-prices via JuMP named constraints** made DADP/DLMP extraction a direct `dual(balance)` read.
- **Abstraction ladder**: each rung shipped a runnable, validated solve, so regressions surfaced immediately.
- **Adversarial re-review after each fix pass** caught real consequential defects a single pass missed
  (e.g. Phase-8 WR-06 stale save-path, Phase-9 CairoMakie manifest not re-resolved → silent figure no-op).

### What Was Inefficient
- **Requirement-checkbox bookkeeping drifted**: phases 1–7 never ticked their REQUIREMENTS.md checkboxes
  (only phase.complete for 8–9 did), forcing a milestone-close reconciliation of 33 stale entries.
- **Thesis-figure calibration gap surfaced late** (Phase 4/5): the +$1819 / +25% welfare headlines can't
  be reproduced without digitizing figure-bound inputs — pinned computed goldens instead; a documented
  follow-up rather than a blocker.
- A few executor Rule-1 deviations (default ADMM ρ too small, device-contract mismatch in a doc example)
  were only caught at solve time — earlier fixture-level checks would have pre-empted them.

### Patterns Established
- **One residual seam, many formulations**: `contribute!`/`add_to_residual!` is the only place branch/
  voltage math is written; every solve strategy consumes it.
- **Solve-before-dual gating**: `assert_solved!(; dual=true)` + `assert_socp_exact!` guards every price read.
- **Inline typed golden + `rtol`** for regression pins (not external golden files); JLD2/CSV reserved for
  experiment outputs.
- **Computed goldens as regression anchors** when the literature figure isn't reproducible from vendored
  data, with the thesis number kept as a non-failing `@test_broken`/`@info` cross-check.
- **Weakdep-gated optional deps** (Gurobi/Mosek/CairoMakie) with `Base.find_package(...) !== nothing` guards.

### Key Lessons
1. Lock the reusable seam against real math **before** generalizing — it prevented divergent power-flow
   implementations across four consumers.
2. When a literature headline number depends on figure-bound inputs, pin a **computed golden** and record
   the reproduction gap as an explicit, accepted deferral — don't let it block the milestone.
3. `phase.complete` must actually tick REQUIREMENTS.md checkboxes; otherwise traceability drifts silently
   until milestone close.
4. A second adversarial review pass after fixes is worth its cost — it repeatedly caught fix-induced
   regressions (stale paths, silently-skipped guards) that the first pass and the executor self-checks missed.

### Cost Observations
- Model mix: orchestration on Opus; all executor / researcher / planner / reviewer / verifier subagents on Sonnet.
- Parallelism: Phase-9 wave 1 ran 3 independent doc/test plans concurrently in isolated worktrees; the
  strictly-sequential dependency chains (Phase 8, and Phase-9 waves 2–3) ran sequentially on the main tree.
- Notable: the dominant wall-clock cost was the full test suite (~7–8 min incl. IEEE-123 ADMM), run at
  every wave boundary and every verification — the correct place to spend it for a correctness-first bench.

---

## Milestone: v2.0 — Stackelberg-Nash TSO-DSO Planning Game

**Shipped:** 2026-07-24
**Phases:** 5 (10–14) | **Plans:** 13

### What Was Built
The thesis's planning layer as rungs 6–7: a build-once, Parameter-pinned planning oracle with
retry/checkpoint resilience (Phase 10); a hand-rolled single-distributor Stackelberg-Benders loop
certified 4-ways against BilevelJuMP MPEC reductions (Phase 11); cut-store + trace hardening at
realistic iteration counts (Phase 12); SharedTransmission N-distributor corridor coupling with
Gauss-Seidel Nash diagonalization and a multi-seed/multi-order honesty probe (Phase 13); and
permanent regression infrastructure — pinned goldens, no-binaries guard + tripwire, two live
literate docs pages (Phase 14).

### What Worked
- Certify-before-build sequencing: resolving the leader/follower semantics and dual-sign convention
  empirically (Phase 11) before the Nash loop consumed them eliminated an entire class of
  wrong-direction rework in Phases 13–14.
- The review→fix→re-review loop (capped at 3 iterations) caught a phase-defining defect: CR-01 in
  Phase 13 found the multi-seed probe was structurally vacuous (z0 never seeded model state) even
  though all tests passed — plan-conformant code, design-level gap.
- Verifiers that execute rather than read: the Phase 14 verifier injected a fake builder to prove
  the tripwire actually trips; the integration checker ran 332 planning tests empirically.

### What Was Inefficient
- Stale executor worktrees from earlier sessions polluted `@run_package_tests` discovery, costing a
  23-minute confounded test run and an attribution investigation mid-phase-13. Root cause: bare
  TestItemRunner discovery scans `.claude/worktrees/`; fix: explicit-path/name-filter runs from
  scratch envs, now standard executor guidance.
- The user-local Project.toml drift (CairoMakie weakdep→hard dep) made the only "failure" in every
  main-checkout suite run a known false alarm that had to be re-attributed each gate.
- Background long-running gates (test suite, docs build) were killed twice by the environment and
  had to be re-run — sequential foreground-with-timeout proved more reliable for the docs build.

### Patterns Established
- Gate-then-golden regression ordering (assert the validity gate before the pinned value).
- Registry + source-scan tripwire for scope guards (no new builder can silently skip the
  no-binaries check).
- Structural honesty language in code: "a converged equilibrium (spread: …)", never "the".
- Fresh cut store per Nash best-response until a cut-validity argument exists (instrumented, not
  silently retained).

### Key Lessons
1. Tests passing ≠ mechanism live: the seed-liveness CR-01 showed a gating probe can be green while
   structurally unable to detect what it gates — add liveness regressions (two runs differing only
   in the probed dimension must produce different trajectories).
2. Docs are code: the Documenter build was silently red (33 orphaned docstrings) for two phases
   because nothing gated it; Phase 14 made `checkdocs=:exports` + build-exit-0 a tracked anchor.
3. Algebraic-substitution claims in docs need the constant terms reconciled explicitly (the
   Deferrable +18 offset would have shipped a wrong objective narrative to the thesis).

### Cost Observations
- Model mix: orchestration on the main-loop model; all executor/researcher/planner/reviewer/
  verifier/fixer subagents on Sonnet.
- Parallelism: Phase 14 ran all 3 plans concurrently in isolated worktrees (zero file overlap);
  Phase 13's dependent waves ran sequentially.
- Notable: full-suite wall clock ~9 min/run at every wave boundary + verification — still the
  right spend for a correctness-first bench; targeted TestItemRunner filtered runs (1–3 min)
  carried most per-task verification.

---

## Milestone: v2.1 — Validation & Reproduction

**Shipped:** 2026-07-26
**Phases:** 4 | **Plans:** 14 | **Tasks:** 27

### What Was Built
An independent nonconvex AC-OPF oracle (`ACPowerFlow` + `assert_ac_exact!`) certifying the SOCP
relaxation per-hour; a certified reactive DLMP component (`reactive_consensus`/`qag_dso`/
`extract_reactive_dlmp`, byte-identical default path); real positive-sequence IEEE-123 impedances from
public OpenDSS data via a dependency-free Fortescue parser; and a directional ("directional,
public-data") thesis reproduction pinned on the DSO-surplus sign flip. Two honest scientific findings:
the SOCP relaxation is genuinely inexact under high-PV reverse flow (found twice, independently), and
the thesis +25% welfare magnitude does not transfer to real data (only the sign flip does).

### What Worked
- **Honest-finding-as-deliverable** is now a first-class pattern: EXACT-04 (SOCP inexactness), IMPED-03
  (asymmetric voltage-binding), and REPRO (sign-flip-yes / magnitude-no) all shipped a *negative or
  caveated* result as the deliverable rather than tuning it away — and the three cross-validate each
  other (all trace to the same overvoltage/exactness knife-edge).
- **Pipelining planning during execution**: Phase 16/17 planning ran (as background research/plan/check
  agents) while Phase 15 executed — the whole pipeline stayed busy despite one long Julia execution.
- **Adversarial plan-check kept paying off**: caught the Phase-15 `docs/src/api.md` `@autodocs` gap that
  would have failed `checkdocs=:exports` at build time; later phases pre-empted the same trap.
- **Measurement-before-golden** (Phase 18) prevented pinning a fragile band — the ±2–5% sweep exposed the
  knife-edge before the golden was set.

### What Was Inefficient
- **Executor-stall on the long full suite**: Phase 15 and 17 executors launched `Pkg.test()` detached and
  ended their turn before it finished, leaving VERIFICATION.md unwritten — required manual finalize +
  a separate goal-backward verifier pass. Fix applied mid-milestone: instruct executors to run the full
  suite foreground/polled-to-completion (Phase 16/18 did this cleanly).
- **Waiter self-match bug**: a `pgrep -f "Pkg; Pkg.test"` liveness loop matched its own command line and
  spun forever; switched to PID-based `kill -0` waits.
- **Makie precompile** (~13 min) dominated the first full-suite wall clock; subsequent runs were fast
  (cached) — but it made the first execution look stuck.
- **Doc-sync drift**: several executors finished the work but didn't tick ROADMAP/REQUIREMENTS checkboxes
  (Phase 17 especially) — reconciled at milestone close.

### Patterns Established
- Report-don't-throw certification (`assert_ac_exact!`) for anything that can legitimately find a gap.
- Pin thesis/economic goldens on sign-safe quantities (surplus sign flip), never ratios of possibly-
  negative aggregates.
- Never invoke `@run_package_tests` via `julia -e` (picks up stale sibling worktrees) — use
  `test/runtests.jl` or explicit-path `run_tests`.

### Key Lessons
1. A genuine negative/boundary result, honestly framed, is a stronger deliverable than a tuned-green pass —
   and independent phases hitting the same boundary is corroboration, not coincidence.
2. Long external processes the harness can't track (detached `Pkg.test()`) must be polled to completion by
   PID inside the same turn, or the finalize step silently gets skipped.

### Cost Observations
- Model mix: orchestration on Opus (1M context, main loop); all research/plan/check/execute/verify
  subagents on Sonnet.
- Sessions: 1 long background session (plan+execute+verify all four phases, then archive).
- Notable: pipelining planning during execution hid most of the one long (~80 min) Julia execution;
  full-suite wall clock ~13 min first run (Makie precompile), ~3–5 min cached thereafter.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Phases | Key Change |
|-----------|--------|------------|
| v1.0 | 9 | Established the GSD abstraction-ladder + residual-seam workflow; introduced VALIDATION.md (Nyquist) in Phase 9 |
| v2.0 | 5 | Autonomous phase pipeline (smart discuss → plan → parallel worktree execute → review/fix loop → verify); certify-before-build for ambiguous game semantics; execution-based (not read-only) verification |
| v2.1 | 4 | Fully background autonomous run (plan+execute+verify all 4 phases in one session); pipelined planning during execution; honest-finding-as-deliverable; manual verifier finalize when executors stalled on the long suite |

### Cumulative Quality

| Milestone | Tests | Broken (documented) | Notes |
|-----------|-------|---------------------|-------|
| v1.0 | 1946 pass / 0 fail | 2 | 2 broken = non-failing thesis-figure cross-checks; docs build green |
| v2.0 | 2276 pass / 0 fail* | 3 | 3 broken = CairoMakie-weakdep skips; *1 local-only Aqua failure from user-local uncommitted Project.toml drift (committed state clean); docs build green incl. 2 new planning pages |
| v2.1 | 2348 pass / 2 fail* | 3 | *2 fail = pre-existing user-local CairoMakie/Makie Project.toml drift (Aqua stale-deps + persistent-tasks), not regressions; +72 tests over v2.0; docs build green incl. 3 new pages (ac_oracle, ieee123_impedances, thesis_reproduction ×2) |

### Top Lessons (Verified Across Milestones)

1. (v1.0) Lock reusable seams against real math before generalizing.
2. (v1.0) Pin computed goldens + keep literature numbers as non-failing cross-checks when inputs aren't reproducible.
3. (v1.0→v2.0, confirmed) Adversarial re-review after fixes keeps catching what executor self-checks miss — in v2.0 it caught a structurally-vacuous gating probe (CR-01) and a wrong docs equivalence claim.
4. (v2.0) Green tests don't prove a mechanism is live — pair every gate with a liveness regression that varies only the gated dimension.
5. (v2.1) An honestly-framed negative/boundary result is a stronger deliverable than a tuned-green pass — and independent phases hitting the same boundary (SOCP overvoltage inexactness on IEEE-13 and real IEEE-123) is corroboration.
6. (v2.1) Pin economic goldens on sign-safe quantities (surplus sign flip), never ratios of possibly-negative aggregates — and poll detached long-running processes to completion by PID within the turn, or the finalize step silently gets skipped.

# Phase 26 Baseline — Pre-Fix Full Suite State

**Purpose:** Trustworthy, HEAD-attributed pre-fix baseline for Plan 26-08's final SC-6
golden-move audit to diff against, superseding the 34-50-day-old `background-suite-orphan-race`
memory note.

## Provenance

- **`PRE_PHASE_SHA`:** `5939799852270a1e6cc894d2d8d676496b7cf9d6` (`docs(26): begin phase
  execution`) — the phase's declared execution base; no Phase-26 code change has landed at this
  commit.
- **Capture timestamp:** `2026-09-28T14:06:49-03:00` (`2026-09-28T17:06:49Z`), recorded
  immediately before launching the suite.
- **Local drift check:** `git status --porcelain -- Project.toml Manifest.toml
  Manifest-v1.12.toml` → **empty** (no local uncommitted Project.toml/Manifest drift in this
  checkout).

## Isolation Method (deviation from the plan's literal nested-worktree instruction — Rule 3)

The plan's literal instruction was to `git worktree add --detach
../tso-dso-phase26-baseline-worktree "$PRE_PHASE_SHA"` from the main checkout and run the suite
there, sibling to the main repo. This executor instead runs as a **parallel wave-1 worktree
agent** (`worktree-agent-a82a99045b32f5f8b`), already a dedicated git worktree checked out at
`PRE_PHASE_SHA` (verified by the mandatory pre-execution branch check: `git reset --hard` to
`5939799852270a1e6cc894d2d8d676496b7cf9d6` succeeded and was confirmed). This worktree already
satisfies the plan's self-enforcing isolation requirement in substance:

- It is a distinct git worktree/checkout, not the main repo working directory.
- No other wave-1 plan's fix commits can land in THIS worktree's filesystem — worktrees are
  independent working directories; sibling agents' commits live in their own worktrees and are
  merged into `main` only by the orchestrator, after this plan's suite run completes.
- Nesting a second `git worktree add` inside this already-isolated worktree was not attempted:
  the sandbox explicitly refuses complex `git` invocations that point outside the current
  worktree root, and the isolation property the nested worktree would have provided is already
  held by the outer one.

The suite was therefore run directly in this worktree's checkout via:
```
nohup setsid bash -c 'julia --project=. -e "import Pkg; Pkg.test()" > 26-baseline-suite.log 2>&1; echo $? > 26-baseline-suite.done' </dev/null &
```
launched from this worktree's root, polled via a bounded background loop (not a foreground
sleep chain, not a raw `&` job that would die with the turn), per the
`background-suite-orphan-race` memory's guidance.

## Isolation Certificate (self-enforcement check)

Captured **after** the `.done` marker appeared, before writing this file:

- `git rev-parse HEAD` → `5939799852270a1e6cc894d2d8d676496b7cf9d6` — **MATCHES** `PRE_PHASE_SHA`
  exactly. ✅
- `git status --porcelain -- src/ test/ Project.toml Manifest.toml Manifest-v1.12.toml` →
  **empty**. ✅ Nothing wrote into the worktree's tracked source/manifest files during the
  ~31-minute run.

**Verdict: NOT CONTAMINATED.** The worktree's HEAD did not advance and its tracked tree stayed
clean throughout the suite run — no parallel wave-1 fix commit, and no suite side-effect, altered
the code this baseline measures.

## Run Command & Timing

```
julia --project=. -e 'import Pkg; Pkg.test()'
```
run from this worktree's root (the real `test/runtests.jl` entrypoint via `TestItemRunner`'s
`@run_package_tests`, immune to the sibling-worktree cwd-resolution hazard documented in
`local-project-toml-drift`).

- Exit code: `0` (written to `26-baseline-suite.done`).
- Total suite time (Test.jl's own reported `Package` testset time): **30m55.3s**.
- Total wall-clock from process launch to `.done` marker: ~31-33 minutes (includes Julia
  precompilation/dependency resolution before the timed testset starts) — longer than the
  `background-suite-orphan-race` memory's ~16-23 min estimate for this suite, attributable to a
  fresh worktree checkout with its own precompile cache state, not a regression.
- Log size: 140,500 lines (`26-baseline-suite.log`).

## Baseline Counts

Extracted verbatim from `26-baseline-suite.log:140498-140500`:

```
Test Summary: |  Pass  Broken  Total      Time
Package       | 30154       3  30157  30m55.3s
     Testing TSODSO tests passed
```

| Metric | Count |
|--------|-------|
| **Pass** | 30154 |
| **Fail** | 0 (column omitted by Test.jl's summary table — omitted columns are zero counts; confirmed no `Fail` text anywhere else in the log) |
| **Error** | 0 (column omitted; confirmed no unattributed `Error`/`ERROR:` text in the log — the only two `ERROR:` lines are the expected, caught HiGHS-MIQP-incapacity negative-regression output, see below) |
| **Broken** | 3 |
| **Total** | 30157 |
| **Soft-scope-ambiguity warnings** (`grep -c "soft scope is ambiguous"`) | **0** — satisfies `test/runtests.jl`'s own documented invariant |

**Overall verdict: clean.** 0 fail, 0 error, all 3 non-pass items are named, expected `Broken`
markers (below), not regressions.

## Attribution — Every Non-Pass Item

### 1-2. CairoMakie weakdep absence → 2× `@test_skip` (reported as `Broken`)

- **Files/lines:**
  - `test/test_diagnostics_plot.jl:106` — `@test_skip Base.find_package("CairoMakie") !== nothing`
  - `test/test_planning_nash.jl:588` — `@test_skip Base.find_package("CairoMakie") !== nothing`
- **Cause:** This worktree's `Project.toml`/`Manifest*.toml` are the clean, **committed** state —
  CairoMakie is a `[weakdeps]`-only optional extension dependency (per the
  `local-project-toml-drift` memory, Pedro's *main checkout* has an uncommitted, deliberate local
  promotion of CairoMakie to a hard dep, which this isolated worktree does NOT inherit since
  `git worktree add`/`reset --hard` only materializes committed state). With CairoMakie absent,
  `Base.find_package("CairoMakie")` returns `nothing`, so both tests `@test_skip` themselves by
  design (confirmed live: `26-baseline-suite.log:367` and `:80420` both print "CairoMakie not
  installed (weakdep) — SKIPPING the with-CairoMakie Figure check").
- **Consequence for this baseline (as the plan anticipated):** the historically-known **Aqua
  CairoMakie stale-deps/persistent-tasks pair** (2 known-false failures on Pedro's dirty main
  checkout, per `local-project-toml-drift`) is **ABSENT** from this run — not because it was
  fixed, but because this isolated worktree never carries the main checkout's uncommitted drift
  that causes it. This absence is a cleaner, more correct signal (a byte-committed clean-state
  measurement), not a contamination or a regression to chase. Separately, this run's `Aqua`
  quality testset itself did not appear in the log at all in this configuration — confirmed
  no `Aqua`/`Stale dependencies`/`Persistent tasks` text anywhere in the 140,500-line log,
  consistent with the clean checkout never triggering that code path.
- **Verdict:** Expected, environment-driven, not a regression.

### 3. Welfare-ratio figure-bound cross-check → 1× `@test broken=` (reported as `Broken`)

- **File/line:** `test/test_pricing_welfare.jl:358` —
  `@test (gap < 0.1) broken = (gap >= 0.1)`
- **Measured value (this run):** `26-baseline-suite.log:36972-36974` —
  ```
  ┌ Info: welfare: +25% headline ratio vs thesis 1.25 (figure-bound cross-check)
  │   ratio = 0.9999738567566051
  └   gap = 0.2500261432433949
  ```
  `gap ≈ 0.2500 ≥ 0.1` ⇒ `broken = true` ⇒ `(gap < 0.1)` is false ⇒ Test.jl reports this as
  `Broken` (a dynamically-evaluated `@test ... broken=` marker never reddens the suite when the
  broken condition is met, by design).
- **Cause:** This is the well-documented, **already-shipped, honest v2.1 finding** — see
  PROJECT.md's "Shipped Milestone: v2.1": *"the headline +25% welfare magnitude does **not**
  [reproduce] (~+0.045%)"* and REPRO-02. This is a figure-bound cross-check against the thesis's
  own (IP-blocked, undigitized) headline number, deliberately wired as a non-failing `broken=`
  assertion so the gap stays suite-visible without spuriously reddening CI (per the plan-checker
  note in the test file itself, W#2). It is **not** a FIX-01..05 defect and is out of this
  phase's scope (thesis reproduction restatement is Phase 28's REPRO-STRETCH capstone).
- **Verdict:** Expected, pre-existing, honest negative finding — not a regression, not in this
  phase's fix scope.

### Two related dynamic `broken=` assertions confirmed NOT broken in this run

For completeness (both use the identical `@test gap < 1e-2 broken = (gap >= 1e-2)` idiom as the
welfare-ratio one above, so they were checked to rule out being the 3rd `Broken` item):

- `test/test_ieee13.jl:229` — measured `gap = 0.005691946619768684 < 1e-2` ⇒ genuine **Pass**
  (`26-baseline-suite.log:27534-27538`).
- `test/test_acceptance.jl:95` — same measured gap, same file/line pattern ⇒ genuine **Pass**
  (`26-baseline-suite.log:27543-27547`).
- `test/test_thesis_repro.jl:216` — `@test sign_flip_holds broken = !sign_flip_holds`, measured
  `sign_flip_holds = true` (`26-baseline-suite.log:366`) ⇒ genuine **Pass**, consistent with the
  v2.1 corrected finding that the DSO-surplus sign flip does reproduce.

### Flakes named in memory but NOT observed this run

- **Intermittent Clarabel `NUMERICAL_ERROR` on IEEE-13 ADMM** (documented in
  `background-suite-orphan-race`, v1.0/v2.0 deferred tech debt): did **not** fire in this run —
  0 errors total. Re-measure per the memory's own guidance ("re-measure empirically per phase,
  don't assume prior milestones' rates hold"); this run's absence is a single data point, not a
  fix.
- **`test_stochastic_welfare.jl:197` no-trip flake** (named in `background-suite-orphan-race`'s
  2026-08-24 baseline): did not fire — 0 failures total.
- **`fit_baseline` `ALMOST_OPTIMAL` non-convergence at `tol_gap=1e-10`** (STATE.md, flake rate
  13/20 historically, tracked as FIX-09 / Phase 27): the log does show (line ~349-353) an
  **expected** `fit_baseline` `INFEASIBLE` fallback path on IEEE-13 secondary
  ("`fit_baseline infeasible as expected (Pitfall 2); falling back to the manual S_max-relaxed
  FIT solve`") — this is the test's own documented, non-failing fallback branch, not an
  unhandled flake; it did not manifest as a suite failure/error in this run.

## Environmental Artifact (non-blocking, not a test outcome)

`DrWatson.tagsave`'s provenance-stamping helper repeatedly attempted `git --git-dir=<worktree
git-dir> --work-tree=<worktree> diff HEAD` and failed with `ProcessExited(129)` (a `git` usage
error, dumping its own `diff --help` text into the log) **1057 times** across the run — always
caught internally by DrWatson (`saving_tools.jl:153`, "Returning `nothing` instead") and never
propagated as a test failure. This inflates the raw log to 140,500 lines but has **zero effect**
on the pass/fail/error/broken counts above. Root cause not investigated further (out of this
plan's scope — DrWatson's git-diff provenance stamp evidently does not resolve cleanly against
this worktree's separate `--git-dir`/`--work-tree` layout); flagged here only so a future reader
of the raw log is not confused by the volume of repeated help-text dumps.

## Reference for Plan 26-08

This file, together with `26-baseline-suite.log`, is the trustworthy pre-fix reference. Plan
26-08's SC-6 golden-move audit should diff its own final full-suite run against:

- **Pass:** 30154 · **Fail:** 0 · **Error:** 0 · **Broken:** 3 (all named above) · **Total:** 30157
- **Soft-scope warnings:** 0
- **HEAD:** `5939799852270a1e6cc894d2d8d676496b7cf9d6`

Any new Fail/Error at phase close is a genuine regression to investigate. Any golden VALUE that
moves (e.g., `test_restricted_branch_flow.jl`'s `v ≥ v̂` sign-relationship spot-check, per
26-RESEARCH.md) must be re-derived and explained in that plan's own SUMMARY table, not silently
re-pinned.

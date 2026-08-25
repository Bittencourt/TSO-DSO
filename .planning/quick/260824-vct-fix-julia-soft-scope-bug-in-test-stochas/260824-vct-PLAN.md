---
quick_id: 260824-vct
description: Fix the Julia soft-scope bug in test_stochastic_welfare.jl's D-06 PF-04 gate scan
date: 2026-08-24
mode: quick
---

# Quick Task 260824-vct: Fix the soft-scope bug in the D-06 PF-04 gate scan

## Why

`test/test_stochastic_welfare.jl`'s `@testitem "stochastic_welfare: D-06 PF-04 gate runs per
scenario, never aggregated ..."` scans `pv_scale` values looking for the one that trips the PF-04
exactness gate, records the result in `tripped`/`trip_pv_scale`, then asserts `@test tripped`.
This is a Julia **soft-scope bug in the test**, already fully root-caused this session (CI run
32791955335), not a solver/environment flake:

- `tripped = false`, `trip_pv_scale = NaN`, `outcomes = String[]` are assigned directly inside the
  `@testitem` body — i.e. at module top level, making them globals.
- The `for pv_scale in (...)` loop that follows is a **soft scope**. The `tripped = true` /
  `trip_pv_scale = pv_scale` assignments inside it (and inside its nested `catch`) therefore
  create **brand-new locals** that die with the loop iteration instead of updating the outer
  globals — Julia's documented soft-scope-ambiguity rule for top-level code.
- CI's own log proves this exactly: a `Warning: Assignment to 'tripped' in soft scope is
  ambiguous ...` (and the identical warning for `trip_pv_scale`) prints immediately before
  `@test tripped` fails, on every Julia version tested. The self-diagnosis `outcomes` vector shows
  exactly ONE entry (`"pv_scale=1.0: solved + certified exact ..."`), proving the loop DID
  `break` on the pv_scale=2.0 trip — the gate fired exactly as measured — only the flag failed to
  escape the loop.
- A minimal repro (`module M; tripped=false; for x in (1,2,3); if x==2; tripped=true; break; end;
  end; println(tripped); end` → prints `false`) matches CI byte-for-byte.

The file's own comment block (currently attributing this to `Pkg.test()` sandbox package
resolution — hypothesis "uncommitted `Project.toml`/`Manifest-v1.12.toml` drift changes the
resolved Clarabel/StableRNGs") is **wrong** and must be replaced with this diagnosis. The
MEASURED content just above it (pv_scale=1.0 exact, pv_scale=2.0 structurally inexact at
maxratio≈9688, `TRIP_PV_SCALE_MEASURED = 2.0`) is correct and stays untouched.

## Scope

Only `test/test_stochastic_welfare.jl` changes. No `src/` changes. Do not weaken, skip, or
`@test_broken` the `@test tripped` assertion — the fix must make it pass because the gate
genuinely trips at pv_scale=2.0, never by loosening it. Keep the per-scale `outcomes` recording
and the `if !tripped` self-diagnosis `@info` block (they cost nothing and remain useful); only
their stale explanatory comment changes.

## Tasks

### Task 1 — wrap the scan's mutable state in a `let`, and correct the diagnosis comment

- **files:** `test/test_stochastic_welfare.jl`
- **action:**
  1. In the `@testitem "stochastic_welfare: D-06 PF-04 gate runs per scenario, ..."` body,
     locate the comment block that currently starts at `# Widened (Rule 1 fix, plan 22-05 —
     discovered by this phase's own closing full-suite` and runs through `# mitigation-in-depth,
     not as the explanation.` (directly below the `# MEASURED (...)` comment, directly above
     `tripped = false`). Replace that entire block with a corrected diagnosis comment. The
     replacement must state, in the file's existing comment style:
     - The historical CI no-trip failure was a Julia **soft-scope bug in this test file**, not a
       solver/package-resolution flake.
     - `tripped`, `trip_pv_scale`, `outcomes` were assigned at `@testitem` top level (module
       global scope); the `for pv_scale in (...)` loop is a soft scope, so the `tripped = true` /
       `trip_pv_scale = pv_scale` assignments inside it created new locals that died with the
       loop instead of updating the globals.
     - Cite the CI evidence: the `Warning: Assignment to 'tripped' in soft scope is ambiguous
       ...` (and `trip_pv_scale`) diagnostic printed immediately before the `@test tripped`
       failure on every Julia version tested, and the self-diagnosis `outcomes` vector showing
       exactly one entry (`pv_scale=1.0: solved + certified exact ...`) — proof the loop DID
       `break` on the pv_scale=2.0 trip and only the flag failed to escape.
     - Explain why every isolated script re-run of the identical logic reproduced the trip: a
       plain script wraps top-level code in a function body, where the same assignment is an
       ordinary (unambiguous) local — same code, different scope class, not an
       environment/package-resolution difference.
     - State the fix: the scan's mutable state now lives inside a `let` block (a hard scope), so
       the loop's assignments resolve unambiguously to the `let`'s own locals; point to the code
       immediately below.
     - Remove the retracted claim that uncommitted `Project.toml`/`Manifest-v1.12.toml` drift
       (or any package-resolution difference) explains the historical failure — do not repeat
       that hypothesis as a live explanation anywhere in this file.
  2. Immediately below that comment, wrap the existing scan (the `tripped = false` /
     `trip_pv_scale = NaN` / `outcomes = String[]` initializers, the `# WR-06/WR-07: per-scale
     record...` comment, and the full `for pv_scale in (...) ... end` loop, byte-identical
     inside) in a `let` block whose locals shadow the same three names, returned as a tuple and
     destructured at `@testitem` top level:
     `tripped, trip_pv_scale, outcomes = let tripped = false, trip_pv_scale = NaN, outcomes =
     String[]` ... (for-loop body unchanged) ... `(tripped, trip_pv_scale, outcomes) end`.
     Do not change anything inside the `for` loop's try/catch body (the `build_stochastic_welfare`
     call, the `push!(outcomes, ...)` lines, the WR-06 comment explaining the `occursin("SOCP
     relaxation INEXACT", ...)` gate-only check, or the `break`) — only the enclosing scope
     changes.
  3. In the `if !tripped ... end` self-diagnosis block immediately after the `let`, the leading
     comment currently says the resolved-versions info is there to check "hypothesis (a)" /
     "the WR-07 comment above" (the sandbox-resolution theory). Reword it to state plainly that
     this block is retained as a general-purpose self-diagnosis in case the gate genuinely fails
     to trip for an unrelated reason in the future, and that the historical failure's real root
     cause was the soft-scope bug fixed above — remove the reference to the retracted
     sandbox-resolution hypothesis. Do not change the `resolved = try ... catch ... end` logic or
     the final `@info` call itself.
  4. Immediately after `@test tripped`, add `@test trip_pv_scale == 2.0` — this asserts the trip
     happened at the specific measured value (not merely that some value tripped it), and uses
     `trip_pv_scale` rather than leaving it a dead binding.
- **verify:** `julia --project=. -e 'include("test/test_stochastic_welfare.jl")'` must run with
  no `LoadError`/parse error (the `@testitem` macro is a no-op outside TestItemRunner discovery,
  so this only proves the file still parses after the edit — the real functional proof is
  Task 2).
- **done:** `git diff test/test_stochastic_welfare.jl` shows only the comment-block replacement,
  the `let`-wrapping of the scan, the reworded `if !tripped` comment, and the new
  `@test trip_pv_scale == 2.0` line — no assertion loosened, no `outcomes`/self-diagnosis logic
  removed, no `src/` files touched.

### Task 2 — verify the gate now trips for the right reason, with the soft-scope warning gone

- **files:** none (verification only)
- **action:** From the repo root, run the D-06 item in isolation via the explicit-path
  TestItemRunner form confirmed to work in this repo (never `julia -e '@run_package_tests'` —
  cwd-based root resolution picks up sibling worktrees per the `local-project-toml-drift`
  project memory). Redirect combined stdout/stderr to a log file so it can be grepped:

  `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib" julia -e 'using TestItemRunner, TSODSO;
  TestItemRunner.run_tests(joinpath(pwd(), "test"); filter=ti->occursin("D-06 PF-04 gate runs
  per scenario", ti.name))' > /tmp/d06-gate-run.log 2>&1; echo "exit=$?"`

  Allow a generous timeout (this item solves several SOCP problems across 11 `pv_scale` values
  plus two solo solves — budget several minutes, not seconds).
- **verify:**
  1. `echo $?` (or the captured `exit=` line) is `0` and the log's TestItemRunner summary shows
     the item passed (e.g. `Pass` count equals `Total` count, no `Fail`/`Error` for this item).
  2. Since `@test trip_pv_scale == 2.0` was added in Task 1, a passing run of assertion #1
     already proves the trip occurred at exactly pv_scale=2.0 (a wrong trip value would fail
     that `@test` and thus the whole item) — no separate printed-value check is needed.
  3. `grep -c "Assignment to .* in soft scope is ambiguous" /tmp/d06-gate-run.log` must be `0`
     (filter out any header/comment noise with `grep -v '^#'` first if the raw count is
     nonzero for an unrelated reason) — the direct signal the scoping fix landed.
  Run the whole check at least twice in a row to rule out a solver-flake false pass (the item
  also depends on `build_stochastic_welfare`'s Clarabel solves, which is a separate, already-
  documented source of variance unrelated to this bug).
- **done:** at least two consecutive runs of the filtered item pass, and in every run the soft-
  scope warning grep returns `0`.

## Constraints

- Only `test/test_stochastic_welfare.jl` changes — no `src/` edits, no other test file edits.
- `@test tripped` (and the new `@test trip_pv_scale == 2.0`) must pass because the gate
  genuinely trips at pv_scale=2.0 — never via `@test_broken`, a loosened condition, or a
  hardcoded bypass.
- The per-scale `outcomes` recording and the `if !tripped` self-diagnosis `@info` block are
  preserved; only their explanatory comments change where they refer to the retracted
  sandbox-resolution hypothesis.
- The MEASURED comment block (pv_scale=1.0 exact, pv_scale=2.0 structurally inexact at
  maxratio≈9688, every larger scale inexact, `TRIP_PV_SCALE_MEASURED = 2.0`) is preserved
  verbatim — only the flake/sandbox-resolution diagnosis directly below it is rewritten.
- Verification uses direct `julia --project=. -e '...'` / explicit-path
  `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib"` TestItemRunner invocations, never a bare
  `julia -e '@run_package_tests'` and never a plain `Pkg.test()`-only check (too slow for this
  quick task and not needed to prove the scoping fix).

## must_haves

- **truths:** the D-06 item passes; the pass is because the PF-04 gate trips at pv_scale=2.0
  specifically (not a loosened assertion); the soft-scope ambiguity warnings at the old :166/:167
  lines no longer appear in the run log; the file's comments no longer claim the historical
  failure was caused by `Pkg.test()` sandbox package-resolution drift.
- **artifacts:** `test/test_stochastic_welfare.jl` (modified — `let`-wrapped scan state,
  corrected diagnosis comment, `@test trip_pv_scale == 2.0` added).
- **key_links:** the `let tripped = false, trip_pv_scale = NaN, outcomes = String[] ... end`
  block's returned tuple → the top-level `tripped, trip_pv_scale, outcomes = ...` destructuring
  → `@test tripped` / `@test trip_pv_scale == 2.0` (the assertions that must read the correct,
  now-properly-scoped values).
</content>

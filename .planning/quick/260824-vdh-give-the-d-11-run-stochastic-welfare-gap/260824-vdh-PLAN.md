---
quick_id: 260824-vdh
description: Give the D-11 run_stochastic welfare_gap golden literal a measured rtol, so it stops failing on Julia 1.12
date: 2026-08-24
mode: quick
---

# Quick Task 260824-vdh: Give the D-11 `run_stochastic` `welfare_gap` golden a measured `rtol`

## Why

`test/test_run_stochastic.jl:127` — `@test r1.oos.welfare_gap ≈ -0.02515629356082627` — fails on
CI's `Julia 1.12 - ubuntu-latest` job only (1.10 and 1.11 pass). Root cause is already fully
measured (CI run 32791955335; this session's own fresh local measurements), not investigated
here — this plan implements the fix.

`≈` with no explicit tolerance defaults to `rtol = sqrt(eps(Float64))` ≈ 1.49e-8. The compared
quantity is a Clarabel-converged iterate (a solver-tolerance-limited output), not an exact closed
form — 1.49e-8 is far tighter than the solver's own accuracy, and tighter than the value's actual
cross-Julia-version spread.

Measured, three fresh `run_stochastic(s)` calls per version, same `Scenario(name="t",
feeder=:ieee13, T=9, stoch_S=3, stoch_H_oos=5)`, bit-for-bit stable across all 3 calls within
each version:

| Julia   | `welfare_gap`            | stable across 3 calls |
|---------|---------------------------|------------------------|
| 1.10.11 | -0.02515629356082627      | yes                    |
| 1.11.9  | -0.02515629356082627      | yes                    |
| 1.12.7  | -0.025156313755701376     | yes                    |

Plus two *different* values observed from CI's own 1.12 runners on two different commits:
`-0.025156313755701376` (commit 304db38 — matches local 1.12.7 exactly) and
`-0.02515643735591766` (commit 3b73633).

Conclusions this plan encodes:
1. The committed golden `-0.02515629356082627` is **correct** — reproduced bit-for-bit on both
   Julia 1.10 and 1.11. It must **not** be re-pinned to a different number.
2. Within-environment determinism is intact (3/3 identical every time, every version) — the
   `@test r1.oos.welfare_gap == r2.oos.welfare_gap == r3.oos.welfare_gap` stability assertion
   above the golden is still testing a real, currently-holding property and must be kept exactly
   as-is, including its position textually before the golden (the D-11
   measurement-before-golden ordering the item is named for).
3. What varies is *across* environments (Julia minor version, and even across commits on the
   same 1.12 runner — a separate, already-diagnosed IEEE-13 numerical-knife-edge finding, noted
   here as context only, not this task's problem). Worst observed relative deviation from the
   golden: `|-0.02515643735591766 - (-0.02515629356082627)| / 0.02515629356082627 ≈ 5.74e-6`.
4. `rtol = 1e-4` clears that worst observed spread by ~17x while staying far below any
   physically meaningful change in a welfare gap (`rtol = 1e-5` would only give ~1.7x headroom —
   too tight to trust against a solver iterate).

## Scope

Only `test/test_run_stochastic.jl` changes. No `src/` changes — there is no product defect here,
only an over-tight test tolerance. Do not change the golden *value*. Do not run
`JuliaFormatter.format(...)` on this file (a separate task owns a repo-wide reformat under a
pinned JuliaFormatter version; this file is not among the drifted files and must keep its current
formatting). Do not touch the `== 0.9.0`-tuple stability assertion's `==` operator or its position
relative to the golden.

## Tasks

### Task 1 — add `rtol=1e-4` to the golden and record the cross-version measurement

- **files:** `test/test_run_stochastic.jl`
- **action:**
  1. In the `@testitem "run_stochastic: D-11 measurement-before-golden — repeated-run stability
     precedes the pinned literal"` body, leave line 115
     (`@test r1.oos.welfare_gap == r2.oos.welfare_gap == r3.oos.welfare_gap`) and everything
     above it completely untouched.
  2. Immediately below the existing `# RE-PINNED for the WR-09 fix (phase-22 review): ...`
     comment block (which documents the prior re-pin and stays, verbatim, as historical
     provenance), add a new comment paragraph recording the Julia-1.12 cross-version finding.
     State plainly, in the file's existing comment style:
     - The golden `-0.02515629356082627` is exact, bit-for-bit, on Julia 1.10.11 and 1.11.9
       (three fresh same-process `run_stochastic` calls each), but Julia 1.12 (measured 1.12.7)
       produces a nearby-but-different converged value, and CI has itself observed two distinct
       1.12 values across two different commits.
     - Include the three-row Julia-version measurement table and the two CI-observed 1.12
       values, exactly as given above in this plan's Why section.
     - State the worst observed relative deviation (`≈5.74e-6`) and that `rtol=1e-4` is chosen
       for ~17x headroom above it — tight enough to catch a real regression, loose enough to
       absorb solver/BLAS/Julia-minor-version iterate drift.
     - Note (one sentence, context only) that cross-commit variation on the same Julia version
       is a separately-tracked IEEE-13 numerical-knife-edge finding, not something this
       tolerance is meant to paper over structurally — it is meant to absorb solver-tolerance
       noise, which is what this quantity actually is.
  3. Change line 127 from `@test r1.oos.welfare_gap ≈ -0.02515629356082627` to
     `@test r1.oos.welfare_gap ≈ -0.02515629356082627 rtol = 1e-4`.
- **verify:** `git diff test/test_run_stochastic.jl` shows only the new comment paragraph and the
  `rtol = 1e-4` addition to the `@test ... ≈ ...` line — no other line in the file changed
  (confirms no incidental reformat).
- **done:** the file parses (see Task 2's run as functional proof) and the diff is scoped exactly
  as described.

### Task 2 — verify the item now passes on Julia 1.12 (the version that was failing)

- **files:** none (verification only)
- **action:** From the repo root, run the D-11 item in isolation on Julia 1.12.7 (`julia +1.12`,
  matching the version CI actually failed on and this session's own measurement) via the
  explicit-path TestItemRunner form confirmed working in this repo — never
  `julia -e '@run_package_tests'`, and never a plain `--project=.` TestItemRunner invocation
  (both known to break or mis-resolve here):

  `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib" julia +1.12 -e 'using TestItemRunner, TSODSO;
  TestItemRunner.run_tests(joinpath(pwd(), "test"); filter=ti->occursin("D-11
  measurement-before-golden", ti.name))' > /tmp/d11-golden-run.log 2>&1; echo "exit=$?"`

  This item makes three full `run_stochastic` calls (plus the earlier item in the same file
  makes a fourth) — budget a generous timeout (minutes, not seconds).

  Optionally, for cross-version confirmation only (not required to prove the fix, since 1.10/1.11
  already produce the exact golden and pass trivially under any `rtol ≥ 0`): repeat the same
  command with `julia +1.10` and `julia +1.11` inside the clean worktree at
  `/tmp/claude-1000/-home-pedro-programming-TSO-DSO/fb15e907-7729-4e8c-8dfc-10ace72db910/scratchpad/cleanwt`
  (the working tree's uncommitted `Project.toml`/`Manifest-v1.12.toml` drift breaks 1.11 loading
  under `--project=.`, though this explicit-`JULIA_LOAD_PATH` form does not use `--project=.` and
  may not hit that trap — verify against the clean worktree regardless if any doubt arises).
- **verify:**
  1. `echo $?` (or the captured `exit=` line) is `0` and `/tmp/d11-golden-run.log`'s
     TestItemRunner summary shows the item passed (`Pass` count equals `Total` count for the
     filtered item, no `Fail`/`Error`).
  2. `grep -v '^#' /tmp/d11-golden-run.log | grep -c "Test Failed"` is `0`.
- **done:** the D-11 item passes on Julia 1.12.7 in a single run of the command above.

## Constraints

- Only `test/test_run_stochastic.jl` changes — no `src/` edits, no other test file edits.
- The golden literal value `-0.02515629356082627` is unchanged — only an explicit `rtol=1e-4` is
  added to its comparison.
- The `@test r1.oos.welfare_gap == r2.oos.welfare_gap == r3.oos.welfare_gap` stability assertion
  keeps its exact `==` operator and its position textually before the golden — never reordered,
  never weakened, never given a tolerance.
- No `JuliaFormatter.format(...)` run on this file (separate task owns the repo-wide reformat
  under a pinned formatter version; this file is not among the drifted files).
- Verification uses the explicit-path `JULIA_LOAD_PATH="$PWD/test:$PWD:@stdlib"` TestItemRunner
  form, run on Julia 1.12 (`julia +1.12`) — never `julia -e '@run_package_tests'`.

## must_haves

- **truths:** the D-11 item passes on Julia 1.12.7 (the version CI observed failing); the golden
  literal value is unchanged; the stability assertion (`==`, before the golden) is unchanged; the
  file's comments record the measured cross-Julia-version table and the `rtol=1e-4` rationale.
- **artifacts:** `test/test_run_stochastic.jl` (modified — `rtol = 1e-4` added to the golden
  `@test`, new comment paragraph documenting the cross-version measurement).
- **key_links:** the three fresh `run_stochastic(s)` calls (`r1`, `r2`, `r3`) → the `==`
  stability assertion (unchanged, before the golden) → the golden `@test ... ≈ ... rtol = 1e-4`
  (now tolerant of the measured ~5.74e-6 worst-case cross-version deviation).
</content>

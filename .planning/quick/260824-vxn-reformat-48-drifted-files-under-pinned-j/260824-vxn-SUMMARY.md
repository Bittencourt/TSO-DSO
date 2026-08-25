---
quick_id: 260824-vxn
status: completed
subsystem: tooling/formatting
tags: [juliaformatter, ci, docstrings]
date: 2026-08-24
---

# Quick Task 260824-vxn: Reformat 48 drifted files under pinned JuliaFormatter 2.10.x — Summary

**One-liner:** Rewrapped one docstring span in `src/models/restriction_exactness.jl` to defuse a
JuliaFormatter 2.10.2 `format_docstrings` reflow bug (content-preserving, its own commit), then
reformatted all 48 drifted files under the pinned JuliaFormatter 2.10.2, verified the diff is
whitespace/layout-only across all 183 tracked `.jl` files, and landed it as one atomic style commit
— restoring format-clean state and greening the CI `format` job.

## History: this task ran twice

**First run (halted):** Task 1 reformatted 48 files cleanly, but Task 2's whitespace-only check
surfaced a genuine content loss in `src/models/restriction_exactness.jl` — JuliaFormatter's
`format_docstrings = true` markdown reflow silently deleted a full sentence from the module
docstring. The run correctly halted (no commit made) and documented the defect for later fixing.
See "Root-caused defect" below — this is preserved institutional knowledge from that run.

**Second run (this one, completed):** The blocker was root-caused and a fix verified independently
before re-invoking this task. Applied the fix as a preliminary Task 0, then executed the plan's
original Tasks 1-3 unchanged.

## Root-caused defect (why Task 0 exists)

The docstring in `src/models/restriction_exactness.jl` contained an inline code span that wrapped
across a line break where the **continuation line began with `|`**:

```
IDENTICAL quantity `assert_socp_exact!` (models/exactness.jl) gates, `gap[b,t] =
|value(l[b,t])·value(v[from_b,t]) − (value(P[b,t])² + value(Q[b,t])²)|` — compared against
```

JuliaFormatter 2.10.2's CommonMark-based docstring reflow parses that continuation line as a
markdown table row (a line starting with `|`) rather than as prose continuation, and silently
drops the preceding sentence during reflow. A second, structurally similar span a few lines later
in the same docstring survives untouched because its continuation begins with `(`, not `|`.

**Fix applied (Task 0):** rewrapped the two-line span into three lines so no continuation line
starts with `|`:

```
IDENTICAL quantity `assert_socp_exact!` (models/exactness.jl) gates,
`gap[b,t] = |value(l[b,t])·value(v[from_b,t]) − (value(P[b,t])² + value(Q[b,t])²)|` —
compared against
```

This is purely a line-break change — not one word of prose was added or removed. Applied via a
Python script with an `assert old in s` guard (fails loudly if the anchor text doesn't match
byte-for-byte, including `·`, `−` U+2212, `²`, `—`) rather than a hand-retyped edit, to guarantee no
character was silently mangled. Committed separately and *before* the reformat commit, so the
reformat commit remains pure formatter output with zero hand-edits mixed in.

## What happened (this run)

**Task 0 — docstring rewrap (new, not in original plan):**
- Applied the verified rewrap to `src/models/restriction_exactness.jl` via a guarded Python
  script; anchor matched, replacement applied, diff confirmed 3 lines changed (2 deletions, 3
  insertions).
- Committed alone: `a8f7659` — `docs(models/restriction_exactness): rewrap docstring span to
  avoid JuliaFormatter reflow bug`.

**Task 1 — reformat under pinned JuliaFormatter 2.10.2:**
- Scratch env at `<scratchpad>/jf210` confirmed at JuliaFormatter **2.10.2** (asserted
  `v"2.10.0" <= v < v"2.11.0"`).
- First `format(["src", "ext", "test", "docs"])` from the repo root returned `false` and rewrote
  exactly **48** files.
- Immediate second `format([...])` call returned `true` (idempotent — the exact CI `format` job
  predicate).
- `git diff --name-only -- src ext test docs | grep -c '\.jl$'` reported exactly `48`.

**Task 2 — content-loss gate (this run's decisive check):**
- Ran the ready-made normalized-diff checker
  (`check_content_loss.py`, whitespace- and comma-insensitive) against the Task 0 commit
  (`a8f7659`) across **all 183 tracked `.jl` files** under `src/ext/test/docs`.
- Result: `OK: no content change (whitespace/commas only)` — every one of the 48 changed files
  (including `restriction_exactness.jl`, now carrying the rewrapped docstring) came back
  content-identical modulo whitespace/commas. **No content loss this time** — the fix held.
- `julia --project=. -e 'using TSODSO'` precompiled cleanly (also re-verified after the commit
  landed).
- Manually inspected the previously-affected docstring lines post-format: full sentence intact,
  no truncation, no word/backtick gluing.

**Task 3 — commit:**
- Recomputed the file list immediately before staging (48 files, matched Task 1's count).
- Staged exactly those 48 paths individually (`xargs git add --` over the recomputed list) —
  `Project.toml`, `Manifest-v1.12.toml`, and `.planning/*` pre-existing dirty state were never
  touched or staged.
- Committed: `0debac9` — `style: reformat 48 files to pinned JuliaFormatter 2.10.2 (restore
  format-clean state)`. `git show --stat HEAD` confirms `48 files changed, 1936 insertions(+),
  1601 deletions(-)`, no `Project.toml`/`Manifest*.toml` in the file list.
- `git status --short -- src ext test docs` returned empty after the commit.

## must_haves status

- **truths:** SATISFIED. `format([...])` returns `true` on a fresh call from the repo root under
  JuliaFormatter 2.10.2. The diff against the pre-task state (`ff8f71f`, then `a8f7659` after the
  rewrap) is whitespace/layout-only across all 183 tracked `.jl` files — verified by normalized
  diff, not just `--ignore-all-space` (which cannot see multi-line reflow). `using TSODSO`
  precompiles cleanly.
- **artifacts:** Produced. Two new commits on top of pre-task `HEAD` (`ff8f71f`):
  `a8f7659` (docstring rewrap, 1 file) and `0debac9` (reformat, 48 files).
- **key_links:** Established. CI's `format` job predicate
  (`if !format(["src", "ext", "test", "docs"]; verbose = true)`) now evaluates `true` at HEAD —
  the same scratch-env-pinned 2.10.2 call, from the repo root (so `.JuliaFormatter.toml` is
  discovered), is the exact call CI makes.

## Commits

- `a8f7659` — `docs(models/restriction_exactness): rewrap docstring span to avoid JuliaFormatter
  reflow bug` (1 file changed, 3 insertions(+), 2 deletions(-))
- `0debac9` — `style: reformat 48 files to pinned JuliaFormatter 2.10.2 (restore format-clean
  state)` (48 files changed, 1936 insertions(+), 1601 deletions(-))

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug, carried over from previous halted run] Added Task 0 (docstring rewrap) ahead
of the plan's original Task 1**
- **Found during:** the previous run of this same quick task (260824-vxn), which correctly halted
  rather than commit a content-losing reformat.
- **Issue:** JuliaFormatter 2.10.2's `format_docstrings` reflow silently deleted a sentence from
  `src/models/restriction_exactness.jl`'s docstring due to a continuation line starting with `|`
  being misparsed as a markdown table row.
- **Fix:** Rewrapped the affected span (line breaks only, zero prose change) via a guarded Python
  script, committed separately and before the reformat commit.
- **Files modified:** `src/models/restriction_exactness.jl`.
- **Commit:** `a8f7659`.

No other deviations. Tasks 1-3 executed exactly as the original plan specified.

## Self-Check: PASSED

- `git log --oneline -3` shows `0debac9` and `a8f7659` on top of `ff8f71f`, confirming both
  commits exist.
- `git show --stat HEAD | tail -1` reads `48 files changed, 1936 insertions(+), 1601 deletions(-)`
  — matches the reported reformat commit.
- `git status --short -- src ext test docs` returns empty — no unstaged/untracked changes remain
  under the four reformatted directories.
- `git status --short` (full) shows only the pre-existing, pre-task dirty entries
  (`.planning/STATE.md`, `Manifest-v1.12.toml`, `Project.toml`, untracked `.planning/quick/*`,
  `.planning/debug/`, `.planning/tmp/`) — none of which this task modified or staged.
- `julia --project=. -e 'using TSODSO'` exits 0 (precompiles cleanly) both immediately after
  formatting and again after the commit landed.

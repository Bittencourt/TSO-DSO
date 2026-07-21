---
phase: 09-documentation-regression-acceptance-gate
plan: 05
subsystem: infra
tags: [github-actions, ci, documenter, literate, cairomakie, deploydocs]

# Dependency graph
requires:
  - phase: 09-04
    provides: "Full six-rung docs/make.jl build (all Literate pages wired, checkdocs=:exports, CI-gated deploydocs, re-resolved docs/Manifest.toml with CairoMakie hard dep)"
provides:
  - "Dedicated `docs` job in .github/workflows/CI.yml that builds Documenter+Literate site on every push/PR"
  - "Explicit docs-env instantiate step (julia-buildpkg@v1, project: docs) so CairoMakie is actually installed in CI before makedocs runs"
  - "Resolved deploydocs repo-slug checkpoint: placeholder kept intentionally, documented as a pre-deploy TODO"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: ["Dedicated single-Julia-version CI job for Julia-version-invariant work (mirrors `format`), separate from the 1.10/1.11/1.12 test matrix"]

key-files:
  created: []
  modified:
    - .github/workflows/CI.yml
    - docs/make.jl

key-decisions:
  - "docs CI job pinned to a single Julia version (1.11, matching `format`), not added as a matrix leg — docs content is Julia-version-invariant (RESEARCH Pitfall 6)"
  - "Explicit julia-buildpkg@v1 step with project: docs added BEFORE the build step, since `format` has no instantiate step but `docs` needs docs/Manifest.toml's CairoMakie installed to avoid a silent no-op figure guard in CI"
  - "deploydocs repo slug placeholder (github.com/PLACEHOLDER-ORG/PLACEHOLDER-REPO.git) kept as-is per researcher decision on the Task 2 human-verify checkpoint — no git remote configured in this checkout to discover the real slug; comment updated to document this as a resolved decision with an explicit pre-deploy TODO"

patterns-established:
  - "Julia-version-invariant CI jobs (docs, format) get a single pinned Julia version; only correctness-sensitive jobs (test) run the full 1.10/1.11/1.12 matrix"

requirements-completed: [EXP-03]

# Metrics
duration: 15min
completed: 2026-07-20
---

# Phase 09 Plan 05: Docs CI Gate Summary

**Added a dedicated `docs` GitHub Actions job (single pinned Julia version, explicit docs-env instantiate via julia-buildpkg@v1) that builds the full Documenter+Literate site with CairoMakie figures on every push/PR, and resolved the deploydocs repo-slug checkpoint by keeping the placeholder per researcher decision.**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-07-20T21:45:00Z (approx)
- **Completed:** 2026-07-20T22:00:23Z
- **Tasks:** 2 (1 auto, 1 checkpoint resolved per pre-supplied user decision)
- **Files modified:** 2

## Accomplishments
- New `docs:` job in `.github/workflows/CI.yml`, structurally mirroring the existing `format` job (single `ubuntu-latest` runner, single pinned Julia `1.11`, no version matrix)
- Explicit `julia-actions/julia-buildpkg@v1` step targeting `project: docs` runs BEFORE `julia --project=docs docs/make.jl`, so the re-resolved `docs/Manifest.toml` (which now hard-depends on CairoMakie per plan 09-04) is actually instantiated in the CI runner — without this step the CairoMakie figure guard (`Base.find_package("CairoMakie")`) would silently no-op in CI
- `Build docs` step runs with `CI: 'true'` in its environment so `docs/make.jl`'s existing `get(ENV, "CI", nothing) == "true"` gates (prettyurls, deploydocs) activate correctly under Actions
- Confirmed via diff that the pre-existing `test:` and `format:` jobs are byte-identical to before this edit — only a new job was added
- Task 2 (deploydocs repo-slug human-verify checkpoint) resolved per user's pre-supplied decision: placeholder kept as-is; `docs/make.jl`'s comment above the `deploydocs` call rewritten to document this as a settled decision (not an open question) with an explicit `TODO(deploydocs repo slug)` marker for whoever performs the first real gh-pages deploy

## Task Commits

Each task was committed atomically:

1. **Task 1: Add the docs CI job (with explicit docs-env instantiate)** - `4f7c404` (feat)
2. **Task 2: Resolve deploydocs repo-slug checkpoint (keep placeholder, per user decision)** - `f53a224` (docs)

**Plan metadata:** (this commit, following SUMMARY + STATE update)

## Files Created/Modified
- `.github/workflows/CI.yml` - Added dedicated `docs` job (checkout -> setup-julia@1.11 -> cache -> julia-buildpkg@v1[project: docs] -> `julia --project=docs docs/make.jl` with `CI: 'true'`)
- `docs/make.jl` - Rewrote the comment above the CI-gated `deploydocs` call to document the repo-slug placeholder as an intentionally-kept, researcher-confirmed decision (not an open TODO awaiting confirmation) with a clear pre-deploy action item

## Decisions Made
- Kept the `deploydocs` repo slug as `github.com/PLACEHOLDER-ORG/PLACEHOLDER-REPO.git` — this checkout has no git remote configured, so the real org/repo slug is not locally discoverable. The user explicitly decided (via the checkpoint resolution instructions for this execution) to keep the placeholder rather than guess or invent a slug. The call remains gated on `CI == "true"`, so it stays inert until this workflow actually runs in GitHub Actions; the comment now flags it as a hard pre-deploy TODO (replace slug + confirm `DOCUMENTER_KEY`/`GITHUB_TOKEN` wiring) rather than as an unresolved question.
- Did not add a version matrix to the `docs` job — docs content (Documenter/Literate rendering) is Julia-version-invariant, and RESEARCH Pitfall 6 explicitly warns against burning 3x CI minutes rebuilding docs identically across 1.10/1.11/1.12.

## Deviations from Plan

None - plan executed exactly as written. Task 2's checkpoint was pre-resolved by the user (keep placeholder) per explicit instructions supplied to this execution, so no further human interaction was required to complete the plan; this resolution is recorded here rather than left pending.

## Issues Encountered
None.

## User Setup Required

None for this plan directly. Carried-forward action items (from the now-resolved Task 2 checkpoint, for whenever the project is ready to deploy docs for real):
1. Replace `docs/make.jl`'s `deploydocs(; repo = "github.com/PLACEHOLDER-ORG/PLACEHOLDER-REPO.git")` placeholder with the real `github.com/ORG/REPO` slug.
2. Push a branch (or open a PR) and confirm the new `docs` job in `.github/workflows/CI.yml` runs green in GitHub Actions.
3. If GitHub Pages deployment is desired: confirm `DOCUMENTER_KEY` (or `permissions: contents: write` + `GITHUB_TOKEN`) is configured in the repo's Actions secrets before merging to the branch `deploydocs` triggers from.
4. Optional/advisory (carried over from Phase 7): in a non-headless environment with CairoMakie installed, eyeball the ADMM convergence-plot figure aesthetics (`docs/literate/admm.jl` output).

## Next Phase Readiness

This closes the last EXP-03 deliverable and Phase 09 (documentation-regression-acceptance-gate). The docs build is now CI-enforced (single dedicated job, docs-env correctly instantiated) as a permanent regression gate for the framework's documentation. No blockers for milestone close; the deploydocs repo slug and GitHub Pages secrets remain a deliberately-deferred, non-blocking action item for whoever first deploys docs from CI.

---
*Phase: 09-documentation-regression-acceptance-gate*
*Completed: 2026-07-20*

## Self-Check: PASSED

- FOUND: .github/workflows/CI.yml
- FOUND: docs/make.jl
- FOUND: .planning/phases/09-documentation-regression-acceptance-gate/09-05-SUMMARY.md
- FOUND: 4f7c404 (Task 1 commit)
- FOUND: f53a224 (Task 2 commit)

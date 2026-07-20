---
phase: 09-documentation-regression-acceptance-gate
reviewed: 2026-07-20T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - test/test_acceptance.jl
  - test/test_pricing_fit.jl
  - docs/make.jl
  - docs/literate/lindistflow.jl
  - docs/literate/convex_branch_flow.jl
  - docs/literate/prosumer_welfare.jl
  - docs/literate/pricing_dlmp.jl
  - docs/literate/admm.jl
  - .github/workflows/CI.yml
findings:
  critical: 2
  warning: 5
  info: 1
  total: 8
status: issues_found
---

# Phase 9: Code Review Report

**Reviewed:** 2026-07-20T00:00:00Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

I read all nine files, cross-referenced them against the actual `src/` APIs they call
(`solve_admm`, `extract_dlmp`, `decompose_dlmp`, `welfare_accounting`, `fit_baseline`,
`generate_profiles`, device constructors), and **actually executed** the Julia code rather
than trusting the code comments:

- Ran every `docs/literate/*.jl` page directly (`julia --project=. docs/literate/<page>.jl`)
  — all six execute successfully.
- Ran `julia --project=docs docs/make.jl` end-to-end (twice, to double-check the exit code)
  — **the build exits 0**, but emits 104 "docstrings not included in the manual" warnings and
  ~15 "Cannot resolve `@ref`" warnings hitting essentially every symbol referenced by every
  generated literate page (`ConvexBranchFlow`, `solve_welfare`, `LinDistFlow`, `Thermostatic`,
  `Deferrable`, `PVBattery`, `Aggregator`, `extract_dlmp`, `decompose_dlmp`,
  `welfare_accounting`, `solve_admm`, `assert_socp_exact!`, ...). This directly contradicts the
  file's own comment claiming the `checkdocs = :exports` change will "fail the build on
  undocumented PUBLIC-API symbols" — see CR-01.
- Reconstructed and ran the IEEE-13 acceptance scenario standalone (bypassing the
  `@testitem`/`TestItemRunner` sandbox) to confirm the pinned golden reproduces
  (`res.cost == -4823.1598620624`, `ctx.meta[:socp_maxgap] = 3.25e-8`,
  `admm.exact_maxgap = 9.17e-10`, `admm.iters = 42`) and that the reused tolerances are not
  currently failing. In the process I found that `admm.exact_maxgap` is computed but never
  asserted for the IEEE-13 acceptance item — see CR-02.
- Reconstructed and ran the FIT regression golden standalone; `res.ratio` reproduces
  `0.6428101637491034` bit-for-bit against the pinned `FIT_RATIO_GOLDEN`. That golden is
  correctly pinned and will not silently skip.

The core numerics (golden values, ADMM≈centralized welfare, DADP cross-validation) are sound
and currently pass. The two BLOCKER-tier findings are about the acceptance/doc **gates not
actually gating what they claim to gate** — both are provable, not speculative — plus several
WARNING-tier gaps in test-selection documentation, tolerance semantics, and CI coverage.

## Critical Issues

### CR-01: `checkdocs = :exports` is neutralized by `warnonly`, so the docs build never fails on undocumented/broken API references

**File:** `docs/make.jl:49-55`
**Issue:** The comment explicitly states the intent: "Tightened from `:none` (Phase 1) to
`:exports` (Phase 9 EXP-03): fail the build on undocumented PUBLIC-API (exported) symbols."
But the very next lines put `:missing_docs` (and `:cross_references`) into `warnonly`:

```julia
checkdocs = :exports,
warnonly = [:missing_docs, :cross_references],
```

`warnonly` demotes exactly the checks that `checkdocs` is supposed to enforce from hard errors
to warnings — so `checkdocs = :exports` is a complete no-op for build-failure purposes. I
verified this empirically by running `julia --project=docs docs/make.jl` to completion:

- **104 exported/public docstrings are not included in the manual** (`Warning: 104 docstrings
  not included in the manual`), including exactly the symbols the six new literate pages exist
  to document: `ConvexBranchFlow`, `LinDistFlow`, `solve_welfare`, `solve_admm`, `extract_dlmp`,
  `decompose_dlmp`, `welfare_accounting`, `fit_baseline`, `Aggregator`, `Thermostatic`,
  `Deferrable`, `PVBattery`, `Bus`, `Branch`, `Feeder`, `assert_socp_exact!`, etc.
- Every single `[`Xxx`](@ref)` cross-reference in every generated page fails to resolve
  ("Cannot resolve `@ref` for ... No docstring found in doc for binding `TSODSO.Xxx`"), for
  ALL SIX generated model pages (`toy_dc`, `lindistflow`, `convex_branch_flow`,
  `prosumer_welfare`, `pricing_dlmp`, `admm`).
- The process still exits `0`.

So this "EXP-03 tightening" cannot ever turn CI red for a missing docstring or a broken `@ref`
on an exported symbol — the exact regression this phase was supposed to introduce a gate for.
Any future contributor who adds an exported function with no docstring, or renames a
documented function without updating a literate page's `@ref`, gets a silent green build.

**Fix:** Either (a) actually write the missing docstrings for the currently-undocumented
exports (or add `@docs`/`@autodocs` blocks so they're "included in the manual") and drop
`:missing_docs`/`:cross_references` from `warnonly` so the check is real, or (b) if the
existing 104-symbol gap is intentionally deferred to a later plan, do not claim in the comment
that this change "fails the build" — state plainly that it is warn-only for now, and track the
104-symbol backlog explicitly (e.g. a `# TODO(docs-backlog)` with a tracking issue) so the
"tightened" framing isn't misleading to future maintainers/reviewers.

### CR-02: The IEEE-13 acceptance item never asserts ADMM's PF-04 exactness certificate — the acceptance gate's "exact relaxation for BOTH cases" claim is only checked on the centralized path for IEEE-13

**File:** `test/test_acceptance.jl:20-72`
**Issue:** The file header claims this is "the single consolidated end-to-end proof that BOTH
headline cases ... reproduce exact SOC relaxation, recovered DADP, and ADMM ≈ centralized
welfare." For the IEEE-123 item (lines 74-109) this is true — it asserts
`res.exact_maxgap < 1e-3` on the ADMM-converged DSO-OPT (line 107). For the IEEE-13 item,
however, only the **centralized** solve's exactness is asserted:

```julia
@test ctx.meta[:socp_maxgap] < 1e-5                          # PF-04 exact relaxation (centralized only)
...
admm = solve_admm(feeder, ConvexBranchFlow(), aggs; T = 24, λ₀ = λ₀, ρ = 100.0, allow_export = true)
...
@test isapprox(admm.welfare, res.cost; rtol = 1e-4)          # ADMM ≈ centralized welfare
@test isapprox(admm.λ, dlmp_c; atol = 1e-2, rtol = 1e-3)     # recovered DADP match
```

`solve_admm` returns `admm.exact_maxgap` (the PF-04 gate on the ADMM-converged DSO-OPT,
`src/admm/solve_admm.jl:104,378`), but the IEEE-13 acceptance item never reads or asserts it.
I confirmed by running the scenario standalone that `admm.exact_maxgap = 9.17e-10` today (so
the check would currently pass) — but nothing in this file would catch a future regression
that made the ADMM-side relaxation inexact for IEEE-13 while welfare/DADP still happened to
land within the (fairly loose — see WR-02) cross-validation tolerance. This is precisely the
"exact relaxation... for BOTH headline cases" guarantee the file's own header advertises, and
it silently doesn't hold for the ADMM path on IEEE-13.

**Fix:** Add the missing certificate check to the IEEE-13 item, symmetric with IEEE-123:

```julia
@test admm.exact_maxgap < 1e-3   # PF-04 exact on the ADMM-converged DSO-OPT (IEEE-13)
```

(Also consider adding `@test admm.iters < 200` for symmetry with `test_admm.jl`'s existing
IEEE-13 crossval item and the IEEE-123 acceptance item — currently omitted here too; low
severity since `solve_admm` fails loudly on non-convergence regardless, but the omission means
this file doesn't itself document/verify the iteration budget the way its sibling does.)

## Warnings

### WR-01: DADP recovery check is a matrix (Frobenius-norm) `isapprox`, not elementwise — a single entry can exceed the stated `atol` and still "pass"

**File:** `test/test_acceptance.jl:63`, `test/test_acceptance.jl:108`
**Issue:** `@test isapprox(admm.λ, dlmp_c; atol = 1e-2, rtol = 1e-3)` compares two
`(n_load_nodes, T)` matrices. Julia's `isapprox` for `AbstractArray` args is norm-based
(`norm(x - y) <= max(atol, rtol * max(norm(x), norm(y)))`), not elementwise. I verified this
empirically on the live IEEE-13 acceptance scenario: `maximum(abs.(admm.λ .- dlmp_c))` is
`0.0166` — i.e. **larger** than the nominal `atol = 1e-2` — yet `isapprox(admm.λ, dlmp_c; atol
= 1e-2, rtol = 1e-3)` still evaluates to `true`, because the aggregate norm over all 240
(bus, hour) entries is dominated by `rtol * norm(dlmp_c)`. So the tolerance actually enforced
is much looser, per-entry, than `atol = 1e-2` suggests to a reader — a single bus/hour DADP
could drift further than that and the "recovered DADP match" assertion would still pass. This
convention is inherited from `test_admm.jl`/`test_ieee123_admm.jl` (not introduced by this
phase), but since this file is billed as the authoritative acceptance gate, it's worth
tightening or at minimum documenting that the check is an aggregate, not a per-node/hour, bound.
**Fix:** If a true per-entry guarantee is wanted, assert
`maximum(abs.(admm.λ .- dlmp_c)) < atol_per_entry` explicitly instead of (or in addition to)
the whole-matrix `isapprox`.

### WR-02: Comments claim a tag/name-based `Pkg.test(; test_args=...)` selection mechanism that does not exist in this repo's `test/runtests.jl`

**File:** `test/test_acceptance.jl:11-12`, `test/test_pricing_fit.jl:6`
**Issue:** `test_acceptance.jl` states: "Item names are tagged `:acceptance` so
`Pkg.test(; test_args=["acceptance"])` selects exactly these two testitems." `test_pricing_fit.jl`
similarly states: "Every `@testitem` name contains 'fit' so `occursin("fit", ti.name)` selects
it." I checked `test/runtests.jl`:

```julia
using TestItemRunner
@run_package_tests
```

`TestItemRunner.@run_package_tests` only filters test items if a `filter = ...` keyword is
passed to the macro **at this call site** (verified against the installed
`TestItemRunner.jl` source: `run_tests(path; filter=nothing, ...)`, and the macro only forwards
`filter`/`verbose` kwargs literally written in the `@run_package_tests` invocation). It does
**not** read `ARGS`/`test_args` at runtime. Since `runtests.jl` passes no `filter` argument,
`Pkg.test(; test_args=["acceptance"])` runs the **entire** test suite — the described
"selects exactly these two testitems" / "selects it" behavior does not exist today. This is
not a correctness bug (nothing is skipped — the whole suite, including these items, always
runs), but it's a misleading claim in the file's own documentation that could send a future
contributor down a dead end trying to get a fast, targeted acceptance-only run.
**Fix:** Either wire an actual `ARGS`-driven filter into `test/runtests.jl` (e.g.
`@run_package_tests filter = ti -> isempty(ARGS) || any(a -> a in string.(ti.tags) || occursin(a, ti.name), ARGS)`)
so the documented invocation genuinely works, or correct the comments to state that tags are
currently just organizational/documentation metadata, not an active filter.

### WR-03: Acceptance file drops the hard per-node/per-hour DADP goldens and keeps only a tautological "broken" cross-check for `v₉[16]`

**File:** `test/test_acceptance.jl:32-33,65-71`
**Issue:** `test_ieee13.jl`'s ground golden test hard-asserts four pinned goldens
(`GOLDEN_V9_16`, `GOLDEN_WELFARE`, `GOLDEN_DADP16`, `GOLDEN_SUM_DADP`); the acceptance file
keeps only `GOLDEN_WELFARE`. In place of the hard `GOLDEN_V9_16` check it keeps only the
non-failing thesis cross-check:

```julia
gap = abs(v9_16 - THESIS_V9_16)
@test gap < 1e-2 broken = (gap >= 1e-2)
```

This construction is tautological by design: `broken` is set to exactly the negation of the
tested condition, so this `@test` can **never fail** regardless of `gap` — it always reports
either Pass (when `gap < 1e-2`) or Broken (when it isn't), never Fail. This mirrors an
existing, well-commented idiom already present in `test_ieee13.jl` (so it isn't new to this
phase), and the intent (a non-failing informational cross-check against a figure-bound thesis
value) is legitimate and well documented — but propagating a tautological assertion into the
file explicitly billed as "the single consolidated end-to-end proof" without also keeping a
hard, tight, single-value voltage regression check (as `test_ieee13.jl` does via
`GOLDEN_V9_16`) is a real reduction in what this specific file certifies. A regression that
moves `v₉[16]` (e.g. a voltage-drop sign error) without moving total welfare outside `rtol =
1e-4` would not be caught by this file's assertions.
**Fix:** Either restore a hard `@test isapprox(v9_16, GOLDEN_V9_16; atol = 1e-4)` alongside the
non-failing thesis cross-check, or explicitly note in the header that per-node golden coverage
is intentionally left to `test_ieee13.jl` and this file only certifies welfare + ADMM
cross-validation (a narrower, but honestly stated, scope).

### WR-04: JuliaFormatter CI job does not check `docs/` — the new literate pages and `docs/make.jl` are unformatted-checked

**File:** `.github/workflows/CI.yml:65`
**Issue:** The `format` job runs `format(["src", "ext", "test"]; verbose = true)`. Phase 9
adds `docs/make.jl` and five new files under `docs/literate/`, none of which fall under any of
those three paths, so they are never subject to the `.JuliaFormatter.toml`-pinned style check
this project otherwise enforces in CI.
**Fix:** Add `"docs"` to the `format(...)` call's path list (Literate source files are plain
Julia and format fine under JuliaFormatter).

### WR-05: `deploydocs` runs unconditionally whenever `CI == "true"`, pointed at a placeholder repo slug, with no `DOCUMENTER_KEY`/`GITHUB_TOKEN` wired in the docs CI job

**File:** `docs/make.jl:60-68`, `.github/workflows/CI.yml:70-91`
**Issue:** This is already self-flagged with a `TODO(deploydocs repo slug)` comment
acknowledging the placeholder must be replaced "before the first real gh-pages deploy," so I'm
not raising it as a new defect — but flagging it as a WARNING for completeness since the
`docs` CI job as currently written has no `GITHUB_TOKEN`/`DOCUMENTER_KEY` env var at all. In
real GitHub Actions CI (`CI=true` will be set), `deploydocs` will execute this branch; because
the placeholder org/repo will not match the actual `GITHUB_REPOSITORY`, Documenter's
repo-slug-mismatch check should make it skip pushing rather than error — but this has not been
exercised, and the missing auth secret means even a corrected slug would not be able to deploy
yet. Tracked already by the author's TODO; call out here so it isn't lost.
**Fix:** Before enabling real deploys: replace the placeholder slug, add
`DOCUMENTER_KEY` (or configure the `GITHUB_TOKEN`-based deploy key flow) as a job env var in
`.github/workflows/CI.yml`'s `docs` job, and do a dry run on a real fork to confirm the
skip-vs-deploy branch behaves as expected.

## Info

### IN-01: Manual verification results (for the record)

Confirmed via direct execution (not part of any defect, recorded for traceability):
- All six `docs/literate/*.jl` pages execute standalone without error.
- `julia --project=docs docs/make.jl` completes with exit code 0 (see CR-01 for what that
  masks).
- The IEEE-13 acceptance scenario, reconstructed and run standalone, reproduces
  `GOLDEN_WELFARE = -4823.1598620624` exactly, `ctx.meta[:socp_maxgap] = 3.25e-8`,
  `admm.exact_maxgap = 9.17e-10`, `admm.iters = 42`, and the DADP cross-check passes (see WR-01
  for the caveat on what "passes" means here).
- `test/test_pricing_fit.jl`'s `FIT_RATIO_GOLDEN = 0.6428101637491034` reproduces bit-for-bit
  when the fixture is reconstructed and re-run standalone — this golden is correctly pinned and
  will not silently skip or drift.

---

_Reviewed: 2026-07-20T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

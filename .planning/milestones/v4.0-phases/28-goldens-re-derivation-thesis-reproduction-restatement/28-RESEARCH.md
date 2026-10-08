# Phase 28: Goldens Re-Derivation & Thesis Reproduction Restatement - Research

**Researched:** 2026-09-29
**Domain:** cross-phase audit + reproducible-research restatement (Julia/JuMP scientific computing, Documenter/Literate docs, DrWatson-style scripts) — no new modeling
**Confidence:** HIGH (the phase is almost entirely archaeology/verification of code and artifacts that already exist; the only genuine unknowns are two measurement questions, both scoped as tasks below)

## Summary

Phase 28 is a **capstone verification/restatement phase**, not a modeling phase. Phases 26–27
already did all the correctness work and already re-derived every test-suite golden they moved
(both phases closed with full `26-GOLDEN-AUDIT.md`/`27-GOLDEN-AUDIT.md` tables and GREEN suites,
0 fail / 0 error). What Phase 28 must do is: (1) **consolidate** those two audits into one
cross-phase document and add a **mechanical script** that proves no future move can slip through
silently; (2) **re-run and restate** the thesis-reproduction and SOCP-inexactness findings that
are narrated in `docs/literate/*.jl` prose, `docs/writeups/`, and `.planning/PROJECT.md` — all of
which currently describe **pre-Phase-26 behavior** and are now stale in specific, locatable ways;
and (3) **regenerate** the PNG/PDF figure artifacts under `results/` that were rendered before the
Phase 26/27 code changes landed.

The central technical finding of this research: three `docs/literate/*.jl` pages
(`thesis_reproduction_ieee123.jl`, `socp_applicability.jl`, `restricted_branch_flow.jl`,
`ac_oracle.jl`) call `ConvexBranchFlow()` **bare** (no `thesis_literal` kwarg) inside **live
`@example` blocks that Documenter actually executes at docs-build time**. Since Phase 26 flipped
the *default* meaning of that bare call (from the old thesis-literal lower-band restriction to the
Gan–Low upper-band restriction), these pages will, on the next docs build, silently compute and
render **different numbers and possibly different exact/inexact classifications** than what their
own surrounding prose still asserts. One of them (`thesis_reproduction_ieee123.jl`) is at
genuine risk of the docs build **throwing outright**, because the identical population point it
solves live was measured in Phase 27 (F-27-05-2) to trip `assert_socp_exact!` at Clarabel's
default tolerance — the committed test golden already carries a `tol_gap_abs=tol_gap_rel=3e-9`
override to survive this, but the literate page does not.

**Primary recommendation:** treat this phase as four independent, mostly non-overlapping work
items (golden-audit script; REPRO-01 restatement + figure regen; SOCP-inexactness dual-mode
re-verification + figure regen; MPC/DLMP docs restatement), each touching a disjoint file set,
followed by one sequential phase-closing gate that runs the full docs build and full test suite —
mirroring the exact wave structure Phases 26 and 27 already used and that this project's own
memory (`background-suite-orphan-race`, `gsd-plan-verify-testitemrunner-trap`) documents as
required practice on this repo.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Cross-phase golden-move audit (parse git diff, flag unexplained numeric moves) | Tooling / scripts (new, language: Claude's discretion) | `.planning/` docs (consolidated report) | Pure diff/text analysis, no Julia model involved |
| Thesis-reproduction re-run (REPRO-01, sign flip + magnitude gap) | `src/pricing/fit.jl` + `src/models/welfare_solve.jl` (already correct, unmodified) | `docs/literate/thesis_reproduction_*.jl`, `scripts/thesis_case123_repro.jl`, `scripts/repro_stability_check.jl` (consumers, need updating) | Domain layer already fixed in Phase 27; restatement work is entirely in the docs/scripts consumer layer |
| SOCP-inexactness dual-mode re-verification (EXACT-04 under both defaults) | `docs/literate/{ac_oracle,restricted_branch_flow,socp_applicability}.jl` + `test/test_ac_oracle.jl` (consumers) | `src/powerflow/ConvexBranchFlow.jl` (read-only reference, unmodified) | No production code changes — this is a documentation/test-comment accuracy question, the underlying model is already correct per Phase 26 |
| MPC/DLMP semantic restatement | `docs/literate/mpc_rolling_horizon.jl`, `scripts/demo_mpc_plots.jl` | `src/experiments/mpc_loop.jl` (already correct, unmodified) | Same pattern: fixed in Phase 27, docs/scripts consumer layer never updated |
| Figure/artifact regeneration | `results/thesis_caseA/`, `results/thesis_case123_repro/`, `results/socp_applicability/`, `results/demo_mpc_plots/`, `results/repro_stability_check/` | `scripts/*.jl` producers | Pure re-run of existing, unmodified scripts against the corrected `src/` |
| Full-suite + docs-build certification gate | CI-equivalent local verification (`Pkg.test()`, `julia --project=docs docs/make.jl`) | — | Phase-closing gate, sequenced last, mirrors Phase 26/27's own Plan-08/Plan-06 pattern |

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Cross-phase golden audit (SC-1)**
- A committed audit script parses `git diff 5939799..HEAD -- test/` (5939799 = pre-Phase-26 base)
  for every changed numeric literal and flags any lacking an adjacent old→new + cause comment; its
  output plus the 26-/27-GOLDEN-AUDIT tables are merged into one `28-CROSS-PHASE-AUDIT.md`.
- Also audit pinned numbers cited in `docs/literate/*.jl` prose and `.planning/PROJECT.md` key
  findings that reference now-moved values.
- Any unexplained move is explained in-phase (comment + audit row) — never silently accepted.

**Thesis reproduction re-run (SC-2)**
- Re-run the FULL REPRO-01 pipeline (`docs/literate/thesis_reproduction_ieee123.jl`, `scripts/`
  repro/stability tooling): sign flip + welfare-magnitude gap, the 5-point stability sweep, and
  regenerate `results/thesis_caseA` figures + `docs/writeups` artifacts that depend on it.
- The repro-point SOCP-exactness drift found in 27-05: MEASURE first — precision artifact →
  measured tol_gap; genuinely inexact → restate as uncertified at that point. Never hide.
- Restatement framing: old vs new side by side with the named cause of each change (FIX-0x /
  PM-0x / 27 execution amendments); a changed result is reported as a finding, not a regression.

**SOCP-inexactness + deferred restatements (SC-3)**
- Re-verify EXACT-04 (and the v2.1/v3.0 inexactness findings) under BOTH the default Gan–Low copy
  (expected exact) and `ConvexBranchFlow(; thesis_literal=true)` (expected inexact); restate as a
  property of the thesis-literal copy. Update `socp_applicability.jl`, `restricted_branch_flow.jl`,
  `ac_oracle.jl` literate pages and PROJECT.md.
- Also restate the Phase-27 deferrals: MPC truth-settled realized_welfare/regret semantics
  (`docs/literate/mpc_rolling_horizon.jl`, `scripts/demo_mpc_plots.jl`) and DLMP `cone`/`drop`
  naming across docs.
- Format: edit pages in place with a "Restated in v4.0 (Phase 28)" callout + one summary page
  listing old→new for every headline finding (and link it from PROJECT.md).
- Run the Documenter/Literate docs build so every edited literate page actually executes.

**Process (carried from 26/27)**
- Full suite after each wave with NO agent worktrees under `.claude/worktrees/` present during the
  run; ≤3 concurrent Julia executors; executors never edit STATE/ROADMAP; findings →
  `28-FINDINGS.md`.
- Real executable `julia --project=.` verify scripts only.

### Claude's Discretion
- Audit-script implementation language/approach; summary page name/location; figure regeneration
  tooling.

### Deferred Ideas (OUT OF SCOPE)
- Removal of deprecated DLMP aliases — Phase 36.
- App. C η<1 complementarity treatment — unscheduled backlog.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| FIX-11 | Each correctness phase re-derives the goldens it moves, in the same phase and with an explanation, so the suite stays green. After FIX-01..10 a cross-phase golden audit confirms none was silently re-pinned, and the v2.1 thesis reproduction (DSO-surplus sign flip, welfare-magnitude gap) and the v2.1/v3.0 SOCP-inexactness findings are re-run and restated in the literate docs and PROJECT.md, including any that changed. | Sections "Cross-Phase Golden Audit Design", "REPRO-01 Pipeline Inventory", "SOCP-Inexactness Dual-Notion Finding", "MPC/DLMP Restatement Inventory", "Pattern Map" below give the concrete file-level inventory and measurement plan needed to satisfy all three of FIX-11's sub-clauses (audit, repro re-run, inexactness re-verification). |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- Julia + JuMP; solvers HiGHS/Ipopt/Clarabel(+SCS)/Gurobi-fallback behind `select_optimizer` — no
  production code in this phase touches solvers, but any measurement script must go through the
  same factory (never hardcode a solver), per the standing convention already used throughout
  `scripts/`.
- Reproducibility: seeded data generation, `Project.toml`/`Manifest.toml` pinned — regenerated
  figures must come from the SAME committed scripts (no ad hoc one-off plotting code), consistent
  with `DrWatson.jl`'s `@quickactivate` pattern already used in every `scripts/*.jl` file touched
  by this phase.
- Documentation: Documenter + Literate rich per-model docs is a **hard requirement** — this phase's
  entire SC-3 deliverable (docs build must actually execute the edited pages) is a direct instance
  of this constraint, not optional polish.
- No new modelling features (explicit phase boundary) — every file this research recommends
  touching is either a test comment, a docs/literate page, a `scripts/` driver, a `results/`
  artifact, or `.planning/PROJECT.md`/`.planning/phases/28-*` — never `src/`.

## Cross-Phase Golden Audit Design (SC-1)

### What already exists (do not re-derive)
`26-GOLDEN-AUDIT.md` and `27-GOLDEN-AUDIT.md` are both complete, both already contain a
"Golden-value moves" table (old→new, file:line, cause, plan) and a "Renames"/"Additive changes"
table, and both certify a GREEN full suite at their respective HEAD commits (`6c25f27` for Phase
26, `ebd94ac` for Phase 27). **SC-1's job is to (a) mechanically prove these two hand-written
tables are complete — nothing slipped through uncommented — and (b) merge them into one document
plus (c) extend the audit to non-test-suite prose** (docs/literate comments, PROJECT.md), which
the Phase 26/27 audits explicitly did NOT cover (they scoped themselves to `test/` + a
finding-consistency check, not literate-page numeric prose).

### Script design
**Base commit:** `5939799` ("docs(26): begin phase execution" — confirmed via `git log`, this is
the exact commit named in CONTEXT.md and is the last commit before Phase 26's first plan landed).
**HEAD:** current tip (`8a96361` at research time; re-resolve at execution time — 183 commits
ahead of base, 34 files changed under `test/`, +2165/−180 lines).

```bash
git diff 5939799..HEAD -- test/ > /tmp/phase28_test_diff.txt
```

Recommended approach (language is Claude's discretion — a short Python or Julia script both work;
Python's `re` + no Julia startup cost makes iteration faster for a one-shot audit tool):

1. Parse the diff into hunks; within each hunk, extract paired `-`/`+` lines.
2. For each pair, extract numeric literals via a regex tuned to this repo's actual golden style
   (verified against real diffs above): `-?\d+\.\d{3,}` (≥3 decimal digits) OR scientific notation
   `-?\d+\.?\d*e[+-]?\d+` OR a bare integer assigned to a name containing `GOLDEN`/`ATOL`/`RTOL`/
   `TOL`/`SEED`/`ITER`/`MAXITER`. This threshold (≥3 decimals) is deliberately chosen from the
   observed goldens (`1.0436080536`, `-4823.1598620624`, `0.6428101637491034`) vs. observed
   non-goldens (hour indices `1:24`, phase numbers `26`, plan IDs `27-09`, line-number citations
   `test_thesis_repro.jl:89`) — spot-check the threshold against a sample of the diff before
   trusting it wholesale (see Known False Positives below).
3. For each flagged pair, check a window of ±5 lines (both the removed AND added hunk context) for
   an attribution comment. Verified project convention (from `test_pricing_fit.jl`'s actual diff):
   `# Phase 26 gap-closure re-pin (PM-06) — ... OLD <value> -> NEW <value>.` — so the detector
   should look for the literal substrings `OLD` and (`->` or `→`) and `NEW`, OR a `Plan-`/`Plan `/
   `FIX-`/`PM-`/`WR-`/`D-` reference, OR the word "moved"/"re-derived"/"re-pin" within the window.
4. Emit one row per flagged-but-unattributed literal: file:line, old value, new value, surrounding
   comment (or "NONE FOUND").
5. Cross-reference every flagged-and-attributed literal against the 26-/27-GOLDEN-AUDIT tables —
   confirm every row in those tables corresponds to something the script independently found (this
   is the actual audit value: proving the hand tables are exhaustive, not just trusting them).

### Known false positives (document these explicitly in the audit script's own header comment)
- **Tolerance/seed round-trips that net to zero across the whole diff window.** `seed=1 → seed=5
  → seed=1` in `test/test_mpc_loop.jj` (27-GOLDEN-AUDIT §1 "Seed history note") — a base-to-HEAD
  diff over `5939799..HEAD` will show **no line change at all** for this one (both endpoints are
  `seed = 1`), so it is a non-issue for a base→HEAD diff scan specifically — but if the script is
  ever run hunk-by-hunk per commit instead of base→HEAD, it will falsely flag this as two
  unexplained moves. Keep the scan strictly base→HEAD, not per-commit.
- **Ratio/margin numbers inside prose comments** (e.g. "≈2.4x margin", "ratio ≈4.04") are not code
  literals and will not appear as diff-parseable `-`/`+` value pairs in most cases, but a comment
  block that is ITSELF rewritten (not just added) can produce a spurious pair if both old and new
  comment text contain decimal-shaped substrings. Restrict literal extraction to lines that are
  NOT pure `#`-comment-only line changes where the number appears only inside prose describing a
  ratio, not assigned to a `const`/passed to `@test`/`isapprox`/`atol=`/`rtol=`.
- **Version/line-number self-references** (`test_thesis_repro.jl:89`, `Plan 27-05`) — filtered by
  the ≥3-decimal-digit / scientific-notation heuristic above; these are short integers or
  dotted-but-short (e.g., `27.05` never appears — it's written `27-05` with a hyphen) so they
  naturally fall outside the regex, but double-check the format-check job's own report
  (`.github/scripts/check_content_loss.py` precedent) for a similar false-positive class if reused.
- **JuliaFormatter-driven whitespace-only reflow** can make a diff hunk pair a formatted line
  against an unformatted one even when the LITERAL value is unchanged (observed project-wide
  hazard, `local-project-toml-drift` / JuliaFormatter memory) — normalize whitespace before
  comparing extracted numeric strings, not before extracting them (i.e., compare the number
  itself, not the raw line).

### Docs/PROJEC.md prose audit (separate, smaller pass — SC-1's second clause)
Grep-verified this research session: **no exact numeric golden values appear in
`.planning/PROJECT.md`** (searched for all 6 headline moved values — zero hits outside `.pdf`
binaries and `docs/build/` which is gitignored). PROJECT.md's "Current State" section already
narrates Phase 26/27 findings in qualitative/directional language ("Headline goldens moved... see
26-GOLDEN-AUDIT.md; restate in Phase 28"), which is itself the placeholder Phase 28 must resolve —
not a stale numeric claim to fix. The literate-page prose audit DOES find live numeric citations
that need checking — enumerated exhaustively in "Pattern Map" below (only 4 hits: two in
`thesis_reproduction_assumptions.jl` citing the CURRENT correct `DSO_BAND_HI=7.211125525764296`
value already, one in `convex_branch_flow.jl` citing the CURRENT `-921.754`/`-921.277` EXACT-04
figures already). **Conclusion: the prose-citation half of SC-1 is nearly a clean bill — the
actual restatement work is concentrated in stale comments/assumptions describing MECHANISMS (e.g.
"the SOC relaxation goes genuinely inexact" in `test_ac_oracle.jl`), not stale numeric literals in
prose.** See the SOCP-inexactness section below for the one substantive gap found.

## REPRO-01 Pipeline Inventory (SC-2)

### The full pipeline, end to end
| Stage | File | Role | Live or precomputed | Timing (measured/estimated) |
|-------|------|------|---------------------|------------------------------|
| Population fixture | `test/fixtures_phase7.jl` (`Phase7Fixtures`) | Phase-17-retuned IEEE-123 population constants (`LOAD_SCALE_IEEE123=0.05`, `PV_SCALE_IEEE123=0.12`, seed=20260719) | N/A — a `TestItems.@testmodule`, must be re-implemented inline in any standalone script (documented gotcha, see `scripts/repro_stability_check.jl`'s own header) | — |
| Committed golden | `test/test_thesis_repro.jl` | The certified `@testitem` — sign flip + `DSO_BAND_LO=0.0`/`DSO_BAND_HI=7.211125525764296` — ALREADY carries the `tol_gap_abs=tol_gap_rel=3e-9` override (Phase 26 PM-05/cluster-E fix) and is confirmed PASSING at Phase 27 close | Runs inside `Pkg.test()` (~21-36 min for the whole suite) | — |
| Live docs page (BROKEN RISK) | `docs/literate/thesis_reproduction_ieee123.jl` | Documenter `@example`-executes `solve_welfare(feeder, ConvexBranchFlow(), aggs; ...)` (line 176) and `fit_baseline(feeder, ConvexBranchFlow(), aggs; ...)` (line 182) on the IDENTICAL population point, with **NO `optimizer`/`tol_gap` override at all** | Live, executed by `julia --project=docs docs/make.jl` | Individual page: seconds (small feeder solve); whole docs build ~measured empirically at execution time, budget generously (CI job has `timeout-minutes: 30`) |
| Companion assumptions page | `docs/literate/thesis_reproduction_assumptions.jl` | Narrates the reduction chain, the `DSO_BAND` derivation, Section 8's stability-sweep discussion; ALREADY cites the CURRENT `7.211125525764296` band value (verified, not stale) | Live `@example`? — verify at execution time; regardless, its PROSE needs a new subsection restating Phase 26/27's effect on this pipeline | — |
| Stability/sweep script | `scripts/repro_stability_check.jl` | `count_failures` (flake rate) + `sweep_population_scale` (±2-5% robustness); the SAME `REPRO_TOL_GAP`/`REPRO_MAX_ITER` env-var mechanism used in Phase 27's F-27-05-1/F-27-05-2 investigation | Manual re-run via `julia --project=. scripts/repro_stability_check.jl`, writes `results/repro_stability_check/findings.txt` | Per F-27-05-2's own measurement, a 20-repeat `count_failures` run at `REPRO_TOL_GAP=1e-10` took long enough to hit a 300s timeout partway through in that session — budget several minutes per sweep configuration |
| IEEE-123 repro figure | `scripts/thesis_case123_repro.jl` | Regenerates `results/thesis_case123_repro/fig_dso_surplus_sign_flip.{pdf,png}` (currently dated 2026-07-26, i.e. v2.1-era, pre-Phase-26/27) | Manual re-run: `julia --project=. scripts/thesis_case123_repro.jl` | — |
| IEEE-13 Case A figures | `scripts/thesis_caseA.jl` | Regenerates 6 figures in `results/thesis_caseA/` (currently dated 2026-08-28, i.e. pre-Phase-26 — the IEEE-13 goldens `GOLDEN_V9_16`/`GOLDEN_WELFARE`/`GOLDEN_DADP16` all moved in Phase 26 Plan 26-17) | Manual re-run: `julia --project=. scripts/thesis_caseA.jl` | — |
| Portuguese writeup | `docs/writeups/thesis_caseA.typ`/`.pdf` | References `results/thesis_caseA/` figures by filename; conceptual/model prose, **no embedded numeric goldens found** (grep-verified this session) — only needs the figure files refreshed underneath it, not text edits, UNLESS a re-typst-compile is desired for freshness (Claude's discretion, not required by CONTEXT.md) | Typst compile is optional; figures are the load-bearing artifact | — |

**No DrWatson `tagsave`/`@produce_or_load` used anywhere in this pipeline** (grep-verified: zero
hits in `thesis_case123_repro.jl`, `thesis_caseA.jl`, `repro_stability_check.jl`). All three
scripts use only `DrWatson.@quickactivate "TSODSO"` (environment activation) plus manual
`mkpath(OUT); save(joinpath(OUT, "$name.pdf"), fig)` — reproducibility here means "re-run the
committed script," not "load a cached, provenance-stamped result." Do not introduce `tagsave` as
part of this phase unless explicitly asked — it would be new tooling scope beyond "regenerate
existing figures."

### The 27-05 "repro population point exactness drift" — what it is and what it affects
**Confirmed root mechanism (measured in this research session by reading `test_thesis_repro.jl`'s
own committed code, not re-run live):** the exact SAME IEEE-123 population point
(`LOAD_SCALE_IEEE123=0.05, PV_SCALE_IEEE123=0.12, seed=20260719`) that F-27-05-2 found trips
`assert_socp_exact!` at Clarabel's DEFAULT `tol_gap=1e-8` (maxgap≈4.38e-6, ratio≈19.25 over the
FIX-08 hybrid floor) is the SAME point `test_thesis_repro.jl:83-89` already guards with
`optimizer = select_optimizer(SOCP(); tol_gap_abs = 3e-9, tol_gap_rel = 3e-9)` — a fix that predates
F-27-05-2 chronologically (landed in Phase 26 as "PM-05/cluster E", a precision-floor fix for a
DIFFERENT, smaller ratio ≈3.94/gap≈4.4e-6 measured at Phase 26 close) but numerically matches
F-27-05-2's own measured gap (4.4e-6 ≈ 4.38e-6) almost exactly. **This is strong (not certain)
evidence the "drift" is the SAME single residual, re-measured twice under two different gate
floors (Phase 26's older, looser gate vs. Phase 27's tighter FIX-08 hybrid floor) — i.e., a
PRECISION-FLOOR ARTIFACT, not a new genuine inexactness, and the EXISTING `tol_gap_abs=3e-9`
override already resolves it (test_thesis_repro.jl is confirmed PASSING at Phase 27 close, 0 fail
0 error).** This conclusion should be independently re-measured (not merely asserted) as Task 1 of
the SC-2 work — CONTEXT.md's own locked decision explicitly requires "MEASURE first," and a
plausible-but-unconfirmed hypothesis from research must not become a plan's premise without a
verification step.

**What this drift affects if NOT fixed the same way:**
- `docs/literate/thesis_reproduction_ieee123.jl`'s live `solve_welfare`/`fit_baseline` calls
  (lines 176, 182) have NO tol_gap override at all — per this measured mechanism, the next docs
  build attempt will very likely throw `SOCP relaxation INEXACT` on `makedocs`, breaking the ENTIRE
  docs build (Documenter aborts on an uncaught exception in an `@example` block), not just this one
  page.
- `scripts/repro_stability_check.jl`'s raw `solve_welfare` calls in `count_failures` (used WITHOUT
  `REPRO_TOL_GAP` set) will also throw at default settings — this is fine/expected if the script is
  always re-run WITH `REPRO_TOL_GAP=<measured value>` going forward, but the script's own committed
  `findings.txt` (dated 2026-08-23, pre-dates Phase 26/27 entirely) needs a fresh run+commit either
  way.
- `scripts/thesis_case123_repro.jl` (the standalone figure-regen script) calls `fit_baseline`
  directly with NO override (grep-verified: zero `tol_gap`/`optimizer` mentions in that file) — it
  will need the SAME override threaded through, OR must independently re-measure that its own
  `solve_welfare`/`fit_baseline` call sites survive at default settings (they may, since
  `fit_baseline`'s SITE-2 is now AC-settled per FIX-09/10 and no longer runs the fragile SOCP path
  that`test_thesis_repro.jl`'s own header comment documents — verify this empirically, don't
  assume).

**Recommended task shape:** ONE task, run BEFORE touching any of the 3 consumer files above:
directly execute (not via TestItemRunner — see Validation Architecture) the exact literal body of
`test_thesis_repro.jl`'s `@testitem`, both with and without its `tol_gap` override, confirm the
measured gap/ratio, and DECIDE per the locked policy (precision artifact → propagate the SAME
measured override to the 3 consumer files; genuinely inexact → restate REPRO-01 as
"uncertified at this specific population point" and pick a DIFFERENT, certifiably-exact nearby
point for the live docs page, documenting why). Do not guess; the measurement is cheap (one
`julia --project=.` script, no full-suite run needed).

## SOCP-Inexactness Dual-Notion Finding (SC-3, part 1)

This is the single most important, least obvious finding from this research session, and it
determines the entire shape of 3 of the 4 literate-page edits under SC-3.

**Two functions certify "exactness" and they measure genuinely different things:**

1. **`assert_socp_exact!`** (`src/models/exactness.jl`) — the FIX-08 hybrid-floor cone-residual
   gate: `atol_b = max(τ_solver=2e-7, ε·ref_b)`, checking `|l·v - (P²+Q²)| ≤ atol_b` per branch/hour.
   This asks: *is the SOCP solution itself branch-flow-physically-consistent* (does the relaxed
   inequality bind with equality)? Under the corrected Gan–Low default (Phase 26), EXACT-04's
   fixture is now measured EXACT by THIS gate (`26-FINDINGS.md`: "EXACT-04 now EXACT, well under
   the PF-04 gate").
2. **`assert_ac_exact!`** (`src/models/ac_oracle.jl:300`) — compares the SOCP context's OWN
   solved `v`/`P` values directly against an independent nonconvex AC-OPF oracle's (`Ipopt`)
   solved `v`/`P` values, hour by hour: `exact = vgap <= atol + rtol*vmag && pgap <= atol +
   rtol*pmag` (verified by direct code read, `src/models/ac_oracle.jl:330-332`). This asks: *does
   the SOCP-optimal dispatch match the TRUE globally-optimal AC dispatch* — a question about
   OPTIMALITY, not physical consistency.

**Why both can legitimately disagree simultaneously on the SAME fixture under the SAME (new
default) formulation:** the corrected default is Gan–Low's "modified OPF" — a genuine RESTRICTION
of the feasible region (per 26-FINDINGS: "conservative restriction on the upper voltage band,
exact by theorem... measurable ~0.05% welfare loss"). A restriction's optimal solution CAN be
branch-flow-physically-consistent (cone-exact, satisfying gate 1) while still being a DIFFERENT,
suboptimal point relative to the true (less-restricted) AC optimum (failing gate 2, because the
restriction excludes the true optimum from its own feasible set). This is NOT the v2.1 "genuine
relaxation looseness" failure mode (a SLACK cone, ratio≫1) — it is a "restriction excludes the
true optimum" failure mode, mechanically different, even though `assert_ac_exact!`'s per-hour
`exact`/`inexact` report may show the identical symptom (`inexact_hours` non-empty).

**Where this bites, concretely — `test/test_ac_oracle.jl`'s own EXACT-04 `@testitem`
(lines ~179-274, verified by direct read this session):**
- Uses bare `ConvexBranchFlow()` (line 205) — i.e. now solves under the NEW Gan–Low default, not
  the old thesis-literal copy the comment describes.
- Its own inline comment (lines 191-193, 265-273) still narrates the OLD mechanism verbatim:
  "pins bus voltage at V²max and drives the SOC relaxation genuinely INEXACT... the documented SOC
  exactness-failure regime" — this describes CONE inexactness (gate 1's failure mode), which per
  26-FINDINGS no longer holds under the default.
- The test's ASSERTIONS (`@test !isempty(inexact_hours)`, `@test diagnosed`) may well still PASS
  — because gate 2 (`assert_ac_exact!`) can still report inexact hours for the DIFFERENT
  restriction-suboptimality reason — but this has NOT been independently re-measured this session
  (research is honest about this: it is a plausible, code-supported hypothesis, not a confirmed
  fact). **This is exactly the "MEASURE, don't guess" situation CONTEXT.md's SC-3 anticipates.**
- Regardless of whether the assertions still pass, **the test's own COMMENT is stale/misleading**
  about WHY they pass — this is a documentation-accuracy defect this phase must fix even if zero
  test code changes.

**Task shape for SC-3 part 1:**
1. Run `test_ac_oracle.jl`'s EXACT-04 fixture directly (both `ConvexBranchFlow()` bare AND
   `ConvexBranchFlow(; thesis_literal=true)`) and record, for each: `assert_socp_exact!`'s
   cone-residual verdict, `assert_ac_exact!`'s per-hour verdict, and WHICH mechanism explains any
   inexact hours (voltage-bound-hit vs. reverse-flow vs. restriction-suboptimality — the existing
   `diagnosed` check in the test only distinguishes voltage-bound/reverse-flow, not
   restriction-vs-relaxation-cause; this phase may need a NEW diagnostic distinguishing them, or
   may satisfy itself with prose explaining the code-level reasoning above without a new test
   assertion — Claude's discretion, but the prose MUST be accurate either way).
2. Update `test/test_ac_oracle.jl`'s comment (not its assertions, unless the measurement in step 1
   shows the assertions themselves need adjusting) to state which mechanism is active under the
   default vs. under `thesis_literal=true`.
3. Update the 3 literate pages per the "Pattern Map" table below.
4. Regenerate `results/socp_applicability/{highpv_3bus,ieee123}_{sweep.csv,findings.txt}` — these
   are STALE (dated 2026-07-26, pre-Phase-26) precomputed artifacts feeding
   `docs/literate/socp_applicability.jl`'s "Substrate B" section (per `docs/make.jl`'s own comment,
   loaded from disk because live IEEE-123 solve exceeds CI timeout). The regeneration driver is
   `scripts/socp_applicability_sweep.jl`, which ALSO calls bare `ConvexBranchFlow()` (verified,
   lines 244/350) — decide explicitly (and document) whether this sweep should run under the
   default, under `thesis_literal=true`, or (recommended, most informative) under BOTH with the
   findings.txt reporting both classifications side by side, since the whole point of this page is
   characterizing where exactness holds/fails.

## MPC/DLMP Restatement Inventory (SC-3, part 2 — Phase-27 deferrals)

**DLMP `.loss`/`.voltage` → `.cone`/`.drop` rename:** ALREADY fully reflected in
`docs/literate/pricing_dlmp.jl` (verified by direct read: uses `.cone`/`.drop` throughout, includes
an explicit note "`decompose_dlmp` returned a `.loss`/`.voltage`-named NamedTuple prior to phase
27; those names are now `.cone`/`.drop`... `.loss`/`.voltage` remain [deprecated aliases]"). **No
further edit needed here** — this specific deferred item is already closed; confirm this
conclusion during execution (a 2-minute re-read) rather than re-doing the work, and note it as
"already satisfied" in `28-FINDINGS.md` so it isn't silently skipped either.

**MPC `realized_welfare`/`regret` semantics:** NOT yet updated. Confirmed by direct read of
`docs/literate/mpc_rolling_horizon.jl` (grep for `forecast_settled_welfare`/`settlement_violations`
/`ac_status`: zero hits) — this page still narrates the PRE-Phase-27 semantics only (a single
`realized_welfare` with no mention that Phase 27 renamed the old forecast-consistent number to
`forecast_settled_welfare` and made `realized_welfare` the NEW truth-settled quantity, nor any
mention of the new `settlement_violations` diagnostic field `run_mpc` now returns). Since this page
is Documenter-executed (`@example`), the NUMBERS it prints will already be correct/current on next
build (they're computed live) — the gap is entirely in the PROSE, which still describes what the
numbers mean using stale semantics. Same for `scripts/demo_mpc_plots.jl` (grep-confirmed: uses
`r.realized_welfare`/`r.regret` extensively, zero mentions of `forecast_settled_welfare` or
`settlement_violations`) — its regenerated figures (`results/demo_mpc_plots/*.png`, all dated
2026-08-28, i.e. BEFORE `src/experiments/mpc_loop.jl`'s 2026-09-29 Phase-27 edit) need a fresh run,
and the script's own prose/printed labels should mention the new truth-settlement mechanism if it
changes what's plotted (verify: does `r.realized_welfare` in the CURRENT code compute a genuinely
different number than what generated the committed Aug-28 figures? Given `mpc_loop.jl` was
directly modified by Phase 27, yes — these figures are stale artifacts of the OLD forecast-settled
number, not just an aesthetic staleness).

**Task shape:**
1. Re-run `scripts/demo_mpc_plots.jl`, regenerate all 4 `results/demo_mpc_plots/*.{png,pdf}` pairs.
2. Add a "Restated in v4.0 (Phase 28)" prose callout to `docs/literate/mpc_rolling_horizon.jl`'s
   §3 (Regret) explaining: `realized_welfare` is now truth-settled (genuine AC power flow,
   `ACPowerFlow(; limits=false)`, physics-only — see FIX-10), the OLD forecast-consistent number
   survives as `forecast_settled_welfare` (a separately-labeled diagnostic, never the headline),
   and `run_mpc` now also reports `settlement_violations` (thermal/voltage overloads recomputed
   directly from solved P/Q/l/v, since operating limits are no longer enforced as a refusal gate
   at truth-settlement time).
3. Same callout treatment (shorter) in `scripts/demo_mpc_plots.jl`'s own header comment.
4. `docs/literate/stochastic_pv_demand.jl` also mentions `regret` (grep hit) — check briefly
   whether it shares the same semantic drift; if it's a SEPARATE (non-MPC) regret concept
   (STOCH-axis, not MPC-axis), no action needed — verify at execution time, do not assume.

## Cross-Phase Finding Consistency (verification-only carry-forward)

Both Phase 26 and Phase 27's own golden audits already ran an internal "finding consistency check"
(26-GOLDEN-AUDIT §4, confirming PM-01/PM-02/PM-04/v2.1-restatement text is IDENTICAL across every
location it's stated). Phase 28's `28-CROSS-PHASE-AUDIT.md` should INCLUDE these two prior checks
by reference (not re-verify from scratch — they're recent, dated 2026-09-29, and nothing since has
touched those specific files per this research's own git-diff scan) but MUST add the 3 new findings
this phase itself produces (REPRO-01 population-drift disposition, EXACT-04 dual-notion
clarification, MPC restatement) to the SAME consistency-check discipline: state each finding once,
canonically, and verify every location that narrates it (docs/literate pages, PROJECT.md,
28-FINDINGS.md) agrees word-for-word on the substance (not necessarily the prose).

## Pattern Map

Analog files for each artifact this phase creates or modifies, keyed to the closest existing
precedent in Phases 26/27 (so the planner can point an executor at a concrete template):

| File to create/modify | Analog / precedent | What to mirror |
|---|---|---|
| `28-CROSS-PHASE-AUDIT.md` (new) | `26-GOLDEN-AUDIT.md` + `27-GOLDEN-AUDIT.md` (merge target) | Same table shape (Golden | File:Line | Old | New | Cause | Plan), same "Final full-suite result" section format, same "Closing verdict" summary paragraph |
| Golden-audit script (new, e.g. `.planning/phases/28-*/scripts/audit_goldens.py` or `.jl`) | No direct precedent — nearest is `.github/scripts/check_content_loss.py` (existing CI script that diffs tracked files for content loss) | Same "diff-then-flag" structure; reuse its git-diff-parsing idiom if Python is chosen |
| `docs/literate/thesis_reproduction_ieee123.jl` (edit: add tol_gap override + restatement callout) | `test/test_thesis_repro.jl:83-89`'s own already-landed fix | Copy the EXACT `optimizer = select_optimizer(SOCP(); tol_gap_abs=3e-9, tol_gap_rel=3e-9)` pattern (pending Task-1 measurement confirming 3e-9 still suffices under current code) |
| `docs/literate/thesis_reproduction_assumptions.jl` (edit: new restatement subsection) | Its OWN existing "Section 8" (population-scale stability discussion, already restated once for the 260823-gea correction) | Same "CORRECTED <date>: ... THAT IS REFUTED/CONFIRMED ..." callout style used at the top of `scripts/thesis_case123_repro.jl` |
| `scripts/repro_stability_check.jl` (re-run, no code edit expected) | Its own `REPRO_TOL_GAP`/`REPRO_MAX_ITER` mechanism (already built for exactly this use case in Phase 27 plan 27-05) | Re-run at measured tol_gap, overwrite `results/repro_stability_check/findings.txt` with a fresh, dated run |
| `scripts/thesis_case123_repro.jl` (edit: thread tol_gap override if Task 1 shows it's needed) | Same pattern as the docs-page fix above | — |
| `results/thesis_case123_repro/fig_dso_surplus_sign_flip.{pdf,png}` (regenerate) | — | Just re-run the script |
| `scripts/thesis_caseA.jl` (re-run, no code edit expected — IEEE-13 goldens moved but the SCRIPT computes live, so it will pick up new values automatically) | — | Re-run, diff the printed values against `test_ieee13.jl`'s new `GOLDEN_*` constants as a sanity cross-check |
| `results/thesis_caseA/*.{pdf,png}` (6 figure pairs, regenerate) | — | Re-run `thesis_caseA.jl` |
| `docs/literate/ac_oracle.jl` (edit: dual-mode EXACT-04 restatement) | `docs/literate/convex_branch_flow.jl`'s own "PM-01 addendum" (already landed in Phase 26 Plan 26-18 — the exact "Restated" callout style CONTEXT.md asks this phase to reuse) | Copy the addendum-subsection pattern verbatim (heading style, "MEASURED:" bolded lead-ins) |
| `docs/literate/restricted_branch_flow.jl` (edit: same dual-mode restatement, since it directly narrates EXACT-04 too — line ~298) | Same as above | Same |
| `docs/literate/socp_applicability.jl` (edit: thesis_literal explicit, restate exact/inexact map) | Same as above; also its own "Is the inexactness real? tolerance ladder" section (already models the right methodology, just needs the `ConvexBranchFlow()` call updated) | — |
| `test/test_ac_oracle.jl` (comment-only edit, verify assertions unchanged or update if Task measurement shows otherwise) | `26-FINDINGS.md`'s Plan 26-18 entry (same "honest-relabel-only, no production code changed" discipline) | — |
| `scripts/socp_applicability_sweep.jl` (edit: run under both `ConvexBranchFlow()` variants, or decide+document one) | — | — |
| `results/socp_applicability/{highpv_3bus,ieee123}_{sweep.csv,findings.txt,sweep.png}` (regenerate) | — | Re-run the sweep script |
| `docs/literate/mpc_rolling_horizon.jl` (edit: restatement callout in §3) | Same "PM-01 addendum" pattern | — |
| `scripts/demo_mpc_plots.jl` (edit: header comment note; re-run) | — | — |
| `results/demo_mpc_plots/*.{png,pdf}` (4 pairs, regenerate) | — | — |
| `.planning/PROJECT.md` (edit: Current State section + possibly a new "v4.0 Phase 28" summary line) | Phase 26/27's own additions to PROJECT.md's "Current State" (already follow a consistent "**Phase N (Name) COMPLETE <date>.** ..." paragraph style) | Follow the SAME paragraph style; do NOT rewrite the historical "Shipped Milestone: v2.1" section's prose — add a forward pointer instead ("see Phase 28 restatement") to avoid rewriting shipped-milestone history |
| `28-FINDINGS.md` (new, standard per-phase findings log) | `26-FINDINGS.md` / `27-FINDINGS.md` | Same structure: one `##` section per plan, findings tagged with disposition |

## Common Pitfalls

### Pitfall 1: Assuming a literate page's live-executed numbers auto-fix the docs
**What goes wrong:** Because Documenter/Literate `@example` blocks re-execute at build time, it's
tempting to think "the numbers will just update themselves, nothing to do here."
**Why it happens:** True for NUMBERS printed inside code blocks, but NOT true for numbers or claims
written in `#`-comment PROSE around those blocks (like the stale `test_ac_oracle.jl` comment
describing a mechanism that no longer applies) — and NOT true if the live call now THROWS
(the `thesis_reproduction_ieee123.jl` risk above), in which case the page doesn't just show a
stale number, it fails to build at all.
**How to avoid:** Treat "does this page's live `@example` block still execute without throwing"
as a SEPARATE checklist item from "is the prose around it still accurate" — both must be verified.
**Warning signs:** A page whose bare `ConvexBranchFlow()` call touches a fixture also mentioned in
Phase 26/27's FINDINGS.md as having moved/drifted.

### Pitfall 2: Treating the 26/27 GOLDEN-AUDIT tables as ground truth without independently verifying
**What goes wrong:** The audit script (SC-1) is only valuable if it independently re-derives that
every moved literal has a comment — trusting the hand-written tables defeats the purpose.
**Why it happens:** The tables are detailed and confidence-inspiring; it's tempting to just copy
them into `28-CROSS-PHASE-AUDIT.md` verbatim.
**How to avoid:** Run the script FIRST, cross-reference its output against the tables SECOND —
the value is in catching anything the tables missed, not in reformatting what they already found.
**Warning signs:** A "merge" step in the plan that never actually runs `git diff` itself.

### Pitfall 3: Conflating "cone-exact" with "AC-optimal" when restating EXACT-04
**What goes wrong:** Writing "EXACT-04 is now exact" without specifying WHICH exactness notion,
reintroducing the exact ambiguity this research had to untangle.
**Why it happens:** `26-FINDINGS.md`'s own prose ("EXACT-04 now EXACT, well under the PF-04 gate")
is scoped to gate 1 (cone-residual) but reads, out of context, like a blanket exactness claim.
**How to avoid:** Every restatement sentence about EXACT-04 must name which of the two gates
(`assert_socp_exact!` cone-residual vs. `assert_ac_exact!` dispatch-comparison) it is describing.
**Warning signs:** A sentence saying "EXACT-04 is exact" with no qualifier, anywhere in the diff.

### Pitfall 4: Re-running the full suite before the docs build, or vice-versa, without checking both are needed at the SAME final commit
**What goes wrong:** Per `background-suite-orphan-race.md`, a full-suite run started before later
docs-page-edit commits land will report stale results; the SAME risk applies symmetrically to a
docs build run before the LAST test-file comment edit lands.
**Why it happens:** Both are long-running (suite ~21-36 min per current baseline; docs build
budget unknown but CI allows 30 min) and easy to kick off "in the background" prematurely.
**How to avoid:** Sequence BOTH as the final, phase-closing gate (mirroring 26-08/27-06's own
"Plan N — phase-closing gate" pattern) — after every wave's file edits are committed, not before.
**Warning signs:** A wave plan that includes "run full suite" as one of its OWN tasks rather than
deferring it to a dedicated closing plan.

### Pitfall 5: Forgetting `.claude/worktrees/` contamination before a certifying run
**What goes wrong:** Per `background-suite-orphan-race.md` item 3, an agent worktree present during
`Pkg.test()` roughly DOUBLES the reported counts and produces dozens of phantom failures.
**How to avoid:** `git worktree list` must show zero `.claude/worktrees/agent-*` entries
immediately before the closing-gate full-suite run.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | `Test` (stdlib) + `TestItems`/`TestItemRunner` (test-only deps, `test/Project.toml`) |
| Config file | `test/runtests.jl` (the real entrypoint) |
| Quick run command | Direct `julia --project=.` script reproducing a single `@testitem`'s literal body (see `gsd-plan-verify-testitemrunner-trap` memory — TestItemRunner does NOT resolve under `--project=.`) |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (~21-36 min per current baseline, per `background-suite-orphan-race` memory) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FIX-11 (SC-1) | Golden-audit script correctly flags a KNOWN unexplained literal and does NOT flag a KNOWN-attributed one | unit (script self-test) | Run the script against a synthetic diff fixture (2-3 lines) with and without an attribution comment; assert the correct flag/no-flag outcome | ❌ new — Wave 0: write a tiny synthetic-diff smoke test alongside the script itself |
| FIX-11 (SC-1) | 28-CROSS-PHASE-AUDIT.md's own claims are exhaustive vs. the real diff | integration | Re-run the script against `git diff 5939799..HEAD -- test/` and manually spot-check 5 rows against the source files (mirrors 26-GOLDEN-AUDIT's own "spot-checked directly against files" methodology) | ✅ — methodology exists, just needs re-application |
| FIX-11 (SC-2) | REPRO-01's `test_thesis_repro.jl` golden still passes at HEAD after any docs/scripts edits (it should be UNTOUCHED by this phase's file list, so this is a regression check, not new coverage) | integration | `julia --project=. -e 'import Pkg; Pkg.test()'` filtered to `:thesis_repro` tag, or a direct script reproducing the `@testitem` body | ✅ |
| FIX-11 (SC-2) | `docs/literate/thesis_reproduction_ieee123.jl` executes without throwing under `julia --project=docs docs/make.jl` | smoke (docs build) | `julia --project=docs docs/make.jl` (full build — Documenter has no single-page build mode; budget the whole ~30 min CI allowance) | ✅ path exists, outcome unverified — this IS the phase's deliverable |
| FIX-11 (SC-3) | `test_ac_oracle.jl`'s EXACT-04 `@testitem` still passes after its comment is corrected (and after any assertion adjustment Task 1's measurement reveals is needed) | unit | Direct script reproducing the `@testitem` body under BOTH `ConvexBranchFlow()` and `ConvexBranchFlow(; thesis_literal=true)` | ✅ |
| FIX-11 (SC-3) | `docs/literate/{ac_oracle,restricted_branch_flow,socp_applicability}.jl` all execute without throwing | smoke (docs build) | Same full docs build as above (single build covers all 3 pages) | Same as above |
| FIX-11 (SC-3, MPC) | `run_mpc`'s returned `settlement_violations` and `forecast_settled_welfare` fields are correctly described in the restated prose (a documentation-accuracy check, not a code test) | manual-only | N/A — reviewed by a human/code-reviewer reading the diff against `src/experiments/mpc_loop.jl`'s actual field names | N/A |

### Sampling Rate
- **Per task commit:** direct `julia --project=.` script reproducing the touched fixture/testitem
  body (never TestItemRunner directly).
- **Per wave merge:** targeted tag-filtered `Pkg.test()` run for the touched test files (e.g.
  `:thesis_repro`, `:ac_oracle` tags) PLUS a `julia --project=docs docs/make.jl` run if any
  literate page in that wave was touched.
- **Phase gate:** full `Pkg.test()` (all tags) AND full `julia --project=docs docs/make.jl`, both
  at the SAME final commit, both launched via the detached/`nohup setsid` pattern
  (`background-suite-orphan-race.md`) since both are long-running.

### Wave 0 Gaps
- [ ] Golden-audit script itself does not exist yet — write it (language: Claude's discretion) plus
  a tiny synthetic-diff self-test, per "Golden Audit Design" above.
- [ ] No committed helper distinguishes cone-exactness-cause from restriction-suboptimality-cause
  in `test_ac_oracle.jl` — decide during Task 1's measurement whether this needs a NEW small
  diagnostic or can be handled by prose alone (Claude's discretion; not mandated by CONTEXT.md).
- Framework install: none — all required tooling (`Test`, `TestItems`, `Documenter`, `Literate`,
  `DrWatson`, `CairoMakie`) is already in `Project.toml`/`docs/Project.toml`/`test/Project.toml`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia 1.10/1.11/1.12 | Full suite, docs build | Assume ✓ (project's own CI matrix; local dev environment already used for Phases 26/27) | Per `Project.toml`/`docs/Manifest.toml` (docs env pinned to Julia 1.12 per CI comment: "docs/Manifest.toml was resolved with julia_version=1.12.5... instantiating on an older Julia fails") | If local Julia is not 1.12, run docs build under a 1.12 toolchain specifically — this is a HARD requirement per the CI workflow's own comment, not a soft preference |
| Clarabel/HiGHS/Ipopt (`*_jll`, precompiled, no system install) | Every solve in this phase's re-runs | ✓ (already used throughout Phases 26/27 in this exact environment) | Per `Project.toml` `[compat]` | — |
| CairoMakie | Figure regeneration (`thesis_caseA.jl`, `demo_mpc_plots.jl`, etc.) | ✓ but flagged as a weakdep with 2 KNOWN-FALSE Aqua failures on a local checkout (`local-project-toml-drift` memory) — expect these 2, do not treat as new regressions | 0.15 (per `docs/Project.toml`) | — |
| Python 3 (if chosen for the audit script) | SC-1 golden-audit script | Assume ✓ (already used for `.github/scripts/check_content_loss.py`) | — | Julia equally viable — Claude's discretion |
| Network access | None of this phase's work requires network (no data fetches; all fixtures are committed constants or public-data-derived tables already in-repo) | N/A | — | — |

**Missing dependencies with no fallback:** none identified.
**Missing dependencies with fallback:** none identified — this phase's tooling footprint is
entirely a subset of what Phases 26/27 already exercised successfully.

## Security Domain

Not applicable — this is a research-library correctness/documentation phase with no
authentication, session, network-facing, or cryptographic surface. `security_enforcement` is
absent from `.planning/config.json` (defaults enabled), but no ASVS category applies to a
single-user local Julia research tool touching only test comments, docs pages, and regenerated
local figure files.

## Blast-Radius / Parallelism Map

Four largely disjoint work items, confirmed by direct file-overlap check this session:

| Work item | Files touched | Overlaps with |
|---|---|---|
| **A — Golden-audit script (SC-1)** | New script file(s) under `.planning/phases/28-*/`, new `28-CROSS-PHASE-AUDIT.md` | None (read-only w.r.t. `src/`/`test/`/`docs/`) |
| **B — REPRO-01 restatement (SC-2)** | `docs/literate/thesis_reproduction_ieee123.jl`, `thesis_reproduction_assumptions.jl`, `scripts/repro_stability_check.jl`, `scripts/thesis_case123_repro.jl`, `scripts/thesis_caseA.jl`, `results/thesis_caseA/*`, `results/thesis_case123_repro/*`, `results/repro_stability_check/findings.txt` | None with C/D |
| **C — SOCP-inexactness dual-mode (SC-3a)** | `docs/literate/{ac_oracle,restricted_branch_flow,socp_applicability}.jl`, `test/test_ac_oracle.jl`, `scripts/socp_applicability_sweep.jl`, `results/socp_applicability/*` | None with B/D |
| **D — MPC/DLMP restatement (SC-3b)** | `docs/literate/mpc_rolling_horizon.jl`, `scripts/demo_mpc_plots.jl`, `results/demo_mpc_plots/*` (DLMP part already closed — verify only) | None with B/C |
| **E — Consolidation (phase-closing gate)** | `.planning/PROJECT.md` (single shared file — sequence LAST, after B/C/D land, to avoid merge conflicts), full suite run, full docs build run | Depends on A+B+C+D all landing first |

**Recommendation:** A, B, C can run as one 3-wide parallel wave (A is not Julia-heavy — a
diff/text script — so it does not count meaningfully against the "≤3 concurrent Julia executors"
process constraint even if run alongside B/C). D can join the SAME wave if capacity allows (its
Julia footprint is one script re-run, similar cost to B's `thesis_caseA.jl`), or run as a short
second wave — Claude's discretion based on the planner's actual concurrency budget. E is always
sequential and last, mirroring Phase 26 Plan 26-08 / Phase 27 Plan 27-06's own "phase-closing gate"
precedent exactly.

## Open Questions (RESOLVED)

1. **Is the REPRO-01 population-point exactness "drift" (F-27-05-2) a precision-floor artifact or
   genuine new inexactness?**
   - What we know: the measured gap (4.38e-6, F-27-05-2) numerically matches the gap Phase 26
     already fixed via a `tol_gap_abs=tol_gap_rel=3e-9` override in the committed golden test
     (`test_thesis_repro.jl`, confirmed passing at Phase 27 close).
   - What's unclear: whether this is genuinely the SAME residual re-measured under two different
     gate floors (precision artifact — RESOLVED by the existing override) or whether Phase 27's
     code changes moved the operating point further (a NEW, distinct inexactness).
   - Recommendation: RESOLVED for planning purposes — treat as "precision-floor artifact, existing
     override already resolves it" as the WORKING hypothesis, but make Task 1 of the SC-2 work an
     explicit, cheap (single-script) MEASUREMENT that confirms or refutes this before touching the
     3 consumer files, per CONTEXT.md's own locked "measure first" instruction. This is not a
     planning blocker — it is a 10-minute verification task inside Wave 1.

2. **Does `test_ac_oracle.jl`'s EXACT-04 `@testitem` still pass, and for the RIGHT reason, under
   the corrected default?**
   - What we know: the full suite is GREEN at both Phase 26 and Phase 27 close (0 fail, 0 error),
     so the test's ASSERTIONS currently pass. The test's COMMENT describes a mechanism
     (cone-inexactness) that, per 26-FINDINGS, no longer holds under the default.
   - What's unclear: whether the assertions pass because of the alternative mechanism this
     research identified (restriction-suboptimality via `assert_ac_exact!`'s dispatch comparison)
     or some other reason not yet investigated.
   - Recommendation: RESOLVED for planning purposes — this is a documentation-accuracy task, not a
     code-correctness risk (the suite is already green). Task shape given above in "SOCP-Inexactness
     Dual-Notion Finding."

3. **Should `scripts/socp_applicability_sweep.jl` regenerate its precomputed CSVs under the
   default, `thesis_literal=true`, or both?**
   - What we know: the page's entire pedagogical point is characterizing exact/inexact regions;
     running under only the (now mostly-exact) default would make the page far less interesting
     and would not let it demonstrate the still-live inexactness the thesis-literal copy exhibits.
   - What's unclear: whether CONTEXT.md intends a full re-sweep under both (more thorough, more
     compute) or a single explicit `thesis_literal=true` re-run (cheaper, preserves the
     pedagogical point, matches the "restate as a property of the thesis-literal copy" framing).
   - Recommendation: RESOLVED — CONTEXT.md's own wording ("restate as a property of the
     thesis-literal copy") points toward running the demonstrative/"is it real" control points
     under `thesis_literal=true` explicitly (matching what Phase 26 Plan 26-18 already did for the
     `test_restricted_branch_flow.jl`/`test_mpc_loop.jl` re-forcing), while the BROADER
     applicability MAP (the full sweep across pv_scale/load_scale/vmax) is more valuable reporting
     BOTH classifications side by side, since that IS new, honest information about how the fix
     changed the map's shape. Leave the exact split as an implementation decision for the plan/
     executor, not a blocking research gap.

## Sources

### Primary (HIGH confidence — direct code/file read this session)
- `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/28-CONTEXT.md` — locked decisions
- `.planning/REQUIREMENTS.md`, `.planning/STATE.md`, `.planning/PROJECT.md` — requirement text, phase history, current narrative
- `.planning/phases/26-network-device-model-correctness/26-GOLDEN-AUDIT.md`, `26-FINDINGS.md`
- `.planning/phases/27-integer-planning-pricing-certificate-correctness/27-GOLDEN-AUDIT.md`, `27-FINDINGS.md`
- `docs/literate/{thesis_reproduction_ieee123,thesis_reproduction_assumptions,convex_branch_flow,ac_oracle,restricted_branch_flow,socp_applicability,mpc_rolling_horizon,pricing_dlmp,stochastic_pv_demand}.jl` — direct read/grep this session
- `test/test_thesis_repro.jl`, `test/test_ac_oracle.jl`, `test/test_pricing_dlmp.jl` — direct read/grep this session
- `scripts/{repro_stability_check,thesis_case123_repro,thesis_caseA,demo_mpc_plots,socp_applicability_sweep}.jl` — direct read/grep this session
- `src/models/ac_oracle.jl`, `src/models/exactness.jl` — direct code read (the dual-notion-of-exactness finding)
- `docs/make.jl`, `.github/workflows/CI.yml`, `docs/Project.toml` — docs build mechanics
- `git diff 5939799..HEAD -- test/` (direct execution this session) — golden-move ground truth
- `git log`, `stat` on `results/*` artifacts — staleness dating

### Secondary (MEDIUM confidence)
- Project memory: `v2.1-socp-inexactness-and-thesis-repro.md`, `exactness-gate-hybrid-floor.md`,
  `background-suite-orphan-race.md`, `gsd-plan-verify-testitemrunner-trap.md`,
  `quality-audit-2026-09-28-defects.md`, `highs-exactness-defaults.md` — all cross-checked against
  the current code/docs this session, no contradictions found

### Tertiary (LOW confidence)
- None — this research relied entirely on direct repository inspection, no external/web sources
  were needed (the domain is entirely internal project history and code).

## Metadata

**Confidence breakdown:**
- Golden audit script design: HIGH — pattern directly verified against real diffs this session
- REPRO-01 pipeline inventory: HIGH — every file/timing claim verified by direct read or `git log`/`stat`
- SOCP-inexactness dual-notion finding: HIGH (code-level mechanism confirmed by reading both
  `assert_socp_exact!` and `assert_ac_exact!`'s actual bodies) but the SPECIFIC claim "test_ac_oracle.jl's
  assertions still pass for the alternative reason" is a plausible, well-supported HYPOTHESIS, not
  independently re-run this session — flagged as Open Question 2, resolved into a measurement task
- MPC/DLMP restatement: HIGH — DLMP closure confirmed complete by direct read; MPC gap confirmed by grep

**Research date:** 2026-09-29
**Valid until:** short — this research is tied to the exact commit `8a96361`/base `5939799`; any
further commits to `test/`, `docs/literate/`, or `scripts/` before Phase 28 executes should
prompt a quick re-verification of the file-staleness claims (re-run the `stat`/`grep` checks in
this document) rather than trusting them indefinitely. 7 days is a reasonable outer bound given
this is an actively-developed repo with near-daily phase commits.

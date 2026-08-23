---
quick_id: 260823-gea
description: Close the two owed v2.1 Phase-18 corrections — re-derive Plan 18-02's golden band from a fresh measurement (not a hardcoded note value), and split repro_stability_check.jl's try/catch per stage + thread the optimizer kwarg
date: 2026-08-23
mode: quick
---

# Quick Task 260823-gea: Close the two owed v2.1 Phase-18 corrections

## Why

STATE.md's "[v2.1 Phase 18 REFUTED — corrections owed]" blocker names two outstanding items from
quick task `260726-mo7` (which added the `optimizer` kwarg to `fit_baseline` and, as a side effect,
proved the whole population-scale sweep now solves 5/5 instead of 1/5 at `tol_gap = 1e-10`):

- **(4)** Plan 18-02's golden band (`DSO_BAND_HI = 5.58855710237937` in `test/test_thesis_repro.jl`)
  was derived as `1.5 × max|dso|` over "successfully-solved points" — which was 1 point at the time.
  With 5 solving, the rule and the pinned value now disagree. The test still passes (never broken),
  but the rule and the number it's supposed to justify no longer match.
- **(5)** `scripts/repro_stability_check.jl` wraps `solve_welfare` + `welfare_accounting` +
  `fit_baseline` in ONE `try/catch` per point, which is *why* spike 003 found Phase 18-01
  misattributed 2 of 4 sweep failures to the wrong function. It also has no `optimizer` kwarg, so it
  cannot be re-run at a tightened tolerance without editing source.

**Sequencing decision (item 4 depends on item 5's fix):** rather than hardcoding the `7.211` implied
by the note in STATE.md/socp-validity-envelope.md (which would be exactly the "certificate
laundering" pattern this project's standing bar forbids — a pinned number with no fresh measurement
behind it), Task A fixes the script first, then Task B uses the FIXED script to re-run the sweep at
`tol_gap = 1e-10` and pins whatever `max|dso|` that fresh, honestly-attributed run actually produces.
This is measurement-before-golden done properly, the same discipline Plan 18-01 itself was built on,
using the corrected tooling instead of reusing a number from a prior spike's throwaway script.

## Context

- `scripts/repro_stability_check.jl` — the script both items touch. Read in full already; key pieces:
  - Header comment (L1-33) narrates the two measurements (flake rate + population sweep) and the
    `Phase7Fixtures` re-implementation-inline rationale.
  - `count_failures` (L216-249): one `try/catch` wraps `solve_welfare` → `welfare_accounting` →
    `fit_baseline`, incrementing a single `failures` counter with no stage attribution.
  - `sweep_population_scale` (L251-330): same three-call chain in one `try/catch` per swept `δ`;
    pushes `(; δ, failed::Bool, dso, fit_dso, prosumer, fit_prosumer, socp_maxgap, error_msg)`.
  - Run section (L332-363): builds the population once, calls both functions, computes
    `sign_flip_survives`, `dso_band_lo = 0.0`, `dso_band_hi = 1.5 * maximum(abs(r.dso) for r in
    successful)` where `successful = filter(r -> !r.failed, results)` (L357-359).
  - Findings writer (L365-499): writes `results/repro_stability_check/findings.txt`, including a
    "Failed-point error detail" section (L431-437) and a `RECOMMENDED BAND:` line printed TWICE —
    once via `@printf("...%.6f...")` (L363, 6-decimal truncated) and once via
    `println(io, "RECOMMENDED BAND: DSO_BAND_LO=$(dso_band_lo), DSO_BAND_HI=$(dso_band_hi)")`
    (L496, full `Float64` string-interpolation precision — this is how the currently-pinned
    `5.58855710237937` got its 15-digit precision; the `%.6f` line was never the source).
  - No `using JuMP`/`using Clarabel` currently; no `optimizer` kwarg anywhere.
- `src/pricing/fit.jl` (`fit_baseline`, L287-): the established pattern to mirror exactly —
  `optimizer = select_optimizer(problem_class(pf))` as the kwarg default (byte-identical default
  path), threaded into every internal solve site.
- `src/models/welfare_solve.jl` (`solve_welfare`, L99-): already has an `optimizer` kwarg with the
  same default-factory pattern — nothing to change here, just consume it.
- `.planning/spikes/003-phase18-fragility-tolerance/check.jl` (L35-36, L184-190) — the validated
  precedent for building a tight-tolerance optimizer in a standalone script: `using JuMP`,
  `using Clarabel`, then
  `optimizer_with_attributes(Clarabel.Optimizer, "verbose" => false, "tol_gap_abs" => tol,
  "tol_gap_rel" => tol)`. Reuse this exact attribute pair for consistency with the already-validated
  spike numbers.
- `test/test_thesis_repro.jl` — the pin. Header comment (L19-28) and in-`@testitem` comment (L36) both
  hardcode `5.58855710237937` and both narrate now-superseded provenance:
  - L19-22 "GOLDEN BAND PROVENANCE" says the band is copied from Plan 18-01's *original* findings.txt.
  - L26-28 says "18-01's `sign_flip_survives=false` finding concerns ONLY the ±2%/±5% sweep (all 4
    non-zero points FAIL the SOCP-exactness gate outright)" — this is now KNOWN FALSE (spike 003 /
    mo7: the sweep is 5/5 and the sign flip holds at every point). This sits immediately next to the
    band comment this task is already rewriting; leaving it would recreate the exact staleness this
    task exists to close, in the same file, two lines away. Fix it in the same edit.
  - The `@test DSO_BAND_LO < acct.dso < DSO_BAND_HI` assertion itself (L66) is untouched — only the
    constant and its narrating comments change.
- `docs/literate/thesis_reproduction_assumptions.jl` (L172-177) — the prose this task must stop being
  stale: "...the band should be re-derived deliberately" (L177) becomes false once Task B lands.
- `.planning/reports/MILESTONE_SUMMARY-v2.1.md` (~L101) — "the DSO-surplus band [0.0, 5.5886] derives
  only from the point that solved exactly" is stale on two counts after this task: the value changes,
  and it now derives from the max over 5 solved points, not 1.
- `.planning/notes/socp-validity-envelope.md` (~L270-272) — item 4 of its "still owed" list narrates
  "the rule now implies 7.211 against a pinned 5.5886" as an open item; mark it resolved with the
  actual final value.
- `.planning/STATE.md` (~L235-238) — the blocker bullet's two `⬜ OWED` markers for items (4) and (5).
  **Scope note:** flip ONLY the two checkbox glyphs (`⬜` → `✅`); do not reword the surrounding
  numbers/prose in that bullet — it is a historical record of what was true when spike 003 ran, and
  the orchestrator owns the quick-task table elsewhere in STATE.md.

**Out of scope (deliberately not touched — historical point-in-time records, already carrying their
own "[CORRECTED ...]" annotation layers per this repo's established convention rather than being
rewritten):** `.planning/milestones/v2.1-phases/18-directional-thesis-reproduction/18-01-SUMMARY.md`,
`18-VERIFICATION.md`, `.planning/MILESTONES.md`, `.planning/spikes/003-phase18-fragility-tolerance/
README.md`, and the other quick tasks' own committed PLAN/SUMMARY files. `docs/src/generated/
thesis_reproduction_assumptions.md` is Literate.jl-generated output — not hand-edited; it resyncs on
the next `docs/make.jl` build.

## Tasks

### Task A — split `repro_stability_check.jl`'s try/catch per stage and thread the `optimizer` kwarg

- **files:** `scripts/repro_stability_check.jl`
- **action:**
  1. Add `using JuMP` and `using Clarabel` to the `using` block (after `using TSODSO`, L37).
  2. Add a module-level configurable optimizer, read once at the top near the existing config
     constants (after L55): parse an optional `REPRO_TOL_GAP` environment variable
     (`get(ENV, "REPRO_TOL_GAP", nothing)`); if present, `parse(Float64, ...)` it and build
     `optimizer_with_attributes(Clarabel.Optimizer, "verbose" => false, "tol_gap_abs" => tol,
     "tol_gap_rel" => tol)` (same attribute pair as spike 003's `check.jl`); if absent, the constant
     is `nothing`. Name it `const REPRO_OPTIMIZER = ...`. When `nothing`, the default path must stay
     byte-for-byte the current behavior — never pass an `optimizer` kwarg downstream in that case.
  3. Give `count_failures` and `sweep_population_scale` both a new `optimizer = nothing` keyword
     parameter. Inside each, compute `opt_kwargs = optimizer === nothing ? NamedTuple() :
     (; optimizer)` once, and splat `opt_kwargs...` into every `solve_welfare(...)` and
     `fit_baseline(...)` call inside that function (not into `welfare_accounting`, which takes no
     optimizer). This mirrors `fit_baseline`'s and `solve_welfare`'s own "only compute/pass the
     override when the caller actually gave one" discipline (INFRA-02).
  4. Split `count_failures`'s single `try/catch` (L228-247) into three sequential per-stage
     `try/catch` blocks per repeat: stage 1 `solve_welfare`, stage 2 `welfare_accounting`, stage 3
     `fit_baseline`. If stage 1 throws, skip stages 2-3 for that repeat (same short-circuit semantics
     as today, since stage 2/3 need stage 1's output) and record which stage failed. Change the
     return type from a bare `Int` to a `NamedTuple`: `(; failures::Int, by_stage::Dict{Symbol,Int})`
     with keys `:solve_welfare`, `:welfare_accounting`, `:fit_baseline` all present (zero-initialized)
     so the caller can report a breakdown even when some stages never failed. Keep the existing
     `@warn "stability measurement failed" repeat = i exception = (e, catch_backtrace())` per
     failure, adding `stage = <symbol>` to the `@warn` kwargs.
  5. Split `sweep_population_scale`'s single `try/catch` (L287-327) the same way: three sequential
     per-stage `try/catch` blocks per swept `δ`, short-circuiting to skip later stages once one fails.
     Replace the `failed::Bool` field in the pushed `NamedTuple` with `failed_stage::Symbol` —
     `:none` when the point fully succeeded, else `:solve_welfare` / `:welfare_accounting` /
     `:fit_baseline`. Keep `error_msg` (empty string when `failed_stage == :none`). Update the
     `@warn "sweep point failed" δ exception = (...)` call to include `stage = <symbol>`.
  6. Update every downstream consumer of the old `failed`/`failures` shapes in the Run and
     findings-writer sections (L332-499): `any_failed = any(r -> r.failed_stage != :none, results)`;
     `successful = filter(r -> r.failed_stage == :none, results)`; the sweep-table printer's
     `if r.failed` branch should print the stage name (e.g. `"FAILED(solve_welfare)"` in the `dso`
     column instead of bare `"FAILED"`); the "Failed-point error detail" loop should print
     `"  δ=$(r.δ) [$(r.failed_stage)]: $(r.error_msg)"`; the flake-rate section should additionally
     report the `by_stage` breakdown from `count_failures`'s new return value (e.g.
     `"failures_by_stage = $(cf.by_stage)"`) so a future misattribution is structurally impossible to
     reintroduce.
  7. Update the Run-section call sites (L339-350) to pass `optimizer = REPRO_OPTIMIZER` to both
     `count_failures(...)` and `sweep_population_scale(...)`.
  8. Update the module header comment (L1-33) to note: the per-stage split (citing spike 003 Finding
     1's misattribution as the reason), the new `REPRO_TOL_GAP` env var and its default (unset =
     today's tolerance, unchanged), and that this fix is quick task `260823-gea`.
- **verify:**
  <automated>
  Default-path regression check (no `REPRO_TOL_GAP` set) reusing the script's own functions without
  paying the full 20-repeat flake measurement: `julia --project=. -e 'include("scripts/
  repro_stability_check.jl")'` up through the point where it would normally run — since the script
  has no `main()` guard, instead write a throwaway scratchpad script that
  `include_string`s the script's source with the trailing "Run" + "Committed findings artifact"
  sections (everything from the `println("Building IEEE-123 population...")` line onward) stripped,
  matching the `260822-hld` precedent for exercising a script's internals without its side effects,
  then calls: `sweep_population_scale(ieee123_modified(); deltas = (0.0,))` and asserts the single
  returned row has `failed_stage == :none` and `dso` within 1e-6 of the previously-committed default
  `dso = 3.725705` (equivalence control — proves the per-stage split didn't change the default
  numeric path). Then call the SAME with `deltas = (0.0,)` and `optimizer =
  optimizer_with_attributes(Clarabel.Optimizer, "tol_gap_abs" => 1e-10, "tol_gap_rel" => 1e-10)` and
  assert `socp_maxgap` is smaller than the default-tolerance run's (proves the kwarg is actually
  consumed, not silently ignored — mirrors `260726-mo7`'s own "caller optimizer actually consumed"
  test).
  </automated>
- **done:** both functions accept and thread `optimizer`; both try/catch blocks are split so a
  failure is attributable to exactly one of `solve_welfare`/`welfare_accounting`/`fit_baseline`; the
  default (`REPRO_TOL_GAP` unset) path is numerically unchanged; passing a tightened optimizer
  measurably tightens `socp_maxgap`.

### Task B — re-measure `max|dso|` under the corrected tolerance and re-derive the golden band

- **files:** `test/test_thesis_repro.jl`, `results/repro_stability_check/findings.txt`
- **action:**
  1. Run the now-fixed script at the tolerance spike 003 validated: `REPRO_TOL_GAP=1e-10 julia
     --project=. scripts/repro_stability_check.jl`. This regenerates `results/
     repro_stability_check/findings.txt` in place (expected: it overwrites the manually-added
     "!!! CORRECTION !!!" banner block from the earlier quick-task fix — this is expected and
     correct, per that banner's own closing note: "Re-running that script OVERWRITES this correction
     block... Until then this correction lives in git history"; the freshly-generated file, with
     correct per-stage attribution built in from Task A, supersedes the manual banner honestly).
  2. Confirm the new findings.txt shows 5/5 points with `failed_stage == :none`
     (no `FAILED(...)` cells in the sweep table) and `sign_flip_survives: true`. If any point fails
     at `tol_gap = 1e-10`, STOP — do not proceed to step 3 with a partial band; this would mean the
     spike 003 result did not reproduce and needs investigation before any golden is touched.
  3. Extract the exact `DSO_BAND_HI` value from findings.txt's `println(io, "RECOMMENDED BAND:
     DSO_BAND_LO=$(dso_band_lo), DSO_BAND_HI=$(dso_band_hi)")` line near the end of the file (full
     `Float64` precision, NOT the earlier `%.6f`-truncated line) — this is the freshly-measured
     `1.5 × max|dso|` over the 5 successfully-solved points, computed by the corrected script, not a
     value copied from a prior note or spike log.
  4. In `test/test_thesis_repro.jl`, replace `const DSO_BAND_HI = 5.58855710237937` (L38) with the
     freshly-extracted value, and the inline comment at L36
     ("-- DSO_BAND_LO=0.0, DSO_BAND_HI=5.58855710237937 -- copied verbatim, never invented here")
     with the new value. Keep `DSO_BAND_LO = 0.0` unchanged (still the sign gate, per L357 of the
     script — unaffected by this re-measurement).
  5. Rewrite the "GOLDEN BAND PROVENANCE (threat T-18-04)" comment block (L19-23) to state: the band
     is copied verbatim from the re-run `results/repro_stability_check/findings.txt`'s
     `RECOMMENDED BAND:` line, produced by quick task `260823-gea`'s re-measurement at
     `tol_gap = 1e-10` after fixing the script's per-stage attribution (superseding the original
     Plan 18-01 derivation, which used only 1 of 5 sweep points).
  6. Rewrite the adjacent stale paragraph (L24-28, "18-01's `sign_flip_survives=false` finding
     concerns ONLY the ±2%/±5% sweep...all 4 non-zero points FAIL the SOCP-exactness gate
     outright") — this is now known false. Replace with: the sign flip is confirmed at ALL 5 swept
     points (not just the exact pinned point), per `260726-mo7`/spike 003; the original 4-of-4
     "FAILED" recording was a solver-tolerance artifact at the default `tol_gap = 1e-8`, not a
     physical boundary. The primary `@testitem`'s gates remain hard regardless — this correction is
     to the comment's narration, not the test logic.
- **verify:**
  <automated>
  `test_thesis_repro.jl` is a `@testitem` (TestItemRunner-only; per this project's own recorded trap,
  does not resolve under plain `--project=.` — do not attempt `julia --project=. test/
  test_thesis_repro.jl`). Write an inline equivalent instead, reusing the exact same call sequence
  the `@testitem` body makes: `julia --project=. -e 'using TSODSO; feeder = ieee123_modified(); ...
  build the same aggregators/λ0 the fixture uses via scripts/repro_stability_check.jl's
  build_ieee123_aggregators/ieee123_lambda0 (include the script with its trailing Run section
  stripped, as in Task A''s verify) ...; ctx, _, _ = solve_welfare(...); acct =
  welfare_accounting(ctx; T=24); fb = fit_baseline(...); fit_dso = fb.social_fit -
  fb.prosumer_surplus; @assert ctx.meta[:socp_maxgap] < 1e-5; @assert acct.dso > 0; @assert fit_dso <
  0; @assert acct.prosumer < fb.prosumer_surplus; @assert 0.0 < acct.dso < <new DSO_BAND_HI>'` and
  confirm every assertion passes with the NEW constant substituted in for the last one — proving the
  updated pin is both internally consistent (matches its own derivation) and does not break the
  existing gate-then-golden checks.
  </automated>
  If a full-suite confirmation is wanted afterward, run `julia --project=. -e 'import Pkg;
  Pkg.test()'` in the background (optional, not required for this task).
- **done:** `results/repro_stability_check/findings.txt` shows a fresh 5/5 run with correct per-stage
  attribution; `DSO_BAND_HI` in `test/test_thesis_repro.jl` is the value that findings.txt actually
  printed (never invented, never copied from a note); the two stale provenance/narration comments are
  rewritten to match; the inline equivalent of the `@testitem` still passes with the new band.

### Task C — update stale prose and flip the STATE.md checkboxes

- **files:** `docs/literate/thesis_reproduction_assumptions.jl`, `.planning/reports/
  MILESTONE_SUMMARY-v2.1.md`, `.planning/notes/socp-validity-envelope.md`, `.planning/STATE.md`
- **action:**
  1. In `docs/literate/thesis_reproduction_assumptions.jl` (L172-177), replace the paragraph "The
     golden magnitude band (`DSO_BAND_LO=0.0, DSO_BAND_HI=5.58855710237937`) pinned in `test/
     test_thesis_repro.jl` still PASSES (max observed `|dso| = 4.807417 < 5.5886`), but it was
     derived as `1.5 × max|dso|` over the then-single solved point; with five solving that rule now
     implies 7.211, so band and rule disagree and the band should be re-derived deliberately." with
     a version stating the band WAS re-derived by quick task `260823-gea`: the new
     `DSO_BAND_HI` value (from Task B), that it is `1.5 × max|dso|` over all 5 now-solving swept
     points (not 1), and that rule and value now agree. Also update the immediately-following
     paragraph (L186-189, "A future population re-tune should still re-run
     `scripts/repro_stability_check.jl` — but that script must first be fixed to split its
     three-solve `try/catch` and to thread the `optimizer` kwarg.") to state this fix already
     landed (`260823-gea`), so a future re-tune can re-run the script directly with no further
     prerequisite.
  2. In `.planning/reports/MILESTONE_SUMMARY-v2.1.md` (~L101), replace "the DSO-surplus band [0.0,
     5.5886] derives only from the point that solved exactly" with the corrected framing: the band
     derives from the max over the 5 points that now solve at `tol_gap = 1e-10` (re-measured by
     `260823-gea`), stating the new numeric value.
  3. In `.planning/notes/socp-validity-envelope.md` (~L270-272), update item 4 of the "v3.0 should be
     re-scoped..." list ("Re-deriving Plan 18-02's golden band, whose `1.5 × max|dso|` rule now
     implies 7.211 against a pinned 5.5886...") to state this item is RESOLVED by `260823-gea`, with
     the actual final pinned value (not 7.211 — use whatever Task B's fresh measurement produced,
     which may differ slightly from the spike's throwaway-script number since it now runs through
     the corrected, committed script).
  4. In `.planning/STATE.md`, locate the "[v2.1 Phase 18 REFUTED — corrections owed]" bullet
     (~L230-238) and change ONLY the two checkbox glyphs: `(4) ⬜ OWED` → `(4) ✅` and
     `(5) ⬜ OWED` → `(5) ✅`. Do not reword any other text in that bullet — it is a historical
     record of the spike 003 finding at the time it was written.
- **verify:**
  - `grep -n "should be re-derived deliberately" docs/literate/thesis_reproduction_assumptions.jl`
    returns no matches (the stale sentence is gone).
  - `grep -n "7.211" .planning/notes/socp-validity-envelope.md` — if still present, it must now read
    as resolved/historical, not as an open item (manually confirm the surrounding sentence, since
    grep alone can't distinguish "still owed" framing from "was resolved, previously computed as"
    framing).
  - `grep -n '(4) ✅\|(5) ✅' .planning/STATE.md` — both markers present in the Phase 18 blocker
    bullet.
- **done:** no file in the repo still asserts the band-vs-rule disagreement as a live, open
  discrepancy; STATE.md's two markers are flipped and nothing else in that bullet changed.

## Constraints

- Do not weaken, delete, or `broken=`-mark any assertion in `test/test_thesis_repro.jl`. The band may
  widen or narrow with the fresh measurement; the assertion structure stays exactly as-is.
- Do not hardcode `7.211` anywhere as the new golden value — it is the value implied by re-deriving
  the rule from the *previously recorded* spike-003 number (`4.807417`), which this plan deliberately
  does NOT use as the source of truth. The pinned value must come from Task B's own fresh run of the
  now-fixed, committed script — even if it turns out numerically close to `7.211`, it must be sourced
  from that run's findings.txt, not asserted from memory.
- Task A and Task B are sequential (B depends on A's fix); Task C can run after B lands (needs the
  final numeric value). Do not parallelize B and C — C quotes B's output value.
- If Task B's re-run does NOT reproduce spike 003's 5/5 result (e.g. a point throws at
  `tol_gap = 1e-10` today that didn't in the spike), stop and report this honestly rather than
  proceeding with a partial-coverage band — this would itself be a new finding worth surfacing, not
  silently working around.

## must_haves

- **truths:**
  - `scripts/repro_stability_check.jl` can be re-run at a chosen solver tolerance via
    `REPRO_TOL_GAP`, with the default (unset) path numerically unchanged from before this task.
  - A failure at any of the three solve stages (`solve_welfare`, `welfare_accounting`,
    `fit_baseline`) is now attributed to the specific stage that failed, both in-memory
    (`failed_stage`/`by_stage`) and in the committed `findings.txt`.
  - `test/test_thesis_repro.jl`'s `DSO_BAND_HI` is sourced from a fresh, honestly-attributed 5-point
    measurement produced by the fixed script — not copied from a note, spike log, or hand-computed
    from a previously-recorded number.
  - No file in the repo (outside the deliberately-excluded historical records) still narrates the
    band/rule disagreement, the stale `fit_baseline`-kwarg-missing caveat, or the false "4 of 5 sweep
    points fail outright" claim as current/open.
- **artifacts:**
  - `scripts/repro_stability_check.jl` — `optimizer` kwarg on `count_failures`/
    `sweep_population_scale`, per-stage `try/catch`, `REPRO_TOL_GAP` env-driven `REPRO_OPTIMIZER`.
  - `results/repro_stability_check/findings.txt` — freshly regenerated, 5/5 solving, per-stage
    attribution visible in the sweep table and failure detail sections.
  - `test/test_thesis_repro.jl` — updated `DSO_BAND_HI` constant and both provenance comments.
- **key_links:**
  - `scripts/repro_stability_check.jl`'s Run section → `count_failures(...; optimizer =
    REPRO_OPTIMIZER)` / `sweep_population_scale(...; optimizer = REPRO_OPTIMIZER)` →
    `solve_welfare(...; optimizer)` / `fit_baseline(...; optimizer)`.
  - `test/test_thesis_repro.jl`'s `DSO_BAND_HI` ← `results/repro_stability_check/findings.txt`'s
    `RECOMMENDED BAND:` line (full-precision `println` form), produced by the `REPRO_TOL_GAP=1e-10`
    run in Task B.

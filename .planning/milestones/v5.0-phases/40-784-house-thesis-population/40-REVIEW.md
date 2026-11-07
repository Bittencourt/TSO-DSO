---
phase: 40-784-house-thesis-population
reviewed: 2026-10-24T12:30:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - docs/make.jl
  - docs/literate/case_a_population.jl
  - scripts/case_a_agreement.jl
  - scripts/case_a_scaling.jl
  - scripts/run_case_a_scaling.sh
  - src/experiments/Scenario.jl
  - src/experiments/materialize.jl
  - test/expected_broken.txt
  - test/test_population_case_a.jl
  - test/test_population_case_a_agreement.jl
  - test/test_population_case_a_scaling.jl
findings:
  critical: 0
  warning: 3
  info: 5
  total: 8
status: clean
re_reviewed: 2026-10-24T18:45:00Z
re_review_iteration: fix loop 1/3 (WR-01, WR-02, WR-03 fixes verified: 5e6e286, cb0a962, bcff112)
re_review_depth: quick
re_review_files_reviewed_list:
  - src/experiments/materialize.jl
  - test/test_population_case_a.jl
  - test/test_population_case_a_scaling.jl
  - docs/literate/case_a_population.jl
---

# Phase 40: Code Review Report

**Reviewed:** 2026-10-24T12:30:00Z
**Depth:** standard
**Files Reviewed:** 11
**Status:** clean (re-review fix loop 1/3: WR-01/02/03 verified fixed — see Re-Review Addendum below)

## Summary

Reviewed the Phase-40 files at standard depth, with cross-file tracing into the called
`src/` seams (`solve_admm`, `_admm_certify`, `solve_welfare`, `extract_dlmp`,
`errors.jl`, `factory.jl`, `Deferrable`/`Aggregator` constructors, `runtests.jl` /
`runner_support.jl`) and against the committed measurement artifacts
(`results/case_a_population/*.csv`) and the `expected_broken.txt` guard.

What was verified positively (adversarially, not rubber-stamped):

- **Cross-engine price comparison is shape/ordering-correct.** `_admm_certify`
  (`src/admm/admm_phases.jl:455`) builds `λ_mat` in ascending-`load_nodes` order —
  exactly matching the agreement script's `extract_dlmp(ctx)[load_buses, :]` row
  subset with `load_buses = sort!([a.bus for a in aggs])`. Both are `(10, T)`.
- **Exception-recording contracts match the source.** `CertificateError` carries
  `kind::Symbol` + `iterations::Union{Nothing,Int}`; `ConvergenceError` carries
  `iterations`; `solve_admm` attaches `residuals.iters` to a final-consolidation
  refusal — so the scripts' `err.iterations === nothing ? -1 : Int(err.iterations)`
  and `err.kind` reads are valid on every recorded path. `:budget_exceeded` is a
  RETURN (not a throw) with `welfare = nothing` → `num_or_missing` → empty CSV cell,
  exactly as the docs page claims.
- **`select_optimizer(SOCP(); tol_gap_abs/rel = 1e-10)`** is the sanctioned kwargs
  override path (`factory.jl:138-144`, layered on the 1e-8 base); the gate itself is
  never touched anywhere in the diff — the honesty policy holds.
- **`expected_broken.txt` skip allowlist matches the `@test_skip` string exactly**
  (including the `10x` spelling), and the guard keys on `(kind, file, item,
  string(orig_expr))` — the tracked skip cannot silently rot or fail spuriously.
- **Docs page figures match the committed CSVs** (ladder iters 2/4/5/5/91/80, rung
  house counts 4×79+6×78=784, sweep walls 593/478/411 s, agreement row
  `tol_gap_1e-10` / `error:CertificateError` / 80 iters / empty band cells), and the
  composition numbers are computed live from the deterministic build (build-only —
  no solves at docs time, as `make.jl` claims).
- **`:default` byte-identical policy holds:** the `:case_a_784` code is strictly
  additive in `materialize.jl`/`Scenario.jl`; `_default_house` and the `:default`
  branch are untouched; `SCENARIO_VALID_POPULATIONS` widening only adds a member.
- **The scaling test's T ≥ 9 floor claim is arithmetic-verified:** `Deferrable(bus,
  t_start, t_end, E, Pmax, b)` with `E = 1.0·ds`, `Pmax = 0.5·ds` requires
  `min(16,T) − min(8,T) + 1 ≥ 2` ⇒ T ≥ 9; T = 10 in the test is safe.
- **`run_case_a_scaling.sh`** propagates every nonzero exit (`|| exit $?`), has no
  silent fallback, and the per-leg `-t N` + `--threads N` pairing matches the
  script's fail-loud process/thread cross-check.

No Critical (correctness/security) defects were found. Three Warnings (an unused,
docstring-misrepresented API parameter; fast-lane CI runtime; a docs-build fragility
against a growth-by-design CSV) and five Info items follow.

## Warnings

### WR-01: `case_a_household_map`'s `seed` argument is never used, and its docstring claims it is

**File:** `src/experiments/materialize.jl:717-759` (docstring claim at 706-711)
**Issue:** The `seed::Integer` parameter is not referenced anywhere in the function
body — the map is fully seed-independent (rows derive only from `_load_buses`,
`_case_a_house_counts`, and `_case_a_pv_group`). Yet the docstring states the map
"derives everything from the SAME primitives ... `_case_a_house_seed`, ..." and
frames the seed argument as part of that derivation. Consequences: (a) the
documented "single source of truth / cannot drift" contract is overstated for the
seeding dimension (nothing about seeding is encoded, so nothing could drift — but a
reader is told otherwise); (b) callers are invited to believe the map varies with
seed (`case_a_household_map(feeder, :ieee13, 42) == case_a_household_map(feeder,
:ieee13, 999)` is TRUE today). A Phase-41 consumer keying settlement groups on this
argument would silently get seed-independent data; the tests cannot catch this
because they only exercise the same-seed purity and field shapes. The docs page
(`docs/literate/case_a_population.jl:92`) passes `s_pop` — reinforcing the wrong
impression.
**Fix:** Either (preferred, no call-site churn) keep the signature but document
seed-independence explicitly and mark the argument as accepted-for-call-symmetry —
e.g. rename to `seed_unused` or add `!_` suffix with a docstring line: "`seed` is
accepted for call-site symmetry but NOT used: the map encodes only assignment
structure (bus / house_index / pv_group), never profile draws, so it is identical
for every seed" — and correct the primitive list to drop `_case_a_house_seed`. Or
actually consume the seed (e.g., assert it equals a sub_seed-derived population
seed) if seed-coupling was intended.

### WR-02: "Fast lane" scaling smoke runs two full-scale ADMM solves (up to ~240 s) in the default CI lane

**File:** `test/test_population_case_a_scaling.jl:82-178` (solve + cap at 157-167)
**Issue:** Item 2 is tagged `[:population]` only (no `:slow`), so it runs in both
the default and the `fast` test set (`runner_support.jl:56`:
`(set == "slow") == (:slow in ti.tags)`). It builds all 784 houses and solves TWO
real serial ADMM problems — rung 0.5 (390 houses) and rung 1.0 (784 houses) at
T = 10 — each under `time_limit_s = 120.0`, and explicitly accepts
`:budget_exceeded` as a recorded status, i.e. the design anticipates the cap
firing. Committed evidence (`scaling_ladder.csv`: full rung = 80 iterations / 508 s
at T = 24) implies the 1.0-rung at T = 10 will consume the full 120 s cap per rung
on a slower CI runner — ~4 minutes of solver time inside the lane whose sibling
file's header advertises "the fast suite stays fast". This erodes CI timeout
margins and the fast/slow contract the phase itself established.
**Fix:** Any one of: (a) shrink the in-suite rungs (e.g. fractions `0.125`/`0.25` —
90/190 houses, measured ~5-iteration convergence at T = 24) keeping the same
construction-path coverage; (b) lower `time_limit_s` to ~30 s so the worst case is
bounded near a minute; or (c) tag the item `tags = [:population, :slow]` (and
confirm the `expected_broken.txt` allowance is unaffected — it is, that file holds
no entry for this item).

### WR-03: Docs page `only(...)` on `agreement.csv` hard-fails the docs build the moment the CSV legitimately grows

**File:** `docs/literate/case_a_population.jl:242-246`
**Issue:** Both measurement scripts' `upsert_row` contract is explicitly multi-row:
rows are keyed on `(julia_version, seed, t_horizon)` and "re-runs replace their own
row and never drop others" — the design invites rows from a Julia-version bump or a
`--seed 43` re-measure. The docs page wraps the read in `only(...)`, so ANY second
row turns `makedocs` into an `ArgumentError` failure. The failure is loud (not a
correctness/silent-wrongness bug), but it couples the docs build to a
grow-by-design artifact: the next re-measure on a new Julia version breaks docs
until the page is hand-edited, which is exactly the kind of delayed build failure
`make.jl`'s own comments work hard to avoid.
**Fix:** Replace `only(read_case_a_csv(...))` with a provenance-keyed selection
matching the page's own stated row identity, e.g.:

```julia
agreement_rows = read_case_a_csv(joinpath(pkgdir(TSODSO), "results",
    "case_a_population", "agreement.csv"))
agreement = only(filter(r -> r["seed"] == "42" && r["t_horizon"] == "24",
    agreement_rows))
```

(keeping the page's appended note naming `julia_version=1.12.5` as the recorded
row), so future rows keyed on other provenance don't break the build while the
page still fails loudly if the seed=42/T=24 row disappears.

## Info

### IN-01: `Scenario` constructor accepts `population = :case_a_784` with `feeder ≠ :ieee13`; rejection is deferred to materialization

**File:** `src/experiments/Scenario.jl:150-157` (guard), `src/experiments/materialize.jl:546-555` (deferred throw)
**Issue:** The inner constructor validates `population` in isolation; the
`:case_a_784` × `:ieee123` combination passes construction and only throws
`ArgumentError` when `_materialize` (`run.jl:61-73`) calls `build_population`. This
is fail-loud and tested, but it sits oddly with the file's own stated invariant
("a `Scenario` can never silently underdetermine a run" — a constructed
`Scenario` holding a known-impossible selector pair is exactly a delayed failure).
**Fix:** One-line cross-field check in the inner constructor:
`if population === :case_a_784 && feeder !== :ieee13 throw(ArgumentError(...)) end`
(mirroring the existing `strategy isa ADMM && !allow_export` cross-check at
`Scenario.jl:204-212`).

### IN-02: Measurement helpers duplicated verbatim across the two measurement scripts

**File:** `scripts/case_a_agreement.jl:86-129`, `scripts/case_a_scaling.jl:106-198`
**Issue:** `parse_kv_flag`, `num_or_missing`, and the entire `upsert_row`
(key-filter + `cols = :union` merge) are byte-identical copies in both scripts.
Any future fix to the upsert logic (e.g., key-column type handling after schema
evolution) must be applied twice and can silently diverge, breaking the
"re-runs replace their own rows" contract asymmetrically between the two CSVs.
**Fix:** Hoist into a shared `scripts/case_a_common.jl` (or a small unexported
module) included by both drivers.

### IN-03: `--threads` is parsed but silently ignored in ladder mode

**File:** `scripts/case_a_scaling.jl:132-134, 426-438`
**Issue:** `threads_declared` is validated against `Threads.nthreads()` only in
`sweep_main`; `julia -t 4 scripts/case_a_scaling.jl --mode ladder --threads 4`
accepts and ignores the flag, and the ladder rows would then record
`threads = 4` (from `Threads.nthreads()` at `case_a_scaling.jl:326`) for what the
comment-driven contract describes as a serial-only leg — a provenance column that
misdescribes the executor footing. Contrasts with the script's own fail-loud
misuse policy (the sweep's mismatch check at 359-367).
**Fix:** In ladder mode, throw `ArgumentError` when `threads_declared !== nothing`
(the ladder is serial-only by locked design), or at minimum validate
`Threads.nthreads() == 1` before running the ladder.

### IN-04: The agreement test's `DLMP_NOISE_BAND` provenance exists only as a prose comment, not a committed artifact

**File:** `test/test_population_case_a_agreement.jl:96-104`
**Issue:** The `1.99e-5` band is honestly gate-then-golden (10× the measured
deepest excursion 1.9893e-6), but unlike every other band in this phase (the
agreement band's home is `agreement.csv`, regenerated by a committed command), the
probe measurement behind `DLMP_NOISE_BAND` — "16/240 elements in
[-1.9893e-6, -1.0e-7]" — lives only in the header comment with no regeneration
command and no committed data. It cannot be re-audited or re-derived when the
solver/Julia version changes; the "recomputable from the probe measurement cited
in the header" claim depends on prose that can silently go stale.
**Fix:** Record the probe (min/percentile DLMP excursions at the midday hours) as
a row in `results/case_a_population/` with a regeneration command in the header —
the same pattern the agreement CSV itself establishes — or add the probe printout
to `scripts/case_a_agreement.jl`'s certified-leg output so re-measuring refreshes
the citation source.

### IN-05: Docs per-page size threshold raised a second time (now 1 MiB)

**File:** `docs/make.jl:65-75`
**Issue:** `size_threshold` was raised 200 → 600/400 KiB (commit dc0de79) and now
→ 1024/800 KiB because `api.md` organically grew to 676 KiB. The bump is
well-documented inline and scoped, but each raise permanently disables the
page-bloat signal for ALL pages, and the stated strategy ("headroom for further
growth") guarantees a third raise. The threshold exists to catch exactly this
growth pattern.
**Fix:** Next time the limit is approached, split `api.md`'s consolidated
`@autodocs` into per-section pages instead of raising again; the 1 MiB headroom
buys time to do that deliberately.

---

_Positive compliance notes (no action): the honesty policy is upheld end-to-end —
the battery-certificate refusal at full scale is recorded in `agreement.csv`
(empty band cells, `error:CertificateError` status), escalated in the test header,
and pinned as an allowlisted tracked skip rather than loosened; per-house seeding
uses `hash((s_pop, :house, bus, house_index))` with the `seed + bus` idiom
confined to the untouched `:default`/`_ieee8500` paths; and the TOL_GAP_PATH
`Symbol("tol_gap_1e-10")` construction correctly avoids the `:tol_gap_1e - 10`
parse trap the comment warns about._

_Reviewed: 2026-10-24T12:30:00Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_

## Re-Review Addendum (fix loop 1/3)

**Re-reviewed:** 2026-10-24T18:45:00Z · **Depth:** quick (fix-region verification only)
**Fix commits:** 5e6e286 (WR-01) · cb0a962 (WR-02) · bcff112 (WR-03)
**Scope:** the four fix-touched files only; the original report above is preserved verbatim (original status `issues_found`, 0 critical / 3 warning / 5 info — the five Info items are advisory and untouched by the fixes). Working tree clean at HEAD `bcff112`.

### Region 1 — WR-01 `seed_unused` rename breaks no caller — VERIFIED

- `src/experiments/materialize.jl:696,723-728`: positional parameter renamed `seed` → `seed_unused`; the body (729-766) never references it. In Julia a positional-parameter rename is invisible to callers (arguments bind by position).
- Full-repo grep for `case_a_household_map`: every call site passes the seed positionally — `docs/literate/case_a_population.jl:92`; `test/test_population_case_a.jl:51,205,206,216,250,268`. Zero `seed =` keyword calls exist anywhere (none are possible: the function declares no such keyword).
- Honesty restored: docstring (706-710) now states the argument is "NOT used ... identical for every seed" and drops `_case_a_house_seed` from the primitive list; the docs page adds the matching seed-independence comment (93-95). New test pins the documented contract: `@test m1 == case_a_household_map(feeder, :ieee13, 999)` (`test_population_case_a.jl:216`).

### Region 2 — WR-02 `:slow` tag move keeps `expected_broken.txt` semantics intact — VERIFIED

- `test/runner_support.jl:56`: `(set == "slow") == (:slow in ti.tags)` — the new item 3 (`tags = [:population, :slow]`, `test_population_case_a_scaling.jl:189-190`) is excluded from `TSODSO_TEST_SET=fast` and included in slow/all, so the fix is effective; filtered-out items never run and produce no Broken/skipped records (`runtests.jl:73-88`).
- No allowlist entry needed for the scaling file: `expected_broken.txt` holds no entry for `test_population_case_a_scaling.jl`, and neither scaling item contains `@test_broken`/`broken=`/`@test_skip` (all assertions positive) — the observed multiset is empty in every lane, so the item renames ("(fast smoke)" suffix; new "(slow)" item) cannot orphan any allowance.
- Agreement file untouched: `git diff --name-only b9b1db5..HEAD` lists exactly the four fix files; `test/test_population_case_a_agreement.jl` is not among them, so its existing allowance (`skipped | test_population_case_a_agreement.jl | population case_a_784: centralized-vs-ADMM agreement band at full scale (agreement) | ...`) still matches verbatim.
- Fast lane stays fast: tiny rungs 1/78 (10 houses) and 0.125 (90 houses) under a 60 s honesty cap; full-scale legs (0.5, 1.0) carry 120 s caps in the slow item only, header naming the exact slow-lane invocation. Soft-scope idiom respected in both items (`push!` mutation of top-level arrays inside `let` — no rebinding).

### Region 3 — WR-03 provenance filter selects exactly 1 recorded row, fails loud otherwise — VERIFIED

- `docs/literate/case_a_population.jl:255-260`: `only(filter(r -> r["seed"] == string(CASE_A_SEED) && r["t_horizon"] == string(T_HORIZON), agreement_rows))`.
- `results/case_a_population/agreement.csv` (columns `julia_version,seed,t_horizon,...`) holds exactly ONE recorded row (`1.12.5,42,24,...`) → the filter selects exactly 1 and `only` succeeds: the docs build works on the recorded data.
- 0 matches (row deleted) → `only` throws `ArgumentError` (loud); >1 matches (e.g. a newer-Julia re-measure adding a same-key row) → also throws (loud), explicitly documented at 249-254 as the honest outcome. Rows keyed on other provenance (a `--seed 43` re-measure, another horizon) are excluded without breaking the build — the grow-by-design CSV no longer breaks docs.
- Adjacent `only(filter(r -> r["executor"] == "serial", sweep))` (line 351) is pre-existing (untouched by bcff112), selects exactly 1 of the 3 recorded sweep rows, and fails loud otherwise — same policy, not a regression.

### Region 4 — No success-path / honesty regressions — VERIFIED

- WR-01 (5e6e286) is behavior-preserving: docstring/comments + the param rename + one new assertion; the map body is otherwise unchanged.
- WR-02 (cb0a962) is test-only: same construction path, same seeds/scales/ρ provenance; `:budget_exceeded` remains an accepted, documented recorded status — a structural assertion, never a performance claim.
- WR-03 (bcff112) is docs-selection-only: printed fields and the honest qualification paragraphs (certificate refusal, no pinned band, tracked skip, escalation) are unchanged (284-296); the trailing provenance note was updated consistently ("the row keyed `seed=42, t_horizon=24` (recorded on `julia_version=1.12.5`)").
- `:default` path untouched across all three commits: the diffs touch only the `:case_a_784` map signature/docstring, two test files, and the docs page — `_default_house` and the `:default`/`:ieee8500` branches are byte-identical.

**Verdict:** all three warnings verified fixed; frontmatter status set to `clean`. No new findings.

_Re-reviewed: 2026-10-24T18:45:00Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: quick (fix-region verification)_

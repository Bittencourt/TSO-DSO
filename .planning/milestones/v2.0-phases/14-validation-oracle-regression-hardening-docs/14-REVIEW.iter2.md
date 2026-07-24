---
phase: 14-validation-oracle-regression-hardening-docs
reviewed: 2026-07-24T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - test/fixtures_planning.jl
  - test/test_planning_goldens.jl
  - test/test_planning_noninteger.jl
  - test/test_planning_coupling.jl
  - test/test_planning_nash.jl
  - docs/src/api.md
  - docs/literate/stackelberg_benders.jl
  - docs/literate/nash_diagonalization.jl
  - docs/make.jl
findings:
  critical: 1
  warning: 3
  info: 4
  total: 8
status: issues_found
---

# Phase 14: Code Review Report

**Reviewed:** 2026-07-24
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Reviewed the PVAL-02 goldens infrastructure (`fixtures_planning.jl` + `test_planning_goldens.jl`), the PVAL-04 consolidated no-binaries guard with source-scan tripwire (`test_planning_noninteger.jl` plus cross-reference comments in `test_planning_coupling.jl`/`test_planning_nash.jl`), and the PVAL-03 docs deliverables (`api.md` Planning `@autodocs` block, two new Literate rung pages, `make.jl` wiring).

Verification performed beyond reading:
- **Both new literate pages were executed live** in the project environment. Rung 7 (`nash_diagonalization.jl`) converges to the hand-checked `z=[0.6,0.6]`, `x_inv=[0.3,0.3]` with probe spread ~4.4e-16 — page claims hold. Rung 6 (`stackelberg_benders.jl`) converges (`gap=2.9e-7`) but produces `UB = 17.755` and `z = 0.6985` — which exposes CR-01 below.
- **Gate-then-golden ordering is correct** in all three goldens testitems: the production gate (`result.gap <= 1e-6`, `result.converged`, probe `n_runs`/all-converged/summary-language) is asserted before any pinned value in every item. Golden values (`0.7/0.7/-0.245`, `[0.6,0.6]/[0.3,0.3]`, spread bounds `1e-4/1e-4/1e-3`) cross-check against `test_planning_certification.jl`'s `Y_HAND/Z_HAND/OBJ_HAND` and `test_planning_nash.jl`'s hand derivations.
- **Tripwire verified against current sources:** exactly four column-0 `function build_*(` definitions exist under `src/planning/` (follower.jl:94, subproblem.jl:110, coupling.jl:174, master.jl:92), matching the 4-key registry; no short-form or indented builder definitions currently exist. The false-negative risk is prospective (WR-01).
- **api.md `Order` fix is complete for the current codebase:** `RETRYABLE_STATUSES` (src/planning/retry.jl:33) is the only exported, docstring-bearing constant in the package, and the Planning Layer block's `Order = [:type, :constant, :function]` now surfaces it. Residual fragility in the other sections is WR-02.

Key concerns: the Rung 6 page's algebraic-substitution claim is stated incorrectly for objective-level quantities and the rendered page will show a self-contradictory leader cost (CR-01); the source-scan tripwire has several silent false-negative shapes (WR-01).

## Critical Issues

### CR-01: Rung 6 page's Deferrable-substitution equivalence claim is wrong for objective values — rendered `UB` (17.755) contradicts the page's own cited `-0.245`

**File:** `docs/literate/stackelberg_benders.jl:62-69, 122-124` (equivalence claim inherited verbatim by `docs/literate/nash_diagonalization.jl:70-73`)
**Issue:** The page argues the public `Deferrable` device reproduces "the SAME economics" as the test-only `ToyElasticDevice` because `U(p) = −(b/2)(p−E)²` "expands to `b·E·p − (b/2)·p²` (dropping the constant `-(b/2)E²` term, RESEARCH A5) — algebraically IDENTICAL to `a·p − (b/2)·p²` whenever `a = b·E`". Two defects:

1. **The implementation does NOT drop that constant.** `src/devices/Deferrable.jl:212` builds `utility = -(d.b/2)*(total_energy - d.E)^2` — the `−(b/2)E²` term is inherent to the squared form. (The "RESEARCH A5" citation is also misattributed: per Deferrable.jl's docstring, A5 sanctions dropping thesis eq. 3.12's separate constant `c`, not this expansion term.) The equivalence therefore holds only **up to an additive constant** `(b/2)E² = 18` on the welfare, i.e. `+18` on the leader's total cost (`cost_k = c_y·y + follower_cost − oracle_cost`, benders.jl:273).
2. **The rendered page is self-contradictory as a result.** The certification narrative (lines 44-48) cites "total cost `-0.245`"; the validation section then displays `result.UB` labeled "the leader's total cost at the incumbent" with no reconciliation. Verified by executing the page live: `UB = 17.75500113214901` (= −0.245 + 18 exactly). A thesis reader comparing the two numbers has no way to reconcile them from the text.

Secondary consequence (also verified live): the +18 offset inflates `|UB|`, and `solve_stackelberg!`'s relative gap normalizes by `max(1, |UB|)` (benders.jl:99) — so the same `tol = 1e-6` is effectively ~17.8× looser on this page's instance than on the certified fixture. The live solve stops at `z = 0.6985`, not ≈0.7000. Harmless for the page's "same ballpark" wording on `z`, but it directly contradicts "reproduces the SAME economics ... ECONOMICALLY EQUIVALENT" as an unqualified claim, and it is the kind of undocumented modeling nuance the project's constraints ("every model assumption documented") forbid.

**Fix:** State the equivalence precisely and reconcile the displayed UB. In `stackelberg_benders.jl`, amend the equivalence paragraph and the UB display, e.g.:

```julia
# ... `Deferrable`'s IMPLEMENTED utility keeps the `−(b/2)E²` constant (it is inherent in
# the squared form), so this instance is equivalent to the certified fixture UP TO AN
# ADDITIVE CONSTANT `(b/2)E² = 18` on the leader's total cost: the equilibrium point
# (`y*`, `z*`) and all prices/duals are IDENTICAL (constants never move an argmax), but
# every objective-level quantity is shifted by +18 — expect `UB ≈ -0.245 + 18 = 17.755`
# below, NOT the certified fixture's own `-0.245`. (The offset also enters the relative
# gap's `max(1, |UB|)` normalization, so the converged `z` here is a few 1e-3 from 0.7.)

result.UB          # ≈ 17.755 = certified -0.245 + (b/2)E²

# The offset-corrected leader cost, directly comparable to the certified -0.245:
result.UB - 0.5 * 6.0^2 * 1.0
```

Apply the same one-sentence qualification to the substitution paragraph in `nash_diagonalization.jl:70-73` (that page displays no objective values, so only the wording needs the fix).

## Warnings

### WR-01: Source-scan tripwire has silent false-negative shapes — a future builder can slip past the no-binaries guard

**File:** `test/test_planning_noninteger.jl:72-81`
**Issue:** The tripwire's stated purpose (T-14-04) is that "a future new builder file/function cannot silently ship without this guard", but the scan `match(r"^function (build_\w+)\(", line)` over `readdir(planning_dir)` misses at least four legal ways to add a builder, in each of which `found == Set(keys(registry))` still passes and the new builder ships unguarded:
1. **Short-form definition:** `build_expansion(; kwargs...) = ...` — no `function` keyword.
2. **Indented definition:** any `function build_*` not at column 0 (e.g. inside a `module`, `if`, or `@static` block) — the `^` anchor misses it.
3. **Subdirectory:** `readdir` is non-recursive; `src/planning/expansion/new.jl` is never scanned.
4. **Outside `src/planning/`:** a builder added to another `src/` subtree (the guard's scope is stated as src/planning, but nothing fails loudly if a planning-layer builder lands elsewhere).

(Verified none of these shapes exist today — all four current builders are long-form at column 0 in flat `src/planning/*.jl` — so the guard is currently sound; the risk is exactly the future-regression case it exists for.)
**Fix:** Harden with a second, syntax-independent detection channel and widen the scan:

```julia
# 1. Recursive + short-form-tolerant scan:
for (root, _, files) in walkdir(planning_dir), fname in files
    endswith(fname, ".jl") || continue
    for line in eachline(joinpath(root, fname))
        m = match(r"^\s*(?:function\s+)?(build_\w+)\s*\(", line)
        m !== nothing && push!(found, m.captures[1])
    end
end
# 2. Semantic union — any exported build_* symbol, regardless of syntax/location:
union!(found, filter(n -> startswith(n, "build_"), string.(names(TSODSO))))
@test found == Set(keys(registry))
```

Note the widened regex can false-positive on a bare call statement at line start — that failure mode is loud (test fails, registry inspected), which is the correct polarity for a tripwire.

### WR-02: `SMAX_NO_LIMIT` is exported, used by both new docs pages, but undocumented — and the non-Planning `@autodocs` sections would fail the build if it (or any other constant) ever gains a docstring

**File:** `docs/src/api.md:35-39` (Units section); `docs/make.jl:69-76`; `src/units/PerUnit.jl:69,145`
**Issue:** The Planning Layer `Order = [:type, :constant, :function]` fix is complete for the current codebase (`RETRYABLE_STATUSES` is the only exported docstring-bearing constant). However:
1. `SMAX_NO_LIMIT` is exported (PerUnit.jl:145) and now appears in the *public API surface the new literate pages teach* (`stackelberg_benders.jl:72`, `nash_diagonalization.jl:76`), yet it has no docstring anywhere — only a `#` comment block (PerUnit.jl:62-68). It is invisible in the rendered API reference.
2. `make.jl:72-74`'s comment claims "an undocumented/unsurfaced EXPORTED symbol now FAILS the build". That overstates `checkdocs = :exports`, which only flags *documented* exported symbols whose docstrings are not surfaced — an undocumented export (like `SMAX_NO_LIMIT`) passes silently, as it does today.
3. Latent build break: the moment anyone converts `SMAX_NO_LIMIT`'s comment into a docstring (the natural fix for point 1), the Units section's `Order = [:type, :function]` will exclude it and `checkdocs = :exports` will then fail the docs build — a delayed, non-obvious failure.
**Fix:** (a) Promote `SMAX_NO_LIMIT`'s comment block to a docstring; (b) add `:constant` to the Units section's `Order` (or uniformly to all `@autodocs` blocks in api.md — it is a no-op for sections with no documented constants and removes the entire class of delayed failure); (c) correct the `make.jl` comment to say `checkdocs` catches *documented-but-unsurfaced* exports.

### WR-03: New docs pages emit repeated JLD2 warnings (and occasional raw HiGHS logs) during execution — noise that lands in the Documenter build output for the two new `@example`-executing pages

**File:** `docs/literate/stackelberg_benders.jl:90-101`, `docs/literate/nash_diagonalization.jl:107-114,155-163` (root cause: `src/planning/checkpoint.jl:56` `@tagsave`, out of this review's file scope)
**Issue:** Verified by live execution of both pages: every `checkpoint_iteration!` call emits `┌ Warning: you passed a key as a symbol instead of a string ... @ JLD2` (DrWatson `@tagsave` passing `Symbol` keys), and at least one solver invocation prints a raw HiGHS log block (`Objective value ... HiGHS run time`) to stdout. Under `Literate.DocumenterFlavor()`, the solve blocks are `@example` blocks whose captured output Documenter renders — the Rung 7 page runs `run_nash!` plus a 6-run `run_nash_probe` (dozens of checkpointed Benders iterations), so the published pages and/or `makedocs` log will carry this repeated noise, degrading the thesis-grade docs this project treats as a hard requirement.
**Fix:** Short-term, wrap the solve calls' checkpoint noise out of the rendered output (e.g. `redirect_stdio`/`with_logger(NullLogger())` inside the example block, or Literate `#hide` on a wrapper). Correct fix: in `src/planning/checkpoint.jl`, pass string keys to the `@tagsave` payload dict (silences the JLD2 warning at its source, benefiting tests and docs alike), and ensure the retry ladder re-silences the solver on escalation.

## Info

### IN-01: Unused `using TSODSO` in `PlanningFixtures`

**File:** `test/fixtures_planning.jl:12`
**Issue:** The `@testmodule` contains only plain numeric `const`s and references no `TSODSO` symbol; the import is dead (and slightly undermines the file's own "DEFINES data only" contract comment by implying a dependency it doesn't have).
**Fix:** Delete `using TSODSO`.

### IN-02: The "gates" in the goldens testitems are tautological — they can never fail on a returned result

**File:** `test/test_planning_goldens.jl:50, 92, 146-149`
**Issue:** `solve_stackelberg!` only returns when `gap ≤ tol` (it raises `ErrorException` on `max_iter` exhaustion — benders.jl:126), and `run_nash!` likewise raises on `max_sweeps` exhaustion (pinned by test_planning_nash.jl's own "raises loudly" item), so `@test result.gap <= 1e-6` and `@test result.converged` cannot fail when reached. They are documentation-only assertions; the real gate is the absence of an exception. Harmless (and consistent with the stated gate-then-golden convention), but nobody should believe they add protection beyond the entrypoints' own raise-on-failure contract.
**Fix:** None required; optionally note the tautology in the comment so a future reader doesn't weaken the entrypoints' raise-on-exhaustion contract believing the test gate would catch it.

### IN-03: The goldens probe testitem re-executes the identical 6-run probe already run by `test_planning_nash.jl` — duplicated fixture literals, drift risk

**File:** `test/test_planning_goldens.jl:99-157` vs `test/test_planning_nash.jl:622-673`
**Issue:** The two items share verbatim fixture literals (specs, seeds, orders, tolerances) and identical gating assertions; only the spread-bound checks are new. The file header's "consolidates without duplicating" holds for the certification, but the probe run itself is now executed twice per suite with two hand-maintained copies of the same fixture — a silent-drift risk (e.g. one copy's seed tuple edited, the other not) rather than a correctness bug.
**Fix:** Consider moving the shared probe fixture literals (seeds/orders/builder kwargs) into `PlanningFixtures` so both items consume one definition; or fold the spread bounds into the existing nash probe item with a cross-reference from the goldens file.

### IN-04: The pinned probe-spread bounds mostly regress numerical noise — the z0 seed dimension is structurally inert on this fixture

**File:** `test/fixtures_planning.jl:32-53`
**Issue:** The fixture comment attributes the ~1e-16 observed spread to the fixture being "fully-symmetric". The stronger, documented reason is `test_planning_nash.jl`'s own WR-05 analysis (lines 900-911): with the derived-default `x_inv0 = z0/corridor_cap` at `T = 1`, a seeded neighbor's consumption and seeded headroom cancel *exactly* in the pooled capacity row, so every z0 seed yields the cold run's sweep-1 feasible set — the probe's seed dimension cannot produce spread on this fixture even in principle (only the order dimension and solver noise remain). The bounds are therefore a valid noise-floor tripwire (verified live: spread 4.4e-16 ≤ 1e-4) but not a seed-sensitivity regression, and the comment's rationale slightly overstates what they pin.
**Fix:** Add one sentence to the bound-derivation comment citing the WR-05 cancellation, so a future reader doesn't interpret the tiny spread as evidence the probe explored genuinely distinct basins.

---

_Reviewed: 2026-07-24_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

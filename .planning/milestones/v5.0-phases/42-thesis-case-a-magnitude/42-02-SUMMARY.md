---
phase: 42-thesis-case-a-magnitude
plan: 02
subsystem: settlement-comparison
tags: [compare-tariffs, agr-optimizer, passthrough-seam, byte-identical-default, julia, tdd]

# Dependency graph
requires:
  - phase: 40-case-a-population
    provides: solve_admm's documented agr_optimizer seam (the receiving end; default nothing = plain select_optimizer(QP()) factory, BYTE-IDENTICAL)
  - phase: 41-settlement-tariffs
    provides: compare_tariffs' fit_optimizer/time_limit_s passthrough precedent (the signature convention mirrored)
  - plan: 42-01
    provides: the pre-registered protocol (ladder mechanism this seam carries) and the wave-1 guard/gain helpers
provides:
  - compare_tariffs(…; agr_optimizer = nothing) — ONE additive passthrough threading the AGR optimizer factory verbatim into the engine = :admm solve_admm call; default byte-identical
  - 2 structural test items in test/test_settlement.jl encoding default-equivalence (explicit factory and explicit nothing vs the kwarg-less call, bitwise)
affects: [42-03/42-04 (runner passes the certified rung's optimizer through), 42-05 (writeup reports the 784-house settlement lenses), 42-06 (reproducibility band)]

# Tech tracking
tech-stack:
  added: []   # zero new packages (threat register T-42-02-SC: empty by construction)
  patterns: [additive-kwarg-passthrough, unconditional-nothing-forwarding, default-equivalence-testing]

key-files:
  created: []
  modified:
    - src/settlement/comparison.jl
    - test/test_settlement.jl

key-decisions:
  - "Option B resolved as planned: ONE additive kwarg agr_optimizer = nothing on compare_tariffs; exactness gate, battery τ, and ρ NOT exposed (they remain untouched)"
  - "Forwarding shape: the engine = :admm if/else collapsed to ONE unconditional solve_admm call forwarding BOTH agr_optimizer and time_limit_s — each defaults to nothing and solve_admm treats nothing as its own default, so the single call is byte-identical to both pre-seam branches (chosen over extending both branches; one shape, not mixed)"
  - "Tests assert DEFAULT-EQUIVALENCE, never a magnitude: explicit select_optimizer(QP()) and explicit nothing vs the kwarg-less call, bitwise on welfare / total_payments / merchandising_surplus (the algebraically-exact class — same effective factory, same solve); no fixture welfare pinned (golden policy)"
  - "Test fixture = the file's existing small 2-bus DADP settlement fixture with the neighbor's explicit bins = [[1, 2], [3]] (default_tou_bins is 24-hour-only) — no new fixture invented"

patterns-established:
  - "Pattern: default-equivalence test — an additive seam's byte-identical-by-default claim is encoded by calling BOTH the kwarg-less form and an explicitly-passed default-equivalent value and asserting bitwise equality on certified scalars"
  - "Pattern: unconditional nothing-forwarding — when a wrapper kwarg defaults to nothing and the callee treats nothing as its own default, forward unconditionally and delete the if/else (provably byte-identical, fewer branches)"

requirements-completed: []   # seam-only plan: REPRO-04/05 complete with the 42-03/42-04 measurement runs this unblocks

# Metrics
duration: 94min
completed: 2026-10-26
---

# Phase 42 Plan 02: compare_tariffs agr_optimizer Passthrough Summary

**ONE additive `agr_optimizer = nothing` kwarg on `compare_tariffs`, forwarded verbatim into the `engine = :admm` `solve_admm` call (the `fit_optimizer`/`time_limit_s` precedent), proven byte-identical by default — the full suite green with the knife-edge canary exactly on its pinned trajectory (iters = 56, welfare = -4823.66604824162).**

## Performance

- **Duration:** 94 min (dominated by the 71m53s full-suite gate — the byte-identical proof)
- **Started:** 2026-10-26T10:51:33Z
- **Completed:** 2026-10-26T12:25Z
- **Tasks:** 2/2 (TDD RED→GREEN pair)
- **Files modified:** 2 (src/settlement/comparison.jl +22/−14; test/test_settlement.jl +114)

## Accomplishments

- **The seam 42-03/42-05 need:** `compare_tariffs` now carries `agr_optimizer` — the pre-registered AGR ladder's mechanism — so the 784-house settlement lenses (surplus split, equity, rebound) and the REPRO-05 proxy re-run share ONE code path at the ladder-certified point, without hand-assembling legs leg-by-leg (Don't-Hand-Roll). Previously `compare_tariffs(engine = :admm)` at 784 houses reproduced the documented iters=80 `CertificateError` refusal on every call.
- **Byte-identical default, proven not asserted:** default `nothing` resolves inside `solve_admm` to the plain `select_optimizer(QP())` factory. Proof = the full suite (33001 pass / 7 pre-registered broken / 0 fail / 0 error) with every pinned golden unmoved and the knife-edge canary bit-exact on its re-pinned trajectory.
- **Docstring parity:** the `fit_optimizer` note gained the mirror sentence (AGR precision seam; nothing = plain factory, byte-identical; gate/τ/ρ not exposed). No `|`-leading wrapped docstring lines (JuliaFormatter content-loss hazard).
- **Surgical diff:** `git diff 81978df -- src/` touches ONLY `src/settlement/comparison.jl` — signature (+1 kwarg default), the `:admm` call site (if/else → one unconditional call), docstring (+6 lines). Gate, τ, ρ, and the `fit_baseline` call shape untouched.

## Task Commits

TDD pair, in history order:

1. **Task 1: RED — structural items for the passthrough** - `f392a09` (test)
2. **Task 2: GREEN — additive kwarg + forwarding + byte-identical gate** - `ac8c7be` (feat)

## Test Evidence

- **RED (`f392a09`):** `TSODSO_TEST_FILES=test_settlement.jl julia --project=. -e 'import Pkg; Pkg.test()'` → exit 1; exactly 2 `MethodError`s — `no method matching compare_tariffs(…; …, agr_optimizer::MathOptInterface.OptimizerWithAttributes)` and `(…; agr_optimizer::Nothing)` — one per new item, the unknown-kwarg RED. All 335 pre-existing settlement assertions still passed, 0 failed (only the 2 new items errored).
- **GREEN filtered gate (`ac8c7be`, gate a):** same command → exit 0, **346/346 pass** — the 338 baseline (RED's 335 settlement + 3 guards) + exactly the 8 new assertions, 3m30s.
- **GREEN full-suite gate (gate b, the byte-identical proof):** `julia --project=. -e 'import Pkg; Pkg.test()'` → exit 0, **33001 pass / 7 broken (all pre-registered in expected_broken.txt) / 0 failed / 0 errored, 71m53s**. Knife-edge canary measured live in the run: `iters = 56`, `welfare = -4823.66604824162` — the exact pinned trajectory. **Zero golden movement.**
- **Plan verification greps:** `grep -n "agr_optimizer" src/settlement/comparison.jl` → exactly 3 sites (docstring :243, kwarg default :263, forwarding :329); `git diff 81978df -- src/` → only `src/settlement/comparison.jl`.

## Files Created/Modified

- `src/settlement/comparison.jl` — `agr_optimizer = nothing` kwarg (adjacent to `fit_optimizer`/`time_limit_s`); `:admm` branch collapsed to one unconditional `solve_admm(…; agr_optimizer = agr_optimizer, time_limit_s = time_limit_s)` with the byte-identical reasoning in a comment; docstring mirror paragraph at the `fit_optimizer` note.
- `test/test_settlement.jl` — two `@testitem`s near the other compare_tariffs items (names contain "settlement", tags `[:settlement]`, explicit `using TSODSO`): "settlement compare_tariffs threads agr_optimizer (default-equivalence, small fixture)" and "settlement compare_tariffs agr_optimizer default is nothing (signature contract)", both on the existing small 2-bus DADP fixture.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] RED fixture died on the `bins` kwarg default before the MethodError could surface**
- **Found during:** Task 1 (first RED run)
- **Issue:** The first draft omitted `bins`, so on the T=3 fixture `compare_tariffs`'s `bins = default_tou_bins(T)` kwarg default threw `ArgumentError` (default_tou_bins is 24-hour-only) at the kwarg-less call — masking the intended unknown-kwarg RED. The plan's own instruction ("read the nearest `compare_tariffs` testitem and mirror its fixture lines") already contained the fix: the neighboring four-leg item passes `bins = [[1, 2], [3]]` for exactly this reason.
- **Fix:** Explicit `bins = [[1, 2], [3]]` in all four calls, mirroring the neighbor; noted in the item-1 comment. Corrected BEFORE the RED commit — the committed RED (`f392a09`) exhibits the intended 2× MethodError on a 335-pass / 0-fail baseline.
- **Files modified:** `test/test_settlement.jl`
- **Commit:** `f392a09` (folded into the RED commit)

No other deviations. No authentication gates. No blockers. Golden policy upheld — no golden re-pinned, no canary touched.

## Known Stubs

None. The passthrough is fully wired and tested; no placeholder paths, no unwired data.

## Threat Check

All three register entries addressed: T-42-02-1 (golden drift via the "additive" seam) mitigated — unconditional `nothing` forwarding = solve_admm's own default, and the full suite + knife-edge canary was the blocking gate (canary bit-exact, zero golden movement); T-42-02-2 (untyped caller-supplied factory) accepted by design per the solve_admm.jl:207 precedent — a bad factory surfaces as a solve-time error recorded as an honest `error:<Type>` row downstream; T-42-02-SC — zero new packages. No security-relevant surface beyond the plan's threat model (no new network/auth/file-IO paths; the kwarg is an in-process optimizer factory).

## Self-Check: PASSED

- `src/settlement/comparison.jl` contains `agr_optimizer` at exactly 3 sites (kwarg default, forwarding, docstring) — FOUND
- `test/test_settlement.jl` contains both new items (names contain "settlement", call `compare_tariffs(…; agr_optimizer = …)`) — FOUND
- Commits `f392a09` (RED) and `ac8c7be` (GREEN) present in `git log`, RED preceding GREEN — FOUND
- Filtered settlement suite exit 0 (346/346) — VERIFIED
- Full suite exit 0 (33001 pass / 7 pre-registered broken / 0 fail / 0 error), canary `iters = 56`, `welfare = -4823.66604824162` — VERIFIED
- `git diff 81978df -- src/` touches only `src/settlement/comparison.jl` — VERIFIED

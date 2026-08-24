---
phase: 24-discrete-integer-investment-expansion
reviewed: 2026-08-24T02:59:10Z
depth: standard
files_reviewed: 13
files_reviewed_list:
  - src/planning/master_integer.jl
  - src/planning/benders.jl
  - src/planning/trace.jl
  - src/solver/factory.jl
  - src/TSODSO.jl
  - docs/literate/integer_investment.jl
  - docs/make.jl
  - test/test_planning_master_integer.jl
  - test/test_planning_benders_integer.jl
  - test/test_planning_certification_integer.jl
  - test/test_planning_trace.jl
  - test/test_solver_factory_milp.jl
  - test/test_planning_noninteger.jl
findings:
  critical: 1
  warning: 4
  info: 2
  total: 7
status: issues_found
---

# Phase 24: Code Review Report

**Reviewed:** 2026-08-24T02:59:10Z
**Depth:** standard
**Files Reviewed:** 13
**Status:** issues_found

## Summary

This phase adds a binary-expansion MILP Benders master (`BendersMasterInteger`), a
genuine Laporte–Louveaux ("no-good cut with a value") integer optimality cut, a
D-16 no-good anti-stall fallback, an exact-match lattice termination gate, and an
exhaustive-enumeration certification against the canonical N=1 toy instance. The
16 CONTEXT.md decisions (D-01..D-16) are implemented as locked, and the
gap-closure wave (24-05.1) genuinely fixed the three stacked defects it documents
(`Q_nu` recourse value, the anti-stall over-eagerness, and the HiGHS
`mip_feasibility_tolerance` residual) — this was independently re-verified during
this review, not merely re-read from the SUMMARY.

The termination gate is a genuinely exclusive branch (no `||` escape hatch), the
continuous default path is untouched at the source-file level (`git diff --stat`
confirms `src/planning/master.jl` has zero changes), the PVAL-04 guard's
self-verifying `EXEMPT` allowlist is sound, and the 256-pair LL-cut algebra proof
plus the `fix.()`/re-`optimize!()` reinforcement checks in
`test_planning_master_integer.jl` test the actual mechanism, not just an outcome.

However, direct execution of the shared "minimize the per-corner recourse via
ternary search" logic (`corner_recourse` in `src/planning/benders.jl`, mirrored
into three test copies and the literate page) surfaced a genuine, demonstrable
correctness defect that is dormant on the shipped D-12 fixture but will silently
produce a wrong recourse value the moment this machinery is reused with a
different device model — see CR-01 below, which the PR's own literate page
independently proves is a real hazard (it works around the identical issue in
its own example without back-porting the fix to the production function). Three
further WARNING-level robustness/maintainability gaps and two INFO items round
out the findings.

## Critical Issues

### CR-01: `corner_recourse`'s `y_inv <= 0` shortcut is silently wrong for any device without zero utility at zero consumption — and the PR's own docs prove it

**File:** `src/planning/benders.jl:104-109` (docstring) and `:110` (code)
**Issue:**

```julia
`y_inv <= 0` short-circuits to `0.0` without any solve — the feasible interval collapses
to the single point `z = 0`, at which both the follower's zero-cost and the oracle's
zero-welfare baseline apply (matches `enumerate_lattice`'s own `y_inv <= 0` branch).
```
```julia
function corner_recourse(oracle, follower, y_inv::Real, T::Int; iters::Int = 100)
    y_inv <= 0 && return 0.0
    ...
```

The docstring asserts, as an unconditional fact, that the oracle's welfare at
`z = 0` is always zero. This is false in general — it is true only for the
specific `ToyElasticDevice` used on the canonical D-12 fixture. The very same
diff's own literate page (`docs/literate/integer_investment.jl:315-321`) states
this explicitly while explaining why its own (separately maintained) enumeration
copy does NOT take this shortcut:

```
# **One deliberate divergence from the test file's own `enumerate_lattice`, found and
# fixed while drafting this page:** the test file special-cases `y_inv <= 0` to
# `Qv = 0.0` without solving anything — valid ONLY because the certified fixture's
# test-only elastic device has ZERO utility at zero consumption. This page's PUBLIC
# `Deferrable` device does not share that property (its utility is centered on a
# nonzero target `E`, so it costs real disutility to be forced to zero), so the
# `y_inv = 0` corner is evaluated by actually calling `Qfun(0.0)` below, never assumed.
```

So the PR author independently discovered and fixed this exact defect while
writing the literate page's own local `enumerate_lattice` copy — but never
back-ported the fix to `corner_recourse` (the production function actually
consumed by `solve_stackelberg!`/`apply_integer_cuts!`), nor to the shipped
`test/test_planning_certification_integer.jl`'s `enumerate_lattice`/
`enumerate_lattice_local`/`enumerate_lattice_local2` copies, all three of which
carry the identical unguarded shortcut.

`b = [0,0,0,0]` (`y_inv = 0`, "zero investment") is a completely ordinary,
reachable lattice corner — not a degenerate/impossible case. The moment
`build_master_integer`/`solve_stackelberg!` is reused with any device whose
welfare/utility is nonzero at zero throughput (e.g. the project's own public
`Deferrable` device, per the literate page's own words), a Benders trial landing
on that corner will silently record `Q_nu = 0.0` for `add_ll_cut!` instead of the
true (generally nonzero) recourse value. Because `0.0` is a perfectly finite
number, this does **not** trip `add_ll_cut!`'s `isfinite(Q_nu)` guard — it fails
silently, producing a mathematically invalid Laporte–Louveaux cut that can
exclude the true optimal lattice point, exactly the class of defect
plan 24-05.1 spent three fix-cycles chasing down for a different root cause.
This is dormant on the shipped, certified D-12 instance (confirmed: the
`ToyElasticDevice` genuinely has zero utility at zero, so the certification's
current 0-violations result is not affected), but it is a live landmine in
shipped `src/` code for the very next researcher who does what this project's
own `CLAUDE.md` describes as its core value ("a researcher can express a
scenario and a model variant declaratively").

**Fix:** Remove the shortcut and always call `Qfun(0.0)` for the single-point
case (as the literate page's own corrected copy already does), or explicitly
document the assumption as a documented precondition of `corner_recourse` and
assert it (e.g. compare an actual `Qfun(0.0)` solve against `0.0` once at
construction time / behind a debug assertion) rather than asserting it as fact
in the docstring. Apply the same fix to `enumerate_lattice`/
`enumerate_lattice_local`/`enumerate_lattice_local2` in
`test/test_planning_certification_integer.jl`, which share the identical
shortcut and would otherwise "agree" with the same wrong answer if ever reused
outside the D-12 fixture.

## Warnings

### WR-01: `corner_recourse`'s ternary search has a tie-breaking defect that silently walks away from the feasible region when the follower's capacity is well below `y_inv/3`

**File:** `src/planning/benders.jl:124-130` (also mirrored in
`test/test_planning_certification_integer.jl`'s three `enumerate_lattice*`
copies and `docs/literate/integer_investment.jl`'s own copy)
**Issue:** The extended-value trick (`Qfun` returns `+Inf` for an infeasible
trial `z`) is sound for a genuinely convex function, but the tie-breaking rule
`Qfun(m1) < Qfun(m2) ? (hi = m2) : (lo = m1)` silently takes the `lo = m1`
branch whenever `Qfun(m1) == Qfun(m2)` — including when **both** probes are
`+Inf` (both beyond the follower's deliverable capacity). Once that happens,
`lo` is permanently pushed past the feasibility boundary, and every subsequent
iteration keeps comparing `Inf < Inf` (always false), converging to
`zstar ≈ hi` with `Qfun(zstar) = Inf`, even though the true (feasible, finite)
minimum exists inside `[0, capacity]`.

Verified directly (100-iteration Julia reproduction against a toy convex +
extended-value indicator function): whenever `capacity < y_inv / 3` on the
*first* iteration, the search diverges to `Inf` on every trial, 100% of the
time; a 200,000-sample randomized sweep found zero cases of a silently
*finite-but-wrong* answer — the failure mode is always "converges to `Inf`",
never a plausible-looking wrong number.

This is **dormant on the shipped D-12 fixture** (`corridor_cap * x_inv_max =
4.0`, and every K=4 lattice corner has `y_inv <= 7.5`, so `y_inv/3 <= 2.5 <
4.0` for every corner — confirmed the first-iteration probes are always
feasible on this exact configuration). But it requires no code change to
trigger — only a parameter change (D-03 explicitly documents `K` as
configurable "a parameter change, not a code change"; the same is true of
`y_max` or the follower's `corridor_cap`/`x_inv_max`). Consequence differs by
call site: in production (`corner_recourse` → `add_ll_cut!`), the resulting
`Q_nu = Inf` trips the `isfinite` guard and crashes loudly (a robustness/
availability issue, not silent corruption); but in the **certification/
enumeration oracle** (`enumerate_lattice` and its 3 duplicated copies), a
mis-flagged corner is silently excluded from `best_total` with **no guard at
all** — the "independent, exhaustive" oracle can silently report the wrong
optimal corner for a reconfigured instance, which is precisely the failure
mode the whole INT-03 certification exists to rule out.
**Fix:** Clamp the ternary-search bracket to the known feasibility boundary
before searching (e.g. binary-search for the largest feasible `z` first, then
ternary-search only within `[0, that boundary]`), or change the tie-break to
shrink both ends together on a tie (`lo = m1; hi = m2`) rather than defaulting
to `lo = m1`. At minimum, add a regression test exercising a capacity/`y_max`
ratio that reaches this branch, and note the implicit precondition
(`follower capacity >= y_inv / 3`, roughly) in the docstring.

### WR-02: `apply_integer_cuts!`'s anti-stall detector uses a single hardcoded absolute tolerance (`STALL_Z_ATOL = 1e-6`) with no adaptivity, and a corner that ties on `z` between iterations bans the corner permanently

**File:** `src/planning/master_integer.jl:519, 580-590`
**Issue:** The gap-closure fix (24-05.1) correctly distinguishes "same corner,
still-converging `z`" from "same corner, converged `z`" — a real and necessary
fix, well-tested on the D-12 fixture (9-iteration clean convergence). But the
distinction rests entirely on one fixed absolute tolerance, `1e-6`, compared via
`isapprox(...; atol = STALL_Z_ATOL, rtol = 0.0)`. Because `add_nogood_cut!`
permanently excludes a corner from the master's feasible region once fired
(unlike an LL cut, which only tightens `θ`), a false-positive "stall" detection
is unrecoverable for the rest of the run — and the true optimal corner is
exactly the corner most likely to be revisited repeatedly as cuts refine it
(per the SUMMARY's own account, `z` moved `0.195 → 0.442 → 0.497 → 0.500`
across the pre-fix banning). On a different fixture/scale where the master's
own genuine cutting-plane convergence naturally produces increments smaller
than `1e-6` for several iterations before settling, this same heuristic could
re-introduce exactly the "ban the optimum before its incumbent converges"
failure mode this gap-closure wave fixed, just at a smaller step size. This is
not a live bug on the tested fixture, but it is a single hardcoded constant
governing whether the global optimum becomes permanently unreachable, with no
test exercising a near-`1e-6`-increment convergence trajectory.
**Fix:** At minimum, document the assumption ("increments below `1e-6` are
assumed to be genuine convergence noise, not real progress, given this
fixture's ~`1e-9` solver precision") as an explicit precondition rather than an
implementation detail, and consider deriving the tolerance from the actual
solver precision/`KNOWN_OPTIMUM_ATOL` order of magnitude rather than a second,
independently-chosen literal. A regression test that forces several
small-but-nonzero `z` increments at the same corner (via a contrived cut
sequence) and asserts the corner is *not* banned prematurely would directly
protect this invariant.

### WR-03: `mip_feasibility_tolerance => 1e-9` is set globally in `select_optimizer(::MILP)`, with no warning to future callers of the seam

**File:** `src/solver/factory.jl:79-97`
**Issue:** The gap-closure comment thoroughly justifies *why* `1e-9` was
chosen for **this** phase's toy MILP (closes a ~7e-8 residual to machine
precision), and correctly notes `MILP()` currently has exactly one call site.
But `select_optimizer(::MILP())` is the *only* solver-naming seam for any
future MILP consumer (INFRA-02) — the next person to call `MILP()` for an
unrelated, differently-scaled MILP (e.g. a larger planning master, or a future
N>1 integer-investment extension) silently inherits a feasibility tolerance
three orders of magnitude tighter than HiGHS's own default, tuned for a tiny
toy instance's specific numerical regime. An overly tight feasibility
tolerance is a well-known cause of spurious `INFEASIBLE`/excessive
branch-and-bound effort on differently-scaled models. This is not a defect in
the current phase's own behavior, but the comment doesn't flag the
forward-compatibility risk for the next maintainer, unlike (for example) the
`SOCP`/`NLP` methods' keyword-override pattern, which lets a caller opt out.
**Fix:** Either give `MILP()` the same `attrs...` keyword-override pattern
already used by `SOCP`/`NLP` (so a future caller can loosen it per-instance
without editing the factory), or add an explicit one-line forward-compatibility
note ("if a future MILP consumer needs a looser feasibility tolerance for a
larger/differently-scaled model, override via ... rather than weakening this
default globally").

### WR-04: The reference `enumerate_lattice` enumeration logic is duplicated four times with no shared source of truth, creating a divergence risk

**File:** `test/test_planning_certification_integer.jl:84-125` (top-level,
confirmed dead code under TestItemRunner's AST-based discovery — see the
file's own header comment), `:204-238` (`enumerate_lattice_local`, nested,
actually executed), `:406-432` (`enumerate_lattice_local2`, nested, actually
executed, missing the `best_b`/`best_y` fields), and
`docs/literate/integer_investment.jl:343-362` (a fifth, independently
maintained copy, which — per CR-01 — has *already* diverged from the other
four on the `y_inv <= 0` handling).
**Issue:** The file header explains, correctly, that TestItemRunner's
AST-based discovery makes a plain top-level function definition dead code
inside a `@testitem`-only file, forcing the nested-copy workaround. That
constraint is real and not fully avoidable without violating the project's own
`@testitem`-only convention. But the result is four to five independently
maintained copies of load-bearing certification logic (the very logic CR-01 and
WR-01 above found defects in), with no mechanical check that they stay
identical. A future fix to one copy (e.g. patching CR-01's `y_inv <= 0`
shortcut in `corner_recourse`) has no structural reminder to also patch the
three-to-four test/docs copies — exactly the failure mode that let the
literate page's copy silently diverge from (and, in this one respect, silently
outperform) the test file's copies within this very diff.
**Fix:** Consider promoting `enumerate_lattice` to a `@testsetup`/`@testmodule`
(TestItemRunner's own mechanism for sharing code across `@testitem`s, which
*is* `using`-importable, unlike a bare top-level function) to collapse the two
in-test copies to one; failing that, add a comment at each copy site
cross-referencing every other copy by file:line so a future editor is at least
pointed at the others.

## Info

### IN-01: `KNOWN_OPTIMUM_ATOL` is a solver-version-pinned magic constant with no automated staleness detection

**File:** `src/planning/benders.jl:42-62`
**Issue:** The constant (`3.957388639008741e-8`) is thoroughly documented with
its provenance (measured Clarabel/HiGHS duality gaps on 2026-08-23) and its
derivation formula. This is good practice. However, it is derived from a
point-in-time measurement of the installed Clarabel/HiGHS solver binaries; if a
future solver upgrade changes the achieved duality gap on this fixture (better
or worse), there is no automated check that would proactively re-verify the
constant — the only symptom would be the certification test in
`test_planning_certification_integer.jl` eventually failing (loudly, via
`max_iter` exhaustion raising `ErrorException`, per the exclusive-branch
termination gate — confirmed correct, not a silent failure mode) at some
future, unrelated dependency bump. This is an acceptable trade-off given the
project's own stated methodology (measure, don't guess), but is worth a
one-line comment noting that a future `Manifest.toml` solver bump is the
expected trigger for re-measuring this constant, so a future CI failure here
is diagnosed quickly rather than treated as a mystery regression.

### IN-02: Dead top-level `enumerate_lattice` function is unreachable from the actual test run

**File:** `test/test_planning_certification_integer.jl:84-125`
**Issue:** As the file's own header thoroughly documents, this function is
never executed by the TestItemRunner-driven suite (`Pkg.test()`) — it exists
only as a docstring-carrying reference definition, independently verified once
via a manual `include()` outside the normal test run. This is a deliberate,
well-documented trade-off forced by TestItemRunner's discovery mechanism, not
an oversight — flagged here only for completeness/traceability, and because it
compounds WR-04's divergence risk (a maintainer skimming this file would
reasonably assume this copy is the one that runs).

---

_Reviewed: 2026-08-24T02:59:10Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

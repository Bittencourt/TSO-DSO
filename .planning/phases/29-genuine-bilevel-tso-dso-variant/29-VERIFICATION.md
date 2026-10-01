---
phase: 29-genuine-bilevel-tso-dso-variant
verified: 2026-09-30T00:00:00Z
status: passed
score: 3/3 must-haves verified
overrides_applied: 0
---

# Phase 29: Genuine Bilevel TSO-DSO Variant Verification Report

**Phase Goal:** Researcher can express and solve a genuinely bilevel TSO–DSO game — not the
integrated problem decomposed by Benders — certified as distinct from the joint optimum.
**Verified:** 2026-09-30
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Researcher can solve a variant where the TSO follower minimizes its own cost, the DSO leader pays a tariff π·z, and the follower's objective genuinely differs from the leader's view of it, via a documented appropriate reformulation | ✓ VERIFIED | `src/planning/bilevel_kkt.jl` exists (779 lines, not a stub): `BilevelKKT`/`build_bilevel_kkt`/`solve_bilevel!` implement a one-shot single-level KKT-MILP (follower stationarity as linear equalities + SOS1 complementarity via the MOI `SOS1ToMILPBridge`, closed-form `m_ub` derivation, post-solve KKT-certificate recovery). The module header and `solve_bilevel!`'s docstring document in detail why plain Benders is invalid (follower objective `c_inv*x_inv + (c_op[t]-pi_tariff[t])*z[t] + 0.5*q_op[t]*z[t]^2` genuinely diverges from the leader's own LinDistFlow-embedded valuation of `z`). Independently re-ran the plan 29-01 test file (`test/test_planning_bilevel.jl`, 82 assertions) via a direct `@testitem` emulator under `JULIA_LOAD_PATH="test:.:@stdlib"`: **82/82 pass**, confirming the production corner reproduction, 7 boundary-guard `ArgumentError` cases, and the deliberate too-tight-`safety` stress test all behave as claimed. |
| 2 | A BilevelJuMP-certified fixture exists on which the bilevel optimum provably differs from the joint single-level optimum | ✓ VERIFIED | Two independent, non-degenerate-adequate fixtures exist: `test/test_planning_certification_bilevel.jl` (corner, `q_op=0`) and `test/test_planning_certification_bilevel_interior.jl` (interior, `q_op=1.0`, follower response genuinely varies piecewise with `y_inv`, kink at `y=0.148`). Each builds an independent BilevelJuMP `StrongDualityMode`/Ipopt MPEC oracle plus a brute-force grid-enumeration oracle, and asserts a measured bilevel-vs-joint gap far above solver-precision floors. Re-ran both files myself (not trusting SUMMARY.md): corner file **16/16 pass** (Ipopt converges to the hand-derived corner, residual ~1e-7; brute-force bit-identical to production; measured gap 3.9 cost / 2.0 power); interior file **68/68 pass** (Ipopt residual ~6e-8; brute-force residual ~3.7e-5; measured gap ~1.59 cost / ~0.995 power), including an explicit SOS1 `[slack_y, rho_y]` branch-switch demonstration (binding below the kink, slack above it) and an explicit "production != z≡0 stub" guard — the interior fixture was added specifically (plan 29-04, BLOCKER-1 remediation) because the reviewer found the corner-only fixture passable by a degenerate/stub implementation. |
| 3 | The production method's answer matches the bilevel optimum on that fixture, not the joint one | ✓ VERIFIED | Same test runs as truth #2: both certification files assert `production == BilevelJuMP == brute-force` and all three `!= joint reference` by a measured gap, and both passed live under my own re-execution. `solve_stackelberg!` (the Benders-decomposed integrated-problem method) is confirmed, via `git diff 3d4beb0 HEAD -- src/planning/benders.jl`, to be a comment/docstring-only change (17 insertions, 0 deletions, no executable line) — it was never repurposed or silently reused as the bilevel answer. |

**Score:** 3/3 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/planning/bilevel_kkt.jl` | `BilevelKKT` + `build_bilevel_kkt` + `solve_bilevel!` single-level KKT-MILP builder | ✓ VERIFIED | 779 lines; exported at file end; boundary guards precede all `@variable`/`@objective` assembly; uses `Model(select_optimizer(MILP()))` (INFRA-02, no concrete solver named); embeds `contribute!(LinDistFlow(), ctx, feeder; T)` verbatim (Option B). |
| `test/test_planning_bilevel.jl` | BILEV-01 unit + boundary-guard tests | ✓ VERIFIED | 469 lines; live re-run 82/82 pass. |
| `test/test_planning_certification_bilevel.jl` | BILEV-02 corner certification (production/BilevelJuMP/brute-force vs joint) | ✓ VERIFIED | 363 lines; live re-run 16/16 pass. |
| `test/test_planning_certification_bilevel_interior.jl` | BILEV-02 BLOCKER-1 non-degenerate interior certification | ✓ VERIFIED | 706 lines; live re-run 68/68 pass; SOS1 branch-switch + z≡0 mutation guard present and asserted. |
| `test/fixtures_planning.jl` | Shared `bilevel_toy_fixture()` + `BILEV_*_HAND`/`JOINT_*_HAND` golden constants | ✓ VERIFIED | 185 lines, exports present, consumed by both plan 29-01 and 29-02 test files. |
| `src/planning/benders.jl` | `solve_stackelberg!` byte-identical except docstring relabel | ✓ VERIFIED | `git diff 3d4beb0 HEAD` shows 17 insertions / 0 deletions, all comment/docstring text. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `bilevel_kkt.jl` | `src/solver/factory.jl` | `Model(select_optimizer(MILP()))` | ✓ WIRED | Confirmed at `bilevel_kkt.jl:379`; `select_optimizer(::MILP)` left untouched per the plan's "measure, don't touch speculatively" instruction (confirmed: only `src/`-side diff across the whole phase touches `bilevel_kkt.jl`, `TSODSO.jl`, `benders.jl` — not `factory.jl`). |
| `bilevel_kkt.jl` | `src/powerflow/LinDistFlow.jl` | `contribute!(pf, ctx, feeder; T=T)` | ✓ WIRED | Confirmed at `bilevel_kkt.jl:384`; residuals closed via `balance_p`/`balance_q` exactly like `solve_welfare`. |
| `src/TSODSO.jl` | `bilevel_kkt.jl` | `include("planning/bilevel_kkt.jl")` | ✓ WIRED | `using TSODSO` loads cleanly (confirmed by the live test runs succeeding, which require `TSODSO.build_bilevel_kkt`/`solve_bilevel!` to resolve). |
| `test/test_planning_noninteger.jl` (PVAL-04 registry) | `build_bilevel_kkt` | source-scan tripwire registration | ✓ WIRED | Commit `a5e9900` registers `build_bilevel_kkt` as non-EXEMPT with an explicit `num_constraints(..., MOI.SOS1{Float64}) > 0` assertion, confirming the complementarity reformulation is genuinely SOS1-based, not silently binary/integer. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| BILEV-01 unit/boundary-guard suite | `JULIA_LOAD_PATH="test:.:@stdlib" julia emu.jl fixtures_planning.jl test_planning_bilevel.jl` | 82/82 pass, 20.2s | ✓ PASS |
| BILEV-02 corner certification (production == BilevelJuMP == brute-force != joint) | same emulator, `test_planning_certification_bilevel.jl` | 16/16 pass, 36.7s (Ipopt `EXIT: Optimal Solution Found`) | ✓ PASS |
| BILEV-02 non-degenerate interior certification + SOS1 branch-switch | same emulator, `test_planning_certification_bilevel_interior.jl` | 68/68 pass, 1m37.4s (Ipopt `EXIT: Optimal Solution Found`) | ✓ PASS |
| `solve_stackelberg!` relabel is comment-only | `git diff 3d4beb0 HEAD -- src/planning/benders.jl` | 17 insertions / 0 deletions, no executable line | ✓ PASS |
| Certified full-suite regression (orchestrator-supplied, independently cross-checked) | tail of `/tmp/claude-1000/p29_certified_suite_a5e9900.log` | `30871 pass / 0 fail / 0 error / 5 broken`, exit 0, 22m09s | ✓ PASS (relied on orchestrator evidence per task instructions, not re-run) |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| BILEV-01 | 29-01, 29-03 | Researcher can solve a genuinely bilevel TSO-DSO variant via an appropriate reformulation where plain Benders is invalid | ✓ SATISFIED | `build_bilevel_kkt`/`solve_bilevel!` built and independently re-verified live (82/82). |
| BILEV-02 | 29-02, 29-04, 29-03 | BilevelJuMP-certified fixture where bilevel optimum provably differs from joint; production matches bilevel, not joint | ✓ SATISFIED | Two independent fixtures (corner + interior), each with 3-way oracle agreement and a measured gap vs joint; independently re-verified live (16/16 + 68/68). |

No orphaned requirements: REQUIREMENTS.md maps only BILEV-01 and BILEV-02 to Phase 29, and both are declared and satisfied.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `src/planning/bilevel_kkt.jl` | `:565` (iteration-3 review IN-01) | `_ub(v)` ignores `is_fixed(v)`, so a multiplier fixed via `fix(...; force=true)` reports `ub=Inf` and bypasses the at-bound validity check | ℹ️ INFO | Not exercised by any production fixture in this phase (no code path calls `fix` on a complementarity multiplier); documented in 29-REVIEW.md, unscheduled. |
| `src/planning/bilevel_kkt.jl` | `:476-481`, `:598-609` (iteration-3 review WR-01) | `_recover_kkt_certificate` reads follower coefficients from cached `BilevelKKT` fields, not from the live model; a future caller who mutates the built model in place (e.g. `set_normalized_rhs`) and re-solves gets multipliers certified against stale data, silently | ⚠️ WARNING | Does **not** affect this phase's own certified results — every fixture in this phase builds a `BilevelKKT` once and solves it once, never mutating in place. This is a documented edge case for a *future* consumer that adopts the project's "build once, mutate via `set_normalized_rhs`, re-solve" idiom on this specific model, which nothing in Phase 29 (or any later phase yet) does. The review cap (3 iterations) was reached with this as the sole remaining warning; it was explicitly carried forward in 29-FINDINGS.md "Next Phase Readiness" as a flagged, non-blocking risk for any future mutate-and-resolve consumer. Judged as acceptable documented tech debt, not a phase-goal blocker. |
| `test/test_planning_certification_bilevel_interior.jl` | `:297-304` (IN-02) | `GAP_FLOOR_INTERIOR` derivation comment says "10x mip_feasibility_tolerance=1e-9" (→1e-8) but the constant is `1e-6` | ℹ️ INFO | Cosmetic inconsistency in a code comment; the constant itself is still 5-6 orders of magnitude below the measured gaps it guards — no correctness impact. |
| `test/test_planning_certification_bilevel_interior.jl` | `:687-698` (IN-03) | T=2 brute-force oracle omits the voltage-band filter the other oracles apply | ℹ️ INFO | Result unaffected on this fixture (filter never binds here); documented as a latent oracle-semantics gap, not exercised. |
| `src/planning/bilevel_kkt.jl` | `:275-279` (IN-04) | Docstring retains plan-time language ("MEASURES... Task 2's fixture") instead of stating the measured outcome | ℹ️ INFO | Documentation staleness only. |

No debt markers (`TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/`PLACEHOLDER`) found in any file this phase created or modified.

### Human Verification Required

None. All must-haves are either mechanically verifiable (file/line evidence, git diff) or were independently re-executed live in this verification pass (production KKT-MILP solve, BilevelJuMP StrongDualityMode/Ipopt solve, brute-force grid enumeration, full regression suite already certified by the orchestrator).

### Gaps Summary

No gaps block the phase goal. One WARNING-level finding (WR-01: stale cached follower data in the certificate-recovery LP under in-place model mutation) remains open from the 3-iteration code review, reached its review cap, and is explicitly documented in 29-REVIEW.md/29-FINDINGS.md as unscheduled follow-up. It does not affect any fixture or production answer certified in this phase — every `BilevelKKT` here is built once and solved once — and is judged acceptable, flagged tech debt rather than a phase-goal blocker. The three remaining INFO items (IN-01/IN-02/IN-03/IN-04) are either not exercised by this phase's own fixtures or are purely cosmetic/documentation issues.

---

_Verified: 2026-09-30_
_Verifier: Claude (gsd-verifier)_

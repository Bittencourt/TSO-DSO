---
phase: 05-distribution-pricing-dadp-dlmp-decomposition
verified: 2026-07-19T00:00:00Z
status: passed
score: 4/4 must-haves verified
overrides_applied: 0
---

# Phase 5: Distribution Pricing — DADP & DLMP Decomposition Verification Report

**Phase Goal:** Extract and validate the day-ahead dynamic price as the dual of the nodal active-power balance, decompose it into energy/loss/congestion/voltage components that sum to the nodal price, and produce the welfare accounting reproducing the +25% headline — over exactness-gated Phase-4 duals.
**Verified:** 2026-07-19
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | DADP/DLMP extracted as dual of nodal active-power balance, per node/hour, sign verified vs hand-solved 2-bus, GATED on PF-04 exactness certificate | ✓ VERIFIED | `src/pricing/dlmp.jl:95` `extract_dlmp` returns `dual(bp[j,t])` over `:balance_p` (N×T). `_assert_priceable` (`dlmp.jl:56-77`) throws `ArgumentError` on an `:l`-bearing SOCP ctx lacking `ctx.meta[:socp_maxgap]`. Sign test: `test_pricing_dlmp.jl:20` load-bus DADP >0 and ≈λ₀; gate refusal test `test_pricing_dlmp.jl:54-85` (`@test_throws ArgumentError`, and lifts on stashing `:socp_maxgap`). |
| 2 | DLMP decomposes into energy/loss/congestion/voltage that SUM to nodal price with correct sign — HARD independent-reconstruction assertion, residual ~machine precision | ✓ VERIFIED | `decompose_dlmp` (`dlmp.jl:163-259`) builds each component from a DISTINCT registered dual (strategy B: `−cone[3]` loss, `−smax[2]` congestion, `−2r(vdrop+cpydrop)` voltage, energy=root λ). HARD `error()` throw at `dlmp.jl:242` on worst residual > `atol+rtol·max`. Tests `test_pricing_dlmp.jl:119,164` assert elementwise sum≈total at atol/rtol 1e-6 with NONZERO congestion (`:161`) and voltage (`:196`) — non-tautological. |
| 3 | Welfare accounting: social/DSO/prosumer with HARD identity social=prosumer+DSO=objective (non-vacuous via sign-flip guard), FIT baseline, +25% headline | ✓ VERIFIED (with documented/accepted +25% quantitative gap) | `welfare_accounting` (`welfare.jl:64-159`) hard `error()` at `:144` on identity violation; `_transfer_flip` self-test mis-signs the DSO transfer. Non-vacuity test `test_pricing_welfare.jl:123` `@test_throws ErrorException welfare_accounting(...; _transfer_flip=true)`. FIT baseline `fit_baseline` (`src/pricing/fit.jl:253`) is a genuine solve via factory. +25% pinned as COMPUTED golden `RATIO_GOLDEN=0.9999738…` (`test_pricing_welfare.jl:217`); thesis 1.25 is a NON-FAILING `@test_broken` cross-check (`:230`). |
| 4 | Economic-direction checks: DADP < λ₀ at PV glut, DADP > λ₀ at congestion (non-vacuous) | ✓ VERIFIED | `economic_direction_checks` (`src/pricing/checks.jl:67-161`) throws `ArgumentError` on a backwards signal per regime. Tests: PV-glut below-wholesale (`test_economic_direction.jl:24-54`), congestion above-wholesale (`:56-82`), and non-vacuity via sign-flipped λ₀/DADP `@test_throws` (`:85-116`). |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `src/pricing/dlmp.jl` | DADP extraction + 4-way decomposition | ✓ VERIFIED | 261 lines; real duality post-processing, gate + hard sum throw. Wired via `include` in TSODSO (`src/TSODSO.jl:79`), exports `extract_dlmp`, `decompose_dlmp`. |
| `src/pricing/welfare.jl` | social=prosumer+DSO surplus identity, +25% ratio | ✓ VERIFIED | 188 lines; hard identity throw + sign-flip self-test. Included (`:82`), exports `welfare_accounting`. |
| `src/pricing/fit.jl` | FIT-OPT counterfactual baseline | ✓ VERIFIED | 384 lines; genuine solve via `select_optimizer` factory, exports `fit_baseline`. Included (`:80`). |
| `src/pricing/checks.jl` | economic-direction checks | ✓ VERIFIED | 164 lines; regime-throwing directional checks. Included (`:81`), exports `economic_direction_checks`. |
| `src/powerflow/ConvexBranchFlow.jl` | registers :cone/:vdrop/:cpydrop/:smax duals (additive) | ✓ VERIFIED | `register_constraint!` for all four (`:156,169,188,207`); stashes `ctx.meta[:pf_vars]` (`:233`). |
| `src/models/welfare_solve.jl` | stashes `:agg_net` per-aggregator net injection | ✓ VERIFIED | `ctx.meta[:agg_net] = agg_net` (`:186`). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `welfare.jl` | `:agg_net` stash | `ctx.meta[:agg_net]` iteration | ✓ WIRED | Producer `welfare_solve.jl:186`, consumer `welfare.jl:106`. |
| `dlmp.jl` | `:balance_p` dual | `dual(bp[j,t])` | ✓ WIRED | Registered `:balance_p` read; PF-04 gate enforced before read. |
| `decompose_dlmp` | `:cone/:vdrop/:cpydrop/:smax` | `dual(...)` per branch | ✓ WIRED | All four registered in ConvexBranchFlow; missing-dual guard throws (`dlmp.jl:172`). |
| `welfare_accounting` | `fit_baseline` | `baseline.social_fit` ratio | ✓ WIRED | `_fit_ratio` consumes solved FIT context. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Full test suite | `julia --project=. -e 'import Pkg; Pkg.test()'` | `Pass 1049, Broken 1, Total 1050` — 0 fail, 0 error | ✓ PASS |
| No concrete solver in pricing modules | `grep Clarabel\|HiGHS\|Ipopt\|Gurobi\|SCS src/pricing/` | Only `Model(optimizer)` / `Model(select_optimizer(...))` factory calls in fit.jl — no hardcoded solver | ✓ PASS |
| Phase-4 golden/exactness unchanged | golden `GOLDEN_WELFARE=-4823.15…` (`test_ieee13.jl:186`) + `test_exactness.jl` in suite | Part of the 1049 passing — additive registration did not regress | ✓ PASS |
| +25% ratio golden pinned, thesis a non-failing cross-check | `test_pricing_welfare.jl:217,230` | Golden ratio ≈0.9999 pinned; thesis 1.25 gap recorded as `broken` | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| PRICE-01 | 05-02 | Extract DADP/DLMP as nodal active-balance dual per node/hour | ✓ SATISFIED | `extract_dlmp` + 2-bus sign + PF-04 gate tests |
| PRICE-02 | 05-01/05-02 | Decompose DLMP into 4 components that sum to nodal price (assertion) | ✓ SATISFIED | `decompose_dlmp` hard sum throw + IEEE-13/high-PV sum tests |
| PRICE-03 | 05-03/05-05 | Welfare split social/DSO/prosumer + FIT baseline (+25% headline) | ✓ SATISFIED | surplus identity + sign-flip guard + FIT baseline + computed-ratio golden (+25% documented gap accepted) |
| PRICE-04 | 05-04 | Economic-direction sanity checks | ✓ SATISFIED | `economic_direction_checks` PV-glut/congestion + sign-flip non-vacuity |

### Anti-Patterns Found

None. No unreferenced TBD/FIXME/XXX debt markers in the pricing modules. All error paths use loud `throw`/`error` (never `@assert`, which `-O` can elide). Empty-container patterns (`zeros`, `Int[]`) are legitimate accumulators overwritten by real dual reads, not stubs. The single `@test_broken` is an intentional, documented, non-failing thesis cross-check.

### Human Verification Required

None outstanding. The one manual-only item in 05-VALIDATION.md (exact +25% / $1457→$1819 absolute match) is explicitly ACCEPTED by the researcher (STATE.md, 2026-07-18) as a figure-bound follow-up with the SAME root cause as the Phase-4 welfare gap: absolute social welfare is negative in the ¢$/kWh calibration, so the ratio of two negatives ≈1.0 rather than 1.25. The computed ratio is pinned as the golden regression anchor and the thesis 1.25 is a non-failing cross-check — per the verification directive this is a documented/accepted gap, NOT a phase failure.

### Gaps Summary

No gaps blocking goal achievement. All four ROADMAP success criteria are observably true in the code:
1. DADP is the `:balance_p` dual, positive-signed (2-bus), and the PF-04 exactness gate throws on an ungated SOCP ctx.
2. The four-way decomposition reconstructs each component from a distinct registered dual and enforces a hard sum-to-price throw; tests confirm residual ~machine precision with genuinely nonzero congestion/voltage terms.
3. The welfare surplus identity `social = prosumer + dso = objective_value` is a hard throw proven non-vacuous by the `_transfer_flip` self-test; the FIT baseline is a genuine solve. The +25% quantitative miss (computed ratio ≈1.0) is an accepted, documented, figure-bound follow-up pinned as a golden with a non-failing thesis cross-check.
4. Economic-direction checks assert below-/above-wholesale excursions and throw on a backwards signal (non-vacuous sign-flip tests).

Suite: 1049 pass / 1 broken (intentional non-failing thesis cross-check) / 0 fail / 0 error — matching the expected result. No concrete solver named in pricing modules; the additive Phase-4 dual registration did not alter the IEEE-13 golden or exactness anchors.

---

_Verified: 2026-07-19_
_Verifier: Claude (gsd-verifier)_

---
phase: 20-overvoltage-capable-relaxation
reviewed: 2026-08-09T00:28:28Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - src/TSODSO.jl
  - src/powerflow/RestrictedBranchFlow.jl
  - src/models/restriction_exactness.jl
  - src/models/ac_dual_fallback.jl
  - src/models/ac_oracle.jl
  - test/test_restricted_branch_flow.jl
  - docs/literate/restricted_branch_flow.jl
  - docs/make.jl
  - docs/src/api.md
findings:
  critical: 1
  warning: 6
  info: 5
  total: 12
status: issues_found
fixes:
  fixed_at: 2026-08-08
  fix_scope: critical_warning
  fixed: 7
  skipped: 0
  info_out_of_scope: 5
---

# Phase 20: Code Review Report

**Reviewed:** 2026-08-09T00:28:28Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Reviewed the Phase 20 diff (`b25d7b4..HEAD`): the Gan-Low OPF-m restricted SOCP formulation
(`RestrictedBranchFlow`), the loss-free shadow-voltage post-processor
(`recover_lossfree_shadow_voltage`), the revised `assert_restriction_exact!` certificate, the
`ac_dual_fallback_price` pricer, tests, and docs wiring. The review was conducted against the
**revised** certificate semantics (ac_feasible = physical cone-feasibility; matches_ac_optimum =
diagnostic; optimality_loss vs the unrestricted bound) — under that design the certificate's
internal logic, throw/report contract, and D-08 keying are coherent, and the math of the
loss-free shadow recursion was verified against the project's stated balance convention (the
telescoping `P̌ = P − Σ_closed-subtree r·ℓ` derivation checks out for parent→child-oriented
branches).

**Tolerance derivations meet the standing bar.** `cone_rtol = 5e-4`/`cone_atol = 2e-7` are
~9.6-9.8× above the measured `5.08e-5`/`2.08e-8` floors on the restricted solve's own cone
residual; `rtol = 1e-3`/`atol = 2e-5` are ~12-14× above the measured clean-hour
restricted-vs-AC floors (`8.05e-5`/`1.44e-6`). Both pairs are measured on the quantity they
gate, on the fixture they run, dated, with worst branch/hour identified, and are deliberately
distinct from the sibling certificates' defaults (`assert_socp_exact!` 1e-4/1e-6,
`assert_ac_exact!` 1e-4/1e-6). No certificate laundering found. The internal consistency of the
documented numbers (ratio ≈0.051 ⟺ mag ≈4.1e-4 ⟺ relative floor 5.08e-5) checks out.

Key concerns: one latent silent-wrong defect in the shadow-voltage recursion (branch-orientation
assumption that the codebase's own sibling function documents as NOT guaranteed), and a cluster
of contract gaps in the certificate and fallback (fabricated provenance formulation, stale
provenance surviving a structural throw, a duplicate Ipopt "seed" variant, a hardcoded concrete
solver outside the factory).

## Fix Status (2026-08-08, `--fix` pass, scope: Critical + Warning)

All 7 in-scope findings fixed, one atomic commit each. Info findings (IN-01..IN-05) are out
of the fix scope and remain open (IN-05's missing-`import Ipopt` half is subsumed by WR-04's
fix: `ac_dual_fallback.jl` no longer references `Ipopt` at all).

**Verification:** each fix verified by a targeted direct Julia/Test.jl script under
`--project=.`; full suite after all fixes: **2563 passed / 0 failed / 3 pre-existing broken**
(clean-worktree run — the 2 known-false Aqua drift failures exist only on the drifted main
checkout; baseline 2546/0/3, +17 from the new regression tests, no regressions). Docs build
green (only pre-existing benign warnings); rendered Rung-3 H1 confirmed "…A Gan-Low OPF-m
Restriction".

| Finding | Status | Commit | Notes |
|---------|--------|--------|-------|
| CR-01 | fixed | `6be860b` (+ `f02e9cf`) | Both recursions now keep tree parent + SIGNED branch index. The reviewer's sketched `sign·P` flip alone would be off by the feeding branch's own `r·ℓ` on a reversed branch (the model's `P[b]` is the child-side SENDING end there); the applied fix uses the exact parent-side flow `r·ℓ − P`. Regression testitem re-encodes one physical point in both orientations and gates both code paths at `1e-12` (byte-level algebra, verified: max deviation `2.2e-16`). Follow-up `f02e9cf` removes a soft-scope `idx` mutation from the testitem (errored under TestItemRunner's module-top-level evaluation; test-only, no src change). |
| WR-01 | fixed | `b5ac2bd` | `formulation = get(ctx.meta, :formulation, :unknown)`; the D-08 marker `RestrictedBranchFlow.contribute!` stashes is now genuinely consumed. Test locks the `ConvexBranchFlow` context to `:unknown`. |
| WR-02 | fixed | `c81a5e7` | `delete!(ctx.meta, :price_provenance)` is the certificate's first action; after a structural-mismatch throw the reused ctx carries no marker. T-mismatch testitem extended with a pre-stashed stale marker. |
| WR-03 | fixed | `cd68bef` | Variant 3 → `(; mu_strategy = "adaptive", bound_push = 1e-4)`; each variant documents its delta from the factory/Ipopt defaults; literate sentence reworded to "up to 5 distinct … (default `n_seeds = 2`)". All 5 verified pairwise-distinct as normalized configurations and solvable. |
| WR-04 | fixed | `671f7a5` | Took the fuller option: `select_optimizer(NLP(); attrs...)` override seam + `nlp_multistart_variants()` both live in `factory.jl`, so the concrete solver name AND its option vocabulary stay in the one designated file; `ac_dual_fallback.jl` names no solver (grep-verified zero `Ipopt` references). |
| WR-05 | fixed | `485bb55` | H1 → "…A Gan-Low OPF-m Restriction"; TSODSO.jl comment → "OPF-m …, with optional OPF-ε margin". The honest OPF-ε negative-result narrative in the page body is untouched. |
| WR-06 | fixed | `5707073` | Validation moved into the INNER constructor (suppresses the auto-generated non-validating one), guarding kwarg AND positional paths with an `ArgumentError` naming the D-01 loosening hazard. Testitem covers both paths. |

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Shadow-voltage recursion silently assumes `branch.from` is the tree parent — undefined-memory read / garbage ε on legal reversed-orientation feeders

**File:** `src/models/ac_oracle.jl:219-227` (also `src/powerflow/RestrictedBranchFlow.jl:225-241`)
**Issue:** Both the post-processing `recover_lossfree_shadow_voltage` and the model-build OPF-m
constraint loop in `RestrictedBranchFlow.contribute!` build a rooted BFS tree but then discard
traversal direction (`branch_of_child[j] = abs(bsigned)`) and read the parent voltage as
`v̂_GL[br.from, t]`. This is only correct when every `Branch(from, to, …)` is stored
parent→child. The codebase explicitly does NOT guarantee that: `assert_radial`
(src/data/topology.jl) validates only tree-ness/connectivity, never orientation, and the
adjacent sibling `recover_voltage_angles` (src/models/ac_oracle.jl:54-58) documents verbatim
that *"a stored `Branch(from, to, …)` need not point parent→child"* and correctly keeps the
signed branch index to flip `S`. `ConvexBranchFlow` itself is orientation-agnostic (its DistFlow
drop and cone are written in the branch's own direction), so a reversed branch is a fully legal,
solvable feeder everywhere else in the framework.

On a feeder with one reversed branch (where `br.from` is the child `i`):

1. `recover_lossfree_shadow_voltage` reads `v̂_GL[br.from, t]` = `v̂_GL[i, t]` — an
   **uninitialized `Matrix{Float64}(undef)` entry** — and silently propagates garbage into the
   returned shadow voltage, the Lemma-1 sanity check, and any measured ε (the exact
   tolerance-provenance pipeline this project's standing bar protects). No error is raised.
2. `RestrictedBranchFlow.contribute!` hits a `KeyError` on `v̂_GL[br.from]` (Dict lookup of the
   not-yet-computed child) — loud but cryptic, and still a crash on a legal `Feeder`.
3. In both, `P̌ = pv.P[b, t] - LossInclR[i]` uses the branch's own-direction `P`/`Q` without the
   sign flip a reversed branch requires (flow toward the child is `−P[b]`), so even fixing the
   parent lookup alone yields a wrong shadow voltage.

Current fixtures (ieee13, ieee123 — "(parent_terminal, child_terminal)" — and the 3-bus test
feeders) all orient parent→child, so this is latent, but nothing validates it and this is a
researcher-facing framework where users construct their own `Feeder`s.

**Fix:** Track the parent explicitly and keep the sign, mirroring `recover_voltage_angles`:
```julia
# in the BFS: parent_of[j] = i; sign_of_child[j] = sign(bsigned)
# forward recursion, both copies:
Pb = sign_of_child[i] * value(pv.P[b, t])   # (or the AffExpr analog in contribute!)
Qb = sign_of_child[i] * value(pv.Q[b, t])
P̌ = Pb - LossInclR[i]
Q̌ = Qb - LossInclX[i]
v̂_GL[i, t] = v̂_GL[parent_of[i], t] - 2 * (br.r * P̌ + br.x * Q̌)
```
Minimum acceptable alternative: an explicit orientation guard in both functions —
`br.from == parent_of[i] || error("recover_lossfree_shadow_voltage requires parent→child branch orientation; branch $b is stored reversed")`
— converting silent garbage into a loud, documented refusal.

## Warnings

### WR-01: Certificate fabricates `formulation = :RestrictedBranchFlow` provenance for ANY context it is handed

**File:** `src/models/restriction_exactness.jl:266-270`
**Issue:** The D-08 provenance stash hardcodes `formulation = :RestrictedBranchFlow` regardless
of what `ctx_restricted` actually is. The certificate accepts any solved branch-flow context —
the phase's own tests exercise it on a plain `ConvexBranchFlow` context
(`test/test_restricted_branch_flow.jl:304`, `:416`), which then carries
`price_provenance.formulation == :RestrictedBranchFlow` — false provenance on a non-restricted
solve. Meanwhile `RestrictedBranchFlow.contribute!` stashes `ctx.meta[:formulation]`
(RestrictedBranchFlow.jl:246) explicitly "consumed by plan 20-03's certificate" — but the
certificate never reads it; the D-08 marker it was written for is dead weight.
**Fix:**
```julia
ctx_restricted.meta[:price_provenance] = (;
    formulation = get(ctx_restricted.meta, :formulation, :unknown),
    certificate = :assert_restriction_exact!,
    status = ac_feasible ? :certified_convex_dual : :cert_failed,
)
```

### WR-02: T-20-08 "stale marker never survives a later failure" contract violated on the structural-mismatch path

**File:** `src/models/restriction_exactness.jl:255-270`
**Issue:** The docstring (lines 108-110) promises the provenance marker is stashed
"UNCONDITIONALLY, on both the pass and fail path (so a stale marker from a prior call on a
reused `ctx` never survives a later failure, T-20-08)". But `assert_ac_exact!` is called at
line 255, BEFORE the stash at line 266, and it throws unconditionally on a horizon mismatch (and
`KeyError`s on missing `pf_vars`). On that failure path a stale `:certified_convex_dual` marker
from a prior call on the same reused ctx survives — exactly the hazard T-20-08 names. The
phase's own T-mismatch test (test_restricted_branch_flow.jl:310-353) uses fresh contexts, so
this gap is untested.
**Fix:** Scrub or pre-stash before any throwing call:
```julia
delete!(ctx_restricted.meta, :price_provenance)   # first line of the function
```
or move the stash (with a provisional `:cert_failed`) ahead of the `assert_ac_exact!` call and
overwrite it with the final verdict afterward.

### WR-03: `_FALLBACK_IPOPT_VARIANTS` contains a duplicate configuration — variant 3 is identical to variant 1, overstating D-11 multi-start evidence

**File:** `src/models/ac_dual_fallback.jl:31-37`
**Issue:** Ipopt's default `mu_strategy` IS `"monotone"`, so `(;)` (variant 1, "NLP() factory
default" — confirmed identical to `select_optimizer(NLP())`'s bare `print_level => 0`) and
`(; mu_strategy = "monotone")` (variant 3) are the same solver configuration. The file's own
D-11 comment claims "distinct, DETERMINISTIC Ipopt convergence-strategy variants... extended
from 2 to 5", but only 4 are distinct. A caller passing `n_seeds = 3` silently gathers a
duplicate trajectory as its third "seed": the agreement report's spread evidence is then partly
vacuous (a duplicate always agrees with seed 1 exactly), which is precisely the kind of
overstated confidence D-11's multi-start evidence exists to prevent. The literate page
(docs/literate/restricted_branch_flow.jl:284-285) compounds this by describing the fallback as
running "from 5 deterministic Ipopt convergence-strategy starts" when the default is
`n_seeds = 2`.
**Fix:** Replace variant 3 with a genuinely distinct strategy, e.g.
`(; mehrotra_algorithm = "yes")` or `(; mu_oracle = "loqo", mu_strategy = "adaptive")`, and
document each variant's delta from the Ipopt default. Reword the literate sentence to "from up
to 5 deterministic variants (default 2)".

### WR-04: `ac_dual_fallback.jl` hardcodes `Ipopt.Optimizer` in `src/`, violating the single-solver-factory constraint (INFRA-02)

**File:** `src/models/ac_dual_fallback.jl:96-100`
**Issue:** `factory.jl`'s header states it is "the ONLY core file (besides the ext/* package
extensions) that names concrete solvers," and CLAUDE.md's "What NOT to Use" table lists
hard-coding a solver inside a model as forbidden (models take an optimizer argument; the factory
is the abstraction). `ac_dual_fallback_price` constructs
`optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 0, ...)` directly — a second `src/`
file now names a concrete solver, and it compiles only because `factory.jl` happens to
`import Ipopt` at module scope (this file has no import of its own — see IN-05). The variant
attribute names are inherently Ipopt-specific, so if the NLP factory backend ever changes, this
file silently pins the old solver with no seam to swap it.
**Fix:** At minimum, derive the base from the factory and layer variants on top:
```julia
opt = MOI.OptimizerWithAttributes(
    select_optimizer(NLP()).optimizer_constructor,
    vcat(select_optimizer(NLP()).params,
         [MOI.RawOptimizerAttribute(String(k)) => v for (k, v) in pairs(variant)]),
)
```
or add a `select_optimizer(NLP(); attrs...)` / `nlp_multistart_variants()` seam in `factory.jl`
so the concrete solver name (and its variant vocabulary) stays in the one designated file.

### WR-05: Rendered docs headline mislabels the mechanism as "OPF-ε" when the page documents OPF-m

**File:** `docs/literate/restricted_branch_flow.jl:1` (also `src/TSODSO.jl:54`)
**Issue:** The literate page's title — the H1 of the rendered Documenter page — is "Rung 3 —
Overvoltage-Capable Relaxation: A Gan-Low OPF-ε Restriction". The page's own body (and the
entire phase, post-escalation) establishes that OPF-ε was the *failed* first attempt ("the
bound-shrink mechanism alone could not close this fixture's gap at ANY feasible value",
lines 305-311) and that the shipped mechanism is OPF-m (`v̂_GL(s) ≤ v̄`, Theorem 2), with OPF-ε
demoted to an optional, off-by-default margin. The title asserts the opposite of the page's
central finding. The include-graph comment in `src/TSODSO.jl:54` ("Gan-Low OPF-ε restricted
formulation") has the same stale label. Docs correctness is a hard project requirement, and
these two labels are exactly the conflation both docstrings repeatedly warn against.
**Fix:** Retitle to "…: A Gan-Low OPF-m Restriction" (or "…: Gan-Low Modified-OPF (OPF-m)
Restriction") and update the TSODSO.jl comment to "OPF-m (with optional OPF-ε margin)".

### WR-06: Negative `ε` is silently ignored instead of rejected — inconsistent with the phase's own no-silent-handling principle (T-20-12)

**File:** `src/powerflow/RestrictedBranchFlow.jl:110-113,164`
**Issue:** `RestrictedBranchFlow(; ε::Real = 0.0)` accepts any `Real`, and `contribute!` gates
the shrink on `pf.ε > 0.0`. A caller passing a negative ε (sign error on a "measured margin") is
silently treated as ε = 0 — no shrink, no error, no warning. The guard prevents the worse
outcome (a negative ε applied via `set_upper_bound` would LOOSEN the voltage bound, converting
the "genuine restriction, never a relaxation" D-01 contract into a relaxation), but silent
acceptance of invalid input contradicts this same phase's T-20-12 discipline in
`ac_dual_fallback_price` ("no silent clamping, so a caller's typo ... is never masked").
**Fix:** Validate in the constructor:
```julia
function RestrictedBranchFlow(; ε::Real = 0.0)
    ε >= 0 || throw(ArgumentError("RestrictedBranchFlow ε must be ≥ 0 (a negative ε would LOOSEN the voltage bound, violating D-01); got $ε"))
    return RestrictedBranchFlow(Float64(ε))
end
```
(and guard the positional `RestrictedBranchFlow(x)` path equivalently).

## Info

### IN-01: `:opfm_shadow_voltage` registered as a flat untyped `Any[]`, losing the (bus, hour) addressing its own diagnostics cite

**File:** `src/powerflow/RestrictedBranchFlow.jl:200,237-243`
**Issue:** The OPF-m constraints are pushed into `opfm_constraints = Any[]` in
(t-outer, BFS-order-inner) order and registered as a flat vector. The certificate's docstring
cites per-(bus, hour) duals ("up to `-24.18` at bus 3, hour 9",
restriction_exactness.jl:168-171) and even sketches
`dual(ctx.constraints[:opfm_shadow_voltage][...])` — but the flat vector cannot be indexed by
(bus, hour) without re-deriving the BFS push order. The test (line 265) can only take a blind
`maximum`.
**Fix:** Register a `Dict{Tuple{Int,Int},ConstraintRef}` keyed `(i, t)` (or a
`JuMP.Containers.DenseAxisArray`), making the documented diagnostic actually addressable and the
container concretely typed.

### IN-02: Stale plan-20-01 comments in the test file describe ε as the future "default kwarg"

**File:** `test/test_restricted_branch_flow.jl:15-18,92-95`
**Issue:** The file header ("a MEASURED, never-searched default for plan 20-02's
`RestrictedBranchFlow` shrink kwarg") and the second testitem's closing comment ("This exact
printed value is what plan 20-02's RestrictedBranchFlow default kwarg will hardcode") predate
the OPF-m pivot: ε is no longer the default (default is `0.0`; `_EXACT04_MEASURED_ε` is an
optional, explicitly-passed margin). Later comments in the same file state the pivot correctly.
**Fix:** Update both comments to "retained as the optional composable OPF-ε margin
(`_EXACT04_MEASURED_ε`), no longer the default after the OPF-m pivot (20-02-SUMMARY.md)".

### IN-03: Unused test-item locals

**File:** `test/test_restricted_branch_flow.jl:117,232,382,407`
**Issue:** `cost`/`dadp` (item 3), `cost_restricted` (items 5 and 7), and item 7's
`cost_unrestricted` are bound and never used.
**Fix:** Replace with `_` placeholders for the values genuinely unused, keeping named bindings
only where asserted.

### IN-04: `matches_ac_optimum` ignores reactive-flow divergence (`qgap` excluded from `exact`)

**File:** `src/models/restriction_exactness.jl:255-256` (root: `src/models/ac_oracle.jl:298`)
**Issue:** `matches_ac_optimum = all(row.exact ...)` inherits `assert_ac_exact!`'s `exact`
predicate, which tests `vgap` and `pgap` only — `qgap` is computed, returned, and never gated.
A restricted dispatch differing from the AC optimum only in reactive flow would report
`matches_ac_optimum = true`. The exclusion is pre-existing (phase 15) and may be deliberate
there, but the phase-20 certificate promotes this predicate to a headline named diagnostic
without documenting that Q divergence is not part of "matches".
**Fix:** One sentence in the `matches_ac_optimum` docstring section: "the per-hour `exact` flag
gates voltage and active-flow gaps only; inspect `hours[t].qgap` for reactive divergence" — or
extend the predicate with a `qgap` term against a Q-scale magnitude.

### IN-05: Missing local `import Ipopt`; self-refuting "confirmed by grep" claim

**File:** `src/models/ac_dual_fallback.jl:24,60-62,96`
**Issue:** (a) The file uses `Ipopt.Optimizer` but carries only `using JuMP`; it resolves solely
because `solver/factory.jl` does `import Ipopt` at module scope — an invisible load-order
dependency the include-graph comment in TSODSO.jl does not mention (subsumed by WR-04's proper
fix, but if the direct reference stays, add the import locally). (b) The docstring's trigger-
discipline evidence — "confirmed by `grep -n 'assert_restriction_exact!\|solve_restricted'`
returning no matches in this file" — is literally false as written: the pattern matches the very
comment (and docstring) that states it. The underlying claim (no *call* relationship) is true.
**Fix:** Reword to "this file contains no call to `assert_restriction_exact!` (references below
are documentation only)".

---

_Reviewed: 2026-08-09T00:28:28Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

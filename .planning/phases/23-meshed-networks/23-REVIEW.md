---
phase: 23-meshed-networks
reviewed: 2026-08-10T15:15:30Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - src/TSODSO.jl
  - src/data/mesh_topology.jl
  - src/data/MeshedFeeder.jl
  - src/powerflow/MeshedFlow.jl
  - src/models/mesh_angle_certificate.jl
  - test/fixtures_phase23.jl
  - test/test_mesh_feeder.jl
  - test/test_mesh_flow.jl
  - test/test_mesh_angle_certificate.jl
  - docs/literate/meshed_reactive_price.jl
  - docs/make.jl
  - docs/Project.toml
findings:
  critical: 2
  warning: 3
  info: 6
  total: 11
status: issues_found
fixes:
  fixed_at: 2026-08-10
  scope: critical_warning
  fixed: 5
  skipped: 0
  commits:
    CR-01: f6190bd
    CR-02: 85546cc
    WR-01: 7f1ad76
    WR-02: ee4e376
    WR-03: 259f766
---

# Phase 23: Code Review Report

**Reviewed:** 2026-08-10T15:15:30Z
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Fix Status (2026-08-10)

All in-scope findings (2 Critical + 3 Warning) fixed, one atomic commit each:

| Finding | Status | Commit | Note |
|---------|--------|--------|------|
| CR-01 | FIXED | `f6190bd` | Backward tree edges now use `−(S_b − z·ℓ_b)`; docstring + traversal comments corrected (IN-01's BFS→DFS mislabel fixed in passing on touched lines). |
| CR-02 | FIXED | `85546cc` | Bound direction corrected everywhere: the SOCP welfare objective is an UPPER bound on the true AC welfare optimum (`W_SOCP ≥ W_AC`; relaxation maximizes over a superset of the AC-feasible points). |
| WR-01 | FIXED | `7f1ad76` | Defaults rebalanced to `atol = rtol = 0.01` (combined bound ≈0.02 at the log-midpoint ≈0.0195; balanced ≈3.2×/≈3.0× margins). Verdicts unchanged on both profiles. |
| WR-02 | FIXED | `ee4e376` | Literate page's four load-bearing claims now guarded with `\|\| error(...)`; wrong "never reaches here" comment fixed. Page verified end-to-end. |
| WR-03 | FIXED | `259f766` | Reversed-orientation regression added — with a documented deviation from the suggested single-branch flip (see below). |

**WR-03 deviation (single-branch flip is not solver-equivalent):** flipping one stored
branch on the diamond turns the exactness-copy cycle identity's even 2-2 ε-split into a
3-1 split, producing a structural ~4e-2 cone gap that `solve_welfare` refuses (the fixture
header's flipped-triangle mechanism). The committed regression instead uses the FULL
root-inward reversal (global ε sign flip — the physically-identical re-encoding that
preserves the identity), which traverses ALL THREE tree edges backward. The same identity
(`Σ ε_b·|z_b|²·ℓ_b = 0`) makes the chord residual nearly immune to the CR-01 bare-flip bug
(per-edge `|z|²·ℓ` errors telescope to ≈0 around the cycle), so CR-01's material effect is
on the RECOVERED PHASOR FIELD (~0.6% voltage error on `:heterogeneous` backward edges — a
certified output), and the regression asserts phasor-field invariance (`< 1e-8`, measured
~2e-10 post-fix vs ~5.6e-3 pre-fix on the radial big-impedance probe) rather than the
review's residual `rtol = 1e-6` (unachievable: the reversal necessarily flips the chord's
anchor endpoint, a measured ~2% second-order effect on `:heterogeneous`).

Info findings: IN-01 partially fixed in passing (`mesh_angle_certificate.jl` only;
`mesh_topology.jl` untouched). IN-02–IN-06 remain open (out of fix scope).

## Summary

Phase 23 (Meshed Networks) was reviewed against the six scrutiny priorities: chord-aware
angle-recovery math, certificate semantics, radial-path protection, tolerance derivation,
fixture math, and delegation purity. Cross-referenced files (`src/models/ac_oracle.jl`,
`src/powerflow/ConvexBranchFlow.jl`, `src/models/welfare_solve.jl`, `src/core/status.jl`,
`src/units/PerUnit.jl`, `src/devices/Aggregator.jl`, `test/fixtures_phase19.jl`) were read
to verify every delegation, stash-key, and "verbatim" claim.

**What holds up:** Radial-path protection is verified — `git diff dd96dfe..HEAD --name-only`
touches no radial source file (`Feeder.jl`, `topology.jl`, `ac_oracle.jl`,
`ConvexBranchFlow.jl` all byte-unchanged); the new `problem_class(::MeshedFlow)` method is
purely additive. Delegation purity is verified — `MeshedFlow.contribute!` adds zero
constraint semantics (one delegated call + one meta stash), and `ConvexBranchFlow`'s KCL
loop (ConvexBranchFlow.jl:213-227) is confirmed graph-generic. The fixture's
triangle-degeneracy derivation is verified against the actual `vdrop`/`cpydrop` constraint
coefficients (ConvexBranchFlow.jl:160-186): subtracting the `v`/`v̂` cycle telescopes yields
`Σ ε_b·3(r²+x²)·l_b = 0`, i.e. the claimed identity up to a harmless factor of 3, and the
odd-cycle zero-forcing conclusion follows. `solve_welfare` is duck-typed (untyped `feeder`
argument), `assert_magnitudes` is topology-blind, `:balance_q` is registered on the reactive
path, and `assert_solved!`'s error message contains the termination status — so every
dependency the new code and the literate page rely on exists.

**What does not hold up:** the certificate's tree traversal replicates the exact Phase-20
CR-01 class of bug (bare sign flip on backward-traversed branches, omitting the branch's own
loss term) into a context where the omitted term is the same order of magnitude as the
residual being certified (CR-01); and the certificate's core scientific output claim —
"the solved objective remains a valid LOWER BOUND on the true AC optimum" — has the bound
direction backwards for this codebase's welfare *maximization* (CR-02). The tolerance
derivation is also internally inconsistent with its own "geometric mean" rationale, leaving
an asymmetric 6.4×/1.5× margin split (WR-01).

## Narrative Findings (AI reviewer)

## Critical Issues

### CR-01: Backward-traversed tree edges use a bare sign flip, omitting the branch's own loss term — the Phase-20 CR-01 bug class, replicated into new code where it is material

**Fix status:** FIXED in `f6190bd` (exact suggested correction applied; docstring/comments updated).
**File:** `src/models/mesh_angle_certificate.jl:199-202` (and the docstring claim at line 64)
**Issue:** For a tree edge traversed against its stored orientation (`bsigned < 0`), the
recursion negates the *sending-end* power and divides by the *receiving-end* voltage:

```julia
S = bsigned > 0 ? Complex(value(pv.P[b, t]), value(pv.Q[b, t])) :
    -Complex(value(pv.P[b, t]), value(pv.Q[b, t]))
Vphasor[j, t] = Vphasor[i, t] - z * conj(S) / conj(Vphasor[i, t])
```

The branch-flow variables `P[b], Q[b]` are sending-end flows measured at `br.from`
(ConvexBranchFlow charges the loss `−r·l/−x·l` at the `to` end — its own KCL comment,
ConvexBranchFlow.jl:208-210). When walking `to → from`, the power flowing toward the child,
measured at the parent (the `to` end), is the negated *receiving-end* flow
`−(S_b − z·l_b)`, not `−S_b`. The exact backward recursion is
`V_from = V_to + z·conj(S_b − z·l_b)/conj(V_to)`; the code computes
`V_to + z·conj(S_b)/conj(V_to)`, an error of exactly `|z|²·l_b/|V|` per backward edge.

This is precisely the bug class `recover_lossfree_shadow_voltage`'s own docstring
(ac_oracle.jl:157-169) documents from Phase-20 CR-01: "A bare sign flip `−P[b]` alone would
be off by the feeding branch's own `r·ℓ[b]`" — here in the phasor domain, off by `z·l_b`.
The pattern is inherited verbatim from `recover_voltage_angles` (ac_oracle.jl:101-105),
where it is negligible on lightly-impedanced radial fixtures (`|z|²·l ~ 1e-5`). It is NOT
negligible here: on the committed `:heterogeneous` profile (`|z|² up to ≈0.24`,
`l_b ~ 0.01–0.06`), the omitted term is `≈0.002–0.015` — the same order as the `:uniform`
residual floor (`0.00627`) and a large fraction of the fail-side margin
(`0.0607 − 0.04 = 0.021`).

Consequence: the certification verdict depends on branch *storage orientation*, which is
physically meaningless and unconstrained by `assert_connected`. Re-encoding the committed
diamond with `Branch(4, 2, …)` instead of `Branch(2, 4, …)` — a byte-identical physical
network — forces a backward tree edge, shifts the chord residual by up to `~0.015`, and can
silently flip the verdict near the bound. The docstring's claim ("sign-flipped if traversed
backwards — this evaluates the branch's OWN defining equation") presents the bare flip as
sufficient; it is not. The committed fixture happens to store all four branches root-outward,
so the DFS never traverses backward and all committed measurements/tests are unaffected —
which is exactly why this ships silently.

**Fix:** subtract the branch's own loss before negating, using the already-stashed `pv.l`:

```julia
S = if bsigned > 0
    Complex(value(pv.P[b, t]), value(pv.Q[b, t]))
else
    # receiving-end flow at the parent (loss charged at the branch's `to` end),
    # negated toward the child: −(S_b − z·l_b)  [Phase-20 CR-01 lesson, phasor domain]
    -(Complex(value(pv.P[b, t]), value(pv.Q[b, t])) - z * value(pv.l[b, t]))
end
```

and add the reversed-orientation regression test (see WR-03). Note the identical latent
defect exists in `recover_voltage_angles` (ac_oracle.jl, byte-locked this phase, D-09) —
flag it for a follow-up plan rather than silently diverging from the "verbatim" claim; if
the certificate is fixed and the oracle is not, the "IDENTICAL recursion" comment at
mesh_angle_certificate.jl:177-182 must be updated.

### CR-02: Certificate's output contract states the wrong bound direction — the SOCP welfare objective is an UPPER bound on the true AC optimum, not a lower bound

**Fix status:** FIXED in `85546cc` (all four locations; no test asserted the old message text).
**File:** `src/models/mesh_angle_certificate.jl:52-53, 96-97, 255-256`; `docs/literate/meshed_reactive_price.jl:154-157`
**Issue:** The docstring (twice), the unrecoverable-path `@warn`/`error` message, and the
literate page all claim: "`objective_value(ctx.model)` ... remains a valid LOWER BOUND on
the true AC optimum (per Low arXiv:1405.0814)". Low's statement is for *minimization*
(cost) OPF, where a relaxation's optimum lower-bounds the true optimum. This codebase's
`solve_welfare` is a **maximization** (`@objective(model, Max, welfare)`,
welfare_solve.jl:238-239), and the caller is explicitly directed to read
`objective_value(ctx.model)` — the welfare value. A relaxation of a maximization satisfies
`W_SOCP ≥ W_AC`: the solved objective is an **upper** bound on the true AC welfare optimum.
As written, the certificate's primary interpretive output (D-07's entire content for the
unrecoverable branch) tells the researcher the true AC optimum is *at least* the reported
value, when in fact it is *at most* that value — the exactly wrong scientific conclusion, in
a project whose core value is "trustworthy results ... with every model assumption
documented". The claim appears verbatim in the user-facing warning message, so every
unrecoverable run actively prints the false statement.
**Fix:** correct the direction in all four locations, e.g.:

```
the SOCP objective is a valid UPPER BOUND on the true AC welfare optimum only
(equivalently, a lower bound on the true minimum cost), NOT a certified AC operating point
```

and mirror the correction in the literate page's "Stated plainly (D-10)" paragraph.

## Warnings

### WR-01: Tolerance derivation is internally inconsistent with its stated "geometric mean" rationale; the fail-side margin is only 1.5×

**Fix status:** FIXED in `7f1ad76` (option (a): `atol = rtol = 0.01`; verdicts re-verified on both profiles).
**File:** `src/models/mesh_angle_certificate.jl:135-144` (docstring), `:238` (the bound)
**Issue:** The docstring says defaults are "centered roughly at the GEOMETRIC MEAN of the
two measured floors" and that "the combined bound `atol + rtol·scale ≈ 0.04` sits almost
exactly between the two measured floors." Neither holds: the geometric mean of
0.00627 and 0.0607 is `≈0.0195`; the arithmetic mean is `≈0.0335`. Each *individual*
default (0.02) sits at the geometric mean, but the decision variable is the combined bound
`atol + rtol·scale ≈ 0.04` — 2.05× the geometric mean, 66% of the way (linearly) toward the
failing floor. The resulting margins are asymmetric: ≈6.4× on the certify side but only
**≈1.52×** on the unrecoverable side (0.0607 vs 0.04). The measured 9.7× floor separation
is adequate, but the threshold placement squanders most of it on one side: a ~34% downward
drift in the `:heterogeneous` residual (solver version bump, MOI bridge change, Clarabel
tolerance change — the class of drift MEMORY.md's SOCP-knife-edge note documents on this
repo) silently flips `test_mesh_angle_certificate` items (b)/(c) and the certificate's
committed semantics. The docstring honestly reports both margins, but the "almost exactly
between" characterization contradicts its own numbers.
**Fix:** either (a) set `atol = rtol = 0.01` so the combined bound `≈0.02` actually sits at
the log-midpoint, giving balanced ≈3.2×/≈3.0× margins on both sides, and re-run both
profiles to confirm; or (b) keep the values but rewrite the derivation paragraph to state
plainly that the combined bound is 2× the geometric mean with a 6.4×/1.5× asymmetric split,
and why the thin fail-side margin is acceptable. Option (a) is strictly better for test
stability.

### WR-02: Literate page's load-bearing claims are displayed but never asserted — a regression ships docs that contradict their own output

**Fix status:** FIXED in `ee4e376` (guards on all four claims; comment corrected; page runs end-to-end).
**File:** `docs/literate/meshed_reactive_price.jl:91-108, 142-157, 183`
**Issue:** The page's central factual claims are computed live but never enforced:
(1) `triangle_infeasible` (line 91-104) is displayed, and the prose asserts
"`triangle_infeasible === true` above confirms, live, ..." — but if a future change makes
the triangle solvable (or the failure message stops containing "INFEASIBLE", or a non-
`ErrorException` is thrown), the page silently renders `false` directly beneath prose
claiming it is `true`. The inline comment "it never reaches here" (line 99) is wrong — the
`false` branch is exactly the reached-on-regression path. (2) Similarly,
`certify_angle_recoverable!(ctx_bess; ...).status` (line 183) and the `r_u`/`r_h` statuses
(lines 142-150) are displayed but not asserted, while the "Finding" section states their
values as fact. The project's own docs discipline ("Doctests keep examples honest",
CLAUDE.md) argues these live claims should be self-checking.
**Fix:** enforce each claim with an explicit error, e.g. after line 104:

```julia
triangle_infeasible || error("Rung 10 doc regression: the odd triangle solved — the degeneracy derivation no longer holds")
```

and analogous one-line guards for `r_u.status == :angle_certified`,
`r_h.status == :angle_unrecoverable`, and the Section-3 certified status. Also fix the
"never reaches here" comment.

### WR-03: No reversed-orientation regression test for the certificate, despite the codebase's own Phase-20 precedent

**Fix status:** FIXED in `259f766` (full root-inward reversal instead of the suggested single-branch flip — see "Fix Status" section's deviation note; phasor-field invariance is the discriminating assertion).
**File:** `test/test_mesh_angle_certificate.jl` (coverage gap, whole file)
**Issue:** Phase-20's CR-01 established the discipline of testing signed-orientation code
against "a byte-identical reversed-orientation re-encoding of the same physical point"
(ac_oracle.jl:167-169, enforced in `test/test_restricted_branch_flow.jl`). The new
certificate is signed-orientation code measuring residuals near a 1.5× margin, yet no test
re-encodes the diamond with a flipped branch (e.g. `Branch(4, 2, …)`) and asserts the
verdicts are unchanged. Such a test would have caught CR-01 immediately — on the current
code, the flipped encoding changes `worst_residual` by the omitted `|z|²·l` term.
**Fix:** add a `@testitem` that builds both profiles with branch 3 stored as
`Branch(4, 2, rx[3]..., SMAX_NO_LIMIT)` (same physics, reversed storage), re-solves, and
asserts `recoverable`/`status` match the canonical encoding's, and that `worst_residual`
agrees within a tight tolerance (e.g. `rtol = 1e-6`), after applying the CR-01 fix.

## Info

### IN-01: Traversals labeled "BFS" are actually DFS (`pop!` on a `Vector` is LIFO)

**Fix status:** PARTIALLY FIXED in passing in `f6190bd` (`mesh_angle_certificate.jl` relabeled DFS on the CR-01-touched lines; `mesh_topology.jl` untouched, still open).
**File:** `src/data/mesh_topology.jl:84-105`; `src/models/mesh_angle_certificate.jl:177-207`
**Issue:** Both files use `queue = [root]; ... u = pop!(queue)` — `pop!` removes from the
end, making the traversal depth-first, while comments/docstrings say "BFS" throughout
(inherited verbatim from `recover_voltage_angles`/`assert_radial`, which mislabel it the
same way). Correctness is unaffected (connectivity and any-spanning-tree both suffice), but
the docstring's "BFS spanning tree" description does not match the tree actually built,
which matters when reasoning about which branch becomes the chord.
**Fix:** either say "DFS" (or "graph traversal") in the new files' comments, or use
`popfirst!` if BFS order is genuinely intended. Do not change `ac_oracle.jl` this phase
(D-09) — just stop propagating the mislabel into new code.

### IN-02: Stale heterogeneous cone-gap figure in the fixture header

**File:** `test/fixtures_phase23.jl:52-54`
**Issue:** Line 53 claims "Empirically verified (this plan, both profiles ...): cone gaps of
`1.6e-8` (`:uniform`) and `1.8e-9` (`:heterogeneous`)" — but the committed `:heterogeneous`
profile is the 8×-scaled one, whose cone gap the same file's own later section (line 99) and
the certificate docstring both report as `~1.8e-11`. The `1.8e-9` figure belongs to the
superseded pre-8× literals and now reads as a measurement of the committed fixture.
**Fix:** update line 53 to `~1.8e-11` (or annotate that `1.8e-9` was measured at the
original 1× literals).

### IN-03: Test comment contradicts itself on the separation magnitude

**File:** `test/test_mesh_angle_certificate.jl:66-67`
**Issue:** "(e) Residual ordering: :heterogeneous sits multiple orders-of-magnitude
(measured ~9.7x, D-08) above :uniform's" — 9.7× is less than one order of magnitude; the
parenthetical refutes the claim it decorates. The assertion itself (`> 5 *`) is fine.
**Fix:** reword to "sits ≈9.7× (measured, D-08) above".

### IN-04: `assert_connected` silently admits self-loop branches

**File:** `src/data/mesh_topology.jl:62-66`
**Issue:** A branch with `from == to` passes the endpoint-range check, contributes a
cancelled (zero) incidence column, and never affects connectivity — so
`MeshedFeeder(buses, [..., Branch(2, 2, ...)], root)` constructs successfully.
`assert_radial` rejects self-loops indirectly (a self-loop wastes an edge, breaking
`B == N-1` + connectivity); the meshed validator has no such backstop. Downstream the
self-loop is permanently a chord in the certificate (benign in practice — the optimizer
drives its `l = P = Q = 0`, residual 0 — but a physically nonsensical feeder should fail at
the construction gate, per the "construction-is-the-gate" discipline).
**Fix:** add to the endpoint loop: `br.from != br.to || throw(ArgumentError("Branch $b is a self-loop ($(br.from)->$(br.to))."))`.

### IN-05: Certificate scrubs provenance, then can die with a bare `KeyError` on a structurally unsuitable context

**File:** `src/models/mesh_angle_certificate.jl:160-164`
**Issue:** `ctx.meta[:feeder]` / `[:T]` / `[:pf_vars]` are indexed directly after the
provenance scrub. A DC/LinDistFlow context (no `:pf_vars`) — or any ctx not built by
`solve_welfare` — raises an uninformative `KeyError`, leaving the ctx with its provenance
deleted. The sibling `assert_ac_exact!` deliberately raises structured errors on "STRUCTURAL
mismatch (differing horizon `T`, missing `pf_vars` keys)" (ac_oracle.jl:26).
**Fix:** guard the reads:
`haskey(ctx.meta, :pf_vars) || error("certify_angle_recoverable! needs ctx.meta[:pf_vars] (a branch-flow context); got a context without it (MESH-03).")` (and similarly for `:feeder`/`:T`).

### IN-06: "Byte-identical to fixtures_phase19" parenthetical is easy to misread

**File:** `docs/literate/meshed_reactive_price.jl:162-166`
**Issue:** The BESS is introduced as "(the project's standard battery price triple,
byte-identical to `test/fixtures_phase19.jl`'s own committed values)". The price triple
(3.8/6.2/8.9) does match, but the power/energy parameters do not
(0.05/0.05/0.08/0.0/0.2/0.1 here vs Phase 19's 0.02/0.02/0.03/0.0/0.08/0.04). The sentence
is technically scoped to the triple, but a reader skimming will conclude the whole device is
the Phase-19 fixture device.
**Fix:** "(its λ_min/λ_med/λ_max price triple byte-identical to `test/fixtures_phase19.jl`;
power/energy ratings sized up for this fixture's loads)".

---

_Reviewed: 2026-08-10T15:15:30Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

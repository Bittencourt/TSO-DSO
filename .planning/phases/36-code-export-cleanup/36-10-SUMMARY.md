---
phase: 36-code-export-cleanup
plan: 10
subsystem: hygiene
tags: [planning-id-scrub, models, pricing]
requires: ["36-09"]
provides:
  - src/models/*.jl and src/pricing/*.jl free of planning identifiers (classifier TOTAL 0 over both directories)
affects: [36-11]
key-files:
  modified:
    - src/models/ac_oracle.jl
    - src/models/exactness.jl
    - src/models/restriction_exactness.jl
    - src/models/mesh_angle_certificate.jl
    - src/models/stochastic_welfare.jl
    - src/models/mpc_window.jl
    - src/models/ac_dual_fallback.jl
    - src/models/complementarity_4q.jl
    - src/models/linear_solve.jl
    - src/models/mpc_trace.jl
    - src/models/oracle.jl
    - src/models/toy_dc.jl
    - src/models/welfare_solve.jl
    - src/pricing/checks.jl
    - src/pricing/dlmp.jl
    - src/pricing/fit.jl
    - src/pricing/welfare.jl
requirements-completed: []
completed: 2026-10-05
---

# Phase 36 Plan 10: Scrub of src/models and src/pricing Summary

Planning identifiers (phase, plan, requirement, decision, review-finding, threat, pitfall and research-artifact references; about 570 classifier hits in 17 files) were removed from `src/models` and `src/pricing`, keeping each rationale as plain prose. The classifier reports TOTAL 0 over both directories. HYG-01 stays pending (later scrub plans and the CI guard remain).

## Commits
- 2d3d61f: scrub ac_oracle, exactness, restriction_exactness, mesh_angle_certificate, stochastic_welfare, mpc_window
- 1a2dab4: JuliaFormatter 2.10.2 pass (check_content_loss OK)
- fb79208: scrub ac_dual_fallback, complementarity_4q, linear_solve, mpc_trace, oracle, toy_dc, welfare_solve, pricing/{checks,dlmp,fit,welfare}
- 3c2faeb: JuliaFormatter 2.10.2 pass (check_content_loss OK)

## Verification
- Classifier: TOTAL 0 on the plan file set and on all of `src/models` and `src/pricing`.
- ast_equiv.jl against the plan-start commit (7792a17): EQUAL for all 17 files.
- thesis_tokens.py: OK. format210.jl re-run over the whole set is a no-op; check_content_loss.py HEAD prints OK.
- Targeted tests: Task 1 set (ac_oracle, exactness, mesh_angle_certificate, mpc_window, migration gate) 101 pass; Task 2 set (oracle, pricing dlmp/welfare/fit, welfare_solve, fourquadbess, migration gate) 881 pass + 1 pre-existing broken; Task 3 set (stochastic_welfare, linear_solve, migration gate) 51 pass. 0 failed, 0 errored. Canary and goldens untouched.

## Message changes
Runtime strings changed (grep of `test/` found no assertion on any of them; `ast_equiv.jl --strings` output reviewed and every entry is listed):

exactness.jl
- ArgumentError: `(FIX-08 head-branch convention requires at least one)` became `(the head-branch convention requires at least one)`.
- CertificateError: `prices REFUSED (thesis 3.43-3.45; PF-04)` became `prices REFUSED (thesis 3.43-3.45)`.

restriction_exactness.jl (CertificateError/@warn text)
- `(Gan-Low OPF-m/OPF-ε, Theorem 2; OVR-02). See restriction_exactness.jl's docstring for the EXACT-04 reference verdict.` became `(Gan-Low OPF-m/OPF-ε, Theorem 2). See restriction_exactness.jl's docstring for the high-PV reference verdict.`

mesh_angle_certificate.jl (CertificateError/@warn text)
- `(Gan-Low angle-recovery condition; MESH-03).` became `(Gan-Low angle-recovery condition).`

complementarity_4q.jl (CertificateError/@warn text)
- `— MESH-04 clause 2; if this` became `— clause 2 of the 4Q certificate; if this`.
- `the honest boundary D-08 documents rather than` became `the honest boundary documented in the derivation rather than`.

welfare_solve.jl (battery complementarity @warn)
- `(relative τ=…, Pmax≈…; App. C, threat T-03-13)` became `(…; App. C)`.

pricing/checks.jl (ArgumentError x2)
- `(shape guard, T-05-11)` became `(shape guard)`.
- `(its exactness-gated DADP dual; threat T-05-01)` became `(its exactness-gated DADP dual)`.

pricing/dlmp.jl (ArgumentError/error text)
- `the PF-04 exactness certificate` became `the exactness certificate`; `(thesis 3.43-3.45; PF-04 gate — see assert_socp_exact!)` became `(thesis 3.43-3.45; see assert_socp_exact!)`.
- `radial tree (DATA-02)` became `radial tree`.
- `registered by plan 05-01)` became `registered by the formulation)`.
- `mis-signed (RESEARCH Pitfall 2; thesis …; threat T-05-02).` became `mis-signed (thesis …).`

pricing/fit.jl (SolveFailedError / error text)
- `never silently accepted (plan 27-09, USER DECISION 2026-09-29) — this is` became `never silently accepted — this is`.
- `possible unit slip — Pitfall 5)` became `possible unit slip)`.

pricing/welfare.jl (ArgumentError/error text)
- `carrying the plan 05-01 surplus stash` became `carrying the surplus stash`.
- `(Open Q2: if it fails by a loss-sized amount, …; threat T-05-03)` became `(if it fails by a loss-sized amount, …)`.
- `(plan 05-03, thesis 3.24-3.28)` became `(thesis 3.24-3.28)`.
- `(degenerate baseline; threat T-05-04)` became `(degenerate baseline)`.
- `possible unit slip — Pitfall 5)` became `possible unit slip)`.

No `@testitem` names changed. (Test files still carry their own planning wording; those belong to the test-scrub plans.)

## Hand-edited MIXED lines
Thesis references (3.31, 3.33, 3.36, 3.37, 3.38, 3.39, 3.43-3.45, 3.46, 3.47, 3.24-3.28, eq. 3.23) on the mixed lines in `exactness.jl`, `pricing/dlmp.jl`, `pricing/fit.jl` and `pricing/welfare.jl` were kept verbatim, confirmed by thesis_tokens.py. Literature references (Gan-Low Theorem 2 and Lemma 1, Birge-Louveaux, Farivar-Low, App. C) were left verbatim.

## Deviations from Plan
- [Rule 1] Process wording the classifier cannot catch was reworded in the same files: `pre-27-07`, `pre-FIX-08`, `spike-002/003`, `27-FINDINGS.md`/`26-FINDINGS.md`, `Open Q`/`Open-Question`, "Wave 3/4", "this phase", "this plan", `orchestrator-revision addendum`, `STATE.md flag`, "review N" and `byte-identical` (became `bit-for-bit identical`, or `UNCHANGED` where it described a code-path guarantee). `SITE-3` (matched by the SITE-N rule) became `SITE 3`.
- A semi-automatic first pass (scratch script outside the repo) removed ID tokens; each hunk was then reviewed and the dangling fragments (orphaned parentheses, possessives, "fix review", stripped leading colons) rewritten by hand. `fit.jl` was redone from the original text with an explicit replacement list because the automatic pass degraded it.
- The plan's Task 3 says to record the plan-start hash in `.planning/tmp/36/`; it is `7792a17`. (The rtk shell hook rewrites `git diff --name-only`, so the final checks used an explicit file list.)

## Known Stubs
None.

## Self-Check: PASSED

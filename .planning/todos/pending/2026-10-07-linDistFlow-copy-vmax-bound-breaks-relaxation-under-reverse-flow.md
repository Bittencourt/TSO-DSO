---
title: LinDistFlow exactness-copy bound v̂ ≤ vmax² makes the SOCP not a relaxation of AC under reverse flow
created: 2026-10-07
source: Phase 37 code review (PV-boom Part A2 stress fixture)
area: model-correctness (research decision)
---

Measured on the PV-boom Part A2 stress fixture (scripts/pv_boom_case_study.jl, findings.txt):
- obj_gap (SOCP − AC, both maximizing welfare) = −0.4773 → the SOCP optimum is worse than an
  AC-feasible point, so the SOCP as configured is NOT a relaxation of the AC model here.
- The `v̂ ≤ vmax²` bound on the LinDistFlow exactness copy (src/powerflow/ConvexBranchFlow.jl ~:258,
  thesis eq. 3.45; the AC model has no v̂) is active at hours 9–12 and 15; the AC solution sits at
  v = vmax² in those hours, and at the AC point the copy recursion gives v̂ up to 1.111137 > 1.1025.
- Deleting only the v̂ upper bounds: obj_gap → −9.73e-6 (99.998 % of the gap removed), cone still
  tight (1.66e-7); one hour (7) still differs (not investigated).

Decision needed (modelling): keep thesis-literal 3.45 (document that it can cut AC-feasible points under
reverse flow), or relax/condition the v̂ bound (affects exactness claims, goldens, thesis reproduction).
Relates to memory note v2.1-socp-inexactness-and-thesis-repro and the "exactness copy" fixes of v4.0
Phase 26. Do not change silently — goldens and the knife-edge canary depend on the current model.

---
status: complete
phase: 42-thesis-case-a-magnitude
source: [42-VERIFICATION.md]
started: 2026-10-26
updated: 2026-10-27
---

## Current Test

[testing complete]

## Tests

### 1. Rendered writeup page visual review
expected: docs/build/generated/case_a_magnitude.html renders cleanly (nav entry, tables, live figures) and the prose honestly frames the UNDEFINED registered-mix gain and the NOT-FULLY-ATTRIBUTED statement.
result: pass
evidence: "Docs rebuilt 2026-10-27 09:23 after WR-03 (b5ece3a had landed post-build): exit 0, page 62.8 KB fresh. Render shows structural UNDEFINED headline ('certified pairs 0 of 5 seeds → headline Δ%: UNDEFINED (no W_FIT exists to divide by)'), live-recomputed seed→rung attribution (42/46 via gap_1e-10 after CertificateError iters 80; 43/44/45 default), 47 honest refusal rows (12 CertificateError / 27 SolveFailedError / 4 ladder_exhausted), 'three-to-seven orders below the thesis +25%', 'The gap is NOT FULLY ATTRIBUTED' section. User confirmed 2026-10-27."

### 2. Optional: re-run the :slow reproducibility item
expected: ~47 min live 784-house seed-42 run reproduces the committed magnitude row within WELFARE_RTOL=1e-8 (strongest independent confirmation rows are machine-produced).
result: skipped
reason: "User declined re-run ('skio' → skip) 2026-10-27 — the band was already certified bit-exact (delta 0.0, WELFARE_RTOL=1e-8) during 42-06; committed CSVs + per-row protocol SHAs + per-unit commits carry the audit trail."

### 3. Editorial sign-off on honest-magnitude/attribution framing
expected: thesis-suitable framing — W_DADP certified 5/5 seeds; FIT INFEASIBLE on every seed → Δ% UNDEFINED at registered mix; measurable certified gains 3–7 orders below +25%; gap not fully attributed (protocol §9 recorded outcome).
result: pass
evidence: "Framing presented in full 2026-10-27 (headline certification 5/5 seeds, mean −378163.5585, spread 1.3e-7 rel, crosscheck |Δ|=0.0235; UNDEFINED at registered mix stated as measured property; certified pairs 3–7 orders below +25%: batteries_out +1.33e-5%, rungs +1.85e-5/+2.38e-6%, proxy +0.0135%; NOT FULLY ATTRIBUTED as permitted terminal state, no tuning). User signed off."

## Summary

total: 3
passed: 2
issues: 0
pending: 0
skipped: 1
blocked: 0

## Gaps

[none]

---
status: complete
phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
source: [31-01-SUMMARY.md, 31-02-SUMMARY.md, 31-03-SUMMARY.md, 31-04-SUMMARY.md, 31-05-SUMMARY.md, 31-06-SUMMARY.md, 31-07-SUMMARY.md, 31-FINDINGS.md]
started: 2026-10-03T00:00:00Z
updated: 2026-10-03T12:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. GNE continuum exposed under interior caps
expected: `uat31.sh gne` — interior-cap testitem all Pass; probe spread > 0.5 within the analytic GNE interval x_inv_1 ∈ [0, 0.7]; corner-cap control spread stays 0.
result: pass
note: run by Claude at user request: interior-cap testitem 21/21 Pass (1m49s)

### 2. Variational-equilibrium selection
expected: `uat31.sh ve` — all three solve_variational_equilibrium testitems Pass: symmetric fixture returns a point of the VE face (non-unique, documented); corner-cap control agrees with the pinned unique equilibrium; asymmetric fixture (c_inv=[1.0,1.4]) returns the unique hand-derived VE x_inv=(0.7,0), z=(0.7,0.7) with equal shared-row multipliers.
result: pass
note: run by Claude: 3 solve_variational_equilibrium testitems, 28/28 Pass (1m09s)

### 3. Integer investment in N>1 Nash diagonalization
expected: `uat31.sh integer` — all testitems Pass: N=2 K=4 integer Nash converges to z=[0.5,0.5], x_inv=[0.25,0.25], UB=-0.225; independent fresh-QP brute force finds no profitable unilateral deviation; damped ω=0.5 run converges (no false CYCLED); input-validation guards fire.
result: pass
note: run by Claude: test_planning_nash_integer.jl 78/78 Pass (1m55s)

### 4. Literate examples still run end to end
expected: `uat31.sh literate` — both docs/literate/nash_diagonalization.jl and integer_investment.jl print exit=0.
result: pass
note: run by Claude: integer_investment.jl exit=0; nash_diagonalization.jl exit=0 under the docs environment (JULIA_LOAD_PATH=docs:.:@stdlib — it needs CairoMakie; the helper's first run used the main env and failed on the missing package, an invocation error not a code defect)

### 5. Writeups state each planning variant's game-theoretic nature accurately (Portuguese)
expected: Reading docs/writeups/stackelberg_vs_psr_n1n2.pdf and docs/writeups/modelo_stackelberg_dso_unico.pdf — taxonomy table (Benders-decomposed integrated / genuine bilevel / shared-constraint GNE+VE) is accurate; integer extension framed as a deliberate deviation (leader y_inv via Laporte–Louveaux vs the PSR note's follower-side Lagrangian); no "não implementado" for the integer master; VE non-uniqueness on the symmetric fixture and uniqueness on the asymmetric one stated correctly.
result: pass
note: read by Claude at user request against src/: taxonomy, integer-extension deviation framing, implemented status, VE (non-)uniqueness all accurate. Minor wording nits already tracked as 31-REVIEW.md info items: free-riding range should be p ∈ [0, 0.5) (IN-02), and the writeup's 'respostas ótimas exatas de Gauss-Seidel não ciclam' omits the ties caveat present in the code docstring. Human full read still pending (user approved-pending-later-read in 31-05).

## Summary

total: 5
passed: 5
issues: 0
pending: 0
skipped: 0

## Gaps

[none yet]

---
quick_id: 260726-plf
description: Correct the 18-03 assumptions page — Section 8 fragility refuted, Phase-17 re-tune premise undermined
date: 2026-07-26
status: complete
---

# Quick Task 260726-plf — Summary

Corrected the last reader-facing artifact carrying the refuted fragility claim. **While doing so,
found that the premise of the entire Phase-17 population re-tune is also a tolerance artifact** —
a larger finding than the one this task set out to fix.

## Changes

`docs/literate/thesis_reproduction_assumptions.jl` — the authoritative Literate source. **Comment
prose only**; no executable line, `const`, or assertion touched.

`docs/src/generated/thesis_reproduction_assumptions.md` — **regenerated** via
`Literate.markdown(...; flavor = DocumenterFlavor())` with make.jl's exact options, rather than
hand-patched, so source and published artifact cannot diverge. (Cheap: `DocumenterFlavor` emits
`@example` blocks, so the solves run at `makedocs` time, not at Literate time.)

### (a) Section 8 — REFUTED, rewritten

Was: *"**No — not confirmed** … `sign_flip_survives: false` — ALL FOUR non-zero perturbation points
FAILED OUTRIGHT … confirmed only at the exact Phase-17-retuned point, NOT across a ±2-5%
neighborhood."*

Now: **"Yes — at all five swept points,"** with the measured table, the numerical explanation, the
`fit_baseline` misattribution, and the golden-band rule/value disagreement. The original wrong verdict
is preserved struck-through at the end of the section.

| δ | socp_maxgap | dadp_dso | fit_dso |
|---|---|---|---|
| −0.05 | 3.505e-08 | +2.709838 | −182.9611 |
| −0.02 | 1.900e-08 | +3.277535 | −190.8755 |
| 0.00 | 1.162e-08 | +3.725742 | −196.2165 |
| +0.02 | 4.610e-08 | +4.163925 | −201.6167 |
| +0.05 | 1.342e-08 | +4.807417 | −209.9950 |

### (b) NEW FINDING — the Phase-17 re-tune was not necessary

The page justified re-tuning the population `0.03/0.06/0.05 → 0.05/0.12/0.0833` on the grounds that
*"the ORIGINAL synthetic-impedance triple broke `solve_welfare`'s SOCP-exactness gate outright on the
real network (worst gap ratio 1.378 > 1)."*

Tested directly this session — the original triple on the **real**-impedance feeder:

| tol_gap | result |
|---|---|
| `1e-8` (default) | THREW, ratio `1.3781586234547918` |
| `1e-10` | **PASSED** — `socp_maxgap = 1.673e-08`, `vpeak = 1.00198` pu, `dso = +0.662750` |

So the anchoring datum is **refuted**: the old point solves cleanly, and `dso` is positive there too
(the DADP half of the sign flip survives). Added as a `!!! warning` admonition. The re-tuned point
remains valid and nothing downstream of it is wrong — it simply was not *required*.

### (c) Sections 5 and 7 — flagged, deliberately NOT called refuted

Both rest on Phase 17's default-tolerance search ("population scale above ~1.02-1.03 pu drives the SOC
relaxation genuinely inexact"). Its anchoring datum is now refuted, and spike 002 found the voltage
**upper bound is never active** on this feeder across a 5.5× PV range (`vpeak` 0.9997-1.016 vs caps
1.05-1.10) — so there is no observed upper-band binding to be asymmetric *about*.

But **Phase 17's full search space was not re-swept**, so both are marked *evidence undermined, needs
re-measurement at tight tolerance*, not refuted. The lower-band claim (`vmin_solved ≈ 0.9487` pu,
load-driven) is real physics and is explicitly preserved in both admonitions.

### (d) Section 6 — untouched

The honesty paragraph (thesis +25% welfare-ratio magnitude does not transfer; ≈+0.045% here) is
unaffected by any of this and remains correct.

## Verification

- `Literate.markdown` regenerated the page without error.
- `julia --project=. docs/literate/thesis_reproduction_assumptions.jl` executes cleanly:
  `live-checked load-node count = 85`, `live-checked population re-tune = (0.05, 0.12, 0.0833)` —
  both live `@assert`s pass, so the comment edits broke nothing.
- Generated `.md` confirmed to carry all three `CORRECTED 2026-07-26` admonitions plus the new
  Section 8 verdict.

## Incidental corroboration

The page's own line-49 datum — ratio **1.378** at `LOAD_SCALE = 0.03` — is the **third independent
confirmation** of this session's other diagnosis: the spurious `test_thesis_repro` failure came from
the stale sibling worktree `TSO-DSO.worktrees/pdf-documentation-thesis-results/`, which still carries
`LOAD_SCALE_IEEE123 = 0.03`. Same population point, same ratio, same cause.

## Still owed

1. ⬜ **Plan 18-02's golden band** — `1.5 × max|dso|` now implies 7.211 vs pinned 5.5886. Not failing
   (4.8074 < 5.5886); re-derive deliberately.
2. ⬜ **`scripts/repro_stability_check.jl`** — split the three-solve `try/catch`; thread the
   `optimizer` kwarg. Blocks regenerating `findings.txt` without losing its correction banner.
3. ⬜ **NEW — re-measure Phase 17's population-scale search at tight tolerance.** Sections 5/7 are
   flagged pending this. It would settle whether the upper-band asymmetry exists at all, and whether
   the re-tune can be reverted (not that it needs to be).

## Notes

- No code, fixture, or test changed. `test/fixtures_phase7.jl` untouched — the re-tuned point stays.
- Executed inline rather than via `gsd-planner`/`gsd-executor`; workflow guarantees kept.

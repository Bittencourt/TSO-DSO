# Phase 26 Findings

Findings discovered during Phase 26 gap-closure execution that are documented as facts (not
silently fixed) and folded into `.planning/STATE.md` by the orchestrator at phase close.
Executors in parallel worktrees append here — never edit `STATE.md` directly.

## Plan 26-14 — App. C eta<1 finding

- [v4.0 Phase 26 finding]: App. C's (pp. 166-168) "no simultaneous charge/discharge" argument —
  the claim that the strict `λ_min < λ_med < λ_max` battery-price ordering alone makes
  simultaneous charge/discharge strictly dominated, with no binary/complementarity constraint
  needed — implicitly assumes round-trip efficiency `η = 1`. For `η < 1`, whenever `DLMP <
  λ_med` and both legs (`p_ch`, `p_dch`) are small, an SOC-neutral round trip earns
  `(λ_med − DLMP)(1 − η²) > 0`, so a GENUINE, KKT-consistent simultaneous charge/discharge CAN
  be the true welfare optimum. This is a LATENT gap in App. C's own parametrization — pre-
  existing, exposed (not caused) by Plan 26-04's operating-point move — and affects EVERY
  `PVBattery` result, not just the fixture below.
- **Measured evidence:** the EXACT-04 high-PV AC (Ipopt/NLP) oracle stress fixture
  (`test/test_ac_oracle.jl`, `pv_scale=1.2`) solves to a KKT-consistent optimum at bus 2, t=7
  with `p_ch ≈ 0.00256`, `p_dch ≈ 0.00305`, verified to 4 digits against the App. C KKT
  identity `(λ_med − DLMP)(1/η² − 1) = b_dch·p_dch + b_ch·p_ch/η²`. The SOCP path's looser
  complementarity tolerance (`τ = 1e-3`) masks the identical effect; the AC/NLP path's tighter
  tolerance (`τ = 1e-6`) catches it — this is WHY the throw previously surfaced only on the AC
  oracle path (`test_ac_oracle.jl:182` and, downstream, `test_restricted_branch_flow.jl:61`/
  `:145`/`:231`/`:398`, which solve the same fixture through the AC oracle).
- **Disposition (locked, PM-02):** DOCUMENT as a finding (this file + `STATE.md` at phase
  close + `docs/literate/prosumer_welfare.jl`); make the AC oracle REPORT (via `@warn`, not
  throw) simultaneous charge/discharge as a diagnostic; add a backlog item for a proper
  complementarity treatment. No utility/model change was made in this phase.
- **What changed (Plan 26-14, `src/models/welfare_solve.jl`):**
  `assert_battery_complementarity!` gained an `on_violation::Symbol = :error` keyword.
  `solve_welfare`'s AC/NLP call site now passes `on_violation = :warn` (via
  `problem_class(pf) isa SOCP ? :error : :warn`) — it logs and continues instead of throwing.
  Every other call site (`src/planning/subproblem.jl`, `src/admm/AgrOpt.jl`,
  `src/models/stochastic_welfare.jl`, and `solve_welfare`'s own SOCP path) is UNCHANGED and
  still throws, byte-for-byte the same message as before this plan.
- **Backlog item — unscheduled, needs a future phase slot:** a proper complementarity
  treatment for the App. C battery model under `η < 1`. Candidate approaches: (a) re-
  parametrize so the discharge cost intercept exceeds `λ_med/η²` (restores strict dominance
  without a constraint); (b) add an explicit `p_ch·p_dch = 0` complementarity constraint
  (binary or MPEC formulation) for validation runs; (c) an η-aware round-trip penalty term
  in the battery utility. This is NOT scheduled against any currently-reserved phase number —
  a future phase must claim it explicitly before implementation begins.

## Plan 26-18 — Gan-Low relabel + v2.1 restatement

- [v4.0 Phase 26 finding]: Plan 26-02's own SUMMARY and the `docs/literate/
  convex_branch_flow.jl` verdict page previously described the corrected `ConvexBranchFlow`
  default (`thesis_literal=false`, Gan-Low direction, `v̂ ≥ v`) as "a genuine relaxation."
  This was INACCURATE (locked decision PM-01, `26-POSTMERGE-TRIAGE.md` cluster I): on the
  EXACT-04 high-PV fixture (`pv_scale=1.2`), the default SOCP optimum is **-921.754** while
  the TRUE AC optimum (Ipopt, two strategies agreeing) is **-921.277**. A relaxation of a
  maximization can never score BELOW a feasible AC point, so the default is provably a
  RESTRICTION — Gan-Low's own "modified OPF": `v̂ ≤ V²max` is load-bearing and
  conservatively enforces `v ≤ V²max` (26-02's own load-bearing/redundant-bound test
  demonstrates this), exact by theorem, with a measurable (~0.05% here) welfare loss. The
  OLD thesis-literal copy (`ConvexBranchFlow(; thesis_literal=true)`) restricts the LOWER
  voltage band instead. **NEITHER form is a genuine relaxation.**
- **Restated finding — the v2.1 "SOCP knife-edge under high-PV reverse flow" finding no
  longer reproduces under the default.** That finding (project memory
  `v2.1-socp-inexactness-and-thesis-repro`) measured EXACT-04 as genuinely cone-INEXACT
  under the (then-default) old thesis-literal copy. Under the corrected (Gan-Low) default
  now shipped since Plan 26-02, EXACT-04 is EXACT (well under the PF-04 gate) — the
  original finding's premise no longer holds under default settings. The finding DOES still
  reproduce, unchanged, under the explicit `ConvexBranchFlow(; thesis_literal=true)`
  opt-in — this is the mechanism Plan 26-18 uses to re-force the tests below.
- **What changed (Plan 26-18):** honest-relabel-only edits to
  `src/powerflow/ConvexBranchFlow.jl`'s struct/`contribute!`/outer-constructor docstrings,
  `docs/literate/convex_branch_flow.jl`'s Verdict subsection (new "PM-01" addendum with the
  EXACT-04 measured numbers), and `26-02-SUMMARY.md` (appended addendum, prior text left
  intact). The Phase-20/21 escalation-ladder tests (`test/test_mpc_loop.jl:95/:187/:294` in
  triage numbering) and the `test_restricted_branch_flow.jl` AC-infeasibility
  synthetic-violation tests (the two testitems' "unrestricted"/"cert_failing" comparison
  legs, formerly triage-numbered `:231`/`:398`) are re-forced with an explicit
  `ConvexBranchFlow(; thesis_literal=true)` construction, restoring their original
  forcing-mechanism intent (the escalation ladder / genuine AC-infeasible synthetic
  violation) under the now-honest, now-exact default. No production code behavior changed —
  only docs/docstrings/planning prose and two test files' fixture construction.

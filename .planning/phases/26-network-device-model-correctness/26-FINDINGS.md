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

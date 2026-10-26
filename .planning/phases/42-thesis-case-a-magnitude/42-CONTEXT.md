# Phase 42: Thesis Case A Magnitude - Context

**Gathered:** 2026-10-26
**Status:** Ready for planning

<domain>
## Phase Boundary

A researcher gets an honest, pre-registered measurement of the DADP-vs-FIT welfare gain at the
real 784-house Case A population — absolute and sign-safe relative values with a seed spread,
reported whatever the magnitude and sign — plus a pre-registered one-factor-at-a-time ablation
over FIT parameters, price range, population and device mix that attributes the remaining gap to
the thesis +25% and is compared against the 1-house-per-bus proxy (≈+0.26%), with no parameter
tuned toward the target. Deliverables: the committed pre-registration protocol (written and
committed BEFORE the Case A run executes), the measurement runner + committed CSV artifacts +
literate writeup, and the ablation/attribution table. Requirements: REPRO-03, REPRO-04,
REPRO-05.

v5.0 policies bind this phase: **honesty policy** (a refused certificate or an infeasible FIT
leg is a recorded measured outcome; the exactness gate and battery τ are never loosened to make
a run pass) and **golden policy** (no golden on the measured magnitude; default paths
byte-identical; the knife-edge canary is never re-pinned).

</domain>

<decisions>
## Implementation Decisions

**Mode:** Auto-accepted recommended answers (autonomous run, user pre-authorization)

### Pre-Registered Protocol & Welfare-Gain Definition (REPRO-03)
- The protocol lives at `.planning/phases/42-thesis-case-a-magnitude/42-CASE-A-PROTOCOL.md` and
  is committed in its own commit BEFORE any Case A run executes (success criterion 1);
  measurement scripts may be written first, but the 784-house run is gated on the protocol
  commit (the script asserts the protocol file exists, fail-loud).
- The relative welfare gain is the SIGN-SAFE form `Δ% = 100·(W_DADP − W_FIT)/|W_FIT|` — the
  `scripts/thesis_case123_repro.jl` precedent. The naive ratio `W_DADP/W_FIT` is NEVER used:
  welfare is large and negative at population scale (−3.78e5 at 784 houses), so the ratio
  sign-inverts — banned by the PROJECT.md Key Decision ("golden pinned on the sign flip, not
  the welfare ratio"). The absolute gain `ΔW = W_DADP − W_FIT` is reported alongside.
- Secondary lenses are reported but never replace the headline: the prosumer/DSO surplus split
  (including the DSO-surplus sign flip — the v2.1/v4.0 headline the thesis itself frames) and
  the DADP-vs-λ₀ price-signal behaviour. No new formulation is introduced for any lens.
- The refusal-handling answer is INSIDE the pre-registered protocol: the bounded AGR
  solver-precision ladder (`default → gap_1e-10 → gap_1e-12 → gapfeas_1e-12`,
  stop-on-first-certified, the `scripts/case_a_agreement.jl` `AGR_TOL_RUNGS` Dict), invoked via
  `solve_admm`'s documented `agr_optimizer` seam. The exactness gate, battery τ and ρ are never
  touched; adding a ladder rung requires editing the script (deliberate-act friction).

### Headline Measurement at the 784-House Population (REPRO-04)
- Engine: the ADMM published-price path (`dadp == λ`) produces the headline DADP numbers —
  comparison.jl documents it as the thesis-relevant published-price path — with the centralized
  `solve_welfare` solve recorded as the cross-check bound; both rows land in the artifacts. The
  FIT leg comes from `fit_baseline` unchanged (batteryless by design, thesis Assumption A4).
- The registered configuration is FROZEN in the protocol, identical to the Phase-40/41
  artifacts: `:case_a_784` population over `:ieee13`, `ConvexBranchFlow()`, T=24,
  λ₀ = `build_price(:mem)`, `allow_export = true`, profiles seed `sub_seed(master, :profiles)`,
  population seed `sub_seed(master, :population)`, ρ = `ADMM().ρ` (locked, no re-tuning),
  executor defaults with provenance stamped. Continuity with the validated calibration beats
  re-tuning (POP-06 provenance).
- Seed spread: master seeds {42 (primary/registered), 43, 44, 45, 46} — households re-derive
  via the POP-02 hash seeding, so each seed is a full honest re-draw. Per-seed absolute and
  relative gains plus mean and min–max spread are reported; seed 42 stays the continuity anchor
  with every prior Case A artifact.
- The known 784-house ADMM refusal at iters=80 (Phase-40 `agreement.csv`: `error:CertificateError`
  at default rung, certified at the `gap_1e-10` rung; Phase-41 `tariff_comparison.csv`
  case-a-784 `(run)` row: battery-complementarity `CertificateError` at iters=80) is handled
  honestly: the refusal is recorded as its own status row, then answered ONLY by the
  pre-registered ladder — never by loosening a gate, never by re-tuning. A FIT-leg solver
  failure (`SolveFailedError`/`CertificateError`/`ConvergenceError` — the ground fixture's
  recorded INFEASIBLE precedent) is likewise an honest status row; the only sanctioned FIT seam
  is the documented `fit_optimizer` conditioning passthrough. The A1/A4 batteryless-FIT
  asymmetry is stated in the writeup, never back-filled.

### Ablation & Gap Attribution (REPRO-05)
- Design: one-factor-at-a-time (OFAT) from the registered configuration, over exactly the four
  axes REPRO-05 names — (a) FIT parameters (`FIT_λ_EXPORT = 9.6` / `FIT_λ_SELF` thesis page-93
  values vs documented variants), (b) price range (λ₀ `:mem` shape vs documented scalings),
  (c) population (784 houses vs 1-house-per-bus proxy vs Phase-40 nested-prefix ladder rungs),
  (d) device mix (batteries in/out, PV-ownership split). Axis names AND values are fixed in the
  protocol BEFORE any ablation run — no free-form search.
- Attribution is a per-axis effect table on Δ% plus a written statement naming which
  thesis-faithful-vs-repo-default differences explain the gap's direction and size. "Gap not
  fully attributed" is an acceptable, recorded outcome; closing the gap to +25% is explicitly
  NOT a success condition (honesty policy).
- Proxy comparison: the SAME protocol (same gain definition, same code path) is re-run on the
  1-house-per-bus `:default` proxy so the restated ≈+0.263% figure is reproduced under the
  pre-registered definition, and the population axis shows the gain-vs-population-size curve
  from the Phase-40 ladder rungs (nested prefixes, no per-rung re-tuning).
- The no-tuning guard is STRUCTURAL: axes/values committed pre-run; every intermediate row
  committed as an artifact (no cherry-picking); any constant introduced after intermediate
  results are visible requires an explicit protocol-amendment commit; the code review checks
  that no constant was fit to the +25% target.

### Artifacts, Tests & Writeup
- Results land in `results/thesis_case_a_magnitude/` as CSVs with the upsert provenance idiom
  (julia_version / threads / blas_threads / seed / t_horizon / mode columns); a kill mid-run
  leaves the rows already captured — a kill is a measured outcome.
- The writeup is a literate page (new page or a dated "Appended" section — the
  Phase-35/39/40 pattern) reporting the protocol, the headline gain table (absolute, relative,
  spread), the ablation table, and the honest-magnitude framing ("whatever it is", PROJECT.md
  v5.0 goal). Derived percentages are recomputed live, never restated stale (Phase-28 CR-01
  discipline).
- Tests cover STRUCTURAL invariants only: the gain definition's sign-safety on negative-welfare
  fixtures, ledger conservation on the measured runs, and the protocol-file-exists guard. Any
  test that runs a full-population solve is `:slow`-tagged. NO golden is pinned on the measured
  magnitude (measured-not-assumed; new goldens only on sign-safe, reproducible plumbing
  quantities, gate-then-golden if ever needed).
- Runner shape: a dedicated measurement script (e.g. `scripts/case_a_magnitude.jl`) assembling
  the existing validated seams — `compare_tariffs` for the four-leg settlement where it fits.
  `src/` stays untouched unless an additive seam proves genuinely necessary: this is a
  measurement phase, and the settlement/comparison machinery already covers the legs.

### the agent's Discretion
- Exact seed count (≥3, recommended 5), ladder rung selection mechanics, script/CSV column
  layout, literate page structure, and the ablation's specific documented variant values within
  the four fixed axes are at the agent's discretion — subject to the protocol-first commit
  ordering.

</decisions>

<code_context>
## Existing Code Insights

### Reusable Assets
- `src/settlement/comparison.jl` — `compare_tariffs` (SETL-02 runner): settles the
  `:dadp/:flat/:tou/:fit` legs over ONE solved DADP run with honest per-leg status rows
  (`error:<Type>`, `fit_inexact`), AC feasibility statuses, battery-certificate counts, equity
  breakouts and rebound; returns DataFrames, does NO file IO; `fit_optimizer` is the documented
  conditioning seam. The `engine = :admm` path inherits the loud non-`:converged` guard.
- `scripts/tariff_comparison.jl` — the committed-measurement idiom: upsert CSV contract,
  `(run)` status rows for a refused DADP run, locked ρ = `ADMM().ρ`. Its case-a-784 attempt is
  already committed: the `(run)` row records `error:CertificateError` (battery complementarity,
  bus 5 t=16, razor-thin margin, iters=80).
- Phase-40 assets: the `:case_a_784` population (`build_population` branch,
  `src/experiments/materialize.jl`), `case_a_household_map`, the nested-prefix scaling ladder
  (`results/case_a_population/scaling_ladder.csv`), and `scripts/case_a_agreement.jl` with its
  bounded `AGR_TOL_RUNGS` ladder — the certified 784-house ADMM point (welfare −378163.5654,
  welfare rel-delta 6.22e-7 vs centralized, certified at the `gap_1e-10` rung after the
  `error:CertificateError` refusal at iters=80 on the default rung).
- `scripts/thesis_caseA.jl` — thesis-faithful Case A framing (784 houses, PV 5 MWp,
  S_max(head)=6.86 MVA, V∈[0.95,1.05], λ₀ = digitized Fig 4.5) and the FIT welfare
  construction (`fa.total_utility − Σ_t λ₀·p_import`; DADP/FIT ratio target ≈1.25).
- `scripts/thesis_case123_repro.jl` — the sign-safe relative gain precedent
  (`100·(welfare_dadp − social_fit)/abs(social_fit)` → restated ≈+0.263%) and the explicit
  ban on the aggregate welfare ratio.
- `src/pricing/fit.jl` — `fit_baseline` (batteryless A4; German-FIT page-93 constants) consumed
  via documented `optimizer` / `on_inexact` kwargs only; `src/pricing/welfare.jl`
  `welfare_accounting` for the surplus split — both consumed, never modified.

### Established Patterns
- Honesty policy: refusals/infeasibilities are recorded rows, never tuned away; "refused with
  certificate" is a valid measured outcome; a first full-scale refusal is a solver-precision
  artifact answered by the bounded precision ladder (research Pitfall 4), never a gate change.
- Golden policy: default paths byte-identical; new goldens only on sign-safe reproducible
  quantities; gate-then-golden / measurement-before-golden; canary (`iters = 56`,
  `welfare = -4823.66604824162`) never re-pinned.
- Pre-registration friction: numeric rung sets live in a script Dict (`AGR_TOL_RUNGS`) — adding
  a rung requires editing the script, the deliberate-act friction the honesty policy wants.
- Artifact discipline: upsert CSVs keyed on provenance identity, dated literate "Appended"
  sections, negative results recorded as first-class outcomes (v3.0 SCALE-05 precedent).
- Julia test invocation: `julia --project=. -e 'import Pkg; Pkg.test()'` only.

### Integration Points
- `solve_admm` (`agr_optimizer` seam, `time_limit_s`, typed `CertificateError` carrying
  iterations) and `solve_welfare` — the measurement's two engines.
- `compare_tariffs` (`houses` + `map_rows` for house granularity) — the settlement assembly.
- `build_feeder` / `build_population` / `build_price` selectors — the frozen registered
  configuration; `case_a_household_map` for per-house attribution.
- `results/` + `docs/literate/` artifact pattern; REQUIREMENTS.md traceability REPRO-03..05.

</code_context>

<specifics>
## Specific Ideas

- The 784-house ADMM refusal at iters=80 is a KNOWN PRECEDENT, not a surprise: the protocol
  pre-registers the ladder answer up front so the measurement cannot silently re-tune after
  seeing a refusal (operator scout directive).
- PROJECT.md v5.0 target framing: "re-attempt the welfare-gain magnitude on the real population
  and report it honestly, whatever it is" — the phase succeeds on the honesty of the
  measurement, not on the size of the gain.
- Phase-28 restatement discipline carries over: every derived percentage in the writeup is
  recomputed live from committed rows and restated with its named cause — no stale derived
  figures.

</specifics>

<deferred>
## Deferred Ideas

- The DSO flexibility-market leg and the SETL-08 five-way comparison table — Phase 45 scope.
- Thesis Appendix E absolute-figure digitization (+$1,819/+25%) — remains deferred per
  PROJECT.md; this phase reports the framework's own absolute values.
- Any coupling with new devices (DEV, Phase 43) or aggregator-actor objectives (ACTOR,
  Phase 44) — the ablation's device-mix axis varies only the EXISTING registered mix.

</deferred>

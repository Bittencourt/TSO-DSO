# Milestone v2.1 — Project Summary

**Generated:** 2026-07-26
**Purpose:** Team onboarding and project review
**Milestone:** v2.1 Validation & Reproduction (shipped 2026-07-26, audit **PASSED**)

---

## 1. Project Overview

**TSO-DSO Integration Optimization Framework (Julia)** — a research framework for experimenting
with a TSO–DSO integration optimization theory built on transactive energy / dynamic distribution
pricing and Stackelberg–Nash equilibria. It implements the two-layer framework from J.P. Palacios'
PhD thesis (UNSJ/CONICET, 2022) and the associated PSR N1–N2 expansion note:

- **Operational layer** (v1.0): day-ahead dynamic pricing over a convex branch-flow distribution
  network, solved as convex social-welfare maximization decomposed by ADMM, with prices emerging
  as duals (DADP/DLMP).
- **Planning layer** (v2.0): Stackelberg–Nash TSO–DSO investment equilibria solved by hand-rolled
  Benders + Gauss-Seidel diagonalization.

**Core value:** a researcher can express a scenario and a model variant declaratively, run it
end-to-end with an open-source solver, and get trustworthy, reproducible results and prices — with
every model assumption documented and every layer swappable.

**v2.1's goal** was not a new research axis: harden the framework's core correctness claims so
every downstream extension — and the thesis itself — rests on validated, citable ground. Four
phases (15–18), 14 plans, 27 tasks, all complete and verified.

### The two headline scientific findings (both honest, both cross-cutting)

1. **The radial SOCP relaxation is genuinely INEXACT under high-PV reverse flow.** Found by the
   new AC oracle on IEEE-13 (`pv_scale=1.2`: 10 inexact afternoon hours, voltage pinned at V²max,
   reverse flow) and independently re-hit on real-impedance IEEE-123 (the upper/overvoltage band
   cannot approach ~1.05 pu while staying exact). Surfaced as a citable finding — cross-referenced
   to Farivar & Low (2013) / Gan et al. (2015) — not tuned away.
2. **Thesis reproduction is DIRECTIONAL only.** The DSO-surplus sign flip reproduces on real
   public data (FIT −196.22 → DADP +3.73; prosumer surplus decreases), but the thesis's +25%
   aggregate-welfare magnitude does **not** transfer (~+0.045% measured), and the sign flip is
   knife-edge-fragile under ±2–5% population-scale perturbation. Every citation of the numbers
   carries a fixed "directional, public-data" qualifier. Exact-figure reproduction
   (+$1,819 / +25%) remains deferred, gated on thesis Appendix E (IP-blocked CONICET repository).

## 2. Architecture & Technical Decisions

v2.1 was additive-only over proven seams — zero new runtime dependencies, no regression of any
shipped path.

- **Decision:** `ACPowerFlow <: AbstractPowerFlow` as a *peer* formulation, dispatched through the
  unchanged `solve_welfare` entrypoint.
  - **Why:** an independent nonconvex AC-OPF (Ipopt, true equality `l·v == P²+Q²` as a
    scalar-quadratic EqualTo constraint) replaces the old toy-point/same-relaxation self-check;
    "same operating point" locked as identical inputs with independent re-optimization.
  - **Phase:** 15
- **Decision:** `assert_ac_exact!` is **report-don't-throw** — returns a per-hour
  `Vector{NamedTuple}` of objective/voltage/branch-flow gaps (scale-free `atol + rtol·magnitude`),
  and throws *only* on a structural T mismatch, never on a genuine numeric gap.
  - **Why:** a genuine relaxation gap must surface as a first-class documented finding, not a
    spurious test failure. The high-PV stress test asserts `!isempty(inexact_hours)` — a POSITIVE
    finding, guarded against local-optimum artifacts by a two-start Ipopt comparison.
  - **Phase:** 15
- **Decision:** Reactive-power naming pinned *before* any code: `qag_dso` (JuMP coupling
  variable), `reactive` (DLMP NamedTuple field), `mu_q` (reserved) — bare `mu` continues to mean
  ONLY the adaptive-ρ residual-balancing band.
  - **Why:** the μ symbol collision (reactive dual vs. adaptive-ρ scalar in `Scenario`'s
    golden-hash schema) was the milestone's first design decision; `Scenario.jl` was declared
    out of scope for the whole phase to avoid a second DrWatson savename golden-hash perturbation.
  - **Phase:** 16
- **Decision:** `reactive_consensus::Bool=false` feature flag; `qag_dso[j,t]` is **pinned via an
  explicit equality** to the physical reactive draw, with an `assert_no_slack` certificate on
  `:balance_q`.
  - **Why:** default path stays byte-identical (goldens unchanged); an unpinned free variable
    would let the solver discard physical reactive demand entirely (threat T-16-03). This is a
    one-shot certified dual read, not a live μ-ascent loop — consistent with thesis A3 (DERs are
    active-only); the live reactive dual-ascent loop is explicitly deferred to meshed+4Q-BESS.
  - **Phase:** 16
- **Decision:** The reactive DLMP is a **5th, separate component** — `extract_reactive_dlmp`
  mirrors `extract_dlmp`'s shape/PF-04 gate, and the `reactive` field is never summed into the
  4-term active-price total (energy+loss+congestion+voltage=total assertion byte-for-byte
  unchanged).
  - **Why:** it is the dual of `:balance_q`, dimensionally and economically distinct from the
    active nodal price.
  - **Phase:** 16
- **Decision:** Real IEEE-123 impedances come from a **dependency-free OpenDSS regex parser +
  Fortescue positive-sequence reduction** (`scripts/reduce_ieee123_impedances.jl`), committing a
  pure-data `const` table (`src/data/ieee123_impedances.jl`, 117 entries in Ω) — topology
  untouched, PMD kept out of runtime `[deps]`.
  - **Why:** citable, standard, reproducible data without dragging PowerModelsDistribution into
    the dependency graph (project constraint since v1.0).
  - **Phase:** 17
- **Decision:** Population re-tune after the real-impedance swap: `LOAD_SCALE_IEEE123`
  0.03→0.05, `PV_SCALE` 0.06→0.12, `DEV_SCALE` 0.05→0.0833 (5/3 ratio to load held), found by
  exhaustive empirical sweep — never by touching impedance data.
  - **Why:** the original population broke the SOCP-exactness gate outright (gap ratio 1.378) on
    real impedances. The re-tuned case is verified voltage-binding, with an honest asymmetric
    finding: the lower band (→0.9 pu) transfers well, the upper band (→1.1 pu) does not — the
    same exactness knife-edge as Phase 15's finding.
  - **Phase:** 17
- **Decision:** **Measurement-before-golden** (BLOCKING plan 18-01): N≥20 flake-rate + ±2–5%
  population-scale sensitivity sweep committed to `findings.txt` *before* any golden was pinned;
  the DSO-surplus band [0.0, 5.5886] derives only from the point that solved exactly.
  - **Why:** guards against pinning transient Clarabel numerical noise or a knife-edge point as a
    permanent regression; the sweep honestly exposed the sign flip's fragility.
  - **Phase:** 18
- **Decision:** Economic goldens pinned on **sign-safe quantities** (DSO-surplus sign flip),
  never ratios of possibly-negative aggregates; the sign-unsafe `welfare_dadp/welfare_fit` ratio
  is never computed anywhere; the "directional, public-data" qualifier is enforced by a
  grep-checkable `cite_repro(x)` helper, not review discipline.
  - **Phase:** 18

## 3. Phases Delivered

| Phase | Name | Status | One-Liner |
|-------|------|--------|-----------|
| 15 | AC-Exactness Oracle | ✅ Complete (3/3 plans) | Independent nonconvex AC-OPF peer (Ipopt) + per-hour report-don't-throw `assert_ac_exact!`; found the SOCP relaxation genuinely inexact at `pv_scale=1.2` (10 hours, voltage pinned, reverse flow), documented in a live literate page |
| 16 | Reactive-Power (μ) Consensus | ✅ Complete (4/4 plans) | `reactive_consensus` flag promotes the DSO-OPT reactive draw to a pinned `qag_dso` coupling variable with an `assert_no_slack`-certified `:balance_q` dual, published as a citable 5th DLMP component; Clarabel flake rates measured (IEEE-13: 55%→15%, IEEE-123: 5%→5%) |
| 17 | Real IEEE-123 Impedances | ✅ Complete (4/4 plans) | Vendored public OpenDSS fixtures → dependency-free Fortescue reduction → committed real per-segment Ω table; population re-tuned to restore voltage binding, with the honest asymmetric upper-band finding |
| 18 | Directional Thesis Reproduction | ✅ Complete (3/3 plans) | Stability-swept, gate-then-golden DSO-surplus sign-flip reproduction on real-impedance IEEE-123 (DADP +3.7257 vs FIT −196.2164) + two live literate pages stating plainly that the +25% magnitude does not transfer |

## 4. Requirements Coverage

Audit verdict (v2.1-MILESTONE-AUDIT.md): **PASSED** — 12/12 requirements, 4/4 phase
verifications, 6/6 cross-phase integration seams wired and live-verified, E2E flow complete.

- ✅ **EXACT-01** — true nonconvex AC-OPF via `ACPowerFlow` peer subtype (Ipopt), same operating point
- ✅ **EXACT-02** — `assert_ac_exact!` on objective/voltage/branch-flow gaps, scale-free tolerance
- ✅ **EXACT-03** — per-hour gap report (never a single boolean); genuine gaps are findings
- ✅ **EXACT-04** — high-PV/reverse-flow stress fixture documents where the relaxation goes inexact
- ✅ **REACT-01** — genuine per-node reactive-balance equality (replacing the free import slack)
- ✅ **REACT-02** — reactive nodal price extracted as a documented DLMP component
- ✅ **REACT-03** — zero regression of the active-only ADMM path (flag default byte-identical); μ collision resolved first
- ✅ **IMPED-01** — offline reproducible OpenDSS parse + Fortescue reduction, PMD out of runtime deps
- ✅ **IMPED-02** — committed real positive-sequence table consumed by `ieee123.jl`, topology untouched
- ✅ **IMPED-03** — real-impedance case verified voltage-binding after documented population re-tune
- ✅ **REPRO-01** — literate page + gate-then-golden test on sign + band, "directional, public-data"
- ✅ **REPRO-02** — consolidated assumptions page; repeated-run stability checked before pinning
- ⏸️ **REPRO-STRETCH-01** (deferred) — exact-figure +$1,819/+25% reproduction, gated on thesis App. E

## 5. Key Decisions Log

Aggregate of the most consequential per-plan decisions (see §2 for the architectural ones):

- **15-01:** the `l`-keyed `assert_socp_exact!` double-fire inside `solve_welfare` under the AC
  equality is harmless (residual ~1e-11) and intentionally retained; `recover_voltage_angles`
  (Baran–Wu recursion) validated against a hand-derived 2-bus closed-form phasor.
- **15-02:** plain `Vector{NamedTuple}` return — no DataFrames dependency; the divergence from
  `assert_socp_exact!`'s throw contract is asserted by tests, not merely documented.
- **15-03:** `pv_scale=1.2` hard-coded (empirically found, no search loop); diagnosis across the
  whole inexact window, not just the first hour (inter-hour coupling artifact).
- **16-03:** the finite-difference sanity pin for the reactive price sums over the horizon
  (per-t comparison under-predicts ~3× under a uniform power-factor perturbation).
- **16-04:** the unexpectedly high IEEE-13 baseline flake rate (55%, `reactive_consensus=false`)
  is reported as-is — measure-and-record, not diagnose-and-patch; `reactive_consensus=true` does
  not worsen flake rates on either fixture, so no separate ρ_q is warranted.
- **17-02:** the SOCP-exactness crossval break after the impedance swap was deliberately left for
  17-03's designated re-tune (scope discipline: fixtures only, never impedance data).
- **18-01:** the sweep's per-point solve wraps in try/catch so a real exactness throw becomes an
  honest FAILED data point instead of zero findings. **[Corrected 2026-07-26]:** the original
  `sign_flip_survives=false` verdict was a solver-tolerance artifact (under-convergence at
  `tol_gap=1e-8`), not a physical exactness boundary — corrected post-hoc with a tolerance-ladder
  re-measurement (sign flip survives 5/5; see quick-task corrections and
  `memory/v2.1-socp-inexactness-and-thesis-repro.md`).
- **18-02:** golden band constants copied verbatim from 18-01's committed `findings.txt` — never
  re-derived or rounded (dependency-integrity boundary).
- **18-03:** the aggregate welfare delta prints only as an explicitly-labeled "secondary,
  fragile" line; `decompose_dlmp` reads the centralized `:balance_q` dual channel — the
  `reactive_consensus` kwarg is ADMM-only and appears nowhere in the repro files.

## 6. Tech Debt & Deferred Items

**Advisory tech debt (from the audit — non-blocking):**
- **Nyquist flag unflipped** on all 4 VALIDATION.md files (`nyquist_compliant: false`) — an
  artifact of manual orchestration; the tests genuinely exist and pass per each VERIFICATION.md.
  Optional: `/gsd:validate-phase {N}` to flip retroactively.
- **ROADMAP wording** "reactive pricing active" is ambiguous — it means the centralized
  DLMP-dual channel, not ADMM `reactive_consensus=true` (threading that kwarg into
  `solve_welfare` would be a MethodError).
- **Test-invocation gotcha:** never run `@run_package_tests` via `julia -e` — cwd-based discovery
  can pick up a stale sibling worktree (produced a spurious exactness "failure" that was the old
  pre-retune point). Use `test/runtests.jl` or explicit-path `TestItemRunner.run_tests`.
- **User-local Project.toml drift** (CairoMakie/Makie): the only 2 failing tests on the main
  checkout are known-false Aqua stale-deps/persistent-tasks artifacts, not regressions.

**Deferred to future milestones (carried in ROADMAP Deferred Notes):**
- **Overvoltage-capable relaxation** — the natural follow-up to the SOCP-inexactness finding.
- **Meshed + 4Q-BESS** (breaks the radial exactness proof; needs its own relaxation treatment),
  including the live reactive dual-ascent loop.
- **Discrete/integer investment expansion** (the PVAL-04 no-binaries guard must be consciously lifted).
- **Stochastic scenarios, MPC/rolling-horizon** research axes.
- **REPRO-STRETCH-01** — exact-figure thesis reproduction, gated on obtaining thesis Appendix E.

**Key retrospective lessons (v2.1):**
1. An honestly-framed negative/boundary result is a stronger deliverable than a tuned-green pass —
   and independent phases hitting the same boundary (IEEE-13 stress + real IEEE-123) is
   corroboration, not coincidence.
2. Long detached processes (`Pkg.test()`) must be polled to completion by PID within the turn, or
   finalize steps silently get skipped (bit Phases 15 and 17; fixed mid-milestone).

## 7. Getting Started

- **Run the tests:** `julia --project test/runtests.jl` (full suite ~13 min on first run due to
  Makie precompile, ~3–5 min cached; 2348 pass, 2 known-false local Aqua failures).
- **Build the docs:** `julia --project=docs docs/make.jl` — 13 live-executed Literate pages under
  `docs/literate/` (the abstraction ladder rungs 0–7 plus `ac_oracle`, `ieee123_impedances`,
  `thesis_reproduction_ieee123`, `thesis_reproduction_assumptions`, `socp_applicability`).
- **Key directories:**
  - `src/powerflow/` — the swappable formulations (DC / LinDistFlow / ConvexBranchFlow SOCP / ACPowerFlow oracle)
  - `src/models/` — `solve_welfare` (GLB-CVX), `oracle.jl` (planning coupling), `ac_oracle.jl`, `exactness.jl`
  - `src/pricing/` — DADP/DLMP extraction + 4(+1)-way decomposition
  - `src/admm/` — AGR-OPT / DSO-OPT subproblems + `solve_admm` (adaptive ρ, reactive flag)
  - `src/planning/` — Benders, Nash diagonalization, shared-transmission coupling
  - `src/data/` — IEEE-13/123 feeders incl. the committed real impedance table
  - `src/experiments/` — declarative `Scenario`, `run_scenario`/`run_sweep`, DrWatson storage
  - `scripts/` — `reduce_ieee123_impedances.jl`, `repro_stability_check.jl`, `thesis_case123_repro.jl`
- **Where to look first:** `src/TSODSO.jl` (the single-ownership include graph), then the literate
  docs pages — each rung executes a real solve beside the thesis equations it implements.
- **Reproduce the headline result:** `scripts/thesis_case123_repro.jl` or the
  `test/test_thesis_repro.jl` gate-then-golden test (5 hard gates on the real-impedance IEEE-123).

---

## Stats

- **Timeline:** 2026-07-25 → 2026-07-26 (single long autonomous session; milestone scoped 2026-07-24)
- **Phases:** 4 / 4 complete (15–18) — 14 plans, 27 tasks
- **Commits:** 50 (tag `v2.0`..`v2.1`)
- **Files changed:** 93 (+18,749 / −1,643)
- **Tests:** 2348 pass (+72 over v2.0), 3 documented `@test_broken`, 2 known-false local-only failures
- **Contributors:** Bittencourt (with Claude Code orchestration — Opus main loop, Sonnet subagents)

# Phase 42: Thesis Case A Magnitude - Research

**Researched:** 2026-10-26
**Domain:** Pre-registered welfare-gain measurement (DADP vs FIT) at the 784-house Case A population + OFAT gap-attribution ablation — assembly of existing validated seams, zero new formulations
**Confidence:** HIGH

## Summary

This phase is a **measurement phase, not a model-building phase**. Every numerical seam it
needs already exists, is tested, and carries committed measured precedents from Phases 40–41:
`solve_admm` with the `agr_optimizer` precision seam (the certified 784-house point is already
on record at the `gap_1e-10` rung, `agreement.csv`), `fit_baseline` (batteryless A4, page-93
FIT triple), `compare_tariffs` (the four-leg settlement runner, SETL-02), the `:case_a_784`
population builder with its nested-prefix ladder helpers, and the sign-safe relative-gain
precedent `100·(W_DADP − W_FIT)/|W_FIT|` from `scripts/thesis_case123_repro.jl` (restated
≈+0.2630% on IEEE-123). The genuinely NEW artifacts are (1) the committed pre-registration
protocol file with a fail-loud script guard — **no precedent exists in this repo**; this is a
new pattern — (2) a dedicated runner `scripts/case_a_magnitude.jl` in the
`case_a_scaling.jl`/`tariff_comparison.jl` idiom, and (3) the honest-magnitude writeup.

The single most consequential technical fact for the planner: **`compare_tariffs` accepts
neither `agr_optimizer` (ADMM leg) nor `optimizer` (centralized leg)** — its `engine = :admm`
path calls `solve_admm` at executor defaults, which at 784 houses reproduces the documented
iters=80 `CertificateError` refusal (Phase-41 committed `(run)` row), and its `engine =
:centralized` path calls `solve_welfare` at the default solver, which the Phase-40 measurement
showed is ALSO refused at full scale (certified only after solver tightening to
`tol_gap_1e-10`). So the headline W_DADP must come from a **direct ladder-governed
`solve_admm` call** (the `run_admm` splat idiom of `scripts/case_a_agreement.jl`), and the
planner must choose between (A) direct seams for the headline + `compare_tariffs` "where it
fits" (zero src changes — CONTEXT's stated default) or (B) one additive passthrough kwarg on
`compare_tariffs` (byte-identical default; the `fit_optimizer`/`time_limit_s` precedent in the
same signature — CONTEXT's "unless an additive seam proves genuinely necessary" clause).
Option B is recommended if the settlement lenses (surplus split, per-house equity) are wanted
at the certified 784-house point without hand-rolling leg assembly (see Architecture
Patterns, Pattern 5).

Runtime is the plan's scarce resource: the 784-house ADMM run costs ~593 s serial to the
iters=80 refusal (`threads_sweep.csv`), the certified `gap_1e-10` run is unmeasured for wall
time but iterations match (80), giving an ~10–15 min/leg estimate; per-seed headline cost
(ADMM ladder + FIT leg + settlement) is plausibly 25–40 min serial, so 5 seeds plus the OFAT
axes total roughly 6–12 h of serial compute. The upsert-CSV contract makes every run
kill-anytime (a kill is a measured outcome), and per-axis `--mode` flags make the work
resumable — the plan should schedule long runs as background tasks with honest
partial-artifact checks, never as one monolithic blocking command.

**Primary recommendation:** Write and commit `42-CASE-A-PROTOCOL.md` FIRST (own commit);
build `scripts/case_a_magnitude.jl` around the `case_a_agreement.jl` ladder idiom + the
`tariff_comparison.jl` artifact idiom; compute the headline from direct `solve_admm`
(ladder) + `fit_baseline` welfares via the sign-safe form; use `compare_tariffs` for the
settlement lenses (proxy and any leg whose engine certifies at protocol-pinned conditioning);
register the script in `scripts/README.md`; write the literate "Appended" section reading
committed CSVs only; test structural invariants only (`:slow`-tag anything that solves the
full population), pin NO golden on the measured magnitude.

<user_constraints>
## User Constraints (from CONTEXT.md — LOCKED)

### Locked Decisions

**Pre-Registered Protocol & Welfare-Gain Definition (REPRO-03)**
- The protocol lives at `.planning/phases/42-thesis-case-a-magnitude/42-CASE-A-PROTOCOL.md` and
  is committed in its own commit BEFORE any Case A run executes (success criterion 1);
  measurement scripts may be written first, but the 784-house run is gated on the protocol
  commit (the script asserts the protocol file exists, fail-loud).
- The relative welfare gain is the SIGN-SAFE form `Δ% = 100·(W_DADP − W_FIT)/|W_FIT|` — the
  `scripts/thesis_case123_repro.jl` precedent. The naive ratio `W_DADP/W_FIT` is NEVER used.
  The absolute gain `ΔW = W_DADP − W_FIT` is reported alongside.
- Secondary lenses are reported but never replace the headline: the prosumer/DSO surplus split
  (including the DSO-surplus sign flip) and the DADP-vs-λ₀ price-signal behaviour. No new
  formulation is introduced for any lens.
- Refusal handling INSIDE the protocol: the bounded AGR solver-precision ladder
  (`default → gap_1e-10 → gap_1e-12 → gapfeas_1e-12`, stop-on-first-certified, the
  `scripts/case_a_agreement.jl` `AGR_TOL_RUNGS` Dict), invoked via `solve_admm`'s documented
  `agr_optimizer` seam. The exactness gate, battery τ and ρ are never touched; adding a ladder
  rung requires editing the script (deliberate-act friction).

**Headline Measurement (REPRO-04)**
- Engine: the ADMM published-price path (`dadp == λ`) produces the headline DADP numbers, with
  the centralized `solve_welfare` solve recorded as the cross-check bound; both rows land in
  the artifacts. The FIT leg comes from `fit_baseline` unchanged (batteryless A4).
- Frozen registered configuration: `:case_a_784` population over `:ieee13`, `ConvexBranchFlow()`,
  T=24, λ₀ = `build_price(:mem)`, `allow_export = true`, profiles seed
  `sub_seed(master, :profiles)`, population seed `sub_seed(master, :population)`,
  ρ = `ADMM().ρ` (locked, no re-tuning), executor defaults with provenance stamped.
- Seed spread: master seeds {42 (primary/registered), 43, 44, 45, 46} — full honest re-draws
  via POP-02 hash seeding. Per-seed absolute and relative gains plus mean and min–max spread;
  seed 42 stays the continuity anchor.
- The known 784-house ADMM refusal at iters=80 is handled honestly: the refusal is recorded as
  its own status row, then answered ONLY by the pre-registered ladder. A FIT-leg solver failure
  (`SolveFailedError`/`CertificateError`/`ConvergenceError`) is likewise an honest status row;
  the only sanctioned FIT seam is the documented `fit_optimizer` conditioning passthrough. The
  A1/A4 batteryless-FIT asymmetry is stated in the writeup, never back-filled.

**Ablation & Gap Attribution (REPRO-05)**
- OFAT from the registered configuration over exactly four axes: (a) FIT parameters
  (`FIT_λ_EXPORT = 9.6` / `FIT_λ_SELF` thesis page-93 values vs documented variants), (b) price
  range (λ₀ `:mem` shape vs documented scalings), (c) population (784 houses vs 1-house-per-bus
  proxy vs Phase-40 nested-prefix ladder rungs), (d) device mix (batteries in/out,
  PV-ownership split). Axis names AND values fixed in the protocol BEFORE any ablation run —
  no free-form search.
- Attribution is a per-axis effect table on Δ% plus a written statement. "Gap not fully
  attributed" is an acceptable, recorded outcome; closing the gap to +25% is explicitly NOT a
  success condition.
- Proxy comparison: the SAME protocol re-run on the 1-house-per-bus `:default` proxy so the
  restated ≈+0.263% figure is reproduced under the pre-registered definition; the population
  axis shows the gain-vs-population curve from the Phase-40 ladder rungs.
- No-tuning guard is STRUCTURAL: axes/values committed pre-run; every intermediate row
  committed; any post-hoc constant requires an explicit protocol-amendment commit; code review
  checks no constant was fit to the +25% target.

**Artifacts, Tests & Writeup**
- Results land in `results/thesis_case_a_magnitude/` as CSVs with the upsert provenance idiom;
  a kill mid-run leaves the rows already captured — a kill is a measured outcome.
- Writeup is a literate page (new page or dated "Appended" section — the Phase-35/39/40
  pattern) with the protocol, headline gain table, ablation table, honest-magnitude framing.
  Derived percentages recomputed live, never restated stale.
- Tests cover STRUCTURAL invariants only: sign-safety on negative-welfare fixtures, ledger
  conservation on measured runs, the protocol-file-exists guard. Full-population-solve tests
  are `:slow`-tagged. NO golden on the measured magnitude.
- Runner shape: dedicated script (e.g. `scripts/case_a_magnitude.jl`) assembling existing
  validated seams — `compare_tariffs` for the four-leg settlement where it fits. `src/` stays
  untouched unless an additive seam proves genuinely necessary.

### the agent's Discretion
- Exact seed count (≥3, recommended 5), ladder rung selection mechanics, script/CSV column
  layout, literate page structure, and the ablation's specific documented variant values within
  the four fixed axes — subject to the protocol-first commit ordering.

### Deferred Ideas (OUT OF SCOPE)
- The DSO flexibility-market leg and the SETL-08 five-way comparison table — Phase 45 scope.
- Thesis Appendix E absolute-figure digitization (+$1,819/+25%) — remains deferred per
  PROJECT.md; this phase reports the framework's own absolute values.
- Any coupling with new devices (DEV, Phase 43) or aggregator-actor objectives (ACTOR,
  Phase 44) — the device-mix axis varies only the EXISTING registered mix.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REPRO-03 | Case A protocol (welfare-gain definition, baseline, parameters) pre-registered in writing before the run | New `42-CASE-A-PROTOCOL.md` + fail-loud script guard (Pattern 1, no repo precedent — design given); sign-safe gain precedent `thesis_case123_repro.jl:337`; refusal ladder pre-registered from `AGR_TOL_RUNGS` (`case_a_agreement.jl:116-126`) |
| REPRO-04 | Researcher runs Case A on the real 784-house population, gets DADP-vs-FIT welfare gain (absolute + relative + seed spread), reported honestly whatever the magnitude | Certified-run seam: `solve_admm(…; agr_optimizer = select_optimizer(QP(); rung…))` (`solve_admm.jl:207-232`, measured precedent `agreement.csv`); FIT leg `fit_baseline` (`fit.jl:382-396`); W_FIT = `fit.welfare` = social_fit (`fit.jl:641-643`); seed loop via `sub_seed` (`materialize.jl:24`); runtime budget measured (`threads_sweep.csv`, `scaling_ladder.csv`) |
| REPRO-05 | Ablation attributes the remaining gap to the thesis +25% (FIT parameters, price range, population, device mix), compared with the 1-house-per-bus proxy (≈+0.26%); no parameter tuned toward the target | Axis seams: (a) `fit_baseline(…; λ_import, λ_export, λ_self)` kwargs (`fit.jl:387-391`); (b) λ₀ vector arithmetic over `build_price(:mem,…)` (`materialize.jl:98-109`); (c) `:default` / `:case_a_784` / `_case_a_rung_counts` nested prefixes (`materialize.jl:349-394`); (d) script-side house rebuild from `_case_a_house` primitives dropping/altering `PVBattery` + `_case_a_pv_group` (`materialize.jl:417-522`); proxy ≈+0.263% provenance is `thesis_case123_repro.jl` on IEEE-123 (see Open Question 1) |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Protocol pre-registration + fail-loud guard | Script (`scripts/case_a_magnitude.jl`) + `.planning/` doc | Git history | The protocol is a planning doc; the guard lives at script top so no run can start ungated |
| Headline W_DADP (published-price path) | `src/admm/solve_admm.jl` (consumed via ladder idiom) | Script | `compare_tariffs` cannot thread `agr_optimizer`; the ladder is caller-owned (deliberate-act friction) |
| Headline W_FIT | `src/pricing/fit.jl` `fit_baseline` (consumed unchanged) | Script | Golden — consumed via documented `optimizer`/`on_inexact` kwargs ONLY |
| Gain arithmetic (Δ, Δ%, spread) | Script | Test file | One pure function in the script/lib, unit-tested for sign-safety on negative fixtures |
| Settlement lenses (surplus split, equity, rebound, price signal) | `src/settlement/comparison.jl` `compare_tariffs` | Script | SETL-02 runner returns DataFrames, no file IO; script owns persistence |
| Centralized cross-check bound | `src/models/welfare_solve.jl` `solve_welfare` | Script | Certified only at tightened solver precision at 784 (measured, `agreement.csv`) |
| Population/price/profile materialization | `src/experiments/materialize.jl` | Script | `build_population`/`build_price`/`sub_seed`/`_case_a_rung_counts`/`_case_a_house` — consumed, never modified |
| CSV artifacts (upsert, provenance) | Script (`tariff_comparison.jl` idiom) | `results/thesis_case_a_magnitude/` | Kill-anytime contract is script-owned |
| Literate writeup | `docs/literate/` page + `docs/make.jl` | Committed CSVs | Committed-CSV pattern — page performs no full-population solve (docs CI budget) |

## Standard Stack

### Core (all already in the project — ZERO new packages this phase)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Julia | 1.12.5 (local; compat floor 1.10) | runtime | pinned environment; FIT-leg 1.12.7 AC-PF flake NOT observed on 1.12.5 [VERIFIED: `julia --version`, 41-RESEARCH Pitfall 2] |
| TSODSO (this package) | — | every numerical seam | `solve_admm`, `solve_welfare`, `fit_baseline`, `compare_tariffs`, `build_*` selectors |
| Clarabel.jl | 0.11.1 | all certified solves | accurate duals ARE the prices; SCS never for certified prices (standing policy) [VERIFIED: 40-RESEARCH env table] |
| CSV.jl / DataFrames.jl | 0.10.16 / 1.8.2 | artifacts | the upsert idiom's building blocks |
| CairoMakie.jl | (docs env) | writeup figures | thesis-grade; docs-env stacked load path |
| Test + TestItemRunner | stdlib / 1.x | structural tests | `@testitem` + `tags`; `TSODSO_TEST_SET` lanes |

### Supporting
| Library | Purpose | When to Use |
|---------|---------|-------------|
| DrWatson `@quickactivate` | script env bootstrap | every `scripts/*.jl` (existing convention) |
| `LinearAlgebra.BLAS` | pin `set_num_threads(1)` | row-to-row comparability of every measured run |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Direct `solve_admm` + `fit_baseline` for headline | additive `agr_optimizer` kwarg on `compare_tariffs` | Option B gives the four-leg settlement at the certified point in ONE call per seed at the cost of one additive src kwarg (byte-identical default, `fit_optimizer` precedent). Option A is zero-src but leaves the surplus-split lens without a 784-house certified carrier (ground CSV shows centralized-engine legs only) |
| `thesis_caseA.jl`-style welfare construction | committed `fit_baseline` welfare | `thesis_caseA.jl` hand-builds the FIT welfare for the digitized thesis framing; `fit_baseline`'s `social_fit` is the validated golden — use it |
| Naive ratio W_DADP/W_FIT | sign-safe `100·Δ/|W_FIT|` | ratio SIGN-INVERTS on negative welfare (welfare ≈ −3.78e5 at 784) — banned by PROJECT.md Key Decision |

**Installation:** none — zero new packages. **Version verification:** n/a (no registry calls this phase).

## Package Legitimacy Audit

**No external packages are installed by this phase** — the entire stack is already pinned in
`Project.toml`/`Manifest.toml` and validated by prior phases. Gate: n/a. If the planner
introduces any new dependency (none is expected), run the Package Legitimacy Gate protocol
before recommending it.

## Architecture Patterns

### System Architecture Diagram

```
                        42-CASE-A-PROTOCOL.md (committed FIRST; git SHA stamped per row)
                                     │  fail-loud guard: isfile + committed?
                                     ▼
  scripts/case_a_magnitude.jl  (--mode headline | proxy | ablation-fit | ablation-price |
        │                       ablation-population | ablation-devices;  --seed 42..46)
        │
        ├─► build_feeder(:ieee13) ─ build_price(:mem, 24) ─ generate_profiles(sub_seed(m,:profiles))
        ├─► build_population(:case_a_784, …, sub_seed(m,:population))      [10 bus roll-ups / 784 houses]
        │      (variants: :default proxy · _case_a_rung_counts prefixes · script-side device-mix rebuild)
        │
        ├─► HEADLINE  W_DADP: AGR LADDER over solve_admm(…; ρ = ADMM().ρ, agr_optimizer = rung)
        │        default ──refuse──► gap_1e-10 ──refuse──► gap_1e-12 ──refuse──► gapfeas_1e-12 ──► HARD STOP
        │        (every rung row recorded; stop-on-first-certified; status rows for refusals)
        │
        ├─► HEADLINE  W_FIT: fit_baseline(feeder, pf, aggs; T, λ₀, on_inexact = :report
        │        [, optimizer = fit_optimizer])  →  fit.welfare   (or honest error row)
        │
        ├─► ΔW = W_DADP − W_FIT ;  Δ% = 100·ΔW/|W_FIT|     [sign-safe; pure function; unit-tested]
        │
        ├─► LENSES: compare_tariffs(feeder, ConvexBranchFlow(), aggs; T, λ₀, engine,
        │        houses = 784 per-house Aggregators, map_rows = case_a_household_map(…))
        │        → summary / household_bills / equity_breakouts / rebound DataFrames
        │        (per-leg honest statuses: ok · fit_inexact · error:<Type>)
        ├─► CROSS-CHECK: solve_welfare(…; optimizer = tightened) → centralized welfare row
        │
        └─► results/thesis_case_a_magnitude/*.csv   (UPSERT keyed on provenance identity;
                 julia_version/threads/blas_threads/seed/t_horizon/mode/protocol_sha columns;
                 kill mid-run ⇒ rows so far ARE the artifact)
                                     │
                                     ▼
        docs/literate/*.jl  "Appended" section — READS the committed CSVs, recomputes every
        derived % live, states the A1/A4 asymmetry + honest-magnitude framing. No solving.
```

### Recommended Project Structure
```
.planning/phases/42-thesis-case-a-magnitude/
├── 42-CASE-A-PROTOCOL.md   # NEW: pre-registration; own commit BEFORE any run; append-only amendments
└── 42-*.md                 # GSD artifacts
scripts/
├── case_a_magnitude.jl     # NEW: the runner (kv-flag idiom, ladder Dict, upsert CSVs)
├── lib/case_a_common.jl    # OPTIONAL: shared guard/gain helpers if tests must include them
└── README.md               # register the new script (CI guard: check_scripts_index.py)
results/thesis_case_a_magnitude/
├── magnitude.csv           # per-seed rows: seed, W_DADP(status, welfare), W_FIT(status, welfare), ΔW, Δ%, rung, iters
├── ablation.csv            # per-axis OFAT rows: axis, variant, ΔW, Δ%
└── (optional lens CSVs)    # only if settlement lenses run at 784
docs/literate/
└── (new page or Appended section + docs/make.jl registration at BOTH sites)
test/
└── test_case_a_magnitude.jl # structural invariants; :slow tag on any full-population item
```

### Pattern 1: The pre-registered protocol guard (NEW pattern — no repo precedent)
**What:** the script refuses to run any Case A measurement unless the protocol file exists AND
is committed; every CSV row stamps the protocol's git SHA so amendments are auditable.
**When to use:** the very first executed code path of `case_a_magnitude.jl` (before building
anything).
**Example:**
```julia
# Source: new pattern for this phase; idioms from case_a_agreement.jl (Dict-as-ladder)
# and thesis_case123_repro.jl (self-asserting finding).
const PROTOCOL_PATH = joinpath(projectdir(), ".planning", "phases",
    "42-thesis-case-a-magnitude", "42-CASE-A-PROTOCOL.md")

protocol_sha() = readchomp(`git log -1 --format=%H -- $PROTOCOL_PATH`)  # "" if never committed

function assert_protocol_registered()
    isfile(PROTOCOL_PATH) || error(
        "case_a_magnitude: PRE-REGISTRATION VIOLATION — protocol file missing at " *
        "$PROTOCOL_PATH. Write and commit 42-CASE-A-PROTOCOL.md BEFORE any Case A run.",
    )
    sha = protocol_sha()
    isempty(sha) && error(
        "case_a_magnitude: PRE-REGISTRATION VIOLATION — protocol exists but is NOT " *
        "committed (no git history). Commit it in its own commit before running.",
    )
    return sha
end
```
**Amendment discipline:** the protocol file is APPEND-ONLY after the pre-run commit — any
post-intermediate-results change is a new dated "AMENDMENT (date, reason)" section in a new
commit; the per-row `protocol_sha` column exposes exactly which version produced each row.
Adding a ladder rung or an ablation value = editing the script/protocol = a deliberate,
reviewable act (the AGR_TOL_RUNGS friction, generalized).

### Pattern 2: The AGR ladder (verbatim reuse of the measured idiom)
**What:** stop-on-first-certified solver-precision ladder, Dict-as-total-permitted-set.
**When to use:** every 784-house ADMM solve (refusal at iters=80 is the EXPECTED first
outcome, twice recorded).
**Example:**
```julia
# Source: scripts/case_a_agreement.jl:116-126 (rung Dict) + :288-296 (splat idiom)
const AGR_TOL_RUNGS = Dict{String, Union{Nothing, NamedTuple}}(
    "default"       => nothing,
    "gap_1e-10"     => (tol_gap_abs = 1e-10, tol_gap_rel = 1e-10),
    "gap_1e-12"     => (tol_gap_abs = 1e-12, tol_gap_rel = 1e-12),
    "gapfeas_1e-12" => (tol_gap_abs = 1e-12, tol_gap_rel = 1e-12,
                        tol_feas_abs = 1e-12, tol_feas_rel = 1e-12),
)
# Rung keys are plain STRINGS: `:gap_1e-10` PARSES AS SUBTRACTION (`:gap_1e - 10`).

r = solve_admm(feeder, pf, aggs; T = T, λ₀ = λ₀, ρ = ADMM().ρ,
    (rung_attrs === nothing ? NamedTuple() :
        (; agr_optimizer = select_optimizer(QP(); rung_attrs...)))...)
# stop-on-first-certified: rung certified iff status == :converged with Real welfare.
# HARD STOP after "gapfeas_1e-12" regardless of outcome. Catch ConvergenceError /
# CertificateError / SolveFailedError → honest status row (iters from err.iterations,
# -1 sentinel when none); anything else rethrows.
```

### Pattern 3: The sign-safe gain (one pure function, one definition)
**What:** the entire REPRO-03 gain definition in three lines; the function everything else reports.
**Example:**
```julia
# Source: scripts/thesis_case123_repro.jl:337 (verbatim form); PROJECT.md sign-flip ban
welfare_gain(w_dadp::Real, w_fit::Real) =
    (Δ = w_dadp - w_fit, Δpct = 100 * (w_dadp - w_fit) / abs(w_fit))
# NEVER: w_dadp / w_fit   — sign-inverts when welfare is negative (it is: ≈ −3.78e5 at 784).
```

### Pattern 4: Upsert CSV artifacts (kill-anytime honesty)
**What:** rows keyed on provenance identity, `cols = :union`, one row per status including
refusals. **When to use:** every CSV this phase writes.
**Example:**
```julia
# Source: scripts/tariff_comparison.jl:198-220 (upsert_row) + :375-401 ((run) status row)
upsert_row(MAGNITUDE_CSV,
    merge((seed = SEED, mode = mode_name, rung = rung, status = status,
           welfare_dadp = wd, welfare_fit = wf, delta_w = d, delta_pct = dp,
           iters = it, protocol_sha = sha), provenance_row(T_H, SEED));
    key = (:mode, :seed, :t_horizon))
# provenance_row stamps julia_version, threads, blas_threads, seed, t_horizon.
```

### Pattern 5: Two architectures for the headline — planner decision point
- **Option A (zero src changes — CONTEXT's stated default):** headline from direct
  `solve_admm`-ladder + `fit_baseline` welfares; `compare_tariffs` used "where it fits"
  (proxy-scale runs, and at 784 only if its default-engine legs certify, which the committed
  evidence says they will NOT at seed 42 without conditioning). Cost: the settlement lenses
  (surplus split, per-house equity) have no certified 784-house carrier unless the script
  re-assembles legs — which violates Don't-Hand-Roll.
- **Option B (recommended if lenses wanted at 784):** ONE additive kwarg on
  `compare_tariffs` — `agr_optimizer = nothing` forwarded verbatim to the `engine = :admm`
  `solve_admm` call, exactly mirroring the existing `fit_optimizer` and `time_limit_s`
  passthroughs in the same signature (`comparison.jl:243-257`). Default `nothing` is
  byte-identical (golden policy); the exactness gate, τ, ρ untouched. This is precisely
  CONTEXT's "unless an additive seam proves genuinely necessary" clause: the protocol
  requires the proxy comparison to run "the SAME code path", and only this kwarg lets
  ladder-conditioned 784 runs and the proxy share `compare_tariffs` end-to-end. Note the
  cost: a refused rung re-runs the whole four-leg settlement on retry (≤2 wasted
  `fit_baseline` solves per seed per the measured precedent — acceptable).

### Anti-Patterns to Avoid
- **Re-tuning after seeing a refusal:** the entire point of pre-registration. Refusals are
  rows; the ladder is the only answer; ρ/τ/gates never move.
- **The naive welfare ratio:** silently sign-inverts on negative welfare. Banned.
- **Golden on the measured magnitude:** never; new goldens only on sign-safe plumbing
  (e.g. `welfare_gain` known-value anchors), gate-then-golden if ever needed.
- **Free-form ablation search:** axes AND values are committed pre-run; "no parameter is
  tuned toward the target" is enforced structurally (protocol + committed intermediate rows +
  code review), not by intention.
- **Solving in the literate page:** committed-CSV reads only (docs 30-min CI budget; Phase-40
  Pitfall 7).
- **Stale derived figures in the writeup:** every % recomputed live from committed rows
  (Phase-28 CR-01 discipline).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Population ladder rungs | new subsetting code | `_case_a_rung_counts` + the `case_a_scaling.jl` prefix construction (assert 1.0-rung == `build_population(:case_a_784,…)` — the existing tripwire) | nested-prefix contract + no-per-rung-retuning already encoded |
| House→bus/PV-group attribution | new mapping | `case_a_household_map` + `_case_a_house`/`_case_a_house_seed` | single source of truth with the builder; alignment asserted in `tariff_comparison.jl` precedent |
| Per-house price-taker dispatch for equity | custom QP per device | `compare_tariffs(houses = …, map_rows = …)` internals (`price_taker_dispatch`) | certificates, τ discipline, exclusion counts already validated |
| FIT counterfactual | any new FIT math | `fit_baseline` unchanged (`optimizer`/`on_inexact` kwargs only) | golden; nested SITE-3 fallback band already encoded (`FIT_SITE3_ALMOST_GAP_TOL`) |
| Surplus split / DSO sign-flip lens | re-derived accounting | `compare_tariffs` summary rows (`dso_total`, `merchandising_surplus`) cross-checked by `welfare_accounting` | ledger conservation is free correctness |
| Solver-precision ladder | ad-hoc tolerance tweaks | `AGR_TOL_RUNGS` Dict + splat idiom | the pre-registered, friction-by-design mechanism |
| CSV artifact contract | bespoke IO | `upsert_row` idiom (`tariff_comparison.jl:198-220`) | kill-anytime, schema-evolving, provenance-stamped |

**Key insight:** this phase is pure assembly + honest recording. The ONLY new code is the
protocol guard, the gain function, the seed/ablation loop, and CSV writers — all script-side.
Any urge to touch `src/` should resolve to Option B's single additive kwarg or nothing.

## Common Pitfalls

### Pitfall 1: The 784-house refusal is the EXPECTED first outcome — plan the ladder in, not around it
**What goes wrong:** a plan that assumes the default-rung ADMM run certifies; the run burns
~10 min then throws, and an unplanned retry loop invites quiet re-tuning.
**Why:** measured twice — `scaling_ladder.csv` rung6 and `threads_sweep.csv` all three legs:
`error:CertificateError` at iters=80 (battery complementarity, bus 5 t=16, product 0.04% over
the ~1e-12 relative band); Phase-41 reproduced it (`tariff_comparison.csv` case-a-784
`(run)` row). [VERIFIED: committed CSVs]
**How to avoid:** the protocol pre-registers the ladder; the script's first 784-house ADMM
attempt IS rung `default`, its refusal row IS data, and `gap_1e-10` is the expected certify
rung (it certified at iters=80, exact_maxgap 2.77e-10, welfare −378163.5654, rel-delta
6.22e-7 vs centralized — `agreement.csv`).
**Warning signs:** any plan task wording that treats `CertificateError` as exceptional.

### Pitfall 2: `compare_tariffs` cannot thread solver conditioning — its 784-house engines BOTH refuse at defaults
**What goes wrong:** calling `compare_tariffs(engine = :admm)` at 784 reproduces the refusal
(no `agr_optimizer` kwarg, `comparison.jl:243-257`); `engine = :centralized` at defaults hits
the SOC-exactness gate refusal Phase-40 measured at full scale (certified only at
`tol_gap_1e-10` — `agreement.csv` centralized path; no `optimizer` kwarg either).
**How to avoid:** headline via direct seams (Option A) or the single additive passthrough
kwarg (Option B). The FIT leg inside `compare_tariffs` DOES have its documented
`fit_optimizer` conditioning seam already.
**Warning signs:** a plan task that says "compare_tariffs produces the headline at 784"
without a conditioning story.

### Pitfall 3: The seed-42 `:default` proxy refuses too — and the ground FIT leg is a recorded INFEASIBLE
**What goes wrong:** assuming the proxy leg is trivial. The seed-42 default population's
centralized run is refused at the battery-complementarity certificate (bus 5 t=16; recorded
as the ground `(run)` row precedent), and the committed ieee13-ground FIT leg is
`error:SolveFailedError` — termination INFEASIBLE (`tariff_comparison.csv` line 5).
**How to avoid:** the proxy re-run uses the same honest-row discipline; the sanctioned FIT
answer is the documented `fit_optimizer` conditioning seam (41-RESEARCH Pitfall 2 —
"tightening solver tolerance preserves the optimum", tested), and a still-refused leg is a
recorded outcome. See Open Question 1 for the feeder-choice consequences.
**Warning signs:** a protocol draft that promises the ≈+0.26% reproduction without pinning
fixture + conditioning.

### Pitfall 4: FIT-price ablation expectations — FIT prices cancel in SOCIAL welfare terms
**What goes wrong:** expecting `λ_import/λ_export/λ_self` to enter `social_fit` directly.
**Why:** `social_fit = fa.total_utility − Σ_t λ₀[t]·imports[t]` — the FIT transfers cancel
(`fit.jl:638-643`). The axis acts INDIRECTLY: FIT prices shape the FIT-OPT dispatch
(incentives), which moves utility and imports, hence welfare.
**How to avoid:** the protocol's axis-(a) hypothesis should predict small, dispatch-mediated
effects; report whatever appears. Never "fix" the definition to make the axis matter.
**Warning signs:** a writeup claiming FIT parameters enter the welfare formula termwise.

### Pitfall 5: Device-mix axis needs a script-side rebuild — `_case_a_house` ignores `pv_fraction`
**What goes wrong:** assuming a kwarg exists to produce "batteries out" or a non-1.0 PV split.
**Why:** `_case_a_house` builds the FIXED 3-device set (Thermostatic + Deferrable +
PVBattery) and `pv_fraction` is accepted "for symmetry… NOT used by this construction"
(`materialize.jl:456-522`); `_CASE_A_PV_FRACTION = 1.0` is map-only.
**How to avoid:** the script rebuilds houses from the SAME `_case_a_house` primitives in
`case_a_household_map` order and then (i) drops `PVBattery` from each house's device vector
before roll-up (batteries-out), or (ii) builds protocol-pinned non-PV houses with the
reduced device set (PV split), keeping `case_a_household_map`'s `pv_group` consistent with
the actual device sets. Roll-up stays 10 bus-level aggregators (the 1:1 guard, 40-RESEARCH
Pitfall 1). All protocol-fixed pre-run; zero src changes.
**Warning signs:** a plan that passes `pv_fraction` and expects devices to change.

### Pitfall 6: Symbol-parsing traps in rung/path names
**What goes wrong:** `:gap_1e-10` parses as `:gap_1e - 10` (subtraction); same for
`:tol_gap_1e-10`.
**How to avoid:** plain `String` keys for rungs (the Dict idiom); explicit `Symbol("tol_gap_1e-10")`
where a Symbol tag is needed (`case_a_agreement.jl:88-90` note). [VERIFIED: script comments]

### Pitfall 7: Suite/housekeeping guards around new files
**What goes wrong:** (a) new script missing from `scripts/README.md` → `check_scripts_index.py`
CI failure (`.github/workflows/CI.yml:175`); (b) any new `@test_broken`/`@test_skip` record
missing from `test/expected_broken.txt` fails the whole suite; (c) new docstring content lost
by JuliaFormatter `|`-continuation bug; (d) soft-scope accumulator bugs making loop tests
vacuous; (e) page not registered at BOTH sites in `docs/make.jl`.
**How to avoid:** register the script; add exact expected_broken keys same-commit if a
conditional-broken site appears; avoid `|`-leading wrapped docstring lines; `let`-wrap scan
state; register Literate tuple + pages tree. [VERIFIED: 40-RESEARCH Pitfalls 7-10,
41-RESEARCH Pitfall 6]

### Pitfall 8: Equality assertions on solver floats across legs/seeds
**What goes wrong:** raw `==` across independently solved legs (or seeds 43-46) flakes on
knife-edge degeneracies.
**How to avoid:** assert STRUCTURAL identities exactly (ledger double-entry, conservation on
the same numbers) and solver comparisons within measured, pinned tolerances (gate-then-golden).
Per-house re-solves need not bitwise-match aggregator dispatch (41-RESEARCH Pitfall 5).
**Warning signs:** a test asserting `w_dadp_seed43 == w_dadp_seed44` or bitwise household sums.

### Pitfall 9: Runtime budget — the phase's real risk
**What goes wrong:** planning the whole measurement as one foreground command; context/timeout
death mid-run loses nothing (upsert contract) but blocks the phase.
**Why it happens:** 784-house ADMM ≈ 593 s serial to refusal at iters=80; certified
`gap_1e-10` run unmeasured for wall time (no wall_s column in `agreement.csv`); ladder
rungs 1-5 sum ≈ 495 s; FIT leg at 784 and per-house re-solves unmeasured at scale.
**How to avoid:** per-axis/per-seed `--mode`/`--seed` flags; background execution with
generous timeouts; `time_limit_s` honesty (`:budget_exceeded` is a recorded outcome, its
`UnconvergedAdmmError` guard is fail-loud); BLAS pinned to 1; one measurement process at a
time (~4 GB observed for the full-scale centralized solve vs ~4 GB currently available).
[VERIFIED: CSVs; 40-RESEARCH env table] [ASSUMED: per-seed 25-40 min extrapolation]

## Runtime State Inventory

Not a rename/refactor/migration phase — omitted per protocol. (No stored keys, service
configs, OS registrations, secret names, or build artifacts carry renamed strings; the phase
adds new result files only.)

## Code Examples

### The frozen registered configuration (verbatim shape)
```julia
# Source: scripts/tariff_comparison.jl case-a-784 mode + case_a_agreement.jl agreement_main
using TSODSO: ADMM, ConvexBranchFlow, build_feeder, build_price, build_population,
              sub_seed, generate_profiles, solve_admm, solve_welfare, fit_baseline,
              select_optimizer, QP, CertificateError, ConvergenceError, SolveFailedError
BLAS.set_num_threads(1)
feeder    = build_feeder(:ieee13)
profiles  = generate_profiles(; seed = sub_seed(SEED, :profiles), T = 24)
λ₀        = build_price(:mem, 24, nothing)
pf        = ConvexBranchFlow()
aggs      = build_population(:case_a_784, feeder, :ieee13, profiles, sub_seed(SEED, :population))
# ADMM leg (ladder): ρ = ADMM().ρ is a REQUIRED kwarg (locked no-re-tuning); agr_optimizer
# is the ONLY sanctioned conditioning. allow_export = true on both engines (exactness enabler).
```

### W_FIT and the headline pair
```julia
# Source: src/pricing/fit.jl:382-396 (kwargs), :641-643 (social_fit definition)
fit = fit_baseline(feeder, pf, aggs; T = 24, λ₀ = λ₀, on_inexact = :report)
# fit.welfare == social_fit == total_utility − Σ_t λ₀·imports  (FIT transfers cancel — Pitfall 4)
# conditioning seam ONLY: fit_baseline(…; optimizer = <differently-conditioned factory>)
w_dadp = admm_result.welfare          # from the certified ladder rung
Δ, Δpct = welfare_gain(w_dadp, fit.welfare)   # Pattern 3 — the ONLY headline definition
```

### Cross-check bound (centralized)
```julia
# Source: scripts/case_a_agreement.jl Leg-1 contract + agreement.csv measured path
ctx, w_cen, _ = solve_welfare(feeder, pf, aggs; T = 24, λ₀ = λ₀, allow_export = true,
    optimizer = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10))
# On CertificateError at default: re-run tightened; record WHICH path in the row
# (centralized_optimizer column: default | tol_gap_1e-10). Gate never touched.
```

### OFAT ablation row shape
```julia
# axis ∈ (:fit_params, :price_range, :population, :device_mix); variant = protocol-pinned value
upsert_row(ABLATION_CSV,
    (axis = "fit_params", variant = "lam_export_half", seed = SEED,
     welfare_dadp = wd, welfare_fit = wf, delta_w = d, delta_pct = dp, status = "ok",
     protocol_sha = sha), provenance_row(T_H, SEED);
    key = (:axis, :variant, :seed, :t_horizon))
# The DADP leg is INDEPENDENT of axis (a) (FIT prices touch only the FIT counterfactual):
# reuse the seed's certified W_DADP; re-solve only fit_baseline. Axes (b) and (d) change the
# DADP problem itself → full ladder re-run per variant. Axis (c) reuses measured rung walls
# (~8 min per full curve at executor defaults, scaling_ladder.csv).
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| 784-house ADMM = refused artifact, per-tariff comparison blocked | certified `agr_optimizer` rung path measured (agreement.csv) + this phase's protocol | Phase 40 (2026-10-24) | the headline is now computable; the ladder is pre-registered, not improvised |
| FIT welfare hand-built in `thesis_caseA.jl` (ratio ≈1.25 target) | `fit_baseline` golden `social_fit` + sign-safe Δ% | Phases 35→41 | one validated definition; the +25% becomes the MEASURED question |
| `compare_tariffs` centralized-only settlements at ground scale | SETL-02 runner with honest per-leg statuses + `(run)` rows | Phase 41 (2026-10-25) | the four-leg settlement exists; only conditioning passthrough is missing (Option B) |

**Deprecated/outdated:** the aggregate welfare ratio as headline (sign-inverts on negative
welfare — banned); `@test_skip`-style hidden skips (use `expected_broken.txt` exact keys);
solving inside literate pages (committed-CSV pattern instead).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Certified `gap_1e-10` 784-house ADMM run costs ~10–15 min serial (per-iteration extrapolation from 593 s/80 iters; tighter AGR tolerance adds overhead; wall time NOT recorded in `agreement.csv`) | Pitfall 9 / Summary | plan time budgets off by ~2×; mitigated by kill-anytime upsert + background scheduling |
| A2 | Per-seed headline cost 25–40 min serial; whole-phase measurement 6–12 h | Summary / Pitfall 9 | scheduling only — artifacts stay honest under any pacing |
| A3 | `fit_baseline` at 784 houses completes in minutes and does not hit the FIT magnitude-sanity band guard (band = `PRICE_MAX·(Np+1)·T`; welfare ≈ −3.78e5 scale) | Headline seams | if it errors, the row is honest data and the phase still succeeds on REPRO-04's "whatever the magnitude" terms — but REPRO-05's FIT axis thins |
| A4 | Option B's additive `compare_tariffs` kwarg is golden-safe (byte-identical default, mirroring `fit_optimizer`/`time_limit_s`) | Pattern 5 | if the planner rejects any src touch, Option A still satisfies the phase with lenses reported only where engines certify |

## Open Questions (RESOLVED)

Resolutions adopted in the phase plans: Q1 → (a) ieee123-primary / ieee13-secondary proxy pin (42-01 §8c, 42-03); Q2 → Option B, the additive byte-identical `agr_optimizer` kwarg (42-02); Q3 → generous budgets + honest `:budget_exceeded` rows, no pre-registration issue (42-05).

1. **Which fixture is "the 1-house-per-bus proxy" for the ≈+0.263% restatement?**
   - What we know: ≈+0.2630% was measured by `thesis_case123_repro.jl` on **IEEE-123** (one
     aggregator per load bus); the committed **ieee13-ground** proxy (`:default`, seed
     20260718) has a certified DADP leg but its FIT leg is a recorded INFEASIBLE, and the
     seed-42 default population refuses the battery certificate.
   - What's unclear: does the protocol pin (a) `:default` on `:ieee123` (matches the ≈+0.263%
     provenance; FIT leg known to work there) as the proxy restatement, with the ieee13
     `:default` as a secondary same-feeder point, or (b) ieee13-only with `fit_optimizer`
     conditioning and an honest possible refusal?
   - Recommendation: pin (a) in the protocol — "same code path, same gain definition" is then
     literally true against the restated figure — and record the ieee13 point as the
     same-feeder proxy row whatever its status.
2. **Option A vs Option B for the settlement lenses at 784** (Pattern 5).
   - What we know: CONTEXT prefers zero src changes but explicitly permits a genuinely
     necessary additive seam; `compare_tariffs` lacks both `agr_optimizer` and `optimizer`.
   - Recommendation: Option B (one additive kwarg, byte-identical default) if the writeup's
     surplus-split/equity lenses must exist at the certified 784-house point; otherwise
     Option A with lenses reported at every scale where engines certify.
3. **Wall time of the certified rung at seeds 43–46** — iterations may differ per seed
   (rung5 hit 91 iters; seed 42 certified at exactly 80).
   - Recommendation: no pre-registration issue (the ladder is seed-independent); just budget
     generously and let `time_limit_s` produce honest `:budget_exceeded` rows if a seed stalls.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia | everything | ✓ | 1.12.5 | — (FIT 1.12.7 flake not observed here) |
| CPU (4 cores) | serial measurement | ✓ | 4 | `-t 4` executor optional; BLAS pinned 1 |
| RAM | full-scale solves | ✓ (15 GB total; ~4 GB available at research time) | — | run ONE measurement process at a time (~4 GB observed) |
| Clarabel.jl | all certified solves | ✓ | 0.11.1 | SCS present but NEVER for certified prices (policy) |
| CSV.jl / DataFrames.jl | artifacts | ✓ | 0.10.16 / 1.8.2 | — |
| `scripts/` CI guard + docs env | new script + page | ✓ | — | register in scripts/README.md; docs/Manifest already TSODSO-linked |
| git | protocol commit gating | ✓ | repo | — |

**Missing dependencies with no fallback:** none. **Missing dependencies with fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Test stdlib + TestItemRunner (`@testitem` + `tags`), `expected_broken.txt` guard |
| Config file | `test/runtests.jl` + `test/runner_support.jl` (`TSODSO_TEST_SET = fast\|slow\|all`) |
| Quick run command | `TSODSO_TEST_FILES=test_case_a_magnitude.jl julia --project=. -e 'import Pkg; Pkg.test()'` |
| Full suite command | `julia --project=. -e 'import Pkg; Pkg.test()'` (CI runs the fast set; 60-min timeout) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| REPRO-03 | Sign-safety of `welfare_gain` on negative-welfare fixtures (W_FIT < 0 ⇒ Δ% sign correct; naive ratio would invert — assert the function, not a magnitude) | unit | `TSODSO_TEST_FILES=test_case_a_magnitude.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ❌ Wave 0 |
| REPRO-03 | Protocol-file guard: throws on missing file; throws on uncommitted file; returns SHA on the committed protocol | unit (tmpdir git repo + real path) | same file | ❌ Wave 0 |
| REPRO-03/04 | Ledger conservation on the measured runs: committed `magnitude.csv`/lens rows satisfy aggregate identities (ledger double-entry on any lens rows; Δ identity Δ = W_DADP − W_FIT re-derived from columns) | unit reading committed CSVs (no solving) | same file | ❌ Wave 0 |
| REPRO-04 | One real 784-house ladder+gain run reproduces the committed `magnitude.csv` seed-42 row within pinned tolerance (or records the honest refusal row) — `:slow` | integration, `:slow` tag | `TSODSO_TEST_SET=slow TSODSO_TEST_FILES=test_case_a_magnitude.jl julia --project=. -e 'import Pkg; Pkg.test()'` | ❌ Wave 0 |
| REPRO-05 | Ablation table structural integrity: every protocol axis/variant value appears in `ablation.csv` exactly once per executed seed (no cherry-picking gap); statuses ∈ the honest set | unit reading committed CSVs | fast lane | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** the fast-lane items of `test_case_a_magnitude.jl` (sign-safety, guard,
  CSV-structure — no solving, seconds).
- **Per wave merge:** full fast suite via `Pkg.test()`.
- **Phase gate:** fast suite green + the `:slow` 784-house item's committed-row agreement
  checked before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `test/test_case_a_magnitude.jl` — sign-safety + guard + CSV-structure items (fast) and
      the `:slow` full-population agreement item
- [ ] Shared gain/guard helper importable by both script and test (`scripts/lib/case_a_common.jl`
      include pattern, or duplicate the 3-line function in the test — planner's call)
- [ ] No framework install needed (TestItemRunner present)

## Security Domain

`security_enforcement` is not disabled in `.planning/config.json` → section required. This is
an offline measurement phase: no network I/O, no auth, no sessions, no new user input paths,
no cryptography. Applicable ASVS surface:

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication / V3 Session / V6 Cryptography | no | nothing to protect; no secrets introduced |
| V4 Access Control | no | artifacts are repo-local files under `results/` |
| V5 Input Validation | yes (repo-internal) | existing fail-loud guards: `compare_tariffs` boundary guards (`comparison.jl:258-300`), `fit_baseline` magnitude-sanity band (`fit.jl:646-653`), `solve_admm` ArgumentError guards; script kv-flag parsers validate types/ranges (`case_a_agreement.jl:130-143` idiom) |

Known threat patterns for this stack: none new. Standing project policies that function as
integrity controls: SCS never certifies prices/exactness; gates never loosened to make a run
pass; the knife-edge canary never re-pinned; every measured row carries provenance.

## Sources

### Primary (HIGH confidence — all verified in-repo this session)
- `src/settlement/comparison.jl` — `compare_tariffs` signature (lines 243-257: NO
  `agr_optimizer`/`optimizer` kwarg), engine paths (:303-323), honest FIT catch (:646-670),
  return contract (:759-765), A1 asymmetry + settlement conventions header
- `src/admm/solve_admm.jl` — `agr_optimizer` seam doc (:207-232), `time_limit_s`/
  `UnconvergedAdmmError` (:162-178, :294-309), return/status contract (:249-262)
- `src/pricing/fit.jl` — page-93 constants (:34-36), `fit_baseline` kwargs (:382-396),
  social_fit definition + FIT-transfer cancellation (:638-643), magnitude band (:646-653)
- `src/experiments/materialize.jl` — `sub_seed` (:24), `build_price(:mem)` (:98-109),
  `_CASE_A_*` constants (:136-139), `_case_a_rung_counts` nested-prefix contract (:349-394),
  `_case_a_house_seed` (:396-414), `_case_a_pv_group` (:417-430), `_case_a_house` fixed
  3-device set, `pv_fraction` unused (:456-522), `build_population` `:case_a_784` branch
  (:546-595)
- `src/models/welfare_solve.jl` — `solve_welfare` signature (:106-127)
- `scripts/case_a_agreement.jl` — `AGR_TOL_RUNGS` (:116-126), ladder policy + rung table
  (:16-79), `run_admm` splat idiom + honest catch (:249-318), agreement_main shape
- `scripts/thesis_case123_repro.jl` — sign-safe gain (:337), ratio ban (:10-17, :308-311),
  ≈+0.2630% restatement + IEEE-123 provenance (:10-11, :44)
- `scripts/tariff_comparison.jl` — upsert contract (:31-46, :198-220), `(run)` status rows
  (:375-401), frozen case-a-784 configuration header, `case_a_houses_flat` map-aligned rebuild
- `scripts/case_a_scaling.jl` — ladder/threads-sweep modes, `DEFAULT_LADDER_FRACTIONS` (:97)
- Committed artifacts: `results/case_a_population/{scaling_ladder,threads_sweep,agreement}.csv`;
  `results/settlement_comparison/tariff_comparison.csv` (ground fit INFEASIBLE row; case-a-784
  `(run)` refusal row with bus-5/t-16 note)
- Prior-phase research: `40-RESEARCH.md` (Pitfalls 1-10, env table), `41-RESEARCH.md`
  (Pitfalls 1-8), `40-03/40-04-SUMMARY.md`, `41-04-SUMMARY.md`
- Repo policy: `CLAUDE.md` (PROJECT.md v5.0 framing), `.github/workflows/CI.yml:171-175`,
  `test/runtests.jl` / `test/expected_broken.txt` conventions, `docs/literate/settlement_equity.jl:330`
  (Appended pattern), `docs/literate/case_a_population.jl:429`

### Secondary (MEDIUM confidence)
- None needed — no external/ecosystem claims; the domain is fully in-repo.

### Tertiary (LOW confidence)
- Per-seed wall-time extrapolations (A1-A3 in Assumptions Log) — flagged `[ASSUMED]`, plan
  must budget generously and rely on kill-anytime artifacts.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — zero new packages; every seam read at source this session
- Architecture: HIGH — all runner idioms have committed, measured precedents (Phases 40-41);
  the only new pattern (protocol guard) is specified concretely
- Pitfalls: HIGH — drawn from committed CSV evidence and two prior phases' research, re-verified
- Runtime estimates: MEDIUM — anchored on measured walls; certified-rung and FIT-leg-at-784
  walls unmeasured (A1-A3)

**Research date:** 2026-10-26
**Valid until:** ~2026-11-25 (stable: measurement phase over a frozen codebase; re-check if
`src/settlement` or `src/admm` change)

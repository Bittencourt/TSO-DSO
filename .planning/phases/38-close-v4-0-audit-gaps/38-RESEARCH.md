# Phase 38: Close v4.0 Audit Gaps - Research

**Researched:** 2026-10-07
**Domain:** Julia/JuMP correctness-gate wiring (SOCP exactness certificate), TestItemRunner suite hygiene, stale-prose sweep of a hand-written 2.9 MB HTML guide
**Confidence:** HIGH for the code/test findings (every number below was measured in this session on Julia 1.12.5 and 1.12.7); MEDIUM for the FRAMEWORK_GUIDE semantic findings (static reading against current source, nothing executed)

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### MPC first-tier certificate (blocker 1)
- Compute the per-branch ratio through the shared library arithmetic (`_cone_row`, or
  `hybrid_ratios(ctx)` if it applies to the MPC window's `ModelContext`). Use the same defaults as
  `assert_socp_exact!`: `rtol = 1e-4`, `atol = nothing` (hybrid floor), `ε = MEASURED_REL_TOL_EXACT`
  and `τ = TAU_SOLVER_EXACT`. The check stays NON-throwing, and the escalation ladder is unchanged.
- Fix the docstring's parity claim so it describes the shared arithmetic.
- Before changing code, measure every MPC fixture/test/golden's first-tier max ratio under both the
  old and the new tolerance.
- USER: **accept explained moves.** If a resolve that used to certify now escalates (restricted or
  AC-dual tier) and a golden or test value moves, that is accepted when the escalation is correct
  behaviour. Each moved golden is documented in the SUMMARY with its old/new ratio and values. The
  canary is never touched.
- Add a regression test: a constructed or perturbed window point the old flat tolerance accepts
  but the hybrid floor refuses, shown to escalate.

#### Orphan ADMM timeout test (blocker 2)
- Convert `test/test_admm_timeout.jl` into `@testitem`(s) that check `:budget_exceeded` under
  `time_limit_s`. Tag `:slow` if measured at 30 s or more. Remove the obsolete
  "deliberately NOT a @testitem" rationale, since discovery has been rooted at `test/` since
  Phase 37. Update `--count-sets --strict` expectations and `expected_broken.txt` only if needed.

#### Stale prose and docs (W1, W2, W4)
- W1: `src/TSODSO.jl:265-278`, `docs/literate/mpc_rolling_horizon.jl:24-27` and
  `docs/literate/stochastic_pv_demand.jl:22-25` say run_mpc/run_stochastic are "NOT wired
  through run_scenario's strategy dispatch". Rewrite them to state the current `TSODSO.run(::MPC)` /
  `run(::Stochastic)` dispatch.
- W2, USER: **full API sweep** of `docs/writeups/FRAMEWORK_GUIDE.html`. Check every code
  example and API mention against the current API: export trim (192 → 90; unexported names need
  `TSODSO.`-qualification or `using TSODSO: x`), `ReactiveMode` module form (`ReactiveMode.LIVE`),
  removed kwargs (`objective_hook`, `horizon_state`, `z`, Bool/Symbol reactive modes), removed DLMP
  `loss`/`voltage` aliases (now `cone`/`drop`), renamed fixtures/tags, renamed constants, the
  `Scenario`/strategy API (Phase 32), and typed errors and status vocabulary (Phase 34). Fix every
  stale usage, remove planning IDs, and list the guide in `docs/writeups/README.md`. The file is
  2.9 MB, so edit surgically (scripted search, targeted replacements) and never regenerate it.
  Prefer static checks; snippets may be executed only from the session scratchpad, never as
  `.jl` files under the repo.
- W4: `src/experiments/store.jl:177-178` says only primitives are stored, but line 191 stores a
  `ReactiveMode.T`. Make the docstring match the behaviour (or store the enum as a primitive,
  provided round-trip loading stays compatible; the planner decides, and docs must match).

#### Extra hardening (W5, W6, W7)
- W5: `Scenario(strategy=ADMM(), allow_export=false)` must raise `ArgumentError` at construction
  (strategy × setting validation), with a test. The error text is consistent with `solve_admm`'s
  existing message.
- W6: `solve_stochastic_oos_step!` (`src/models/stochastic_welfare.jl:749`) runs no cone gate.
  Add the exactness check (shared gate, same defaults) so the out-of-sample `welfare_gap` is
  certified. If an OOS solve is inexact, the failure must be visible, with no silent pass. The
  planner decides between throwing `CertificateError` and recording a per-scenario status, following
  the Phase 34 status/exception policy (`docs/src/status_policy.md`). Measure every stochastic
  golden/test under the new gate first; explained moves are accepted, the canary never.
- W7: run `.github/scripts/check_setup_names.py` in the CI `format` job (with `--selftest` if it
  has one), after confirming it passes locally.

#### Gates
- Full suite sequential on Julia 1.12.5 and 1.12.7 via `suite_detached.sh` + `check_suite_log.py`.
  Baseline: 32224 / 32219 pass, 0/0, Broken 5. Itemize every pass delta. Canary iters = 56.
- JET ratchet (`scripts/jet_check.jl` on 1.12.7) gives 0 NEW. The three guards plus
  `check_setup_names.py`, `--count-sets --strict`, the docs build, `format210.jl` and
  `check_content_loss.py HEAD` all pass.

### Claude's Discretion
- Whether to reuse `_cone_row` directly or `hybrid_ratios`; test fixture construction; OOS-gate
  failure representation within the status policy; FRAMEWORK_GUIDE sweep tooling.

### Deferred Ideas (OUT OF SCOPE)
- W3: literate pages for `solve_bilevel!`, `solve_variational_equilibrium`, integer `run_nash!`.
- Phase 29 WR-01/IN-01 (bilevel certificate recovery reads cached coefficients; `_ub` ignores `is_fixed`).

Also out of scope (CONTEXT "Phase Boundary"): the accepted todos (seed 42, LinDistFlow-copy vmax
bound, 1.12.7 fit_baseline), the IEEE-8500 harness, W3, Phase 29's WR-01/IN-01. The knife-edge
canary (iters = 56, welfare = -4823.66604824162) is never re-pinned.
</user_constraints>

<phase_requirements>
## Phase Requirements

Gap closure; no new requirement IDs.

| ID | Description (REQUIREMENTS.md) | Research Support |
|----|-------------|------------------|
| FIX-08 | SOCP exactness gate uses a per-branch relative floor; a test shows a slack cone on a small branch is flagged | MPC first tier must route through the hybrid floor (Finding 1). Regression point measured: high-PV fixture `pv_scale=1.2`, `l[2,1] ≥ l* + 5e-7` gives old ratio 0.499, new ratio 2.457 on both patches |
| FIX-10 | MPC settlement against the truth plant | Published per-step prices are now certified by the same gate as the library (Finding 1); settlement path itself is not touched |
| ARCH-02 | Strategy types dispatched by one `run(strategy, scenario)` | W1 prose (Finding 6); W5 strategy × setting validation in the `Scenario` inner constructor (Finding 4) |
| ARCH-08 | One documented status policy for all entry points | Timeout test runs in the suite (Finding 2); W6 failure mode fits the policy (Finding 3) |
| HYG-02 | Removed stubs/back-compat shims | FRAMEWORK_GUIDE still shows `reactive_consensus = :live` (Finding 7) |
| HYG-03 | Export trim / namespacing | FRAMEWORK_GUIDE uses about 35 unexported names unqualified (Finding 7) |
| HYG-05 | `:slow` tags; fast and slow sets cover every test | Orphan timeout test becomes `@testitem`(s); count-sets effect computed (Finding 2) |
</phase_requirements>

## Summary

All seven work items are small, but the measurements change two of the planning assumptions.

**MPC gate (blocker 1).** `hybrid_ratios` works on the window's `ModelContext` as it is:
`build_mpc_window` sets `ctx.feeder = feeder` and `ctx.T = H` (`src/models/mpc_window.jl` builder
lines `ctx.feeder = feeder; ctx.T = H`), and the head branch comes from `_socp_head_branch(feeder)`.
Calling `hybrid_ratios` at decision points goes against its own docstring ("NEVER used to decide
pass/fail"), so the recommended fix factors the gate loop out of `assert_socp_exact!` into one
non-throwing internal helper (`_socp_cone_check(ctx; …) -> (; maxgap, maxratio)`) and calls it from
both places. Measured over every MPC scenario the suite or docs run: **on 1.12.5 no resolve flips.
On 1.12.7 exactly one resolve flips**: the forced-PV-shortfall fixture (`T=9, MPC(H=3, step=1,
forecast_error=0.3), seed=1`) at t=4, which goes from ratio 0.233 to 1.165, escalates to
`:certified_convex_dual_restricted`, and changes `status` from `:certified` to `:degraded`. Only
`dadp_trace[4]` moves (0.008895250684296654 → 0.008894113604359186). No test asserts either value,
so **no test or golden moves on either patch.** Margins are thin: the happy-path fixture's worst
hybrid ratio is **0.938 on 1.12.5** (0.323 on 1.12.7), and that item asserts "never escalates".

**OOS stochastic gate (W6).** Throwing `CertificateError` would break the build. On the docs
page's own scenario (`T=9, Stochastic(S=5, probabilities=[.05,.15,.30,.30,.20], H_oos=10)`),
**5 of 10 held-out solves are refused on 1.12.5 (max ratio 1.63) and 2 of 10 on 1.12.7 (max
1.94)**. Tightening Clarabel's tolerances does not fix it: at `tol_gap = 5e-10` it gets worse
(7/10), and `tol_feas ≤ 1e-10` makes the solve fail outright (`SolveFailedError`). The refused rows
are cone *violations* (`l·v < P²+Q²`) of 2–3.3e-7, just above `τ_solver = 2e-7`, at nonzero local
prices. The CI golden (`S=3, H_oos=5`) passes with max 0.366 / 0.350. The four direct-harness unit
tests on the near-lossless 2-bus fixture also trip at default tolerances (ratios up to 51, where
even the old flat gate gives 10.4). With `tol_gap = 5e-10` those all drop below 0.5. **Recommended:
throw in the step function, then skip and report in the orchestrator.** That mirrors the existing
infeasible-draw pattern and adds one documented status.

**Everything else is mechanical.** The timeout test takes 47.2 s cold and 11.7 s warm. Its parts
measure 0.27 s (maxiter cap), 0.28 s (`:budget_exceeded`) and 12.1 s (full convergence, 103 iters).
`check_setup_names.py` passes (21 testmodules, 220 setup uses, 0 unresolved) and has `--selftest`
(4 cases OK). The FRAMEWORK_GUIDE (3775 lines; 2.82 MB of it is 16 base64 images) has 9 `<pre>`
blocks and 482 `<code>` spans. The sweep found about 35 unexported names used unqualified, 2
Symbol reactive modes, about 10 DLMP `loss`/`voltage` mentions, about 12 flat-Scenario/strategy
statements and 19 planning-ID hits. Separately, about 10 v3.0/v4.0 *semantic* contradictions were
found (see Open Question 1).

**Primary recommendation:** Add `_socp_cone_check` in `exactness.jl` and use it for
`assert_socp_exact!`, the MPC first tier and the OOS step. Make the OOS refusal a skip-and-report
status, not a run-aborting throw. Edit the guide with a scratch-only, count-asserting Python
replacer, then verify it statically with the existing `check_script_api.jl` and planning-ID rules.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Cone-exactness arithmetic (per-branch ratio) | Models layer (`src/models/exactness.jl`) | — | One source of truth (`_cone_row`); every certificate consumer must call it, never re-implement it |
| MPC per-resolve certification + escalation | Experiments layer (`src/experiments/mpc_loop.jl`) | Models layer (gate helper) | Non-throwing ladder belongs to the orchestrator; the numbers come from the models layer |
| OOS held-out exactness | Models layer (`solve_stochastic_oos_step!` throws typed error) | Experiments layer (`_stoch_solve_held_out!` converts it to skip-and-report) | Mirrors the existing split: low-level solve throws `SolveFailedError`, the orchestrator converts documented ones into a status |
| strategy × setting validation | Experiments layer (`Scenario` inner constructor) | `solve_admm` keeps its own guard (defense in depth) | Construction-invariant rule already used for strategy × pf (`supports_pf`) |
| Result persistence (`reactive_consensus_mode`) | Experiments layer (`store.jl`) | — | Persisted dict contract |
| Test discovery / set membership | Test infra (`test/runtests.jl`, `runner_support.jl`, `scripts/run_tests_filtered.jl`) | CI (`.github/workflows/*.yml`) | — |
| Guide correctness | Docs (`docs/writeups/FRAMEWORK_GUIDE.html`, hand-written HTML) | Static checkers in `.github/scripts/` (run ad hoc) | Not part of the docs build and not in any guard's scope |

## Standard Stack

No new packages. Everything uses the pinned project environment.

| Tool | Version (measured) | Purpose |
|------|---------|---------|
| Julia | 1.12.5 (`julia +release`), 1.12.7 (`julia +1.12`) | Both gate patches available locally [VERIFIED: juliaup status] |
| TestItemRunner | 1.1.5 (test/Manifest, Julia 1.12) | Suite runner [CITED: test/runtests.jl header] |
| JuMP / Clarabel | pinned in Manifest-v1.12.toml | Solves; `select_optimizer(SOCP(); tol_gap_abs, tol_gap_rel)` override exists [VERIFIED: src/solver/factory.jl:136] |
| DrWatson/JLD2 | pinned | `wsave`/`wload` round-trip (W4 experiment) [VERIFIED: run in session] |
| JuliaFormatter | 2.10.x via `.github/scripts/format210.jl` (temp env) | Format gate [CITED: format210.jl] |
| Python 3 | system | `check_setup_names.py`, `check_planning_ids.py`, guide sweep scripts |

**Installation:** none.

## Package Legitimacy Audit

No external packages are installed in this phase. slopcheck is not needed. The project
environment and its Manifest stay unchanged.

| Package | Registry | Age | Downloads | Source Repo | slopcheck | Disposition |
|---------|----------|-----|-----------|-------------|-----------|-------------|
| (none) | — | — | — | — | — | — |

**Packages removed due to slopcheck [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### Data flow (certificate paths after the fix)

```
Scenario ──TSODSO.run(::MPC)──> _run_mpc loop ──solve_mpc_window!──> MpcWindow.ctx (feeder, T=H, pf_vars)
                                      │
                                      └─> _mpc_certify_and_price
                                             │  _socp_cone_check(o.ctx)   <── shared with assert_socp_exact!
                                             ├─ maxratio ≤ 1 → :certified_convex_dual, price = dual(balance_p)
                                             └─ maxratio > 1 → Restricted tier → AC-dual tier → :cert_failed (unchanged)

Scenario ──TSODSO.run(::Stochastic)──> _run_stochastic
     in-sample: build_stochastic_welfare ── assert_socp_exact! per scenario (throws, unchanged)
     held-out loop h=1..H_oos: _stoch_solve_held_out!(h_oos, h)
             └─ solve_stochastic_oos_step!  ── solve_with_retry! ── [NEW] gate via _socp_cone_check → throw CertificateError(kind=:socp_exact)
                   catch SolveFailedError & INFEASIBLE → (NaN, infeasible=true)        (existing)
                   catch CertificateError(:socp_exact) → (W_h, inexact=true) + @warn  (NEW)
             realized_welfare = mean over feasible & exact draws (or feasible only — Open Question 2)
             status = _stochastic_status(infeasible_h, inexact_h)
```

### Pattern 1: one non-throwing gate kernel, many policies
**What:** Factor the `assert_socp_exact!` loop into `_socp_cone_check(ctx; rtol=1e-4, atol=nothing,
ε=MEASURED_REL_TOL_EXACT, τ_solver=TAU_SOLVER_EXACT) -> (; maxgap, maxratio)`. It uses the same
`_socp_head_branch` lookup, the same `ArgumentError` on a zero-match feeder, and the same
`(b, br) in enumerate(feeder.branches), t in 1:T` loop over `_cone_row`. `assert_socp_exact!`
becomes "check then throw" and keeps its verdict and message unchanged. The MPC tier and the OOS
step call the kernel.
**Why not `hybrid_ratios`:** it works on the window ctx (verified), but its docstring says it is
"NEVER used to decide pass/fail (anti-certificate-laundering)", and it allocates and sorts every
row. Equality still holds: `maximum(r.ratio for r in hybrid_ratios(ctx)) == _socp_cone_check(ctx).maxratio`,
so tests can use `hybrid_ratios` as the oracle.
**`head_b` for the MPC window:** `_socp_head_branch(o.ctx.feeder)` is the first branch incident to
`feeder.root` (IEEE-13: the root branch; MPC fixtures: branch 1). It is computed by the helper; the
MPC code never touches it.

### Pattern 2: low level throws a typed error; the orchestrator converts documented ones into a status
Already used by `_stoch_solve_held_out!` (`src/experiments/run_stochastic.jl` ~62-79) for
`SolveFailedError` with an INFEASIBLE status. Extending it to `CertificateError` with
`kind === :socp_exact` matches status_policy §1 ("THROW for certificate refusals … RETURN a status
for … the documented stochastic skip-and-report").

### Pattern 3: strategy × setting validation in the inner constructor
`Scenario`'s inner constructor already rejects strategy × pf via `supports_pf`
(`src/experiments/Scenario.jl:194-203`). `with_strategy` goes through the inner constructor, so
`TSODSO.run(ADMM(), s_noexport)` will also throw at construction, and `run_sweep` builds every
Scenario before any solve (`sweep.jl:36-38`), so a bad sweep combination fails before work starts.

### Anti-Patterns to Avoid
- **Re-implementing the cone formula anywhere.** That is how this gap arose. Leave no inline
  `l·v − (P²+Q²)` loop in `mpc_loop.jl`.
- **Raising τ_solver/ε or the OOS tolerance to make the docs scenario pass.** The project rule is
  never to raise τ/ε (memory: exactness-gate-hybrid-floor). Measured: tighter Clarabel tolerances
  do not help on the docs fixture.
- **Planning-ID tokens in new comments/test names.** `check_planning_ids.py` scans
  src/test/scripts/docs/literate/docs/src/README/CI.yml and flags `FIX-08`, `ARCH-08`, `Phase 38`,
  `phase 27`, `wave`/`waves`, `D-05`, `byte-identical`, `code review`, `-SUMMARY` and similar
  [VERIFIED: .github/scripts/planning_id_rules.py]. Do not write "W5"/"W6"-style labels either.
- **A `.jl` with `@testitem` under the repo outside `test/`** (memory: testitemrunner-scans-scratch-jl).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-branch cone ratio in MPC/OOS | inline `lhs/rhs/tol` loop | `_cone_row` via a shared `_socp_cone_check` | Parity by construction; this phase exists because a copy drifted |
| Old-vs-new tolerance comparison in tests | hand formula | `TSODSO.hybrid_ratios(ctx; atol = 1e-6)` reproduces the OLD flat gate exactly (`atol_b = atol`) | Documented override path in `_cone_row` |
| Guide API checking | new regex lint | `.github/scripts/check_script_api.jl <abs path of scratch blocks>` (accepts absolute paths; verified) + `planning_id_rules.RULES` over tag-stripped text | Existing, self-tested tools |
| Suite run/parse | ad hoc `Pkg.test` + grep | `.github/scripts/suite_detached.sh LABEL` + `check_suite_log.py LABEL --broken 5` | Exit-status capture, totals parsing, canary check |
| Formatting | global JuliaFormatter | `julia --startup-file=no .github/scripts/format210.jl <paths>` | Pins 2.10.x |

## Runtime State Inventory

Not a rename phase. Only W4 touches persisted state.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `data/sims/*.jld2` (gitignored, local only) written by `run_and_store`. ADMM runs hold `reactive_consensus_mode::TSODSO.ReactiveMode.T`. Measured: loading without TSODSO gives `JLD2.ReconstructedPrimitive{:T, UInt32}` plus a "does not exist in workspace; reconstructing" warning; loading with TSODSO gives the enum | None (no migration). If W4 switches to Symbol storage, old files keep the enum and new files hold `:OFF/:CERTIFIED/:LIVE`; document both in status_policy §7 |
| Live service config | None. Verified: no external services | — |
| OS-registered state | None | — |
| Secrets/env vars | None. `TSODSO_TEST_SET`/`TSODSO_TEST_FILES`/`TSODSO_TEST_VERBOSE` are unchanged | — |
| Build artifacts | None. Sibling worktrees exist at `../TSO-DSO.worktrees/{operational-planning-integration,pdf-documentation-thesis-results}` (outside `.claude/worktrees`). Discovery is rooted at `test/`, so they are not scanned | Before gate runs, confirm `git worktree list` shows no `.claude/worktrees/agent-*` |

## Detailed Findings (answers to the orchestrator's questions)

### Finding 1 — MPC first-tier gate (blocker 1)

**Current code** (`src/experiments/mpc_loop.jl:866-875`):
```julia
pv = _require_pf_vars(o.ctx)
cone_maxratio = 0.0
for (b, br) in enumerate(feeder.branches), τ in 1:(o.H)
    lhs = value(pv.l[b, τ]) * value(pv.v[br.from, τ])
    rhs = value(pv.P[b, τ])^2 + value(pv.Q[b, τ])^2
    gap = abs(lhs - rhs)
    tol = 1e-6 + 1e-4 * max(abs(lhs), abs(rhs))
    cone_maxratio = max(cone_maxratio, gap / tol)
end
step_certified = cone_maxratio <= 1     # NEVER throws here
```

**Replacement** (after adding `_socp_cone_check` to `exactness.jl`, see Code Examples):
```julia
# First-tier certificate: the SAME per-(branch, hour) arithmetic and defaults as
# assert_socp_exact! (shared _socp_cone_check -> _cone_row), evaluated without throwing.
cone_maxratio = _socp_cone_check(o.ctx).maxratio
step_certified = cone_maxratio <= 1     # NEVER throws here
```
The window ctx is fully populated: `ctx.feeder = feeder`, `ctx.T = H`, and `pf_vars` is stashed by
`ConvexBranchFlow.contribute!`. MPC and Stochastic accept only `:convex_branch_flow`
(`supports_pf`, `strategies.jl:216-230`), so `pf_vars.l` always exists on this path. The `feeder`
argument and `o.ctx.feeder` are the same object in `run_mpc` and in every test. An optional
cross-check (`o.ctx.feeder === feeder || throw(ArgumentError(...))`) is cheap but not required.

**Docstring lines to rewrite:** `mpc_loop.jl:795-801` ("An inline REIMPLEMENTATION … at ITS SAME
`rtol=1e-4`/`atol=1e-6` defaults … the ONE place this file deliberately copies a tolerance"),
`:814` ("On a failed inline check"), `:99` ("first-tier inline cone check passed"), `:904`.
Other prose that becomes stale: `test/fixtures_mpc.jl:217,246-259` ("inline cone-residual check
(rtol=1e-4, atol=1e-6, run_mpc's own per-resolve formula)"), `test/test_mpc_loop.jl:7,359,363,418-419`
("inline check", "ratios ≈ 9432"), `docs/literate/mpc_rolling_horizon.jl:272` ("≈ 9157×"),
`docs/literate/ac_oracle.jl:231-232`, `test/test_ac_oracle.jl:226` (9157–9166). The high-PV
number barely moves under the hybrid floor, because the `rtol` term dominates at that cone
magnitude. Measured 1.12.5: t=1 9156.5 → 9177.7, t=4 9166.4 → 9172.5, verdict unchanged
(`:certified_convex_dual_restricted`). Re-word as "≈ 9.2×10³" or leave the numbers. Only the
"atol=1e-6 inline" wording has to change.

**MEASURED first-tier max ratio per resolve, OLD (flat 1e-6) vs NEW (hybrid)** [VERIFIED: scratch
`p38/mpc_measure.jl` patching `_mpc_certify_and_price` to log both, decision kept OLD]:

| Scenario (consumers) | 1.12.5 max OLD / NEW (worst t) | 1.12.7 max OLD / NEW | Flips |
|---|---|---|---|
| A happy: `T=9, MPC(H=3, terminal_soc=true, forecast_error=0.0)`, seed 1 — test_mpc_loop "end-to-end … never escalates", test_status_policy, test_strategies "run(MPC) common shape", "dispatch uniformity", "run_and_store round-trip" | 0.4204 / **0.9383** (t=4; b=9, gap 1.879e-7) | 0.1131 / 0.3230 | none (1.12.5 margin only 6.6%) |
| B shortfall: `T=9, MPC(H=3, step=1, terminal_soc=true, forecast_error=0.3)`, seed 1 — test_mpc_loop items 2, 4 ("A6 call site"), 9 ("AC truth settlement REPORTS") | 0.1574 / 0.7708 (t=4) | 0.2332 / **1.1653** (t=4; b=6, τ=3, gap 2.333e-7) | **1.12.7 t=4 → :certified_convex_dual_restricted** |
| C1 stride step=1: `MPC(H=3, forecast_error=0.05, step=1)` — "mpc_step strides" | 0.2485 / 0.8338 (t=6) | 0.1439 / 0.3301 | none |
| C2 stride step=2 | 0.0341 / 0.1704 | 0.0356 / 0.1780 | none |
| D default `MPC()` (H=6, fe=0.05), T=9 — test_strategies "fallback to defaults" (:slow) | 0.0643 / 0.3155 | 0.0886 / 0.4424 | none |
| E docs/script: `T=24, MPC(H=6, terminal_soc=true, forecast_error=0.08)` — docs/literate/mpc_rolling_horizon.jl, scripts/demo_mpc_plots.jl | 0.0895 / 0.4466 (19 resolves) | 0.0897 / 0.4478 | none |
| High-PV `pv_scale=3.0`, `thesis_literal=true` (test_mpc_loop items 5, 6, 8; direct `_mpc_certify_and_price`) | 9156.5 / 9177.7 (t=1); 9166.4 / 9172.5 (t=4) | not re-run (far above 1) | none (already escalates) |

**What moves (1.12.7, scenario B only, measured with the NEW decision):** `cert_status_trace[4]`
`:certified_convex_dual` → `:certified_convex_dual_restricted`; `status` `:certified` →
`:degraded`; `dadp_trace[4]` 0.008895250684296654 → 0.008894113604359186. Unchanged: `regret`
(-0.0469747761931103), `realized_welfare` (-468.99585116665), `forecast_settled_welfare`,
`settlement_violations` (abs_hour 5: `n_thermal_violations=1`, `max_overload_ratio=1.0417750983837797`)
and `pvbattery_truth_trace`. Escalation only re-prices; it never changes the applied dispatch. **No
test assertion reads B's `status`/`cert_status_trace`/`dadp_trace`**, so no test value moves on
either patch. The SUMMARY must still record this as an explained move (old ratio 0.233, new
1.165, the 1.12.7 values above). Nothing else flips on either patch.

**Regression point (old accepts, new refuses)** [VERIFIED on both patches]. Use `MPCFixtures`'
high-PV feeder at `pv_scale = 1.2` (exact under the default `ConvexBranchFlow()`: baseline old
0.00226 / new 0.0111), `H = MPCFixtures.H = 3`, `terminal_soc = false`, `λ₀ = mpc_lambda0()`.
Solve, read `l0 = value(o.ctx.pf_vars.l[2, 1])` (branch 2, the light interior branch 2→3), add
`@constraint(o.model, o.ctx.pf_vars.l[2, 1] >= l0 + 5e-7)`, re-solve with `solve_mpc_window!(o)`,
then call `_mpc_certify_and_price(feeder, aggs, o, λ₀, 1; measured_state = ms, fe = (; pv_factor = 1.0, demand_factor = 1.0))`.

| δ | old ratio (`hybrid_ratios(ctx; atol=1e-6)` max) | new ratio | current code | fixed code |
|---|---|---|---|---|
| 3e-7 | 0.3008 (1.12.7: 0.3007) | 1.4804 (1.4798) | `:certified_convex_dual` | `:certified_convex_dual_restricted` |
| **5e-7 (recommended)** | **0.4993 (0.4992)** | **2.4571 (2.4566)** | `:certified_convex_dual` | `:certified_convex_dual_restricted` |
| 7e-7 | 0.7024 | 3.4562 (3.4560) | `:certified_convex_dual` | `:certified_convex_dual_restricted` |

The worst row is b=2, t=1, gap ≈ 5.01e-7, `atol_b = 2e-7` (interior branch: `ε·ref_b` is tiny,
so τ dominates). δ = 5e-7 gives about 2× margin below 1 on the old side and about 2.5× above 1
on the new side, the same margins as test_exactness.jl's synthetic item. **Do not use
`MPCFixtures.mpc_feeder()`** (the near-lossless 2-bus window) as a "certifies at tier 1" control.
Its *unperturbed* solve already measures old 0.469 / new 2.306, so it escalates under the hybrid
floor. No test currently certifies through it (test_mpc_terminal / test_mpc_window never call the
certify path).

### Finding 2 — orphan ADMM timeout test (blocker 2)

- File: plain script, 3 `@testset` blocks, 19 `@test`s, ends with `println(...)`. TestItemRunner
  only extracts `@testitem`/`@testmodule`/`@testsnippet`, so top-level code in the file is ignored.
  The converted file must put everything inside items (same as `test_benchmark_ieee8500.jl`, which
  stays a manual script).
- **Runtime (1.12.5, measured):** whole script cold 47.2 s (testset), 56.8 s wall with load; warm
  re-run 11.7 s. Per part (fresh process / warm): Test 1 `maxiter=1` throws `ConvergenceError` in
  31.6 s cold (all of it first-solve compile) / 0.27 s warm. Test 2 `time_limit_s=1e-9` →
  `:budget_exceeded` after `iters=1` in 0.95 / 0.28 s. Test 3 full run → `:converged` in 103 iters,
  12.55 / 12.12 s. Max RSS 1.24 GB.
- **Tag decision.** Phase 37's measured rule (37-TIMINGS.md) is ":slow iff file total ≥ 30 s AND
  item ≥ 5 s in a full instrumented run". In a full run the compile is shared with earlier ADMM
  items in the same worker, so the file is about 13 s → **fast** by that rule. Measured in
  isolation (filtered runner, cold) it is about 47 s. Recommended: two items. (a)
  "`:budget_exceeded` + the maxiter cap still throws" (Tests 1+2, tags `[:admm]`, fast, about 0.6 s
  warm). (b) "unbudgeted run converges with `:converged` and all fields populated" (Test 3, about
  12 s warm, fast by the Phase 37 rule). Re-measure both in the gate's verbose suite run
  (`TSODSO_TEST_VERBOSE=1`) and tag `:slow` only if the in-suite time is ≥ 30 s. Tighten
  `@test_throws Exception` to `@test_throws ConvergenceError` (measured type), which gives
  Phase 34 typed-error coverage.
- **Coverage overlap:** `:converged` is also asserted in test_admm_phases.jl:123 and
  test_admm_meshed.jl:53/128, and the maxiter cap in test_admm.jl:160. **`:budget_exceeded` has no
  other test** (test_benchmark_ieee8500.jl:180 is manual-only).
- **Counts** (baseline measured now: `count-sets: all=511 fast=474 slow=37 files=98 canary=1 outside=0`):
  2 fast items → all=513 fast=476 slow=37 files=99. 1 fast item → 512/475/37/99. If (b) is
  `:slow` → 513/475/38/99. **Nothing in the repo hard-codes 511/474/37** (grep of
  test/, scripts/, .github/, docs/src). `check_tally` only checks consistency (fast+slow==all,
  outside==0, canary not slow, strict: slow>0 and fast>0), so no runner code changes are needed.
  `expected_broken.txt` is unaffected (no Broken/skip in this file).
- Fixture setup: `ieee13_modified()`, `generate_profiles(; seed=20260718, T=24)`,
  `TSODSO.build_population(:default, feeder, :ieee13, profiles, 20260718)`, `ConvexBranchFlow()`,
  `TSODSO.build_price(:mem, 24, nothing)`, ρ = 100. Repeat these six lines inline in each item (no
  new `@testmodule`, so `check_setup_names.py` needs nothing new). Use plain locals, not `const`,
  and no `for`/`try` reassignment of outer names at item top level (memory: testitem-try-scoping-trap).
- Remove the header's "Deliberately NOT a TestItemRunner `@testitem`" paragraph and the "Run directly"
  line.

### Finding 3 — OOS stochastic gate (W6)

**Call sites:** `solve_stochastic_oos_step!` is called only by `_stoch_solve_held_out!`
(`run_stochastic.jl:62-79`) in src, and directly by test_stochastic_oos_harness.jl (lines 80, 122,
129, 188, 241) and, through `_stoch_solve_held_out!`, test_run_stochastic.jl:59-100.
Scenario-level consumers of `run_stochastic`: test_run_stochastic (same-seed, mask, golden
`welfare_gap ≈ -0.018591711034105174 rtol=1e-4`), test_status_policy:111, test_strategies
(common shape :slow, fallback :slow, dispatch uniformity, run_and_store round-trip),
docs/literate/stochastic_pv_demand.jl, scripts/compare_default_stochastic.jl (seed 42,
unmeasured), and the writeup `compare_default_stochastic.typ` (cites gap -0.0360, 0/10 infeasible).

**MEASURED hybrid max ratio per OOS solve (default harness optimizer, `tol_gap=1e-8`)** [VERIFIED: scratch `p38/oos_measure.jl`]:

| Fixture | 1.12.5 per-solve ratios (refused) | 1.12.7 | Notes |
|---|---|---|---|
| Golden `T=9, Stochastic(S=3, H_oos=5)` (also default `Stochastic()` T=9) | 0.236, 0.290, 0.184, 0.118, 0.366 (0) | max 0.350 (0) | `welfare_gap` 1.12.5 = -0.018591711034105174; 1.12.7 = -0.018591674331901231 |
| Docs `T=9, S=5, p=[.05,.15,.30,.30,.20], H_oos=10` | 0.86, 0.68, 0.59, **1.31**, 0.89, **1.02**, **1.14**, 0.29, **1.63**, **1.07** (**5/10**) | 0.85, 0.86, 0.58, **1.94**, **1.08**, 0.98, 0.72, 0.67, 0.84, 0.68 (**2/10**) | `welfare_gap` 0.016867421597680732 (1.12.5) |
| harness build-once (stoch_feeder, 3 pin cycles) | **1.13**, **10.57**, 0.65 | same | near-lossless 2-bus, `allow_export=false` harness default |
| harness pin-binding (2 solves) | **51.2**, **50.4** (old flat: 10.4, 10.2) | same | old gate would also refuse |
| harness FourQuadBESS | 0.37 | same | |
| harness FourQuadBESS q pin | **1.49** | same | |
| run_stochastic infeasible→recover (2nd solve) | **7.29** (old 1.49) | same | first solve is INFEASIBLE (unchanged) |

**Tolerance ladder on the docs scenario (1.12.5):** `tol_gap` 1e-8 → 5 refused; 2e-9 → 5; 1e-9 → 6
(plus one `ALMOST_OPTIMAL` retry); 5e-10 → 7; 2e-10 → 7; 1e-10 → 8. Adding `tol_feas = 1e-9` leaves
the ratios unchanged; `tol_feas ≤ 1e-10` exhausts the retry ladder (`SolveFailedError`). With
`tol_gap = 5e-10` every harness unit fixture becomes exact (max 0.496), and the golden stays
inside its pin (-0.018590973661162025, rel. diff 4.0e-5 < rtol 1e-4). **Diagnosis** (refused docs
rows): `l·v < P²+Q²`, i.e. cone *violation* rather than slack, of 2.05–3.31e-7 on lightly loaded
lateral branches (|cone| 1.6e-6–2.5e-5, relative 1.3–13.7%), at nonzero local prices
(4.7–6.7, close to λ₀). This is a solver-accuracy floor on the pinned-dispatch problem, about
1–3× τ_solver. It is not a zero-price degeneracy and is not fixable by tolerance. [ASSUMED
mechanism: degenerate/non-strictly-complementary pin equalities `p_ch == pin` at bound values
limit IPM accuracy; not verified.]

**Recommendation (planner decides):**
- In `solve_stochastic_oos_step!`: after `solve_with_retry!`, `if has_branch_current(h.ctx)` run
  the shared check and on `maxratio > 1` **throw** `CertificateError(...; kind = :socp_exact)`.
  Keep the `Model` return type. This keeps the low-level function policy-consistent (status_policy
  §1: certificate refusals throw; in-sample already throws via `build_stochastic_welfare`).
  Store `h.ctx.meta[:socp_maxgap]`/`[:socp_maxratio]` for introspection.
- In `_stoch_solve_held_out!`: add `catch e isa CertificateError && e.kind === :socp_exact` →
  `@warn` and return the welfare with an `inexact` flag. Do not abort the loop. Return a 3-tuple
  `(welfare, infeasible, inexact)`. Existing 2-name destructuring in test_run_stochastic.jl:85/91
  still works in Julia.
- `_run_stochastic`: add `oos.inexact_h::Vector{Bool}` (and optionally `oos.socp_maxratio_h`, NaN
  for infeasible). Status vocabulary gets one new value, e.g. `:oos_inexact_skipped` (precedence
  over `:oos_infeasible_skipped`; the masks carry full detail). Update `STATUS_VOCABULARY`
  (`src/core/errors.jl:117-123`), the test pin `test/test_status_policy.jl:17`, `_stochastic_status`,
  the `run_stochastic` docstring (`run_stochastic.jl:320-332` and :90-145), status_policy.md §1
  (RETURN list), §3 ("Meaning of …") and the `throws` dict row (`:run_stochastic` should also list
  `CertificateError (in-sample)`; it is missing today even though `build_stochastic_welfare`
  throws it).
- **Why not throw out of `run_stochastic`:** the docs build would fail on 1.12.5 (5/10) and 1.12.7
  (2/10). At about 15–20% refusal per draw on IEEE-13 T=9, any `H_oos = 10` run would usually throw.
- **Direct harness tests** (test_stochastic_oos_harness.jl: build-once, pin-binding, FourQuadBESS-q;
  test_run_stochastic.jl recover step) will throw at default tolerance with throw-in-step. Fix them
  by passing `optimizer = select_optimizer(TSODSO.SOCP(); tol_gap_abs = 5e-10, tol_gap_rel = 5e-10)`
  to `build_stochastic_oos_harness`. Measured: all ≤ 0.496, the same tolerance and rationale as the
  in-sample builder (`stochastic_welfare.jl:166-186`). Alternatively assert the throw where the
  test's point is mechanics. Do **not** change the harness default optimizer: that moves the golden
  slightly and makes the docs scenario worse.
- **Downstream fields that can change:** only when a draw is inexact. Golden fixture on both
  patches: nothing changes (all exact), so the `welfare_gap` golden, `realized_welfare`,
  `infeasible_h` and `status === :solved` stay put. Docs page and compare script: `status`,
  `inexact_h`, and (only under the exclusion variant, see Open Question 2) `realized_welfare`/`welfare_gap`
  and the "feasible" scatter. Page prose must report the count live, never hard-code it, since it
  differs by patch (5 vs 2). `store.jl` `:welfare_gap` is unchanged in shape.

### Finding 4 — W5 allow_export × ADMM

- **Where:** the `Scenario` inner constructor (`src/experiments/Scenario.jl:120-214`), right after
  the `supports_pf` block (194-203). This catches the keyword constructor (`Scenario(;...)`,
  `strategy = :admm` legacy and `ADMM()` struct), `with_strategy` (so `TSODSO.run(ADMM(), s)` with
  `s.allow_export == false` throws before any materialization) and `run_sweep` (builds all
  Scenarios first).
- **Existing text** (`src/admm/solve_admm.jl:296-301`):
  `"solve_admm requires allow_export=true (the free-sign priced frontier is the SOC-exactness enabler; import-only is not supported)"`.
  Suggested Scenario message, consistent with it:
  `"Scenario: strategy ADMM requires allow_export = true (the free-sign priced frontier is the SOC-exactness enabler; import-only is not supported by solve_admm)"`.
  Keep the `solve_admm` guard (direct callers).
- **Tests touching it:** none construct ADMM + `allow_export=false` today. test_experiments.jl:343
  builds `Scenario(; base..., allow_export = false)` with the *default Centralized* strategy, which
  stays valid. Add assertions to test_strategies.jl (or test_scenario_pf.jl "pf construction
  guards"): `@test_throws ArgumentError Scenario(name="x", strategy=ADMM(), allow_export=false)`,
  the legacy `strategy = :admm` form, `TSODSO.run(ADMM(), Scenario(name="x", allow_export=false))`,
  and that `Centralized/MPC/Stochastic` with `allow_export=false` still construct. Fast, no solve.
- Update the Scenario docstring "Construction errors" list (`Scenario.jl:98-102`) and optionally
  `run_sweep`'s docstring.

### Finding 5 — W4 store.jl

- `result_to_dict` docstring (`store.jl:170-181`) claims "Only primitives/arrays are stored … so the
  JLD2 loads without TSODSO types". Line 191 stores `res.reactive_consensus_mode` (`ReactiveMode.T`
  for ADMM, `missing` otherwise). **Measured:** without TSODSO, `wload` returns
  `JLD2.ReconstructedPrimitive{:T, UInt32}` (`Reconstruct@T(2)`) plus a warning; with TSODSO it
  returns the enum (`== ReactiveMode.LIVE` is true). So the docstring is false for ADMM artifacts.
- **No in-repo reader** of the stored `reactive_consensus_mode`: `collate_summary`'s `keep`
  list excludes it, and the tests only read the in-memory `ScenarioResult` property.
- **Recommendation:** store `Symbol(mode)` (`:OFF/:CERTIFIED/:LIVE`; `Symbol(ReactiveMode.LIVE) === :LIVE`
  measured) and keep `missing` for non-ADMM. The docstring then stays true, matching `:strategy`/`:pf`
  (already Symbols) and the `is_prim` contract test_strategies.jl:316-361 enforces for MPC/Stochastic.
  Old files still load (enum with TSODSO, reconstructed without). Update status_policy.md §7
  "Stored simulation provenance" accordingly. Cheap fast test with no solve: build a
  `ScenarioResult(s, 0.0, zeros(1,1), 0.0, 0.0, ADMMDetails(1, 0.0, 0.0, ReactiveMode.LIVE))`,
  assert `TSODSO.result_to_dict(r)[:reactive_consensus_mode] === :LIVE`, then
  `wsave`/`wload` in `mktempdir()` and check the value `isa Symbol`. Alternative (minimal): fix the
  docstring only and say `reactive_consensus_mode` is the one non-primitive and loads as a
  reconstructed type without TSODSO.
- Also stale in the same area: `sweep.jl` `collate_summary` docstring "result_to_dict persists
  `struct2dict(s)`" (optional fix).

### Finding 6 — W1 stale passages and correct facts

| Location | Stale text | Facts to state |
|---|---|---|
| `src/TSODSO.jl:265-269` | "run_mpc is an INDEPENDENT entry point — it is NOT wired through run_scenario's strategy dispatch, reads Scenario's additive mpc_* fields directly" | `mpc_loop.jl` defines `run(st::MPC, s::Scenario)` (line 1681, returns `ScenarioResult` with `MPCDetails`) and the thin wrapper `run_mpc(s)` (1667, raw NamedTuple). `run_scenario(s) = run(s.strategy, s)` (`run.jl:161`) therefore reaches it. Knobs live on `s.strategy::MPC` (`H, step, terminal_soc, forecast_error`). It loads after `run.jl`/`store.jl`/`sweep.jl` because it extends `run` and builds `ScenarioResult` |
| `src/TSODSO.jl:272-277` | same claims for run_stochastic, "additive stoch_* fields" | `run(st::Stochastic, s)` (`run_stochastic.jl:346`) and `run_stochastic(s)` (333). Knobs on `s.strategy::Stochastic` (`S, probabilities, H_oos`) |
| `docs/literate/mpc_rolling_horizon.jl:24-31` | "exactly ONE entry point signature `run_mpc(s::Scenario)` (an 'independent sibling orchestrator' — it is NOT wired through run_scenario's …)" | Two equivalent entry points: `TSODSO.run(MPC(...), s)` / `run_scenario(s)` (ScenarioResult) and `run_mpc(s)` (full NamedTuple incl. trace). Neither accepts a bare feeder/pf/aggregators tuple, which is why the page builds a Scenario |
| `docs/literate/stochastic_pv_demand.jl:21-25` | same | `TSODSO.run(Stochastic(...), s)` / `run_stochastic(s)` |
| FRAMEWORK_GUIDE.html 593-600, 3606-3648 | "deliberately separate entry points … not wired … byte-identical" | same facts (see W2 table) |

`docs/literate/experiments.jl:363-365` already states the current dispatch. Keep the edits
formatter-clean (docs/ is in the format scope).

### Finding 7 — W2 FRAMEWORK_GUIDE.html sweep

**Provenance:** hand-written standalone HTML. No generator meta tag, and no Quarto/markdown source
in the repo. Added in a0fc4bc (2026-08-11, v2.x era) and touched once in fbc1e35 (Phase 28 numbers).
3775 lines; 16 base64 `data:` image URIs make up 2,823,220 bytes. With them stripped, the text is
219,498 bytes and the line numbers are identical (the URIs sit inside single lines). 9 `<pre>`
blocks, 482 `<code>` spans. The guide is not in the scope of `check_planning_ids.py`,
`check_script_api.jl` or the docs build. Line numbers below are original-file lines.

**A. Code blocks (`<pre>`)** — `check_script_api.jl` on the extracted blocks (scratch, absolute
path, `using TSODSO; using JuMP` prelude) reports 3 findings:

| Line | Stale | Fix |
|---|---|---|
| 575 | `Model(select_optimizer(SOCP()))`; comment lists `LP/MILP/QP/SOCP/NLP` | `TSODSO.SOCP()` (or `using TSODSO: SOCP`); problem classes are public, not exported |
| 3430 | `Scenario(name="demo", feeder=:ieee13, strategy=:centralized, seed=1, T=24)` | `strategy = Centralized()` (Symbol still accepted as legacy, but this is the Phase 32 API) |
| 3472-3476 | `aggs = build_population(..., sub_seed(...))`: `...` is a parse error; `build_population`/`sub_seed` unexported | `TSODSO.build_population(s.population, feeder, s.feeder, profiles, TSODSO.sub_seed(s.seed, :population))`. The `sub_seed` definition matches `materialize.jl:24` |
| 3504 | `strategy = :centralized`, `run_scenario(s)` | `Centralized()`; optionally `TSODSO.run(s.strategy, s)` |
| 3530 | `strategy = :admm` | `ADMM()`. `res_a.iters/final_r/final_s` still valid (forwarded properties) |
| 875 | checker flags `T` | false positive (fragment's free loop bound); add `T = 24; nB = …` to the scratch prelude |
| 536, 3554, 3576 | — | current (`contribute!`, `run_and_store`, `scenario_filename`, `run_sweep`, `collate_summary` exported; sweep `:strategy => [:centralized, :admm]` matches test_experiments usage) |

**B. Unexported names written unqualified in `<code>` spans** (export list measured:
`Base.isexported` gives 91 = 90 + module; 91 more are public-only): reactive_factor (1379, 1475),
extract_reactive_dlmp (1741, 1822), set_rho! (2167), **converged (2258; internal, not even
public)**, ac_dual_fallback_price (2403), max_jump/mean_jump (2452), build_mpc_window/MpcWindow
(2460), build_stochastic_welfare (2660), StochasticOosHarness (2662), build_planning_oracle (2950),
add_optimality_cut! (3020), solve_follower! (3066), build_master (3076), build_follower (3164),
write_back! (3264, 3383), **is_converged (3298: "one exported is_converged method" is false)**,
run_nash_probe (3308, 3386, 3404, 3742), PlanningOracle (3372), FollowerLP (3375), BendersMaster
(3378), activate_distributor! (3383), build_feeder/build_price/build_population/sub_seed
(3465-3467, 3639-3640). False positives: `run` at 637/3640 (file name `run.jl`),
`_mpc_certify_and_price` (2459, underscore internal named as a source pointer).

**C. Removed reactive forms:** 2088 heading "Step 7 — the reactive mirror (Phase 19,
`reactive_consensus = :live`)" → `ReactiveMode.LIVE`, drop "Phase 19". 2764
`solve_admm(...; reactive_consensus = :live)` → `reactive_consensus = ReactiveMode.LIVE`. 2259
"the OFF / CERTIFIED / LIVE three-state reactive mode and its normalization" → "the `ReactiveMode`
module (`ReactiveMode.OFF/CERTIFIED/LIVE`, type `ReactiveMode.T`)". No `objective_hook`,
`horizon_state`, `operational_oracle`, `z` kwarg, `normalize_reactive_mode` or `.loss/.voltage`
accessor appears.

**D. DLMP naming** (fields now `energy, cone, drop, congestion, reactive, total`; `NamedTuple(d)`
order `(energy, cone, congestion, drop, reactive, total)` [VERIFIED: src/pricing/dlmp.jl:241-263]):
504 "(energy / loss / congestion / voltage)"; 1689/1691 LaTeX underbrace labels `loss (3.39)` /
`voltage (3.33/3.43)`; 1699 "Loss —", 1706 "Voltage —"; 1714-1719 "loss is not the leftover … energy+loss+congestion+voltage … Reaching the returned NamedTuple" (it returns a
`DlmpDecomposition` struct now); 1730 "marginal-loss component". Keep the physics words
("marginal-loss") but name the fields `cone`/`drop`. Re-check the four-term formula against
`decompose_dlmp`'s docstring, since the receiving-end limit (3.37, `:smax_rev`) now also feeds
congestion [ASSUMED; verify in dlmp.jl].

**E. Scenario/strategy API (Phase 32):** 593-600 ("selected by one field … separate entry points
… byte-identical"); 2375 `mpc_terminal_soc = false` → `MPC(terminal_soc = false)`; 3422-3439
("primitives only … strategy selector (:centralized or :admm), the ADMM knobs … one flat schema,
and additive mpc_* and stoch_* blocks") → `strategy::AbstractStrategy` struct holding its own knobs
(Scenario is no longer primitives-only); 3445-3448 (ρ ≤ 0 is validated by `ADMM(...)`;
probabilities by `Stochastic(...)`); 3464 "run_scenario first materializes" (now
`TSODSO.run(strategy, s)`; `run_scenario` is the wrapper); 3606-3634 (mpc_*/stoch_* fields, "no-ops
… changed the savename string"); 3644, 3648 "independent entry points".

**F. Module/exports/typed errors:** 606-613 ("src/TSODSO.jl exports nothing … a comment per file
recording which plan owns it … Each seam file declares its own exports"). TSODSO.jl now also
declares the `@compat public` advanced API, and the plan-ownership comments were scrubbed. Say 90
exported names and public names qualified as `TSODSO.x`. Typed errors/status: no stale statement
found. Optional improvement: 2084 "solve_admm throws loudly" → `ConvergenceError`; mention
`time_limit_s`/`:budget_exceeded`. 3299 "Exhausting max_sweeps raises loudly" → `ConvergenceError`.
Fixture/tag names (`PhaseNFixtures`, `:phaseN`, `fixtures_phaseN`) and `_FIX08` constants: **none
found.**

**G. Planning identifiers** (`planning_id_rules.RULES` over tag-stripped text, 19 hits): 453-455
(`.planning/PROJECT.md`, `.planning/research/THEORY-*.md`; point to README/docs instead), 600,
3590, 3611 (`byte-identical` → "bit-for-bit identical"), 1039 (`EXACT-04` in a figure caption),
2012/2183/2267 (`PF-04`), 2081-2082 (`Phase-6`, `Phase 7`), 2088/2763 (`Phase 19`), 2192
(`ADMM-04`), 3731-3734 (`Phase 28 code-review restatement, CR-01; … pre-Phase-26/27 …`, `Phase 28
retired`). Also `INT-STRETCH` at 3342 (not matched by the rules, but a planning tag).

**H. Semantic contradictions with v3.0/v4.0 code** (not API names; see Open Question 1):
792-793 ("reverse-direction limit (3.37) is not implemented" — implemented in Phase 26 as
`:smax_rev`); 918-947 (copy eq. 3.43 in thesis-literal `+rℓ` form with the "−2(r²+x²)ℓ" argument;
the default is now Gan–Low `P̂ = P − r·l`, and `thesis_literal = true` is the opt-in restriction
[VERIFIED: ConvexBranchFlow.jl:25-36, 82-86]); 963-969 (gate defaults `atol 1e-6` → hybrid
`atol_b = max(τ_solver=2e-7, ε·ref_b)`); 2366, 2378-2379 (terminal pin is `soc[H+1]`; the `H ≥ 2`
guard was removed [VERIFIED: mpc_window.jl builder doc step 1]); 2393-2395 (Tier 1 "inline … atol
1e-6"; rewrite after blocker 1); 2347, 2419-2424 ("settlement is forecast-consistent, not
truth-settled … deferred"; AC truth settlement is now in place); 3184-3186, 3338-3342, 3715-3718,
3763 ("continuous-only, no binary/integer variable anywhere in src/planning/"; integer planning
exists since v3.0, e.g. `BendersMasterInteger`, `build_master_integer`); 629 and 3715 ("~2,800-test
suite" → about 32,200 assertions in 511 `@testitem`s); 2571-2594 (OOS: add the new exactness check
once W6 lands).

**Tooling recommendation:**
1. A scratch Python editor (outside the repo) that reads the raw HTML and applies an ordered list
   of `(old, new, expected_count)` replacements, aborting without writing if any count differs.
   Compare the SHA-256 of all 16 `data:` URIs before and after (must match) and check that
   `html.parser` tag-balance counts are unchanged.
2. Static verification after editing (all scratch-only): (a) re-run the scan (categories B–G must
   be empty apart from an explicit false-positive allowlist); (b) planning-ID rules over
   tag-stripped text → 0 hits; (c) extract the `<pre>` blocks to `$SCRATCH/guide_blocks/*.jl` with
   a `using TSODSO; using JuMP; T = 24` prelude, then
   `julia +release --project=. --startup-file=no .github/scripts/check_script_api.jl $SCRATCH/guide_blocks`
   → `0 finding(s)`. Snippets are never executed.
3. Optional (needs user agreement, see Open Question 3): add `docs/writeups/*.html` to
   `check_planning_ids.py` scope with data-URI stripping. Not required by the success criteria.
4. `docs/writeups/README.md`: add a line/row for `FRAMEWORK_GUIDE.html` (standalone, self-contained
   HTML with embedded figures, hand-maintained, tracked as-is, not generated). The README currently
   says only the `.typ` sources are tracked.

### Finding 8 — W7 check_setup_names.py

Passes now: `21 testmodules, 220 setup uses, 0 unresolved`, exit 0. Has `--selftest`
(`selftest OK: 4 case(s)`). It finds the repo root via `git rev-parse` of the script's own
directory, so it works in a CI checkout. Add it to the `format` job in `.github/workflows/CI.yml`
after "Check for planning identifiers" (before or after the scripts-index steps), with the same
`if: ${{ !cancelled() }}` convention:
```yaml
      - name: Check @testitem setup names resolve
        if: ${{ !cancelled() }}
        shell: bash
        run: |
          python3 .github/scripts/check_setup_names.py --selftest
          python3 .github/scripts/check_setup_names.py
```

## Common Pitfalls

### Pitfall 1: happy-path MPC fixture sits at 0.938 under the hybrid floor on 1.12.5
**What goes wrong:** "mpc_loop: end-to-end … never escalates" asserts every step is
`:certified_convex_dual`. On 1.12.5 its worst resolve is 0.938, a 6.6% margin.
**Why:** IEEE-13 light branches have gaps of about 1.9e-7 against `τ_solver = 2e-7`.
**How to avoid:** measure on both patches in the gate (done here: 0.938 / 0.323). Record the
margin in the SUMMARY. Do not raise τ. If a future patch tips it, that is an explained move.
**Warning signs:** a `run_mpc: per-resolve cone check failed` warning in a happy-path log.

### Pitfall 2: OOS gate as a throw out of run_stochastic breaks the docs build
See Finding 3: 5/10 refused on 1.12.5 and 2/10 on 1.12.7 for the docs scenario.

### Pitfall 3: direct-harness tests trip at default tolerance
With a throwing step, these throw: test_stochastic_oos_harness build-once (cycles 1–2),
pin-binding, FourQuadBESS-q, and the recovery solve in test_run_stochastic (the latter is caught
by `_stoch_solve_held_out!` if it gets the new catch). Pass a `5e-10` optimizer in those tests
(measured fix).

### Pitfall 4: planning-ID guard on new prose
New comments, test names and docstrings must avoid `FIX-08`, `ARCH-08`, `Phase 38`, `blocker`,
`wave`, `byte-identical`, `code review`, `W5`/`W6` and similar. Run
`python3 .github/scripts/check_planning_ids.py` before committing.

### Pitfall 5: formatter content loss
JuliaFormatter's `format_docstrings` can drop `|`-continued inline code spans (CI.yml comment,
commit a8f7659). Run `format210.jl` on touched files, then `python3 .github/scripts/check_content_loss.py HEAD`.

### Pitfall 6: concurrent Julia / stale suite logs
Never run two Julia processes at once. Check the log start time against commits before
believing a delta (memory: background-suite-orphan-race). Full suite takes about 30–60 min. Use
`suite_detached.sh`, not a foreground tool call (the 10 min tool timeout kills it).

### Pitfall 7: TestItemRunner scoping
No top-level `try` or loop reassignment in the new `@testitem`s. Wrap them in functions or `let`.

### Pitfall 8: JET ratchet
`scripts/jet_baseline.txt` (36 lines) has no entries for mpc_loop/stochastic/Scenario/store/exactness,
so any new inference report in those files is NEW and fails. Keep the helper type-stable (it
returns a concrete NamedTuple of Float64).

## Code Examples

### Shared non-throwing gate kernel (exactness.jl) — recommended
```julia
# Source: refactor of src/models/exactness.jl:226-294 (assert_socp_exact! loop), same order/ops.
function _socp_cone_check(
    ctx::ModelContext;
    rtol::Real = 1e-4,
    atol::Union{Nothing, Real} = nothing,
    ε::Real = MEASURED_REL_TOL_EXACT,
    τ_solver::Real = TAU_SOLVER_EXACT,
)
    pv = _require_pf_vars(ctx)
    feeder = _require_feeder(ctx)
    T = _require_T(ctx)
    head_b = _socp_head_branch(feeder)
    head_b === nothing && throw(ArgumentError("…same message as assert_socp_exact!…"))
    maxgap = 0.0
    maxratio = 0.0
    for (b, br) in enumerate(feeder.branches), t in 1:T
        row = _cone_row(pv, br, b, t, head_b, rtol, atol, ε, τ_solver)
        maxgap = max(maxgap, row.gap)
        maxratio = max(maxratio, row.ratio)
    end
    return (; maxgap, maxratio)
end
# assert_socp_exact!(ctx; kw...) = (c = _socp_cone_check(ctx; kw...);
#     c.maxratio <= 1 || throw(CertificateError(<unchanged message>; kind = :socp_exact)); c.maxgap)
```

### MPC regression test skeleton
```julia
@testitem "mpc_loop: first-tier certificate applies the hybrid exactness floor — a light-branch slack the flat 1e-6 floor accepted now escalates" tags =
    [:mpc_loop] setup = [MPCFixtures] begin
    using TSODSO, Test
    using TSODSO: build_mpc_window, solve_mpc_window!
    using JuMP: @constraint, value, set_parameter_value, set_objective_coefficient
    feeder = MPCFixtures.mpc_high_pv_feeder()
    aggs = MPCFixtures.build_mpc_high_pv_aggregators(feeder; pv_scale = 1.2)
    H = MPCFixtures.H
    λ₀ = MPCFixtures.mpc_lambda0()
    o = build_mpc_window(feeder, ConvexBranchFlow(), aggs; H = H, terminal_soc = false)
    # ... slide Ppv/Tout/Pdc slices 1:H and λ₀ exactly as the existing escalation items do ...
    solve_mpc_window!(o)
    l0 = value(o.ctx.pf_vars.l[2, 1])
    @constraint(o.model, o.ctx.pf_vars.l[2, 1] >= l0 + 5e-7)   # inject a 5e-7 cone slack
    solve_mpc_window!(o)
    old_max = maximum(r.ratio for r in TSODSO.hybrid_ratios(o.ctx; atol = 1e-6))
    @test old_max <= 1                      # measured 0.499: the flat 1e-6 floor accepts
    r = TSODSO._mpc_certify_and_price(feeder, aggs, o, λ₀, 1; measured_state = ms, fe = fe)
    @test r.cone_maxratio == TSODSO.hybrid_ratios(o.ctx)[1].ratio   # parity with the library
    @test r.cone_maxratio > 1               # measured 2.457
    @test r.cert_status == :certified_convex_dual_restricted        # measured on 1.12.5 and 1.12.7
end
```

### Guide static scan (scratch only; essence of p38/guide_scan.py)
```python
import re, html
raw = open(GUIDE, encoding="utf-8").read()
stripped = re.sub(r"data:[a-z/+]+;base64,[A-Za-z0-9+/=]+", "DATAURI", raw)   # line numbers preserved
spans = [(m.start(), html.unescape(re.sub(r"<[^>]+>", "", m.group(1))))
         for m in re.finditer(r"<code[^>]*>(.*?)</code>", stripped, re.S)]
# flag: TSODSO names (names(TSODSO; all=true)) not Base.isexported and not preceded by "TSODSO."
#       reactive_consensus\s*=\s*(:\w+|true|false) ; (?<!ReactiveMode\.)\b(OFF|LIVE|CERTIFIED)\b
#       \.(loss|voltage)\b ; strategy\s*=\s*:\w+ ; mpc_\w+ / stoch_\w+ ; planning_id_rules.RULES
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Flat `atol = 1e-6` cone floor | Hybrid `atol_b = max(2e-7, 1e-9·ref_b)` | Phase 27 | MPC tier and OOS step must adopt it (this phase) |
| `strategy::Symbol` + flat knobs | `strategy::AbstractStrategy` struct; `TSODSO.run(st, s)` | Phase 32 | W1, guide section E |
| `ErrorException` throws | `TSODSOError` hierarchy + `STATUS_VOCABULARY` | Phase 34 | W6 status, timeout test `ConvergenceError` |
| 192 exports, bare `OFF/LIVE` | 90 exports + `@compat public`; `ReactiveMode` module | Phase 36 | guide sections B, C |
| `fixtures_phaseN.jl`, `_FIX08` constants | content names, `MEASURED_REL_TOL_EXACT`/`TAU_SOLVER_EXACT` | Phase 36 | none found in the guide |
| Discovery could reach sibling trees | `run_tests(test_dir)` rooted at `test/` | Phase 37 | timeout test can be a `@testitem` |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The OOS cone-violation floor comes from degenerate pin equalities limiting IPM accuracy | Finding 3 | Low. The recommendation does not depend on the mechanism, only on the measured ratios |
| A2 | The DLMP four-term formula in the guide (1686-1692) may need a receiving-end congestion term after Phase 26 | Finding 7 D | Low. Verify against `decompose_dlmp` docstring during the edit |
| A3 | The timeout items will measure < 30 s inside a full verbose suite (compile shared with earlier ADMM items) | Finding 2 | Low. If ≥ 30 s, tag `:slow`; the counts table covers both outcomes |
| A4 | `scripts/compare_default_stochastic.jl` (seed 42) and its Portuguese writeup may show inexact draws under W6 | Finding 3 | Medium. Unmeasured; if inexact draws are excluded from `realized_welfare`, the writeup's cited gap (-0.0360) could change |

## Open Questions (RESOLVED)

All four were resolved by the user decisions recorded in 38-CONTEXT.md "Research Refinements" (2026-10-07).

1. **(RESOLVED) Does W2's "full API sweep" include the semantic v3.0/v4.0 contradictions (Finding 7 H)?**
   - Resolution: yes. USER (W2): the sweep fixes model text too; the ~10 false statements get a short note naming the version that changed them; §5.1 gets a corrective note, not a rewrite (plan 09).
   - What we know: the success criterion says "swept against the current API (every stale usage
     fixed)", and the phase goal says "prose no longer contradicts the code". The H items are not
     API names but are factually false now (3.37, copy direction, gate tolerance, terminal pin,
     settlement, integer planning, test count).
   - Recommendation: fix the one-line factual items directly. For §5.1 (copy derivation), add a
     short corrective note naming the Gan–Low default and the `thesis_literal = true` opt-in rather
     than rewriting the derivation. Confirm scope with the user if the plan grows.
2. **(RESOLVED) W6 variant: exclude inexact held-out draws from `realized_welfare`, or keep them and only flag?**
   - Resolution: USER (W6) chose "Exclude + report": the step throws `CertificateError`, `_stoch_solve_held_out!` records the draw with a new status, and an `inexact_h` mask excludes it (plans 04, 05).
   - Exclude: `welfare_gap` is certified, as CONTEXT intends, and mirrors the infeasible skip. But
     the docs-page numbers then depend on the patch (5 vs 2 excluded), and the compare-script
     writeup may move.
   - Keep and flag: numbers stay stable and status shows the problem, but `welfare_gap` is then not
     "certified".
   - Recommendation: exclude, keep `welfare_h[h]` finite (not NaN) with an `inexact_h` mask, and
     add the new status. The golden fixture is unaffected either way (all exact on both patches).
3. **(RESOLVED) Add the guide to a CI guard?**
   - Resolution: no. Research Refinements: "verified once with scratch checks; no new CI guard over the guide" (plans 08, 09).
   Optional. The data-URI-stripping variant of the planning-ID
   guard is about 10 lines. Recommendation: no new CI guard this phase. Do the one-off scratch
   verification and record it in the SUMMARY.
4. **(RESOLVED) `:slow` measurement context for the timeout items**
   - Resolution: Research Refinements: two fast items under the Phase 37 in-suite rule; counts move by +2 items (plan 06); the gate re-measures in-suite time (plan 10).
   — recommend the Phase 37 rule (in-suite,
   verbose); see A3.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Julia 1.12.5 | gates, measurements | ✓ | `julia +release` 1.12.5 | — |
| Julia 1.12.7 | gate, JET | ✓ | `julia +1.12` 1.12.7 | — |
| Test env (TestItemRunner, JET) | runner, JET | ✓ | via `JULIA_LOAD_PATH="@:$PWD/test:@stdlib"` | — |
| docs env (CairoMakie, Documenter) | docs build | ✓ (docs/Manifest julia 1.12.5) | — | — |
| python3 | guards, guide scripts | ✓ | system | — |
| JuliaFormatter 2.10 | format gate | fetched by format210.jl into a temp env (needs network/registry) | 2.10.x | CI format job |

**Missing dependencies with no fallback:** none.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Test (stdlib) + TestItemRunner 1.1.5 (`@testitem`, `@testmodule` setups) |
| Config file | `test/runtests.jl` (discovery rooted at `test/`), `test/runner_support.jl`, `test/expected_broken.txt` |
| Quick run command | `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +release --project=. -t2 scripts/run_tests_filtered.jl "$PWD" file:<basename.jl>` |
| Discovery/count check | `... scripts/run_tests_filtered.jl "$PWD" --count-sets --strict` (baseline all=511 fast=474 slow=37 files=98) |
| Full suite command | `.github/scripts/suite_detached.sh p38_1125` (default `julia --project=. -e 'import Pkg; Pkg.test()'`; for 1.12.7 pass `julia +1.12 --project=. -e 'import Pkg; Pkg.test()'`) then `python3 .github/scripts/check_suite_log.py p38_1125 --broken 5` |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| FIX-08 / FIX-10 | MPC tier uses the hybrid floor; old-accepts/new-refuses point escalates; `cone_maxratio` equals `hybrid_ratios` max | unit/integration | `... run_tests_filtered.jl "$PWD" file:test_mpc_loop.jl` | test file ✅, new item ❌ |
| FIX-08 | `assert_socp_exact!` verdicts unchanged after the kernel refactor | unit | `... file:test_exactness.jl,test_admm_exactness_default.jl` | ✅ |
| ARCH-08 / HYG-05 | `solve_admm(...; time_limit_s=1e-9).status == :budget_exceeded`, no price fields; maxiter cap throws `ConvergenceError` | integration | `... file:test_admm_timeout.jl` | file ✅ (plain script → convert) |
| HYG-05 | count-sets consistent, timeout items discovered | infra | `... --count-sets --strict` | ✅ |
| ARCH-02 | `Scenario(strategy=ADMM(), allow_export=false)` → `ArgumentError`; legacy `:admm`; `TSODSO.run(ADMM(), s_noexport)` | unit (no solve) | `... file:test_strategies.jl` | ❌ new assertions |
| ARCH-08 | OOS inexact draw → skip-and-report flag + status; golden stays `:solved`; vocabulary pin updated | unit + integration | `... file:test_run_stochastic.jl,test_stochastic_oos_harness.jl,test_status_policy.jl` | ✅ (edits) |
| W4 (store) | `result_to_dict` stores `:LIVE` Symbol; wload gives a Symbol | unit (no solve) | `... file:test_experiments.jl` (or test_strategies.jl) | ❌ new item |
| W1/W2 prose | docs build green; literate pages execute | docs | `julia --project=docs docs/make.jl` (via suite_detached.sh `--mode docs`) | ✅ |
| W2 guide | 0 static findings | static (scratch) | `julia +release --project=. --startup-file=no .github/scripts/check_script_api.jl $SCRATCH/guide_blocks` + scratch scan | n/a (scratch) |
| W7 | setup names resolve; selftest | static | `python3 .github/scripts/check_setup_names.py --selftest && python3 .github/scripts/check_setup_names.py` | ✅ |
| Gates | planning IDs, scripts index, script API, content loss, JET | static | `python3 .github/scripts/check_planning_ids.py`; `python3 .github/scripts/check_scripts_index.py`; `julia --project=. .github/scripts/check_script_api.jl`; `python3 .github/scripts/check_content_loss.py HEAD`; `JULIA_LOAD_PATH="@:$PWD/test:@stdlib" julia +1.12 --project=. -t2 scripts/jet_check.jl` | ✅ |

### Sampling Rate
- **Per task commit:** the filtered-runner command for the touched test file(s), plus `check_planning_ids.py` and `format210.jl` on touched files.
- **Per wave merge:** `--count-sets --strict`; filtered runs of every file touched in the wave.
- **Phase gate:** full suite on 1.12.5 then 1.12.7 (sequential, never concurrent), docs build, JET on 1.12.7, all guards. Canary log lines must show iters = 56 and welfare = -4823.66604824162.

### Wave 0 Gaps
- [ ] New `@testitem` for the MPC regression point and parity (test_mpc_loop.jl).
- [ ] test_admm_timeout.jl converted into `@testitem`(s).
- [ ] W5 assertions (test_strategies.jl or test_scenario_pf.jl).
- [ ] W6 tests: harness-level inexact flag (pin-binding fixture at default tolerance gives a robust ratio of about 51), `_stochastic_status` pure-helper cases, updated vocabulary pin.
- [ ] W4 no-solve round-trip item.
No framework install needed.

## Security Domain

`security_enforcement` absent from config → enabled. Research code with no network surface, auth or secrets.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | no | — |
| V4 Access Control | no | — |
| V5 Input Validation | yes | `Scenario` inner-constructor `ArgumentError` validation (W5 extends it) |
| V6 Cryptography | no | (FNV digest in filenames is explicitly not a security hash) |

### Known Threat Patterns
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Deserializing JLD2 artifacts with custom types | Tampering | W4 Symbol storage reduces type reconstruction. Artifacts are local and gitignored |
| CI step injection | Tampering | New CI step runs a repo-local script with no inputs from PR metadata |

## Sources

### Primary (HIGH confidence) — measured or read in this session
- `src/experiments/mpc_loop.jl` (99, 245-300, 470-520, 780-1001, 1650-1700), `src/models/exactness.jl` (1-460), `src/models/mpc_window.jl` (20-275), `src/core/ModelContext.jl` (50-145)
- `src/models/stochastic_welfare.jl` (40-60, 160-190, 425-445, 486-750), `src/experiments/run_stochastic.jl` (1-350), `src/core/errors.jl:109-125`, `docs/src/status_policy.md`
- `src/experiments/Scenario.jl`, `strategies.jl`, `run.jl`, `store.jl` (80-250), `sweep.jl`, `src/admm/solve_admm.jl:270-305`, `src/TSODSO.jl:255-335`
- `test/test_admm_timeout.jl`, `test/runtests.jl`, `test/runner_support.jl`, `test/expected_broken.txt`, `scripts/run_tests_filtered.jl`, `test/fixtures_mpc.jl`, `test/fixtures_stochastic.jl`, `test/test_mpc_loop.jl`, `test/test_run_stochastic.jl`, `test/test_stochastic_oos_harness.jl`, `test/test_strategies.jl`, `test/test_experiments.jl`, `test/test_exactness.jl`
- `.github/workflows/CI.yml`, `slow.yml`, `.github/scripts/{check_setup_names.py, check_planning_ids.py, planning_id_rules.py, check_script_api.jl, suite_detached.sh, check_suite_log.py, format210.jl}`, `scripts/jet_check.jl`, `scripts/jet_baseline.txt`
- `.planning/phases/36-code-export-cleanup/36-BREAKING-LEDGER.md`, `36-07` commits, `.planning/phases/37-test-infrastructure-repo-hygiene/37-TIMINGS.md`, `37-slow-items.txt`
- Scratch measurement scripts (session scratchpad `p38/`): `mpc_patch.jl`, `mpc_measure.jl`, `mpc_B.jl`, `mpc_regression.jl`, `mpc_highpv.jl`, `oos_measure.jl`, `oos_ladder.jl`, `oos_ladder2.jl`, `oos_diag.jl`, `admm_parts.jl`, `guide_scan.py`, `guide_blocks/`

### Secondary / Tertiary
- None. No web sources were needed. Every claim comes from repo code or session measurement.

## Metadata

**Confidence breakdown:**
- MPC gate and measurements: HIGH (both patches, decision-path instrumented)
- Timeout test conversion and counts: HIGH (measured times; count-sets run)
- OOS gate behaviour: HIGH (measurements); MEDIUM (root-cause mechanism, A1)
- FRAMEWORK_GUIDE inventory: HIGH for the API/planning-ID lists (scripted); MEDIUM for the semantic list (manual reading)

**Research date:** 2026-10-07
**Valid until:** about 2026-11-07, or until the next change to Clarabel/Julia patch or exactness constants.

## Suggested Plan Decomposition (sequential on the main tree; never two Julia processes)

| # | Plan | Files | Depends on |
|---|------|-------|-----------|
| 01 | Shared gate kernel `_socp_cone_check` + `assert_socp_exact!` refactor (no verdict change) | exactness.jl | — |
| 02 | MPC first tier via the kernel; docstring; regression and parity item; stale MPC test/fixture comments; record the 1.12.7 move in the SUMMARY | mpc_loop.jl, test_mpc_loop.jl, fixtures_mpc.jl, (mpc_rolling_horizon.jl:272 wording) | 01 |
| 03 | OOS step gate (throw) + orchestrator skip-and-report + status vocabulary + status_policy.md + docs page prose + test edits (5e-10 optimizer in harness tests) | stochastic_welfare.jl, run_stochastic.jl, errors.jl, status_policy.md, stochastic_pv_demand.jl, test_* | 01 |
| 04 | Timeout test → `@testitem`(s) | test_admm_timeout.jl | — |
| 05 | Scenario ADMM × allow_export validation + tests + docstring | Scenario.jl, test_strategies.jl | — |
| 06 | store.jl reactive mode as Symbol (or docstring-only) + test + status_policy §7 | store.jl, test, status_policy.md | 03 (status_policy.md edits sequential) |
| 07 | W1 prose (TSODSO.jl, two literate pages) | src/TSODSO.jl, docs/literate/* | 03 (same literate file) |
| 08 | W7 CI step | CI.yml | — |
| 09a/b | FRAMEWORK_GUIDE: (a) API + planning-ID + README listing; (b) semantic corrections (if confirmed) | FRAMEWORK_GUIDE.html, docs/writeups/README.md | 02, 03 (guide text describes the new behaviour) |
| 10 | Gate: format210 + content-loss, guards incl. check_setup_names, count-sets --strict, JET 1.12.7, docs build, full suite 1.12.5 then 1.12.7, itemize deltas vs 32224/32219/0/0/5, canary | — | all |

Expected suite delta: added assertions from the new items (MPC regression item about 5, timeout
19 migrated plus 0–1 new, W5 about 5, W4 about 3, W6 about 6–10). Every delta must be itemized
against the baseline.

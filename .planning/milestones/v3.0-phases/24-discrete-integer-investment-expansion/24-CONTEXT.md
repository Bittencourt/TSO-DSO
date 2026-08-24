# Phase 24: Discrete/Integer Investment Expansion - Context

**Gathered:** 2026-08-23
**Status:** Ready for planning

<domain>
## Phase Boundary

The single-distributor planning Benders loop gains genuine **integer investment**: binary-expansion
investment levels in the master, solved as a HiGHS MILP behind the existing `select_optimizer`
factory, converging on genuine Laporte–Louveaux integer optimality cuts, certified on a tiny
instance against an independent oracle, with the PVAL-04 no-binaries guard **scoped rather than
deleted**. Requirements INT-01..04.

Touches only `src/planning/` (plus the PVAL-04 guard test). Single-distributor Stackelberg scope —
the N>1 Nash/diagonalization path is NOT in scope for integrality here.

</domain>

<decisions>
## Implementation Decisions

### Investment Lattice Design (INT-01)
- **D-01:** **Pure binary expansion of `y_max`**, NOT engineering block sizes and NOT an explicit
  level menu. `y_inv = (y_max / 2^K) · Σ_k 2^k b_k`. Integrality is deliberately framed as a
  **solver-behaviour axis, not a physical claim** — the discreteness carries no engineering meaning
  in this phase. Chosen for the clean convergence-to-continuous diff (as K grows the lattice
  refines toward the continuous baseline), which is the correctness lever the roadmap wanted.
- **D-02:** **Endpoint convention: divide by `2^K`** (round step sizes), NOT `2^K − 1`.
  Consequence, accepted with eyes open: all-ones gives `y_max·(1 − 2^-K)`, so **`y_max` itself is
  never attainable** and the continuous diff carries a known `2^-K` boundary bias. This MUST be
  stated explicitly in the fixture docstring and the literate page — it is a documented artifact,
  not a bug to be discovered later.
  **Verified to be harmless on the canonical instance:** the continuous golden optimum is
  `N1_Y_HAND = 0.7` (`test/fixtures_planning.jl:20`), deep in the interior of `[0, 8.0]`, so the
  unreachable endpoint never binds here.
- **D-03:** **Default `K = 4`** → 16 levels, step `y_max/16 = 0.5` for `y_max = 8.0`, reachable set
  `{0, 0.5, 1.0, …, 7.5}`. K is configurable (a parameter change, not a code change), but a
  committed fixture default is pinned so there is something to golden-test against (gate-then-golden
  ordering). K=4 over K=3 because the finer lattice produces a less degenerate cut sequence, which
  is what makes INT-02's re-measured iteration behaviour meaningful.
- **D-04 (derived, load-bearing):** the canonical instance has a **genuine, non-degenerate
  integrality gap** — `0.7` is NOT on the K=4 lattice, and its neighbours are `0.5` and `1.0`. The
  integer optimum therefore must differ from the continuous one. Do NOT "fix" a nonzero gap here;
  a zero gap would be the suspicious outcome.

### Integer Master Seam (INT-01, INT-04)
- **D-05:** A **NEW separate builder** (`build_master_integer` or similar) alongside a **completely
  untouched `build_master`**. NOT a `integer=false` flag on the existing builder. Rationale: the
  continuous v2.0 path stays byte-identical **by construction rather than by argument**, so the
  `PVAL-02..04` goldens are trivially safe to diff against — which is precisely the dependency the
  roadmap names for this phase.
- **D-06:** The **PVAL-04 exemption is a per-builder carve-out, not a conditional one.** The new
  builder's name IS added to `test/test_planning_noninteger.jl`'s registry (it must be — see D-07)
  but appears on an explicit `EXEMPT` list; the unmodified no-binaries assertion still runs over all
  four existing builders. Exemption must be greppable by name.
- **D-07 (constraint discovered in code, not negotiable):** `test/test_planning_noninteger.jl` is
  **not just a registry** — it carries a **source-scan tripwire** asserting the discovered
  `build_*` set *equals* the registry keys (walkdir over `src/planning/`, docstring-aware regex,
  plus an exported-symbol channel). A new builder therefore **cannot be omitted** from the registry
  to dodge the guard; omission fails the tripwire loudly. The exemption must be an explicit
  allowlist inside the item.
- **D-08:** `solve_stackelberg!` reaches the integer master via a **`master = nothing` injection
  kwarg**, mirroring the **existing `follower = nothing` seam** in the same signature. When
  `nothing`, the loop builds `build_master(; master_kwargs..., T = T)` exactly as today
  (`src/planning/benders.jl:185`); when supplied, it uses the caller's prebuilt master. Reuses an
  established seam rather than inventing a parallel one; default path untouched.
  **Note for the planner:** `benders.jl:62` documents an invariant that no `build_*`/`Model(` call
  appears outside the single construction point. Injection moves construction to the caller for the
  integer path — that docstring must be UPDATED to describe the seam, not silently falsified.
- **D-09:** `MILP <: ProblemClass` **already exists** (`src/solver/ProblemClass.jl:31`) and the
  factory already maps it. INT-01's "new/extended `ProblemClass` as needed" most likely needs
  **nothing new** — verify before adding anything.

### Certification Oracle & Tiny Instance (INT-03)
- **D-10:** **Exhaustive enumeration is the PRIMARY certificate**; a BilevelJuMP reduction is a
  **SECONDARY independent confirmation** where mode-compatible, and its unavailability is a
  documented non-blocker, NOT a coverage gap. Enumerate all 16 lattice points, solve the follower at
  each, take the best — exhaustive by construction, no sampling possible.
- **D-11 (corrects an inherited research flag):** STATE.md's Phase 24 flag worried whether
  BilevelJuMP's KKT/SOS1/Fortuny-Amat modes support **any mixed-integer follower**. That concern
  **likely does not apply to this phase**: integrality lives in the **leader** (`y_inv`) while the
  **follower stays continuous**, and integer leader variables sit in the outer MILP where those
  reductions handle them normally. Verify at implementation time, but do not treat the flag as a
  blocker on the original grounds. Precedent: `test/test_planning_goldens.jl:52` already describes
  the N=1 golden as "hand-enumerated/BilevelJuMP-certified".
- **D-12:** Certify on the **existing canonical N=1 toy** — `Phase6Fixtures.two_bus_feeder()` +
  `ToyDeviceFixture.ToyElasticDevice(2, 6.0, 1.0, 10.0)` + single aggregator, `c_y = 0.3`,
  `y_max = 8.0`, `λ₀ = [4.0]`, `T = 1`, at `K = 4`. NOT a new smaller fixture. Reuses
  already-reviewed, stable fixtures and gives a direct diff against the continuous `PVAL-02` golden.

### Cut Policy, Termination & This Phase's Own Certificate (INT-02)
- **D-13:** Termination is a **lattice-gap EXACT criterion**, explicitly NOT the continuous loop's
  inherited `tol = 1e-6` gap tolerance (reusing it would be exactly the "certificate laundering"
  the milestone forbids). Terminate when `UB − LB` falls below the smallest objective separation two
  distinct lattice points can produce — on a finite lattice this is an **optimality proof, not a
  tolerance**.
- **D-14 (open risk, with a decided fallback):** `δ_min` is **NOT simply `c_y · step`** (= 0.15
  here). That bounds only the leader-cost separation; the follower's continuous response to two
  adjacent lattice points can partially offset it, so the true objective separation may be smaller
  — potentially arbitrarily small. A rigorous `δ_min` may require the follower's Lipschitz behaviour
  in `y`. **Decided fallback: the enumeration-backed criterion.** On the certified tiny instance,
  terminate when the incumbent MATCHES the enumerated optimum — exact by construction, no `δ_min`
  needed, and enumeration is already the primary oracle so it is free. **Accepted cost:** this works
  only where enumeration is tractable, so a production criterion for large lattices is an
  **explicitly deferred open item**, not something to be quietly papered over with a tolerance.
- **D-15:** Phase 24's **own new certificates** (beyond INT-03's enumeration agreement) are:
  1. **Per-cut validity assertion** — every LL cut generated during the certified run is checked
     against the enumerated optimum; a valid cut must NEVER cut off the true optimal lattice point.
     This tests the **cut itself**, not merely whether the loop happened to land on the right
     answer, and it directly answers the open "are the cuts valid at this granularity" question.
  2. **Continuous-baseline diff** — assert the theory-required relation to the continuous golden
     (`y = 0.7`): the continuous relaxation objective is a valid bound on the integer objective, and
     the integer solution is one of the lattice neighbours bracketing it. Ties the new regime back
     to the stable v2.0 baseline.
  Explicitly **NOT selected as certificates:** a no-good-count-zero assertion, and a
  finite-termination iteration bound. Do not add them as gates.
- **D-16:** **No-good cuts are allowed, counted, and surfaced.** They remain available as INT-02's
  anti-stall fallback. Every firing is counted and recorded in the run trace/report, and the count
  is reported alongside any result. Convergence is only ever **attributed** to the LL cuts: a run
  that needed no-goods is reported as `:nogood_assisted` rather than presented as clean LL
  convergence. `m > 0` does **not** fail the run — but it must never be invisible.

### Claude's Discretion
- The concrete algebraic form of the LL cut, cut-management//dedup strategy, and where the cut
  bookkeeping lives (`benders.jl` vs a new module) are implementation choices for research/planning.
- MILP solver attribute tuning (HiGHS gap/threads/presolve) is discretionary, provided nothing is
  hard-coded outside `select_optimizer`.
- Trace/report field naming for the no-good bookkeeping (D-16) is discretionary as long as the count
  and the `converged_via` attribution are both present.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & milestone bars
- `.planning/REQUIREMENTS.md` §INT-01..INT-04 (lines 112–128) — the four requirements this phase
  closes, verbatim.
- `.planning/ROADMAP.md` §"Phase 24: Discrete/Integer Investment Expansion" — goal, dependency
  rationale, and the four success criteria.
- `.planning/STATE.md` §Blockers/Concerns — the Phase 24 research flag (see D-11, which partially
  corrects it) and the cross-cutting "own certificate / no certificate laundering" standing bar.

### The continuous baseline this phase must diff against
- `src/planning/master.jl:1221` — `build_master`, the LP master to leave untouched (D-05).
- `src/planning/benders.jl:185` — the single `build_master` construction point the `master =`
  injection seam wraps (D-08).
- `src/planning/benders.jl:62` — the documented no-`build_*`-elsewhere invariant that D-08 requires
  be UPDATED rather than silently falsified.
- `src/planning/benders.jl` — `solve_stackelberg!` signature, including the existing
  `follower = nothing` seam that D-08 mirrors.

### Guard that must be scoped, not deleted (INT-04)
- `test/test_planning_noninteger.jl:25` — the PVAL-04 no-binaries guard: 4-builder registry PLUS the
  source-scan tripwire (walkdir, docstring-aware regex, exported-symbol channel) described in D-07.
- `test/test_planning_nash.jl:317` — the PVAL-04 continuous-only companion check on `run_nash!`.

### Goldens and fixtures for certification (INT-03)
- `test/test_planning_goldens.jl:25` — the N=1 PVAL-02 golden, its gate-then-value assertion
  ordering, and the "hand-enumerated/BilevelJuMP-certified" provenance note at line 52.
- `test/fixtures_planning.jl:20` — `N1_Y_HAND = 0.7`, `N1_Z_HAND = 0.7`, `N1_OBJ_HAND = -0.245`.
- `test/fixtures_phase6.jl` — `two_bus_feeder()`; `ToyDeviceFixture` — `ToyElasticDevice`.

### Solver factory
- `src/solver/ProblemClass.jl:31` — `MILP <: ProblemClass` already exists (D-09).
- `src/solver/factory.jl` — `select_optimizer`; the MILP→HiGHS mapping. Nothing may name a solver
  directly (INFRA-02).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `follower = nothing` injection kwarg on `solve_stackelberg!` — the exact seam shape D-08 reuses
  for `master`.
- `MILP <: ProblemClass` + factory mapping — already present; no new problem class expected (D-09).
- The whole iterate/checkpoint/trace loop in `benders.jl` (`retry.jl`, `checkpoint.jl`, `trace.jl`)
  — the injection approach in D-08 keeps all of it, which is where most prior review-hardening lives.
- Canonical N=1 toy fixtures — reused wholesale for certification (D-12).

### Established Patterns
- **Gate-then-golden assertion ordering** (`test_planning_goldens.jl:48-55`): the loop's own
  convergence gate must pass BEFORE any pinned value is consulted. The integer tests must follow
  this, with D-13/D-14's criterion as the gate.
- **Boundary guards first** in builders (`build_master` throws on `T < 1`, `y_max <= 0`, `c_y < 0`
  before assembling the objective) — the integer builder should guard `K` the same way.
- **Never `Model(HiGHS.Optimizer)` directly** — `select_optimizer(...)` only, per the INFRA-02
  comment at `master.jl`.
- **Finite epigraph lower bounds at build time** (`α_op >= α_op_lb`, `α_x >= α_x_lb`, "Pitfall M1")
  — the zero-cut first solve depends on them; the integer master needs the same treatment.

### Integration Points
- `build_master_integer` → new, in `src/planning/master.jl` (or a sibling), registered + exempted in
  `test/test_planning_noninteger.jl`.
- `master = nothing` kwarg → `solve_stackelberg!` in `src/planning/benders.jl`, resolved at line 185.
- LL cut generation + no-good bookkeeping → `benders.jl` cut section (`:op` / `:x` cut families
  already exist as the pattern to follow), surfaced through `trace.jl`.

</code_context>

<specifics>
## Specific Ideas

- The convergence-to-continuous story is the point of D-01: the user explicitly accepted that the
  discreteness is physically meaningless in exchange for a clean, interpretable diff against the
  continuous baseline. Do not retro-fit a physical justification for the lattice.
- The user explicitly accepted the `2^-K` unreachable-endpoint artifact (D-02) in exchange for round
  step sizes that read well in a literate page. It must be DOCUMENTED, not engineered away.
- Two certificates were offered and declined (no-good-count-zero, finite-termination bound). Their
  absence is a decision, not an oversight — do not reintroduce them as gates.

</specifics>

<deferred>
## Deferred Ideas

- **A production termination criterion for large lattices** — D-14's enumeration-backed fallback is
  tractable only where exhaustive enumeration is. If the rigorous `δ_min` derivation does not hold
  up, deriving a criterion that scales beyond enumerable lattices is explicitly deferred, and must
  be recorded as an open item rather than substituted with a tolerance.
- **Integrality in the N>1 Nash / diagonalization path** — this phase is single-distributor
  Stackelberg only (INT-01). Integer investment across multiple distributors, and what integrality
  does to Gauss-Seidel diagonalization's already-absent uniqueness guarantee, is a separate phase.
- **Engineering block sizes / explicit level menus** (the D-01 alternatives) — if a later phase wants
  physically-meaningful lumpy investment, that is a modelling extension on top of this machinery.

</deferred>

---

*Phase: 24-discrete-integer-investment-expansion*
*Context gathered: 2026-08-23*

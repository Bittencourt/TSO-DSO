# Phase 31 Findings: GNE Nash Fixture, Integer N>1 & Planning Docs Refresh

**Phase:** 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
**Closed:** 2026-10-02 (pending orchestrator suite certification — see "READY FOR
ORCHESTRATOR SUITE CERTIFICATION" below)
**Requirements:** BILEV-06, BILEV-07, BILEV-08

This document consolidates the fixture designs, measured numbers, fixes, and audit results
across plans 31-01 (carried-over Phase-30 WR-01/WR-02/WR-03 warnings), 31-02 (integer
master epigraph bound validation + LL cut guard), 31-03 (GNE fixture + variational
equilibrium), 31-04 (integer N>1 Nash wiring + cycle detection), 31-05 (planning docs
refresh), and 31-07 (WR-03 Option A build-time clamp), per this plan's seven required points.

## 1. WR-01/WR-02/WR-03 (plans 31-01/31-02/31-07)

**WR-01 (plan 31-01, FIXED, committed `986aa4b`):** `_oracle_or_infeasible` no longer maps
an unconfirmed `MOI.ALMOST_INFEASIBLE` straight to `+Inf`. It now requires confirmation via
the same slack-min `feas_oracle` the outer Benders loop already uses: with no `feas_oracle`
supplied, the status is treated as unconfirmed and the original throw is rethrown (fail
loud); with a `feas_oracle` supplied, `solve_feasibility_oracle!(feas_oracle, z).v` is
classified via `_feas_cut_class`, and only a `:disagree` verdict rethrows. `feas_oracle` is
threaded through `corner_recourse` → `_corner_recourse_ternary`/`_corner_recourse_joint` →
`ll_cut_recourse(::BendersMasterInteger, ...)`, and the one production call site inside
`solve_stackelberg!` now passes the already-built `feas_oracle`. Test design: 4 new
regression tests using a `MOI.Utilities.MockOptimizer`-backed fake oracle to deterministically
pin `termination_status` without a real solve (unconfirmed `ALMOST_INFEASIBLE` rethrows; a
`:separating`-class confirmation returns `nothing`; a `:disagree`-class confirmation rethrows;
a plain `MOI.INFEASIBLE` is unaffected). Results: 157/157 pass across the 6-file regression
sweep used to confirm the fix.

**WR-02 (plan 31-02, FIXED, committed `11ffec4`):** `build_master_integer` ported `build_master`'s
full `bounds_ctx`/`:auto`/`lb_slack` validation machinery verbatim (`α_op_lb`/`α_x_lb` now
accept `Union{Symbol,Real}`, `:auto` default, byte-identical resolution path to `build_master`
on the opt-out path). `BendersMasterInteger` gained a `lb_slack::NamedTuple{(:op,:x),...}`
field and a type-specific `_accepted_lb_slack` method, picked up automatically by
`benders.jl`'s pre-existing generic dispatcher. `add_ll_cut!` gained an `atol::Real = 1e-6`
keyword and now throws a named `ErrorException` (never silently appends an invalid cut) when
its own `Q_nu >= L` precondition is violated beyond `atol * max(1, |L|)`. The docstring's
previously-wrong Hamming-distance-`k` math (`D <= -1` / `θ >= L - 2k(Q_nu-L)`) was corrected
to `D = 1-k` / `θ >= L - (k-1)(Q_nu - L)`. Test design: 6 new `@testitem`s for Task 1
(`:auto` requires `bounds_ctx`, `:auto` resolution matches `derive_alpha_op_lb`/
`derive_alpha_x_lb`, build-time rejection of an over-high explicit bound, honest skip for
`follower_kwargs = nothing`, `_accepted_lb_slack` type-specific dispatch, IN-03 unknown-Symbol
guard) and 1 new `@testitem` for Task 2 (the `Q_nu >= L` guard throws and leaves `master.cuts`
unmutated; the boundary `Q_nu == L` does not throw; a custom `atol` widens acceptance).

**WR-03's final resolution (plan 31-07, Option A, FIXED, committed `7707071`/`b12b284`):**
Plan 31-01's own Task 2 first attempted the plan-directed Option B (30-REVIEW.md: widen
`solve_stackelberg!`'s convergence certificate by `_accepted_lb_slack`) and found, by direct
measurement, that it **breaks the project's flagship pinned Benders goldens** — `build_master`'s
own recorded `lb_slack ≈ (op=1.0028508990723707e-6, x=1.0e-6)` for ANY explicit-bound
`solve_stackelberg!` call (not just near-the-edge bounds) since Phase 30's unconditional
`bounds_ctx` wiring made that recording unconditional; `lb_slack_total ≈ 2.0e-6` exceeds the
project's own standard `tol=1e-6`, causing `test_planning_benders.jl`'s flagship N=1 golden
and `test_planning_alpha_bounds_stackelberg.jl`'s pre-existing tests to exhaust `max_iter`
without converging. Plan 31-01 reverted Task 2 (`git checkout --`, never committed) and
recommended Option A as a follow-up.

Plan 31-07 implemented **Option A**: `build_master`/`build_master_integer` now compute
`α_eff = min(requested, d.bound)` in the accepted-explicit-bound branch (both epigraphs),
install `α_eff` — never the raw requested value — on the JuMP variable's lower bound, `@warn`
(maxlog=1) when a clamp actually fires, and record `requested − α_eff` on a new
`BendersMaster.lb_clamped`/`BendersMasterInteger.lb_clamped` field. `slack_op`/`slack_x` are
now unconditionally `0.0` in that branch, so `lb_slack` is provably `(; op=0.0, x=0.0)` on
BOTH master types for every call path (`:auto`, accepted-and-clamped, accepted-and-unclamped,
opt-out). The rejection ceiling is byte-identical to before. `BendersMasterInteger`'s own
`L = α_op_lb_resolved + α_x_lb_resolved` is now computed from the CLAMPED resolved values — a
strictly tighter, still-valid global lower bound for the Laporte-Louveaux cut.

**Why Option A does not have Option B's problem:** Option B widened the RUNTIME convergence
certificate to compensate for a build-time acceptance slack that is a worst-case constant
(not a measurement of how much slack was actually used) — this unconditionally loosens every
explicit-bound call's convergence test by an amount that can exceed `tol` itself. Option A
instead eliminates the slack AT THE SOURCE: an accepted-but-slack explicit bound is clamped
down to the certified `:auto`-equivalent minimum at build time, so `lb_slack` is genuinely
`0.0` and `solve_stackelberg!`'s convergence certificate (`benders.jl`) and
`_assert_epigraph_floor` need **zero changes** — confirmed by `grep` showing zero edits to
`benders.jl`/`nash.jl` in either of plan 31-07's task diffs. Three test files were updated to
prove the clamp (`test_planning_master.jl`, `test_planning_alpha_bounds_stackelberg.jl`,
`test_planning_master_integer.jl`) — each now asserts the installed bound equals the certified
minimum (not the raw requested value), that `lb_clamped` records the positive clamp amount
when a clamp fires, and that `lb_slack` is always zero; one production-style
`_assert_epigraph_floor` call using the RAW unclamped bound is deliberately kept in
`test_planning_alpha_bounds_stackelberg.jl` to prove the underlying WR-03 finding (an
unclamped bound genuinely would trip the floor) remains true.

**BILEV-07's "Phase-30 open integer-path review warnings are FIXED here" claim is now FULLY
true** — WR-01 (31-01), WR-02 (31-02), and WR-03 (31-07, Option A) are all fixed and
committed; no part of the carried-over Phase-30 review is left open.

## 2. BILEV-06a: interior-cap GNE fixture (plan 31-03)

**Fixture design:** a variant of the existing 2-distributor toy
(`test/test_planning_nash.jl`, T=1, `corridor_cap=2.0`) with `x_inv_max=[1.0,1.0]` — a margin
of 0.3 above the analytically-derived pooled-capacity minimum `S_min=0.7`, safely non-binding
everywhere on the GNE interval without being a de facto `Inf` (per 31-RESEARCH.md's own
Pitfall-4 guidance). The pooled corridor capacity constraint binds while no individual
`x_inv_max[i]` binds — opening a 1-D continuum in how the shared capacity is split.

**Ground truth (analytical):** the equilibrium set is the interval
`{(x1, 0.7−x1) : x1 ∈ [0, 0.7]}` — every point on this line is a generalized Nash equilibrium
since the ONLY binding coupling is the pooled sum, and either distributor can be given more
or less of the shared capacity without changing total welfare at the margin.

**Measured `x_inv_spread` floor:** an 8-run probe (`run_nash_probe`'s extended
`(; z0, x_inv0)` seed dispatch, `x_inv0 ∈ {0.0, 0.2, 0.5, 0.7} × 2` sweep orders) measured
`x_inv_spread ≈ 0.6999` — exceeding a measured floor of `0.5` (not a picked constant) with
a margin of `~0.2`, while `z_spread ≈ 5.8e-4` stayed near-zero. This is documented explicitly
as a CORRECT property of an investment-split continuum (the shared `z` outcome barely moves
while `x_inv`'s split varies freely across the full interval), not a probe bug. Every
converged run's `(x_inv_1, x_inv_2)` summed to `S_min=0.7` within `atol=1e-3`.

**Corner-cap control fixture:** the pre-existing `x_inv_max=[0.3,0.3]` fixture (unique
equilibrium, both individual caps bind) was KEPT and its regression TIGHTENED:
`x_inv_spread < 1e-6` (measured ~0.0) and `z_spread < 1e-6` (measured ~1.11e-16) — confirming
the corner-cap case stays genuinely unique while the interior-cap case genuinely is not.

**`run_nash_probe`'s seed-dispatch extension — final shape:** `seeds` entries accept EITHER a
bare `z0` matrix (unchanged, byte-identical default path) OR a `(; z0, x_inv0)` NamedTuple
that forwards `run_nash!`'s own pre-existing `x_inv0` keyword — additive, fully
backward-compatible dispatch on seed shape.

## 3. BILEV-06b: variational-equilibrium selection (plan 31-03)

**Final design:** a new standalone `solve_variational_equilibrium(specs; T, corridor_cap,
x_inv_max, c_inv, c_op)` function (`run_nash!` itself is UNCHANGED). Confirmed the players'
costs ARE separable except through the shared pooled-capacity row (Rosen-separable), so the
method solves ONE monolithic joint JuMP model containing the shared `capacity[t]` row once —
written DIRECTLY over each distributor's own `z[i,t]` rather than reusing
`build_shared_transmission`'s separate per-distributor-dualizable `x_op[i,t]` identity-coupled
variable (documented as a deliberate simplification: the dualizable `x_op` row exists only
for `DistributorView`'s per-distributor Benders iteration, which a single monolithic solve
does not need). VE ⇔ equal shared-row multipliers is realized trivially by construction (one
row, written once — the single shared multiplier `π_capacity` is finite and necessarily
identical across distributors since there is only one copy of the constraint).

**Measured no-profitable-deviation certification result:** certified on the interior-cap
fixture — the VE's `(x_inv_1, x_inv_2)` sums to `S_min=0.7` with `z ≈ (0.7, 0.7)`; a
no-profitable-deviation re-solve against a freshly pinned `SharedTransmission` (using
`solve_stackelberg!`) confirms neither distributor can improve by unilateral deviation —
`solve_stackelberg!`'s own `UB` matched `cost_per_distributor` to `~4.3e-8`, well inside the
measured `1e-4` tolerance. The VE also agrees with the corner-cap control's pinned unique
equilibrium (`z=[0.6,0.6]`, `x_inv=[0.3,0.3]`) when the equilibrium IS unique, as expected.

**Degenerate-face vertex — reported honestly:** on the interior-cap fixture, the joint LP's
degenerate face (the shared constraint's many equally-optimal splits) landed on the
**symmetric point** `x_inv ≈ (0.35, 0.35)` for the VE solve — the plan's own context
anticipated reporting either outcome honestly; the symmetric split is what Clarabel's
interior-point method produced on this fixture (not an asymmetric vertex), consistent with
IPM solutions tending toward analytic centers of degenerate faces rather than LP-simplex-style
extreme points.

**Two Rule-1 bugs found and fixed during implementation (both load-bearing, not scope creep):**
1. JuMP object-dictionary name collision when a SECOND distributor's `contribute!` call tried
   to register the same fixed symbol names (`:v`, `:P`, `:Q`, ...) on the shared `Model` —
   fixed via `JuMP.unregister(model, name)` after each distributor's `contribute!` call
   (formulation-generic, no hardcoded name list; underlying variables/constraints stay fully
   live via `ctx_i.residuals`/`ctx_i.meta[:pf_vars]`).
2. `cost_per_distributor` omitted the `-λ₀·z` pricing term that `solve_stackelberg!`'s own
   `UB` includes — caught by the no-profitable-deviation cross-check itself (measured gap
   `2.8`, exactly `λ₀[1]*z[i,1] = 4.0*0.7`), fixed by subtracting
   `sum(specs[i].λ₀[t]*value(z[i,t]) for t in 1:T)` alongside the device/aggregator utility
   term.

## 4. BILEV-07: integer investment at N>1 (plan 31-04)

**Final `run_nash!` `integer` kwarg shape:** `integer::Union{Nothing,NamedTuple} = nothing`
(e.g. `integer = (; K = 4, α_x_lb = 0.0)`). When supplied, every distributor's best response
inside the N-distributor Gauss-Seidel sweep loop builds a FRESH `build_master_integer`
(`α_op_lb = :auto` via the SAME `bounds_ctx` machinery `build_master`/`solve_stackelberg!`
already use since plan 31-02's porting work, `α_x_lb` an explicit, unvalidated bound
defaulting to `0.0` — the same accepted, documented skip the continuous path already uses for
`DistributorView`'s pooled-capacity coupling) and passes it via `solve_stackelberg!`'s
pre-existing `master=` keyword. The continuous (`integer === nothing`) path is byte-identical
to every pre-Phase-31 call (confirmed: full pre-existing `test_planning_nash.jl` suite,
132 pass / 1 pre-existing broken / 0 fail; `docs/literate/nash_diagonalization.jl` end-to-end
exit 0).

**Measured per-best-response integer MILP wall time at N=2:** a single N=2, K=4 integer Nash
run (2 sweeps, 4 best responses total) took ~67s wall time on the toy fixture — noticeably
slower than the continuous fixture's sub-second convergence, consistent with 31-RESEARCH.md's
own single-distributor measurement (~4s/best-response) scaled up by extra Laporte-Louveaux
corner-recourse ternary-search re-solves the shared-transmission `DistributorView` follower's
own capacity ceiling triggers more often than the single-distributor `FollowerLP` fixture did.

**Brute-force certification result (both distributors):** per-player 16-point brute-force
enumeration via the PRODUCTION `corner_recourse` (never a re-derived enumeration) confirmed
NO profitable unilateral deviation for either distributor at the reported equilibrium
(`z=[0.5,0.5]`, `x_inv=[0.25,0.25]`, `UB=[-0.225,-0.225]` — the nearest K=4 lattice point
at/below the known continuous optimum `z=0.6`) — measured diff `2.22e-16` (machine epsilon)
against a measured `1e-6` no-profitable-deviation tolerance ceiling.

**Cycling detection — restated verbatim, not upgraded or downgraded:** cycle detection
(exact-binary-state `Dict{Vector{Int},Int}` over the fixed canonical distributor order
`1:shared.N`, raising a loud, named `ErrorException` reporting the full cycle shape on a
revisited state) was implemented and is exercised IMPLICITLY by every converged run (the
`visited_joint_b` dictionary is populated and checked on every sweep). However, an END-TO-END
demonstration of a genuinely CYCLING integer diagonalization was NOT achieved on this toy
N=2/K=4 fixture — per the plan's own explicit allowance, this item was honestly DOWNGRADED to
the standalone dictionary-logic replication (`test/test_planning_nash_integer.jl`'s third
`@testitem`, exact `Vector{Int}` equality mirroring `master_integer.jl`'s own `visited`
pattern), exercised and verified in isolation rather than forced on a live run. This is a
documented, honest limitation — not silently upgraded to "demonstrated end-to-end."

**Rule-1 bug fixed (load-bearing, found during this plan's own execution):**
`solve_follower!(::DistributorView, ...)` (`src/planning/coupling.jl`) previously raised a
generic, unnamed `ErrorException` on ANY confirmed `MOI.INFEASIBLE` without a Farkas dual ray
— a code path `corner_recourse`'s ternary search triggers routinely (it explores trial `z`
across the full `[0, y_inv]` master lattice range, which regularly exceeds what the OTHER,
currently-pinned distributor's shared capacity permits). Fixed by adding a third, additive
branch returning `(; feasible = false, v = NaN, u = fill(NaN, T))` for this
confirmed-but-uncertified case — transparent to `corner_recourse`'s own `Qfun` (reads only
`.feasible`), while a caller needing a real cut (`solve_stackelberg!`'s own outer
feasibility-cut branch) still hits `add_feasibility_cut!`'s own finiteness guard and fails
loudly there instead. Without this fix, NO integer-Nash run on this fixture (or any fixture
where a `DistributorView`'s own capacity-reduced feasible range is smaller than the master's
own lattice ceiling) could complete at all.

## 5. BILEV-08: planning docs refresh (plan 31-05)

**Confirmation both `.typ` files compile:** `typst compile` exited 0 on both
`docs/writeups/stackelberg_vs_psr_n1n2.typ` and `docs/writeups/modelo_stackelberg_dso_unico.typ`
on first attempt for both files during this plan's execution.

**Stale claims removed:** `stackelberg_vs_psr_n1n2.typ`'s "Extensão inteira — problemas
(8)-(9)" section no longer claims "Não implementado"/"Nenhuma variável binária/inteira
existe" (both false since Phase 24). The table now maps each PSR equation group onto the
actual construct, explicitly documenting TWO independent deviations from the PSR note: (1)
the repo integerizes the LEADER's investment `y_inv` (N2, via `build_master_integer`'s binary
expansion `b[1:K]`), not the note's FOLLOWER-side (N1) `x_inv`/`x_op`/`z_x`; (2) recourse is
enforced via `add_ll_cut!`'s Laporte-Louveaux integer L-shaped cuts (Laporte & Louveaux 1993),
not the note's Lagrangian relaxation of copy constraints (Zou-Ahmed-Sun 2019) — a mechanism
deviation independent of the target-variable deviation. `modelo_stackelberg_dso_unico.typ`'s
stale "Sem variáveis binárias em lugar algum" bullet was corrected to state continuous
investment is the default with `BendersMasterInteger` available via `master=`.

**Human checkpoint resolution:** `approved-pending-later-read` — the user responded
"approved" to unblock the plan's completion but explicitly deferred the actual prose
read-through of the two PDFs to a later session, to raise any issues separately if found.
Recorded honestly as NOT a completed, confirmed-accurate read (every citation in the new
prose was independently grep-verified against `src/`/`test/` before the checkpoint, and both
documents compile cleanly, but the narrative prose itself has not yet had a full human read).

**Additional scope landed:** a new "Taxonomia dos variantes de planejamento" section in
`modelo_stackelberg_dso_unico.typ` (table: `solve_stackelberg!` / `solve_bilevel!` /
`run_nash!`+`solve_variational_equilibrium`, each row citing its backing function AND test
file); three Documenter docstrings cross-referenced (`solve_stackelberg!`, `solve_bilevel!`,
`run_nash!`); `docs/src/api.md`'s Planning Layer `@autodocs` `Pages` list extended to include
`planning/bilevel_kkt.jl` (previously entirely undocumented in Documenter). The two refreshed
PDFs were force-added (`git add -f`) per an explicit user decision made during the checkpoint,
overriding the project-wide `.gitignore` convention (`/docs/writeups/*.pdf`) for these two
files only — `.gitignore` itself was left untouched (a one-off override, not a convention
change).

## 6. Design deviations (restated honestly, not silently reconciled)

- **(31-01)** Task 2's plan-directed WR-03 fix (Option B, convergence-certificate widening)
  broke multiple pre-existing pinned Benders goldens when implemented exactly as specified —
  the plan's own premise ("lb_slack is 0.0 on every pre-existing call site") was false for
  `BendersMaster` once Phase 30's unconditional `bounds_ctx` wiring is accounted for. Reverted
  rather than committed; recommended Option A as a follow-up, which plan 31-07 implemented.
  See point 1 above for the full resolution.
- **(31-03)** Two Rule-1 bugs found and fixed during `solve_variational_equilibrium`'s first
  implementation (JuMP name collision across distributors sharing one `Model`;
  `cost_per_distributor` missing the `-λ₀·z` pricing term) — both necessary for the function
  to work at all (N>1) or for its own certification to be meaningful rather than silently
  wrong. See point 3 above.
- **(31-04)** A Rule-1 bug in `solve_follower!(::DistributorView)` (a confirmed
  `MOI.INFEASIBLE` without a Farkas ray was previously an unrecoverable error) had to be fixed
  for the new integer wiring to run at ALL — not an optional hardening, a hard blocker. See
  point 4 above.
- **(31-04)** The end-to-end cycling demonstration was honestly downgraded to the standalone
  dictionary-logic replication per the plan's own explicit allowance — restated verbatim in
  point 4 above, not silently upgraded.
- **(31-05)** The plan's own instruction to "commit both refreshed .pdf outputs alongside the
  .typ sources" conflicted with the pre-existing, deliberate `.gitignore` convention
  (`/docs/writeups/*.pdf` is ignored project-wide). Plan 31-05's Task 1 followed the actual
  repo convention (committed only `.typ` sources); a later explicit user decision during the
  checkpoint override force-added the two PDFs anyway, in a separate commit, with
  `.gitignore` itself left untouched.
- **(31-05)** The Task 3 human-verify checkpoint was approved by the user WITHOUT a completed
  prose read-through (explicitly deferred) — recorded as `approved-pending-later-read`, not a
  completed verification.
- **Process note (mirrors the Phase-30 precedent this plan's own handoff design is modeled
  on):** this plan (31-06) is executed non-autonomously per its own frontmatter
  (`autonomous: false`) — Task 1 (golden audit + consolidated findings) and Task 2's
  preparation (preconditions) are both executed by the plan executor; the full-suite
  `Pkg.test()` certification itself is deliberately deferred to the orchestrator, per the
  `background-suite-orphan-race` memory note (a spawned sub-agent's detached/background
  processes do not survive its own tool-call batch ending).

## 7. Golden-move audit result

```
BASE=36e3c1e  # docs(30-06): complete [phase close] plan -- TRUE Phase-30 close commit,
              # confirmed via `git log --oneline --all | grep -i "30-06"` cross-referenced
              # against 30-FINDINGS.md's own "READY FOR ORCHESTRATOR SUITE CERTIFICATION"
              # section (HEAD sha `38b2e05` is an ANCESTOR of this commit; `36e3c1e` is the
              # actual final "docs(30-06): complete [phase close] plan" commit, i.e. the true
              # close point per this plan's own hardcoded verify block)

python3 .planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/scripts/audit_goldens.py --base 36e3c1e --head HEAD
# Golden-move audit: 36e3c1e..HEAD -- test/

Total flagged numeric-literal moves: 0
Attributed: 0  Allowlisted: 0  Unattributed: 0
AUDIT_EXIT: 0
```

**Exit code 0, zero flagged moves at all** (not zero-unattributed-among-many-flagged) —
confirming Phase 31 only ADDS new measured constants (the GNE-interval `x_inv_spread` floor
`0.5`, the WR-01/02/03 fix tolerances/clamps, the integer-Nash brute-force comparison
tolerance `1e-6`, the VE no-profitable-deviation tolerance `1e-4`, etc.) and never touches,
moves, or re-pins any pre-existing golden value.

---

## READY FOR ORCHESTRATOR SUITE CERTIFICATION

**HEAD sha:** `445c08a` (`docs(31-06): golden-move audit + consolidated phase findings` — the
commit that adds this very file). Parent commit `85a96be`
(`docs(31-05): complete BILEV-08 planning docs refresh plan`) was the full state of all prior
Phase-31 plans (31-01, 31-02, 31-03, 31-04, 31-05, 31-07) with a clean working tree — this
plan's own Task 2 found no outstanding `src/`/`test/`/`docs/` changes beyond this findings
file itself requiring a new commit before certification. `git status --short` is clean at
`445c08a` on branch `main`.

**Preconditions confirmed:**

1. `git worktree list` — **no `.claude/worktrees/agent-*` entries.** Two unrelated, stale
   worktrees exist at a different path pattern
   (`~/programming/TSO-DSO.worktrees/operational-planning-integration` on branch
   `agents/operational-planning-integration`;
   `~/programming/TSO-DSO.worktrees/pdf-documentation-thesis-results` on branch
   `agents/pdf-documentation-thesis-results`) — identical to the two stale worktrees already
   reported (and not treated as blocking) in `30-FINDINGS.md`'s own precondition check. These
   do NOT match the `background-suite-orphan-race` contamination pattern (which is
   specifically about live `.claude/worktrees/agent-*` sessions doubling the reported suite
   count) and are outside this repo's own `test/`/`src/` tree scope.
2. No stale `Pkg.test`/live `julia` processes running — confirmed via
   `pgrep -fa "[j]uliaup/julia"` (zero matches, exit 1) and `pgrep -fa "Pkg.test"` (the one
   match returned is the `pgrep` invocation's own command-line self-match via the Bash
   wrapper's `eval` string, not a real running process — confirmed by inspecting the matched
   line, which is the shell wrapper's own `eval '... pgrep ...'` invocation).
3. `git status --short` clean at HEAD `445c08a`; working tree on branch `main` (this is the
   main working tree — `.git` is a directory, not a worktree file — so no worktree-specific
   HEAD-safety assertions apply).

**Phase-30 close baseline to compare against:** **31091 pass / 0 fail / 0 error / 5 broken**
(recorded in `30-FINDINGS.md`'s own "CERTIFIED: Full-Suite Tallies" section, certified HEAD
`22b7eb5`, re-confirmed docs-only through `c68aa19`, and again through `36e3c1e`).

**This phase's new/extended test files** whose `@testitem`s should be added to that baseline
when the orchestrator certifies:
- `test/test_planning_benders_integer.jl` (extended, plan 31-01 — 4 new `@testitem`s for WR-01)
- `test/test_planning_alpha_bounds_stackelberg.jl` (extended, plans 31-01 revert-verified /
  31-07 — WR-03 Option A clamp assertions)
- `test/test_planning_master_integer.jl` (extended, plans 31-02 / 31-07 — 7 new `@testitem`s
  for WR-02 + `_accepted_lb_slack`/clamp rewrite)
- `test/test_planning_master.jl` (extended, plan 31-07 — WR-03 Option A clamp assertions)
- `test/test_planning_nash.jl` (extended, plan 31-03 — interior-cap GNE fixture + probe
  testitem, tightened corner-cap control regression, 2 new VE certification testitems)
- `test/test_planning_nash_integer.jl` (new, plan 31-04 — 3 `@testitem`s: N=2 K=4 convergence
  + brute-force certification, integer kwarg boundary guards, cycle-detection standalone
  replication)

**Fail/error must stay 0. Broken must stay 5** — this phase adds no new `@test_broken`.
Plan 31-04's own Test 3 (end-to-end cycling demonstration) was downgraded to a standalone
LOGIC replication rather than recorded as a new `@test_broken` item (see point 4/6 above) —
it is a passing test of the detection mechanism in isolation, not a `@test_broken`-marked
gap. No plan in this phase introduced a new `@test_broken`/`broken=` marker.

**This plan's own executor never launches, polls, or waits for `Pkg.test()`.** The
ORCHESTRATOR is responsible for: launching the single detached
`julia --project=. -e 'import Pkg; Pkg.test()'` run via its own persistent background-process
mechanism, confirming the log's first timestamp postdates HEAD `445c08a`, filtering for zero
`.claude/worktrees/` contamination, comparing the final tallies against the baseline above,
and appending those final tallies directly into this file.

<!-- ORCHESTRATOR: append certified full-suite tallies below this line once the run completes. -->

## CERTIFIED: Full-Suite Tallies

**Certified run:** single detached run launched by the orchestrator (never this plan's own
executor). Started 2026-10-02T08:56:54-03:00, duration 29m37.9s, exit 0,
`"Testing TSODSO tests passed"`. Log: `/tmp/claude-1000/p31_certified_suite_32e4cd5.log`.
Zero `.claude/worktrees/agent-*` entries; zero worktree paths found in the log (no
contamination, per the `background-suite-orphan-race` memory's own detection method).

**Certified HEAD:** `32e4cd5` (`docs(31-06): correct self-referential HEAD sha in
31-FINDINGS.md`) — the readiness-marker HEAD recorded above. The repo's actual HEAD at the
time this section is written is `476e165` (`docs(31): add code review report`), docs-only
relative to `32e4cd5` (confirmed: `31-REVIEW.md` only, zero `src/`/`test/` diff) — this
mirrors the Phase-29/Phase-30 precedent (certified at a code commit, closed one or more
docs-only commits later) and the certified run genuinely covers the code being shipped.

**Tallies:** **31190 pass / 0 fail / 0 error / 5 broken** (31195 total).

**Baseline comparison:** Phase-30 close baseline (`30-FINDINGS.md`, certified HEAD `22b7eb5`)
was **31091 pass / 0 fail / 0 error / 5 broken**. Delta: **+99 pass**, fail/error unchanged
at 0, **broken unchanged at 5** (confirming Phase 31 adds no new `@test_broken`, as predicted
in the readiness section above and in point 6's deviation log).

**Golden-move audit at this HEAD:** re-confirmed in point 7 above — exit 0, zero flagged
moves, `--base 36e3c1e --head HEAD` (re-run against the certified state would show the same
zero-flag result; `31-REVIEW.md` is a `.planning/` doc, outside the audit script's `test/`
scope).

**Zero re-pinned pre-existing goldens** at the certified HEAD, same conclusion as point 7's
pre-certification run.

## Known Open Issues (post-certification code review, left unresolved)

**Process note:** after the certified suite run above, the orchestrator ran a code-review
pass against this phase's full diff (`git diff 36e3c1e`, commit `476e165`,
`31-REVIEW.md`) — **2 critical / 6 warning / 7 info findings**. The user explicitly
**STOPPED autonomous mode after this review**, so **no fix iteration was run**. Every finding
below is OPEN, not fixed. Per the coordinator's explicit instruction: **Phase 31 is
certified-green on tests, but BILEV-06 (VE selection) and BILEV-07 (cycle detection) have
known correctness gaps pending a fix round — the phase is NOT being marked verified; full
phase-level completion is deferred to a later session.**

### Critical findings (2)

**CR-01 — Integer cycle detection fires on runs that are still converging (reproduced).**
`src/planning/nash.jl:736-754` (key built at 633-641). The cycle key is only the joint
binary vector `b`, but the game state also includes the continuous `z`/`x_inv`; binaries
routinely settle before those do, so any run needing ≥3 sweeps with a stable `b` is reported
as a false "CYCLED" error. **Reproduced**: the BILEV-07 test fixture with
`integer=(;K=4), ω=0.5` throws
`integer diagonalization CYCLED — the joint binary state [1,0,0,0,1,0,0,0] recurred at sweep 2
(first seen at sweep 1)` after 107s — damping halves the residual each sweep while `b` stays
fixed, and point 4's own standalone-replication-only cycle test (exact `Dict` key equality,
never calling `run_nash!`) cannot catch this class of false positive. **This directly
contradicts point 4 above's own "exercised implicitly by every converged run" framing** — it
is exercised, but demonstrated here to be WRONG on a converging run, not merely
untested-end-to-end as point 4 honestly stated. Fix proposed (not applied): key on the full
committed state (joint_b, rounded z, rounded x_inv), checked only when the sweep has not
converged; or require `b` to recur with a non-decreasing residual (mirroring Phase 24's
`apply_integer_cuts!` stall-guard pattern).

**CR-02 — The VE is not unique on the interior-cap fixture; docs/tests wrongly claim
selection.** `src/planning/nash.jl:285-292, 1037-1049, 1079-1083`;
`docs/writeups/stackelberg_vs_psr_n1n2.typ:229-231`; `test/test_planning_nash.jl` (VE
testitem). With `c_inv = [1, 1]` (the shipped interior-cap fixture from point 2/3 above), the
joint objective and every constraint depend on `x_inv` only through `x1 + x2`, so the joint
problem's optimal face is the ENTIRE split segment, and every GNE point on the continuum has
an IDENTICAL shared-row multiplier `π = 0.5` — the VE set equals the GNE set on this fixture.
**This directly contradicts point 3 above's framing of `solve_variational_equilibrium` as
genuinely "selecting" a distinguished equilibrium**: on the fixture actually shipped,
"VE selection" is mathematically empty (every GNE already satisfies the VE's own
equal-multiplier criterion), so the returned point `(0.35, 0.35)` (point 3's "degenerate-face
vertex" paragraph) is merely solver-dependent, not a selection in any meaningful sense. The
writeup's "Dentro do continuum de GNEs acima, o VE é o GNE cujo multiplicador ... é
IDÊNTICO" is literally false AS A DISTINGUISHING STATEMENT for this fixture (true but vacuous
— true of every point). The existing tests (`sum(x_inv)≈0.7`, `isfinite(π)`,
no-profitable-deviation) cannot distinguish a VE from any other GNE, since all three hold at
every point of the continuum. Rosen's uniqueness argument needs diagonal strict concavity,
which this linear-in-`x` fixture lacks. Fix proposed (not applied): state explicitly in the
docs that the VE is non-unique on this fixture and the returned point is solver-dependent;
add a SEPARATE selection-test fixture with asymmetric `c_inv` or a strictly convex investment
cost so the VE is actually unique, and assert the hand-derived split there.

### Warnings (6)

- **WR-01:** the new no-Farkas-ray infeasible branch (point 4 above's Rule-1 fix,
  `coupling.jl:434-444`) is a dead end for every caller that needs a cut: at T>1,
  `_corner_recourse_joint.evaluate` pushes a NaN feasibility cut into the small LP and JuMP
  throws an opaque `Invalid coefficient NaN` error; in the outer loop, `add_feasibility_cut!`
  aborts the whole Nash run on a merely-infeasible trial. The coupling docstring's "fails
  loudly there" claim does not hold — nothing can recover. Fix proposed: route a
  `NaN`/non-finite cut to `nothing` (bisection fallback) instead of pushing it; re-solve once
  with presolve off to get a genuine Farkas ray before falling back.
- **WR-02:** `modelo_stackelberg_dso_unico.typ:195` wrongly claims `inexact_policy` applies
  to all three taxonomy rows including the bilevel KKT row — `bilevel_kkt.jl` never calls
  `solve_stackelberg!`, has no `inexact_policy`, and rejects QP/SOCP formulations. Fix
  proposed: restrict the claim to rows 1 and 3; state row 2 is LP-only.
- **WR-03:** `test_planning_nash_integer.jl`'s "brute-force certification" (point 4 above) is
  NOT independent — the enumeration reuses production `corner_recourse` with the same
  oracle/follower/accounting as the UB under test, so a bug there would be reproduced on both
  sides of the comparison; the measured equilibrium (`z=[0.5,0.5]`, `x_inv=[0.25,0.25]`,
  `UB=-0.225`) is never asserted as a pinned value. Fix proposed: assert the hand-derived
  lattice equilibrium directly; certify each lattice point via a separately-built LP/QP, not
  `corner_recourse`.
- **WR-04:** `add_ll_cut!`'s `Q_nu >= L` tolerance band (point 1/WR-02 above) still permits
  an invalid cut: for `L − atol·max(1,|L|) ≤ Q_nu < L`, the guard passes but the appended cut
  has negative slope, over-constraining θ by up to `(K−1)·atol·|L|`. The public `atol` kwarg
  allows arbitrarily invalid cuts. Fix proposed: clamp `Q_eff = max(Q_nu, L)` after the guard
  passes, logging the clamp.
- **WR-05:** in the corner search (point 1/WR-01 above), a `:weak` or unconfirmed
  infeasibility verdict is treated as confirmed and mapped to `+Inf` just like a genuine
  `:separating` verdict — `LOCALLY_INFEASIBLE`/`INFEASIBLE_OR_UNBOUNDED` are also labelled
  "CERTIFIED" and skip confirmation entirely. This can drop a near-boundary minimizer and
  make the Laporte-Louveaux cut slightly invalid. Fix proposed: confirm only on
  `:separating`; rethrow/bisect on `:weak`; route `LOCALLY_INFEASIBLE` through feas_oracle
  confirmation too.
- **WR-06:** the `integer` kwarg path (point 4 above) silently ignores any
  `spec.master_kwargs.α_op_lb`/`α_x_lb` the caller supplies, and assumes nonnegative
  `c_inv`/`c_op` (never validated) when deriving its own default `α_x_lb = 0.0` — a negative
  `c_op` makes `L` an invalid bound and the run aborts deep inside `add_ll_cut!` or the floor
  guard instead of failing at the boundary with a clear message. Fix proposed: throw if
  `master_kwargs` contains α-bound keys while `integer !== nothing` (or honor them); validate
  `c_inv, c_op ≥ 0` or derive `α_x_lb` from their actual signs.

### Info (7, documentation/cosmetic, no correctness impact)

IN-01 (`CORNER_INFEASIBLE_STATUSES` dead code, self-admitted), IN-02 (a stale `benders.jl`
comment claiming "tolerance includes the build-time acceptance slack" — `lb_slack` is always
zero post-31-07, so the field and `_accepted_lb_slack` are dead weight), IN-03 (`run_nash!`
docstring Algorithm step 4 is garbled), IN-04 (`stackelberg_vs_psr_n1n2.typ`'s claim that
`b[1:K]` are the "ÚNICAS variáveis binárias" in `src/planning/` is misleading —
`bilevel_kkt.jl`'s SOS1 pairs are bridged to binaries by `SOS1ToMILPBridge`), IN-05
(`nash.jl` never checks `result_i.y` actually lies on the lattice or `idx_i < 2^K`), IN-06
(the interior-cap probe's `z_spread` measurement, point 2 above, sits ~6× the outer
tolerance vs. a 17×-looser assertion bound — unexplained, not just unexercised), IN-07
(`@warn ... maxlog=1` in the WR-03/Option A clamp hides every clamp after the first in
multi-build contexts such as Nash; `run_nash_probe` cannot forward `integer`, so integer N>1
multiplicity cannot currently be probed the way point 2's continuous-case probe was).

### Verdict

**Phase 31 is certified-green on tests** (31190/0/0/5, +99 over the Phase-30 baseline, zero
regressions, zero new broken) **but is NOT being marked verified at the phase level.**
BILEV-06 (variational-equilibrium selection, CR-02) and BILEV-07 (integer cycle detection,
CR-01) both have known, reproduced correctness gaps — the shipped VE "selection" is vacuous
on the shipped fixture, and the cycle detector can raise a false-positive error on a
genuinely converging integer Nash run. These are carried forward, unresolved, pending a
dedicated fix round in a later session — not silently accepted as the phase's final state.

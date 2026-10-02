---
phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh
plan: 05
subsystem: docs
tags: [typst, documenter, julia, benders, bilevel, nash, gne, laporte-louveaux]

# Dependency graph
requires:
  - phase: 31-01
    provides: "WR-01 fix context (ALMOST_INFEASIBLE confirmation via feas_oracle) — referenced only indirectly, not cited in the writeups"
  - phase: 31-02
    provides: "build_master_integer's bounds_ctx/:auto/lb_slack machinery; add_ll_cut!'s Q_nu >= L guard — the constructs this plan maps the PSR note's integer-extension equations onto"
  - phase: 31-03
    provides: "run_nash_probe's (;z0,x_inv0) seed extension, the interior-cap GNE fixture, solve_variational_equilibrium — the constructs this plan's new Nash/GNE/VE prose and taxonomy row describe"
  - phase: 31-04
    provides: "run_nash!'s integer kwarg + cycle detection, test_planning_nash_integer.jl — cited directly in both writeups' integer-extension/Nash sections"
  - phase: 31-07
    provides: "build_master/build_master_integer's lb_clamped field (WR-03 Option A) — cited in solve_stackelberg!'s master= docstring paragraph"
provides:
  - "stackelberg_vs_psr_n1n2.typ refreshed: integer-extension table (8)-(9) maps onto build_master_integer/add_ll_cut! instead of asserting non-implementation; states explicitly that the repo integerizes the LEADER's investment (y_inv, N2) via Laporte-Louveaux L-shaped cuts, not the PSR note's follower-side (N1) Lagrangian relaxation; Nash section gains a GNE-multiplicity paragraph, a new solve_variational_equilibrium subsection, and an integer-N>1 note"
  - "modelo_stackelberg_dso_unico.typ refreshed: new 'Taxonomia dos variantes de planejamento' section naming all three planning variants (solve_stackelberg!, solve_bilevel!, run_nash!/solve_variational_equilibrium), each citing its backing function AND test file; stale 'sem variáveis binárias' implementation note fixed"
  - "Three Documenter entry-point docstrings cross-referenced: solve_stackelberg! -> run_nash!/solve_variational_equilibrium + BendersMasterInteger's own bounds_ctx validation; solve_bilevel! -> the new taxonomy table; run_nash! -> GNE-multiplicity caveat + solve_variational_equilibrium pointer"
  - "docs/src/api.md's Planning Layer @autodocs Pages list now includes planning/bilevel_kkt.jl (previously undocumented in Documenter)"
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Doc-refresh verification via grep-confirmed citation existence (every function/test name cited in new prose independently checked against src/ and test/) before trusting prose accuracy to a human read-through"

key-files:
  created: []
  modified:
    - docs/writeups/stackelberg_vs_psr_n1n2.typ
    - docs/writeups/modelo_stackelberg_dso_unico.typ
    - docs/writeups/stackelberg_vs_psr_n1n2.pdf
    - docs/writeups/modelo_stackelberg_dso_unico.pdf
    - src/planning/benders.jl
    - src/planning/bilevel_kkt.jl
    - src/planning/nash.jl
    - docs/src/api.md

key-decisions:
  - "Integer-extension table/prose state explicitly that the repo's integer extension targets a DIFFERENT variable than the PSR note: the LEADER's investment y_inv (N2), via build_master_integer's binary expansion b[1:K], versus the note's FOLLOWER-side (N1) x_inv/x_op/z_x integerization — a genuine deviation in target, not just mechanism, documented as such rather than papered over."
  - "Recourse-enforcement mechanism documented as a second, independent deviation: add_ll_cut!'s Laporte-Louveaux integer L-shaped cuts (Laporte & Louveaux 1993; Birge & Louveaux 2011 Sec. 5.2) versus the PSR note's Lagrangian relaxation of copy constraints (Zou-Ahmed-Sun 2019) — both address the same class of problem (MIP with expensive convex recourse) via mathematically distinct paths."
  - "User decision (post-checkpoint): force-add the two refreshed PDFs (git add -f) despite the project-wide .gitignore convention (/docs/writeups/*.pdf, 'track source, regenerate PDF'), committed separately from the .typ source commit; .gitignore itself left untouched — this overrides this plan's own Task 1 commit-message deviation note, which had deliberately NOT committed the PDFs per the pre-existing convention."

requirements-completed: ["BILEV-08"]

# Metrics
duration: ~20min (active work; checkpoint approval arrived in a later session)
completed: 2026-10-02
---

# Phase 31 Plan 05: Planning Docs Refresh (BILEV-08) Summary

**Both Portuguese Typst writeups and three Documenter entry-point docstrings now state the game-theoretic taxonomy of every planning variant (integrated-decomposed-by-Benders, genuine bilevel, shared-constraint GNE/VE) with every claim citing its backing function and test file, replacing stale "integer extension not implemented" claims that had been false since Phase 24.**

## Performance

- **Duration:** ~20 min of active editing/verification (Tasks 1-2); the Task 3 human-verify checkpoint was approved in a separate, later session
- **Started:** 2026-10-01T23:41Z (approx, immediately after plan 31-07's merge)
- **Completed:** 2026-10-02T08:48Z (PDF force-add commit, post-checkpoint)
- **Tasks:** 3 of 3 complete (2 auto tasks + 1 checkpoint, approved)
- **Files modified:** 8 (2 `.typ` sources, 2 `.pdf` outputs, 3 `.jl` docstring-only edits, 1 `api.md`)

## Accomplishments

- **`stackelberg_vs_psr_n1n2.typ`'s "Extensão inteira — problemas (8)-(9)" section** no longer claims "Não implementado"/"Nenhuma variável binária/inteira existe" (both false since Phase 24). The table now maps each PSR equation group onto the actual construct: (8a)-(8c) map to a documented deviation (the repo integerizes `y_inv`/N2/leader via `build_master_integer`, not `x_inv`/`x_op`/N1/follower as the note targets); (8e) maps to `build_master_integer`'s binary-expansion `y_inv = (y_max/2^K)·Σb_k`; (8f)-(9e) map to `add_ll_cut!`'s Laporte-Louveaux cut, labelled as a deliberate mechanism deviation from the note's Lagrangian relaxation. A new paragraph states `b[1:K]` ARE the only binary/integer variables in `src/planning/` today, citing `master_integer.jl`, `test/test_planning_master_integer.jl`, and `test/test_planning_nash_integer.jl`. The "Resumo de desvios deliberados" bullet is rewritten to match.
- **The "Equilíbrio de Nash multi-distribuidor" section** gains: (a) a GNE-multiplicity paragraph citing the interior-cap continuum fixture (`test/test_planning_nash.jl`) and the extended `run_nash_probe` seed mechanism (`(;z0,x_inv0)`); (b) a new "Seleção do equilíbrio variacional" subsection documenting `solve_variational_equilibrium`'s monolithic-joint-solve design and no-profitable-deviation certification; (c) a short note on `run_nash!`'s `integer` kwarg (BILEV-07) citing `test/test_planning_nash_integer.jl`.
- **`modelo_stackelberg_dso_unico.typ`** gains a new "Taxonomia dos variantes de planejamento" section (table: `solve_stackelberg!` / `solve_bilevel!` / `run_nash!`+`solve_variational_equilibrium`, each row citing its backing function AND test file), plus notes that `BendersMasterInteger` is usable via `master=` in both the Benders and Nash rows, and that the Phase-30 `inexact_policy` applies to all three. The stale "Sem variáveis binárias em lugar algum" implementation bullet is corrected to state continuous investment is the default with `BendersMasterInteger` available via `master=`.
- **Three Documenter docstrings cross-referenced:** `solve_stackelberg!`'s "Honest relabelling" paragraph now points to `run_nash!`/`solve_variational_equilibrium` for the N>1 case and the new taxonomy doc; its `master=` paragraph now notes `BendersMasterInteger`'s own `bounds_ctx`/`lb_slack`/`lb_clamped` validation (plans 31-02/31-07). `solve_bilevel!` gains a taxonomy cross-reference naming `modelo_stackelberg_dso_unico.typ`. `run_nash!` gains a GNE-multiplicity caveat and a pointer to `solve_variational_equilibrium` (its own docstring already used the matching `# Algorithm`/`# Returns`/`# Throws` heading convention — no amendment needed there).
- `docs/src/api.md`'s Planning Layer `@autodocs` `Pages` list now includes `"planning/bilevel_kkt.jl"` (previously entirely undocumented in Documenter).
- Every function/test name cited in new/changed prose was independently grep-confirmed to exist in `src/`/`test/` before being cited (see Verification below).

## Task Commits

Each task was committed atomically:

1. **Task 1: Refresh both .typ writeups + compile** - `28c6eb6` (docs)
2. **Task 2: Documenter docstring cross-references** - `67d6af4` (docs)
3. **Task 3: Human read-through checkpoint** - approved ("approved"); no code commit (checkpoint-only task)
4. **Post-checkpoint: commit refreshed PDFs (user decision, force-added)** - `13229fe` (docs)

**Plan metadata:** this commit (SUMMARY + STATE/ROADMAP update)

## Files Created/Modified

- `docs/writeups/stackelberg_vs_psr_n1n2.typ` - integer-extension table/prose rewritten; Nash section extended (GNE-multiplicity paragraph, VE subsection, integer-N>1 note); "Resumo de desvios deliberados" bullet fixed
- `docs/writeups/modelo_stackelberg_dso_unico.typ` - new "Taxonomia dos variantes de planejamento" section; "Notas de implementação" bullet fixed
- `docs/writeups/stackelberg_vs_psr_n1n2.pdf`, `docs/writeups/modelo_stackelberg_dso_unico.pdf` - recompiled, force-added per user decision (see Deviations)
- `src/planning/benders.jl` - `solve_stackelberg!`'s docstring: "Honest relabelling" paragraph + `master=` paragraph extended (docstring-only, no behavior change)
- `src/planning/bilevel_kkt.jl` - `solve_bilevel!`'s docstring: taxonomy cross-reference added (docstring-only)
- `src/planning/nash.jl` - `run_nash!`'s docstring: GNE-multiplicity caveat + `solve_variational_equilibrium` pointer added (docstring-only)
- `docs/src/api.md` - `planning/bilevel_kkt.jl` added to the Planning Layer `@autodocs` `Pages` list

## Decisions Made

See `key-decisions` in frontmatter: the integer-extension deviation is documented as TWO independent deviations (target variable AND recourse mechanism), not conflated into one; the PDF force-add is a user decision made during the checkpoint, overriding this plan's own Task 1 deviation note (which had followed the pre-existing `.gitignore` convention and left the PDFs uncommitted).

## Deviations from Plan

### Auto-fixed / Adjusted Issues

**1. [Rule 4-adjacent — pre-existing repo convention conflicts with plan instruction] PDFs are gitignored project-wide, contrary to the plan's "commit alongside sources" assumption**

- **Found during:** Task 1, immediately before the first commit.
- **Issue:** The plan's `<action>` states "Commit both refreshed `.pdf` outputs alongside the `.typ` sources (the project's existing convention...)". Direct inspection showed `.gitignore` line 43 explicitly ignores `/docs/writeups/*.pdf` with the comment "Authored writeups: track the Typst source, ignore the compiled PDF (regenerable via `typst compile`)" — applied uniformly to EVERY writeup in that directory (`compare_default_stochastic.pdf`, `ieee8500_exatidao_socp.pdf`, `thesis_caseA.pdf` are likewise present on disk but untracked). The plan's premise was stale/incorrect.
- **Action taken (Task 1):** Recompiled both PDFs in place for the human-verify checkpoint, but committed only the `.typ` sources — followed the repo's actual, deliberate convention rather than the plan's stale assumption, and documented the conflict explicitly in the Task 1 commit message.
- **Resolution (post-checkpoint, this session):** the coordinator relayed an explicit user decision made during the checkpoint review to force-add these two PDFs anyway (`git add -f`), committed separately (`13229fe`) from the `.typ` source commit, with `.gitignore` itself left untouched (a one-off override, not a convention change).
- **Files modified:** `docs/writeups/stackelberg_vs_psr_n1n2.pdf`, `docs/writeups/modelo_stackelberg_dso_unico.pdf`.
- **Committed in:** `28c6eb6` (note only, no PDF), `13229fe` (PDFs, force-added).

---

**Total deviations:** 1 (a pre-existing repo-convention conflict with the plan's own stale instruction, resolved by an explicit user decision during the checkpoint).
**Impact on plan:** No impact on the writeups' content or correctness — purely a version-control-tracking question, now resolved per explicit user direction.

## Issues Encountered

None beyond the PDF-tracking deviation above. Both `typst compile` invocations exited 0 on first attempt for both files; the `JULIA_LOAD_PATH="test:.:@stdlib" julia -e 'using TSODSO'` load check (mandatory for the docstring-only `.jl` edits) passed cleanly.

## Checkpoint Record

**Task 3 (human-verify checkpoint): APPROVED-PENDING-LATER-READ.** The user responded "approved" to unblock the plan's completion, but explicitly deferred the actual prose read-through of the two PDFs to a later time, raising any issues separately if found. This is recorded here as `approved-pending-later-read`, NOT as a completed, confirmed-accurate read — if the user's later read surfaces a narrative-accuracy issue in either writeup, it should be filed as a follow-up fix against this plan's own deliverables, not treated as a regression introduced elsewhere.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- BILEV-08 is complete: both writeups and all three entry-point docstrings accurately state the game-theoretic taxonomy, every claim citing a backing function and test file, with the stale "not implemented" claims removed.
- Phase 31's full scope (BILEV-06, BILEV-07, BILEV-08) is now complete across plans 31-01 through 31-07 (31-06 was folded/not separately needed — see phase tracking).
- The checkpoint's prose read-through remains open (`approved-pending-later-read`) — a lightweight follow-up item, not a blocker, since every citation was independently grep-verified and both documents compile cleanly.
- No blockers for downstream work.

---
*Phase: 31-gne-nash-fixture-integer-n-1-planning-docs-refresh*
*Completed: 2026-10-02*

## Self-Check: PASSED

- FOUND: docs/writeups/stackelberg_vs_psr_n1n2.typ
- FOUND: docs/writeups/modelo_stackelberg_dso_unico.typ
- FOUND: docs/writeups/stackelberg_vs_psr_n1n2.pdf
- FOUND: docs/writeups/modelo_stackelberg_dso_unico.pdf
- FOUND: src/planning/benders.jl
- FOUND: src/planning/bilevel_kkt.jl
- FOUND: src/planning/nash.jl
- FOUND: docs/src/api.md
- FOUND commit: 28c6eb6
- FOUND commit: 67d6af4
- FOUND commit: 13229fe

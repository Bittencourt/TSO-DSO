---
phase: quick-261107-qzn
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - src/powerflow/ConvexBranchFlow.jl
  - src/models/ac_oracle.jl
  - src/models/restriction_exactness.jl
  - docs/literate/convex_branch_flow.jl
  - docs/literate/ac_oracle.jl
  - docs/literate/restricted_branch_flow.jl
  - docs/src/index.md
  - docs/writeups/FRAMEWORK_GUIDE.html
  - test/test_convex_branch_flow.jl
  - test/test_ac_oracle.jl
  - scripts/pv_boom_case_study.jl
  - results/pv_boom/findings.txt
  - .planning/PROJECT.md
  - .planning/todos/pending/2026-10-07-linDistFlow-copy-vmax-bound-breaks-relaxation-under-reverse-flow.md
  - .planning/todos/completed/2026-10-07-linDistFlow-copy-vmax-bound-breaks-relaxation-under-reverse-flow.md
autonomous: true
requirements: [QUICK-261107-qzn]
must_haves:
  truths:
    - "Every doc/comment site describes the default copy (v̂ ≤ vmax², eq. 3.45) as a per-branch inner approximation, not Gan-Low OPF-m and not exact by theorem"
    - "No code line, golden, tolerance, fence, CSV number or runtime string changed"
    - "check_planning_ids still reports 354 hits"
    - "Targeted tests pass; only results/pv_boom/findings.txt changed under results/, prose only"
    - "The 2026-10-07 todo lives in .planning/todos/completed/ with a resolution note"
  artifacts:
    - path: ".planning/todos/completed/2026-10-07-linDistFlow-copy-vmax-bound-breaks-relaxation-under-reverse-flow.md"
      provides: "resolved todo"
  key_links:
    - from: "new wording"
      to: ".planning/debug/lindistflow-vmax-reverse-flow.md"
      via: "evidence (c) site list and root_cause/option A facts"
---

<objective>
Re-document the default ConvexBranchFlow exactness copy as a per-branch inner approximation (researcher's "Option A"). Docs, comments and docstrings only. No behaviour change.

Output: corrected wording at every site in the debug session's evidence (c), a prose-only findings.txt edit, and the todo closed.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@CLAUDE.md
@.planning/debug/lindistflow-vmax-reverse-flow.md
@.planning/todos/pending/2026-10-07-linDistFlow-copy-vmax-bound-breaks-relaxation-under-reverse-flow.md

<facts>
Use these exact facts in the new wording (do not re-derive):
- Identity: the default copy satisfies v̂ − v = Σ_{b∈path(j)} (r_b²+x_b²)·l_b ≥ 0 (coefficient 1, not 2). So v̂ ≤ vmax² enforces v ≤ vmax² − Σ_path |z|²l: an inner restriction of the upper voltage band that grows with accumulated path losses.
- Not Gan-Low: OPF-m uses the lossless shadow voltage v̂_GL(s), implemented as RestrictedBranchFlow / recover_lossfree_shadow_voltage. Each branch's copy removes only that branch's own loss, so v̂ at a bus decreases with downstream branch currents. The Gan-Low exactness theorem therefore does not apply beyond single-branch paths.
- 3-bus high-PV stress fixture: pv_scale 1.2 cone tight but welfare −921.754 vs AC −921.277 (keep this number). pv_scale >= 1.3 default is cone-inexact (gap 0.22 to 7.95) and refused by the exactness gate. So the default is neither a relaxation of AC nor exactness-guaranteeing in general; the gate catches inexact cases, no silent wrong prices.
- Realistic fixtures unaffected: IEEE-13 seed 7, IEEE-13 PV-boom sweep (pv_mult 0 to 4.0), IEEE-123 seed 7: bound never active (dual <= 6.7e-7, min slack >= 3.1e-3).
- pv_boom residual −9.73e-6 after deleting the bound is solver tolerance: Ipopt bound_relax_factor 6.10e-6 + Clarabel tol_gap 3.63e-6. With both tight, the bound-free SOCP is a true relaxation on that fixture (+2.6e-9, 0 inexact hours).
- Sign: since the copy-direction change the default has v̂ >= v (asserted in test/test_convex_branch_flow.jl). Any docstring calling the project's copy a lower-bound shadow (v >= v̂) is stale.
</facts>

Hard rules:
- Planning-ID guard: new text must NOT contain "Phase NN", "P26", "v4.0 P26", plan/wave/review/quick IDs. Say "the copy-direction change". Gate `python3 .github/scripts/check_planning_ids.py` must print "FAIL: 354 hit(s), 0 stale" (baseline; expected).
- Only comment/docstring/markdown/prose lines. In .jl files never touch code lines (Literate pages execute at docs build). If a runtime string (message, verdict label, CSV value) would need changing, leave it and list it in the SUMMARY as out of scope.
- Leave alone: generic "SOCP relaxation must be validated exact" in CLAUDE.md and PROJECT.md Constraints; "SOC relaxation" meaning cone 3.39 alone.
- Verify each site by reading it; fix only what is actually wrong. Sequential on main tree; no worktrees/branches/checkout/reset/stash.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; message prefix `docs(quick-261107-qzn):`.
</context>

<tasks>

<task type="auto">
  <name>Task 1: Fix source, test-comment and Julia-literate sites</name>
  <files>src/powerflow/ConvexBranchFlow.jl, src/models/ac_oracle.jl, src/models/restriction_exactness.jl, test/test_convex_branch_flow.jl, test/test_ac_oracle.jl, docs/literate/convex_branch_flow.jl, docs/literate/ac_oracle.jl, docs/literate/restricted_branch_flow.jl</files>
  <action>
Read evidence entry (c) (11:15) and the Resolution in the debug file, then edit comments/docstrings only:
1. ConvexBranchFlow.jl: header (~l.17-35), type docstring (~l.83-86, 99-104, 119-127), constructor docstring (~l.143-152), bound comment (~l.215-222, drop "drives the cone tight"). State the identity, inner-approximation reading, not-Gan-Low (point to RestrictedBranchFlow for OPF-m), not exact by theorem, gate catches inexact cases, v̂ >= v sign.
2. ac_oracle.jl: fix recover_lossfree_shadow_voltage docstring sign (~l.125-131); assert_ac_exact! docstring (~l.266/281) stop calling obj_gap "relaxed vs true" for the default (describe as comparison against AC / bound-free relaxation as appropriate).
3. restriction_exactness.jl (~l.196-206): fix comments/docstrings treating the default as the "unrestricted relaxation's" upper bound. Runtime verdict/message strings stay unchanged; record any such string needing change for the SUMMARY.
4. docs/literate/convex_branch_flow.jl: title "Overvoltage-Capable Relaxation" and ~l.271-273, 314-316, 341-343; ac_oracle.jl l.1-8 framing; restricted_branch_flow.jl corresponding framing. Only `#` comment / markdown lines. If the title is inside a `# #` markdown header it may change; if it appears in code strings, leave it and note it.
5. test/*.jl: comments only (test_convex_branch_flow.jl ~l.98-104; test_ac_oracle.jl). Assertions untouched.
Grep tests (`grep -rn` on key docstring phrases you change, in test/ and docs/make.jl) to confirm none matches docstring text; if one does, keep that text intact.
Then format touched .jl files only: `julia --project=. .github/scripts/format210.jl <files>`; run `python3 .github/scripts/check_content_loss.py HEAD`; run `git diff` to confirm only comment/docstring lines changed in src/ and test/. Commit docs changes `docs(quick-261107-qzn): re-document default copy as inner approximation (src, tests, literate)`; if the formatter changed anything beyond the edits, commit that separately as `style(quick-261107-qzn): ...`.
  </action>
  <verify>
    <automated>cd /home/pedro/programming/TSO-DSO && TSODSO_TEST_SET=all TSODSO_TEST_FILES=test_convex_branch_flow.jl,test_ac_oracle.jl,test_restricted_branch_flow.jl julia --project=. -e 'import Pkg; Pkg.test()' && git checkout -- test/Project.toml test/Manifest.toml && python3 .github/scripts/check_planning_ids.py | tail -1</automated>
  </verify>
  <done>Targeted tests pass; planning-ids line reads "FAIL: 354 hit(s), 0 stale"; test/Project.toml and Manifest.toml restored; src/test diffs are comment/docstring-only; no stale "Gan-Low modified OPF" / "exact by theorem" / "v >= v̂ lower-bound shadow" claim remains at these sites.</done>
</task>

<task type="auto">
  <name>Task 2: Fix markdown/HTML docs, pv_boom narrative, findings.txt, PROJECT.md</name>
  <files>docs/src/index.md, docs/writeups/FRAMEWORK_GUIDE.html, scripts/pv_boom_case_study.jl, results/pv_boom/findings.txt, .planning/PROJECT.md</files>
  <action>
1. docs/src/index.md (~l.35-38, 94-97) and docs/writeups/FRAMEWORK_GUIDE.html §5.1 and §6: apply the facts wording to prose only (HTML: text nodes only, keep markup/ids). Check `git ls-files docs/src/generated`; it is empty/untracked, so leave generated output alone.
2. scripts/pv_boom_case_study.jl Part A2: edit only printed narrative strings (prose inside println/@info text), no numeric formatting, no code logic. Replace "UNRESOLVED"/"not diagnosed" with the explanation: the gap is by design (the restriction) and the residual −9.73e-6 is solver tolerance (Ipopt bound_relax_factor 6.10e-6 + Clarabel tol_gap 3.63e-6; bound-free SOCP true relaxation, +2.6e-9, 0 inexact hours). Do NOT re-run the script.
3. results/pv_boom/findings.txt Part A2: hand-edit the same prose; every number stays byte-identical. Confirm with `git diff --word-diff -- results/pv_boom/findings.txt` (prose only) and `git diff --stat -- results/` (only that file).
4. .planning/PROJECT.md: ~l.402-404, plus l.64 and l.503 only if they describe the default copy (line numbers may have shifted; grep "3.45\|exactness copy\|vmax"). Leave Constraints text. No planning IDs in new text.
Run the format step for scripts/pv_boom_case_study.jl (`julia --project=. .github/scripts/format210.jl scripts/pv_boom_case_study.jl`), then `python3 .github/scripts/check_content_loss.py HEAD`. Commit `docs(quick-261107-qzn): re-document default copy in guides, pv_boom narrative, PROJECT.md`; separate `style(quick-261107-qzn)` commit if formatter changed anything.
  </action>
  <verify>
    <automated>cd /home/pedro/programming/TSO-DSO && git diff HEAD~1 --stat -- results/ | tail -3 && python3 .github/scripts/check_planning_ids.py | tail -1 && julia --project=. -e 'Meta.parseall(read("scripts/pv_boom_case_study.jl", String)); println("parse ok")'</automated>
  </verify>
  <done>Only results/pv_boom/findings.txt differs under results/, prose-only word-diff; planning-ids still 354; script parses; guides/PROJECT.md no longer claim Gan-Low/exact-by-theorem for the default.</done>
</task>

<task type="auto">
  <name>Task 3: Close the 2026-10-07 todo</name>
  <files>.planning/todos/pending/2026-10-07-linDistFlow-copy-vmax-bound-breaks-relaxation-under-reverse-flow.md, .planning/todos/completed/2026-10-07-linDistFlow-copy-vmax-bound-breaks-relaxation-under-reverse-flow.md</files>
  <action>
`mkdir -p .planning/todos/completed` and `git mv` the todo from pending/ to completed/. Append a short "Resolution" section: resolved by re-documentation (Option A) per the debug session `.planning/debug/lindistflow-vmax-reverse-flow.md`; default copy is a per-branch inner approximation, gate refuses inexact cases, no behaviour change; residual was solver tolerance. Do not add the quick ID inside any file scanned by check_planning_ids (todo path under .planning is fine, but re-run the gate to confirm 354). Commit `docs(quick-261107-qzn): close vmax-bound reverse-flow todo` with the trailer.
  </action>
  <verify>
    <automated>cd /home/pedro/programming/TSO-DSO && test -f .planning/todos/completed/2026-10-07-linDistFlow-copy-vmax-bound-breaks-relaxation-under-reverse-flow.md && test ! -f .planning/todos/pending/2026-10-07-linDistFlow-copy-vmax-bound-breaks-relaxation-under-reverse-flow.md && python3 .github/scripts/check_planning_ids.py | tail -1</automated>
  </verify>
  <done>Todo is in completed/ with a resolution note; gate still 354.</done>
</task>

</tasks>

<verification>
- Targeted tests pass (Task 1 command); test/Project.toml and test/Manifest.toml restored.
- `git diff --stat -- results/` shows only findings.txt; word-diff shows prose only.
- check_planning_ids: "FAIL: 354 hit(s), 0 stale".
- SUMMARY lists any runtime strings left unchanged as out of scope. Docs build is run by the orchestrator, not here.
</verification>

<success_criteria>
All evidence-(c) sites carry the inner-approximation wording; zero behaviour change; todo closed; commits atomic with required prefix and trailer.
</success_criteria>

<output>
Create `.planning/quick/261107-qzn-re-document-default-convexbranchflow-exa/261107-qzn-SUMMARY.md` when done
</output>

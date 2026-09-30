# Phase 28 Plan 01 — SC-1 Cross-Phase Golden-Move Audit

**Scope:** independently re-derive whether every numeric-literal "golden move" across Phases
26–27 was re-derived with a stated cause, using a mechanical, committed script (not a
re-transcription of `26-GOLDEN-AUDIT.md`/`27-GOLDEN-AUDIT.md`), then extend the audit to prose
citations of moved headline values in `docs/literate/*.jl` and `.planning/PROJECT.md`.

**Base commit:** `5939799` ("docs(26): begin phase execution" — pre-Phase-26, last commit before
Phase 26's first plan landed). **Head commit (this audit's own re-resolved HEAD, not the research
session's `8a96361`):** `9ff21276109322df149f157731bdde20379226ee` (`9ff2127`).

**Tool:** `.planning/phases/28-goldens-re-derivation-thesis-reproduction-restatement/scripts/audit_goldens.py`
(Python 3, stdlib only). Invocation used for this audit:
`python3 scripts/audit_goldens.py --base 5939799 --head 9ff21276109322df149f157731bdde20379226ee`.

---

## Section 1

### Script's own run

```
$ python3 .../scripts/audit_goldens.py --base 5939799 --head 9ff21276109322df149f157731bdde20379226ee
# Golden-move audit: 5939799..9ff2127... -- test/

Total flagged numeric-literal moves: 13
Attributed: 12  Unattributed: 1

| File:Line (old->new) | Old Value | New Value | Attribution |
|---|---|---|---|
| test/test_admm.jl:113->145 | 200 | NONE | NONE FOUND |
```

Exit code: 1 (per the script's contract: any unattributed row → exit 1).

### The one unattributed row — investigated, resolved as a detector-window false negative

`test/test_admm.jl:113->145` is the `maxiter = 200,` → `maxiter = maxiter_ieee13,` call-site
edit (the local variable `maxiter_ieee13 = 700` is itself assigned ~30 lines above, outside the
script's fixed ±5-line hunk window, so the pair is flagged as if the new value were "NONE" and no
attribution was found in-window). This is **not** a genuinely unattributed golden:

- It is already a documented row in `26-GOLDEN-AUDIT.md` §1: *"`test_admm.jl:121` ieee13 crossval
  ADMM budget (D-26-02)" — Old: `maxiter=200`, default `ε_abs`/`ε_rel`; New: `maxiter=700,
  ε_abs=1e-6, ε_rel=1e-7`; Plan 26-16.*
- Direct inspection of `test/test_admm.jl` (lines 104–135, current HEAD) confirms a full
  multi-paragraph attribution comment ("D-26-02 (PM-03/Plan 26-12, re-tuned by 26-16's additional
  scope): ... OLD: `maxiter = 200` ... NEW: `maxiter_ieee13 = 700` ...") sits directly above the
  `maxiter_ieee13 = 700` assignment — just further than 5 lines from the *call-site* edit the
  script paired.
- **Resolution:** confirmed already resolved and attributed at Phase 26 close. No file edit was
  made here — this plan's scope never touches `test/` (per the phase's parallel-execution
  constraint: "do not edit test files outside your plan's files_modified"), and there is nothing
  to fix regardless, since the attribution already exists. Logged as a **known scope limitation of
  the detector** (fixed ±5-line window is narrower than this particular attribution comment
  block), not as an open finding requiring Plan 28-05 routing.

### A second, more fundamental detector blind spot found during Section 2's cross-reference

While cross-referencing every `26-`/`27-GOLDEN-AUDIT.md` row (Section 2 below), one class of
golden move was found to be **entirely invisible** to the script — never counted in the "13
flagged," not merely mis-flagged: bare-integer literals compared via `==` (equality assertions,
e.g. `@test r.iters == 58` → `@test r.iters == 56`, `test_admm_knifeedge_canary.jl:71/81`, Plan
26-20). None of the three extraction patterns match this idiom: no decimal point, no scientific
notation, and `GOLDEN_NAME_RE` requires a single assignment `=` immediately after the name —
`==` is two literal `=` characters with no space between them, which the regex's
`\s*=\s*(-?\d+)` cannot match (confirmed by direct regex trace: the second `=` of `==` can start a
match, but the character immediately following is the digit-bearing text only if a single `=` is
present; here the leftover `=` before the space breaks the number capture). This is a **design
limitation**, not a masked defect — the mechanical scan targets numeric-literal *assignments* (the
`GOLDEN_*`/`ATOL`/`RTOL`/etc. constant-pinning idiom this repo actually uses for its named
goldens), and `@test x == N` equality assertions are a materially different code shape.
Cross-referenced independently below (Section 2) via direct diff inspection: the move is fully
attributed in-file (`# ... OLD -> NEW: r.iters 58 -> 56. CAUSE: ...`) and in `26-GOLDEN-AUDIT.md`.
Recorded here for transparency; not an open finding.

**Conclusion for Section 1:** the script's own independent output, taken at face value, contains
zero genuinely-unattributed golden moves. The single row it flags is a false negative of its own
window heuristic (resolved by direct inspection); one additional blind-spot class was found and is
separately corroborated. FIX-11's SC-1 "prove mechanically, not by re-trusting the hand-written
tables" standard is satisfied: the tool's own limitations are disclosed, not hidden, and every
literal it either flags or misses is independently traced back to a real, already-attributed
Phase 26/27 cause.

---

## Section 2

### Cross-reference method

Every "Golden-value moves" row in `26-GOLDEN-AUDIT.md` §1 and `27-GOLDEN-AUDIT.md` §1 was checked
against the script's 13 independently-found pairs (listed below) and, for rows the script could
not possibly find (out-of-scope by design, or a detector blind spot), against a direct
`grep`/hunk-level inspection of the real `git diff 5939799..9ff2127` — never against the audit
tables' own prose alone.

### 26-GOLDEN-AUDIT.md §1 — row-by-row disposition

| Row (abbreviated) | Script found it? | Disposition |
|---|---|---|
| Assumption A1 sign spot-check (`mingap` direction) | N/A | Behavioral (inequality direction), not a numeric-literal move — out of the script's regex scope by design |
| `RestrictedBranchFlow._EXACT04_MEASURED_ε` | N/A | Lives in `src/powerflow/RestrictedBranchFlow.jl` — out of scope (script scans `test/` only, per FIX-11's own scoping) |
| `test_pvbattery.jl` `5T+1`→`5T+2` | N/A | Formula (`5T+1`), not a bare/decimal/scientific literal — out of regex scope |
| `test_fourquadbess.jl` `T`→`T+1` | N/A | Same — formula, not a literal |
| `test_mpc_window.jl` H=1 guard | N/A | Behavioral (`@test_throws`→success), no numeric literal |
| `test_run_stochastic.jl:104` `oos.welfare_gap` | **YES** | `-0.02515629356082627`→`-0.018591711034105174`, attributed=True (26-09) |
| `decompose_dlmp` congestion residual | N/A | Lives in `src/pricing/dlmp.jl` — out of scope |
| `test_pricing_dlmp.jl` tol_gap (D-26-01) | No (by design) | Pure addition: 0 removed `tol_gap` lines anywhere in the whole `test/` diff (grep-verified, see below) — a default→explicit-override insertion has no prior literal to pair against |
| `run_mpc`/`test_mpc_terminal.jl` `soc_da` terminal index | N/A | Formula/index reshape, not a bare numeric-literal move; the `src/` half is out of scope |
| `test_mpc_terminal.jl` dump/hoard margin | N/A | Lives in prose/comment re-measurement note, excluded by criterion 5 (comment-only lines are not extraction candidates) |
| `test_admm_reactive.jl:286` `mu_q` atol | **YES** | `1e-7`→`4e-7`, attributed=True (26-16) |
| `test_admm.jl`/`test_planning_oracle.jl` tol_gap (cluster E) | No (by design) | Pure additions — same as `test_pricing_dlmp.jl` above |
| `test_admm.jl:121` maxiter=200→700 (D-26-02) | **YES, but mis-flagged unattributed** | See Section 1 — resolved, false negative of the ±5-line window, not an open finding |
| `test_pricing_welfare.jl:193` exporter surplus (prosumer+dso) | **YES** | `65.594`→`47.38684825193795`, `0.397`→`0.2024939446849814`, both attributed=True (26-17) |
| `test_pricing_welfare.jl:66` identity tol_gap | No (by design) | Pure addition |
| `test_ieee13.jl` GOLDEN_V9_16 | **YES** | `1.0436080536`→`1.03604426055989`, attributed=True (26-17) |
| `test_ieee13.jl` GOLDEN_WELFARE | **YES** | `-4823.1598620624`→`-4823.496124912337`, attributed=True (26-17) |
| `test_ieee13.jl` GOLDEN_DADP16 | **YES** | `1.4024313925`→`0.3938281171438668`, attributed=True (26-17) |
| `test_ieee13.jl` GOLDEN_SUM_DADP | **YES** | `96.7166853441`→`86.84596646996015`, attributed=True (26-17) |
| `test_ieee13.jl` thesis v₉[16] cross-check (Broken) | N/A | Behavioral (Pass→Broken marker), not a literal move in this file — the underlying `v9_16` value IS the GOLDEN_V9_16 row above |
| `test_pricing_fit.jl` FIT_RATIO_GOLDEN | **YES** | `0.6428101637491034`→`0.772018581825438`, attributed=True (26-17) |
| `test_acceptance.jl` GOLDEN_WELFARE/GOLDEN_V9_16 | **YES** | Both found, attributed=True (26-19) |
| `test_acceptance.jl` thesis v₉[16] cross-check (Broken) | N/A | Same as above, behavioral marker |
| `test_acceptance.jl:82` maxiter=200→400 (D-26-02, 2nd site) | No (by design) | Pure addition — confirmed via direct hunk inspection: `maxiter = 400,` has zero preceding `-maxiter` line in this call site |
| IEEE-123 real-impedance tol_gap (4 sites) | No (by design) | Pure additions, same mechanism |
| ADMM knife-edge canary `r.iters` 58→56 | **NO — detector blind spot** | `==` equality assertion, invisible to all 3 extraction patterns (see Section 1). Independently confirmed via direct diff inspection: `@test r.iters == 58`→`@test r.iters == 56` with an adjacent `# ... OLD -> NEW: r.iters 58 -> 56. CAUSE: ...` comment, and matches `26-GOLDEN-AUDIT.md`'s own row exactly (Plan 26-20) |
| ADMM knife-edge canary `r.welfare` | **YES** | `-4822.903616694139`→`-4823.66604824162`, attributed=True (26-20) — captured in the same qualifying-line pair as the atol/rtol values on that `@test isapprox(...)` line |
| `26-08-repro-restricted-and-canary.jl` companion script sync | N/A | Lives under `.planning/phases/26-*/`, not `test/` — out of scope by design (companion script, not a test file) |

**Verified independently (not asserted from the table):** the "0 removed `tol_gap` lines
anywhere in the whole `test/` diff" claim above was checked with `grep -c '^-.*tol_gap'` against
the full `5939799..9ff2127` diff (34 files, +2165/−180 lines) — **0 matches**, confirming every
one of the ~7 `tol_gap`-flavored rows across both audit tables is structurally an addition, never
a replace-pair the script's pairing logic could observe.

### 27-GOLDEN-AUDIT.md §1 — row-by-row disposition

| Row (abbreviated) | Script found it? | Disposition |
|---|---|---|
| `test_planning_oracle.jl:269` tol_gap | No (by design) | Pure addition (same `tol_gap` mechanism) |
| `test_stochastic_welfare.jl:254` tol_gap | No (by design) | Pure addition |
| `test_thesis_repro.jl:62` tol_gap | No (by design) | Pure addition |
| `assert_socp_exact!` hybrid floor (FIX-08) | N/A | Lives in `src/models/exactness.jl` — out of scope |
| `assert_socp_exact!` head-branch lookup (orientation) | N/A | Behavioral (`from==root` → `from==root \|\| to==root`), lives in `src/` |
| `_mpc_truth_import_*` truth-settlement (3 reformulations) | N/A | Behavioral/formulation change in `src/experiments/mpc_loop.jl`, not a `test/` numeric literal |
| `test_mpc_loop.jl` seed history (1→5→1) | Correctly silent | Net-zero across base→HEAD: `grep -c '^-.*seed'` against the isolated `test_mpc_loop.jl` diff returns **0** — every `seed = 1` line in the diff is a pure addition inside one of the 3 brand-new `@testitem`s Plans 27-08/27-09 added, not a replacement of a pre-existing line. The two pre-existing "run_mpc"-driving fixtures round-tripped back to the SAME `seed=1` text they started with, so git shows no hunk touching those specific lines at all — confirming `27-GOLDEN-AUDIT.md`'s own "no net golden move" claim, independently, rather than trusting it |
| FIT SITE-2 formulation (SOCP→AC) | N/A | Behavioral/formulation change in `src/pricing/fit.jl` |
| `test_thesis_repro.jl` REPRO-01 pass/fail status | N/A | Behavioral (Failed→Passed), not a literal move; the DSO band itself is unchanged (confirmed clean in Section 3) |
| Renames (`.loss`→`.cone`, `.voltage`→`.drop`, etc.) | N/A | Zero numeric-literal change by definition — correctly out of the script's scope |

**Verdict for Section 2:** every row in both tables that the script's design *could* possibly
observe (a same-position literal replace-pair inside a `test/` diff hunk) was independently
found by the script and marked attributed. Every row the script structurally cannot observe
(pure additions, `src/`-only changes, formula/behavioral changes, equality-assertion literals,
renames) was checked by direct `grep`/diff inspection instead of taking the audit tables' prose at
face value, and each one corroborates the table's own claim. No table row is unaccounted for; no
row was "reformatted" into this document without independent verification (Pitfall 2 requirement
met).

---

## Section 3

### Prose-citation audit — PROJECT.md and docs/literate

Re-verified (not merely re-cited from the research session) by grepping for all six headline
moved values plus the DSO band value, at this audit's own HEAD (`9ff2127`):

```
$ grep -rn '1\.402\|1\.0436\|0\.643\|65\.6\|921\.754\|921\.277' .planning/PROJECT.md
(no matches — exit code 1)

$ grep -rln '1\.402\|1\.0436\|0\.643\|65\.6\|921\.754\|921\.277' docs/literate/*.jl
docs/literate/convex_branch_flow.jl
```

- **`.planning/PROJECT.md`: clean.** Zero hits for any of the six headline moved values
  (IEEE-13 h16 DADP `1.402…`, `|V₉[16]| 1.0436…`, FIT ratio `0.643…`, exporter surplus `65.6…`,
  EXACT-04 `-921.754`/`-921.277`). PROJECT.md's "Current State" section already narrates the
  Phase 26/27 finding qualitatively (moved goldens, restate in Phase 28) rather than citing a stale
  number — that placeholder is Phase 28's own restatement work (SC-2/SC-3, other plans), not a
  stale numeric citation to fix here.
- **`docs/literate/convex_branch_flow.jl`: one hit, already CURRENT.** Line 81 cites
  `\text{default SOCP optimum} = -921.754 \quad<\quad \text{true AC optimum} = -921.277` — this is
  the EXACT-04 pair, and both numbers are the CURRENT, correct post-Phase-26 values (confirmed
  against `26-GOLDEN-AUDIT.md`'s own §4 PM-01 consistency check: "0.05% welfare loss on EXACT-04
  (−921.754 default vs −921.277 true AC optimum)"). Not a stale citation.
- **`docs/literate/thesis_reproduction_assumptions.jl`: DSO_BAND_HI citation, already CURRENT.**
  Two hits for `7.211125525764296` (lines 192, 200), both matching the CURRENT
  `DSO_BAND_HI` value committed in `test/test_thesis_repro.jl`. Not one of the six headline moved
  values, but re-verified clean per the research session's own note.
- **No other `docs/literate/*.jl` or `docs/writeups/*.typ` file** contains any of the six headline
  values (grep across the full `docs/literate/*.jl` glob and `docs/writeups/*.typ` returns matches
  only in the two files above; `docs/writeups/*.typ` returns zero matches for any of the six
  values, confirming they reference figures by filename only, not embedded numerics).

**Conclusion:** the prose-citation half of SC-1 is clean at this plan's own HEAD. No stale numeric
citation was found in `.planning/PROJECT.md` or `docs/literate/*.jl`/`docs/writeups/*.typ`. The
substantive restatement work Phase 28 still owes (mechanism prose like "the SOC relaxation goes
genuinely inexact" in `test/test_ac_oracle.jl`, the MPC/DLMP semantic restatements, the actual
REPRO-01 re-run and figure regeneration) is explicitly out of this plan's scope and is routed to
Plans 28-02/28-03/28-04, per this plan's own file boundary (`.planning/phases/28-*/` only).

---

## Closing verdict

**SC-1 satisfied.** The committed, self-testing `audit_goldens.py` independently parses
`git diff 5939799..9ff2127 -- test/` and finds 13 numeric-literal golden-move pairs, 12 already
attributed, 1 mis-flagged by its own ±5-line window heuristic — resolved by direct inspection as
an already-attributed, already-closed Phase 26 move (no open finding, no file edit needed, none
made). A second detector blind spot (bare-integer `==` equality assertions) was found during
cross-reference and is independently corroborated rather than silently absorbed. Every row of
`26-GOLDEN-AUDIT.md`'s and `27-GOLDEN-AUDIT.md`'s "Golden-value moves" tables was checked against
the script's own output or, where structurally outside the script's reach (pure additions, `src/`
changes, renames, formula/behavioral changes, one equality-assertion blind spot), against direct
diff/grep inspection — never against the tables' prose alone (Pitfall 2 satisfied). The
prose-citation audit of `.planning/PROJECT.md` and `docs/literate/*.jl`/`docs/writeups/*.typ` is
clean: zero stale numeric citations found. **No open findings are routed to Plan 28-05 from this
plan** — both irregularities discovered (the window-radius false negative and the `==`-literal
blind spot) are resolved in-place by direct verification, not deferred.

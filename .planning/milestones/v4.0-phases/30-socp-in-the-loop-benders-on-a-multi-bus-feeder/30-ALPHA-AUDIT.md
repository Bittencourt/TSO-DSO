# Phase 30, Plan 30-02 (BILEV-05): Repo-Wide T>1 α_op_lb/α_x_lb Audit

**Run:** 2026-10-01
**Script:** `scripts/audit_alpha_bounds.jl` (run from this phase directory via
`JULIA_LOAD_PATH="../../../test:../../../:@stdlib" julia scripts/audit_alpha_bounds.jl`)
**Exit code:** `0` (clean — a rejection finding would NOT change this; the script exits
nonzero ONLY on a genuine script error, never on an audit verdict)

This report independently re-verifies the T>1 `α_op_lb`/`α_x_lb` call-site census across
all 10 planning test files (never trusting 30-RESEARCH.md Pitfall 4's own claim blindly),
extends the census to every `src/`-level `solve_stackelberg!`/`build_master` call site
(checker BLOCKER 1 + BLOCKER 2), and runs the NEW `derive_alpha_op_lb`/`derive_alpha_x_lb`
derivation formula against every distinct T>1 shape found.

## Step 1 — Independent T>1 census (`test/test_planning_*.jl`, 10 files)

Re-derived from scratch this session by reading every `α_op_lb=`/`α_x_lb=` occurrence
alongside every `T = <n>` literal in each of the 10 files (`grep -n "α_op_lb\s*="` /
`grep -n "T\s*=\s*[0-9]\+"`), resolving every indirection (`T = shared.T`) to its concrete
value by reading the defining `build_shared_transmission(...)` call.

| File | α_op_lb/α_x_lb line(s) | Governing `T` | Notes |
|---|---|---|---|
| `test_planning_benders.jl` | 51, 130, 186, 233 | 1 | all `T = 1` |
| `test_planning_benders_integer.jl` | 26, 99 | 1 | all `T = 1` |
| `test_planning_certification.jl` | 181 | 1 | `T = 1` |
| `test_planning_certification_integer.jl` | 357, 473, 548 | 1 | `T = 1`; the file's OWN `T=2` sites (lines 612, 691) call `build_planning_oracle`/`build_follower` DIRECTLY for `corner_recourse` testing — **never `build_master`** — so they carry NO `α_op_lb`/`α_x_lb` literal to audit |
| `test_planning_goldens.jl` | 31, 77, 110 | 1 | all `T = 1` |
| `test_planning_master.jl` (pre-30-02) | 25, 32, 39, 49, 62, 92, 101, 114, 134, 153 | 1 | all `T = 1` (this plan's own 7 new `@testitem`s add no NEW T>1 literal — item 5 CALLS `derive_alpha_op_lb` directly at T=8 to cross-check the hardening finding, it does not introduce a new call site to audit) |
| `test_planning_master_integer.jl` | 10 occurrences (lines 21–270) | 1 | all `T = 1` |
| `test_planning_nash.jl` | 171, 205, 277, 346, 383, 439, 495, 544, 633, 687, 735, 780, 843 | 1 | all `T = 1` — including the ONE indirection site, `T = shared.T` (line 451): EVERY `build_shared_transmission(...)` call in this file (11 call sites, lines 262–829) passes `T = 1` explicitly, confirmed by direct grep of every one |
| `test_planning_noninteger.jl` | 70, 96 | 1 | all `T = 1` |
| `test_planning_hardening.jl` | 50, 83, 116, 139 | 1 | `T = 1` |
| `test_planning_hardening.jl` | **267** | **8** | **THE ONLY T>1 site** — `α_op_lb = -50.0, α_x_lb = 0.0` inside `master_kwargs`, reached via `TSODSO.solve_stackelberg!(...)` (line ~271), **not** a direct `build_master(...)` call |

**Confirmed finding (independently re-verified, matches 30-RESEARCH.md Pitfall 4's own
claim):** `test/test_planning_hardening.jl`'s own `T=8` fixture (line 267) is the ONLY
`α_op_lb`/`α_x_lb` call site anywhere in this 10-file set using `T>1`.

## Step 1b — `src/` call-site census (checker BLOCKER 1 + BLOCKER 2)

`grep -rn "solve_stackelberg!(\|build_master(" src/`:

| File:line | Call | Literal `α_op_lb`/`α_x_lb`? | Disposition |
|---|---|---|---|
| `src/planning/benders.jl:741` | `master = master === nothing ? build_master(; master_kwargs..., T = T) : master` | None of its own (forwards `master_kwargs`) | The SOLE `build_master` call site inside `solve_stackelberg!` itself. **TODAY** (before plan 30-04 lands) this call passes no `bounds_ctx`, so its `α_op_lb`/`α_x_lb` resolution is the byte-identical explicit-value path. Plan 30-04 makes `solve_stackelberg!` ALWAYS construct and pass `bounds_ctx` here — once that lands, this call's `α_op_lb` becomes LIVE-VALIDATED at build time on every invocation. |
| `src/planning/nash.jl:475` | `run_nash!` calls `solve_stackelberg!(...; master_kwargs = spec.master_kwargs, follower = DistributorView(shared, i), follower_kwargs = NamedTuple())` once per distributor per sweep | None of its own (forwards `specs[i].master_kwargs`) | An **INDIRECTION site** — carries NO `α_op_lb`/`α_x_lb` literal, forwarding whatever its `specs` caller supplies. Because `run_nash!` ALWAYS supplies a pre-built `follower = DistributorView(...)`, every call through it has `bounds_ctx.follower_kwargs = nothing` once plan 30-04 lands: `α_op_lb` is LIVE-VALIDATED through this site, but `α_x_lb`'s build-time check is the documented, honest scope-limit SKIP (never a silent pass) for every `run_nash!` call — the universal runtime floor guard (plan 30-04) remains the defense-in-depth. |

**Every literal `master_kwargs` value exercised against `run_nash!` in-repo today:**
`test/test_planning_nash.jl`'s own `T=1`, `α_op_lb=-5.0`/`α_x_lb=0.0` literals (already
covered in the Step 1 census above, lines 171/205/277/346/383/439/495/544/633/687/735/780/843).
**No T>1 literal reaches `run_nash!` anywhere in this repo.**

## Step 2 — Derivation-formula audit of every found T>1 shape

Script output (full run captured verbatim):

```
test_planning_hardening.jl:267  T=8
  α_op_lb: literal=-50.0  derived=-16.000001000000015  VERDICT=accepted
  α_x_lb:  literal=0.0  derived=-1.0e-6  VERDICT=accepted
```

Derived via `TSODSO.derive_alpha_op_lb(feeder, LinDistFlow(), [agg]; λ₀=fill(4.0,8), T=8,
y_max=8.0)` and `TSODSO.derive_alpha_x_lb(; T=8, corridor_cap=2.0, x_inv_max=2.0,
c_inv=1.0, c_op=fill(0.5,8))`, using the EXACT T=8 fixture literals from
`test_planning_hardening.jl`'s own header comment/fixture body (`dev =
ToyElasticDevice(2, 6.0, 1.0, 10.0)`, `agg` with `zeros(8)` Pdc, `λ₀ = fill(4.0, 8)`,
`follower_kwargs` with `c_op = fill(0.5, 8)`).

`ALPHA_LB_REJECTION_TOL = 1e-6` (measured, see `src/planning/master.jl`'s own docstring
derivation comment).

- `α_op_lb = -50.0` vs. derived minimum `-16.000001...`: `-50.0 > -16.000001 + 1e-6` is
  `false` → **accepted**. (`-5.0`, the PRE-fix literal this same file's own header comment
  documents as invalid, WOULD be rejected: `-5.0 > -16.000001 + 1e-6` is `true` — confirmed
  independently in `test_planning_master.jl`'s own new `@testitem` item 5, see
  `30-02-SUMMARY.md`.)
- `α_x_lb = 0.0` vs. derived minimum `-1.0e-6`: `0.0 > -1.0e-6 + 1e-6 = 0.0` is `false`
  (not strictly greater) → **accepted**.

## Step 3 — Honest finding statement

**No PREVIOUSLY-UNKNOWN invalid bound was found.** The only T>1 site in the 10-file census
(`test_planning_hardening.jl`'s T=8 fixture, line 267) uses `α_op_lb=-50.0`, which the new
derivation formula **ACCEPTS** — exactly as expected, since this bound was ALREADY fixed
in-repo (from the originally-invalid `-5.0`) per that file's own documented finding
(30-RESEARCH.md Pitfall 4). `α_x_lb=0.0` at T=8 is likewise accepted.

This is the expected answer per 30-RESEARCH.md's own prediction ("the only T>1 site is the
ALREADY-fixed T=8 case") — the re-verification in this session did **not** uncover any
additional T>1 call site, in either `test/` or `src/`, that this plan's own prior research
had not already anticipated. No fix is needed as part of this plan; plan 30-04's own
wiring of `bounds_ctx` through `solve_stackelberg!` (including through `run_nash!`) will
make this already-valid bound LIVE-VALIDATED (not merely audited) on every future run.

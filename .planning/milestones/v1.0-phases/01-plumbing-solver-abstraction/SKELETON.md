# Walking Skeleton — TSO-DSO Integration Optimization Framework (`TSODSO`)

**Phase:** 1
**Generated:** 2026-07-18

## Capability Proven End-to-End

> A researcher constructs a trivial single-node feeder as immutable per-unit structs, calls the toy
> DC solve, and receives a finite objective **and** the nodal-balance dual — routed through the full
> keystone: per-unit ingestion → immutable data model → `select_optimizer(::ProblemClass)` factory →
> `ModelContext` residual registry → `assert_solved!` status discipline. No model file names a solver;
> a non-optimal solve or a non-radial feeder fails loudly.

This is the "rung 0" of the abstraction ladder. It proves every architectural seam connects with
real-but-trivial math before any power-flow physics, device, or decomposition is added.

## Architectural Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Language / modeling | Julia 1.10 LTS floor (dev on 1.11/1.12) + JuMP 1.30.x | LTS floor for reproducibility; JuMP gives per-constraint `dual()`, native `Parameter`, `SecondOrderCone`, solver-agnostic MOI layer (CLAUDE.md, not Convex.jl) |
| Package / module name | `TSODSO` | Valid Julia identifier (no hyphen); matches repo `TSO-DSO`. RESEARCH open-question A1 — chosen at planner discretion |
| Solver abstraction | `select_optimizer(::ProblemClass)` singleton-type dispatch factory | Only `solver/factory.jl` (+ weakdep exts) names a concrete solver; models request by problem class (INFRA-02). Singletons > `@enum` so weakdep exts add methods without editing core |
| Open-source solvers | HiGHS (LP/MILP), Clarabel (QP/SOCP), Ipopt (NLP) | CLAUDE.md defaults. `direct_model` reserved for HiGHS only — **Clarabel is copy_to-only** (RESEARCH Pitfall 1, corrects the CLAUDE.md perf note) |
| Commercial solvers | Gurobi / MosekTools as `[weakdeps]` + package `[extensions]` | Never a hard dependency; loads only if the user has a license (INFRA-02 opt-in). Modern replacement for `Requires.jl` |
| Status discipline | `assert_solved!` wrapping `is_solved_and_feasible(model; dual, allow_local=false)` + slack recompute | Single choke point; supersedes hand-checking `termination_status == OPTIMAL`; `allow_local=false` demands global optimum for the convex core (INFRA-03) |
| Data model | Immutable, JuMP-free, concretely-typed parametrized structs (`Feeder{T}`, `Bus{T}`, `Branch{T}`); `SparseArrays` incidence | Data has no solver/model knowledge; validation is a construction invariant (DATA-01) |
| Radial validation | `edges == nodes-1 ∧ BFS-connected ∧ one root` at construction | Tree ⟺ these conditions; SOC exactness (later phases) holds only on radial trees. ~15-line BFS, no Graphs.jl dep (DATA-02) |
| Per-unit system | `PerUnitBase{T}` (S_base MVA, V_base kV), convert once at ingestion, `@assert` magnitude bands | One documented base; loud tripwires against SI/pu mixing (INFRA-05) |
| Residual seam | `ModelContext` with `constraints`/`residuals`/`meta` registries + `AbstractPowerFlow` contract | Formulations `add_to_residual!` into a shared nodal balance with no `if formulation ==` branching (PF-01); Phase 1 exercises it trivially |
| Directory layout | Subfoldered `src/` (`units/ data/ solver/ core/ powerflow/ models/`) + `ext/` + `test/` (TestItems) + `docs/` (Documenter+Literate) | Explicit seam ownership; one `@testitem` per rung/seam |
| Reproducibility | Committed `Project.toml` + `Manifest.toml`, `[compat]` floor `julia = "1.10"`, CI matrix 1.10/1.11/1.12 | Clean-checkout resolution on LTS + current (INFRA-01) |

## Stack Touched in Phase 1

- [x] Project scaffold (PkgTemplates: Project.toml, committed Manifest.toml, CI matrix, Aqua/JET, Documenter, `.JuliaFormatter.toml`)
- [x] Test runner — TestItems + TestItemRunner (`@run_package_tests`), one `@testitem` per seam
- [x] Data — one real immutable feeder built + validated radial (and a non-tree feeder rejected)
- [x] Solver abstraction — one real `select_optimizer(::LP)` → HiGHS-backed `Model`
- [x] Solve — one real toy DC `optimize!` through `assert_solved!`, returning objective + balance dual
- [x] "Deployment" equivalent — documented local full-stack run: `julia --project=. -e 'import Pkg; Pkg.test()'` and a Literate `docs/literate/toy_dc.jl` page that executes end-to-end

## Out of Scope (Deferred to Later Slices)

> Explicit so later phases do not re-litigate Phase 1's minimalism.

- Any power-flow physics beyond the trivial single-node balance (DC/LinDistFlow → Phase 2; SOCP → Phase 4)
- Any prosumer device model, aggregator, or social-welfare objective (Phases 2–3)
- Duals-as-prices / DADP / DLMP decomposition (Phase 5)
- ADMM / Benders decomposition and build-once re-solve loops (Phases 6–7) — the `Parameter` pattern is *wired but unused* in Phase 1
- IEEE 13/123 fixtures and thesis parameters (Phase 4, DATA-03)
- Seeded Markov-chain demand/PV generation (Phase 3, DATA-04)
- `operational_oracle(z)→(cost,π)` seam and SEAM-01 extension stubs (Phase 4)
- Multi-node incidence exercised by real branch flow (Phase 2) — Phase 1 keeps the residual seam trivial

## Subsequent Slice Plan

Each later phase adds one vertical slice on top of this skeleton without altering its architectural decisions:

- Phase 2: LinDistFlow/DC linear formulation + one flexible load meeting at `Rp/Rq`; first nodal-balance dual from a centralized linear solve (rung 1)
- Phase 3: full prosumer device library + aggregator + `GLB-CVX` social-welfare on linear flow (rung 2a)
- Phase 4: SOCP Convex Branch Flow + LinDistFlow exactness + IEEE 13 + `operational_oracle` seam (rung 2b, correctness milestone)
- Phase 5: DADP/DLMP extraction + four-way decomposition + welfare accounting (rung 3)
- Phase 6–7: ADMM (`AGR-OPT`/`DSO-OPT`) build-once, adaptive-ρ, IEEE 123 (rung 4)
- Phase 8–9: experiment harness + reproducibility + literate docs + v1 regression acceptance gate

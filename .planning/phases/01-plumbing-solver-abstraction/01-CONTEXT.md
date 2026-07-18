# Phase 1: Plumbing & Solver Abstraction - Context

**Gathered:** 2026-07-18
**Status:** Ready for planning
**Mode:** Auto-generated (infrastructure phase — discuss skipped)

<domain>
## Phase Boundary

Lock the architectural keystone — a pure, JuMP-free data model (feeder + device structs),
a `ModelContext` + residual registry, a solver abstraction (`select_optimizer(::ProblemClass)`),
and status/per-unit discipline — validated against real-but-trivial math: a toy DC single-node,
single-period centralized solve. No power-flow physics, no devices beyond the toy, no
decomposition. This phase establishes the seams every later phase reuses.

Requirements in scope: INFRA-01, INFRA-02, INFRA-03, INFRA-05, DATA-01, DATA-02, PF-01.

</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
All implementation choices are at Claude's discretion — pure infrastructure phase. Anchor
decisions to the authoritative tech-stack guidance in `CLAUDE.md` and the vision/constraints in
`.planning/PROJECT.md`:

- **Modeling:** JuMP (not Convex.jl); models never name a concrete solver.
- **Solver factory:** one thin `select_optimizer(::ProblemClass)` / `make_solver` factory — HiGHS
  (LP/MILP), Clarabel (conic/QP), Ipopt (NLP) as open-source defaults; Gurobi/Mosek opt-in only
  behind the factory, never a hard dependency.
- **Data model:** immutable, JuMP-free, concretely-typed parametrized structs
  (`struct Feeder{T<:Real} … end`); `SparseArrays` for incidence/topology.
- **Status discipline:** every solve asserts `termination_status == OPTIMAL`; fail loudly on
  non-optimal status or hidden constraint slack.
- **Per-unit:** one documented per-unit system, converted once at ingestion, with
  magnitude-sanity assertions on electrical and monetary quantities.
- **Radial validation:** feeder validated as a tree (N nodes → N−1 branches, connected, one root);
  non-tree feeder raises a clear error.
- **Reproducibility:** committed `Project.toml` + `Manifest.toml`, `[compat]` floors at Julia 1.10
  LTS, tested on 1.10 and 1.11.

</decisions>

<code_context>
## Existing Code Insights

Greenfield — no `src/` yet. Codebase context (scaffold layout, conventions) will be established
during plan-phase research, guided by the PkgTemplates/Test/Documenter/JuliaFormatter tooling
choices documented in `CLAUDE.md`.

</code_context>

<specifics>
## Specific Ideas

No specific requirements — infrastructure phase. The `CLAUDE.md` Technology Stack section is the
binding reference for library choices, versions, and architectural seams (JuMP-vs-Convex,
Clarabel-as-default-conic, from-scratch model, solver factory).

</specifics>

<deferred>
## Deferred Ideas

None — infrastructure phase.

</deferred>

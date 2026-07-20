# Phase 9 — Deferred Items

## WR-04 — JuliaFormatter coverage of `docs/` (code-review deferral)

- **Source:** 09-REVIEW.md finding WR-04 (Warning).
- **Issue:** The CI `format` job does not run JuliaFormatter over `docs/`. Adding `docs/` to the
  formatter job now would immediately break CI because `docs/` is not v2-style-conformant.
- **Why deferred:** Running `JuliaFormatter.format("docs")` breaks apart multi-line device-constructor
  argument lists in the literate pages (e.g. `docs/literate/prosumer_welfare.jl`), detaching inline
  equation/assumption comments (`# bus, η, Δt, Pmax, ...`) from the arguments they annotate — directly
  at odds with the CLAUDE.md hard requirement that model equations/assumptions stay legible beside the
  code. This needs a deliberate, hand-reviewed formatting pass, not a mechanical one.
- **Action (later):** hand-review a formatting pass over `docs/` that preserves inline-comment
  placement, then add `docs/` to the CI format job.

## WR-05 — `deploydocs` placeholder repo slug (settled user decision, not a defect)

- **Source:** 09-REVIEW.md finding WR-05; 09-05 checkpoint.
- **Decision (user, 2026-07-20):** KEEP the `github.com/PLACEHOLDER-ORG/PLACEHOLDER-REPO.git`
  placeholder in `docs/make.jl` + the TODO. No git remote is configured in this checkout, so the real
  slug is unknown. `deploydocs` only runs under the `CI` env var, so the placeholder does not affect
  local builds or the v1 acceptance gate.
- **Action (before first gh-pages deploy):** replace the placeholder with the real `github.com/ORG/REPO`
  slug and wire `DOCUMENTER_KEY`/`GITHUB_TOKEN` in CI secrets.

## Docstring-manual wiring (tracked, from CR-01)

- ~104 exported-symbol docstrings exist in `src/` but are not yet surfaced in the rendered manual via
  `@docs`/`@autodocs` blocks. `checkdocs=:exports` warns about these (non-fatal per the locked
  green-docs-build decision). Wiring them into pages and then dropping `:missing_docs`/
  `:cross_references` from `warnonly` (a true hard-fail docs gate) is a follow-up, not v1 scope.

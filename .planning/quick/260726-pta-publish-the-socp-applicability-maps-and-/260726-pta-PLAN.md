---
quick_id: 260726-pta
description: Publish the SOCP applicability maps and sweep experiments on the Documenter site
date: 2026-07-26
mode: quick
---

# Quick Task 260726-pta — Publish the SOCP applicability maps on GH Pages

The applicability maps and the noise-floor finding currently live only in `.planning/spikes/`, which
is planning-internal and never reaches the Documenter site. They are among the more citable results
this project has produced and belong on the published site.

## The forced design decision — live vs precomputed

The CI docs job has a **30-minute timeout** (`.github/workflows/CI.yml:76`) and other literate pages
already run real solves. Measured sweep costs:

| substrate | points | cost |
|---|---|---|
| 3-bus high-PV | 150 | **70 s** — affordable live |
| real IEEE-123 | 54 | **~16 min** — NOT affordable live |

So: **live-execute the 3-bus map** (the boundary is real, verified at build time, figure generated
live) and **load the IEEE-123 map from committed CSV**, stating its provenance — script, commit, and
wall time — explicitly on the page. Precomputed data is labelled as such; nothing is presented as
live that isn't.

## Tasks

### Task 1 — promote the sweep to a first-class experiment

- **files:** `scripts/socp_applicability_sweep.jl` (new),
  `results/socp_applicability/{highpv_3bus,ieee123}_sweep.csv` (staged)
- **action:** Lift the two spike sweeps into one re-runnable script following the house
  `scripts/repro_stability_check.jl` convention (DrWatson `projectdir`, committed findings output,
  per-point try/catch with failure CLASSIFICATION, positive/negative controls asserted and printed).
  Must cover both substrates behind a selector.
- **verify:** re-running reproduces the committed CSVs' verdict columns.

### Task 2 — the documented page

- **files:** `docs/literate/socp_applicability.jl` (new)
- **action:** A narrative page that answers "when is the SOC relaxation applicable, and how do you
  know?" It must carry, in prose a reader can act on:
  1. the free cone-gap detector (`src/models/exactness.jl:8`) — the measurement, and that it costs
     nothing beyond the SOCP solve;
  2. the **live** 3-bus map + figure, with the two EXACT-04 control points marked;
  3. the **precomputed** IEEE-123 map + figure, provenance stated;
  4. the two substrate-dependent findings: voltage headroom is first-order on the stress fixture;
     on real impedances the bound is **never active** and there is no structural inexactness;
  5. the **noise-floor caveat** — `atol = 1e-6` sits at Clarabel's achievable residual on 122
     branches, so ~48% of IEEE-123 points flag spuriously at default tolerance. Includes the
     tolerance-ladder discriminator (4.76 → 0.0029 at an identical optimum) and the rule: *a ratio
     near 1 is not evidence*.
  6. what does **not** generalize — spike 001's zero-false-negatives and cliff/empty-band findings
     were substrate-specific, and saying so is the point of the page.
- **verify:** page executes standalone; figures render.

### Task 3 — register and build

- **files:** `docs/make.jl`
- **action:** Add to the `Literate.markdown` source tuple and to the `pages` list under `"Models"`.
- **verify:** full `julia --project=docs docs/make.jl` completes and the page appears in the built
  site with both figures.

## Constraints

- **Label precomputed data as precomputed.** Never imply a live solve that did not run.
- Keep the CI docs build inside its 30-minute budget — do not add the IEEE-123 sweep live.
- Read data via a repo-root-relative path that works in a bare CI checkout (`pkgdir(TSODSO)`), not
  a `.planning/` path — docs must not depend on planning-internal directories.
- INFRA-02: no concrete solver named in the page's model code; go through the factory.
- Do not restate spike findings more strongly than the spikes do. The IEEE-123 result is
  "no *structural* inexactness found in the swept region", **not** "the relaxation is exact".

## must_haves

- **truths:** page is registered and builds; 3-bus map live; IEEE-123 map precomputed-and-labelled;
  noise-floor caveat and the non-generalizing findings both stated
- **artifacts:** `scripts/socp_applicability_sweep.jl`, `results/socp_applicability/*.csv`,
  `docs/literate/socp_applicability.jl`, `docs/make.jl`
- **key_links:** `src/models/exactness.jl:8`, `.github/workflows/CI.yml:76` (the timeout that forces
  the design), `.planning/spikes/00{1,2}-*/README.md` (the source findings)

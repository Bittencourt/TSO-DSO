---
title: Investigate demo seed 42 tripping the battery-complementarity gate
created: 2026-10-06
source: Phase 37 research (user decision: separate debug task)
area: model-quality
---

`scripts/run_scenario.jl` (default demo, seed 42) fails with "Battery complementarity violated at bus 2,
t=16" — the gate fires correctly and loudly; seed 7 runs fine (ADMM 56 iterations). Also fails at the
pre-Phase-36 commit (438e162^), so not a cleanup regression.

Question: is a default-population seed tripping the complementarity gate a model-quality concern
(e.g. battery charge/discharge simultaneity being economically optimal under some price shape, needing
a complementarity enforcement change), or simply a seed to avoid in demos?

Start with `/gsd-debug`. Do not loosen the gate.

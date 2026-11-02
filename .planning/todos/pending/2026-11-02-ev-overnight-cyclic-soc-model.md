---
title: Overnight EV model (cyclic SOC + trip energy) for wrap-session EVs
created: 2026-11-02
source: Phase 43 code review WR-01 / verification human item (accepted as documented limitation)
area: model-fidelity (devices)
---

Wrap sessions (arrival > departure, i.e. overnight) in `src/devices/ElectricVehicle.jl` use
same-day semantics: `soc0` is the SOC at hour 1, only hours `1..t_dep` count toward the soft
departure target, and no trip energy is consumed between departure and arrival. Documented in the
header/docstring and pinned by a test in `test/test_electricvehicle.jl` (WR-01 fix, c1190cb).

The researcher accepted this on 2026-11-02 for closing Phase 43. Before citing flex-population EV
results (`build_population(...; flex_devices=...)`) in the thesis, consider a true overnight model:
cyclic SOC (soc[T] linked to soc[1] across the trip), explicit trip energy E_trip drawn while away,
and a target defined over the session that wraps midnight. Must stay convex/binary-free and must not
change the default path or the `:case_a_784` goldens (flex devices are opt-in).

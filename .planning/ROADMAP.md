# Roadmap: TSO-DSO Integration Optimization Framework (Julia)

## Milestones

- ✅ **v1.0 Operational Transactive-Energy Core** — Phases 1–9 (shipped 2026-07-20)
- ✅ **v2.0 Stackelberg-Nash TSO–DSO Planning Game** — Phases 10–14 (shipped 2026-07-24)
- ✅ **v2.1 Validation & Reproduction** — Phases 15–18 (shipped 2026-07-26)
- ✅ **v3.0 Research Extension Rungs** — Phases 19–25 (shipped 2026-08-24)
- ✅ **v4.0 Correctness & Depth** — Phases 26–38 (shipped 2026-10-08)
- ✅ **v5.0 Aggregator Layer at Scale** — Phases 39–47 (shipped 2026-11-07)

Full phase details, decisions, and per-phase artifacts for shipped milestones are archived in
[`milestones/v1.0-ROADMAP.md`](milestones/v1.0-ROADMAP.md),
[`milestones/v2.0-ROADMAP.md`](milestones/v2.0-ROADMAP.md),
[`milestones/v2.1-ROADMAP.md`](milestones/v2.1-ROADMAP.md),
[`milestones/v3.0-ROADMAP.md`](milestones/v3.0-ROADMAP.md),
[`milestones/v4.0-ROADMAP.md`](milestones/v4.0-ROADMAP.md), and
[`milestones/v5.0-ROADMAP.md`](milestones/v5.0-ROADMAP.md).

## Phases

<details>
<summary>✅ v5.0 Aggregator Layer at Scale (Phases 39–47) — SHIPPED 2026-11-07</summary>

- [x] Phase 39: Parallel-Ready ADMM & Gating Measurements (5/5 plans) — completed 2026-10-24
- [x] Phase 40: 784-House Thesis Population (6/6 plans) — completed 2026-10-24
- [x] Phase 41: Settlement, Ledger & Equity (4/4 plans) — completed 2026-10-26
- [x] Phase 42: Thesis Case A Magnitude (6/6 plans) — completed 2026-10-26
- [x] Phase 43: Flexible Devices (EV, Heat Pump, Smart Inverter) (5/5 plans) — completed 2026-11-02
- [x] Phase 44: Aggregator as Actor (7/7 plans) — completed 2026-11-03
- [x] Phase 45: Flexibility Market vs Price Coordination (7/7 plans) — completed 2026-11-05
- [x] Phase 46: IEEE-8500 Headline Measurement (go/no-go) (5/5 plans) — completed 2026-11-06
- [x] Phase 47: v5.0 Audit Gap Closure (3/3 plans) — completed 2026-11-07

</details>

No milestone in progress. Start the next one with `/gsd-new-milestone`.

## Deferred / Future-Milestone Notes

- **Large-lattice integer termination criterion** — a rigorous `δ_min` is not derivable (`Q`'s
  local slope is a continuous SOCP dual price with no established Lipschitz bound), so the
  enumeration-backed criterion (Phase 24, v3.0) is tractable only where enumeration is. BILEV-07
  (Phase 31, v4.0) extends integer investment to N>1 Nash but does not resolve this; still open
  past v5.0.

Items formerly listed here — **SCALE-STRETCH**, the Phase-18 `fit_baseline` convergence flake,
the MESH-06 composition advisory, and integer investment beyond single-distributor Stackelberg —
are now in scope for v4.0 as ARCH-10 (Phase 35), FIX-09 (Phase 27), ARCH-06 (Phase 34), and
BILEV-07 (Phase 31) respectively, and are no longer deferred.

Deferred at the v5.0 close (2026-11-07; details in `milestones/v5.0-REQUIREMENTS.md` and
`milestones/v5.0-MILESTONE-AUDIT.md`):

- **SETL-F2: actor-aware flexibility market and tariff comparison.** Settle `Portfolio`/`ProfitObjective`
  wedges through `clear_flex_market`/`compare_tariffs`. Today these entry points refuse `actors` with an
  `ArgumentError`.
- **IEEE-8500 d=0.1 T=24 headline.** NO-GO on this host (11.209 GiB VmHWM). A GO needs memory levers
  (`HourSplitDsoOpt`, a per-hour solver-state pool, names off, an AgrOpt pool) or a host with more RAM.
- **Reactive (q) dispatch in flex stage 2.** `SmartInverterPV`/`FourQuadBESS` are refused there today.


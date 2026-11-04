---
title: Opt-in ΔW (efficiency loss) field on actor solve results
created: 2026-11-03
source: Phase 44 verification human item 9 (accepted deviation from 44-CONTEXT)
area: actors / reporting
---

44-CONTEXT says every result carries `welfare` (social), the actor objective and `ΔW` against the
welfare optimum. As built, `solve_admm`/`solve_welfare` with `actors=` report social welfare and the
actor objective, but ΔW needs a second welfare-objective solve plus
`actor_efficiency(W_opt, W_soc)`, or a read of `results/actor_behaviour/actor_behaviour_sweep.csv`.

Possible follow-up: an opt-in keyword, such as `reference_welfare=:solve` or a supplied `W_opt`, that runs or
accepts the welfare-optimum reference and adds `:dW_abs`/`:dW_rel` to the result. It must stay opt-in so the
default path stays byte-identical and the digest fence is untouched.

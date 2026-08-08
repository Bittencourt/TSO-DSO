# Deferred Items — Phase 19 (4Q-BESS + Live Reactive Dual-Ascent)

Out-of-scope discoveries logged during plan execution, per the executor's scope-boundary rule
(only auto-fix issues directly caused by the current task's own changes).

## From plan 19-07 (solve_admm.jl LIVE reactive dual-ascent)

### `:cone` name collision between `ConvexBranchFlow` and `FourQuadBESS` in a SHARED model

- **Found during:** Task 2 verification — attempting to cross-validate a `solve_admm(...;
  reactive_consensus = :live)` run against the centralized `solve_welfare` for a
  `FourQuadBESS`-bearing aggregator.
- **Issue:** `src/powerflow/ConvexBranchFlow.jl` registers its per-branch apparent-power SOC
  cone as `@constraint(model, cone[...], ...)` (network layer). `src/devices/FourQuadBESS.jl`
  ALSO registers its device-level apparent-power cone as `@constraint(m, cone[t=1:T], ...)`
  (device layer). Both use the bare JuMP container name `:cone`. Whenever a `FourQuadBESS`
  aggregator is combined with `ConvexBranchFlow` in ONE SHARED model — i.e. any direct
  `solve_welfare(feeder, ConvexBranchFlow(), aggregators)` call where `aggregators` includes a
  `FourQuadBESS` device — JuMP throws: `"An object of name cone is already attached to this
  model"`.
- **Why it does NOT affect this plan (19-07):** `solve_admm`'s two-block ADMM decomposition
  builds AGR-OPT (where `FourQuadBESS.contribute!` registers `:cone`) and DSO-OPT (where
  `ConvexBranchFlow.contribute!` registers `:cone`) as TWO SEPARATE JuMP `Model`s — they never
  share a model, so the collision never triggers on the ADMM path. Verified: `solve_admm(...;
  reactive_consensus = :live)` on a 2-bus + `FourQuadBESS` fixture converges and runs cleanly
  end-to-end (this plan's Task 1/Task 2 verification).
- **Why it blocks future work:** plan 19-08's Validation Architecture table row ("`:live` mode's
  converged welfare/λ/μ agree with `solve_welfare` centralized cross-validation") requires
  calling the CENTRALIZED `solve_welfare` on the SAME `FourQuadBESS`-bearing aggregator set used
  for the `:live` ADMM run — that call will hit this collision as written today.
- **Fix (deferred, out of scope for this plan):** rename one of the two `:cone` registrations to
  a distinct name (e.g. `FourQuadBESS.jl`'s device-level cone → `:bess_cone`, or scope it under a
  per-device/per-bus qualified name) in `src/devices/FourQuadBESS.jl` (plan 19-02's file) and/or
  `src/powerflow/ConvexBranchFlow.jl` (out of this plan's `files_modified` scope, which is
  strictly `src/admm/solve_admm.jl`). Plan 19-08 (or whichever plan first needs the centralized
  cross-validation for a 4Q-bearing aggregator) should fix this before relying on
  `solve_welfare` with a `FourQuadBESS` device present.
- **Files that would need the fix:** `src/devices/FourQuadBESS.jl` (rename its `cone` constraint
  registration) — NOT touched by this plan.

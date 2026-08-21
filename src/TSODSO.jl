"""
    TSODSO

Walking-skeleton chassis for the TSO–DSO Integration Optimization Framework.

This top module ONLY wires the include graph of the architectural seams, in
dependency order. Each seam file is created empty (comment-only) in plan 01-01
and filled by exactly one later plan, which declares that seam's own `export`s.
`TSODSO.jl` itself exports nothing — it is the assembly point, never a shared
edit surface, so Waves 2–3 fill stubs without ever touching this file.
"""
module TSODSO

# --- Units (owned by plan 01-02, INFRA-05) ---
include("units/PerUnit.jl")

# --- Data model (owned by plan 01-02, DATA-01 / DATA-02) ---
include("data/Feeder.jl")
include("data/topology.jl")

# --- Meshed feeder data model (plan 23-01, MESH-01) --- a SEPARATE struct from
# `Feeder`, gated by `assert_connected` instead of `assert_radial` (D-01/D-09
# lock: `Feeder`/`topology.jl` above are byte-unchanged). `mesh_topology.jl`
# must load BEFORE `MeshedFeeder.jl` (its inner constructor calls
# `assert_connected` at call time -- world-age resolution, mirroring
# `Feeder.jl`/`topology.jl`'s own documented ordering note above).
include("data/mesh_topology.jl")
include("data/MeshedFeeder.jl")

# --- Seeded profile generator (owned by plan 03-02, DATA-04) ---
include("data/profiles.jl")

# --- Modified IEEE 13-node feeder fixture (owned by plan 04-03, DATA-03) ---
include("data/ieee13.jl")

# --- Modified IEEE 123-node feeder fixture (owned by plan 07-02, DATA-03 scale target) ---
# STUB seam wired here by plan 07-01 (after ieee13.jl in the data block); filled by 07-02.
include("data/ieee123.jl")

# --- IEEE-8500 scale-benchmark feeder fixtures (owned by plan 25-03, SCALE-01/02) ---
# References IEEE123_SWITCH_R/IEEE123_SWITCH_X (D-13 near-ideal reuse), so must load AFTER
# ieee123.jl.
include("data/ieee8500.jl")

# --- Solver abstraction (owned by plan 01-03, INFRA-02) ---
include("solver/ProblemClass.jl")
include("solver/factory.jl")

# --- Core (owned by plan 01-03, PF-01 residual seam / INFRA-03 status) ---
include("core/ModelContext.jl")
include("core/status.jl")

# --- Power-flow interface (owned by plan 01-03, PF-01) ---
include("powerflow/AbstractPowerFlow.jl")

# --- Power-flow formulations (owned by plan 02-02, PF-02) ---
include("powerflow/DCPowerFlow.jl")
include("powerflow/LinDistFlow.jl")

# --- SOCP Convex Branch Flow formulation (owned by plan 04-02, PF-03) ---
include("powerflow/ConvexBranchFlow.jl")

# --- Independent nonconvex AC-OPF oracle (peer formulation, owned by plan 15-01, EXACT-01) ---
# Included immediately after ConvexBranchFlow.jl (it references the `_SMAX_NO_LIMIT` const that
# file defines) and before problem_class_trait.jl; it adds `problem_class(::ACPowerFlow) = NLP()`.
include("powerflow/ACPowerFlow.jl")

# --- Gan-Low OPF-m restricted formulation, with optional OPF-ε margin (owned by plan
# 20-02, OVR-01) --- included right after ACPowerFlow.jl: it delegates to
# ConvexBranchFlow.contribute! and must load after it.
include("powerflow/RestrictedBranchFlow.jl")

# --- Meshed SOCP branch-flow formulation (owned by plan 23-02, MESH-02) --- delegates to
# ConvexBranchFlow.contribute! (byte-identical constraint set -- ALREADY graph-generic, no
# new model-time math) and must load after it, mirroring RestrictedBranchFlow.jl's own
# ordering rationale above.
include("powerflow/MeshedFlow.jl")

# --- Power-flow → problem-class routing trait (owned by plan 04-01, INFRA-02 / PF-03) ---
# Included AFTER the powerflow formulations (needs `AbstractPowerFlow`) and after
# solver/ProblemClass.jl (needs `QP`): it maps a formulation to its solver problem class.
include("solver/problem_class_trait.jl")

# --- Devices (owned by plan 02-03, DEV-03) ---
include("devices/AbstractDevice.jl")
include("devices/Interruptible.jl")

# --- Concrete prosumer devices (owned by plans 03-03 / 03-04) ---
include("devices/Thermostatic.jl")   # DEV-01
include("devices/Deferrable.jl")     # DEV-02
include("devices/PVBattery.jl")      # DEV-04
include("devices/FourQuadBESS.jl")   # plan 19-02, MESH-04
include("devices/FixedCapacitor.jl") # plan 25-04, SCALE-03/D-10 (second q_inject consumer)

# --- Aggregator roll-up: the network-facing residual writer (plan 03-05, DEV-05) ---
include("devices/Aggregator.jl")

# --- Models (owned by plan 01-04 rung 0 / plan 02-04 rung 1 integration) ---
include("models/toy_dc.jl")
include("models/linear_solve.jl")

# --- GLB-CVX centralized social-welfare solve (owned by plan 03-05, OPT-01) ---
include("models/welfare_solve.jl")

# --- SOCP relaxation exactness gate (owned by plan 04-05, PF-04) ---
include("models/exactness.jl")
include("models/complementarity_4q.jl")   # plan 19-05, MESH-04

# --- operational_oracle + SEAM-01 extension stubs (owned by plan 04-04, OPT-03 / SEAM-01) ---
include("models/oracle.jl")

# --- AC-exactness oracle post-processing (owned by plan 15-01/15-02, EXACT-01/02/03) ---
# Sits beside models/exactness.jl: reads ModelContext.meta[:pf_vars] populated by BOTH the SOCP
# (ConvexBranchFlow) and AC (ACPowerFlow) solves. recover_voltage_angles (15-01) recovers true
# voltage phasors; assert_ac_exact! (15-02) certifies the SOCP relaxation per-hour against the AC
# oracle. Included after models/oracle.jl and before the pricing/ block.
include("models/ac_oracle.jl")

# --- Angle-recoverability a-posteriori certificate (owned by plan 23-03, MESH-03) --- must
# load AFTER models/ac_oracle.jl: it generalizes that file's recover_voltage_angles BFS with
# explicit chord tracking + a per-chord closure-residual check (the loop-consistency
# mechanism a meshed MeshedFlow context needs, per RESEARCH.md's "silently loop-blind"
# finding — recover_voltage_angles itself is left byte-unchanged, D-09-adjacent).
include("models/mesh_angle_certificate.jl")

# --- Restricted-SOCP AC-feasibility + optimality-loss certificate (owned by plan 20-03, OVR-02) ---
# Must load AFTER models/ac_oracle.jl: assert_restriction_exact! calls assert_ac_exact! internally.
include("models/restriction_exactness.jl")

# --- Nonconvex-AC-dual fallback pricer (owned by plan 20-04, OVR-03) --- no ordering
# dependency on restriction_exactness.jl (it never calls the certificate, D-09), placed
# adjacent for readability. Reuses solve_welfare(..., ACPowerFlow(), ...) verbatim.
include("models/ac_dual_fallback.jl")

# --- MpcTrace: rolling-horizon price-consistency ledger (owned by plan 21-02, MPC-03) ---
# JuMP-free, no ordering dependency; placed beside the other models/ files.
include("models/mpc_trace.jl")

# --- MpcWindow: build-once receding-horizon window model (owned by plan 21-03, MPC-01/02) ---
# No ordering dependency on mpc_trace.jl (both models/ files, grouped for diff locality).
include("models/mpc_window.jl")

# --- Stochastic PV/demand two-stage extensive-form welfare builder (owned by plan 22-02, ---
# STOCH-01/02) --- ORCHESTRATION over already-validated builders (ConvexBranchFlow/
# ModelContext/exactness.jl/Aggregator/PVBattery, all already loaded above); no
# ordering dependency beyond those. Placed immediately after mpc_window.jl per the plan.
include("models/stochastic_welfare.jl")

# --- Distribution pricing: DLMP decomposition, FIT baseline, checks, welfare accounting ---
# Wired empty (comment-only) in plan 05-01, AFTER models/oracle.jl (each consumes a solved
# ctx / the operational oracle). Dependency order: dlmp → fit → checks → welfare. Each seam
# is filled by exactly one Wave-2 plan, which declares its own exports.
include("pricing/dlmp.jl")      # DLMP extraction + four-way decomposition (plan 05-02, PRICE-02)
include("pricing/fit.jl")       # flat feed-in-tariff baseline (plan 05-03, PRICE-04)
include("pricing/checks.jl")    # economic-direction price checks (plan 05-04, PRICE-05)
include("pricing/welfare.jl")   # social = prosumer + DSO surplus split (plan 05-05, PRICE-03)

# --- ADMM decomposition core: AGR-OPT / DSO-OPT subproblems + the dual-ascent loop ---
# Wired (plan 06-01, this plan is the SOLE owner of this shared edit) AFTER the pricing seams
# — ADMM is ORCHESTRATION over the already-validated Phase-1–5 builders (RESEARCH Pattern 4):
# it consumes the solved-ctx / `extract_dlmp` seams and reuses device / `ConvexBranchFlow`
# `contribute!` verbatim, so NO Phase-5 source file is modified. Dependency order: residuals
# (pure data) → AgrOpt → DsoOpt → solve_admm (the loop consumes the other three). Each seam
# file declares its own exports; residuals.jl is filled by this plan, the other three by
# Waves 2–3, so those waves never touch TSODSO.jl.
include("admm/residuals.jl")    # AdmmResiduals primal/dual residual ledger (plan 06-01, ADMM-01)
include("admm/ReactiveMode.jl") # OFF/CERTIFIED/LIVE 3-state enum (plan 19-01, MESH-05)
include("admm/AgrOpt.jl")       # per-node aggregator QP subproblem (plan 06-02, ADMM-01, thesis 3.46)
include("admm/DsoOpt.jl")       # whole-network SOCP subproblem (plan 06-03, ADMM-01, thesis 3.47)
include("admm/solve_admm.jl")   # hand-rolled dual-ascent loop + cross-validation (plan 06-04, ADMM-01/03/04)

# --- Planning-layer resilience primitives: escalating retry + iteration checkpointing ---
# Wired (plan 10-01, this plan is the SOLE owner of this shared edit) AFTER admm/ and
# models/oracle.jl — ORCHESTRATION over the already-validated welfare/ADMM builders
# (RESEARCH Pattern 4): `solve_with_retry!` wraps `assert_solved!` (INFRA-03) verbatim, and
# `checkpoint_iteration!`/`resume_from_checkpoint` reuse `store.jl`'s `@tagsave` idiom
# verbatim. NO Phase 4-9 source file is modified (D-03/D-11). Phase 10-02's
# `planning/subproblem.jl` (below) and Phase 13's `planning/coupling.jl` join this
# directory. `planning/subproblem.jl` MUST load AFTER `retry.jl` (its
# `solve_planning_oracle!` calls `solve_with_retry!`, D-08) — hence its position as the
# THIRD line of this block, after `retry.jl` and `checkpoint.jl`. `planning/follower.jl`
# (plan 11-01, PLAN-04) has NO load-time dependency on `subproblem.jl` (it is a wholly
# separate LP with its own `FollowerLP` struct) but is positioned FOURTH, immediately
# after `subproblem.jl`, purely for diff stability as the planning/ block grows.
# `planning/master.jl` (plan 11-01, PLAN-05) is positioned FIFTH, after `follower.jl` —
# plan 11-02's `benders.jl` needs both `follower.jl` and `master.jl` loaded first, hence
# `benders.jl` is positioned SIXTH (final) in this block: it is the outer loop consuming
# all five prior planning/ files (`retry.jl`, `checkpoint.jl`, `subproblem.jl`,
# `follower.jl`, `master.jl`) via `solve_planning_oracle!`/`solve_follower!`/
# `solve_master!`/`checkpoint_iteration!` at call time.
include("planning/retry.jl")        # solve_with_retry! wraps assert_solved! (plan 10-01, D-08/D-09)
include("planning/checkpoint.jl")   # checkpoint_iteration!/resume_from_checkpoint (plan 10-01, D-10)
include("planning/trace.jl")        # BendersTrace convergence ledger (plan 12-01, roadmap criterion 2; zero load-time deps, no JuMP)
include("planning/subproblem.jl")   # PlanningOracle build-once z-pin oracle (plan 10-02, PLAN-01/02)
include("planning/follower.jl")     # FollowerLP transmission-reinforcement LP + Farkas certs (plan 11-01, PLAN-04)
include("planning/master.jl")       # BendersMaster build-once epigraph + persistent cut rows (plan 11-01, PLAN-05)
include("planning/benders.jl")      # solve_stackelberg! outer Benders loop (plan 11-02, PLAN-06)
include("planning/coupling.jl")     # SharedTransmission per-distributor views (plan 13-01, NASH-01)
include("planning/nash.jl")         # NashTrace/run_nash! outer Gauss-Seidel loop (plan 13-02, NASH-02/03/04)

# --- Convergence diagnostics: plotting API stubs (owned by plan 07-01, ADMM-05) ---
# Wired AFTER the admm/ seams — the plot functions consume the JuMP-free `AdmmResiduals`
# ledger. The core declares only method-less generic functions + exports (NO CairoMakie
# import); the CairoMakie-backed methods live in the TSODSOMakieExt weakdep extension
# (plan 07-06), so `using TSODSO` stays plot-free (threat T-07-01).
include("diagnostics/plots.jl")

# --- Experiment harness: declarative Scenario -> swappable-strategy run -> sweep+provenance ---
# Wired (plan 08-01, this plan is the SOLE owner of this shared edit) AFTER admm/ and
# diagnostics/ — the harness is ORCHESTRATION over the already-validated Phase 1-7 builders
# (RESEARCH Summary / Architectural Responsibility Map): run_scenario calls solve_welfare,
# solve_admm, and extract_dlmp; nothing here modifies a Phase 1-7 source file. Dependency
# order: Scenario (primitive selectors) -> materialize (selectors+seed -> feeder/λ₀/aggs) ->
# run (strategy dispatch -> ScenarioResult) -> store (per-run @tagsave provenance) -> sweep
# (dict_list expansion + diff-friendly CSV collation, consumes store's run_and_store). Each
# seam is a comment-only STUB in this plan, filled file-disjointly by exactly one later plan
# (08-02 Scenario+materialize, 08-03 run, 08-04 store+sweep), so Waves 2-4 never touch this file.
include("experiments/Scenario.jl")      # primitive-selector Scenario struct (plan 08-02, EXP-01)
include("experiments/materialize.jl")   # sub_seed + build_feeder/price/population (plan 08-02, INFRA-04)
include("experiments/run.jl")           # ScenarioResult + run_scenario dispatch (plan 08-03, EXP-01/INFRA-04)
include("experiments/store.jl")         # run_and_store @tagsave provenance (plan 08-04, INFRA-04)
include("experiments/sweep.jl")         # run_sweep + collate_summary diff-friendly CSV (plan 08-04, EXP-02)

# --- MPC / rolling-horizon / real-time pricing: run_mpc(scenario) closed-loop orchestrator ---
# Wired LAST (plan 21-05, MPC-01..04) after experiments/sweep.jl: run_mpc is an INDEPENDENT
# entry point (D-01, Pitfall 7) — it is NOT wired through run_scenario's strategy dispatch,
# reads Scenario's additive mpc_* fields (plan 21-04) directly, and consumes MpcWindow/
# MpcTrace (plans 21-02/21-03) plus Phase-20's certificate/fallback ladder.
include("experiments/mpc_loop.jl")

# --- Stochastic PV/demand uncertainty: run_stochastic(scenario) extensive-form + ---
# out-of-sample orchestrator --- Wired LAST (plan 22-04, STOCH-01..03), after
# experiments/mpc_loop.jl: run_stochastic is an INDEPENDENT entry point (D-01/D-02),
# mirroring run_mpc's own positioning — it is NOT wired through run_scenario's strategy
# dispatch, reads Scenario's additive stoch_* fields (plan 22-01) directly, and consumes
# build_stochastic_welfare/build_stochastic_oos_harness/solve_stochastic_oos_step!
# (plans 22-02/22-03).
include("experiments/run_stochastic.jl")

end # module TSODSO

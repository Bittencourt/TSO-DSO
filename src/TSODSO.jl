"""
    TSODSO

TSO-DSO Integration Optimization Framework: a research bench for transactive-energy
dynamic distribution pricing and Stackelberg-Nash TSO-DSO planning, built on JuMP with
swappable open-source solvers.

# Layers

  - **Data** (`Feeder`, `MeshedFeeder`, IEEE 13/123/8500 fixtures, `generate_profiles`):
    radial and meshed distribution networks and seeded profile generation.
  - **Core** (`ModelContext`, `contribute!`, residual and objective hooks, `TSODSOError`
    and the certificate / convergence / solve-failure error types): the shared model
    container every formulation and device writes into.
  - **Solver factory** (`ProblemClass`, `select_optimizer`): models never name a solver.
  - **Power flow** (`DCPowerFlow`, `LinDistFlow`, `ConvexBranchFlow`,
    `RestrictedBranchFlow`, `MeshedFlow`, `ACPowerFlow`): interchangeable network models.
  - **Devices** (`Thermostatic`, `Deferrable`, `Interruptible`, `PVBattery`, `FourQuadBESS`,
    `FixedCapacitor`, `Aggregator`): prosumer models.
  - **Models and certificates** (`solve_welfare`, `operational_oracle`, `assert_socp_exact!`,
    `assert_ac_exact!`, ...): centralized welfare solves and relaxation-exactness gates.
  - **Pricing** (`extract_dlmp`, `decompose_dlmp`, `fit_baseline`, `welfare_accounting`):
    prices recovered as duals of the nodal balance.
  - **ADMM** (`solve_admm`, `AgrOpt`, `DsoOpt`, the `ReactiveMode` namespace): the
    operational-layer decomposition.
  - **Experiments** (`Scenario`, `run_scenario`, `run_sweep`, `run_mpc`, `run_stochastic`):
    declarative scenarios, swappable strategies and provenance-stamped storage.
  - **Planning** (`solve_stackelberg!`, `run_nash!`, `SharedTransmission`): the Benders and
    Gauss-Seidel Stackelberg-Nash investment layer.
  - **Diagnostics** (`plot_convergence`, ...): method-less plot functions whose methods are
    provided by the CairoMakie extension.

# API policy

The researcher-facing entry points, data, device, model, result and error types are
exported. Advanced building blocks (problem-class singletons, per-unit base helpers,
planning components, exactness helpers, experiment builders, ...) are declared `public`:
they are documented and stable but must be qualified, e.g. `TSODSO.SOCP()`. Purely
internal helpers are reachable as `TSODSO.name` and carry no stability promise. See the API
and architecture pages of the documentation.
"""
module TSODSO

import Compat: @compat

# --- Units ---
include("units/PerUnit.jl")

# --- Data model ---
include("data/Feeder.jl")
include("data/topology.jl")

# --- Meshed feeder data model --- a SEPARATE struct from `Feeder`, gated by
# `assert_connected` instead of `assert_radial` (`Feeder`/`topology.jl` above are
# UNCHANGED). `mesh_topology.jl` must load BEFORE `MeshedFeeder.jl` (its inner
# constructor calls `assert_connected` at call time -- world-age resolution, mirroring
# `Feeder.jl`/`topology.jl`'s own documented ordering note above).
include("data/mesh_topology.jl")
include("data/MeshedFeeder.jl")

# --- Seeded profile generator ---
include("data/profiles.jl")

# --- Modified IEEE 13-node feeder fixture ---
include("data/ieee13.jl")

# --- Modified IEEE 123-node feeder fixture (scale target) ---
include("data/ieee123.jl")

# --- IEEE-8500 scale-benchmark feeder fixtures ---
# References IEEE123_SWITCH_R/IEEE123_SWITCH_X (near-ideal switch reuse), so must load AFTER
# ieee123.jl.
include("data/ieee8500.jl")

# --- Solver abstraction ---
include("solver/ProblemClass.jl")
include("solver/factory.jl")

# --- Power-flow interface ---
# Included BEFORE core/ModelContext.jl: the typed `ModelContext.pf` field needs it first.
include("powerflow/AbstractPowerFlow.jl")

# --- Core (residual seam and solve-status handling) ---
include("core/ModelContext.jl")
include("core/balance.jl")
include("core/errors.jl")
include("core/status.jl")

# --- Power-flow formulations ---
include("powerflow/DCPowerFlow.jl")
include("powerflow/LinDistFlow.jl")

# --- SOCP Convex Branch Flow formulation ---
include("powerflow/ConvexBranchFlow.jl")

# --- Independent nonconvex AC-OPF oracle (peer formulation) ---
# Included immediately after ConvexBranchFlow.jl (it references the `_SMAX_NO_LIMIT` const that
# file defines) and before problem_class_trait.jl; it adds `problem_class(::ACPowerFlow) = NLP()`.
include("powerflow/ACPowerFlow.jl")

# --- Gan-Low OPF-m restricted formulation, with optional OPF-ε margin ---
# Included right after ACPowerFlow.jl: it delegates to
# ConvexBranchFlow.contribute! and must load after it.
include("powerflow/RestrictedBranchFlow.jl")

# --- Meshed SOCP branch-flow formulation --- delegates to
# ConvexBranchFlow.contribute! (bit-for-bit identical constraint set -- ALREADY graph-generic, no
# new model-time math) and must load after it, mirroring RestrictedBranchFlow.jl's own
# ordering rationale above.
include("powerflow/MeshedFlow.jl")

# --- Power-flow → problem-class routing trait ---
# Included AFTER the powerflow formulations (needs `AbstractPowerFlow`) and after
# solver/ProblemClass.jl (needs `QP`): it maps a formulation to its solver problem class.
include("solver/problem_class_trait.jl")

# --- Devices ---
include("devices/AbstractDevice.jl")
include("devices/Interruptible.jl")

# --- Concrete prosumer devices ---
include("devices/Thermostatic.jl")
include("devices/Deferrable.jl")
include("devices/PVBattery.jl")
include("devices/FourQuadBESS.jl")
include("devices/FixedCapacitor.jl") # second q_inject consumer

# --- Aggregator roll-up: the network-facing residual writer ---
include("devices/Aggregator.jl")

# --- Models (rung 0 and rung 1 integration) ---
include("models/toy_dc.jl")
include("models/linear_solve.jl")

# --- GLB-CVX centralized social-welfare solve ---
include("models/welfare_solve.jl")

# --- SOCP relaxation exactness gate ---
include("models/exactness.jl")
include("models/complementarity_4q.jl")

# --- operational_oracle (frontier coupling dual wrapper) ---
include("models/oracle.jl")

# --- AC-exactness oracle post-processing ---
# Sits beside models/exactness.jl: reads ModelContext.pf_vars populated by BOTH the SOCP
# (ConvexBranchFlow) and AC (ACPowerFlow) solves. recover_voltage_angles recovers true
# voltage phasors; assert_ac_exact! certifies the SOCP relaxation per-hour against the AC
# oracle. Included after models/oracle.jl and before the pricing/ block.
include("models/ac_oracle.jl")

# --- Angle-recoverability a-posteriori certificate --- must
# load AFTER models/ac_oracle.jl: it generalizes that file's recover_voltage_angles BFS with
# explicit chord tracking + a per-chord closure-residual check (the loop-consistency
# mechanism a meshed MeshedFlow context needs, since the plain BFS is silently
# loop-blind -- recover_voltage_angles itself is left UNCHANGED).
include("models/mesh_angle_certificate.jl")

# --- Restricted-SOCP AC-feasibility + optimality-loss certificate ---
# Must load AFTER models/ac_oracle.jl: assert_restriction_exact! calls assert_ac_exact! internally.
include("models/restriction_exactness.jl")

# --- Nonconvex-AC-dual fallback pricer --- no ordering
# dependency on restriction_exactness.jl (it never calls the certificate), placed
# adjacent for readability. Reuses solve_welfare(..., ACPowerFlow(), ...) verbatim.
include("models/ac_dual_fallback.jl")

# --- MpcTrace: rolling-horizon price-consistency ledger ---
# JuMP-free, no ordering dependency; placed beside the other models/ files.
include("models/mpc_trace.jl")

# --- MpcWindow: build-once receding-horizon window model ---
# No ordering dependency on mpc_trace.jl (both models/ files, grouped for diff locality).
include("models/mpc_window.jl")

# --- Stochastic PV/demand two-stage extensive-form welfare builder ---
# ORCHESTRATION over already-validated builders (ConvexBranchFlow/
# ModelContext/exactness.jl/Aggregator/PVBattery, all already loaded above); no
# ordering dependency beyond those. Placed immediately after mpc_window.jl.
include("models/stochastic_welfare.jl")

# --- Distribution pricing: DLMP decomposition, FIT baseline, checks, welfare accounting ---
# Loaded AFTER models/oracle.jl (each consumes a solved
# ctx / the operational oracle). Dependency order: dlmp → fit → checks → welfare. Each file
# declares its own exports.
include("pricing/dlmp.jl")      # DLMP extraction + four-way decomposition
include("pricing/fit.jl")       # flat feed-in-tariff baseline
include("pricing/checks.jl")    # economic-direction price checks
include("pricing/welfare.jl")   # social = prosumer + DSO surplus split

# --- ADMM decomposition core: AGR-OPT / DSO-OPT subproblems + the dual-ascent loop ---
# Loaded AFTER the pricing files
# — ADMM is ORCHESTRATION over the already-validated welfare, pricing and device builders:
# it consumes the solved-ctx / `extract_dlmp` seams and reuses device / `ConvexBranchFlow`
# `contribute!` verbatim, so NO pricing source file is modified. Dependency order: residuals
# (pure data) → AgrOpt → DsoOpt → solve_admm (the loop consumes the other three). Each
# file declares its own exports.
include("admm/residuals.jl")    # AdmmResiduals primal/dual residual ledger
include("admm/ReactiveMode.jl") # OFF/CERTIFIED/LIVE 3-state enum
include("admm/AgrOpt.jl")       # per-node aggregator QP subproblem (thesis 3.46)
include("admm/DsoOpt.jl")       # whole-network SOCP subproblem (thesis 3.47)
include("admm/admm_state.jl")   # AdmmState + reactive singleton dispatch hooks
include("admm/admm_phases.jl")  # _admm_build/_admm_iterate!/_adapt_rho! named phases
include("admm/solve_admm.jl")   # hand-rolled dual-ascent loop + cross-validation

# --- Planning-layer resilience primitives: escalating retry + iteration checkpointing ---
# Loaded AFTER admm/ and
# models/oracle.jl — ORCHESTRATION over the already-validated welfare/ADMM builders:
# `solve_with_retry!` wraps `assert_solved!` verbatim, and
# `checkpoint_iteration!`/`resume_from_checkpoint` reuse `store.jl`'s `@tagsave` idiom
# verbatim. NO earlier source file is modified. `planning/subproblem.jl` MUST load AFTER
# `retry.jl` (its `solve_planning_oracle!` calls `solve_with_retry!`) — hence its position
# as the THIRD line of this block, after `retry.jl` and `checkpoint.jl`.
# `planning/follower.jl` has NO load-time dependency on `subproblem.jl` (it is a wholly
# separate LP with its own `FollowerLP` struct) but is positioned FOURTH, immediately
# after `subproblem.jl`, purely for diff stability as the planning/ block grows.
# `planning/master.jl` is positioned FIFTH, after `follower.jl` —
# `benders.jl` needs both `follower.jl` and `master.jl` loaded first, hence
# `benders.jl` is positioned SIXTH (final) in this block: it is the outer loop consuming
# all five prior planning/ files (`retry.jl`, `checkpoint.jl`, `subproblem.jl`,
# `follower.jl`, `master.jl`) via `solve_planning_oracle!`/`solve_follower!`/
# `solve_master!`/`checkpoint_iteration!` at call time.
include("planning/retry.jl")        # solve_with_retry! wraps assert_solved!
include("planning/checkpoint.jl")   # checkpoint_iteration!/resume_from_checkpoint
include("planning/trace.jl")        # BendersTrace convergence ledger (zero load-time deps, no JuMP)
include("planning/subproblem.jl")   # PlanningOracle build-once z-pin oracle
include("planning/feasibility_oracle.jl") # FeasibilityOracle slack-min feasibility-cut oracle
include("planning/ac_recheck.jl")   # ac_recheck_incumbent incumbent-only AC physics re-check
include("planning/follower.jl")     # FollowerLP transmission-reinforcement LP + Farkas certs
include("planning/master.jl")       # BendersMaster build-once epigraph + persistent cut rows
include("planning/master_integer.jl") # BendersMasterInteger binary-expansion MILP master
include("planning/benders.jl")      # solve_stackelberg! outer Benders loop
# Independent entry point (build-once + one-shot solve, no outer loop) for the
# GENUINELY bilevel TSO-DSO variant — needs only follower.jl's/
# master.jl's ALREADY-LOADED sibling files transitively (ModelContext, powerflow,
# solver); it does not itself depend on follower.jl/master.jl/benders.jl at load time,
# positioned here purely for diff-locality with the rest of planning/.
include("planning/bilevel_kkt.jl")  # BilevelKKT / build_bilevel_kkt / solve_bilevel!
include("planning/coupling.jl")     # SharedTransmission per-distributor views
include("planning/nash.jl")         # NashTrace/run_nash! outer Gauss-Seidel loop

# --- Convergence diagnostics: plotting API stubs ---
# Loaded AFTER the admm/ files — the plot functions consume the JuMP-free `AdmmResiduals`
# ledger. The core declares only method-less generic functions + exports (NO CairoMakie
# import); the CairoMakie-backed methods live in the TSODSOMakieExt weakdep extension,
# so `using TSODSO` stays plot-free.
include("diagnostics/plots.jl")

# --- Experiment harness: declarative Scenario -> swappable-strategy run -> sweep+provenance ---
# Loaded AFTER admm/ and
# diagnostics/ — the harness is ORCHESTRATION over the already-validated builders:
# run_scenario calls solve_welfare,
# solve_admm, and extract_dlmp; nothing here modifies an earlier source file. Dependency
# order: Scenario (primitive selectors) -> materialize (selectors+seed -> feeder/λ₀/aggs) ->
# run (strategy dispatch -> ScenarioResult) -> store (per-run @tagsave provenance) -> sweep
# (dict_list expansion + diff-friendly CSV collation, consumes store's run_and_store).
# Strategy types precede Scenario, which holds an AbstractStrategy.
include("experiments/strategies.jl")    # AbstractStrategy/Centralized/ADMM/MPC/Stochastic + run + supports_pf
include("experiments/Scenario.jl")      # primitive-selector Scenario struct
include("experiments/materialize.jl")   # sub_seed + build_feeder/price/population
include("experiments/run.jl")           # ScenarioResult + run_scenario dispatch
include("experiments/store.jl")         # run_and_store @tagsave provenance
include("experiments/sweep.jl")         # run_sweep + collate_summary diff-friendly CSV

# --- MPC / rolling-horizon / real-time pricing: run_mpc(scenario) closed-loop orchestrator ---
# Loaded LAST after experiments/sweep.jl: run_mpc is an INDEPENDENT
# entry point — it is NOT wired through run_scenario's strategy dispatch,
# reads Scenario's additive mpc_* fields directly, and consumes MpcWindow/
# MpcTrace plus the restricted-SOCP certificate/fallback ladder.
include("experiments/mpc_loop.jl")

# --- Stochastic PV/demand uncertainty: run_stochastic(scenario) extensive-form +
# out-of-sample orchestrator --- Loaded LAST, after
# experiments/mpc_loop.jl: run_stochastic is an INDEPENDENT entry point,
# mirroring run_mpc's own positioning — it is NOT wired through run_scenario's strategy
# dispatch, reads Scenario's additive stoch_* fields directly, and consumes
# build_stochastic_welfare/build_stochastic_oos_harness/solve_stochastic_oos_step!.
include("experiments/run_stochastic.jl")

# --- Advanced API: documented and stable but not exported (qualify as `TSODSO.name`) ---
# Declared with Compat's `@compat public` so that `public` also works on Julia 1.10.

# Units: the per-unit base and its ingestion-time conversion helpers.
@compat public PerUnitBase, Z_base, I_base, to_pu_impedance, to_pu_power

# Solver abstraction: problem-class singletons and optimizer selection.
@compat public LP,
QP,
SOCP,
NLP,
MILP,
GurobiChoice,
MosekChoice,
SCSChoice,
problem_class,
alternative_optimizer,
commercial_optimizer

# Data: fixture node sets, relabelling maps and topology helpers.
@compat public ieee123_load_nodes,
ieee123_relabel_map,
ieee8500_load_nodes,
ieee8500_mv_load_buses,
ieee8500_capacitor_buses,
ieee8500_relabel_map,
ieee8500_mv_relabel_map,
build_ieee123,
assert_connected,
markov_path

# Power-flow capability queries and balance helpers.
@compat public has_branch_current,
has_reactive,
reactive_factor,
is_flexible_load,
close_balance!

# Exactness and recovery helpers.
@compat public hybrid_ratios,
socp_gap_report,
recover_lossfree_shadow_voltage,
recover_voltage_angles,
ac_dual_fallback_price

# Pricing.
@compat public extract_reactive_dlmp

# ADMM penalty control.
@compat public set_rho!, set_rho_q!

# MPC and stochastic building blocks.
@compat public MpcTrace,
any_cert_failed,
max_jump,
mean_jump,
build_mpc_window,
solve_mpc_window!,
StochasticOosHarness,
build_stochastic_welfare,
build_stochastic_oos_harness,
solve_stochastic_oos_step!

# Experiment builders.
@compat public build_feeder, build_population, build_powerflow, build_price, sub_seed

# Planning building blocks.
@compat public PlanningOracle,
build_planning_oracle,
solve_planning_oracle!,
FollowerLP,
build_follower,
solve_follower!,
BendersMaster,
build_master,
solve_master!,
add_feasibility_cut!,
add_optimality_cut!,
BendersMasterInteger,
build_master_integer,
add_ll_cut!,
add_nogood_cut!,
apply_integer_cuts!,
FeasibilityOracle,
build_feasibility_oracle,
solve_feasibility_oracle!,
ac_recheck_incumbent,
checkpoint_iteration!,
resume_from_checkpoint,
solve_with_retry!,
RETRYABLE_STATUSES,
LADDER_ATTR_NAMES,
BilevelKKT,
build_bilevel_kkt,
solve_bilevel!,
solve_variational_equilibrium,
run_nash_probe,
activate_distributor!,
update_coupling!,
write_back!,
is_converged,
trace_summary

end # module TSODSO

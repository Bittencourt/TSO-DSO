# # Rung 7 — Nash Diagonalization & Shared Corridor
#
# This page is the PVAL-03 literate proof for the multi-distributor Nash equilibrium
# seam (NASH-01/NASH-02/NASH-03/NASH-04): it executes the real
# [`build_shared_transmission`](@ref)/[`run_nash!`](@ref)/[`run_nash_probe`](@ref)
# hand-rolled Gauss-Seidel diagonalization end-to-end during the Documenter build, on
# the SAME N=2 symmetric toy fixture `test/test_planning_nash.jl`'s own hand-checked
# regression uses, so the numbers below are genuinely solved — never a hardcoded literal
# copied from a goldens/test file (mirrors the Rung 6 page's own reproducibility-proof
# pattern, threat T-14-05).
#
# ## The shared-corridor coupling model
#
# [`build_shared_transmission`](@ref) generalizes Rung 6's single-distributor follower
# LP to `N` distributors sharing ONE pooled transmission corridor: each distributor `i`
# owns an individually-dualizable coupling row `coupling[i,t]: x_op[i,t] == z[i,t]` (its
# own delivered flow tied to its own Benders trial `z_i`) plus its own investment
# `x_inv[i]`, while the pooled capacity row
#
# ```math
# \text{capacity}[t]:\quad \sum_i x_{\text{op}}[i,t] \;\le\; \text{corridor\_cap} \cdot \sum_i x_{\text{inv}}[i]
# ```
#
# is the ONE genuinely new shared constraint — every distributor's delivered flow
# competes for one aggregate, pooled corridor capacity. Per-distributor investment
# OWNERSHIP (each distributor pays `c_inv[i]*x_inv[i]` for its own reinforcement share)
# is a deliberate departure from a naive equal-split cost sketch — see
# [`build_shared_transmission`](@ref)'s own docstring for the full rationale.
#
# ## The outer Gauss-Seidel loop
#
# [`run_nash!`](@ref) drives the diagonalization: each sweep visits every distributor
# `i` in turn (`activate_distributor!` unpins distributor `i`'s own investment ceiling
# and pins every OTHER distributor's row at its last committed value), runs a full
# single-distributor Stackelberg best-response (`solve_stackelberg!` with a
# [`DistributorView`](@ref) standing in for a standalone follower), then `write_back!`s
# the converged flow and investment before moving to the next distributor. Sweeps
# repeat until the worst-distributor residual across a full sweep falls below
# `tol_outer` (NASH-03) — there is NO general uniqueness/convergence guarantee for
# Gauss-Seidel diagonalization on a genuinely coupled game, which is exactly why NASH-04
# (below) exists.
#
# ## Two-level convergence diagnostics
#
# [`NashTrace`](@ref) is a two-level ledger: the OUTER level records each sweep's
# worst-distributor `nash_residual`; the INNER level records, for every distributor's
# own atomic best-response within that sweep, the Benders iteration count, converged
# gap, retry count, and cuts rebuilt (each best-response starts its own cut store empty
# — see [`build_shared_transmission`](@ref)'s own correctness argument for why stale
# cuts across a `z_{-i}` change would be unsound). [`trace_summary`](@ref) rolls this
# ledger into one reporting `NamedTuple`.
#
# ## NASH-04 — never present one run as canonical
#
# Gauss-Seidel diagonalization has no general convergence/uniqueness proof, so this
# project's own honesty gate, [`run_nash_probe`](@ref), runs `run_nash!` across MULTIPLE
# seeds and BOTH sweep orders and reports the MAXIMUM pairwise spread across every run —
# never a mean, never a single hand-picked run. A caller presenting results to a human
# MUST report a converged equilibrium alongside its measured spread, structurally never
# implying diagonalization certified a single, unique answer (see
# [`run_nash_probe`](@ref)'s own docstring for the full honesty argument).

using TSODSO
using TSODSO: Bus, Branch, Feeder

# ## Building the N=2 symmetric toy fixture
#
# The SAME near-lossless 2-bus feeder shape as Rung 6, reused per distributor (each
# distributor solves its own operational welfare oracle over an IDENTICAL feeder/
# aggregator pair — only the shared corridor couples them). The device is the SAME
# public `Deferrable` substitute for the certified fixture's test-only elastic device
# used on Rung 6 (`E=6.0`, `b=1.0` — equivalent to the elastic device's `a=6.0`,
# `b=1.0` since `a = b·E`, UP TO the additive constant `−(b/2)·E²` that `Deferrable`'s
# squared utility form KEEPS: the equilibrium point and all prices/duals are identical,
# only objective-level quantities carry a constant `+18` shift — see the Rung 6 page's
# reconciliation of its displayed `UB`. This page displays no objective-level
# quantities, so no number below carries that offset).

buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)]
branches = [Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT)]
feeder = Feeder(buses, branches, 1)

T = 1
dev = Deferrable(2, 1, 1, 6.0, 10.0, 1.0)
agg = Aggregator(2, 0.9, [dev], fill(0.0, T))
spec = (;
    feeder = feeder,
    pf = LinDistFlow(),
    aggregators = [agg],
    λ₀ = [4.0],
    master_kwargs = (; c_y = 0.3, y_max = 8.0, α_op_lb = -5.0, α_x_lb = 0.0),
)
specs = [spec, spec]

shared = build_shared_transmission(;
    N = 2,
    T = 1,
    corridor_cap = 2.0,
    x_inv_max = [0.3, 0.3],
    c_inv = [1.0, 1.0],
    c_op = [[0.5], [0.5]],
)

# ## Running the Gauss-Seidel loop live
#
# A cold start (`z0 = zeros(2, 1)`) — `run_nash!` builds nothing beyond the already
# build-once `shared` corridor; every sweep re-solves via `set_parameter_value`/
# `optimize!` only.

z0 = zeros(2, 1)
result = run_nash!(
    specs,
    shared;
    z0 = z0,
    tol_outer = 1e-4,
    max_sweeps = 50,
    checkpoint_dir = mktempdir(),
)

# ## Validation — a converged equilibrium
#
# Whether the outer Gauss-Seidel loop reached a converged equilibrium (the loop's own
# residual test, never an asserted iteration count):

result.converged

# The converged per-distributor coupling flows `z` — the pooled corridor's shared
# capacity binds symmetrically for both distributors on this fixture:

result.z

# The converged per-distributor investments `x_inv`:

result.x_inv

# ## NASH-04 — the multi-seed/multi-order honesty probe
#
# A single `run_nash!` call above reached ONE converged point from ONE cold start.
# NASH-04 requires reporting a converged equilibrium alongside a measured spread across
# multiple seeds and sweep orders — never presenting that one run as definitive.
# `run_nash_probe` repeats the SAME fixture from a cold start, a saturating start, and a
# skewed start, in both `:forward` and `:reverse` sweep order:

build_shared = () -> build_shared_transmission(;
    N = 2,
    T = 1,
    corridor_cap = 2.0,
    x_inv_max = [0.3, 0.3],
    c_inv = [1.0, 1.0],
    c_op = [[0.5], [0.5]],
)
seeds = (;
    zero = zeros(2, 1),
    saturating = fill(2.0 * (0.3 + 0.3) / 2, 2, 1),
    skewed = [0.5; 0.1;;],
)
orders = (:forward, :reverse)

probe = run_nash_probe(
    specs,
    build_shared;
    seeds = seeds,
    orders = orders,
    tol_outer = 1e-4,
    max_sweeps = 50,
    checkpoint_dir = mktempdir(),
)

# The probe's own honest summary string — literally constructed to say "a converged
# equilibrium", structurally never a phrase implying uniqueness (by construction — no
# run is ever singled out as canonical):

probe.summary

# The measured max-pairwise-distance spread across all 6 probe runs (3 seeds × 2
# orders) — a genuinely computed number, not an asserted bound:

probe.spread

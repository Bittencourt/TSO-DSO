# # Rung 11 — Discrete/Integer Investment Expansion (Planning)
#
# This page is Phase 24's INT-04 deliverable: it documents the genuinely new mathematics
# the phase added to the single-distributor Stackelberg-Benders planning loop — a
# binary-expansion MILP investment master, the Laporte-Louveaux "no-good cut with a
# value," the honest termination story, and a certification saga that caught (and then
# fixed) three real, stacked defects in already-merged code. Every number below comes
# from a LIVE call to [`build_master_integer`](@ref)/[`solve_stackelberg!`](@ref)/
# [`solve_planning_oracle!`](@ref)/[`solve_follower!`](@ref) during the Documenter build
# (T-24-16) — never a literal copied from a test file — and this page imports ONLY
# `TSODSO` (never importing `BilevelJuMP`, `HiGHS`, or `Ipopt`, T-24-17), mirroring
# `stackelberg_benders.jl`'s own established discipline.
#
# Substance over triumphalism: this phase's own certification effort found a genuine,
# pre-existing bug in already-merged code, and diagnosing it took three rounds, not one.
# That is presented below as a methodological result in its own right, not smoothed over.

# ## The lattice — pure binary expansion, with a documented unreachable endpoint (D-01/D-02/D-03)
#
# The leader's flexibility investment is not a single continuous variable — it is a
# binary expansion over `K` raw bits `b_1, …, b_K`:
#
# ```
# y_inv = (y_max / 2^K) · Σ_{k=1}^{K} 2^{k-1} · b_k
# ```
#
# This is a deliberate choice (D-01): the discreteness carries **no engineering
# meaning** here — it is not an attempt to model physically lumpy investment blocks or
# an explicit menu of standard sizes. It is framed purely as a **solver-behavior axis**,
# chosen because it gives a clean, interpretable diff against the continuous v2.0
# baseline as `K` grows and the lattice refines.
#
# **The divisor is `2^K`, not `2^K − 1` (D-02).** This is the "round step size"
# convention — for the default `K = 4`, `y_max = 8.0` fixture below, the step is
# `y_max / 2^K = 0.5` and the reachable lattice is the clean set
# `{0, 0.5, 1.0, …, 7.5}`. The accepted, documented consequence is that the all-ones
# corner reaches `y_max·(1 − 2^{-K}) = 7.5`, **never `y_max = 8.0` itself** — `y_max` is
# structurally unattainable on this lattice. This is stated here as an ACCEPTED
# artifact of the convention, not a bug to be "fixed" by switching the divisor. It is
# verified harmless on the canonical instance used below because the continuous optimum
# (`y* ≈ 0.7`) sits deep in the interior of `[0, 8.0]`, nowhere near the unreachable
# boundary.

using TSODSO

K = 4
y_max = 8.0
lattice = [(y_max / 2^K) * i for i in 0:(2 ^ K - 1)]

# The full K=4 reachable set — a genuinely computed range, not a hardcoded literal:

lattice

# The largest reachable point, and the gap to the nominal ceiling it never reaches:

(lattice[end], y_max - lattice[end])

# ## The genuine, non-degenerate integrality gap (D-04)
#
# This instance's continuous Stackelberg optimum is `y* ≈ 0.7` (the same golden value
# certified in `test/fixtures_planning.jl`'s `N1_Y_HAND`), and `0.7` is **not** a
# lattice point — its two lattice neighbors are `0.5` and `1.0`. The integer optimum
# on this fixture must therefore differ from the continuous one. This is stated
# plainly, not apologized for: a **zero** gap here would be the suspicious outcome,
# since it would mean the continuous optimum happened to land exactly on a lattice
# point by coincidence. A genuine gap is the expected, correct behavior of a lattice
# that does not contain the unconstrained optimum.

# ## The Laporte-Louveaux cut (Finding 1)
#
# Citation: G. Laporte and F. V. Louveaux, "The integer L-shaped method for stochastic
# integer programs with complete recourse," *Operations Research Letters* 13 (1993),
# pp. 133-142; also Birge & Louveaux, *Introduction to Stochastic Programming*, 2nd
# ed., Sec. 5.2 ("Binary First-Stage Variables"), Springer, 2011.
#
# Given an incumbent binary trial `b^ν` with "on" set `S^ν = {i : b^ν_i = 1}` and its
# EXACT recourse value `Q(b^ν)` (obtained by actually re-solving the recourse, never
# estimated), define
#
# ```
# D(b) = Σ_{i∈S^ν} b_i − Σ_{i∉S^ν} b_i − |S^ν| + 1
# ```
#
# The cut is
#
# ```
# θ ≥ (Q(b^ν) − L) · D(b) + L,    θ = α_op + α_x
# ```
#
# — written strictly over the RAW binaries `b_k` returned by
# [`build_master_integer`](@ref), **never** over the derived expression `y_inv`
# (substituting `y_inv`'s numeric value would silently break the whole combinatorial
# argument — this is the single most important correctness constraint in the phase).
# At the incumbent itself `D(b^ν) = 1`, so the cut reduces to `θ ≥ Q(b^ν)` — tight and
# exact. At every OTHER binary corner (Hamming distance `k ≥ 1` from `b^ν`),
# `D(b) = 1 − 2k ≤ −1`, and since `Q(b^ν) − L ≥ 0` the cut reduces to something
# already implied by the master's own `θ ≥ L` epigraph bound — the cut adds **zero**
# new information anywhere except at the incumbent it was derived from. This is why it
# requires no convexity assumption on `Q` at all (unlike a standard Benders cut) and
# why it delivers *finite* termination even for a smooth, non-polyhedral recourse.
# `L = α_op_lb + α_x_lb = -5.0` on this fixture — the SAME finite epigraph lower bound
# `build_master` already declares at build time (Pitfall M1), reused verbatim with zero
# new derivation, confirmed valid by measurement in plan 24-01.
#
# **Why the existing continuous `add_optimality_cut!`/`add_feasibility_cut!` cuts
# remain valid and keep firing UNCHANGED alongside the LL cut (Finding 2):**
# `Q(y_inv) = min_{0≤z≤y_inv}[α_op(z)+α_x(z)]` is a partial minimization of a
# jointly-convex function over a jointly-convex, monotonically expanding feasible set —
# hence `Q` is convex in the *continuous relaxation* of `y_inv`. Since `y_inv` is
# *linear* in the raw binaries `b`, any subgradient cut derived at a trial `z_k` is a
# globally valid supporting hyperplane over the ENTIRE continuous relaxation, hence
# valid at every one of the `2^K` binary corners. This is precisely the classical
# justification behind A. M. Geoffrion, "Generalized Benders Decomposition," *Journal
# of Optimization Theory and Applications* 10(4) (1972), pp. 237-260: master variables'
# integrality is irrelevant to a cut's *validity*, only to its *sufficiency* for finite
# termination. Laporte & Louveaux's own 1993 method explicitly retains ordinary
# L-shaped cuts alongside the new integer cut for exactly this reason — the LL cut is a
# pure ADDITION, not a replacement.

# ## The MILP exactness fix (Finding 4)
#
# HiGHS's own runtime default `mip_rel_gap` is `1e-4`, not `0.0` — left unset, the
# master's own MILP re-solve could be licensed to terminate up to `1e-4` *relative* of
# its true optimum, silently reintroducing exactly the "certificate laundering" slack a
# lattice-exact termination criterion (below) is supposed to exclude. `select_optimizer`
# in `src/solver/factory.jl` now sets `mip_rel_gap => 0.0` for every `MILP()` solve —
# a required, not cosmetic, fix for the outer loop's own exactness claim to be sound.

# ## The PVAL-04 guard lift — scoped, not deleted (D-06/D-07)
#
# The project's standing "no bare binaries outside the planning master" guard
# (`test/test_planning_noninteger.jl`) is a source-scan tripwire, not just a registry:
# it walks `src/planning/` and asserts the discovered `build_*` functions equal the
# registry keys, so a new builder cannot dodge it by omission. `build_master_integer`
# is registered exactly like every other builder, then carries an explicit,
# self-verifying `EXEMPT` allowlist entry — the exemption is a per-builder carve-out,
# never a conditional one, and it is a VERIFIED statement ("this builder genuinely has
# binaries," asserted, not merely assumed) rather than a blind skip. Every other
# builder — the operational layer and the continuous planning layer — remains
# completely binary-free, checked unmodified.

# ## How the certification caught (and fixed) three stacked defects
#
# Phase 24's own certification effort (an independent, exhaustive enumeration of all
# 16 K=4 lattice points, solving the real recourse at each) did not simply confirm the
# integer loop's correctness — it found a genuinely INVALID cut in already-merged code,
# and closing the gap took three separate, independently-discovered fixes:
#
# 1. **The recourse value handed to the LL cut was wrong.** `add_ll_cut!` requires the
#    TRUE minimized recourse `Q(y_inv(b^ν)) = min_{z∈[0,y_inv]}[...]`, but the caller
#    was passing the recourse evaluated at whatever `z` the master's CURRENT trial
#    happened to pick — an upper-bound surrogate, since the master's box constraint
#    only guarantees `z ≤ y_inv`, not `z` = the minimizer. Concretely, a fired cut at
#    the true optimal corner (`b=[1,0,0,0]`, `y=0.5`) had RHS `-0.1756`, exceeding the
#    true enumerated optimum's own total of `-0.225` — a cut that excludes the true
#    optimal lattice point is, by definition, invalid.
# 2. **An independently-discovered second defect.** Fixing (1) alone was not enough:
#    the anti-stall no-good heuristic banned ANY revisited binary corner on its second
#    visit, regardless of whether the master's own `z` there was still genuinely
#    converging — banning the TRUE optimal corner mid-refinement (its `z` moved
#    `0.195 → 0.442 → 0.497 → 0.500`, real progress) before its incumbent value ever
#    reached the true minimum, making exact convergence provably unreachable no matter
#    how correct the recourse value was.
# 3. **An independently-discovered third defect.** With (1) and (2) fixed, the
#    certified run still missed the enumerated optimum by a small, fully deterministic
#    `~7e-8` residual — traced to HiGHS's own runtime default
#    `mip_feasibility_tolerance = 1e-6`, which let the master accept a `z` up to
#    `~1e-6` outside its own box bound `z ≤ y_inv` as "feasible" at a corner whose true
#    argmin sits exactly on that boundary. Tightening it to `1e-9` closed the residual
#    to machine precision.
#
# **Why the exhaustive 256-pair (16 incumbents × 16 corners) algebra proof passed
# cleanly while the cut mechanism was still invalid:** that proof validates the cut's
# OWN algebra — tightness at the incumbent, slackness elsewhere — against a FIXED,
# already-given `Q_nu`. It has no way to see a defect in what SUPPLIES `Q_nu` to the
# cut in the first place. Testing a mechanism in isolation and testing the outcome of
# the full pipeline that feeds it are different questions; a green result on the first
# says nothing about the second. This is the transferable lesson: a per-cut algebra
# proof and a full-loop certification against an independent oracle are BOTH required,
# and neither substitutes for the other.
#
# **A finding that generalizes beyond this phase:** an outer termination criterion that
# advertises itself as *exact* silently inherits whatever slack the INNER solver leaves
# unconfigured. `mip_rel_gap` closes one such gap; `mip_feasibility_tolerance` closes a
# different one. Anyone reusing this "exact lattice termination" machinery on a new
# problem should check both defaults explicitly, not just the more famous
# `mip_rel_gap` — this project's own first pass missed the second one too.

# ## Termination — an honest negative result, and the certified fallback (D-13/D-14)
#
# The integer loop's termination criterion is explicitly NOT the continuous loop's
# inherited `tol = 1e-6` relative-gap tolerance — reusing it would be exactly the kind
# of "certificate laundering" this milestone forbids on a genuinely new mathematical
# regime. The intended criterion is a lattice-gap EXACT test: terminate when
# `UB − LB` falls below the smallest objective separation two distinct lattice points
# can produce (`δ_min`) — on a finite lattice this is an optimality PROOF, not a
# tolerance.
#
# **The honest negative result:** a rigorous, generic `δ_min` is NOT derivable for this
# problem class. By the same convexity argument as Finding 2, `Q`'s local slope at any
# point equals — by the envelope theorem — the shadow price of the box constraint
# `z ≤ y_inv`: a continuous SOCP dual price on the oracle side. Nothing in this
# project's theory establishes an a-priori Lipschitz bound on how that dual price
# varies with `z`, independent of the actual feeder/device/price data. Since the total
# objective is `F(y_inv) = c_y·y_inv + Q(y_inv)` (linear plus convex-decreasing), if the
# oracle's marginal price happens to equal `c_y` on some segment, two adjacent lattice
# points can produce an arbitrarily small — or exactly zero — true objective
# separation, with no generic formula ruling this out.
#
# **The actual termination path used here is the enumeration-backed fallback**
# (D-14): on a tractable, exhaustively-enumerable lattice, terminate when the
# incumbent MATCHES the independently enumerated optimum — exact by construction, and
# free, since the enumeration already serves as the certification oracle. **The
# accepted cost, stated plainly, not papered over:** this only works where exhaustive
# enumeration is tractable. A production termination criterion for large,
# non-enumerable lattices is an explicitly DEFERRED open item, not something this
# phase quietly solves.

# ## No-good cuts as an anti-stall fallback — honest attribution (D-16)
#
# The classical (un-weighted) no-good cut remains available as a fallback: it forbids
# exact re-visitation of a stalled binary corner but pins no objective value, so it is
# strictly weaker than the LL cut. No-good firings are always counted
# (`result.nogood_count`) and convergence is only ever ATTRIBUTED to the LL cuts
# themselves — a run that needed a no-good cut is reported as `:nogood_assisted`
# (`result.converged_via`), never presented as clean Laporte-Louveaux convergence.
# `nogood_count > 0` never fails a run; it must simply never be invisible.

# ## The BilevelJuMP secondary certificate — unavailable here, narrated, not re-executed (D-10/D-11)
#
# The primary certificate for this phase is the exhaustive enumeration executed live
# below. A `BilevelJuMP` MPEC reduction was investigated as a secondary, independent
# confirmation (as it is for the continuous Rung 6 page) and found UNAVAILABLE on this
# fixture for two independent, verified reasons — this is a documented non-blocker
# (D-10), not a coverage gap, and per CLAUDE.md's "validation oracle only, test-only
# dependency" rule, **`BilevelJuMP` is never imported anywhere in this published page**:
#
#   1. `StrongDualityMode`/`ProductMode` (Ipopt-backed) reject a binary leader
#      immediately (`MOI.UnsupportedConstraint{VariableIndex,ZeroOne}`) — Ipopt cannot
#      represent ANY discrete variable, regardless of objective linearity.
#   2. `BigMMode` (HiGHS-backed) CAN represent a binary leader in principle, but on
#      this fixture's genuinely quadratic upper-level welfare term it degrades to the
#      SAME MIQP incapacity ("Cannot solve MIQP problems with HiGHS") already
#      documented as a permanent negative regression in
#      `test/test_planning_certification.jl` — a failure that fires independently of
#      leader integrality.
#
# Both findings are verified, reproducible spikes, recorded in full in
# `test/test_planning_certification_integer.jl`'s file header and
# `24-RESEARCH.md`'s Priority Finding 3 — not re-derived or re-attempted here.

# ## Live-executed section — building the D-12-equivalent fixture
#
# The certified fixture (`Phase6Fixtures.two_bus_feeder()` +
# `ToyDeviceFixture.ToyElasticDevice`) uses test-only structs unreachable from a
# published docs page. Mirroring `stackelberg_benders.jl`'s own established pattern,
# this page reconstructs the SAME economics with the PUBLIC `Deferrable` device: its
# utility `U(p) = −(b/2)(p−E)²` expands to `a·p − (b/2)p² − (b/2)E²`, matching the toy
# device's `a·p − (b/2)p²` shape whenever `a = b·E`, plus a constant. Setting
# `E = 6.0, b = 1.0` (so `a = 6.0`, matching the certified fixture's own `a`) with
# `T = 1` reproduces the IDENTICAL equilibrium (`y*`, `z*`, and every dual/price) up to
# a constant additive shift on objective-LEVEL quantities — irrelevant here since the
# enumeration oracle below is built from the SAME public objects, so the shift cancels
# out of every comparison this page makes. No number below is copied from a test file.

using TSODSO: Bus, Branch, Feeder

buses = [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)]
branches = [Branch(1, 2, 1e-3, 1e-3, SMAX_NO_LIMIT)]
feeder = Feeder(buses, branches, 1)

T = 1
dev = Deferrable(2, 1, 1, 6.0, 10.0, 1.0)
agg = Aggregator(2, 0.9, [dev], fill(0.0, T))

λ₀ = [4.0]
follower_kwargs = (; corridor_cap = 2.0, x_inv_max = 2.0, c_inv = 1.0, c_op = [0.5])
c_y = 0.3
α_op_lb = -5.0
α_x_lb = 0.0

# ## The continuous baseline, solved live (grounds the D-04 claim above in a real number)
#
# The SAME continuous master this fixture would use in Rung 6 — `master = nothing`,
# no `known_optimum` — solved live on THIS instance, so the `y* ≈ 0.7` claim discussed
# under D-04 above is backed by a genuinely computed number in THIS page, not merely a
# citation of `stackelberg_benders.jl`'s own separate run.

result_cont = solve_stackelberg!(
    feeder,
    LinDistFlow(),
    [agg];
    λ₀ = λ₀,
    T = T,
    follower_kwargs = follower_kwargs,
    master_kwargs = (; c_y = c_y, y_max = y_max, α_op_lb = α_op_lb, α_x_lb = α_x_lb),
    tol = 1e-6,
    max_iter = 100,
    checkpoint_dir = mktempdir(),
)

result_cont.y

# ## An independent, exhaustive enumeration oracle (self-contained, built ONCE)
#
# A short, self-contained ternary-search enumeration over all `2^K` lattice points —
# the SAME technique (and the SAME `y_inv(b)` formula `build_master_integer` itself
# uses) as `test/test_planning_certification_integer.jl`'s own `enumerate_lattice`,
# reproduced here independently so this page is genuinely self-certifying, not merely
# narrating someone else's result. `Q` is convex in `z` on this fixture (concave
# oracle welfare plus convex follower cost), so ternary search converges to the true
# constrained minimum; an undeliverable trial `z` (beyond the follower's own corridor
# capacity, independent of `y_max`) is treated as `+Inf` in the extended-value sense.
#
# **One deliberate divergence from the test file's own `enumerate_lattice`, found and
# fixed while drafting this page:** the test file special-cases `y_inv <= 0` to
# `Qv = 0.0` without solving anything — valid ONLY because the certified fixture's
# test-only elastic device has ZERO utility at zero consumption. This page's PUBLIC
# `Deferrable` device does not share that property (its utility is centered on a
# nonzero target `E`, so it costs real disutility to be forced to zero), so the
# `y_inv = 0` corner is evaluated by actually calling `Qfun(0.0)` below, never assumed.

oracle = build_planning_oracle(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = T)
follower = build_follower(; follower_kwargs..., T = T)

function Qfun(z)
    fr = solve_follower!(follower, [z])
    fr.feasible || return Inf
    orr = solve_planning_oracle!(oracle, [z])
    return fr.cost - orr.cost
end

#
# **WR-01 fix (Phase 24 code review):** the naive tie-break `f(m1) < f(m2) ? (hi=m2) :
# (lo=m1)` diverges to `+Inf` whenever BOTH trial points land outside the follower's own
# deliverable capacity (`Inf < Inf` is `false`, so the tie falls to `lo = m1`, walking the
# search window AWAY from the guaranteed-feasible `z = 0` anchor and never recovering on a
# bounded interval) -- reachable via ordinary `K`/`y_max`/`corridor_cap` reconfiguration,
# dormant on this page's own specific numbers. Fixed by shrinking from the right
# (`hi = m2`) on a double-infinite tie, and by failing loudly (never silently) if the
# search still produces a non-finite value, since `z = 0` is always feasible and bounds
# `Q(y_inv)` from above.

function ternary_min(f, lo, hi; iters::Int = 100)
    for _ in 1:iters
        m1 = lo + (hi - lo) / 3
        m2 = hi - (hi - lo) / 3
        f1, f2 = f(m1), f(m2)
        if isinf(f1) && isinf(f2)
            hi = m2
        elseif f1 < f2
            hi = m2
        else
            lo = m1
        end
    end
    z = (lo + hi) / 2
    return f(z)
end

function enumerate_lattice(; K::Int = 4, y_max::Real = 8.0, c_y::Real = 0.3)
    n = 2^K
    all_totals = Vector{Float64}(undef, n)
    best_total = Inf
    best_y = NaN
    best_b = Int[]
    for i in 0:(n - 1)
        b = [(i >> (k - 1)) & 1 for k in 1:K]
        y_inv = (y_max / 2^K) * sum(2.0^(k - 1) * b[k] for k in 1:K)
        Qv = y_inv <= 0 ? Qfun(0.0) : ternary_min(Qfun, 0.0, y_inv)
        isfinite(Qv) || throw(
            ErrorException(
                "enumerate_lattice: ternary search diverged to a non-finite Q at " *
                "y_inv=$y_inv (WR-01 regression, Phase 24 code review).",
            ),
        )
        total = c_y * y_inv + Qv
        all_totals[i + 1] = total
        if total < best_total
            best_total = total
            best_y = y_inv
            best_b = b
        end
    end
    return (; best_b, best_y, best_total, all_totals)
end

enum_result = enumerate_lattice(; K = K, y_max = y_max, c_y = c_y)

# The independently, exhaustively enumerated optimum on this K=4 lattice — genuinely
# computed above, not a golden literal:

(enum_result.best_b, enum_result.best_y, enum_result.best_total)

# ## Solving the certified integer Benders loop live
#
# `build_master_integer` builds the binary-expansion MILP master ONCE (behind
# `select_optimizer(MILP())`, INFRA-02); `solve_stackelberg!` is called with
# `known_optimum = enum_result.best_total` (D-13/D-14's exact-match termination) so
# convergence is a genuine proof against the independent oracle just computed above,
# not a coincidental `gap ≤ tol` match.

imaster = build_master_integer(;
    T = T,
    K = K,
    c_y = c_y,
    y_max = y_max,
    α_op_lb = α_op_lb,
    α_x_lb = α_x_lb,
)

checkpoint_dir = mktempdir()
result = solve_stackelberg!(
    feeder,
    LinDistFlow(),
    [agg];
    λ₀ = λ₀,
    T = T,
    follower_kwargs = follower_kwargs,
    master_kwargs = NamedTuple(),
    master = imaster,
    known_optimum = enum_result.best_total,
    max_iter = 50,
    checkpoint_dir = checkpoint_dir,
)

# ## Validation — a real, live-computed answer
#
# The converged leader investment, on the K=4 lattice (compare against `result_cont.y`
# above — these are expected to differ, per D-04):

result.y

# The converged upper bound, matching the independently enumerated optimum computed
# above (both values are live-solved in this SAME page, so this comparison is a real,
# self-contained certification, not a copied literal on either side):

(result.UB, enum_result.best_total, result.UB - enum_result.best_total)

# How many Benders iterations the certified run took:

result.iters

# D-16 visibility — the no-good count and the honest convergence attribution. A count
# of `0` and `:clean` here means this run needed no anti-stall fallback; either
# outcome is legitimate and both are always surfaced, never hidden:

(result.nogood_count, result.converged_via)

# The number of genuine Laporte-Louveaux cuts fired over the course of the run — the
# mechanism whose own certification saga is narrated above:

count(c -> c.kind == :ll, imaster.cuts)

# ## D-15 certificate 1 — per-cut LL validity, checked live against the enumerated optimum
#
# The exact certificate the "three stacked defects" saga above required: every fired
# LL cut, evaluated at the TRUE enumerated optimal corner, must never claim a total
# BELOW `enum_result.best_total` there (a cut that excludes the true optimum is
# invalid by definition — this is precisely the check that caught defect 1 above,
# before it was fixed).

function D_at(b_trial::Vector{Int}, x::Vector{Int})
    S = findall(==(1), b_trial)
    Sc = setdiff(1:length(b_trial), S)
    return sum(x[i] for i in S; init = 0) - sum(x[i] for i in Sc; init = 0) - length(S) + 1
end

ll_cuts = filter(c -> c.kind == :ll, imaster.cuts)
violations = [
    (cut.b_trial, (cut.Q_nu - cut.L) * D_at(cut.b_trial, enum_result.best_b) + cut.L)
    for cut in ll_cuts if
    (cut.Q_nu - cut.L) * D_at(cut.b_trial, enum_result.best_b) + cut.L >
    enum_result.best_total + 1e-6
]

# The number of invalid cuts found live in THIS run — `0` is the correct, expected
# outcome now that all three defects are fixed:

length(violations)

# ## D-15 certificate 2 — the continuous relaxation brackets the integer answer
#
# Relaxing integrality can only improve (lower) the achievable minimum, so the
# continuous objective must be a valid lower bound on the integer one; and the integer
# solution must be a lattice neighbor of the continuous optimum (lattice step
# `y_max / 2^K`, D-04):

(result_cont.UB <= result.UB + 1e-6, abs(result.y - result_cont.y) <= (y_max / 2^K) + 1e-6)

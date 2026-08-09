# # Rung 3 — Overvoltage-Capable Relaxation: A Gan-Low OPF-m Restriction
#
# The previous page ("Rung 3: AC-Exactness Oracle") documented a genuine SOC-relaxation
# inexactness on a high-PV, reverse-flow feeder (EXACT-04): the SOCP relaxation pins a bus
# voltage at its squared upper bound and inflates a fictitious squared branch current
# `l` so that `l·v > P²+Q²` strictly, and `solve_welfare` correctly REFUSES the resulting
# prices under its default exactness gate. This page documents the mechanism that resolves
# that finding: [`RestrictedBranchFlow`](@ref), a genuine feasible-set RESTRICTION implementing
# Gan, Li, Topcu & Low's (2015) "Modified OPF" construction — *"Exact Convex Relaxation of
# Optimal Power Flow in Radial Networks,"* IEEE Trans. Automatic Control 60(1):72-87, 2015
# (arXiv:1311.7170) — Theorem 1, Theorem 2, Lemma 1, and Definition 3 (eq. 18). Every number
# shown below is RECOMPUTED live during this page's build, exactly like the previous page.

using TSODSO
using TSODSO.JuMP

# ## Building the high-PV stress fixture
#
# A small 3-bus radial feeder with low-impedance branches and tight voltage headroom, plus
# aggregators whose PV back-feed is scaled into the over-voltage regime (`pv_scale = 1.2`, the
# value the test suite settled on empirically). This is the SAME construction logic as the test
# suite's `Phase4Fixtures` high-PV fixture, and the SAME fixture the previous page builds —
# inlined here VERBATIM because literate pages do not load test-only modules.

const T = 24

mem_price = Float64[
    3.8,
    3.7,
    3.6,
    3.6,
    3.7,
    4.0,
    4.8,
    5.8,
    6.5,
    6.2,
    5.9,
    5.7,
    5.6,
    5.8,
    6.0,
    6.8,
    8.2,
    9.0,
    8.6,
    7.4,
    6.2,
    5.2,
    4.4,
    4.0,
]
temperature = Float64[
    19,
    18,
    17,
    16,
    16,
    17,
    19,
    21,
    23,
    26,
    28,
    30,
    31,
    32,
    32,
    31,
    29,
    27,
    25,
    23,
    22,
    21,
    20,
    19,
]

buses = [
    Bus(1, 0.95, 1.05, true),      # root / MEM frontier
    Bus(2, 0.95, 1.05, false),
    Bus(3, 0.95, 1.05, false),
]
branches = [
    Branch(1, 2, 0.05, 0.05, 99.0),   # low-impedance ⇒ back-feed swings voltage fast
    Branch(2, 3, 0.05, 0.05, 99.0),
]
feeder = Feeder(buses, branches, 1)

# One aggregator per non-root bus, each a Thermostatic + Deferrable + PVBattery, with the PV
# profile scaled by `pv_scale = 1.2` into the over-voltage / reverse-flow regime.

pv_scale = 1.2
aggs = map(2:length(feeder.buses)) do bus
    prof = generate_profiles(seed = 20260406 + bus, T = T)
    Ppv = Float64[pv_scale * p for p in prof.pv]
    Pdc = Float64[0.2 * d for d in prof.demand]
    therm = Thermostatic(bus, 0.2, 0.05, 15.0, 30.0, 22.0, 0.0, 1.0, 0.5, temperature)
    defer = Deferrable(bus, 8, 16, 1.0, 0.5, 0.5)
    batt = PVBattery(bus, 0.95, 1.0, 0.1, 0.0, 0.2, 0.1, 3.8, 6.2, 8.9, Ppv)
    Aggregator(bus, 0.95, [therm, defer, batt], Pdc)
end;

# ## The Gan-Low condition
#
# Gan-Low's Theorem 1 states the SOC relaxation is exact provided TWO conditions hold. **C1**
# `A_ls·A_l,s+1···A_l,t-1·u_lt > 0` for any leaf `l` and any `s,t` — a condition that depends
# ONLY on line impedances, upper bounds on power injections, and the voltage LOWER bound (never
# the upper bound `v̄`), so it is CHECKABLE A PRIORI in `O(n)` time and does not depend on the
# solution at all. **C2** every SOCP solution's power injections lie in `S_volt`, the region
# where the LOSS-FREE ("Linear DistFlow") shadow voltage `v̂_GL(s)` (Definition 3, eq. 18) —
# the voltage that WOULD result from the same injections if every branch's squared current `ℓ`
# were zero — does not exceed the physical upper bound `v̄`. Unlike C1, **C2 CANNOT be checked
# a priori**: it depends on where the optimal solution actually lands, and it is EXACTLY what
# fails in the over-voltage regime the previous page documents (voltage pinned at `V²max`, so
# the optimal injection is not in `S_volt`).
#
# Gan-Low's Theorem 2 fixes this by FORCING C2 to hold by construction: add the direct
# constraint `v̂_GL(s) ≤ v̄` (their eq. 11/12). Since Lemma 1 proves `v ≤ v̂_GL(s)` unconditionally
# for any point satisfying the true branch-flow equations with `ℓ ≥ 0`, this new constraint is
# STRICTLY MORE RESTRICTIVE than the existing `v ≤ v̄` alone — a genuine feasible-set
# restriction, never a relaxation tightening. Theorem 2 (verbatim): *"SOCP-m is exact if C1
# holds"* — no longer conditioned on C2 at all, because C2 now holds automatically. This
# structural constraint ("OPF-m") is [`RestrictedBranchFlow`](@ref)'s primary mechanism, always
# active. A simpler special case ("OPF-ε", Section IV-D) — shrinking `v`'s own upper bound by a
# single scalar `ε` (Definition 3's "modification gap," `ε := max{‖v̂_GL(s) − v‖∞}` over the
# AC-feasible set) — is PROVABLY a subset of OPF-m's feasible set and remains available as an
# OPTIONAL, composable extra margin (`RestrictedBranchFlow(; ε = ...)`, default `0.0`, off).
#
# **C1's a-priori check on this fixture.** C1 depends only on `(r, x, p̄, q̄, v̲)` — this
# fixture's impedances (`r = x = 0.05`), voltage lower bound (`v̲ = 0.95² = 0.9025`), and the
# aggregators' upper bounds on net active/reactive injection. The paper's own worked linear-chain
# example (Fig. 5 / eq. 7) reduces C1, for a 2-branch chain like this fixture's, to a single
# nontrivial `2×2` matrix-vector inequality `A₁·u₂ > 0`. This project's own research pass into
# the paper (`RESEARCH.md`, Open Question #2) did not independently re-derive that exact
# worked-example formula with enough confidence to plug this fixture's specific PV-nameplate /
# battery-discharge upper bounds into it here — rather than fabricate a numeric "C1 margin" that
# was never actually derived from the paper's formula (a real risk this page's own threat model
# flags, T-20-14), this page substitutes an honestly-scoped alternative: it LIVE-RECOMPUTES the
# same measured modification gap `ε` that plan 20-01 first measured, using the identical recipe
# (an independently-solved [`ACPowerFlow`](@ref) point, then [`recover_lossfree_shadow_voltage`](@ref)),
# inlined here so the number can never silently drift from the code that produces it.

ctx_ac_for_ε, _, _ = solve_welfare(
    feeder,
    ACPowerFlow(),
    aggs;
    T = T,
    λ₀ = mem_price,
    allow_local = true,
    allow_export = true,
)
v̂_GL_check = recover_lossfree_shadow_voltage(ctx_ac_for_ε)
pv_ac_for_ε = ctx_ac_for_ε.meta[:pf_vars]
N = length(feeder.buses)

# Lemma 1 sanity check (`v ≤ v̂_GL(s)` everywhere — the number below must be `≥ 0`, up to solver
# noise):

lemma1_mingap = minimum(
    v̂_GL_check[j, t] - value(pv_ac_for_ε.v[j, t]) for j in 1:N, t in 1:T
)

# The measured modification gap itself (Definition 3, eq. 18), recomputed live on THIS fixture:

ε_measured = maximum(
    v̂_GL_check[j, t] - value(pv_ac_for_ε.v[j, t]) for j in 1:N, t in 1:T
)

# **This live `ε_measured` is a real, citable, non-fabricated number confirming the modification
# gap is small and strictly positive on this fixture's actual parameters — consistent with C1
# holding — but it is NOT a substitute for C1's own a-priori algebraic check.** This page states
# explicitly, per RESEARCH.md's own honest-fallback recommendation: **C1's full symbolic
# verification on this fixture's specific injection bounds is DEFERRED**, not performed here. The
# citable expectation that C1 holds is drawn from the literature, not an independent re-derivation
# on this fixture: Gan-Low's own Section VI empirically finds C1 holds with a comfortable margin
# (`η* > 1.3`, often `> 10`) on every IEEE 13/34/37/123-bus test network they tried, including
# networks with over 130% DG penetration — and OPF-m's own measured success below (the SOC cone
# closing to noise-floor scale) is itself consistent with, though not a formal proof of, C1
# holding here too.

# ## Solving all three formulations on the same data
#
# `ConvexBranchFlow(rtol_exact = 1.0)` is the SAME diagnostic override the previous page uses —
# it exposes the loose, genuinely-inexact SOCP relaxation solution for comparison instead of
# having `solve_welfare` refuse it. `ACPowerFlow()` is the independent nonconvex ground truth.
# `RestrictedBranchFlow()` uses its DEFAULT constructor — no explicit `ε` override — proving the
# OPF-m mechanism alone (Theorem 2, no tunable margin) is sufficient on this fixture.

ctx_socp, cost_socp, _ = solve_welfare(
    feeder,
    ConvexBranchFlow(),
    aggs;
    T = T,
    λ₀ = mem_price,
    allow_export = true,
    rtol_exact = 1.0,
)

ctx_ac, cost_ac, _ = solve_welfare(
    feeder,
    ACPowerFlow(),
    aggs;
    T = T,
    λ₀ = mem_price,
    allow_local = true,
    allow_export = true,
)

ctx_restricted, cost_restricted, _ = solve_welfare(
    feeder,
    RestrictedBranchFlow(),
    aggs;
    T = T,
    λ₀ = mem_price,
    allow_export = true,
)

# ## The free PF-04 signal
#
# `assert_socp_exact!` (PF-04) is the EXISTING, UNMODIFIED cone-exactness gate — it needs no new
# code to certify `RestrictedBranchFlow`'s solution, because `solve_welfare` already runs it
# internally on every SOCP-class formulation and stashes the result under `ctx.meta[:socp_maxgap]`.
# Contrast the unrestricted diagnostic solve's gap against the restricted solve's gap:

ctx_socp.meta[:socp_maxgap]

#-

ctx_restricted.meta[:socp_maxgap]

# The unrestricted relaxation's gap is orders of magnitude above the benign-feeder noise floor —
# the direct numerical signature of the fictitious over-current the previous page documents.
# `RestrictedBranchFlow`'s gap collapses to noise-floor scale, a FREE validation signal requiring
# zero new certificate code: OPF-m's structural `v̂_GL(s) ≤ v̄` constraint forces the SOC cone
# itself tight, exactly as Theorem 2 predicts.

# ## The OVR-02 certificate
#
# [`assert_restriction_exact!`](@ref) is a NEW, NAMED certificate (peer to `assert_socp_exact!`
# and `assert_ac_exact!`) that certifies the PHYSICAL AC-feasibility of the restricted solution
# (the same cone-tightness residual as PF-04, but with its OWN independently-measured
# tolerances) and separately reports whether the restricted DISPATCH matches the independently-
# solved AC optimum, plus the optimality loss versus an unrestricted bound. Called live here
# with `report = true` so a genuine certificate failure would print a diagnostic instead of
# throwing (it does not fail on this fixture, but the call is defensive regardless):

restriction_report = assert_restriction_exact!(
    ctx_restricted,
    ctx_ac;
    unrestricted_cost = cost_socp,
    report = true,
)

#-

restriction_report.ac_feasible

#-

restriction_report.matches_ac_optimum

#-

restriction_report.optimality_loss

# **Two DISTINCT questions, two DISTINCT, both now-measured answers on this fixture:**
# `ac_feasible` asks "is the restricted solution a genuine, physically-realizable branch-flow
# point?" — YES, because OPF-m's structural constraint forces the SOC cone tight (the same
# signal the free PF-04 check above shows). `matches_ac_optimum` asks the STRICTLY HARDER
# question "does the restricted dispatch reproduce the SAME operating point the independent AC
# oracle finds optimal?" — on this fixture the answer is NO during the high-PV window, because
# Gan-Low's restriction is a genuine, provable feasible-set SUBSET (`F_{OPF-m} ⊆ F_OPF`) that
# excludes the true AC optimum exactly where it actively binds. `optimality_loss` quantifies
# that divergence in welfare terms against the unrestricted (loose) SOCP relaxation's own bound.

# ## Fallback semantics
#
# [`ac_dual_fallback_price`](@ref) is the documented fallback pricer for the case
# `assert_restriction_exact!` genuinely FAILS its `ac_feasible` gate (D-09) — i.e. when even
# OPF-m's restricted cone is not tight, so no dual price can be trusted as a genuine AC operating
# point. It is a second, seeded, nonconvex re-solve of the SAME `ACPowerFlow()` path already
# used above, from up to 5 distinct deterministic Ipopt convergence-strategy starts (default
# `n_seeds = 2`; the CI-gated cheap subset), tagging its result
# `price_status = :local_ac_dual` and returning a mandatory `agreement_report` comparing the
# seeds. It is NEVER invoked automatically by `assert_restriction_exact!` or by `solve_welfare`
# — the CALLER decides whether to route to it, gated on `restriction_report.ac_feasible`.
#
# On THIS fixture `restriction_report.ac_feasible` is `true` (confirmed above), so the fallback
# is NOT triggered here — deliberately: triggering a fallback that is not needed would misrepresent
# what this fixture's mechanism actually requires. Its soundness is documented as evidence from
# elsewhere in this phase instead: a quarantined 5-seed sweep on this same fixture (exercised via
# a synthetic certificate-failure, `.planning/spikes/004-ovr-fallback-multistart/`) found all 5
# seeds agree to `~1e-7` (`max_cost_spread ≈ 3.84e-7`, `max_dadp_spread ≈ 1.05e-7`) — strong
# evidence the fallback mechanism itself is numerically stable and trustworthy on this fixture's
# regime, for the fixtures/scenarios where OPF-m's own certificate genuinely does fail.

# ## Finding
#
# EXACT-04 — the high-PV, reverse-flow feeder that the previous page found the plain SOC
# relaxation genuinely, physically inexact on — is now PRICEABLE via a genuine restriction of
# the convex feasible set, not a relaxation hack: Gan-Low's OPF-m mechanism
# (`v̂_GL(s) ≤ v̄`, Theorem 2) forces condition C2 to hold by construction, closing the SOC cone
# to noise-floor scale (the free PF-04 signal above) with NO tunable parameter to search (D-03).
# This is a STRICTLY MORE POWERFUL result than the simpler OPF-ε special case this project's own
# research first attempted: an exhaustive sweep of every feasible `ε` (documented in plan
# 20-02's summary) found the bound-shrink mechanism alone could not close this fixture's gap at
# ANY feasible value — the residual stayed six orders of magnitude above the exactness gate even
# at the largest feasible `ε`, because EXACT-04's dominant residual is driven by reverse power
# flow, not primarily by voltage pinning at `v`'s own bound. That honest negative result is a
# citable finding in its own right, not a discarded false start: OPF-ε remains available,
# retained as an optional composable margin on top of OPF-m, for a researcher on a DIFFERENT
# fixture where the simpler mechanism alone might suffice.
#
# The measured optimality loss (`restriction_report.optimality_loss` above) quantifies exactly
# how far the restricted dispatch's welfare diverges from the unrestricted relaxation's own bound
# during the window where OPF-m's restriction genuinely binds — a real, principled, honestly
# reported number, not zero, because `matches_ac_optimum = false` there. The fallback semantics
# section above documents when a DIFFERENT fixture or scenario should route to
# `ac_dual_fallback_price` instead: whenever `assert_restriction_exact!`'s `ac_feasible` gate
# itself fails, which does not happen on THIS fixture, but which the fallback's own quarantined
# multi-seed evidence confirms is a sound, trustworthy pricer when it is needed.

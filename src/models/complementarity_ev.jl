# src/models/complementarity_ev.jl
#
# SEAM: post-solve complementarity certificate for V2G ElectricVehicle devices (peer of
# complementarity_4q.jl / the battery certificate in welfare_solve.jl).
#
# WHAT IT CERTIFIES. `ElectricVehicle` (V2G) carries NO `p_ch·p_dch == 0` constraint and NO binary
# (either would break QP convexity and the duals that ARE the transactive prices). Absence of
# simultaneous charge/discharge rests on the strict App. C parametrization plus `c_deg > 0`, which
# only holds at NON-NEGATIVE effective prices: at a sufficiently negative price an SOC-neutral
# round trip earns (1 − η²)(λ_med + |λ|) − η²·c_deg > 0 and co-charge is the KKT-consistent
# optimum (the repo's own App. C η<1 finding, welfare_solve.jl:309-321). This certificate VERIFIES
# `p_ch[t]·p_dch[t] < τ_ev·Pmax²` after every solve and REPORTS the honest boundary.
#
# SELECTION. Trait-routed over the type-paired device stash (`ctx.agg_device_types`, 43-01): an
# entry is EV-checked iff its paired type has `storage_kind === :ev` AND it carries a `p_dch`
# leg (V1G has none, so it is trivially compliant). There is NO legacy shape fallback: the EV is a
# new device and its vars would false-match the battery shape, which is exactly why the battery
# and 4Q selectors route on the trait instead.
#
# SCALE-FREE TEST. `p_ch`, `p_dch` and `Pmax` scale identically with the per-unit base, so the
# ratio `p_ch·p_dch / Pmax²` is base-invariant (same argument as welfare_solve.jl:324-336). Pmax is
# recovered as the largest `upper_bound` over the horizon (outside the session window the bound is
# 0, so index 1 is NOT representative).
#
# TOLERANCE PROVENANCE (MEASURED, never a peer's constant -- the certificate-laundering bar).
# `TAU_EV` is a DIFFERENT regime from the battery τ (1e-6 QP / 1e-3 SOCP) and the 4Q rtol/atol:
# a different device, a different parametrization (session window + c_deg), a different numerical
# floor. Measured (2026-11-02) on the centralized two-bus + V2G-EV-only fixture
# (`solve_welfare`, ConvexBranchFlow, T = 24, Pmax = 0.02 pu, Emax = 0.08, wrap window 18 -> 8,
# c_deg = 0.05, App. C triple 3.8/6.2/8.9, seeds SEED_2BUS .. SEED_2BUS+4 = 20260719..23).
# Quantity: max_t p_ch[t]·p_dch[t] / Pmax² over the horizon, COMPLIANT solves only.
#
#   regime                                    seed   max ratio       Σp_dch
#   flat λ₀ = 4 (no arbitrage; interior)      all    ≤ 1.3e-13       ~1e-13
#   swing λ₀ (1 | 4 | 12 by hour), soc0=0.06 .719   1.21e-8         0.0280
#                                             .720   1.61e-8         0.0280
#                                             .721   7.2e-10        0.0280
#                                             .722   1.75e-8        0.0280
#                                             .723   4.3e-10        0.0280
#   swing λ₀, soc0 = 0.04                     max    6.4e-9         0.0280
#
# The GENUINE-dispatch regime (both legs used, in different hours) sets the floor: ≤ 1.75e-8
# (scale-relative). `TAU_EV = 2e-7` sizes ~an order (≈11×) above that floor (mirrors
# `assert_socp_exact!`'s sizing discipline) and is a much tighter test than the SOCP-path battery
# τ = 1e-3: a co-charge leg pair above ~0.045% of Pmax on each side already trips it. The negative-
# price co-charge fixture sits at ratio ≈ 0.8 of Pmax² -- ~4e6× above TAU_EV, unambiguous.
# ADMM final-consolidation sizing is recorded where it is measured (test_electricvehicle.jl).
#
# Reads `ctx.agg_device_vars`, `ctx.agg_device_types`, `ctx.T`. Uses `CertificateError` (never
# `@assert`) per project convention.

"""
    TAU_EV

Default relative tolerance of [`assert_ev_complementarity!`](@ref) (fraction of `Pmax²`), measured
on the compliant V2G two-bus fixtures -- see this file's provenance header.
"""
const TAU_EV = 2e-7

"""
    assert_ev_complementarity!(ctx::ModelContext; τ::Real = TAU_EV, T::Int = _require_T(ctx),
                               on_violation::Symbol = :error, report::Bool = false) -> Float64

Verify `value(p_ch[t])·value(p_dch[t]) < τ·Pmax²` for every V2G `ElectricVehicle` in the type-paired
device stash. Returns the worst observed ratio `p_ch·p_dch / (τ·Pmax²)` (so `> 1` means a
violation; `0.0` when no V2G EV is present -- a no-op on EV-free populations).

On a violation: `on_violation = :error` throws `CertificateError(; kind = :ev)`, `:warn` logs a
warning; `report = true` neutralizes BOTH (the 4Q contract) and only returns the ratio -- the
honesty-policy vehicle for fixtures where co-charge is the genuine optimum.
"""
function assert_ev_complementarity!(
    ctx::ModelContext;
    τ::Real = TAU_EV,
    T::Int = _require_T(ctx),
    on_violation::Symbol = :error,
    report::Bool = false,
)
    on_violation in (:error, :warn) || throw(
        ArgumentError(
            "assert_ev_complementarity!: invalid on_violation=$(repr(on_violation)), expected :error or :warn",
        ),
    )
    !isempty(ctx.agg_device_vars) || return 0.0

    maxratio = 0.0
    for (bus, varlist) in ctx.agg_device_vars
        types = get(ctx.agg_device_types, bus, nothing)
        for (i, v) in enumerate(varlist)
            _stash_entry_has_kind(types, v, i, :ev, _ -> false) || continue
            haskey(v, :p_dch) || continue          # V1G: no discharge leg, compliant by build
            pmax = 0.0
            for t in 1:T
                has_upper_bound(v.p_ch[t]) && (pmax = max(pmax, upper_bound(v.p_ch[t])))
            end
            pmax > 0 || (pmax = 1.0)               # degenerate (all-zero/absent bounds) guard
            scale² = max(abs(pmax), 1e-8)^2
            for t in 1:T
                prod = value(v.p_ch[t]) * value(v.p_dch[t])
                ratio = prod / (τ * scale²)
                maxratio = max(maxratio, ratio)
                prod < τ * scale² && continue
                report && continue
                msg =
                    "EV complementarity violated at bus $bus, t=$t: " *
                    "p_ch·p_dch = $prod ≥ τ·Pmax² = $(τ * scale²) (relative τ=$τ, Pmax≈$pmax); " *
                    "at a negative effective price with η<1 an SOC-neutral round trip is the " *
                    "KKT-consistent optimum — the honest V2G boundary (App. C η<1 finding), " *
                    "not necessarily a bug"
                if on_violation === :error
                    throw(CertificateError(msg; kind = :ev))
                else
                    @warn msg
                end
            end
        end
    end
    return maxratio
end

export assert_ev_complementarity!

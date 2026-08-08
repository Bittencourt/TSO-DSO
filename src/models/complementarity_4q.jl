# src/models/complementarity_4q.jl
#
# SEAM: 4Q-BESS post-solve complementarity certificate (MESH-04 clause 2).
# OWNER: plan 19-05.
#
# Defines `assert_4q_complementarity!(ctx; rtol, atol, report)`: a NEW, named certificate,
# a peer of `assert_socp_exact!` (`exactness.jl`) and `assert_battery_complementarity!`
# (`welfare_solve.jl`), that numerically checks `p_ch[t]·p_dch[t] ≈ 0` for every
# `FourQuadBESS` stashed under `ctx.meta[:agg_device_vars]` — selected by its OWN,
# distinguishing `:q` key (a `PVBattery`'s vars never carry `:q` and are never touched
# here; `welfare_solve.jl`'s OLD check is symmetrically tightened to skip anything WITH
# `:q`). Its `rtol`/`atol` defaults are MEASURED against this device's own Clarabel-solved
# noise floor on a benign fixture (D-07) — never copied from `assert_battery_complementarity!`'s
# `Pmax²`-scaled constant (certificate-laundering guard, T-19-10). Throws by default
# (`error`, never `@assert`); a `report = true` kwarg neutralizes the throw into a `@warn`
# without any other `src/` edit (D-06), so the honest negative-price + grid-charging
# boundary the `FourQuadBESS.jl` derivation docstring predicts (D-08) can be surfaced as a
# diagnostic rather than muted.
#
using JuMP

"""
    assert_4q_complementarity!(ctx::ModelContext; rtol::Real = 1e-6, atol::Real = 1e-6,
                                T::Int = ctx.meta[:T], report::Bool = false)
        -> maxratio::Float64

Certify the App. C-style no-simultaneous-charge/discharge condition `p_ch[t]·p_dch[t] ≈ 0`
for every `FourQuadBESS` at a solved point, and REFUSE (throw) when it is violated — the
peer, 4Q-specific certificate MESH-04 clause 2 requires (`assert_socp_exact!` is the SOCP-
cone peer; `assert_battery_complementarity!` is the `PVBattery`-only peer this function
does NOT replace, it TIGHTENS its selection instead — see below).

Iterates `ctx.meta[:agg_device_vars]` (a `Dict{Int,Vector{Any}}` keyed by bus, populated by
`Aggregator.contribute!`) and selects ONLY the 4Q shape: `haskey(v,:p_ch) && haskey(v,:p_dch)
&& haskey(v,:q)`. The `:q` key is the SOLE distinguishing field — a `PVBattery`'s vars
(`(;p_ch,p_dch,soc,pv_used)`) never carry it and are therefore NEVER touched by this
function; `assert_battery_complementarity!`'s loop condition is symmetrically tightened
(`welfare_solve.jl`) to skip anything WITH `:q`, so the two checks are structurally mutually
exclusive over the same stash (T-19-11) — never both silently matching the same device.

For each selected device and `t ∈ 1:T`, computes `gap = value(p_ch[t])·value(p_dch[t])` and
an `isapprox`-style COMBINED WR-01 tolerance scaled by the device's OWN rating:

    scale = max(Pch_max, Pdch_max)     # recovered via has_upper_bound/upper_bound, mirrors
                                        # assert_battery_complementarity!'s Pmax recovery
    tol   = atol + rtol · scale²

mirroring `assert_socp_exact!`'s `atol + rtol·max(...)` COMBINED-bound shape (an absolute
floor plus a scale-relative fraction) rather than `assert_battery_complementarity!`'s
single-`Pmax` shape, because `Pch_max` and `Pdch_max` are INDEPENDENT for a `FourQuadBESS`
(D-02/D-04) and can differ. On violation (`gap > tol`) it raises a loud `error(...)` naming
the bus/time/values/tolerance and REFUSES to return a clean diagnostic — UNLESS `report =
true`, which replaces the `error(...)` with an `@warn` carrying the SAME message and lets
the loop continue (D-06's neutralization kwarg — no other `src/` edit needed to opt into
diagnostic mode). Returns `maxratio = maxₜ gap/tol` over every checked device/time — the
worst observed gap-to-tolerance ratio, mirroring `assert_socp_exact!`'s "return a
diagnostic on success" contract (in `report` mode this is returned even when it exceeds 1,
so a caller can inspect HOW badly a fixture violated the certificate without an exception).
Is a no-op (`maxratio` stays `0.0`) when `ctx.meta[:agg_device_vars]` is absent or contains
no 4Q device.

# Tolerance provenance (D-07, T-19-10 — measurement, not a copy)

`assert_battery_complementarity!`'s relative tolerance `τ` (`1e-6` QP-path / `1e-3` SOCP-
path, scaled by `PVBattery`'s `Pmax²`) is a DIFFERENT device's constant, calibrated against
a DIFFERENT device's numerical behavior — reusing it here would be certificate-laundering
(the v3.0 standing bar: every new mathematical regime earns its OWN measured tolerance).
This function's `rtol`/`atol` defaults were instead measured directly against a benign,
strictly-App.-C-dominated `FourQuadBESS` fixture (one device, standalone `ModelContext`,
`SOCP()`/Clarabel, `@objective(m, Max, res.utility - λ_test*sum(res.p_inject))` with a
POSITIVE in-band `λ_test` swept across 5 representative values spanning the device's own
`λ_min..λ_max` band — no grid-charging incentive, no negative price). The observed
Clarabel-solved `p_ch[t]·p_dch[t]` noise floor at that benign optimum, on a device with
`Pch_max=4, Pdch_max=5` (`scale² = 25`):

    λ_test=1.5  max|p_ch·p_dch| ≈ 2.53e-9   (relative to scale²: ≈ 1.01e-10)
    λ_test=2.5  max|p_ch·p_dch| ≈ 1.82e-9   (relative to scale²: ≈ 7.28e-11)
    λ_test=4.0  max|p_ch·p_dch| ≈ 9.67e-10  (relative to scale²: ≈ 3.87e-11)
    λ_test=6.0  max|p_ch·p_dch| ≈ 5.09e-10  (relative to scale²: ≈ 2.04e-11)
    λ_test=8.5  max|p_ch·p_dch| ≈ 2.91e-10  (relative to scale²: ≈ 1.16e-11)

i.e. the absolute noise floor sits ≤ ~2.6e-9 and the scale-relative noise floor sits
≤ ~1.1e-10 across the swept band. The chosen defaults `atol = 1e-6` and `rtol = 1e-6`
clear these with ~3 orders of margin (`atol`) and ~3-4 orders of margin (`rtol` on
`scale²`) respectively (mirrors `assert_socp_exact!`'s "an order below/above the measured
floor" sizing discipline) while remaining independent of, and TIGHTER than,
`assert_battery_complementarity!`'s SOCP-path `τ = 1e-3` — this certificate is not a
loosened copy of that one.

Reads `ctx.meta[:agg_device_vars]` and `ctx.meta[:T]`. Uses an explicit `error(...)` (never
`@assert`, elided under `-O`), per project convention (`src/core/status.jl`).
"""
function assert_4q_complementarity!(
    ctx::ModelContext;
    rtol::Real = 1e-6,
    atol::Real = 1e-6,
    T::Int = ctx.meta[:T],
    report::Bool = false,
)
    haskey(ctx.meta, :agg_device_vars) || return 0.0

    maxratio = 0.0
    for (bus, varlist) in ctx.meta[:agg_device_vars]
        for v in varlist
            (haskey(v, :p_ch) && haskey(v, :p_dch) && haskey(v, :q)) || continue   # a 4Q device
            # Rated charge/discharge power (D-02/D-04: INDEPENDENT bounds) — the base-scaling
            # reference. The atol floor guards a (degenerate) zero/absent upper bound against
            # a div-by-zero, mirroring assert_battery_complementarity!'s Pmax recovery.
            pch_max = has_upper_bound(v.p_ch[1]) ? upper_bound(v.p_ch[1]) : 1.0
            pdch_max = has_upper_bound(v.p_dch[1]) ? upper_bound(v.p_dch[1]) : 1.0
            scale = max(abs(pch_max), abs(pdch_max), 1e-8)
            tol = atol + rtol * scale^2
            for t in 1:T
                prod = value(v.p_ch[t]) * value(v.p_dch[t])
                ratio = prod / tol
                maxratio = max(maxratio, ratio)
                prod <= tol && continue
                msg =
                    "4Q-BESS complementarity violated at bus $bus, t=$t: " *
                    "p_ch·p_dch=$prod exceeds atol+rtol·scale²=$tol " *
                    "(rtol=$rtol, atol=$atol, scale=$scale) — MESH-04 clause 2; if this " *
                    "fixture has a negative effective nodal price and grid-charging " *
                    "enabled, this MAY be the honest boundary D-08 documents rather than " *
                    "a bug — see FourQuadBESS.jl's complementarity derivation docstring"
                if report
                    @warn msg
                else
                    error(msg)
                end
            end
        end
    end
    return maxratio
end

export assert_4q_complementarity!

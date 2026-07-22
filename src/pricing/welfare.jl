# src/pricing/welfare.jl
#
# SEAM: welfare accounting — social = prosumer + DSO surplus split (PRICE-03).
# OWNER: plan 05-05.
#
# Empty (comment-only) stub wired onto the include graph in plan 05-01. Plan 05-05 fills
# it and declares its own `export`s. It will export:
#   - `welfare_accounting(ctx; T, ...)` — split the social welfare into prosumer surplus and
#     DSO surplus from a solved ctx. Prosumer surplus = Σ_j U_agⱼ − Σ_j Σ_t λ_j[t]·p_agⱼ[t]
#     (thesis eqs. 3.46/3.47), where Σ_j U_agⱼ = value(ctx.meta[:objective]) and the
#     price-transfer term reads the per-aggregator net injection p_agⱼ[t] stashed under
#     `ctx.meta[:agg_net]` (the additive Phase-4 seam from plan 05-01) priced at the DADP
#     λ_j[t]; the surplus-identity (prosumer + DSO == social) is the correctness net.
#
# Consumes ONLY the additive `ctx.meta[:agg_net]` stash + the registered `:balance_p` dual —
# no change to `solve_welfare`. DISTINCT from the Phase-3 operational solve
# (models/welfare_solve.jl): this is post-solve ACCOUNTING, not the optimization.

using JuMP

"""
    welfare_accounting(ctx::ModelContext; T = ctx.meta[:T], λ₀ = nothing,
                       baseline = nothing, rtol = 1e-4, atol = 1e-4,
                       _transfer_flip = false)
        -> (; social, dso, prosumer[, ratio])

Split the solved GLB-CVX welfare (thesis eq. 3.38) into **prosumer** and **DSO** surplus
(PRICE-03), asserting the exact accounting identity

    social  ==  prosumer + dso  ==  objective_value(ctx.model)      (within a relative tol)

Reads only stashed primals/duals — **no re-solve**. The three quantities (thesis page 98):

  - `social`   = `objective_value(ctx.model)` — the GLB-CVX social welfare (3.38);
  - `prosumer` = `Σ_j U_agⱼ + Σ_j Σ_t λ_j[t]·p_agⱼ[t]` — the AGR-OPT value (3.46), where
    `Σ_j U_agⱼ = value(ctx.meta[:objective])` and the price-transfer term prices each
    aggregator's net INJECTION `p_agⱼ[t]` (`net = p_inject − Pdc`, `ctx.meta[:agg_net]`, plan
    05-01) at the DADP `λ_j[t] = extract_dlmp(ctx)`. The transfer is **added** (not subtracted):
    a net-EXPORTER (net>0) at a positive λ EARNS `λ·net`, an importer PAYS it — thesis 3.46
    prices net DEMAND (= −net injection), so with the net-injection stash the sign flips to `+`;
  - `dso`      = `−Σ_j Σ_t λ_j[t]·p_agⱼ[t] − Σ_t λ₀[t]·p_import[t]` — the −DSO-OPT value (3.47):
    the DSO's MEM revenue at the frontier minus what it pays prosumers for their net injection
    (it collects the DLMP−wholesale spread).

The `Σ_j λ_j·p_agⱼ` **price-transfer cancels** between `prosumer` (`+transfer`) and `dso`
(`−transfer`), leaving `Σ_j U_agⱼ − Σ_t λ₀[t]·p_import[t]` = the GLB-CVX objective (3.38).

**The `social == prosumer + dso` identity is ALGEBRAICALLY VACUOUS for the surplus-SPLIT sign**
(WR-01): the transfer cancels for EITHER sign convention, so the sum-identity alone CANNOT
catch a flipped single-settlement transfer — that is a *dual*-consistency / dropped-term gate
(it fires on a term present in one settlement but not the other), NOT a split-sign gate. The
INDIVIDUAL surplus signs/values are what pin the economics (exporter earns, importer pays); the
`test/test_pricing_welfare.jl` suite asserts those directly. The `_transfer_flip` hook is a
SELF-TEST that mis-signs the transfer in the DSO settlement ONLY (breaking the cancellation by
introducing an asymmetry) so the sum-identity assertion fires — proving THAT assertion is
non-vacuous for its actual purpose (a one-sided term error; threat T-05-03).

`λ₀` (the MEM/wholesale price) defaults to the root DADP `extract_dlmp(ctx)[root, t]` — the
thesis "energy component = dual(balance_p[root,t])"; at the priced-frontier optimum it equals
the true λ₀ by KKT, and using it keeps the identity a genuine dual-consistency check. Pass an
explicit `λ₀` to use the wholesale profile directly.

When `baseline` is a solved FIT context (from [`fit_baseline`](@ref), plan 05-03) the result
additionally carries `ratio = social / baseline.social_fit` — the headline +25%-social-welfare
number (thesis Case A ≈ 1.25), reported as a COMPUTED ratio (see the test's pinned golden +
non-failing thesis cross-check).

Throws (never `@assert`) on a missing stash, a non-finite / out-of-band surplus (Pitfall 5),
or a violated surplus identity — reporting the mismatch magnitude so a sign/term bug is
localizable. Inherits the PF-04 exactness gate from [`extract_dlmp`](@ref) (an ungated SOCP
ctx is refused).
"""
function welfare_accounting(
    ctx::ModelContext;
    T::Int = ctx.meta[:T],
    λ₀ = nothing,
    baseline = nothing,
    rtol::Real = 1e-4,
    atol::Real = 1e-4,
    _transfer_flip::Bool = false,
)
    for key in (:agg_net, :objective, :p_import, :feeder)
        haskey(ctx.meta, key) || throw(
            ArgumentError(
                "welfare_accounting: ctx.meta is missing :$key — this is not a solved " *
                "solve_welfare ModelContext carrying the plan 05-01 surplus stash " *
                "(thesis 3.38/3.46/3.47).",
            ),
        )
    end

    feeder = ctx.meta[:feeder]
    root = feeder.root

    # Per-node DADP λ_j[t] (runs the PF-04 exactness gate; refuses an ungated SOCP ctx).
    λ = extract_dlmp(ctx)                              # (N, Tfull) matrix
    Tfull = size(λ, 2)
    T <= Tfull || throw(
        ArgumentError("welfare_accounting: T=$T exceeds the solved horizon Tfull=$Tfull"),
    )

    # MEM/wholesale price λ₀[t]: use the passed profile, else recover the ENERGY component
    # from the root DADP (thesis energy = dual(balance_p[root,t]); = λ₀ at the priced optimum).
    λ0 =
        λ₀ === nothing ? Float64[λ[root, t] for t in 1:T] :
        Float64[float(λ₀[t]) for t in 1:T]
    length(λ0) >= T ||
        throw(ArgumentError("welfare_accounting: λ₀ has length $(length(λ0)) < T=$T"))

    # Priced-frontier import p_import[t] (free-sign with allow_export) and its MEM cost.
    pimp = value.(ctx.meta[:p_import])
    mem_cost = sum(λ0[t] * pimp[t] for t in 1:T)      # Σ_t λ₀[t]·p_import[t]

    # Price-transfer Σ_j Σ_t λ_j[t]·p_agⱼ[t] (thesis 3.46/3.47) — the term that cancels.
    transfer = 0.0
    for entry in ctx.meta[:agg_net]
        b = entry.bus
        (1 <= b <= size(λ, 1)) || throw(
            ArgumentError("welfare_accounting: aggregator bus=$b outside 1:$(size(λ, 1))"),
        )
        for t in 1:T
            transfer += λ[b, t] * value(entry.net[t])
        end
    end

    util = value(ctx.meta[:objective])                # Σ_j U_agⱼ (total prosumer utility)

    # AGR-OPT value (3.46). `transfer = Σⱼ Σₜ λⱼ·netⱼ` where `net = p_inject − Pdc` is the net
    # INJECTION (net>0 ⇒ export). Thesis 3.46 prices the aggregator's net DEMAND (= −net
    # injection): an aggregator that net-EXPORTS at a positive DADP λ EARNS `λ·net`, an
    # importer PAYS it. So the transfer is ADDED to the prosumer surplus (exporter earns), NOT
    # subtracted — subtracting conflated the 3.22 net-injection sign with the 3.46 net-demand
    # cost term (CR-01; 05-RESEARCH:213-217).
    prosumer = util + transfer
    # −DSO-OPT value (3.47): the DSO collects the DLMP−wholesale spread — its MEM revenue
    # (`−mem_cost`, positive when the feeder net-exports to the market) MINUS what it pays the
    # prosumers for their net injection (`transfer`). Mirror-image of the prosumer side so the
    # `Σⱼλⱼ·netⱼ` transfer cancels and `prosumer + dso == util − mem_cost == social`.
    # `_transfer_flip` mis-signs the transfer in the DSO settlement ONLY (a broken cancellation)
    # so the identity assertion below fires — the non-vacuous self-test (threat T-05-03); it is
    # NOT part of the physical accounting.
    dso = (_transfer_flip ? transfer : -transfer) - mem_cost

    social = objective_value(ctx.model)               # GLB-CVX optimum (3.38)

    # Magnitude-sanity guard (Pitfall 5 / threat T-05-05): finite and within the per-unit band
    # (¢$/kWh-consistent prices × horizon × buses) — a clean power-of-ten unit slip fails here.
    Np = length(feeder.buses)
    band = PRICE_MAX * (Np + 1) * T
    for (nm, v) in ((:social, social), (:prosumer, prosumer), (:dso, dso))
        isfinite(v) || error("welfare_accounting: $nm surplus is non-finite ($v)")
        abs(v) < band || error(
            "welfare_accounting: $nm=$v out of magnitude-sanity band ±$band " *
            "(¢\$/kWh-consistent, thesis 3.38; possible unit slip — Pitfall 5)",
        )
    end

    # HARD surplus identity (thesis 3.38/3.46/3.47; threat T-05-03): social == prosumer + dso.
    # `social` is `objective_value` by definition, so this equivalently asserts
    # `prosumer + dso ≈ objective_value(ctx.model)`. Relative tolerance (scale-free, mirroring
    # assert_socp_exact!). The THROW is load-bearing — the `_transfer_flip` self-test fires it.
    resid = abs((prosumer + dso) - social)
    tol = atol + rtol * max(abs(social), abs(prosumer) + abs(dso))
    resid <= tol || error(
        "welfare_accounting: surplus identity VIOLATED — |(prosumer+dso) − social| = $resid " *
        "exceeds tol=$tol (prosumer=$prosumer, dso=$dso, social=$social). The Σⱼλⱼ·p_agⱼ " *
        "price-transfer did NOT cancel: a mis-signed or dropped term in the AGR-OPT (3.46) / " *
        "DSO-OPT (3.47) settlement (Open Q2: if it fails by a loss-sized amount, add the " *
        "documented −r·l loss term and re-derive; thesis 3.38/3.46/3.47; threat T-05-03).",
    )

    # +25% headline (thesis Case A, page 98): with a solved FIT baseline (05-03) report the
    # COMPUTED ratio social_DADP / social_FIT (≈ 1.25). The ABSOLUTE welfare is figure-bound
    # (RESEARCH Pitfall 4; STATE Phase-4 caveat), so only the RATIO is a trustworthy claim —
    # pinned as a golden by the test, with the thesis ~1.25 a NON-FAILING cross-check. German-
    # FIT prices λ_import=6.6 / λ_export=9.6 / λ_self=5.6 ¢$/kWh (thesis page 93, fit.jl).
    baseline === nothing && return (; social, dso, prosumer)
    return (; social, dso, prosumer, ratio = _fit_ratio(social, baseline))
end

"""
    _fit_ratio(social_dadp, baseline) -> Float64

The +25%-social-welfare headline as a COMPUTED ratio `social_DADP / social_FIT` (thesis Case A
≈ 1.25), where `baseline` is the solved FIT context from [`fit_baseline`](@ref) (plan 05-03,
carrying `social_fit`). Throws (never `@assert`) on a degenerate (≈0) or non-finite baseline so
a mis-specified counterfactual fails loudly instead of silently skewing the headline
(threat T-05-04).
"""
function _fit_ratio(social_dadp::Real, baseline)
    hasproperty(baseline, :social_fit) || throw(
        ArgumentError(
            "welfare_accounting: `baseline` has no `social_fit` field — pass a solved FIT " *
            "context from fit_baseline(...) (plan 05-03, thesis 3.24-3.28).",
        ),
    )
    social_fit = baseline.social_fit
    (isfinite(social_fit) && abs(social_fit) > eps(Float64)) || error(
        "welfare_accounting: FIT baseline social_fit=$social_fit is non-finite or ≈0 — cannot " *
        "form the +25% ratio (degenerate baseline; threat T-05-04).",
    )
    ratio = social_dadp / social_fit
    isfinite(ratio) || error("welfare_accounting: +25% ratio is non-finite ($ratio)")
    return ratio
end

export welfare_accounting

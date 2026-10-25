# Equity-metric known-value certificates (SETL-04) + positive-support exclusions.
#
# Every new mathematical regime gets its own known-value gate (v3.0 standing bar):
# hand-computed, exact anchors — including a NEGATIVE-value Gini anchor computed BY
# HAND — and exclusion counts asserted as RETURNED VALUES, never implicit.

@testitem "equity: uniform anchor — (Gini, Theil, Atkinson, Palma) = (0, 0, 0, 0.25) exactly" tags =
    [:equity] begin
    using TSODSO, Test

    u = fill(7.0, 10)
    @test gini(u) == 0.0
    t = theil(u)
    @test t.theil == 0.0
    @test t.n == 10
    @test t.n_excluded == 0
    a = atkinson(u)
    @test a.atkinson == 0.0
    @test a.n == 10
    @test a.n_excluded == 0
    @test a.epsilon == 0.5
    # Palma: n_top = 1, n_bottom = 4 -> (1*u) / (4*u) = 0.25 EXACTLY (totals cancel).
    @test palma(u) == 0.25
end

@testitem "equity: hand-computed negative-value Gini anchor — gini([-2, 1, 3, 6]) == 0.8125" tags =
    [:equity] begin
    using TSODSO, Test

    # Hand arithmetic (pinned, NOT recomputed via the implementation's own formula path):
    #   sorted [-2, 1, 3, 6]; unordered pairwise |xi - xj|: 3 + 5 + 8 + 2 + 5 + 3 = 26;
    #   ordered pairs double it: S = 52.  mu = (-2+1+3+6)/4 = 2.
    #   G = 52 / (2 * 4^2 * 2) = 52/64 = 0.8125 — a NEGATIVE-bearing vector, computed
    #   over ALL values (never zeroed/dropped), value > relative spread intuition.
    x = [-2.0, 1.0, 3.0, 6.0]
    @test gini(x) == 0.8125
end

@testitem "equity: Theil/Atkinson exclude non-positives WITH reported counts; Palma sign caveat -3.0" tags =
    [:equity] begin
    using TSODSO, Test

    x = [-2.0, 1.0, 3.0, 6.0]

    # Theil on the positive-support subset {1, 3, 6}: exclusion REPORTED (= 1), index
    # equals an INLINE INDEPENDENT recomputation (different code path from the impl).
    t = theil(x)
    @test t.n == 4
    @test t.n_excluded == 1
    xp = [1.0, 3.0, 6.0]
    mu = sum(xp) / length(xp)
    t_expected = sum(xi -> (xi / mu) * log(xi / mu), xp) / length(xp)
    @test isapprox(t.theil, t_expected; rtol = 1e-12)

    # Atkinson (eps = 0.5 fixed module constant) on the same subset: exclusion REPORTED.
    a = atkinson(x)
    @test a.n == 4
    @test a.n_excluded == 1
    @test a.epsilon == 0.5
    a_expected = 1 - (sum(xi -> xi^(1 - 0.5), xp) / length(xp))^(1 / (1 - 0.5)) / mu
    @test isapprox(a.atkinson, a_expected; rtol = 1e-12)

    # Palma over the ascending-sorted FULL vector — pinned small-n counts:
    #   n_top = max(1, floor(0.1*4)) = 1, n_bottom = max(1, floor(0.4*4)) = 1
    #   top = {6.0}, bottom = {-2.0}  =>  6 / (-2) = -3.0 EXACTLY.
    # A NEGATIVE ratio — the documented sign caveat when the bottom-40% sum < 0.
    @test palma(x) == -3.0
end

@testitem "equity: Palma exact 10%/40% shares at n=10, and a negative-appended rescale matches recompute" tags =
    [:equity] begin
    using TSODSO, Test

    x = collect(1.0:10.0)
    # n = 10: top decile = {10} sum 10; bottom 40% = {1,2,3,4} sum 10 => 1.0 EXACTLY.
    @test palma(x) == 1.0

    # Negative appended and the whole vector rescaled — totals cancel, ratio recomputed
    # inline under the same pinned counts (n = 11: n_top = 1, n_bottom = 4).
    x2 = vcat(x, -100.0) ./ 10.0
    xs = sort(x2)
    n_top = max(1, floor(Int, 0.1 * length(x2)))
    n_bottom = max(1, floor(Int, 0.4 * length(x2)))
    expected = sum(xs[(end - n_top + 1):end]) / sum(xs[1:n_bottom])
    @test isapprox(palma(x2), expected; rtol = 1e-12)
end

@testitem "equity: all-non-positive input — Theil/Atkinson NaN with n_excluded == n, Palma stays finite" tags =
    [:equity] begin
    using TSODSO, Test

    x = [-4.0, -3.0, -2.0, -1.0]
    t = theil(x)
    @test isnan(t.theil)
    @test t.n_excluded == 4
    a = atkinson(x)
    @test isnan(a.atkinson)
    @test a.n_excluded == 4
    # Palma: top = {-1} sum -1, bottom = {-4} sum -4 => 0.25 — finite, defined.
    p = palma(x)
    @test isfinite(p)
    @test p == 0.25
end

@testitem "equity: fail-loud guards — empty, zero-mean non-uniform, non-finite, bad epsilon" tags =
    [:equity] begin
    using TSODSO, Test

    # Empty vector: ArgumentError on ALL four metrics.
    @test_throws ArgumentError gini(Float64[])
    @test_throws ArgumentError theil(Float64[])
    @test_throws ArgumentError atkinson(Float64[])
    @test_throws ArgumentError palma(Float64[])

    # Gini zero-mean degeneracy: all-zero (all-equal) => 0.0; NON-uniform mu == 0 => throw.
    @test gini([0.0, 0.0, 0.0]) == 0.0
    @test_throws ArgumentError gini([-1.0, 1.0])

    # Non-finite values rejected loudly on every metric.
    @test_throws ArgumentError gini([1.0, NaN])
    @test_throws ArgumentError gini([Inf, 1.0])
    @test_throws ArgumentError theil([1.0, Inf])
    @test_throws ArgumentError atkinson([NaN])
    @test_throws ArgumentError palma([1.0, -Inf])

    # Atkinson epsilon: must lie in (0, 1) ∪ (1, ∞); eps = 1 (log form) unimplemented.
    @test_throws ArgumentError atkinson([1.0, 2.0, 3.0]; epsilon = 1.0)
    @test_throws ArgumentError atkinson([1.0, 2.0, 3.0]; epsilon = 0.0)
    @test_throws ArgumentError atkinson([1.0, 2.0, 3.0]; epsilon = -0.5)
end

@testitem "equity: load_terciles — floor/floor/remainder-to-middle, stable ascending ranks" tags =
    [:equity] begin
    using TSODSO, Test

    # n = 10: n_lo = 3, n_hi = 3, n_mid = 4 — EXACTLY 3 low / 4 mid / 3 high, with
    # low = ranks 1-3, mid = ranks 4-7, high = ranks 8-10 of the ascending order.
    labels = load_terciles(collect(1.0:10.0))
    @test count(==(:low), labels) == 3
    @test count(==(:mid), labels) == 4
    @test count(==(:high), labels) == 3
    # identity totals: label 1..3 = :low, 4..7 = :mid, 8..10 = :high
    @test labels == [:low, :low, :low, :mid, :mid, :mid, :mid, :high, :high, :high]

    # n = 4 => 1/2/1; n = 3 => 1/1/1 (remainder to the MIDDLE).
    l4 = load_terciles([40.0, 10.0, 30.0, 20.0])
    @test count(==(:low), l4) == 1
    @test count(==(:mid), l4) == 2
    @test count(==(:high), l4) == 1
    # ascending ranks: 10 -> low, 20 & 30 -> mid, 40 -> high
    @test l4 == [:high, :low, :mid, :mid]

    l3 = load_terciles([3.0, 1.0, 2.0])
    @test count(==(:low), l3) == 1
    @test count(==(:mid), l3) == 1
    @test count(==(:high), l3) == 1
    @test l3 == [:high, :low, :mid]
end

@testitem "equity: equity_breakdown — per-group metric set, direct-call equivalence" tags =
    [:equity] begin
    using TSODSO, Test

    values = [1.0, 2.0, 3.0, 4.0]
    groups = [:pv, :pv, :non_pv, :non_pv]
    bd = equity_breakdown(values, groups)
    @test bd isa Dict
    @test issetequal(keys(bd), (:pv, :non_pv))
    for g in (:pv, :non_pv)
        d = bd[g]
        # all SEVEN fields present per group
        @test haskey(d, :n)
        @test haskey(d, :gini)
        @test haskey(d, :theil)
        @test haskey(d, :theil_n_excluded)
        @test haskey(d, :atkinson)
        @test haskey(d, :atkinson_n_excluded)
        @test haskey(d, :palma)
    end
    @test bd[:pv].n == 2
    @test bd[:non_pv].n == 2

    # Group metrics equal a DIRECT call on each group's members (independent path).
    @test bd[:pv].gini == gini([1.0, 2.0])
    @test bd[:non_pv].gini == gini([3.0, 4.0])
    tp = theil([1.0, 2.0])
    @test bd[:pv].theil == tp.theil
    @test bd[:pv].theil_n_excluded == tp.n_excluded
    ap = atkinson([3.0, 4.0])
    @test bd[:non_pv].atkinson == ap.atkinson
    @test bd[:non_pv].atkinson_n_excluded == ap.n_excluded
    @test bd[:non_pv].palma == palma([3.0, 4.0])
end

@testitem "equity: household-map-shaped breakouts — pv_group AND bus groupings" tags =
    [:equity] begin
    using TSODSO, Test

    # case_a_household_map row shape (materialize.jl): the ONLY grouping source.
    row_t = @NamedTuple{
        house::Int,
        bus::Int,
        aggregator::Int,
        device_set::Symbol,
        pv_group::Symbol,
        house_index::Int,
    }
    rows = row_t[
        (
            house = 1,
            bus = 2,
            aggregator = 2,
            device_set = :thermostatic_deferrable_pvbattery,
            pv_group = :pv,
            house_index = 1,
        ),
        (
            house = 2,
            bus = 2,
            aggregator = 2,
            device_set = :thermostatic_deferrable_pvbattery,
            pv_group = :non_pv,
            house_index = 2,
        ),
        (
            house = 3,
            bus = 3,
            aggregator = 3,
            device_set = :thermostatic_deferrable_pvbattery,
            pv_group = :pv,
            house_index = 1,
        ),
        (
            house = 4,
            bus = 3,
            aggregator = 3,
            device_set = :thermostatic_deferrable_pvbattery,
            pv_group = :non_pv,
            house_index = 2,
        ),
    ]
    values = [10.0, 20.0, 30.0, 40.0]

    by_pv = equity_breakdown(values, [r.pv_group for r in rows])
    @test issetequal(keys(by_pv), (:pv, :non_pv))
    by_bus = equity_breakdown(values, [r.bus for r in rows])
    @test issetequal(keys(by_bus), (2, 3))
    # every group non-empty
    @test all(g -> by_pv[g].n >= 1, keys(by_pv))
    @test all(g -> by_bus[g].n >= 1, keys(by_bus))

    # Load terciles of baseline consumption — the third locked grouping.
    terc = load_terciles(values)
    by_terr = equity_breakdown(values, terc)
    @test issetequal(keys(by_terr), (:low, :mid, :high))
end

@testitem "equity: breakout guards — mismatch, empty, non-finite" tags = [:equity] begin
    using TSODSO, Test

    @test_throws ArgumentError equity_breakdown([1.0, 2.0, 3.0], [:a, :b])
    @test_throws ArgumentError equity_breakdown(Float64[], Symbol[])
    @test_throws ArgumentError equity_breakdown([1.0, NaN], [:a, :b])
    @test_throws ArgumentError load_terciles(Float64[])
    @test_throws ArgumentError load_terciles([1.0, Inf])
end

@testitem "equity: rebound known value — amount 2.0, ratio 0.4 exactly, per-hour detail" tags =
    [:equity] begin
    using TSODSO, Test

    # Hand-pinned 4-hour case: baseline vs counterfactual NET-LOAD profiles.
    # delta = cf - baseline = [0, -5, 2, 0]; reduction at t=2; increase at t=3
    # (AFTER the first reduction => counts). amount = 2.0; ratio = 2 / 5 = 0.4 EXACTLY.
    r = rebound([0.0, 10.0, 10.0, 10.0], [0.0, 5.0, 12.0, 10.0])
    @test r.delta == [0.0, -5.0, 2.0, 0.0]
    @test r.reduction_hours == [2]
    @test r.increase_hours == [3]
    @test r.rebound_amount == 2.0
    @test r.rebound_ratio == 0.4
end

@testitem "equity: rebound identical profiles — amount 0.0, ratio NaN, no reduction hours" tags =
    [:equity] begin
    using TSODSO, Test

    r = rebound([1.0, 2.0, 3.0], [1.0, 2.0, 3.0])
    @test r.delta == [0.0, 0.0, 0.0]
    @test isempty(r.reduction_hours)
    @test isempty(r.increase_hours)
    @test r.rebound_amount == 0.0
    # No reductions => ratio undefined => NaN (documented convention; isnan comparison).
    @test isnan(r.rebound_ratio)
end

@testitem "equity: rebound — an increase BEFORE any reduction is excluded" tags = [:equity] begin
    using TSODSO, Test

    # delta = [0, 2, -5]: the increase at t=2 precedes the first reduction (t=3) —
    # NOT a shift into a later hour. amount 0.0; reductions exist (denominator 5)
    # so ratio = 0.0 — defined and zero, distinct from the no-reduction NaN.
    r = rebound([0.0, 10.0, 10.0], [0.0, 12.0, 5.0])
    @test r.delta == [0.0, 2.0, -5.0]
    @test r.reduction_hours == [3]
    @test isempty(r.increase_hours)
    @test r.rebound_amount == 0.0
    @test r.rebound_ratio == 0.0
end

@testitem "equity: rebound — two reduction hours, increases summed across post-first-reduction hours" tags =
    [:equity] begin
    using TSODSO, Test

    # Hand-computed: baseline = 5 each hour; cf = [5, 3, 7, 4, 6, 5]
    # => delta = [0, -2, 2, -1, 1, 0]; reductions {2, 4}; increases {3, 5}
    # (both strictly after the FIRST reduction at t=2). amount = 2 + 1 = 3.0;
    # denominator = -(-2 + -1) = 3.0; ratio = 1.0 — all EXACT.
    r = rebound(fill(5.0, 6), [5.0, 3.0, 7.0, 4.0, 6.0, 5.0])
    @test r.delta == [0.0, -2.0, 2.0, -1.0, 1.0, 0.0]
    @test r.reduction_hours == [2, 4]
    @test r.increase_hours == [3, 5]
    @test r.rebound_amount == 3.0
    @test r.rebound_ratio == 1.0
end

@testitem "equity: rebound guards — mismatch, non-finite, empty" tags = [:equity] begin
    using TSODSO, Test

    @test_throws ArgumentError rebound([1.0, 2.0], [1.0])
    @test_throws ArgumentError rebound(Float64[], Float64[])
    @test_throws ArgumentError rebound([1.0, NaN], [1.0, 2.0])
    @test_throws ArgumentError rebound([1.0, 2.0], [1.0, Inf])
end

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
    a_expected =
        1 - (sum(xi -> xi^(1 - 0.5), xp) / length(xp))^(1 / (1 - 0.5)) / mu
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

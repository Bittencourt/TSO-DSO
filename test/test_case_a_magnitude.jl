# Seam: scripts/lib/case_a_common.jl — the Phase 42 case-a-magnitude structural
# invariants: the SIGN-SAFE welfare-gain definition (REPRO-03's headline quantity) and the
# fail-loud pre-registration protocol guard. FAST-LANE items: no solving, no TSODSO import
# (pure Julia + git only), seconds each — every item `include`s the lib via the
# repo-root-relative path and must not pay the package load. NO golden is pinned on the
# measured magnitude — the only exact anchors are plumbing quantities (the gain
# definition's algebra and the guard's contract), per the protocol's golden policy
# (42-CASE-A-PROTOCOL.md §10). Item names contain "magnitude" so the `occursin` filters
# select them.
#
# The git-dependent guard items build throwaway tmpdir git repos (mktempdir + `git init`)
# with INLINE identity flags (`-c user.name/-c user.email`, gpg signing off) so the tests
# are hermetic — no dependence on any global git identity.
#
# 42-04 placement decision (recorded per the plan's Task-1 instruction): the device-variant
# rebuild helper (`case_a_houses_variant`), its alignment tripwire
# (`assert_houses_map_aligned`) and the bus-level roll-up (`case_a_variant_rollup`) live in
# `scripts/lib/case_a_common.jl` (the plan frontmatter's artifact path). The lib stays
# include-composable without TSODSO (the guard/gain items above never load it): the rebuild
# helpers reference TSODSO ONLY through `TSODSO.X`-qualified names resolved at CALL time, so
# an `include` succeeds anywhere while a CALL requires `using TSODSO` first — the runner and
# the three rebuild items below do exactly that. The rebuild items are still FAST-LANE: they
# construct houses (profile draws, seconds) and roll them up — NO solve, no ladder, no FIT.

@testitem "magnitude gain: sign-safe on the negative-welfare population shape" begin
    include(joinpath(@__DIR__, "..", "scripts", "lib", "case_a_common.jl"))

    # The thesis +25%-ratio shape at the 784-house population: W_FIT = -3.78e5,
    # W_DADP = -4.725e5 (DADP is WORSE — more negative). The NAIVE ratio
    # W_DADP/W_FIT = 1.25 → a POSITIVE-looking number for a welfare LOSS. This silent
    # sign inversion is exactly why the naive ratio is BANNED (PROJECT.md Key Decision;
    # 42-CASE-A-PROTOCOL.md §1) and why the registered form divides by |W_FIT|. The
    # inversion is DOCUMENTED in this comment, never asserted as behavior: no test below
    # computes or asserts the naive ratio's value.
    let w_fit = -3.78e5, w_dadp = -4.725e5, g = welfare_gain(w_dadp, w_fit)
        @test g.Δpct < 0                     # DADP worse ⇒ the REGISTERED gain is negative
        @test g.Δpct ≈ -25.0                 # algebraically exact: 100·(−94500)/378000
        @test g.Δ == w_dadp - w_fit          # the absolute gain is the plain difference, exactly
    end

    # The improving direction: DADP better (less negative) ⇒ POSITIVE registered gain.
    let g_up = welfare_gain(-3.78e5 + 100, -3.78e5)
        @test g_up.Δpct > 0
        @test g_up.Δ > 0
    end

    # Conventional behavior when W_FIT > 0: the sign of Δpct equals the sign of ΔW.
    let g_pos = welfare_gain(110.0, 100.0), g_neg = welfare_gain(90.0, 100.0)
        @test g_pos.Δpct > 0 && g_pos.Δ > 0
        @test g_neg.Δpct < 0 && g_neg.Δ < 0
    end
end

@testitem "magnitude gain: exact known-value anchor" begin
    include(joinpath(@__DIR__, "..", "scripts", "lib", "case_a_common.jl"))

    # Plumbing-only golden, sanctioned by 42-CASE-A-PROTOCOL.md §10 (new goldens only on
    # sign-safe, reproducible plumbing quantities): the algebra anchor of the registered
    # definition on positive welfare. NOT a magnitude assertion — the measured magnitude
    # is never pinned anywhere in this suite.
    @test welfare_gain(110.0, 100.0) == (Δ = 10.0, Δpct = 10.0)
end

@testitem "magnitude protocol guard: missing file fails loudly" begin
    include(joinpath(@__DIR__, "..", "scripts", "lib", "case_a_common.jl"))

    # A missing protocol file must ERROR (fail-loud), naming the violation class.
    let repo = mktempdir(),
        path = joinpath(repo, "nonexistent.md"),
        err = try
            assert_protocol_registered(path)
            nothing
        catch e
            e
        end

        @test err !== nothing
        @test err isa ErrorException
        @test occursin("PRE-REGISTRATION VIOLATION", sprint(showerror, err))
    end
end

@testitem "magnitude protocol guard: uncommitted file fails loudly" begin
    include(joinpath(@__DIR__, "..", "scripts", "lib", "case_a_common.jl"))

    # A protocol file that exists but has NO git history (written into a fresh tmpdir git
    # repo, never committed) must ERROR: an uncommitted protocol is no pre-registration.
    let repo = mktempdir(), path = joinpath(repo, "42-CASE-A-PROTOCOL.md")
        run(`git init -q $repo`)
        write(path, "pre-registration fixture\n")
        err = try
            assert_protocol_registered(path)
            nothing
        catch e
            e
        end
        @test err !== nothing
        @test err isa ErrorException
        @test occursin("NOT", sprint(showerror, err))
        @test occursin("committed", sprint(showerror, err))
    end
end

@testitem "magnitude protocol guard: committed file returns SHA" begin
    include(joinpath(@__DIR__, "..", "scripts", "lib", "case_a_common.jl"))

    # A committed protocol file passes the guard, which returns the full 40-hex git SHA
    # (the value later plans stamp into every CSV row's protocol_sha column).
    let repo = mktempdir(), path = joinpath(repo, "42-CASE-A-PROTOCOL.md")
        run(`git init -q $repo`)
        write(path, "pre-registration fixture — committed\n")
        run(`git -C $repo add $path`)
        run(
            `git -C $repo -c user.name=gsd-test -c user.email=gsd@test.invalid -c commit.gpgsign=false commit -q -m "pre-registration protocol fixture"`,
        )
        sha = assert_protocol_registered(path)
        @test sha isa String
        @test occursin(r"^[0-9a-f]{40}$", sha)
    end
end

@testitem "magnitude runner source contract: pre-planned values match the protocol" begin
    # The source-level no-free-form-search guard (42-03-PLAN Task 1): the runner's
    # pre-planned values — the AGR ladder rungs, the protocol seed set, the mode
    # whitelist, the registered population, the pre-registration guard, and the locked
    # ρ source — are pinned AS COMMITTED TEXT in `scripts/case_a_magnitude.jl`, so
    # silently adding a rung/seed/mode (or swapping the gain definition) shows up as a
    # test failure unless the protocol (42-CASE-A-PROTOCOL.md) is amended too — the
    # deliberate-act friction (PATTERNS: "Pre-planned Dict = the only permitted values").
    #
    # FAST LANE: reads the script as TEXT — no include, no execution, no solving.
    #
    # Assertion hygiene: every assertion is `occursin`-based, NEVER count-based (a
    # comment mentioning a pinned value would self-invalidate a grep-count gate). The
    # mode-whitelist assertion is CONTAINS-not-exact on purpose: later waves EXTEND the
    # whitelist with crosscheck/lenses/ablation-* modes, and this contract must stay
    # green through those extensions — only removal/rename of a registered mode fails.
    src_path = joinpath(@__DIR__, "..", "scripts", "case_a_magnitude.jl")
    @test isfile(src_path)  # RED when the runner is absent — the natural first failure
    src = read(src_path, String)

    # (1) The four pre-registered AGR ladder rungs — String keys (the
    #     `scripts/case_a_agreement.jl` `AGR_TOL_RUNGS` Dict, verbatim rung set).
    for rung in ("\"default\"", "\"gap_1e-10\"", "\"gap_1e-12\"", "\"gapfeas_1e-12\"")
        @test occursin(rung, src)
    end

    # (2) The protocol seed set (42-CASE-A-PROTOCOL.md §3): 42 = primary/registered
    #     anchor, 43–46 = the spread. A new seed requires a protocol amendment first.
    @test occursin("(42, 43, 44, 45, 46)", src)

    # (3) The pre-registration gate on the main path (the first executed code path —
    #     no protocol file, no run; an uncommitted protocol, no run).
    @test occursin("assert_protocol_registered", src)

    # (4) The mode whitelist CONTAINS `headline` and `proxy` — contains-not-exact (the
    #     whitelist is extendable by later waves; it must never shrink or rename these).
    @test occursin("headline", src)
    @test occursin("proxy", src)

    # (5) The headline runs the REGISTERED 784-house population at the registered
    #     configuration (42-CASE-A-PROTOCOL.md §2) — not a smaller stand-in.
    @test occursin("build_population(:case_a_784", src)

    # (6) The protocol document is cited by its CONTEXT-locked path.
    @test occursin("42-CASE-A-PROTOCOL.md", src)

    # (7) ρ is sourced from the strategy's own default — the LOCKED no-re-tuning
    #     configuration (a REQUIRED kwarg; never a script-local number).
    @test occursin("ADMM().ρ", src)

    # (8) The gain is computed ONLY by the registered sign-safe definition from the lib;
    #     the BANNED naive-ratio shape (it sign-inverts on negative welfare) appears
    #     NOWHERE in the script — comments included (they spell it in uppercase instead).
    @test occursin("welfare_gain", src)
    @test !occursin("w_dadp / w_fit", src)
end

@testitem "magnitude committed CSVs: schema, honest statuses, Δ identity" begin
    # Structural item over the COMMITTED artifacts (42-03-PLAN Task 3; fast lane — reads
    # results, NO solving): the CSVs are the evidence chain, so this re-derives every
    # identity algebraically — a hand-edited CSV breaks visibly. The status vocabulary is
    # the honesty policy's (protocol §4/§5): `error:<TypeName>` prefix rows (refusals are
    # data), the known ok-forms, the typed `:budget_exceeded` honest early exit, and
    # `reused` (a row copied from another committed CSV — provenance-transparent reuse,
    # never re-solved, never fabricated; emitted by 42-04's population-axis rows, so the
    # vocabulary must admit it — MED-2). Its `note` must name the source file+row.
    #
    # The Δ identity is ALGEBRAIC, not a magnitude golden (golden policy): wherever BOTH
    # welfares are present and numeric, delta_w re-derives as their difference and
    # delta_pct as 100·delta_w/|welfare_fit| (sign-safe denominator). The lens-row
    # ledger checks (lens_summary.csv, written from 42-05 onward — LOW-4): the
    # settlement-ledger structural identities that hold on EVERY compare_tariffs
    # summary leg — `merchandising_surplus == dso_total` (the ledger's named-line
    # ALIAS: `build_settlement_ledger` sets merchandising_surplus = balances[:dso],
    # the same balance) and `total_payments == -aggregators_total` (the payment
    # mirror). NOT `welfare ≈ dso + merch + aggs`: the social welfare's ledger
    # companions are the UTILITY sums (device disutility, ≈ −3.78e5 at 784 houses),
    # which are not summary columns — the assumed four-line identity fails on the
    # committed Phase-41 ground artifact itself (42-05 correction: the identity was
    # written before any lens artifact existed).
    using CSV
    using DataFrames: DataFrame, eachrow

    dir = joinpath(@__DIR__, "..", "results", "thesis_case_a_magnitude")
    csvs =
        isdir(dir) ? filter(f -> endswith(f, ".csv"), readdir(dir; join = true)) : String[]
    isempty(csvs) && error(
        "no artifacts yet: results/thesis_case_a_magnitude/ has no CSV — run " *
        "`julia --project=. scripts/case_a_magnitude.jl --mode proxy` and commit proxy.csv",
    )
    for csv in csvs
        df = CSV.read(csv, DataFrame)
        for r in eachrow(df)
            # provenance: every row auditable to its environment + exact protocol version
            # (T-42-03-3)
            @test hasproperty(r, :protocol_sha)
            @test !isempty(string(coalesce(r.protocol_sha, "")))
            @test hasproperty(r, :julia_version)
            @test !isempty(string(coalesce(r.julia_version, "")))
            for c in (:threads, :blas_threads, :seed, :t_horizon)
                @test hasproperty(r, c) && !(r[c] isa Missing)
            end
            # the honest status vocabulary
            status = hasproperty(r, :status) ? string(coalesce(r.status, "")) : ""
            @test startswith(status, "error:") ||
                  status in ("ok", "converged", "fit_inexact", ":budget_exceeded", "reused")
            if status == "reused"
                note = string(coalesce(get(r, :note, ""), ""))
                @test !isempty(note) && occursin(".csv", lowercase(note))
            end
            # the Δ identity (algebraic re-derivation)
            if all(
                   c -> hasproperty(r, c),
                   (:welfare_dadp, :welfare_fit, :delta_w, :delta_pct),
               ) &&
               r.welfare_dadp isa Real &&
               r.welfare_fit isa Real &&
               isfinite(r.welfare_dadp) &&
               isfinite(r.welfare_fit)
                d = Float64(r.welfare_dadp) - Float64(r.welfare_fit)
                @test r.delta_w isa Real
                @test isapprox(Float64(r.delta_w), d; rtol = 1e-9)
                @test r.delta_pct isa Real
                @test isapprox(
                    Float64(r.delta_pct),
                    100 * d / abs(Float64(r.welfare_fit));
                    rtol = 1e-9,
                )
            end
            # the lens-row ledger checks (only once 42-05 writes lens_summary.csv)
            if endswith(csv, "lens_summary.csv")
                if all(c -> hasproperty(r, c), (:dso_total, :merchandising_surplus)) && all(
                    v -> v isa Real && isfinite(v),
                    (r.dso_total, r.merchandising_surplus),
                )
                    @test isapprox(
                        Float64(r.merchandising_surplus),
                        Float64(r.dso_total);
                        rtol = 1e-12,
                    )
                end
                if all(c -> hasproperty(r, c), (:total_payments, :aggregators_total)) &&
                   all(
                    v -> v isa Real && isfinite(v),
                    (r.total_payments, r.aggregators_total),
                )
                    @test isapprox(
                        Float64(r.total_payments),
                        -Float64(r.aggregators_total);
                        rtol = 1e-9,
                    )
                end
            end
        end
    end
end

@testitem "magnitude ablation source contract: axis Dicts match the protocol" begin
    # The 42-04 source-level no-free-form-search guard (42-04-PLAN Task 1; the 42-03
    # source-contract pattern generalized to the four REPRO-05 ablation axes): each axis
    # Dict is pinned AS COMMITTED TEXT — the exact protocol-pinned variant set
    # (42-CASE-A-PROTOCOL.md §7) must appear as one `axis => [...]` line, so silently
    # adding/removing/rewording a variant is a visible script edit + test edit + protocol
    # amendment (the deliberate-act friction, T-42-04-1).
    #
    # FAST LANE: reads the runner as TEXT — no include, no execution, no solving.
    # Assertion hygiene: `occursin`-based, NEVER count-based; the mode-whitelist assertion
    # is contains-semantics (extendable by protocol amendments, never shrinkable).
    src_path = joinpath(@__DIR__, "..", "scripts", "case_a_magnitude.jl")
    @test isfile(src_path)
    src = read(src_path, String)

    # (a) fit_params (protocol §7a): the registered page-93 triple + the symmetric
    #     multiplicative λ_export probes (×0.5, ×2.0).
    @test occursin(
        "\"fit_params\" => [\"registered\", \"lam_export_half\", \"lam_export_double\"]",
        src,
    )
    # (b) price_range (protocol §7b): the registered :mem signal + elementwise λ₀ scalings.
    @test occursin("\"price_range\" => [\"registered\", \"scale_0.5\", \"scale_2.0\"]", src)
    # (c) population (protocol §7c): the two pinned proxies, the Phase-40 nested-prefix
    #     ladder fractions (case_a_scaling.jl DEFAULT_LADDER_FRACTIONS), and the headline
    #     row itself (full_784 — reused, never re-run). Pinned as the exact multi-line
    #     Dict entry (the list exceeds the 92-char formatter margin, so the committed
    #     source carries this block verbatim — any variant change moves a line).
    @test occursin(
        "    \"population\" => [\n" *
        "        \"proxy_ieee123\",\n" *
        "        \"ieee13_default\",\n" *
        "        \"1/78\",\n" *
        "        \"0.125\",\n" *
        "        \"0.25\",\n" *
        "        \"0.5\",\n" *
        "        \"0.75\",\n" *
        "        \"1.0\",\n" *
        "        \"full_784\",\n" *
        "    ],",
        src,
    )
    # (d) device_mix (protocol §7d): registered 3-device set, batteries out, PV split.
    @test occursin(
        "\"device_mix\" => [\"registered\", \"batteries_out\", \"pv_half\"]",
        src,
    )

    # The mode whitelist carries the four ablation modes (contains-semantics).
    @test occursin("ablation-fit", src)
    @test occursin("ablation-price", src)
    @test occursin("ablation-population", src)
    @test occursin("ablation-devices", src)
end

@testitem "magnitude device-variant rebuild: batteries_out drops exactly PVBattery everywhere" begin
    # 42-04-PLAN Task 1, rebuild item 1 (T-42-04-2): the `batteries_out` variant drops
    # EXACTLY the PVBattery from every house — the Thermostatic + Deferrable pair survives
    # untouched, house count and map order are unchanged, and the variant map's PV
    # attribution is recomputed from the ACTUAL device sets (no house is :pv anymore).
    # Construction only (10 houses at the 1/78 prefix): no solve, seconds.
    using TSODSO
    using TSODSO: build_feeder
    include(joinpath(@__DIR__, "..", "scripts", "lib", "case_a_common.jl"))

    feeder = build_feeder(:ieee13)
    reg_houses, reg_map = case_a_houses_variant(
        feeder,
        :ieee13,
        24,
        42;
        variant = "registered",
        fraction = 1 / 78,
    )
    # The registered rebuild at the smallest prefix: 10 houses (1 per bus), each with the
    # FIXED 3-device set (Thermostatic + Deferrable + PVBattery).
    @test length(reg_houses) == 10
    @test length(reg_map) == length(reg_houses)
    @test all(h -> length(h.devices) == 3, reg_houses)
    @test all(
        h ->
            any(d -> d isa PVBattery, h.devices) &&
            any(d -> d isa Thermostatic, h.devices) &&
            any(d -> d isa Deferrable, h.devices),
        reg_houses,
    )

    houses, map_rows = case_a_houses_variant(
        feeder,
        :ieee13,
        24,
        42;
        variant = "batteries_out",
        fraction = 1 / 78,
    )
    # House count and order unchanged vs the registered rebuild...
    @test length(houses) == length(reg_houses)
    @test all(k -> houses[k].bus == reg_houses[k].bus, eachindex(houses))
    # ...PVBattery is gone EVERYWHERE, the flexible pair survives everywhere...
    @test all(h -> !any(d -> d isa PVBattery, h.devices), houses)
    @test all(
        h ->
            any(d -> d isa Thermostatic, h.devices) &&
            any(d -> d isa Deferrable, h.devices),
        houses,
    )
    # ...and the variant map's PV attribution follows the ACTUAL device sets.
    @test length(map_rows) == length(houses)
    @test all(r -> r.pv_group == :non_pv, map_rows)
    @test all(r -> r.device_set == :thermostatic_deferrable, map_rows)
end

@testitem "magnitude device-variant rebuild: pv_half is a prefix split with consistent map" begin
    # 42-04-PLAN Task 1, rebuild item 2 (T-42-04-2): the `pv_half` variant keeps the
    # 3-device set for the FIRST HALF of the prefix (in household-map order) and drops the
    # PVBattery from the rest; the variant map's pv_group/device_set agree with the ACTUAL
    # device sets house-for-house; the bus-level roll-up yields exactly one aggregator per
    # bus (the 1:1 roll-up guard). Construction only: no solve, seconds.
    using TSODSO
    using TSODSO: build_feeder
    include(joinpath(@__DIR__, "..", "scripts", "lib", "case_a_common.jl"))

    feeder = build_feeder(:ieee13)
    houses, map_rows = case_a_houses_variant(
        feeder,
        :ieee13,
        24,
        42;
        variant = "pv_half",
        fraction = 1 / 78,
    )
    n = length(houses)
    split = div(n, 2)   # first half keeps PV, second half is Thermostatic+Deferrable only
    @test n == 10
    @test split == 5
    @test all(k -> length(houses[k].devices) == (k <= split ? 3 : 2), eachindex(houses))
    @test all(
        k -> (k <= split) == any(d -> d isa PVBattery, houses[k].devices),
        eachindex(houses),
    )
    # The variant map agrees with the actual device sets, house-for-house.
    @test all(
        k -> (map_rows[k].pv_group == :pv) == any(d -> d isa PVBattery, houses[k].devices),
        eachindex(houses),
    )
    @test all(
        k ->
            (map_rows[k].pv_group == :pv) ==
            (map_rows[k].device_set == :thermostatic_deferrable_pvbattery),
        eachindex(houses),
    )
    # The bus-level roll-up: exactly one aggregator per bus in the map (the 1:1 guard —
    # at the 1/78 prefix, 10 houses over 10 buses roll up to 10 aggregators).
    aggs = case_a_variant_rollup(houses, map_rows; context = "test pv_half roll-up")
    @test length(aggs) == 10
    @test sort!([a.bus for a in aggs]) == sort!(collect(Set(r.bus for r in map_rows)))
end

@testitem "magnitude device-variant rebuild: drift tripwire fails loudly" begin
    # 42-04-PLAN Task 1, rebuild item 3 (T-42-04-2): the rebuild's alignment tripwire
    # (the tariff_comparison.jl:511-518 fail-loud shape) must ERROR when the rebuilt
    # houses disagree with the household map — here the map rows are handed in REVERSED
    # order (a perturbed house order), and the error message must name the drift.
    using TSODSO
    using TSODSO: build_feeder
    include(joinpath(@__DIR__, "..", "scripts", "lib", "case_a_common.jl"))

    feeder = build_feeder(:ieee13)
    houses, map_rows = case_a_houses_variant(
        feeder,
        :ieee13,
        24,
        42;
        variant = "registered",
        fraction = 1 / 78,
    )
    local err
    err = try
        assert_houses_map_aligned(houses, reverse(map_rows), "test rebuild")
        nothing
    catch e
        e
    end
    @test err !== nothing
    @test err isa ErrorException
    msg = sprint(showerror, err)
    @test occursin("drift", msg) || occursin("aborting loudly", msg)
end

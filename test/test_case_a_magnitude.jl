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

@testitem "magnitude gain: sign-safe on the negative-welfare population shape" begin
    include(joinpath(@__DIR__, "..", "scripts", "lib", "case_a_common.jl"))

    # The thesis +25%-ratio shape at the 784-house population: W_FIT = -3.78e5,
    # W_DADP = -4.725e5 (DADP is WORSE — more negative). The NAIVE ratio
    # W_DADP/W_FIT = 1.25 → a POSITIVE-looking number for a welfare LOSS. This silent
    # sign inversion is exactly why the naive ratio is BANNED (PROJECT.md Key Decision;
    # 42-CASE-A-PROTOCOL.md §1) and why the registered form divides by |W_FIT|. The
    # inversion is DOCUMENTED in this comment, never asserted as behavior: no test below
    # computes or asserts the naive ratio's value.
    let w_fit = -3.78e5,
        w_dadp = -4.725e5,
        g = welfare_gain(w_dadp, w_fit)
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
    let g_pos = welfare_gain(110.0, 100.0),
        g_neg = welfare_gain(90.0, 100.0)
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
    let repo = mktempdir(),
        path = joinpath(repo, "42-CASE-A-PROTOCOL.md")
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
    let repo = mktempdir(),
        path = joinpath(repo, "42-CASE-A-PROTOCOL.md")
        run(`git init -q $repo`)
        write(path, "pre-registration fixture — committed\n")
        run(`git -C $repo add $path`)
        run(`git -C $repo -c user.name=gsd-test -c user.email=gsd@test.invalid -c commit.gpgsign=false commit -q -m "pre-registration protocol fixture"`)
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

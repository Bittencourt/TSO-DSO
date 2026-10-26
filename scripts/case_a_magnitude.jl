# scripts/case_a_magnitude.jl
#
# REPRO-03/04/05 (Phase 42): the pre-registered welfare-gain MAGNITUDE measurement —
# DADP vs FIT on the thesis Case A configuration, under the committed pre-registration
# protocol `.planning/phases/42-thesis-case-a-magnitude/42-CASE-A-PROTOCOL.md` (the guard
# below REFUSES to run anything unless that file exists AND is committed).
#
# usage:
#   julia --project=. scripts/case_a_magnitude.jl --mode headline [--seed 42] [--time-limit-s S]
#   julia --project=. scripts/case_a_magnitude.jl --mode proxy
#   julia --project=. scripts/case_a_magnitude.jl --mode ablation-fit      [--variant V|--variant all]
#   julia --project=. scripts/case_a_magnitude.jl --mode ablation-price    [--variant V|--variant all]
#   julia --project=. scripts/case_a_magnitude.jl --mode ablation-population [--variant V|--variant all]
#   julia --project=. scripts/case_a_magnitude.jl --mode ablation-devices  [--variant V|--variant all]
#   julia --project=. scripts/case_a_magnitude.jl --mode crosscheck [--seed 42]
#   julia --project=. scripts/case_a_magnitude.jl --mode lenses     [--seed 42]
#
# Modes (--mode):
#
#   headline  DEFAULT. ONE registered master seed per invocation (default 42, the
#             continuity anchor; 43–46 are the pre-registered spread). The FROZEN
#             registered configuration (protocol §2) — `:case_a_784` over `:ieee13`,
#             ConvexBranchFlow, T = 24, λ₀ = :mem, allow_export = true, ρ = ADMM().ρ
#             (locked, no re-tuning) — runs the PRE-REGISTERED AGR solver-precision
#             ladder (`AGR_TOL_RUNGS`, stop-on-first-certified, hard stop after the last
#             rung) over `solve_admm` (the published-price engine), then the UNCHANGED
#             `fit_baseline` FIT leg (batteryless by design, thesis Assumption A4), then
#             the SIGN-SAFE registered gain. LONG-RUNNING (the 784-house measurement is
#             plan 42-05's payload; certify machinery on the proxy mode first).
#   proxy     The SAME code path (`_measure_point`) on the small protocol-pinned
#             fixtures: IEEE-123 `:default` (seed 20260719 — the ≈+0.263% provenance
#             fixture, `thesis_case123_repro.jl` SEED_IEEE123) first, then IEEE-13
#             `:default` (seed 20260718 — the ground-fixture regression seed). Minutes
#             scale. Expected honest outcomes: ieee123 certifies with a FIT leg;
#             ieee13 records the KNOWN FIT INFEASIBLE (`error:SolveFailedError`,
#             the committed `tariff_comparison.csv` precedent) — recorded, never
#             re-tuned. `--seed` is rejected: the fixtures pin their own seeds.
#   ablation-*  The REPRO-05 OFAT ablation axes (protocol §7), one axis per mode:
#               `ablation-fit` (fit_params), `ablation-price` (price_range),
#               `ablation-population` (population), `ablation-devices` (device_mix).
#               Every axis/variant is a PRE-PLANNED Dict value (`ABLATION_AXES`, pinned by
#               the source-contract test; adding a variant = script edit + protocol
#               amendment). Rows land in `ablation.csv` keyed on
#               (axis, variant, seed, t_horizon, kind, rung) with honest statuses.
#               Ablations run at the REGISTERED SEED 42 ONLY (protocol §3). Axis leg
#               independence (protocol §7): (a) re-solves ONLY fit_baseline, reusing the
#               seed's certified W_DADP from magnitude.csv (missing → loud error — never a
#               silent re-solve); (b)/(d) re-run the full AGR ladder per variant; (c) walks
#               the nested-prefix rungs (no per-rung re-tuning) and reuses the proxy rows
#               (proxy.csv) and the headline row (magnitude.csv, `full_784`/`rung_1.0`)
#               with `status = "reused"` provenance-transparent rows.
#               `--variant` selects one Dict variant (or `all`, the default = the full
#               axis); the population axis accepts the Dict-key fraction string (`1/78`)
#               OR its decimal expansion, normalized to the Dict key. The full-axis heavy
#               runs are plan 42-05's payload.
#   crosscheck  The centralized CROSS-CHECK bound (protocol §6) at the registered anchor
#               seed 42: `solve_welfare(feeder, pf, aggs; T, λ₀, allow_export = true)` on
#               the registered population — on a `CertificateError` at the default
#               optimizer there is ONE sanctioned tightening (`select_optimizer(SOCP();
#               tol_gap_abs/rel = 1e-10)` — the measured `agreement.csv` path); the row
#               records WHICH path produced it (`centralized_optimizer`:
#               default | tol_gap_1e-10 | refused — the SOC-exactness gate is never
#               touched). The row reuses the certified seed-42 W_DADP from magnitude.csv
#               (provenance-transparent; the certified AGR rung names the conditioning),
#               records the welfare abs/rel deltas, and re-fetches the certified rung's
#               published DADP prices for the DADP-vs-λ₀ price-signal lens
#               (price_max_abs/rel_delta vs λ₀, the agreement.jl `max(|λ₀|, 1)` rel form).
#               LONG-RUNNING (the full-scale centralized solve is the ~4 GB leg).
#   lenses      The four-leg SETTLEMENT LENSES (protocol §1 secondary lenses) at the
#               certified 784-house point, seed 42: `compare_tariffs(feeder, pf, aggs;
#               T, λ₀, engine = :admm, ρ = ADMM().ρ, agr_optimizer = <the certified
#               rung's optimizer>, houses = the per-house rebuild, map_rows =
#               case_a_household_map-aligned)` — one summary row per tariff leg
#               (dadp/flat/tou/fit, never dropped) with honest per-leg statuses: the FIT
#               leg's `fit_inexact`/`error:<Type>` is a recorded outcome (the ground
#               INFEASIBLE precedent), never a dropped leg. Rows land in
#               lens_summary.csv (surplus split incl. the DSO-surplus sign-flip lens,
#               feasibility, battery counts, equity, rebound + provenance). If the ADMM
#               leg refuses at the passed certified rung, one honest `(run)` status row
#               is recorded per the tariff_comparison idiom. LONG-RUNNING.

#
# Honesty policy (protocol §4/§5, v5.0 policies): every solver refusal is a RECORDED
# outcome — `error:<TypeName>` status rows (iters from the typed error, −1 sentinel when
# the error carries none), the typed `:budget_exceeded` wall-clock early exit, and
# `fit_inexact`/retry outcomes. The ONLY sanctioned answers are the pre-registered AGR
# ladder (via `solve_admm`'s documented `agr_optimizer` seam) and the ONE pinned FIT
# retry (the SOLVER tightened to `tol_gap 1e-10` — never a gate, never ρ, never battery
# τ). A kill mid-run leaves the rows already captured (upsert contract) — a kill is a
# measured outcome.
#
# The gain is computed ONLY by `welfare_gain` from `scripts/lib/case_a_common.jl` — the
# registered SIGN-SAFE form `Δ% = 100·(W_DADP − W_FIT)/|W_FIT|`. The naive ratio W_DADP/W_FIT
# is BANNED (it sign-inverts on negative welfare: welfare ≈ −3.78e5 at 784 houses, so a
# welfare LOSS would read as a positive-looking ratio > 1 — PROJECT.md Key Decision;
# protocol §1). It appears nowhere in this script, and the source-contract test asserts
# that absence.
#
# CSV contract (the `tariff_comparison.jl` idiom): rows are UPSERTED with `cols = :union`
# keyed on their provenance identity PLUS the row-granularity columns (kind, rung) —
# re-runs replace their own rows and never drop siblings; every row stamps
# `protocol_sha` + full provenance (julia_version / threads / blas_threads / seed /
# t_horizon). Every rung attempt is its own row (refusals included). One measurement
# process at a time.
#
# Outputs (results/thesis_case_a_magnitude/):
#   magnitude.csv   — headline rows: one per rung attempt + one gain row per seed
#   proxy.csv       — proxy rows: same shapes, with a `fixture` identity column
#   crosscheck.csv  — the centralized cross-check bound at the certified seed-42 point
#                     (which optimizer path, reused W_DADP, agreement + price-lens deltas)
#   lens_summary.csv — the four-leg settlement rows (dadp/flat/tou/fit) at the certified
#                     point, honest per-leg statuses + provenance
#   ablation.csv    — OFAT ablation rows: `axis` + `variant` identity columns, one row per
#                     ladder attempt / gain / provenance-transparent reuse
#
# Regenerate the committed proxy artifact (minutes-scale):
#   julia --project=. scripts/case_a_magnitude.jl --mode proxy

using DrWatson
@quickactivate "TSODSO"
using TSODSO
using TSODSO:
    ADMM,
    CertificateError,
    ConvergenceError,
    ConvexBranchFlow,
    FIT_λ_EXPORT,
    FIT_λ_IMPORT,
    FIT_λ_SELF,
    QP,
    SOCP,
    SolveFailedError,
    UnconvergedAdmmError,
    _CASE_A_TOTAL_HOUSES,
    build_feeder,
    build_population,
    build_price,
    compare_tariffs,
    fit_baseline,
    generate_profiles,
    select_optimizer,
    solve_admm,
    solve_welfare,
    sub_seed
using CSV
using DataFrames: DataFrame, eachrow, nrow
using LinearAlgebra: BLAS

include(joinpath(@__DIR__, "lib", "case_a_common.jl"))   # the 42-01 helpers: the guard,
# welfare_gain, provenance_row, flatten_note — ONE shared definition, never re-derived here.

# ---- the pre-planned values (the protocol, restated as runnable identity) ---------------------

# The protocol seed set (42-CASE-A-PROTOCOL.md §3): 42 = primary/registered anchor with
# every prior Case A artifact, 43–46 = the pre-registered spread. Adding a seed is a
# protocol amendment + a script edit (this tuple is pinned by the source-contract test).
const SEEDS = (42, 43, 44, 45, 46)
const REGISTERED_SEED = first(SEEDS)

# The mode whitelist. EXTENDABLE by later waves (crosscheck/lenses modes are planned) —
# never shrink or rename a registered mode: the source-contract test pins the registered
# members with contains-semantics on purpose.
const MODES = (
    "headline",
    "proxy",
    "crosscheck",
    "lenses",
    "ablation-fit",
    "ablation-price",
    "ablation-population",
    "ablation-devices",
)

# The PRE-PLANNED AGR solver-precision ladder (verbatim from
# `scripts/case_a_agreement.jl:116-126`; protocol §4). The Dict IS the entire permitted
# ladder — the rungs tighten Clarabel's OWN convergence precision via the documented
# `agr_optimizer` seam; the exactness gate, the battery τ and ρ are NEVER touched. Rung
# keys are plain STRINGS (`:gap_1e-10` would parse as subtraction). Adding a rung
# requires editing this Dict + a protocol amendment (the deliberate-act friction).
const AGR_TOL_RUNGS = Dict{String, Union{Nothing, NamedTuple}}(
    "default" => nothing,
    "gap_1e-10" => (tol_gap_abs = 1e-10, tol_gap_rel = 1e-10),
    "gap_1e-12" => (tol_gap_abs = 1e-12, tol_gap_rel = 1e-12),
    # gapfeas_1e-12 (AMENDMENT 2026-10-26, first execution of this rung): the
    # pre-registered attrs `tol_feas_abs`/`tol_feas_rel` do NOT exist in the installed
    # Clarabel 0.11.1 (`Settings` carries a single `tol_feas` field) — the rung crashed
    # with `FieldError` on its first-ever execution (42-05, price_range/scale_0.5). The
    # rung's pre-registered INTENT (protocol §4: feasibility tolerance 1e-12 on top of
    # rung 2) is executed as `tol_feas = 1e-12`; the rung NAME, its ladder position and
    # its last-resort role are unchanged. No gate, no ρ, no battery τ is touched.
    "gapfeas_1e-12" => (tol_gap_abs = 1e-12, tol_gap_rel = 1e-12, tol_feas = 1e-12),
)
# The declared run order (Julia Dicts are unordered): step 0 → 3 of the protocol §4
# table. Guarded below against drift from the Dict.
const AGR_RUNG_ORDER = ("default", "gap_1e-10", "gap_1e-12", "gapfeas_1e-12")
sort(collect(keys(AGR_TOL_RUNGS))) == sort(collect(AGR_RUNG_ORDER)) || error(
    "case_a_magnitude: AGR_RUNG_ORDER $(AGR_RUNG_ORDER) does not exactly cover " *
    "AGR_TOL_RUNGS keys $(sort(collect(keys(AGR_TOL_RUNGS)))) — the ladder Dict and its " *
    "declared run order drifted (aborting loudly)",
)

# The protocol-pinned proxy fixtures (42-CASE-A-PROTOCOL.md §7c/§8): the ≈+0.263%
# provenance fixture FIRST (the restatement point), then the same-feeder regression
# fixture whose known honest statuses are EXPECTED rows.
const PROXY_FIXTURES = (
    (
        fixture = "ieee123-default",
        feeder_sym = :ieee123,
        pop_sym = :default,
        seed = 20260719,
    ),
    (fixture = "ieee13-default", feeder_sym = :ieee13, pop_sym = :default, seed = 20260718),
)

const FEEDER_SYM = :ieee13   # the registered headline feeder (protocol §2)
const PRICE_SYM = :mem       # the registered price signal (protocol §2)
const T_H = 24               # the registered horizon (protocol §2)
const OUT_DIR = joinpath(projectdir(), "results", "thesis_case_a_magnitude")
const MAGNITUDE_CSV = joinpath(OUT_DIR, "magnitude.csv")
const PROXY_CSV = joinpath(OUT_DIR, "proxy.csv")
const ABLATION_CSV = joinpath(OUT_DIR, "ablation.csv")
const CROSSCHECK_CSV = joinpath(OUT_DIR, "crosscheck.csv")
const LENS_CSV = joinpath(OUT_DIR, "lens_summary.csv")

# ---- the pre-planned OFAT ablation axes (protocol §7, verbatim) --------------------------------
#
# The four REPRO-05 axes with their EXACT protocol-pinned variant sets (42-CASE-A-PROTOCOL.md
# §7; the Task-1 source-contract test pins each axis's variant list as committed text). The
# Dict IS the entire permitted variant set per axis: adding a value requires editing this
# Dict + a protocol amendment (the deliberate-act friction — T-42-04-1).
const ABLATION_AXES = Dict{String, Vector{String}}(
    # (a) FIT price parameters (§7a): the registered page-93 triple + the symmetric
    #     multiplicative λ_export probes (×0.5 / ×2.0).
    "fit_params" => ["registered", "lam_export_half", "lam_export_double"],
    # (b) λ₀ scalings (§7b): the registered :mem signal + the elementwise probes.
    "price_range" => ["registered", "scale_0.5", "scale_2.0"],
    # (c) population scale and fixtures (§7c): the two pinned proxies, the Phase-40
    #     nested-prefix ladder fractions (scripts/case_a_scaling.jl DEFAULT_LADDER_FRACTIONS),
    #     and the headline row itself (full_784 — reused, never re-run).
    "population" => [
        "proxy_ieee123",
        "ieee13_default",
        "1/78",
        "0.125",
        "0.25",
        "0.5",
        "0.75",
        "1.0",
        "full_784",
    ],
    # (d) device mix (§7d): the registered 3-device mix, batteries out, PV ownership split.
    "device_mix" => ["registered", "batteries_out", "pv_half"],
)

# Mode → axis: each ablation mode measures exactly its protocol axis (§7 lettering).
const ABLATION_MODE_AXIS = Dict{String, String}(
    "ablation-fit" => "fit_params",
    "ablation-price" => "price_range",
    "ablation-population" => "population",
    "ablation-devices" => "device_mix",
)

# The population-axis rung VALUES for the Dict-key fraction strings (§7c: the Phase-40
# nested-prefix ladder, `scripts/case_a_scaling.jl:97` DEFAULT_LADDER_FRACTIONS). Guarded
# below against drift from the population axis Dict.
const POPULATION_RUNG_FRACTIONS = Dict{String, Float64}(
    "1/78" => 1 / 78,
    "0.125" => 0.125,
    "0.25" => 0.25,
    "0.5" => 0.5,
    "0.75" => 0.75,
    "1.0" => 1.0,
)
# Drift guard: the rung-value table and the population axis Dict must cover exactly the
# same fraction variants (the axis's remaining entries are the three non-fraction variants).
begin
    pop_axis = ABLATION_AXES["population"]
    non_fraction = ("proxy_ieee123", "ieee13_default", "full_784")
    is_rung(v) = v in keys(POPULATION_RUNG_FRACTIONS)
    Set(filter(is_rung, pop_axis)) == Set(keys(POPULATION_RUNG_FRACTIONS)) &&
    all(v -> is_rung(v) || v in non_fraction, pop_axis) || error(
        "case_a_magnitude: POPULATION_RUNG_FRACTIONS keys " *
        "$(sort(collect(keys(POPULATION_RUNG_FRACTIONS)))) do not exactly cover the " *
        "population axis's fraction variants $(pop_axis) — the axis Dict and the rung " *
        "values drifted (aborting loudly)",
    )
end

# The population-axis proxy variants and the committed proxy fixtures they REUSE
# (protocol §7c: `proxy_ieee123`/`ieee13_default` rows come from proxy.csv — reused, never
# re-solved; the fixture name/seed come from PROXY_FIXTURES).
const POPULATION_VARIANT_FIXTURES = Dict{String, String}(
    "proxy_ieee123" => "ieee123-default",
    "ieee13_default" => "ieee13-default",
)

# The OFAT ablations run at the REGISTERED SEED ONLY (42-CASE-A-PROTOCOL.md §3: "The OFAT
# ablations run at seed 42 only" — a pre-registered scoping decision).
const SEED_ABLATION = REGISTERED_SEED

# The ablation upsert key: the plan's provenance identity (:axis, :variant, :seed,
# :t_horizon) PLUS the row-granularity columns (:kind, :rung) — the 42-03 lesson: the
# runner emits MULTIPLE rows per variant (one per ladder attempt + the gain/reuse row)
# and upserts per row, so the bare identity key would make every write DELETE the
# sibling rows of the same variant (a kill must leave captured rows).
const ABLATION_KEY = (:axis, :variant, :seed, :t_horizon, :kind, :rung)

# The per-run protocol SHA — filled by `main` from the guard, stamped on EVERY row
# (tampering mitigations T-42-03-1/T-42-03-3: each row is auditable to the exact
# protocol version that produced it).
const PROTOCOL_SHA = Ref("")

# ---- kv-flag parsing (tariff_comparison.jl / case_a_agreement.jl conventions) -----------------

function parse_kv_flag(args, flag::String, default)
    idx = findfirst(==(flag), args)
    idx === nothing && return default
    idx == length(args) && throw(ArgumentError("$flag requires a value (none given)"))
    return args[idx + 1]
end

"""
    _resolve_ablation_variants(mode, variant_spec) -> Vector{String}

Validate `--variant` against the mode's pre-planned axis Dict (T-42-04-4: an unknown value
is an ArgumentError listing the permitted variants — misuse exits nonzero BEFORE any work).
`nothing` (flag absent) and `"all"` both mean the FULL axis in protocol order. The
population axis additionally accepts a rung fraction's decimal expansion (e.g.
`0.01282051282051282`), normalized to the Dict key — committed row labels remain
`rung_<Dict-key>`.
"""
function _resolve_ablation_variants(mode::String, variant_spec)
    axis = ABLATION_MODE_AXIS[mode]
    permitted = ABLATION_AXES[axis]
    (variant_spec === nothing || variant_spec == "all") && return collect(permitted)
    v = String(variant_spec)
    if axis == "population"
        v in keys(POPULATION_RUNG_FRACTIONS) && return [v]
        v in ("proxy_ieee123", "ieee13_default", "full_784") && return [v]
        f = tryparse(Float64, v)
        if f !== nothing
            for (k, kf) in POPULATION_RUNG_FRACTIONS
                isapprox(f, kf; rtol = 1e-12, atol = 1e-15) && return [k]
            end
        end
    elseif v in permitted
        return [v]
    end
    throw(
        ArgumentError(
            "--variant $(repr(v)) is not a pre-registered '$axis' variant — the " *
            "protocol-pinned set (42-CASE-A-PROTOCOL.md §7) is: $(join(permitted, ", ")) " *
            "(or \"all\" for the full axis; population rung fractions also accept their " *
            "decimal expansion)",
        ),
    )
end

parse_args!(args) = begin
    mode = let m = parse_kv_flag(args, "--mode", "headline")
        m in MODES || throw(
            ArgumentError(
                "--mode must be one of the registered modes ($(join(MODES, ", ")); the " *
                "whitelist is extendable by later protocol amendments, never shrinkable) " *
                "— got $(repr(m))",
            ),
        )
        m
    end
    axis = let a = parse_kv_flag(args, "--axis", nothing)
        a === nothing ? nothing :
        let v = String(a)
            haskey(ABLATION_AXES, v) || throw(
                ArgumentError(
                    "--axis must be one of the pre-registered axes " *
                    "($(join(sort(collect(keys(ABLATION_AXES))), ", "))) — got $(repr(v))",
                ),
            )
            v
        end
    end
    variant = parse_kv_flag(args, "--variant", nothing)
    seed = let s = parse_kv_flag(args, "--seed", nothing)
        s === nothing ? nothing :
        let v = parse(Int, s)
            v in SEEDS || throw(
                ArgumentError(
                    "--seed $(v) is not a pre-registered seed — the protocol seed set " *
                    "(42-CASE-A-PROTOCOL.md §3) is: $(join(SEEDS, ", ")) (42 = primary/" *
                    "registered anchor). A new seed requires a protocol amendment first.",
                ),
            )
            v
        end
    end
    time_limit_s = let tl = parse_kv_flag(args, "--time-limit-s", nothing)
        tl === nothing ? nothing :
        let v = parse(Float64, tl)
            v > 0 || throw(
                ArgumentError(
                    "--time-limit-s must be > 0 (got $v) — a budget stop is the honest " *
                    "recorded `:budget_exceeded` outcome, never a silent truncation",
                ),
            )
            v
        end
    end
    variants = String[]
    if haskey(ABLATION_MODE_AXIS, mode)
        # Ablation modes: --axis (when given) must name the mode's own axis; the seed is
        # the REGISTERED 42 only (protocol §3); --variant is validated against the axis
        # Dict here — misuse exits nonzero before any work (T-42-04-4).
        mode_axis = ABLATION_MODE_AXIS[mode]
        axis === nothing ||
            axis == mode_axis ||
            throw(
                ArgumentError(
                    "--axis $(repr(axis)) does not match --mode $(repr(mode)) — that mode " *
                    "measures the '$(mode_axis)' axis (protocol §7)",
                ),
            )
        seed !== nothing &&
            seed != SEED_ABLATION &&
            throw(
                ArgumentError(
                    "the OFAT ablations run at the registered seed $(SEED_ABLATION) only " *
                    "(42-CASE-A-PROTOCOL.md §3: a pre-registered scoping decision — spread is " *
                    "measured on the headline, attribution is anchored at the registered seed)",
                ),
            )
        variants = _resolve_ablation_variants(mode, variant)
    elseif mode in ("crosscheck", "lenses")
        # Protocol §6 + the lens policy: the cross-check bound and the settlement lenses
        # are pinned to the CERTIFIED point — the registered anchor seed 42 only.
        # --axis/--variant stay ablation-only (misuse exits before any work).
        (axis === nothing && variant === nothing) || throw(
            ArgumentError(
                "--axis/--variant are ablation-mode flags — --mode $(repr(mode)) " *
                "accepts neither",
            ),
        )
        seed !== nothing &&
            seed != REGISTERED_SEED &&
            throw(
                ArgumentError(
                    "--mode $(repr(mode)) is scoped to the registered anchor seed " *
                    "$(REGISTERED_SEED) (the certified 784-house point; protocol §6 + the " *
                    "lens policy) — got $(repr(seed))",
                ),
            )
    elseif axis !== nothing || variant !== nothing
        throw(
            ArgumentError(
                "--axis/--variant are ablation-mode flags — --mode $(repr(mode)) accepts " *
                "neither",
            ),
        )
    end
    (; mode, axis, variant, seed, time_limit_s, variants)
end

# ---- honest solver-outcome recording ----------------------------------------------------------

"""
    run_rung_outcome(feeder, pf, aggs; T, λ₀, rung_attrs, time_limit_s)
        -> (; status, welfare, iters, message)

ONE ladder rung: `solve_admm` at executor defaults (ρ = `ADMM().ρ` — the locked
no-re-tuning configuration; maxiter/tolerances untouched) with the rung's conditional
splat — the `default` rung adds NOTHING (byte-identical call); a tightened rung threads
`agr_optimizer = select_optimizer(QP(); rung_attrs...)` (the documented seam). A rung is
CERTIFIED iff it returns `:converged` with a finite Real welfare (the function's own
converged contract). Solver-outcome failures are RECORDED OUTCOMES per the honesty
policy: a maxiter stall (`ConvergenceError`), a certificate refusal (`CertificateError`)
and a solver failure (`SolveFailedError`) become `error:<TypeName>` rows (iters from the
error, −1 sentinel when it carries none); the typed `UnconvergedAdmmError` non-`:converged`
guard becomes `error:unconverged_admm`; the wall-clock budget exit is the honest
`:budget_exceeded` row (NO certified welfare BY DESIGN). Anything else (misuse, a bug)
PROPAGATES and exits nonzero.
"""
function run_rung_outcome(feeder, pf, aggs; T::Int, λ₀, rung_attrs, time_limit_s)
    try
        r = solve_admm(
            feeder,
            pf,
            aggs;
            T = T,
            λ₀ = λ₀,
            ρ = ADMM().ρ,
            allow_export = true,
            (
                rung_attrs === nothing ? NamedTuple() :
                (; agr_optimizer = select_optimizer(QP(); rung_attrs...))
            )...,
            time_limit_s = time_limit_s,
        )
        if r.status === :converged && r.welfare isa Real && isfinite(r.welfare)
            return (;
                status = "converged",
                welfare = Float64(r.welfare),
                iters = Int(r.iters),
                message = "",
            )
        else
            # the honest wall-clock early exit: `:budget_exceeded` carries no welfare
            # BY DESIGN (never a plausible-but-uncertified price) — a recorded outcome.
            return (;
                status = ":budget_exceeded",
                welfare = missing,
                iters = Int(r.iters),
                message = "solve_admm returned status=:budget_exceeded (time_limit_s " *
                          "budget) — no certified welfare (honest early exit)",
            )
        end
    catch err
        if err isa ConvergenceError || err isa CertificateError || err isa SolveFailedError
            return (;
                status = "error:" * string(nameof(typeof(err))),
                welfare = missing,
                iters = err.iterations === nothing ? -1 : Int(err.iterations),
                message = first(string(err.msg), 400),
            )
        elseif err isa UnconvergedAdmmError
            return (;
                status = "error:unconverged_admm",
                welfare = missing,
                iters = -1,
                message = first(string(err.msg), 400),
            )
        else
            rethrow()
        end
    end
end

"""
    run_ladder_outcome(feeder, pf, aggs; T, λ₀, time_limit_s)
        -> (; rows, certified)

The PRE-REGISTERED AGR ladder (protocol §4): run `AGR_TOL_RUNGS` in declared order,
STOP-ON-FIRST-CERTIFIED, HARD STOP after the last rung. Every rung attempt is one row
(refusals included); if every executed rung refuses, the terminal state is the recorded
`error:ladder_exhausted` row — the DOCUMENTED NON-CLOSURE, never an out-of-Dict
tolerance. `certified` is the winning rung row (with its Real `welfare_dadp`) or
`nothing`.
"""
function run_ladder_outcome(feeder, pf, aggs; T::Int, λ₀, time_limit_s)
    rows = NamedTuple[]
    certified = nothing
    for rung in AGR_RUNG_ORDER
        rung_attrs = AGR_TOL_RUNGS[rung]
        println(
            "  ladder rung '",
            rung,
            "': ",
            rung_attrs === nothing ? "plain QP factory (executor default)" :
            string(rung_attrs),
            " — solving...",
        )
        flush(stdout)
        wall_s = @elapsed outcome = run_rung_outcome(
            feeder,
            pf,
            aggs;
            T = T,
            λ₀ = λ₀,
            rung_attrs = rung_attrs,
            time_limit_s = time_limit_s,
        )
        row = (
            kind = "rung",
            rung = rung,
            status = outcome.status,
            welfare_dadp = outcome.welfare,
            welfare_fit = missing,
            delta_w = missing,
            delta_pct = missing,
            iters = outcome.iters,
            wall_s = wall_s,
            note = flatten_note(outcome.message),
        )
        push!(rows, row)
        println(
            "  ladder rung '",
            rung,
            "': ",
            outcome.status,
            " iters=",
            outcome.iters,
            " (",
            round(wall_s; digits = 1),
            " s)",
        )
        flush(stdout)
        if outcome.welfare isa Real
            certified = row
            break   # STOP-ON-FIRST-CERTIFIED (protocol §4)
        end
    end
    if certified === nothing
        # HARD STOP after the last rung — the honest terminal state is the DOCUMENTED
        # NON-CLOSURE, recorded as its own row (never an out-of-Dict tolerance).
        push!(
            rows,
            (
                kind = "rung",
                rung = "(ladder)",
                status = "error:ladder_exhausted",
                welfare_dadp = missing,
                welfare_fit = missing,
                delta_w = missing,
                delta_pct = missing,
                iters = missing,
                wall_s = missing,
                note = "every pre-registered AGR rung refused — the documented " *
                       "non-closure (protocol §4); no tolerance outside the Dict was tried",
            ),
        )
        println(
            "  ladder EXHAUSTED: all pre-registered rungs refused — recorded as " *
            "error:ladder_exhausted (hard stop; no out-of-Dict tolerance)",
        )
        flush(stdout)
    end
    return (; rows = rows, certified = certified)
end

# ---- the FIT leg (unchanged fit_baseline + the ONE pinned retry) ------------------------------

function _fit_result(fb; note::String, retry::String)
    if fb.welfare isa Real && isfinite(fb.welfare)
        return (;
            status = "ok",
            welfare_fit = Float64(fb.welfare),
            message = note,
            retry = retry,
        )
    else
        return (;
            status = "fit_inexact",
            welfare_fit = missing,
            message = note *
                      " — fit_baseline reported a non-certified outcome " *
                      "(on_inexact = :report; social_fit = $(fb.social_fit))",
            retry = retry,
        )
    end
end

# The registered FIT price triple — sourced from the model's own page-93 constants
# (`src/pricing/fit.jl` FIT_λ_*, the protocol §2/§7a registered values), never re-stated
# as script-local numbers. The default `run_fit_outcome` call splats this verbatim.
const _FIT_REGISTERED =
    (λ_import = FIT_λ_IMPORT, λ_export = FIT_λ_EXPORT, λ_self = FIT_λ_SELF)

"""
    run_fit_outcome(feeder, pf, aggs; T, λ₀, fit_prices = _FIT_REGISTERED)
        -> (; status, welfare_fit, message, retry)

The FIT leg: `fit_baseline` UNCHANGED (batteryless by design, thesis Assumption A4) with
`on_inexact = :report` (protocol §5's registered call). `fit_prices` is the FIT price triple
`(λ_import, λ_export, λ_self)` forwarded to `fit_baseline`'s documented kwargs — the
registered default is the page-93 triple FROM THE MODEL'S OWN CONSTANTS (`FIT_λ_*`), so the
default call is byte-identical to every pre-42-04 call; only the axis-(a) ablation variants
pass a different triple (protocol §7a). On a typed solver failure
(`SolveFailedError`/`CertificateError`/`ConvergenceError` — the committed ieee13-ground
FIT INFEASIBLE precedent is exactly this class) the protocol-pinned ONE retry runs with
the SOLVER tightened (`select_optimizer(QP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)`)
— a SOLVER change, never a gate change. BOTH the attempt and the retry outcomes are
recorded in the returned status/note; a still-refused leg after the single retry is a
recorded outcome. Anything else PROPAGATES.
"""
function run_fit_outcome(feeder, pf, aggs; T::Int, λ₀, fit_prices = _FIT_REGISTERED)
    local fb
    try
        fb = fit_baseline(
            feeder,
            pf,
            aggs;
            T = T,
            λ₀ = λ₀,
            on_inexact = :report,
            fit_prices...,
        )
    catch err
        (err isa ConvergenceError) ||
            (err isa CertificateError) ||
            (err isa SolveFailedError) ||
            rethrow()
        status = "error:" * string(nameof(typeof(err)))
        message = first(string(err.msg), 400)
        println(
            "  FIT leg: ",
            status,
            " at the registered call — the protocol-pinned ONE retry (SOLVER tightened " *
            "to tol_gap 1e-10; never a gate, never ρ, never battery τ)...",
        )
        flush(stdout)
        try
            fb = fit_baseline(
                feeder,
                pf,
                aggs;
                T = T,
                λ₀ = λ₀,
                on_inexact = :report,
                optimizer = select_optimizer(
                    QP();
                    tol_gap_abs = 1e-10,
                    tol_gap_rel = 1e-10,
                ),
                fit_prices...,
            )
        catch err2
            (err2 isa ConvergenceError) ||
                (err2 isa CertificateError) ||
                (err2 isa SolveFailedError) ||
                rethrow()
            return (;
                status = "error:" * string(nameof(typeof(err2))),
                welfare_fit = missing,
                message = "attempt: " *
                          status *
                          " (" *
                          first(message, 200) *
                          "); " *
                          "pinned retry also refused: " *
                          first(string(err2.msg), 200),
                retry = "tol_gap_1e-10",
            )
        end
        return _fit_result(
            fb;
            note = "attempt: " * status * "; pinned retry (tol_gap_1e-10) certified",
            retry = "tol_gap_1e-10",
        )
    end
    return _fit_result(fb; note = "registered call (on_inexact = :report)", retry = "none")
end

# ---- the SHARED measurement point (the "same code path" claim, made structural) ---------------

"""
    _solve_and_gain_rows(feeder, pf, aggs, λ₀; T, time_limit_s) -> Vector{NamedTuple}

ONE measurement point's legs — the pre-registered AGR ladder (stop-on-first-certified), the
UNCHANGED `fit_baseline` FIT leg (with the ONE pinned retry), and the gain row — SHARED by
every measuring mode (headline, proxy, and the ablation axes (b)/(c)/(d)): the protocol §8
"same code path" claim is this function, not a description. Returns the point's rows: one
per rung attempt (+ the terminal `error:ladder_exhausted` row when the ladder closes empty)
and one gain row.
"""
function _solve_and_gain_rows(feeder, pf, aggs, λ₀; T::Int, time_limit_s)
    println("  ", length(aggs), " aggregators — AGR ladder (stop-on-first-certified)...")
    flush(stdout)
    ladder =
        run_ladder_outcome(feeder, pf, aggs; T = T, λ₀ = λ₀, time_limit_s = time_limit_s)

    println("  FIT leg (fit_baseline unchanged; on_inexact = :report)...")
    flush(stdout)
    fit_out = run_fit_outcome(feeder, pf, aggs; T = T, λ₀ = λ₀)
    println("  → FIT leg: ", fit_out.status)
    flush(stdout)

    rows = NamedTuple[]
    append!(rows, ladder.rows)
    if ladder.certified !== nothing &&
       fit_out.welfare_fit isa Real &&
       isfinite(fit_out.welfare_fit)
        # The ONLY gain computation in this script — the registered SIGN-SAFE definition
        # from the shared lib (protocol §1). The banned naive ratio appears nowhere.
        g = welfare_gain(ladder.certified.welfare_dadp, fit_out.welfare_fit)
        push!(
            rows,
            (
                kind = "gain",
                rung = ladder.certified.rung,
                status = "ok",
                welfare_dadp = ladder.certified.welfare_dadp,
                welfare_fit = fit_out.welfare_fit,
                delta_w = g.Δ,
                delta_pct = g.Δpct,
                iters = missing,
                wall_s = missing,
                note = "SIGN-SAFE registered gain (protocol §1): DADP ladder rung " *
                       "'$(ladder.certified.rung)' vs FIT leg ($(fit_out.retry)); " *
                       "the naive W_DADP/W_FIT ratio is banned",
            ),
        )
    else
        why =
            ladder.certified === nothing ?
            "no AGR ladder rung certified (ladder exhausted — documented non-closure)" :
            "DADP certified at rung '$(ladder.certified.rung)' but the FIT leg did not certify"
        push!(
            rows,
            (
                kind = "gain",
                rung = ladder.certified === nothing ? "(none)" : ladder.certified.rung,
                status = fit_out.status,
                welfare_dadp = ladder.certified === nothing ? missing :
                               ladder.certified.welfare_dadp,
                welfare_fit = fit_out.welfare_fit isa Real ? fit_out.welfare_fit : missing,
                delta_w = missing,
                delta_pct = missing,
                iters = missing,
                wall_s = missing,
                note = flatten_note(
                    "no certified pair — " *
                    why *
                    "; FIT: " *
                    (isempty(fit_out.message) ? "no certified welfare" : fit_out.message),
                ),
            ),
        )
    end
    return rows
end

"""
    _measure_point(feeder_sym, pop_sym, seed; T, time_limit_s) -> Vector{NamedTuple}

ONE measurement point at the frozen registered configuration with `(feeder_sym, pop_sym, seed)` bound — the population build, then `_solve_and_gain_rows` (the shared ladder + FIT +
gain path). Returns the point's rows: one per rung attempt (+ the terminal
`error:ladder_exhausted` row when the ladder closes empty) and one gain row.
"""
function _measure_point(
    feeder_sym::Symbol,
    pop_sym::Symbol,
    seed::Int;
    T::Int = T_H,
    time_limit_s = nothing,
)
    # The FROZEN REGISTERED CONFIGURATION (42-CASE-A-PROTOCOL.md §2), spelled out:
    #     feeder   = build_feeder(:ieee13)
    #     profiles = generate_profiles(; seed = sub_seed(SEED, :profiles), T = 24)
    #     λ₀       = build_price(:mem, 24, nothing)
    #     pf       = ConvexBranchFlow()
    #     aggs     = build_population(:case_a_784, feeder, :ieee13, profiles, sub_seed(SEED, :population))
    # The generic calls below ARE that configuration with (feeder_sym, pop_sym, seed)
    # bound; the headline binds (:ieee13, :case_a_784, seed) — byte-for-byte the
    # registered point. NO value here is a free constant beyond what the seams require.
    feeder = build_feeder(feeder_sym)
    profiles = generate_profiles(; seed = sub_seed(seed, :profiles), T = T)
    λ₀ = build_price(PRICE_SYM, T, nothing)
    pf = ConvexBranchFlow()
    aggs =
        build_population(pop_sym, feeder, feeder_sym, profiles, sub_seed(seed, :population))
    if pop_sym === :case_a_784
        # Fail-loud population-shape tripwire (the case_a_agreement idiom): each house
        # contributes exactly 3 devices rolled into its bus aggregator.
        houses = div(sum(length(a.devices) for a in aggs), 3)
        houses == _CASE_A_TOTAL_HOUSES || error(
            "case_a_magnitude: the built :case_a_784 population carries $houses houses " *
            "(3 devices each) but the selector's total is $_CASE_A_TOTAL_HOUSES — the " *
            "population shape changed; re-measure deliberately (aborting loudly)",
        )
    end
    println("  point :", pop_sym, " @ :", feeder_sym, " seed=", seed, ":")
    flush(stdout)
    return _solve_and_gain_rows(feeder, pf, aggs, λ₀; T = T, time_limit_s = time_limit_s)
end

# ---- CSV upsert machinery (the tariff_comparison.jl idiom) ------------------------------------

"""
    upsert_row(path, row::NamedTuple; key) -> nothing

Append-or-replace `row` in the CSV at `path`, keyed on `key` (a tuple of column names):
existing rows whose key matches the new row's are REPLACED, all other rows are kept
(`cols = :union` merges column sets across schema evolution). Header is written on
create. Re-runs replace their own rows and never drop siblings' rows; a kill mid-run
leaves the rows already captured (honesty policy — a kill is a measured outcome).
"""
function upsert_row(path::String, row::NamedTuple; key::NTuple{N, Symbol} where {N})
    mkpath(dirname(path))
    new = DataFrame([row])
    df = if isfile(path)
        old = CSV.read(path, DataFrame)
        keyof(r) = Tuple(r[c] for c in key)
        new_keys = Set(keyof(r) for r in eachrow(new))
        keep = filter(r -> !(keyof(r) in new_keys), old)
        vcat(keep, new; cols = :union)
    else
        new
    end
    CSV.write(path, df)
    return nothing
end

"""
    ensure_schema(path, cols) -> nothing

Guarantee the CSV exists (header-only when no row was ever captured): an empty table is
the HONEST content of a mode whose run-level failure left zero certified rows (a missing
FILE would read as "the measurement never ran"; a header-only table reads as "it ran and
certified nothing").
"""
function ensure_schema(path::String, cols::Vector{Symbol})
    mkpath(dirname(path))
    isfile(path) || CSV.write(path, DataFrame([Any[] for _ in cols], cols))
    return nothing
end

const MEASURE_COLS = Symbol[
    :kind,
    :rung,
    :status,
    :welfare_dadp,
    :welfare_fit,
    :delta_w,
    :delta_pct,
    :iters,
    :wall_s,
    :note,
    :protocol_sha,
    :julia_version,
    :threads,
    :blas_threads,
    :seed,
    :t_horizon,
]
const MAGNITUDE_COLS = Symbol[:mode; MEASURE_COLS]
const PROXY_COLS = Symbol[:fixture; MEASURE_COLS]
const ABLATION_COLS = vcat([:axis, :variant], MEASURE_COLS)
# The crosscheck row (protocol §6): the centralized bound + WHICH optimizer path, the
# reused certified W_DADP, the welfare agreement deltas, and the DADP-vs-λ₀ price lens
# re-fetched at the certified rung. `kind`/`rung` keep the row-granularity upsert idiom.
const CROSSCHECK_COLS = Symbol[
    :mode,
    :kind,
    :rung,
    :houses,
    :aggregators,
    :centralized_optimizer,
    :welfare_centralized,
    :welfare_dadp,
    :welfare_abs_delta,
    :welfare_rel_delta,
    :price_max_abs_delta,
    :price_max_rel_delta,
    :status,
    :note,
    :protocol_sha,
    :julia_version,
    :threads,
    :blas_threads,
    :seed,
    :t_horizon,
]
# The lens rows: compare_tariffs' own summary schema (tariff/engine/status/welfare/
# surplus split/equity/rebound/...) + the runner identity (mode/rung/protocol_sha/
# provenance). The declared list is the IDENTITY set — `cols = :union` carries the rest.
const LENS_COLS = Symbol[
    :mode,
    :tariff,
    :engine,
    :rung,
    :status,
    :welfare,
    :dso_total,
    :merchandising_surplus,
    :aggregators_total,
    :fairness_total,
    :feasibility_status,
    :batt_ok,
    :batt_refused,
    :batt_not_checked,
    :gini_bills,
    :theil_bills,
    :atkinson_bills,
    :palma_bills,
    :gini_surplus,
    :theil_surplus,
    :atkinson_surplus,
    :palma_surplus,
    :rebound_amount,
    :rebound_ratio,
    :bills_granularity,
    :notes,
    :protocol_sha,
    :julia_version,
    :threads,
    :blas_threads,
    :seed,
    :t_horizon,
]

# WR-04 discipline: the ACTIVE mode's artifact EXISTS (header-only when nothing was
# captured) BEFORE any failure branch — a run-level failure must ship its honest empty
# table, never a missing FILE. Per-mode by design: each mode writes exactly its own
# artifact, so the guarantee covers that mode's every exit path.
function ensure_all_schemas(mode::String)
    if mode == "headline"
        ensure_schema(MAGNITUDE_CSV, MAGNITUDE_COLS)
    elseif mode == "proxy"
        ensure_schema(PROXY_CSV, PROXY_COLS)
    elseif mode == "crosscheck"
        ensure_schema(CROSSCHECK_CSV, CROSSCHECK_COLS)
    elseif mode == "lenses"
        ensure_schema(LENS_CSV, LENS_COLS)
    else
        ensure_schema(ABLATION_CSV, ABLATION_COLS)
    end
    return nothing
end

"""
    write_point_rows(path, cols, identity, rows, T_H, seed; key) -> nothing

Upsert one CSV row per measurement row: identity columns (mode/fixture + the row's own
kind/rung), then the measured columns, then `protocol_sha`, then the provenance stamp —
the plan's row merge order. The upsert key carries the row-granularity columns (kind,
rung) so sibling rows of the same run replace only themselves.
"""
function write_point_rows(
    path::String,
    cols::Vector{Symbol},
    identity::NamedTuple,
    rows::Vector{<:NamedTuple},
    T_H::Int,
    seed::Int;
    key::NTuple{N, Symbol} where {N},
)
    for r in rows
        row =
            merge(identity, r, (protocol_sha = PROTOCOL_SHA[],), provenance_row(T_H, seed))
        # Guard the MERGED row: the raw measurement rows carry the measured columns;
        # identity + protocol_sha + provenance are merged here (the plan's row merge
        # order) — the WRITTEN row must carry every declared column.
        all(c in keys(row) for c in cols) || error(
            "case_a_magnitude: row is missing a declared column — merged row has " *
            "$(keys(row)), declared $cols",
        )
        upsert_row(path, row; key = key)
    end
    return nothing
end

# ---- modes ------------------------------------------------------------------------------------

function headline_main(seed::Int, time_limit_s)
    assert_protocol_registered()   # the guard is the mains' first statement too — the
    # CLI path inherits it from main; a direct call is gated independently (T-42-03-1).
    BLAS.set_num_threads(1)
    ensure_all_schemas("headline")
    println(
        "case_a_magnitude headline: seed=",
        seed,
        " (protocol §3), T=",
        T_H,
        ", ρ=",
        ADMM().ρ,
        " (executor default, NO re-tuning), time_limit_s=",
        repr(time_limit_s),
        " — measuring the registered 784-house point (LONG-RUNNING)...",
    )
    flush(stdout)
    wall_s = @elapsed rows = _measure_point(FEEDER_SYM, :case_a_784, seed; time_limit_s)
    write_point_rows(
        MAGNITUDE_CSV,
        MAGNITUDE_COLS,
        (mode = "headline",),
        rows,
        T_H,
        seed;
        key = (:mode, :seed, :t_horizon, :kind, :rung),
    )
    for r in rows
        println(
            "  → [",
            r.kind,
            "] rung=",
            r.rung,
            " status=",
            r.status,
            " welfare_dadp=",
            repr(r.welfare_dadp),
            " welfare_fit=",
            repr(r.welfare_fit),
            " delta_pct=",
            repr(r.delta_pct),
        )
    end
    flush(stdout)
    println(
        "case_a_magnitude headline seed=",
        seed,
        " complete in ",
        round(wall_s; digits = 1),
        " s → ",
        MAGNITUDE_CSV,
    )
    flush(stdout)
    return nothing
end

function proxy_main(time_limit_s)
    assert_protocol_registered()   # the guard is the mains' first statement too (T-42-03-1)
    BLAS.set_num_threads(1)
    ensure_all_schemas("proxy")
    println(
        "case_a_magnitude proxy: ",
        length(PROXY_FIXTURES),
        " protocol-pinned fixtures (ieee123/20260719 → ieee13/20260718), T=",
        T_H,
        ", time_limit_s=",
        repr(time_limit_s),
        " — certifying the measurement machinery at proxy scale...",
    )
    flush(stdout)
    wall_s = @elapsed for fx in PROXY_FIXTURES
        rows = _measure_point(fx.feeder_sym, fx.pop_sym, fx.seed; time_limit_s)
        write_point_rows(
            PROXY_CSV,
            PROXY_COLS,
            (fixture = fx.fixture,),
            rows,
            T_H,
            fx.seed;
            key = (:fixture, :seed, :t_horizon, :kind, :rung),
        )
        println("  → $(fx.fixture): $(length(rows)) rows recorded")
        flush(stdout)
    end
    println(
        "case_a_magnitude proxy complete in ",
        round(wall_s; digits = 1),
        " s → ",
        PROXY_CSV,
    )
    flush(stdout)
    return nothing
end

# ---- crosscheck + lenses (REPRO-04 bound + settlement lenses; protocol §6, §1 lenses) ---------

"""
    _certified_rung_row(seed::Int) -> DataFrameRow

The seed's CERTIFIED AGR rung row from magnitude.csv (mode=headline, kind=rung,
status=converged, finite Real welfare_dadp). The crosscheck/lenses modes REUSE this
certified DADP conditioning — the rung name selects the `AGR_TOL_RUNGS` attrs and
`welfare_dadp` is the reused headline welfare; the ladder is never re-run here. A missing
or uncertified headline fails LOUDLY (never a silent re-solve).
"""
function _certified_rung_row(seed::Int)
    isfile(MAGNITUDE_CSV) || error(
        "case_a_magnitude: crosscheck/lenses reuse the seed-$(seed) certified AGR rung " *
        "from $MAGNITUDE_CSV — run `--mode headline` first (a missing headline must fail " *
        "loudly, never be silently re-solved)",
    )
    df = CSV.read(MAGNITUDE_CSV, DataFrame)
    matches = filter(
        r ->
            string(r.mode) == "headline" &&
            r.seed == seed &&
            string(r.kind) == "rung" &&
            string(r.status) == "converged" &&
            r.welfare_dadp isa Real &&
            isfinite(r.welfare_dadp),
        df,
    )
    isempty(matches) && error(
        "case_a_magnitude: no certified AGR rung row for seed $(seed) in " *
        "$MAGNITUDE_CSV — crosscheck/lenses reuse the certified DADP conditioning " *
        "(the ladder is never re-run here); run `--mode headline` first",
    )
    return matches[end, :]
end

"""
    _rung_optimizer(rung::String) -> optimizer-or-nothing

The certified rung's AGR optimizer factory via the documented seam (`AGR_TOL_RUNGS` attrs
splatted into `select_optimizer(QP(); ...)`); the `default` rung resolves to `nothing`
(byte-identical plain-factory path).
"""
function _rung_optimizer(rung::AbstractString)
    haskey(AGR_TOL_RUNGS, rung) ||
        error("case_a_magnitude: unknown AGR rung $(repr(rung)) — not in AGR_TOL_RUNGS")
    attrs = AGR_TOL_RUNGS[rung]
    return attrs === nothing ? nothing : select_optimizer(QP(); attrs...)
end

# The tightened centralized-path symbol (the case_a_agreement.jl precedent): the bare
# literal `:tol_gap_1e-10` parses as SUBTRACTION — the constant is the only safe spelling.
const TOL_GAP_PATH = Symbol("tol_gap_1e-10")

"""
    _run_centralized_leg(feeder, pf, aggs; T, λ₀)
        -> (; ctx, welfare, path, refused_kind)

The centralized cross-check leg (`scripts/case_a_agreement.jl` `run_centralized` shape):
`solve_welfare` at the DEFAULT optimizer; on a `CertificateError` the ONE sanctioned
tightening (`select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10)` — the
measured `agreement.csv` path). The SOC-exactness gate is NEVER touched. `path` records
which route certified (`:default` | TOL_GAP_PATH | `nothing` when both refused —
the honest recorded outcome, `refused_kind` naming the final certificate). The tightened
path symbol is the TOL_GAP_PATH constant (Symbol("tol_gap_1e-10")) — the bare literal
`:tol_gap_1e-10` PARSES AS SUBTRACTION (Pitfall 6; the case_a_agreement precedent).
"""
function _run_centralized_leg(feeder, pf, aggs; T::Int, λ₀)
    try
        ctx, welfare, _ =
            solve_welfare(feeder, pf, aggs; T = T, λ₀ = λ₀, allow_export = true)
        return (; ctx = ctx, welfare = welfare, path = :default, refused_kind = nothing)
    catch err
        err isa CertificateError || rethrow()
        println(
            "  centralized leg: CertificateError at the DEFAULT optimizer — the ONE " *
            "sanctioned tightening (SOLVER tol_gap_abs/rel = 1e-10, NEVER the gate)...",
        )
        flush(stdout)
    end
    try
        ctx, welfare, _ = solve_welfare(
            feeder,
            pf,
            aggs;
            T = T,
            λ₀ = λ₀,
            allow_export = true,
            optimizer = select_optimizer(SOCP(); tol_gap_abs = 1e-10, tol_gap_rel = 1e-10),
        )
        return (; ctx = ctx, welfare = welfare, path = TOL_GAP_PATH, refused_kind = nothing)
    catch err
        err isa CertificateError || rethrow()
        println(
            "  centralized leg: CertificateError ALSO at the tightened solver — recorded " *
            "honestly (the gate was never touched).",
        )
        flush(stdout)
        return (;
            ctx = nothing,
            welfare = missing,
            path = nothing,
            refused_kind = Symbol(err.kind),
        )
    end
end

function crosscheck_main(seed::Int, time_limit_s)
    assert_protocol_registered()   # the guard is the mains' first statement (T-42-03-1)
    BLAS.set_num_threads(1)
    ensure_all_schemas("crosscheck")
    rung_row = _certified_rung_row(seed)
    rung = String(rung_row.rung)   # explicit String (CSV.jl String15: string(::InlineString) returns the inline type)
    w_dadp = Float64(rung_row.welfare_dadp)
    build = _registered_case_a_build(seed)
    houses = div(sum(length(a.devices) for a in build.aggs), 3)
    println(
        "case_a_magnitude crosscheck (protocol §6): seed=",
        seed,
        ", T=",
        T_H,
        " — certified W_DADP reused from magnitude.csv (rung '",
        rung,
        "', W_DADP=",
        w_dadp,
        "); re-fetching the certified rung's published prices, then the centralized " *
        "solve_welfare bound (LONG-RUNNING, ~4 GB leg)...",
    )
    flush(stdout)

    # (i) The certified rung's published DADP prices, re-fetched for the DADP-vs-λ₀ lens
    #     (prices are not persisted in magnitude.csv; the certified conditioning is
    #     deterministic, so this reproduces the certified solve's own prices).
    local λ_admm, admm_note
    rung_attrs = AGR_TOL_RUNGS[rung]
    try
        r = solve_admm(
            build.feeder,
            build.pf,
            build.aggs;
            T = T_H,
            λ₀ = build.λ₀,
            ρ = ADMM().ρ,
            allow_export = true,
            (
                rung_attrs === nothing ? NamedTuple() :
                (; agr_optimizer = select_optimizer(QP(); rung_attrs...))
            )...,
            time_limit_s = time_limit_s,
        )
        if r.status === :converged && r.welfare isa Real && isfinite(r.welfare)
            λ_admm = r.λ
            admm_note =
                "ADMM prices re-fetched at the certified rung '$rung' (iters=$(r.iters), " *
                "welfare=$(r.welfare) vs reused W_DADP=$w_dadp)"
        else
            λ_admm = nothing
            admm_note =
                "ADMM price re-fetch returned status=:budget_exceeded at the " *
                "certified rung '$rung' — no prices (honest early exit)"
        end
    catch err
        (err isa ConvergenceError) ||
            (err isa CertificateError) ||
            (err isa SolveFailedError) ||
            rethrow()
        λ_admm = nothing
        admm_note =
            "ADMM price re-fetch at the certified rung '$rung' refused: " *
            first(string(err.msg), 250)
    end
    println("  price re-fetch: ", admm_note)
    flush(stdout)

    # (ii) The centralized bound (protocol §6: default → ONE sanctioned tightening).
    cen = _run_centralized_leg(build.feeder, build.pf, build.aggs; T = T_H, λ₀ = build.λ₀)
    welfare_c =
        cen.welfare isa Real && isfinite(cen.welfare) ? Float64(cen.welfare) : missing
    centralized_optimizer =
        cen.path === :default ? "default" :
        cen.path === TOL_GAP_PATH ? "tol_gap_1e-10" :
        "refused:default+tol_gap_1e-10 kind=:$(cen.refused_kind)"
    println(
        "  centralized: optimizer_path=",
        centralized_optimizer,
        " welfare_centralized=",
        repr(welfare_c),
    )
    flush(stdout)

    # (iii) Agreement deltas (only when the centralized leg certified) and the
    #       DADP-vs-λ₀ price lens (only when the re-fetch certified).
    measurable = welfare_c isa Real
    welfare_abs = measurable ? abs(w_dadp - welfare_c) : missing
    welfare_rel = measurable ? welfare_abs / abs(welfare_c) : missing
    priceable = λ_admm !== nothing
    λ₀row = permutedims(Float64.(build.λ₀))          # 1×T row for broadcasting over (n×T)
    price_abs = priceable ? maximum(abs.(λ_admm .- λ₀row)) : missing
    price_rel =
        priceable ? maximum(abs.(λ_admm .- λ₀row) ./ max.(abs.(λ₀row), 1.0)) : missing

    status = welfare_c isa Real ? "ok" : "error:CertificateError"
    note = flatten_note(
        "centralized cross-check bound (protocol §6); welfare_dadp reused from " *
        "magnitude.csv (mode=headline, seed=$(seed), rung '$rung', status=converged) — " *
        "provenance-transparent reuse; price lens: price_max_abs_delta = max|λ_DADP − λ₀| " *
        "elementwise over the (n_load_nodes × T) published DADP vs λ₀ row-broadcast, " *
        "price_max_rel_delta uses the agreement.jl max(|λ₀|, 1) denominator; " *
        admm_note,
    )
    row = merge(
        (
            mode = "crosscheck",
            kind = "crosscheck",
            rung = rung,
            houses = houses,
            aggregators = length(build.aggs),
            centralized_optimizer = centralized_optimizer,
            welfare_centralized = welfare_c,
            welfare_dadp = w_dadp,
            welfare_abs_delta = welfare_abs,
            welfare_rel_delta = welfare_rel,
            price_max_abs_delta = price_abs,
            price_max_rel_delta = price_rel,
            status = status,
            note = note,
            protocol_sha = PROTOCOL_SHA[],
        ),
        provenance_row(T_H, seed),
    )
    all(c in keys(row) for c in CROSSCHECK_COLS) || error(
        "case_a_magnitude: crosscheck row is missing a declared column — has " *
        "$(keys(row)), declared $CROSSCHECK_COLS",
    )
    upsert_row(CROSSCHECK_CSV, row; key = (:mode, :seed, :t_horizon, :kind, :rung))
    println(
        "case_a_magnitude crosscheck complete → ",
        CROSSCHECK_CSV,
        " (status=",
        status,
        ", welfare_abs_delta=",
        repr(welfare_abs),
        ", price_max_abs_delta=",
        repr(price_abs),
        ")",
    )
    flush(stdout)
    return nothing
end

function lenses_main(seed::Int, time_limit_s)
    assert_protocol_registered()   # the guard is the mains' first statement (T-42-03-1)
    BLAS.set_num_threads(1)
    ensure_all_schemas("lenses")
    rung_row = _certified_rung_row(seed)
    rung = String(rung_row.rung)   # explicit String (CSV.jl String15: string(::InlineString) returns the inline type)
    build = _registered_case_a_build(seed)
    houses, map_rows = case_a_houses_variant(
        build.feeder,
        FEEDER_SYM,
        T_H,
        seed;
        variant = "registered",
        fraction = 1.0,
    )
    println(
        "case_a_magnitude lenses (protocol §1 secondary lenses): seed=",
        seed,
        ", T=",
        T_H,
        " — compare_tariffs engine=:admm at the certified rung '",
        rung,
        "' (houses=",
        length(houses),
        ", aggregators=",
        length(build.aggs),
        "; four-leg settlement, honest per-leg statuses — LONG-RUNNING)...",
    )
    flush(stdout)
    local summary
    try
        cmp = compare_tariffs(
            build.feeder,
            build.pf,
            build.aggs;
            T = T_H,
            λ₀ = build.λ₀,
            engine = :admm,
            ρ = ADMM().ρ,
            agr_optimizer = _rung_optimizer(rung),
            houses = houses,
            map_rows = map_rows,
            time_limit_s = time_limit_s,
        )
        summary = cmp.summary
    catch err
        (err isa ConvergenceError) ||
            (err isa CertificateError) ||
            (err isa SolveFailedError) ||
            rethrow()
        # The ADMM leg refused at the PASSED CERTIFIED rung (should not — the certified
        # conditioning): the honest `(run)` status row per the tariff_comparison idiom.
        row = merge(
            (
                mode = "lenses",
                tariff = "(run)",
                engine = "admm",
                rung = rung,
                status = "error:" * string(nameof(typeof(err))),
                notes = flatten_note(first(string(err.msg), 400)),
                protocol_sha = PROTOCOL_SHA[],
            ),
            provenance_row(T_H, seed),
        )
        upsert_row(LENS_CSV, row; key = (:mode, :tariff, :engine, :seed, :t_horizon))
        println(
            "lenses: ADMM leg refused at the certified rung — (run) status row recorded → ",
            LENS_CSV,
        )
        flush(stdout)
        return nothing
    end
    for r in eachrow(summary)
        nt = NamedTuple(r)
        # Line-oriented artifact hygiene (the tariff_comparison idiom): the summary
        # `notes` can carry solver messages with embedded newlines — flatten them
        # BEFORE the row lands (the FIT refusal's message is multi-line).
        haskey(nt, :notes) && (nt = merge(nt, (notes = flatten_note(nt.notes),)))
        row = merge(
            nt,
            (mode = "lenses", rung = rung, protocol_sha = PROTOCOL_SHA[]),
            provenance_row(T_H, seed),
        )
        upsert_row(LENS_CSV, row; key = (:mode, :tariff, :engine, :seed, :t_horizon))
        println(
            "  → tariff=",
            r.tariff,
            " status=",
            r.status,
            " welfare=",
            repr(r.welfare),
            " dso_total=",
            repr(r.dso_total),
        )
    end
    println(
        "case_a_magnitude lenses complete: ",
        nrow(summary),
        " tariff legs recorded → ",
        LENS_CSV,
    )
    flush(stdout)
    return nothing
end

# ---- OFAT ablation axes (REPRO-05; protocol §7) ------------------------------------------------

"""
    _registered_case_a_build(seed) -> (; feeder, pf, aggs, λ₀)

The FROZEN REGISTERED population build (protocol §2) shared by the ablation axes that
solve at the full registered population: `:case_a_784` over `:ieee13` with the registered
sub-seeds, `ConvexBranchFlow`, λ₀ = `:mem` at T = `T_H`. The 784-house shape tripwire
runs here (fail-loud before any solve).
"""
function _registered_case_a_build(seed::Int)
    feeder = build_feeder(FEEDER_SYM)
    profiles = generate_profiles(; seed = sub_seed(seed, :profiles), T = T_H)
    λ₀ = build_price(PRICE_SYM, T_H, nothing)
    pf = ConvexBranchFlow()
    aggs = build_population(
        :case_a_784,
        feeder,
        FEEDER_SYM,
        profiles,
        sub_seed(seed, :population),
    )
    houses = div(sum(length(a.devices) for a in aggs), 3)
    houses == _CASE_A_TOTAL_HOUSES || error(
        "case_a_magnitude: the built :case_a_784 population carries $houses houses " *
        "(3 devices each) but the selector's total is $_CASE_A_TOTAL_HOUSES — the " *
        "population shape changed; re-measure deliberately (aborting loudly)",
    )
    return (; feeder = feeder, pf = pf, aggs = aggs, λ₀ = λ₀)
end

"""
    _certified_headline_row() -> DataFrameRow

The seed-42 headline gain row's CERTIFIED DADP side from magnitude.csv (mode=headline,
kind=gain, finite Real welfare_dadp). Axis (a) REUSES this W_DADP — the DADP leg is
independent of the FIT axis (protocol §7 leg-independence rule) and is NEVER re-solved
here: a missing headline (or a gain row without a Real welfare_dadp) fails LOUDLY. The
gain row's STATUS may honestly be a FIT-leg refusal (the measured 784 outcome — the FIT
counterfactual refused after the sanctioned retry): the reused quantity is the certified
W_DADP from the row's recorded ladder rung, and the row's own status travels with it in
the ablation note — never silently dropped, never re-solved.
"""
function _certified_headline_row()
    isfile(MAGNITUDE_CSV) || error(
        "case_a_magnitude: ablation-fit needs the seed-$(SEED_ABLATION) certified headline " *
        "W_DADP from $MAGNITUDE_CSV — the DADP leg is independent of the FIT axis and is " *
        "REUSED, never re-solved (protocol §7 leg-independence rule); run " *
        "`--mode headline` first (a missing headline must fail loudly, never be " *
        "silently re-solved)",
    )
    df = CSV.read(MAGNITUDE_CSV, DataFrame)
    candidates = filter(
        r ->
            string(r.mode) == "headline" &&
            r.seed == SEED_ABLATION &&
            string(r.kind) == "gain" &&
            r.welfare_dadp isa Real &&
            isfinite(r.welfare_dadp),
        df,
    )
    isempty(candidates) && error(
        "case_a_magnitude: no seed-$(SEED_ABLATION) headline gain row with a certified " *
        "welfare_dadp in $MAGNITUDE_CSV — ablation-fit reuses the certified W_DADP and " *
        "never re-solves the DADP leg (protocol §7); run `--mode headline` first",
    )
    return candidates[end, :]
end

"""
    _reused_gain_row(src_csv, src_desc, src) -> NamedTuple

One provenance-transparent REUSE row (protocol §7c reuse discipline; T-42-04-3): the
source gain row's measured values are copied verbatim, the status becomes `reused`, and
the note NAMES the source CSV + row — reuse is never re-solved and never fabricated.
"""
function _reused_gain_row(src_csv::AbstractString, src_desc::AbstractString, src)
    note =
        "reused from $src_csv ($src_desc, kind=gain, source status=" *
        "$(string(coalesce(src.status, "")))) — provenance-transparent reuse " *
        "(protocol §7c reuse discipline); never re-solved, never fabricated"
    return (
        kind = "gain",
        rung = string(coalesce(src.rung, "")),
        status = "reused",
        welfare_dadp = src.welfare_dadp,
        welfare_fit = src.welfare_fit,
        delta_w = src.delta_w,
        delta_pct = src.delta_pct,
        iters = src.iters,
        wall_s = missing,
        note = flatten_note(note),
    )
end

"""
    _proxy_reuse_rows(variant) -> (rows, measurement_seed)

The population-axis proxy variants (`proxy_ieee123` / `ieee13_default`, protocol §7c):
reuse the fixture's gain row from the committed proxy.csv. The measurement seed travels
with the row (the fixtures pin their own seeds) so the reused row's provenance names the
seed the numbers actually came from.
"""
function _proxy_reuse_rows(variant::String)
    fixture = POPULATION_VARIANT_FIXTURES[variant]
    isfile(PROXY_CSV) || error(
        "case_a_magnitude: population variant '$variant' reuses the committed proxy row " *
        "from $PROXY_CSV — run `--mode proxy` first (reused rows are never re-solved; " *
        "a missing source artifact fails loudly)",
    )
    df = CSV.read(PROXY_CSV, DataFrame)
    matches = filter(r -> string(r.fixture) == fixture && string(r.kind) == "gain", df)
    isempty(matches) && error(
        "case_a_magnitude: no gain row for fixture '$fixture' in $PROXY_CSV — a reused " *
        "row cannot be fabricated; run `--mode proxy` first",
    )
    src = matches[end, :]
    return (
        [_reused_gain_row(PROXY_CSV, "fixture=$fixture, seed=$(src.seed)", src)],
        Int(src.seed),
    )
end

"""
    _headline_reuse_rows(label) -> (rows, measurement_seed)

The population-axis headline reuse (`full_784` — and the fraction-1.0 rung, which the
protocol §7c declares IS the headline measurement): reuse the seed-42 gain row from
magnitude.csv, never re-run. The reuse mirrors `_proxy_reuse_rows`: the source row's
measured values are copied VERBATIM (whatever its honest status — the measured 784 outcome
is a FIT-leg refusal, and the source status travels in the note), the status becomes
`reused`, provenance-transparent. A missing headline fails loudly.
"""
function _headline_reuse_rows(label::String)
    isfile(MAGNITUDE_CSV) || error(
        "case_a_magnitude: population variant '$label' is REUSED from the certified " *
        "headline row (protocol §7c: the headline row itself — reused, never re-run) — " *
        "run `--mode headline` first (a missing headline fails loudly, never re-solved " *
        "here)",
    )
    df = CSV.read(MAGNITUDE_CSV, DataFrame)
    matches = filter(
        r ->
            string(r.mode) == "headline" &&
            r.seed == SEED_ABLATION &&
            string(r.kind) == "gain",
        df,
    )
    isempty(matches) && error(
        "case_a_magnitude: no seed-$(SEED_ABLATION) headline gain row in " *
        "$MAGNITUDE_CSV — '$label' is reused from it, never re-run (protocol §7c)",
    )
    src = matches[end, :]
    return (
        [_reused_gain_row(MAGNITUDE_CSV, "mode=headline, seed=$(SEED_ABLATION)", src)],
        SEED_ABLATION,
    )
end

"""
    _write_ablation_rows(axis, variant, rows, measurement_seed)

The ablation write boundary: identity `(axis, variant)` + the measurement rows +
`protocol_sha` + provenance, upserted into ablation.csv under `ABLATION_KEY` (the
row-granularity key — sibling rows of the same variant replace only themselves).
"""
function _write_ablation_rows(axis::String, variant::String, rows, measurement_seed::Int)
    write_point_rows(
        ABLATION_CSV,
        ABLATION_COLS,
        (axis = axis, variant = variant),
        rows,
        T_H,
        measurement_seed;
        key = ABLATION_KEY,
    )
    return nothing
end

# Axis (a) values (protocol §7a): the probes are symmetric multiplicative deviations of
# the MODEL'S OWN registered λ_export (9.6 → 4.8 / 19.2 at the committed constants);
# λ_import and λ_self are unchanged. Sourced from the FIT_λ_* constants, never re-stated.
function _fit_params_for_variant(v::AbstractString)
    v == "registered" && return _FIT_REGISTERED
    v == "lam_export_half" &&
        return (λ_import = FIT_λ_IMPORT, λ_export = FIT_λ_EXPORT / 2, λ_self = FIT_λ_SELF)
    v == "lam_export_double" &&
        return (λ_import = FIT_λ_IMPORT, λ_export = FIT_λ_EXPORT * 2, λ_self = FIT_λ_SELF)
    throw(
        ArgumentError(
            "_fit_params_for_variant: unknown fit_params variant $(repr(v)); the " *
            "protocol-pinned set is $(ABLATION_AXES["fit_params"])",
        ),
    )
end

function ablation_fit_main(variants::Vector{String}, time_limit_s)
    assert_protocol_registered()   # the guard is the mains' first statement (T-42-03-1)
    BLAS.set_num_threads(1)
    ensure_all_schemas("ablation-fit")
    headline = _certified_headline_row()
    w_dadp = Float64(headline.welfare_dadp)
    build = _registered_case_a_build(SEED_ABLATION)
    println(
        "case_a_magnitude ablation-fit (fit_params, protocol §7a): seed=",
        SEED_ABLATION,
        ", T=",
        T_H,
        " — DADP REUSED from magnitude.csv (headline rung '",
        headline.rung,
        "', W_DADP=",
        w_dadp,
        "); re-solving ONLY fit_baseline per variant (leg independence)...",
    )
    flush(stdout)
    for v in variants
        prices = _fit_params_for_variant(v)
        println(
            "  variant '",
            v,
            "': λ_export=",
            prices.λ_export,
            " (λ_import=",
            prices.λ_import,
            ", λ_self=",
            prices.λ_self,
            ") — FIT solving...",
        )
        flush(stdout)
        wall_s = @elapsed fit_out = run_fit_outcome(
            build.feeder,
            build.pf,
            build.aggs;
            T = T_H,
            λ₀ = build.λ₀,
            fit_prices = prices,
        )
        certified = fit_out.welfare_fit isa Real && isfinite(fit_out.welfare_fit)
        g = certified ? welfare_gain(w_dadp, fit_out.welfare_fit) : nothing
        row = (
            kind = "gain",
            rung = string(headline.rung),
            status = fit_out.status,
            welfare_dadp = w_dadp,
            welfare_fit = certified ? fit_out.welfare_fit : missing,
            delta_w = certified ? g.Δ : missing,
            delta_pct = certified ? g.Δpct : missing,
            iters = missing,
            wall_s = wall_s,
            note = flatten_note(
                "fit_params ablation (protocol §7a; FIT prices cancel in social welfare " *
                "terms — the axis acts via dispatch incentives): DADP reused from " *
                "magnitude.csv (headline rung '$(headline.rung)'), only fit_baseline " *
                "re-solved; FIT: $(fit_out.message)",
            ),
        )
        _write_ablation_rows("fit_params", v, [row], SEED_ABLATION)
        println(
            "  → variant '",
            v,
            "': status=",
            fit_out.status,
            " delta_pct=",
            certified ? repr(g.Δpct) : "(no certified pair)",
            " (",
            round(wall_s; digits = 1),
            " s)",
        )
        flush(stdout)
    end
    return nothing
end

# Axis (b) values (protocol §7b): elementwise multiplicative λ₀ scalings — 1× (the
# registered signal), 0.5×, 2.0×.
function _price_scale_for_variant(v::AbstractString)
    v == "registered" && return 1.0
    v == "scale_0.5" && return 0.5
    v == "scale_2.0" && return 2.0
    throw(
        ArgumentError(
            "_price_scale_for_variant: unknown price_range variant $(repr(v)); the " *
            "protocol-pinned set is $(ABLATION_AXES["price_range"])",
        ),
    )
end

function ablation_price_main(variants::Vector{String}, time_limit_s)
    assert_protocol_registered()   # the guard is the mains' first statement (T-42-03-1)
    BLAS.set_num_threads(1)
    ensure_all_schemas("ablation-price")
    build = _registered_case_a_build(SEED_ABLATION)
    println(
        "case_a_magnitude ablation-price (price_range, protocol §7b): seed=",
        SEED_ABLATION,
        ", T=",
        T_H,
        " — the full AGR ladder re-runs per λ₀ scaling (the DADP problem itself changes)...",
    )
    flush(stdout)
    for v in variants
        scale = _price_scale_for_variant(v)
        λ₀v = build.λ₀ .* scale
        println("  variant '", v, "': λ₀ ×", scale, " — ladder + FIT + gain...")
        flush(stdout)
        wall_s = @elapsed rows = _solve_and_gain_rows(
            build.feeder,
            build.pf,
            build.aggs,
            λ₀v;
            T = T_H,
            time_limit_s = time_limit_s,
        )
        _write_ablation_rows("price_range", v, rows, SEED_ABLATION)
        for r in rows
            println(
                "    → [",
                r.kind,
                "] rung=",
                r.rung,
                " status=",
                r.status,
                " delta_pct=",
                repr(r.delta_pct),
            )
        end
        println("    (variant '", v, "' in ", round(wall_s; digits = 1), " s)")
        flush(stdout)
    end
    return nothing
end

function ablation_population_main(variants::Vector{String}, time_limit_s)
    assert_protocol_registered()   # the guard is the mains' first statement (T-42-03-1)
    BLAS.set_num_threads(1)
    ensure_all_schemas("ablation-population")
    feeder = build_feeder(FEEDER_SYM)
    pf = ConvexBranchFlow()
    λ₀ = build_price(PRICE_SYM, T_H, nothing)
    println(
        "case_a_magnitude ablation-population (population, protocol §7c): seed=",
        SEED_ABLATION,
        ", T=",
        T_H,
        " — nested-prefix rungs solve fresh (no per-rung re-tuning); proxies + " *
        "full_784/rung_1.0 are reused rows...",
    )
    flush(stdout)
    for v in variants
        if haskey(POPULATION_RUNG_FRACTIONS, v)
            fraction = POPULATION_RUNG_FRACTIONS[v]
            label = "rung_$v"
            if fraction >= 1.0
                # Protocol §7c: "the 1.0-rung IS the headline measurement" — the curve's
                # full-population point is the certified headline row itself, REUSED
                # (never re-run); the smaller rungs solve fresh below.
                rows, seed_for_row = _headline_reuse_rows(label)
                println(
                    "  variant '",
                    label,
                    "': REUSED from magnitude.csv (protocol §7c) — no solve",
                )
                flush(stdout)
            else
                houses, map_rows = case_a_houses_variant(
                    feeder,
                    FEEDER_SYM,
                    T_H,
                    SEED_ABLATION;
                    variant = "registered",
                    fraction = fraction,
                )
                aggs = case_a_variant_rollup(
                    houses,
                    map_rows;
                    context = "ablation-population $label",
                )
                println(
                    "  variant '",
                    label,
                    "': fraction=",
                    fraction,
                    ", houses=",
                    length(houses),
                    ", aggregators=",
                    length(aggs),
                    " — ladder-governed solve + fit at this population...",
                )
                flush(stdout)
                rows = _solve_and_gain_rows(
                    feeder,
                    pf,
                    aggs,
                    λ₀;
                    T = T_H,
                    time_limit_s = time_limit_s,
                )
                seed_for_row = SEED_ABLATION
            end
            _write_ablation_rows("population", label, rows, seed_for_row)
            for r in rows
                println(
                    "    → [",
                    r.kind,
                    "] rung=",
                    r.rung,
                    " status=",
                    r.status,
                    " delta_pct=",
                    repr(r.delta_pct),
                )
            end
            flush(stdout)
        elseif haskey(POPULATION_VARIANT_FIXTURES, v)
            rows, seed_for_row = _proxy_reuse_rows(v)
            println(
                "  variant '",
                v,
                "': REUSED from proxy.csv (fixture ",
                POPULATION_VARIANT_FIXTURES[v],
                ", seed ",
                seed_for_row,
                ") — no solve",
            )
            flush(stdout)
            _write_ablation_rows("population", v, rows, seed_for_row)
            println(
                "    → gain row reused: status=",
                rows[1].status,
                " delta_pct=",
                repr(rows[1].delta_pct),
            )
            flush(stdout)
        else
            rows, seed_for_row = _headline_reuse_rows(v)
            println(
                "  variant '",
                v,
                "': REUSED from magnitude.csv (protocol §7c: the headline row itself) — no solve",
            )
            flush(stdout)
            _write_ablation_rows("population", v, rows, seed_for_row)
            println(
                "    → gain row reused: status=",
                rows[1].status,
                " delta_pct=",
                repr(rows[1].delta_pct),
            )
            flush(stdout)
        end
    end
    return nothing
end

# The case_a_scaling.jl structural-equality idiom: `Aggregator`s are immutable with
# Vector fields, so `==` compares those fields by REFERENCE — structural equality is
# field-wise (device Vectors compare element-wise under `==`).
function _struct_fieldwise_equal(x, y)
    typeof(x) === typeof(y) || return false
    for n in fieldnames(typeof(x))
        getfield(x, n) == getfield(y, n) || return false
    end
    return true
end

function _aggregators_structurally_equal(x, y)
    x.bus == y.bus || return false
    x.φ == y.φ || return false
    x.Pdc == y.Pdc || return false
    length(x.devices) == length(y.devices) || return false
    return all(_struct_fieldwise_equal(dx, dy) for (dx, dy) in zip(x.devices, y.devices))
end

function ablation_devices_main(variants::Vector{String}, time_limit_s)
    assert_protocol_registered()   # the guard is the mains' first statement (T-42-03-1)
    BLAS.set_num_threads(1)
    ensure_all_schemas("ablation-devices")
    feeder = build_feeder(FEEDER_SYM)
    pf = ConvexBranchFlow()
    λ₀ = build_price(PRICE_SYM, T_H, nothing)
    println(
        "case_a_magnitude ablation-devices (device_mix, protocol §7d): seed=",
        SEED_ABLATION,
        ", T=",
        T_H,
        " — the full AGR ladder re-runs per variant on the rebuilt population (the DADP " *
        "problem itself changes)...",
    )
    flush(stdout)
    for v in variants
        houses, map_rows = case_a_houses_variant(
            feeder,
            FEEDER_SYM,
            T_H,
            SEED_ABLATION;
            variant = v,
            fraction = 1.0,
        )
        aggs =
            case_a_variant_rollup(houses, map_rows; context = "ablation-devices variant $v")
        if v == "registered"
            # The strongest drift guard (the case_a_scaling 1.0-rung tripwire): the
            # registered rebuild at the full fraction IS build_population(:case_a_784,...).
            profiles =
                generate_profiles(; seed = sub_seed(SEED_ABLATION, :profiles), T = T_H)
            full_ref = build_population(
                :case_a_784,
                feeder,
                FEEDER_SYM,
                profiles,
                sub_seed(SEED_ABLATION, :population),
            )
            length(aggs) == length(full_ref) &&
            all(_aggregators_structurally_equal(r, f) for (r, f) in zip(aggs, full_ref)) ||
                error(
                    "ablation-devices variant 'registered': the rebuilt 1.0-fraction roll-up " *
                    "does NOT match build_population(:case_a_784, ...) — the rebuild drifted " *
                    "from the builder (aborting loudly)",
                )
            println(
                "  ✓ registered rebuild matches the build_population roll-up " *
                "(structural check, ",
                length(houses),
                " houses)",
            )
            flush(stdout)
        end
        println(
            "  variant '",
            v,
            "': houses=",
            length(houses),
            ", aggregators=",
            length(aggs),
            " — ladder + FIT + gain...",
        )
        flush(stdout)
        wall_s = @elapsed rows = _solve_and_gain_rows(
            feeder,
            pf,
            aggs,
            λ₀;
            T = T_H,
            time_limit_s = time_limit_s,
        )
        _write_ablation_rows("device_mix", v, rows, SEED_ABLATION)
        for r in rows
            println(
                "    → [",
                r.kind,
                "] rung=",
                r.rung,
                " status=",
                r.status,
                " delta_pct=",
                repr(r.delta_pct),
            )
        end
        println("    (variant '", v, "' in ", round(wall_s; digits = 1), " s)")
        flush(stdout)
    end
    return nothing
end

# ---- entry ------------------------------------------------------------------------------------

function main(args)
    # THE PRE-REGISTRATION GATE — the FIRST executed code path (T-42-03-1): no protocol
    # file → no run; an uncommitted protocol → no run. Everything below exists only to
    # serve a measurement under the committed protocol version stamped on every row.
    PROTOCOL_SHA[] = assert_protocol_registered()
    parsed = parse_args!(args)
    if parsed.mode == "proxy" && parsed.seed !== nothing
        throw(
            ArgumentError(
                "--seed is not valid with --mode proxy — the proxy fixtures pin their " *
                "own protocol seeds (ieee123-default → 20260719, the ≈+0.263% provenance " *
                "fixture; ieee13-default → 20260718, the ground-fixture regression seed)",
            ),
        )
    end
    println(
        "case_a_magnitude: mode=",
        parsed.mode,
        " protocol_sha=",
        PROTOCOL_SHA[],
        " threads=",
        Threads.nthreads(),
        " blas=",
        BLAS.get_num_threads(),
        " (pinning BLAS to 1)",
    )
    flush(stdout)
    if parsed.mode == "headline"
        headline_main(
            parsed.seed === nothing ? REGISTERED_SEED : parsed.seed,
            parsed.time_limit_s,
        )
    elseif parsed.mode == "proxy"
        proxy_main(parsed.time_limit_s)
    elseif parsed.mode == "crosscheck"
        crosscheck_main(
            parsed.seed === nothing ? REGISTERED_SEED : parsed.seed,
            parsed.time_limit_s,
        )
    elseif parsed.mode == "lenses"
        lenses_main(
            parsed.seed === nothing ? REGISTERED_SEED : parsed.seed,
            parsed.time_limit_s,
        )
    else
        println(
            "case_a_magnitude ",
            parsed.mode,
            ": axis '",
            ABLATION_MODE_AXIS[parsed.mode],
            "', variants [",
            join(parsed.variants, ", "),
            "], seed=",
            SEED_ABLATION,
            " (protocol §3/§7)...",
        )
        flush(stdout)
        if parsed.mode == "ablation-fit"
            ablation_fit_main(parsed.variants, parsed.time_limit_s)
        elseif parsed.mode == "ablation-price"
            ablation_price_main(parsed.variants, parsed.time_limit_s)
        elseif parsed.mode == "ablation-population"
            ablation_population_main(parsed.variants, parsed.time_limit_s)
        else
            ablation_devices_main(parsed.variants, parsed.time_limit_s)
        end
        println("case_a_magnitude ", parsed.mode, " complete → ", ABLATION_CSV)
        flush(stdout)
    end
    return nothing
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end

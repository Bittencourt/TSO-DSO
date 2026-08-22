# scripts/reduce_ieee8500_impedances.jl — dependency-free (Base + stdlib regex only)
#
# Parses the 10 vendored, offline OpenDSS IEEE-8500 source files
# (`scripts/data/ieee8500/*.dss`, pinned commit 3b208397160213cae4a9e2d0a7d1aa3528ce26e1, fetched
# and sha256-verified 2026-08-21), reduces MV/LV line-code impedance matrices to positive-sequence
# R1/X1 pairs via Fortescue-averaging (same method as `reduce_ieee123_impedances.jl`), reduces the
# 9 3-winding center-tap service-transformer codes via a balanced-load star-equivalent decomposition
# (D-05 REVISED, Assumption A1), and (in default mode) emits a committed Julia source file at
# `src/data/ieee8500_impedances.jl` with per-segment series impedance in Ohms (MV/LV branches) or
# percent-on-own-kVA-base (transformer edges) — topology is read as plain text and never re-derived.
#
# This fixture has two pitfalls IEEE-123 never had (see 25-RESEARCH.md Architecture Patterns §3):
#   1. Phase-suffix-collapse introduces genuine PARALLEL EDGES (3 confirmed capacitor-jumper
#      collisions + 4 regulator banks) that must be assert-identical-then-deduped, never averaged.
#   2. The 3-winding center-tap transformer reduction is `R_total=ΣRs[1:3]`,
#      `X_total=0.5*(Xhl+Xht+Xlt)` — NOT the naive 2-winding `%Rs[1]+%Rs[2]`/bare-`Xhl` placeholder.
#
# Regulator/switch segments (voltage regulators + the substation transformer + the 38 ENABLED
# `switch=y` tie segments in Lines.dss) carry NO real impedance value in the emitted table — they
# get the SAME near-ideal low-impedance treatment as `IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` at
# fixture-build time (D-13, Assumption A2 analog); tap changing is not modeled. The remaining 5 of
# 43 `switch=y` records carry an explicit `enabled=False` in the source text — genuine,
# authoritative normally-open tie switches — and are EXCLUDED from `IEEE8500_REGULATOR_EDGES`
# entirely, mirroring `ieee123.jl`'s treatment of its 4 normally-open tie switches (kept out of
# `IEEE123_EDGES` so the graph is a clean tree). Confirmed by direct computation: including all 43
# switches produces `edges - (buses - 1) == 5` (5 independent cycles); excluding exactly the 5
# `enabled=False` records yields a fully connected tree over all 4,873 buses with `edges == 4872 ==
# buses - 1`, matching `assert_radial`'s edge-count theorem exactly.
#
# Three degenerate segments are resolved by a topological BUS-MERGE (quick task 260822-pxb,
# 2026-08-22 — see `detect_length_class_merge_pairs`/`merge_near_zero_mv_edges!` below and
# .planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md item 1): 2 genuine 1-ft
# real-conductor bus-split segments (`length=0.0003048 km`, an exact imperial round-trip), and
# `HVMV_Sub_connector` (the substation Low Side Bus busbar tie, `r_ohm=1e-6` — a modeling
# placeholder, not a physical line, that structurally breaks LinDistFlow SOC-exactness). Unlike
# the D-13 near-ideal treatment below (which keeps a bus pair but reassigns its impedance value),
# a bus-merge REMOVES the degenerate pair entirely: the two buses are collapsed into one survivor
# (chosen by a remaining-degree rule, lexicographic tie-break), and the casualty bus name never
# appears in the generated table (SUPERSEDES an earlier D-13-style value-reassignment for the
# connector specifically — see deferred-items.md item 1 for the full before/after history).
#
# Zero package dependencies (no `using`/`import` statements anywhere in this file): the parser is
# Base + stdlib PCRE regex only, so `Project.toml [deps]` is untouched by this script.
#
# Run:
#     julia scripts/reduce_ieee8500_impedances.jl            # regenerate the table
#     julia scripts/reduce_ieee8500_impedances.jl --verify   # self-check only, no file write

const SCRIPT_DIR = @__DIR__
const DATA_DIR = joinpath(SCRIPT_DIR, "data", "ieee8500")
const MASTER_DSS = joinpath(DATA_DIR, "Master.dss")
const LINECODES2_DSS = joinpath(DATA_DIR, "LineCodes2.DSS")
const LINES_DSS = joinpath(DATA_DIR, "Lines.dss")
const TRANSFORMERS_DSS = joinpath(DATA_DIR, "Transformers.dss")
const LOADXFMRCODES_DSS = joinpath(DATA_DIR, "LoadXfmrCodes.dss")
const TRIPLEX_LINES_DSS = joinpath(DATA_DIR, "Triplex_Lines.DSS")
const TRIPLEX_LINECODES_DSS = joinpath(DATA_DIR, "Triplex_Linecodes.dss")
const LOADS_DSS = joinpath(DATA_DIR, "Loads.dss")
const CAPACITORS_DSS = joinpath(DATA_DIR, "Capacitors.dss")
const REGULATORS_DSS = joinpath(DATA_DIR, "Regulators.dss")
const OUT_FILE = joinpath(SCRIPT_DIR, "..", "src", "data", "ieee8500_impedances.jl")

# Provenance (Task 1, `25-DATA-PROVENANCE.md`) — hardcoded per that task's emit_output guidance
# ("read back... via regex, or hardcode the SHA task 1 resolved").
const PINNED_COMMIT_SHA = "3b208397160213cae4a9e2d0a7d1aa3528ce26e1"
const FETCH_VERIFIED_DATE = "2026-08-21"

# Pinned sanity value for the transformer-reduction formula (RESEARCH.md Architecture Patterns §1,
# Common Pitfalls §2): CT5 (`%Rs=[0.6,1.2,1.2]`, `Xhl=Xht=2.04`, `Xlt=1.36`) reduces to
# `R_total=3.00%`, `X_total=2.72%` under the CONFIRMED (not the superseded placeholder) formula.
const CT5_R_PCT_EXPECTED = 3.00
const CT5_X_PCT_EXPECTED = 2.72
const SANITY_ATOL = 1.0e-2

# ─────────────────────────────────────────────────────────────────────────────────────────
# Substation busbar-tie connector: bus-MERGE treatment (SUPERSEDES the D-13 near-ideal reshape)
# (phase-25 gap-closure, 2026-08-21, deferred-items.md item 1 — SUPERSEDED 2026-08-22 by quick
# task 260822-pxb; see 25-DATA-PROVENANCE.md and deferred-items.md item 1 for the full history)
# ─────────────────────────────────────────────────────────────────────────────────────────
#
# `Lines.dss`'s `HVMV_Sub_connector` record (`bus1=_HVMV_Sub_LSB bus2=HVMV_Sub_48332
# length=0.001 km r1=0.001 x1=0.01`) reduces to `r_ohm=1e-6`, `x_ohm=1e-5` — a genuine MODELING
# PLACEHOLDER for the substation Low Side Bus busbar tie (the source's own `length=0.001` km is
# its floor/placeholder minimum, not a surveyed physical span), not a real metered line segment.
#
# PHYSICAL JUSTIFICATION: a substation busbar tie is not a physical conductor run at all — by
# definition it is a single physical node exposed as two named terminals. Unlike a
# voltage-regulator bank, the substation transformer, or a genuine `switch=y` tie (all of which
# ARE distinct physical devices, correctly given the near-ideal low-impedance treatment, D-13,
# Assumption A2 analog — see Step 5 below), the busbar tie has no device between its two named
# buses at all. A bus-MERGE is therefore STRICTLY MORE FAITHFUL than assigning it ANY impedance
# value, however small: it removes the non-physical element entirely instead of inventing a
# resistance for it. (The prior D-13 near-ideal reshape assigned `r=0.09330 Ω`/`x=0.04665 Ω`, a
# ~93,000x inflation over the literal parsed value — a reasonable interim stopgap, now superseded.)
#
# SOC-EXACTNESS GRADIENT ARGUMENT (why this edge needed special handling at all — unchanged; only
# the MECHANISM below changed from reassignment to removal): the LinDistFlow SOC-exactness
# argument needs a strictly-positive `r·l` loss-cost gradient in the objective to drive the
# squared-current variable `l` to its tight minimal value at the optimum. At this fixture's own
# per-unit base (`S_base=0.5 MVA`, `V_base=12.47 kV` — matches `src/data/ieee8500.jl`'s
# `IEEE8500_MV_BASE`), the literal parsed value is `r≈3.2e-9 pu` — six orders of magnitude below
# this project's own D-13 near-ideal convention (`IEEE123_SWITCH_R=3e-4 pu`/
# `IEEE123_SWITCH_X=1.5e-4 pu`, `src/data/ieee123.jl:79-80`). On a branch this close to zero-r the
# loss gradient is essentially absent, so the SOCP cone residual on THIS one branch did not shrink
# as solver tolerance tightened under the ORIGINAL (pre-fix) parse (measured: tol=1e-6 gap=0.4960
# -> tol=1e-8 gap=0.1796, STALLING then NaN at tighter rungs) — a STRUCTURAL relaxation failure,
# not shrinking numerical noise. A bus-merge resolves this MORE completely than the D-13 reshape
# did: there is no longer any near-zero-r edge at all to contribute a stalling cone residual. Full
# before/after record: deferred-items.md item 1 (both the original reshape and this superseding
# merge) and this quick task's SUMMARY.
#
# MECHANISM: detected via the SAME literal near-zero-`r_ohm` threshold as before
# (`MV_NEAR_ZERO_R_THRESHOLD_OHM`), then MERGED using the SAME generic bus-merge machinery as the
# 2 length-class 1-ft real-conductor splits (`resolve_merge_pairs`/`apply_merge!`, see
# `merge_near_zero_mv_edges!` below) — the degenerate edge disappears entirely rather than
# surviving with a reassigned value. Survivor: `HVMV_Sub_48332` (an exact degree tie between both
# endpoints — `_HVMV_Sub_LSB`'s only other connection is the logical regulator-bank edge,
# `HVMV_Sub_48332`'s only other connection is `LN5710794-3` into the rest of the feeder —
# resolved by the lexicographic tie-break: `"HVMV_Sub_48332" < "_HVMV_Sub_LSB"`, since `'H'`
# (ASCII 72) sorts before `'_'` (ASCII 95)).

# Explicit, documented THRESHOLD (never a hardcoded bus-pair name match) so a future upstream data
# refresh that silently widens or shrinks this set fails LOUDLY (see
# `merge_near_zero_mv_edges!`'s assert-exactly-1 check below) instead of quietly expanding this
# treatment. Picked to isolate exactly the one known degenerate segment with comfortable margin:
# across every parsed MV/LV branch in this fixture, the next-smallest `r_ohm` value is ≈4.8e-5 Ω
# (>=4.8x above this threshold) — nothing else in the real vendored data is anywhere close.
const MV_NEAR_ZERO_R_THRESHOLD_OHM = 1.0e-5
# (`merge_near_zero_mv_edges!` itself is defined further below, after the generic bus-merge
# machinery it reuses — see the "Zero-length / near-zero bus-merge machinery" section.)

# ─────────────────────────────────────────────────────────────────────────────────────────
# Bus-name normalization (8500's alphanumeric bus names, unlike 123's integer terminals)
# ─────────────────────────────────────────────────────────────────────────────────────────

"""
    parse_bus_base(tok) -> String

Strip a trailing phase-suffix run of one-or-more `.N` groups from a raw OpenDSS bus token, e.g.
`"M1009763.2"` -> `"M1009763"`, `"X2804253A.1.0"` -> `"X2804253A"` (the service-transformer LV
terminal case has a TWO-group suffix, `.1.0`/`.0.2`, unlike 123's single-group suffix — a
single-application `\\.\\d+\$` regex would leave a stray `.1`/`.0` behind, so this strips ALL
trailing dot-number groups in one pass via `(\\.\\d+)+\$`).
"""
function parse_bus_base(tok::AbstractString)
    return replace(tok, r"(\.\d+)+$" => "")
end

"""
    canonical_pair(b1, b2) -> Tuple{String,String}

Order-independent bus-pair key (lexicographically sorted), used throughout for deduping
phase-collapsed parallel edges (RESEARCH.md Code Examples "Deduplicating phase-collapsed parallel
edges").
"""
canonical_pair(b1::AbstractString, b2::AbstractString) = b1 < b2 ? (b1, b2) : (b2, b1)

"""
    regex_escape(s) -> String

Escape regex metacharacters in a string so it can be embedded literally in a `Regex(...)`
constructor. None of this fixture's linecode/XfmrCode names actually contain metacharacters
(letters, digits, `_`, `-`, `/` only), but this is applied defensively rather than assumed.
"""
function regex_escape(s::AbstractString)
    return replace(s, r"([.^$|()\[\]{}*+?\\])" => s"\\\1")
end

# ─────────────────────────────────────────────────────────────────────────────────────────
# Shared matrix reduction — COPIED VERBATIM from scripts/reduce_ieee123_impedances.jl
# (RESEARCH.md confirms direct transfer, same Ω-matrix pipe-delimited lower-triangular form)
# ─────────────────────────────────────────────────────────────────────────────────────────

"""
    parse_lower_triangular(s) -> Matrix{Float64}

Parse an OpenDSS pipe-delimited matrix literal into a full symmetric `n×n` matrix. Handles BOTH
conventions observed across this project's vendored `.dss` files: the LOWER-TRIANGULAR form
`reduce_ieee123_impedances.jl` and `LineCodes2.DSS` (MV) use (row `i` has exactly `i` values,
e.g. `"a | b c | d e f"`), AND the FULL-MATRIX form `Triplex_Linecodes.dss` (LV) uses (every row
has exactly `n` values, e.g. `"a b | b a"` for the 2×2 case) — `reduce_ieee123_impedances.jl`
never exercised the full-matrix form since IEEE-123 has no triplex secondaries. Detected by row
length pattern; throws loudly on any row-length pattern matching neither convention instead of
silently mis-shaping the matrix.
"""
function parse_lower_triangular(s::AbstractString)
    rows = split(s, '|')
    n = length(rows)
    row_vals = [parse.(Float64, split(strip(row))) for row in rows]
    lengths = length.(row_vals)
    mat = zeros(Float64, n, n)
    if lengths == collect(1:n)
        # Lower-triangular form: row i has i values, mirrored onto both triangles.
        for (i, vals) in enumerate(row_vals)
            for (j, v) in enumerate(vals)
                mat[i, j] = v
                mat[j, i] = v
            end
        end
    elseif all(==(n), lengths)
        # Full-matrix form: every row already has all n values.
        for (i, vals) in enumerate(row_vals)
            for (j, v) in enumerate(vals)
                mat[i, j] = v
            end
        end
    else
        throw(
            ArgumentError(
                "matrix literal has an unrecognized row-length pattern (neither lower-triangular " *
                "1:$(n) nor full $(n)×$(n)): row lengths = $lengths, content = \"$s\"",
            ),
        )
    end
    return mat
end

"""
    fortescue_reduce(mat) -> Float64

Positive-sequence Fortescue-averaging reduction of an `n×n` (n=1,2) symmetric line-code impedance
matrix: `R1 = mean(diag) - mean(offdiag)` (identically for X1). For `n == 1` there is no
off-diagonal at all — short-circuits directly to `mat[1,1]`.
"""
function fortescue_reduce(mat::AbstractMatrix{<:Real})
    n = size(mat, 1)
    size(mat, 2) == n || throw(
        ArgumentError("fortescue_reduce requires a square matrix, got size $(size(mat))"),
    )
    n == 1 && return Float64(mat[1, 1])
    diagvals = Float64[mat[i, i] for i in 1:n]
    offdiag = Float64[]
    for i in 1:n, j in 1:n
        i == j && continue
        push!(offdiag, mat[i, j])
    end
    return sum(diagvals) / n - sum(offdiag) / length(offdiag)
end

"""
    parse_linecode_rx_by_name(linecodes_text, name) -> (R1, X1)

Extract and Fortescue-reduce the `rmatrix=`/`xmatrix=` block for `New Linecode.<name>` (name
lookup, NOT the integer lookup `reduce_ieee123_impedances.jl` uses — 8500's linecodes are named,
e.g. `1ph-x4_acsrx4_acsr`). Works identically against `LineCodes2.DSS` (MV, `Units=km`) and
`Triplex_Linecodes.dss` (LV, `units=kft`) — the block SHAPE is the same in both files.

TWO of `LineCodes2.DSS`'s 69 codes (`1P_1/0_AXNJ_DB`, `3P_1/0_AXNJ_DB` — referenced 113 times by
`Lines.dss`) are defined as a SINGLE-LINE inline `r1=`/`x1=` positive-sequence pair instead of an
`rmatrix=`/`xmatrix=` block (no Fortescue reduction needed — the value already IS positive-
sequence); this is checked FIRST, falling back to the matrix-block form otherwise.
"""
function parse_linecode_rx_by_name(linecodes_text::AbstractString, name::AbstractString)
    esc_name = regex_escape(name)

    line_pat = "New\\s+[Ll]inecode\\." * esc_name * "\\b[^\\n]*"
    lm = match(Regex(line_pat, "i"), linecodes_text)
    lm === nothing &&
        throw(ArgumentError("could not find a New Linecode.$(name) definition in the vendored text"))
    line = lm.match
    mr1 = match(r"\br1=([\d.eE+-]+)"i, line)
    mx1 = match(r"\bx1=([\d.eE+-]+)"i, line)
    if mr1 !== nothing && mx1 !== nothing
        return (parse(Float64, mr1.captures[1]), parse(Float64, mx1.captures[1]))
    end

    pat = "New\\s+[Ll]inecode\\." * esc_name * "\\b" *
          ".*?~\\s*[Rr]matrix\\s*=\\s*\\[([^\\]]+)\\]" *
          ".*?~\\s*[Xx]matrix\\s*=\\s*\\[([^\\]]+)\\]"
    m = match(Regex(pat, "is"), linecodes_text)
    m === nothing && throw(
        ArgumentError("could not find an rmatrix/xmatrix block for linecode.$(name)"),
    )
    rmat = parse_lower_triangular(m.captures[1])
    xmat = parse_lower_triangular(m.captures[2])
    return (fortescue_reduce(rmat), fortescue_reduce(xmat))
end

# ─────────────────────────────────────────────────────────────────────────────────────────
# Step 1: MV `Lines.dss` — three record shapes (linecode-referencing, inline r1=/x1=, switch=y)
# ─────────────────────────────────────────────────────────────────────────────────────────

"""
    MVLinecodeRef

One parsed MV `New Line.*` statement that references a `Linecode=<name>` — bus tokens already
phase-stripped to their base name, length in km (the file's own declared `Units=km`).
"""
struct MVLinecodeRef
    bus1_base::String
    bus2_base::String
    linecode::String   # lowercased
    length_km::Float64
end

"""
    ImpedanceEdge

A generic phase-tagged impedance record ready for the assert-identical-then-dedupe step —
used for MV lines, LV triplex lines, and (indirectly, via zero-length inline records) nothing
else. Real Ω values only; regulator/switch near-ideal treatment is applied separately.
"""
struct ImpedanceEdge
    bus1_base::String
    bus2_base::String
    r_ohm::Float64
    x_ohm::Float64
end

"""
    parse_mv_lines(text) -> (Vector{MVLinecodeRef}, Vector{ImpedanceEdge}, Vector{Tuple{String,String}}, Vector{Tuple{String,String}})

Line-by-line (never a single big cross-field regex, so field ORDER in the source text does not
matter) parse of every `New Line.*` statement in the vendored `Lines.dss` text, dispatched into
four buckets:
  1. ENABLED `switch=y` tie segments (38 of 43 confirmed) — bus pair only, no impedance parsed
     (D-13: these get the SAME near-ideal treatment as regulators, assigned by the caller).
  2. DISABLED `switch=y` tie segments (5 of 43 confirmed, explicit `enabled=False` in the source
     text — real, authoritative normally-open ties) — bus pair only, EXCLUDED from the network
     entirely (the IEEE-123 precedent: normally-open tie switches stay open, so the graph is a
     clean tree). Without this split the reduction silently treats every switch as closed, which
     produces `edges != N-1` at `Feeder` construction time (5-cycle over-count) — see plan 25-03's
     Task 1 deviation note.
  3. `Linecode=<name>` references (2,473 confirmed) — deferred Ω lookup, returned as
     `MVLinecodeRef`.
  4. Inline `r1=`/`x1=` records (`HVMV_Sub_connector` + the 9 raw `CAP_*` capacitor-connector
     jumpers, 3 confirmed collision groups of 3 each) — real Ω computed directly here as
     `ImpedanceEdge`.
Throws loudly if any `New Line.*` statement matches none of the four shapes (never silently
drops a record).
"""
function parse_mv_lines(text::AbstractString)
    linecode_recs = MVLinecodeRef[]
    inline_recs = ImpedanceEdge[]
    switch_pairs = Tuple{String, String}[]
    disabled_switch_pairs = Tuple{String, String}[]
    total_seen = 0
    for raw in split(text, '\n')
        occursin(r"^\s*New\s+Line\."i, raw) || continue
        total_seen += 1
        m1 = match(r"[Bb]us1=(\S+)", raw)
        m2 = match(r"[Bb]us2=(\S+)", raw)
        (m1 === nothing || m2 === nothing) &&
            throw(ArgumentError("New Line statement missing Bus1/Bus2: $raw"))
        b1 = parse_bus_base(m1.captures[1])
        b2 = parse_bus_base(m2.captures[1])

        if occursin(r"switch=y"i, raw)
            if occursin(r"enabled=false"i, raw)
                push!(disabled_switch_pairs, (b1, b2))
            else
                push!(switch_pairs, (b1, b2))
            end
            continue
        end

        mlc = match(r"[Ll]inecode=(\S+)", raw)
        if mlc !== nothing
            mlen = match(r"[Ll]ength=([\d.]+)", raw)
            mlen === nothing &&
                throw(ArgumentError("linecode-referencing New Line missing Length=: $raw"))
            munits = match(r"[Uu]nits=(\S+)", raw)
            (munits === nothing || lowercase(munits.captures[1]) != "km") && throw(
                ArgumentError(
                    "expected units=km for a linecode-referencing MV line, got: $raw",
                ),
            )
            push!(
                linecode_recs,
                MVLinecodeRef(
                    b1,
                    b2,
                    lowercase(String(mlc.captures[1])),
                    parse(Float64, mlen.captures[1]),
                ),
            )
            continue
        end

        mr1 = match(r"\br1=([\d.eE+-]+)"i, raw)
        mx1 = match(r"\bx1=([\d.eE+-]+)"i, raw)
        (mr1 === nothing || mx1 === nothing) && throw(
            ArgumentError(
                "New Line statement matches neither Linecode= nor switch=y nor r1=/x1=: $raw",
            ),
        )
        mlen = match(r"[Ll]ength=([\d.]+)", raw)
        munits = match(r"[Uu]nits=(\S+)", raw)
        mlen === nothing && throw(ArgumentError("inline r1=/x1= New Line missing Length=: $raw"))
        (munits === nothing || lowercase(munits.captures[1]) != "km") && throw(
            ArgumentError("expected units=km for an inline r1=/x1= MV line, got: $raw"),
        )
        len_km = parse(Float64, mlen.captures[1])
        r_ohm = parse(Float64, mr1.captures[1]) * len_km
        x_ohm = parse(Float64, mx1.captures[1]) * len_km
        push!(inline_recs, ImpedanceEdge(b1, b2, r_ohm, x_ohm))
    end
    expected =
        length(linecode_recs) +
        length(inline_recs) +
        length(switch_pairs) +
        length(disabled_switch_pairs)
    expected == total_seen || throw(
        ArgumentError(
            "internal consistency check failed: saw $total_seen New Line.* statements but only " *
            "classified $expected (linecode=$(length(linecode_recs)), inline=$(length(inline_recs)), " *
            "switch=$(length(switch_pairs)), disabled_switch=$(length(disabled_switch_pairs)))",
        ),
    )
    return linecode_recs, inline_recs, switch_pairs, disabled_switch_pairs
end

# ─────────────────────────────────────────────────────────────────────────────────────────
# Zero-length bus-merge (quick task 260822-pxb, 2026-08-22) — REPLACES impedance fabrication with
# a topological bus MERGE for genuinely degenerate 1-ft real-conductor line splits.
# ─────────────────────────────────────────────────────────────────────────────────────────
#
# `Lines.dss` contains exactly 2 `New Line.*` records with `length=0.0003048 km` — EXACTLY 1.000
# ft, an exact imperial round-trip that fingerprints an artificial bus-split marker (both
# reference REAL linecodes: `3PH_H-397_ACSR...` and `1PH-x4_ACSRx4_ACSR`, i.e. genuine conductor,
# not a placeholder). Both were created when a longer original line was split to insert a
# service-transformer attachment bus (`LN5473436-1`/`LN5473436-2`, `LN6259981-1`/`LN6259981-2`).
# Two buses 1 ft apart are electrically the SAME node: the physically faithful fix is to MERGE
# the pair (collapse to one bus, reattach the service transformer to the survivor), never to
# assign either endpoint an impedance value — assigning ANY r/x here would invent resistance a
# real 1-ft span of 397_ACSR/x4_ACSR does not have.
#
# `length_km` (not `r_ohm`) is the detection KEY for this class: it needs no per-linecode lookup,
# and `0.0003048` km is a suspicious EXACT round number in imperial units, unlike this fixture's
# other short-but-non-round real MV segments (`0.000259836`, `0.000383926`, `0.000560638`,
# `0.000658611`, `0.000731906`, `0.000842188` km — no evidence ties these to the measured
# SOCP-exactness failure this task addresses; left untouched, "next tier"). The 53
# `length=0.001 km` inline `r1=1.0/x1=1.0` records (`CAP_*`-style capacitor-jumper/stub markers)
# are a DIFFERENT class entirely — deliberately artificial placeholder markers, not real short
# conductor spans — and are explicitly NOT merged in this pass either.
const MV_ZERO_LENGTH_KM = 0.0003048

"""
    detect_length_class_merge_pairs(linecode_recs) -> Vector{Tuple{String,String}}

Scan `linecode_recs` (pre-impedance-resolution `MVLinecodeRef`s) for any entry whose `length_km`
is `MV_ZERO_LENGTH_KM` (1.000 ft) within a tight `atol`; collect the canonical bus pair for each
match. Throws a loud `ArgumentError` unless EXACTLY 2 match — this fixture's 2 confirmed genuine
1-ft real-conductor bus-split segments (`LN5473436-1`, `LN6259981-1`) — so a future vendored-data
refresh that silently widens or shrinks this set fails loudly here instead of being silently
absorbed into the merge.
"""
function detect_length_class_merge_pairs(linecode_recs::Vector{MVLinecodeRef})
    pairs = Tuple{String, String}[]
    for r in linecode_recs
        if isapprox(r.length_km, MV_ZERO_LENGTH_KM; atol = 1.0e-9)
            push!(pairs, canonical_pair(r.bus1_base, r.bus2_base))
        end
    end
    length(pairs) == 2 || throw(
        ArgumentError(
            "expected EXACTLY 2 length-class ($(MV_ZERO_LENGTH_KM) km, 1.000 ft) degenerate MV " *
            "bus-split segments eligible for a merge, got $(length(pairs)): $(pairs) — the " *
            "vendored source may have changed; re-verify the intended scope of this treatment " *
            "before proceeding, do not silently widen or shrink it",
        ),
    )
    return pairs
end

"""
    compute_bus_degrees(linecode_recs, inline_recs, reg_edges, xfmr_instances) -> Dict{String,Int}

Compute a bus-name -> degree map over the fully-parsed-but-not-yet-merged MV topology: a bus's
degree is the count of DISTINCT logical connections touching it, from the COMBINED
`linecode_recs`+`inline_recs` (each already exactly one raw record per physical MV line at this
fixture's phase-collapse convention — counting these raw records directly is therefore already a
correct per-physical-edge count, no further dedupe needed for degree purposes), the logical
regulator/switch edge Set (`reg_edges`, ALREADY phase-deduplicated by `build_regulator_edges` —
counting its raw 3-per-bank phase records instead would inflate a regulator bank's contribution
3x relative to an ordinary MV line), and the count of `xfmr_instances` whose `mv_base` equals it
(each already one raw record per physical service transformer).
"""
function compute_bus_degrees(
    linecode_recs::Vector{MVLinecodeRef},
    inline_recs::Vector{ImpedanceEdge},
    reg_edges::Set{Tuple{String, String}},
    xfmr_instances::Vector{Tuple{String, String, String}},
)
    degree = Dict{String, Int}()
    bump!(name::AbstractString) = (degree[name] = get(degree, name, 0) + 1)
    for r in linecode_recs
        bump!(r.bus1_base)
        bump!(r.bus2_base)
    end
    for r in inline_recs
        bump!(r.bus1_base)
        bump!(r.bus2_base)
    end
    for (a, b) in reg_edges
        bump!(a)
        bump!(b)
    end
    for (mv_base, _, _) in xfmr_instances
        bump!(mv_base)
    end
    return degree
end

"""
    resolve_merge_pairs(pairs, degree) -> Dict{String,String}

Generic merge-pair resolver: given a `Vector{Tuple{String,String}}` of canonical degenerate bus
pairs and a pre-merge `degree` map (from `compute_bus_degrees`), asserts the pairs are PAIRWISE
DISJOINT (no bus name appears in more than one pair — throws loudly otherwise; chained/transitive
merges are explicitly unhandled and out of scope) and, for each pair, computes each endpoint's
degree MINUS 1 (excluding the pair's own edge/attachment contribution to itself — the degenerate
edge between the pair already bumped both endpoints' degree by exactly 1 in `compute_bus_degrees`)
then selects the SURVIVOR as the endpoint with the strictly greater remaining degree; on an exact
tie, the LEXICOGRAPHICALLY SMALLER bus name survives (Julia's default `String` ordering) — fully
deterministic, no bus-name special-casing. Returns a `Dict{String,String}` merge map (casualty =>
survivor).
"""
function resolve_merge_pairs(
    pairs::Vector{Tuple{String, String}},
    degree::Dict{String, Int},
)
    seen = Set{String}()
    for (a, b) in pairs
        for name in (a, b)
            name in seen && throw(
                ArgumentError(
                    "bus \"$name\" appears in more than one degenerate merge pair — " *
                    "chained/transitive merges are unhandled and out of scope for this " *
                    "reduction script; disjointness violated across pairs: $(pairs)",
                ),
            )
            push!(seen, name)
        end
    end
    merge_map = Dict{String, String}()
    for (a, b) in pairs
        da = get(degree, a, 0) - 1
        db = get(degree, b, 0) - 1
        survivor, casualty = if da > db
            (a, b)
        elseif db > da
            (b, a)
        else
            a < b ? (a, b) : (b, a)
        end
        merge_map[casualty] = survivor
    end
    return merge_map
end

"""
    apply_merge!(linecode_recs, inline_recs, switch_pairs, disabled_switch_pairs, xfmr_instances,
                 reg_edges, merge_map, drop_pairs) -> nothing

Generic rename-and-drop step applying a merge map (from `resolve_merge_pairs`) to every parsed-but-
not-yet-impedance-resolved MV structure, mutating each argument in place:

  1. DROP the `linecode_recs`/`inline_recs` entries whose canonical bus pair is in `drop_pairs`
     entirely (they never reach the impedance-computation loop — this is how the degenerate edges
     disappear, never via a self-loop).
  2. Rename `bus1_base`/`bus2_base` on every REMAINING `linecode_recs`/`inline_recs` entry, and
     both elements of every `switch_pairs`/`disabled_switch_pairs`/`reg_edges` entry, through the
     merge map (no-op for names absent from the map).
  3. Rename `mv_base` ONLY (never `lv_base`) on every `xfmr_instances` entry.
  4. Assert NO entry anywhere has `bus1_base == bus2_base` (or is a self-referential pair) after
     renaming — throws loudly if one appears (would indicate an undetected pre-existing parallel
     path this task's disjointness analysis did not anticipate; never silently drop it). A
     post-rename PARALLEL edge (two distinct records landing on the same bus pair with genuinely
     different impedance values) is caught downstream, loudly, by the existing `dedupe_edges`
     assert-identical-or-throw mechanism when `mv_edges_raw`/LV edges are assembled — it never
     silently averages or arbitrarily picks one value.
"""
function apply_merge!(
    linecode_recs::Vector{MVLinecodeRef},
    inline_recs::Vector{ImpedanceEdge},
    switch_pairs::Vector{Tuple{String, String}},
    disabled_switch_pairs::Vector{Tuple{String, String}},
    xfmr_instances::Vector{Tuple{String, String, String}},
    reg_edges::Set{Tuple{String, String}},
    merge_map::Dict{String, String},
    drop_pairs::Vector{Tuple{String, String}},
)
    rn(name::AbstractString) = get(merge_map, name, name)
    drop_set = Set(drop_pairs)

    kept_linecode = MVLinecodeRef[]
    for r in linecode_recs
        canonical_pair(r.bus1_base, r.bus2_base) in drop_set && continue
        push!(kept_linecode, MVLinecodeRef(rn(r.bus1_base), rn(r.bus2_base), r.linecode, r.length_km))
    end
    empty!(linecode_recs)
    append!(linecode_recs, kept_linecode)

    kept_inline = ImpedanceEdge[]
    for r in inline_recs
        canonical_pair(r.bus1_base, r.bus2_base) in drop_set && continue
        push!(kept_inline, ImpedanceEdge(rn(r.bus1_base), rn(r.bus2_base), r.r_ohm, r.x_ohm))
    end
    empty!(inline_recs)
    append!(inline_recs, kept_inline)

    for i in eachindex(switch_pairs)
        a, b = switch_pairs[i]
        switch_pairs[i] = (rn(a), rn(b))
    end
    for i in eachindex(disabled_switch_pairs)
        a, b = disabled_switch_pairs[i]
        disabled_switch_pairs[i] = (rn(a), rn(b))
    end
    for i in eachindex(xfmr_instances)
        mv_base, lv_base, code = xfmr_instances[i]
        xfmr_instances[i] = (rn(mv_base), lv_base, code)
    end

    renamed_reg_edges = Set{Tuple{String, String}}()
    for (a, b) in reg_edges
        push!(renamed_reg_edges, canonical_pair(rn(a), rn(b)))
    end
    empty!(reg_edges)
    union!(reg_edges, renamed_reg_edges)

    for r in linecode_recs
        r.bus1_base == r.bus2_base && throw(
            ArgumentError("bus merge introduced a self-loop in linecode_recs at \"$(r.bus1_base)\""),
        )
    end
    for r in inline_recs
        r.bus1_base == r.bus2_base && throw(
            ArgumentError("bus merge introduced a self-loop in inline_recs at \"$(r.bus1_base)\""),
        )
    end
    for (a, b) in switch_pairs
        a == b && throw(ArgumentError("bus merge introduced a self-loop in switch_pairs at \"$a\""))
    end
    for (a, b) in disabled_switch_pairs
        a == b &&
            throw(ArgumentError("bus merge introduced a self-loop in disabled_switch_pairs at \"$a\""))
    end
    for (a, b) in reg_edges
        a == b && throw(ArgumentError("bus merge introduced a self-loop in reg_edges at \"$a\""))
    end
    return nothing
end

"""
    merge_near_zero_mv_edges!(linecode_recs, inline_recs, switch_pairs, disabled_switch_pairs,
                               xfmr_instances, reg_edges, degree) -> Dict{String,String}

SUPERSEDES the prior D-13 near-ideal VALUE-REASSIGNMENT treatment (deferred-items.md item 1,
2026-08-21) with a bus-MERGE (quick task 260822-pxb, 2026-08-22) — see the file-header comment
above ("Substation busbar-tie connector: bus-MERGE treatment") for the full physical/
SOC-exactness-gradient justification, unchanged; only the mechanism changed.

Scans `inline_recs` (already-final-Ω `ImpedanceEdge`s — no separate per-km linecode lookup is
needed for these, unlike `linecode_recs`, so the near-zero-`r_ohm` threshold can be checked
directly here) for any entry whose `r_ohm` is below `MV_NEAR_ZERO_R_THRESHOLD_OHM`; throws loudly
unless EXACTLY 1 segment matches (this fixture's 1 confirmed degenerate segment, the
`HVMV_Sub_connector` substation busbar tie) — the same single-data-point guarantee the prior
reshape function enforced. Resolves the survivor via the SAME generic `resolve_merge_pairs` used
for the length-class splits (reusing the caller-supplied pre-merge `degree` map — valid here
since neither of this pair's buses overlaps any length-class casualty/survivor) and applies the
merge via the SAME generic `apply_merge!`, mutating `linecode_recs`/`inline_recs`/`switch_pairs`/
`disabled_switch_pairs`/`xfmr_instances`/`reg_edges` IN PLACE (including `reg_edges`, since
`_HVMV_Sub_LSB` is also an endpoint of the logical regulator-bank edge — omitting that rename
would leave a dangling, un-merged bus reference there).
"""
function merge_near_zero_mv_edges!(
    linecode_recs::Vector{MVLinecodeRef},
    inline_recs::Vector{ImpedanceEdge},
    switch_pairs::Vector{Tuple{String, String}},
    disabled_switch_pairs::Vector{Tuple{String, String}},
    xfmr_instances::Vector{Tuple{String, String, String}},
    reg_edges::Set{Tuple{String, String}},
    degree::Dict{String, Int},
)
    pairs = Tuple{String, String}[]
    for r in inline_recs
        if r.r_ohm < MV_NEAR_ZERO_R_THRESHOLD_OHM
            push!(pairs, canonical_pair(r.bus1_base, r.bus2_base))
        end
    end
    length(pairs) == 1 || throw(
        ArgumentError(
            "expected EXACTLY 1 degenerate near-zero-impedance MV segment (r_ohm < " *
            "$(MV_NEAR_ZERO_R_THRESHOLD_OHM) Ω) eligible for a merge, got $(length(pairs)): " *
            "$(pairs) — the vendored source may have changed; re-verify the intended scope of " *
            "this treatment (deferred-items.md item 1) before proceeding, do not silently widen it",
        ),
    )
    merge_map = resolve_merge_pairs(pairs, degree)
    apply_merge!(
        linecode_recs,
        inline_recs,
        switch_pairs,
        disabled_switch_pairs,
        xfmr_instances,
        reg_edges,
        merge_map,
        pairs,
    )
    println(
        "Bus merge (near-zero-r connector): $(length(merge_map)) pair(s) merged: " *
        "$(sort!(collect(merge_map)))",
    )
    return merge_map
end

# ─────────────────────────────────────────────────────────────────────────────────────────
# Step 2: assert-identical-then-dedupe (Pitfall 1 — parallel edges after phase-suffix collapse)
# ─────────────────────────────────────────────────────────────────────────────────────────

"""
    dedupe_edges(records) -> Dict{Tuple{String,String}, Tuple{Float64,Float64}}

Build the `(from,to)` -> `[records]` multimap keyed by the SORTED bus-pair; for any key with >1
record, assert ALL copies have identical `r_ohm`/`x_ohm` (within `rtol=1e-6`) and throw loudly
if not — NEVER average, NEVER arbitrarily pick (T-25-03). Keeps exactly one value per key.
RESEARCH.md Code Examples "Deduplicating phase-collapsed parallel edges", generalized from
`LineRecord` to the shared `ImpedanceEdge` type so this same function serves BOTH the MV and LV
dedupe steps.
"""
function dedupe_edges(records::Vector{ImpedanceEdge})
    by_pair = Dict{Tuple{String, String}, Vector{ImpedanceEdge}}()
    for r in records
        key = canonical_pair(r.bus1_base, r.bus2_base)
        push!(get!(by_pair, key, ImpedanceEdge[]), r)
    end
    result = Dict{Tuple{String, String}, Tuple{Float64, Float64}}()
    for (key, recs) in by_pair
        r_ref, x_ref = recs[1].r_ohm, recs[1].x_ohm
        all(
            rec ->
                isapprox(rec.r_ohm, r_ref; rtol = 1.0e-6) &&
                isapprox(rec.x_ohm, x_ref; rtol = 1.0e-6),
            recs,
        ) || throw(
            ArgumentError(
                "edge $key collapses $(length(recs)) non-identical phase-tagged records — " *
                "cannot safely dedupe, inspect source data",
            ),
        )
        result[key] = (r_ref, x_ref)
    end
    return result
end

"""
    assert_no_self_loops(keys_iter, context)

Throws `ArgumentError` if any `(bus1_base, bus2_base)` pair in `keys_iter` has `bus1_base ==
bus2_base`. Applied AFTER dedupe (RESEARCH.md confirms zero self-loops exist in the real vendored
`Lines.dss`, but this is asserted rather than assumed).
"""
function assert_no_self_loops(keys_iter, context::AbstractString)
    for (b1, b2) in keys_iter
        b1 == b2 &&
            throw(ArgumentError("self-loop detected at bus \"$b1\" in $context — check source data"))
    end
    return nothing
end

# ─────────────────────────────────────────────────────────────────────────────────────────
# Step 3: LV `Triplex_Lines.DSS` (real per-load kW path support) + `Loads.dss` + `Capacitors.dss`
# ─────────────────────────────────────────────────────────────────────────────────────────

"""
    parse_triplex_lines(text) -> Vector{Tuple{String,String,String,Float64}}

Parse every `New Line.*` statement in `Triplex_Lines.DSS`: `(bus1_base, bus2_base,
linecode_lowercased, length_ft)`. ALL 1,177 records declare `units=ft` (asserted, not assumed) —
`Triplex_Linecodes.dss` rates its matrices in `units=kft` (ohms per 1000 ft), so the caller must
divide `length_ft` by 1000 before multiplying by the reduced R1/X1 — this unit mismatch (ft vs
kft) is NOT flagged in 25-RESEARCH.md's prose but is required for correct LV impedance values;
omitting it would silently inflate every LV branch impedance by 1000x.
"""
function parse_triplex_lines(text::AbstractString)
    recs = Tuple{String, String, String, Float64}[]
    for raw in split(text, '\n')
        occursin(r"^\s*New\s+Line\."i, raw) || continue
        m1 = match(r"[Bb]us1=(\S+)", raw)
        m2 = match(r"[Bb]us2=(\S+)", raw)
        mlc = match(r"[Ll]inecode=(\S+)", raw)
        mlen = match(r"[Ll]ength=([\d.]+)", raw)
        munits = match(r"[Uu]nits=(\S+)", raw)
        (m1 === nothing || m2 === nothing || mlc === nothing || mlen === nothing || munits === nothing) &&
            throw(ArgumentError("Triplex_Lines.DSS record missing an expected field: $raw"))
        lowercase(munits.captures[1]) == "ft" ||
            throw(ArgumentError("expected units=ft for a Triplex_Lines.DSS record, got: $raw"))
        b1 = parse_bus_base(m1.captures[1])
        b2 = parse_bus_base(m2.captures[1])
        push!(recs, (b1, b2, lowercase(String(mlc.captures[1])), parse(Float64, mlen.captures[1])))
    end
    return recs
end

"""
    parse_loads(text) -> Dict{String,Float64}

Parse `Loads.dss`'s 1,177 `New Load.*` records into `SX-bus-base -> real kW` (D-03). Throws if
any bus base repeats (exactly one load per SX bus is expected).
"""
function parse_loads(text::AbstractString)
    loads = Dict{String, Float64}()
    for raw in split(text, '\n')
        occursin(r"^\s*New\s+Load\."i, raw) || continue
        mbus = match(r"[Bb]us1=(\S+)", raw)
        mkw = match(r"\bkW=([\d.]+)"i, raw)
        (mbus === nothing || mkw === nothing) &&
            throw(ArgumentError("New Load statement missing Bus1/kW: $raw"))
        bus = parse_bus_base(mbus.captures[1])
        haskey(loads, bus) &&
            throw(ArgumentError("duplicate load bus \"$bus\" in Loads.dss — expected exactly one load per SX bus"))
        loads[bus] = parse(Float64, mkw.captures[1])
    end
    return loads
end

"""
    parse_capacitors(text) -> Dict{String,Float64}

Parse `Capacitors.dss`'s 10 `New Capacitor.*` records (3 single-phase records for each of 3
banks + 1 three-phase record for the 4th bank), ACCUMULATING kvar per bus base — the 3
single-phase records at, e.g., `R20185.1/.2/.3` collapse to one `"R20185" => 900.0` entry.
"""
function parse_capacitors(text::AbstractString)
    caps = Dict{String, Float64}()
    for raw in split(text, '\n')
        occursin(r"^\s*New\s+Capacitor\."i, raw) || continue
        mbus = match(r"[Bb]us1=(\S+)", raw)
        mkvar = match(r"\bkvar=([\d.]+)"i, raw)
        (mbus === nothing || mkvar === nothing) &&
            throw(ArgumentError("New Capacitor statement missing Bus1/kvar: $raw"))
        bus = parse_bus_base(mbus.captures[1])
        caps[bus] = get(caps, bus, 0.0) + parse(Float64, mkvar.captures[1])
    end
    return caps
end

# ─────────────────────────────────────────────────────────────────────────────────────────
# Step 4: 3-winding center-tap service-transformer reduction (D-05 REVISED, Assumption A1)
# ─────────────────────────────────────────────────────────────────────────────────────────

"""
    XfmrCode

A reduced `XfmrCode` definition: `r_pct`/`x_pct` on the transformer's OWN kVA base (D-09: no
pu-conversion here), and `kva` (the code's own rating, read from `kVAs=[...]`'s first entry — all
three windings share the same kVA rating in this fixture).
"""
struct XfmrCode
    r_pct::Float64
    x_pct::Float64
    kva::Float64
end

"""
    parse_xfmr_codes(text) -> Dict{String,XfmrCode}

Parse `LoadXfmrCodes.dss`'s 9 `New XfmrCode.*` definitions and reduce each via the CONFIRMED
(post-research) 3-winding balanced center-tap formula:
`R_total% = %Rs[1]+%Rs[2]+%Rs[3]`, `X_total% = 0.5*(Xhl+Xht+Xlt)` — NOT the superseded
2-winding placeholder (`%Rs[1]+%Rs[2]`, bare `Xhl`) that under-counted both R and X (Common
Pitfalls §2). Derived and verified against OpenDSS's own `Transformer.pas` this research session
— not lifted from a citable published formula (Assumption A1).
"""
function parse_xfmr_codes(text::AbstractString)
    codes = Dict{String, XfmrCode}()
    for raw in split(text, '\n')
        occursin(r"^\s*New\s+XfmrCode\."i, raw) || continue
        mname = match(r"New\s+XfmrCode\.(\S+)"i, raw)
        mkva = match(r"kVAs=\[\s*([\d.]+)"i, raw)
        mrs = match(r"%Rs=\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\]"i, raw)
        mxhl = match(r"\bXhl=([\d.]+)"i, raw)
        mxht = match(r"\bXht=([\d.]+)"i, raw)
        mxlt = match(r"\bXlt=([\d.]+)"i, raw)
        (mname === nothing || mkva === nothing || mrs === nothing || mxhl === nothing || mxht === nothing || mxlt === nothing) &&
            throw(ArgumentError("New XfmrCode statement missing an expected field: $raw"))
        name = String(mname.captures[1])
        kva = parse(Float64, mkva.captures[1])
        rs1, rs2, rs3 = parse.(Float64, (mrs.captures[1], mrs.captures[2], mrs.captures[3]))
        xhl, xht, xlt = parse.(Float64, (mxhl.captures[1], mxht.captures[1], mxlt.captures[1]))
        r_total_pct = rs1 + rs2 + rs3
        x_total_pct = 0.5 * (xhl + xht + xlt)
        haskey(codes, name) &&
            throw(ArgumentError("duplicate XfmrCode definition for \"$name\" in $(LOADXFMRCODES_DSS)"))
        codes[name] = XfmrCode(r_total_pct, x_total_pct, kva)
    end
    return codes
end

"""
    parse_xfmr_instances(text) -> Vector{Tuple{String,String,String}}

Parse `LoadXfmrCodes.dss`'s 1,177 `New Transformer.* XfmrCode=<code> buses=[<mv> <lv1> <lv2>]`
instances into `(mv_bus_base, lv_bus_base, code_name)` triples. Asserts the two LV terminals
(`X<name>.1.0`/`X<name>.0.2`) share the SAME base bus name after phase-stripping — they are the
two secondary legs of the SAME physical service transformer.
"""
function parse_xfmr_instances(text::AbstractString)
    instances = Tuple{String, String, String}[]
    for raw in split(text, '\n')
        occursin(r"^\s*New\s+Transformer\."i, raw) || continue
        occursin(r"XfmrCode="i, raw) || continue
        mcode = match(r"XfmrCode=(\S+)"i, raw)
        mbuses = match(r"buses=\[\s*(\S+)\s+(\S+)\s+(\S+)\s*\]"i, raw)
        (mcode === nothing || mbuses === nothing) &&
            throw(ArgumentError("service-transformer New Transformer missing XfmrCode=/buses=: $raw"))
        mv_base = parse_bus_base(mbuses.captures[1])
        lv_base1 = parse_bus_base(mbuses.captures[2])
        lv_base2 = parse_bus_base(mbuses.captures[3])
        lv_base1 == lv_base2 || throw(
            ArgumentError(
                "service transformer's two LV terminals do not share a base bus name: $raw",
            ),
        )
        push!(instances, (mv_base, lv_base1, String(mcode.captures[1])))
    end
    return instances
end

"""
    build_xfmr_edges(instances, codes) -> Dict{Tuple{String,String}, NamedTuple}

Look up each parsed instance's `XfmrCode` and assemble the final
`Dict{Tuple{String,String}, NamedTuple{(:r_pct,:x_pct,:code,:kva), ...}}` keyed
`(mv_bus_base, lv_bus_base)`. Throws loudly on an unknown code reference or a duplicate
`(mv,lv)` key (expected exactly one service transformer per MV/LV bus pair).
"""
function build_xfmr_edges(
    instances::Vector{Tuple{String, String, String}},
    codes::Dict{String, XfmrCode},
)
    edges = Dict{
        Tuple{String, String},
        NamedTuple{(:r_pct, :x_pct, :code, :kva), Tuple{Float64, Float64, String, Float64}},
    }()
    for (mv_base, lv_base, code_name) in instances
        haskey(codes, code_name) || throw(
            ArgumentError(
                "service transformer references unknown XfmrCode \"$code_name\" — the " *
                "referenced-code tripwire should have caught this",
            ),
        )
        key = (mv_base, lv_base)
        haskey(edges, key) && throw(
            ArgumentError(
                "duplicate service-transformer edge $key — expected exactly one transformer " *
                "per (mv,lv) bus pair",
            ),
        )
        c = codes[code_name]
        edges[key] = (r_pct = c.r_pct, x_pct = c.x_pct, code = code_name, kva = c.kva)
    end
    return edges
end

# ─────────────────────────────────────────────────────────────────────────────────────────
# Step 5: Regulators / substation transformer / switch ties -> near-ideal edge set (D-13)
# ─────────────────────────────────────────────────────────────────────────────────────────

"""
    parse_transformer_bus_pairs(text) -> Vector{Tuple{String,String}}

Parse every `New Transformer.* buses=(<bus1>, <bus2>)` statement (the regulator-bank /
substation-transformer syntax — DISTINCT from the service-transformer `buses=[<mv> <lv1> <lv2>]`
syntax handled by `parse_xfmr_instances`) into phase-stripped `(bus1_base, bus2_base)` pairs.
Works against BOTH `Regulators.dss` (VREG2/VREG3/VREG4, 3 single-phase records each) and
`Transformers.dss` (`FEEDER_REG`, 3 single-phase records, PLUS the single 3-phase `HVMV_Sub`
substation transformer record) — same call site, same function, per D-13's "regulator banks plus
the substation transformer" requirement.
"""
function parse_transformer_bus_pairs(text::AbstractString)
    pairs = Tuple{String, String}[]
    for raw in split(text, '\n')
        occursin(r"^\s*New\s+Transformer\."i, raw) || continue
        occursin(r"buses=\(", raw) || continue
        m = match(r"buses=\(\s*(\S+?)\s*,\s*(\S+?)\s*\)"i, raw)
        m === nothing &&
            throw(ArgumentError("regulator/substation New Transformer missing buses=(...): $raw"))
        b1 = parse_bus_base(m.captures[1])
        b2 = parse_bus_base(m.captures[2])
        push!(pairs, (b1, b2))
    end
    return pairs
end

"""
    build_regulator_edges(reg_pairs, switch_pairs) -> Set{Tuple{String,String}}

Collapse the regulator-bank/substation-transformer pairs (3 raw phase records per bank ->
1 edge each, VREG2/VREG3/VREG4/FEEDER_REG + the single-record HVMV_Sub substation transformer)
AND the 38 ENABLED `switch=y` tie-segment pairs from `Lines.dss` into ONE `Set{Tuple{String,String}}`
— D-13's "Regulator and switch segments carry the... near-ideal low-impedance treatment (Assumption
A2 analog)" applies uniformly to both categories, so both land in the same emitted set. The caller
passes only the ENABLED switch pairs (`switch_pairs`, not `disabled_switch_pairs`) — the 5
`enabled=False` normally-open ties never reach this function, matching `ieee123.jl`'s exclusion of
its 4 normally-open tie switches. A plain `Set` naturally collapses the regulator banks' 3
identical-bus-pair phase records to 1 (there is no impedance value to compare here — the whole
point is that neither category carries a real impedance in this table), so no separate
assert-identical step is needed, unlike the MV/LV dedupe. Self-loops are asserted defensively.
"""
function build_regulator_edges(
    reg_pairs::Vector{Tuple{String, String}},
    switch_pairs::Vector{Tuple{String, String}},
)
    edges = Set{Tuple{String, String}}()
    for (b1, b2) in reg_pairs
        b1 == b2 && throw(
            ArgumentError("self-loop in regulator/substation-transformer bus pair: ($b1, $b2)"),
        )
        push!(edges, canonical_pair(b1, b2))
    end
    for (b1, b2) in switch_pairs
        b1 == b2 && throw(ArgumentError("self-loop in switch=y record: ($b1, $b2)"))
        push!(edges, canonical_pair(b1, b2))
    end
    return edges
end

# ─────────────────────────────────────────────────────────────────────────────────────────
# emit_output / verify / main
# ─────────────────────────────────────────────────────────────────────────────────────────

"""
    emit_output(mv_edges, lv_edges, xfmr_edges, cap_kvar, load_kw, reg_edges, outfile) -> String

Write the committed Julia source file declaring all six generated `const` tables. Returns the
path written.
"""
function emit_output(
    mv_edges::Dict{Tuple{String, String}, Tuple{Float64, Float64}},
    lv_edges::Dict{Tuple{String, String}, Tuple{Float64, Float64}},
    xfmr_edges::Dict{
        Tuple{String, String},
        NamedTuple{(:r_pct, :x_pct, :code, :kva), Tuple{Float64, Float64, String, Float64}},
    },
    cap_kvar::Dict{String, Float64},
    load_kw::Dict{String, Float64},
    reg_edges::Set{Tuple{String, String}},
    outfile::AbstractString,
)
    io = IOBuffer()
    println(io, "# src/data/ieee8500_impedances.jl")
    println(io, "#")
    println(
        io,
        "# GENERATED by scripts/reduce_ieee8500_impedances.jl — DO NOT hand-edit; re-run the",
    )
    println(io, "# script and re-commit if the upstream .dss files change.")
    println(io, "#")
    println(io, "# Source: raw.githubusercontent.com/dss-extensions/electricdss-tst/")
    println(io, "#         $(PINNED_COMMIT_SHA)/Version8/Distrib/IEEETestCases/8500-Node/")
    println(
        io,
        "#         (Master.dss, LineCodes2.DSS, Lines.dss, Transformers.dss, LoadXfmrCodes.dss,",
    )
    println(
        io,
        "#         Triplex_Lines.DSS, Triplex_Linecodes.dss, Loads.dss, Capacitors.dss,",
    )
    println(
        io,
        "#         Regulators.dss), pinned commit fetched and sha256-verified " *
        "$(FETCH_VERIFIED_DATE)",
    )
    println(io, "#         (vendored copies committed at scripts/data/ieee8500/).")
    println(io, "#")
    println(
        io,
        "# NOTE: Master.dss redirects LineCodes2.DSS (Ohm matrices, Units=km) for MV lines — NOT",
    )
    println(io, "# LineCodes.dss (a different, unrelated file bundled in the same upstream repo).")
    println(io, "#")
    println(io, "# 3-winding center-tap service-transformer reduction (D-05 REVISED):")
    println(io, "#     R_total% = %Rs[1] + %Rs[2] + %Rs[3]")
    println(io, "#     X_total% = 0.5 * (Xhl + Xht + Xlt)")
    println(
        io,
        "# Derived and verified against OpenDSS's own Transformer.pas this research session — not",
    )
    println(
        io,
        "# a citable published formula (Assumption A1). See 25-RESEARCH.md Architecture Patterns",
    )
    println(io, "# §1 for the full star-equivalent-decomposition derivation.")
    println(io, "#")
    println(
        io,
        "# Values are per-segment SERIES IMPEDANCE IN OHMS (MV/LV branches, positive-sequence",
    )
    println(
        io,
        "# Fortescue-averaged) or PERCENT ON THE TRANSFORMER'S OWN kVA BASE (transformer edges) —",
    )
    println(
        io,
        "# NEITHER is per-unit. Converted once at ingestion in ieee8500_modified() via",
    )
    println(io, "# to_pu_impedance (D-09) — never inside this reduction script.")
    println(io, "#")
    println(
        io,
        "# Regulator/switch segments (IEEE8500_REGULATOR_EDGES) carry NO real impedance value in",
    )
    println(
        io,
        "# this table — they are assigned the SAME near-ideal low-impedance treatment as",
    )
    println(
        io,
        "# IEEE123_SWITCH_R/IEEE123_SWITCH_X at fixture-build time (D-13, Assumption A2 analog);",
    )
    println(io, "# tap changing is not modeled.")
    println(io, "#")
    println(
        io,
        "# 5 of the source's 43 switch=y Lines.dss records carry an explicit enabled=False",
    )
    println(
        io,
        "# (genuine normally-open tie switches) and are EXCLUDED entirely from this set — the",
    )
    println(
        io,
        "# IEEE-123 precedent (normally-open ties stay open so the graph is a clean tree).",
    )
    println(io, "#")
    println(
        io,
        "# BUS MERGE (quick task 260822-pxb, 2026-08-22, REPLACES an earlier impedance-fabrication",
    )
    println(
        io,
        "# approach for this class): Lines.dss contains 2 New Line.* records with",
    )
    println(
        io,
        "# length=0.0003048 km (EXACTLY 1.000 ft) on a REAL linecode-referenced conductor —",
    )
    println(
        io,
        "# LN5473436-1 (bus2=L2674047, 3PH_H-397_ACSR) and LN6259981-1 (bus2=L3178969,",
    )
    println(
        io,
        "# 1PH-x4_ACSR), each a bus-split inserted to attach a service transformer (T5260514C,",
    )
    println(
        io,
        "# T5355596B respectively) onto a midpoint bus 1 ft from its neighbor. Two buses 1 ft",
    )
    println(
        io,
        "# apart are electrically the SAME node, so each pair is MERGED (never given a fabricated",
    )
    println(
        io,
        "# impedance value) onto the degree-rule survivor named above (L2674047, L3178969) — see",
    )
    println(
        io,
        "# scripts/reduce_ieee8500_impedances.jl's detect_length_class_merge_pairs/",
    )
    println(
        io,
        "# resolve_merge_pairs/apply_merge!, and 25-DATA-PROVENANCE.md for the full record",
    )
    println(
        io,
        "# (including the exact casualty bus names, which by design appear NOWHERE below).",
    )
    println(io, "#")
    println(
        io,
        "# BUS MERGE for the substation Low Side Bus busbar tie (Lines.dss's HVMV_Sub_connector",
    )
    println(
        io,
        "# record — quick task 260822-pxb, 2026-08-22, SUPERSEDING an earlier D-13 near-ideal",
    )
    println(
        io,
        "# value-reassignment): the record parses to a genuinely near-zero Ω value (r=1e-6,",
    )
    println(
        io,
        "# x=1e-5, a modeling placeholder for a non-physical busbar tie, not a physical line) that",
    )
    println(
        io,
        "# structurally breaks LinDistFlow SOC-exactness, so its 2 named endpoints are MERGED into",
    )
    println(
        io,
        "# the single survivor bus \"HVMV_Sub_48332\" (lexicographic tie-break on an exact degree",
    )
    println(
        io,
        "# tie) by reduce_ieee8500_impedances.jl's merge_near_zero_mv_edges! — see",
    )
    println(
        io,
        "# .planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md item 1 and",
    )
    println(
        io,
        "# 25-DATA-PROVENANCE.md for the full before/after record (including the casualty bus",
    )
    println(
        io,
        "# name, which by design appears NOWHERE below).",
    )
    println(io)
    println(
        io,
        "const IEEE8500_MV_BRANCH_RX_OHMS = Dict{Tuple{String, String}, Tuple{Float64, Float64}}(",
    )
    for key in sort!(collect(keys(mv_edges)))
        r, x = mv_edges[key]
        println(io, "    ($(repr(key[1])), $(repr(key[2]))) => ($(r), $(x)),")
    end
    println(io, ")")
    println(io)
    println(
        io,
        "const IEEE8500_LV_BRANCH_RX_OHMS = Dict{Tuple{String, String}, Tuple{Float64, Float64}}(",
    )
    for key in sort!(collect(keys(lv_edges)))
        r, x = lv_edges[key]
        println(io, "    ($(repr(key[1])), $(repr(key[2]))) => ($(r), $(x)),")
    end
    println(io, ")")
    println(io)
    println(
        io,
        "const IEEE8500_XFMR_EDGES = Dict{Tuple{String, String}, " *
        "NamedTuple{(:r_pct, :x_pct, :code, :kva), Tuple{Float64, Float64, String, Float64}}}(",
    )
    for key in sort!(collect(keys(xfmr_edges)))
        v = xfmr_edges[key]
        println(
            io,
            "    ($(repr(key[1])), $(repr(key[2]))) => (r_pct=$(v.r_pct), x_pct=$(v.x_pct), " *
            "code=$(repr(v.code)), kva=$(v.kva)),",
        )
    end
    println(io, ")")
    println(io)
    println(io, "const IEEE8500_CAPACITOR_KVAR = Dict{String, Float64}(")
    for key in sort!(collect(keys(cap_kvar)))
        println(io, "    $(repr(key)) => $(cap_kvar[key]),")
    end
    println(io, ")")
    println(io)
    println(io, "const IEEE8500_LOAD_KW = Dict{String, Float64}(")
    for key in sort!(collect(keys(load_kw)))
        println(io, "    $(repr(key)) => $(load_kw[key]),")
    end
    println(io, ")")
    println(io)
    println(io, "const IEEE8500_REGULATOR_EDGES = Set{Tuple{String, String}}([")
    for key in sort!(collect(reg_edges))
        println(io, "    ($(repr(key[1])), $(repr(key[2]))),")
    end
    println(io, "])")
    write(outfile, String(take!(io)))
    return outfile
end

"""
    verify() -> nothing

Self-check mode (`--verify`): parses `LoadXfmrCodes.dss`'s `XfmrCode` definitions and asserts the
`CT5` code's reduced `(R_total_pct, X_total_pct)` matches the pinned sanity pair within
`SANITY_ATOL`, throwing `ArgumentError` otherwise (Common Pitfalls §2 — the whole point of this
gate is to catch a regression to the superseded, silently-under-counting placeholder formula
before it ever reaches a fixture, per T-25-02).
"""
function verify()
    loadxfmrcodes_text = read(LOADXFMRCODES_DSS, String)
    codes = parse_xfmr_codes(loadxfmrcodes_text)
    length(codes) == 9 ||
        throw(ArgumentError("expected exactly 9 XfmrCode definitions, got $(length(codes))"))

    haskey(codes, "CT5") ||
        throw(ArgumentError("expected an XfmrCode named \"CT5\" in $(LOADXFMRCODES_DSS)"))
    ct5 = codes["CT5"]
    isapprox(ct5.r_pct, CT5_R_PCT_EXPECTED; atol = SANITY_ATOL) || throw(
        ArgumentError(
            "CT5 r_pct sanity check failed: got $(ct5.r_pct), expected ≈$(CT5_R_PCT_EXPECTED) " *
            "(atol=$(SANITY_ATOL)) — check for a regression to the superseded 2-winding placeholder",
        ),
    )
    isapprox(ct5.x_pct, CT5_X_PCT_EXPECTED; atol = SANITY_ATOL) || throw(
        ArgumentError(
            "CT5 x_pct sanity check failed: got $(ct5.x_pct), expected ≈$(CT5_X_PCT_EXPECTED) " *
            "(atol=$(SANITY_ATOL)) — check for a regression to the superseded 2-winding placeholder",
        ),
    )

    println(
        "PASS: 9 XfmrCodes ingested; CT5 R_total%=$(ct5.r_pct), X_total%=$(ct5.x_pct) " *
        "(pinned ≈$(CT5_R_PCT_EXPECTED)/≈$(CT5_X_PCT_EXPECTED))",
    )
    return nothing
end

"""
    main() -> nothing

Default (non-`--verify`) mode: full parse+reduce of all 10 vendored files, dedupe MV/LV parallel
edges, build the transformer/regulator/switch edge tables, parse loads/capacitors, then emit the
committed `src/data/ieee8500_impedances.jl`.
"""
function main()
    if ARGS == ["--verify"]
        verify()
        return nothing
    end

    lines_text = read(LINES_DSS, String)
    linecodes2_text = read(LINECODES2_DSS, String)
    triplex_lines_text = read(TRIPLEX_LINES_DSS, String)
    triplex_linecodes_text = read(TRIPLEX_LINECODES_DSS, String)
    loads_text = read(LOADS_DSS, String)
    capacitors_text = read(CAPACITORS_DSS, String)
    regulators_text = read(REGULATORS_DSS, String)
    transformers_text = read(TRANSFORMERS_DSS, String)
    loadxfmrcodes_text = read(LOADXFMRCODES_DSS, String)

    # --- MV: Lines.dss (parse only; impedance resolution deferred until AFTER the length-class
    #     bus-merge below, per detect_length_class_merge_pairs's own doc: it operates on
    #     linecode_recs BEFORE any per-km linecode impedance resolution) ---
    linecode_recs, inline_recs, switch_pairs, disabled_switch_pairs = parse_mv_lines(lines_text)
    length(switch_pairs) == 38 || throw(
        ArgumentError("expected exactly 38 enabled switch=y ties, got $(length(switch_pairs))"),
    )
    length(disabled_switch_pairs) == 5 || throw(
        ArgumentError(
            "expected exactly 5 disabled (enabled=False, normally-open) switch=y ties, got " *
            "$(length(disabled_switch_pairs))",
        ),
    )

    # --- Service transformers: LoadXfmrCodes.dss (9 codes + 1,177 instances) — parsed EARLY
    #     (quick task 260822-pxb reordering) so xfmr_instances is available for degree counting
    #     and merge renaming BEFORE the length-class bus-merge below. ---
    xfmr_codes = parse_xfmr_codes(loadxfmrcodes_text)
    length(xfmr_codes) == 9 ||
        throw(ArgumentError("expected exactly 9 XfmrCode definitions, got $(length(xfmr_codes))"))
    xfmr_instances = parse_xfmr_instances(loadxfmrcodes_text)
    length(xfmr_instances) == 1177 || throw(
        ArgumentError(
            "expected exactly 1177 service-transformer instances, got $(length(xfmr_instances))",
        ),
    )

    # --- Regulators + substation transformer + switch ties (D-13, near-ideal, no real Z here) —
    #     ALSO parsed EARLY (quick task 260822-pxb reordering) so the LOGICAL (phase-deduplicated)
    #     reg_edges Set is available for degree counting BEFORE the length-class bus-merge below
    #     (a 3-phase regulator bank must count once here, not 3x, relative to an ordinary MV line
    #     record — see compute_bus_degrees's own doc). ---
    reg_pairs = vcat(
        parse_transformer_bus_pairs(regulators_text),
        parse_transformer_bus_pairs(transformers_text),
    )
    reg_edges = build_regulator_edges(reg_pairs, switch_pairs)

    # --- Quick task 260822-pxb: length-class zero-length bus-merge (replaces impedance
    #     fabrication for the 2 genuine 1-ft real-conductor bus-split segments). Mutates
    #     linecode_recs/inline_recs/switch_pairs/disabled_switch_pairs/xfmr_instances/reg_edges
    #     IN PLACE before any of them are used further. The SAME pre-merge `degree` map is reused
    #     below for the connector's near-zero-r merge (valid: neither pair's buses overlap). ---
    degree = compute_bus_degrees(linecode_recs, inline_recs, reg_edges, xfmr_instances)
    length_class_pairs = detect_length_class_merge_pairs(linecode_recs)
    length_class_merge_map = resolve_merge_pairs(length_class_pairs, degree)
    apply_merge!(
        linecode_recs,
        inline_recs,
        switch_pairs,
        disabled_switch_pairs,
        xfmr_instances,
        reg_edges,
        length_class_merge_map,
        length_class_pairs,
    )
    println(
        "Bus merge (length-class): $(length(length_class_merge_map)) pairs merged: " *
        "$(sort!(collect(length_class_merge_map)))",
    )

    # --- Quick task 260822-pxb: near-zero-r substation busbar-tie connector bus-merge (SUPERSEDES
    #     the D-13 near-ideal value-reassignment treatment) — see merge_near_zero_mv_edges!'s own
    #     doc and the file-header comment above for the full justification. ---
    merge_near_zero_mv_edges!(
        linecode_recs,
        inline_recs,
        switch_pairs,
        disabled_switch_pairs,
        xfmr_instances,
        reg_edges,
        degree,
    )

    # --- MV impedance resolution (surviving linecode_recs, post both bus-merges) + assembly ---
    mv_codes = sort!(unique(r.linecode for r in linecode_recs))
    mv_linecode_rx = Dict(code => parse_linecode_rx_by_name(linecodes2_text, code) for code in mv_codes)
    mv_edges_raw = ImpedanceEdge[]
    for r in linecode_recs
        R1, X1 = mv_linecode_rx[r.linecode]
        push!(mv_edges_raw, ImpedanceEdge(r.bus1_base, r.bus2_base, R1 * r.length_km, X1 * r.length_km))
    end
    append!(mv_edges_raw, inline_recs)
    mv_edges = dedupe_edges(mv_edges_raw)
    assert_no_self_loops(keys(mv_edges), "IEEE8500_MV_BRANCH_RX_OHMS")

    # --- LV: Triplex_Lines.DSS + Triplex_Linecodes.dss (kft base, ft length -> /1000 conversion) ---
    triplex_recs = parse_triplex_lines(triplex_lines_text)
    lv_codes = sort!(unique(r[3] for r in triplex_recs))
    lv_linecode_rx =
        Dict(code => parse_linecode_rx_by_name(triplex_linecodes_text, code) for code in lv_codes)
    lv_edges_raw = ImpedanceEdge[]
    for (b1, b2, code, length_ft) in triplex_recs
        R1, X1 = lv_linecode_rx[code]
        length_kft = length_ft / 1000.0
        push!(lv_edges_raw, ImpedanceEdge(b1, b2, R1 * length_kft, X1 * length_kft))
    end
    lv_edges = dedupe_edges(lv_edges_raw)
    assert_no_self_loops(keys(lv_edges), "IEEE8500_LV_BRANCH_RX_OHMS")

    # --- Service-transformer edges (xfmr_instances already parsed + merge-renamed above) ---
    xfmr_edges = build_xfmr_edges(xfmr_instances, xfmr_codes)

    # --- Loads + capacitors ---
    load_kw = parse_loads(loads_text)
    cap_kvar = parse_capacitors(capacitors_text)

    outfile = emit_output(mv_edges, lv_edges, xfmr_edges, cap_kvar, load_kw, reg_edges, OUT_FILE)
    println(
        "Wrote MV=$(length(mv_edges)) LV=$(length(lv_edges)) XFMR=$(length(xfmr_edges)) " *
        "REG=$(length(reg_edges)) CAP=$(length(cap_kvar)) LOAD=$(length(load_kw)) to $(outfile)",
    )
    return nothing
end

main()

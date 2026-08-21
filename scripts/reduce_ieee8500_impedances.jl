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
# One MV segment (`HVMV_Sub_connector`, the substation Low Side Bus busbar tie) parses to a
# genuinely near-zero Ω value (r=1e-6, x=1e-5 — a modeling placeholder, not a physical line) that
# structurally breaks LinDistFlow SOC-exactness (see `reshape_near_zero_mv_edges!` below and
# .planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md item 1). It KEEPS its
# entry in `IEEE8500_MV_BRANCH_RX_OHMS` (same bus pair, same table) but its r/x VALUES are
# reassigned to the D-13 near-ideal Ω-equivalent — this is a documented, single-edge data-shaping
# decision, not the same "no real Ω value" mechanism used for regulators/switches below.
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
# D-13 near-ideal-branch treatment, extended to a degenerate real MV busbar-tie connector
# (phase-25 gap-closure, 2026-08-21 — see .planning/phases/25-ieee-8500-scalability-benchmark/
# deferred-items.md item 1, deferred there by plan 25-05)
# ─────────────────────────────────────────────────────────────────────────────────────────
#
# `Lines.dss`'s `HVMV_Sub_connector` record (`bus1=_HVMV_Sub_LSB bus2=HVMV_Sub_48332
# length=0.001 km r1=0.001 x1=0.01`) reduces to `r_ohm=1e-6`, `x_ohm=1e-5` — a genuine MODELING
# PLACEHOLDER for the substation Low Side Bus busbar tie (the source's own `length=0.001` km is
# its floor/placeholder minimum, not a surveyed physical span), not a real metered line segment.
#
# PHYSICAL JUSTIFICATION: a substation busbar tie is not a physical conductor run; treating it as
# "near-ideal" (small but strictly non-degenerate impedance) is the SAME modeling choice this same
# script already applies to every voltage-regulator bank, the substation transformer, and the 38
# enabled `switch=y` tie segments in this fixture (D-13, Assumption A2 analog — see Step 5 below).
#
# SOC-EXACTNESS GRADIENT ARGUMENT: the LinDistFlow SOC-exactness argument needs a strictly-positive
# `r·l` loss-cost gradient in the objective to drive the squared-current variable `l` to its tight
# minimal value at the optimum. At this fixture's own per-unit base (`S_base=0.5 MVA`,
# `V_base=12.47 kV` — matches `src/data/ieee8500.jl`'s `IEEE8500_MV_BASE`), the literal parsed
# value is `r≈3.2e-9 pu` — six orders of magnitude below this project's own D-13 near-ideal
# convention (`IEEE123_SWITCH_R=3e-4 pu`/`IEEE123_SWITCH_X=1.5e-4 pu`, `src/data/ieee123.jl:79-80`).
# On a branch this close to zero-r the loss gradient is essentially absent, so the SOCP cone
# residual on THIS one branch does not shrink as solver tolerance tightens (measured before this
# fix: tol=1e-6 gap=0.4960 -> tol=1e-8 gap=0.1796, STALLING then NaN at tighter rungs) — a
# STRUCTURAL relaxation failure, not shrinking numerical noise. Reassigning it to the D-13
# Ω-equivalent below restores a genuine noise floor that shrinks 27x tighter at tol=1e-8 (measured
# after: 0.03128 -> 0.001141, a 157x improvement at tol=1e-8) and behaves like real numerical
# noise instead of a structural floor. Full before/after record: deferred-items.md item 1.
#
# TABLE PLACEMENT: unlike the regulator/switch edge Set (`IEEE8500_REGULATOR_EDGES`, which carries
# NO real Ω value at all — its members are converted from `IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` pu
# directly at fixture-build time in `ieee8500.jl`), this edge KEEPS its native entry in
# `IEEE8500_MV_BRANCH_RX_OHMS` — SAME bus pair, SAME table, SAME connectivity. Only its `r_ohm`/
# `x_ohm` VALUES are reassigned, to the Ω-equivalent of `IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` at
# THIS fixture's own MV per-unit base. This keeps the fix entirely inside the already-Ω-valued MV
# table (no topology change, no new near-ideal category, `IEEE8500_REGULATOR_EDGES` untouched).
const IEEE8500_MV_S_BASE_MVA = 0.5     # matches src/data/ieee8500.jl's IEEE8500_MV_BASE.S_base
const IEEE8500_MV_V_BASE_KV = 12.47    # matches src/data/ieee8500.jl's IEEE8500_MV_BASE.V_base
const IEEE8500_MV_ZBASE_OHM = IEEE8500_MV_V_BASE_KV^2 / IEEE8500_MV_S_BASE_MVA  # ≈311.0018 Ω
const D13_NEAR_IDEAL_R_PU = 3.0e-4     # matches src/data/ieee123.jl's IEEE123_SWITCH_R verbatim
const D13_NEAR_IDEAL_X_PU = 1.5e-4     # matches src/data/ieee123.jl's IEEE123_SWITCH_X verbatim
const D13_NEAR_IDEAL_R_OHM_AT_MV_BASE = D13_NEAR_IDEAL_R_PU * IEEE8500_MV_ZBASE_OHM  # ≈0.09330 Ω
const D13_NEAR_IDEAL_X_OHM_AT_MV_BASE = D13_NEAR_IDEAL_X_PU * IEEE8500_MV_ZBASE_OHM  # ≈0.04665 Ω

# Explicit, documented THRESHOLD (never a hardcoded bus-pair name match) so a future upstream data
# refresh that silently reshapes a DIFFERENT or ADDITIONAL set of branches fails LOUDLY (see
# `reshape_near_zero_mv_edges!`'s assert-exactly-1 check below) instead of quietly expanding this
# treatment. Picked to isolate exactly the one known degenerate segment with comfortable margin:
# across every parsed MV/LV branch in this fixture, the next-smallest `r_ohm` value is ≈4.8e-5 Ω
# (>=4.8x above this threshold) — nothing else in the real vendored data is anywhere close.
const MV_NEAR_ZERO_R_THRESHOLD_OHM = 1.0e-5
# (`reshape_near_zero_mv_edges!` itself is defined further below, after the `ImpedanceEdge`
# struct it operates on — see Step 1.)

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
    reshape_near_zero_mv_edges!(mv_edges_raw) -> Vector{Tuple{String,String}}

Scan `mv_edges_raw` (pre-dedupe `ImpedanceEdge` records) for any entry whose `r_ohm` is below
`MV_NEAR_ZERO_R_THRESHOLD_OHM`; reassign ITS `r_ohm`/`x_ohm` IN PLACE to
`D13_NEAR_IDEAL_R_OHM_AT_MV_BASE`/`D13_NEAR_IDEAL_X_OHM_AT_MV_BASE` (same bus pair, same vector
slot — the edge is never removed or moved to a different table/category) and return the list of
reshaped bus pairs. Throws loudly unless EXACTLY 1 segment matches — this is a documented,
single-data-point decision (deferred-items.md item 1), not a general near-zero-branch filtering
mechanism, so a future vendored-source refresh that changes this set is caught immediately rather
than silently reshaping a different scope of branches.
"""
function reshape_near_zero_mv_edges!(mv_edges_raw::Vector{ImpedanceEdge})
    reshaped_pairs = Tuple{String, String}[]
    for i in eachindex(mv_edges_raw)
        e = mv_edges_raw[i]
        if e.r_ohm < MV_NEAR_ZERO_R_THRESHOLD_OHM
            mv_edges_raw[i] = ImpedanceEdge(
                e.bus1_base,
                e.bus2_base,
                D13_NEAR_IDEAL_R_OHM_AT_MV_BASE,
                D13_NEAR_IDEAL_X_OHM_AT_MV_BASE,
            )
            push!(reshaped_pairs, canonical_pair(e.bus1_base, e.bus2_base))
        end
    end
    length(reshaped_pairs) == 1 || throw(
        ArgumentError(
            "expected EXACTLY 1 degenerate near-zero-impedance MV segment (r_ohm < " *
            "$(MV_NEAR_ZERO_R_THRESHOLD_OHM) Ω) eligible for the D-13 near-ideal reshape, got " *
            "$(length(reshaped_pairs)): $(reshaped_pairs) — the vendored source may have changed; " *
            "re-verify the intended scope of this treatment (deferred-items.md item 1) before " *
            "proceeding, do not silently widen it",
        ),
    )
    println(
        "D-13 near-ideal reshape: $(length(reshaped_pairs)) degenerate MV segment(s) reassigned " *
        "from a literal near-zero Ω value to (r=$(D13_NEAR_IDEAL_R_OHM_AT_MV_BASE), " *
        "x=$(D13_NEAR_IDEAL_X_OHM_AT_MV_BASE)) Ω: $(reshaped_pairs)",
    )
    return reshaped_pairs
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
        "# NOT A VERBATIM TRANSCRIPTION for ONE MV edge: (\"HVMV_Sub_48332\", \"_HVMV_Sub_LSB\")",
    )
    println(
        io,
        "# — the substation Low Side Bus busbar tie (Lines.dss's HVMV_Sub_connector record) —",
    )
    println(
        io,
        "# parses to a genuinely near-zero Ω value (r=1e-6, x=1e-5, a modeling placeholder, not a",
    )
    println(
        io,
        "# physical line) that structurally breaks LinDistFlow SOC-exactness. Its r_ohm/x_ohm",
    )
    println(
        io,
        "# VALUES below are the D-13 near-ideal Ω-equivalent (IEEE123_SWITCH_R/X converted at this",
    )
    println(
        io,
        "# fixture's own MV per-unit base), reassigned by reduce_ieee8500_impedances.jl's",
    )
    println(
        io,
        "# reshape_near_zero_mv_edges! (phase-25 gap-closure, 2026-08-21) — see",
    )
    println(
        io,
        "# .planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md item 1 and",
    )
    println(
        io,
        "# 25-DATA-PROVENANCE.md for the full before/after record.",
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

    # --- MV: Lines.dss + LineCodes2.DSS ---
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
    mv_codes = sort!(unique(r.linecode for r in linecode_recs))
    mv_linecode_rx = Dict(code => parse_linecode_rx_by_name(linecodes2_text, code) for code in mv_codes)
    mv_edges_raw = ImpedanceEdge[]
    for r in linecode_recs
        R1, X1 = mv_linecode_rx[r.linecode]
        push!(mv_edges_raw, ImpedanceEdge(r.bus1_base, r.bus2_base, R1 * r.length_km, X1 * r.length_km))
    end
    append!(mv_edges_raw, inline_recs)
    reshape_near_zero_mv_edges!(mv_edges_raw)
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

    # --- Service transformers: LoadXfmrCodes.dss (9 codes + 1,177 instances) ---
    xfmr_codes = parse_xfmr_codes(loadxfmrcodes_text)
    length(xfmr_codes) == 9 ||
        throw(ArgumentError("expected exactly 9 XfmrCode definitions, got $(length(xfmr_codes))"))
    xfmr_instances = parse_xfmr_instances(loadxfmrcodes_text)
    length(xfmr_instances) == 1177 || throw(
        ArgumentError(
            "expected exactly 1177 service-transformer instances, got $(length(xfmr_instances))",
        ),
    )
    xfmr_edges = build_xfmr_edges(xfmr_instances, xfmr_codes)

    # --- Regulators + substation transformer + switch ties (D-13, near-ideal, no real Z here) ---
    reg_pairs = vcat(
        parse_transformer_bus_pairs(regulators_text),
        parse_transformer_bus_pairs(transformers_text),
    )
    reg_edges = build_regulator_edges(reg_pairs, switch_pairs)

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

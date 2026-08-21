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
# Regulator/switch segments (voltage regulators + the substation transformer + `switch=y` tie
# segments in Lines.dss) carry NO real impedance value in the emitted table — they get the SAME
# near-ideal low-impedance treatment as `IEEE123_SWITCH_R`/`IEEE123_SWITCH_X` at fixture-build time
# (D-13, Assumption A2 analog); tap changing is not modeled.
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
    parse_mv_lines(text) -> (Vector{MVLinecodeRef}, Vector{ImpedanceEdge}, Vector{Tuple{String,String}})

Line-by-line (never a single big cross-field regex, so field ORDER in the source text does not
matter) parse of every `New Line.*` statement in the vendored `Lines.dss` text, dispatched into
three buckets:
  1. `switch=y` tie segments (43 confirmed) — bus pair only, no impedance parsed (D-13: these get
     the SAME near-ideal treatment as regulators, assigned by the caller).
  2. `Linecode=<name>` references (2,473 confirmed) — deferred Ω lookup, returned as
     `MVLinecodeRef`.
  3. Inline `r1=`/`x1=` records (`HVMV_Sub_connector` + the 9 raw `CAP_*` capacitor-connector
     jumpers, 3 confirmed collision groups of 3 each) — real Ω computed directly here as
     `ImpedanceEdge`.
Throws loudly if any `New Line.*` statement matches none of the three shapes (never silently
drops a record).
"""
function parse_mv_lines(text::AbstractString)
    linecode_recs = MVLinecodeRef[]
    inline_recs = ImpedanceEdge[]
    switch_pairs = Tuple{String, String}[]
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
            push!(switch_pairs, (b1, b2))
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
    expected = length(linecode_recs) + length(inline_recs) + length(switch_pairs)
    expected == total_seen || throw(
        ArgumentError(
            "internal consistency check failed: saw $total_seen New Line.* statements but only " *
            "classified $expected (linecode=$(length(linecode_recs)), inline=$(length(inline_recs)), " *
            "switch=$(length(switch_pairs)))",
        ),
    )
    return linecode_recs, inline_recs, switch_pairs
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


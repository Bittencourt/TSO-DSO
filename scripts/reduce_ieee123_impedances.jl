# scripts/reduce_ieee123_impedances.jl — dependency-free (Base + stdlib regex only)
#
# Parses the two vendored, offline OpenDSS IEEE-123 source files
# (`scripts/data/IEEE123Master.dss` + `scripts/data/IEEELineCodes.DSS`, fetched 2026-07-25),
# reduces each 3-phase/2-phase/1-phase line-code impedance matrix to a positive-sequence
# R1/X1 pair via Fortescue-averaging, and (in default mode) emits a committed Julia source
# file at `src/data/ieee123_impedances.jl` with per-segment series impedance in Ohms, keyed
# by the EXISTING `IEEE123_EDGES` terminal pairs already in `src/data/ieee123.jl` — topology
# is read as plain text and never re-derived (IMPED-01/IMPED-02).
#
# Zero package dependencies (no `using` statements anywhere in this file): the parser is
# Base + stdlib PCRE regex only, so `Project.toml [deps]` is untouched by this script.
#
# Run:
#     julia scripts/reduce_ieee123_impedances.jl            # regenerate the table
#     julia scripts/reduce_ieee123_impedances.jl --verify   # self-check only, no file write

const SCRIPT_DIR = @__DIR__
const MASTER_DSS = joinpath(SCRIPT_DIR, "data", "IEEE123Master.dss")
const LINECODES_DSS = joinpath(SCRIPT_DIR, "data", "IEEELineCodes.DSS")
const IEEE123_JL = joinpath(SCRIPT_DIR, "..", "src", "data", "ieee123.jl")
const OUT_FILE = joinpath(SCRIPT_DIR, "..", "src", "data", "ieee123_impedances.jl")

# Pinned sanity value (RESEARCH.md "Architecture Patterns > Pattern 2", independently
# re-derived from the live upstream file content this research session).
const LINECODE1_R1_EXPECTED = 0.057967
const LINECODE1_X1_EXPECTED = 0.118756
const SANITY_ATOL = 1.0e-5

# ─────────────────────────────────────────────────────────────────────────────────────────
# Step 1: parse "New Line.*" statements out of the vendored master file
# ─────────────────────────────────────────────────────────────────────────────────────────

"""
    LineRecord

One parsed `New Line.*` statement: the (phase-stripped, "r"-regulator-suffix-stripped)
terminal pair, the referenced `LineCode=` number, and the segment `Length=` value.
"""
struct LineRecord
    name::String
    bus1::Int
    bus2::Int
    linecode::Int
    length::Float64
end

"""
    parse_terminal(tok) -> Int

Extract the leading integer terminal number out of a raw OpenDSS bus token. Handles the
plain case (`"149"` -> 149), the phase-suffix case already stripped by the caller's regex,
AND the internal regulator-secondary-node suffix (`"9r"` -> 9, `"25r"` -> 25, `"160r"` -> 160)
that appears on a handful of `Bus1=` fields feeding regulators — the existing, already-
collapsed `IEEE123_EDGES` fixture keys on the bare terminal number, not the regulator-node
alias, so this normalization is required for the (p, c) lookup in Step 3 to succeed at all
(RESEARCH Pitfall 3: the fixture already collapses these internal regulator nodes).
"""
function parse_terminal(tok::AbstractString)
    m = match(r"^(\d+)", tok)
    m === nothing &&
        throw(ArgumentError("could not parse a leading terminal number out of bus token \"$tok\""))
    return parse(Int, m.captures[1])
end

"""
    parse_line_records(master_text) -> Vector{LineRecord}

Regex-parse every `New Line.<name> ... Bus1=... Bus2=... LineCode=... Length=...` statement
in the vendored master file text (verified pattern, RESEARCH.md "Code Examples"). Statements
without a `LineCode=` field (the `New Line.Sw1`..`Sw8` switch/tie definitions, which specify
`r1=`/`x1=` directly instead) simply do not match and are silently excluded — exactly the
switch/regulator segments this reduction must not touch (Common Pitfall 3, Assumption A2).
The regex intentionally has no dotall flag, so `.` never crosses a newline: each match stays
confined to its own single-line statement.
"""
function parse_line_records(master_text::AbstractString)
    line_re = r"New\s+Line\.(\S+)\s+.*?Bus1=(\S+?)(?:\.\S+)?\s+Bus2=(\S+?)(?:\.\S+)?\s+LineCode=(\d+)\s+Length=([\d.]+)"i
    records = LineRecord[]
    for m in eachmatch(line_re, master_text)
        name = String(m.captures[1])
        bus1 = parse_terminal(m.captures[2])
        bus2 = parse_terminal(m.captures[3])
        linecode = parse(Int, m.captures[4])
        len = parse(Float64, m.captures[5])
        push!(records, LineRecord(name, bus1, bus2, linecode, len))
    end
    return records
end

"""
    referenced_linecodes(records) -> Vector{Int}

The SET of distinct `LineCode=` values actually referenced by `New Line.*` statements,
sorted ascending. Only these must ever be parsed out of the shared `IEEELineCodes.DSS`
file — never the full 29 (Common Pitfall 2: that file bundles line codes for four
different IEEE test feeders; 17 of the 29 belong to the 13/34/4-node cases, not this one).
"""
function referenced_linecodes(records::Vector{LineRecord})
    return sort!(unique(r.linecode for r in records))
end

# ─────────────────────────────────────────────────────────────────────────────────────────
# Step 2: parse the referenced linecode rmatrix/xmatrix blocks + Fortescue-reduce them
# ─────────────────────────────────────────────────────────────────────────────────────────

"""
    parse_lower_triangular(s) -> Matrix{Float64}

Parse an OpenDSS pipe-delimited LOWER-TRIANGULAR matrix literal (e.g.
`"0.086666667 | 0.029545455 0.088371212 | 0.02907197 0.029924242 0.087405303"`) into a
full symmetric `n×n` matrix. Row `i` (1-indexed) must contain exactly `i` values
(`(i,1),...,(i,i)`); throws loudly on any row with the wrong element count instead of
silently mis-shaping the matrix.
"""
function parse_lower_triangular(s::AbstractString)
    rows = split(s, '|')
    n = length(rows)
    mat = zeros(Float64, n, n)
    for (i, row) in enumerate(rows)
        vals = parse.(Float64, split(strip(row)))
        length(vals) == i || throw(
            ArgumentError(
                "malformed lower-triangular matrix row $i (expected $i value(s), got " *
                "$(length(vals))): \"$row\"",
            ),
        )
        for (j, v) in enumerate(vals)
            mat[i, j] = v
            mat[j, i] = v
        end
    end
    return mat
end

"""
    fortescue_reduce(mat) -> Float64

Positive-sequence Fortescue-averaging reduction of an `n×n` (n=1,2,3) symmetric line-code
impedance matrix: `R1 = mean(diag) - mean(offdiag)` (identically for X1, given the xmatrix).
For `n == 1` there is no off-diagonal at all — short-circuits directly to `mat[1,1]`, no
reduction needed for a single-phase linecode (RESEARCH.md "Architecture Patterns > Pattern 2").
"""
function fortescue_reduce(mat::AbstractMatrix{<:Real})
    n = size(mat, 1)
    size(mat, 2) == n ||
        throw(ArgumentError("fortescue_reduce requires a square matrix, got size $(size(mat))"))
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
    parse_linecode_rx(linecodes_text, n) -> (R1, X1)

Extract and Fortescue-reduce the `rmatrix=`/`xmatrix=` block for `New linecode.<n>` out of
the vendored `IEEELineCodes.DSS` text. The block regex requires a `[...]`-bracketed matrix
literal immediately after `rmatrix =`/`xmatrix =` — this alone is sufficient to skip the
file's own disabled `!!!~ rmatrix = (...)` comment lines (which use parens, not brackets),
with no separate comment-stripping pass needed. Throws loudly if linecode `n`'s block, or
either matrix inside it, cannot be found.
"""
function parse_linecode_rx(linecodes_text::AbstractString, n::Integer)
    block_re = Regex(
        "New\\s+linecode\\.$(n)\\b.*?~\\s*rmatrix\\s*=\\s*\\[([^\\]]+)\\]" *
        ".*?~\\s*xmatrix\\s*=\\s*\\[([^\\]]+)\\]",
        "is",
    )
    m = match(block_re, linecodes_text)
    m === nothing && throw(
        ArgumentError("could not find an rmatrix/xmatrix block for linecode.$(n) in $(LINECODES_DSS)"),
    )
    rmat = parse_lower_triangular(m.captures[1])
    xmat = parse_lower_triangular(m.captures[2])
    return (fortescue_reduce(rmat), fortescue_reduce(xmat))
end

"""
    parse_all_linecodes(linecodes_text, codes) -> Dict{Int, Tuple{Float64,Float64}}

Parse+reduce ONLY the given `codes` (the 12 linecodes actually referenced by
`IEEE123Master.dss`), never the other 17 defined in the shared file.
"""
function parse_all_linecodes(linecodes_text::AbstractString, codes::Vector{Int})
    d = Dict{Int, Tuple{Float64, Float64}}()
    for n in codes
        d[n] = parse_linecode_rx(linecodes_text, n)
    end
    return d
end

# ─────────────────────────────────────────────────────────────────────────────────────────
# Step 3: (default mode only) look up each existing IEEE123_EDGES tuple and emit Ω values
# ─────────────────────────────────────────────────────────────────────────────────────────

"""
    parse_edges(ieee123_text) -> Vector{Tuple{Int,Int}}

Regex-extract the `IEEE123_EDGES` tuple list literally out of `src/data/ieee123.jl`'s TEXT
(never `using TSODSO`, never a duplicate hardcoded copy — RESEARCH.md interfaces contract).
"""
function parse_edges(ieee123_text::AbstractString)
    m = match(Regex("const\\s+IEEE123_EDGES\\s*=\\s*\\[(.*?)\\]", "s"), ieee123_text)
    m === nothing && throw(ArgumentError("could not find `const IEEE123_EDGES = [...]` in $(IEEE123_JL)"))
    tup_re = r"\((\d+),\s*(\d+)\)"
    return Tuple{Int, Int}[(parse(Int, tm.captures[1]), parse(Int, tm.captures[2])) for tm in eachmatch(tup_re, m.captures[1])]
end

"""
    parse_switch_edges(ieee123_text) -> Set{Tuple{Int,Int}}

Regex-extract the `IEEE123_SWITCH_EDGES` set literally out of `src/data/ieee123.jl`'s TEXT —
these 5 near-ideal switch/regulator segments are excluded from the real-impedance lookup
entirely (Assumption A2: they keep their existing near-ideal synthetic value).
"""
function parse_switch_edges(ieee123_text::AbstractString)
    m = match(Regex("const\\s+IEEE123_SWITCH_EDGES\\s*=\\s*Set\\(\\[(.*?)\\]\\)", "s"), ieee123_text)
    m === nothing &&
        throw(ArgumentError("could not find `const IEEE123_SWITCH_EDGES = Set([...])` in $(IEEE123_JL)"))
    tup_re = r"\((\d+),\s*(\d+)\)"
    return Set{Tuple{Int, Int}}((parse(Int, tm.captures[1]), parse(Int, tm.captures[2])) for tm in eachmatch(tup_re, m.captures[1]))
end

"""
    find_line_record(records, p, c) -> LineRecord

Look up the `New Line.*` record matching edge `(p, c)` in EITHER bus order (the raw file's
own listing order does not always match `IEEE123_EDGES`'s (parent, child) order). Throws
loudly on a lookup miss rather than silently defaulting (Common Pitfall 3's explicit warning
sign: "a lookup failure ... must throw loudly at script run time").
"""
function find_line_record(records::Vector{LineRecord}, p::Int, c::Int)
    for r in records
        ((r.bus1 == p && r.bus2 == c) || (r.bus1 == c && r.bus2 == p)) && return r
    end
    throw(ArgumentError("no New Line.* record found for edge ($p, $c) in either bus order — check $(MASTER_DSS)"))
end

"""
    build_branch_rx_ohms(edges, switch_edges, records, linecodes)
        -> (Dict{Tuple{Int,Int},Tuple{Float64,Float64}}, Dict{Tuple{Int,Int},Tuple{Int,Float64}})

For every `edges` tuple NOT in `switch_edges`, look up its raw line record, compute
`z_Ω = R1 × Length` / `x_Ω = X1 × Length` with NO length-unit conversion factor (OpenDSS's
own no-op default when `Units=` is unset anywhere in the file chain — Common Pitfall 1), and
return both the Ω table and a linecode/length metadata table (for the emitted comment).
"""
function build_branch_rx_ohms(
    edges::Vector{Tuple{Int, Int}},
    switch_edges::Set{Tuple{Int, Int}},
    records::Vector{LineRecord},
    linecodes::Dict{Int, Tuple{Float64, Float64}},
)
    rx = Dict{Tuple{Int, Int}, Tuple{Float64, Float64}}()
    meta = Dict{Tuple{Int, Int}, Tuple{Int, Float64}}()
    for (p, c) in edges
        (p, c) in switch_edges && continue
        rec = find_line_record(records, p, c)
        haskey(linecodes, rec.linecode) || throw(
            ArgumentError(
                "edge ($p, $c) references linecode.$(rec.linecode), which is outside the parsed " *
                "12-code set — the referenced-linecode-set tripwire should have caught this",
            ),
        )
        R1, X1 = linecodes[rec.linecode]
        rx[(p, c)] = (R1 * rec.length, X1 * rec.length)
        meta[(p, c)] = (rec.linecode, rec.length)
    end
    return rx, meta
end

"""
    emit_output(rx, meta, outfile) -> String

Write a committed Julia source file declaring `const IEEE123_BRANCH_RX_OHMS` (per-segment
series impedance in Ohms, keyed by the original IEEE-123 terminal pairs), matching the
provenance-comment convention documented in 17-PATTERNS.md. Returns the path written.
"""
function emit_output(
    rx::Dict{Tuple{Int, Int}, Tuple{Float64, Float64}},
    meta::Dict{Tuple{Int, Int}, Tuple{Int, Float64}},
    outfile::AbstractString,
)
    io = IOBuffer()
    println(io, "# src/data/ieee123_impedances.jl")
    println(io, "#")
    println(io, "# GENERATED by scripts/reduce_ieee123_impedances.jl — DO NOT hand-edit; re-run the")
    println(io, "# script and re-commit if the upstream .dss files change.")
    println(io, "#")
    println(io, "# Source: raw.githubusercontent.com/tshort/OpenDSS/master/Distrib/IEEETestCases/123Bus/")
    println(io, "#         IEEE123Master.dss + IEEELineCodes.DSS, fetched 2026-07-25 (vendored copies")
    println(io, "#         committed at scripts/data/, exact case IEEELineCodes.DSS required).")
    println(io, "#")
    println(io, "# Values are per-segment SERIES IMPEDANCE IN OHMS (positive-sequence, Fortescue-averaged")
    println(io, "# from each linecode's rmatrix/xmatrix), NOT per-unit. Converted once at ingestion in")
    println(io, "# ieee123_modified() via to_pu_impedance (src/units/PerUnit.jl:53).")
    println(io, "#")
    println(io, "# Keyed by ORIGINAL IEEE-123 terminal pairs (pre-relabel), matching IEEE123_EDGES exactly")
    println(io, "# (src/data/ieee123.jl). NO length-unit conversion applied (OpenDSS Units= unspecified")
    println(io, "# means no-op) — do NOT introduce a feet/miles/kft scale factor here.")
    println(io, "const IEEE123_BRANCH_RX_OHMS = Dict{Tuple{Int,Int}, Tuple{Float64,Float64}}(")
    for key in sort!(collect(keys(rx)))
        r_Ω, x_Ω = rx[key]
        lc, len = meta[key]
        println(io, "    ($(key[1]), $(key[2])) => ($(r_Ω), $(x_Ω)),   # LineCode=$(lc), Length=$(len)")
    end
    println(io, ")")
    write(outfile, String(take!(io)))
    return outfile
end

# ─────────────────────────────────────────────────────────────────────────────────────────
# CLI entry points
# ─────────────────────────────────────────────────────────────────────────────────────────

"""
    verify() -> nothing

Self-check mode (`--verify`): runs the full parse+reduce (Steps 1-2 only — no
`src/data/ieee123.jl` edge lookup, no file write) and throws loudly on either tripwire:
exactly 12 linecodes ingested, and linecode.1's reduced `(R1, X1)` matching the pinned
sanity pair within `atol = 1e-5`.
"""
function verify()
    master_text = read(MASTER_DSS, String)
    linecodes_text = read(LINECODES_DSS, String)

    records = parse_line_records(master_text)
    codes = referenced_linecodes(records)
    length(codes) == 12 || throw(
        ArgumentError(
            "expected exactly 12 distinct linecodes referenced by New Line.* in $(MASTER_DSS), " *
            "got $(length(codes)): $(codes)",
        ),
    )

    linecodes = parse_all_linecodes(linecodes_text, codes)
    length(linecodes) == 12 ||
        throw(ArgumentError("expected exactly 12 parsed linecodes, got $(length(linecodes))"))

    R1, X1 = linecodes[1]
    isapprox(R1, LINECODE1_R1_EXPECTED; atol = SANITY_ATOL) || throw(
        ArgumentError(
            "linecode.1 R1 sanity check failed: got $R1, expected ≈$(LINECODE1_R1_EXPECTED) " *
            "(atol=$(SANITY_ATOL))",
        ),
    )
    isapprox(X1, LINECODE1_X1_EXPECTED; atol = SANITY_ATOL) || throw(
        ArgumentError(
            "linecode.1 X1 sanity check failed: got $X1, expected ≈$(LINECODE1_X1_EXPECTED) " *
            "(atol=$(SANITY_ATOL))",
        ),
    )

    println(
        "PASS: 12 linecodes ingested; linecode.1 R1=$(R1), X1=$(X1) " *
        "(pinned ≈$(LINECODE1_R1_EXPECTED)/≈$(LINECODE1_X1_EXPECTED))",
    )
    return nothing
end

"""
    main() -> nothing

Default (non-`--verify`) mode: full parse+reduce, THEN read `src/data/ieee123.jl` as plain
text to extract `IEEE123_EDGES`/`IEEE123_SWITCH_EDGES`, look up each non-switch edge's real
segment impedance, and emit the committed `src/data/ieee123_impedances.jl` const table.
"""
function main()
    if ARGS == ["--verify"]
        verify()
        return nothing
    end

    master_text = read(MASTER_DSS, String)
    linecodes_text = read(LINECODES_DSS, String)

    records = parse_line_records(master_text)
    codes = referenced_linecodes(records)
    length(codes) == 12 || throw(
        ArgumentError(
            "expected exactly 12 distinct linecodes referenced by New Line.* in $(MASTER_DSS), " *
            "got $(length(codes)): $(codes)",
        ),
    )
    linecodes = parse_all_linecodes(linecodes_text, codes)

    ieee123_text = read(IEEE123_JL, String)
    edges = parse_edges(ieee123_text)
    switch_edges = parse_switch_edges(ieee123_text)

    rx, meta = build_branch_rx_ohms(edges, switch_edges, records, linecodes)
    outfile = emit_output(rx, meta, OUT_FILE)
    println("Wrote $(length(rx)) branch impedances (of $(length(edges)) total edges, " *
            "$(length(switch_edges)) switch edges excluded) to $(outfile)")
    return nothing
end

main()

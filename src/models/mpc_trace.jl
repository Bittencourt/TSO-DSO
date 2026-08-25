# src/models/mpc_trace.jl
#
# SEAM: MpcTrace — the rolling-horizon price-consistency ledger (MPC-03).
# OWNER: plan 21-02.
#
# A pure data / bookkeeping type — NO JuMP, NO solves — mirroring `AdmmResiduals`
# (`src/admm/residuals.jl`) so both the rolling-horizon orchestrator (Wave 3/4's `mpc_loop.jl`)
# and a future CairoMakie plotting extension or the literate rung page can consume it WITHOUT
# pulling JuMP or a solver.
#
# WHAT IT RECORDS (D-09 / D-10, MPC-03's "step-to-step price jumps, cumulative deviation"
# requirement):
#
#     dadp[k]        the published real-time DADP at rolling step k
#     dadp_da[k]     the day-ahead reference DADP at the SAME absolute hour
#     jump[k]        = |dadp[k] − dadp[k−1]|            (step-to-step price jump, 0.0 at k=1)
#     cum_deviation[k] = cum_deviation[k−1] + |dadp[k] − dadp_da[k]|  (cumulative deviation from
#                        the day-ahead path)
#     cert_status[k] a Symbol tagging the step's certificate/fallback outcome
#                     (`:certified_convex_dual`, `:certified_convex_dual_restricted` — the
#                     restricted-tier rescue's OWN provenance, WR-04 — `:local_ac_dual`,
#                     `:cert_failed`, per D-04's fallback ladder — only the literal
#                     `:cert_failed` symbol counts as a genuine failure for
#                     `any_cert_failed`)
#
# so a caller can drive price-consistency diagnostics (`max_jump`, `mean_jump`,
# `any_cert_failed`) without re-deriving the deviation bookkeeping at every call site.

"""
    MpcTrace

A mutable, JuMP-free ledger of a rolling-horizon MPC run's per-step published DADP,
step-to-step price jump, cumulative deviation from the day-ahead DADP path, and per-step
certificate/fallback status (MPC-03).

Fields:

  - `dadp_trace::Vector{Float64}` — the published real-time DADP per recorded step.
  - `dadp_da_trace::Vector{Float64}` — the day-ahead reference DADP at that SAME absolute hour,
    recorded alongside for the cumulative-deviation computation and so a caller can reconstruct
    the raw deviation series.
  - `jump_trace::Vector{Float64}` — the step-to-step price jump `|dadp[k] − dadp[k−1]|`; the
    first recorded step has no predecessor so its jump is `0.0`.
  - `cum_deviation_trace::Vector{Float64}` — the running cumulative deviation
    `Σ |dadp[k] − dadp_da[k]|` from the day-ahead DADP path.
  - `cert_status_trace::Vector{Symbol}` — the certificate/fallback outcome tag recorded at each
    step (D-04's ladder: `:certified_convex_dual`, `:certified_convex_dual_restricted` — the
    restricted-tier rescue, WR-04 — `:local_ac_dual`, `:cert_failed`).
  - `steps::Int` — the number of recorded steps (`== length(dadp_trace) == …`).

All five traces are kept EQUAL LENGTH (`== steps`). Construct empty via
[`MpcTrace()`](@ref); append one step with [`record!`](@ref); query price-consistency via
[`max_jump`](@ref), [`mean_jump`](@ref), [`any_cert_failed`](@ref).
"""
mutable struct MpcTrace
    dadp_trace::Vector{Float64}
    dadp_da_trace::Vector{Float64}
    jump_trace::Vector{Float64}
    cum_deviation_trace::Vector{Float64}
    cert_status_trace::Vector{Symbol}
    steps::Int
end

"""
    MpcTrace() -> MpcTrace

Construct an EMPTY price-consistency ledger: every trace vector empty and `steps == 0`.
Records are appended via [`record!`](@ref).
"""
MpcTrace() = MpcTrace(Float64[], Float64[], Float64[], Float64[], Symbol[], 0)

# --- internal: the shared sequential-k fail-loud guard (project throw-on-misuse convention,
# reimplemented here — never imported from `admm/residuals.jl`, this file stays file-disjoint
# per the project's established seam convention) ---
@inline function _assert_sequential(trace::MpcTrace, k::Integer)
    expected = trace.steps + 1
    k == expected ||
        throw(ArgumentError("record!: expected sequential step $expected, got k=$k"))
    return nothing
end

"""
    record!(trace::MpcTrace, k::Integer, dadp::Real, dadp_da::Real, cert_status::Symbol) -> MpcTrace

Append step `k`'s published real-time DADP `dadp`, the day-ahead reference DADP `dadp_da` at
the same absolute hour, and the certificate/fallback outcome `cert_status`, deriving and
recording the step-to-step price jump and running cumulative deviation. `k` must be the next
sequential step (`trace.steps + 1`) — a fail-loud guard against a double-record or a skipped
step, mirroring `AdmmResiduals`'s own `record!` guard exactly. Returns `trace`.
"""
function record!(
    trace::MpcTrace,
    k::Integer,
    dadp::Real,
    dadp_da::Real,
    cert_status::Symbol,
)
    _assert_sequential(trace, k)
    jump = trace.steps == 0 ? 0.0 : abs(float(dadp) - last(trace.dadp_trace))
    cum =
        (trace.steps == 0 ? 0.0 : last(trace.cum_deviation_trace)) +
        abs(float(dadp) - float(dadp_da))
    push!(trace.dadp_trace, float(dadp))
    push!(trace.dadp_da_trace, float(dadp_da))
    push!(trace.jump_trace, jump)
    push!(trace.cum_deviation_trace, cum)
    push!(trace.cert_status_trace, cert_status)
    trace.steps += 1
    return trace
end

"""
    max_jump(trace::MpcTrace) -> Float64

The maximum recorded step-to-step price jump. Returns `0.0` on an empty ledger (never
`NaN`/error).
"""
max_jump(trace::MpcTrace) = trace.steps == 0 ? 0.0 : maximum(trace.jump_trace)

"""
    mean_jump(trace::MpcTrace) -> Float64

The mean recorded step-to-step price jump. Returns `0.0` on an empty ledger (never
`NaN`/error).
"""
mean_jump(trace::MpcTrace) = trace.steps == 0 ? 0.0 : sum(trace.jump_trace) / trace.steps

"""
    any_cert_failed(trace::MpcTrace) -> Bool

`true` iff any recorded step's certificate/fallback status is the literal `:cert_failed`
symbol. Returns `false` on an empty ledger. Only `:cert_failed` counts as a failure —
`:certified_convex_dual_restricted` (the restricted-tier rescue, WR-04) and `:local_ac_dual`
are SUCCESSFUL escalations (D-04's ladder semantics), not failures.
"""
any_cert_failed(trace::MpcTrace) =
    trace.steps == 0 ? false : any(==(:cert_failed), trace.cert_status_trace)

export MpcTrace, record!, max_jump, mean_jump, any_cert_failed

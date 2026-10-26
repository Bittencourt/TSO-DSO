# scripts/lib/case_a_common.jl
#
# Shared Phase-42 "case-a-magnitude" helpers — a plain-Julia include-able lib (NO DrWatson,
# NO TSODSO dependency): both the measurement runner (plans 42-03/42-04,
# `scripts/case_a_magnitude.jl`) and the structural test file (`test/test_case_a_magnitude.jl`)
# `include` this file directly.
#
# Honesty-policy framing: the functions here make Phase 42's pre-registration STRUCTURALLY
# enforceable rather than aspirational (42-CASE-A-PROTOCOL.md, committed BEFORE any Case A
# run). `assert_protocol_registered` is the fail-loud gate every Case A measurement main
# calls before building or solving anything: no protocol file, no run; an uncommitted
# protocol, no run. `welfare_gain` is the ONE registered gain definition — the SIGN-SAFE
# form `100·(W_DADP − W_FIT)/|W_FIT|` (protocol §1); the naive ratio `W_DADP/W_FIT` is
# banned (it sign-inverts on negative welfare — welfare is ≈ −3.78e5 at 784 houses) and NO
# ratio method exists here. `provenance_row`/`flatten_note` stamp every CSV row so each row
# is auditable to its measurement environment, and every row carries the `protocol_sha`
# returned by the guard so post-hoc protocol edits are visible in every artifact.

using LinearAlgebra: BLAS

# The CONTEXT-locked protocol path. The repo root is derived from @__DIR__ walking up two
# levels (this file lives in <root>/scripts/lib/) — NOT projectdir() — so the lib works
# identically from the test env and from the script env.
const PROTOCOL_PATH = joinpath(
    dirname(dirname(@__DIR__)),
    ".planning",
    "phases",
    "42-thesis-case-a-magnitude",
    "42-CASE-A-PROTOCOL.md",
)

"""
    welfare_gain(w_dadp::Real, w_fit::Real) -> NamedTuple

The REGISTERED Case A welfare-gain definition (42-CASE-A-PROTOCOL.md §1; the
`scripts/thesis_case123_repro.jl` sign-safe form): returns
`(Δ = w_dadp - w_fit, Δpct = 100 * (w_dadp - w_fit) / abs(w_fit))`.

The denominator is `abs(w_fit)` so the sign of `Δpct` always equals the sign of `ΔW` —
including when welfare is negative (it is, at the 784-house population: ≈ −3.78e5). The
naive ratio `w_dadp / w_fit` is NEVER computed or reported: on negative welfare it
SIGN-INVERTS (a DADP welfare loss reads as a gain > 1). Banned by the PROJECT.md Key
Decision and protocol §1.
"""
welfare_gain(w_dadp::Real, w_fit::Real) =
    (Δ = w_dadp - w_fit, Δpct = 100 * (w_dadp - w_fit) / abs(w_fit))

"""
    protocol_sha(path::AbstractString = PROTOCOL_PATH) -> String

The full 40-hex SHA of the latest commit touching `path`, via
`git -C <dir of path> log -1 --format=%H -- <path>`. Returns `""` when the file has no git
history (never committed, or the repo has no commits at all). Never throws on the
"no history" condition — an empty SHA is the honest answer, and
[`assert_protocol_registered`](@ref) is what turns it into a loud failure.
"""
function protocol_sha(path::AbstractString = PROTOCOL_PATH)
    isfile(path) || return ""
    sha = try
        readchomp(`git -C $(dirname(path)) log -1 --format=%H -- $(path)`)
    catch
        return ""
    end
    # readchomp returns a SubString{String} (chomp keeps the parent buffer); the contract —
    # and every later CSV row's protocol_sha stamp — is a plain String.
    return String(sha)
end

"""
    assert_protocol_registered(path::AbstractString = PROTOCOL_PATH) -> String

The pre-registration gate (42-CASE-A-PROTOCOL.md; every Case A measurement main calls this
BEFORE building or solving anything). Errors — fail-loud, message names the
"PRE-REGISTRATION VIOLATION" — when the protocol file is missing, or when it exists but is
NOT committed (no git history ⇒ empty SHA: an uncommitted protocol is no pre-registration).
Returns the full 40-hex protocol SHA otherwise (later plans stamp it into every CSV row, so
any post-hoc protocol edit is visible in every artifact — the tampering mitigation
T-42-01-1/T-42-01-2).
"""
function assert_protocol_registered(path::AbstractString = PROTOCOL_PATH)
    isfile(path) || error(
        "case_a_magnitude: PRE-REGISTRATION VIOLATION — protocol file missing at " *
        "$path. Write and commit 42-CASE-A-PROTOCOL.md BEFORE any Case A run.",
    )
    sha = protocol_sha(path)
    isempty(sha) && error(
        "case_a_magnitude: PRE-REGISTRATION VIOLATION — protocol exists at $path but is " *
        "NOT committed (no git history). Commit it in its own commit before running.",
    )
    return sha
end

"""
    provenance_row(T_H::Int, seed::Int) -> NamedTuple

The provenance stamp merged into every measurement row (`scripts/tariff_comparison.jl`
verbatim shape): julia_version / threads / blas_threads / seed / t_horizon. Runners pin
`BLAS.set_num_threads(1)` at main start so the stamped value is row-to-row comparable.
"""
provenance_row(T_H::Int, seed::Int) = (
    julia_version = string(VERSION),
    threads = Threads.nthreads(),
    blas_threads = BLAS.get_num_threads(),
    seed = seed,
    t_horizon = T_H,
)

"""
    flatten_note(s) -> String

Committed-CSV note hygiene (`scripts/tariff_comparison.jl` verbatim): the status `notes`
carry solver messages that legitimately contain newlines, but the artifact CSVs are
LINE-ORIENTED by repo convention — embedded newlines are flattened to "; " and double
quotes to single; the message CONTENT is preserved verbatim otherwise.
"""
flatten_note(s) = replace(replace(String(s), '\n' => "; ", '\r' => ""), '"' => "'")

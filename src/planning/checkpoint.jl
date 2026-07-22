# src/planning/checkpoint.jl
#
# SEAM: per-iteration checkpoint save/resume primitive (D-10).
# OWNER: plan 10-01.
#
# `checkpoint_iteration!`/`resume_from_checkpoint` persist and reload the Benders (future,
# Phase 11) outer-loop iteration state. Reuses the project's already-established
# `@tagsave` (DrWatson) provenance-stamped JLD2 idiom verbatim from
# `src/experiments/store.jl`'s `run_and_store` — including the `gitpath = pkgdir(@__MODULE__)`
# fix that makes `:gitcommit` stamp correctly even when `Pkg.test()` runs from a sandboxed
# working directory, and `safe = true` (routes through `safesave`, never silently overwrites
# a prior checkpoint — T-10-02).
#
# Per D-10: `resume_from_checkpoint` ALWAYS reports the HIGHEST-numbered checkpoint file as
# the one to redo, never "trust-complete" — the (future) Benders loop caller is responsible
# for redoing that iteration in full. This primitive deliberately has NO "skip if already the
# highest" shortcut.

using DrWatson: @tagsave, datadir, wload

"""
    checkpoint_iteration!(state, iter::Int; dir::AbstractString = datadir("planning_checkpoints")) -> String

Persist `iter` and `state` to a JLD2 file under `dir` (created if it does not exist) via
`@tagsave`, mirroring `src/experiments/store.jl`'s `run_and_store` idiom verbatim
(`storepatch = true`, `gitpath = pkgdir(@__MODULE__)`, `safe = true`). Returns the path
written. The file is named `iter_NNNNN.jld2` (5-digit zero-padded, e.g. `iter_00001.jld2`)
so a lexicographic sort of filenames is also numerically correct
([`resume_from_checkpoint`](@ref) relies on this).

`iter` MUST be in `0:99999` — the HARD limit of the 5-digit zero-padded filename
contract — else `ArgumentError` is thrown (WR-03). A negative value would produce a
malformed name (`lpad(-3, 5, '0')` pads the string `"-3"`), and a value > 99999 would
produce `iter_100000.jld2`, which sorts lexicographically BEFORE `iter_99999.jld2` and
would make [`resume_from_checkpoint`](@ref) silently resume from the wrong (lower)
iteration.

`dir` is an EXPLICIT keyword (default `datadir("planning_checkpoints")`) so tests pass
`mktempdir()` and stay hermetic — mirrors `run_and_store`'s discipline.
"""
function checkpoint_iteration!(
    state,
    iter::Int;
    dir::AbstractString = datadir("planning_checkpoints"),
)
    # WR-03: enforce the 5-digit zero-padded filename contract. Outside 0:99999 the name
    # is malformed (negative) or sorts lexicographically BEFORE lower iterations
    # (> 99999), silently breaking resume_from_checkpoint's highest-numbered invariant.
    0 <= iter <= 99999 || throw(
        ArgumentError(
            "iter must be in 0:99999 (5-digit zero-padded filename contract), got $iter",
        ),
    )
    mkpath(dir)
    path = joinpath(dir, "iter_$(lpad(iter, 5, '0')).jld2")
    @tagsave(
        path,
        Dict(:iteration => iter, :state => state);
        storepatch = true,
        gitpath = pkgdir(@__MODULE__),
        safe = true,
    )
    return path
end

"""
    resume_from_checkpoint(dir::AbstractString = datadir("planning_checkpoints"))

Return `nothing` if `dir` contains no CANONICAL `iter_NNNNN.jld2` checkpoint files,
otherwise `wload` the HIGHEST-numbered one (lexicographic sort on the zero-padded
`iter_NNNNN.jld2` name is numerically correct) and return `(; iteration, state)` — a
`NamedTuple` built from the
`wload`ed dict's STRING keys (`"iteration"`, `"state"`; the `wload`/JLD2 round-trip always
returns `Dict{String,Any}`, never `Dict{Symbol,Any}`, regardless of the in-memory key type
`@tagsave` originally received — verified in `test/test_experiments.jl`'s "INFRA-04
provenance tagsave" testitem).

Per D-10, this ALWAYS reports the highest-numbered checkpoint — even if it may be a
possibly-partial write from a crashed iteration — as the one the caller must redo. There is
deliberately NO "skip if already the highest" shortcut: only strictly lower-numbered
checkpoints are ever treated as complete/skippable, and that decision belongs to the
(future) Benders-loop caller, not this primitive.

The scan is RESTRICTED to canonical `iter_NNNNN.jld2` names (CR-02). `safe = true` in
[`checkpoint_iteration!`](@ref) routes through DrWatson's `safesave`, which — on a
re-save of the same iteration (the crash-redo workflow this primitive exists for) —
renames the EXISTING file to `iter_NNNNN_#1.jld2` and writes the NEW data to the
canonical name. Because `'_'` sorts after `'.'`, a naive all-`.jld2` sort put the STALE
backup last and silently resumed the pre-redo state (with multiple redos, the OLDEST).
Backups (`iter_NNNNN_#k.jld2`) and foreign `.jld2` files are therefore EXCLUDED: the
canonical file always holds the freshest save for its iteration.
"""
function resume_from_checkpoint(dir::AbstractString = datadir("planning_checkpoints"))
    isdir(dir) || return nothing
    # CR-02: canonical names ONLY — never DrWatson safesave backups (iter_NNNNN_#k.jld2,
    # which hold STALE pre-redo state yet sort lexicographically AFTER the fresh canonical
    # file), never foreign .jld2 files (which would raise KeyError("iteration")).
    files = sort(
        filter(
            f -> occursin(r"^iter_\d{5}\.jld2$", basename(f)),
            readdir(dir; join = true),
        ),
    )
    isempty(files) && return nothing
    dict = wload(files[end])
    return (; iteration = dict["iteration"], state = dict["state"])
end

export checkpoint_iteration!, resume_from_checkpoint

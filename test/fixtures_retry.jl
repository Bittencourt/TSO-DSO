# test/fixtures_retry.jl
#
# Retry-and-report helper for known intermittent solver failures. A TestItems `@testmodule`
# consumed via `setup=[FlakeRetry]`.
#
# CONTRACT: `with_solve_retry(f)` retries the SOLVE only. `f` must only compute numbers and
# return them; the caller runs its `@test`s on the returned value, outside the retry path.
# Every retry is logged with `@info`, the last error is rethrown once `tries` is exhausted,
# and a grep-able `RETRY SUMMARY` line is printed at process exit.
#
# STATUS: reserved. No production test item uses `with_solve_retry` yet (the flake harness
# measured 20/20 clean runs on the targeted items), so only test/test_flake_retry.jl
# exercises it. Note for a future consumer: the default `retry_on` includes
# `ConvergenceError`; for a deterministic ADMM run a retry repeats the same failure, so pass
# an explicit `retry_on` without it unless the solve is genuinely nondeterministic.

@testmodule FlakeRetry begin
    using TSODSO
    using JuMP: MOI

    const RECORDS = Tuple{String, Int}[]
    const HOOK_REGISTERED = Ref(false)

    """
    Is `e` a failure the helper may retry (typed, numerical, never infeasibility).
    """
    function retryable(e, retry_on)::Bool
        any(T -> e isa T, retry_on) || return false
        e isa TSODSO.SolveFailedError &&
            return e.termination_status in TSODSO.RETRYABLE_STATUSES
        return true
    end

    function status_label(e)::String
        e isa TSODSO.SolveFailedError && return string(e.termination_status)
        return "n/a"
    end

    function print_summary()
        used = filter(r -> r[2] > 1, RECORDS)
        if isempty(used)
            println("RETRY SUMMARY: no retries used ($(length(RECORDS)) guarded solve(s))")
        else
            detail = join(("$(l) x$(a)" for (l, a) in used), "; ")
            @warn "RETRY SUMMARY: $(length(used)) guarded solve(s) needed retries: $detail"
        end
        return nothing
    end

    function register_hook!()
        HOOK_REGISTERED[] && return nothing
        HOOK_REGISTERED[] = true
        atexit(print_summary)
        return nothing
    end

    """
        with_solve_retry(f; tries = 3, label = "solve",
                         retry_on = (SolveFailedError, ConvergenceError)) -> f()'s value
    """
    function with_solve_retry(
        f;
        tries::Int = 3,
        label::AbstractString = "solve",
        retry_on = (TSODSO.SolveFailedError, TSODSO.ConvergenceError),
    )
        register_hook!()
        local attempt = 0
        while true
            attempt += 1
            local result
            local err = nothing
            try
                result = f()
            catch e
                retryable(e, retry_on) ||
                    (push!(RECORDS, (String(label), attempt)); rethrow())
                err = e
            end
            if err === nothing
                push!(RECORDS, (String(label), attempt))
                return result
            end
            if attempt >= tries
                push!(RECORDS, (String(label), attempt))
                throw(err)
            end
            @info "flake retry" label attempt error_type = string(typeof(err)) status =
                status_label(err)
        end
    end

    retry_records() = copy(RECORDS)
    reset_retry_records!() = (empty!(RECORDS); nothing)
end

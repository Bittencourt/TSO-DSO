# src/actors/efficiency.jl
#
# SEAM: efficiency-loss report for a non-welfare actor objective (Phase 44, ACTOR-02).
# `W_opt` is the social-welfare optimum (all actors on `WelfareObjective`, or `ProfitObjective(0)`);
# `W_soc` is the SOCIAL welfare (utilities minus lambda0' p_import) reached under the actor
# objective. By optimality of the welfare problem `W_soc <= W_opt` up to solver noise, so
# `delta_abs >= 0`; a materially negative value is a bug, not a finding.

"""
    actor_efficiency(W_opt, W_soc) -> (; delta_abs, delta_rel)

Efficiency loss of an actor objective: `delta_abs = W_opt - W_soc` and
`delta_rel = delta_abs / abs(W_opt)`. Reports, never throws on sign; throws `ArgumentError` on
non-finite inputs or `W_opt == 0` (relative loss undefined).
"""
function actor_efficiency(W_opt::Real, W_soc::Real)
    (isfinite(W_opt) && isfinite(W_soc)) ||
        throw(ArgumentError("actor_efficiency: inputs must be finite, got $W_opt, $W_soc"))
    W_opt == 0 && throw(ArgumentError("actor_efficiency: W_opt == 0, relative loss undefined"))
    delta_abs = Float64(W_opt) - Float64(W_soc)
    return (; delta_abs, delta_rel = delta_abs / abs(Float64(W_opt)))
end

export actor_efficiency

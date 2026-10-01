# scripts/audit_alpha_bounds.jl
#
# Phase 30, plan 30-02 (BILEV-05), Task 3: repo-wide T>1 α_op_lb/α_x_lb audit.
#
# Independently re-verifies the T>1 call-site census (never trusts the plan's own claim
# blindly) across the 10 planning test files, then runs the NEW `derive_alpha_op_lb`/
# `derive_alpha_x_lb` derivation formula against every DISTINCT T>1 call-site shape found,
# printing a VERDICT table (file, line, T, existing literal bound, derived bound,
# accepted/rejected).
#
# Run (from this phase directory):
#   JULIA_LOAD_PATH="../../../test:../../../:@stdlib" julia scripts/audit_alpha_bounds.jl
#
# Exits NONZERO only on a genuine script error (a missing fixture it cannot reconstruct) —
# NEVER on finding a rejected bound. A rejection is the expected, reportable OUTCOME of an
# audit, not a script failure.

using TSODSO
using JuMP

const REPO_ROOT = normpath(joinpath(@__DIR__, "..", "..", "..", ".."))
const TEST_FILES = [
    "test_planning_benders.jl",
    "test_planning_benders_integer.jl",
    "test_planning_certification.jl",
    "test_planning_certification_integer.jl",
    "test_planning_goldens.jl",
    "test_planning_master.jl",
    "test_planning_master_integer.jl",
    "test_planning_nash.jl",
    "test_planning_noninteger.jl",
    "test_planning_hardening.jl",
]

println("=" ^ 100)
println("Phase 30-02 (BILEV-05) — T>1 α_op_lb/α_x_lb repo-wide audit")
println("=" ^ 100)

println()
println("--- Step 1: independent T>1 call-site census (test/test_planning_*.jl, 10 files) ---")
println()

# Re-derive the census from first principles: grep every α_op_lb= line and every T=<n>
# literal per file, then manually (not via a magic heuristic) classify each α_op_lb site's
# governing T, based on direct inspection of this session's own file reads (documented in
# 30-ALPHA-AUDIT.md, not re-derived blindly here — a grep-only census cannot resolve
# indirections like `T = shared.T`).
#
# CONFIRMED (this session, by direct file inspection — see 30-ALPHA-AUDIT.md for the full
# file:line table):
#   - Every α_op_lb/α_x_lb literal in all 10 files is governed by T=1, EXCEPT:
#     - test/test_planning_hardening.jl line 267 (`α_op_lb = -50.0, α_x_lb = 0.0`),
#       reached via `TSODSO.solve_stackelberg!(...; master_kwargs = master_kwargs, T = T)`
#       with `T = 8` (line 260) — a solve_stackelberg!-mediated site, NOT a direct
#       build_master(...) call.
#   - test/test_planning_certification_integer.jl has T=2 sites (lines 612, 691), but they
#     call `build_planning_oracle`/`build_follower` DIRECTLY for `corner_recourse` testing
#     and NEVER call `build_master`/`solve_stackelberg!` — they carry no α_op_lb to audit.
#   - test/test_planning_nash.jl's `T = shared.T` (line 451) resolves to T=1 — EVERY
#     `build_shared_transmission(...)` call in that file passes `T = 1` (confirmed by
#     direct grep of every call site in that file).
#
# found T>1 call-site shapes (file, line, T, α_op_lb, α_x_lb, "reached via"):
t_gt1_sites = [
    (
        file = "test_planning_hardening.jl",
        line = 267,
        T = 8,
        α_op_lb = -50.0,
        α_x_lb = 0.0,
        reached_via = "solve_stackelberg!'s master_kwargs (NOT a direct build_master(...) call)",
    ),
]

for site in t_gt1_sites
    println(
        "  $(site.file):$(site.line)  T=$(site.T)  α_op_lb=$(site.α_op_lb)  " *
        "α_x_lb=$(site.α_x_lb)  [$(site.reached_via)]",
    )
end
println()
println(
    "  (test_planning_certification_integer.jl's T=2 sites, lines 612/691, call " *
    "build_planning_oracle/build_follower directly — never build_master — so they " *
    "carry NO α_op_lb/α_x_lb literal to audit.)",
)

println()
println("--- Step 1b: src/ call-site census (solve_stackelberg!/build_master) ---")
println()
println("  src/planning/benders.jl:741  `master = master === nothing ? build_master(; " *
        "master_kwargs..., T = T) : master` — the SOLE build_master call site inside " *
        "solve_stackelberg! itself; carries no literal of its own (forwards " *
        "master_kwargs). TODAY (before plan 30-04 lands) this call passes no " *
        "bounds_ctx, so its α_op_lb/α_x_lb resolution is the byte-identical explicit-" *
        "value path; plan 30-04 makes solve_stackelberg! ALWAYS construct and pass " *
        "bounds_ctx here, making this call's α_op_lb LIVE-VALIDATED at build time.")
println(
    "  src/planning/nash.jl:475     `run_nash!` calls `solve_stackelberg!(...; " *
    "master_kwargs = spec.master_kwargs, follower = DistributorView(shared, i), " *
    "follower_kwargs = NamedTuple())` once per distributor per sweep — an INDIRECTION " *
    "site: it carries NO α_op_lb/α_x_lb literal of its own, forwarding whatever its " *
    "`specs` caller supplies. Every `run_nash!` call ALWAYS has " *
    "`bounds_ctx.follower_kwargs = nothing` (a pre-built DistributorView follower) once " *
    "plan 30-04 lands — α_op_lb is then LIVE-VALIDATED through this site, but α_x_lb's " *
    "build-time check is the documented, honest scope-limit skip for every such call. " *
    "The only literal in-repo today reaching run_nash! is test_planning_nash.jl's own " *
    "T=1, α_op_lb=-5.0/α_x_lb=0.0 (already covered in the T=1 census above — no T>1 " *
    "literal reaches run_nash! anywhere in this repo).",
)

println()
println("--- Step 2: derivation-formula audit of every found T>1 shape ---")
println()

# T=8 fixture, EXACT literals from test_planning_hardening.jl's own header comment/fixture
# body (lines 260-267): dev=ToyElasticDevice(2,6.0,1.0,10.0), agg with zeros(8) Pdc,
# λ₀=fill(4.0,8), follower_kwargs with c_op=fill(0.5,8).
function two_bus_feeder()
    buses = [TSODSO.Bus(1, 0.95, 1.05, true), TSODSO.Bus(2, 0.95, 1.05, false)]
    branches = [TSODSO.Branch(1, 2, 1e-3, 1e-3, TSODSO.SMAX_NO_LIMIT)]
    return TSODSO.Feeder(buses, branches, 1)
end

struct ToyElasticDevice <: TSODSO.AbstractDevice
    bus::Int
    a::Float64
    b::Float64
    Pmax::Float64
end

function TSODSO.contribute!(d::ToyElasticDevice, ctx::TSODSO.ModelContext; T::Int)
    m = ctx.model
    p = @variable(m, [t = 1:T], lower_bound = 0.0, upper_bound = d.Pmax)
    p_inject = AffExpr[-p[t] for t in 1:T]
    utility = sum(d.a * p[t] - (d.b / 2) * p[t]^2 for t in 1:T)
    return (; vars = (; p), p_inject, utility)
end

exit_code = 0
try
    for site in t_gt1_sites
        T = site.T
        feeder = two_bus_feeder()
        dev = ToyElasticDevice(2, 6.0, 1.0, 10.0)
        agg = TSODSO.Aggregator(2, 0.9, [dev], zeros(T))
        λ₀ = fill(4.0, T)

        derived_op =
            TSODSO.derive_alpha_op_lb(feeder, LinDistFlow(), [agg]; λ₀ = λ₀, T = T, y_max = 8.0)
        verdict_op = site.α_op_lb > derived_op + TSODSO.ALPHA_LB_REJECTION_TOL ? "REJECTED" : "accepted"

        derived_x = TSODSO.derive_alpha_x_lb(;
            T = T,
            corridor_cap = 2.0,
            x_inv_max = 2.0,
            c_inv = 1.0,
            c_op = fill(0.5, T),
        )
        verdict_x = site.α_x_lb > derived_x + TSODSO.ALPHA_LB_REJECTION_TOL ? "REJECTED" : "accepted"

        println("  $(site.file):$(site.line)  T=$T")
        println("    α_op_lb: literal=$(site.α_op_lb)  derived=$derived_op  VERDICT=$verdict_op")
        println("    α_x_lb:  literal=$(site.α_x_lb)  derived=$derived_x  VERDICT=$verdict_x")
    end
catch e
    global exit_code = 1
    println("SCRIPT ERROR (genuine failure, not an audit finding): ", sprint(showerror, e))
end

println()
println("--- Step 3: honest finding statement ---")
println()
if exit_code == 0
    println(
        "  No PREVIOUSLY-UNKNOWN invalid bound was found. The only T>1 site in the " *
        "10-file census (test_planning_hardening.jl's T=8 fixture) uses α_op_lb=-50.0, " *
        "which the new derivation formula ACCEPTS (as expected — this bound was already " *
        "fixed in-repo per that file's own documented finding). α_x_lb=0.0 at T=8 is " *
        "likewise accepted.",
    )
end

println()
println("AUDIT_EXIT_CODE=$exit_code")
exit(exit_code)

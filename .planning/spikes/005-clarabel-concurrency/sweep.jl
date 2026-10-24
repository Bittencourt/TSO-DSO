# Spike 005 — Clarabel concurrency & determinism: the sweep.
#
# QUESTION: are Clarabel solves executed inside `Threads.@spawn` tasks BITWISE-equal to
# serial solves — under `julia -t 4`, on a REAL multi-aggregator ADMM fixture, under the
# production configuration (indirect `Model` construction via the factory,
# `BLAS.set_num_threads(1)` + `MOI.NumberOfThreads() = 1` on every AGR model)?
# This is the PAR-02 gate artifact: the Phase-39 threaded ADMM executor is enabled ONLY if
# this spike records a PASS. Also settles the `direct_model` question as a classified
# outcome (failure classes are data).
#
# SUBSTRATE (observe-only — ZERO changes anywhere under src/): `TSODSO._admm_build` on the
# replicated minimal-scenario fixture (IEEE-13, seed 7, T=24, `ConvexBranchFlow()`, LIVE
# reactive consensus — the production smart default for this population, which carries a
# flexible-load member; the knife-edge canary's own fixture). Per aggregator j the unit of
# comparison is SOLVE-ONLY: the iteration-1 AGR-OPT step exactly as `_react_agr_solve!`
# does mid-loop — `solve_agr!(agr, st.λ[j], st.c[j], st.ρf; μ_j = ls.μq[j], d_j = ls.d[j],
# ρ_q = ls.ρ_qf, check_battery = false, strict = false)` (coefficient −λ_j − ρ·c_j on `pag`
# + `optimize!` of that aggregator's OWN JuMP model). Each task touches ONLY its own
# `AgrOpt.model` (disjoint per j); NO `st` writes happen inside any task (Dict READS are
# safe — writes are what race; all result application happens in the serial join, mirroring
# the locked executor design). NO DSO solve, NO λ update — the loop itself is already
# shared-and-serial by design; this spike measures exactly the grain that will be threaded.
#
# LEGS (all recorded per aggregator into sweep.csv, plus a per-leg all-equal summary):
#   1. serial_ref     — solve every aggregator sequentially (fresh state).
#   2. serial_recheck — identical re-run on ANOTHER freshly built state. POSITIVE CONTROL:
#                       must reproduce leg 1 BITWISE on every aggregator.
#   3. threaded       — fresh state; BLAS.set_num_threads(1) once; MOI.NumberOfThreads()=1
#                       on every AGR model (belt-and-braces pinning; accepted by Clarabel
#                       0.11.1); one `Threads.@spawn` task per aggregator doing its own
#                       coeff-set + optimize!, fetched in `load_nodes` order with the
#                       TaskFailedException unwrap the locked executor design prescribes.
#   4. direct_model   — attempt `JuMP.direct_model(Clarabel.Optimizer())` + a first
#                       `@variable`; CATCH and record the exception type as a classified
#                       outcome row (expected `MathOptInterface.AddVariableNotAllowed`).
#
# CONTROLS (non-negotiable, checked on EVERY run — a sweep that cannot reproduce a known
# result cannot be trusted when it reports a clean one):
#   POSITIVE: leg 2 ≡ leg 1 bitwise on every aggregator, else the script ERRORS.
#   NEGATIVE: on a dedicated scratch state, perturb ONE aggregator's coupling price
#             λ_j[1] by +eps() (1 ulp) and require the byte-compare vs leg 1 to FAIL.
#             If the solver absorbs that ulp (bit-identical output), the perturbation is
#             escalated ulp-by-ulp (a recorded data row: how many ulps became visible) —
#             a comparator that cannot detect ANY perturbation ERRORS the script.
#   CROSS-STATE: the scratch state's UNPERTURBED solve must also reproduce leg 1 bitwise
#             (a third, free reproducibility check) — else the script ERRORS.
#
# COMPARATOR: BITWISE, never `isapprox` — Float64 vectors via `reinterpret(UInt8, ·)` byte
# equality, scalars via `isequal`; an FNV-1a sha-style byte digest per (leg, j) over
# (pag bytes, objective bits, utility bits, barrier-iteration bits) so any mismatch is
# attributable to a specific (leg, aggregator).
#
# Run:  julia -t 4 --project=. .planning/spikes/005-clarabel-concurrency/sweep.jl
#
# Process-local note: BLAS.set_num_threads(1) here mutates THIS spike process only — the
# knife-edge canary's environment is untouched (each run is a fresh `julia` process).

using TSODSO
using JuMP
using LinearAlgebra: BLAS
using CSV
using DataFrames
import Clarabel

const T_HORIZON = 24
const SEED = 7
const SPIKE_DIR = @__DIR__
const EXPECTED_DIRECT_MODEL_ERROR = "MathOptInterface.AddVariableNotAllowed"

# ---- fixture replication (the ExperimentHarnessFixtures.minimal_scenario_kwargs recipe) ----

"""
Replicate `ExperimentHarnessFixtures.minimal_scenario_kwargs()` locally (a TestItems
`@testmodule` is unreachable from a plain script) and materialize through the PRODUCTION
factory seams: `build_feeder` → `generate_profiles` → `build_price` → `build_population`.
`sub_seed(SEED, :profiles)` / `sub_seed(SEED, :population)` mirror `Scenario._materialize`
verbatim, so this is byte-identical to what `run_scenario` would materialize for
`Scenario(; name = "harness-fixture", feeder = :ieee13, strategy = :admm, seed = 7, T = 24)`.
"""
function build_fixture()
    feeder = TSODSO.build_feeder(:ieee13)
    profiles = TSODSO.generate_profiles(; seed = TSODSO.sub_seed(SEED, :profiles), T = T_HORIZON)
    λ₀ = TSODSO.build_price(:mem, T_HORIZON, profiles)
    aggs = TSODSO.build_population(
        :default,
        feeder,
        :ieee13,
        profiles,
        TSODSO.sub_seed(SEED, :population),
    )
    return feeder, λ₀, aggs
end

"""
Build one fresh `AdmmState` via the PRODUCTION factory `TSODSO._admm_build` with the
production ADMM defaults (ρ = 100.0, ρ_q = ρ; strategy `ADMM()`'s own defaults) and the
production smart-default reactive consensus for this population (LIVE — a flexible-load
member is present; same resolution `solve_admm` makes via `_default_reactive_consensus`).
"""
function build_state(feeder, λ₀, aggs)
    ρf = 100.0                      # ADMM() default ρ
    ρ_qf = 100.0                    # ADMM() default ρ_q = ρ
    mode = TSODSO.normalize_reactive_mode(TSODSO.ReactiveMode.LIVE)
    rmode = TSODSO._react_mode(mode)
    # Scenario's default pf selector — the production ADMM-capable formulation.
    st = TSODSO._admm_build(feeder, TSODSO.ConvexBranchFlow(), aggs, T_HORIZON, λ₀, ρf, ρ_qf, mode, rmode)
    return st
end

# ---- the solve-only per-aggregator unit (the exact grain the executor will thread) -----------

"""
The iteration-1 AGR-OPT solve-only unit for aggregator `j`, EXACTLY the mid-loop step
`_react_agr_solve!(rmode, st, j)` performs minus the `st` writes: per-j reads
(`st.λ[j]`, `st.c[j]`, `st.ρf`, LIVE `ls.μq[j]`/`ls.d[j]`/`ls.ρ_qf` — all safe from any
thread), coefficient −λ_j − ρ·c_j on `pag` (+ the LIVE qag_live analog) via the production
`solve_agr!`, `optimize!` of THIS aggregator's own model only. Returns the solution values;
touches no shared mutable state.
"""
function agr_solve_unit(st, j)
    agr = st.agr_by_bus[j]
    ls = st.react
    r = TSODSO.solve_agr!(
        agr,
        st.λ[j],
        st.c[j],
        st.ρf;
        μ_j = ls.μq[j],
        d_j = ls.d[j],
        ρ_q = ls.ρ_qf,
        check_battery = false,
        strict = false,
    )
    return (pag = r.pag, utility = r.utility)
end

"""
Full metric record for one (leg, j): solution values + the MOI barrier-iteration count
read from that aggregator's own model (always read in the SERIAL region — after fetch on
the threaded leg — mirroring the locked join design).
"""
function record_solution(st, j, sol)
    agr = st.agr_by_bus[j]
    return (
        bus = j,
        pag = sol.pag,
        objective_value = JuMP.objective_value(agr.model),
        utility = sol.utility,
        barrier_iterations = JuMP.MOI.get(agr.model, JuMP.MOI.BarrierIterations()),
    )
end

# ---- bitwise comparator (never isapprox) ------------------------------------------------------

# FNV-1a 64-bit over raw bytes — a sha-style attributable digest, stable within a process.
_fnv_update(h::UInt64, bytes) =
    foldl(bytes; init = h) do acc, b
        (acc ⊻ b) * 0x00000100000001b3
    end

"""
Byte digest of one solution record: pag bytes, then objective-value bits, utility bits and
barrier-iteration bits. Identical records ⇒ identical digest; a differing digest localizes
a mismatch to a specific (leg, aggregator).
"""
function digest_record(rec)
    h = _fnv_update(0xcbf29ce484222325, reinterpret(UInt8, rec.pag))
    h = _fnv_update(h, reinterpret(UInt8, [rec.objective_value]))
    h = _fnv_update(h, reinterpret(UInt8, [rec.utility]))
    h = _fnv_update(h, reinterpret(UInt8, [UInt64(rec.barrier_iterations)]))
    return string(h; base = 16, pad = 16)
end

biteq_pag(a, b) =
    length(a) == length(b) && all(reinterpret(UInt8, collect(a)) .== reinterpret(UInt8, collect(b)))

record_equal(r1, r2) =
    biteq_pag(r1.pag, r2.pag) &&
    isequal(r1.objective_value, r2.objective_value) &&
    isequal(r1.utility, r2.utility) &&
    isequal(r1.barrier_iterations, r2.barrier_iterations)

# ---- CSV row ledger ---------------------------------------------------------------------------

const ROWS = []  # (; leg, bus, metric, value, note)

function row!(leg, bus, metric, value, note = "")
    # One physical line per row: strip embedded newlines (solver exception text carries
    # multi-line `showerror` output) so line-based inspection of sweep.csv stays sane.
    clean(s) = replace(string(s), '\n' => " | ", '\r' => "")
    push!(ROWS, (; leg = clean(leg), bus = clean(bus), metric = clean(metric),
        value = clean(value), note = clean(note)))
    return nothing
end

# ---- legs --------------------------------------------------------------------------------------

function run_serial_leg!(st, load_nodes, leg)
    recs = Dict{Int, Any}()
    for j in load_nodes
        sol = agr_solve_unit(st, j)
        rec = record_solution(st, j, sol)
        recs[j] = rec
        row!(leg, j, "pag_byte_digest", digest_record(rec))
        row!(leg, j, "objective_value", rec.objective_value)
        row!(leg, j, "utility", rec.utility)
        row!(leg, j, "barrier_iterations", rec.barrier_iterations)
    end
    return recs
end

function run_threaded_leg!(st, load_nodes)
    # Production configuration: BLAS pinned ONCE (process-global LBT state — per-task calls
    # would themselves race) + Clarabel solver threads pinned to 1 on EVERY AGR model
    # (belt-and-braces; QDLDL is single-threaded anyway, but the direct_solve_method
    # selection must never pick a threaded backend).
    BLAS.set_num_threads(1)
    for j in load_nodes
        JuMP.set_attribute(st.agr_by_bus[j].model, JuMP.MOI.NumberOfThreads(), 1)
    end
    futs = Dict{Int, Task}()
    for j in load_nodes
        futs[j] = Threads.@spawn agr_solve_unit($st, $j)
    end
    recs = Dict{Int, Any}()
    for j in load_nodes  # fetch in load_nodes order — serial error attribution (PAR-03 shape)
        sol = try
            fetch(futs[j])
        catch e
            e isa TaskFailedException ? throw(e.task.exception) : rethrow()
        end
        rec = record_solution(st, j, sol)
        recs[j] = rec
        row!("threaded", j, "pag_byte_digest", digest_record(rec))
        row!("threaded", j, "objective_value", rec.objective_value)
        row!("threaded", j, "utility", rec.utility)
        row!("threaded", j, "barrier_iterations", rec.barrier_iterations)
    end
    return recs
end

# ---- main --------------------------------------------------------------------------------------

function main()
    Threads.nthreads() >= 2 ||
        error("spike 005 must run under `julia -t N` with N ≥ 2 (got Threads.nthreads() = " *
              "$(Threads.nthreads())); the threaded leg is meaningless otherwise")

    feeder, λ₀, aggs = build_fixture()
    st_ref = build_state(feeder, λ₀, aggs)
    load_nodes = st_ref.load_nodes

    println("="^100)
    println("Spike 005 — Clarabel concurrency & determinism (PAR-02 gate)")
    println("="^100)
    println("julia            : ", VERSION)
    println("threads          : ", Threads.nthreads(), " (BLAS before pinning: ", BLAS.get_num_threads(), ")")
    println("fixture          : IEEE-13 (ieee13), seed ", SEED, ", T=", T_HORIZON, ", ConvexBranchFlow()")
    println("aggregators      : ", length(aggs), " on load_nodes ", load_nodes)
    println("reactive mode    : LIVE (production smart default for this population)")
    println("clarabel         : ", pkgversion(Clarabel))
    println("juMP             : ", pkgversion(JuMP))
    println("-"^100)

    # Leg 1: serial reference.
    rec_ref = run_serial_leg!(st_ref, load_nodes, "serial_ref")

    # Leg 2: serial recheck on a FRESH state — the POSITIVE CONTROL.
    st_re = build_state(feeder, λ₀, aggs)
    rec_re = run_serial_leg!(st_re, load_nodes, "serial_recheck")
    positive_ok = all(record_equal(rec_ref[j], rec_re[j]) for j in load_nodes)
    row!("positive_control", "ALL", "serial_recheck_bitwise_equal", positive_ok ? "PASS" : "FAIL",
        "fresh-state serial re-run vs serial_ref, bitwise on every aggregator")
    println("POSITIVE CONTROL (serial_recheck ≡ serial_ref bitwise): ",
        positive_ok ? "PASS" : "FAIL")

    # Leg 3: threaded @spawn leg under the production configuration.
    st_thr = build_state(feeder, λ₀, aggs)
    rec_thr = run_threaded_leg!(st_thr, load_nodes)
    per_metric = Dict{Int, NamedTuple}()
    threaded_equal = true
    for j in load_nodes
        r1, r3 = rec_ref[j], rec_thr[j]
        pm = (pag = biteq_pag(r1.pag, r3.pag),
            objective_value = isequal(r1.objective_value, r3.objective_value),
            utility = isequal(r1.utility, r3.utility),
            barrier_iterations = isequal(r1.barrier_iterations, r3.barrier_iterations))
        per_metric[j] = pm
        threaded_equal &= all(pm)
        row!("threaded_vs_serial_ref", j, "pag_bitwise_equal", pm.pag)
        row!("threaded_vs_serial_ref", j, "objective_value_bitwise_equal", pm.objective_value)
        row!("threaded_vs_serial_ref", j, "utility_bitwise_equal", pm.utility)
        row!("threaded_vs_serial_ref", j, "barrier_iterations_equal", pm.barrier_iterations)
    end
    verdict = threaded_equal ? "BITWISE-EQUAL" : "DIFFERS"
    row!("verdict", "ALL", "threaded_vs_serial", verdict,
        "under julia -t $(Threads.nthreads()), BLAS=1, MOI.NumberOfThreads()=1, Clarabel $(pkgversion(Clarabel))")

    # Leg 4: direct_model — classified outcome (failure classes are data, never a crash).
    dm_type = ""
    dm_msg = ""
    dm_ok = false
    try
        m = JuMP.direct_model(Clarabel.Optimizer())
        @variable(m, x[1:3])
        dm_type = "NO_ERROR"   # would contradict the session probe — recorded either way
    catch e
        dm_type = string(typeof(e))
        dm_msg = sprint(showerror, e)
        dm_ok = occursin(EXPECTED_DIRECT_MODEL_ERROR, dm_type)
    end
    row!("direct_model", "NA", "exception_type", dm_type,
        dm_ok ? "expected outcome: direct_model constructs but fails at first variable addition" :
                "UNEXPECTED outcome class")
    row!("direct_model", "NA", "expected", EXPECTED_DIRECT_MODEL_ERROR, first(dm_msg, 160))

    # NEGATIVE CONTROL: perturb one aggregator's coupling price on a dedicated scratch state;
    # the byte-compare vs serial_ref MUST fail (comparator proven live). Start at the plan's
    # 1 ulp (+ eps()); escalate ulp-by-ulp if the solver absorbs a perturbation — the ulp
    # count that first became visible is recorded as data.
    st_neg = build_state(feeder, λ₀, aggs)
    j★ = first(load_nodes)
    sol0 = agr_solve_unit(st_neg, j★)
    rec0 = record_solution(st_neg, j★, sol0)
    row!("cross_state_control", j★, "unperturbed_scratch_vs_serial_ref",
        record_equal(rec_ref[j★], rec0) ? "PASS" : "FAIL",
        "third fresh state must also reproduce serial_ref bitwise")
    record_equal(rec_ref[j★], rec0) ||
        error("CROSS-STATE control failed: an unperturbed scratch solve of bus $j★ did not " *
              "reproduce serial_ref bitwise — the fixture is not deterministic; no result here " *
              "can be trusted")
    println("CROSS-STATE CONTROL (unperturbed scratch ≡ serial_ref bitwise): PASS")

    λ_orig = copy(st_neg.λ[j★])
    neg_seen = false
    neg_ulp_exp = -1
    for ulp_exp in 0:20
        st_neg.λ[j★][1] = λ_orig[1] + eps() * 2.0^ulp_exp
        solk = agr_solve_unit(st_neg, j★)
        reck = record_solution(st_neg, j★, solk)
        if !record_equal(rec_ref[j★], reck)
            neg_seen = true
            neg_ulp_exp = ulp_exp
            break
        end
    end
    row!("negative_control", j★, "byte_compare_after_perturbation",
        neg_seen ? "FAILED_AS_DESIGNED" : "UNEXPECTEDLY_EQUAL",
        neg_seen ? "coupling price perturbed by eps()*2^$(neg_ulp_exp) became visible" :
                   "no perturbation up to eps()*2^20 changed the output bits")
    println("NEGATIVE CONTROL (perturbed λ_j must FAIL the byte-compare): ",
        neg_seen ? "FAILED_AS_DESIGNED (visible at eps()*2^$neg_ulp_exp)" : "UNEXPECTEDLY_EQUAL")
    positive_ok || error("POSITIVE control failed: a fresh-state serial re-run did not reproduce " *
                         "serial_ref bitwise on every aggregator — the comparator or fixture is " *
                         "untrustworthy; refusing to report a threaded verdict")
    neg_seen || error("NEGATIVE control failed: no coupling-price perturbation up to eps()*2^20 " *
                      "changed the output bits — the comparator cannot detect differences; " *
                      "refusing to report a threaded verdict")

    # ---- stdout table ----
    println("-"^100)
    println(rpad("bus", 6), rpad("digest serial_ref", 20), rpad("digest serial_recheck", 20),
        rpad("digest threaded", 20), "threaded == serial?")
    for j in load_nodes
        println(
            rpad(j, 6),
            rpad(digest_record(rec_ref[j]), 20),
            rpad(digest_record(rec_re[j]), 20),
            rpad(digest_record(rec_thr[j]), 20),
            all(per_metric[j]) ? "BITWISE-EQUAL" : "DIFFERS",
        )
    end
    println("-"^100)
    println("positive control : ", positive_ok ? "PASS" : "FAIL")
    println("negative control : ", neg_seen ? "FAILS-as-designed (comparator live)" : "BROKEN")
    println("direct_model     : ", dm_type, dm_ok ? "  (expected outcome)" : "  (UNEXPECTED)")
    println("VERDICT (threaded vs serial, production configuration): ", verdict)
    println("="^100)

    # ---- CSV (simple overwrite — a spike output, no keyed upsert needed) ----
    out = joinpath(SPIKE_DIR, "sweep.csv")
    CSV.write(out, DataFrame(ROWS))
    println("wrote ", out, " (", length(ROWS), " rows)")
    return verdict
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end

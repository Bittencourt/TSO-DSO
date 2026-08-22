# test/test_benchmark_ieee8500.jl
#
# D-16 deterministic goldens on the `--quick` point (SCALE-04, phase 25 plan 25-05).
#
# Plain `Test.jl` script (NOT a TestItemRunner `@testitem`): this test invokes an EXTERNAL
# SCRIPT as a subprocess (an integration test per `25-VALIDATION.md`'s Per-Task Verification
# Map), and this project's own recorded lesson is that TestItemRunner invoked via
# `julia --project=. -e '... @run_package_tests ...'` (a `-e` string with no real
# `__source__.file`) resolves the test root via cwd and can pick up SIBLING WORKTREE test
# copies, producing spurious failures. A plain script with a real entrypoint file sidesteps
# that entirely. Run directly:
#
#   julia --project=. test/test_benchmark_ieee8500.jl
#
# STABILITY-BEFORE-GOLDEN (Phase 22 D-11's measurement-before-golden convention): the `--quick`
# point (`julia --project=. scripts/benchmark_ieee8500.jl --fixture ieee8500-mv --quick`) was
# run **3 times** during this plan's authoring, confirmed 2026-08-21, on the quiet post-wave-3
# machine — every run produced IDENTICAL `model_vars` (137594), `model_cons` (275118),
# `termination_status` ("OPTIMAL"), `admm_status` ("budget_exceeded"), and `admm_iters` (1). See
# `.planning/phases/25-ieee-8500-scalability-benchmark/25-05-SUMMARY.md` for the full 3-run
# trace. Wall time (`assembly_time_s`/`solve_time_s`/`admm_time_s`/`total_time_s`) is NEVER
# asserted below (D-16: wall time is recorded in the CSV, but never a golden).
#
# SUPERSEDED 2026-08-22 (quick task 260822-pxb — historical entry above preserved, this note is
# appended, not a replacement): the `ieee8500-mv` fixture's bus/branch count moved (2521/2520 ->
# 2518/2517) after a 3-pair topological bus-merge replaced impedance fabrication for 2 genuine
# 1-ft real-conductor bus-splits plus the substation busbar-tie connector (see
# `src/data/ieee8500_impedances.jl`'s generated-file header and `25-DATA-PROVENANCE.md`). This
# file's OWN Test 1 (run `--quick` twice in the SAME session, compare directly against each
# other) re-confirmed stability on the NEW topology: both runs produced IDENTICAL `model_vars`
# (137444) and `model_cons` (274818) — the golden in Test 2 below is updated to these
# freshly-measured, stable values. `termination_status` ("OPTIMAL"), `admm_status`
# ("budget_exceeded"), and `admm_iters` (1) did NOT change and are left untouched.

using Test
using CSV, DataFrames

const PROJECT_ROOT = normpath(joinpath(@__DIR__, ".."))
const SCRIPT = joinpath(PROJECT_ROOT, "scripts", "benchmark_ieee8500.jl")
const CSV_PATH = joinpath(PROJECT_ROOT, "results", "ieee8500_benchmark", "density_sweep.csv")

"""
    run_quick() -> DataFrameRow

Runs `julia --project=<repo root> scripts/benchmark_ieee8500.jl --fixture ieee8500-mv --quick`
as a REAL SUBPROCESS (never `include`d in-process — this is a genuine end-to-end check of the
harness AS A USER INVOKES IT, matching `25-VALIDATION.md`'s documented quick command exactly),
then parses the resulting `density_sweep.csv`'s row for the `(fixture="ieee8500-mv",
solver="clarabel")` key `--quick` always produces. `main(ARGS)` overwrites/replaces this exact
row on every invocation (`run_sweep_mode`'s own key-based CSV upsert), so reading the row back
after the subprocess exits reflects THIS run, not a stale one from an earlier session.
"""
function run_quick()
    run(`julia --project=$PROJECT_ROOT $SCRIPT --fixture ieee8500-mv --quick`)
    df = CSV.read(CSV_PATH, DataFrame)
    rows = filter(r -> r.fixture == "ieee8500-mv" && r.solver == "clarabel", df)
    @assert nrow(rows) == 1 "expected exactly 1 ieee8500-mv/clarabel row in $CSV_PATH after " *
                            "--quick, got $(nrow(rows))"
    return only(eachrow(rows))
end

@testset "D-16 deterministic goldens on the --quick point" begin
    # Test 1: stability — run --quick TWICE in this session and compare the three deterministic
    # quantities directly against EACH OTHER (not yet against a pinned literal) — this is the
    # measurement-before-golden discipline itself, encoded as a live assertion.
    r1 = run_quick()
    r2 = run_quick()

    @test r1.model_vars == r2.model_vars
    @test r1.model_cons == r2.model_cons
    @test r1.termination_status == r2.termination_status
    @test r1.admm_status == r2.admm_status
    @test r1.admm_iters == r2.admm_iters

    # Test 2: the golden itself — originally pinned 2026-08-21 after confirming 3-run stability
    # (this file's own 2-run check above, PLUS a third run recorded in 25-05-SUMMARY.md); RE-PINNED
    # 2026-08-22 (quick task 260822-pxb) after the fixture's bus-merge changed its topology (see
    # the file-header note above) — re-confirmed stable across this file's own 2-run check on the
    # NEW topology before updating. Asserts ONLY the three deterministic quantities D-16 names
    # (ADMM iteration count, model variable/constraint dimensions, solver termination status) —
    # NEVER wall time.
    @test r2.model_vars == 137444
    @test r2.model_cons == 274818
    @test r2.termination_status == "OPTIMAL"
    @test r2.admm_status == "budget_exceeded"
    @test r2.admm_iters == 1
end

println("test_benchmark_ieee8500.jl: ALL TESTS PASSED")

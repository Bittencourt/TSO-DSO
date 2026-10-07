# Test entrypoint.
#
# TestItemRunner discovers every `@testitem` under `test/` (and `src/`) and runs
# each in its own isolated module. The src/
# seams are exercised by the per-feature items.
# The runner infrastructure itself must stay healthy (failures, not a crash).
#
# Soft-scope-ambiguity bugs inside @testitem bodies (durable detection-method note,
# a past test fix): TestItemRunner evaluates each `@testitem` body as MODULE
# TOP-LEVEL code (a bare assignment there is a module global). A `for`/`while`/`try`
# nested under that top level is a SOFT SCOPE: a bare reassignment to the same name
# inside it (e.g. `caught = e` inside a `catch`, or `s += i` inside a `for`) creates a
# BRAND-NEW LOCAL that dies with the block instead of ever updating the outer global.
# The consequence is worse than a lint nit -- an `@test` reading that outer name can
# become permanently VACUOUS (it passes regardless of what happened inside the loop),
# silently invisible to a normal green run. This has hit the suite twice: the exactness
# gate scan in `test/test_stochastic_welfare.jl` (commit `d8e8999`) and the `caught`
# exception gate in `test/test_planning_certification_integer.jl`
# (both fixed). The established fix idiom (used both times): move the block's mutable
# accumulator state into a `let` block (a hard scope, immune to the ambiguity), and
# destructure the `let`'s returned tuple back into the `@testitem` top level immediately
# afterward.
#
# AUTHORITATIVE detector: Julia's own lowering-time warning -- `Warning: Assignment to
# X in soft scope is ambiguous ...` -- printed on a full suite run. `grep -c "soft scope
# is ambiguous"` over a full-suite run log must be `0`. Measured empirically: the
# warning fires when TestItemRunner evaluates a `@testitem` body via `Core.eval(mod,
# body_expr)` (its actual mechanism) but does NOT fire for the same ambiguous code
# wrapped in a literal `module ... end` syntax block, nor for a plain `julia script.jl`
# top-level run -- Julia only warns on this class of top-level `Core.eval`, not on
# statically-parsed module bodies or scripts. A local reproduction script must mimic
# `Core.eval(Module(), quote ... end)` to see the warning; a `module ... end`-wrapped
# repro will silently pass without ever printing it.
#
# A grep-based pre-commit hint for this pattern (a small script that is not part of the repo)
# is a cheap, OPTIONAL, non-authoritative check;
# it had known false positives and false negatives
# and is never a substitute for the grep above.
#
# Selection and guards: `TSODSO_TEST_SET` = fast | slow | all (unset = all;
# any other value is an error). `TSODSO_TEST_VERBOSE=1` passes verbose=true so per-item
# Time is printed. `TSODSO_TEST_FILES=a.jl,b.jl` restricts to those basenames (short runs).
# Only items under test/ are selected, a zero selection fails, and any Broken/skipped
# record not listed in test/expected_broken.txt fails the run.
using TestItemRunner, Test
include(joinpath(@__DIR__, "runner_support.jl"))

function tso_run_all()
    set = test_set_from_env()
    test_dir = @__DIR__
    selected = Ref(0)
    filt = function (ti)
        m = tso_selected(ti, set, test_dir)
        m && (selected[] += 1)
        return m
    end
    verbose = get(ENV, "TSODSO_TEST_VERBOSE", "") == "1"
    allowed = read_expected_broken(joinpath(test_dir, "expected_broken.txt"))
    @testset "TSODSO" begin
        outer = Test.get_testset()
        @run_package_tests filter = filt verbose = verbose
        @testset "guards" begin
            @test selected[] > 0
            recs = broken_records(outer)
            bad = [r for r in recs if !is_allowed(r, allowed)]
            foreach(
                r -> println("UNEXPECTED ", r.kind, " record: ", r.where, " :: ", r.expr),
                bad,
            )
            @test isempty(bad)
        end
    end
end

tso_run_all()

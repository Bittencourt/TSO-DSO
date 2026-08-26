# Wave 0 test entrypoint.
#
# TestItemRunner discovers every `@testitem` under `test/` (and `src/`) and runs
# each in its own isolated module. In Wave 0 all seam items are RED (the src/
# stubs are empty), which is the intended state — later plans drive them green.
# The runner infrastructure itself must stay healthy (failures, not a crash).
#
# Soft-scope-ambiguity bugs inside @testitem bodies (durable detection-method note,
# quick task 260826-0y4): TestItemRunner evaluates each `@testitem` body as MODULE
# TOP-LEVEL code (a bare assignment there is a module global). A `for`/`while`/`try`
# nested under that top level is a SOFT SCOPE: a bare reassignment to the same name
# inside it (e.g. `caught = e` inside a `catch`, or `s += i` inside a `for`) creates a
# BRAND-NEW LOCAL that dies with the block instead of ever updating the outer global.
# The consequence is worse than a lint nit -- an `@test` reading that outer name can
# become permanently VACUOUS (it passes regardless of what happened inside the loop),
# silently invisible to a normal green run. This has hit the suite twice: the D-06 PF-04
# gate scan in `test/test_stochastic_welfare.jl` (commit `d8e8999`) and the `caught`
# exception gate in `test/test_planning_certification_integer.jl` (quick task
# 260826-0y4). The established fix idiom (used both times): move the block's mutable
# accumulator state into a `let` block (a hard scope, immune to the ambiguity), and
# destructure the `let`'s returned tuple back into the `@testitem` top level immediately
# afterward.
#
# AUTHORITATIVE detector: Julia's own lowering-time warning -- `Warning: Assignment to
# X in soft scope is ambiguous ...` -- printed on a full suite run. `grep -c "soft scope
# is ambiguous"` over a full-suite run log must be `0`. Measured this session: the
# warning fires when TestItemRunner evaluates a `@testitem` body via `Core.eval(mod,
# body_expr)` (its actual mechanism) but does NOT fire for the same ambiguous code
# wrapped in a literal `module ... end` syntax block, nor for a plain `julia script.jl`
# top-level run -- Julia only warns on this class of top-level `Core.eval`, not on
# statically-parsed module bodies or scripts. A local reproduction script must mimic
# `Core.eval(Module(), quote ... end)` to see the warning; a `module ... end`-wrapped
# repro will silently pass without ever printing it.
#
# `.planning/quick/260826-0y4-fix-vacuous-caught-assertion-soft-scope-/softscope_scan.py`
# is a cheap, OPTIONAL, non-authoritative pre-commit grep-based hint for this pattern --
# see its own docstring's LIMITATIONS paragraph for its measured false-positive/
# false-negative rate. It is never a substitute for the grep above.
using TestItemRunner

@run_package_tests

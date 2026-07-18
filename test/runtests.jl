# Wave 0 test entrypoint.
#
# TestItemRunner discovers every `@testitem` under `test/` (and `src/`) and runs
# each in its own isolated module. In Wave 0 all seam items are RED (the src/
# stubs are empty), which is the intended state — later plans drive them green.
# The runner infrastructure itself must stay healthy (failures, not a crash).
using TestItemRunner

@run_package_tests

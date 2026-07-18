# src/data/topology.jl
#
# SEAM: radial (tree) validation (DATA-02).
# OWNER: plan 01-02.
#
# When filled, this file will provide `assert_radial` / `is_radial` using a sparse
# node–branch incidence (SparseArrays) plus BFS connectivity: a simple graph is a
# tree iff `edges == nodes - 1` AND connected AND exactly one designated root.
# A non-radial feeder raises a clear `ArgumentError`. Declares its own exports.
#
# Intentionally empty in plan 01-01: the package must precompile with this stub.

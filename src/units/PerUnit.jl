# src/units/PerUnit.jl
#
# SEAM: per-unit system (INFRA-05).
# OWNER: plan 01-02.
#
# When filled, this file will provide `PerUnitBase{T}`, the convert-once-at-
# ingestion helpers (`to_pu_power`, `to_pu_impedance`, ...), and the magnitude-
# sanity `@assert` bands (documented placeholder base: S_base = 1.0 MVA,
# V_base = 4.16 kV). It declares its own exports when implemented.
#
# Intentionally empty in plan 01-01: the package must precompile with this stub.

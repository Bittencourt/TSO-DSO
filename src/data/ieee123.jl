# src/data/ieee123.jl
#
# SEAM: modified IEEE 123-node feeder built-in fixture (DATA-03, scale target).
# OWNER: plan 07-01 wires this STUB into the include graph; plan 07-02 FILLS it.
#
# NAMING (IN-02): "IEEE 123-node" is the HISTORICAL name of the source test feeder, NOT a
# guaranteed bus count — the MODIFIED thesis Case B (App. E, p.170) relabels the thesis
# terminals to the framework's contiguous `bus.id == 1-based position` convention and keeps
# only the RADIAL branch set (tie switches open, so `edges == N − 1`). Read "123-node" as the
# lineage of the fixture, not its size.
#
# STUB (this plan): comment-only seam so the include graph is complete and file-disjoint for
# Wave 2. Plan 07-02 fills:
#
#     ieee123_modified() -> Feeder{Float64}
#
# the voltage-constrained (V ∈ [0.9, 1.1]) modified IEEE-123 feeder from thesis App. E, ALREADY
# per-unit (no SI→pu step), with a documented `thesis_terminal → 1..N` relabeling table and the
# substation/frontier terminal (150) as the root. Construction runs `assert_radial` +
# `assert_magnitudes` (RESEARCH Pitfall 4), so an invalid feeder can never be returned. The
# ~37 non-load junction (transit / zero-injection) buses are handled by the DSO-OPT transit-node
# relaxation (plan 07-03, RESEARCH Pitfall 5), not here — this file only ships the topology.
#
# Filled by plan 07-02 (DATA-03 / RESEARCH "IEEE-123 fixture").

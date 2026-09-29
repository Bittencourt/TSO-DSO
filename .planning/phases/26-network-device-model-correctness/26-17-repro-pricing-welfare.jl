# .planning/phases/26-network-device-model-correctness/26-17-repro-pricing-welfare.jl
#
# Direct-script reproduction of test/test_pricing_welfare.jl's two Plan-26-17-Task-3 items —
# TestItemRunner traps under --project=. (see the gsd-plan-verify-testitemrunner-trap memory):
#
#   (a) the near-lossless 2-bus identity testitem (":66"): confirms it solves cleanly at the
#       tol_gap Task 3 pinned (parsed live from the file), and that the surplus identity holds
#       to machine precision at that tol_gap.
#   (b) the net-EXPORTER testitem (":193"): re-measures the surplus split and asserts it matches
#       the CURRENTLY-PINNED prosumer/dso literals, parsed live from the edited test file (never
#       hardcoded here), so a wrong (or missing) re-pin fails this check.

using TSODSO
using TSODSO: Bus, Branch, Feeder
using JuMP

src = read("test/test_pricing_welfare.jl", String)

# --- (a) :66 near-lossless identity ---------------------------------------------------------
idx66 = findfirst("near-lossless 2-bus identity", src)
idx66 === nothing && error(
    "Could not locate the :66 near-lossless testitem in test/test_pricing_welfare.jl",
)
section66 = src[first(idx66):min(lastindex(src), first(idx66) + 3000)]
m66 = match(r"tol_gap_abs\s*=\s*([0-9.eE+-]+)", section66)
m66 === nothing && error(
    "Plan 26-17 Task 3 must add an explicit tol_gap_abs override to the :66 testitem's " *
    "solve_welfare call",
)
tol66 = parse(Float64, m66.captures[1])
println("PARSED :66 tol_gap_abs = ", tol66)

feeder66 = Feeder(
    [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
    [Branch(1, 2, 1.0e-6, 0.02, 10.0)],
    1,
)
T66 = 3
batt66 = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T66))
agg66 = Aggregator(2, 0.9, [batt66], fill(0.1, T66))
ctx66, obj66, _ = solve_welfare(
    feeder66,
    ConvexBranchFlow(),
    [agg66];
    T = T66,
    λ₀ = fill(40.0, T66),
    allow_export = true,
    optimizer = select_optimizer(SOCP(); tol_gap_abs = tol66, tol_gap_rel = tol66),
)
acct66 = welfare_accounting(ctx66; T = T66)
isapprox(acct66.prosumer + acct66.dso, acct66.social; rtol = 1e-6, atol = 1e-6) || error(
    ":66 near-lossless identity FAILED to hold tightly at the pinned tol_gap=$(tol66) " *
    "(prosumer+dso=$(acct66.prosumer + acct66.dso), social=$(acct66.social))",
)
println("OK :66 solves cleanly at tol_gap=", tol66, ", identity holds tightly")

# --- (b) :193 net-EXPORTER golden re-pin -----------------------------------------------------
feeder193 = Feeder(
    [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
    [Branch(1, 2, 0.01, 0.02, 10.0)],
    1,
)
T193 = 3
batt193 = PVBattery(2, 0.95, 1.0, 0.5, 0.0, 2.0, 1.0, 1.0, 2.0, 3.0, fill(0.2, T193))
agg193 = Aggregator(2, 0.9, [batt193], fill(0.1, T193))
ctx193, obj193, _ = solve_welfare(
    feeder193,
    ConvexBranchFlow(),
    [agg193];
    T = T193,
    λ₀ = fill(40.0, T193),
    allow_export = true,
)
acct193 = welfare_accounting(ctx193; T = T193)
println("MEASURED :193 prosumer=", acct193.prosumer, " dso=", acct193.dso)

idx193 = findfirst("net-EXPORTER earns", src)
idx193 === nothing && error(
    "Could not locate the :193 net-EXPORTER testitem in test/test_pricing_welfare.jl",
)
section193 = src[first(idx193):min(lastindex(src), first(idx193) + 3000)]
mp = match(r"acct\.prosumer,\s*([0-9.eE+-]+)\s*;\s*atol\s*=\s*([0-9.eE+-]+)", section193)
md = match(r"acct\.dso,\s*([0-9.eE+-]+)\s*;\s*atol\s*=\s*([0-9.eE+-]+)", section193)
(mp === nothing || md === nothing) && error(
    "Could not parse the pinned prosumer/dso golden literals from the :193 testitem in " *
    "test/test_pricing_welfare.jl",
)
pinned_prosumer, atol_p = parse(Float64, mp.captures[1]), parse(Float64, mp.captures[2])
pinned_dso, atol_d = parse(Float64, md.captures[1]), parse(Float64, md.captures[2])
println(
    "PARSED pinned prosumer=", pinned_prosumer, " (atol=", atol_p,
    "), dso=", pinned_dso, " (atol=", atol_d, ")",
)

ok_p = isapprox(acct193.prosumer, pinned_prosumer; atol = atol_p)
ok_d = isapprox(acct193.dso, pinned_dso; atol = atol_d)
(ok_p && ok_d) || error(
    ":193 golden re-pin FAILED: measured prosumer=$(acct193.prosumer) dso=$(acct193.dso) vs " *
    "pinned prosumer=$(pinned_prosumer)±$(atol_p) dso=$(pinned_dso)±$(atol_d)",
)
println("OK :193 measured surpluses match the pinned golden literals")

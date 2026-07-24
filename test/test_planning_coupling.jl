# test/test_planning_coupling.jl
#
# Seam: src/planning/coupling.jl (NASH-01). `SharedTransmission` +
# `build_shared_transmission` build the N-distributor shared corridor
# EXACTLY ONCE; `activate_distributor!`/`update_coupling!`/`write_back!`
# mutate it via Parameter/bound updates only (never a rebuild);
# `solve_follower!(::DistributorView, ...)` returns a feasible cost/dual
# slice for the active distributor or a GENUINE HiGHS Farkas certificate.
# Items tagged `[:planning]`, names contain "planning" and "coupling"
# (occursin filter convention, mirrors test_planning_follower.jl).
#
# Shared N=2 toy fixture (ASYMMETRIC per Revision 1, plan-checker pass
# 2026-07-23) used by every @testitem below: T=1, corridor_cap=2.0,
# x_inv_max=[0.3, 0.5], c_inv=[1.0, 3.0], c_op=[[0.5], [0.5]].
#
# Rationale for the asymmetric design (replacing an original symmetric
# x_inv_max=[0.3,0.3]/c_inv=[1.0,1.0] fixture): with symmetric values,
# freezing distributor 2 at its OWN ceiling (x_inv_2=0.3) and requiring a
# pooled sum of 0.6 forces BOTH distributors to their ceiling
# simultaneously — a write_back! bug that fails to actually pin x_inv[2]'s
# bounds is INVISIBLE, because x_inv[2] already sits at its own
# @variable-declared upper bound regardless of whether write_back! pinned
# it deliberately. The asymmetric x_inv_max leaves genuine headroom a
# broken pin could exploit; the asymmetric c_inv (distributor 2's
# investment unit-cost is 3x distributor 1's) eliminates the LP tie a
# broken pin would otherwise hide behind (with equal costs a solver is
# indifferent about WHICH distributor's investment relaxes the pooled row).
#
# Hand-derived reasoning: freeze distributor 2 (simulating it having
# already taken its turn) via write_back!(shared, 2, [0.2], 0.1) — z_2=0.2,
# x_inv_2=0.1, WELL BELOW distributor 2's own ceiling (x_inv_max[2]=0.5),
# unlike an at-ceiling freeze. The pooled capacity row requires
# x_inv[1] + x_inv[2] >= (z_1 + z_2) / corridor_cap. For distributor 1's
# feasible-branch request z_1=0.4: required pooled investment =
# (0.4 + 0.2) / 2.0 = 0.3; with x_inv[2] CORRECTLY pinned at 0.1,
# distributor 1's own x_inv[1] is uniquely forced to 0.3 - 0.1 = 0.2 — NOT
# at its own ceiling of 0.3, a genuinely determined, non-trivial value.
# Cost = c_inv[1]*0.2 + c_op[1][1]*0.4 = 0.2 + 0.2 = 0.4, with the pooled
# capacity row exactly binding (0.6 == 0.6, nonzero dual).
#
# If write_back!'s bound-pin on x_inv[2] were BROKEN (bounds left at their
# build-time default [0, 0.5] instead of pinned to [0.1, 0.1]), the SAME
# shared model would treat x_inv[2] as a genuinely free decision variable
# coupled directly into distributor 1's own solve; because c_inv[2]=3.0
# strictly exceeds c_inv[1]=1.0, the solver's UNIQUE optimum (no tie) would
# greedily satisfy the entire 0.3 pooled requirement from the CHEAP
# x_inv[1] alone — x_inv[1]=0.3 (exactly meets its own ceiling),
# x_inv[2]=0.0 — giving cost = 1.0*0.3 + 0.5*0.4 = 0.5, STRICTLY DIFFERENT
# from the correctly-pinned 0.4. Testitem 3 below asserts the
# correctly-pinned value (0.4); a regression to the OLD symmetric/
# at-ceiling fixture would have silently passed even with a broken pin —
# this is exactly the gap Revision 1 closes.
#
# The SAME asymmetric headroom independently discriminates the infeasible
# branch too: distributor 1's request z_1=0.61 exceeds the correctly-pinned
# pooled cap of corridor_cap*(0.3+0.1)=0.8 by 0.01 (0.61+0.2=0.81 > 0.8),
# producing a genuine Farkas certificate; but under a broken pin, x_inv[2]'s
# freed headroom (up to its own ceiling 0.5) raises the reachable pooled
# cap to corridor_cap*(0.3+0.5)=1.6, making the SAME request trivially
# feasible — so testitem 4 is a second, independent regression on the
# identical bug.

@testitem "planning coupling: build_shared_transmission guards" tags = [:planning] begin
    using TSODSO

    base_x_inv_max = [0.3, 0.5]
    base_c_inv = [1.0, 3.0]
    base_c_op = [[0.5], [0.5]]

    @test_throws ArgumentError build_shared_transmission(;
        N = 1,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = base_x_inv_max,
        c_inv = base_c_inv,
        c_op = base_c_op,
    )
    @test_throws ArgumentError build_shared_transmission(;
        N = 2,
        T = 0,
        corridor_cap = 2.0,
        x_inv_max = base_x_inv_max,
        c_inv = base_c_inv,
        c_op = base_c_op,
    )
    @test_throws ArgumentError build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 0.0,
        x_inv_max = base_x_inv_max,
        c_inv = base_c_inv,
        c_op = base_c_op,
    )
    @test_throws ArgumentError build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3],
        c_inv = base_c_inv,
        c_op = base_c_op,
    )
    @test_throws ArgumentError build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.0],
        c_inv = base_c_inv,
        c_op = base_c_op,
    )
    @test_throws ArgumentError build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = base_x_inv_max,
        c_inv = [1.0],
        c_op = base_c_op,
    )
    @test_throws ArgumentError build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = base_x_inv_max,
        c_inv = base_c_inv,
        c_op = [[0.5]],
    )
    @test_throws ArgumentError build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = base_x_inv_max,
        c_inv = base_c_inv,
        c_op = [[0.5, 0.3], [0.5]],
    )
end

@testitem "planning coupling: build-once invariant across activate!/update_coupling!/write_back!" tags =
    [:planning] begin
    using TSODSO
    using JuMP: num_variables, num_constraints

    shared = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.5],
        c_inv = [1.0, 3.0],
        c_op = [[0.5], [0.5]],
    )

    nv0 = num_variables(shared.model)
    nc0 = num_constraints(shared.model; count_variable_in_set_constraints = true)

    activate_distributor!(shared, 1)
    update_coupling!(shared, 1, [0.3])
    write_back!(shared, 1, [0.3], 0.15)
    activate_distributor!(shared, 2)
    solve_follower!(DistributorView(shared, 2), [0.2])

    @test num_variables(shared.model) == nv0
    @test num_constraints(shared.model; count_variable_in_set_constraints = true) == nc0
end

@testitem "planning coupling: feasible branch — distributor 1 delivers z=0.4 against a frozen, partially-committed distributor 2 (capacity dual nonzero, Pitfall 3 regression; asymmetric fixture makes a broken write_back! pin a true cost discriminator, Revision 1)" tags =
    [:planning] begin
    using TSODSO
    using JuMP: dual

    shared = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.5],
        c_inv = [1.0, 3.0],
        c_op = [[0.5], [0.5]],
    )

    write_back!(shared, 2, [0.2], 0.1)
    activate_distributor!(shared, 1)
    res = solve_follower!(DistributorView(shared, 1), [0.4])

    @test res.feasible == true
    # Hand-derived: with x_inv[2] correctly pinned at 0.1, x_inv[1] is
    # uniquely forced to 0.3 - 0.1 = 0.2; cost = 1.0*0.2 + 0.5*0.4 = 0.4.
    # NOT 0.5 — the value a broken write_back! pin on x_inv[2] would
    # produce (see file header derivation).
    @test res.cost ≈ 0.4 atol = 1e-6
    @test length(res.π_s) == 1

    @test abs(dual(shared.model[:capacity][1])) > 1e-8
end

@testitem "planning coupling: infeasible branch — distributor 1 exceeds remaining pooled headroom (Farkas certificate; independently discriminates a broken write_back! pin via the asymmetric ceiling headroom, Revision 1)" tags =
    [:planning] begin
    using TSODSO

    shared = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.5],
        c_inv = [1.0, 3.0],
        c_op = [[0.5], [0.5]],
    )

    write_back!(shared, 2, [0.2], 0.1)
    activate_distributor!(shared, 1)
    res = solve_follower!(DistributorView(shared, 1), [0.61])

    @test res.feasible == false
    @test isfinite(res.v) && res.v > 0
    @test all(isfinite, res.u)
end

@testitem "planning coupling: activate_distributor! restores investment freedom after write_back! pinned it" tags =
    [:planning] begin
    using TSODSO
    using JuMP: lower_bound, upper_bound

    shared = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.5],
        c_inv = [1.0, 3.0],
        c_op = [[0.5], [0.5]],
    )

    write_back!(shared, 1, [0.3], 0.15)
    @test lower_bound(shared.x_inv[1]) == 0.15
    @test upper_bound(shared.x_inv[1]) == 0.15

    activate_distributor!(shared, 1)
    @test lower_bound(shared.x_inv[1]) == 0.0
    @test upper_bound(shared.x_inv[1]) == 0.3
end

@testitem "planning coupling: PVAL-04 continuous-only regression — no binary/integer variable anywhere in the shared model" tags =
    [:planning] begin
    using TSODSO
    using JuMP: all_variables, is_binary, is_integer

    shared = build_shared_transmission(;
        N = 2,
        T = 1,
        corridor_cap = 2.0,
        x_inv_max = [0.3, 0.5],
        c_inv = [1.0, 3.0],
        c_op = [[0.5], [0.5]],
    )

    @test all(v -> !is_binary(v) && !is_integer(v), all_variables(shared.model))
end

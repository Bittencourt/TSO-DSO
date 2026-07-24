# test/fixtures_planning.jl
#
# Seam: PVAL-02 — a dedicated, `fixtures_phase4.jl`-style `@testmodule` holding the
# permanent regression goldens for the planning layer's two certified/hand-checked
# equilibria (N=1 Phase 11 BilevelJuMP certification, N=2 Phase 13 hand-checked Nash
# equilibrium), plus loose upper bounds on the N=2 multi-seed/multi-order probe's
# reported spread. This module DEFINES data only (mirrors fixtures_phase4.jl's own
# T-04-08 contract): plain top-level `const`s, no top-level call to any TSODSO solve
# entrypoint, consumed by test/test_planning_goldens.jl via `setup=[..., PlanningFixtures]`.

@testmodule PlanningFixtures begin
    using TSODSO

    # N=1 certified Stackelberg equilibrium (Phase 11 BilevelJuMP certification — see
    # test/test_planning_certification.jl's `BilevelCertFixture.Y_HAND`/`Z_HAND`/`OBJ_HAND`,
    # lines 69-74). This is the RE-DERIVED hand-enumeration answer
    # (`total(z) = 0.5*z^2 - 0.7*z`, first-order condition `z=0.7`), NOT
    # 11-01-PLAN.md's original (incorrect) y*=1.0/z*=1.0/-0.2 — see that file's header
    # DEVIATION note for the full derivation.
    const N1_Y_HAND = 0.7
    const N1_Z_HAND = 0.7
    const N1_OBJ_HAND = -0.245

    # N=2 hand-checked congested Nash equilibrium (Phase 13, symmetric toy fixture:
    # build_shared_transmission N=2 T=1 corridor_cap=2.0 x_inv_max=[0.3,0.3]
    # c_inv=[1.0,1.0] c_op=[[0.5],[0.5]]) — see test/test_planning_nash.jl lines 242-256
    # for the full derivation: pooled capacity corridor_cap*(x_inv_1+x_inv_2)=1.2 caps
    # z_i<=0.6 each, binding below the unconstrained z*=0.7.
    const N2_Z_HAND = [0.6, 0.6]
    const N2_XINV_HAND = [0.3, 0.3]

    # N=2 multi-seed (3) x multi-order (2) probe spread bounds — a LOOSE UPPER BOUND
    # (not an exact spread value), per CONTEXT.md's Claude's-Discretion resolution: the
    # equilibrium point z=[0.6,0.6] above is the stable hand-derived quantity, while the
    # probe's reported spread across seeds/orders is a solver-numerics-sensitive
    # diagnostic, not a value to pin exactly. Derived by running the SAME 3-seed x
    # 2-order probe shape as test/test_planning_nash.jl lines 622-660 (seeds = zero /
    # saturating / skewed, orders = (:forward, :reverse)) directly against the
    # production `run_nash_probe` entrypoint in a scratch dev-linked environment this
    # session. On this fully-symmetric toy fixture every seed/order combination
    # converges to the SAME equilibrium, so the observed spread sits at floating-point
    # noise (~1e-16), not genuine seed-dependence; each bound below is pinned many
    # orders of magnitude above that noise floor (headroom for cross-platform solver
    # variability) while remaining far below the ~0.01-0.7 spread a genuinely
    # seed-dependent equilibrium would produce (cf. test_planning_nash.jl's own
    # `[0.6,0.6]` vs `[0.7,0.0]` distinct-equilibria CR-01 regression).
    # observed z_spread ≈ 2.22e-16 (machine epsilon); bound pinned at 1e-4.
    const N2_PROBE_Z_SPREAD_MAX = 1e-4
    # observed x_inv_spread ≈ 0.0; bound pinned at 1e-4.
    const N2_PROBE_XINV_SPREAD_MAX = 1e-4
    # observed cost_spread ≈ 3.33e-16 (machine epsilon); bound pinned at 1e-3 (looser —
    # cost is a derived/scaled quantity, not a primal variable).
    const N2_PROBE_COST_SPREAD_MAX = 1e-3

    export N1_Y_HAND,
        N1_Z_HAND,
        N1_OBJ_HAND,
        N2_Z_HAND,
        N2_XINV_HAND,
        N2_PROBE_Z_SPREAD_MAX,
        N2_PROBE_XINV_SPREAD_MAX,
        N2_PROBE_COST_SPREAD_MAX
end

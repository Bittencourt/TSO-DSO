# test/fixtures_planning.jl
#
# Seam: planning-layer goldens — a dedicated, `fixtures_ieee13.jl`-style `@testmodule` holding the
# permanent regression goldens for the planning layer's two certified/hand-checked
# equilibria (N=1 BilevelJuMP certification, N=2 hand-checked Nash
# equilibrium), plus loose upper bounds on the N=2 multi-seed/multi-order probe's
# reported spread. This module DEFINES data only (mirrors fixtures_ieee13.jl's own
# contract): plain top-level `const`s, no top-level call to any TSODSO solve
# entrypoint, consumed by test/test_planning_goldens.jl via `setup=[..., PlanningFixtures]`.

@testmodule PlanningFixtures begin
    using TSODSO

    # N=1 certified Stackelberg equilibrium (BilevelJuMP certification — see
    # test/test_planning_certification.jl's `BilevelCertFixture.Y_HAND`/`Z_HAND`/`OBJ_HAND`,
    # lines 69-74). This is the RE-DERIVED hand-enumeration answer
    # (`total(z) = 0.5*z^2 - 0.7*z`, first-order condition `z=0.7`), NOT
    # the original (incorrect) y*=1.0/z*=1.0/-0.2 first derivation — see that test file's header
    # note for the full derivation.
    const N1_Y_HAND = 0.7
    const N1_Z_HAND = 0.7
    const N1_OBJ_HAND = -0.245

    # N=2 hand-checked congested Nash equilibrium (symmetric toy fixture:
    # build_shared_transmission N=2 T=1 corridor_cap=2.0 x_inv_max=[0.3,0.3]
    # c_inv=[1.0,1.0] c_op=[[0.5],[0.5]]) — see test/test_planning_nash.jl lines 242-256
    # for the full derivation: pooled capacity corridor_cap*(x_inv_1+x_inv_2)=1.2 caps
    # z_i<=0.6 each, binding below the unconstrained z*=0.7.
    const N2_Z_HAND = [0.6, 0.6]
    const N2_XINV_HAND = [0.3, 0.3]

    # N=2 multi-seed (3) x multi-order (2) probe spread bounds — a LOOSE UPPER BOUND
    # (not an exact spread value): the
    # equilibrium point z=[0.6,0.6] above is the stable hand-derived quantity, while the
    # probe's reported spread across seeds/orders is a solver-numerics-sensitive
    # diagnostic, not a value to pin exactly. Derived by running the SAME 3-seed x
    # 2-order probe shape as test/test_planning_nash.jl lines 622-660 (seeds = zero /
    # saturating / skewed, orders = (:forward, :reverse)) directly against the
    # production `run_nash_probe` entrypoint in a scratch dev-linked environment.
    # On this fully-symmetric toy fixture every seed/order combination
    # converges to the SAME equilibrium, so the observed spread sits at floating-point
    # noise (~1e-16), not genuine seed-dependence; each bound below is pinned many
    # orders of magnitude above that noise floor (headroom for cross-platform solver
    # variability) while remaining far below the ~0.01-0.7 spread a genuinely
    # seed-dependent equilibrium would produce (cf. test_planning_nash.jl's own
    # `[0.6,0.6]` vs `[0.7,0.0]` distinct-equilibria regression).
    # observed z_spread ≈ 2.22e-16 (machine epsilon); bound pinned at 1e-4.
    const N2_PROBE_Z_SPREAD_MAX = 1e-4
    # observed x_inv_spread ≈ 0.0; bound pinned at 1e-4.
    const N2_PROBE_XINV_SPREAD_MAX = 1e-4
    # observed cost_spread ≈ 3.33e-16 (machine epsilon); bound pinned at 1e-3 (looser —
    # cost is a derived/scaled quantity, not a primal variable).
    const N2_PROBE_COST_SPREAD_MAX = 1e-3

    """
        bilevel_toy_fixture() -> NamedTuple

    The shared locked 2-bus/T=1 fixture for the GENUINELY bilevel TSO-DSO variant:
    a near-lossless 2-bus feeder (root bus 1 + load bus 2),
    the TSO follower's own cost coefficients (`corridor_cap`, `x_inv_max`, `c_inv`,
    `c_op`, `pi_tariff`, `q_op`), and the DSO leader's own investment/network-welfare
    coefficients (`c_y`, `y_max`, `v_d`, `d_max`, `agg_bus`). Consumed by BOTH the
    sanity-check corner case and the bilevel certification
    fixture.

    `pi_tariff = [0.2]` is deliberately far below `c_op = [0.5]` — the follower's own
    marginal profit `pi_tariff[t]-c_op[t] = -0.3` is strictly negative for every unit
    of `z`, so its optimal response is `x_inv=z=0` for EVERY `y_inv >= 0`, a
    structural — not knife-edge — dominance argument.
    `q_op = [0.0]` deliberately keeps the follower's own cost
    LINEAR/bang-bang, reproducing the earlier behavior bit-for-bit — the
    genuinely NON-DEGENERATE, interior-response fixture with `q_op > 0` is a separate
    concern; this corner fixture is retained here purely as
    a cheap sanity check.

    # Hand-derived expectations (VERIFIED, not blindly trusted, by a

    # direct-script run — re-derive independently if a discrepancy appears, exactly

    # like this file's own N1_Y_HAND note)

      - BILEVEL (production `solve_bilevel!` on this fixture): since the follower's
        response is `x_inv=z=0` regardless of `y_inv` (strict per-unit cost
        dominance, not solver-dependent), the leader's own objective reduces to
        `c_y*y_inv` alone, minimized at `y_inv=0` ⇒ `y*=0, x_inv*=0, z*=[0.0], d*=[0.0], total*=0.0`.
      - JOINT (single planner, true costs, no tariff — see the bilevel certification test for the actual
        reference model): `z` is bounded by `d_max=2.0` (network-tied `d[t]=z[t]`
        exactly, lossless single-branch feeder) and by `corridor_cap*x_inv`; net
        coefficient on `z` is `c_op[t]-v_d[t] = -2.5` (strictly beneficial to
        deliver, so `z*=d_max=2.0`), requiring `x_inv*=1.0` (from
        `corridor_cap*x_inv>=z` binding) and `y_inv*=1.0` (minimal `y_inv>=x_inv`,
        since `c_y>0`): `total* = 0.1*1 + 1.0*1 + 0.5*2 - 3.0*2 = -3.9`.
      - MEASURED GAP: `|0.0 - (-3.9)| = 3.9`, and `z` differs `0.0` vs `2.0` — both
        orders of magnitude above any HiGHS `mip_feasibility_tolerance`/
        `mip_rel_gap`-class quantity (see the HiGHS exactness defaults), i.e. a genuine
        structural finding, not solver
        noise.
    """
    function bilevel_toy_fixture()
        feeder = Feeder(
            [Bus(1, 0.95, 1.05, true), Bus(2, 0.95, 1.05, false)],
            [Branch(1, 2, 1e-3, 1e-3, 99.0)],
            1,
        )
        return (;
            feeder = feeder,
            T = 1,
            agg_bus = 2,
            corridor_cap = 2.0,
            x_inv_max = 2.0,
            c_inv = 1.0,
            c_op = [0.5],
            pi_tariff = [0.2],
            q_op = [0.0],
            c_y = 0.1,
            y_max = 2.0,
            v_d = [3.0],
            d_max = 2.0,
        )
    end

    # Bilevel golden constants — the measured production/
    # joint answers on `bilevel_toy_fixture()`, consumed by
    # test/test_planning_certification_bilevel.jl's single @testitem instead of
    # inline literals, mirroring this file's own N1_Y_HAND/N1_Z_HAND/N1_OBJ_HAND
    # block convention.
    #
    # BILEV_* (production `TSODSO.solve_bilevel!` on this fixture): ANALYTIC
    # argument (see `bilevel_toy_fixture`'s own docstring) — the follower's
    # response is `x_inv=z=0` for EVERY `y_inv` (strict per-unit cost dominance,
    # `pi_tariff[1]-c_op[1] = -0.3 < 0`), so the leader's objective reduces to
    # `c_y*y_inv` alone, minimized at `y_inv=0`. EMPIRICALLY CONFIRMED by a live
    # solve (`julia`, stacked `JULIA_LOAD_PATH="test:.:@stdlib"`):
    # production, BilevelJuMP StrongDualityMode (residual ~1e-7, an Ipopt
    # interior-point noise floor near the corner, NOT a disagreement), and
    # brute-force grid enumeration (bit-identical, residual exactly 0.0) all
    # agree at this exact corner.
    const BILEV_Y_HAND = 0.0
    const BILEV_Z_HAND = 0.0
    const BILEV_TOTAL_HAND = 0.0

    # JOINT_* (the true single-planner, no-tariff reference on this fixture):
    # ANALYTIC argument (see `bilevel_toy_fixture`'s own docstring) — the net
    # coefficient on `z` is `c_op[1]-v_d[1] = -2.5` (strictly beneficial to
    # deliver), so `z*=d_max=2.0` (network-tied `d[t]=z[t]` exactly, lossless
    # single-branch feeder), requiring `x_inv*=1.0` (from
    # `corridor_cap*x_inv>=z` binding) and `y_inv*=1.0` (minimal `y_inv>=x_inv`,
    # since `c_y>0`). EMPIRICALLY CONFIRMED: live solve of
    # `build_joint_reference` (embedded `contribute!(LinDistFlow(), ...)`,
    # `TSODSO.assert_solved!`) reproduces this exactly (`total = 0.1*1 + 1.0*1 +
    # 0.5*2 - 3.0*2 = -3.9`).
    const JOINT_Y_HAND = 1.0
    const JOINT_XINV_HAND = 1.0
    const JOINT_Z_HAND = 2.0
    const JOINT_TOTAL_HAND = -3.9

    # BILEV_GAP_FLOOR — solver-precision mitigation: derived
    # from a MEASURED solver-precision quantity, 10x the production MILP's own
    # `select_optimizer(MILP())` `mip_feasibility_tolerance=1e-9` (the HiGHS
    # exactness defaults), NEVER as a fraction of the very
    # `|BILEV_TOTAL_HAND - JOINT_TOTAL_HAND| = 3.9` / `|BILEV_Z_HAND -
    # JOINT_Z_HAND| = 2.0` gaps it is meant to validate. Both gaps sit 8 orders
    # of magnitude above this floor; `total_cost` (a cost quantity, O(1)-O(4)
    # scale here) and `z` (a power quantity bounded by `d_max=2.0`) are within
    # the same order of magnitude in THIS fixture (checked, not assumed), so one
    # shared floor is valid for both assertions.
    const BILEV_GAP_FLOOR = 1e-8

    export N1_Y_HAND,
        N1_Z_HAND,
        N1_OBJ_HAND,
        N2_Z_HAND,
        N2_XINV_HAND,
        N2_PROBE_Z_SPREAD_MAX,
        N2_PROBE_XINV_SPREAD_MAX,
        N2_PROBE_COST_SPREAD_MAX,
        bilevel_toy_fixture,
        BILEV_Y_HAND,
        BILEV_Z_HAND,
        BILEV_TOTAL_HAND,
        JOINT_Y_HAND,
        JOINT_XINV_HAND,
        JOINT_Z_HAND,
        JOINT_TOTAL_HAND,
        BILEV_GAP_FLOOR
end

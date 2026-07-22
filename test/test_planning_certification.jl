# test/test_planning_certification.jl
#
# Seam: PLAN-07 + PVAL-01 — certify (not assume) the leader/follower role
# assignment and coupling-dual sign convention chosen in plans 11-01/11-02, using
# an INDEPENDENT BilevelJuMP MPEC reduction on the SAME tiny toy instance,
# cross-checked against a hand-worked enumeration. Two permanent [:planning]-
# tagged @testitems (retained forever, never a one-off validation script):
#   1. StrongDualityMode + ProductMode (see DEVIATION note below) agree with
#      each other AND with the hand-enumerated optimum.
#   2. solve_stackelberg! (the production Benders loop, plan 11-02) agrees with
#      the certified BilevelJuMP answer on the IDENTICAL toy instance.
#
# NOTE (INFRA-02 exception, Pitfall B3, mirrors test_planning_retry.jl's own
# documented-exception convention): `BilevelModel`'s own constructor contract
# requires a bare zero-arg solver constructor (`HiGHS.Optimizer`/
# `Ipopt.Optimizer`), not an `OptimizerWithAttributes` from the project's own
# solver-factory abstraction (INFRA-02's sole solver-naming seam elsewhere).
# This file — and ONLY this file besides `ext/TSODSOGurobiExt.jl` — imports
# HiGHS/Ipopt directly, because BilevelJuMP is a validation-oracle-only,
# test-only dependency (never imported by `src/`), per CLAUDE.md's "validation
# oracle only" rule.
#
# RE-DERIVED HAND ENUMERATION (NOT 11-01-PLAN.md's stated y*=1.0/z*=1.0/-0.2):
# per 11-02-SUMMARY.md's own discovery (independently re-verified here, per
# this plan's explicit instruction NOT to blindly reuse 11-01-PLAN.md's stated
# numbers), the leader's total minimization on this instance is the
# UNCONSTRAINED convex quadratic `total(z) = c_y*z + m_f*z - welfare(z)`, with
# `welfare(z) = (a-λ₀)*z - (b/2)*z^2 = 2z - 0.5z^2` and `m_f = 1.0`:
# substituting, `total(z) = 0.5*z^2 - 0.7*z`, first-order condition `z=0.7`
# gives `total(0.7) = -0.245 < total(1.0) = -0.2` — i.e. `z*=1.0` is NOT even a
# stationary point of the fixture it claims to describe (an arithmetic slip in
# 11-01-PLAN.md's own <toy_fixture> block, not a defect in any src/ code). This
# file asserts against the RE-DERIVED, verified `y* = z* = 0.7`,
# `total = -0.245`.
#
# DEVIATION FROM PLAN (Rule 1 — auto-fixed bug in the plan's own assumed
# approach, empirically measured this session): the plan's <interfaces> block
# specifies `BigMMode(...)` with `HiGHS.Optimizer` as one of the two
# independent certification reformulations. Measured directly this session:
# `BilevelJuMP.BigMMode`'s Fortuny-Amat/Big-M reformulation of the follower
# LP's KKT/complementarity conditions introduces BINARY indicator variables;
# combined with this instance's genuinely QUADRATIC Upper-level welfare term
# (`-(2z - 0.5z^2)`, load-bearing — it is the SAME closed-form oracle welfare
# the production PlanningOracle computes), the resulting single-level
# reformulation is a MIQP (mixed-integer QUADRATIC program) — a problem class
# HiGHS categorically does NOT support, REGARDLESS of Big-M bound choice or
# instance size (confirmed: `optimize!` does not throw; it returns normally
# with `termination_status(model) == MOI.OTHER_ERROR`, and HiGHS itself prints
# "Cannot solve MIQP problems with HiGHS"). This is NOT a Big-M-bound tuning
# issue (Pitfall B1's warning sign is two DIFFERENT solved answers disagreeing
# — here BigMMode+HiGHS never reaches a solved answer at all, at any bound).
# Per Rule 1, `BilevelJuMP.BigMMode`+HiGHS is retained here ONLY as a
# documented, asserted NEGATIVE regression (so this finding is never silently
# rediscovered by a future plan) — never as a live "certifying" solve.
# `BilevelJuMP.ProductMode` (already shipped in the installed BilevelJuMP
# 0.6.3 — NO new dependency) substitutes for BigMMode's role as the SECOND,
# structurally-independent reformulation: it reformulates complementarity as
# an epsilon-relaxed bilinear PRODUCT inequality (solved via Ipopt, a genuinely
# different algebraic path from `StrongDualityMode`'s strong-duality EQUALITY
# reformulation), preserving PLAN-07/PVAL-01's actual intent — "two
# independent reformulations cross-checked against hand enumeration" — without
# requiring any new test-only dependency or a licensed MIQP-capable solver
# (Gurobi is not licensed in this environment; verified no `gurobi.lic`/`GRB_*`
# present, and CLAUDE.md reserves Gurobi for a licensed fallback only).

@testmodule BilevelCertFixture begin
    using BilevelJuMP, HiGHS, Ipopt, JuMP

    # Hand-enumerated optimum, RE-DERIVED — see this file's own header comment
    # for the full derivation. NOT 11-01-PLAN.md's stated (incorrect) y*=1.0/
    # z*=1.0/total=-0.2.
    const Y_HAND = 0.7
    const Z_HAND = 0.7
    const OBJ_HAND = -0.245

    # The Phase-11 toy instance (11-01-PLAN.md's own <toy_fixture>, reused
    # verbatim): T=1, corridor_cap=2.0, x_inv_max=2.0, c_inv=1.0, c_op=[0.5],
    # c_y=0.3, oracle welfare closed form welfare(z) = 2*z - 0.5*z^2. Built
    # TWICE (once per mode) since each BilevelModel owns its own solver
    # instance — no build-once/re-solve here, this is a throwaway MPEC built
    # fresh per assertion, unlike the production build-once JuMP models.
    function build_toy_bilevel(mode)
        model = BilevelModel(Ipopt.Optimizer, mode = mode)
        @variable(Upper(model), y_inv >= 0)
        @variable(Upper(model), z)
        @constraint(Upper(model), z <= y_inv)
        @constraint(Upper(model), z >= 0)
        @variable(Lower(model), 0 <= x_inv <= 2.0)
        @variable(Lower(model), x_op >= 0)
        @constraint(Lower(model), invest_op, x_op <= 2.0 * x_inv)
        @constraint(Lower(model), coupling, x_op == z)
        @objective(Lower(model), Min, 1.0 * x_inv + 0.5 * x_op)
        @objective(
            Upper(model),
            Min,
            0.3 * y_inv + 1.0 * x_inv + 0.5 * x_op - (2 * z - 0.5 * z^2)
        )
        optimize!(model)
        return (; model, y_inv, z, x_inv, x_op)
    end

    # BigMMode+HiGHS — retained ONLY as a documented NEGATIVE regression (see
    # this file's header DEVIATION note): this instance's quadratic Upper
    # objective, combined with BigMMode's own binary complementarity
    # indicators, produces a genuine MIQP that HiGHS cannot solve.
    function build_toy_bilevel_bigm(; primal_big_M = 20.0, dual_big_M = 20.0)
        model = BilevelModel(
            HiGHS.Optimizer,
            mode = BilevelJuMP.BigMMode(
                primal_big_M = primal_big_M,
                dual_big_M = dual_big_M,
            ),
        )
        @variable(Upper(model), y_inv >= 0)
        @variable(Upper(model), z)
        @constraint(Upper(model), z <= y_inv)
        @constraint(Upper(model), z >= 0)
        @variable(Lower(model), 0 <= x_inv <= 2.0)
        @variable(Lower(model), x_op >= 0)
        @constraint(Lower(model), invest_op, x_op <= 2.0 * x_inv)
        @constraint(Lower(model), coupling, x_op == z)
        @objective(Lower(model), Min, 1.0 * x_inv + 0.5 * x_op)
        @objective(
            Upper(model),
            Min,
            0.3 * y_inv + 1.0 * x_inv + 0.5 * x_op - (2 * z - 0.5 * z^2)
        )
        optimize!(model)
        return (; model, y_inv, z, x_inv, x_op)
    end
end

@testitem "planning certification: StrongDualityMode + ProductMode agree with each other and the hand-enumerated optimum (z*=0.7); BigMMode+HiGHS documented MIQP incapacity" tags =
    [:planning] setup = [BilevelCertFixture] begin
    using BilevelJuMP, JuMP

    # Mode 1: StrongDualityMode (Ipopt) — strong-duality EQUALITY reformulation.
    r_sd = BilevelCertFixture.build_toy_bilevel(BilevelJuMP.StrongDualityMode())
    @test termination_status(r_sd.model) == MOI.LOCALLY_SOLVED
    @test isapprox(value(r_sd.y_inv), BilevelCertFixture.Y_HAND; atol = 1e-3)
    @test isapprox(value(r_sd.z), BilevelCertFixture.Z_HAND; atol = 1e-3)
    @test isapprox(objective_value(r_sd.model), BilevelCertFixture.OBJ_HAND; atol = 1e-3)

    # Mode 2: ProductMode (Ipopt) — epsilon-relaxed bilinear-PRODUCT
    # complementarity reformulation. Substitutes for BigMMode+HiGHS as the
    # SECOND, structurally-independent reformulation (see file header
    # DEVIATION note) — already shipped in BilevelJuMP 0.6.3, no new dependency.
    r_prod = BilevelCertFixture.build_toy_bilevel(BilevelJuMP.ProductMode(1e-9))
    @test termination_status(r_prod.model) == MOI.LOCALLY_SOLVED
    @test isapprox(value(r_prod.y_inv), BilevelCertFixture.Y_HAND; atol = 1e-3)
    @test isapprox(value(r_prod.z), BilevelCertFixture.Z_HAND; atol = 1e-3)
    @test isapprox(objective_value(r_prod.model), BilevelCertFixture.OBJ_HAND; atol = 1e-3)

    # Pairwise agreement between the two INDEPENDENT, structurally-different
    # reformulations:
    @test isapprox(value(r_sd.y_inv), value(r_prod.y_inv); rtol = 1e-4)
    @test isapprox(value(r_sd.z), value(r_prod.z); rtol = 1e-4)
    @test isapprox(objective_value(r_sd.model), objective_value(r_prod.model); rtol = 1e-4)

    # DOCUMENTED, PERMANENT negative regression (Pitfall B1's own warning sign
    # does NOT apply here — this is a categorical solver-capability gap, not a
    # bound-tuning issue; see file header DEVIATION note): BigMMode+HiGHS never
    # reaches a solved status on this instance, at ANY Big-M bound, because the
    # single-level reformulation is a genuine MIQP. `optimize!` does not throw;
    # it returns normally with `termination_status == MOI.OTHER_ERROR`.
    r_bigm = BilevelCertFixture.build_toy_bilevel_bigm()
    @test termination_status(r_bigm.model) == MOI.OTHER_ERROR
end

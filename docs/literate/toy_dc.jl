# # Rung 0 — The Toy DC Walking Skeleton
#
# This page is the **reproducibility proof** of the walking skeleton: it executes the real
# [`solve_toy_dc`](@ref) end-to-end during the Documenter build, so the numbers
# below cannot silently drift from the code. It is deliberately
# minimal — one page proving the docs pipeline works. The richer per-model math docs
# are on the pages that follow.
#
# ## The per-unit base
#
# Every electrical quantity in the framework is **per-unit**: SI inputs are
# converted to per-unit exactly once, at ingestion, and never mixed with SI
# downstream. The framework ships a single documented placeholder base at a
# typical IEEE-13 distribution voltage level:
#
# ```math
# S_\text{base} = 1.0~\text{MVA}, \qquad V_\text{base} = 4.16~\text{kV}
# ```
#
# with the derived impedance and current bases
#
# ```math
# Z_\text{base} = \frac{V_\text{base}^2}{S_\text{base}}, \qquad
# I_\text{base} = \frac{S_\text{base}}{\sqrt{3}\, V_\text{base}}.
# ```
#
# This placeholder is **superseded by the real feeder fixtures** used on later pages;
# it exists here only so the toy model has a documented, sane per-unit context.

using TSODSO
using TSODSO: I_base, PerUnitBase, Z_base

base = PerUnitBase(1.0, 4.16)          # S_base [MVA], V_base [kV]
(Z_base = Z_base(base), I_base = I_base(base))   # derived bases

# ## The toy DC math
#
# Rung 0 is strictly **single-node, single-period**. There is one servable load $p_\text{load} \in [0, 1]$ (pu) and one
# import $p_\text{import} \ge 0$ (pu) drawn from the frontier node. The nodal
# balance simply pins import to load,
#
# ```math
# p_\text{import} - p_\text{load} = 0,
# ```
#
# and we maximise a toy social welfare (value of served load minus import cost):
#
# ```math
# \max_{p_\text{import},\, p_\text{load}} \; 3\, p_\text{load} - 1\, p_\text{import}.
# ```
#
# Even though there is only one node, the balance is routed through the **shared
# residual registry** `ctx.residuals[:nodal_balance]` (the residual-seam contract), so a
# branch-flow formulation contributes into the *same* expression with no
# `if formulation ==` branching. The solve goes through the `assert_solved!`
# status choke point and the balance's **dual** is the nodal price
# (the DADP consumed by the pricing pages).

# ## Building and solving a trivial feeder
#
# A single root bus, no branches — the minimal valid radial feeder. Construction
# itself validates the topology and per-unit magnitudes (an invalid feeder cannot
# exist).

buses = [Bus(1, 0.95, 1.05, true)]      # id, vmin, vmax (pu), is_root
branches = Branch{Float64}[]            # no branches at rung 0
feeder = Feeder(buses, branches, 1)     # validated on construction

# Solve end-to-end through every seam — the factory chooses the LP backend by
# problem class, so this page names **no concrete solver**:

ctx, objective, price = solve_toy_dc(feeder)

# The optimal welfare (load is valuable at 3, import costs 1, so it serves the
# full unit of load):

objective

# The nodal-balance dual — the price seam that later phases interpret as the
# distribution price:

price

# And the residual seam really was exercised: the shared residual registry holds the
# accumulated nodal-balance expression.

haskey(ctx.residuals, :nodal_balance)

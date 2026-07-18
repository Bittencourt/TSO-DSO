# Pitfalls Research

**Domain:** Julia/JuMP optimization research framework — TSO-DSO transactive energy (convex branch-flow SOCP + ADMM) and Stackelberg-Nash planning (Benders/diagonalization)
**Researched:** 2026-07-18
**Confidence:** HIGH on optimization math and solver behavior (verified against source theory + solver docs); MEDIUM on Julia performance specifics (verified against JuMP docs/discourse); MEDIUM on planning-layer cut correctness (single primary source, PSR note, plus standard L-shaped/SDDiP literature)

> This is a research/experiment library for a PhD thesis. Most failure modes here are **silent correctness bugs** that produce plausible-but-wrong numbers (prices, welfare, equilibria) rather than crashes. The single greatest risk is publishing or building on a result that is quietly wrong. Every pitfall below is oriented toward that risk: catch wrongness with an automated invariant, not with eyeballs.

---

## Critical Pitfalls

### Pitfall 1: SOCP branch-flow relaxation is inexact and nobody checks

**What goes wrong:**
The Baran-Wu DistFlow current definition `l_{i,j} = (P² + Q²)/v_i` (thesis 3.34) is nonconvex. The framework relaxes it to the SOC inequality `l_{i,j} ≥ (P² + Q²)/v_i` (3.39). The relaxed problem always solves and always returns a voltage/price profile — but if the relaxation is **inexact** at the optimum (inequality strict, `l_{i,j}·v_i > P² + Q²`), the returned `l` is a fictitious over-current, the voltages are wrong, and **the DADP/DLMP duals are physically meaningless**. The thesis is explicit (3.43-3.45, and Julia-port checklist item 5): without the LinDistFlow exactness constraints the prices are garbage, but the solver gives no error.

**Why it happens:**
- Developers implement (3.39) as the "obvious" convex model and forget the parallel loss-less LinDistFlow copy `(P̂, Q̂, v̂)` with the **upper** voltage bound (3.43, 3.45) is what forces equality.
- Standard exactness theory (Gan-Low, Farivar-Low) requires conditions that **break under high DER**: reverse power flow (net injection at a bus from PV), binding *upper* voltage limits (over-voltage from PV back-feed — exactly Case B, the 123-node voltage-constrained feeder with `V ∈ [0.9,1.1]`), and negative LMPs. These are precisely the interesting regimes this thesis targets (high PV penetration, over-voltage). The relaxation is most likely to go inexact in the very scenarios the research cares about.
- With multi-objective / welfare objectives that can *reward* inflating losses (e.g., soaking up PV), the relaxation gap can open up in a way pure cost-min OPF would not.

**How to avoid:**
- Implement the LinDistFlow exactness constraints (thesis 3.43-3.45 / IET eqs 37-42) from day one, not as an afterthought. Treat them as part of the definition of the power-flow model, not an optional add-on.
- **Automated exactness invariant, run after every solve:** compute `gap_{i,j} = l_{i,j}·v_i − (P_{i,j}² + Q_{i,j}²)` for all branches and assert `max |gap| < τ` (τ scaled to per-unit, e.g. 1e-5). This is checklist item 5 and it must be a hard test, not a manual `v₉[16]=1.0493` spot-check.
- Report the exactness residual as a first-class output of every operational solve, logged alongside the prices.
- Have a known-exact fixture (small radial feeder, no reverse flow) AND a known-hard fixture (high PV, over-voltage) so the test suite exercises both the easy and the exactness-stressing regime.

**Warning signs:**
- `l·v` noticeably exceeds `P²+Q²` on any branch.
- Voltages pinned at the *upper* bound with PV back-feed.
- DLMPs that don't decompose cleanly (loss/congestion/voltage terms don't sum to the nodal price).
- Prices that look "off" — e.g., negative where you expected positive, or insensitive to congestion.

**Phase to address:** SOCP branch-flow model phase (first AC power-flow rung of the abstraction ladder). The exactness test is a gating acceptance criterion for that phase.

---

### Pitfall 2: ADMM converges to the wrong thing (or doesn't converge) at congested/voltage-binding hours

**What goes wrong:**
The ADMM outer loop updates prices as duals (`λ_j^{k+1} = λ_j^k + ρ·R_{p,j}`). Several distinct failures masquerade as each other:
1. **Slow crawl** — residuals decrease but take thousands of iterations (thesis reports ~28; if you see 500+, something is wrong).
2. **Oscillation / limit cycle** — residuals bounce, never settling, typically when `ρ` is too large or the aggregator QP and network SOCP are badly scaled relative to each other.
3. **False convergence** — the primal residual `R_{p,j}` hits tolerance but the *dual* residual (change in `λ` between iterations, i.e. coupling variable movement) is still large, so you stop at a non-optimal, non-consensus point. The reported DADP is then not the true DLMP.
4. **Convergence to a point where the SOCP relaxation is inexact** — ADMM "converges" but the underlying network subproblem never tightened (compounds Pitfall 1).

Congested hours (Case A) and voltage-binding hours (Case B) are where the coupling constraints bind hardest and convergence is slowest/most fragile.

**Why it happens:**
- Fixed `ρ=1000` copied from the thesis without realizing it is tuned to that problem's per-unit scaling and units (¢$/kWh, MW). Change units or feeder size and the tuned `ρ` is wrong.
- Stopping on the primal residual alone (thesis 2.6 states "converge when |R| ≤ ε ∀t,j") without also monitoring the dual residual — this is the textbook Boyd et al. ADMM stopping-criterion mistake. Primal feasibility ≠ optimality.
- No warm-starting between hours/iterations, so every subproblem solve starts cold.
- ADMM on the **SOCP** network subproblem is not guaranteed to converge as cleanly as on a QP; the conic subproblem needs its own solver accuracy to be tight or the outer residuals never settle.

**How to avoid:**
- Track **both** primal residual (`R_{p,j}`, `R_{q,j}` — consensus violation) and dual residual (`ρ·(z^{k+1} − z^k)` — change in coupling flows). Stop only when both are below tolerance. This is the single most important correctness fix for the ADMM layer.
- Implement residual balancing / adaptive `ρ` (Boyd §3.4.1: increase `ρ` when primal residual dominates, decrease when dual dominates, e.g. factor 2, ratio threshold 10). Do not hard-code `ρ=1000`.
- Normalize the problem to per-unit before choosing `ρ` so the penalty is scale-invariant across feeders.
- **Cross-validate against the monolithic solve.** The project ships both centralized and ADMM strategies precisely so ADMM's welfare and prices can be checked against the monolithic optimum on small cases. Make "ADMM optimum matches centralized optimum to tolerance" an automated test on every fixture small enough to solve monolithically.
- Warm-start each subproblem from the previous iteration's solution.
- Cap iterations and **fail loudly** (not silently return the last iterate) if the cap is hit.

**Warning signs:**
- Iteration count far above the ~28 baseline.
- Residual plots that plateau above tolerance or oscillate.
- ADMM welfare ≠ centralized welfare on a small feeder.
- DADP differs from the monolithic dual of the active-balance constraint.

**Phase to address:** ADMM decomposition phase. The centralized solve must exist and be validated *before* ADMM so it can serve as ground truth.

---

### Pitfall 3: Unit and per-unit scaling errors silently corrupt prices and utilities

**What goes wrong:**
The model mixes electrical quantities (MW, MVA, kV, squared per-unit voltages), monetary quantities (thesis uses **¢$/kWh** for `λ_max/min/med`; wholesale `λ₀` may be in **$/MWh**), and quadratic utility coefficients `a, b` derived from those prices (3.13-3.14, 3.17-3.20). A single unit mismatch — e.g. mixing ¢/kWh with $/MWh (a factor of 10× or 100×), or feeding MW into a coefficient calibrated for kW (`P_max_b = 5 kW` vs feeder MW quantities) — produces an objective where one term dwarfs the others. The optimizer then effectively ignores the small term. The solve succeeds; the welfare number and prices are quietly off by orders of magnitude.

**Why it happens:**
- The thesis freely mixes ¢$/kWh (prices), kW (device power, `P_max_b=5`), and MW/MVA (feeder aggregates). Aggregation (3.22) sums house-level kW into nodal MW; the utility coefficients must be consistent with whichever unit the power variable carries.
- Quadratic coefficient `b = (λ_max − λ_min)/(P_max − P_min)` (3.14) has units of price/power; if `P` is in different units at device vs aggregator level, `b` is wrong after aggregation.
- Squared-voltage variables (`v = V²`) are easy to confuse with voltage; bounds `V²_min ≤ v ≤ V²_max` (0.95² vs 0.95) are a classic off-by-square bug.

**How to avoid:**
- **Adopt a single per-unit system** (common `S_base`, `V_base`) for all electrical quantities and a single monetary unit ($/MWh recommended) throughout the optimization layer. Convert at the data-ingestion boundary only, once.
- Encode units in the data layer (e.g. Unitful.jl at ingestion, or at minimum a documented convention + assertions on magnitudes) and strip to plain floats before the hot solve loop.
- Add magnitude sanity assertions: nodal prices within a plausible band (e.g. 0.1×–10× wholesale), voltages `v ∈ [0.81, 1.21]` (i.e. `[0.9², 1.1²]`), currents non-negative.
- Write down, in the model docs, the exact units of every variable and coefficient. This is a documentation-drift guard (see Pitfall 10).

**Warning signs:**
- Welfare or prices off by a clean factor of 10, 100, or 1000.
- One objective term (e.g. wholesale cost `λ₀ᵀp₀`) dominating so utilities are ignored, or vice versa.
- Voltages near 1.0 when you expected `v ≈ 1.0` (or ~0.81/1.21 confusion).
- ADMM `ρ` that "should" work needing wild retuning.

**Phase to address:** Data/scenario layer phase and the first optimization model phase — establish the per-unit convention before any model is built on top of it. Cheap to fix early, expensive later.

---

### Pitfall 4: Solver mismatch — using Ipopt on the SOCP (or trusting a low-accuracy conic point)

**What goes wrong:**
The operational model is convex (LP + QP + SOCP). Several solver traps:
1. **Ipopt on the SOCP as if it were a generic NLP.** Ipopt will solve the convex-but-nonlinear form, but it treats the SOC as a smooth constraint, can stall near the cone boundary, returns local-solver tolerances, and gives KKT duals whose interpretation as DLMPs needs care. It also does not exploit conic structure → slower, less accurate at scale.
2. **Conic solver returns a "low-accuracy" / "almost solved" status** (SCS especially, sometimes Clarabel on ill-conditioned problems) and the code reads it as optimal. A low-accuracy conic point can violate the exactness gap (Pitfall 1) and yield bad duals.
3. **HiGHS asked to do SOCP.** HiGHS supports LP, MILP, and convex QP — **not** SOCP (verified). Handing it the cone silently fails or errors; developers then reformulate incorrectly.
4. **Gurobi/Mosek licensing leaking into a "pure open-source" pipeline** — a fixture or default quietly depends on a commercial solver, so results are not reproducible by collaborators without a license, violating a hard project constraint.

**How to avoid:**
- Route problem classes to appropriate solvers behind the solver-abstraction: SOCP → **Clarabel** (native conic, actively maintained, good accuracy) or SCS/ECOS; QP → HiGHS/Clarabel; MILP masters (planning layer) → HiGHS; NLP-only → Ipopt. Ipopt is a *cross-check*, not the primary SOCP solver.
- **Always check `termination_status(model) == OPTIMAL` and `primal_status == FEASIBLE_POINT`** — never assume. For conic solvers, also assert the solver's own accuracy/duality-gap is tight before trusting duals. Reject `ALMOST_OPTIMAL`/`SLOW_PROGRESS` unless explicitly whitelisted for a diagnostic run.
- Solve the same small fixture with two solvers (e.g. Clarabel and Ipopt, or Clarabel and Mosek if available) and assert objective + exactness gap agree. Cross-solver agreement is the strongest correctness signal available.
- Keep the default pipeline commercial-solver-free; make Gurobi/Mosek opt-in via config, and have CI run the open-source path. Pin the open-source path as the reproducibility baseline.
- Tighten conic solver tolerances when duals feed downstream (ADMM prices, Benders cuts) — default SCS tolerance (1e-4) is often too loose for meaningful DLMPs.

**Warning signs:**
- Termination status other than `OPTIMAL` being ignored.
- Different objective values from different solvers on the same model.
- Exactness gap (Pitfall 1) that shrinks when you tighten solver tolerance → you were reading a loose point.
- A collaborator can't reproduce a result → hidden Gurobi/Mosek dependency.

**Phase to address:** Solver-abstraction phase (early) sets routing and status-checking discipline; revisited in the SOCP and ADMM phases for accuracy requirements.

---

### Pitfall 5: Rebuilding JuMP models inside loops (ADMM iterations, hours, scenarios, diagonalization sweeps)

**What goes wrong:**
The natural way to write ADMM/rolling-horizon/Benders is a loop that constructs a fresh JuMP model each iteration (`model = Model(); @variable ...; @constraint ...`). At the scale this project targets (150k+ variables at full feeder × 24h × houses, plus many ADMM iterations × scenarios × diagonalization sweeps), model *construction* and MOI copy-to-solver overhead dominate runtime and blow up memory/GC. Experiments that should take minutes take hours; large cases OOM.

**Why it happens:**
- ADMM changes only the dual `λ_j` (an objective coefficient / RHS) between iterations; nothing structural changes, yet the whole model is rebuilt.
- Benders adds one cut per iteration to a master whose structure is otherwise fixed.
- Rolling-horizon/MPC shifts parameters, not structure.
- Rebuilding is the path of least resistance and works fine on toy cases, so the problem only surfaces at scale — after the architecture is set.

**How to avoid:**
- Build each subproblem model **once**; update only what changes between solves:
  - ADMM: update the objective coefficients / parameters for `λ_j`, `μ_j`, and the `(ρ/2)‖R‖²` terms in place. Use `set_normalized_coefficient` / `set_objective_coefficient`, or `MOI.Parameter` / ParametricOptInterface for the dual and `ρ` values.
  - Benders: `@constraint` to *add* cuts to a persisted master (constraints add cheaply); never rebuild the master.
  - Rolling horizon: parameterize the horizon RHS/costs; see JuMP's own rolling-horizon tutorial.
- **Caveat (verified):** ParametricOptInterface is not always faster than rebuild — for some structures (e.g. big-M changes) POI has been measured slower than reconstruction (POI issue #108). Benchmark in-place vs rebuild on a representative case before committing. The reliable win is persisting the model and using solver-native parameter/coefficient updates + warm starts.
- Keep model construction out of the hot loop and warm-start solves from the previous iterate.
- Design the subproblem API around "build once, update, resolve" from the start — retrofitting in-place updates into a rebuild-per-iteration architecture is a rewrite.

**Warning signs:**
- Runtime scaling with (model size × iterations) rather than (solve time × iterations).
- Heavy GC / rising memory across ADMM iterations.
- `@time`/profiler showing time in model construction / `MOI.copy_to`, not in the solver.

**Phase to address:** ADMM decomposition phase for the operational loop; planning phase for Benders/diagonalization. The subproblem interface designed in the architecture phase should assume in-place updates.

---

### Pitfall 6: Julia type instability, global scope, and allocation in the numerical core

**What goes wrong:**
Classic Julia performance killers appear in the data-generation (Markov chains at 1-min resolution) and the ADMM/Benders driver loops: code written in global scope, type-unstable functions (variables changing type, untyped struct fields, `Any` containers), and per-iteration allocation. Result: 10-100× slowdowns that make large experiments impractical and are invisible on toy cases.

**Why it happens:**
- Research code is often written script-style in the global scope of a file/REPL; globals are type-unstable by default in Julia.
- Struct fields left untyped (`struct Feeder; data; end`) or abstractly typed (`Vector{Any}`) break specialization.
- The Markov-chain device/PV simulation (thesis 2.8) runs many fine-grained steps and is easy to write allocation-heavy.

**How to avoid:**
- Wrap all hot code in functions; avoid non-`const` globals. Pass data as arguments.
- Concretely type struct fields; use `@code_warntype` / `JET.jl` on the ADMM step, the subproblem builders, and the Markov simulator.
- Preallocate and reuse buffers in the simulation and residual computations; profile with `@profile` / `Profile.Allocs`.
- This is a *supporting* concern, not the core research risk — do not prematurely optimize the model math. Optimize the driver loops and data generation once correctness is established and a large case is slow.

**Warning signs:**
- `@code_warntype` shows red `Any`/`Union` types in hot functions.
- Allocation counts growing with problem size in the driver loop.
- Toy cases instant, large cases surprisingly slow beyond what solve time explains.

**Phase to address:** Not a gating phase concern early; address in a performance-hardening pass once the operational layer is correct and the first large (123-node) case is exercised.

---

### Pitfall 7: Wrong-sign or misidentified duals — the DADP is not what you think

**What goes wrong:**
The entire transactive scheme hinges on `λ_j` being the dual of the **nodal active-power balance** (thesis 3.31), with a specific sign convention, and on the DLMP decomposing into energy + loss + congestion + voltage terms. Two failure modes:
1. **Sign/convention error:** JuMP's dual sign depends on constraint sense and objective sense (max vs min). The model *maximizes* welfare (3.38); getting the dual sign wrong flips the price signal (charges look like credits). The result is internally consistent and passes feasibility — it's just backwards.
2. **Reading the dual of the wrong constraint** (e.g. the reactive balance 3.32, or the LinDistFlow copy, or a reformulation-introduced constraint) and labeling it the DADP.
3. **In ADMM, the recovered `λ_j` is the penalty-update dual**, which only equals the true LP/QP dual at convergence *and* when the relaxation is exact. If either fails, the "price" is not the DLMP.

**How to avoid:**
- Pin down the sign convention with a hand-computed 2-bus example where the price is known analytically; assert the sign in a test.
- **Validate the ADMM dual against the monolithic dual:** at convergence, `λ_j` from ADMM must equal `dual(active_balance_constraint)` from the centralized SOCP solve, to tolerance. This is the definitive check and ties directly to shipping both solve strategies.
- Verify the **DLMP decomposition adds up**: energy + loss + congestion + voltage components must reconstruct the nodal price (thesis §4 / DLMP decomposition). A decomposition that doesn't sum to the total price signals a sign or attribution bug.
- Cross-check economic sanity: at PV over-generation the DADP should fall *below* the MEM price; at congestion it should rise *above* (thesis §4). Encode these as directional assertions on the case fixtures.

**Warning signs:**
- Prices below wholesale during congestion, or above during PV glut (backwards).
- DLMP components not summing to the nodal price.
- ADMM dual ≠ centralized dual at convergence.

**Phase to address:** DLMP extraction/validation phase, immediately after both centralized and ADMM solves exist.

---

### Pitfall 8: Infeasibility masking and silently wrong constraints

**What goes wrong:**
A model bug (transposed incidence, wrong branch orientation parent→child, a device window `T_{h,d}` that can't be met, an over-tight voltage/thermal bound, an initial SOC that's infeasible) makes the true model infeasible. But: (a) a slack/penalty added "for robustness" absorbs the infeasibility and returns a meaningless optimum; (b) the ADMM outer loop keeps iterating on an infeasible-per-hour subproblem and reports the last iterate; (c) `termination_status` is `INFEASIBLE` but the code doesn't check and reads stale `value(...)` (often zeros or garbage). All three produce numbers that look like results.

**Why it happens:**
- Radial branch orientation (parent `i` → child `j`, thesis §1) is easy to get backwards on some branches; the balance constraints (3.31-3.32) then describe a different network.
- Elastic penalties/slacks are added early to "get it running" and never removed.
- Device temporal-coupling constraints (thermostatic 3.2, programmable window 3.4, SOC 3.6) with real data can be genuinely infeasible for some houses.
- Not checking termination status (see Pitfall 4) means infeasibility is read as a solution.

**How to avoid:**
- Assert `termination_status == OPTIMAL` (or a whitelisted status) after **every** solve; never call `value()` on a non-optimal model. Fail loud.
- No hidden slacks in the correctness path. If relaxation/slack is needed for diagnostics, make it explicit, penalized, and *reported* (nonzero slack = flagged warning), never silent.
- Validate network topology on load: radial structure (N nodes → N−1 branches, connected, one root at node 0), consistent parent→child orientation, incidence matrix rank.
- Use JuMP/solver IIS / conflict tools (`compute_conflict!` where supported) to localize infeasibility during development.
- Feasibility unit tests per device model on synthetic edge cases (tight windows, extreme SOC).

**Warning signs:**
- Results that don't change when you change an input that should matter.
- Nonzero slack/penalty variables in a "feasible" solve.
- Objective exactly 0 or suspiciously round.
- `INFEASIBLE`/`INFEASIBLE_OR_UNBOUNDED` in solver logs that the driver ignored.

**Phase to address:** Every optimization phase; establish the status-check + no-hidden-slack discipline in the very first model phase as a coding standard.

---

### Pitfall 9: Planning layer — invalid Benders cuts, LP duals from MIP subproblems, and binary-expansion granularity error

**What goes wrong:** (Deferred to the planning milestone, but the architecture must not preclude correctness.)
1. **Standard Benders cuts using LP duals of a subproblem that is actually a MIP.** The PSR note is explicit: the cut representation is exact only for continuous/LP (or binary) subproblems. When the second-level (transmission reinforcement) has integer investments, LP-relaxation duals produce **invalid cuts** that can cut off the true optimum — the Benders master then converges confidently to a wrong equilibrium. Integer subproblems require **Lagrangian / integer L-shaped cuts** (multipliers from maximizing the Lagrangian of the copy constraints, per the SDDiP / Zou-Ahmed-Sun and Bansal-Küçükyavuz references), not LP duals.
2. **Binary-expansion granularity error.** Continuous interconnection flow `z_{y,s}` is discretized as `z = Δ·Σ n·2^ĵ` with `Δ = z̄/(2^{J+1}−1)`. Too few bits → coarse `Δ` → the "coupling flow" the leader sees is quantized, biasing the equilibrium; the error is silent and only appears as a discrepancy vs a fine-grid or continuous reference.
3. **Coupling dual `π_s` misread** — it is the marginal reinforcement cost of a unit of interconnection flow (≈ TUST / additional transmission tariff, ≈ DLMP link). Wrong sign or wrong constraint here breaks the whole value-of-flexibility story.

**Why it happens:**
- Benders is usually taught with LP subproblems; the integer case is a genuinely different algorithm and easy to conflate.
- Binary expansion is a modeling convenience whose accuracy cost is invisible unless deliberately measured.
- The PSR note itself flags the LP-only validity caveat and the Δ-granularity approximation.

**How to avoid:**
- Gate cut generation on subproblem class: LP/continuous → classical Benders duals; MIP → Lagrangian/integer L-shaped cuts. Make the cut generator explicitly aware of which regime it's in; assert it.
- Validate the planning layer on a tiny case solvable as a **monolithic MILP** (the full integrated problem 1) and require Benders/diagonalization to reproduce that optimum. Same "decomposition matches monolith" discipline as the operational ADMM check.
- Treat `Δ` (bit count `J`) as a convergence parameter: run a granularity sweep and report the equilibrium's sensitivity to it; document the residual approximation error.
- Verify cut validity: a valid cut must never exceed the true `α({z})` at any evaluated point — assert `α^k ≥ cut(z^k)` at generated points.

**Warning signs:**
- Benders lower bound crossing/exceeding a known upper bound (invalid cut).
- Equilibrium that shifts materially as you add bits to the expansion.
- Master converges but monolithic MILP on a small case disagrees.

**Phase to address:** Planning-layer milestone (deferred). Architecture phase must keep the operational subproblem swappable as a Benders subproblem (coupling variable = interconnection flow) so this is buildable later without rework.

---

### Pitfall 10: Diagonalization / Nash equilibrium non-convergence, non-uniqueness, and leader/follower ambiguity

**What goes wrong:** (Planning milestone.)
1. **Gauss-Seidel diagonalization (optimize each distributor in turn, fix others) may not converge** — it can cycle or diverge; it has no general convergence guarantee for non-potential games. Researchers often assume a fixed point exists and is reached.
2. **Non-uniqueness of Nash equilibria** — even if it converges, the equilibrium found depends on initialization and sweep order. Reporting "the" equilibrium is wrong; there may be several, and the framework can silently pick different ones run-to-run (a reproducibility hazard).
3. **Leader/follower labeling ambiguity** — the PSR note itself labels leader/follower inconsistently once (distributor should be leader). Hard-coding the wrong role inverts the Stackelberg structure: you'd solve the follower as if it moved first, giving a different (wrong) equilibrium concept entirely.

**Why it happens:**
- Diagonalization is intuitive and easy to code; its convergence caveats are easy to ignore.
- Source-document ambiguity (flagged in THEORY-papers.md cautionary flags) invites a coin-flip implementation.
- Equilibrium multiplicity is a subtle game-theory point, not an obvious software bug.

**How to avoid:**
- Confirm distributor = leader with the author before hard-coding the Stackelberg direction; encode the role assignment as an explicit, documented parameter, not an implicit code structure.
- Detect diagonalization non-convergence: cap sweeps, monitor the max change in flows across a full round, and **fail loud** with diagnostics if it doesn't contract. Do not report a non-converged iterate.
- Probe equilibrium (non-)uniqueness: run diagonalization from multiple seeds / sweep orders and report whether they agree. Log the initialization with the result (reproducibility).
- Where tractable, validate against the monolithic MILP optimum (Pitfall 9) and, on small cases, against a BilevelJuMP.jl KKT single-level reduction as an independent check.

**Warning signs:**
- Flow changes across sweeps not shrinking.
- Different seeds → different reported equilibria.
- Results sensitive to which distributor is optimized first.

**Phase to address:** Planning-layer milestone (deferred). Note the leader/follower parameterization as an architecture requirement now.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Skip LinDistFlow exactness constraints, ship bare SOC relaxation | Fewer constraints, faster to code | Prices meaningless whenever exactness fails (high-DER cases = the research target) | Never — it defines the model |
| Hard-code `ρ=1000`, `ε=5e-5` from the thesis | Reproduces the paper's toy run | Breaks on any rescaled/larger feeder; hides convergence bugs | Only for reproducing the exact paper fixture |
| Rebuild JuMP model each ADMM/Benders iteration | Simplest possible loop | Runtime/memory blow-up at 150k+ vars; architecture rewrite to fix | Toy-case prototyping only |
| Stop ADMM on primal residual alone | Matches the thesis's stated criterion | False convergence, wrong DLMPs | Never (always add dual residual) |
| Add slack to "just get it feasible" | Unblocks a stuck solve | Silent wrong answers; masks real infeasibility | Only as an explicit, penalized, *reported* diagnostic |
| Ipopt as the one solver for everything | One dependency, always "works" | Loose duals, no conic accuracy, slow at scale | As a cross-check, never as sole SOCP solver |
| LP-relaxation Benders cuts for integer planning subproblem | Reuses classical Benders code | Invalid cuts → wrong equilibrium | Only if the subproblem is genuinely LP/continuous |
| Coarse binary expansion (few bits) for interconnection flow | Small, fast MILP | Quantized coupling biases the equilibrium silently | Only with a reported granularity-sensitivity study |
| Untyped structs / global-scope driver scripts | Fast to prototype | 10-100× slowdown at scale | Prototyping; must be fixed before large cases |

## Integration Gotchas

External "services" here = solvers and the numerical/data stack.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| HiGHS | Handing it an SOCP | HiGHS = LP/MILP/convex-QP only (verified); route cones to Clarabel/SCS/ECOS |
| Clarabel/SCS (conic) | Trusting `ALMOST_OPTIMAL`/loose duals as the DLMP | Assert `OPTIMAL` + tight duality gap; tighten tolerance when duals feed ADMM/Benders |
| Ipopt | Using it as the primary SOCP solver | Use as an independent cross-check; primary SOCP solver is conic |
| Gurobi/Mosek | Leaking into the default pipeline → non-reproducible | Commercial solvers opt-in behind the abstraction; CI runs the open-source path |
| JuMP duals | Assuming a sign without checking objective/constraint sense | Verify sign on a hand-solved 2-bus case; assert in tests |
| ParametricOptInterface | Assuming in-place is always faster | Benchmark vs rebuild (POI can be slower, issue #108); rely on persisted model + native coefficient updates + warm start |
| Solver environment | Unpinned solver versions → drifting numerics | Pin everything via `Manifest.toml`; record solver versions with results |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Rebuild model per iteration | Time in `MOI.copy_to`, GC churn | Build once, update coefficients, warm start | Full feeder × 24h × houses (150k+ vars) × many iterations |
| No warm-starting across ADMM iters / hours / scenarios | Every solve cold, iteration count high | Warm start from previous iterate | Large feeders, many ADMM iterations |
| Cold Benders master rebuild | Cuts re-added from scratch each iter | Persist master, add one `@constraint` per cut | Planning layer with many cuts/scenarios |
| Type-unstable driver + Markov simulator | Allocation grows with size, `@code_warntype` red | Functions not globals, concrete types, preallocate | 1-min resolution simulation over many houses/days |
| Solving all hours/scenarios serially | Wall-clock linear in scenario count | Parallelize independent subproblems (AGR-OPT per node, DSO-OPT per hour, scenarios) | Multi-scenario stochastic extension |
| Over-tight conic tolerance everywhere | Slow solves | Tight tolerance only where duals matter | Large SOCP subproblems |

## Security Mistakes

Not a web/production system; "security" here maps to **research integrity and reproducibility**.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Unpinned environment (`Project.toml` without `Manifest.toml`) | Results not reproducible; solver-version-dependent numbers | Commit `Manifest.toml`; record Julia + solver versions with every experiment |
| Unseeded Markov data generation | Non-reproducible scenarios; can't rerun a published figure | Explicit seeds threaded through the RNG; log seed with results |
| Commercial-solver-dependent "results" | Collaborators without a license can't verify | Open-source default path validated in CI |
| Results not tied to code+data version | Can't trace a thesis figure back to what produced it | Stamp outputs with git commit + config hash + seed |

## UX Pitfalls

"Users" = the PhD researcher and collaborators; UX = researcher ergonomics and trust.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Silent wrong results (no invariant checks) | Researcher builds a paper on a bad number | Automated exactness/dual/decomposition invariants reported on every run |
| Convergence/exactness diagnostics buried | Can't tell a good solve from a bad one | Surface residuals, exactness gap, iteration count, termination status as first-class outputs |
| Model math drifting from the docs | Reader can't trust the "documented assumptions" (a hard project requirement) | Keep equation numbers (3.31 etc.) as code references; doc-tests that check formulas |
| One giant model, no abstraction ladder | Can't isolate where a bug entered | DC/linear → LinDistFlow → SOCP rungs with the same interface, each validated |

## "Looks Done But Isn't" Checklist

- [ ] **SOCP solve:** returns voltages/prices — but is the relaxation *exact*? Verify `max|l·v − (P²+Q²)| < τ` on every branch.
- [ ] **ADMM convergence:** primal residual under tolerance — but is the *dual* residual too, and does welfare match the centralized solve?
- [ ] **DADP prices:** extracted — but correct sign, and do the DLMP components sum to the nodal price?
- [ ] **Any solve:** produced `value()`s — but was `termination_status == OPTIMAL` actually checked?
- [ ] **Battery model:** no binaries (App. C proof) — but verified `p_ch·p_dch ≈ 0` at the optimum on real data?
- [ ] **Feasibility:** solved — but are there hidden nonzero slacks masking infeasibility?
- [ ] **Units:** runs — but per-unit consistent across device (kW) → aggregator (MW) → price (¢/kWh vs $/MWh)?
- [ ] **Reproducibility:** script runs — but with committed `Manifest.toml` and logged seed, on the open-source solver path?
- [ ] **Benders (planning):** converges — but are cuts valid for the subproblem class (LP vs MIP), and does it match the monolithic MILP on a small case?
- [ ] **Diagonalization (planning):** returns an equilibrium — but did it actually converge, and is it seed/order-independent?
- [ ] **Cross-validation:** ADMM/Benders result — checked against the monolithic solve on every small-enough fixture?

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Inexact SOCP relaxation | LOW-MEDIUM | Add/repair LinDistFlow exactness constraints (3.43-3.45); re-verify gap. Localized fix if model is modular. |
| ADMM false convergence | LOW | Add dual-residual stopping + adaptive `ρ`; re-validate against centralized. |
| Unit/scaling error | MEDIUM | Introduce single per-unit system at data boundary; audit every coefficient; re-run fixtures. Painful if scattered. |
| Wrong dual sign | LOW | Fix sign convention, add hand-solved regression test. |
| Rebuild-per-iteration architecture | HIGH | Refactor subproblem API to build-once/update — approaches a rewrite if pervasive. Prevent via early interface design. |
| Invalid Benders cuts (LP duals on MIP) | MEDIUM-HIGH | Swap in Lagrangian/integer-L-shaped cut generator; re-derive; validate vs monolith. |
| Non-converging diagonalization | MEDIUM | Add convergence detection + damping; investigate uniqueness; may need reformulation. |

## Pitfall-to-Phase Mapping

Phase names are logical (roadmap not yet fixed); ordering follows the abstraction ladder (toy → SOCP → devices → centralized → ADMM → DLMP → planning).

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. SOCP inexactness | SOCP branch-flow model | Automated `l·v ≈ P²+Q²` gap test on easy + high-PV fixtures |
| 2. ADMM convergence | ADMM decomposition (after centralized exists) | Primal+dual residual stop; ADMM welfare = centralized welfare |
| 3. Unit/per-unit scaling | Data/scenario layer + first model | Magnitude assertions; single documented per-unit system |
| 4. Solver mismatch / loose duals | Solver-abstraction (early), revisited SOCP/ADMM | Status checks; cross-solver objective agreement |
| 5. Model rebuild in loops | ADMM + planning; interface in architecture | Runtime scales with solve-time not build-time; profiler |
| 6. Julia type instability | Performance-hardening pass (post-correctness) | `@code_warntype`/JET clean on hot loops |
| 7. Wrong-sign / misidentified DADP | DLMP extraction/validation | ADMM dual = centralized dual; DLMP components sum; economic-direction assertions |
| 8. Infeasibility masking | Every model phase (standard from first) | `OPTIMAL` asserted; no silent slacks; topology validation |
| 9. Benders cut validity / granularity | Planning milestone (arch keeps subproblem swappable) | Cut ≤ true α; match monolithic MILP; Δ-sensitivity sweep |
| 10. Diagonalization / leader-follower | Planning milestone (role param in arch now) | Convergence detection; seed-independence; author-confirmed roles |

## Sources

- Project source theory (equation-level): `.planning/research/THEORY-thesis.md`, `.planning/research/THEORY-papers.md`, `.planning/PROJECT.md` — Palacios PhD thesis (UNSJ 2022), IET GTD 2019, PSR N1-N2 note. HIGH (primary sources for the models and their stated caveats).
- SOCP branch-flow exactness theory: Farivar & Low, "Branch Flow Model: Relaxations and Convexification" (IEEE TPS 2013); Gan, Li, Topcu, Low, "Exact Convex Relaxation of OPF in Radial Networks" — exactness fails under reverse flow / binding upper voltage. HIGH (established literature).
- ADMM tuning / stopping (primal+dual residuals, adaptive ρ): Boyd, Parikh, Chu, Peleato, Eckstein, "Distributed Optimization and Statistical Learning via ADMM" (2011), §3.3-3.4. HIGH.
- HiGHS capabilities (LP/MILP/convex QP, no SOCP): HiGHS docs / Wikipedia — verified via WebSearch 2026-07-18. HIGH.
- Clarabel conic solver: Clarabel docs (Context7 `/oxfordcontrol/clarabeldocs`). HIGH.
- JuMP in-place updates / ParametricOptInterface performance caveat (issue #108) and rolling-horizon tutorial: jump.dev docs + ParametricOptInterface.jl repo — verified via WebSearch 2026-07-18. MEDIUM-HIGH.
- Integer L-shaped / Lagrangian cuts for MIP subproblems: Zou, Ahmed, Sun (SDDiP, 2019); Bansal & Küçükyavuz (2025) — cited in PSR note; LP duals invalid for integer subproblems. MEDIUM (single project source + standard literature).
- Julia performance (type stability, globals, allocation): Julia performance-tips docs; standard practice. HIGH.

---
*Pitfalls research for: Julia/JuMP TSO-DSO transactive-energy + Stackelberg-Nash optimization research framework*
*Researched: 2026-07-18*

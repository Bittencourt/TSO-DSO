# Domain Pitfalls: v5.0 Aggregator Layer at Scale

**Domain:** Transactive-energy research bench (Julia/JuMP, convex SOCP feeder, DADP duals as prices, DSO-aggregator ADMM). This file covers only pitfalls of ADDING the v5.0 features to the existing framework.
**Researched:** 2026-10-09
**Overall confidence:** MEDIUM. Project-history items are HIGH (taken from PROJECT.md and RETROSPECTIVE.md). Julia threading, convex-relaxation and economics items rest on established practice and training knowledge. Nothing was run and no live docs were re-checked, so each is flagged for a doc or measurement check at implementation time.

Phase names below are suggestions for the roadmapper:
- **P-SCALE**: parallel ADMM, 784-house population, 8500 run
- **P-ACTOR**: profit-max and multi-node aggregators, behavioural response
- **P-SETTLE**: settlement and equity
- **P-DEV**: EV, heat pump, Volt-VAR
- **P-REPRO**: Case A magnitude

---

## Critical Pitfalls

### C1: Sharing a JuMP model or Clarabel optimizer across threads
**What goes wrong:** ADMM subproblems are build-once and re-solved with Parameters. Threading over them with `Threads.@threads` while mutating one shared model, or sharing the `ModelContext` or retry-ladder state, corrupts the model or crashes. A related variant is a shared `AdmmState` written from several tasks.
**Why it happens:** JuMP and MOI models are not thread-safe for modification, and solves mutate solver state. The v4.0 mutable `AdmmState` and the "restore conditioning per draw" ladder are global-ish mutable state.
**Consequences:** Rare segfaults, wrong duals, silently contaminated retry or escalation state (a later solve inherits an earlier solve's loosened tolerances, the same class as the v4.0 lesson).
**Prevention:**
- One model per aggregator (or per fixed chunk), built and owned by exactly one task for the whole solve. Never mutate a model from a task that does not own it.
- Make the retry or escalation ladder per-model state, not module-global.
- Write results only into pre-allocated slots indexed by aggregator ID. Do not use `push!` on a shared vector.
- Keep a serial reference path (`nthreads=1`) that stays the canonical default.
**Detection:** Results differ between `-t 1` and `-t N` beyond solver tolerance. Intermittent crashes. A liveness regression that varies only the thread count.
**Phase:** P-SCALE (first plan, before anything else is parallelized).

### C2: Nondeterminism breaks bit-for-bit reproducibility (and the canary)
**What goes wrong:** Parallel ADMM changes floating-point summation order (residual norms, nodal aggregation `Σ p_ag`). The knife-edge canary (`iters=56`, `welfare=-4823.66604824162`) and the pinned goldens shift. Someone is then tempted to re-pin, which is forbidden.
**Why it happens:**
- Dynamic scheduling, `@threads :dynamic`, and `threadid()`-indexed buffers (tasks can migrate between threads).
- Atomic or locked accumulation in completion order.
- Thread-count-dependent chunking.
- Clarabel multithreaded linear algebra, if a threaded KKT backend is ever enabled.
**Consequences:** The "seeded, bit-for-bit" core-value claim is false for the parallel path. Residual-based stopping flips by one iteration.
**Prevention:**
- Parallelize only the independent solve; reduce serially afterwards, in fixed aggregator-index order.
- Use static chunking that does not depend on thread count, or accumulate per-aggregator and then sum in index order. Never `threadid()`-index buffers.
- Parallel mode is opt-in. The default path stays serial and byte-identical, as in the v1 to v3 rule. The canary and goldens must never be re-pinned.
- Add a test asserting parallel and serial runs give identical `iters` and bit-identical welfare and prices. Only if bit-equality is demonstrably unachievable, document the tolerance and state it explicitly, measured rather than picked.
- Use `sub_seed`-style per-aggregator seeds derived from the aggregator ID, not from the task or thread. (Note the existing deferred debt: `sub_seed` cross-version hash stability.)
**Detection:** `iters` differs run to run. Canary moves under `-t 4`. Results differ across machines with different core counts.
**Phase:** P-SCALE.

### C3: BLAS and solver thread oversubscription
**What goes wrong:** Julia threads times BLAS threads times any threaded linear solver oversubscribes the cores. Wall-clock gets slower than serial, and memory churn rises.
**Why it happens:** OpenBLAS defaults to all cores. Dense pieces (device models, small QPs) call BLAS inside every Julia thread.
**Consequences:** Parallel speedup under 1x, noisy timings that make the measured 8500 results (solve time) untrustworthy, and nondeterminism if BLAS reductions are threaded.
**Prevention:**
- Call `LinearAlgebra.BLAS.set_num_threads(1)` inside the parallel region or at startup of parallel mode, and restore it afterwards.
- Record `Threads.nthreads()` and BLAS threads in the provenance stamp (DrWatson `tagsave`).
- Benchmark serial vs 2/4/8 threads on the 784-house case before claiming a speedup.
- Check which Clarabel linear-solver backend is used (default QDLDL is single-threaded). Do not enable a threaded backend without re-checking C2.
**Detection:** `top` shows more than 100% x nthreads. Speedup below ~ideal, or negative.
**Phase:** P-SCALE. **Confidence:** MEDIUM (verify Clarabel backend defaults in current docs).

### C4: Parallel peak memory multiplies the existing memory wall
**What goes wrong:** IEEE-8500 already OOMs (earlyoom-kill at d=0.25 T=24 around 10.4 GiB on a 15.9 GB host). Parallel aggregator solves hold N live solver factorizations at once. Peak is roughly serial peak times concurrency, so the headline run dies sooner.
**Why it happens:** Build-once keeps every aggregator's model and Clarabel state resident (that is the design). Parallelism adds simultaneous KKT factorization workspaces. About 3.4 GiB of T=10 loop growth is still unattributed. GC pressure rises with threads, and Julia GC may not return memory to the OS.
**Consequences:** Another unmeasured headline run, which would be a SCALE-05 repeat. Worse, the OOM kill may look like a solver failure.
**Prevention:**
- Measure first: attribute the 3.4 GiB (per-hour DSO solver state is the current hypothesis) before adding parallelism on top.
- Bound concurrency by memory (`ntasks = min(nthreads, floor(mem_budget/est_per_model))`) rather than by core count.
- Keep the per-point wrapper with OOM attribution and staged memory profiler from Phase 35. Report peak RSS per point.
- Options to lower footprint: build smaller T chunks, per-hour DSO solve then free, avoid retaining unused duals, consider `direct_model` for hot subproblems, and call `GC.gc()` plus drop references between phases.
- The 784-house population is small relative to 8500. Do not conflate the two. The 8500 population is a separate density and scaling design.
- Honest-measurement discipline: if the 8500 point still fails, report a lower-bounded requirement, not a tuned pass.
**Detection:** RSS growth per iteration (not just per solve). `earlyoom` log. A harness that dies without attribution.
**Phase:** P-SCALE (8500 run last in the phase, after the 784-house run is parallel and measured).

### C5: The 8500 exactness gate keeps refusing, and someone loosens it
**What goes wrong:** At 8500 (d=0.1, T=10) ADMM converged in 8 iterations and the hybrid-floor gate refused it (ratio about 569, a genuine cone gap). A v5.0 deadline pressure leads to raising the tolerance or tau to get a green headline.
**Why it happens:** The milestone goal is a "measured run." It conflicts with "gate refuses."
**Prevention:** Per the exactness-gate policy: tighten `tol_gap`, never raise tau. Report refused-but-measured results with the status vocabulary (solve time, iterations, exactness ratio, peak memory). Define in the requirement that "measured" includes "refused with certificate," so the phase is satisfiable honestly. Investigate whether the gap is a genuine back-feed inexactness (PV-driven) or a conditioning artifact, using `ACPowerFlow(limits=false)` on the fixed dispatch.
**Detection:** Any diff touching `atol_exact`, tau, or hybrid floor constants.
**Phase:** P-SCALE.

### C6: ADMM convergence collapses with many heterogeneous agents
**What goes wrong:** Moving from about 13 or 123 one-house-per-bus aggregators to 784 houses and multi-node portfolios, with EVs, heat pumps and inverters, makes the single global rho a bad fit. Primal and dual residuals stall, rho adaptation oscillates, and iterations balloon (the existing canary already needs 56 on the small fixture).
**Why it happens:**
- Residual scaling differs by orders of magnitude across agents (kW house vs MW feeder).
- Residual-balancing adaptive rho can thrash when agent types differ.
- Multi-node portfolios add coupling across buses, so the consensus structure is no longer separable per node.
- Nonconvex-flavoured devices (C9, C10) break ADMM convergence guarantees.
- Stopping on the aggregate residual hides one non-converged agent class.
**Consequences:** Non-converged prices reported as duals, `:budget_exceeded` everywhere, or false convergence with prices far from the centralized dual.
**Prevention:**
- Normalize residuals per agent or per unit before the stop test. Report worst-agent and per-class residuals, not only the norm.
- Cross-validate every new population against the centralized solve at a small size (existing welfare rtol 1e-4 and price-gap checks) before scaling. Keep the centralized solve as the oracle for 784 houses (fits in memory, unlike 8500).
- Bound rho adaptation (freeze after K iterations, cap ratio changes) and measure iteration counts per scale and per device mix in a sweep.
- Add each device class separately and re-validate ADMM vs centralized after each addition, not all together.
- Do not rely on ADMM convergence for nonconvex extras (see C9, C10). Use convex relaxations or certificates.
**Detection:** Iteration counts that grow superlinearly with agent count. Residual plateau. Prices differing from centralized by more than the stated tolerance.
**Phase:** P-SCALE (population), re-checked at the end of P-ACTOR and P-DEV.

### C7: Profit-maximizing aggregator makes the problem bilevel or nonconvex
**What goes wrong:** An aggregator who buys at the DSO price and sells to customers at a tariff, maximizing its own profit, is a Stackelberg-type game. If the aggregator's decisions affect the DSO price (which they do, since prices are duals of the balance constraint), the aggregator's problem is an MPEC with price-quantity bilinear terms `λ·p`. Dropping that term (price-taker) is a different model.
**Why it happens:** Profit = tariff revenue minus `λ_j p_j`. If `λ` is endogenous and the tariff is a decision, products of variables appear. That is nonconvex, and duals-as-prices no longer follow from one convex program.
**Consequences:**
- The convex single-level welfare program no longer represents the market. The DADP dual is no longer a competitive price.
- Welfare comparisons "profit-max vs social welfare" silently compare different price definitions.
- ADMM can converge to a non-equilibrium point or cycle.
**Prevention:**
- State explicitly, in the model docs, which of three formulations is being built, and gate each separately:
  1. Price-taker aggregator (convex per aggregator given `λ`, fixed tariff): ADMM or a diagonalization fixed point. Prices are duals of the DSO welfare problem only if the DSO problem uses the aggregators' declared bids or utilities. Verify.
  2. Aggregator with market power or a decision-dependent tariff: genuinely bilevel. Reuse the v4.0 bilevel KKT-MILP machinery (SOS1, certified three ways) on small fixtures only. Do not scale it.
  3. Fixed margin or markup tariff: stays convex (linear in `p`), and it is the recommended default.
- Keep the profit-max variant a separate `AbstractObjective`/strategy so the social-welfare default path stays byte-identical.
- Check the "price-taking equilibrium equals welfare optimum" identity numerically: with zero margin and price-taking the profit-max result must equal the social-welfare result. That is the liveness test for the new objective.
- Report the efficiency loss (welfare gap) as a finding, never tune it away. Do not call the result "the equilibrium" (use the project's "a converged equilibrium (spread...)" language) if more than one fixed point is possible; run the multi-seed probe.
**Detection:** Bilinear `λ·p` in the objective; a nonconvex status from JuMP or Clarabel rejecting the model; profit-max welfare exceeding social welfare (impossible if both are solved correctly with the same constraints).
**Phase:** P-ACTOR (first requirement: formulation choice recorded in a decision before coding).

### C8: Behavioural response (opt-out, partial compliance, rebound) breaks convexity and duals
**What goes wrong:** Opt-out is binary. Partial compliance as a fixed fraction is fine (linear scaling), but compliance that depends on price (endogenous) is nonconvex or a fixed point. Rebound (consumption shifted forward) adds inter-temporal coupling that, if modelled as a penalty on cumulative shift, is convex, but if as a hard conditional, is not. Comfort limits as hard constraints can make some prices infeasible.
**Prevention:**
- Model opt-out as an exogenous scenario parameter (a fraction of non-responsive load, seeded), not as a binary decision. Behavioural response is a scenario axis, not an endogenous variable, in v5.0.
- Express rebound as a convex penalty or linear energy-recovery constraint, and document it.
- Comfort limits as slack-with-penalty so infeasibility is reported, not thrown (report-don't-throw policy).
- Verify the dual still equals the nodal balance dual after the change by comparing to a centralized solve, and run `assert_no_slack`.
**Phase:** P-ACTOR.

### C9: EV and V2G complementarity (simultaneous charge and discharge) and relaxation exactness
**What goes wrong:** The convex EV model relaxes `p_ch · p_dch = 0`. When the effective price is low, negative, or flat across hours, or when losses are free or small, the relaxed solution charges and discharges at once, burning energy as a "free resistor." This already appeared (App. C eta<1 overlap) and the battery terminal-SOC bug in v4.0.
**Why it happens:** Relaxed battery models are exact only when the objective penalizes the overlap (positive efficiency loss times positive marginal price). With negative LMPs (PV oversupply, binding upper voltage), exactness fails. EV arrival and departure windows add two further traps: SOC target at departure forces energy, which can make overlap profitable, and an unplugged EV must have `p = 0` outside its window (a missing mask silently lets it charge while away).
**Consequences:** Overstated flexibility, wrong DADPs in negative-price hours, V2G "arbitrage" that is purely artifact, and a reported "welfare gain" from nonphysical cycling.
**Prevention:**
- Reuse `assert_4q_complementarity!`-style certificate for EV: report per-hour `min(p_ch, p_dch)` overlap with a measured tolerance, in report-don't-throw form.
- Hard-code window masks (arrival, departure) as parameters, and test an EV outside its window has zero power.
- Enforce a departure SOC target as a constraint with a slack penalty (report infeasible plug-ins) and a terminal-SOC rule (no free terminal energy, same lesson as v4.0 battery).
- Include degradation cost or throughput cost for V2G (strictly positive) so overlap is never free; document it as a modeling assumption, not a tuning knob.
- If the certificate fails, do not use a binary silently. A MILP is a scope change (the planning layer has a no-binaries guard). Either document the inexact regime as a finding or add an explicit mixed-integer opt-in on small fixtures with HiGHS tolerances measured (see C16).
- Test fixtures must include a negative-price window to prove the certificate can fail (liveness).
**Detection:** Both `p_ch` and `p_dch` above a measured epsilon in the same hour. Welfare rising when efficiency loss rises. Net energy arbitrage with zero price spread.
**Phase:** P-DEV.

### C10: Heat pump COP nonlinearity
**What goes wrong:** Real COP depends on outdoor and supply temperature (and compressor part load). Electric power `P = Q_thermal / COP(T_out)`. If the COP is a function of a decision variable (supply temperature or indoor setpoint), this is bilinear or nonconvex. Even with COP as an exogenous time series, the thermal RC model with a thermal-power variable is linear and fine, but modelling `P = Q/COP(t)` with COP as a function of state breaks convexity.
**Why it happens:** Researchers copy a detailed COP curve into the optimization model.
**Prevention:**
- Use COP as an exogenous, hourly time series from outdoor temperature (precomputed, seeded, documented). Then `P_el[t] = Q[t] / COP[t]` is linear.
- Keep indoor temperature as a state with the RC discretization (a linear dynamic). Treat heating and cooling as separate nonnegative variables, and never both on at once (add a cost, or certify like C9).
- Document the discretization (exact exponential vs forward Euler) and its stability: a forward-Euler step that is too large for a small thermal time constant gives an unstable or sign-flipping model. Check `dt/(RC)` is within stability, or use the exact discretization.
- Comfort band as a soft constraint (C8). Initial and terminal indoor temperatures must be linked (periodic or fixed), otherwise the building "free-rides" on stored heat, which is the same class as the free terminal energy bug.
- The reactive draw: heat pump load uses a power factor, so apply `q = p tan(phi)` consistently with the flexible-load fix (v4.0 FIX-05).
- Validate against a closed-form steady state (constant outdoor temperature gives analytic equilibrium temperature).
**Detection:** Power depends on a decision in a nonlinear way; the model rejected by Clarabel; indoor temperature drifting free at horizon end.
**Phase:** P-DEV.

### C11: Volt-VAR droop is nonconvex (and the SOCP gate is already fragile)
**What goes wrong:** The Volt-VAR curve `q = f(V)` is piecewise-linear, with a deadband and saturation, a function of the voltage that is itself a decision variable in the same program. Embedding it as equality constraints makes the problem nonconvex (piecewise with dead zone, non-monotone selection). Treating `q` as a free decision variable bounded by the inverter capability `p^2 + q^2 <= S^2` is convex, but then it is optimal reactive dispatch and not a droop. Calling it Volt-VAR would be a mislabel.
**Why it happens:** The SOCP relaxation is already fragile under PV back-feed and binding upper voltage, which is exactly where Volt-VAR acts (it absorbs vars at high voltage). Adding reactive absorption changes the loss and voltage tradeoff and can break or fix exactness in non-obvious ways.
**Consequences:** Inexact relaxation, or a "Volt-VAR" result that is actually an OPF dispatch, which overstates benefit.
**Prevention:**
- Be explicit about three levels, and label each correctly:
  1. Convex capability-limited `q` dispatch: `P^2 + Q^2 <= S^2` as an SOC constraint (a rotated cone is already used in `FourQuadBESS`). Reuse that. Call it "optimal VAR dispatch."
  2. Droop as a fixed-point evaluated outside the solve: solve, evaluate droop at the resulting voltages, update `q` as a parameter, repeat (Gauss-Seidel style), and report convergence or cycling. It is a heuristic with no guarantee; document the iteration and detect limit cycles.
  3. Exact droop via MILP or complementarity: out of scope for v5.0 unless the small-fixture oracle is explicitly wanted.
- Revisit the exactness certificate after adding `q` sources: run `assert_ac_exact!` and `ACPowerFlow(limits=false)` on fixed dispatch. Do not assume a prior exactness result carries over.
- The v2.1 thesis assumption A3 (DERs active-only, `qag_dso` fixed) is being relaxed. Reactive consensus (`reactive_consensus`, LIVE mode) then matters, so the reactive dual (`:balance_q`) must be checked with `assert_no_slack`. Verify the live ADMM two-block dual ascent still converges with PV inverters as q-sources.
- Keep Volt-VAR off by default (byte-identical path).
**Detection:** The ADMM voltage constraint active while inverters are not absorbing; cone gap rising after adding inverters; droop iteration cycling.
**Phase:** P-DEV (last device, after EV and heat pump), with an exactness re-check.

### C12: Equity metrics on DLMPs are misread
**What goes wrong:**
- Nodal DLMP differences are read as unfairness, when they are efficient signals of losses, congestion and voltage. Distance from the substation explains most spread.
- The 4-way decomposition components (energy, loss, congestion, voltage) are summed or compared across nodes in ways that mix reference conventions.
- Gini, Theil or percentile gaps on bills are computed over nodes (not households), so a node with 200 houses and one with 1 are weighted equally.
- Welfare gain across heterogeneous households is averaged, hiding losers. Distribution of surplus change is not a distribution of bills.
- Equity is computed from a model that reports prices, but prices at a tariff-flat scheme are not duals, so cross-scheme comparisons have different bases.
- Negative or near-zero denominators (bills near zero for prosumers who are net sellers) make ratios and Gini explode or become undefined.
**Prevention:**
- Fix the unit of analysis (household) and weights explicitly; carry household count per bus through the 784-house population (the old 1-house-per-bus proxy gives wrong weights).
- Report the 4-way DLMP decomposition components separately and never conflate with the reactive component (existing rule: never sum reactive into the active total).
- Use sign-safe metrics: absolute and per-household surplus change, share of losers, the distribution (quantiles), and Gini or Palma only on non-negative quantities (e.g. gross payments), noting which. Do not take ratios of possibly-negative aggregates, the same rule as the thesis golden.
- Include a "distance-from-substation" control (or report the loss-only component), so a spatial gradient is not read as discrimination.
- Label metrics as descriptive of this model's assumptions (seeded synthetic loads, public feeder data), not as policy conclusions.
- Check the metrics on a closed-form 2-bus fixture (known DLMP differences).
**Detection:** An equity index that is nearly 1 or 0 for any scenario; sign changes on small perturbations; results that change when houses are relabelled across nodes.
**Phase:** P-SETTLE.

### C13: Tariff-comparison welfare accounting double counts
**What goes wrong:** Transfers get counted as welfare. Bills paid by the prosumer equal revenue for the aggregator and DSO, so summing consumer surplus plus aggregator profit plus DSO surplus is the same as total welfare only if transfers net to zero. Typical errors:
- Counting the FIT payment to PV as both a prosumer gain and a (non-)cost to the DSO, or counting wholesale cost twice (in the DSO surplus and in the aggregator cost).
- Congestion rent (and loss and voltage components of the DLMP) not assigned to any actor, so budget does not balance: `Σ_j λ_j p_j` over nodes is not equal to the wholesale payment. The difference is the merchandising surplus, which must be an explicit line.
- Comparing tariffs with different quantities: FIT or flat tariffs yield a different dispatch (flat prices do not elicit flexibility), but "bill savings" are compared at the same dispatch.
- Flat vs nodal: flat tariff revenue is not cost-reflective, so the DSO runs a deficit that must be attributed.
- Mixing signs: the project already learned that welfare ratios of possibly-negative aggregates are sign-unsafe (the thesis +25%).
- Settling FIT at the model's relaxed physics instead of truth (v4.0 fix: FIT and MPC are settled on AC physics, with violations reported).
**Prevention:**
- Define one ledger per scenario: every cash flow has a payer and payee, and a test asserts `Σ_actors net = 0` (or equals total physical welfare change) to machine tolerance, including the merchandising surplus line. This is the liveness test.
- Welfare = social surplus (device utilities minus true production and loss costs), computed identically across tariffs. Bills and transfers are reported separately, never added to welfare.
- Decompose by actor: prosumer, aggregator, DSO, upstream. Report each tariff against the same baseline and say which baseline.
- Compute each tariff scheme as its own scenario with its own dispatch (price response under that tariff), and settle every scheme on the same physical model.
- Pin goldens on sign-safe differences (as in the thesis sign flip). Never re-pin.
**Detection:** Budget imbalance; a tariff that "creates" welfare at zero physical change; sum of actors does not equal the aggregate.
**Phase:** P-SETTLE (define the ledger and conservation test before implementing any tariff).

### C14: Claiming the thesis +25% magnitude
**What goes wrong:** Under pressure, the 784-house population gets tuned (loads, PV scale, prices, penalty parameters, batteries) until the ratio reaches +25%, or the number is reported without stating that the thesis data (App. E) is unavailable. Previous directional result: sign flip reproduces, magnitude about +0.26%. The v2.1 "knife-edge" was also found to depend on population settings.
**Why it happens:** The target number is known, so tuning becomes search-for-confirmation. The ratio of welfare is sign-unsafe near zero or negative aggregates and moves strongly with small changes in the denominator.
**Consequences:** A thesis-visible claim that cannot be defended. Violates "report it honestly, whatever it is."
**Prevention:**
- Pre-register the protocol before running: fixed population (784 houses, seeds, data sources), fixed metric definition (what numerator and denominator, which baseline: FIT), and a sensitivity sweep range chosen independently of the target.
- Report the number obtained, with the sweep (measurement-before-golden), and frame it as "reproduced / not reproduced under public-data assumptions." Keep the thesis figure as a non-failing cross-check (`@test_broken` or `@info`), as for v1.
- Pin goldens on sign-safe quantities, never on the ratio. State that the exact figure is not reproducible without App. E.
- Do not tune any free parameter by looking at distance to +25%. A parameter may be varied only in a documented sweep reported in full.
- Compare the real 784-house result with the 1-house-per-bus proxy (+0.26%) and attribute the difference by cause; if there is none, that is the result.
- Check metric definition against the thesis text (welfare gain defined on which quantity); a definitional mismatch can explain a magnitude gap without any tuning, but must be demonstrated, not assumed.
**Detection:** A parameter change commit message mentioning "to match"; sweep with no reported spread; magnitude claim without the baseline definition.
**Phase:** P-REPRO (last; depends on 784-house population from P-SCALE and settlement definitions from P-SETTLE).

---

## Moderate Pitfalls

### M1: Retry ladder and Clarabel NUMERICAL_ERROR under parallelism
**What goes wrong:** Intermittent Clarabel `NUMERICAL_ERROR` already exists. With hundreds of subproblems per iteration, the chance that at least one fails per iteration rises, and per-task retry ladders can change results (an escalated tolerance in one agent).
**Prevention:** Retry per subproblem with logged escalation level; report the count of escalations per run; restore conditioning per subproblem so later solves never inherit an escalation; a failed subproblem after the ladder yields a typed `SolveFailedError` (not a swallowed catch-all); count and report escalations in the trace.
**Phase:** P-SCALE.

### M2: Rebuilding models inside the loop at the new scale
**What goes wrong:** New device classes (EV windows, heat-pump RC) are added as constructor-time structures, and varying data (EV arrival, outdoor temperature) is baked into constraints, forcing rebuilds per scenario or per ADMM iteration.
**Prevention:** Data that changes per solve goes through Parameters or `set_normalized_rhs`; only `lambda, mu, rho` change per ADMM iteration. Keep devices as anonymous-container constraints (existing convention). Note the TestItem top-level scoping trap when writing tests (wrap in functions).
**Phase:** P-DEV, P-SCALE.

### M3: Multi-node aggregator portfolios break per-node separability
**What goes wrong:** An aggregator spanning buses has one objective, but ADMM consensus is per node. Splitting by node loses the cross-node coupling (shared budget, shared battery, portfolio-level compliance), while solving by aggregator duplicates nodal injections and complicates the nodal balance dual.
**Prevention:** Define the consensus variable as nodal injection `p_{a,j}[t]` and keep the nodal-balance dual as the price; the aggregator subproblem owns all its nodes. Validate: the single-node aggregator case reduces exactly to the existing model (degenerate-case anchor, as done for stochastic S=1). Check that price at each node still equals the nodal balance dual and not an aggregator-level average.
**Phase:** P-ACTOR.

### M4: Welfare objective changes under the profit-max switch hide Deferrable-style constant offsets
**What goes wrong:** Algebraic substitution leaves constant terms (the earlier Deferrable +18 offset), so profit-max and welfare objectives are compared with different constants.
**Prevention:** Reconcile constants explicitly in docs and tests; compare differences, not levels.
**Phase:** P-ACTOR.

### M5: Flexibility market vs price-based coordination are not apples to apples
**What goes wrong:** A DSO flexibility market (procure kW at a price for congestion relief) has a different information structure and product than DADP. Comparing welfare without equal physical constraints, baseline definition (customer baseline load, gaming), and payment rule (pay-as-bid vs uniform) misattributes differences.
**Prevention:** Same network, same devices, same exactness gate; state the baseline and payment rule; account for baseline manipulation as a known limitation; treat the flexibility market as a documented formulation with its own certificate. Settlement ledger conservation (C13) applies.
**Phase:** P-SETTLE.

### M6: Case A population construction hidden degrees of freedom
**What goes wrong:** Assigning 784 houses to 13 (or 123) buses, and sampling load, PV, and battery per house, has many hidden choices; results change with the assignment rule.
**Prevention:** Seeded, documented assignment; report sensitivity to the assignment seed; keep population data loading in the data layer (CSV) with the seed in provenance.
**Phase:** P-SCALE, P-REPRO.

### M7: Test-infrastructure traps that will bite new tests
**What goes wrong:** `@testitem` top-level scope breaks `try x=...` and loop reassignment; TestItemRunner scans scratch `.jl` files and agent worktrees; plans' `<verify>` TestItemRunner commands fail under `--project=.`; detached suite orphans give phantom regressions; the 2 known-false Aqua failures; threaded tests multiply runtime.
**Prevention:** Wrap logic in functions; keep scratch scripts outside the repo; run targeted tests via direct scripts; poll long suites by PID; put heavy 784-house and 8500 items in `:slow`, and keep the canary fast. Add threaded tests with `Threads.nthreads()` guards (CI default may be 1 thread). Expected-broken list must be updated for any new broken site.
**Phase:** all.

---

## Minor Pitfalls

### m1: Solver tolerances silently undercut claims
HiGHS default `mip_rel_gap=1e-4` and `mip_feasibility_tolerance=1e-6` undercut any "exact" claim if MILP is used for EV, V2G, or small bilevel oracles. Measure comparison epsilons, do not pick them. Reuse the existing floor.

### m2: Figures and docs
New experiments need Literate pages (hard requirement) and `checkdocs=:exports`; new exports go through `public` (exports were trimmed 192 to 90; do not re-bloat). Planning-ID guard and API-script check run in CI.

### m3: Provenance
Record thread count, BLAS threads, solver versions, population seed, and git state with every parallel result (DrWatson `tagsave`). Note that dirty-tree gitpatch keys inflate counts.

### m4: Time-zone and DST in EV and heat-pump data
Arrival or departure across midnight (wrap-around windows) and DST days (23 or 25 hours) break fixed T=24 indexing; wrap-around windows are the common bug. Test an overnight EV (arrive 18:00, depart 07:00).

### m5: Price-sign-dependent behaviour
Negative DADPs under PV oversupply flip the sign of many assumptions (curtailment, battery cycling, V2G). Include a negative-price fixture in every new device test.

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| P-SCALE: parallel solves | Shared model state (C1), nondeterminism (C2), BLAS oversubscription (C3) | One model per task, ordered serial reduction, `BLAS.set_num_threads(1)`, serial default, parallel equals serial test |
| P-SCALE: 784 houses | Heterogeneous-agent ADMM stall (C6), population hidden DOFs (M6) | Per-agent residual scaling, centralized oracle at 784, seeded assignment |
| P-SCALE: 8500 | Memory multiplication (C4), gate refusal pressure (C5), retry noise (M1) | Memory-bounded concurrency, attribute the 3.4 GiB first, report refused-with-certificate as a measured result |
| P-ACTOR: profit-max | Bilevel or bilinear, broken dual-as-price (C7), behavioural nonconvexity (C8), multi-node coupling (M3) | Decide the formulation first; fixed-margin convex default; zero-margin equals welfare liveness test; behaviour as exogenous scenario axis |
| P-SETTLE: tariffs | Double counting (C13), misread equity (C12), flexibility market baseline (M5) | Conserved ledger test; household-weighted sign-safe metrics; same physics for all schemes |
| P-DEV: EV/V2G | Charge/discharge overlap, window masks, free terminal SOC (C9) | Overlap certificate, degradation cost, negative-price fixture, terminal SOC rule |
| P-DEV: heat pump | COP nonlinearity, RC stability, free terminal temperature (C10) | Exogenous COP series, exact discretization, periodic/terminal temperature |
| P-DEV: Volt-VAR | Droop nonconvex, SOCP exactness fragile at back-feed (C11) | Capability-cone dispatch labelled honestly, droop as outer fixed point, exactness re-check, off by default |
| P-REPRO: magnitude | Tuning toward +25% (C14) | Pre-registered protocol, full sweep, sign-safe goldens, no re-pin, report whatever it is |

## Ordering implications for the roadmap
1. P-SCALE parallel kernel with serial-equivalence tests first. Everything else is validated by ADMM vs centralized, so determinism and per-model ownership must precede new agent types.
2. Define the settlement ledger and conservation test (C13) early, since P-ACTOR comparisons (profit-max vs welfare) and P-REPRO depend on consistent accounting. It can be built in parallel with P-ACTOR.
3. Devices (P-DEV) one class at a time, each re-validated against centralized and exactness gates; Volt-VAR last.
4. P-REPRO last. 8500 headline run last within P-SCALE or as its own late phase, because memory work is open-ended.

**Research flags:**
- Needs deeper phase research: P-ACTOR formulation (price-taker vs market power; ADMM diagonalization convergence), C11 Volt-VAR fixed-point behaviour, and the 8500 memory attribution.
- Standard patterns, likely no extra research: settlement ledger, EV/heat-pump convex models, equity metric definitions (but verify metric definitions against literature).

## Sources and confidence
- Project history (PROJECT.md, RETROSPECTIVE.md): HIGH. Includes memory-wall data, canary, gate policy, FIX-05, App. C eta<1 overlap, bilevel machinery, report-don't-throw, sign-safe goldens.
- Julia and JuMP threading guidance (model-per-task, `threadid()` pitfalls, BLAS thread setting): MEDIUM, established community practice, not re-verified against current docs this session. Verify: Clarabel default linear-solver backend and thread behaviour, JuMP thread-safety statement, `direct_model` support.
- Relaxation exactness for storage and EV with negative prices, COP bilinearity, Volt-VAR non-convexity, ADMM heterogeneity: MEDIUM, from convex-optimization and power-systems literature knowledge (e.g. Gan-Low branch-flow work already used in this project; Li, Chen, Low on storage relaxation exactness), not re-checked online.
- Equity and tariff-accounting items: MEDIUM-LOW; these are accounting-design judgments and should be confirmed against the settlement requirements when written.

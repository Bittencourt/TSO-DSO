# Theory Extraction — Palacios PhD Thesis (UNSJ, 2022)

> Source: `docs/references/86. Tesis Doctoral Juan Pablo Palacios (2).pdf` (185 pp.)
> Core published version: Palacios, Samper, Vargas, *"Dynamic transactive energy scheme for
> smart distribution networks in a Latin American context,"* IET GTD 13(9):1481–1490, 2019.
> Extracted by research agent; verbatim technical digest retained for implementation.

## ⚠ Framing correction (critical for implementation)

The operational model is **NOT** a Stackelberg-Nash / bilevel MPEC. It is:

- A **single-level, convex, cooperative social-welfare maximization** (`GLB-OPT`) over the whole
  distribution network for a 24-hour horizon.
- Solved **distributedly via ADMM** — split into per-node aggregator subproblems (`AGR-OPT`) and
  one network subproblem (`DSO-OPT`).
- The dynamic transactive tariff **DADP is the Lagrange/dual multiplier of the nodal active-power
  balance constraint** (a DLMP obtained by marginal pricing). No KKT-of-a-lower-level, no
  complementarity, no MPEC, no binaries.

The *conceptual narrative* is hierarchical/leader-follower (DSO designs the price, prosumers
respond), but the *solution machinery is convex dual decomposition*. For the Julia port:
**JuMP + a conic (SOCP) solver, plus an outer ADMM loop that updates prices as dual variables.**
Do not reach for MPEC/bilevel tooling for this layer. (The Stackelberg-Nash game lives in the
N1–N2 planning layer — see `THEORY-papers.md`.)

## 1. Actors & physical mapping

- **DSO** — sits between wholesale market (MEM) and aggregators. Buys/sells at exogenous `λ₀[t]`,
  sets day-ahead dynamic tariff (DADP) at each node, enforces network security. Conceptual leader.
- **Aggregators** `ag_j`, one per load node `j` (a distribution transformer / feeder node grouping
  prosumer houses `H_j`). Schedule prosumers' flexible loads + PV-battery. Conceptual followers.
- **Prosumers / houses** `h` — own PV, batteries, thermostatic/programmable/interruptible flexible
  loads + inelastic loads. Managed by HEMS.
- **MEM** (wholesale market) — exogenous price `λ₀[t]`, deterministic, known ∀t.
- Node `j=0` = MEM/transmission frontier — **this is the TSO–DSO boundary**, priced at `λ₀`.
  Radial feeder; branches `(i,j)∈B`, `i` parent → `j` child.

## 2. Mathematical formulation

Indices: `t∈T` (24 hourly steps, Δt=1h), houses `h∈H`, node/aggregator `j∈N`, branches `(i,j)∈B`,
flexible loads `d∈D_h`, inelastic loads `dc∈Dc_h`.

### 2.1 Prosumer device models (temporal coupling)

**Thermostatic loads** (A/C, fridge) — temperature linear in power:
```
T_in[t+1] = T_in[t] + α(T_out[t] − T_in[t]) − β·p[t]        (3.2)
T_min ≤ T_in[t] ≤ T_max                                     (3.3)
```
**Programmable / deferrable loads** (washer, EV) — energy within window `T_{h,d}`, else p=0:
```
E_min ≤ Σ_{t∈T_{h,d}} p[t] ≤ E_max                          (3.4)
P_min ≤ p[t] ≤ P_max                                        (3.5)
```
**PV + battery (BSS):**
```
soc[t+1] = soc[t] + (η·p_ch[t] − (1/η)·p_dch[t])·Δt          (3.6)
0 ≤ p_ch[t] ≤ P_pv[t] ≤ P_max_b     (charge limited by PV)   (3.7)
0 ≤ p_dch[t] ≤ P_max_b                                       (3.8)
E_min_b ≤ soc[t] ≤ E_max_b                                   (3.9)
```

### 2.2 Preference (utility/cost) functions — quadratic, convex, binary-free

```
Interruptible/elastic load utility (concave):
  U_{h,d}(p) = Σ_t [ a·p[t] − (b/2)·p[t]² ]                                  (3.10)
Thermostatic utility:
  U(T_in) = c − (b/2)·Σ_t (T_in[t] − T_min[t])²                             (3.11)
Programmable utility:
  U(p) = c − (b/2)·(Σ p[t] − E_max)²                                        (3.12)
Coefficients:
  a = λ_max + P_min·b ;   b = (λ_max − λ_min)/(P_max − P_min)               (3.13)-(3.14)
Battery charge utility / discharge cost:
  U_ch(p_ch)  = Σ_t [ a_ch·p_ch − (b_ch/2)·p_ch² ]                          (3.15)
  C_dch(p_dch) = Σ_t [ a_dch·p_dch + (b_dch/2)·p_dch² ]                     (3.16)
  a_ch=λ_med ; b_ch=(λ_med−λ_min)/P_max_b ;
  a_dch=λ_med ; b_dch=(λ_max−λ_med)/P_max_b                                 (3.17)-(3.20)
```
`λ_med` = indifference price (no charge/discharge). Typical `λ_max=9, λ_min=1, λ_med=4` ¢$/kWh,
`P_max_b=5` kW. **Appendix C proves** that with `λ_min ≤ λ_med ≤ λ_max`, `p_ch` and `p_dch`
cannot both be positive at optimum → **no binary/complementarity needed**. (Key for the port.)

### 2.3 Aggregator aggregation

```
U_{ag_j}(p_ag) = Σ_{h∈H_j} [ U_ch − C_dch + Σ_d (U_{h,d}(p) + U_{h,d}(T_in)) ]   (3.21)
p_{ag_j}[t] = Σ_{h∈H_j} ( p_ch − p_dch − P_pv + Σ_d p_{h,d} + Σ_dc p_{h,dc} )     (3.22)
q_{ag_j}[t] = Σ_{h∈H_j} ( Σ_d p_{h,d}·√(1−φ²)/φ + Σ_dc p_{h,dc}·√(1−φ²)/φ )       (3.23)
```
`p_ag>0` = net consumption. `φ` = load power factor (∈[0.85,0.95]). Batteries = active power only.
Inelastic loads `p_{h,dc}` are **parameters** (from demand simulation), not decisions.

### 2.4 Distribution network — Branch Flow Model (DistFlow), SOCP + LinDistFlow exactness

`v_i` = squared voltage (`v_0` fixed), `l_{i,j}` = squared current, `P_{i,j},Q_{i,j}` = branch flows.
```
p_0[t]=P_{0,1}[t] ; q_0[t]=Q_{0,1}[t]                                        (3.29)-(3.30)
R_{p,j}=P_{i,j} − r·l_{i,j} − p_{ag_j} − Σ_{m:j→m}P_{j,m} = 0   (active bal)  (3.31)
R_{q,j}=Q_{i,j} − x·l_{i,j} − q_{ag_j} − Σ_{m:j→m}Q_{j,m} = 0   (react bal)  (3.32)
v_j = v_i − 2(r·P_{i,j}+x·Q_{i,j}) + (r²+x²)·l_{i,j}            (voltage)    (3.33)
l_{i,j} = (P_{i,j}²+Q_{i,j}²)/v_i                              (NONCONVEX)  (3.34)
V²_min ≤ v_i ≤ V²_max                                                       (3.35)
S²_max,ij ≥ P_{i,j}²+Q_{i,j}²  (fwd) ;  ≥ P_{j,i}²+Q_{j,i}² (rev)           (3.36)-(3.37)
```
**SOC relaxation** of (3.34):  `l_{i,j} ≥ (P_{i,j}²+Q_{i,j}²)/v_i`   (3.39)
**Exactness** via a parallel loss-less **LinDistFlow** copy (`P̂,Q̂,v̂`) with upper voltage bound:
```
v̂_j = v̂_i − 2{ r(P_{i,j}+r·l_{i,j}) + x(Q_{i,j}+x·l_{i,j}) }                (3.43)
V²_min ≤ v_i, v̂_i ≤ V²_max                                                  (3.45)
```
With (3.45), (3.34) holds with equality at the optimum (relaxation exact). **Essential** — without
it the DADP prices are meaningless.

### 2.5 Global problem (single-level social welfare)

```
GLB-OPT:  max Σ_{j∈N} U_{ag_j}(p_ag) − (λ_0)ᵀ·p_0                            (3.38)
          s.t. (3.2)–(3.9),(3.22)–(3.23),(3.29)–(3.37)
GLB-CVX:  same objective, SOC-relaxed + LinDistFlow exactness              (convex: LP+QP+SOCP)
```
Objective = social welfare = total prosumer utility − DSO's MEM purchase cost (`λ₀ᵀp₀`).

### 2.6 ADMM decomposition (the actual solver)

`λ_j[t]` (active) and `μ_j[t]` (reactive) = dual vars, `ρ>0` penalty. `λ_j` **is the DADP**.
```
AGR-OPT (per node, parallel, QP; separable per house):
  max U_{ag_j}(p_ag) − (λ_j)ᵀ·p_ag − (ρ/2)·‖R_{p,j}‖²   s.t. (3.2)–(3.9)     (3.46)
DSO-OPT (per hour, SOCP):
  min λ_0[t]p_0[t] − Σ_j { λ_j[t]R_{p,j}[t] + μ_j[t]R_{q,j}[t]
                           + (ρ/2)(R_{p,j}[t]²+R_{q,j}[t]²) }                (3.47)
  s.t. (3.29)–(3.33),(3.36)–(3.37),(3.39),(3.43),(3.45)
Dual update:  λ_j^{k+1}=λ_j^k+ρ·R_{p,j} ;  μ_j^{k+1}=μ_j^k+ρ·R_{q,j}
Converge when |R_{p,j}[t]|≤ε and |R_{q,j}[t]|≤ε ∀t,j.
```
Params: `ρ=1000`, `ε=5×10⁻⁵`, ≈28 iterations. At convergence (3.34) equality → global optimum;
`λ_j` = final DADP. Appendix B also gives a Predictor-Corrector Proximal Multipliers (PCPM) variant.

### 2.7 FIT benchmark (comparison baseline)

German-style feed-in tariff `FIT-OPT` per prosumer (3.24)–(3.28); prices `λ_im,λ_e,λ_s`. Used to
show DADP raises social welfare (+25%) vs FIT.

### 2.8 Temporal / data-generation aspects

- Horizon 24×1h. Inter-temporal coupling: SOC (3.6), thermostatic (3.2), programmable window (3.4).
- Device/demand/PV simulation runs at 1-min resolution via **first-order Markov chains** (home
  occupancy, cloud luminosity index, PV output) → aggregated to hourly → enter optimization as
  parameters. Markov models are **data-generation**, not part of the optimization.

## 3. Solution method summary

Single convex `GLB-CVX` (SOCP) → decomposed by **ADMM** into aggregator QPs + per-hour network
SOCPs; duals `λ_j,μ_j` updated by gradient ascent with penalty `ρ`. Transactive prices = duals of
active balance (DLMP decomposition = wholesale + loss + congestion + voltage terms).
Original solvers: MATLAB + Optimization Toolbox + **CVX**. **Julia mapping:** JuMP + SOCP solver
(Clarabel / SCS / ECOS / Mosek); native outer ADMM loop. No integers.

## 4. Transactive energy scheme

- **DADP** = hourly nodal distribution tariff (next 24h) = dual `λ_j[t]` of nodal active balance.
  Energy charges only (fixed O&M/expansion excluded).
- At PV over-generation / over-voltage → DADP drops **below** MEM price (soak up PV). At
  congestion / high-demand → DADP rises **above** MEM price (curtail, reward battery discharge).

## 5. Case studies

**Case A — Modified IEEE 13-node feeder ("11 nodes"; node 0 = MEM frontier):** 13.2 kV, 10
aggregators. 784 houses; PV=5 MWp, elastic=6.5 MW, inelastic=1.5 MW; `V∈[0.95,1.05]`,
`S_max,01=6.86 MVA`; `λ_max=8.9,λ_min=3.8,λ_med=6.2` ¢$/kWh. Congestion-driven. Results (DADP vs
FIT): social benefit +25% ($1457→$1819); DSO surplus −$2829→+$439; prosumer −68%. 28 iterations,
exact relaxation confirmed (`v₉[16]=1.0493`). Sensitivity: 896 houses, 5 cases (battery×1.5,
PV×1.5, willingness×1.5, alt MEM profile).

**Case B — Modified IEEE 123-node feeder:** 4.16 kV, 85 load nodes, 850 houses. PV=5 MWp,
elastic=4 MW, inelastic=2 MW; **`V∈[0.9,1.1]`**, `S_max,01=3.8 MVA`. **Voltage-constrained** (not
congestion). Social benefit $1976 = DSO $275 + prosumer $1701.

Data sources: UK Time-Use Survey + DECC (occupancy), Loughborough irradiance (PV Markov), IEEE
13/123 feeders (modified), San Juan temperature.

## 6. Julia port checklist

1. One convex model `GLB-CVX`, then split by ADMM: `AGR-OPT` (QP/node, per-house separable),
   `DSO-OPT` (SOCP/hour). Native outer loop for dual updates.
2. JuMP + SOCP solver (Clarabel/SCS/ECOS/Mosek). No binaries, no MPEC tooling for this layer.
3. Implement the **LinDistFlow exactness trick** (3.40–3.45) — essential.
4. Batteries need **no complementarity** — parametrization (3.15–3.20) guarantees it.
5. Output `λ_j[t]` as DADP; validate exactness via `l_{i,j}·v_i ≈ P²+Q²` at convergence.

Source locations: formulation pp. 71–88; case data pp. 89–123; App. C (battery proof) pp. 166–168,
App. D (appliance data), App. E (123-node R/X).

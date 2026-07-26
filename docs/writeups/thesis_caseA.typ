#set page(
  paper: "a4",
  margin: (x: 2.2cm, y: 2.4cm),
  header: context {
    if counter(page).get().first() > 1 [
      #set text(size: 8pt, fill: gray)
      _Camada Operacional da Tese — Caso A (IEEE-13 modificado)_
      #h(1fr) Projeto TSO-DSO
      #linebreak()
    ]
  },
  numbering: "1",
)
#set text(font: "New Computer Modern", lang: "pt", region: "br", size: 10.5pt)
#set par(justify: true, leading: 0.65em)
#set heading(numbering: "1.1")

#show heading.where(level: 1): it => v(0.8em) + it
#show heading.where(level: 2): it => v(0.4em) + it

#align(center)[
  #text(size: 20pt, weight: "bold")[Camada Operacional da Tese — Caso A]
  #v(0.3em)
  #text(size: 12pt, fill: gray)[Formulação completa do modelo e reprodução dos resultados do IEEE-13 modificado]
  #v(0.8em)
  #line(length: 60%, stroke: 0.5pt + gray)
  #v(0.8em)
]

_Trabalho derivado da implementação em Julia (módulos `src/models/`, `src/admm/`, `src/pricing/` do projeto TSO-DSO), reproduzida via `solve_welfare` em `src/models/welfare_solve.jl` e exercitada por `scripts/thesis_caseA.jl`. As figuras deste documento são geradas automaticamente pelo script e residem em `results/thesis_caseA/`._

#v(0.3em)

= Resumo

Este documento descreve, em uma única fonte, o modelo da *camada operacional* da tese de Palacios (UNSJ/CONICET, 2022) — Capítulo 3 — e como reproduzi-lo computacionalmente usando o script `scripts/thesis_caseA.jl` do projeto TSO-DSO. O *Caso A* da tese é o resultado canônico da camada operacional: o alimentador IEEE-13 modificado (11 nós, 10 agregadores, fronteira MEM no nó 0) calibrado com 784 casas, 5 MWp de PV e bandas de tensão $V in 0,95..1,05$ pu.

O modelo é uma *maximização cooperativa de bem-estar social* de nível único (GLB-CVX) sobre um horizonte de 24 horas, resolvida por decomposição ADMM. O sinal transativo — a *tarifa dinâmica dia-à-dia* DADP — é o *dual do balanço ativo nodal* (uma DLMP), emergindo da resolução, não imposto. O documento cobre:

  + a formulação matemática completa (eq. 3.2–3.45 da tese), com cada restrição mapeada ao seu construtor em `src/`;
  + o cenário, parâmetros e curvas de entrada do Caso A;
  + como o ADMM decompõe o problema em subproblemas por agregador (AGR-OPT, QP) e por hora (DSO-OPT, SOCP);
  + o benchmark FIT (tarifa de inserção alemã) contra o qual o DADP é comparado;
  + como executar o script `thesis_caseA.jl` e interpretar suas seis figuras;
  + os resultados-chave e como eles se comparam aos alvos da tese.

= Por que este modelo (não é um MPEC)

#text(fill: gray)[_Leia antes de qualquer coisa: a correção de enquadramento._

O modelo operacional *NÃO* é um Stackelberg–Nash / MPEC bilevel. É:

- Uma *maximização cooperativa de bem-estar social*, convexa e de nível único (`GLB-OPT`) sobre toda a rede de distribuição, em um horizonte de 24 horas.
- Resolvida *distribuidamente por ADMM* — decomposta em subproblemas por agregador (`AGR-OPT`) e um subproblema de rede por hora (`DSO-OPT`).
- A tarifa transativa dinâmica *DADP é o multiplicador de Lagrange / dual do balanço ativo nodal* (uma DLMP obtida por pricing marginal). *Sem KKT de nível inferior, sem complementaridade, sem MPEC, sem binários.*

A narrativa *conceitual* é hierárquica/líder-seguidor (DSO desenha o preço, prosumers respondem), mas a *maquinaria de solução é decomposição dual convexa*. O equilíbrio de Stackelberg–Nash vive na camada de *planejamento* N1–N2 — ver o documento irmão `modelo_stackelberg_dso_unico.typ`. Não procure ferramentas MPEC/bilevel para esta camada.
]

= Conjuntos, índices e atores

#table(
  columns: (auto, 1fr),
  align: (left, left),
  stroke: none,
  [*Símbolo*], [*Significado*],
  [$t in {1, dots, T}$], [passos de tempo (horizonte dia-à-dia, $T = 24$, $Delta t = 1$ h)],
  [$j in {0, 1, dots, N}$], [barras do alimentador; $j = 0$ = raiz (fronteira MEM/TSO–DSO)],
  [$(i, j) in cal(B)$], [trechos radiais, pai $i ->$ filho $j$],
  [$h in H_j$], [casas prosumer agregadas no nó $j$],
  [$d in D_h$], [cargas flexíveis (termostáticas, postergáveis, interrompíveis) da casa $h$],
  [$d c in D c_h$], [cargas inelásticas da casa $h$ (parâmetros, não decisões)],
)

*Atores:*

- *DSO* — entre a MEM (mercado atacadista) e os agregadores. Compra/vende a $lambda_0[t]$ exógeno, fixa a tarifa DADP em cada nó, impõe segurança de rede.
- *Agregadores* $a g_j$ — um por nó de carga. Agendam cargas flexíveis + PV-bateria dos prosumers.
- *Prosumers / casas* $h$ — possuem PV, baterias, cargas termostáticas/programáveis/interruptíveis + cargas inelásticas. Geridos por um HEMS.
- *MEM* (mercado atacadista) — preço $lambda_0[t]$ determinístico, conhecido $forall t$.

= Formulação matemática

== Modelos de dispositivos (acoplamento temporal)

*Cargas termostáticas* (A/C, geladeira) — temperatura linear na potência:

$
cases(
  T_"in"[t+1] = T_"in"[t] + alpha (T_"out"[t] - T_"in"[t]) - beta dot.c p[t] & "(3.2)" ,
  T_"min" <= T_"in"[t] <= T_"max" & "(3.3)"
)
$

*Cargas postergáveis / programáveis* (máquina, EV) — energia dentro de janela $T_(h,d)$:

$
cases(
  E_"min" <= sum_(t in T_(h,d)) p[t] <= E_"max" & "(3.4)" ,
  P_"min" <= p[t] <= P_"max" & "(3.5)"
)
$

*PV + bateria (BSS):*

$
cases(
  "soc"[t+1] = "soc"[t] + (eta dot.c p_"ch"[t] - 1/eta dot.c p_"dch"[t]) dot.c Delta t & "(3.6)" ,
  0 <= p_"ch"[t] <= P_"pv"[t] <= P_"max,b" & "(3.7)" ,
  0 <= p_"dch"[t] <= P_"max,b" & "(3.8)" ,
  E_"min,b" <= "soc"[t] <= E_"max,b" & "(3.9)"
)
$

Implementação: `src/devices/` — `Thermostatic`, `Deferrable`, `PVBattery` chamados via `contribute!` em `solve_welfare`.

== Funções de utilidade (quadráticas, convexas, sem binários)

$
"Interruptível": U_(h,d)(p) = sum_t [a dot.c p[t] - b/2 p[t]^2] quad "(3.10)"
$
$
"Termostática": U(T_"in") = c - b/2 sum_t (T_"in"[t] - T_"min"[t])^2 quad "(3.11)"
$
$
"Programável": U(p) = c - b/2 (sum p[t] - E_"max")^2 quad "(3.12)"
$
$
a = lambda_"max" + P_"min" dot.c b ; quad b = (lambda_"max" - lambda_"min") / (P_"max" - P_"min") quad "(3.13–3.14)"
$

*Bateria:*

$
U_"ch"(p_"ch") = sum_t [a_"ch" dot.c p_"ch" - b_"ch"/2 p_"ch"^2] quad "(3.15)"
$
$
C_"dch"(p_"dch") = sum_t [a_"dch" dot.c p_"dch" + b_"dch"/2 p_"dch"^2] quad "(3.16)"
$
$
a_"ch" = lambda_"med"; quad b_"ch" = (lambda_"med" - lambda_"min")/P_"max,b"; quad a_"dch" = lambda_"med"; quad b_"dch" = (lambda_"max" - lambda_"med")/P_"max,b" quad "(3.17–3.20)"
$

$lambda_"med"$ = preço de indiferença (sem carga/descarga). Com $lambda_"min" <= lambda_"med" <= lambda_"max"$, o *Apêndice C da tese prova* que $p_"ch"$ e $p_"dch"$ não podem ambos ser positivos no ótimo — *sem complementaridade, sem binários*. (Crítico para a portabilidade.)

== Agregação do agregador

$
U_(a g_j)(p_"ag") = sum_(h in H_j) [U_"ch" - C_"dch" + sum_d (U_(h,d)(p) + U_(h,d)(T_"in"))] quad "(3.21)"
$
$
p_(a g_j)[t] = sum_(h in H_j) (p_"ch" - p_"dch" - P_"pv" + sum_d p_(h,d) + sum_(d c) p_(h,d c)) quad "(3.22)"
$
$
q_(a g_j)[t] = sum_(h in H_j) (sum_d p_(h,d) dot.c sqrt(1 - phi^2)/phi + sum_(d c) p_(h,d c) dot.c sqrt(1 - phi^2)/phi) quad "(3.23)"
$

$p_(a g_j) > 0$ = consumo líquido. $phi$ = fator de potência ($in 0,85..0,95$). Baterias são potência ativa apenas.

== Rede — Branch Flow Model com relaxação SOC + exatidão LinDistFlow

$v_i$ = tensão ao quadrado ($v_0$ fixada), $l_(i,j)$ = corrente ao quadrado, $P_(i,j), Q_(i,j)$ = fluxos de trecho.

$
p_0[t] = P_(0,1)[t]; quad q_0[t] = Q_(0,1)[t] quad "(3.29–3.30)"
$

$
R_(p,j)[t] = P_(i j) - r_(i j) dot.c l_(i j) - p_(a g_j)[t] - sum_(m : j -> m) P_(j m) = 0 quad "(balanço ativo, 3.31)"
$

$
R_(q,j)[t] = Q_(i j) - x_(i j) dot.c l_(i j) - q_(a g_j)[t] - sum_(m : j -> m) Q_(j m) = 0 quad "(balanço reativo, 3.32)"
$

$
v_j = v_i - 2(r_(i j) P_(i j) + x_(i j) Q_(i j)) + (r_(i j)^2 + x_(i j)^2) dot.c l_(i j) quad "(queda de tensão, 3.33)"
$

$
l_(i j) = (P_(i j)^2 + Q_(i j)^2) / v_i quad "(NÃO CONVEXA, 3.34)"
$

$
V_"min"^2 <= v_i <= V_"max"^2 quad "(limites de tensão, 3.35)"
$

$
S_"max,i j"^2 >= P_(i j)^2 + Q_(i j)^2 quad "(frente)" ; quad >= P_(j i)^2 + Q_(j i)^2 quad "(trás) — (3.36–3.37)"
$

*Relaxação SOC* de (3.34):

$
l_(i j) dot.c v_i >= P_(i j)^2 + Q_(i j)^2 quad "(3.39)"
$

*Truque de exatidão* via uma cópia paralela *sem perdas* (LinDistFlow) $hat(P), hat(Q), hat(v)$ com o limite superior de tensão aplicado a ambas:

$
hat(v)_j = hat(v)_i - 2[r_(i j)(P_(i j) + r_(i j) dot.c l_(i j)) + x_(i j)(Q_(i j) + x_(i j) dot.c l_(i j))] quad "(cópia de exatidão, 3.43)"
$

$
V_"min"^2 <= v_i, hat(v)_i <= V_"max"^2 quad "(limites em ambas as cópias, 3.45)"
$

Com (3.45), (3.34) vale com igualdade no ótimo (relaxação exata). *Essencial* — sem isso os preços DADP são sem sentido. O construtor está em `src/powerflow/ConvexBranchFlow.jl` (struct `ConvexBranchFlow`).

== Problema global — bem-estar social de nível único

$
"GLB-OPT:" quad max sum_(j in N) U_(a g_j)(p_"ag") - lambda_0^T dot.c p_0 quad "(3.38)"
$
sujeito a (3.2)–(3.9), (3.22)–(3.23), (3.29)–(3.37).

$
"GLB-CVX:" quad "mesmo objetivo, relaxado por SOC + exatidão LinDistFlow (convexo: LP + QP + SOCP)"
$

Objetivo = bem-estar social = utilidade total dos prosumers $-$ custo de compra do DSO na MEM ($lambda_0^T p_0$). Implementado em `src/models/welfare_solve.jl::solve_welfare`.

== Decomposição ADMM (o resolvedor real)

$lambda_j[t]$ (ativo) e $mu_j[t]$ (reativo) são as variáveis duais, $rho > 0$ é a penalidade. *$lambda_j$ é o DADP.*

*AGR-OPT* (por nó, paralelo, QP; separável por casa):

$
max U_(a g_j)(p_"ag") - lambda_j^T dot.c p_"ag" - rho/2 norm(R_(p,j))^2 quad "sujeito a (3.2)–(3.9)" quad "(3.46)"
$

*DSO-OPT* (por hora, SOCP):

$
min lambda_0[t] dot.c p_0[t] - sum_j {lambda_j[t] dot.c R_(p,j)[t] + mu_j[t] dot.c R_(q,j)[t] + rho/2 (R_(p,j)[t]^2 + R_(q,j)[t]^2)} quad "(3.47)"
$

sujeito a (3.29)–(3.33), (3.36)–(3.37), (3.39), (3.43), (3.45).

*Atualização dual:*

$
lambda_j^(k+1) = lambda_j^k + rho dot.c R_(p,j); quad mu_j^(k+1) = mu_j^k + rho dot.c R_(q,j)
$

Converge quando $abs(R_(p,j)[t]) <= epsilon$ e $abs(R_(q,j)[t]) <= epsilon$ $forall t, j$. Parâmetros típicos: $rho = 1000$, $epsilon = 5 times 10^-5$, $approx 28$ iterações. Na convergência (3.34) vale com igualdade $arrow.r$ ótimo global; $lambda_j$ = DADP final.

Implementação: `src/admm/`. Os modelos são *construídos uma vez* e resolvidos novamente via `Parameter`s / `set_parameter_value` do JuMP — nunca reconstruídos dentro do loop (a disciplina construir-uma-vez; Pitfall M1 do projeto).

== Benchmark FIT (tarifa de inserção alemã)

Para demonstrar que o DADP *aumenta* o bem-estar social, a tese compara contra um baseline FIT-OPT por prosumer (eq. 3.24–3.28) — um esquema sem rede onde cada casa se agenda contra tarifas fixas $lambda_"im", lambda_e, lambda_s$. A implementação em `src/pricing/fit.jl::_fit_opt_solve` resolve o agendamento FIT-OPT por prosumer (sem rede, sem bateria); o script então despacha esse agregado através de um AC-PF DistFlow com perdas em um alimentador com *tensão relaxada* (a tese "observa 3.35 não imposto") e *limite térmico do trecho de cabeça relaxado* — o schedule FIT é cego à rede e seria INFACTÍVEL de outra forma, o que é *a própria crítica da tese ao FIT*. O bem-estar social FIT é

$
W_"FIT" = sum_j U_"flex,j" - sum_t lambda_0[t] dot.c p_"import"[t]
$

onde $p_"import"$ é o intercâmbio de fronteira com perdas do AC-PF (não um abate sem perdas). A tese relata $W_"DADP" / W_"FIT" approx 1,25$ (+25%) no Caso A calibrado.

= Cenário Caso A — IEEE-13 modificado

O Caso A (pp. 89–123 da tese) é o resultado canônico da camada operacional:

#table(
  columns: (auto, 1fr),
  align: (left, left),
  stroke: none,
  [*Parâmetro*], [*Valor (Caso A da tese)*],
  [Alimentador], [IEEE-13 modificado, 11 nós (nó 0 = fronteira MEM + 10 nós de carga)],
  [Tensão], [13,2 kV; banda $V in 0,95..1,05$ pu],
  [Limite aparente], [$S_"max,01" = 6,86$ MVA no trecho de cabeça (congestionado)],
  [Agregadores], [10 (um por nó de carga)],
  [Casas], [784 (aprox. 78/nó)],
  [PV], [5 MWp],
  [Cargas elásticas], [6,5 MW],
  [Cargas inelásticas], [1,5 MW],
  [Horizonte], [24 h dia-à-dia, $Delta t = 1$ h],
  [Preço MEM], [$lambda_0[t]$ da Fig. 4.5 da tese (digitizado)],
  [Preferência de preço], [$lambda_"max" = 8,9$; $lambda_"min" = 3,8$; $lambda_"med" = 6,2$ ¢/kWh],
  [Característica], [Congestionamento-dirigido (não tensão)],
)

Os resultados publicados (DADP vs FIT):

- *Bem-estar social* +25% ($1457 arrow.r 1819$ USD).
- *Excedente do DSO* $-2829 arrow.r +439$ USD.
- *Excedente do prosumer* $-68$%.
- Relaxação SOCP exata confirmada; $v_9[16] = 1,0493$ (perto do limite 1,05).
- ADMM converge em 28 iterações.

= Como reproduzir

== Pré-requisitos

- Julia $>= 1,10$ (LTS) com o ambiente do projeto: ative com `julia --project=.` na raiz do repositório. As dependências (JuMP, Clarabel, CairoMakie, DrWatson, …) estão fixadas em `Project.toml`/`Manifest.toml`.
- Sem passos de instalação externos — os solvers (Clarabel, HiGHS, Ipopt) vêm como pré-compilados via `*_jll`.

== Executando

```bash
julia --project=. scripts/thesis_caseA.jl
```

O script:

+ Ativa o projeto DrWatson (`@quickactivate "TSODSO"`).
+ Constrói o alimentador via `build_feeder(:ieee13)`, a população via `build_population(:default, ...)`, e o preço MEM via `build_price(:mem, T, nothing)` (Fig. 4.5 digitizada).
+ Resolve o ótimo de bem-estar DADP (`solve_welfare` — GLB-CVX SOCP, eq. 3.38) e o baseline FIT.
+ Extrai DADP (`extract_dlmp`), a decomposição DLMP em quatro termos (`decompose_dlmp`), a contabilidade de bem-estar (`welfare_accounting`), o intercâmbio de fronteira, e o certificado de exatidão SOCP (`meta[:socp_maxgap]`).
+ Renderiza seis figuras (PDF + PNG) em `results/thesis_caseA/`.

== Aviso de escala (importante)

A população `:default` do repositório é um *proxy redimensionado de 1-casa-por-nó* para o caso de 784 casas — magnitudes por-unidade consistentes, mas a população está em escala reduzida. Consequentemente:

- As *formas* (perfis DADP, decomposição DLMP, comportamento de tensão) são reproduzidas fielmente.
- A *razão DADP/FIT* neste proxy fica $approx 1,0$ (não os 1,25 da tese), porque a lacuna de bem-estar entre FIT e DADP só se abre na calibração completa das 784 casas.
- Para aproximar a magnitude da tese, escale a bateria/população (helper `flexibility_population` em `scripts/demo_flexibility_plots.jl`).

Isso espelha o próprio enquadramento da tese (Pitfall 4 da pesquisa): o bem-estar absoluto é limitado pela figura; a *razão* é a alegação confiável.

= Figuras e interpretação

As seis figuras abaixo são geradas automaticamente por `scripts/thesis_caseA.jl` e residem em `results/thesis_caseA/` (versões PDF e PNG). As versões PNG estão embutidas aqui.

== Figura A — DADP vs preço MEM $lambda_0$

#image("../../results/thesis_caseA/figA_dadp_vs_mem.png", width: 100%)

*Interpretação:* o sinal transativo. Em cada nó de agregador, o DADP *sobe acima* de $lambda_0$ em congestão / alta demanda (curtail, recompensa descarga da bateria) e *cai abaixo* em sobre-geração de PV (absorve PV). A curva tracejada preta é o preço MEM $lambda_0$ — o sinal TSO. As curvas coloridas são os DADPs locais por barra — uma *DLMP*, não uma tarifa única.

== Figura A2 — Dispositivos flexíveis no nó 9

#image("../../results/thesis_caseA/figA2_devices_node9.png", width: 100%)

*Interpretação:* o despacho por dispositivo no nó 9 da tese (índice estrutural 10) sob a tarifa DADP. (a) O DADP local que os dispositivos veem. (b) Carga termostática A/C: pré-resfria antes do pico de calor. (c) Carga postergável despachada em sua janela. (d) Bateria PV: carrega da PV do meio-dia, descarrega no pico de preço noturno. O DADP *coordena* esses dispositivos — cada um responde ao mesmo sinal de preço local.

== Figura B — Decomposição DLMP em quatro termos

#image("../../results/thesis_caseA/figB_dlmp_decomposition.png", width: 100%)

*Interpretação:* energia + perda + congestionamento + tensão = DADP (média sobre as barras). O componente de *congestionamento* domina no trecho de cabeça sob carga — é o termo que torna o DADP um DLMP (preço locacional) em vez de uma tarifa plana. O termo de tensão reflete a restrição (3.45) ativa no pior barramento perto do limite 1,05.

== Figura C — Perfil de tensão no pior barramento

#image("../../results/thesis_caseA/figC_voltage_profile.png", width: 100%)

*Interpretação:* magnitude de tensão $abs(V)$ ao longo do dia em cada barra de agregador; banda de 0,95 a 1,05 pu sombreada. O pior barramento (destacado) permanece *dentro* da banda mas aproxima-se do limite superior perto do pico noturno — o comportamento relatado pela tese ($v_9[16] approx 1,0493$). Esta é a evidência visual da exatidão SOCP: a relaxação é justa, então os perfis de tensão são fisicamente significativos.

== Figura D — DADP vs FIT: bem-estar e divisão de excedente

#image("../../results/thesis_caseA/figD_dadp_vs_fit_surplus.png", width: 100%)

*Interpretação:* (a) bem-estar social total sob cada esquema, com a razão $+X%$ anotada. (b) divisão do excedente entre prosumer e DSO. No Caso A calibrado da tese, DADP *aumenta* o bem-estar social +25% e transforma o excedente do DSO de fortemente negativo (sob FIT) em positivo — o DSO deixa de subsidiar a injeção de PV cega à rede.

== Figura E — Intercâmbio na fronteira TSO$arrow.l.r$DSO

#image("../../results/thesis_caseA/figE_frontier_exchange.png", width: 100%)

*Interpretação:* perfil de importação/exportação na fronteira $p_0$ ao longo do dia. Sob DADP (linha sólida) o DSO *otimamente* negocia — importa no vale, exporta no pico de PV. Sob FIT (tracejado) os prosumers se auto-agendam contra tarifas fixas e o residual é despejado na MEM, resultando em um perfil mal-coordenado (e frequentemente infactível sem o relaxamento intencional do AC-PF).

== Figura F — Superfície DADP (barras $times$ horas)

#image("../../results/thesis_caseA/figF_dadp_heatmap.png", width: 100%)

*Interpretação:* a *superfície de preço transativo completa* — DADP em cada barra de agregador (eixo y) ao longo de cada hora (eixo x). Os pontos quentes mostram congestão localizada; os pontos frios mostram excesso de PV. Esta é a principal deliverable de pricing: uma tarifa nodal horária derivada puramente dos duais da rede.

= Resultados e validação

== O que o script imprime

Ao rodar `julia --project=. scripts/thesis_caseA.jl`, o log do console reporta (para a população `:default` redimensionada):

- `welfare (social)` — ótimo de bem-estar DADP.
- `prosumer surplus`, `dso surplus` — divisão de excedente DADP.
- `SOCP exactness` — o certificado `socp_maxgap` (relaxação justa; alvo $<< 10^-3$).
- `peak DADP` vs `lambda_0 peak` — a faixa dinâmica do sinal de preço.
- `welfare (FIT)` e `DADP/FIT ratio` — a comparação de referência.

== Alegações reproduzíveis vs limitadas pela figura

#table(
  columns: (1fr, 1fr, 1fr),
  align: (left, left, left),
  stroke: none,
  [*Alegação da tese*], [*Alvo publicado*], [*Status neste repo*],
  [Forma DADP sobe acima / cai abaixo de $lambda_0$], [Qualitativo], [Reproduzido (Fig. A)],
  [Decomposição DLMP: congestão domina sob carga], [Qualitativo], [Reproduzido (Fig. B)],
  [Exatidão SOCP], [$v_9[16] approx 1,0493$], [Reproduzido (certificado $<< 10^-3$)],
  [Tensão no pior barramento perto de 1,05], [$approx 1,05$ pu], [Reproduzido (Fig. C)],
  [Despacho coordenado de dispositivos no nó 9], [Qualitativo], [Reproduzido (Fig. A2)],
  [Perfil de intercâmbio coordenado vs descoordenado], [Qualitativo], [Reproduzido (Fig. E)],
  [Superfície DADP nodal], [Qualitativo], [Reproduzido (Fig. F)],
  [Razão DADP/FIT], [$approx 1,25$], [Escala-dependente — $approx 1,0$ no proxy `:default`; escale a população para reproduzir],
)

== Limites (quando o modelo falha)

- *Relaxação SOCP não exata:* se `socp_maxgap` for grande ($>> 10^-3$), o DADP é sem sentido. Solução: ative a *cópia de exatidão LinDistFlow* (3.43–3.45) — já ativa por padrão em `ConvexBranchFlow()`. Verifique com `ctx.meta[:socp_maxgap]`.
- *População muito pequena:* a razão DADP/FIT colapsa perto de 1,0. Solução: escale via `flexibility_population` ou use um cenário calibrado de 784 casas.
- *ADMM não converge:* reduza $rho$ ou aumente o máximo de iterações; verifique os resíduos $R_(p,j), R_(q,j)$.

= Notas de implementação

- *Construir-uma-vez, resolver-muito:* o modelo `GLB-CVX` é construído uma vez em `solve_welfare` e resolvido novamente via `Parameter`s / `set_parameter_value` — a mesma disciplina da camada ADMM. Nunca reconstrua o modelo dentro de um loop.
- *Sem binários em qualquer lugar:* o esquema de coeficientes $lambda_"min" <= lambda_"med" <= lambda_"max"$ das eq. 3.17–3.20 garante complementaridade da bateria automaticamente (Apêndice C da tese).
- *Solver-abstraction:* todos os modelos recebem um otimizador via `select_optimizer(problem_class(PF))`. Clarabel é o padrão conic; HiGHS para LP/MILP; Ipopt para o oráculo AC-PF do baseline FIT. Nenhum modelo nomeia um solver diretamente.
- *Reprodutibilidade:* `DrWatson.@quickactivate` fixa o ambiente; a geração de perfis/demanda é via `generate_profiles(; seed = sub_seed(SEED, :profiles), T = T)` — determinístico dado a seed.

#v(1em)
#line(length: 100%, stroke: 0.4pt + gray)
#v(0.3em)
#text(size: 8.5pt, fill: gray)[
  *Referências:* \
  Palacios, J. P. _Tese de Doutorado_, UNSJ/CONICET, 2022, Capítulo 3 (formulação) e §4.1 Caso A (pp. 89–123). \
  Palacios, Samper, Vargas. "Dynamic transactive energy scheme for smart distribution networks in a Latin American context," _IET Generation, Transmission & Distribution_ 13(9):1481–1490, 2019. \
  Implementação: `src/models/welfare_solve.jl`, `src/admm/`, `src/pricing/{dlmp,fit,welfare}.jl`, `src/powerflow/ConvexBranchFlow.jl`, `src/devices/`; script driver `scripts/thesis_caseA.jl`; figuras em `results/thesis_caseA/`. \
  Documento irmão sobre a camada de planejamento: `modelo_stackelberg_dso_unico.typ`.
]

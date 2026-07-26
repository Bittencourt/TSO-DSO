#set page(
  paper: "a4",
  margin: (x: 2.2cm, y: 2.4cm),
  header: context {
    if counter(page).get().first() > 1 [
      #set text(size: 8pt, fill: gray)
      _Modelo de Equilíbrio de Stackelberg com um Único DSO_
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
  #text(size: 20pt, weight: "bold")[Modelo de Equilíbrio de Stackelberg com um Único DSO]
  #v(0.3em)
  #text(size: 12pt, fill: gray)[Formulação completa do problema de otimização bilevel]
  #v(0.8em)
  #line(length: 60%, stroke: 0.5pt + gray)
  #v(0.8em)
]

_Trabalho derivado da implementação em Julia (módulo `src/planning/` do projeto TSO-DSO), resolvida via decomposição de Benders em `solve_stackelberg!` (`src/planning/benders.jl`)._

#v(0.3em)

O modelo reside na *camada de planejamento* e representa o equilíbrio de Stackelberg–Nash entre TSO e DSO descrito na nota PSR (Paper 2 em `THEORY-papers.md`). É um problema *bilevel*: o distribuidor (DSO) é o _líder_ que investe em flexibilidade $y_"inv"$ e escolhe um perfil de importação $z[t]$; o sistema de transmissão é o _seguidor_ que investe em reforço de corredor para entregar essa importação. A decomposição de Benders decompõe o problema em um mestre (o líder) e dois subproblemas (o oráculo operacional e o seguidor de transmissão).

= Conjuntos e índices

#table(
  columns: (auto, 1fr),
  align: (left, left),
  stroke: none,
  [*Símbolo*], [*Significado*],
  [$t in {1, dots, T}$], [passos de tempo (horizonte do dia anterior, $T = 24$)],
  [$j in {1, dots, N}$], [barras do alimentador; $j = 1$ = raiz (fronteira MEM)],
  [$(i, j) in cal(B)$], [trechos radiais, pai $i ->$ filho $j$ ($N - 1$ no total)],
)

= Variáveis de decisão

*Líder (mestre):*
- $y_"inv" in [0, y_"max"]$ — investimento em flexibilidade (contínuo)
- $z[t] in [0, y_"inv"]$ — perfil de importação que o líder assume (a *variável de acoplamento*)

*Seguidor (LP de transmissão):*
- $x_"inv" in [0, x_"inv,max"]$ — investimento em reforço de corredor
- $x_"op"[t] >= 0$ — fluxo operacional entregue pelo corredor

*Oráculo (SOCP de bem-estar operacional — formulação ConvexBranchFlow):*
- $v[j, t]$, $hat(v)[j, t]$ — magnitude de tensão ao quadrado, verdadeira / cópia de exatidão
- $P[b, t]$, $Q[b, t]$ — fluxo ativo/reativo do trecho
- $l[b, t] >= 0$ — corrente do trecho ao quadrado
- $p_"import"[t]$ — intercâmbio de fronteira de sinal livre (fixado em $z[t]$)
- $q_"import"[t]$ — fronteira reativa de sinal livre (quando a formulação tem canal reativo)
- variáveis dos dispositivos de cada agregador (potência do A/C, potência postergável, carga/descarga/SOC da bateria)

= O problema bilevel completo

$ "min"_(y_"inv", z) space c_y dot.c y_"inv" + alpha_"op"(z) + alpha_x(z) $

sujeito a:

$ 0 <= z[t] <= y_"inv", quad 0 <= y_"inv" <= y_"max" $

onde as duas funções de custo implícitas são definidas por subproblemas:

== (1) Oráculo de bem-estar operacional — $alpha_"op"(z)$

Esta é `solve_planning_oracle!` — uma versão fixada em $z$ do SOCP de bem-estar GLB-CVX da tese (eq. 3.38). Seu *negativo* é o custo de bem-estar do líder:

$
alpha_"op"(z) = -max[underbrace(sum_j U_(a g_j), "utilidade dos agregados") - sum_t lambda_0[t] dot.c p_"import"[t]]
$

sujeito à rede DistFlow completa + restrições dos dispositivos dos agregadores.

*Rede (ConvexBranchFlow, tese 3.31–3.45):*

$ R_(p,j)[t] = P_(i j) - r_(i j) dot.c l_(i j) - p_(a g_j)[t] - sum_(m : j -> m) P_(j m) = 0 quad "(balanço ativo, 3.31)" $

$ R_(q,j)[t] = Q_(i j) - x_(i j) dot.c l_(i j) - q_(a g_j)[t] - sum_(m : j -> m) Q_(j m) = 0 quad "(balanço reativo, 3.32)" $

$ v_j = v_i - 2(r_(i j) P_(i j) + x_(i j) Q_(i j)) + (r_(i j)^2 + x_(i j)^2) dot.c l_(i j) quad "(queda de tensão, 3.33)" $

$ l_(i j) dot.c v_i >= P_(i j)^2 + Q_(i j)^2 quad "(relaxação SOC, 3.39)" $

$ hat(v)_j = hat(v)_i - 2[r_(i j)(P_(i j) + r_(i j) dot.c l_(i j)) + x_(i j)(Q_(i j) + x_(i j) dot.c l_(i j))] quad "(cópia de exatidão, 3.43)" $

$ V_"min"^2 <= v_j, hat(v)_j <= V_"max"^2 quad "(limites de tensão, 3.45)" $

$ P_(i j)^2 + Q_(i j)^2 <= S_"max,i j"^2 quad "(limite de potência aparente, 3.36; apenas trecho de cabeça)" $

*Agregadores (tese 3.21–3.23):*

$ p_(a g_j)[t] = sum_(h in H_j)(p_"ch" - p_"dch" - p_"pv" + sum_d p_(h,d)) - P_"dc,j"[t] $

$ q_(a g_j)[t] = -P_"dc,j"[t] dot.c tan(arccos phi) $

além das restrições temporais de cada dispositivo (recursão de SOC 3.6, termostático 3.2–3.3, postergável 3.4–3.5) — reutilizando `contribute!` literalmente de `solve_welfare`.

*A costura de acoplamento de Benders (D-01):*

$ p_"import"[t] = z[t] quad "(o pino cujo dual " pi[t] " é o gradiente do corte de Benders)" $

Portanto, $alpha_"op"(z)$ é o *bem-estar ótimo negado* quando a importação de fronteira é forçada a igualar o $z$ escolhido pelo líder. Seu gradiente $nabla alpha_"op"(z) = pi[t]$ vem do dual da restrição de pino.

== (2) Seguidor de reforço de transmissão — $alpha_x(z)$

Esta é `solve_follower!` (`follower.jl`) — um pequeno LP:

$ alpha_x(z) = "min"_(x_"inv", x_"op") space c_"inv" dot.c x_"inv" + sum_t c_"op"[t] dot.c x_"op"[t] $

sujeito a:

$ x_"op"[t] <= "corridor_cap" dot.c x_"inv" quad "(capacidade por unidade de investimento)" $

$ x_"op"[t] = z[t] quad "(acoplamento: entregar a importação do líder)" $

$ 0 <= x_"inv" <= x_"inv,max", quad x_"op"[t] >= 0 $

Seu dual de acoplamento $pi_s[t]$ = dual de $x_"op"[t] = z[t]$ = *custo marginal de reforço* de uma unidade a mais de importação. Se $z$ for *inentregável* (nenhum reforço pode carregá-lo), o seguidor retorna um *certificado de Farkas* $(v, u)$ em vez disso → um corte de factibilidade no mestre.

= Como Benders resolve o problema (o loop `solve_stackelberg!`)

Como $alpha_"op"(z)$ e $alpha_x(z)$ são funções de valor convexas (mínimo de LP/SOCP), Benders as substitui por *variáveis de epígrafo + cortes* e resolve uma sequência de LPs mestres:

== LP Mestre (construído uma vez, cortes acrescentados — `master.jl`)

$ "min"_(y_"inv", z, alpha_"op", alpha_x) space c_y dot.c y_"inv" + alpha_"op" + alpha_x $

sujeito a:

$ 0 <= z[t] <= y_"inv", quad 0 <= y_"inv" <= y_"max" $

$ alpha_"op" >= alpha_"op,lb", quad alpha_x >= alpha_"x,lb" quad "(limites inferiores finitos — evita infactibilidade dual na 1ª iteração, Pitfall M1)" $

*Cortes de otimalidade* (acrescentados a cada iteração factível $k$, um por subproblema — Benders *multi-corte*):

$ alpha_"op" >= -"oracle_cost"_k + sum_t pi_k[t] dot.c (z[t] - z_k[t]) $

$ alpha_x >= "follower_cost"_k + sum_t pi_(s,k)[t] dot.c (z[t] - z_k[t]) $

*Cortes de factibilidade* (quando $z_k$ é inentregável, do raio de Farkas do seguidor):

$ v_k + sum_t u_k[t] dot.c (z[t] - z_k[t]) <= 0 $

== A iteração

+ Resolva o mestre → obtenha $z_k$ e o LB (objetivo do mestre, um limite inferior).
+ Resolva o seguidor($z_k$):
  - Se INFACTÍVEL → adicione corte de factibilidade, *continue* (nunca atualiza UB, nunca chama o oráculo).
  - Caso contrário → obtenha o custo e o gradiente $pi_(s,k)$.
+ Resolva o oráculo($z_k$) → obtenha o custo e o gradiente $pi_k$. \
  Adicione cortes de otimalidade em $alpha_"op"$ e $alpha_x$.
+ Custo verdadeiro $= c_y dot.c y_k + "follower_cost" - "oracle_cost"$ → candidato a UB (incumbente).
+ Intervalo $= (U B - L B) \/ max(1, |U B|)$; pare se intervalo $<= 10^(-6)$.

- *LB* (objetivo do mestre) sobe por baixo à medida que os cortes se acumulam.
- *UB* (melhor custo verdadeiro encontrado) desce por cima.
- Converge para o *incumbente* $(y_"best", z_"best")$ — o iterado que alcançou UB, não o último iterado.

= Resultado

O equilíbrio que o modelo retorna:

$ (y_"inv"^*, z^*) = "argmin" space {c_y y_"inv" + alpha_"op"(z) + alpha_x(z)} $

é o *equilíbrio de Stackelberg*: o investimento em flexibilidade e o perfil de importação ótimos do distribuidor, *antecipando* a resposta de reforço do sistema de transmissão. O dual $pi_s[t]$ no ótimo é o *custo marginal de reforço de interconexão* — o sinal de TUST (tarifa de uso do sistema de transmissão).

No caso de múltiplos distribuidores (`coupling.jl`), uma diagonalização de Gauss–Seidel sobre o Stackelberg de cada distribuidor converge para o *equilíbrio de Nash*.

= Notas de implementação

- O oráculo reutiliza literalmente os construtores de `solve_welfare` (`contribute!(pf, dots)`, `contribute!(agg, dots)`) — o subproblema da camada de planejamento *é* a resolução de bem-estar DADP, parametrizada na importação via a restrição de pino.
- Todos os três modelos são *construídos uma vez* e resolvidos novamente via `Parameter`s / `set_parameter_value` do JuMP — nunca reconstruídos dentro do loop (espelha a disciplina de construir-uma-vez da camada ADMM).
- Sem variáveis binárias em lugar algum (investimento contínuo + fluxos contínuos) — LP/SOCP puro, então Benders converge finitamente com o teste de intervalo relativo.

#v(1em)
#line(length: 100%, stroke: 0.4pt + gray)
#v(0.3em)
#text(size: 8.5pt, fill: gray)[
  *Referências:* \
  Palacios, J. P. _Tese de Doutorado_, UNSJ/CONICET, 2022, Capítulo 4. \
  Nota PSR: "Reforços interconexões N1–N2 via Stackelberg + Nash" (Português). \
  Implementação: `src/planning/` no projeto TSO-DSO (`master.jl`, `follower.jl`, `subproblem.jl`, `benders.jl`).
]

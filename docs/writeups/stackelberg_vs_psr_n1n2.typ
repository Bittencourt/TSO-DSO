#set page(
  paper: "a4",
  margin: (x: 2.2cm, y: 2.4cm),
  header: context {
    if counter(page).get().first() > 1 [
      #set text(size: 8pt, fill: gray)
      _Nota PSR N1-N2 ↔ Camada de Planejamento Implementada_
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

// Tabelas: nunca usar `auto` em colunas de texto longo — uma coluna `auto`
// larga colapsa as colunas `fr` a largura zero (texto sobreposto/embaralhado).
#show table: set text(size: 9pt)
#set table(inset: 5pt)

#align(center)[
  #text(size: 20pt, weight: "bold")[Nota PSR N1-N2 ↔ Camada de Planejamento Implementada]
  #v(0.3em)
  #text(size: 12pt, fill: gray)[Mapeamento termo-a-termo entre "Reforços interconexões N1-N2 através de equilíbrios de Stackelberg e Nash" (PSR, jun. 2026) e `src/planning/`]
  #v(0.8em)
  #line(length: 60%, stroke: 0.5pt + gray)
  #v(0.8em)
]

_Trabalho derivado da leitura direta de `docs/references/Expansão-N1-N2-EquilibriosStackelberg-Nash-v2 (1).pdf` (nota interna PSR, 9 pp., jun. 2026) e da implementação em Julia do módulo `src/planning/` do projeto TSO-DSO (`master.jl`, `follower.jl`, `subproblem.jl`, `benders.jl`, `coupling.jl`, `nash.jl`), resolvida via decomposição de Benders + diagonalização de Gauss-Seidel._

#v(0.3em)

= Resumo

Este documento é o *complemento*, não o substituto, de `modelo_stackelberg_dso_unico.typ` (que já narra a implementação da camada de planejamento em prosa livre). Aqui o objetivo é mais estrito: para *cada* equação da nota PSR — problemas (1), (2), (4), (7) e a extensão inteira (8)-(9), com seus rótulos `(1a)`-`(1j)`, `(2a)`-`(2e)`, `(4a)`-`(4f)` — apontar o construtor Julia específico (arquivo + nome da variável/restrição) que a realiza, ou declarar explicitamente que ela ainda não foi implementada. Nenhuma equação da nota é omitida silenciosamente: cada uma recebe uma etiqueta explícita *Equivalente*, *Desvio deliberado* ou *Não implementado*.

A nota PSR foi lida diretamente do PDF primário (não apenas do dígest condensado em `.planning/research/THEORY-papers.md`) — ver a nota de leitura na @sec-estrutura sobre uma discrepância encontrada entre o dígest e a fonte primária quanto aos rótulos N1/N2.

= Conjuntos e índices

#table(
  columns: (auto, 1fr, 1fr),
  align: (left, left, left),
  stroke: 0.4pt + gray,
  [*Nota PSR*], [*Significado (PSR)*], [*Contraparte no repositório*],
  [$s in S$], [índice de cenário (a nota pondera por $1/S$ em toda parte)], [*Não implementado* — o repositório não tem índice de cenário; cada iteração de Benders (`solve_stackelberg!`) resolve um *trial determinístico único* `z_k`, não uma expectativa $ (1/S) sum_s (dot) $. Ver `INT-STRETCH`/análise de estocasticidade em `STATE.md` (fora do escopo desta nota).],
  [N1], [sistema de transmissão (variáveis $x$)], [`follower.jl` — `FollowerLP` (`x_inv`, `x_op[t]`)],
  [N2], [distribuidora (variáveis $y$, $z$)], [`master.jl` — `BendersMaster` (`y_inv`, `z[t]`) + `subproblem.jl` — `PlanningOracle` (a operação de N2)],
  [primeiro nível / líder], [problema (4), a distribuidora], [`master.jl` — `BendersMaster`, resolvido por `solve_master!`],
  [segundo nível / seguidor], [problema (2), o sistema de transmissão], [`follower.jl` — `FollowerLP`, resolvido por `solve_follower!`],
  [—], [não há um terceiro nível explícito na nota — a operação de N2 (eq. 1f) entra linearmente no objetivo do líder], [`subproblem.jl` — `PlanningOracle`: um SOCP de bem-estar completo (tese eq. 3.31–3.45) que a nota PSR trata apenas como um balanço linear abstrato; o repositório precisa de um *terceiro* subproblema porque essa operação deixou de ser linear],
)

= Estrutura do jogo <sec-estrutura>

== Nota de leitura: os rótulos N1/N2 e líder/seguidor

O parágrafo introdutório da nota PSR (p. 3) é explícito: _"...reforços nas interligações para importação de energia das distribuidoras (N2) do sistema de transmissão (N1)..."_ — ou seja, *N1 = sistema de transmissão*, *N2 = distribuidora*. Essa correspondência é usada de forma consistente em todo o documento: "(1a) e (1d) representam restrições de investimentos em N1 e N2, respectivamente" (as variáveis $x$ ficam com N1; as variáveis $y$ com N2), e mais adiante, de forma explícita: _"Problema (4) pode ser interpretado como o problema de líder ou de primeiro nível de Stackelberg e o problema (2) como o problema de segundo nível."_ Como o problema (4) é o problema-$y$ (distribuidora/N2) e o problema (2) é o problema-$x$ (transmissão/N1), a nota primária é *internamente consistente*: distribuidora (N2, $y$) = líder = primeiro nível; transmissão (N1, $x$) = seguidor = segundo nível.

#text(fill: gray)[_Achado de leitura:_ o dígest em `.planning/research/THEORY-papers.md` (linha 29) parafraseia essa correspondência *invertida* ("N1 = distribution side; N2 = transmission side") — uma transcrição equivocada do dígest, não uma ambiguidade genuína da nota primária. A correspondência de variáveis usada pelo próprio dígest (`x_inv,x_op,s` ↔ N1/transmissão; `y_inv,y_op,s` ↔ N2/distribuidora) já está correta; apenas a frase de abertura do dígest inverteu os rótulos textuais N1/N2. Este documento adota a leitura direta da fonte primária — a MESMA leitura que a implementação já assume: `master.jl` (variáveis $y$) = líder = distribuidora; `follower.jl` (variáveis $x$) = seguidor = transmissão.]

== Uma distribuidora → Stackelberg

Problema (4) (líder, distribuidora/N2) vs. problema (2) (seguidor, transmissão/N1) $arrow.r$ `solve_stackelberg!` (`benders.jl`): a cada iteração $k$, resolve o mestre (`solve_master!`), depois o seguidor no trial $z_k$ (`solve_follower!`), depois — se o seguidor for factível — o oráculo operacional (`solve_planning_oracle!`), acrescentando cortes de otimalidade ao mestre. Ver @sec-cortes para a derivação completa do laço.

== Múltiplos distribuidores → Nash via diagonalização de Gauss-Seidel

Problema (7) (equilíbrio de Nash, $I$ distribuidoras) $arrow.r$ `coupling.jl` (`SharedTransmission`, o corredor de transmissão compartilhado) + `nash.jl` (`run_nash!`, o laço externo de diagonalização de Gauss-Seidel). Ver @sec-nash.

= Variáveis — mapeamento lado a lado <sec-vars>

#table(
  columns: (auto, 1.3fr, 1.5fr),
  align: (left, left, left),
  stroke: 0.4pt + gray,
  [*Símbolo PSR*], [*Significado (PSR)*], [*Identificador Julia*],
  [$x_"inv"$], [investimento em reforço de N1 (transmissão)], [`follower.jl` — `FollowerLP.x_inv` (contínuo, `0 <= x_inv <= x_inv_max`)],
  [$x_"op,s"$], [operação de N1 no cenário $s$], [`follower.jl` — `FollowerLP.x_op[t]` (sem índice de cenário — `t` é hora, não cenário)],
  [$y_"inv"$], [investimento genérico de N2 (distribuidora)], [`master.jl` — `BendersMaster.y_inv` (contínuo, `0 <= y_inv <= y_max`)],
  [$y_"op,s"$], [operação genérica de N2 no cenário $s$ (balanço linear abstrato, eq. 1f)], [`subproblem.jl` — `PlanningOracle`: TODA a rede branch-flow SOCP + dispositivos dos agregadores (tese eq. 3.31–3.45) — a operação de N2 real, não abstrata],
  [$y_"inv,flex"$], [investimento *especificamente* em flexibilidade (baterias, agregadores)], [Colapsado em `master.jl`'s `y_inv` — o repositório não distingue investimento "genérico" de N2 de investimento "em flexibilidade"; `y_inv` *é* o investimento em flexibilidade],
  [$z_"flex,s"$], [operação de flexibilidade (fluxo habilitado pela flexibilidade)], [`master.jl` — `BendersMaster.z[t]`, limitado por `box_hi[t]: z[t] <= y_inv`],
  [$z_"x,s"$], [fluxo de exportação de N1 na interligação, cenário $s$], [`follower.jl` — `FollowerLP.z[t]` (`Parameter`, ajustado via `set_parameter_value.` a cada trial de Benders)],
  [$z_"y,s"$], [fluxo de importação de N2 na interligação, cenário $s$], [`master.jl` — `BendersMaster.z[t]` (a MESMA variável física que `subproblem.jl`'s `p_import[t]`, via `pin[t]: p_import[t] == z[t]`)],
  [$pi_s$], [dual do acoplamento (2e) — custo marginal de reforço], [`follower.jl` — `π_s = dual.(f.coupling)`, retornado por `solve_follower!`],
  [$w^k$], [valor ótimo do problema (2) no trial $z^k$ — o termo constante do corte], [`benders.jl` — `follower_res.cost` (passado como `cost_k` a `add_optimality_cut!(master, :x, ...)`)],
)

= Objetivo — comparação

*PSR problema (1), integrado (uma distribuidora):*

$ "Min" { c_"x,inv" x_"inv" + c_"y,inv" y_"inv" + c_"y,inv,flex" y_"inv,flex" + 1/S sum_s (c_"x,op" x_"op,s" + c_"y,op" y_"op,s") } quad "(1)" $

*PSR problema (2), seguidor (N1/transmissão), parametrizado por $z_"y,s"$:*

$ alpha({z_"y,s"}) = "Min" { c_"x,inv" x_"inv" + 1/S sum_s c_"x,op" x_"op,s" } quad "(2)" $

*PSR problema (4), líder (N2/distribuidora), com cortes de Benders:*

$ "Min" { c_"y,inv" y_"inv" + c_"y,inv,flex" y_"inv,flex" + 1/S sum_s c_"y,op" y_"op,s" + alpha } quad "(4)" $

*Repositório — `follower.jl` (segue exatamente a forma de (2)):*

$ alpha_x(z) = "Min"_(x_"inv", x_"op") { c_"inv" dot.c x_"inv" + sum_t c_"op"[t] dot.c x_"op"[t] } $

*Repositório — `master.jl` (o mestre do líder):*

$ "Min"_(y_"inv", z, alpha_"op", alpha_x) { c_y dot.c y_"inv" + alpha_"op" + alpha_x } $

*Repositório — `subproblem.jl` (o oráculo — bem-estar como custo negado):*

$ alpha_"op"(z) = -max [ sum_j U_(a g_j) - sum_t lambda_0 [t] dot.c p_"import"[t] ] $

*Comparação, termo a termo:* $c_"y,inv" y_"inv" + c_"y,inv,flex" y_"inv,flex"$ (PSR, dois termos de investimento) $arrow.r$ `master.jl`'s único termo $c_y dot.c y_"inv"$ — o repositório colapsa os dois investimentos de N2 da nota em um só (*Equivalente*, com o colapso de nomenclatura já documentado em @sec-vars). O termo $(1/S) sum_s c_"y,op" y_"op,s"$ (PSR, custo *linear* abstrato de operação de N2) $arrow.r$ o repositório substitui esse termo pelo *negativo do ótimo de bem-estar* de um SOCP genuíno (`alpha_"op"(z)`), não uma expressão linear — *Equivalente (reforçado)*: o repositório precisa de um epígrafe de Benders para esse termo justamente porque ele deixou de ser linear; a nota PSR não precisa, porque trata $y_"op,s"$ como linear e o inclui diretamente no objetivo do líder. O termo $alpha$ (PSR, único epígrafe cobrindo apenas o custo de reforço de N1) $arrow.r$ `master.jl`'s $alpha_x$ — mapeamento direto (*Equivalente*). O repositório introduz um SEGUNDO epígrafe ($alpha_"op"$) que a nota PSR não tem — ver @sec-cortes para a justificativa completa.

= Restrições — derivação constrangimento-a-constrangimento

== Problema (1) — formulação integrada, uma distribuidora

#table(
  columns: (auto, 1.2fr, 1.4fr, 0.8fr),
  align: (center, left, left, left),
  stroke: 0.4pt + gray,
  [*Eq.*], [*Significado (PSR)*], [*Construtor Julia*], [*Etiqueta*],
  [(1a)], [$A x_"inv" <= b$ — restrições genéricas de investimento em N1 (transmissão).], [`follower.jl`: `0 <= x_inv <= x_inv_max` (`build_follower`).], [Equivalente],
  [(1b)], [$x_"op,s" <= M_x x_"inv"$ — capacidade operacional limitada pelo investimento em N1.], [`follower.jl`: `invest_op[t]: x_op[t] <= corridor_cap * x_inv`.], [Equivalente],
  [(1c)], [$F_x x_"op,s" = d_"x,s"$ — balanço de demanda na rede interna de N1, por cenário.], [Nenhum — `follower.jl` não modela uma rede de transmissão interna, apenas um corredor escalar agregado.], [Desvio deliberado],
  [(1d)], [$B y_"inv" <= h$ — restrições genéricas de investimento em N2 (distribuidora).], [`master.jl`: `0 <= y_inv <= y_max` (`build_master`).], [Equivalente],
  [(1e)], [$y_"op,s" <= M_y y_"inv"$ — operação de N2 limitada pelo investimento.], [`master.jl`: `box_hi[t]: z[t] <= y_inv`.], [Equivalente],
  [(1f)], [$F_y y_"op,s" = d_"y,s"$ — balanço de demanda na rede interna de N2 (a operação real da distribuidora).], [`subproblem.jl`: `balance_p[j,t]`/`balance_q[j,t]` — a rede branch-flow SOCP COMPLETA da tese (eq. 3.31–3.45), com dispositivos dos agregadores.], [Equivalente (reforçado)],
  [(1g)], [$z_"x,s" - H_x x_"op,s" = 0$ — balanço de fronteira em N1.], [`follower.jl`: `coupling[t]: x_op[t] == z[t]` ($H_x$ especializado à identidade).], [Equivalente],
  [(1h)], [$z_"y,s" - H_y y_"op,s" - H_"y,flex" z_"flex,s" = 0$ — balanço de fronteira em N2 + contribuição de flexibilidade.], [`subproblem.jl`: `pin[t]: p_import[t] == z[t]`, combinado com o balanço nodal na barra-raiz (`balance_p[feeder.root,t]`, que já soma todas as contribuições dos agregadores/flexibilidade).], [Equivalente (embutido no balanço de rede, não uma linha $H_y$ separada)],
  [(1i)], [$z_"flex,s" <= H_"y,invflex" y_"inv,flex"$ — operação de flexibilidade limitada pelo investimento em flexibilidade.], [`master.jl`: a MESMA linha `box_hi[t]: z[t] <= y_inv` que realiza (1e) — no repositório, `z[t]` desempenha tanto o papel de $y_"op,s"$ quanto o de $z_"flex,s"$, já que a única operação de N2 modelada no nível do líder É a flexibilidade.], [Equivalente ($H_"y,invflex"$ especializado à identidade)],
  [(1j)], [$z_"x,s" - z_"y,s" = 0$ — acoplamento N1↔N2 (exportação = importação), a ÚNICA restrição que monta o acoplamento explicitamente.], [Nenhuma restrição explícita — `follower.jl` e `subproblem.jl` referenciam a MESMA variável `z[t]` (o `z` do mestre, passado como `z_trial` a ambos os subproblemas a cada iteração de Benders).], [Equivalente (por construção) — o repositório colapsa $z_"x,s"$/$z_"y,s"$ em uma única variável compartilhada, em vez de duas variáveis ligadas por uma igualdade],
)

== Problema (2) — subproblema do seguidor (N1/transmissão), parametrizado por $z_"y,s"$

#table(
  columns: (auto, 1.2fr, 1.4fr, 0.8fr),
  align: (center, left, left, left),
  stroke: 0.4pt + gray,
  [*Eq.*], [*Significado (PSR)*], [*Construtor Julia*], [*Etiqueta*],
  [(2a)], [$A x_"inv" <= b$.], [`follower.jl`: `0 <= x_inv <= x_inv_max`.], [Equivalente],
  [(2b)], [$x_"op,s" <= M_x x_"inv"$.], [`follower.jl`: `invest_op[t]`.], [Equivalente],
  [(2c)], [$F_x x_"op,s" = d_"x,s"$.], [Nenhum — sem rede interna de N1 (mesma lacuna de (1c)).], [Desvio deliberado],
  [(2d)], [$z_"x,s" - H_x x_"op,s" = 0$.], [`follower.jl`: `coupling[t]: x_op[t] == z[t]`.], [Equivalente],
  [(2e)], [$1/S z_"x,s" = 1/S z_"y,s"$, dual $pi_s$ — o acoplamento cujo multiplicador é o custo marginal de reforço.], [`follower.jl`: o MESMO `coupling[t]`, cujo dual é lido em `solve_follower!` como `π_s = dual.(f.coupling)` — exatamente o $pi_s$ da nota.], [Equivalente na forma do multiplicador; Desvio deliberado no fator de escala — sem índice de cenário $s$, sem a média $(1/S) sum_s$: cada iteração de Benders é um trial determinístico único, não uma expectativa],
)

== Problema (4) — mestre do líder (N2/distribuidora), com cortes de Benders

#table(
  columns: (auto, 1.2fr, 1.4fr, 0.8fr),
  align: (center, left, left, left),
  stroke: 0.4pt + gray,
  [*Eq.*], [*Significado (PSR)*], [*Construtor Julia*], [*Etiqueta*],
  [(4a)], [$B y_"inv" <= h$.], [`master.jl`: `0 <= y_inv <= y_max`.], [Equivalente],
  [(4b)], [$y_"op,s" <= M_y y_"inv"$.], [`master.jl`: `box_hi[t]: z[t] <= y_inv`.], [Equivalente],
  [(4c)], [$F_y y_"op,s" = d_"y,s"$.], [`subproblem.jl`: `balance_p`/`balance_q` (a rede branch-flow completa) — a mesma correspondência reforçada de (1f).], [Equivalente (reforçado)],
  [(4d)], [$z_"y,s" - H_y y_"op,s" - H_"y,flex" z_"flex,s" = 0$.], [`subproblem.jl`: `pin[t]` + balanço nodal na raiz — mesma correspondência de (1h).], [Equivalente (embutido)],
  [(4e)], [$z_"flex,s" <= H_"y,invflex" y_"inv,flex"$.], [`master.jl`: `box_hi[t]` — mesma correspondência de (1i).], [Equivalente],
  [(4f)], [$alpha >= w^k + 1/S sum_s pi_s^k (z_"y,s" - z_(y,s)^k), quad k=1,...,K$ — os CORTES DE BENDERS.], [`master.jl`: `add_optimality_cut!` — `α >= cost_k + Σ_t grad_k[t]*(z[t]-z_k[t])`, forma matematicamente idêntica.], [Equivalente na forma; Desvio deliberado na cardinalidade — ver @sec-cortes],
)

== Extensão inteira — problemas (8)-(9)

A nota PSR trata o caso em que $x_"inv"$, $x_"op,s"$ (e o fluxo de interligação, via expansão binária) são variáveis inteiras (Seção 4), formando um MIP (problema 8) resolvido por relaxação Lagrangeana das restrições de cópia (problema 9), com multiplicadores obtidos por maximização do Lagrangeano — a máquina de Stochastic Dual Dynamic Integer Programming / cortes L-shaped inteiros (Zou-Ahmed-Sun 2019; Bansal-Küçükyavuz 2025).

#table(
  columns: (auto, 2fr, 0.8fr),
  align: (center, left, left),
  stroke: 0.4pt + gray,
  [*Eq.*], [*Conteúdo (PSR)*], [*Etiqueta*],
  [(8a)–(8c)], [Restrições de investimento/operação/balanço de N1, herdadas de (1a)–(1c), agora com $x_"inv"$, $x_"op,s"$ possivelmente inteiros.], [Não implementado (`INT-STRETCH`)],
  [(8d)], [$z_"x,s" - H_x x_"op,s" = 0$ (mesma forma de (1g)/(2d)).], [Não implementado (`INT-STRETCH`)],
  [(8e)], [Expansão binária do fluxo de interligação: $z_"x,s" = Delta sum_j u_(j,y,s)^+ 2^j - Delta sum_j u_(j,y,s)^- 2^j$.], [Não implementado (`INT-STRETCH`)],
  [(8f)–(8g)], [Restrições de cópia $ (1/S) u_(j,y,s)^+ = (1/S) n_(j,y,s)^+ $ / $ (1/S) u_(j,y,s)^- = (1/S) n_(j,y,s)^- $, cujos duais $pi_(j,y,s)^+$/$pi_(j,y,s)^-$ formam os cortes Lagrangeanos.], [Não implementado (`INT-STRETCH`)],
  [(9a)–(9e)], [O Lagrangeano relaxado do problema (8) e a maximização de seus multiplicadores ótimos.], [Não implementado (`INT-STRETCH`)],
)

Nenhuma variável binária/inteira existe em lugar algum de `src/planning/` hoje — nem em `master.jl`, nem em `follower.jl`, nem em `coupling.jl` (PVAL-04, regressão-testado diretamente). Este é o item `INT-STRETCH` do quadro de itens adiados de `STATE.md`, deferido explicitamente para a Fase 24 (v3.0) — um gap rastreado, não esquecido.

= Cortes de Benders — derivação <sec-cortes>

A nota PSR usa um ÚNICO epígrafe $alpha$ (4f) porque o custo de operação de N2, $y_"op,s"$, é *linear* e entra diretamente no objetivo do líder (eq. 4) — não precisa de sua própria função de valor convexa/epígrafe, apenas o custo de reforço de N1 (função de $z$ via o problema 2) precisa.

O repositório precisa de DOIS epígrafes (`master.jl`'s `α_op`, `α_x`) porque sua operação de N2 (`subproblem.jl`'s `PlanningOracle`) É um SOCP de bem-estar genuíno — não uma expressão linear substituível diretamente no objetivo do líder. `benders.jl`'s `add_optimality_cut!(master, :op, -oracle_res.cost, oracle_res.π, lb_res.z)` e `add_optimality_cut!(master, :x, follower_res.cost, follower_res.π_s, lb_res.z)` geram, a cada iteração factível, um corte por subproblema — Benders *multi-corte* — na MESMA forma matemática de (4f):

$ alpha >= "cost"_k + sum_t "grad"_k [t] dot.c (z[t] - z_k [t]) $

Além disso, o repositório tem um ramo que a nota PSR não especifica explicitamente: cortes de FACTIBILIDADE, quando o seguidor (`follower.jl`) é infactível no trial $z_k$ — um certificado de Farkas genuíno do HiGHS (`dual_status(model) == MOI.INFEASIBILITY_CERTIFICATE`), nunca uma heurística de "sempre factível":

$ v_k + sum_t u_k [t] dot.c (z[t] - z_k [t]) <= 0 $

Isso é um *acréscimo deliberado* de robustez sobre a nota PSR (que assume implicitamente a factibilidade do problema 2 em todo o texto) — não uma correspondência com nenhuma equação numerada da nota, mas uma extensão consistente com sua própria intenção de decomposição de Benders.

= Equilíbrio de Nash multi-distribuidor <sec-nash>

Problema (7) da nota PSR: para $I$ distribuidoras, cada uma resolve seu próprio problema (6) (a distribuidora $i$ como função das injeções fixas das outras, ${z_(j,y,s), j != i}$), e o equilíbrio de Nash é o conjunto de decisões em que nenhuma distribuidora pode melhorar sua função de custo dado o que as outras fazem — "calculado através de um processo de diagonalização em que cada distribuidora é otimizada fixando os fluxos das outras distribuidoras calculadas na última vez que foram otimizadas" (nota PSR, p. 8).

#table(
  columns: (auto, 1.2fr, 1.4fr, 0.8fr),
  align: (center, left, left, left),
  stroke: 0.4pt + gray,
  [*Eq.*], [*Significado (PSR)*], [*Construtor Julia*], [*Etiqueta*],
  [(7a)–(7e)], [Restrições de investimento/operação/acoplamento/flexibilidade da distribuidora $i$ (mesma forma de (6a)–(6e), herdadas de (1d)–(1i)).], [`coupling.jl`: `SharedTransmission` — `x_inv[i]`, `x_op[i,t]`, `coupling[i,t]: x_op[i,t] == z[i,t]` (uma linha independentemente dualizável por distribuidor por hora).], [Equivalente],
  [(7f)], [$alpha_i >= w_i^k ({z_(j,y,s), j != i}) + 1/S sum_s pi_(i,s)^k ({z_(j,y,s), j != i})(z_(i,y,s) - z_(i,y,s)^k)$ — os cortes de Benders da distribuidora $i$, dependentes dos fluxos das outras.], [`nash.jl`: `run_nash!` chama `solve_stackelberg!` (uma resolução COMPLETA do Benders de (4f), fresca a cada resposta ótima) com um `DistributorView(shared, i)` — o mestre de cada distribuidor $i$ acumula seus PRÓPRIOS cortes, começando vazio a cada resposta ótima (decisão travada de correção, `coupling.jl`).], [Equivalente],
  [(7) — o equilíbrio], [$ { (y_(i,"inv")^e, y_(i,"op,s")^e, z_(i,y,s)^e, alpha_(i,s)^e), i=1,...,I } $ tal que cada $i$ resolve seu próprio problema ótimo dado ${z_(j,y,s)^e, j != i}$.], [`nash.jl`: `run_nash!` — laço externo de Gauss-Seidel: para cada distribuidor $i$ em ordem, `activate_distributor!` → `solve_stackelberg!` → `write_back!` IMEDIATAMENTE (nunca Jacobi) → repete até `is_converged(trace, tol_outer, N)`.], [Equivalente (estrutura de Gauss-Seidel idêntica)],
)

*Desvio deliberado (alocação de custo de investimento compartilhado):* a nota PSR não especifica como o custo de um reforço de transmissão COMPARTILHADO por múltiplas distribuidoras deveria ser dividido entre elas — o problema (6)/(7) trata cada $y_i$/$x$ com uma notação que sugere um $x$ potencialmente único por par de distribuidoras, sem resolver a questão de alocação de custo explicitamente. `coupling.jl` resolve essa ambiguidade adotando *propriedade de investimento por distribuidor*: cada distribuidor $i$ possui seu próprio $x_"inv"[i]$ e paga seu próprio $c_"inv"[i] dot.c x_"inv"[i]$; o objeto genuinamente COMPARTILHADO é apenas a capacidade agregada do corredor (`capacity[t]: Σᵢ x_op[i,t] <= corridor_cap * Σᵢ x_inv[i]`) — uma decisão de modelagem documentada explicitamente no cabeçalho de `coupling.jl` como um afastamento deliberado do esboço tentativo de custo-igualmente-dividido de `13-RESEARCH.md`, em favor do modelo teoricamente-mais-limpo em que a melhor resposta de cada distribuidor precifica apenas seu próprio investimento.

O `run_nash_probe` (`nash.jl`) instrumenta uma prática de robustez além do que a nota PSR especifica: como a diagonalização de Gauss-Seidel não tem garantia geral de unicidade/convergência (concern carregado de `STATE.md`), toda execução relatada é sondada através de múltiplas sementes (`≥3`) e ordens de varredura (`≥2`), reportando o *spread* observado entre execuções — nunca apresentando uma única execução como "o" equilíbrio.

= Resumo de equivalências

- A estrutura Stackelberg-via-Benders de uma distribuidora — mestre/líder (problema 4 ↔ `master.jl`) e seguidor (problema 2 ↔ `follower.jl`) — é *matematicamente idêntica*, com o mesmo tipo de corte de otimalidade (4f).
- O dual do acoplamento como custo marginal de reforço, $pi_s$ (2e) ↔ `follower.jl`'s `π_s = dual.(f.coupling)`, é *o mesmo objeto matemático*.
- A diagonalização de Gauss-Seidel para o equilíbrio de Nash (problema 7) ↔ `nash.jl`'s `run_nash!` é *a mesma estrutura algorítmica*, com o mesmo timing (write-back imediato, nunca Jacobi).
- O acoplamento N1↔N2 (1j)/(2d)/(2e)/(1g) ↔ as restrições nomeadas `coupling[t]`/`pin[t]` do repositório são *a mesma relação física de acoplamento de fronteira*, apenas implementadas com uma variável compartilhada em vez de uma igualdade entre duas variáveis.

= Resumo de desvios deliberados

- *Sem índice de cenário:* o repositório não tem $s in S$ nem a média $(1/S) sum_s$ — cada iteração de Benders é um trial determinístico único, não uma expectativa estocástica.
- *Riqueza do oráculo além de $y_"op,s"$ abstrato:* `subproblem.jl` reutiliza o SOCP de bem-estar COMPLETO da tese (dispositivos dos agregadores, rede branch-flow, eq. 3.31–3.45) como a "operação de N2", em vez do balanço linear abstrato $F_y y_"op,s" = d_"y,s"$ da nota — um *reforço*, não uma equivalência simples, e por isso o repositório precisa de um segundo epígrafe de Benders ($alpha_"op"$) que a nota PSR não precisa.
- *Minimalismo do seguidor:* `follower.jl` é uma LP deliberadamente minimalista de UM ÚNICO corredor escalar, sem a rede interna de N1 (balanço de demanda (1c)/(2c)) que a nota PSR postula genericamente.
- *Convenção de sinal de $z$:* `master.jl`'s `z[t]` é limitado em $[0, y_"inv"]$ — um fluxo de importação fisicamente não negativo — em vez de um fluxo com sinal livre.
- *Alocação de custo de investimento compartilhado (Nash):* `coupling.jl` resolve a ambiguidade de alocação de custo do problema (6)/(7) da nota com propriedade de investimento POR distribuidor, uma decisão documentada explicitamente (ver @sec-nash).
- *Extensão inteira (problemas 8-9) genuinamente não implementada* — rastreada como `INT-STRETCH` em `STATE.md`, deferida para a Fase 24 (v3.0). Nenhuma variável binária/inteira existe em `src/planning/` hoje.

= Referências

#v(1em)
#line(length: 100%, stroke: 0.4pt + gray)
#v(0.3em)
#text(size: 8.5pt, fill: gray)[
  *Referências:* \
  Palacios, J. P. _Tese de Doutorado_, UNSJ/CONICET, 2022, Capítulo 4 (camada de planejamento). \
  Nota PSR: "Reforços interconexões N1-N2 através de equilíbrios de Stackelberg e Nash", documento interno, Junho 2026 (`docs/references/Expansão-N1-N2-EquilibriosStackelberg-Nash-v2 (1).pdf`, 9 pp.) — lida diretamente para este documento. \
  `.planning/research/THEORY-papers.md` — dígest cruzado das duas fontes (Paper 1 IET-2019 + nota PSR); ver @sec-estrutura para uma correção pontual encontrada nesse dígest. \
  Zou, J., Ahmed, S., Sun, X.A. (2019). "Stochastic dual dynamic integer programming." _Mathematical Programming_ 175, 461–502. \
  Bansal, A., Küçükyavuz, S. (2025). "Integer L-shaped and Lagrangian cuts revisited: a unified perspective." _Operations Research Letters_. \
  Implementação: `src/planning/master.jl`, `src/planning/follower.jl`, `src/planning/subproblem.jl`, `src/planning/benders.jl`, `src/planning/coupling.jl`, `src/planning/nash.jl` no projeto TSO-DSO. \
  Documento irmão (narrativa da implementação): `modelo_stackelberg_dso_unico.typ` — este documento complementa-o com o mapeamento termo-a-termo contra a fonte PSR; consulte-o para a narrativa livre do laço de Benders e do resultado.
]

#set page(
  paper: "a4",
  margin: (x: 2.2cm, y: 2.4cm),
  header: context {
    if counter(page).get().first() > 1 [
      #set text(size: 8pt, fill: gray)
      _Determinístico vs Estocástico — Comparação Lado a Lado_
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

// Tabelas: nunca usar `auto` em colunas de texto longo (ver ieee8500_exatidao_socp.typ).
#show table: set text(size: 9pt)
#set table(inset: 5pt)

#align(center)[
  #text(size: 20pt, weight: "bold")[Determinístico vs Estocástico — Comparação Lado a Lado]
  #v(0.3em)
  #text(size: 12pt, fill: gray)[Um forecast, um preço — ou cinco futuros, um cronograma protegido e cinco preços (IEEE-13, $T = 9$)]
  #v(0.8em)
  #line(length: 60%, stroke: 0.5pt + gray)
  #v(0.8em)
]

_Trabalho derivado do script `scripts/compare_default_stochastic.jl`, que exercita dois pontos de entrada independentes da camada operacional: `run_scenario` (estratégia `:centralized`, Rung 1) e `run_stochastic` (forma extensiva de dois estágios + avaliação fora da amostra, Rung 9). Todas as figuras e tabelas deste documento são geradas automaticamente pelo script e residem em `results/compare_default_stochastic/` (figuras em PDF+PNG, mais os artefatos `summary.csv`, `dadp_tidy.csv` e `oos_draws.csv`). Números atualizados em outubro de 2026 pela reexecução do script com o código atual: as correções de modelagem posteriores à primeira versão deste documento moveram os bem-estares e os preços do vale fotovoltaico (horas 4–6); o gate de exatidão das re-resoluções held-out, introduzido na mesma atualização, não excluiu nenhum sorteio nesta corrida._

#v(0.3em)

= Resumo

Este documento compara, no MESMO alimentador (`:ieee13`), mesma semente-mestra (`seed = 42`), mesmo horizonte ($T = 9$, o piso da população `:default`) e mesma família de perfis exógenos, as duas respostas que o arcabouço dá à pergunta "qual preço dia-à-dia publicar?":

- *DEFAULT (determinístico)* — `run_scenario` com estratégia `:centralized`: UM sorteio de perfil entra, uma maximização de bem-estar social convexa (GLB-CVX, SOCP) é resolvida, UM cronograma de bateria e UM caminho de preço DADP saem. Bem-estar medido: $-538,8957$; certificado de exatidão SOCP $2,14 times 10^-8$.
- *STOCHASTIC (dois estágios)* — `run_stochastic`: $S = 5$ cenários in-sample com pesos não-uniformes $p = (0,05; 0,15; 0,30; 0,30; 0,20)$ entram numa única forma extensiva que amarra UM cronograma de primeira etapa (bateria) por antecipatividade e resolve as cinco cópias de rede de uma vez; saem CINCO DADPs (um por cenário — a saída primária) mais a expectativa ponderada $E["DADP"]$ (resumo derivado, não um preço com restrição associada). O cronograma comprometido é então re-pontuado contra $10$ sorteios held-out disjuntos: bem-estar realizado $-538,7869$, gap realizado$-$in-sample $-0,0324$, $0/10$ infactíveis, $0/10$ inexatos.

A mensagem central é sobre *forma*, não magnitude: o caminho de preço do default acompanha $E["DADP"]$ com desvio máximo $approx 0,03$ em valor absoluto (menos de 1% do preço local fora do vale fotovoltaico das horas 4–6, onde o próprio preço é quase nulo), enquanto a *distribuição* que a forma extensiva carrega — o leque min$-$máx dos cinco DADPs — atinge $0,127$ na hora 7 ($approx 2,7%$ do preço local), exatamente onde o despacho de bateria entre cenários diverge. Um price-maker que publica apenas o número determinístico descarta silenciosamente essa condição-cenário — o custo da informação que o resumo derivado $E["DADP"]$ não transporta.

= O que está — e o que NÃO está — sendo comparado

Antes de qualquer número, o aviso de comparabilidade que o próprio script imprime:

- *As famílias de sementes são DISJUNTAS por construção.* `run_scenario` materializa seu único sorteio de `sub_seed(seed, :profiles)`; `run_stochastic` materializa seus sorteios in-sample de `sub_seed(seed, :stoch_insample_profiles_k)` e os held-out de `sub_seed(seed, :stoch_oos_profiles_h)`. Nenhum sorteio estocástico replica o determinístico. Os números de bem-estar das duas corridas estão, portanto, sobre realizações exógenas diferentes — a diferença bruta $-538,8957$ vs $-538,7545$ NÃO é uma alegação de "o estocástico melhora o bem-estar em 0,14".
- *Os objetivos também diferem:* o número default é o bem-estar de UM sorteio; o in-sample estocástico é o bem-estar *esperado ponderado por probabilidades* sobre cinco sorteios. A comparação corretamente definida dentro do mundo estocástico é o gap fora-da-amostra: realizado $-$ in-sample $= -0,0324$.
- *O que é comparável de fato:* os *formatos* das saídas — um caminho de preço contra cinco caminhos + um cronograma compartilhado; a condicionalidade-cenário do preço por hora; a robustez do cronograma comprometido contra futuros não vistos.

= Os dois pipelines

== Default: `run_scenario` (`:centralized`)

Um único problema GLB-CVX (bem-estar social sobre a rede de fluxo-de-ramal convexa, relaxação SOCP com certificado de exatidão), resolvido monoliticamente por Clarabel. O DADP é o dual do balanço ativo nodal na barra de carga — uma DLMP. A formulação completa (eq. 3.2–3.45 da tese) está documentada no writeup irmão `thesis_caseA.typ`.

== Estocástico: `run_stochastic` (forma extensiva + held-out)

A forma extensiva de dois estágios resolve, num único `Model` compartilhado:

$ max sum_k p_k dot.c W_k (x, u_k) quad "sujeito a:" quad cases(
  "cópia de rede + dispositivos do cenário" k "para cada" k,
  x = x_k space forall k quad "(anti-anticipação: bateria compartilhada)",
) $

onde $x$ é o cronograma de bateria de primeira etapa (amarrado entre cenários por igualdades de não-anticipação explícitas) e $u_k$ são as decisões de segunda etapa do cenário $k$. Cada cópia de rede tem seu próprio gate de exatidão SOCP, avaliado INDEPENDENTEMENTE — nunca agregado. A avaliação fora-da-amostra fixa o $x$ resolvido uma única vez (contrato build-once) e re-resolve $10$ cenários held-out contra ele; um sorteio genuinamente infactível contra o cronograma comprometido seria mascarado e reportado, nunca absorvido — nesta corrida, $0/10$ infactíveis. Cada re-resolução held-out passa ainda pelo MESMO gate de exatidão SOCP da resolução in-sample: um sorteio recusado (resíduo de cone acima do piso de precisão do solver) é excluído do bem-estar realizado e do gap e reportado, nunca entra na média — nesta corrida, $0/10$ inexatos (o mesmo resultado em Julia 1.12.5 e 1.12.7). As re-resoluções held-out usam a tolerância padrão do Clarabel ($"tol_gap" = 10^(-8)$), mais frouxa que a da forma extensiva in-sample ($5 times 10^(-10)$); por isso o número de sorteios excluídos depende da versão do solver/Julia, e o status da corrida é `:solved` (seria `:oos_inexact_skipped` se algum sorteio fosse excluído).

O vetor de probabilidades em sino $(0,05; 0,15; 0,30; 0,30; 0,20)$ — cenários centrais mais prováveis que os extremos — não é estética: um vetor uniforme espaçado $(0,10; 0,15; 0,20; 0,25; 0,30)$ derruba o gate de convergência do Clarabel (`ALMOST_OPTIMAL`/`NEARLY_FEASIBLE_POINT`) exatamente neste fixture $T = 9$, um knife-edge documentado na página `docs/literate/stochastic_pv_demand.jl` no espírito "reportar, não afinar" do projeto.

= Como executar

```bash
julia --project=. scripts/compare_default_stochastic.jl
```

O script imprime o relatório completo no console e grava em `results/compare_default_stochastic/`:

#table(
  columns: (1fr, 1fr),
  align: (left, left),
  [*Artefato*], [*Conteúdo*],
  [`dadp_comparison.{pdf,png}`], [default vs os 5 DADPs por cenário + $E["DADP"]$; painel direito: desvios de $E["DADP"]$],
  [`scenario_fan.{pdf,png}`], [os 5 sorteios in-sample de PV/demanda (replay bit-idêntico via `sub_seed`)],
  [`welfare_robustness.{pdf,png}`], [cronograma comprometido re-pontuado nos 10 held-out; dispersão de preço por hora],
  [`price_envelope.{pdf,png}`], [banda min$-$máx dos DADPs com os dois caminhos-resumo; barras default $- E["DADP"]$],
  [`summary.csv`], [tabela chave/valor: bem-estares, gaps, certificados, tempos],
  [`dadp_tidy.csv`], [DADP em formato longo (fonte $times$ hora), pronto para análise],
  [`oos_draws.csv`], [bem-estar realizado por sorteio held-out + máscaras de infactibilidade e de inexatidão],
)

Reprodutibilidade: duas execuções completas do script (processos separados) produziram números idênticos — verificado na versão anterior; a reexecução de outubro foi única. É a garantia de reprodutibilidade de mesma semente, pois todo sorteio flui por sub-fluxos `sub_seed`, nunca pelo RNG global.

= Resultados numéricos

== Escalares

#table(
  columns: (1.1fr, 1fr, 1.6fr),
  align: (left, right, left),
  [*Grandeza*], [*Valor*], [*Nota*],
  [bem-estar default], [$-538,8957$], [sorteio único próprio, objetivo de UM cenário],
  [exatidão SOCP default], [$2,14 times 10^-8$], [certificado de exatidão, muito abaixo de $10^-3$],
  [bem-estar in-sample estocástico], [$-538,7545$], [esperado ponderado por $p_k$ sobre 5 cenários],
  [exatidão SOCP estocástico (máx)], [$1,9 times 10^-9$], [máx sobre gates POR cenário],
  [bem-estar realizado (held-out)], [$-538,7869$], [média uniforme sobre os 10 sorteios utilizáveis (factíveis e certificados exatos)],
  [gap fora-da-amostra], [$-0,0324$], [realizado $-$ in-sample; $approx 0,006%$ da escala],
  [sorteios infactíveis], [$0 / 10$], [máscara de infactibilidade vazia nesta corrida],
  [sorteios inexatos (excluídos)], [$0 / 10$], [gate de exatidão nas re-resoluções held-out; nenhum recusado],
  [dispersão máx. de DADP], [$0,1274$ (hora 7)], [máx sobre horas de (máx$-$mín entre cenários)],
)

== DADPs por cenário na barra de preços

#table(
  columns: (auto, auto, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr, 1fr),
  align: (left, right, right),
  [*fonte*], [$p_k$], [t=1], [t=2], [t=3], [t=4], [t=5], [t=6], [t=7], [t=8], [t=9],
  [cenário 1], [0,05], [3,817], [3,733], [3,582], [0,010], [0,004], [0,006], [4,843], [5,907], [6,614],
  [cenário 2], [0,15], [3,817], [3,740], [3,564], [0,010], [0,016], [0,016], [4,855], [5,907], [6,582],
  [cenário 3], [0,30], [3,817], [3,733], [3,571], [0,008], [0,011], [0,020], [4,774], [5,944], [6,615],
  [cenário 4], [0,30], [3,817], [3,740], [3,576], [0,015], [0,003], [0,003], [4,728], [5,913], [6,614],
  [cenário 5], [0,20], [3,817], [3,740], [3,575], [0,009], [0,006], [0,016], [4,851], [5,913], [6,615],
  [$E["DADP"]$ (derivado)], [—], [3,817], [3,737], [3,573], [0,011], [0,008], [0,013], [4,791], [5,921], [6,610],
  [*default*], [—], [3,818], [3,737], [3,602], [0,008], [0,005], [0,025], [4,819], [5,925], [6,633],
)

Estrutura do dia de preço: patamares de $approx 3,6$–$3,8$ nas horas 1–3 (tarde/noite sem PV), colapso para $approx 0,003$–$0,025$ nas horas 4–6 (meio-dia fotovoltaico — o preço cai abaixo de $lambda_0$ para absorver PV) e rampa noturna $4,8 -> 6,6$ nas horas 7–9.

= Figuras e interpretação

== Figura 1 — DADP default vs os cinco DADPs por cenário

#image("../../results/compare_default_stochastic/dadp_comparison.png", width: 100%)

*Interpretação:* à escala completa do preço (esquerda), os cinco caminhos por cenário quase coincidem e o default (preto sólido) acompanha o feixe, ficando ligeiramente acima dele nas horas 3, 6 e 9 — variação condicional-cenário *real mas modesta* neste fixture. O painel direito mostra o que a escala esconde: desvio nulo até a precisão do solver ($approx 10^(-8)$) na hora 1 (fora do pico, o piso de preço de todo cenário vincula da mesma forma) e dispersão genuinamente condicional ao cenário nas horas do meio do horizonte, culminando em $plus.minus 0,06$ na hora 7.

== Figura 2 — o leque de cenários in-sample

#image("../../results/compare_default_stochastic/scenario_fan.png", width: 100%)

*Interpretação:* os cinco sorteios exógenos (PV à esquerda, demanda à direita) sobre os quais a forma extensiva protege — regenerados AQUI pelas mesmas costuras de semente que `run_stochastic` usa (`sub_seed(seed, :stoch_insample_profiles_k)`), então cada curva é bit-idêntica ao que o cenário $k$ viu dentro da resolução. A identidade de cor segue a entidade: o cenário 4 (laranja, $p = 0,30$) mantém PV residual na hora 7 ($approx 0,17$, o maior valor nessa hora) com demanda baixa ($0,6$) e é exatamente quem tem o DADP mínimo nessa hora (4,728) — rastreável entre figuras. O cenário 1 (azul) coincide com o 4 em PV da hora 5 em diante e tem a mesma demanda na hora 7 (seu traço fica sob o laranja), mas paga 4,843: a hora 7 isolada não explica todo o preço, e as horas anteriores também contam.

== Figura 3 — robustez fora-da-amostra do cronograma comprometido

#image("../../results/compare_default_stochastic/welfare_robustness.png", width: 100%)

*Interpretação:* (esquerda) os 10 pontos são os bem-estares realizados do MESMO cronograma de primeira etapa contra sorteios que ele nunca viu; todos factíveis (nenhum vermelho) e certificados exatos (nenhum marcador vazado de sorteio excluído), a linha preta (média realizada) fica logo abaixo da linha tracejada (expectativa in-sample) — a distância visível É o gap $-0,032$. (direita) a dispersão de preço por hora: nula na hora 1 (até a precisão do solver, $approx 10^(-8)$), pico 0,127 na hora 7 — o mapa de "onde o preço é condicional ao cenário".

== Figura 4 — envelope de preço: o número único vs a distribuição

#image("../../results/compare_default_stochastic/price_envelope.png", width: 100%)

*Interpretação:* a banda min$-$máx dos cinco DADPs é o *risco de preço* que a forma extensiva carrega e que o default não vê. O default (vermelho) acompanha a banda de perto, mas sai dela por cima nas horas 3, 6 e 9 (até $approx 0,02$ acima do máximo dos cenários; marginalmente também na hora 1), com desvio máximo de $approx 0,03$ de $E["DADP"]$ (painel direito; positivo nas horas 1, 3 e 6–9, negativo nas 2, 4 e 5 — na hora 2 apenas $-0,0007$). Neste fixture a banda é estreita em valor absoluto ($<= 0,13$; $<= 2,7%$ do preço local fora do vale fotovoltaico — nas horas 4–6 o preço é quase nulo e a razão relativa perde sentido) — mas é *estruturalmente* o único lugar onde ela pode ser medida.

= Achados

+ *O default ≈ $E["DADP"]$, e isso é o esperado — mas não é o ponto.* O caminho determinístico acompanha a expectativa derivada com $|Delta lambda| <= 0,03$. A informação que o número único NÃO transporta é a banda: até $0,127$ na hora 7, concentrada exatamente nas horas onde o despacho de bateria entre cenários diverge (fim de PV + rampa noturna de demanda).

+ *Condicionamento-cenário tem estrutura horária identificável.* Hora 1: dispersão nula até a precisão do solver ($approx 10^(-8)$; piso de preço comum vincula fora do pico). Horas 4–6 (vale fotovoltaico): dispersão $0,007$–$0,017$ via disponibilidade de PV distinta. Hora 7: pico de dispersão $0,127$, com o cenário 4 — o de maior disponibilidade de PV restante e menor demanda na hora 7 — pagando o menor preço — o mecanismo DLMP respondendo ao cenário, não ruído.

+ *O gap fora-da-amostra é pequeno e NEGATIVO nesta corrida.* $-0,032$ ($approx 0,006%$ da escala de bem-estar): o cronograma comprometido realizou ligeiramente ABAIXO da expectativa in-sample sobre os 10 held-out, todos certificados exatos. O sinal é dependente do fixture — a página literata do Rung 9 reporta o próprio gap ao vivo (positivo na corrida medida), e lá o gate de exatidão exclui parte dos sorteios held-out, num número que depende do build do solver; ambos são reportados como medidos, sem alegação de generalização de sinal. O que a corrida confirma é a *magnitude*: held-out próximos em caráter dos in-sample $arrow$ cronograma fixo generaliza bem ($0/10$ infactíveis, $0/10$ inexatos).

+ *Cada cópia de rede estocástica é certificada independente e exata.* Gap máximo por cenário $1,9 times 10^-9$ — a forma extensiva NÃO degradou a exatidão da relaxação (nunca agregar certificados). Preços, sendo duais, saem de redes certificadas.

+ *Determinismo verificado end-to-end.* Duas execuções completas em processos separados imprimiram valores idênticos até o último dígito impresso — verificado na versão anterior; a reexecução de outubro foi única. É a garantia de reprodutibilidade de mesma semente no plano horizontal: sementes-mestra idênticas produzem experimentos idênticos.

= Limitações honestas

- *Bem-estares default vs estocástico não são diretamente comparáveis* (sorteios disjuntos, objetivos distintos — Seção 2). Este documento deliberadamente NÃO converte a diferença bruta 0,14 numa alegação de superioridade.
- *Tempos de resolução não são benchmark de solver.* O default rodou primeiro no processo e pagou a compilação first-call do caminho `:centralized` ($48$ s); o estocástico ($9,4$ s) herda código já aquecido. Ambos são limites superiores de wall-time, não medidas de solver.
- *Fixture pequeno, dispersão modesta.* $S = 5$ cenários num IEEE-13 redimensionado com variabilidade de PV/demanda moderada produz uma banda de preço estreita. A banda larga (e o valor de hedging) exige cenários extremos ou população calibrada — a costura para isso já existe (`flexibility_population`, `stoch_probabilities` livres), só não é exercitada aqui.

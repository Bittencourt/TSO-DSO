#set page(
  paper: "a4",
  margin: (x: 2.2cm, y: 2.4cm),
  header: context {
    if counter(page).get().first() > 1 [
      #set text(size: 8pt, fill: gray)
      _Exatidão SOCP no IEEE-8500_
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
  #text(size: 20pt, weight: "bold")[Exatidão SOCP no IEEE-8500]
  #v(0.3em)
  #text(size: 12pt, fill: gray)[Investigação da inexatidão estrutural: oito estágios, três voltas erradas, e a resolução por merge topológico]
  #v(0.8em)
  #line(length: 60%, stroke: 0.5pt + gray)
  #v(0.8em)
]

_Trabalho derivado da investigação registrada em `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` e `25-DATA-PROVENANCE.md`, das tarefas rápidas `260822-oi7` (diagnóstico por trecho e veredito de mecanismo), `260822-pxb` (primeira passada de merge de barras) e `260822-rle` (segunda passada, resolução), e dos artefatos committados `results/ieee8500_benchmark/socp_gap_report.csv` e `noise_floor_calibration.csv`. O gate de certificação em si — `assert_socp_exact!` — está em `src/models/exactness.jl`._

#v(0.3em)

= Resumo

Este documento registra, em sequência auditável — incluindo os raciocínios que se mostraram ERRADOS — a investigação que resolveu a inexatidão estrutural da relaxação SOCP no fixture IEEE-8500 (malha completa MT+BT reduzida a sequência positiva balanceada). A inexatidão não é um detalhe cosmético: neste projeto os preços transativos (DADP) SÃO os duais da restrição de balanço nodal, então uma relaxação frouxa produz duais de uma rede que não existe. O documento cobre por que `assert_socp_exact!` lança exceção em vez de retornar um valor; os oito estágios da investigação, incluindo três voltas erradas explicitamente rotuladas; a tabela de resultado em três passadas que reduziu o gap de exatidão do ponto-título em 18x; o estado final, independentemente verificado, do fixture reduzido; as costuras do banco de experimentação que já existiam e se pagaram; o que a investigação forçou o banco a crescer; achados colaterais; e uma lista honesta de itens ainda em aberto.

= Por que a exatidão é uma precondição, não uma métrica de qualidade

O modelo convexo substitui a igualdade de fluxo de potência não convexa pela desigualdade cônica

$ l dot.c v >= P^2 + Q^2 quad "(tese 3.39)" $

com a cópia de exatidão em 3.43–3.45. Preços neste arcabouço SÃO duais — a DADP é o dual do balanço ativo nodal — então um cone frouxo produz o dual de uma rede que não existe. `assert_socp_exact!` portanto LANÇA EXCEÇÃO em vez de retornar um valor, e está posicionado depois de `assert_solved!` e estritamente ANTES de qualquer leitura de `dual()`, de modo que um preço nunca pode ser extraído de uma resolução não certificada. Sua mensagem termina em `"prices REFUSED (thesis 3.43-3.45; PF-04)"`. O veredito usa um limite combinado: `gap <= atol + rtol · max(|lhs|, |rhs|)`.

= A investigação, em sequência

A investigação avançou em oito estágios, incluindo três voltas erradas — rotuladas explicitamente como tal, porque o valor deste registro para um apêndice de tese está exatamente em tornar o raciocínio auditável, inclusive o raciocínio que falhou.

== Estágio A — o piso que não encolhia

O IEEE-8500 OpenDSS vendorizado foi fixado no commit `3b208397160213cae4a9e2d0a7d1aa3528ce26e1` e reduzido a uma tabela Julia committada por um único script sem dependências externas. A calibração de piso de ruído retornou pisos de `0,1796` e `0,5653` — contra `2,6e-9` do IEEE-13 — e o resíduo NÃO encolhia à medida que a tolerância do solver era apertada: a assinatura de um gap ESTRUTURAL, não de ruído numérico do solver. Suspeito: o trecho `HVMV_Sub_48332 -> _HVMV_Sub_LSB`, a 1 μΩ.

== Estágio B — VOLTA ERRADA 1: a correção fabricou uma impedância

`HVMV_Sub_connector` é declarado na fonte como `length=0.001 units=km r1=0.001 x1=0.01`, ou seja, `1e-6 Ω`. A convenção D-13 de quase-idealidade elevou esse valor para `0,09330 Ω` — aproximadamente 93.000x. A correção foi verificada primeiro por experimento (piso `0,180 -> 0,00114`, uma melhoria de 157x, voltando a encolher com a tolerância) e colocada no script de redução com uma verificação assert-exatamente-1 — essa parte estava certa. Mas o valor foi INVENTADO em vez de remover um elemento não físico. Superada no Estágio H.

== Estágio C — VOLTA ERRADA 2: um limiar relatado como propriedade dos dados

Uma varredura por `r < 1e-5 Ω` encontrou exatamente uma correspondência e foi relatada como "exatamente 1 de 3.654 arestas é degenerada". O próximo ofensor ficava em `4,797e-5 Ω` — logo acima desse corte arbitrário.

== Estágio D — o muro de memória, e uma pista falsa

A varredura completa de densidades foi morta por OOM (`OOM-killer`) em todos os pontos-título, numa máquina compartilhada de 15 GiB; decisivamente, `ieee8500-mv @ 0.5` teve sucesso uma vez em 102 s e foi morto por OOM na re-execução — o muro era de contenção da máquina compartilhada, não um limite do modelo. `T = 24` precisou de mais de `9,75 GiB`; `T = 10` coube em `3,2 GB`. O resíduo parecia acompanhar o tamanho da rede, o que foi lido como evidência de condicionamento — uma pista falsa, já que fixtures maiores simplesmente carregam mais artefatos degenerados.

== Estágio E — VOLTA ERRADA 3: extrapolar um piso de tolerância entre pontos de operação

O ponto-título retornou `ALMOST_OPTIMAL` (recusado — duais quase-factíveis nunca devem ser publicados). Foi rastreado a uma varredura rodando Clarabel em `tol_gap = 1e-8`, um valor que a escada de calibração já havia medido como falho. Mas afrouxar para `1e-7` NÃO corrigiu o problema: a escada havia sido medida na densidade `0,05` / `T=24` e aplicada a um ponto de densidade `0,1` / `T=10` — pontos de operação diferentes. Falha produtiva: expôs que `run_admm_point` nunca passava a nova costura `atol_exact`, então o portão de consolidação final do ADMM permanecia fixo (*hardcoded*) em `1e-6` contra um piso medido três ordens de grandeza maior.

== Estágio F — o diagnóstico por trecho e o veredito de mecanismo

`socp_gap_report` (aditivo, sem lançar exceção) retorna os piores pares (trecho, passo de tempo), com `r_pu`, sinal de fluxo reverso, carregamento, e a mesma razão de limite combinado. A regra de decisão foi fixada ANTES de medir: ESTRUTURAL se os ofensores se concentrarem em segmentos de baixa resistência quase-ideais; FÍSICO se em trechos carregados com $P < 0$; NUMÉRICO se dispersos. Evidência, todos em `tol=1e-8` exceto o ponto-título em `tol=1e-6`:

#table(
  columns: (2fr, 0.9fr, 1fr, 0.9fr),
  align: (left, right, right, center),
  stroke: 0.4pt + gray,
  [*Ponto*], [*gap*], [*`r_pu` do ofensor*], [*Veredito*],
  [`ieee13` @ densidade 1.0 (controle, adoção MÁXIMA)], [1.93e-8], [0.15–0.30], [EXATO],
  [`ieee8500-mv` @ 0.1], [5.78e-4], [1.542e-7], [EXATO],
  [`ieee8500-mv` @ 0.25], [3.77e-3], [1.542e-7], [INEXATO],
  [`ieee8500` @ 0.1, `T=10`], [3.25e-2], [1.542e-7], [INEXATO],
)

O MESMO trecho liderou os três pontos do IEEE-8500. Fluxo reverso co-ocorre mas NÃO discrimina: 3 dos 5 principais ofensores do IEEE-13 também carregam $P<0$ e são exatos. O aumento de densidade de 0,1 para 0,25 piorou o MESMO trecho em vez de produzir um novo conjunto disperso, excluindo NUMÉRICO. *VEREDITO: ESTRUTURAL.*

== Estágio G — verificação na fonte: a redução estava CORRETA

Linha-fonte: `New Line.LN5473436-1 bus1=M1142828 bus2=L2674047 length=0.0003048 units=km Linecode=3PH_H-397_ACSR...`. A resistência de sequência positiva $r_1 = 0,157372$ Ω/km (normal para um condutor 397 ACSR); comprimento `0,0003048 km` = EXATAMENTE 1,000 pé; $r_1 dot.c L = 4,7967 times 10^(-5)$ Ω contra o valor committado `4,797e-5`; `r_pu = 1,5423e-7` contra o valor committado `1,542e-7` — quatro algarismos significativos. NÃO é um bug de *parsing*. `LN5473436-1` e `LN5473436-2` são uma DIVISÃO de uma linha original única, inserindo a barra onde o transformador de serviço `T5260514C` se conecta. O REENQUADRAMENTO: duas barras a um pé de distância SÃO o mesmo nó, então a redução correta é MESCLAR (*merge*) as duas. Aplicar o `r_pu = 3e-4` de D-13 a um condutor real inventaria \~2.000x sua resistência física real só para passar em um portão — corrupção de modelo, não uma correção.

== Estágio H — redução topológica, em duas passadas

Maquinaria genérica de *merge* de barras no script de redução: sobrevivente por grau, desempate lexicográfico, redirecionamento de arestas, reanexação de transformadores, e tratamento explícito de auto-laços (par adjacente) e arestas paralelas (vizinho compartilhado). A Passada 1 mesclou 3 pares — as duas divisões de 1 pé mais o conector, cuja substituição do Estágio B foi REVERTIDA. A dominância então transferiu-se para `LN5486729-1`, a 0,561 m, com o mesmo sufixo de divisão `-N`, então o limiar havia sido mais estreito que o fenômeno. A Passada 2 o ampliou para sub-métrico.

A CLASSE COMPLETA — 8 segmentos, 7 de 8 carregando um sufixo de divisão `-N`, todos PAREADAMENTE DISJUNTOS:

#table(
  columns: (1.1fr, 1fr, 1.6fr, 0.9fr),
  align: (left, right, left, center),
  stroke: 0.4pt + gray,
  [*Linha-fonte*], [*Comprimento*], [*Barras (baixa <-> sobrevivente)*], [*Passada*],
  [`LN5837496-1`], [0,260 m (0,852 pé)], [`P829798` <-> `M1108489`], [2],
  [`LN5473436-1`], [0,305 m (1,000 pé)], [`M1142828` <-> `L2674047`], [1],
  [`LN6259981-1`], [0,305 m (1,000 pé)], [`M1009834` <-> `L3178969`], [1],
  [`LN6268990-2`], [0,384 m (1,260 pé)], [`M1047613` <-> `M1047612`], [2],
  [`LN5486729-1`], [0,561 m (1,839 pé)], [`M1069311` <-> `M1069310`], [2],
  [`LN5927299-1`], [0,659 m (2,161 pé)], [`M1125974` <-> `L3104796`], [2],
  [`LN5472394-1`], [0,732 m (2,401 pé)], [`M1026708` <-> `M1026709`], [2],
  [`LN5865233-1`], [0,842 m (2,763 pé)], [`M1047744` <-> `L3178971`], [2],
)

EXCLUSÃO DELIBERADA: 53 outros registros na fonte têm EXATAMENTE `length = 0.001` km — 43 amarrações de chave (*switch ties*) e 9 tocos de conexão de capacitor (`CAP_*`) com impedância inline fabricada em `r_pu ~ 3,2e-6`, isto é, MAIS resistivos que o ofensor, e uma classe diferente. O limiar é estritamente sub-métrico, seguro contra ponto flutuante, mais uma asserção de prefixo `CAP_`.

= O resultado — tabela de três passadas

Os `atol` permaneceram INALTERADOS durante toda a investigação — nenhum limiar foi ajustado para produzir este resultado.

#table(
  columns: (1.7fr, 0.8fr, 0.8fr, 0.8fr, 1.5fr, 1fr),
  align: (left, right, right, right, center, center),
  stroke: 0.4pt + gray,
  [*Ponto*], [*Pré-merge*], [*Passada 1*], [*Passada 2*], [*Razão vs. próprio `atol`*], [*Veredito*],
  [`ieee8500-mv` @ 0.1], [5,781e-4], [3,853e-4], [2,056e-4], [0,50 → 0,34 → 0,179x], [exato],
  [`ieee8500-mv` @ 0.25], [3,773e-3], [8,137e-4], [5,239e-4], [3,29 → 0,71 → 0,457x], [inexato → *EXATO*],
  [`ieee8500` @ 0.1, `T=10`], [3,250e-2], [6,130e-3], [1,822e-3], [6,54 → 1,23 → 0,367x], [*EXATO*],
)

`atol`: `ieee8500-mv` = 1,1460e-3, `ieee8500` = 4,9691e-3 — ambos calibrados ANTES do início deste trabalho. Ponto-título: redução de 18x no total, de 6,54x acima de seu piso para 0,367x dele, removendo 9 artefatos (a conexão de barramento do Estágio B + os 8 segmentos sub-métricos do Estágio H).

NOVO OFENSOR DOMINANTE: `L2916620 <-> N1136366` = `LN5472390-3`, comprimento 4,745 m, `r_pu = 2,401e-6` — um condutor real genuinamente mais longo, fora da classe sub-métrica, então a classe de artefatos está ESGOTADA, não apenas o limiar sendo perseguido.

= Estado final da malha (verificado independentemente)

- Ponto-título: 4.866 barras / 4.865 trechos; apenas-MT: 2.512 / 2.511; 9 *merges* no total; radial em ambos; ZERO auto-laços; ZERO arestas paralelas.
- Trecho de cabeça D-08 intacto em `smax = 55,0`, com todos os demais em `SMAX_NO_LIMIT`.
- Barras de carga: 1.177 / 1.138; carga total 10.773,17 kW conservada.

= Como o banco foi usado — costuras que já existiam e valeram a pena

- O portão PF-04 antes de qualquer leitura de `dual()`: o arcabouço recusou-se a publicar preços para 4.866 barras em vez de retornar números plausíveis. O defeito surgiu como uma recusa, não como DLMPs errados.
- Construção do `Feeder` como invariante (`assert_radial` + `assert_magnitudes` no construtor): a primeira construção do fixture pegou que 5 registros `switch=y` marcados `enabled=False` deixavam a topologia com 5 ciclos.
- `to_pu_impedance` convertido UMA VEZ na ingestão — por isso a aritmética fonte-vs-committado reconciliou a quatro algarismos significativos na primeira tentativa.
- A fábrica `select_optimizer`: trocar tolerâncias e adicionar SCS nunca tocou um modelo.
- Artefatos CSV committados: a única razão pela qual uma comparação antes/depois em três passadas é reconstruível.

= O que o experimento forçou o banco a crescer

Tudo aditivo; `assert_socp_exact!` permanece byte-idêntico durante toda a investigação: `socp_relaxation_gap`, `--calibrate-noise-floor`, `socp_gap_report` / `--gap-report`, `--clarabel-tol` com padrões cientes do *fixture*, `--t-horizon`, `--calibration-density` com colunas de proveniência de densidade e horizonte na escada CSV, a costura `atol_exact`/`rtol_exact`, `time_limit_s` (saída honesta `:budget_exceeded`), a maquinaria de *merge* de barras, `FixedCapacitor`.

= Achados colaterais

- Nenhum cruzamento Clarabel-SCS no intervalo medido; Clarabel domina. Mais útil: SCS atingiu `OPTIMAL` no IEEE-13 mas produziu desvios de DADP de 2,33 e 4,82, contra 0,0022–0,0050 no IEEE-123 — suporte empírico para a regra de pilha tecnológica vigente de que SCS não deve certificar preços.
- O muro de memória é dirigido pelo horizonte, não pela escala (`T=24` > 9,75 GiB; `T=10` cabe em 3,2 GB).
- Defeito do *harness*: a varredura escreve todas as linhas em UM único *upsert* ao final do laço de densidade, então um único OOM descartou três sucessos já computados.

= Itens em aberto

- Os resultados da varredura committados na Fase 25 estão DESATUALIZADOS: esta foi uma mudança de identidade do *fixture*, então `density_sweep_full.csv` e a escada original descrevem o *fixture* pré-*merge* de 4.875 barras e não são comparáveis a nada atual.
- O verdadeiro ponto-título de \~40x em `T = 24` nunca foi medido; sua real necessidade de memória está apenas limitada inferiormente.
- As medições de SCS dependem de uma instalação Julia GLOBAL em vez de um ambiente fixado no repositório — um gap de reprodutibilidade contra a própria regra de manifesto committado do projeto (INFRA-01).
- Os 53 tocos artificiais de exatamente 1 m permanecem intocados, registrados como o próximo nível.
- Higiene de certificado precisa de uma regra escrita: `--calibration-density` torna fácil calibrar um piso exatamente no ponto sendo certificado, o que produz uma razão tautológica de 1,000 — o gap e o piso saíram bit-idênticos quando isso foi tentado.

#v(1em)
#line(length: 100%, stroke: 0.4pt + gray)
#v(0.3em)
#text(size: 8.5pt, fill: gray)[
  *Referências:* \
  Palacios, J. P. _Tese de Doutorado_, UNSJ/CONICET, 2022, Capítulo 3 (formulação, eq. 3.31–3.45). \
  `.planning/phases/25-ieee-8500-scalability-benchmark/deferred-items.md` — registro primário dos Itens 1, 2 (aberto), 3, 4, 5. \
  `.planning/phases/25-ieee-8500-scalability-benchmark/25-DATA-PROVENANCE.md` — proveniência dos dados-fonte e das seções de desvio da transcrição literal. \
  Tarefas rápidas: `260822-oi7-SUMMARY.md` (diagnóstico e veredito de mecanismo), `260822-pxb-SUMMARY.md` (passada 1 de *merge*), `260822-rle-SUMMARY.md` (passada 2, resolução). \
  Implementação: `src/models/exactness.jl` (`assert_socp_exact!`, `socp_relaxation_gap`, `socp_gap_report`); `scripts/reduce_ieee8500_impedances.jl`; `scripts/benchmark_ieee8500.jl`. \
  Evidência: `results/ieee8500_benchmark/socp_gap_report.csv`, `noise_floor_calibration.csv`. \
  Dados-fonte: `dss-extensions/electricdss-tst`, `Version8/Distrib/IEEETestCases/8500-Node/`, commit fixado `3b208397160213cae4a9e2d0a7d1aa3528ce26e1`.
]

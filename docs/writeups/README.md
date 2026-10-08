# Writeups

Authored prose documents for the TSO-DSO project — model formulations and results reproductions,
mostly written in [Typst](https://typst.app/), plus one standalone HTML framework guide.

- **Tracked:** the `.typ` sources (the source of truth) and `FRAMEWORK_GUIDE.html`, a
  hand-maintained, self-contained HTML file tracked as-is (not generated; it has no `.typ`
  source).
- **Not tracked:** the compiled `.pdf` (gitignored — regenerate with `typst compile <file>.typ`).

This is deliberately separate from `docs/references/` (gitignored), which holds **third-party
copyrighted** material (the thesis, papers, PSR note) kept local and not redistributed.

| Writeup | Companion script | Figures |
|---------|------------------|---------|
| `FRAMEWORK_GUIDE.html` — framework guide (architecture, models, decomposition, experiments): a standalone, self-contained HTML file with embedded figures; hand-maintained and tracked as-is (not generated, no `.typ` source) | — | embedded in the HTML |
| `thesis_caseA.typ` — Camada Operacional da Tese, Caso A (IEEE-13 modificado) | `scripts/thesis_caseA.jl` | `results/thesis_caseA/` |
| `modelo_stackelberg_dso_unico.typ` — single-DSO Stackelberg model (v2.0 planning layer) | — | — |
| `stackelberg_vs_psr_n1n2.typ` — term-by-term PSR N1-N2 note ↔ `src/planning/` mapping | — | — |
| `ieee8500_exatidao_socp.typ` — investigação da exatidão SOCP no IEEE-8500 (oito estágios, três voltas erradas, resolução por merge topológico) | — | — |
| `compare_default_stochastic.typ` — Determinístico vs Estocástico lado a lado (default single-forecast vs forma extensiva S=5 + held-out, IEEE-13 T=9) | `scripts/compare_default_stochastic.jl` | `results/compare_default_stochastic/` |

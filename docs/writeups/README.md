# Writeups

Authored prose documents for the TSO-DSO project — model formulations and results reproductions,
written in [Typst](https://typst.app/).

- **Tracked:** the `.typ` sources (the source of truth).
- **Not tracked:** the compiled `.pdf` (gitignored — regenerate with `typst compile <file>.typ`).

This is deliberately separate from `docs/references/` (gitignored), which holds **third-party
copyrighted** material (the thesis, papers, PSR note) kept local and not redistributed.

| Writeup | Companion script | Figures |
|---------|------------------|---------|
| `thesis_caseA.typ` — Camada Operacional da Tese, Caso A (IEEE-13 modificado) | `scripts/thesis_caseA.jl` | `results/thesis_caseA/` |
| `modelo_stackelberg_dso_unico.typ` — single-DSO Stackelberg model (v2.0 planning layer) | — | — |
| `stackelberg_vs_psr_n1n2.typ` — term-by-term PSR N1-N2 note ↔ `src/planning/` mapping | — | — |
| `ieee8500_exatidao_socp.typ` — investigação da exatidão SOCP no IEEE-8500 (oito estágios, três voltas erradas, resolução por merge topológico) | — | — |

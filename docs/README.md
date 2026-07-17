# Documentação — índice

Ponto de partida da documentação do `GoogleCloud_Projects`. Comece pelo doc-mestre e
desça para o detalhe conforme a necessidade.

## 🧭 Comece aqui
- **[ARQUITETURA-GERAL.md](ARQUITETURA-GERAL.md)** — visão completa: o projeto, os 3 MCPs,
  a arquitetura no Google Cloud, deploy, custo e as decisões. **Leia primeiro.**

## 🏛️ Arquitetura e padrões
- [ARQUITETURA_REFERENCIA_MCP.md](ARQUITETURA_REFERENCIA_MCP.md) — as "6 regras de ouro" de um
  MCP barato e estável no Cloud Run **+ a exceção (VM) para sessão persistente**.
- [mcp-conectores-e-deploy.md](mcp-conectores-e-deploy.md) — os conectores no claude.ai
  (regra do nome ASCII), URLs, pipeline de deploy dos 3 MCPs.
- [whatsapp-mcp-arquitetura.md](whatsapp-mcp-arquitetura.md) — arquitetura do MCP de WhatsApp,
  as 15 ferramentas, e a **tabela de troubleshooting** (405, git ownership, 9º dígito, OAuth…).

## 💰 Custos
- [custos-consolidado.md](custos-consolidado.md) — custo dos 3 MCPs + monitoria, e por que ~R$0.
- [COMO_LER.md](COMO_LER.md) — como interpretar o relatório diário de custos (`reports/`).
- [SETUP.md](SETUP.md) — setup único da monitoria (BigQuery export, service account, secrets).
- [PAGES.md](PAGES.md) — publicar o painel web (`docs/index.html`) no GitHub Pages.
- [LOGS.md](LOGS.md) — sink de logs.

## 📈 Decisões e vereditos (o "porquê")
- [estudo-viabilidade-mcp-whatsapp.md](estudo-viabilidade-mcp-whatsapp.md) — por que WhatsApp via Baileys em VM.
- [veredito-analise-estrutural.md](veredito-analise-estrutural.md) — estrutura de preço não gera edge (não construir a #2).
- [status-operacoes-risco-payoff.md](status-operacoes-risco-payoff.md) — risco por payoff (travado vs descoberto).
- [whitelist-dinamica-dados-ativos.md](whitelist-dinamica-dados-ativos.md) — whitelist = aba DADOS_ATIVOS.
- [auditoria-independente-mcps.md](auditoria-independente-mcps.md) — auditoria por recálculo independente (1 bug achado).

## 🗂️ Onde vive cada coisa
- Código dos MCPs (cópias): [`../patches/`](../patches/) — `oplab_mcp/`, `google-sheets-mcp/`, `whatsapp_mcp/`.
- Scripts de deploy: [`../scripts/`](../scripts/).
- Relatórios de custo (gerados): [`../reports/`](../reports/).
- Queries de billing: [`../queries/`](../queries/).

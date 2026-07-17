# GoogleCloud_Projects

Ecossistema pessoal para **operar derivativos na B3** (venda de volatilidade / travas) com apoio
do Claude, rodando **quase inteiramente no Google Cloud a ~R$0/mês**. Duas frentes convivem aqui:

1. **Três servidores MCP** que dão ao Claude ferramentas de mercado, carteira e alertas.
2. **Monitoria total de custos GCP** — para garantir que a conta nunca escape do free tier.

> 📖 **Entenda tudo em 5 min:** [`docs/ARQUITETURA-GERAL.md`](docs/ARQUITETURA-GERAL.md) é o
> documento-mestre (o quê, onde roda, como faz deploy, quanto custa e por quê). Índice completo
> da documentação em [`docs/README.md`](docs/README.md).

---

## 🤖 Os três MCPs

| MCP | Função | Onde roda | Custo |
|-----|--------|-----------|-------|
| **OpLab** | Mercado, IV Rank, estrutura de preço, backtests, manejo | Cloud Run (`oplab-mcp-server`) | ~R$0 |
| **Cockpit** | Carteira/posições e risco (lê a planilha Google Sheets) | Cloud Run (`oplab-sheets-mcp`) | ~R$0 |
| **WhatsApp** | Envia alertas / recebe comandos (com confirmação de entrega) | Compute Engine e2-micro (Always Free) | ~R$0 |

O Claude (claude.ai) conecta nos 3 como conectores MCP e orquestra: lê mercado/carteira e pode
te alertar no WhatsApp. Detalhes em [`docs/mcp-conectores-e-deploy.md`](docs/mcp-conectores-e-deploy.md)
e [`docs/whatsapp-mcp-arquitetura.md`](docs/whatsapp-mcp-arquitetura.md).

**Código dos MCPs** (cópias versionadas): [`patches/`](patches/) · **Deploy**: [`scripts/`](scripts/)
(rodados no Cloud Shell). Repos de origem: `brunotrolo/oplab_mcp`, `brunotrolo/google-sheets-mcp`,
`brunotrolo/WhatsApp_MCP`.

### Por que ~R$0/mês
Cloud Run com `min-instances=0` (escala a zero) para OpLab/Cockpit; VM `e2-micro` no **Always Free
tier** para o WhatsApp (a sessão WhatsApp Web exige processo sempre ligado, incompatível com Cloud
Run). Detalhe consolidado em [`docs/custos-consolidado.md`](docs/custos-consolidado.md).

---

## 💰 Monitoria de custos GCP

Kit para descobrir **a origem de cada centavo** cobrado no Google Cloud. A fonte é o **BigQuery
Billing Export detalhado** (nível de recurso). O relatório se gera **sozinho todo dia** via GitHub
Actions e é commitado em [`reports/`](reports/); há também um painel web ([`docs/index.html`](docs/index.html)).

```
BigQuery Billing Export → queries/*.sql → scripts/gerar_relatorio.sh → reports/cost-report-DATA.md
                                       (GitHub Action diária + sob demanda)
```

| Caminho | O quê |
|---------|-------|
| [`docs/SETUP.md`](docs/SETUP.md) | Setup único: export, service account, secrets |
| [`docs/COMO_LER.md`](docs/COMO_LER.md) | Como interpretar o relatório e achar os vilões |
| [`docs/PAGES.md`](docs/PAGES.md) | Publicar o painel web no GitHub Pages |
| [`queries/`](queries/) | 8 queries SQL (serviço, SKU, recurso, dia, label, créditos, idle, projeto) |
| [`reports/`](reports/) | Relatórios gerados (commitados automaticamente) |

Peça ao Claude: **"lê o último relatório de custos e me diz de onde vem cada centavo"**.

---

## 🗂️ Estrutura do repositório

| Pasta | Conteúdo |
|---|---|
| [`docs/`](docs/) | Toda a documentação (comece por `ARQUITETURA-GERAL.md`) |
| [`patches/`](patches/) | Cópias versionadas do código dos 3 MCPs |
| [`scripts/`](scripts/) | Scripts de deploy (Cloud Shell) e utilitários |
| [`queries/`](queries/) | Queries SQL da monitoria de custos |
| [`reports/`](reports/) | Relatórios de custo gerados automaticamente |

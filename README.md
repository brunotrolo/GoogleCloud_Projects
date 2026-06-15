# GoogleCloud_Projects — Monitoria Total de Custos GCP

Kit para descobrir **a origem de cada centavo** cobrado no Google Cloud — seja
infra (Cloud Run, Compute, rede, storage, logging) ou qualquer SKU recorrente que
"liga junto com o projeto" e dispara a fatura.

A fonte é o **BigQuery Billing Export detalhado** (nível de recurso), que registra
cada SKU em cada recurso. O relatório se gera **sozinho todo dia** via GitHub Actions
e é commitado em [`reports/`](reports/) — depois é só me pedir pra ler e analisar.

## 📊 Painel web (GitHub Pages)

Há também um **painel HTML** (`docs/index.html`) que mostra visualmente o total,
o custo por serviço, **a origem de cada centavo (por SKU)**, por dia e por projeto.
Para publicar, veja [`docs/PAGES.md`](docs/PAGES.md). Ele já vem semeado com dados
reais de exemplo e passa a se atualizar sozinho junto com o relatório.

## Como funciona

```
BigQuery Billing Export  →  queries/*.sql  →  scripts/gerar_relatorio.sh  →  reports/cost-report-DATA.md
                                          (GitHub Action diária + sob demanda)
```

## Estrutura

| Caminho | O quê |
|---------|-------|
| [`docs/SETUP.md`](docs/SETUP.md) | Passo a passo (faz uma vez): export, service account, secrets |
| [`docs/COMO_LER.md`](docs/COMO_LER.md) | Como interpretar o relatório e achar os vilões |
| [`queries/`](queries/) | 8 queries SQL: por serviço, SKU, recurso, dia, label, créditos, idle, projeto |
| [`scripts/gerar_relatorio.sh`](scripts/gerar_relatorio.sh) | Roda as queries e monta o relatório Markdown |
| [`.github/workflows/cost-report.yml`](.github/workflows/cost-report.yml) | Automação diária + manual |
| [`reports/`](reports/) | Relatórios gerados (commitados automaticamente) |

## Começar

1. Siga [`docs/SETUP.md`](docs/SETUP.md) (≈10 min, uma vez só).
2. Espere o primeiro relatório aparecer em `reports/` (ou dispare manual em **Actions**).
3. Me chame: **"lê o último relatório de custos e me diz de onde vem cada centavo"**.

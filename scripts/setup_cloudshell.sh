#!/usr/bin/env bash
#
# setup_cloudshell.sh — Configura TODA a automação a partir do Google Cloud Shell.
#
# O que ele faz (via terminal, sem cliques):
#   1. Cria a service account de leitura do billing + chave JSON
#   2. Usa o `gh` (GitHub CLI, já instalado no Cloud Shell) para:
#        - gravar os secrets BQ_BILLING_TABLE e GCP_SA_KEY no repo
#        - ligar o GitHub Pages apontando para main /docs
#   3. Dispara o workflow uma vez para gerar o painel já com dados reais
#
# ANTES de rodar, edite as 2 variáveis abaixo (PROJETO e TABELA).
# A TABELA você pega no Console depois de ligar o "Custo de uso detalhado"
# (Billing → Exportação → BigQuery). Esse passo do export é o ÚNICO que
# precisa ser feito no Console — não existe comando gcloud para ele.
#
set -euo pipefail

# ===================== EDITE AQUI =====================
PROJETO="oplab-sheets-mcp-project"     # projeto que contém o dataset do billing export
TABELA="oplab-sheets-mcp-project.billing.gcp_billing_export_resource_v1_01A65F_62F735_7F6904"  # nome COMPLETO da tabela do export
REPO="brunotrolo/GoogleCloud_Projects" # repo onde está o painel
# ======================================================

echo "==> 1/4 Criando service account de leitura em $PROJETO"
gcloud config set project "$PROJETO" >/dev/null
gcloud services enable bigquery.googleapis.com >/dev/null

SA="cost-report@${PROJETO}.iam.gserviceaccount.com"
gcloud iam service-accounts describe "$SA" >/dev/null 2>&1 || \
  gcloud iam service-accounts create cost-report \
    --display-name="Cost Report (leitura billing)"

gcloud projects add-iam-policy-binding "$PROJETO" \
  --member="serviceAccount:${SA}" --role="roles/bigquery.jobUser" --condition=None >/dev/null
gcloud projects add-iam-policy-binding "$PROJETO" \
  --member="serviceAccount:${SA}" --role="roles/bigquery.dataViewer" --condition=None >/dev/null

echo "==> 2/4 Gerando chave da service account"
gcloud iam service-accounts keys create /tmp/sa-key.json --iam-account="$SA" >/dev/null

echo "==> 3/4 Configurando GitHub (secrets + Pages) via gh"
gh auth status >/dev/null 2>&1 || gh auth login
gh secret set BQ_BILLING_TABLE --repo "$REPO" --body "$TABELA"
gh secret set GCP_SA_KEY       --repo "$REPO" < /tmp/sa-key.json

# liga o Pages em main /docs (ignora erro se já estiver ligado)
gh api -X POST "repos/${REPO}/pages" \
  -f "source[branch]=main" -f "source[path]=/docs" >/dev/null 2>&1 || \
  echo "   (Pages já estava ligado ou requer ativação manual em Settings → Pages)"

echo "==> 4/4 Disparando o workflow para gerar o painel agora"
gh workflow run "Relatório de Custos GCP" --repo "$REPO" || \
  echo "   (rode manualmente em Actions → Run workflow se necessário)"

rm -f /tmp/sa-key.json
echo ""
echo "✅ Pronto! Em ~2 min:"
echo "   - Painel: https://brunotrolo.github.io/GoogleCloud_Projects/"
echo "   - Relatórios: pasta reports/ do repo"
echo ""
echo "Obs.: o billing export só registra dados a partir do momento em que foi"
echo "ligado no Console — pode levar algumas horas para os primeiros números."

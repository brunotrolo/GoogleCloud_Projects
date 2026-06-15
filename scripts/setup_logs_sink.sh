#!/usr/bin/env bash
#
# setup_logs_sink.sh — Exporta os logs de REQUISIÇÃO do Cloud Run para o BigQuery,
# nos dois projetos dos MCPs, gravando no mesmo dataset. Assim dá para contar
# chamadas por MCP ao longo do tempo (e cruzar com o custo por chamada).
#
# Rode no Google Cloud Shell. Não toca no código dos MCPs.
#
set -euo pipefail

# ===================== EDITE SE PRECISAR =====================
DATASET_PROJ="oplab-mcp-server"          # projeto que vai guardar o dataset de logs
DATASET="mcp_logs"                        # nome do dataset
LOCATION="US"                             # local do dataset (igual ao do billing)
PROJETOS=("oplab-mcp-server" "oplab-sheets-mcp-project")  # projetos com MCPs no Cloud Run
# =============================================================

echo "==> Criando dataset $DATASET_PROJ:$DATASET"
bq --location="$LOCATION" mk --dataset "$DATASET_PROJ:$DATASET" 2>/dev/null || echo "   (dataset já existe)"

FILTER='resource.type="cloud_run_revision" AND logName:"run.googleapis.com%2Frequests"'
DEST="bigquery.googleapis.com/projects/${DATASET_PROJ}/datasets/${DATASET}"

for P in "${PROJETOS[@]}"; do
  SINK="mcp-requests-to-bq"
  echo "==> Criando sink em $P"
  if gcloud logging sinks describe "$SINK" --project "$P" >/dev/null 2>&1; then
    gcloud logging sinks update "$SINK" "$DEST" --project "$P" --log-filter="$FILTER" >/dev/null
  else
    gcloud logging sinks create "$SINK" "$DEST" --project "$P" --log-filter="$FILTER" >/dev/null
  fi
  # dá permissão de escrita da conta do sink no dataset
  SA=$(gcloud logging sinks describe "$SINK" --project "$P" --format="value(writerIdentity)")
  echo "   writer: $SA"
  bq add-iam-policy-binding --member="$SA" --role="roles/bigquery.dataEditor" \
     "${DATASET_PROJ}:${DATASET}" >/dev/null 2>&1 || \
  gcloud projects add-iam-policy-binding "$DATASET_PROJ" \
     --member="$SA" --role="roles/bigquery.dataEditor" --condition=None >/dev/null
done

echo ""
echo "✅ Sinks criados. Os logs começam a popular o BigQuery a partir de AGORA."
echo "   Tabela (após o 1º request): ${DATASET_PROJ}.${DATASET}.run_googleapis_com_requests_*"
echo ""
echo "Adicione este secret no GitHub para o painel usar os logs:"
echo "   gh secret set LOGS_TABLE --repo brunotrolo/GoogleCloud_Projects \\"
echo "     --body '${DATASET_PROJ}.${DATASET}.run_googleapis_com_requests_*'"

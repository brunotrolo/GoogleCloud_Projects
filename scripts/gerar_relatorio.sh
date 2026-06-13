#!/usr/bin/env bash
#
# gerar_relatorio.sh — Roda todas as queries do diretório queries/ contra o
# BigQuery Billing Export e monta UM relatório Markdown detalhado em reports/.
#
# Uso:
#   export BQ_BILLING_TABLE="projeto.dataset.gcp_billing_export_resource_v1_XXXXXX"
#   export DIAS="${DIAS:-30}"          # janela de análise (padrão 30 dias)
#   ./scripts/gerar_relatorio.sh
#
# Pré-requisitos: gcloud autenticado e bq instalado (vem no Cloud Shell e na Action).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${BQ_BILLING_TABLE:?Defina BQ_BILLING_TABLE=projeto.dataset.gcp_billing_export_resource_v1_XXXXXX}"
DIAS="${DIAS:-30}"

END="$(date -u +%F)"
START="$(date -u -d "-${DIAS} days" +%F 2>/dev/null || date -u -v-"${DIAS}"d +%F)"

mkdir -p reports
OUT="reports/cost-report-${END}.md"

echo "# Relatório de Custos GCP — ${END}" >  "$OUT"
echo ""                                    >> "$OUT"
echo "- **Período:** ${START} → ${END} (${DIAS} dias)" >> "$OUT"
echo "- **Fonte:** \`${BQ_BILLING_TABLE}\` (BigQuery Billing Export)" >> "$OUT"
echo "- **Gerado em (UTC):** $(date -u '+%F %T')" >> "$OUT"
echo "" >> "$OUT"

# Títulos amigáveis por arquivo
declare -A TITULOS=(
  [01_resumo_por_servico.sql]="1. Custo por Serviço (visão macro)"
  [02_por_sku.sql]="2. Custo por SKU (item exato cobrado)"
  [03_por_recurso.sql]="3. Custo por Recurso específico"
  [04_por_dia.sql]="4. Custo por Dia (tendência)"
  [05_por_label.sql]="5. Custo por Label"
  [06_creditos.sql]="6. Créditos aplicados"
  [07_custo_recorrente_idle.sql]="7. Custo Recorrente / Idle (liga e já cobra)"
  [08_por_projeto.sql]="8. Custo por Projeto"
)

run_query () {
  local file="$1"
  local titulo="${TITULOS[$(basename "$file")]:-$(basename "$file")}"
  echo "## ${titulo}" >> "$OUT"
  echo "" >> "$OUT"

  local sql
  sql="$(sed -e "s|@TABLE@|${BQ_BILLING_TABLE}|g" \
             -e "s|@START@|${START}|g" \
             -e "s|@END@|${END}|g" "$file")"

  if bq query --use_legacy_sql=false --format=prettyjson "$sql" > /tmp/q.json 2>/tmp/q.err; then
    python3 scripts/json_to_md.py /tmp/q.json >> "$OUT" || echo "_(sem linhas / erro ao formatar)_" >> "$OUT"
  else
    echo '```' >> "$OUT"
    cat /tmp/q.err >> "$OUT"
    echo '```' >> "$OUT"
  fi
  echo "" >> "$OUT"
}

for f in queries/*.sql; do
  run_query "$f"
done

echo "Relatório gerado em: $OUT"

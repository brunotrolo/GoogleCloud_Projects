#!/usr/bin/env python3
"""gerar_monitoring.py — Fonte de dados QUASE EM TEMPO REAL para o painel.

Em vez do BigQuery billing export (lento e não-retroativo), usa o Cloud
Monitoring, que reflete o uso do Cloud Run em minutos:
  - run.googleapis.com/container/billable_instance_time  → tempo faturável
  - run.googleapis.com/request_count                     → nº de chamadas

Estima o custo a partir do tempo faturável e dos preços do Cloud Run (us-east1,
cobrança por requisição). Escreve docs/data/costs.json.

Auth: usa Application Default Credentials (o google-github-actions/auth já provê).
"""
import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

from google.cloud import monitoring_v3

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIAS = int(os.environ.get("DIAS", "14"))

# Serviços monitorados: (projeto, nome_do_servico, vCPU, memoria_GiB)
SERVICES = [
    ("oplab-mcp-server", "oplab-mcp-server", 1.0, 0.5),
    ("oplab-sheets-mcp-project", "oplab-sheets-mcp", 1.0, 0.5),
]

# Preços Cloud Run us-east1 (request-based), em USD. Ajustáveis por env.
PRICE_CPU = float(os.environ.get("PRICE_CPU_VCPU_S", "0.000024"))   # USD por vCPU-segundo
PRICE_MEM = float(os.environ.get("PRICE_MEM_GIB_S", "0.0000025"))   # USD por GiB-segundo
USD_BRL = float(os.environ.get("USD_BRL", "5.40"))

client = monitoring_v3.MetricServiceClient()
now = datetime.now(timezone.utc)
start = now - timedelta(days=DIAS)

interval = monitoring_v3.TimeInterval(
    {"end_time": {"seconds": int(now.timestamp())},
     "start_time": {"seconds": int(start.timestamp())}}
)


def daily_sum(project: str, service: str, metric: str):
    """Retorna {dia(YYYY-MM-DD): soma} para o metric/serviço, alinhado por dia."""
    aggregation = monitoring_v3.Aggregation(
        {
            "alignment_period": {"seconds": 86400},
            "per_series_aligner": monitoring_v3.Aggregation.Aligner.ALIGN_DELTA,
            "cross_series_reducer": monitoring_v3.Aggregation.Reducer.REDUCE_SUM,
            "group_by_fields": ["resource.labels.service_name"],
        }
    )
    flt = (
        f'metric.type="{metric}" '
        f'AND resource.labels.service_name="{service}"'
    )
    out = defaultdict(float)
    try:
        results = client.list_time_series(
            request={
                "name": f"projects/{project}",
                "filter": flt,
                "interval": interval,
                "view": monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL,
                "aggregation": aggregation,
            }
        )
        for ts in results:
            for p in ts.points:
                day = datetime.fromtimestamp(p.interval.end_time.timestamp(), timezone.utc).strftime("%Y-%m-%d")
                val = p.value.double_value or p.value.int64_value
                out[day] += float(val)
    except Exception as e:  # noqa: BLE001
        print(f"AVISO monitoring {service}/{metric}: {e}", file=sys.stderr)
    return out


by_day_total = defaultdict(float)
by_calls = []
by_mcp = []
total_cost = 0.0

for project, service, vcpu, mem in SERVICES:
    bit = daily_sum(project, service, "run.googleapis.com/container/billable_instance_time")
    reqs = daily_sum(project, service, "run.googleapis.com/request_count")

    sec_total = sum(bit.values())
    req_total = sum(reqs.values())
    # custo estimado = tempo faturável (s) * (vCPU*preço_cpu + mem*preço_mem), em BRL
    cost_per_sec = (vcpu * PRICE_CPU + mem * PRICE_MEM) * USD_BRL
    cost = sec_total * cost_per_sec
    total_cost += cost

    for day, sec in bit.items():
        by_day_total[day] += sec * cost_per_sec
    for day, c in reqs.items():
        by_calls.append({"mcp": service, "dia": day, "chamadas": round(c)})

    by_mcp.append({
        "mcp": service,
        "requisicoes": round(req_total),
        "billable_segundos": round(sec_total),
        "custo_liquido": round(cost, 2),
        "custo_por_requisicao": round(cost / req_total, 6) if req_total else 0,
    })

by_day = [{"dia": d, "custo_liquido": round(v, 2)} for d, v in sorted(by_day_total.items())]
last_day = by_day[-1]["dia"] if by_day else None

by_service = [{"servico": "Cloud Run (estimado)", "custo_liquido": round(total_cost, 2)}]

data = {
    "generated_at": now.strftime("%Y-%m-%d %H:%M UTC"),
    "fonte": "Cloud Monitoring (tempo quase real). Custo é ESTIMADO a partir do tempo faturável de CPU/memória do Cloud Run.",
    "data_source": "monitoring",
    "last_data_day": last_day,
    "period": {"start": start.strftime("%Y-%m-%d"), "end": now.strftime("%Y-%m-%d")},
    "currency": "BRL",
    "total": round(total_cost, 2),
    "by_mcp": sorted(by_mcp, key=lambda x: -x["custo_liquido"]),
    "by_calls": by_calls,
    "by_service": by_service,
    "by_sku": [],
    "by_day": by_day,
    "by_project": [],
}

out_path = os.path.join(ROOT, "docs", "data", "costs.json")
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)

print(f"OK: {out_path} — total estimado BRL {total_cost:.2f}, último dia com dados: {last_day}")

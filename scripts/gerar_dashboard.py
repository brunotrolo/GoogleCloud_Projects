#!/usr/bin/env python3
"""Gera docs/data/costs.json (consumido pela página HTML do GitHub Pages).

Roda as queries de queries/*.sql contra o BigQuery Billing Export via `bq` e
monta um único JSON com total, por serviço, por SKU, por dia e por projeto.

Uso:
  BQ_BILLING_TABLE="projeto.dataset.gcp_billing_export_resource_v1_XXXX" \
  DIAS=30 python3 scripts/gerar_dashboard.py
"""
import json
import os
import subprocess
import sys
from datetime import date, timedelta

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TABLE = os.environ.get("BQ_BILLING_TABLE")
DIAS = int(os.environ.get("DIAS", "30"))

if not TABLE:
    sys.exit("Defina BQ_BILLING_TABLE=projeto.dataset.gcp_billing_export_resource_v1_XXXX")

END = date.today()
START = END - timedelta(days=DIAS)


def run_sql_file(fname: str):
    path = os.path.join(ROOT, "queries", fname)
    with open(path, encoding="utf-8") as fh:
        sql = fh.read()
    sql = (sql.replace("@TABLE@", TABLE)
              .replace("@START@", START.isoformat())
              .replace("@END@", END.isoformat()))
    out = subprocess.run(
        ["bq", "query", "--use_legacy_sql=false", "--format=prettyjson", sql],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        print(f"AVISO: falha em {fname}: {out.stderr}", file=sys.stderr)
        return []
    return json.loads(out.stdout or "[]")


def to_float(rows, *keys):
    for r in rows:
        for k in keys:
            if k in r and r[k] is not None:
                try:
                    r[k] = float(r[k])
                except (TypeError, ValueError):
                    pass
    return rows


by_service = to_float(run_sql_file("01_resumo_por_servico.sql"), "custo_liquido", "custo_bruto", "creditos")
by_sku = to_float(run_sql_file("02_por_sku.sql"), "custo_liquido", "custo_bruto", "quantidade")
by_day = to_float(run_sql_file("04_por_dia.sql"), "custo_liquido")
by_project = to_float(run_sql_file("08_por_projeto.sql"), "custo_liquido")

total = round(sum(r.get("custo_liquido", 0) for r in by_service), 2)
currency = (by_service[0].get("moeda") if by_service else "BRL") or "BRL"

data = {
    "generated_at": END.isoformat(),
    "fonte": "Atualizado automaticamente a partir do BigQuery Billing Export.",
    "period": {"start": START.isoformat(), "end": END.isoformat()},
    "currency": currency,
    "total": total,
    "by_service": by_service,
    "by_sku": by_sku,
    "by_day": by_day,
    "by_project": by_project,
}

out_path = os.path.join(ROOT, "docs", "data", "costs.json")
os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(data, fh, ensure_ascii=False, indent=2)

print(f"Gerado: {out_path} (total {currency} {total})")

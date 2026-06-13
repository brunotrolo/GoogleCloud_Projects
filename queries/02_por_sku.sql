-- 02 — Custo por SKU (granularidade fina: o item exato cobrado)
-- Ex.: "Cloud Run CPU Allocation Time", "Network Egress", "PD Capacity"
SELECT
  service.description                                   AS servico,
  sku.description                                       AS sku,
  ROUND(SUM(cost), 2)                                   AS custo_bruto,
  ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS custo_liquido,
  ROUND(SUM(usage.amount), 2)                           AS quantidade,
  ANY_VALUE(usage.unit)                                 AS unidade,
  currency                                              AS moeda
FROM `@TABLE@`
WHERE DATE(usage_start_time) BETWEEN '@START@' AND '@END@'
GROUP BY servico, sku, moeda
HAVING custo_liquido > 0.001
ORDER BY custo_liquido DESC
LIMIT 50;

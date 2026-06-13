-- 07 — CUSTO RECORRENTE / IDLE ("liguei o projeto e já vem custo")
-- Os suspeitos clássicos que cobram MESMO sem tráfego/uso:
--   IPs estáticos reservados, discos persistentes, snapshots, Cloud SQL,
--   NAT gateway, Load Balancer, min-instances de Cloud Run, imagens em Artifact Registry,
--   logging/monitoring retidos.
SELECT
  service.description                                   AS servico,
  sku.description                                       AS sku,
  ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS custo_liquido,
  currency                                              AS moeda
FROM `@TABLE@`
WHERE DATE(usage_start_time) BETWEEN '@START@' AND '@END@'
  AND (
       LOWER(sku.description) LIKE '%static ip%'
    OR LOWER(sku.description) LIKE '%external ip%'
    OR LOWER(sku.description) LIKE '%unused%'
    OR LOWER(sku.description) LIKE '%idle%'
    OR LOWER(sku.description) LIKE '%pd capacity%'
    OR LOWER(sku.description) LIKE '%ssd%'
    OR LOWER(sku.description) LIKE '%snapshot%'
    OR LOWER(sku.description) LIKE '%nat gateway%'
    OR LOWER(sku.description) LIKE '%forwarding rule%'
    OR LOWER(sku.description) LIKE '%load balanc%'
    OR LOWER(sku.description) LIKE '%cloud sql%'
    OR LOWER(sku.description) LIKE '%storage%'
    OR LOWER(sku.description) LIKE '%artifact%'
    OR LOWER(sku.description) LIKE '%container registry%'
    OR LOWER(sku.description) LIKE '%logging%'
    OR LOWER(sku.description) LIKE '%monitoring%'
    OR LOWER(sku.description) LIKE '%min instance%'
    OR LOWER(sku.description) LIKE '%committed%'
    OR LOWER(sku.description) LIKE '%license%'
  )
GROUP BY servico, sku, moeda
HAVING custo_liquido > 0.001
ORDER BY custo_liquido DESC;

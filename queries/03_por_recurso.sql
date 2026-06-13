-- 03 — Custo por RECURSO específico (qual instância/serviço/disco é o vilão)
-- Requer o export "detalhado" (resource-level). resource.name = id global do recurso.
SELECT
  service.description                                   AS servico,
  resource.name                                         AS recurso,
  ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS custo_liquido,
  currency                                              AS moeda
FROM `@TABLE@`
WHERE DATE(usage_start_time) BETWEEN '@START@' AND '@END@'
  AND resource.name IS NOT NULL
GROUP BY servico, recurso, moeda
HAVING custo_liquido > 0.001
ORDER BY custo_liquido DESC
LIMIT 50;

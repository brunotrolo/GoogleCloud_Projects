-- 01 — Custo por SERVIÇO (visão macro: "qual produto do GCP está cobrando")
-- Responde: Cloud Run? Compute? Logging? Networking? Storage?
SELECT
  service.description                                   AS servico,
  ROUND(SUM(cost), 2)                                  AS custo_bruto,
  ROUND(SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS creditos,
  ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS custo_liquido,
  currency                                              AS moeda
FROM `@TABLE@`
WHERE DATE(usage_start_time) BETWEEN '@START@' AND '@END@'
GROUP BY servico, moeda
HAVING custo_liquido > 0.001
ORDER BY custo_liquido DESC;

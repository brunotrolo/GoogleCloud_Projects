-- 05 — Custo por LABEL (separa MCP-A de MCP-B, ambiente, dono...)
-- Só funciona bem se você rotular os recursos. Mostra labels existentes.
SELECT
  l.key                                                 AS label_chave,
  l.value                                               AS label_valor,
  ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS custo_liquido,
  currency                                              AS moeda
FROM `@TABLE@`, UNNEST(labels) AS l
WHERE DATE(usage_start_time) BETWEEN '@START@' AND '@END@'
GROUP BY label_chave, label_valor, moeda
HAVING custo_liquido > 0.001
ORDER BY custo_liquido DESC
LIMIT 50;

-- 08 — Custo por PROJETO (se houver mais de um projeto na conta de billing)
SELECT
  project.id                                            AS projeto_id,
  project.name                                          AS projeto_nome,
  ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS custo_liquido,
  currency                                              AS moeda
FROM `@TABLE@`
WHERE DATE(usage_start_time) BETWEEN '@START@' AND '@END@'
GROUP BY projeto_id, projeto_nome, moeda
HAVING custo_liquido > 0.001
ORDER BY custo_liquido DESC;

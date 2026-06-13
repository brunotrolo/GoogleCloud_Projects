-- 04 — Custo por DIA (tendência: detecta o "liguei o projeto e disparou")
SELECT
  DATE(usage_start_time)                                AS dia,
  ROUND(SUM(cost) + SUM(IFNULL((SELECT SUM(c.amount) FROM UNNEST(credits) c), 0)), 2) AS custo_liquido,
  currency                                              AS moeda
FROM `@TABLE@`
WHERE DATE(usage_start_time) BETWEEN '@START@' AND '@END@'
GROUP BY dia, moeda
ORDER BY dia;

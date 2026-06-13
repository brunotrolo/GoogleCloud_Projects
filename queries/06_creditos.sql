-- 06 — CRÉDITOS aplicados (free tier, descontos, promoções)
-- Mostra o que está sendo abatido — útil pra prever quando o crédito acabar.
SELECT
  service.description                                   AS servico,
  c.type                                                AS tipo_credito,
  c.name                                                AS nome_credito,
  ROUND(SUM(c.amount), 2)                               AS valor_credito,
  currency                                              AS moeda
FROM `@TABLE@`, UNNEST(credits) AS c
WHERE DATE(usage_start_time) BETWEEN '@START@' AND '@END@'
GROUP BY servico, tipo_credito, nome_credito, moeda
ORDER BY valor_credito;

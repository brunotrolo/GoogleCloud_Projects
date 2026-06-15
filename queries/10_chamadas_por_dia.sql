-- 10 — CHAMADAS por dia, por MCP (origem: logs de requisição do Cloud Run)
-- Cada linha = um dia de um MCP, com o nº de chamadas recebidas e a latência média.
-- Use junto com o "custo por chamada" (seção Uso por MCP) para estimar o custo.
SELECT
  resource.labels.service_name                          AS mcp,
  DATE(timestamp)                                       AS dia,
  COUNT(*)                                              AS chamadas,
  ROUND(AVG(SAFE_CAST(REGEXP_EXTRACT(httpRequest.latency, r'([0-9.]+)') AS FLOAT64)), 3) AS latencia_media_s
FROM `@LOGS@`
WHERE DATE(timestamp) BETWEEN '@START@' AND '@END@'
GROUP BY mcp, dia
ORDER BY dia, mcp;

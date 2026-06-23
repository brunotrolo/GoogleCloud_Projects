#!/usr/bin/env bash
#
# healthcheck_mcps.sh — Saúde dos MCPs: /health, handshake, nº de ferramentas e latência.
# Não precisa de gcloud nem credencial — só curl. Rode no Cloud Shell ou em qualquer terminal.
#
#   ./scripts/healthcheck_mcps.sh
#
set -uo pipefail

SERVICES=(
  "OpLab|https://oplab-mcp-server-544531071750.us-east1.run.app"
  "Sheets|https://oplab-sheets-mcp-6763522987.us-east1.run.app"
)

HDR=(-H "Content-Type: application/json" -H "Accept: application/json, text/event-stream")
INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"healthcheck","version":"1.0"}}}'
TOOLS='{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'

ms() { awk "BEGIN{printf \"%.0f ms\", ($2-$1)*1000}"; }

echo "🏥 Health-check dos MCPs — $(date '+%F %T %Z')"
ALL_OK=1

for entry in "${SERVICES[@]}"; do
  name="${entry%%|*}"; url="${entry#*|}"
  echo ""
  echo "════════════════════════════════════════════════════════"
  echo "🔎 $name"
  echo "   $url"

  # 1) /health
  read -r code ttot < <(curl -s -o /dev/null -w "%{http_code} %{time_total}" --max-time 30 "$url/health" || echo "000 0")
  echo "   • /health      : HTTP $code  (${ttot}s)"

  # 2) initialize (1ª chamada => mede cold start)
  t0=$(date +%s.%N)
  init=$(curl -s --max-time 30 "${HDR[@]}" -X POST "$url/mcp" -d "$INIT" || echo "")
  t1=$(date +%s.%N)
  sname=$(printf '%s' "$init" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
  proto=$(printf '%s' "$init" | grep -o '"protocolVersion":"[^"]*"' | head -1 | cut -d'"' -f4)
  if printf '%s' "$init" | grep -q '"result"'; then
    echo "   • initialize   : ✅  $(ms "$t0" "$t1")  [cold start]"
    echo "       serverInfo.name = $sname | protocol = $proto"
  else
    echo "   • initialize   : ❌ FALHOU"
    printf '       %s\n' "$(printf '%s' "$init" | head -c 160)"
    ALL_OK=0
  fi

  # 3) tools/list — conta ferramentas + latência (3 amostras, já "quente")
  cnt=0; best=99
  for i in 1 2 3; do
    t2=$(date +%s.%N)
    tools=$(curl -s --max-time 30 "${HDR[@]}" -X POST "$url/mcp" -d "$TOOLS" || echo "")
    t3=$(date +%s.%N)
    cnt=$(printf '%s' "$tools" | grep -o '"name":"[^"]*"' | wc -l | tr -d ' ')
    lat=$(awk "BEGIN{printf \"%.0f\", ($t3-$t2)*1000}")
    [ "$lat" -lt "$best" ] 2>/dev/null && best=$lat
  done
  echo "   • tools/list   : 🔧 $cnt ferramentas  | latência (quente) ~${best} ms"
  [ "$cnt" -gt 0 ] || ALL_OK=0

  # nomes das ferramentas
  printf '%s' "$tools" | grep -o '"name":"[^"]*"' | cut -d'"' -f4 | sed 's/^/       - /'
done

echo ""
echo "════════════════════════════════════════════════════════"
if [ "$ALL_OK" -eq 1 ]; then
  echo "✅ RESULTADO: os dois MCPs estão SAUDÁVEIS (handshake + ferramentas OK)."
else
  echo "⚠️  RESULTADO: algo falhou acima — veja os ❌."
fi

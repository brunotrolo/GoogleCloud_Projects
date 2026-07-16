#!/usr/bin/env bash
#
# aplicar_bs_local.sh — Corrige o get_options_bs do MCP OpLab: passa a calcular
# Black-Scholes LOCALMENTE quando o chamador informa os inputs do what-if.
#
# BUG CORRIGIDO (comprovado em auditoria): a API OpLab /market/options/bs IGNORA
# os parâmetros spotprice/vol quando recebe o symbol de uma opção (usa dado interno
# stale) e dá erro 500 no modo ação. Resultado: "e se o spot fosse X" devolvia número
# silenciosamente errado. Agora, se spotprice+strike+vol+prazo+type vierem informados,
# o MCP calcula por fórmula fechada (europeu, validado contra Hull); senão, passthrough.
#
#   cd ~/GoogleCloud_Projects && git pull && ./scripts/aplicar_bs_local.sh
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/patches/oplab_mcp"
WORK="$(mktemp -d)"; cd "$WORK"

git clone --depth 1 https://github.com/brunotrolo/oplab_mcp.git
cd oplab_mcp

cp "$SRC/bs_engine.ts"                  src/utils/bs_engine.ts
cp "$SRC/whitelist_source.ts"           src/utils/whitelist_source.ts
cp "$SRC/iv_calculator.ts"              src/utils/iv_calculator.ts
cp "$SRC/index.ts"                      src/index.ts
cp "$SRC/manejo_engine.ts"              src/utils/manejo_engine.ts
cp "$SRC/estrutura_engine.ts"           src/utils/estrutura_engine.ts
cp "$SRC/backtest_engine.ts"            src/utils/backtest_engine.ts
cp "$SRC/backtest_estrutural_engine.ts" src/utils/backtest_estrutural_engine.ts

echo "==> Testes (falha aborta o deploy)..."
cp "$SRC/bs_engine.test.ts" src/utils/bs_engine.test.ts
cp "$SRC/whitelist_source.test.ts" src/utils/whitelist_source.test.ts
node --experimental-strip-types src/utils/bs_engine.test.ts
node --experimental-strip-types src/utils/whitelist_source.test.ts
rm -f src/utils/bs_engine.test.ts src/utils/whitelist_source.test.ts

if git diff --quiet && [ -z "$(git status --porcelain)" ]; then
  echo "Nada a mudar (já está atualizado)."
else
  git add src/
  git config user.email "actions@github.com"
  git config user.name "bs-local-bot"
  git commit -qm "fix: get_options_bs calcula Black-Scholes local no what-if (endpoint ignora spotprice/vol)"
  git push
  echo "✅ Código enviado ao GitHub."
fi

echo "==> Redeploy (preserva configs de custo)..."
gcloud run deploy oplab-mcp-server --source . \
  --region us-east1 --project oplab-mcp-server \
  --cpu=1 --memory=512Mi --cpu-throttling --min-instances=0 --max-instances=2 --timeout=120

echo ""
echo "✅ Deploy concluído. Prova do fix (spot 43.14 vs 48 têm que dar preços DIFERENTES):"
cat <<'CURL'
for S in 43.14 48; do
curl -s -X POST https://oplab-mcp-server-544531071750.us-east1.run.app/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_options_bs","arguments":{
    "symbol":"ITUBH435","type":"CALL","spotprice":'"$S"',"strike":43.22,"irate":14.15,"dtm":27,"vol":23.4}}}' \
  | grep -o '"price":[0-9.]*'; done
CURL
echo ""
echo "No claude.ai NÃO precisa reconectar (mesma URL /mcp) — abra uma CONVERSA NOVA."

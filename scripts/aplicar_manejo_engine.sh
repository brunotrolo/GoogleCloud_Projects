#!/usr/bin/env bash
#
# aplicar_manejo_engine.sh — Publica o Motor de Manejo/Rolagem ATM-ITM no MCP da
# OpLab (nova ferramenta get_analise_manejo) e redeploya preservando as configs
# de custo. Código já compilado, testado (Monte Carlo vs fórmula fechada,
# determinismo, sanidade) e revisado adversarialmente (3 defeitos corrigidos).
#
#   cd ~/GoogleCloud_Projects && git pull && ./scripts/aplicar_manejo_engine.sh
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/patches/oplab_mcp"
WORK="$(mktemp -d)"; cd "$WORK"

git clone --depth 1 https://github.com/brunotrolo/oplab_mcp.git
cd oplab_mcp

cp "$SRC/manejo_engine.ts"    src/utils/manejo_engine.ts
cp "$SRC/iv_calculator.ts"    src/utils/iv_calculator.ts
cp "$SRC/estrutura_engine.ts" src/utils/estrutura_engine.ts
cp "$SRC/index.ts"            src/index.ts

if git diff --quiet && [ -z "$(git status --porcelain)" ]; then
  echo "Nada a mudar."
else
  git add src/
  git config user.email "actions@github.com"
  git config user.name "manejo-engine-bot"
  git commit -qm "feat: motor de manejo/rolagem ATM-ITM (get_analise_manejo) — 6 modulos com Monte Carlo de vol realizada"
  git push
  echo "✅ Código enviado ao GitHub."
fi

echo "==> Redeploy preservando configs de custo..."
gcloud run deploy oplab-mcp-server --source . \
  --region us-east1 --project oplab-mcp-server \
  --cpu=1 --memory=512Mi --cpu-throttling --min-instances=0 --max-instances=2 --timeout=120

echo ""
echo "✅ Deploy concluído. Teste ponta a ponta (VALE3 real):"
cat <<'CURL'
curl -s -X POST https://oplab-mcp-server-544531071750.us-east1.run.app/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_analise_manejo","arguments":{
    "ticker":"VALE3",
    "legs":[
      {"option_ticker":"VALES790","side":"VENDA","quantity":500,"entry_price":1.79},
      {"option_ticker":"VALES795","side":"COMPRA","quantity":500,"entry_price":1.04}
    ]}}}' | head -c 3000
CURL
echo ""
echo "No claude.ai NÃO precisa reconectar o conector (mesma URL /mcp) — mas abra"
echo "uma CONVERSA NOVA para a ferramenta nova aparecer na lista."

#!/usr/bin/env bash
#
# aplicar_oplab_completo.sh — Deploy do estado ATUAL completo do MCP OpLab.
# Reúne, num único deploy, tudo que está em patches/oplab_mcp/ ainda não publicado:
#   • fix get_options_bs (Black-Scholes LOCAL no what-if — PR #7)
#   • get_backtest_estrutural com incluir_operacoes=true (lista de trades individuais,
#     para auditoria/reconstrução independente — Teste #5)
#   • whitelist dinâmica (DADOS_ATIVOS) — já deployada antes, reincluída p/ consistência
#
# Substitui, por ora, os scripts aplicar_bs_local.sh e aplicar_whitelist_dinamica.sh
# (o index.ts atual importa bs_engine.ts, então tudo precisa subir junto).
#
#   cd ~/GoogleCloud_Projects && git checkout main && git pull && ./scripts/aplicar_oplab_completo.sh
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
  git config user.name "oplab-bot"
  git commit -qm "feat: BS local (get_options_bs) + get_backtest_estrutural incluir_operacoes (auditoria)"
  git push
  echo "✅ Código enviado ao GitHub."
fi

echo "==> Redeploy (preserva configs de custo)..."
gcloud run deploy oplab-mcp-server --source . \
  --region us-east1 --project oplab-mcp-server \
  --cpu=1 --memory=512Mi --cpu-throttling --min-instances=0 --max-instances=2 --timeout=120

echo ""
echo "✅ Deploy concluído. Fecha o Teste #5 (reconstrução independente):"
cat <<'CURL'
# 1) rode o backtest com o detalhe das operações:
curl -s -X POST https://oplab-mcp-server-544531071750.us-east1.run.app/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_backtest_estrutural",
       "arguments":{"tickers":["ITUB4"],"incluir_operacoes":true}}}' > /tmp/bt_itub.json
# 2) escolha 3 operações (início/meio/recente) do array "operacoes" e rode:
#    python3 scripts/backtest_oracle.py --d0 <entrada_date> --strike <strike> --premio <premio_entrada> \
#      --spot_d0 <close em D0> --vol <iv/100> --dte <dte> --spot_venc <spot_vencimento> \
#      --use_spread --strike_prot <strike_protecao> --premio_prot <premio_protecao> --delta_backtest <delta>
CURL
echo ""
echo "No claude.ai NÃO precisa reconectar (mesma URL /mcp) — abra uma CONVERSA NOVA."

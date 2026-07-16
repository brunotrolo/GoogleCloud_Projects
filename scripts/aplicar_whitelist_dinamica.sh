#!/usr/bin/env bash
#
# aplicar_whitelist_dinamica.sh — Atualiza a whitelist padrão do MCP OpLab (fallback
# quando `tickers` não é informado) e a liga à aba DADOS_ATIVOS da planilha.
#
# O QUE MUDA:
#  • Lista fixa atualizada para os 26 ativos da DADOS_ATIVOS (15/07/2026): saem
#    CMIN3, COGN3, CPLE6, ELET3; entram EQTL3, EGIE3, BPAC11. (CSAN3 permanece.)
#  • Fim da deriva: se DADOS_ATIVOS_CSV_URL estiver setada (endpoint "Publicar na
#    web → CSV" da aba DADOS_ATIVOS), o servidor lê a lista de lá com cache de 4h e
#    atualiza a whitelist IN-PLACE — vale para get_iv_rank_bulk, get_smart_money_tracker,
#    get_backtest_protocolo2, get_backtest_estrutural e get_analise_manejo de uma vez.
#    Sem a env (ou se a leitura falhar), usa a lista fixa (fallback seguro).
#  • Núcleo puro em src/utils/whitelist_source.ts, com 7 testes.
#
# COMO LIGAR A SINCRONIZAÇÃO DINÂMICA (opcional, faz uma vez):
#  1. Na planilha, Arquivo → Compartilhar → Publicar na web → aba DADOS_ATIVOS,
#     formato CSV → copie a URL.
#  2. Rode este script com a URL:  DADOS_ATIVOS_CSV_URL="https://..." ./scripts/aplicar_whitelist_dinamica.sh
#     (o script repassa a env para o Cloud Run). Sem informar, o deploy mantém o
#     comportamento de lista fixa.
#
#   cd ~/GoogleCloud_Projects && git pull && ./scripts/aplicar_whitelist_dinamica.sh
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/patches/oplab_mcp"
WORK="$(mktemp -d)"; cd "$WORK"

git clone --depth 1 https://github.com/brunotrolo/oplab_mcp.git
cd oplab_mcp

cp "$SRC/whitelist_source.ts"           src/utils/whitelist_source.ts
cp "$SRC/iv_calculator.ts"              src/utils/iv_calculator.ts
cp "$SRC/index.ts"                      src/index.ts
# Arquivos que compartilham o mesmo conjunto de patches (mantém o repo consistente):
cp "$SRC/manejo_engine.ts"              src/utils/manejo_engine.ts
cp "$SRC/estrutura_engine.ts"           src/utils/estrutura_engine.ts
cp "$SRC/backtest_engine.ts"            src/utils/backtest_engine.ts
cp "$SRC/backtest_estrutural_engine.ts" src/utils/backtest_estrutural_engine.ts

echo "==> Testes do núcleo da whitelist (falha aborta o deploy)..."
cp "$SRC/whitelist_source.test.ts" src/utils/whitelist_source.test.ts
node --experimental-strip-types src/utils/whitelist_source.test.ts
rm -f src/utils/whitelist_source.test.ts

if git diff --quiet && [ -z "$(git status --porcelain)" ]; then
  echo "Nada a mudar (já está atualizado)."
else
  git add src/
  git config user.email "actions@github.com"
  git config user.name "whitelist-bot"
  git commit -qm "feat: whitelist padrao = DADOS_ATIVOS (26 ativos) + sync dinamico via CSV com fallback"
  git push
  echo "✅ Código enviado ao GitHub."
fi

# Repassa a URL do CSV ao Cloud Run só se ela estiver no ambiente (senão, lista fixa).
ENVFLAG=()
if [ -n "${DADOS_ATIVOS_CSV_URL:-}" ]; then
  ENVFLAG=(--update-env-vars "DADOS_ATIVOS_CSV_URL=${DADOS_ATIVOS_CSV_URL}")
  echo "==> DADOS_ATIVOS_CSV_URL detectada — sincronização dinâmica LIGADA."
else
  echo "==> Sem DADOS_ATIVOS_CSV_URL — mantém lista fixa (fallback). Para ligar, veja o topo do script."
fi

echo "==> Redeploy (preserva configs de custo)..."
gcloud run deploy oplab-mcp-server --source . \
  --region us-east1 --project oplab-mcp-server \
  --cpu=1 --memory=512Mi --cpu-throttling --min-instances=0 --max-instances=2 --timeout=120 \
  "${ENVFLAG[@]}"

echo ""
echo "✅ Deploy concluído. Valide (deve trazer 26 ativos, sem COGN3/CMIN3/CPLE6/ELET3):"
cat <<'CURL'
curl -s -X POST https://oplab-mcp-server-544531071750.us-east1.run.app/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_iv_rank_bulk","arguments":{"periodo":252}}}' | head -c 2000
CURL
echo ""
echo "No claude.ai NÃO precisa reconectar (mesma URL /mcp) — abra uma CONVERSA NOVA."

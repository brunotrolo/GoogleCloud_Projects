#!/usr/bin/env bash
#
# dump_files_content.sh — Concatena o conteúdo COMPLETO da pasta files/ do
# google-sheets-mcp em analysis/files_content.md (commit + push), pra o Claude
# ler e fazer a mesclagem 8 -> 3 sem perder informação.
#
#   cd ~/GoogleCloud_Projects && git pull && ./scripts/dump_files_content.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/analysis/files_content.md"
WORK="$(mktemp -d)"
mkdir -p "$ROOT/analysis"

git -C "$WORK" clone --depth 1 https://github.com/brunotrolo/google-sheets-mcp.git >/dev/null 2>&1
D="$WORK/google-sheets-mcp/files"
cd "$D"

{
  echo "# Conteúdo completo de files/ — $(date -u '+%F %T') UTC"
  find . -type f | sort | while read -r f; do
    rel="${f#./}"
    echo ""
    echo "=================================================================="
    echo "===== ARQUIVO: $rel ($(wc -c <"$f" | tr -d ' ') bytes, $(wc -l <"$f" | tr -d ' ') linhas) ====="
    echo "=================================================================="
    echo '```'
    cat "$f"
    echo '```'
  done
} > "$OUT"

cd "$ROOT"
git add analysis/files_content.md
git config user.email "actions@github.com" 2>/dev/null || true
git config user.name "dump-bot" 2>/dev/null || true
git commit -q -m "analise: dump do conteudo de files/ para mesclagem" || echo "(sem mudancas)"
git push
echo "✅ Conteúdo despejado em analysis/files_content.md e enviado."
echo "   Agora peça: 'leia o conteudo e gere os 3 arquivos mesclados'."

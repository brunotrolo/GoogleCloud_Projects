#!/usr/bin/env bash
#
# inventario_files.sh — Analisa a pasta files/ do google-sheets-mcp e grava um
# relatório detalhado em analysis/files_inventory.md (commit + push), pra o Claude
# ler direto do repositório e propor o plano de redução.
#
#   cd ~/GoogleCloud_Projects && git pull && ./scripts/inventario_files.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/analysis/files_inventory.md"
WORK="$(mktemp -d)"
mkdir -p "$ROOT/analysis"

echo "Clonando google-sheets-mcp..."
git -C "$WORK" clone --depth 1 https://github.com/brunotrolo/google-sheets-mcp.git >/dev/null 2>&1
D="$WORK/google-sheets-mcp/files"
if [ ! -d "$D" ]; then echo "Pasta files/ não encontrada"; exit 1; fi
cd "$D"

{
  echo "# Inventário da pasta files/ — $(date -u '+%F %T') UTC"
  echo ""
  echo "- **Total de arquivos:** $(find . -type f | wc -l | tr -d ' ')"
  echo "- **Tamanho total:** $(du -sh . | cut -f1)"
  echo ""
  echo "## Por extensão (qtde | tamanho)"
  echo '```'
  find . -type f | sed 's/.*\.//' | sort | uniq -c | sort -rn
  echo '```'
  echo ""
  echo "## Subpastas"
  echo '```'
  find . -mindepth 1 -type d | sed 's|^\./||' | sort || echo "(nenhuma)"
  echo '```'
  echo ""
  echo "## Duplicados EXATOS (mesmo conteúdo / md5)"
  echo '```'
  find . -type f -exec md5sum {} + | sort | awk '{c[$1]=c[$1]" "$2; n[$1]++} END{for(k in n) if(n[k]>1) print n[k]" copias:"c[k]}' | sort -rn || echo "nenhum"
  echo '```'
  echo ""
  echo "## Arquivos (nome | bytes | linhas | amostra)"
  echo '| arquivo | bytes | linhas | amostra (1ª linha útil) |'
  echo '|---|---|---|---|'
  find . -type f | sort | while read -r f; do
    rel="${f#./}"
    bytes=$(wc -c <"$f" | tr -d ' ')
    lines=$(wc -l <"$f" 2>/dev/null | tr -d ' ')
    sample=$(grep -m1 -v '^[[:space:]]*$' "$f" 2>/dev/null | head -c 90 | tr '|\n\r' '   ' )
    printf '| %s | %s | %s | %s |\n' "$rel" "$bytes" "$lines" "$sample"
  done
} > "$OUT"

cd "$ROOT"
git add analysis/files_inventory.md
git config user.email "actions@github.com" 2>/dev/null || true
git config user.name "inventory-bot" 2>/dev/null || true
git commit -q -m "analise: inventario da pasta files/ do sheets-mcp" || echo "(sem mudancas)"
git push
echo ""
echo "✅ Inventário gravado em analysis/files_inventory.md e enviado."
echo "   Agora peça ao Claude: 'leia o inventario e proponha o plano'."

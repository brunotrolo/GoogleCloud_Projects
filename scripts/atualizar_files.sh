#!/usr/bin/env bash
#
# atualizar_files.sh — Copia os 3 arquivos consolidados (já atualizados) de
# patches/google-sheets-mcp-files/ para files/ do google-sheets-mcp e dá push.
# Use sempre que editar os 3 documentos (ex.: mudar a whitelist).
#
#   cd ~/GoogleCloud_Projects && git pull && ./scripts/atualizar_files.sh
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/patches/google-sheets-mcp-files"
WORK="$(mktemp -d)"; cd "$WORK"
git clone --depth 1 https://github.com/brunotrolo/google-sheets-mcp.git
cd google-sheets-mcp

cp "$SRC/00_INICIO.md"  files/00_INICIO.md
cp "$SRC/01_PROJETO.md" files/01_PROJETO.md
cp "$SRC/02_SISTEMA.md" files/02_SISTEMA.md

if git diff --quiet; then
  echo "Nada mudou."
else
  git config user.email "actions@github.com"
  git config user.name "files-bot"
  git commit -aqm "docs: atualiza whitelist 24->27 (add CPLE6, ELET3, WEGE3)"
  git push
  echo "✅ files/ atualizado e enviado."
fi

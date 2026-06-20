#!/usr/bin/env bash
#
# aplicar_docs_mcps.sh — Publica a doc de gestão de custos (COST_MANAGEMENT.md)
# nos dois MCPs e adiciona um destaque no README de cada um.
#
# Rode no Cloud Shell, dentro do repo:
#   cd ~/GoogleCloud_Projects && git pull && ./scripts/aplicar_docs_mcps.sh
#
set -euo pipefail

DOC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/docs/ARQUITETURA_REFERENCIA_MCP.md"
WORK="$(mktemp -d)"

NOTE=$'\n\n---\n\n## 💰 Gestão de custos (LEIA ANTES DE FAZER DEPLOY)\n\nEste MCP roda no Google Cloud Run. Para não gerar custo elevado, siga a arquitetura\nde referência em [**COST_MANAGEMENT.md**](COST_MANAGEMENT.md): transporte **Streamable\nHTTP stateless** (nunca SSE), `--cpu-throttling`, `--min-instances=0`, `--timeout=120`.\nRegra de ouro: **conexão não pode ficar pendurada** — é o que faz a CPU ser cobrada 24/7.\n'

for repo in oplab_mcp google-sheets-mcp; do
  echo "==> $repo"
  git -C "$WORK" clone --depth 1 "https://github.com/brunotrolo/${repo}.git"
  cp "$DOC" "$WORK/$repo/COST_MANAGEMENT.md"
  if ! grep -q "COST_MANAGEMENT.md" "$WORK/$repo/README.md" 2>/dev/null; then
    printf '%s' "$NOTE" >> "$WORK/$repo/README.md"
  fi
  git -C "$WORK/$repo" config user.email "actions@github.com"
  git -C "$WORK/$repo" config user.name "docs-bot"
  git -C "$WORK/$repo" add COST_MANAGEMENT.md README.md
  if git -C "$WORK/$repo" diff --cached --quiet; then
    echo "   (sem mudanças)"
  else
    git -C "$WORK/$repo" commit -q -m "docs: arquitetura de referencia de gestao de custos (COST_MANAGEMENT.md)"
    git -C "$WORK/$repo" push
    echo "   ✅ publicado"
  fi
done
echo ""
echo "✅ Documentação de custos publicada nos dois MCPs."

#!/usr/bin/env bash
#
# add_health_sheets.sh — Adiciona a rota /health no MCP do Sheets e redeploya
# preservando as configs de custo (cpu-throttling, min-instances=0, timeout=120).
#
#   cd ~/GoogleCloud_Projects && git pull && ./scripts/add_health_sheets.sh
#
set -euo pipefail

WORK="$(mktemp -d)"
cd "$WORK"
git clone --depth 1 https://github.com/brunotrolo/google-sheets-mcp.git
cd google-sheets-mcp

if grep -q "'/health'" src/index.ts; then
  echo "Rota /health já existe — nada a fazer."
else
  perl -0pi -e "s/(app\.listen\()/app.get('\/health', (_req, res) => res.json({ status: 'ok', service: 'oplab-sheets-mcp', tools: 14 }));\n\n\$1/" src/index.ts
  git config user.email "actions@github.com"
  git config user.name "health-bot"
  git commit -aqm "feat: adiciona rota /health"
  git push
  echo "✅ /health commitado e enviado."
fi

echo "==> Redeploy preservando configs de custo..."
gcloud run deploy oplab-sheets-mcp --source . \
  --region us-east1 --project oplab-sheets-mcp-project \
  --cpu=1 --memory=512Mi --cpu-throttling --min-instances=0 --max-instances=2 --timeout=120

echo ""
echo "✅ Pronto. Teste:  curl -s https://oplab-sheets-mcp-6763522987.us-east1.run.app/health"

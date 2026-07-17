#!/usr/bin/env bash
#
# aplicar_whatsapp_mcp.sh — Provisiona do ZERO o MCP de WhatsApp (Baileys puro):
#   1. Publica o código em github.com/brunotrolo/WhatsApp_MCP
#   2. Habilita a API do Compute Engine no projeto novo
#   3. Libera firewall (80/443 — 22/SSH já vem liberado por padrão)
#   4. Reserva IP estático (grátis enquanto anexado a instância rodando)
#   5. Cria a VM e2-micro (Always Free tier) em us-east1-b com Node+Baileys+Caddy
#      já instalados via startup-script (idempotente — seguro rodar de novo)
#
# HTTPS automático via Caddy + sslip.io (não precisa de domínio próprio):
# a URL final fica https://<IP-da-VM>.sslip.io/mcp
#
# Custo esperado: ~R$0/mês (dentro do Always Free tier — 1x e2-micro + 20GB
# disco + IP estático anexado, tudo em us-east1). Ver docs/estudo-viabilidade-
# mcp-whatsapp.md para o raciocínio completo.
#
#   cd ~/GoogleCloud_Projects && git pull && ./scripts/aplicar_whatsapp_mcp.sh
#
set -euo pipefail

PROJECT_ID="whatsapp-mcp-server-502704"
ZONE="us-east1-b"
REGION="us-east1"
VM_NAME="whatsapp-mcp-vm"
REPO_URL="https://github.com/brunotrolo/WhatsApp_MCP.git"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/patches/whatsapp_mcp"

echo "==> 1/6 Publicando código em $REPO_URL..."
WORK="$(mktemp -d)"; cd "$WORK"
if git clone "$REPO_URL" repo 2>/dev/null; then
  cd repo
else
  mkdir repo && cd repo && git init -q -b main && git remote add origin "$REPO_URL"
fi
cp -r "$SRC"/. .
if git diff --quiet 2>/dev/null && [ -z "$(git status --porcelain)" ]; then
  echo "   Nada a mudar (já está atualizado)."
else
  git add -A
  git -c user.email="actions@github.com" -c user.name="whatsapp-mcp-bot" commit -qm "feat: servidor MCP WhatsApp (Baileys puro) + provisionamento"
  git branch -M main
  git push -u origin main
  echo "   ✅ Código publicado."
fi
cd "$WORK"

echo "==> 2/6 Configurando projeto GCP ($PROJECT_ID) e habilitando Compute Engine..."
gcloud config set project "$PROJECT_ID" --quiet
gcloud services enable compute.googleapis.com --quiet

echo "==> 3/6 Firewall (libera 80/443 para o Caddy emitir e servir HTTPS)..."
gcloud compute firewall-rules create allow-whatsapp-mcp-https \
  --project="$PROJECT_ID" --network=default --direction=INGRESS \
  --action=ALLOW --rules=tcp:80,tcp:443 --source-ranges=0.0.0.0/0 --quiet \
  2>/dev/null || echo "   (regra já existe, ok)"

echo "==> 4/6 Reservando IP estático (grátis enquanto anexado a instância rodando)..."
gcloud compute addresses create whatsapp-mcp-ip \
  --project="$PROJECT_ID" --region="$REGION" --quiet 2>/dev/null || echo "   (IP já reservado, ok)"
STATIC_IP="$(gcloud compute addresses describe whatsapp-mcp-ip --project="$PROJECT_ID" --region="$REGION" --format='get(address)')"
HOSTNAME="${STATIC_IP}.sslip.io"
echo "   IP estático: $STATIC_IP  →  https://$HOSTNAME"

echo "==> 5/6 Chave de API do MCP e número de destino..."
# Se a VM já existe, NÃO gera chave nova nem pergunta o número — o startup-script
# preserva o /etc/systemd/system/whatsapp-mcp.env que já está lá (ver abaixo).
VM_JA_EXISTE="$(gcloud compute instances describe "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" --format='get(name)' 2>/dev/null || true)"
if [ -n "$VM_JA_EXISTE" ]; then
  echo "   VM já existe — preservando a X-API-Key e o número atuais (não pergunta de novo)."
  MCP_API_KEY=""; WHATSAPP_DESTINO=""   # vazios: o startup-script não sobrescreve o env existente
else
  if [ -z "${MCP_API_KEY:-}" ]; then MCP_API_KEY="$(openssl rand -hex 32)"; fi
  read -rp "   Seu número de WhatsApp, DDI+DDD+número, só dígitos (ex: 5511999999999): " WHATSAPP_NUMBER
  WHATSAPP_DESTINO="${WHATSAPP_NUMBER}@s.whatsapp.net"
fi

echo "==> 6/6 Criando a VM e2-micro (Always Free tier) em $ZONE..."
cat > "$WORK/startup-script.sh" <<STARTUP
#!/usr/bin/env bash
set -e
apt-get update -qq
apt-get install -y -qq git curl debian-keyring debian-archive-keyring apt-transport-https gnupg

if ! command -v node >/dev/null; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y -qq nodejs
fi

if ! command -v caddy >/dev/null; then
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' > /etc/apt/sources.list.d/caddy-stable.list
  apt-get update -qq
  apt-get install -y -qq caddy
fi

id -u whatsapp-mcp &>/dev/null || useradd --system --home /opt/whatsapp-mcp --shell /usr/sbin/nologin whatsapp-mcp

# O repo é clonado como root e depois tem o dono trocado para whatsapp-mcp; sem esta
# linha, o `git pull` (rodando como root) falha com "dubious ownership" e o set -e
# aborta o startup-script ANTES do npm install/restart — deixando o código velho.
git config --global --add safe.directory /opt/whatsapp-mcp
if [ -d /opt/whatsapp-mcp/.git ]; then
  cd /opt/whatsapp-mcp && git pull -q
else
  rm -rf /opt/whatsapp-mcp && git clone -q "$REPO_URL" /opt/whatsapp-mcp
fi
cd /opt/whatsapp-mcp
npm install --omit=dev --silent
mkdir -p /opt/whatsapp-mcp/auth_info_baileys
chown -R whatsapp-mcp:whatsapp-mcp /opt/whatsapp-mcp

# Só escreve o env na PRIMEIRA vez (chave/número presentes e arquivo ainda ausente).
# Em re-deploys de VM existente, MCP_API_KEY vem vazio → preserva o env atual.
if [ ! -f /etc/systemd/system/whatsapp-mcp.env ] && [ -n "$MCP_API_KEY" ]; then
  cat > /etc/systemd/system/whatsapp-mcp.env <<ENVFILE
MCP_API_KEY=$MCP_API_KEY
PORT=8080
WHATSAPP_DESTINO=$WHATSAPP_DESTINO
ENVFILE
  chmod 600 /etc/systemd/system/whatsapp-mcp.env
fi

cp /opt/whatsapp-mcp/whatsapp-mcp.service /etc/systemd/system/whatsapp-mcp.service
systemctl daemon-reload
systemctl enable whatsapp-mcp
# restart (não "enable --now"): num reboot/reset o systemd já subiu o serviço com o
# código ANTIGO antes do git pull acima terminar; "enable --now" não reinicia um
# serviço já rodando, então o código novo não entrava. restart força pegar o pull.
systemctl restart whatsapp-mcp

cat > /etc/caddy/Caddyfile <<CADDYFILE
$HOSTNAME {
	reverse_proxy localhost:8080
}
CADDYFILE
systemctl enable caddy
systemctl restart caddy
STARTUP

gcloud compute instances create "$VM_NAME" \
  --project="$PROJECT_ID" --zone="$ZONE" \
  --machine-type=e2-micro \
  --image-family=debian-12 --image-project=debian-cloud \
  --boot-disk-size=20GB --boot-disk-type=pd-standard \
  --address=whatsapp-mcp-ip \
  --metadata-from-file=startup-script="$WORK/startup-script.sh" \
  --quiet 2>/dev/null || {
    echo "   (VM já existe — reaplicando o startup-script com um reset)"
    gcloud compute instances add-metadata "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" \
      --metadata-from-file=startup-script="$WORK/startup-script.sh" --quiet
    gcloud compute instances reset "$VM_NAME" --project="$PROJECT_ID" --zone="$ZONE" --quiet
  }

echo ""
echo "✅ Provisionamento disparado. A VM leva ~3-5 min instalando tudo na primeira vez."
echo ""
echo "═══ GUARDE ISSO — não é reexibido automaticamente ═══"
echo "  URL do MCP:  https://$HOSTNAME/mcp"
if [ -n "$MCP_API_KEY" ]; then
  echo "  X-API-Key:   $MCP_API_KEY"
else
  echo "  X-API-Key:   (preservada — a mesma da primeira instalação)"
fi
echo "═══════════════════════════════════════════════════"
echo ""
echo "PRÓXIMO PASSO (manual, uma única vez) — parear o WhatsApp via QR code:"
echo "  gcloud compute ssh $VM_NAME --project=$PROJECT_ID --zone=$ZONE"
echo "  sudo journalctl -u whatsapp-mcp -f"
echo "  (escaneie o QR com WhatsApp → Aparelhos conectados → Conectar um aparelho)"
echo ""
echo "Depois, teste com:"
echo "  curl -s https://$HOSTNAME/health"

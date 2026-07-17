# WhatsApp MCP — arquitetura, deploy e troubleshooting

**Status:** ✅ em produção (2026-07-17) · **Repo do MCP:** [github.com/brunotrolo/WhatsApp_MCP](https://github.com/brunotrolo/WhatsApp_MCP) · **Projeto GCP:** `whatsapp-mcp-server-502704` (isolado dos MCPs OpLab/Cockpit) · **Deploy:** `scripts/aplicar_whatsapp_mcp.sh` · **Custo:** ~R$0/mês (Always Free tier)

Terceiro MCP do ecossistema. Uma única ferramenta — `enviar_mensagem_whatsapp(texto)` —
para o Claude mandar alertas (ex.: risco de carteira) no WhatsApp pessoal do operador.
Decorre de `docs/estudo-viabilidade-mcp-whatsapp.md`.

---

## Arquitetura em uma olhada

```
Claude (claude.ai)
   │  POST https://<IP>.sslip.io/mcp/<CHAVE>   (chave no path — sem header)
   ▼
Caddy (HTTPS automático, porta 443)  ──►  Node/Express :8080  ──►  Baileys (sessão WhatsApp Web)
   VM Compute Engine e2-micro (Always Free, us-east1-b, sempre ligada)          │
                                                                                ▼
                                                          WhatsApp do REMETENTE (número-robô)
                                                                                │  envia para
                                                                                ▼
                                                          WhatsApp do DESTINO (número principal)
```

### Dois números, dois papéis (a distinção que mais confunde)
- **Remetente (robô):** o número que **escaneia o QR** e mantém a sessão. Deve ser um número
  **secundário** (reduz risco de banimento do principal). Neste deploy: `5511965481716`.
- **Destino:** onde os alertas **chegam** — `WHATSAPP_DESTINO`, o número principal que você lê.
  Neste deploy: `5511976765644`.
- ⚠️ **Se remetente == destino**, você manda mensagem para si mesmo e ela cai no chat
  "Mensagem para mim" (fácil de achar que "não chegou"). Use números diferentes.

---

## Decisões de arquitetura

| Decisão | Por quê |
|---|---|
| **Baileys puro** (sem Evolution API) | Elimina Postgres e Redis (que a Evolution API só exige para multi-instância). |
| **Compute Engine, não Cloud Run** | Sessão WhatsApp Web = WebSocket persistente; Cloud Run congela CPU entre requisições. |
| **`e2-micro` Always Free (us-east1)** | Cota gratuita permanente (1 VM + 30GB disco). OpLab/Cockpit usam Cloud Run, não tocam essa cota. ~R$0/mês. |
| **IP estático** | O hostname HTTPS (`<IP>.sslip.io`) embute o IP; se mudasse, URL/cert quebrariam. Grátis enquanto anexado a instância rodando. |
| **Caddy + `sslip.io`** | HTTPS automático (Let's Encrypt) sem precisar de domínio próprio. `<IP>.sslip.io` resolve para o próprio IP. |
| **Reconexão explícita** | Baileys ≥ v6 não reconecta sozinho; ouvimos `connection.update` e reconectamos com delay de 5s (exceto em `loggedOut`, que exige novo QR). |
| **`fetchLatestBaileysVersion()`** | Sem isso, o Baileys usa uma versão embutida que fica velha → o WhatsApp rejeita o handshake com **405** e nunca emite o QR. |
| **Auth pela CHAVE no PATH** (`/mcp/<chave>`) | O conector do claude.ai (fora do beta de request headers) só guarda a URL. A chave viaja no caminho. Também há auth por header `x-api-key` (para curl e para o beta). |
| **Destino fixo via env** | A ferramenta só recebe `texto`; o destino não é parâmetro → o modelo não consegue mandar para o número errado. |
| **`onWhatsApp()` antes de enviar** | Resolve o JID canônico. No Brasil, o "9º dígito" faz o número digitado divergir do JID registrado → sem isso o envio "tem sucesso" mas não é entregue. |

---

## Deploy

`./scripts/aplicar_whatsapp_mcp.sh` (idempotente). Faz, do zero: publica o código em
`WhatsApp_MCP`, habilita Compute Engine, libera firewall 80/443, reserva o IP estático,
e cria a VM `e2-micro` com um `startup-script` que instala Node 20 + Caddy, clona o repo,
sobe o systemd (`Restart=always`) e configura o Caddyfile com o hostname `sslip.io`.

- **1ª execução:** pergunta o número de destino e gera a `X-API-Key`.
- **Re-execução (VM já existe):** preserva chave e número; dá `reset` na VM (reaplica o
  startup-script → `git pull` + `npm install` + `restart`).

### Pareamento por QR (manual — segurança do WhatsApp, não automatizável)
```bash
gcloud compute ssh whatsapp-mcp-vm --project=whatsapp-mcp-server-502704 --zone=us-east1-b
sudo journalctl -u whatsapp-mcp -f
```
Escanear com o celular **remetente**: WhatsApp → Aparelhos conectados → Conectar um aparelho.
A sessão fica salva em `/opt/whatsapp-mcp/auth_info_baileys` e reconecta sozinha depois.

### Conectar no claude.ai
Conectores → Adicionar conector personalizado → **URL** = `https://<IP>.sslip.io/mcp/<CHAVE>`
(nome ASCII puro, ex. `WhatsApp`; sem OAuth). A chave está em
`/etc/systemd/system/whatsapp-mcp.env` na VM.

### Ferramentas (MCP)

Todo envio **confirma a entrega** (espera o recibo do WhatsApp por até 7s) e retorna
`{ entregue, status, id }`. `entregue=false` ⇒ chegou ao servidor mas não ao aparelho (destino
offline) → o orquestrador reenvia/loga. Status: `pendente → enviado_ao_servidor → entregue → lido`
(via evento Baileys `messages.update`); o ack de entrega não depende de recibos de leitura.

**Recomendadas (sempre ligadas):** `enviar_mensagem_whatsapp`, `enviar_imagem_whatsapp`,
`enviar_documento_whatsapp`, `ler_mensagens_recebidas` (two-way), `verificar_status_envio`,
`verificar_status_conexao`, `guia_de_uso` (guia para a própria LLM), e
`enviar_alerta_falado` (TTS → nota de voz; aparece só com `GOOGLE_TTS_API_KEY`).

**Alerta falado:** `enviar_alerta_falado(texto)` gera a fala com Google Cloud TTS (Neural pt-BR),
transcodifica para opus (ffmpeg) e envia como nota de voz — o operador ouve o alerta sem abrir o
app. Requer uma API key restrita ao TTS na env `GOOGLE_TTS_API_KEY` (setup em
`patches/whatsapp_mcp/docs/FERRAMENTAS.md`). Free tier ~1M chars/mês → ~R$0.

**Mídia:** imagem/documento/áudio aceitam `url` ou `base64`, com timeouts (download 20s, envio 45s)
e limite de 16MB — mídia problemática retorna erro claro em vez de pendurar a requisição.

**Extras (desligadas por padrão — `HABILITAR_FERRAMENTAS_EXTRAS=true`):** `enviar_audio_whatsapp`,
`enviar_video_whatsapp`, `enviar_sticker_whatsapp`, `responder_mensagem_whatsapp` (reply),
`editar_mensagem_whatsapp`, `apagar_mensagem_whatsapp`, `reagir_mensagem_whatsapp`,
`marcar_como_lida_whatsapp`, `enviar_presenca_whatsapp`. Implementadas para exploração futura;
só aparecem/funcionam com a flag ligada. Cada capacidade "bot-like" a mais aumenta o risco de
banimento — para alertas pessoais, mantenha só o necessário.

**Para autorizar os extras** (na VM):
```bash
echo 'HABILITAR_FERRAMENTAS_EXTRAS=true' | sudo tee -a /etc/systemd/system/whatsapp-mcp.env
sudo systemctl restart whatsapp-mcp
```

### Endpoints HTTP
- `POST /mcp/:key` — MCP autenticado pela chave no path (usado pelo claude.ai).
- `POST /mcp` — MCP autenticado pelo header `x-api-key` (curl/testes).
- `GET /health` — público, sem segredo: `{ status, whatsapp, online, conectado_desde, uptime_processo_s, ultima_entrega_confirmada, ... }` (serve de uptime check externo).

---

## 🔧 Troubleshooting — a saga documentada (leia antes de repetir os erros)

Cada linha foi um bug real enfrentado neste deploy, com o sintoma e o fix.

| Sintoma | Causa raiz | Correção |
|---|---|---|
| Loop `statusCode 405`, QR nunca aparece | Versão do WhatsApp Web embutida no Baileys estava velha | `fetchLatestBaileysVersion()` + bump do pacote `@whiskeysockets/baileys` |
| Reconexão em "martelo" (405 a cada 2s) | Reconexão instantânea empilhava sockets | Delay de 5s + flag anti-sobreposição + `removeAllListeners()` antes de recriar |
| Código novo nunca subia após deploy | `git pull` (como root) falhava com `detected dubious ownership` (repo tem dono `whatsapp-mcp`); `set -e` abortava o startup-script antes do restart | `git config --global --add safe.directory /opt/whatsapp-mcp` no startup-script |
| VM seguia no código antigo após reset | `systemctl enable --now` não reinicia serviço já rodando | Trocar por `systemctl enable` + `systemctl restart` |
| "Mensagem enviada com sucesso" mas **não chega** | "9º dígito" do Brasil: `5511976765644@...` ≠ JID registrado | Resolver o JID via `sock.onWhatsApp(numero)` antes de enviar |
| Mensagem "não chega" (mesmo com JID certo) | Remetente == destino → foi para o chat "Mensagem para mim" | Parear o robô com um número **diferente** do destino |
| claude.ai: "não foi possível registrar no serviço de login / OAuth" | Endpoint indisponível (VM em reset) **ou** faltava a rota `/mcp/:key` (código antigo) | Esperar o servidor voltar; garantir código novo; usar a URL `/mcp/<chave>` |
| `curl /mcp/<chave>` → `Cannot POST` (404) | VM rodando código antigo (deploy/reset ainda em `npm install`) | Forçar na VM: `git pull && npm install && systemctl restart`; conferir `grep 'mcp/:key' index.js` |
| SSH: `Connection refused` / `insufficient scopes` | VM ainda bootando após `reset`; ou rodar `gcloud ssh` de dentro da própria VM | Esperar ~60-90s; rodar `gcloud` sempre do **Cloud Shell**, não da VM |
| `git pull` na VM: "Already up to date" mas código velho | O deploy publica em `WhatsApp_MCP` só no **passo 1** (Cloud Shell); rodar comandos na VM não republica | Rodar o script de deploy no **Cloud Shell**, não colar comandos soltos na VM |
| Avisos `Gaia id not found` no `gcloud` | Ruído do Cloud Shell/Regional Access Boundary | Inofensivo — o deploy conclui normalmente (`Done.`) |
| `stream errored out` 515 logo após o QR | Comportamento **normal** do Baileys pós-pareamento ("restart required") | Nenhuma — o código reconecta em 5s e conecta |
| `401 conflict device_removed` | O aparelho foi removido em "Aparelhos conectados" (ou re-pareado) | Reiniciar o serviço gera novo QR |

### Regra de ouro dos dois terminais
- **Cloud Shell** (prompt `@cloudshell`): roda o script de deploy e comandos `gcloud`.
- **Dentro da VM** (prompt `@whatsapp-mcp-vm`, após `gcloud compute ssh`): roda `sudo systemctl`, `journalctl`, `git -C /opt/whatsapp-mcp`.
- Nunca colar `exit` junto com o próximo comando (o `exit` fecha a sessão e o resto se perde).

---

## Se a sessão cair (logout remoto, troca de aparelho)
`GET /health` reporta `deslogado_precisa_novo_qr`. Refaça o pareamento:
```bash
# na VM:
sudo systemctl stop whatsapp-mcp
sudo rm -rf /opt/whatsapp-mcp/auth_info_baileys
sudo systemctl start whatsapp-mcp
sudo journalctl -u whatsapp-mcp -f   # escaneie o novo QR
```

## Atualizar o código depois
Rode `./scripts/aplicar_whatsapp_mcp.sh` no Cloud Shell (publica + reset). Se o reset ficar
em código antigo por lentidão do `npm install`, force na VM:
`sudo git -C /opt/whatsapp-mcp pull && sudo npm --prefix /opt/whatsapp-mcp install --omit=dev && sudo systemctl restart whatsapp-mcp`.

## Limitações conhecidas
- **Risco de banimento não-zero** (WhatsApp não-oficial). Mitigação: número secundário como remetente.
- **Sem redundância**: 1 VM. `Restart=always` cobre crash do processo, não queda da VM.
- **Reautorização manual** por QR se a sessão for deslogada.

## Ideias de melhoria futura (backlog)
- Suporte a mídia/imagem (gráficos de carteira) — Baileys já suporta.
- Rate-limit/anti-flood no envio.
- Migrar auth de `useMultiFileAuthState` para um store mais robusto se o volume crescer.
- Health check externo (uptime monitor) que avisa se a VM/sessão cair.
- Avaliar a **API oficial da Meta** se o risco de banimento incomodar (ver estudo de viabilidade).

# WhatsApp MCP — arquitetura e decisões

**Data:** 2026-07-17 · **Repo do MCP:** [github.com/brunotrolo/WhatsApp_MCP](https://github.com/brunotrolo/WhatsApp_MCP) · **Projeto GCP:** `whatsapp-mcp-server-502704` (isolado dos MCPs OpLab/Cockpit) · **Deploy:** `scripts/aplicar_whatsapp_mcp.sh`

Decorrência direta de `docs/estudo-viabilidade-mcp-whatsapp.md`. Este documento registra as escolhas de arquitetura desta implementação.

## Decisões

| Decisão | Por quê |
|---|---|
| **Baileys puro, sem Evolution API** | Elimina Postgres e Redis inteiros (Evolution API só precisa deles pra multi-instância/multi-usuário, algo que este caso — 1 número, 1 destinatário — não usa). Reduz a VM ao mínimo. |
| **Compute Engine `e2-micro`, não Cloud Run** | Sessão WhatsApp Web = WebSocket persistente. Cloud Run congela CPU entre requisições por design — incompatível com manter conexão viva. |
| **`e2-micro` no Always Free tier (`us-east1`)** | Cota gratuita permanente do Google (1 instância + 30GB disco + rede, por conta de billing). Como o OpLab/Cockpit rodam em Cloud Run (não tocam essa cota), ela está livre para este projeto. Custo esperado: **~R$0/mês**. |
| **IP estático (não efêmero)** | O hostname HTTPS (`sslip.io`) tem o IP embutido no nome — se o IP mudasse a cada reinício, a URL/certificado quebrariam. IP estático é grátis **enquanto anexado a uma instância rodando**; só cobra se ficar reservado e solto. |
| **Caddy + `sslip.io`** | HTTPS automático (emissão e renovação de certificado Let's Encrypt) sem precisar comprar/configurar domínio próprio. `<IP>.sslip.io` resolve para o próprio IP sem cadastro. |
| **Reconexão explícita no código** | Baileys, desde a v6, não reconecta sozinho. `connection.update` é escutado manualmente; reconecta sempre, exceto em `DisconnectReason.loggedOut` (aí precisa de novo QR — não dá pra automatizar, é segurança do WhatsApp). |
| **`X-API-Key` obrigatório em `/mcp`** | Diferente das ferramentas de leitura (OpLab/Cockpit), esta tem efeito colateral real no mundo (manda mensagem). Chave compartilhada como defesa extra além da URL, gerada automaticamente no deploy. |
| **Destinatário fixo (`WHATSAPP_DESTINO`), não parâmetro da ferramenta** | Evita que uma alucinação do modelo mande a mensagem pro número errado — a única ferramenta exposta (`enviar_mensagem_whatsapp`) só recebe o texto. |
| **`useMultiFileAuthState`** | A própria documentação do Baileys desaconselha em produção de alto volume (I/O). Para 1 sessão, <10 msgs/dia, é adequado — a ressalva é sobre escala, não sobre este caso de uso. |

## O que o script de deploy faz (idempotente — seguro rodar de novo)

1. Publica o código de `patches/whatsapp_mcp/` no repo `WhatsApp_MCP`.
2. Habilita a API do Compute Engine no projeto `whatsapp-mcp-server-502704`.
3. Libera firewall para `80`/`443` (SSH já vem liberado por padrão em projeto novo).
4. Reserva o IP estático.
5. Cria a VM `e2-micro` com um `startup-script` que instala Node 20, Caddy, clona o repo, sobe o systemd service (`Restart=always`) e configura o Caddyfile com o hostname `sslip.io` correto.
6. Ao final, imprime a **URL do MCP** e a **`X-API-Key`** — únicas nesta execução, guardar.

## Passo manual único: pareamento por QR code

Não é automatizável (segurança do próprio WhatsApp). Depois do deploy:

```bash
gcloud compute ssh whatsapp-mcp-vm --project=whatsapp-mcp-server-502704 --zone=us-east1-b
sudo journalctl -u whatsapp-mcp -f
```

Escanear com **WhatsApp → Aparelhos conectados → Conectar um aparelho**. A sessão fica salva em `/opt/whatsapp-mcp/auth_info_baileys` na VM e reconecta sozinha depois disso — a menos que seja deslogada remotamente, caso em que é preciso repetir este passo.

## Limitações conhecidas (herdadas do estudo de viabilidade)

- **Risco de banimento não-zero** (~20%/ano segundo a pesquisa da comunidade, independente de volume) — é o WhatsApp não-oficial, ver estudo. Mitigação parcial: usar um número secundário como remetente, não o pessoal.
- **Sem redundância**: 1 VM, sem HA. Se cair, os alertas ficam mudos até reinício manual (`systemctl restart`, que o `Restart=always` já cobre pra crash de processo — não cobre queda da própria VM/projeto).
- **Reautorização manual** sempre que a sessão for deslogada (troca de aparelho, logout remoto, etc.).

## Como atualizar o código depois

O `startup-script` só roda automaticamente na *criação* da VM. Pra aplicar mudanças de código numa VM já existente, o script de deploy detecta isso e força um `gcloud compute instances reset` (reaplica o startup-script, que faz `git pull` + reinstala dependências) — basta rodar `./scripts/aplicar_whatsapp_mcp.sh` de novo.

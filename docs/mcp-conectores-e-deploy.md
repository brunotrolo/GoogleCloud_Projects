# MCPs — Conectores no claude.ai e Pipeline de Deploy

Referência operacional dos **três** MCPs do projeto de derivativos B3 (OpLab, Cockpit, WhatsApp).
Visão geral do sistema em [ARQUITETURA-GERAL.md](ARQUITETURA-GERAL.md).

## ⚠️ Regra de ouro: nome de conector = ASCII puro

Ao adicionar um **conector personalizado** no claude.ai, o **nome NÃO pode ter
acento, cedilha, til ou espaço**. Use só `[A-Za-z0-9_-]`.

**Por quê:** o claude.ai deriva o *namespace* das ferramentas a partir do nome do
conector. Nomes como `Operações`, `Google Sheets Operações`, `Análise` são
sanitizados (`ç`/`õ`/`ã`/espaço viram `_`), o que quebra o casamento no índice de
busca (`tool_search`) — resultado: **as ferramentas do conector nunca aparecem**,
mesmo com o servidor 100% funcional.

- ❌ `Operações`, `Google Sheets Operações`, `Análise B3`
- ✅ `Cockpit`, `OpLab`, `SheetsOps`, `Operacoes`

Sintoma clássico do erro: o `tool_search` só devolve as ferramentas dos conectores
de nome ASCII (ex.: OpLab) e "não encontra" as do conector de nome acentuado,
apesar de ele aparecer como *Conectado* e listar as ferramentas nas permissões.

Diagnóstico definitivo (feito em 2026-07): o handshake MCP (`initialize`) dos dois
servidores é **idêntico** (mesmo `protocolVersion`, `capabilities`, schemas válidos)
— só o nome do conector mudava o comportamento. Trocar `Operações` → `Cockpit`
resolveu na hora.

## Os três servidores

| MCP | Serviço | Projeto | Auth do conector | Depende de |
|-----|---------|---------|------------------|-----------|
| OpLab (análise/manejo) | Cloud Run `oplab-mcp-server` | `oplab-mcp-server` | URL `/mcp` (segredo interno) | API OpLab (token estático) |
| Cockpit (planilha) | Cloud Run `oplab-sheets-mcp` | `oplab-sheets-mcp-project` | URL `/mcp` (segredo interno) | Google Sheets API (service account) |
| WhatsApp (alertas) | Compute Engine VM `whatsapp-mcp-vm` | `whatsapp-mcp-server-502704` | **URL `/mcp/<chave>`** (chave no path) | WhatsApp Web (Baileys, sessão por QR) |

URLs `/mcp`:
- OpLab: `https://oplab-mcp-server-544531071750.us-east1.run.app/mcp`
- Cockpit: `https://oplab-sheets-mcp-6763522987.us-east1.run.app/mcp`
- WhatsApp: `https://34.139.120.158.sslip.io/mcp/<MCP_API_KEY>`

> **Por que o WhatsApp usa a chave no path?** O conector padrão do claude.ai (fora do beta de
> "request headers") só guarda a URL — sem header customizado. Então a `MCP_API_KEY` viaja
> embutida no caminho (`/mcp/<chave>`). Os MCPs do Cloud Run não expõem essa auth porque o
> segredo deles (token OpLab / service account) é interno ao servidor, não enviado pelo cliente.
> O WhatsApp tem efeito colateral real (manda mensagem), por isso exige a chave.

## Pipeline de deploy

O código-fonte dos MCPs vive em repositórios separados
(`brunotrolo/oplab_mcp`, `brunotrolo/google-sheets-mcp`, `brunotrolo/WhatsApp_MCP`).
Editamos cópias em `patches/` e publicamos via scripts no Cloud Shell:

```bash
cd ~/GoogleCloud_Projects && git pull
./scripts/aplicar_oplab_completo.sh     # OpLab (Cloud Run)
./scripts/aplicar_sheets_antiflaky.sh   # Cockpit (Cloud Run)
./scripts/aplicar_whatsapp_mcp.sh       # WhatsApp (Compute Engine VM)
```

Cada script clona o repo do MCP, copia os arquivos de `patches/`, commita, dá push
e faz o deploy — `gcloud run deploy` (Cloud Run) ou provisiona/atualiza a VM (WhatsApp).
Os erros "Regional Access Boundary 404 / Gaia id not found" no output do `gcloud` são
ruído/telemetria — o deploy conclui ("Done.").

> **WhatsApp — 1ª vez:** exige parear a sessão por QR code (SSH na VM + `journalctl`) e conectar
> com um número **secundário** como remetente. Todo o passo a passo e o troubleshooting
> (405, git ownership, 9º dígito, OAuth) estão em [whatsapp-mcp-arquitetura.md](whatsapp-mcp-arquitetura.md).

## Custo e cold start

- Ambos com `min-instances=0` (escala a zero) → **~R$0**, dentro do free tier.
- Anti cold-start **sem custo**: o `googleapis` do Cockpit é carregado *lazy* (só na
  1ª chamada de ferramenta, nunca no handshake) e o deploy usa `--cpu-boost`.
- Se precisar garantir container sempre quente: `scripts/sheets_warm_on.sh`
  (`min-instances=1`, ~R$45–50/mês) e rollback com `scripts/sheets_warm_off.sh`.
  **Não foi necessário** — o problema de indexação era o nome acentuado, não cold start.

## Robustez do Cockpit MCP

- `tools/list` estático (não toca no Sheets) → handshake ~0,3s.
- Cache de leitura por range (TTL 45s) → menos latência e menos consumo de cota.
- Erros de cota/permissão/timeout retornam mensagem acionável.

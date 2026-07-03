# MCPs — Conectores no claude.ai e Pipeline de Deploy

Referência operacional dos dois MCPs do projeto de derivativos B3.

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

## Os dois servidores (Cloud Run)

| MCP | Serviço Cloud Run | Projeto | Depende de |
|-----|-------------------|---------|-----------|
| OpLab (análise/manejo) | `oplab-mcp-server` | `oplab-mcp-server` | API OpLab (token estático) |
| Cockpit (planilha) | `oplab-sheets-mcp` | `oplab-sheets-mcp-project` | Google Sheets API (OAuth service account) |

URLs `/mcp`:
- OpLab: `https://oplab-mcp-server-544531071750.us-east1.run.app/mcp`
- Cockpit: `https://oplab-sheets-mcp-6763522987.us-east1.run.app/mcp`

## Pipeline de deploy

O código-fonte dos MCPs vive em repositórios separados
(`brunotrolo/oplab_mcp`, `brunotrolo/google-sheets-mcp`). Editamos cópias em
`patches/` e publicamos via scripts no Cloud Shell:

```bash
cd ~/GoogleCloud_Projects && git pull
./scripts/aplicar_manejo_engine.sh      # OpLab (motor de manejo)
./scripts/aplicar_sheets_antiflaky.sh   # Cockpit (Google Sheets)
```

Cada script clona o repo do MCP, copia os arquivos de `patches/`, commita, dá push
e roda `gcloud run deploy`. Os erros "Regional Access Boundary 404" no output do
`gcloud` são ruído/telemetria — o deploy conclui ("Done.").

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

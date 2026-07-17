# Custos consolidados — os 3 MCPs + monitoria

**Última atualização:** 2026-07-17 · **Total esperado: ~R$0/mês** (dentro do free tier do GCP).

Este documento consolida o custo de tudo que roda no Google Cloud neste projeto e explica,
recurso por recurso, por que a conta fecha em zero — e qual é a única variável a observar.

## Retrato por MCP / recurso

| MCP / recurso | Serviço GCP | Mecanismo de custo | Custo | Por que ~R$0 |
|---|---|---|---|---|
| OpLab | Cloud Run `oplab-mcp-server` | vCPU/RAM por requisição | ~R$0 | `min-instances=0` (escala a zero) + free tier de requisições |
| Cockpit | Cloud Run `oplab-sheets-mcp` | vCPU/RAM por requisição | ~R$0 | idem (googleapis lazy + `--cpu-boost` no boot) |
| WhatsApp — VM | Compute Engine `e2-micro` | por hora (VM 24/7) | ~R$0 | **Always Free tier**: 1 e2-micro em us-east1/us-west1/us-central1 |
| WhatsApp — disco | Persistent Disk 20GB standard | por GB | ~R$0 | free tier inclui 30GB standard |
| WhatsApp — IP estático | IP reservado | por hora se ocioso | ~R$0 | grátis **enquanto anexado a VM rodando** (a nossa não desliga) |
| Mensagens WhatsApp | — (Baileys) | — | ~R$0 | conexão não-oficial: **sem taxa por mensagem** (a API oficial da Meta cobraria ~R$0,04/msg) |
| Monitoria de custos | BigQuery (billing export) | por dados varridos/armazenados | ~R$0 | volume mínimo, dentro do free tier |
| CI (relatório diário) | GitHub Actions | minutos | R$0 | fora do GCP; free tier do GitHub |

## A única variável: egress de rede (1 GB/mês grátis)
- **Texto**: desprezível.
- **Imagem/documento** (ferramentas novas do WhatsApp): consomem banda de saída ao enviar para o
  WhatsApp. 1 GB ≈ ~2.000 imagens de 500KB ou ~1.000 documentos de 1MB por mês. No volume pessoal
  (<10 msgs/dia) sobra muito.
- Só começaria a custar centavos com **muito vídeo pesado diário** — não é o caso de um canal de alertas.

## Asteriscos honestos (as poucas formas de "vazar" custo)
1. **Parar a VM do WhatsApp** (stop, não delete) e deixá-la parada → o IP estático reservado passa a
   cobrar (~US$0,007/h). Como o desenho é "sempre ligada", não ocorre no uso normal.
2. **Ligar `min-instances>=1`** em algum Cloud Run (ex.: `sheets_warm_on.sh`) → container quente 24/7,
   ~R$45–50/mês. **Não é necessário** (o problema de "tool not found" era nome de conector, não cold start).
3. **Habilitar os extras do WhatsApp e disparar mídia em massa** → egress. Improvável no uso pessoal.
4. **Exceder o free tier da conta** (ex.: rodar uma 2ª VM e2-micro) → a cota "1 e2-micro grátis" é por
   **conta de billing**, não por projeto. OpLab/Cockpit usam Cloud Run (não tocam essa cota), então ela
   está livre para a VM do WhatsApp.

## Como vigiar (a monitoria existe pra isso)
O relatório diário em [`../reports/`](../reports/) quebra o custo por serviço/SKU/recurso/dia. A
**seção 7 (recorrente/idle)** é o principal detector de "liga e cobra". Peça ao Claude:
*"lê o último relatório de custos e me diz de onde vem cada centavo"*. Como ler: [COMO_LER.md](COMO_LER.md).

## Comparativo — o que se economizou
| Alternativa evitada | Custo que teria |
|---|---|
| Z-API (WhatsApp gerenciado) | R$55–99/mês |
| Evolution API self-hosted (GCP realista, com VM + banco) | ~R$115/mês |
| Cloud Run com `min-instances=1` (por MCP) | ~R$45–50/mês cada |
| **Solução atual (3 MCPs)** | **~R$0/mês** |

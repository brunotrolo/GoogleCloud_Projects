# Como ler o relatório de custos

Cada relatório em `reports/cost-report-AAAA-MM-DD.md` tem 8 seções. Aqui está
o que olhar em cada uma — e o que normalmente é o culpado do "liguei e veio custo".

| Seção | O que responde | Quando olhar |
|-------|----------------|--------------|
| 1. Por Serviço | Qual produto GCP cobra mais (Cloud Run, Compute, Logging...) | Sempre — visão macro |
| 2. Por SKU | O item EXATO cobrado dentro do serviço | Pra entender *o quê* dentro do serviço |
| 3. Por Recurso | Qual instância/disco/serviço específico | Pra achar o recurso vilão e desligar |
| 4. Por Dia | Tendência diária | Pra ver se foi pico pontual ou custo fixo |
| 5. Por Label | Custo por MCP / ambiente (se você rotular) | Pra separar MCP-A de MCP-B |
| 6. Créditos | Quanto de free tier/desconto está abatendo | Pra prever quando o crédito acaba |
| 7. Recorrente/Idle | Custos que cobram MESMO parado | **O principal suspeito do seu caso** |
| 8. Por Projeto | Custo por projeto na conta de billing | Se houver vários projetos |

## Os suspeitos clássicos de "liga e já cobra" (seção 7)

Esses cobram **24/7 mesmo sem uso**, e costumam ser a surpresa na fatura:

- **IP externo/estático reservado** não usado → cobra por hora.
- **Disco persistente / SSD** de VMs paradas → cobra capacidade.
- **Snapshots** acumulados.
- **Cloud Run com `min-instances >= 1`** → mantém container quente cobrando CPU/RAM.
- **Cloud SQL** ligado → cobra por hora mesmo sem query.
- **NAT Gateway / Load Balancer / Forwarding Rule** → taxa fixa por hora.
- **Artifact/Container Registry** → armazenamento de imagens antigas.
- **Logging/Monitoring** → retenção de logs além do free tier.

## Como me pedir a análise

Depois que existir pelo menos um arquivo em `reports/`, me diga:

> "Lê o último relatório de custos e me explica de onde vem cada centavo."

Eu leio o Markdown, cruzo as seções e te entrego: o ranking dos vilões, o que é
custo fixo vs. uso, e **o que dá pra desligar/ajustar** pra parar o sangramento.

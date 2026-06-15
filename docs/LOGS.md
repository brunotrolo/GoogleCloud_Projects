# Rastreamento de chamadas por MCP (logs de infra)

Mostra **quantas vezes cada MCP foi acionado** e quando — sem tocar no código dos
MCPs. A origem são os **logs de requisição do Cloud Run**, exportados para o
BigQuery por um *log sink*.

> Limite honesto: os logs de infra mostram **chamadas por serviço (MCP)**, não o
> nome da ferramenta nem a conversa específica. Para isso seria preciso
> instrumentar o código dos MCPs. Aqui você vê o volume e, cruzando com o
> "custo por chamada" do painel, estima o custo de cada uso.

## Ligar (uma vez, no Cloud Shell)

```bash
cd ~/GoogleCloud_Projects && git pull
./scripts/setup_logs_sink.sh
```

O script cria o dataset `mcp_logs` e um sink em cada projeto de MCP
(`oplab-mcp-server` e `oplab-sheets-mcp-project`), apontando para o BigQuery.

Depois, registre o secret para o painel usar os logs (o próprio script imprime
o comando pronto):

```bash
gh secret set LOGS_TABLE --repo brunotrolo/GoogleCloud_Projects \
  --body 'oplab-mcp-server.mcp_logs.run_googleapis_com_requests_*'
```

## Resultado

- Nova seção no painel: **"Chamadas por dia (por MCP)"** (gráfico empilhado).
- Os logs começam a popular **a partir de agora** (não são retroativos).
- O job diário passa a incluir as chamadas automaticamente.

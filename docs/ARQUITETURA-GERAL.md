# Arquitetura geral do projeto — visão completa

> **Para a "sessão futura" (ou outra pessoa):** este é o documento-mestre. Lê ele primeiro
> e você entende tudo — o que existe, onde roda no Google Cloud, como faz deploy, quanto custa
> e por quê cada decisão foi tomada. Os detalhes profundos ficam nos docs linkados ao final.

**Última atualização:** 2026-07-17

---

## 1. O que é este projeto

Um ecossistema pessoal do operador (Bruno) para **operar derivativos na B3** (venda de
volatilidade / travas) com apoio do Claude, rodando **quase inteiramente no Google Cloud a ~R$0/mês**.
São duas frentes que convivem no mesmo repositório `GoogleCloud_Projects`:

1. **Monitoria de custos GCP** (a origem do repo) — BigQuery Billing Export → relatório diário
   em `reports/` + painel em `docs/index.html`. Serve para "descobrir a origem de cada centavo"
   e garantir que a conta não escape do free tier.
2. **Três servidores MCP** que dão ao Claude ferramentas de mercado, carteira e alertas:
   - **OpLab** — dados de mercado, IV Rank, estrutura de preço, backtests, manejo.
   - **Cockpit** — a carteira/posições e o risco (lê a planilha Google Sheets).
   - **WhatsApp** — envia alertas (e recebe comandos) no WhatsApp pessoal.

O Claude (claude.ai) é o **orquestrador**: conecta nos 3 MCPs, lê mercado/carteira e pode
te alertar no WhatsApp com confirmação de entrega.

```
        ┌──────────────────────────── claude.ai (orquestrador) ────────────────────────────┐
        │  conectores MCP:   OpLab            Cockpit            WhatsApp                    │
        └──────┬──────────────────┬───────────────────┬──────────────────────────────────────┘
               │ HTTPS /mcp        │ HTTPS /mcp         │ HTTPS /mcp/<chave>
        ┌──────▼──────┐    ┌───────▼────────┐    ┌──────▼─────────────┐
        │  Cloud Run  │    │   Cloud Run    │    │  Compute Engine     │
        │ oplab-mcp   │    │ oplab-sheets   │    │  e2-micro (VM 24/7) │
        │ (stateless) │    │  (stateless)   │    │  Baileys (WhatsApp) │
        └──────┬──────┘    └───────┬────────┘    └──────┬─────────────┘
               │ API OpLab         │ Google Sheets API   │ WhatsApp Web
          (token estático)   (service account)      (sessão pareada por QR)
```

---

## 2. Os três MCPs — mapa de referência

| | **OpLab** | **Cockpit** | **WhatsApp** |
|---|---|---|---|
| Função | Mercado, gregas, IV Rank, estrutura, backtests, manejo | Carteira/posições e risco (lê a planilha) | Enviar alertas / receber comandos |
| Repo do código | `brunotrolo/oplab_mcp` | `brunotrolo/google-sheets-mcp` | `brunotrolo/WhatsApp_MCP` |
| Projeto GCP | `oplab-mcp-server` | `oplab-sheets-mcp-project` | `whatsapp-mcp-server-502704` |
| Serviço GCP | Cloud Run `oplab-mcp-server` | Cloud Run `oplab-sheets-mcp` | Compute Engine VM `whatsapp-mcp-vm` |
| Região | us-east1 | us-east1 | us-east1-b |
| Runtime | Node/Express + MCP SDK | Node/Express + MCP SDK | Node/Express + MCP SDK + Baileys |
| Transporte | StreamableHTTP stateless | StreamableHTTP stateless | StreamableHTTP stateless |
| Estado | nenhum (escala a zero) | nenhum (escala a zero) | **sessão WhatsApp persistente** (VM sempre ligada) |
| Auth do conector | URL `/mcp` (segredo do servidor é interno) | URL `/mcp` (idem) | URL `/mcp/<chave>` (chave no path) |
| Dependência externa | API OpLab (token) | Google Sheets API (service account) | WhatsApp Web (QR) |
| Custo | ~R$0 (`min-instances=0`) | ~R$0 (`min-instances=0`) | ~R$0 (Always Free tier) |
| Doc dedicada | `ARQUITETURA_REFERENCIA_MCP.md` | `mcp-conectores-e-deploy.md` | `whatsapp-mcp-arquitetura.md` |

### URLs `/mcp`
- OpLab: `https://oplab-mcp-server-544531071750.us-east1.run.app/mcp`
- Cockpit: `https://oplab-sheets-mcp-6763522987.us-east1.run.app/mcp`
- WhatsApp: `https://34.139.120.158.sslip.io/mcp/<MCP_API_KEY>`

### Regra de ouro dos conectores (aprendida na dor)
No claude.ai, o **nome do conector deve ser ASCII puro** (`[A-Za-z0-9_-]`, sem acento/espaço).
Nome acentuado quebra o índice de busca de ferramentas e elas "somem" mesmo com o servidor OK.
Ex.: usar `Cockpit`, não `Operações`. Detalhe em `mcp-conectores-e-deploy.md`.

---

## 3. Os dois padrões de arquitetura (e por que existem)

### Padrão A — Cloud Run stateless (OpLab, Cockpit)
Para MCPs **request/response**. As "6 regras de ouro" (detalhe em `ARQUITETURA_REFERENCIA_MCP.md`):
`--cpu-throttling`, `--min-instances=0`, `StreamableHTTPServerTransport`, `--timeout=120`,
`--max-instances=2`, e **servidor novo por requisição**. Isso mantém o custo em ~R$0 (free tier)
e a estabilidade no app do Claude. Libs pesadas (googleapis) são carregadas *lazy* para não
atrasar o handshake (anti cold-start sem custo).

### Padrão B — VM Always Free (WhatsApp) — a exceção
A sessão WhatsApp Web (Baileys) é um **WebSocket 24/7**: precisa de CPU sempre viva e disco
persistente para a credencial da sessão. Isso é **incompatível com Cloud Run** (que congela a
CPU entre requisições e escala a zero). Solução: **Compute Engine `e2-micro` no Always Free tier**
— VM sempre ligada, mas ~R$0/mês porque cabe na cota gratuita permanente. HTTPS sem domínio via
**Caddy + `<IP>.sslip.io`**; IP estático (grátis enquanto anexado). Detalhe e troubleshooting
completo em `whatsapp-mcp-arquitetura.md`.

**Regra de decisão para um MCP novo:** precisa manter conexão viva o tempo todo? → VM e2-micro
free tier. É request/response? → Cloud Run com as 6 regras. Na dúvida, Cloud Run.

---

## 4. Como o código é versionado e deployado

O código-fonte de cada MCP vive em **repositório próprio** (`oplab_mcp`, `google-sheets-mcp`,
`WhatsApp_MCP`). Editamos **cópias** em `patches/<mcp>/` **dentro deste repo** e publicamos com
scripts rodados no **Cloud Shell** — nunca editamos os repos dos MCPs à mão.

```
patches/oplab_mcp/           → scripts/aplicar_*.sh        → github.com/brunotrolo/oplab_mcp → Cloud Run
patches/google-sheets-mcp/   → scripts/aplicar_sheets_*.sh → github.com/brunotrolo/google-sheets-mcp → Cloud Run
patches/whatsapp_mcp/        → scripts/aplicar_whatsapp_mcp.sh → github.com/brunotrolo/WhatsApp_MCP → VM
```

Cada script: clona o repo do MCP, copia os arquivos de `patches/`, commita, dá push e faz o
deploy (`gcloud run deploy` para Cloud Run; provisiona/atualiza a VM para o WhatsApp).
Os avisos `Regional Access Boundary 404 / Gaia id not found` no output do `gcloud` são
**ruído/telemetria** — o deploy conclui (`Done.`).

**Scripts principais de deploy** (há outros pontuais em `scripts/`):
- OpLab: `aplicar_oplab_completo.sh` (agrega os fixes) · `aplicar_manejo_engine.sh` · `aplicar_whitelist_dinamica.sh` · `aplicar_bs_local.sh`
- Cockpit: `aplicar_sheets_antiflaky.sh` · `aplicar_status_operacoes_v2.sh`
- WhatsApp: `aplicar_whatsapp_mcp.sh` (provisiona projeto+VM+firewall+IP+Caddy do zero; idempotente)

---

## 5. Custo — por que tudo fica em ~R$0/mês

| Recurso | Custo | Como se mantém grátis |
|---|---|---|
| Cloud Run (OpLab, Cockpit) | ~R$0 | `min-instances=0` (escala a zero) + free tier de requisições |
| Compute Engine e2-micro (WhatsApp) | ~R$0 | Always Free tier (1 VM + 30GB disco, us-east1) |
| IP estático (WhatsApp) | ~R$0 | Grátis enquanto anexado a VM rodando (a nossa não desliga) |
| Mensagens WhatsApp | ~R$0 | Baileys (não-oficial) não tem taxa por mensagem |
| BigQuery (billing export) | ~R$0 | Volume mínimo, dentro do free tier |

Única variável: **egress de rede** (1 GB/mês grátis). No volume pessoal (poucos alertas/dia,
imagens/docs esporádicos) sobra muito. Detalhe consolidado em `custos-consolidado.md`.
A monitoria diária (`reports/`) existe justamente para pegar qualquer surpresa antes que vire fatura.

---

## 6. Decisões e vereditos registrados (o "porquê")

| Documento | O que registra |
|---|---|
| `veredito-analise-estrutural.md` | Backtest provou que filtrar entrada por estrutura NÃO gera edge → a ferramenta #2 (projeção) não foi construída |
| `status-operacoes-risco-payoff.md` | Reescrita do `get_status_operacoes` por lógica de payoff (risco travado vs descoberto) |
| `whitelist-dinamica-dados-ativos.md` | Whitelist padrão do OpLab = aba DADOS_ATIVOS (26 ativos) + sync dinâmico |
| `auditoria-independente-mcps.md` | Auditoria por recálculo independente: achou 1 bug (get_options_bs), 2 alertas de dado; anti-look-ahead do backtest verificado |
| `estudo-viabilidade-mcp-whatsapp.md` | Estudo de custo/viabilidade que decidiu o WhatsApp (Baileys em VM vs alternativas) |
| `whatsapp-mcp-arquitetura.md` | Arquitetura + a saga de troubleshooting do WhatsApp (405, 9º dígito, OAuth, etc.) |

---

## 7. Índice de toda a documentação
Ver `docs/README.md` (índice categorizado de todos os docs).
